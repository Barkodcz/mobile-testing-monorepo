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

See the implementation guide for the full Bitrise setup.
