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
