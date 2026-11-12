# New test scenarios plan

Discovery + plan for 7 additive scenarios. **Nothing has been implemented yet.** Per the task's
own rule, this is written before any changes, and flags anything that needs your input first.

## Confirmed: all 4 apps already share identical element IDs
`count_label`, `decrement_button`, `increment_button`, `reset_button` — exposed as
`accessibilityIdentifier` (iOS), `testTag` + `testTagsAsResourceId=true` (Android), `testID`
(React Native), `Key(...)` (Flutter). This means Maestro flows and Appium locators can be
written almost identically across platforms, and the existing Android Maestro flows can be
near-verbatim ported to iOS/RN by swapping `appId`.

## Exact Bitrise Step versions confirmed via step_search (to pin)
- `xcode-build-for-test@3.6.0`
- `xcode-test-shard-calculation@0.2.1`
- `xcode-test-without-building@1.0.1`
- `virtual-device-testing-for-android@1.3.6`
- `android-build-for-ui-testing@1.0.0` (already used before `android_ui_tests` was switched to a script route; still valid, unmodified here)

---

## Scenario-by-scenario plan

### 1. Maestro on iOS
- **New files**: `apps/ios/maestro/config.yaml`, `apps/ios/maestro/counter_basic.yaml`,
  `apps/ios/maestro/counter_reset.yaml` — ports of the two existing Android flows, `appId:
  io.bitrise.sample.counter` (same bundle ID family, confirmed in `apps/ios/project.yml`).
- **New workflow**: `ios-maestro-e2e` in `bitrise/ios.yml`. Boots simulator (reuses
  `_ios_setup`), builds the app (need an `.app` bundle — `xcodebuild build` or reuse
  `xcode-build` convention), installs Maestro CLI at a pinned version via the same pattern as
  `maestro-test@1` already in `bitrise/e2e.yml` (pin `maestro_version`), runs
  `maestro test apps/ios/maestro --format junit`.
