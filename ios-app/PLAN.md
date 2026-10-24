# iOS "what am I wearing" app for Ryan's Watches

## Context

The Watches stack already knows every watch in the collection: the classifier's canonical list (`__doodles:watch-canonical`, 45 entries today, `{post_id, brand, model}`) is the de-duplicated set of unique watches, and each entry maps back to a Bluesky post with images. What it does not know is **which one is on the wrist right now**. This plan adds:

1. A tiny authenticated **wear API** inside the existing Next.js frontend (same container, same Redis).
2. A SwiftUI **iOS app** in `./ios-app/` whose single job is "tap the watch you're wearing", sorted most-worn first, with a morning nudge whose action buttons let you log without opening the app, and an interactive Home Screen widget for the same one-tap log.

Design tenet: fewest taps. In-app the primary task is **open → tap one row** (1 tap). From the lock screen or Home Screen it is **1 tap, zero taps inside the app**.

Decisions already made with you:
- **E2E:** manual. You run the simulator on your Mac and report back. (No hosted iOS-simulator MCP exists: AgentCloud shut down; XcodeBuildMCP, now under Sentry, is macOS-only with no hosted mode.) If you later want an agent-driven loop, open a second Claude Code session on the Mac with `claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`.
- **Surfaces in v1:** in-app picker + notification actions + interactive widget.
- **Tests:** I run them here. Swift core tests in the `swift:6.0-jammy` Docker image (arm64 manifest confirmed). API tests against Redis logical DB 15, never DB 0.

Facts that shape the plan (verified):
- Prod frontend is `ryanswatches.com` → Caddy → `localhost:8142`; dev is `dev.ryanswatches.com` → `:42420`. Both HTTPS, so the app never needs an ATS exception.
- The compose project dir is `/mnt/ubuntu_home/ryanswatches` but there is **no `.env` in the repo dir**; the deployment env lives elsewhere. Adding `WEAR_API_TOKEN` to the live container is a step for you.
- There is no auth anywhere in the frontend today, and no test framework in either service.
- `frontend/lib/api-middleware.ts` already has `rateLimit`, `runMiddleware`. `frontend/lib/redis.ts` has `getRedisClient`, `CanonicalEntry`, `WatchMeta`, `getWatchStats`, a private `applyHeroOverrides`, and `frontend/lib/utils.ts` has `groupPostsByBaseUri`. All reusable.
- No Swift toolchain on this box; Docker is available.

---

## Part A: Backend (frontend/, Next.js pages router)

### A1. Auth helper: `frontend/lib/wear-auth.ts`
- `requireWearToken(req, res): boolean`. Reads `WEAR_API_TOKEN` from env.
  - Env unset/empty → `503 {error:"Wear API disabled"}` (feature off by default).
  - Missing/malformed `Authorization: Bearer …` or mismatch → `401 {error:"Unauthorized"}`.
  - Compare with `crypto.timingSafeEqual` over SHA-256 digests of both sides (length-independent).
- Never log the token. Generic 401 body.

### A2. Data layer: `frontend/lib/wear.ts`
Redis keys (add to README key list + CLAUDE.md):
- `__doodles:wear-events` — hash `eventId → JSON WearEvent`
- `__doodles:wear-timeline` — zset `score = wornAt epoch ms`, `member = eventId`

