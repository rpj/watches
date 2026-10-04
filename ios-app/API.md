# Wear API contract (v1)

Single source of truth for the backend routes (`frontend/pages/api/wear/*`,
`frontend/lib/wear.ts`) and the Swift client (`ios-app/WristCore`). Change
this file first, then both sides.

Base URL is the gallery origin: prod `https://ryanswatches.com`, dev
`https://dev.ryanswatches.com`. All routes live under `/api/wear/`.

## Auth

Every request carries `Authorization: Bearer <WEAR_API_TOKEN>`.

| Condition | Response |
|---|---|
| Server env `WEAR_API_TOKEN` unset or empty | `503 {"error":"Wear API disabled"}` on every route |
| Header missing, not `Bearer <token>`, or token mismatch | `401 {"error":"Unauthorized"}` |

- Comparison is constant-time (`crypto.timingSafeEqual` over SHA-256 digests).
- The token is never logged and never echoed back.
- `WEAR_API_TOKEN` is read on every request, not cached at module load.
- The rate limiter runs **before** auth, so failed-token probes consume rate-limit slots and token guessing is throttled to the per-IP budget below. Auth runs before any data-layer access or method check, so a bad token always yields 401 (or 503), never 405.

Rate limit: 60 requests/minute per client IP (`x-forwarded-for`, which Caddy sets, falling back to socket address). Existing `X-RateLimit-*` headers; over limit → `429 {"error":"Too many requests. Please try again later."}` with `Retry-After`.

Content: JSON only. Wrong method → `405 {"error":"Method not allowed"}`. Every error body produced by the routes is `{ "error": "<human readable>" }`. One exception: POST bodies over 8 KB are rejected by Next's body parser itself with a `413` and a plain-text body before the route runs.

No CORS headers are set: the only client is a native app.

## Types

```ts
type WearSource = 'app' | 'notification' | 'widget' | 'shortcut';

interface WearEvent {
  id: string;          // client-generated idempotency key, /^[A-Za-z0-9-]{8,64}$/ (UUID v4 recommended)
  watchId: string;     // canonical post_id, e.g. "3m2uvdvq7622g"
  wornAt: string;      // ISO 8601 with offset, set by the client at tap time, e.g. "2026-10-04T08:12:31-07:00"
  source: WearSource;
  recordedAt: string;  // server time, ISO 8601 UTC with milliseconds, e.g. "2026-10-04T15:12:32.418Z"
}

interface WearWatch {
  id: string;                  // canonical post_id
  brand: string;
  model: string;
  imageUrl: string | null;     // hero image (honours __doodles:hero-overrides), Bluesky CDN feed_fullsize
  thumbnailUrl: string | null; // same image via feed_thumbnail (~75 KB webp); equals imageUrl when derivation is impossible
  postUrl: string;             // https://bsky.app/profile/<handle>/post/<id>
  wearCount: number;           // number of WearEvents for this watch
  lastWornAt: string | null;   // greatest wornAt among its events, verbatim as stored
  postCount: number;           // watch-meta entries about this watch: the canonical post itself (kind unique-watch) + follow-on posts whose references_post_id is this id
}
```

Swift mirrors these 1:1 (`WearSource`, `WearEvent`, `WearWatch`, `WatchesResponse`, `EventsResponse`, `RecordResponse`) with the same JSON keys. The Swift date decoder must accept both offset form (`-07:00`) and `Z`, with or without fractional seconds. Dates are kept as `String` on the wire type and parsed on demand.

## Ordering of `watches`

1. `wearCount` descending
2. `postCount` descending
3. canonical recency descending: later position in `__doodles:watch-canonical` (= newer) sorts first
4. `brand` ascending, then `model` ascending (case-insensitive `localeCompare`)

The comparator is exported as `compareWearWatches(a, b)` from `frontend/lib/wear.ts` and takes `canonicalIndex` via a wrapper record `{ watch, canonicalIndex }`.

## Endpoints

### `GET /api/wear/watches`