- **Reporting**: `maestro-test@1` Step (native, matches `maestro_android`'s exact pattern) —
  automatic attachment of `startRecording` video + `takeScreenshot` via the Step itself, same
  as Android. **No new scripts needed, this reuses the exact proven mechanism.**
- **Risk to existing setup**: none — new workflow, new folder, doesn't touch `e2e/maestro/` or
  `apps/android`.

### 2. Maestro on React Native (both platforms)
- **New files**: `apps/react-native/maestro/config.yaml`, `counter_basic.yaml`,
  `counter_reset.yaml` (same journeys as `apps/react-native/e2e/counter.e2e.js`'s two Detox
  tests — "shows the initial count", "increments and resets"), plus
  `apps/react-native/maestro/README.md` mapping each Detox test ↔ its Maestro equivalent.
- **New workflows**: `react-native-maestro-android` and `react-native-maestro-ios` in
  `bitrise/react-native.yml`. Android variant builds a debug APK (`react-native` CLI or
  Gradle directly, same as `apps/android`'s own pattern) and runs on an AVD; iOS variant builds
  via `xcodebuild`/CocoaPods (reusing `cocoapods-install@2`, already used by `rn_detox_ios`) and
  runs on a simulator.
- **Reporting**: `maestro-test@1`, same as scenario 1 — fully automatic.
- **Risk**: `apps/react-native/e2e/counter.e2e.js` (Detox) is untouched; new `maestro/` folder
  is additive only.

### 3a. XCUITest sharded
- **New pipeline** `ios-xcuitest-sharded` in `bitrise/ios.yml`:
  - Stage 1 (`ios-xcuitest-build`): `xcode-build-for-test@3.6.0` on `CounterApp-UI` scheme →
    produces the `.xctestrun`/test bundle → shared via **pipeline intermediate files**
    (`BITRISE_TEST_BUNDLE_PATH`).
  - Stage 2 (`xcode-test-shard-calculation@0.2.1`): reads the test bundle, computes N shards
    (N via env var, default 2 given this app only has 2 UI tests — more shards than tests is
    pointless, flagging this as a real constraint, not an oversight).
  - Stage 3 (N parallel workflows `ios-xcuitest-shard-1`, `ios-xcuitest-shard-2`, ...): each
    pulls the intermediate files, runs `xcode-test-without-building@1.0.1` with its shard's
    `Test Selection` input, each with its own `deploy-to-bitrise-io` so every shard's results
    land in the Tests tab as separate entries.
- **Risk**: none to existing — entirely new pipeline, doesn't touch `ios_ui_tests`.
- **Caveat**: with only 2 test methods in `CounterUITests`, sharding into more than 2 pieces
  means some shards run 0 tests — still valid, demonstrates the mechanism, just flagging the
  reality for this specific sample app.

### 3b. Maestro sharded (Android)
- **New pipeline** `android-maestro-sharded` in `bitrise/e2e.yml`:
  - Stage 1 (`android-maestro-shard-build`): `./gradlew :app:assembleDebug` → APK shared via
    pipeline intermediate files.
  - Stage 2..N+1: N parallel workflows (`SHARD_COUNT` env var, default 3 per the task spec,
    though this repo currently only has 2 Maestro flow files — shard 3 would run 0 flows with
    the naive "one flow per shard, round-robin" assignment below; flagging the same
    small-sample-size reality as 3a).
  - **Shard assignment**: round-robin by alphabetical flow filename index modulo shard count
    (`ls e2e/maestro/*.yaml | awk 'NR % SHARD_COUNT == <shard_index>'`), documented inline in
    the workflow and in this doc's final version.
- **Reporting**: each shard workflow runs `maestro-test@1` against only its assigned flow
  files, with a distinct `test_name` (e.g. `Maestro shard 1 (Android)`) so each shows up as a
  separate Tests tab entry.
- **Risk**: none — new pipeline/workflows, `maestro_android` (the existing unsharded workflow)
  untouched.

### 4. Android instrumentation on Virtual Device Testing (Firebase Test Lab)
- **New workflow** `android-espresso-vdt` in `bitrise/android.yml`: `android-build-for-ui-testing@1.0.0`
  (reuses the exact Step `android_ui_tests` used *before* being switched to the script route —
  this scenario explicitly asks for VDT, so the native pre-switch pattern is the right fit
  here) → `virtual-device-testing-for-android@1.3.6` with `test_type: instrumentation`,
  `download_test_results: true`, device list from a `VDT_DEVICE_LIST` env var (default to 1-2
  cheap devices, e.g. `NexusLowRes,24,en,portrait`).
- **🚧 BLOCKER, needs your input**: Virtual Device Testing requires Firebase Test Lab access —
  specifically a **Google Cloud / Firebase service account JSON key added as a Bitrise Generic
  File Storage item or secret**, referenced as the Step's `service_account_json_key_path`
  input, plus a Firebase project GCP billing account (VDT is metered). I can write the
  workflow fully, but it **cannot run until you add that credential and tell me the
  project/env var name to reference**. Flagging now rather than after writing it, since this
  matches the exact shape of the BrowserStack-secrets blocker from earlier in this repo's
  history.
- **Risk**: none to existing — `android_ui_tests` (local emulator) is untouched.

### 5. Appium against local emulator and simulator
- **Shared config switch**: `e2e/appium/conftest.py`'s `driver` fixture gets an additive branch
  on a new `APPIUM_TARGET` env var (`local` | `browserstack`, default `browserstack` to match
  current behavior exactly — **existing BrowserStack path is untouched**, just wrapped in an
  `if APPIUM_TARGET == "browserstack":` so the existing code path is byte-for-byte preserved).
  Local branch points `webdriver.Remote` at `http://localhost:4723` instead of BrowserStack's
  hub, and skips the BrowserStack-specific `bstack:options`/session-status calls.
- **New workflow** `android-appium-local` in `bitrise/e2e.yml`: AVD Manager (same pattern as
  `maestro_android`) → install + start an Appium server (`npm install -g appium@2.x
  appium-uiautomator2-driver@<pinned>`, run in background) → `APPIUM_TARGET=local pytest
  e2e/appium/tests`. **This introduces Node/npm into what's currently a pure-Python Appium
  setup** — Appium's server itself is Node-based regardless of which language the client/tests
  are written in, so this is unavoidable, not a design choice I'm second-guessing.
- **New workflow** `ios-appium-local` in `bitrise/ios.yml`: boots a simulator (`_ios_setup`'s
  pattern) → same local Appium server → **new** pytest file
  `e2e/appium/tests/test_counter_ios.py` (XCUITest driver, `appium.options.ios.XCUITestOptions`,
  targeting `apps/ios`'s built `.app`) covering 2-3 journeys (start at zero, increment+reset,
  decrement floor at zero) — existing `test_counter.py` (Android) untouched.
- **Video**: `start_recording_screen()`/`stop_recording_screen()` already exist in
  `conftest.py` for BrowserStack; same calls work against a local Appium server (it's a
  standard W3C/Appium extension command, not BrowserStack-specific) — reused as-is in the new
  branch, no duplication.
- **Risk**: the `conftest.py` edit is the one "shared file must change" case here. It's a pure
  *addition* (new `if` branch, new env var default preserving old behavior) — I'll show the
  diff before/after to confirm it doesn't alter the BrowserStack path.

### 6. Classic XCTest next to Swift Testing
- **New file**: `apps/ios/CounterAppTests/CounterXCTests.swift` — same assertions as
  `CounterTests.swift` (starts at zero, increment, decrement floor, label format) rewritten in
  XCTest (`XCTAssertEqual` instead of `#expect`), **same file, same target** (`CounterAppTests`)
  since XCTest and Swift Testing can coexist in one test bundle/scheme — no new Xcode target
  needed, which is the smallest possible additive change. `CounterTests.swift` untouched.
- **No new workflow needed**: `ios_unit_tests` already runs the whole `CounterAppTests` target
  via `xcode-test@6`, so the new XCTest file is picked up automatically. The Tests tab already
  separates by test class, so `CounterXCTests` shows up distinctly from `CounterTests` (Swift
  Testing) and `CounterSnapshotTests` — confirming "both appear separately" doesn't need any
  config since xcresult always reports per-class already.
- **Risk**: none — additive file in an existing, already-tested target/scheme.

### 7. fastlane `scan` variant
- **New files**: `apps/ios/fastlane/Fastfile` (new, doesn't exist yet — confirmed via search),
  `apps/ios/fastlane/Appfile`. One lane, e.g. `scan_xcuitest`, calling `scan` with
  `scheme: "CounterApp-UI"`, `output_types: "junit"`, `output_directory: "test-results"`.
- **New workflow** `ios-fastlane-scan` in `bitrise/ios.yml`: `_ios_setup` → install fastlane
  (`gem install fastlane --no-document`, pinned version) → boot+record simulator (reuse
  `scripts/recording/start-ios-sim.sh`, same as `ios_ui_tests_manual`) → `fastlane
  scan_xcuitest` → stop recording, convert, attach via `attach_media_to_junit.py` (reusing the
  exact mechanism `ios_ui_tests_manual` already proved works) → `custom-test-results-export@1`
  → `deploy-to-bitrise-io`.
- **Risk**: none — brand new `fastlane/` directory, new workflow.

---

## Summary of things that need your input before/during implementation

1. **VDT (scenario 4) is blocked on a Firebase service account credential** — same shape of
   blocker as the still-unresolved BrowserStack secrets. I'll write the workflow regardless (so
   it's ready the moment the credential exists) but can't verify it runs.
2. **Scenario 5 touches `e2e/appium/conftest.py`** (shared file) — purely additive (new env var
   branch, old behavior preserved under the existing default), but flagging since the task
   rules single out shared-file edits for extra care.
3. **Shard counts for 3a/3b are constrained by how few tests this sample app has** — I'll
   implement the mechanism faithfully (configurable via env var) but some shards will
   legitimately run zero tests at the defaults given in the task. Not a bug, just the reality
   of a demo app with 2 UI tests / 2 Maestro flows.
4. Given the sheer size of this task (7 scenarios, several multi-stage pipelines), I'd like to
   confirm pacing before starting: build and push one scenario at a time, same cadence as the
   recording/reporting work earlier this session (commit + push + live-verify after each,
   status update after each, no per-commit confirmation needed)?

## Build order (proposed)
Easiest/lowest-risk first, same philosophy as before: **6 (XCTest) → 1 (iOS Maestro) → 2 (RN
Maestro) → 7 (fastlane scan) → 5 (Appium local) → 4 (VDT, writable but unverifiable) → 3a/3b
(sharding, most complex, most Bitrise-specific machinery)**.
