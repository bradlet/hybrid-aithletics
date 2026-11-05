# Mobile Testing on iPhone

A guide for installing and testing Hybrid AIthletics on a physical iPhone for real-world testing and personal use.

## Prerequisites

Before you can run the app on your iPhone, you'll need:

- **iPhone running iOS 17+** (tested on iPhone 17 Pro)
- **Free Apple ID** — Sign in to Xcode with your Apple ID
- **USB cable or Wi-Fi connection** — For connecting your device to Xcode
- **Xcode 15+** with the app project open

## One-Time Setup

### 1. Add Your Apple ID to Xcode

1. Open Xcode
2. Go to **Xcode** menu > **Settings** (or **Preferences** on older versions)
3. Click the **Accounts** tab
4. Click **+** to add an account
5. Select **Apple ID** and sign in with your credentials
6. Xcode will automatically create a free development team for you

### 2. Configure Code Signing

Code signing proves the app came from you. Xcode can manage this automatically:

1. Open the Hybrid AIthletics project in Xcode
2. Select the **Hybrid AIthletics** target in the project navigator
3. Go to the **Signing & Capabilities** tab
4. Check **Automatically manage signing**
5. Select your **Team** from the dropdown (your Apple ID account)
6. Xcode will create a development certificate and provisioning profile automatically

If you see errors:
- Make sure your Apple ID is listed in **Settings > Accounts**
- Try clicking **Download Manual Profiles** if automatic management fails
- Ensure your bundle identifier is unique (e.g., `com.yourname.HybridAIthletics`)

### 3. Connect Your iPhone

**Via USB (recommended):**
1. Connect your iPhone to your Mac with a USB cable
2. Unlock your iPhone and tap **Trust** when prompted
3. Open Xcode — your device should appear in the top toolbar

**Via Wi-Fi:**
1. Connect both your Mac and iPhone to the same Wi-Fi network
2. In Xcode, go to **Window** > **Devices and Simulators**
3. Select your iPhone in the left sidebar
4. Check **"Connect via network"** and confirm
5. Your device should appear in Xcode's build target dropdown

### 4. Trust the Developer Certificate on Your iPhone

The first time you run an app signed with your development certificate, you must trust it:

1. On your iPhone, go to **Settings** > **General** > **VPN & Device Management**
2. Tap the developer certificate (your Apple ID name)
3. Tap **Trust** and confirm

You only need to do this once per certificate.

## Building and Installing the App

### Run on Device from Xcode

1. **Select your iPhone as the build target:**
   - Click the target dropdown at the top-left of Xcode (next to the scheme)
   - Select your iPhone from the list

2. **Build and run:**
   - Press **Cmd+R** (or click the Play button)
   - Xcode will compile the app and install it on your device
   - The app launches automatically when installation completes

3. **App stays on your iPhone:**
   - The app remains installed and you can tap it to open it anytime
   - To update after code changes, just rebuild in Xcode

### Command-Line Build and Install

Alternatively, build from the terminal:

```bash
xcodebuild \
  -scheme "Hybrid AIthletics" \
  -destination 'platform=iOS,name=iPhone 17 Pro' \
  -configuration Debug \
  build-for-testing
```

Replace `iPhone 17 Pro` with your actual device name if different. Find it with:

```bash
xcrun xctrace list devices 2>&1 | grep -i iphone
```

## Testing the App

### Real Device Testing Advantages

Testing on a real device is important because:

- **Performance** — Simulators don't accurately reflect real performance; device testing shows true speed
- **CloudKit sync** — Cloud syncing works on device but is limited in the simulator
- **Storage constraints** — Test with limited device storage
- **Network conditions** — Test with real cellular and Wi-Fi connections
- **Touch feel** — UI feels different on actual hardware vs. simulator
- **Battery usage** — Monitor real battery drain during extended testing

### Testing Workflows

