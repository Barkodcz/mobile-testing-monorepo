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
- **~~BLOCKER~~ Correction (originally written, since corrected)**: this plan originally assumed
  VDT needed a Firebase/GCP service account credential as a Bitrise secret, same shape as the
  BrowserStack blocker. That assumption was wrong. Checked `virtual-device-testing-for-android`'s
  actual inputs via `step_inputs`: its `api_token` input already defaults to
  `$ADDON_VDTESTING_API_TOKEN`, which Bitrise auto-provisions the moment the **Virtual Device
  Testing add-on** is enabled on this app (Bitrise dashboard → app → Add-ons). No Firebase/GCP
  project, service account JSON, or separate billing setup is needed on your end — just enable
  the add-on. See the final-status table below.
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

1. ~~VDT (scenario 4) is blocked on a Firebase service account credential~~ **Corrected**: just
   enable the Virtual Device Testing add-on in the Bitrise dashboard (Add-ons tab) — no separate
   credential needed. See the secrets table below.
2. **Scenario 5 touches `e2e/appium/conftest.py`** (shared file) — purely additive (new env var
   branch, old behavior preserved under the existing default). Diff reviewed, BrowserStack path
   (`APPIUM_TARGET` unset or `browserstack`) is byte-for-byte unchanged.
3. **Shard counts for 3a/3b are constrained by how few tests this sample app has** — implemented
   faithfully (configurable via env var), and as flagged up front, some shards legitimately run
   zero tests/flows at the task's own default counts. See the shard-assignment notes below for
   the exact, confirmed-live mapping.
4. Pacing confirmed: build and push one scenario at a time, commit + push + live-verify after
   each, no per-commit confirmation.

## Build order (as actually built)
**6 (XCTest) → 1 (iOS Maestro) → 2 (RN Maestro) → 7 (fastlane scan) → 5 (Appium local) → 4 (VDT,
written, add-on not yet enabled) → 3b (Maestro sharded) → 3a (XCUITest sharded)**.

## Real bugs found and fixed during live verification

None of these were anticipated in the discovery phase above; all confirmed via real Bitrise
builds, not guessed:

1. **UNRESOLVED, genuine CI-environment blocker**: `ios-maestro-e2e`, `ios-maestro-e2e-rn`, and
   `ios-appium-local` all fail installing/launching the built `.app` directly via `simctl`
   (which is what Maestro and Appium's XCUITest driver do), while `xcode-test`/`xcodebuild test`
   (`ios_ui_tests`, `ios_ui_tests_manual`) — which launch through Xcode's own test harness
   instead — work fine with the exact same app. Maestro reports `FBSOpenApplicationServiceErrorDomain`
   / denied by `SBMainWorkspace`; Appium reports "Simulator architecture is not supported by the
   ... application". Four distinct, independently-plausible fixes were tried live and **none
   resolved it**:
   - `xcrun simctl bootstatus -b` after boot, to rule out a boot-race (boot was confirmed fully
     complete — took 40-60s — and the error still occurred).
   - `open -a Simulator` to ensure the GUI process (not just a headless-booted device) is
     running (no change).
   - Pinning `ARCHS: arm64` / excluding `x86_64` for the simulator SDK in
     `apps/ios/project.yml`, in case `xcodebuild archive` (what `xcode-build-for-simulator`
     actually runs, even for a simulator destination) produced a binary arch mismatch on
     Bitrise's arm64 Mac runners (no change — and the resulting `.xctestrun`/xcresult filenames
     still read `arm64-x86_64` regardless, suggesting this setting wasn't the lever that matters
     here, or Xcode's naming doesn't reflect it).
   - Ad-hoc codesigning the built `.app` (`codesign --force --deep --sign -`), since
     `xcode-build-for-simulator`'s own xcconfig forces `CODE_SIGNING_ALLOWED=NO` and iOS 18.x
     simulators are known to sometimes deny direct-launch of unsigned apps while tolerating them
     under a test harness (no change).
   - The fact that this hits **two unrelated app codebases** (native `CounterApp`/XcodeGen and
     the React Native app/CocoaPods) with the **identical** failure mode is a strong signal this
     is a property of the Bitrise macOS stack / Xcode 16.4 / iOS 18.x simulator combination
     itself, not of either app's build configuration. Recommended next steps for whoever picks
     this up: compare against a plain non-CI (local Apple Silicon Mac) repro; try an older/newer
     `osx-xcode-*` stack; or file it with Bitrise/mobile.dev (Maestro) support with the exact
     `FBSOpenApplicationServiceErrorDomain` text above, since it reproduces outside of anything
     in this repo's control.
   - **Left in place**: the `bootstatus -b` wait (legitimate regardless) and the ad-hoc codesign
     step (harmless, may matter on other stacks) in `ios-maestro-e2e`, `ios-maestro-e2e-rn`, and
     `ios-appium-local`. The `ARCHS`/`EXCLUDED_ARCHS` pin stays in `project.yml` too (harmless).