Types (exported, mirrored 1:1 in Swift):
```ts
type WearSource = 'app' | 'notification' | 'widget' | 'shortcut';
interface WearEvent { id: string; watchId: string; wornAt: string; source: WearSource; recordedAt: string }
interface WearWatch {
  id: string;            // canonical post_id
  brand: string; model: string;
  imageUrl: string | null; thumbnailUrl: string | null; postUrl: string;
  wearCount: number; lastWornAt: string | null;
  postCount: number;     // unique-watch + follow-on posts referencing this id (from watch-meta)
}
```
Functions:
- `listWearWatches()` → `{ watches: WearWatch[], current: WearEvent|null }`
  - Canonical via `lrange __doodles:watch-canonical`. Images: load `all-doodles:posts` once, `groupPostsByBaseUri`, pick hero index from `__doodles:hero-overrides` (export `applyHeroOverrides` from `redis.ts` or batch `hmget`; do not call `getFullPostById` per watch). `thumbnailUrl` = `imageUrl` with `/feed_fullsize/` → `/feed_thumbnail/` (pure fn, falls back to imageUrl).
  - Counts from the timeline/events in one pass.
  - **Sort:** `wearCount desc` → `postCount desc` → canonical position desc (newer first) → `brand, model` asc. Pure comparator `compareWearWatches` exported for unit tests.
- `recordWear({id, watchId, wornAt, source})` → `{event, created}`; validates `id` (uuid-ish, ≤64 chars), `watchId` ∈ canonical, `wornAt` parses, `source` ∈ enum. Idempotent via `HSETNX`; `ZADD` only when created. Multi-command via pipeline.
- `listWearEvents(limit=50)` newest first; `deleteWearEvent(id)` → boolean.
- `getCurrentWear()` = highest-score member.

### A3. Routes: `frontend/pages/api/wear/`
All: `requireWearToken` first, then `rateLimit({maxRequests: 60})`. No CORS (native client, no browser origin). `405` otherwise. JSON only; `bodyParser.sizeLimit: '8kb'` on POST.
- `watches.ts` — `GET` → `{ watches, current, generatedAt }`
- `events.ts` — `GET ?limit=` → `{ events }`; `POST` body `WearEvent` minus `recordedAt` → `201 {event, created:true}` or `200 {event, created:false}` on duplicate id; `400 {error}` on validation failure.
- `events/[id].ts` — `DELETE` → `204` | `404`.

### A4. Config plumbing
- `.env.example`: `# WEAR_API_TOKEN=` with comment (generate via `openssl rand -hex 32`; unset = wear API disabled).
- `docker-compose.yml` frontend env: `- WEAR_API_TOKEN=${WEAR_API_TOKEN}`.
- `README.md`: new "Wear API & iOS app" section (endpoints, keys, token setup, where the app lives). `CLAUDE.md` (root + frontend): env var, keys, `ios-app/` in overview + `npm test`.
- `.gitignore`: `ios-app/**/*.xcodeproj/`, `xcuserdata/`, `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcresult`.

### A5. Tests (new: vitest + node-mocks-http, devDependencies only)
- `frontend/package.json`: `"test": "vitest run"`, `"typecheck": "tsc --noEmit"`. `frontend/vitest.config.ts`. Add `tests/**` to `tsconfig.exclude` so `next build` ignores them.
- `frontend/tests/setup.ts`: **refuses to run unless `REDIS_URL` ends in `/15`** (hard guard against DB 0); `flushdb` before each integration test; fixture seeder writes canonical + posts + meta + hero-override.
- Unit: `compareWearWatches` ordering (all four tie-break levels), thumbnail URL derivation, token compare (match / mismatch / wrong length / missing header / env unset), body validation.
- Integration (real Redis DB 15): `GET watches` shape + sort + hero-override image + thumbnail; `POST` creates then duplicate id returns 200/`created:false` with no double count; unknown watchId → 400; `DELETE` → 204 then 404; `current` tracks latest by `wornAt`, not insertion order; every route 401 without token, 503 with env unset, 405 on wrong method.

---

## Part B: iOS app (`./ios-app/`)

Working name **Wrist** (bundle prefix `com.ryanswatches`, trivially renamed in `project.yml`). iOS 17.0+, SwiftUI, Swift tools 5.10 (Xcode 16+). iPhone, portrait.