**Quick Testing:**
1. Make a code change in Xcode
2. Press **Cmd+R** to rebuild and reinstall
3. The app relaunches automatically

**Background Testing:**
1. Build and run the app (it installs on your device)
2. Leave Xcode
3. Use the app normally on your iPhone
4. When you're ready to test a code change, go back to Xcode and press **Cmd+R**

**Debugging Issues:**
1. Connect your iPhone and select it as the target in Xcode
2. Build and run (press **Cmd+R**)
3. Use Xcode's **Debug Navigator** to view console output
4. Set breakpoints in code and step through execution

## Reviewing Installed Data

Once the app is running on your device, you can inspect CloudKit data and local storage:

### CloudKit Data
- In Xcode, go to **Window** > **Developer Tools** > **CloudKit Dashboard**
- Sign in with the same Apple ID you use on your iPhone
- View your app's CloudKit container and any synced workouts

### Local Storage
- Xcode's Debug Navigator shows app logs and memory usage
- CloudKit sync status is logged during app runtime

## Running Tests from the CLI

### Unit Tests (macOS — fast, no simulator)

Unit tests run on your Mac and don't require a simulator. They test data models, CSV parsing, formatting logic, and other non-UI code:

```bash
# Run all unit tests
xcodebuild test -scheme "Hybrid AIthletics" \
  -only-testing:"Hybrid AIthleticsTests"
```

This is fast and ideal for development iteration. Tests use a stub AI coach service, so the Gemma model is not needed.

### UI Tests (iOS Simulator)

UI tests require a simulator and exercise the full app interface — calendar interaction, workout recording, deletion flows, etc.:

```bash
# Run all UI tests on iPhone 17 simulator
xcodebuild test -scheme "Hybrid AIthletics" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hybrid AIthleticsUITests"
```

### History Tab Functional Tests

To run only the History tab UI tests:

```bash
xcodebuild test -scheme "Hybrid AIthletics" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hybrid AIthleticsUITests/HistoryUITests"
```

### AICoachCore Package Tests

Test the shared prompt-building library (no iOS dependency):

```bash
cd Packages/AICoachCore && swift test
```

## Troubleshooting

### "Cannot run in foreground"
- Your iPhone storage is likely full
- Free up space by deleting photos, apps, or other files
- Try reinstalling: Uninstall the app from your iPhone, then rebuild in Xcode

### "Code signing failed" or "Team unavailable"
- Verify your Apple ID is in **Xcode Settings > Accounts**
- Check that **Automatically manage signing** is enabled and a Team is selected
- Try restarting Xcode

### "Device not appearing in Xcode"
- Unlock your iPhone and tap **Trust** if prompted
- Unplug and re-plug the USB cable
- Restart both Xcode and your iPhone
- For Wi-Fi connection issues, disconnect and reconnect to the network

### App crashes on launch
- Check Xcode's Debug console (bottom panel) for crash logs
- Look for error messages like `CoachRuntimeError.runtimeUnavailable` — the MLX packages weren't resolved for this build (tests use a stub, so they never hit it)
- For other crashes, set a breakpoint and rebuild to debug

### CloudKit sync not working
- Ensure you're signed in to iCloud on your iPhone (**Settings > [Your Name] > iCloud**)
- Verify the CloudKit container ID in `Hybrid_AIthletics.entitlements` matches your registered container in the Apple Developer portal
- Check network connectivity

## Uninstalling the App

To remove the app from your iPhone:
- Tap and hold the app icon on your home screen
- Select **Remove App** > **Delete App** > **Delete**
- Or go to **Settings > General > iPhone Storage**, find the app, and select **Delete App**

Note that this will also delete all app data. Rebuilding in Xcode will reinstall it.

## Next Steps

- See [README.md](../README.md) for build and test commands
- See [RELEASING.md](./RELEASING.md) for publishing to the App Store
- See [ARCHITECTURE.md](./ARCHITECTURE.md) for app architecture details