3. **`ios-appium-local`'s hardcoded `platform_version` default (`18.0`)** didn't match any
   simulator SDK actually installed on the stack (`18.4`/`18.5`/`18.6`/`16.4`/`17.5` at the time).
   Fixed by capturing the exact UDID of the simulator CI already booted and built into, and
   having Appium attach via `udid` instead of re-resolving by version.
4. **`xcode-test-shard-calculation`'s `product_path` input wants the `.xctestrun` file**
   (formats: xctestrun/xctestproducts), not the raw test bundle directory — fixed by pointing it
   at `BITRISE_XCTESTRUN_FILE_PATH`.
5. **Pipeline intermediate files broke the `.xctestrun`'s relative path to the built `.app`**:
   `BITRISE_XCTESTRUN_FILE_PATH` is a file *inside* `BITRISE_TEST_BUNDLE_PATH`'s own directory
   tree, and the `.xctestrun` references the `.app` via a path relative to that tree. Listing
   both as separate pipeline intermediate files makes `pull-intermediate-files` extract them
   into two different, isolated directories downstream, breaking that reference. Fixed by
   passing only the bundle directory through the pipeline and re-locating the `.xctestrun` file
   inside it with `find` at each downstream stage.
6. **A classic `set -e -o pipefail` + empty-glob bug** in the Maestro sharding script: `ls
   nonexistent-glob | wc -l` inside a `$(...)` aborts the whole script when a shard has zero
   matching flow files (because `ls` exits nonzero on no match, and `pipefail` propagates that
   even though `wc -l` itself succeeds) — before the `run_if`-controlling env var ever got set.
   Fixed by switching the count to `find`, which doesn't error on zero matches.
7. **Classic RN Metro-bundler gotcha** (scenario 2): debug builds need the Metro bundler running
   to render anything; a debug APK/simulator build showed neither the counter label nor the
   buttons. Fixed by building `Release` configuration instead (both Android Gradle and iOS
   `xcode-build-for-simulator`), which embeds the JS bundle.

## Final status per scenario

| # | Scenario | Status |
| --- | --- | --- |
| 1 | Maestro on iOS | Code complete (flows, workflow); **blocked** on the unresolved CI launch-denial issue (#1 above) |
| 2 | Maestro on React Native (Android + iOS) | Android side **done, verified passing**; iOS side **blocked** on the same unresolved issue |
| 3a | XCUITest sharded pipeline | Code complete after the product_path, intermediate-files, and shard-file-discovery fixes; re-verification in progress |
| 3b | Maestro sharded pipeline (Android) | **Done, verified passing** — shard 3 correctly skips with 0 flows at the default shard count |
| 4 | Android instrumentation on VDT | **Written, needs you to enable the add-on** — see secrets table |
| 5 | Appium local (Android + iOS) | Android side **done, verified passing**; iOS side **blocked** on the same unresolved issue |
| 6 | Classic XCTest next to Swift Testing | **Done, verified** — both classes show separately in the Tests tab |
| 7 | fastlane `scan` variant | **Done, verified passing** |

All code for every scenario is written, additive, and committed. The only unresolved item is the
iOS-simulator-direct-launch issue affecting the iOS side of scenarios 1, 2, and 5 — a CI
environment issue external to this repo's code, documented in detail above.

## Shard assignment (confirmed live)

- **3a (`ios_xcuitest_sharded`)**: `xcode-test-shard-calculation` with `shard_calculation:
  alphabetically` splits `CounterApp-UI`'s 2 test methods across `XCUITEST_SHARD_COUNT` (default
  2) shards — one test per shard at the default.
- **3b (`android_maestro_sharded`)**: manual round-robin by alphabetical flow filename,
  `ls e2e/maestro/counter_*.yaml | sort | awk 'NR % N == <index>'`. At the default
  `MAESTRO_SHARD_COUNT=3` with the repo's 2 flow files: shard 1 runs `counter_basic.yaml` (1 mod
  3 = 1), shard 2 runs `counter_reset.yaml` (2 mod 3 = 2), shard 3 runs nothing (no index mod 3
  == 0) — its `maestro-test` step is skipped via `run_if` rather than failing on "no flows
  found".

## Secrets / accounts you need to add in Bitrise

- **Virtual Device Testing add-on** (Bitrise dashboard → this app → Add-ons → enable Virtual
  Device Testing) — required for `android-espresso-vdt` (scenario 4) to run. No separate
  Firebase/GCP credential: once enabled, `virtual-device-testing-for-android`'s `api_token`
  input resolves from the auto-provisioned `$ADDON_VDTESTING_API_TOKEN`.
- `BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY` — unchanged, pre-existing requirement for
  `appium_browserstack`, not part of this round of scenarios.