### B0. Layout
```
ios-app/
  README.md            # Mac setup + run + test + hand-off checklist
  API.md               # the wire contract (shared source of truth for Part A and B)
  PLAN.md              # this plan, committed for sub-agents / future sessions
  project.yml          # XcodeGen spec → `xcodegen generate` produces Wrist.xcodeproj (gitignored)
  WristCore/           # SwiftPM, pure Foundation, NO UIKit/SwiftUI → tests run on Linux in Docker
  WristKit/            # SwiftPM, iOS-only shared code for app + widget (Keychain, App Group, intents, live transport, nudge scheduler)
  Wrist/               # app target (SwiftUI)
  WristWidget/         # widget extension target
  WristTests/          # iOS XCTest (Mac only): WristKit seams with fakes
  WristUITests/        # one smoke XCUITest: launch → tap first row → "Wearing" label updates
```
Why XcodeGen: a hand-written `.pbxproj` can't be validated from Linux; a declarative `project.yml` can be reviewed and regenerates deterministically. One-time `brew install xcodegen` on the Mac.

### B1. `WristCore` (Linux-testable; this is where the logic lives)
- `Models.swift` — `WearWatch`, `WearEvent`, `WearSource`, `WatchesResponse`, `EventsResponse`, `RecordResponse` (Codable, ISO8601 with fractional-seconds-tolerant decoder). Fixture JSON in tests copied verbatim from `API.md`.
- `HTTPTransport.swift` — `protocol HTTPTransport { func send(_ req: HTTPRequest) async throws -> HTTPResponse }`. Core never imports URLSession (keeps Linux build trivial); `WristKit` provides the URLSession transport.
- `WearAPIClient.swift` — `watches()`, `record(event)`, `events(limit:)`, `delete(id:)`; attaches bearer token; maps 401 → `WearAPIError.unauthorized`, 503 → `.disabled`, 4xx body `{error}` → `.server(message)`.
- `Ranking.swift` — `topWatches(_:limit:)` and `shortLabel(for:)` (brand + truncated model, ≤ ~18 chars for notification/widget buttons; de-duplicated when two watches collide).
- `NudgeSchedule.swift` — pure: `nextFireDates(config: NudgeConfig, now:, calendar:, lastLoggedLocalDay:) -> [Date]` for the next 7 days, **skipping today if already logged today**. `NudgeConfig { enabled, hour, minute }`. Also `isLoggedToday(events, now, calendar)`.
- `WearStore.swift` — actor. Holds snapshot `[WearWatch]`, `current`, and a **pending-event queue** (`PendingQueueStorage` protocol; file-backed impl lives in WristKit). `logWear(watchId, source)`: creates event (UUID, `wornAt = now` with local offset), applies optimistically (count+1, current=event, re-sort), enqueues, attempts `flush()`. `undo(eventId)`: reverse optimistic change, DELETE (or drop from queue if never sent). `refresh()` replaces snapshot but keeps unsent pending events applied on top. Pure Linux tests cover: optimistic ordering, idempotent flush after transport failure, undo before/after send, refresh merge.
- `SecretStore.swift` — `protocol SecretStore { get/set/delete(key) }` + `InMemorySecretStore` for tests.
- `Tests/WristCoreTests/` — XCTest (works on Linux). `MockTransport` records requests and returns scripted responses.

