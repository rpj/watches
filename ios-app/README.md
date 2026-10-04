# Wrist — iOS companion for Ryan's Watches

Wrist is a one-tap "I'm wearing this" logger for the watch collection, with the most-worn watches listed first. It sends a morning nudge notification with action buttons for your top watches, and has a Home Screen widget for logging without opening the app.

## Layout

| Path | What |
| --- | --- |
| `WristCore/` | SwiftPM, pure Foundation (models, API client, ranking, nudge schedule, wear store). Linux-testable. |
| `WristKit/` | SwiftPM, iOS-only code shared by app and widget (Keychain, App Group, URLSession transport, intents, nudge scheduler). |
| `Wrist/` | SwiftUI app target. |
| `WristWidget/` | Widget extension target. |
| `WristTests/` | iOS XCTest (Mac only): WristKit seams with fakes. |
| `WristUITests/` | One smoke XCUITest: launch, tap first row, "Wearing" label updates. |
| `project.yml` | XcodeGen spec. `Wrist.xcodeproj` is generated and gitignored. |

## Requirements

- macOS 14.5+ and Xcode 16+
- `brew install xcodegen`
- An Apple Developer team ID for signing (a free personal team is fine)

## Generate & open

```bash
cd ios-app
DEVELOPMENT_TEAM=YOUR_TEAM_ID xcodegen generate
open Wrist.xcodeproj
```

Find your team ID in Xcode > Settings > Accounts, or under Membership at developer.apple.com. If `com.ryanswatches` is taken under your team, change the bundle prefix, bundle IDs, App Group (`group.com.ryanswatches.wrist`) and keychain group in `project.yml` (and the matching strings in WristKit), then regenerate.

## Run in the simulator

Pick the `Wrist` scheme and an iPhone 16 simulator, then press Cmd-R. First launch shows Setup: enter the server URL (default `https://ryanswatches.com`) and the token, which is the server's `WEAR_API_TOKEN`. For the dev server use `https://dev.ryanswatches.com`.

## Headless build & test

```bash
xcodebuild -scheme Wrist -destination 'platform=iOS Simulator,name=iPhone 16' build test
```

Unit tests only:

```bash
xcodebuild -scheme Wrist -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:WristTests
```

## Linux-side tests

What runs without a Mac (WristCore only):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/WristCore":/src -w /src swift:6.0-jammy swift test
```

## Manual E2E checklist

Use Simulator > Features > Toggle Appearance to check both dark and light.

1. Launch, complete Setup, paste the token.
2. The watch list renders sorted most-worn first.
3. Tap a row: "Wearing now" updates, a haptic fires, and the Undo bar appears.
4. Open Settings and enable the nudge at a time 1 minute out.
5. Background or lock the app.
6. The notification appears with 3 action buttons.
7. Tap one, then reopen the app: current watch and counts are updated.
8. Add the medium widget to the Home Screen.
9. Tap a chip in the widget: both the widget and the app reflect it.
10. Simulator > Features > turn the network off, then tap a row: a "1 unsent" pill shows.
11. Turn the network back on: the pill clears.

## Server setup

```bash
openssl rand -hex 32   # generate the token
# add WEAR_API_TOKEN=<token> to the deployment env, then:
docker compose up -d --build frontend

# 401 without the header
curl -sS -o /dev/null -w '%{http_code}\n' https://ryanswatches.com/api/wear/watches
# 200 with it
curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $WEAR_API_TOKEN" https://ryanswatches.com/api/wear/watches
```

## Troubleshooting

- **"Signing for Wrist requires a development team"**: set `DEVELOPMENT_TEAM` and run `xcodegen generate` again.
- **"No such module WristKit" / "WristCore"**: File > Packages > Resolve Package Versions, or regenerate the project.
- **Widget not updating**: remove and re-add the widget; confirm the App Group id is identical in both entitlements files.
- **Notifications not showing in the simulator**: allow them under Settings app > Wrist > Notifications, and make sure the app was foregrounded once after enabling the nudge.