```json
200
{
  "watches": [WearWatch, ...],
  "current": WearEvent | null,
  "generatedAt": "2026-10-04T15:12:32.418Z"
}
```

`current` is the event with the greatest `wornAt` (zset score). Order among equal timestamps is unspecified.

### `GET /api/wear/events?limit=50`

`limit`: integer 1..500, default 50. Non-integer or out of range → `400`.

```json
200
{ "events": [WearEvent, ...] }   // newest (greatest wornAt) first
```

### `POST /api/wear/events`

Body: `{ "id", "watchId", "wornAt", "source" }` (exactly `WearEvent` minus `recordedAt`; unknown keys ignored).

| Outcome | Response |
|---|---|
| Stored | `201 { "event": WearEvent, "created": true }` |
| `id` already exists | `200 { "event": <the stored event>, "created": false }` — retry-safe; the retry body is ignored |
| Malformed JSON, missing/invalid field, `id` fails the pattern, unknown `watchId`, unparseable `wornAt`, `wornAt` more than 24 h in the future, unknown `source` | `400 { "error": "..." }` |

`recordedAt` is set by the server.

### `DELETE /api/wear/events/{id}`

| Outcome | Response |
|---|---|
| Deleted | `204` (no body) |
| Unknown id | `404 { "error": "Not found" }` |
| `id` fails the pattern | `400` |

## Redis layout

| Key | Type | Content |
|---|---|---|
| `__doodles:wear-events` | hash | `eventId → JSON WearEvent` |
| `__doodles:wear-timeline` | zset | `score = Date.parse(wornAt)` (ms), `member = eventId` |

Record = `HSETNX` events (idempotency) and, only if that returned 1, `ZADD` timeline. Delete = `HDEL` + `ZREM`. Counts and `current` are derived from these two keys on each read; no denormalized counters.

Reads of the canonical list (`__doodles:watch-canonical`), posts (`all-doodles:posts`), classifier meta (`__doodles:watch-meta`) and hero overrides (`__doodles:hero-overrides`) are unchanged from the rest of the frontend.

## Fixtures

Used verbatim by `frontend/tests/fixtures.ts` and `WristCore/Tests`. DID `did:plc:ep6hd5cp5gxj6pifezbar6nc`, handle `ryanswatches.com`.

Canonical list (oldest first, exactly this order):

```json
[
  { "post_id": "3m2uvdvq7622g", "brand": "Citizen", "model": "Eco Drive E110-K16750" },
  { "post_id": "3m2uxrekinc2e", "brand": "Skagen",  "model": "233LTMN Quartz" },
  { "post_id": "3mwz3ctxxnc26", "brand": "Kurono",  "model": "Malachite" }
]
```

Posts (one entry per image; Skagen has two images and a hero override of `1`):

| uri | imageUrls[0] |
|---|---|
| `at://did:plc:ep6hd5cp5gxj6pifezbar6nc/app.bsky.feed.post/3m2uvdvq7622g#image0` | `https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa` |
| `at://did:plc:ep6hd5cp5gxj6pifezbar6nc/app.bsky.feed.post/3m2uxrekinc2e#image0` | `https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenzero` |
| `at://did:plc:ep6hd5cp5gxj6pifezbar6nc/app.bsky.feed.post/3m2uxrekinc2e#image1` | `https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone` |
| `at://did:plc:ep6hd5cp5gxj6pifezbar6nc/app.bsky.feed.post/3mwz3ctxxnc26#image0` | `https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite` |
| `at://did:plc:ep6hd5cp5gxj6pifezbar6nc/app.bsky.feed.post/3m3followon001#image0` | `https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenband` |

`postUrl` = `https://bsky.app/profile/ryanswatches.com/post/<basePostId>`. `createdAt` ascending in table order starting `2026-05-01T00:00:00.000Z`, one day apart.

watch-meta:

```json
{
  "3m2uvdvq7622g": { "kind": "unique-watch", "brand": "Citizen", "model": "Eco Drive E110-K16750", "references_post_id": null, "confidence": 0.95, "classified_at": "2026-05-04T00:19:19.968Z" },
  "3m2uxrekinc2e": { "kind": "unique-watch", "brand": "Skagen",  "model": "233LTMN Quartz",        "references_post_id": null, "confidence": 0.9,  "classified_at": "2026-05-04T00:19:19.968Z" },
  "3mwz3ctxxnc26": { "kind": "unique-watch", "brand": "Kurono",  "model": "Malachite",             "references_post_id": null, "confidence": 0.97, "classified_at": "2026-10-04T00:00:00.000Z" },
  "3m3followon001": { "kind": "follow-on",   "brand": "Citizen", "model": "Eco Drive E110-K16750", "references_post_id": "3m2uvdvq7622g", "confidence": 0.8, "classified_at": "2026-05-06T00:00:00.000Z" }
}
```

hero-overrides: `{ "3m2uxrekinc2e": "1" }` → Skagen's `imageUrl` is the `bafkreiskagenone` image.

Expected `postCount`: Citizen 2, Skagen 1, Kurono 1.

**With no events**, `GET /api/wear/watches` returns watches in the order **Citizen, Kurono, Skagen** (postCount wins for Citizen; Kurono beats Skagen on canonical recency) and `current: null`.

Events, inserted in this order:

```json
[
  { "id": "11111111-1111-4111-8111-111111111111", "watchId": "3m2uvdvq7622g", "wornAt": "2026-10-01T08:00:00-07:00", "source": "app" },
  { "id": "22222222-2222-4222-8222-222222222222", "watchId": "3mwz3ctxxnc26", "wornAt": "2026-10-03T08:05:00-07:00", "source": "notification" },
  { "id": "33333333-3333-4333-8333-333333333333", "watchId": "3m2uvdvq7622g", "wornAt": "2026-10-02T07:58:00-07:00", "source": "widget" }
]
```

**After these**, order is **Citizen (wearCount 2, lastWornAt `2026-10-02T07:58:00-07:00`), Kurono (1), Skagen (0)**, and `current` is the Kurono event `2222…` even though the Citizen event `3333…` was inserted last.

Sample full response (shape reference for Swift Codable tests; `recordedAt`/`generatedAt` values are illustrative):

```json
{
  "watches": [
    {
      "id": "3m2uvdvq7622g",
      "brand": "Citizen",
      "model": "Eco Drive E110-K16750",
      "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
      "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
      "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3m2uvdvq7622g",
      "wearCount": 2,
      "lastWornAt": "2026-10-02T07:58:00-07:00",
      "postCount": 2
    },
    {
      "id": "3mwz3ctxxnc26",
      "brand": "Kurono",
      "model": "Malachite",
      "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
      "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
      "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3mwz3ctxxnc26",
      "wearCount": 1,
      "lastWornAt": "2026-10-03T08:05:00-07:00",
      "postCount": 1
    },
    {
      "id": "3m2uxrekinc2e",
      "brand": "Skagen",
      "model": "233LTMN Quartz",
      "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
      "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
      "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3m2uxrekinc2e",
      "wearCount": 0,
      "lastWornAt": null,
      "postCount": 1
    }
  ],
  "current": {
    "id": "22222222-2222-4222-8222-222222222222",
    "watchId": "3mwz3ctxxnc26",
    "wornAt": "2026-10-03T08:05:00-07:00",
    "source": "notification",
    "recordedAt": "2026-10-03T15:05:01.204Z"
  },
  "generatedAt": "2026-10-04T15:12:32.418Z"
}
```

## Thumbnail derivation

`thumbnailUrl = imageUrl.replace('/img/feed_fullsize/', '/img/feed_thumbnail/')` when the URL contains `/img/feed_fullsize/`; otherwise `thumbnailUrl = imageUrl`. Verified live: the `feed_thumbnail` variant of a stored URL returns `200 image/webp` at roughly a quarter of the size.