### B2. `WristKit` (iOS-only, shared by app + widget)
- `URLSessionTransport` (`HTTPTransport`), `KeychainSecretStore` (access group `$(AppIdentifierPrefix)com.ryanswatches.wrist.shared`, `kSecAttrAccessibleAfterFirstUnlock` so widget/notification actions work after reboot), `AppGroupStore` (group `group.com.ryanswatches.wrist`: server URL, nudge config, snapshot JSON for the widget, pending queue file).
- `Services.swift` — `LiveServices.make()` wires store + client + keychain + app group; the single composition root used by app, widget, and intents.
- `LogWearIntent: AppIntent` (`watchId` parameter, `openAppWhenRun = false`): `await services.store.logWear(watchId, source: .widget)`, then `WidgetCenter.shared.reloadAllTimelines()`. Used by widget `Button(intent:)` and reusable from Shortcuts.
- `NudgeScheduler` — wraps `UNUserNotificationCenter` behind `protocol NotificationCenterClient` (fake in WristTests). `reschedule(using store)`: compute dates via `NudgeSchedule`, register category `WEAR_PICK` with ≤3 `UNNotificationAction`s whose identifiers are `log:<watchId>` and titles from `shortLabel`, remove all pending `nudge-*` requests, add one non-repeating request per date (ids `nudge-YYYY-MM-DD`). Called on app foreground, after every log, after every refresh. Logging today removes `nudge-<today>`.
- `NotificationActionHandler` — `UNUserNotificationCenterDelegate.didReceive`: parse `log:<watchId>` → `store.logWear(source: .notification)` → `reschedule` → reload widgets. Default tap just opens the picker.

### B3. App target `Wrist/`
- `WristApp.swift` (`@main`, sets delegate, requests notification auth when nudge is first enabled), `AppModel` (`@Observable`, bridges `WearStore` to SwiftUI, handles foreground refresh + queue flush).
- **`PickerView` (home screen, the whole app):**
  - Header card: "Wearing now" — hero thumbnail, brand/model, "since 8:12 AM" (or "Nothing logged yet").
  - List below: rows (thumbnail 56pt, **brand** bold / model, right-aligned "12×"), sorted most-worn; current row shows a checkmark. **Tap row = log** (haptic `.success`, optimistic re-sort animated). No confirm dialog.
  - After a tap: 5-second bottom bar "Logged Citizen Eco Drive · Undo".
  - Pull-to-refresh. Offline/failed send → subtle "1 unsent · retrying" pill; never blocks the tap.
  - Toolbar: single gear → `SettingsView`. No tabs, no onboarding carousel.
- `SetupView` (first launch only): server URL (prefilled `https://ryanswatches.com`), token paste field, "Connect" → `watches()` succeeds → save to Keychain/App Group → picker. Error text inline.
- `SettingsView`: Nudge toggle + time (default 08:00), one-line explanation "Skipped on days you've already logged", "Reset connection", version. That's all.
- Visual: match the site's paper-and-ink palette (cream/near-black, bronze `#8b6634`/`#c89456` accent), system fonts, hairline separators. Dark mode default follows system.

### B4. Widget target `WristWidget/`
- `WristWidgetBundle`, `TopWatchesWidget` with `StaticConfiguration` reading `AppGroupStore` snapshot.
- `.systemSmall`: current watch thumbnail + brand (tap opens app).
- `.systemMedium`: current watch on the left; right column = three `Button(intent: LogWearIntent(watchId:))` chips for top-3 (excluding current). Timeline: single entry, reloaded by the app/intents.

### B5. Mac-only tests `WristTests/`
- `KeychainSecretStore` roundtrip; `NudgeScheduler` with fake center (category has ≤3 actions with correct ids/titles, requests = 7 ids minus today when logged, all removed when disabled); `AppGroupStore` snapshot roundtrip; `LogWearIntent` with mock transport logs + reloads.
- `WristUITests`: launch with `-uiTesting` flag (AppModel swaps in an in-memory transport with fixture data) → tap first row → assert "Wearing now" title changes.

### B6. `project.yml` essentials
Targets `Wrist` (application), `WristWidget` (app-extension, `com.apple.widgetkit-extension`, embedded), `WristTests`, `WristUITests`; local packages `WristCore`, `WristKit`; entitlements for both app + widget: App Group + Keychain access group; `UILaunchScreen` empty dict; `CFBundleDisplayName Wrist`; `DEVELOPMENT_TEAM` left blank (automatic signing in Xcode; simulator needs none). Scheme `Wrist` runs both test bundles.

---

## Part C: Sub-agent fan-out

