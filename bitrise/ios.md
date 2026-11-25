# `bitrise/ios.yml` — native iOS (CounterApp) CI reference

This document fully describes [`bitrise/ios.yml`](./ios.yml), the Bitrise
config module for the native iOS sample app under
[`apps/ios`](../apps/ios). It is included into the root
[`bitrise.yml`](../bitrise.yml) via `include:`.

For generic Bitrise concepts (workflows vs. pipelines, pipeline intermediate
files, the Tests-tab attachment-naming convention, triggers, `deploy-to-bitrise-io`,
caching, step-version pinning) see
[`../docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) — this document
only covers what is specific to the iOS module.

## 1. Overview

The app under test is **CounterApp**, a trivial SwiftUI counter (increment /
decrement / reset, bundle id `io.bitrise.sample.counter`) generated from
[`apps/ios/project.yml`](../apps/ios/project.yml) by XcodeGen. It exists
purely as a vehicle to demonstrate, side by side, every practical way of
running and reporting iOS tests on Bitrise:

- **Unit + snapshot tests** (`ios_unit_tests`): Swift Testing (`CounterXCTests`/
  `CounterTests`) plus `swift-snapshot-testing` (`CounterSnapshotTests`), via
  the native `xcode-test` step.
- **XCUITest UI tests**, run three different ways against the same
  `CounterApp-UI` scheme/`CounterAppUITests` target, to contrast their
  reporting/recording trade-offs:
  - `ios_ui_tests` — native `xcode-test` step ("Approach A").
  - `ios_ui_tests_manual` — raw `xcodebuild test` + `xcpretty` ("Approach B").
  - `ios-fastlane-scan` — fastlane's `scan` lane.
- **Maestro E2E** (`ios-maestro-e2e`, wrapped as the `maestro_ios` pipeline):
  the same journeys as the Android Maestro flows, ported to iOS. See also
  [`bitrise/e2e.md`](e2e.md) for the cross-platform (`maestro_cross_platform`)
  and parallel-copies (`maestro_android_parallel`) pipelines that build on
  this workflow.
- **Appium** (`ios-appium-local`): Python/pytest driving a local Appium
  server + XCUITest driver against a local simulator.
- **Sharded XCUITest** (`ios_xcuitest_sharded` pipeline): build the UI test
  bundle once, split it into N shards, run each shard in its own workflow
  with its own Tests-tab entry.

A reader opening a build of this module on bitrise.io should expect: a Tests
tab entry per workflow (sometimes more than one, as in the sharded
pipeline), an Artifacts tab with `.xcresult`/`.zip`/recording files, and —
depending on the workflow — a video attached directly to a test case versus
only a loose file in Artifacts (see §5).

## 2. Prerequisites

### Stack / machine

Every workflow in this file pins the same macOS stack and machine type in
its own `meta.bitrise.io` block (there is no iOS-wide default in the root
`bitrise.yml`, whose top-level `meta` is a Linux stack for the
non-iOS/Android modules):

| | value |
|---|---|
| `stack` | `osx-xcode-27.2.x` (Xcode 27.2.x image — check the exact bundled Xcode/Simulator runtime versions at https://stacks.bitrise.io) |
| `machine_type_id` | `g2.mac.medium` |

`ios-xcuitest-shard-calc` does **not** declare a `before_run` (it doesn't
need `_ios_setup`/a git checkout — it only consumes intermediate files from
the previous stage) but it does still declare the same `meta` block, since
pipeline stages don't inherit `meta` from each other.

### Tools

- **XcodeGen** — handled by the `xcodegen@0.0.5` Step in `_ios_setup` (its
  `deps.brew: xcodegen` installs the CLI itself; the Step then runs
  `xcodegen generate` using the `spec_path`/`project_path` inputs) to turn
  [`apps/ios/project.yml`](../apps/ios/project.yml) into `CounterApp.xcodeproj`.
  This replaced a two-line `brew install xcodegen && xcodegen generate`
  script — functionally identical, but note `xcodegen@0.0.5` is
  **community-maintained** (last published 2019, single-commit source); see
  §9.
- **CocoaPods** — not used. The only external dependency is a Swift Package
  (`SnapshotTesting`, resolved by Xcode itself during the build/test step).
- **xcpretty** — installed ad hoc in `ios_ui_tests_manual` only
  (`gem install xcpretty`), to convert `xcodebuild test`'s raw output into
  JUnit XML.
- **fastlane** — installed by the `fastlane@3.5.3` Step's own
  `update_fastlane` input (default `true`) in `ios-fastlane-scan`; no
  separate `gem install` step needed.
- **ffmpeg** — expected to be preinstalled on the stack image; used by
  [`scripts/recording/stop-ios-sim.sh`](../scripts/recording/stop-ios-sim.sh)
  to convert `.mov` → `.mp4`. Not installed by any step in this file — if
  it's missing, the script just warns and leaves the unattachable `.mov`
  behind.
- **Maestro CLI** — installed by the `maestro-test` step itself, version
  pinned via its `maestro_version: 2.12.1` input.
- **Appium / Node** — installed ad hoc in `ios-appium-local`
  (`npm install -g appium@2.11.0`, `appium driver install xcuitest@7.29.0`).
  Node itself is assumed preinstalled on the stack.
- **Python/pytest** — a fresh venv is created per-run in `ios-appium-local`
  from [`e2e/appium/requirements.txt`](../e2e/appium/requirements.txt).

### Secrets / env vars

This module needs **no secrets** — everything targets a local simulator with
ad hoc/automatic code signing, never a real device or App Store Connect.
Env vars used (all plain, non-secret):

| Var | Set where | Purpose |
|---|---|---|
| `RECORD_VIDEO` | app-level `envs` in root [`bitrise.yml`](../bitrise.yml), default `all` | Gates whether recording scripts/attachment script keep a video for a passing run (`all`/`failures`/`off`). |
| `XCUITEST_SHARD_COUNT` | app-level `envs` in root `bitrise.yml`, default `"2"` | Number of shards `ios-xcuitest-shard-calc` divides `CounterApp-UI`'s tests into. |
| `BITRISE_APP_DIR_PATH` | exported by `envman` in `ios-maestro-e2e`/`ios-appium-local`'s build step | Path to the built, ad hoc-signed `.app`, consumed by `maestro-test`/Appium/`codesign`. |
| `APPIUM_IOS_UDID` | exported by `envman` in `ios-appium-local` | UDID of the booted simulator, handed to the Appium capabilities so Appium doesn't have to resolve a drifting `platform_version`. |
| `XCTESTRUN_FILE_PATH`, `ONLY_TESTING_PATH` | exported by `envman` in the sharded pipeline's calc/shard workflows | Locate the `.xctestrun` file and this shard's test-selection file after `pull-intermediate-files`. |

No step in this file references a Bitrise **Secret** (API key, certificate
password, signing identity, etc.) — flagging this explicitly per the task:
there is nothing here that implies an external credential dependency.

## 3. Triggers and pipelines

- **`ios` pipeline** (in the root `bitrise.yml`'s `pipelines:`, defined
  together with the other platforms' pipelines... actually defined in this
  file): wires `ios_unit_tests` and `ios_ui_tests` as independent
  (non-`depends_on`) workflows. Triggered on:
  - `push` to `main`, when changed files match
    `^(apps/ios/.*|bitrise/ios\.yml)$`.
  - any `pull_request` (drafts excluded via `draft_enabled: false`) with the
    same changed-files filter.

  `ios_ui_tests_manual` is **deliberately excluded** from this pipeline —
  the YAML's own comment explains it exists only to demonstrate Approach B,
  not to double-run the UI tests on every push.

- **`maestro_ios` pipeline**: wraps the single `ios-maestro-e2e` workflow,
  with no `triggers:` block — manual-start only, same reasoning as the
  workflow itself. Exists so Maestro-on-iOS can be started the same way
  (Start build → Pipeline) as the other Maestro pipelines documented in
  [`bitrise/e2e.md`](e2e.md).

- **Manual-trigger-only workflows** (no trigger block at all, not listed in
  any pipeline of its own — started from the Bitrise UI "Start build"
  dialog, or via `maestro_ios`/`maestro_cross_platform` for
  `ios-maestro-e2e`): `ios-maestro-e2e`,
  `ios-fastlane-scan`, `ios-appium-local`, `ios_ui_tests_manual`. Per their
  own summaries, the reasons are: avoiding extra simulator minutes on every
  push (`ios-maestro-e2e`), existing purely as an alternative-approach demo
  that would otherwise duplicate `ios_ui_tests`/`ios_ui_tests_manual`
  (`ios-fastlane-scan`), and being a new/separate scenario not meant to run
  on every commit (`ios-appium-local`, `ios_ui_tests_manual`).

- **`ios_xcuitest_sharded` pipeline**: also has no trigger — it must be
  started as a **pipeline** from the Bitrise UI, not by running any one of
  its workflows directly (the YAML comment is explicit about this; several
  of its stages have no `before_run: [_ios_setup]` and depend entirely on
  intermediate files from the prior stage, so running them standalone would
  fail). Wiring:

  ```
  ios-xcuitest-shard-build  (stage 1: build-for-testing once)
          |  pipeline_intermediate_files: BITRISE_TEST_BUNDLE_PATH
          v
  ios-xcuitest-shard-calc   (stage 2: pull bundle, compute N shards)
          |  pipeline_intermediate_files: BITRISE_TEST_SHARDS_PATH, BITRISE_TEST_BUNDLE_PATH
          +------------------+
          v                  v
  ios-xcuitest-shard-1   ios-xcuitest-shard-2   (stage 3: each depends_on shard-calc,
                                                   run in parallel, each its own Tests tab entry)
  ```

  The intermediate-files mechanism itself (archive/extract between stages)
  is explained generically in `../docs/BITRISE_CONCEPTS.md`; the
  iOS-specific wrinkle — **why only `BITRISE_TEST_BUNDLE_PATH` is listed**
  in stage 1's `deploy-to-bitrise-io`, and not `BITRISE_XCTESTRUN_FILE_PATH`
  too — is covered in §9 (it's a real bug this file hit and fixed).

## 4. Workflow-by-workflow walkthrough

### `_ios_setup` (shared `before_run` helper, not a standalone workflow)

| Step | What it does | Inputs | Notes |
|---|---|---|---|
| `git-clone@8.5.2` | "Git Clone Repository" — checks out the repo (PR-merge/branch-head/tag/commit depending on trigger) and exports git metadata. | defaults | |
| `xcodegen@0.0.5` — "Generate Xcode project" | Installs XcodeGen (via the Step's own `deps.brew: xcodegen`) and runs `xcodegen generate` to turn `project.yml` into `CounterApp.xcodeproj`. Replaced a two-line `brew install xcodegen && xcodegen generate` script. | `spec_path: $BITRISE_SOURCE_DIR/apps/ios/project.yml`; `project_path: $BITRISE_SOURCE_DIR/apps/ios` | Community-maintained Step (not Bitrise-official), last published 2019 — functionally equivalent to the script it replaced, but worth knowing it's a lower-maintenance dependency than the official Steps elsewhere in this file. Confirmed working live across every iOS workflow (they all go through `_ios_setup`). |

Every other workflow in this file (except the shard-calc/shard-1/shard-2
stages) starts with `before_run: [_ios_setup]`.

### `ios_unit_tests`

Summary: Swift Testing unit tests + swift-snapshot-testing.

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `xcode-test@6.6.1` | "Xcode Test for iOS" — runs the scheme's tests, exports results (`.xcresult`) for the following `deploy-to-bitrise-io` step to pick up automatically. | `project_path: apps/ios/CounterApp.xcodeproj`; `scheme: CounterApp-Unit`; `destination: platform=iOS Simulator,name=Bitrise iOS default,OS=latest` | Inline comment: "exports to the Tests tab automatically" — no manual JUnit wrangling needed because `xcode-test` + `deploy-to-bitrise-io` is the native/supported pairing. |
| 2 | `script@1.2.1` — "Keep snapshot reference images" | Zips the `__Snapshots__` folder (the swift-snapshot-testing reference images under [`apps/ios/CounterAppTests/__Snapshots__`](../apps/ios/CounterAppTests/__Snapshots__)) into the deploy dir, if present. | `is_always_run: true`; `working_dir: .../CounterAppTests`; script zips `__Snapshots__` to `$BITRISE_DEPLOY_DIR/ios-snapshots.zip` if the dir exists | Comment: "First run records missing references here; download and commit them" — i.e. this is the recovery path when a snapshot test fails because there's no reference yet: download the zip from Artifacts, extract into the repo, commit. |
| 3 | `deploy-to-bitrise-io@2.26.2` | Uploads everything in `$BITRISE_DEPLOY_DIR` to Artifacts and converts/uploads the `.xcresult` test results to the Tests tab. | `is_always_run: true` | |

No video recording in this workflow — it's unit/snapshot tests, not UI
tests, so there's nothing on-screen worth capturing.

### `ios_ui_tests` ("Approach A": native Step + externally-recorded video)

Summary (verbatim intent, from the YAML): keep the native `xcode-test` step,
pre-boot the simulator so `simctl` can record it; screenshots XCTest itself
captures on failure still auto-attach via `.xcresult`, but the *externally*
recorded video can only be deployed as a plain Artifact, not attached to a
Tests-tab test case (see §5 for why).

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `script@1.2.1` — "Boot simulator and start recording" | Boots the named simulator (ignoring the error if already booted), then starts `simctl io … recordVideo` in the background via [`scripts/recording/start-ios-sim.sh`](../scripts/recording/start-ios-sim.sh). | script: `xcrun simctl boot "Bitrise iOS default" 2>/dev/null \|\| true`; then `start-ios-sim.sh booted $BITRISE_SOURCE_DIR/recordings/ios-ui-tests.mov` | `"Bitrise iOS default"` is a Bitrise-maintained simulator alias, not a hardcoded device model name — see §9 for why that matters. `start-ios-sim.sh` is a no-op if `$RECORD_VIDEO=off`; it sleeps 1s after launching `recordVideo` to let it attach before the UI is driven. |
| 2 | `xcode-test@6.6.1` | Runs `CounterApp-UI` (the `CounterAppUITests` target) against the already-booted simulator. | `project_path`, `scheme: CounterApp-UI`, same `destination` as above | |
| 3 | `script@1.2.1` — "Stop recording and keep it as a build artifact" | Stops the recording (`stop-ios-sim.sh`, which converts `.mov`→`.mp4`), then copies the `.mp4` into `$BITRISE_DEPLOY_DIR` if it's non-empty. | `is_always_run: true` | This copy is a **plain Artifacts-tab file**, `ios-ui-tests-recording.mp4` — it is never wired into any JUnit/`.xcresult` test case, so it will never show up attached to a specific test in the Tests tab (see §5). |
| 4 | `deploy-to-bitrise-io@2.26.2` | Uploads Artifacts + `.xcresult` test results. | `is_always_run: true` | |

### `ios-maestro-e2e` (manual-trigger-only)

Summary: ports of the Android Maestro flows to iOS, same journeys, new
folder [`apps/ios/maestro`](../apps/ios/maestro).

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `script@1.2.1` — "Build for simulator (raw xcodebuild build, not archive)" | Builds the `CounterApp-UI` scheme directly for the simulator with `xcodebuild build` (not the `xcode-build-for-simulator` Step), with code signing off, then `envman`-exports the resulting `.app` path. | script: `xcodebuild build -project apps/ios/CounterApp.xcodeproj -scheme CounterApp-UI -sdk iphonesimulator -destination "platform=iOS Simulator,name=Bitrise iOS default,OS=latest" -derivedDataPath "$BITRISE_SOURCE_DIR/ios-sim-build" CODE_SIGNING_ALLOWED=NO`; then `find … -name 'CounterApp.app'` and `envman add --key BITRISE_APP_DIR_PATH` | **Pitfall, documented inline and confirmed live twice**: the `xcode-build-for-simulator` Step always runs `xcodebuild archive` under the hood, and `archive` is fundamentally a device-distribution action — even with an explicit `-sdk iphonesimulator`, it still tagged the output for the iOS *device* platform, so `simctl` refused to install it. Plain `xcodebuild build` doesn't have this problem (it's what `xcode-test`/raw `xcodebuild test` already use successfully), so this step builds directly instead of using the official Step. |
| 2 | `script@1.2.1` — "Ad-hoc codesign the built app" | `codesign --force --deep --sign - "$BITRISE_APP_DIR_PATH"` | | **Pitfall, confirmed live across 3 attempts, builds #98/#108/#119/#127**: an unsigned app (from `CODE_SIGNING_ALLOWED=NO`) is fine when XCTest's own harness launches it (as in `xcode-test`/`xcodebuild test`), but a bare `simctl launch` — which is what Maestro/Appium do — gets denied by SpringBoard on iOS 18.x simulators ("SBMainWorkspace"). Ad hoc signing (`--sign -`) fixes it without needing any real identity/provisioning. |
| 3 | `bundle::ios_simulator_boot` | Step bundle (root [`bitrise.yml`](../bitrise.yml), see [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §7) — boots the simulator, then **blocks until it's fully ready** with `simctl bootstatus`. | bundle steps: `xcrun simctl boot … \|\| true`; `xcrun simctl bootstatus "Bitrise iOS default" -b` | `bootstatus -b` is the fix for races where Maestro/Appium try to interact with a simulator that `simctl boot` returned from but hasn't actually finished booting yet — see §9. Previously an inline `script@1.2.1` here; factored into the shared bundle since the identical two lines appear in several workflows across this repo. |
| 4 | `maestro-test@1.2.0` | "Maestro Test" — installs the Maestro CLI at the pinned version, installs the app, runs `maestro test` against every flow under `flow_path`, exports results (with each flow's screenshots/`startRecording` videos/logs attached to its own test case) to the Tests tab, and zips the Maestro output folder as an artifact. | `app_path: $BITRISE_APP_DIR_PATH`; `flow_path: $BITRISE_SOURCE_DIR/apps/ios/maestro`; `test_name: Maestro E2E (iOS)`; `maestro_version: 2.12.1`; `num_flaky_test_attempts: 1` | Per StepLib docs, the Step requires exactly one device of the target platform already running — that's why the prior "boot simulator" step exists. `num_flaky_test_attempts: 1` means a flow that fails once but passes on retry is reported as flaky rather than failing the build. |
| 5 | `deploy-to-bitrise-io@2.26.2` | Uploads Artifacts + the Maestro test results. | `is_always_run: true` | |

### `ios-fastlane-scan` (manual-trigger-only)

Summary: runs the same `CounterApp-UI` scheme via fastlane's `scan`, a third
way to run the same suite alongside `ios_ui_tests`/`ios_ui_tests_manual`.
`scan` writes real JUnit XML directly, so this gets a true Tests-tab video
attachment (same mechanism as `ios_ui_tests_manual`).

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `script@1.2.1` — "Boot simulator and start recording" | Boots the simulator, starts recording. | script: `xcrun simctl boot …`; `start-ios-sim.sh booted $BITRISE_SOURCE_DIR/recordings/ios-fastlane-scan.mov` | Previously this step also ran `gem install fastlane -v '~> 2.223' --no-document` — that's now handled by the `fastlane@3.5.3` Step below (its `update_fastlane` input defaults to `true`), so this step only boots the simulator and starts recording. |
| 2 | `fastlane@3.5.3` | Official "fastlane" Step. Installs/updates the fastlane gem, then runs the `scan_xcuitest` lane from [`apps/ios/fastlane/Fastfile`](../apps/ios/fastlane/Fastfile). Replaced a `gem install fastlane` + `fastlane scan_xcuitest` script pair. | `lane: scan_xcuitest`; `work_dir: $BITRISE_SOURCE_DIR/apps/ios` | The lane itself (see Fastfile) calls `scan(project: "CounterApp.xcodeproj", scheme: "CounterApp-UI", devices: ["Bitrise iOS default"], output_directory: "test-results", output_types: "junit", output_files: "xcuitest.xml", clean: false, skip_slack: true, skip_build: false)` — note `devices` takes the same `"Bitrise iOS default"` alias as a device *name*, which `scan`/`fastlane` resolves against the already-booted simulator. The Step's `update_fastlane` input (default `true`) replaces the manual `gem install` the previous script-based version needed; fastlane's own `scan` action creates `output_directory` itself, so the old script's `mkdir -p test-results` line was also unnecessary and was dropped. Confirmed working live (build #188/#206 and others). |
| 3 | `script@1.2.1` — "Stop recording and attach it to the Tests tab" | Stops/converts the recording, then (if non-empty) runs [`attach_media_to_junit.py add-recording-testcase`](../scripts/reporting/attach_media_to_junit.py) to inject a synthetic passing test case into `xcuitest.xml` and copy the `.mp4` using the Bitrise attachment-naming convention. | `working_dir: .../apps/ios`; `--classname CounterAppUITests.CounterUITests`; `--media …ios-fastlane-scan.mp4`; `--dest-dir test-results` | `--name` isn't passed, so the script's default `zz_session_recording` is used as the synthetic test-case name (the `zz_` prefix sorts it after the real test cases in most UIs). The script itself respects `$RECORD_VIDEO` (off/failures/all) and never fails the build on any attachment error. |
| 4 | `custom-test-results-export@2.0.0` | "Export test results to Test Reports" — packages `test-results/xcuitest.xml` (and its sibling attachment files) for the next `deploy-to-bitrise-io` step to pick up, since `scan`'s JUnit output isn't auto-detected the way `xcode-test`'s `.xcresult` is. | `test_name: XCUITest UI tests (fastlane scan)`; `base_path: $BITRISE_SOURCE_DIR/apps/ios/test-results`; `search_pattern: */xcuitest.xml` | |
| 5 | `deploy-to-bitrise-io@2.26.2` | Uploads Artifacts + the exported test results. | `is_always_run: true` | |

### `ios-appium-local` (manual-trigger-only)

Summary: Appium (XCUITest driver) against a local simulator and a local
Appium server, covering 2–3 journeys via
[`e2e/appium/tests/test_counter_ios.py`](../e2e/appium/tests/test_counter_ios.py).

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `bundle::ios_simulator_boot` | Boots + waits for the simulator — same Step bundle as `ios-maestro-e2e` step 3 (see [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §7). | bundle steps: `xcrun simctl boot … \|\| true`; `xcrun simctl bootstatus … -b` | Split out of what used to be one combined "Build for simulator and start local Appium server" script, so the boot-only part is shared via the bundle instead of duplicated. |
| 2 | `script@1.2.1` — "Start local Appium server" | Resolves the simulator's exact UDID via `simctl list devices booted -j` piped into a small Python snippet, exports it, installs Appium 2.11.0 + the XCUITest driver 7.29.0, starts the Appium server in the background (`nohup … &`), polls its `/status` endpoint up to 30s. | key exports: `envman add --key APPIUM_IOS_UDID …` | **Pitfall, confirmed live on build #102**: the build step below uses `OS=latest`, which drifts across stack updates and previously produced `"'18.0' does not exist in the list of simctl SDKs"` when Appium was instead given a hardcoded `platform_version`. Resolving and handing Appium the simulator's exact UDID sidesteps the drift entirely. Appium is started on `--base-path /wd/hub` (legacy JSON-Wire-style base path) with `--allow-insecure chromedriver_autodownload` (irrelevant for iOS but harmless/standard boilerplate from the shared Appium setup pattern). |
| 3 | `script@1.2.1` — "Build for simulator (raw xcodebuild build, not archive)" | Same `xcodebuild build … CODE_SIGNING_ALLOWED=NO` pattern as `ios-maestro-e2e` step 1, for the same `xcode-build-for-simulator`/`archive` platform-tagging reason (comment cross-references `ios-maestro-e2e`). | identical command | |
| 4 | `script@1.2.1` — "Ad-hoc codesign the built app" | `codesign --force --deep --sign - "$BITRISE_APP_DIR_PATH"` | | **Pitfall, confirmed live build #129**: Appium's direct `simctl`-level launch of the unsigned app was denied by SpringBoard, surfacing as the misleading error `"Simulator architecture is not supported"` — actually the same ad hoc-signing issue as `ios-maestro-e2e`. |
| 5 | `script@1.2.1` — "Run Appium tests (local iOS)" | Sets env vars for the test file, creates a Python venv, installs `requirements.txt`, runs pytest against `tests/test_counter_ios.py` with a JUnit output. | `working_dir: $BITRISE_SOURCE_DIR/e2e/appium`; exports `APPIUM_SERVER_URL=http://localhost:4723/wd/hub`, `APPIUM_IOS_APP_PATH="$BITRISE_APP_DIR_PATH"`, `APPIUM_IOS_DEVICE="Bitrise iOS default"`; `pytest tests/test_counter_ios.py --junitxml=test-results/appium-ios-local.xml` | `APPIUM_IOS_UDID` is already in the env from step 2's `envman add` (comment notes this explicitly — no re-export needed). |
| 6 | `script@1.2.1` — "Stop local Appium server" | `kill "$(cat /tmp/appium-server.pid)" 2>/dev/null \|\| true` | `is_always_run: true` | Cleans up the background server regardless of test outcome. |
| 7 | `custom-test-results-export@2.0.0` | Exports `appium-ios-local.xml` for the Tests tab. | `test_name: Appium on local iOS Simulator`; `base_path: $BITRISE_SOURCE_DIR/e2e/appium/test-results`; `search_pattern: */appium-ios-local.xml` | `is_always_run: true` |
| 8 | `deploy-to-bitrise-io@2.26.2` | Uploads Artifacts + exported results. | `is_always_run: true` | |

No separate video-recording step here — video capture for Appium comes from
the test code itself (base64 video capture via the driver), not a Bitrise
step; see §5.

### `ios_ui_tests_manual` ("Approach B", manual-trigger-only)

Summary: same `CounterApp-UI` suite as `ios_ui_tests`, but driven by a
manual `xcodebuild test` instead of the native Step, trading away
`.xcresult` auto-attachment convenience for full control of the simulator
lifecycle and a real JUnit XML to attach the recording to (a true Tests-tab
video attachment).

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `script@1.2.1` — "Boot simulator and start recording" | Boots the simulator, installs `xcpretty` if missing, starts recording. | script: `xcrun simctl boot …`; `gem list -i xcpretty >/dev/null 2>&1 \|\| gem install xcpretty --no-document`; `start-ios-sim.sh booted …ios-ui-tests-manual.mov` | |
| 2 | `script@1.2.1` — "Run xcodebuild test" | Runs the suite with raw `xcodebuild test`, piping through `xcpretty --report junit` to get a JUnit XML. | `working_dir: .../apps/ios`; `set -o pipefail`; `xcodebuild test -project CounterApp.xcodeproj -scheme CounterApp-UI -destination "platform=iOS Simulator,name=Bitrise iOS default,OS=latest" \| xcpretty --report junit --output test-results/xcuitest.xml` | Note: `set -o pipefail` here (not `-eo`) — if `xcodebuild test` reports test failures, the pipeline still needs to continue to `xcpretty` to produce the JUnit XML rather than aborting on the non-zero `xcodebuild` exit code; `pipefail` alone (without `-e`) lets that happen while still correctly failing the step based on the pipe's overall exit status. |
| 3 | `script@1.2.1` — "Stop recording and attach it to the Tests tab" | Same `attach_media_to_junit.py add-recording-testcase` pattern as `ios-fastlane-scan`. | `--classname CounterAppUITests.CounterUITests`; `--media …ios-ui-tests-manual.mp4`; `--dest-dir test-results` | `is_always_run: true` |
| 4 | `custom-test-results-export@2.0.0` | Exports `xcuitest.xml`. | `test_name: XCUITest UI tests (manual xcodebuild)`; `base_path: $BITRISE_SOURCE_DIR/apps/ios/test-results`; `search_pattern: */xcuitest.xml` | `is_always_run: true` |
| 5 | `deploy-to-bitrise-io@2.26.2` | Uploads Artifacts + exported results. | `is_always_run: true` | |

### `ios_xcuitest_sharded` pipeline stages

#### `ios-xcuitest-shard-build` (stage 1/3)

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `xcode-build-for-test@3.6.0` | "Xcode Build for testing for iOS" — runs `xcodebuild build-for-testing`, producing a test bundle directory (`BITRISE_TEST_BUNDLE_PATH`) and an `.xctestrun` file (`BITRISE_XCTESTRUN_FILE_PATH`, which lives *inside* that bundle directory and references the built `.app` via a path relative to it). | `project_path: apps/ios/CounterApp.xcodeproj`; `scheme: CounterApp-UI`; `destination: generic/platform=iOS Simulator`; `automatic_code_signing: "off"` | `generic/platform=iOS Simulator` (vs. a concrete simulator name) is the standard destination for a build-only step — no simulator needs to be booted yet, this stage only compiles. |
| 2 | `deploy-to-bitrise-io@2.26.2` | Shares the test bundle as a **pipeline intermediate file**. | `is_always_run: true`; `pipeline_intermediate_files: BITRISE_TEST_BUNDLE_PATH` | **Pitfall, confirmed live build #125**, documented at length inline: listing *both* `BITRISE_TEST_BUNDLE_PATH` and `BITRISE_XCTESTRUN_FILE_PATH` here makes the downstream `pull-intermediate-files` step extract them into two separate, isolated directories — breaking the `.xctestrun`'s relative reference to the `.app` ("bundle identifier... couldn't be read"). Only the bundle directory is listed; downstream stages re-find the `.xctestrun` file by searching inside it. |

#### `ios-xcuitest-shard-calc` (stage 2/3, no `before_run`)

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `pull-intermediate-files@1.3.7` | Downloads the intermediate files shared by the named upstream workflow, extracting the bundle directory locally and re-pointing `BITRISE_TEST_BUNDLE_PATH` at it. | `artifact_sources: ios-xcuitest-shard-build` | |
| 2 | `script@1.2.1` — "Locate the .xctestrun file inside the pulled test bundle" | `find`s the single `.xctestrun` file at the top level of the pulled bundle dir and exports its path. | script: `find "$BITRISE_TEST_BUNDLE_PATH" -maxdepth 1 -name '*.xctestrun' \| head -1`; `envman add --key XCTESTRUN_FILE_PATH` | Direct consequence of the stage-1 pitfall above — this re-discovery step exists specifically because the `.xctestrun` path itself isn't shared as its own intermediate file. |
| 3 | `xcode-test-shard-calculation@0.2.1` | "Xcode test shard calculation" — reads the test bundle/`.xctestrun` and divides its tests into N shards, producing `BITRISE_TEST_SHARDS_PATH` (a directory of per-shard test-selection files). | `product_path: $XCTESTRUN_FILE_PATH`; `shard_count: $XCUITEST_SHARD_COUNT` | **Pitfall, confirmed live build #112**: `product_path` must be the `.xctestrun` file itself (StepLib docs: supported formats are `xctestrun`/`xctestproducts`) — passing `BITRISE_TEST_BUNDLE_PATH` (the raw directory) fails with `"unsupported test products file extension"`. |
| 4 | `deploy-to-bitrise-io@2.26.2` | Shares both the shard files and the test bundle onward to the shard-1/shard-2 stages. | `is_always_run: true`; `pipeline_intermediate_files: BITRISE_TEST_SHARDS_PATH`, `BITRISE_TEST_BUNDLE_PATH` | The bundle has to be re-shared here too — `pipeline_intermediate_files` scoping is per-producing-workflow, so shard-1/shard-2 (which declare `artifact_sources: ios-xcuitest-shard-calc`, not `-build`) need it to come from this stage, not the original one. |

#### `ios-xcuitest-shard-1` / `ios-xcuitest-shard-2` (stage 3/3, no `before_run`)

Identical structure, differing only in which shard file they pick and their
own (automatically separate) Tests-tab entry:

| # | Step | What it does | Inputs | Notes |
|---|---|---|---|---|
| 1 | `pull-intermediate-files@1.3.7` | Pulls the bundle + shard files from stage 2. | `artifact_sources: ios-xcuitest-shard-calc` | |
| 2 | `script@1.2.1` — "Locate the .xctestrun file and this shard's test-selection file" | Re-finds the `.xctestrun`; then picks the Nth file alphabetically from `BITRISE_TEST_SHARDS_PATH` (1st for shard-1, `sed -n '1p'`; 2nd for shard-2, `sed -n '2p'`). | `envman add --key XCTESTRUN_FILE_PATH`, `--key ONLY_TESTING_PATH` | **Pitfall, documented inline**: `xcode-test-shard-calculation`'s output filenames aren't documented. A first attempt guessed a `shard_1.txt`-style naming convention — it failed live because that file didn't exist, and the *next* Step then misparsed the literal (nonexistent) guessed path as if it were a test identifier, producing the confusing error `"Tests in target 'var' can't be run"`. The fix: don't guess a naming scheme at all — sort the shard directory's files and take the Nth one positionally. |
| 3 | `bundle::ios_simulator_boot` | Step bundle (see [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §7) — boots the simulator, then waits with `simctl bootstatus`. | bundle steps: `xcrun simctl boot … \|\| true`; `xcrun simctl bootstatus … -b` | Previously a bare `xcrun simctl boot … \|\| true` with **no** `bootstatus` wait, unlike the Maestro/Appium workflows — a documented asymmetry (`xcode-test-without-building` seemed to tolerate a still-booting simulator in practice). Adopting the shared bundle here incidentally fixes that gap for free, bringing this workflow in line with every other simulator-booting workflow in the repo. |
| 4 | `xcode-test-without-building@1.0.1` | "Xcode Test without building" — runs `xcodebuild test-without-building` against the prebuilt bundle, restricted to this shard's test selection, producing `BITRISE_XCRESULT_PATH`. | `xctestrun: $XCTESTRUN_FILE_PATH`; `destination: platform=iOS Simulator,name=Bitrise iOS default,OS=latest`; `only_testing: $ONLY_TESTING_PATH` | `only_testing` here is given a *file path* (the shard's test-selection file), not an inline test-identifier list — consistent with `xcode-test-shard-calculation`'s stated pairing with this Step. |
| 5 | `deploy-to-bitrise-io@2.26.2` | Uploads this shard's `.xcresult`/results — a separate Tests-tab entry per shard, as each is its own workflow/build step invocation. | `is_always_run: true` | |

## 5. Video recording

The repo's recording strategy differs by test framework, and — critically —
by whether the video is **attached to a specific Tests-tab test case** or
only sits as a **loose Artifacts-tab file**. Per the `ios_ui_tests` comment,
this hinges entirely on one mechanic: Bitrise's `.xcresult`-based
auto-attachment only covers attachments the test process itself captured
through XCTest's own attachment API — a video file recorded from *outside*
the test process (by a separate `simctl io recordVideo` command) has no way
to be matched back to a specific `<testcase>` inside an `.xcresult` bundle.

| Workflow | Recording mechanism | Attachment result |
|---|---|---|
| `ios_unit_tests` | none | n/a |
| `ios_ui_tests` | `simctl io … recordVideo` wrapped around the whole native `xcode-test` run ([`start-ios-sim.sh`](../scripts/recording/start-ios-sim.sh)/[`stop-ios-sim.sh`](../scripts/recording/stop-ios-sim.sh)) | **Artifacts-tab file only** (`ios-ui-tests-recording.mp4`) — `xcode-test` produces `.xcresult`, and this externally-captured file can't be matched into it. XCTest's own failure screenshots, captured through its own API, still auto-attach fine. |
| `ios_ui_tests_manual` | same `simctl io … recordVideo` wrap, around raw `xcodebuild test` | **True Tests-tab video attachment** — because this workflow builds its own JUnit XML (via `xcpretty --report junit`) instead of relying on `.xcresult`, [`attach_media_to_junit.py`](../scripts/reporting/attach_media_to_junit.py) can inject a synthetic `<testcase>` into that JUnit XML and name the media file per Bitrise's attachment-naming convention, which *is* a supported path for JUnit-based (not `.xcresult`-based) reports. |
| `ios-fastlane-scan` | same `simctl` wrap, around `fastlane scan` | **True Tests-tab video attachment**, same JUnit-synthetic-testcase mechanism as above — `scan`'s own `output_types: junit` output plays the same role `xcpretty` plays in `ios_ui_tests_manual`. |
| `ios-maestro-e2e` | Maestro's **built-in** `startRecording`/`stopRecording` flow commands (see [`counter_basic.yaml`](../apps/ios/maestro/counter_basic.yaml), [`counter_reset.yaml`](../apps/ios/maestro/counter_reset.yaml)) | True Tests-tab attachment, natively — the `maestro-test` Step's own documented behavior attaches each flow's recording/screenshots directly to that flow's own test case, since Maestro (not an external process) captures and reports it. |
| `ios-appium-local` | base64 video capture through the Appium/XCUITest driver inside the test code itself (`test_counter_ios.py`/its fixtures), not a Bitrise step | Depends entirely on what the pytest fixture does with the captured base64 payload (e.g. decode + attach to the JUnit report, or write as a side artifact) — this file's workflow itself does nothing with video beyond running pytest and exporting its JUnit XML, so check `e2e/appium/conftest.py`/`tests/test_counter_ios.py` for the actual attachment behavior. |

All the `simctl`-based paths honor `$RECORD_VIDEO` (`all`/`failures`/`off`)
both at capture time (`start-ios-sim.sh` no-ops entirely if `off`) and at
attach time (`attach_media_to_junit.py` drops the video for a passing suite
if `failures`).

## 6. Test reporting

| Workflow | Report mechanism | Why |
|---|---|---|
| `ios_unit_tests` | `.xcresult` auto-attached by `deploy-to-bitrise-io` after `xcode-test` | Simplest/most "native" path — correct whenever you don't need a synthetic recording test case. |
| `ios_ui_tests` | same `.xcresult` auto-attach | Keeps the native Step's convenience; trades away the ability to attach the externally-recorded video to a test case (§5). |
| `ios_ui_tests_manual` | manual `xcodebuild test \| xcpretty --report junit` → `custom-test-results-export` | Gives up `.xcresult` auto-attachment and the native Step's convenience, in exchange for a JUnit XML that *can* carry a synthetic video-attachment test case. |
| `ios-fastlane-scan` | `scan`'s own `output_types: junit` → `custom-test-results-export` | Same trade-off as above, but via fastlane's own JUnit writer instead of `xcpretty`. |
| `ios-maestro-e2e` | `maestro-test`'s native export (one entry per flow) | Nothing manual needed — Maestro's own Step handles both running and reporting. |
| `ios-appium-local` | pytest `--junitxml` → `custom-test-results-export` | Appium/pytest has no Bitrise-native auto-export, so it always goes through `custom-test-results-export`, regardless of recording. |
| sharded stages | native `.xcresult` from `xcode-test-without-building`, auto-attached per shard workflow | Each shard workflow is its own build-step invocation, so each gets an independent Tests-tab entry. |

**Why three separate approaches exist for "the same" `CounterApp-UI` suite**
(`ios_ui_tests`/`ios_ui_tests_manual`/`ios-fastlane-scan`), in the YAML's own
words: each is a genuine point on a convenience-vs-control trade-off curve.
The native Step (`ios_ui_tests`) is the least code and gets automatic
`.xcresult` handling, but can't carry an externally-recorded video onto a
specific test case. Manual `xcodebuild` (`ios_ui_tests_manual`) and fastlane
`scan` (`ios-fastlane-scan`) both give up that native convenience in
exchange for a JUnit XML they fully control, which *can* carry the
synthetic recording attachment — they differ only in whose JUnit writer
(`xcpretty` vs. `scan`'s own) and whose ecosystem (raw `xcodebuild` vs.
fastlane) produces it.

## 7. Run it locally

```bash
# From the repo root:
cd apps/ios
brew install xcodegen   # if not already installed
xcodegen generate

# Unit + snapshot tests (Swift Testing + swift-snapshot-testing):
xcodebuild test \
  -project CounterApp.xcodeproj -scheme CounterApp-Unit \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# XCUITest UI tests, native xcodebuild:
xcodebuild test \
  -project CounterApp.xcodeproj -scheme CounterApp-UI \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# fastlane scan (same scheme):
bundle exec fastlane scan_xcuitest   # or: fastlane scan_xcuitest, from apps/ios

# Maestro (build + ad hoc sign first, then point Maestro at the folder):
xcodebuild build -project CounterApp.xcodeproj -scheme CounterApp-UI \
  -sdk iphonesimulator -derivedDataPath ./ios-sim-build CODE_SIGNING_ALLOWED=NO
APP=$(find ./ios-sim-build/Build/Products -name 'CounterApp.app' | head -1)
codesign --force --deep --sign - "$APP"
maestro test apps/ios/maestro --app-id io.bitrise.sample.counter

# Appium: boot a simulator, build+sign the app as above, start `appium`,
# then from e2e/appium:
pip install -r requirements.txt
APPIUM_IOS_APP_PATH="$APP" APPIUM_IOS_DEVICE="iPhone 16" \
  pytest tests/test_counter_ios.py
```

To run the actual Bitrise-defined workflows locally with the Bitrise CLI
(requires a macOS machine with Xcode, and the `bitrise` CLI installed):

```bash
bitrise run ios_unit_tests
bitrise run ios_ui_tests
bitrise run ios-maestro-e2e
bitrise run ios-fastlane-scan
bitrise run ios-appium-local
bitrise run ios_ui_tests_manual
# The sharded pipeline's stages depend on pipeline-only intermediate files
# and generally can't be meaningfully run individually with `bitrise run`;
# use the Bitrise UI's "Start build > Pipeline" against ios_xcuitest_sharded.
```

## 8. Adapting this to your own project

Minimal changes needed per approach, when copying this pattern into another
iOS project:

- **Everywhere**: replace `"Bitrise iOS default"` with your own device-name
  convention (keep using a Bitrise-maintained simulator alias rather than a
  hardcoded model name — see §9), and swap `io.bitrise.sample.counter` /
  `CounterApp` / `CounterApp-Unit` / `CounterApp-UI` / `CounterAppUITests`
  for your own bundle id, project, scheme, and target names.
- **Unit tests (`ios_unit_tests` pattern)**: just `xcode-test` + `deploy-to-bitrise-io`; nothing else to change beyond scheme/project paths.
- **UI tests via native Step (`ios_ui_tests`)**: add the pre-boot +
  `start-ios-sim.sh`/`stop-ios-sim.sh` pair only if you want a recording at
  all — accept that it'll land as an Artifact, not a Tests-tab attachment.
- **UI tests with a true video attachment (`ios_ui_tests_manual`/`ios-fastlane-scan`)**:
  you need a JUnit-producing test runner (`xcpretty --report junit` or
  `scan`'s `output_types: junit`) plus
  [`attach_media_to_junit.py`](../scripts/reporting/attach_media_to_junit.py)
  (or an equivalent) and `custom-test-results-export`. Keep the
  `--classname`/`--name` pair consistent with how your JUnit writer actually
  names the suite/test (here, `CounterAppUITests.CounterUITests` — a
  synthetic default name since the attachment is suite-level, not per-test).
- **Maestro**: build with plain `xcodebuild build` (never
  `xcode-build-for-simulator`), ad hoc codesign (`codesign --sign -`), use
  `simctl bootstatus -b` after boot, then `maestro-test`. Put your flows in a
  dedicated folder with a `config.yaml` (`flows: ["*.yaml"]` is enough).
- **Appium**: same build+sign recipe as Maestro, plus resolving the
  simulator's real UDID (don't trust a Step's own `platform_version`-style
  input to stay in sync with `OS=latest`), and running your own Appium
  server + pytest/whatever client you use.
- **Sharded XCUITest**: `xcode-build-for-test` → share only the test bundle
  directory as a pipeline intermediate file (not the `.xctestrun` file
  separately) → `xcode-test-shard-calculation` with the `.xctestrun`'s
  resolved path, not the bundle directory → one `xcode-test-without-building`
  workflow per shard, each re-discovering its own shard file positionally
  rather than assuming a filename convention.

## 9. Troubleshooting / known issues

These are the real failure modes this file's own inline comments document
(not fixed here — this module works around all of them already, but a
reader modifying it should know why each workaround exists):

1. **`xcode-build-for-simulator` tags the output for the device platform,
   not the simulator, even with `-sdk iphonesimulator`.** Confirmed live
   twice. Root cause: the Step runs `xcodebuild archive`, which is
   fundamentally a device-distribution action in Xcode and doesn't reliably
   resolve to the simulator platform regardless of flags. `simctl` then
   refuses to install the resulting `.app` ("has code for platforms: [iOS,
   arm64]... device can run: iOS-simulator"). Workaround: build directly
   with plain `xcodebuild build` instead of using the Step (`ios-maestro-e2e`, `ios-appium-local`).
2. **An unsigned app launched directly via `simctl launch` is denied by
   SpringBoard on iOS 18.x simulators**, even though the same unsigned app
   runs fine under `xcode-test`/`xcodebuild test` (because XCTest's own
   harness does the launching there, not a bare `simctl launch`). Surfaces
   as `"SBMainWorkspace"` (Maestro, confirmed live builds #98/#108/#119/#127)
   or the misleading `"Simulator architecture is not supported"` (Appium,
   confirmed live build #129). Fix: ad hoc codesign the built app
   (`codesign --force --deep --sign -`) before launching it outside XCTest.
3. **`simctl boot` can return before the simulator has actually finished
   booting**, causing races when the next command tries to interact with it
   immediately. Fix: follow `simctl boot` with `simctl bootstatus -b`, which
   blocks until the simulator is truly ready — both lines are now the shared
   `bundle::ios_simulator_boot` Step bundle (see
   [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §7), used by
   `ios-maestro-e2e`, `ios-appium-local`, and (previously the one exception,
   with no `bootstatus` wait at all) `ios-xcuitest-shard-1`/`-2` — adopting
   the bundle there closed that gap instead of leaving it as a known
   asymmetry.
4. **A hardcoded `platform_version` for Appium drifts out of sync with a
   build step's `OS=latest` destination across stack updates.** Confirmed
   live build #102: `"'18.0' does not exist in the list of simctl SDKs"`.
   Fix: resolve and hand Appium the simulator's exact UDID instead of a
   version string.
5. **Listing both `BITRISE_TEST_BUNDLE_PATH` and `BITRISE_XCTESTRUN_FILE_PATH`
   in `pipeline_intermediate_files` breaks the `.xctestrun`'s relative
   reference to the built `.app`.** `pull-intermediate-files` extracts each
   listed path into its own isolated directory, severing the relative path
   the `.xctestrun` uses to find the app inside what used to be a single
   tree. Confirmed live build #125: `"bundle identifier... couldn't be
   read"`. Fix: share only the bundle directory; have downstream stages
   `find` the `.xctestrun` inside it themselves.
6. **`xcode-test-shard-calculation`'s `product_path` input rejects a raw
   test-bundle directory.** Confirmed live build #112:
   `"unsupported test products file extension"`. It wants the `.xctestrun`
   file itself (supported formats: `xctestrun`/`xctestproducts`).
7. **`xcode-test-shard-calculation`'s output shard filenames aren't
   documented, and guessing wrong fails in a confusing way.** A first
   attempt assumed a `shard_1.txt`-style convention; it failed because that
   file didn't exist, and the next Step then misparsed the literal
   (nonexistent) guessed path as a test identifier itself, producing
   `"Tests in target 'var' can't be run"`. Fix: don't guess a naming scheme
   — sort the shard-output directory's files and take the Nth one
   positionally for shard N.
8. **A hardcoded simulator device-model name (e.g. `"iPhone 16"`) will
   eventually stop matching what a given stack image actually ships.**
   `"Bitrise iOS default"` is a Bitrise-maintained alias that always
   resolves to a valid, available simulator on whatever stack is current —
   used everywhere in this file instead of a concrete device name for that
   reason (not called out as a numbered "confirmed live" bug in the YAML,
   but implied by consistent use of the alias throughout and worth stating
   explicitly for anyone tempted to hardcode a device name when copying this
   pattern).
9. **Possible gap, not confirmed as a live failure — flagged for the
   reader**: `ios-appium-local`'s Appium server is started with
   `--base-path /wd/hub`, a legacy JSON-Wire-style base path; newer
   Appium/driver combinations sometimes default to a bare `/` base path.
   If the client or driver version changes, double-check
   `APPIUM_SERVER_URL=http://localhost:4723/wd/hub` in step 4 still matches
   what the server in step 1 is actually serving.
10. **Attachment-script default naming**: in `ios-fastlane-scan`/`ios_ui_tests_manual`,
    `attach_media_to_junit.py add-recording-testcase` is called without
    `--name`, so the synthetic test case is always named
    `zz_session_recording` (the script's default) under classname
    `CounterAppUITests.CounterUITests` — this is a suite-level recording
    attached to one synthetic case, not a per-real-test-case video; anyone
    expecting the recording keyed to `testStartsAtZero`/
    `testIncrementDecrementReset` individually should know it isn't.
