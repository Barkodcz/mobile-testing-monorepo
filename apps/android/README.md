# Android sample app

A tiny native Android counter app (Jetpack Compose) — increment, decrement, reset — used as this
monorepo's reference app for Android testing frameworks on Bitrise.

Same element IDs as the iOS/React Native/Flutter sample apps (`count_label`,
`decrement_button`, `increment_button`, `reset_button`, exposed as Compose `testTag`s with
`testTagsAsResourceId = true` so Maestro/Appium can find them by resource id), so the exact same
E2E journeys can be written once and ported across platforms.

## Framework / test types

- **Unit tests** — JUnit (`app/src/test`)
- **Snapshot tests** — [Paparazzi](https://github.com/cashapp/paparazzi) (`app/src/test`, same
  source set as unit tests — Paparazzi renders without an emulator)
- **Instrumented UI tests** — Jetpack Compose UI Test (`app/src/androidTest`)

## Folder layout

```
app/
├── build.gradle.kts        <- app module Gradle config (Paparazzi plugin, testOptions, etc.)
└── src/
    ├── main/                <- app code (MainActivity.kt, Compose UI)
    ├── test/                <- JUnit unit tests + Paparazzi snapshot tests
    └── androidTest/         <- instrumented Compose UI tests (run on an emulator/device)
build.gradle.kts            <- project-level Gradle config
settings.gradle.kts
gradle.properties
gradlew / gradlew.bat
```

## Run tests locally

```bash
cd apps/android
./gradlew testDebugUnitTest            # unit tests
./gradlew verifyPaparazziDebug         # snapshot tests (fails on any pixel diff)
./gradlew recordPaparazziDebug         # re-record snapshot baselines
./gradlew connectedDebugAndroidTest    # instrumented UI tests (needs a running emulator/device)
```

## CI

See [`../../bitrise/android.md`](../../bitrise/android.md) for the full Bitrise setup (every
workflow, step, and how video/screenshots reach the Tests tab).