I (Fable) own: `API.md` contract, `WristCore` design + `WearStore` + `NudgeSchedule`, `WristKit` intent/scheduler/delegate, integration of agent output, review, and test runs. Mechanical, well-specified work goes to sub-agents in parallel waves. Each brief includes the exact file list, interfaces to conform to, the test cases to write, and "do not run anything" (I run the gates).

**Wave 1 (after I write `API.md` + `wear.ts`/`WristCore` interfaces), run concurrently:**
| Agent | Model | Scope |
|---|---|---|
| backend-data | sonnet | A2 `lib/wear.ts` + unit tests; export `applyHeroOverrides` from `redis.ts` |
| backend-routes | sonnet | A1 `wear-auth.ts`, A3 three routes, integration tests + `tests/setup.ts` DB-15 guard, vitest config, package.json scripts/devDeps |
| config-docs | haiku | A4 `.env.example`, `docker-compose.yml`, README section, CLAUDE.md ×2, `.gitignore` |
| swift-models | sonnet | B1 `Models.swift`, `WearAPIClient.swift`, `HTTPTransport.swift`, `Ranking.swift` + `MockTransport` + Codable/ranking tests from `API.md` fixtures |

**Gate 1 (me):** `npm run typecheck && npm test` (REDIS_URL=…/15) in `frontend/`; `docker run --rm -v …/WristCore:/src -w /src swift:6.0-jammy swift test`. Fix or send back.

**Wave 2, concurrently:**
| Agent | Model | Scope |
|---|---|---|
| ios-views | sonnet | B3 `PickerView`, `WatchRow`, `SetupView`, `SettingsView`, `AppModel` against the `WearStore` API + wireframe spec |
| ios-widget | sonnet | B4 widget bundle/views/provider, `AppGroupStore` snapshot reader |
| ios-project | sonnet | B6 `project.yml`, entitlements, `Info.plist` keys, `ios-app/README.md` Mac checklist |
| (me) | — | B2 `WristKit` Keychain/transport/intent/scheduler/delegate, B1 `WearStore` + `NudgeSchedule` |

**Gate 2 (me):** re-run both suites; read every iOS file for API misuse (no compiler here, so this review is the substitute); `/security-review` of the auth path and token handling.

**Wave 3:** ios-tests (sonnet) writes B5 `WristTests` + the smoke UI test against the fakes I defined. Final review pass, then hand-off.

Branch/commits: you've already put the repo on branch `ios-app` (clean tree). I'll commit atomically and often on that branch: one commit per coherent unit (contract docs; data layer + tests; routes + tests; config plumbing; each Swift module; each iOS target; each test bundle; every gate fix), each with the attribution trailer. No pushes unless you ask. I will **not** rebuild/redeploy the live frontend container; that is your call after review.

---

## Verification

**Here (Linux), each gate:**
```bash
cd frontend && npm install && npm run typecheck && REDIS_URL=redis://localhost:6379/15 npm test
docker run --rm -v "$PWD/ios-app/WristCore":/src -w /src swift:6.0-jammy swift test
```
Integration tests seed and flush **only** DB 15; `tests/setup.ts` aborts on any other DB.

**On your Mac (hand-off checklist, also in `ios-app/README.md`):**
```bash
brew install xcodegen
cd ios-app && xcodegen generate && open Wrist.xcodeproj
# or headless:
xcodebuild -scheme Wrist -destination 'platform=iOS Simulator,name=iPhone 16' build test
```
Paste any compiler errors back to me. Then in the simulator: Setup → paste token → list renders sorted → tap a row → "Wearing now" updates, haptic, Undo bar → Settings → enable nudge at a time 1 minute out → lock/background → notification shows 3 action buttons → tap one → reopen app, current + counts updated → add medium widget → tap a chip → widget + app reflect it. Kill network (Simulator ▸ Features) → tap a row → "1 unsent" pill → restore → clears.

