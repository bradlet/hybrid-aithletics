# Hybrid AIthletics

Hybrid AIletics (pronunciation: `/eɪˈθlɛtɪks/`; "ay-THLET-iks") is an iOS exercise tracking application designed for hybrid athletes with a focus on endurance training. It is a *personal* fitness application, explicitly without social aspects to support the notion that our fitness journies should not be built on comparison but through self-motivation to reach our own health and fitness goals.

The app helps plan weekly training routines, record completed workouts, and track mileage over time. It also provides dynamic exercise program insights and suggestions utilizing onboard AI. We explicitly opt to use small language models which can run entirely on your own mobile device for several key reasons:

1. We believe that you should always have complete ownership of your data. Your health data will never be shared with an AI provider / company through any API; it never leaves your phone (though, we do support ICloud storage, but this is highly secure and not shared with 3rd parties).
2. We want you to feel comfortable getting AI insights on your training as often as possible, without worrying about environmental impact: your usage is not adding to the plethora of data centers using energy and water; it's all on-device with lightweight AI models.
3. We will always maintain a **zero-subscription model**. We are tired of the subscription economy, too, and want to provide a highly-functional tool to aid you in your health and endurance competition journey, that will keep you performing at your peak for years to come.

We don't withhold any features from the free app. Upgrade one time only to support the creators and unlock an ad-free experience. Forever.

## Features

### Aerobic Training (Tab 1)
- **Weekly calendar** with Sunday-Saturday swimlanes showing planned exercises
- **Drag-and-drop** to reschedule exercises between days
- **Mileage header** showing planned vs. completed miles for the current week with progress indicator
- **Record workouts** via the checkmark button on any exercise — pre-fills from the plan, all fields editable
- **Repeat weekly** — mark any exercise as repeating and it automatically appears on the same day every week
- **Exercise types**: Run, Long Run, Tempo Run, Interval Run, Easy Run, Recovery Run, Walk, Bike, Swim, Hike, Elliptical, Other

### AI Coach
- **On-device running coach** powered by Google's Gemma 4 E2B running locally via [MLX-Swift](https://github.com/ml-explore/mlx-swift-examples)
- Reviews the last four weeks of recorded workouts — including two optional radial-dial ratings, **"How did it feel?" (1–5, Very Weak → Very Strong)** and **"How hard was it?" (RPE 1–10)** — and the next two weeks of scheduled exercises
- Suggests concrete adaptations: workout type, duration, distance, intensity, additions, or removals
- **Fully offline** after initial model download, no API calls, no subscription — aligned with the one-time-payment business model
- Model weights (~4.3 GB) are downloaded from Hugging Face on first use and cached locally for offline access

### Strength Training (Tab 2)
- Placeholder — weekly strength training calendar coming in a future release

