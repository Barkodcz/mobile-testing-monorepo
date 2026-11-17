# Flutter sample app

A tiny Flutter counter app (`CounterApp`/`CounterScreen`) — increment, decrement, reset — used as
this monorepo's reference app for Flutter testing frameworks on Bitrise. The `android/`/`ios/`
native platform folders aren't committed; every CI workflow regenerates them with `flutter
create` if missing (they're build output, not source).

Same element IDs as the Android/iOS/React Native sample apps (`count_label`,
`decrement_button`, `increment_button`, `reset_button`, exposed as Flutter `Key`s), matching the
"same app, same tags, many frameworks" convention used across this whole monorepo.

## Framework / test types

- **Unit/widget tests** — `flutter_test` (`test/`)
- **Golden (pixel-diff) tests** — `flutter_test`'s built-in golden-image comparison
  (`test/goldens/`)
- **Instrumented tests** — [`integration_test`](https://docs.flutter.dev/testing/integration-tests)
  (Flutter's own instrumented-test framework, runs on a real Android emulator)
- **Patrol** — [Patrol](https://patrol.leancode.co) (`patrol_test/`), `integration_test` plus
  *native*, non-Flutter interactions (press Home, open the notification shade), run on both
  Android (via Gradle/instrumentation) and iOS (via an XCUITest-based runner)

## Folder layout

```
lib/                 <- app source (main.dart, counter widget)
test/                <- unit, widget, and golden tests; test/goldens/ holds committed baselines
integration_test/    <- integration_test suite
patrol_test/          <- Patrol suite (counter_patrol_test.dart)
tool/
├── patrol_setup_android.py   <- patches the generated android/ project for Patrol's JUnit runner
└── patrol_setup_ios.rb       <- patches the generated ios/ project for Patrol's XCUITest runner
pubspec.yaml
```

## Run tests locally

```bash
cd apps/flutter
flutter test                                    # unit, widget, golden
flutter test --update-goldens test/goldens      # re-record golden baselines
flutter test integration_test -d <device-id>    # needs a running Android emulator

dart pub global activate patrol_cli 4.8.0
patrol test --device <device-id>                # Android emulator or iOS Simulator
```

## CI

See [`../../bitrise/flutter.md`](../../bitrise/flutter.md) for the full Bitrise setup — every
workflow and step, the native project setup Patrol needs on each platform, and how
video/screenshots reach the Tests tab (including a known gap: Patrol screenshots don't currently
attach on iOS).
