# Mobile Testing Monorepo

One Bitrise app, four sample apps, every common mobile test type. Each platform has its own
Bitrise config module in `bitrise/`, and each module's pipeline only runs when its files change.

| Folder | App | Tests | Bitrise pipeline |
| --- | --- | --- | --- |
| `apps/ios` | SwiftUI (XcodeGen) | Swift Testing, swift-snapshot-testing, XCUITest | `ios` |
| `apps/android` | Jetpack Compose | JUnit, Paparazzi, Compose UI Test | `android` |
| `apps/react-native` | React Native | Jest + RNTL, Jest snapshots, Detox | `react_native` |
| `apps/flutter` | Flutter | unit, widget, golden, integration_test, Patrol | `flutter` |
| `e2e/maestro` | (Android app) | Maestro flows | `maestro` |
| `e2e/appium` | (Android app) | Appium + pytest on BrowserStack | `appium` |

## Run locally

```bash
# iOS (macOS + Xcode 16)
cd apps/ios && brew install xcodegen && xcodegen generate
xcodebuild test -project CounterApp.xcodeproj -scheme CounterApp-Unit -destination 'platform=iOS Simulator,name=iPhone 16'

# Android (JDK 17 + Android SDK)
cd apps/android && ./gradlew testDebugUnitTest verifyPaparazziDebug connectedDebugAndroidTest

# React Native
cd apps/react-native && npm ci && npx jest

# Flutter
cd apps/flutter && flutter test
cd apps/flutter && patrol test   # Patrol: emulator running, see guide Step 5b

# Maestro (emulator running, Android app installed)
maestro test e2e/maestro
```

See the implementation guide for the full Bitrise setup. See `docs/testing-guide.md` for a
detailed walkthrough of every suite and its on/off switches, and
`docs/new-test-scenarios-plan.md` for the scenarios below (Maestro iOS/RN, VDT, sharding, Appium
local, classic XCTest, fastlane scan) with final per-scenario status and required secrets.

## All workflows

Pipeline-only entries run a fixed set of workflows and aren't triggered directly; everything
else can be started standalone from the Bitrise UI. "Where" is the device target; "Sharded"
and "Video" describe the Tests-tab result, not whether a recording script exists.

| Workflow / Pipeline | Platform | Framework | Where | Sharded | Video | Trigger |
| --- | --- | --- | --- | --- | --- | --- |
| `ios_unit_tests` | iOS | Swift Testing + swift-snapshot-testing | simulator (local VM) | no | no | push/PR (`ios`) |
| `ios_ui_tests` | iOS | XCUITest (native Step) | simulator (local VM) | no | xcresult only (not Tests-tab) | push/PR (`ios`) |
| `ios_ui_tests_manual` | iOS | XCUITest (manual `xcodebuild test`) | simulator (local VM) | no | yes | manual |
| `ios-fastlane-scan` | iOS | XCUITest via fastlane `scan` | simulator (local VM) | no | yes | manual |
| `ios-maestro-e2e` | iOS | Maestro | simulator (local VM) | no | yes | manual |
| `ios-appium-local` | iOS | Appium (XCUITest driver) + pytest | simulator (local VM) | no | yes | manual |
| `ios_xcuitest_sharded` (pipeline: build→calc→shard-1/2) | iOS | XCUITest, `xcode-test-shard-calculation` | simulator (local VM) | yes (`XCUITEST_SHARD_COUNT`, default 2) | no | manual |
| `android_unit_tests` | Android | JUnit (native Step) | JVM, no device | no | no | push/PR (`android`) |
| `android_snapshot_tests` | Android | Paparazzi | JVM, no device | no | diff images | push/PR (`android`) |
| `android_record_snapshots` | Android | Paparazzi (record mode) | JVM, no device | no | no | manual |
| `android_ui_tests` | Android | Compose UI Test (instrumented) | emulator (local VM) | no | yes | push/PR (`android`) |
| `android-espresso-vdt` | Android | Same Compose UI tests, via Virtual Device Testing | Bitrise VDT (Firebase Test Lab) | no | yes (VDT-provided) | manual, **needs VDT add-on enabled** |
| `rn_jest_tests` | React Native | Jest + RNTL + Jest snapshots | JVM, no device | no | no | push/PR (`react_native`) |
| `rn_detox_ios` | React Native | Detox | simulator (local VM) | no | yes | push/PR (`react_native`) |
| `android-maestro-e2e-rn` | React Native | Maestro | emulator (local VM) | no | yes | manual |
| `ios-maestro-e2e-rn` | React Native | Maestro | simulator (local VM) | no | yes | manual |
| `flutter_tests` | Flutter | unit, widget, golden | JVM, no device | no | no | push/PR (`flutter`) |
| `flutter_record_goldens` | Flutter | golden (record mode) | JVM, no device | no | no | manual |
| `flutter_integration_tests` | Flutter | `integration_test` | emulator (local VM) | no | yes | push/PR (`flutter`) |
| `flutter_patrol_android` | Flutter | Patrol | emulator (local VM) | no | yes (+ native screenshots) | push/PR (`flutter`) |
| `maestro_android` | (Android app) | Maestro | emulator (local VM) | no | yes | push/PR (`maestro`) |
| `appium_browserstack` | (Android app) | Appium + pytest | BrowserStack (real device) | no | yes | push on main (`appium`), **needs `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY`** |
| `android-appium-local` | (Android app) | Appium + pytest | emulator (local VM) | no | yes | manual |
| `android_maestro_sharded` (pipeline: build→shard-1/2/3) | (Android app) | Maestro | emulator (local VM) | yes (`MAESTRO_SHARD_COUNT`, default 3) | yes | manual |

### Secrets / accounts to add in Bitrise (never hardcoded)

- `BROWSERSTACK_USERNAME`, `BROWSERSTACK_ACCESS_KEY` — Secrets, for `appium_browserstack`. Already
  required before this round of scenarios; unchanged here.
- Virtual Device Testing add-on enabled on this app (Bitrise dashboard → app → Add-ons) — for
  `android-espresso-vdt`. No separate Firebase/GCP credential needed: once enabled, the Step's
  `api_token` input resolves from the auto-provisioned `$ADDON_VDTESTING_API_TOKEN`.