**Deploy (you, after review):** generate token (`openssl rand -hex 32`), add `WEAR_API_TOKEN` to the deployment env, `docker compose up -d --build frontend`, confirm `curl -sS -o /dev/null -w '%{http_code}' https://ryanswatches.com/api/wear/watches` is `401` without the header and `200` with it.

## Out of scope (possible follow-ups)
Showing "currently wearing" on the website; hiding sold/fake entries from the picker (`__doodles:wear-hidden` set); Siri `AppEntity` for "log my Speedmaster"; wear-duration analytics; Apple Watch companion.

---

# TODO.md follow-ups: icon, search, hold-to-log, wearing card, wearage page

## Context

The Wrist app and wear API shipped on branch `ios-app` and have real data (one event so far). `TODO.md` lists five follow-ups: three in the app (icon, search, mis-tap protection) and two on the site (a "last one on my wrist" card, a percentage-based "wearage" page with a 7-hour nightly deduction). Decisions already made with you:

- **Card** sits under the brands list in the front-page header.
- **Mis-taps**: hold-to-log with a filling ring (~0.65 s), plus a History screen with swipe-to-delete. Widget chips stay tap-to-log.
- **Wearage math**: a watch is credited from its event until the next event (latest runs to now); at the end of every local day, 7 hours come off whichever watch is on the wrist; the page shows each watch's share of that awake wrist-time, all-time and last 30 days, never hours. Local day via `WEAR_TIMEZONE` (default `America/Los_Angeles`), deduction via `WEAR_SLEEP_HOURS` (default 7). Wear data becomes public on the site.

Verified facts: no new dependencies are needed (`sharp` 0.34 is already in `frontend` and rasterizes SVG; Node 20 has full ICU for `Intl` time zones; `date-fns` v2 has no tz support so day math uses `Intl`). The front page already polls `/api/watch-stats` every 5 minutes, so the card can ride that interval. `/wearage` as a static route wins over the `/[handle]` dynamic route.

---

## Part A — Backend data + one public route (`frontend/`)

### A1. `lib/wearage.ts` (pure, Linux-tested) — me
```ts
export interface WearageOptions { timeZone: string; sleepHours: number; now: Date; since?: Date }
export interface WearageShare { watchId: string; ms: number; share: number; wears: number; lastWornAt: string | null }
export interface WearageSummary { totalMs: number; daysTracked: number; firstEventAt: string | null; shares: WearageShare[] }
export function computeWearage(events: WearEvent[], opts: WearageOptions): WearageSummary
export function localDayStart(ms: number, timeZone: string): number   // Intl-based, DST-safe
export function nextLocalDayStart(ms: number, timeZone: string): number
```
Algorithm: sort events by `wornAt`; interval i = `[e_i, e_{i+1})`, last = `[e_n, now)`; clip to `[since, now)` (an interval that began before `since` counts from `since`); split at local-day boundaries; for every **completed** day, the interval touching the day's end loses `min(sleepHours h, its ms in that day)` (clamp, no spill to earlier watches; the current partial day gets no deduction); sum ms per watch; `share = ms / totalMs`; `wears` = events in window per watch. Unparseable `wornAt` skipped; zero events → empty summary.

Tests (`tests/wearage.test.ts`, fixed `America/Los_Angeles`): one event two full days ago → `2×17h + today's partial`; switch mid-day splits correctly; switch at 23:30 → late watch `0.5h − 7h → 0`, earlier watch keeps its full day; `since` clipping; the 2026-11-01 fall-back 25-hour day still deducts exactly 7h; shares sum to 1 ± 1e-9; `localDayStart` round-trips across DST.

### A2. `lib/wear.ts` additions — me
- Factor `loadCanonicalWithImages()` out of `listWearWatches()` (canonical + hero-aware image + postUrl) and reuse it.
- `getWearingNow(): Promise<WearingNow | null>` → `{ watch: { id, brand, model, imageUrl, thumbnailUrl, postUrl }, event: WearEvent }` from `getCurrentWear()`.
- `getWearageData(now = new Date())` → `{ allTime, last30Days, watches (id → brand/model/images), config: { timeZone, sleepHours } }` using `WEAR_TIMEZONE` / `WEAR_SLEEP_HOURS` (validated: unknown zone → UTC with a `console.warn`; hours clamped 0..23).

