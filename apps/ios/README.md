# iOS sample app

A tiny native iOS counter app (SwiftUI) — increment, decrement, reset — used as this monorepo's
reference app for iOS testing frameworks on Bitrise. The Xcode project itself isn't committed; it
is generated from [`project.yml`](project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen).

Same element IDs as the Android/React Native/Flutter sample apps (`count_label`,
`decrement_button`, `increment_button`, `reset_button`, exposed via `accessibilityIdentifier`),
so the exact same E2E journeys can be written once and ported across platforms.

## Framework / test types

- **Unit tests** — [Swift Testing](https://developer.apple.com/documentation/testing) and classic
  XCTest, side by side in the same target/scheme (`CounterAppTests`)
- **Snapshot tests** — [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
  (`CounterAppTests/__Snapshots__` holds the committed reference images)
- **UI tests** — XCUITest (`CounterAppUITests`), run four different ways in CI (native Step, two
  manual `xcodebuild` approaches, and via fastlane `scan`) specifically to demonstrate the
  tradeoffs between them — see the CI doc.
- **E2E** — [Maestro](maestro/) flows against the built app
- **E2E** — [Appium](../../e2e/appium/) (XCUITest driver) against a local simulator

## Folder layout

```
project.yml              <- XcodeGen project definition (generates CounterApp.xcodeproj)
CounterApp/               <- app source (SwiftUI views, state)
CounterAppTests/          <- Swift Testing + XCTest unit tests, snapshot tests + baselines
CounterAppUITests/        <- XCUITest UI tests
maestro/                  <- Maestro E2E flow files
fastlane/                 <- fastlane Fastfile/Appfile (scan lane for XCUITest)
```

## Run tests locally

```bash
cd apps/ios
brew install xcodegen && xcodegen generate
xcodebuild test -project CounterApp.xcodeproj -scheme CounterApp-Unit \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project CounterApp.xcodeproj -scheme CounterApp-UI \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI

See [`../../bitrise/ios.md`](../../bitrise/ios.md) for the full Bitrise setup — every workflow and
step, why several different approaches to the same XCUITest suite exist side by side, and how
video/screenshots reach the Tests tab.