### History (Tab 3)
- **Summary stats**: all-time, year-to-date, and month-to-date mileage
- **Monthly calendar** with colored workout indicators and day-tap detail popovers
- **Paginated workout log** sorted by most recent, with lazy-loading scroll
- **CSV export/import** and **Apple Health import** in the toolbar menu
- **Google Sheets Sync** — opt-in auto export of the entire workout history to a personal Google Sheet on every add/edit/delete (one-way; the sheet is overwritten on every save). See [Google Sheets Sync Setup](#google-sheets-sync-setup) below.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI |
| Data | SwiftData |
| Sync | CloudKit (automatic via SwiftData) |
| On-device LLM | MLX-Swift + Gemma 4 E2B (4-bit, downloaded on first use) |
| Testing | Swift Testing framework |
| Min iOS | 17.0 |

## Project Layout

```
Hybrid AIthletics/
  Models/           SwiftData @Model classes and ExerciseType enum
  Config/           ModelContainer factory, environment keys (units, aiCoach)
  Extensions/       Date arithmetic, distance formatting
  Services/
    AICoach/        Protocol-based on-device coach (MLX + Gemma 4 E2B)
  Views/
    AerobicTraining/  Weekly calendar, exercise cards, add/record sheets, AI coach sheet
    Strength/         Placeholder view
    History/          Summary stats, monthly calendar, workout list
  ContentView.swift   Root TabView
  Hybrid_AIthleticsApp.swift  App entry point (injects AICoachService)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture documentation, [docs/DATA_MODEL.md](docs/DATA_MODEL.md) for an in-depth data model reference, [docs/adrs/](docs/adrs/) for architectural decision records, [docs/MOBILE_TESTING.md](docs/MOBILE_TESTING.md) for testing on a physical iPhone, and [docs/RELEASING.md](docs/RELEASING.md) for App Store publishing instructions.

## Building

Open `Hybrid AIthletics.xcodeproj` in Xcode 15+ and build for an iOS 17+ simulator or device.

### AI Coach Model

The AI coach model (~4.3 GB, Gemma 4 E2B 4-bit) downloads automatically from Hugging Face on first use and is cached locally for offline access. No manual setup is required — the MLXLLM framework handles downloading and caching transparently.

> **Note:** The app compiles, runs, and passes all tests without any model present. All unit tests use `StubAICoachService`.

### CloudKit Setup

CloudKit sync is configured but requires a container ID registered in the Apple Developer portal. Update the container identifier in:
1. `Hybrid_AIthletics.entitlements` — `icloud-container-identifiers` array
2. Apple Developer portal — register the iCloud container

## Google Sheets Sync Setup

The Google Sheets Sync feature is opt-in: when enabled from the History tab's toolbar menu, the entire workout history is overwritten to a Google Sheet on every add, edit, or delete (debounced to 30 seconds). The sheet itself is created in the user's Google Drive on first enable; the app stores its ID in `AppConfiguration` (CloudKit-synced across devices).

To work, the app needs a Google Cloud Console **OAuth 2.0 iOS Client ID** registered against this app's bundle identifier. Tokens are stored in the iOS Keychain by the `GoogleSignIn-iOS` SDK; the app stores no client secret (iOS OAuth clients are public clients).

### One-time setup (developer side)

#### 1. Add the GoogleSignIn-iOS Swift package

In Xcode: **File → Add Package Dependencies…**, paste `https://github.com/google/GoogleSignIn-iOS`, choose "Up to next major version" from `9.0.0`. Add the **GoogleSignIn** product to the `Hybrid AIthletics` target.

The app's sync code is gated behind `#if canImport(GoogleSignIn)` (mirroring the MLX-Swift pattern), so the project builds and runs even before this dependency is added — sync attempts simply throw `notImplemented` until the SDK is wired up.

#### 2. Create a Google Cloud project and enable the Sheets API

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and create (or pick) a project.
2. **APIs & Services → Library** → search for **Google Sheets API** → Enable.

#### 3. Configure the OAuth Consent Screen

The app uses the `auth/drive.file` scope, which grants per-file access only to the spreadsheet the app creates — not the rest of the user's Drive. This is a **non-sensitive** scope, so no Google verification or privacy-policy URL is required.

> **Note on the 7-day token expiry:** while the app stays in **Testing** publishing status, Google expires refresh tokens after 7 days. (The no-expiry exemption applies only to apps that request *solely* the basic `openid`/`email`/`profile` scopes — `drive.file`, though non-sensitive for verification purposes, is not one of them.) This is expected: when a token expires the History tab's sync menu shows **"Sign in to resume Sheets Sync"**, which re-authenticates and resumes syncing to the **same** spreadsheet (it never creates a new file). To avoid the weekly expiry entirely, publish the OAuth consent screen to **In production** — for the non-sensitive `drive.file` scope this needs no verification.

1. **APIs & Services → OAuth consent screen** → User type: **External** → Create.
2. App information: name (e.g. "Hybrid AIthletics"), user support email, developer contact email. The app logo, privacy policy URL, ToS URL, and authorized domains can all be left blank.
3. **Scopes** step: add `https://www.googleapis.com/auth/drive.file`. Do **not** add `auth/spreadsheets` — that scope is broader (full Drive Sheets access) and would trigger sensitive-scope verification.
4. **Test users** step: add your own Google account email. Only test users can sign in while the app is in Testing mode.
5. Save. Publishing status stays at **Testing** indefinitely; no verification needed.

#### 4. Create the iOS OAuth Client ID

1. **APIs & Services → Credentials → + Create Credentials → OAuth client ID**.
2. Application type: **iOS**.
3. Bundle ID: paste this app's bundle identifier (visible in Xcode → project → Signing & Capabilities). It looks like `com.bradlet.HybridAIthletics` or similar.
4. **App Store ID** and **Team ID** fields are optional and can be left blank for development.
5. Click Create. Copy the **Client ID** (looks like `1234567890-abcdef…apps.googleusercontent.com`).

iOS OAuth clients **do not have a client secret** — they're public clients and use PKCE under the hood. This is correct and expected.

#### 5. Wire the Client ID into the app

Edit `Hybrid AIthletics/Info.plist` and add the following two top-level keys (replace `YOUR_CLIENT_ID` and `YOUR_REVERSED_CLIENT_ID`):

```xml
<key>GIDClientID</key>
<string>1234567890-abcdef.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.1234567890-abcdef</string>
        </array>
    </dict>
</array>
```

The `CFBundleURLSchemes` value is the **reversed** form of the Client ID (split on `.`, reverse the order, drop the `.apps.googleusercontent.com` suffix and prepend `com.googleusercontent.apps`). Google Cloud Console shows you the exact reversed form on the iOS Client ID detail page — copy it from there to avoid typos.

#### 6. (Optional) Verify locally

Build and run the app. Open the History tab → toolbar menu → **Google Sheets Sync** → Enable. The OAuth flow should present in an in-app browser, you sign in with the Google account you registered as a test user (Option A) or any Google account (Option B once verified), grant the Sheets scope, and the app creates a new spreadsheet titled "Hybrid AIthletics" in your Drive and writes the workout history.

### What the user sees in-app

- **Disabled** (default): toolbar menu shows **Google Sheets Sync** as a single button. Tapping it shows a confirmation alert explaining export-only behavior. On confirm: OAuth → spreadsheet created → initial sync.
- **Enabled, healthy**: menu shows **Disable Google Sheets Sync**. Mutations debounce for 30 s then upload silently.
- **Enabled, last sync failed** (transient network/API error): a red dot overlays the toolbar's `…` icon. Menu shows a **Retry** button with the failure reason.
- **Enabled but the OAuth token is missing or expired** (a fresh CloudKit-synced device, or the 7-day Testing-mode expiry): menu shows **Sign in to resume Sheets Sync**. Tapping presents OAuth — re-signing in even when a stale, expired session is cached — and then re-syncs to the existing spreadsheet (does not create a new one).

## Running Tests

Tests use the Swift Testing framework.

### Unit Tests (macOS — fast, no simulator needed)

Run from Xcode (Cmd+U) or via CLI:

```bash
# Run all unit tests on macOS
xcodebuild test -scheme "Hybrid AIthletics" \
  -only-testing:"Hybrid AIthleticsTests"
```

Unit tests run on macOS and don't require a simulator. They're fast and test all SwiftData models, CSV parsing, date/distance formatting, and logic layer code. Tests use `StubAICoachService` so the model is not needed.

### UI Tests (iOS Simulator)

Run UI tests with:

```bash
# Run all UI tests on iPhone 17 simulator
xcodebuild test -scheme "Hybrid AIthletics" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hybrid AIthleticsUITests"
```

UI tests exercise the full app in the simulator and validate multi-step flows like calendar navigation, workout recording, and deletion.

### AICoachCore Package Tests

Test the shared prompt-building library:

```bash
cd Packages/AICoachCore && swift test
```

## Distance Units

All distances are stored internally in miles. A central `AppConfiguration` model controls display units (miles or kilometers), propagated via a SwiftUI `EnvironmentKey`. To switch to metric, update `AppConfiguration.useMetricUnits` — all views react automatically.

## License

This project is licensed under the [MIT License](LICENSE) with the [Commons Clause](https://commonsclause.com/) condition. You are free to view, fork, modify, and contribute to the source code, but you may not sell the software or any product substantially derived from it. See the [LICENSE](LICENSE) file for full terms.