### A3. Public route `pages/api/wearing.ts` — sonnet
`GET` only, **no token** (this is the public face, unlike `/api/wear/*`), `rateLimit` 100/min, CORS like `watch-stats.ts` → `200 { wearing: WearingNow | null }`. Tests: null when no events; populated after `recordWear`; 405.

### A4. Config + docs — haiku
`.env.example` + `docker-compose.yml` (`WEAR_TIMEZONE`, `WEAR_SLEEP_HOURS`), README (env vars, `/api/wearing`, `/wearage`, method footnote), root + frontend `CLAUDE.md` (env, routes, `lib/wearage.ts`). `ios-app/API.md` gets one line noting `/api/wearing` is public and outside the token contract. Trim shipped items from `TODO.md` in the final commit.

---

## Part B — Front-page card (`frontend/`) — sonnet

- `components/WearingNow.tsx` + `styles/WearingNow.module.css`: renders nothing when null. One line in the Stats idiom: 28 px round thumbnail (`next/image`), `ON THE WRIST` label (0.6875rem, 0.18em tracking, muted), `Rolex Air King 126900` linking to `/post/<id>?ref=/`, `· since 8:12 AM` (today) or `· since Oct 3`, and a trailing `wearage →` link to `/wearage`. Time formatted after mount (same hydration-safety pattern as the post page). Theme-aware via existing CSS variables; hairline above it inside the header, keeping the bronze `::after` rule as the final gesture.
- `pages/index.tsx`: `serverWearing` from `getWearingNow()` in `getServerSideProps` (try/catch → null); `fetchWearing()` added to the existing 5-minute interval; `<WearingNow>` rendered right after `<Stats>`.

---

## Part C — `/wearage` page (`frontend/`) — sonnet, after reading the dataviz skill

- `pages/wearage.tsx` (SSR via `getWearageData`) + `styles/Wearage.module.css`. Shell mirrors `index.tsx` (top icon row, wordmark link home, page title "Wearage" in the Lato italic style, smaller).
- Sections: numbers strip (`N days tracked · N wears · N watches worn`); **Share of wrist time** with an All time / Last 30 days toggle (both datasets SSR'd, client state): rows of thumbnail 40 px, brand/model, a bar on a hairline track, percentage to one decimal, sorted desc, zero-share watches collapsed into "N never logged"; **By brand** aggregated the same way; **Method** footnote in prose (credited until the next log; 7 h off at the end of each day; shares of awake wrist-time, not hours; time zone named).
- Bars are plain CSS (no chart library). **Before writing them, read the `dataviz` skill**: text percentage always present, bar carries an accessible label, accent-on-hairline palette consistent in light and dark, no 3-D or gradients.

---

## Part D — iOS (`ios-app/`)

### D1. App icon — me
Art-deco mark, subtle: near-black field `#0c0c0c`, bronze `#c89456` thin geometry (stepped sunburst fan behind a circular dial outline, twelve index ticks, a stepped crown at 3 o'clock), inner hairlines in muted `#8a857d`, no text. Three SVG variants in `ios-app/design/`, rasterized to 1024-pt PNG previews by a committed `ios-app/design/render-icon.mjs` (node + the frontend's `sharp`). You pick; the winner becomes `Wrist/Assets.xcassets/AppIcon.appiconset/AppIcon.png` with `filename` set in `Contents.json`. Optional later: iOS 18 dark/tinted variants.

### D2. Search — sonnet
- WristCore `WatchSearch.filter(_ watches: [WearWatch], query: String) -> [WearWatch]`: case- and diacritic-insensitive; every whitespace-separated query token must match somewhere in `brand + " " + model`; empty query returns input unchanged; order preserved. Linux tests.
- `PickerView`: a search row directly under the current card (magnifying glass, `TextField("Search watches")`, clear button, `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`, `.submitLabel(.search)`, rounded `Color(.tertiarySystemFill)` background, identifier `picker.search`). List rows filter live; `ContentUnavailableView.search` when nothing matches; card stays.

### D3. Hold-to-log — me
Rows become plain content (not `Button`) with `.onLongPressGesture(minimumDuration: HoldToLog.duration, maximumDistance: 24, perform:, onPressingChanged:)`. Trailing slot: the `12×` count fades out while pressing and a bronze ring (`Circle().trim(from: 0, to: progress)`, 2.5 pt, rotated −90°) fills linearly over the duration; release early resets it. `perform` → `.success` haptic → `model.log`. `HoldToLog.duration = 0.65`. VoiceOver: `.accessibilityAction(named: "Log")` and hint "Hold to log". Undo bar unchanged. Row identifiers unchanged.

### D4. History screen — sonnet
Toolbar icon `clock.arrow.circlepath` (identifier `picker.history`) → `HistoryView`: recent events (limit 100) grouped by local day; row = thumbnail, watch name, time, source glyph; swipe-to-delete → `model.deleteEvent(id)` which calls `store.undo(eventID:)` (already handles sent and server events) then reloads. `AppModel` gains `recentEvents()` and `deleteEvent(_:)` using a client from a new `WristServices.makeClient() -> WearAPIClient?` (saved connection). Identifiers `history.list`, `history.row.<eventId>`.

### D5. Tests — sonnet
`PickerSmokeTests`: row uses `press(forDuration: 1.0)`; new test opens History and asserts the list exists; search test types "kur" and asserts only the Kurono row remains. `WristCoreTests/WatchSearchTests` on Linux.

### D6. Docs
`ios-app/README.md` checklist gains hold-to-log, search, History, icon. `ios-app/PLAN.md` appended with this plan.

---

## Part E — Fan-out and order

**Wave 1 (parallel):** me → A1 + A2 (+ tests); sonnet `backend-wearing` → A3 + tests; sonnet `front-card` → B against the `WearingNow` shape in A2; sonnet `ios-search` → D2; haiku `config-docs` → A4 (except the TODO trim); me → D1 icon variants.
**Gate 1:** `npm run typecheck && npm test` (Redis DB 15), `swift test` in Docker. Commit per unit.
**Wave 2 (parallel):** sonnet `wearage-page` → C (told to read the dataviz skill file first); sonnet `ios-history` → D4; me → D3 hold-to-log.
**Gate 2:** tests again; my read-through of every iOS file (no compiler here); sonnet `ios-tests` → D5; D6 docs; you pick the icon; wire it; trim `TODO.md`.

Commits atomic on `ios-app` as before, no pushes. I do not rebuild the live frontend container.

---

## Verification

**Here:**
```bash
cd frontend && npm run typecheck && npm test        # DB 15 only
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/ios-app/WristCore":/src -w /src swift:6.0-jammy swift test
```
**Visual check of the site work here**, with your OK as part of this plan: start `npm run dev` (port 42420, which Caddy already exposes as `dev.ryanswatches.com`; SSR reads production Redis DB 0 read-only) and use the Playwright MCP to screenshot `/` (card) and `/wearage` in dark and light, then stop the server. Icon previews land as PNGs in `ios-app/design/` for you to open.

**On your Mac:** `git pull && cd ios-app && xcodegen generate`, build; checklist: hold a row → ring fills → haptic + log; release early → nothing; search "kur" filters; History shows the wear, swipe deletes it and the picker count drops; icon on the Home Screen.

**Deploy (you):** `docker compose up -d --build frontend` for the card, the page, and `/api/wearing`; optionally set `WEAR_TIMEZONE` / `WEAR_SLEEP_HOURS` if the defaults don't fit.
