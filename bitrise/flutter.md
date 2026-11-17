# `bitrise/flutter.yml`

Shared Bitrise concepts (workflows vs. pipelines, triggers, the Tests tab, the attachment-naming
convention, caching, step pinning) are covered once in [`../docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md)
— this doc only covers what's specific to the Flutter module.

## 1. Overview

This module builds and tests `apps/flutter` — a Flutter counter app with the same UI/behavior as
the other three sample apps — using four different testing approaches:

| Workflow | What it tests | Device |
|---|---|---|
| `flutter_tests` | Unit, widget, and golden (pixel-diff) tests via `flutter test` | none (JVM/Dart VM only) |
| `flutter_record_goldens` | Records new golden-image baselines | none, manual only |
| `flutter_integration_tests` | `integration_test` package (Flutter's own instrumented-test framework) | Android emulator |
| `flutter_patrol_android` | [Patrol](https://patrol.leancode.co) — `integration_test` plus native (non-Flutter) interactions, e.g. pressing Home | Android emulator |
| `flutter_patrol_ios` | Same Patrol test suite, run through Patrol's XCUITest-based iOS runner | iOS Simulator |

Expect: JUnit results on the Tests tab for every workflow except `flutter_record_goldens`; a
golden-diff image attached to the failing test case for `flutter_tests`; suite-level video for
`flutter_integration_tests` and both Patrol workflows; **per-test native screenshots** for
`flutter_patrol_android` (Patrol's richest screenshot support in this repo); for
`flutter_patrol_ios`, test execution + video work, but screenshots currently don't attach (see
§9).

## 2. Prerequisites

| Workflow | Stack | Machine |
|---|---|---|
| `flutter_tests`, `flutter_record_goldens` | inherited from root `bitrise.yml` (`ubuntu-noble-24.04-bitrise-2025-android`) | inherited (`g2.linux.medium`) |
| `flutter_integration_tests`, `flutter_patrol_android` | `ubuntu-noble-24.04-bitrise-2025-android` | `g2.linux.large` |
| `flutter_patrol_ios` | `osx-xcode-27.2.x` | `g2.mac.medium` |

Tools: Flutter SDK (installed by `flutter-installer@1.1.1` with `version: stable`, i.e. whatever
the current stable channel resolves to at build time — not a pinned Flutter version), the Android
SDK/emulator images Bitrise's Android stack ships with (for `avd-manager`), and on the iOS
workflow: Xcode (from the `osx-xcode-27.2.x` stack), CocoaPods (preinstalled on that stack, used
defensively — see §4 workflow `flutter_patrol_ios`), and the `xcodeproj` and `fastlane` Ruby
gems (installed on demand by the workflow itself if missing).

Secrets/env vars used (all names only — none of these are actual secret *values*):

| Name | Set where | Purpose |
|---|---|---|
| `RECORD_VIDEO` | root `bitrise.yml` app env (`all` by default) | Not read directly by this module's scripts (unlike Android/iOS native UI tests) — Patrol's video capture here is unconditional; see §5. |
| `BITRISE_EMULATOR_SERIAL` | set by `avd-manager`/`wait-for-android-emulator` | Device id passed to `flutter test integration_test -d` and `patrol test --device`. |
| `BITRISE_SOURCE_DIR`, `BITRISE_DEPLOY_DIR` | Bitrise CLI built-ins | Repo checkout root; artifact deploy directory. |

No external credentials (no BrowserStack/Firebase-style secret) are needed anywhere in this
module — every device is a local emulator/simulator.

## 3. Triggers and pipelines

The `flutter` pipeline triggers on push to `main` and on any pull request, gated by
`changed_files.regex: '^(apps/flutter/.*|bitrise/flutter\.yml)$'` — i.e. only when a change
touches `apps/flutter/` or this YAML file itself.

Pipeline wiring:

```
flutter_tests
  ├─▶ flutter_integration_tests   (depends_on: [flutter_tests])
  ├─▶ flutter_patrol_android      (depends_on: [flutter_tests])
  └─▶ flutter_patrol_ios          (depends_on: [flutter_tests])
```

All three device-based workflows run in parallel once `flutter_tests` passes — they don't depend
on each other, only on the fast no-device suite passing first. `flutter_record_goldens` is not
part of any pipeline and has no `triggers:` — it only runs when started manually from the Bitrise
UI.

Every workflow in this file shares one `before_run: [_flutter_setup]` helper workflow:

- `git-clone@8.5.2` — clones the repo.
- `flutter-installer@1.1.1` (`version: stable`) — installs the Flutter SDK. Per the Step's own
  docs, it must run *before* the cache-restore step for caching to work correctly — and indeed
  it's listed before `restore-dart-cache` here.
- `restore-dart-cache@3.0.2` — restores the pub cache (key/path computed automatically from
  `pubspec.lock`).

## 4. Workflow-by-workflow walkthrough

### `flutter_tests`

1. **`script@1.2.1` — "Run flutter test"** (`working_dir: apps/flutter`)
   ```bash
   set -o pipefail
   dart pub global activate junitreport
   mkdir -p test-results
   flutter test --machine | dart pub global run junitreport:tojunit --output test-results/flutter.xml
   ```
   `flutter test --machine` emits machine-readable JSON events to stdout; `junitreport:tojunit`
   converts that stream to JUnit XML. **Why `set -o pipefail` alone, not `set -eo pipefail`**: if
   `-e` were also set, the script would abort the instant `flutter test`'s own exit code is
   non-zero — before `tojunit` ever gets to read/convert the piped JSON — so a genuinely failing
   test run would silently produce *no* JUnit XML at all. Dropping `-e` for this one line lets a
   failing suite still produce a valid (failing) XML for the next steps to process.
2. **`script@1.2.1` — "Attach golden diff image (if any test failed)"**, `is_always_run: true`
   ```bash
   DIFF_PNG="$(ls test/goldens/failures/*.png 2>/dev/null | head -n1 || true)"
   if [ -n "$DIFF_PNG" ]; then
     python3 "$BITRISE_SOURCE_DIR/scripts/reporting/attach_media_to_junit.py" attach-to-first-failure \
       --junit-xml test-results/flutter.xml --media "$DIFF_PNG" --label golden_diff --dest-dir test-results
   else
     echo "No golden failure image found, nothing to attach."
   fi
   ```
   Golden tests ([`golden_toolkit`](https://pub.dev/packages/golden_toolkit)-style, built into
   `flutter test`) write an actual-vs-expected diff PNG under `test/goldens/failures/` only when
   a golden comparison fails. Since the script doesn't know in advance *which* test will fail or
   what its exact JUnit name will be, it uses `attach_media_to_junit.py`'s `attach-to-first-failure`
   mode — it scans `flutter.xml` for the first `<failure>`/`<error>` and attaches there. No-op
   (prints a message, doesn't fail) if nothing failed.
3. **`custom-test-results-export@2.0.0`**, `is_always_run: true` — `test_name: Flutter tests`,
   `base_path: apps/flutter/test-results`, `search_pattern: "*/flutter.xml"`. Generic export route
   (see [concepts §3](../docs/BITRISE_CONCEPTS.md#3-deploy-to-bitriseio-and-the-tests-tab)).
4. **`save-dart-cache@1.1.1`** — no inputs set; saves the pub cache for next time.
5. **`deploy-to-bitrise-io@2.26.2`**, `is_always_run: true` — uploads the exported test result
   (and anything left in `$BITRISE_DEPLOY_DIR`) to the build's Tests/Artifacts tabs.

**Recommendation**: the `-e`/pipe interaction above is a real, non-obvious footgun — any script
step that does `tool_that_can_fail | converter` and needs the converter's output *regardless* of
the first command's exit code should drop `-e` for that line (or capture the exit code
separately), not rely on `set -eo pipefail` out of habit.

### `flutter_record_goldens`

Manual-only helper, not in any pipeline.

1. **`script@1.2.1` — "Record goldens"**
   ```bash
   set -eo pipefail
   flutter pub get
   flutter test --update-goldens test/goldens
   cp test/goldens/*.png "$BITRISE_DEPLOY_DIR/"
   ```
   `--update-goldens` makes `flutter test` write the *actual* rendered output as the new golden
   baseline instead of diffing against the old one. The PNGs are copied (not zipped — they're
   individual files, not a directory) straight into `$BITRISE_DEPLOY_DIR` so `deploy-to-bitrise-io`
   picks them up as plain downloadable artifacts. A human then downloads them from the Artifacts
   tab and commits them to `test/goldens/` manually — this step does not commit anything itself.
2. **`deploy-to-bitrise-io@2.26.2`**, `is_always_run: true`.

### `flutter_integration_tests`

1. **`avd-manager@2.2.0`** — `profile: pixel_6`, `api_level: "34"`, `tag: google_apis`,
   `abi: x86_64`. Creates and boots an Android Virtual Device matching a Pixel 6 profile on API
   34 (Android 14) with Google APIs, x86_64 (fast on the Linux build machines this runs on — per
   the Step's own docs, Android emulators can't run on Apple Silicon machines at all, which is
   why this workflow pins the Linux stack rather than inheriting a Mac one).
2. **`wait-for-android-emulator@1.0.10`** — blocks until the AVD above finishes booting.
3. **`script@1.2.1` — "Start screen recording"**: runs
   [`scripts/recording/start-android.sh`](../scripts/recording/start-android.sh)
   `/sdcard/bitrise-recordings integration-test` — starts an `adb shell screenrecord`-based
   recording labeled `integration-test`. (Host-side, not on-device, because on-device recording
   APIs are blocked by SELinux for an app-process UID — Flutter's instrumented test code can't
   invoke `screenrecord` itself.)
4. **`script@1.2.1` — "Run integration_test"** (`working_dir: apps/flutter`)
   ```bash
   set -o pipefail
   [ -d android ] || flutter create . --platforms=android,ios --org io.bitrise.sample --project-name counter_flutter
   flutter pub get
   dart pub global activate junitreport
   mkdir -p test-results
   flutter test integration_test -d "$BITRISE_EMULATOR_SERIAL" --machine \
     | dart pub global run junitreport:tojunit --output test-results/integration.xml
   ```
   The `ios`/`android` platform folders aren't committed to this repo (they're generated, not
   source) — `flutter create` regenerates them if missing, idempotently (`[ -d android ] ||`
   guards against recreating them on a checkout that *does* have them, e.g. a cache hit). Same
   `set -o pipefail` (no `-e`) reasoning as `flutter_tests`.
5. **`script@1.2.1` — "Stop screen recording"**, `is_always_run: true`: runs
   [`screenshot-android.sh`](../scripts/recording/screenshot-android.sh) for a final-state
   screenshot, then [`stop-android.sh`](../scripts/recording/stop-android.sh) to finalize the
   recording.
6. **`script@1.2.1` — "Attach the recording and screenshot"**, `is_always_run: true`
   ```bash
   RECORDING="$("$BITRISE_SOURCE_DIR/scripts/recording/concat-chunks.sh" \
     "$BITRISE_SOURCE_DIR/recordings/bitrise-recordings/integration-test_chunk*.mp4" \
     "$BITRISE_SOURCE_DIR/recordings/integration-test_combined.mp4")"
   if [ -n "$RECORDING" ]; then
     python3 ".../attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/integration.xml \
       --classname counter_flutter.integration_test.app_test \
       --media "$RECORDING" --dest-dir test-results
   else
     echo "No recording found, exporting test results without a video attachment."
   fi
   if [ -s ".../integration-test-final.png" ]; then
     python3 ".../attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/integration.xml \
       --classname counter_flutter.integration_test.app_test \
       --media ".../integration-test-final.png" --label screenshot --always --dest-dir test-results
   fi
   ```
   `integration_test` has no native per-test screenshot/video API, so there's no real `<testcase>`
   whose exact name is already known to attach to — `add-recording-testcase` **synthesizes** a
   passing `zz_session_recording`-style testcase entry under the given classname if one doesn't
   already exist in the XML, then attaches the file to it. The screenshot call passes `--always`,
   bypassing the `$RECORD_VIDEO` gate screenshots don't need to respect (see
   [concepts](../docs/BITRISE_CONCEPTS.md)); the video call does not pass `--always`, so whether
   it's actually kept depends on `attach_media_to_junit.py`'s own read of `$RECORD_VIDEO` against
   whether the XML it's about to attach to shows any failures.
7. **`custom-test-results-export@2.0.0`**, `is_always_run: true` — `test_name: Flutter
   integration tests`, `search_pattern: "*/integration.xml"`.
8. **`save-dart-cache@1.1.1`**, **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`).

### `flutter_patrol_android`

1. **`avd-manager@2.2.0`** — same profile as above.
2. **`script@1.2.1` — "Prepare Android project for Patrol"**
   ```bash
   set -eo pipefail
   [ -d android ] || flutter create . --platforms=android,ios --org io.bitrise.sample --project-name counter_flutter
   python3 tool/patrol_setup_android.py      # no-op if already applied
   flutter pub get
   dart pub global activate patrol_cli 4.8.0
   envman add --key PATH --value "$PATH:$HOME/.pub-cache/bin"
   ```
   [`tool/patrol_setup_android.py`](../apps/flutter/tool/patrol_setup_android.py) patches the
   generated `android/` project: it sets `testInstrumentationRunner` to Patrol's own
   `PatrolJUnitRunner` in `app/build.gradle.kts`, enables `ANDROIDX_TEST_ORCHESTRATOR`, adds the
   orchestrator dependency, and writes a parameterized `MainActivityTest.java` JUnit runner class
   that discovers and runs every Dart test Patrol finds. It's idempotent — every patch is skipped
   if already present, so re-running it on a cached checkout is safe. `patrol_cli` is pinned to
   `4.8.0` (`pubspec.yaml` separately pins `patrol: ^4.10.0` — the two must be compatible, per a
   comment in `pubspec.yaml`: "needs patrol_cli 4.8.0+ and patrol 4.10.0+ (both pinned)").
   `envman add --key PATH ...` persists the pub-cache `bin` directory (where `patrol_cli`'s
   executable lands) onto `$PATH` for *later* steps in the same workflow — `envman` is Bitrise's
   mechanism for exporting an env var from one step to every step that runs after it.
3. **`wait-for-android-emulator@1.0.10`**.
4. **`script@1.2.1` — "Start screen recording"**: `start-android.sh ... patrol` (same mechanism
   as `flutter_integration_tests`, different recording label).
5. **`script@1.2.1` — "Run Patrol tests"**
   ```bash
   set -eo pipefail
   export PATH="$PATH:$HOME/.pub-cache/bin"
   patrol test --device "$BITRISE_EMULATOR_SERIAL" --verbose
   ```
   `patrol test` builds the app + its generated `MainActivityTest` instrumentation APK, installs
   both on the given device, and runs every Dart test Patrol discovers under
   `patrol_test/` (per `pubspec.yaml`'s `test_directory: patrol_test`) as real Android
   instrumented (Gradle `connectedAndroidTest`) tests — each one capable of calling into native
   Android UI (e.g. pressing Home, opening notifications) in addition to normal Flutter widget
   interaction.
6. **`script@1.2.1` — "Stop screen recording"**, `is_always_run: true`: `stop-android.sh`.
7. **`script@1.2.1` — "Collect Patrol JUnit XML and reports"**, `is_always_run: true`
   ```bash
   set -eo pipefail
   mkdir -p test-results
   npx --yes junit-report-merger test-results/patrol.xml "build/app/outputs/androidTest-results/**/*.xml"
   zip -qr "$BITRISE_DEPLOY_DIR/patrol-html-report.zip" build/app/reports/androidTests 2>/dev/null || true
   zip -qr "$BITRISE_DEPLOY_DIR/patrol-screenshots.zip" patrol_test/screenshots 2>/dev/null || true
   if [ -d patrol_test/screenshots ]; then
     find patrol_test/screenshots -type f -name "*.png" | while read -r f; do
       test_name="$(basename "$(dirname "$f")")"
       test_classname="$(basename "$(dirname "$(dirname "$f")")")"
       label="$(basename "$f" .png | sed -E 's/^[0-9]+_//')"
       python3 ".../attach_media_to_junit.py" rename \
         --classname "$test_classname" --name "$test_name" --media "$f" --label "$label" --dest-dir test-results
     done
   fi
   RECORDING="$(.../concat-chunks.sh ".../patrol_chunk*.mp4" ".../patrol_combined.mp4")"
   if [ -n "$RECORDING" ]; then
     python3 ".../attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/patrol.xml \
       --classname io.bitrise.sample.counter_flutter.MainActivityTest \
       --media "$RECORDING" --dest-dir test-results
   fi
   ```
   AGP writes one instrumented-test result XML per connected device under
   `build/app/outputs/androidTest-results/`; `junit-report-merger` (run via `npx` — Node is
   preinstalled on this stack) merges them into one `patrol.xml`. The two `zip`s are **convenience
   Artifacts-tab copies**, not the Tests-tab attachment mechanism — `deploy-to-bitrise-io` only
   picks up files in `$BITRISE_DEPLOY_DIR`, not raw directories copied with `cp -r`, so the
   comment in the YAML explicitly calls out zipping instead (see
   [concepts §4](../docs/BITRISE_CONCEPTS.md#4-the-attachment-naming-convention)). The actual
   per-test-case attachment is the `find ... | while read` loop: Patrol's own
   `screenshot_on_failure`/on-demand screenshot API writes files to
   `patrol_test/screenshots/<classname>/<name>/<timestamp>_<label>.png` — a folder structure that
   **already encodes the exact JUnit `<classname>`/`<name>` it belongs to**, so `rename` mode can
   attach each one directly with no guessing (unlike `integration_test`'s synthetic-testcase
   approach above, which has no such native per-test API to rely on). The recording is attached to
   the real `MainActivityTest` classname — Patrol's generated JUnit runner class name from
   `tool/patrol_setup_android.py` — as a suite-level video.
8. **`custom-test-results-export@2.0.0`**, `is_always_run: true` — `test_name: Patrol (Android)`,
   `search_pattern: "*/patrol.xml"`.
9. **`save-dart-cache@1.1.1`**, **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`).

### `flutter_patrol_ios`

Same Dart test suite (`patrol_test/counter_patrol_test.dart`) as `flutter_patrol_android`, run
through Patrol's XCUITest-based iOS runner instead of Gradle/instrumentation. This workflow needed
real native iOS project setup that plain `flutter create` doesn't provide — see
[`apps/flutter/tool/patrol_setup_ios.rb`](../apps/flutter/tool/patrol_setup_ios.rb) and the
three-item breakdown below.

1. **`script@1.2.1` — "Prepare iOS project for Patrol"**
   ```bash
   set -eo pipefail
   [ -d ios ] || flutter create . --platforms=android,ios --org io.bitrise.sample --project-name counter_flutter
   flutter pub get
   dart pub global activate patrol_cli 4.8.0
   envman add --key PATH --value "$PATH:$HOME/.pub-cache/bin"
   gem list -i xcodeproj >/dev/null 2>&1 || gem install xcodeproj --no-document
   ruby tool/patrol_setup_ios.rb      # no-op if already applied
   ```
   `tool/patrol_setup_ios.rb` uses the `xcodeproj` Ruby gem (already available on `osx-xcode-*`
   stacks as a CocoaPods dependency; the `gem install` line is a defensive fallback) to patch the
   generated `ios/Runner.xcodeproj`:
   - **Adds a native `RunnerUITests` XCUITest target.** `flutter create` only generates a
     unit-test target (`RunnerTests`), never a UI-test target — without one, Patrol's own
     `xctestrun` patch step has nothing real to attach to and the run fails with `Cannot test
     target "RunnerUITests" ... Missing test product at (null)`. The script writes the
     `TargetAttributes.TestTargetID` project attribute (the same one Xcode itself writes when you
     add a UI Testing Bundle target via File → New → Target and pick "Runner" under "Target to be
     Tested") — this, not just the `TEST_TARGET_NAME` build setting, is what makes `xcodebuild`
     populate `TestBundlePath`/`TestHostPath` correctly in the produced `.xctestrun`.
   - **Writes the real native glue**, `ios/RunnerUITests/RunnerUITests.m` — Objective-C, copied
     verbatim from Patrol's own example app
     (`github.com/leancodepl/patrol` `packages/patrol/example/ios/RunnerUITests`):
     ```objectivec
     @import XCTest;
     @import patrol;
     @import ObjectiveC.runtime;

     PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
     ```
     This macro (not Swift — an earlier attempt with an empty Swift placeholder class got the
     native plumbing green without ever actually running the Dart test, silently reporting
     `Total: 0`) bridges to Patrol's `AutomatorServer` and the Dart-defined tests.
   - **Links `RunnerUITests` against `FlutterGeneratedPluginSwiftPackage`.** The macro's
     `@import patrol;` resolves through this local Swift package, which `flutter pub get`
     generates (it aggregates every plugin's native code, including the `patrol` plugin's).
     Flutter's own build tooling keeps the `Runner` app target's link to it in sync
     automatically, but has no awareness of this hand-added target, so it's never linked there —
     without it, the build fails with `Module 'patrol' not found`. The script adds its own
     `XCSwiftPackageProductDependency` + `Frameworks`-build-phase `PBXBuildFile` for the same
     package, mirroring exactly what's committed in Patrol's own example `.pbxproj`.
2. **`script@1.2.1` — "Pod install (if this Flutter version generated a Podfile)"**
   (`working_dir: apps/flutter/ios`)
   ```bash
   set -eo pipefail
   if [ -f Podfile ]; then
     pod install
   else
     echo "No Podfile, skipping pod install (project uses Swift Package Manager)."
   fi
   ```
   Flutter 3.24+ defaults new iOS projects to Swift Package Manager and only emits a `Podfile` if
   a plugin actually needs CocoaPods — this app has none, so `cocoapods-install@3.1.1` (the native
   Step) would hard-fail with `No Podfile found`; this conditional script replaces it.
3. **`script@1.2.1` — "Boot simulator for Patrol"**: `xcrun simctl boot "Bitrise iOS default"`
   (tolerating "already booted"), then `xcrun simctl bootstatus "Bitrise iOS default" -b` to
   actually block until SpringBoard is ready (`simctl boot` alone returns before the simulator can
   accept app launches).
4. **`script@1.2.1` — "Start screen recording"**: runs
   [`start-ios-sim.sh`](../scripts/recording/start-ios-sim.sh) `booted .../patrol-ios.mov` —
   `xcrun simctl io booted recordVideo` under the hood, targeting whichever simulator is currently
   booted.
5. **`script@1.2.1` — "Run Patrol tests"**
   ```bash
   set -o pipefail   # no -e: a failing suite must still leave us a log to convert
   export PATH="$PATH:$HOME/.pub-cache/bin"
   patrol test --device "Bitrise iOS default" --verbose 2>&1 | tee patrol-ios-build.log
   ```
   `patrol test` builds the Runner app + `RunnerUITests.xctest` and drives them via
   `xcodebuild build-for-testing` / `test-without-building`, then runs each Dart test as a real
   XCUITest test case that can call into native iOS automation (pressing Home, opening the
   notification shade) in addition to Flutter widget interaction. Log is `tee`'d to a file for the
   next step even though nothing currently reads it back — it's there in case future debugging
   needs the raw build output.
6. **`script@1.2.1` — "Stop screen recording"**, `is_always_run: true`: `stop-ios-sim.sh` —
   stops the `recordVideo` process with `SIGINT` (never `-9`, which corrupts the `.mov`'s moov
   atom) and converts `.mov → .mp4` with `ffmpeg` (Bitrise's Tests tab doesn't accept `.mov`).
7. **`script@1.2.1` — "Collect Patrol results (JUnit, screenshots, video)"**, `is_always_run: true`
   ```bash
   set -eo pipefail
   mkdir -p test-results
   gem list -i fastlane >/dev/null 2>&1 || gem install fastlane -v '~> 2.223' --no-document
   XCRESULT_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" . -maxdepth 6 -name '*.xcresult' -exec ls -dt {} + | head -1)"
   if [ -n "$XCRESULT_PATH" ]; then
     fastlane run trainer path:"$XCRESULT_PATH" output_directory:test-results output_filename:patrol-ios.xml extension:.xml
     zip -qr "$BITRISE_DEPLOY_DIR/patrol-ios-xcresult.zip" "$XCRESULT_PATH" 2>/dev/null || true
     mkdir -p ios-attachments
     xcrun xcresulttool export attachments --path "$XCRESULT_PATH" --output-path ios-attachments >/dev/null 2>&1 || true
     if [ -f ios-attachments/manifest.json ]; then
       python3 - ios-attachments <<'PYEOF'
       # parses manifest.json, copies .png/.jpg attachments into
       # patrol_test/screenshots/<classname>/<name>/<label>.<ext>
       PYEOF
     fi
   fi
   zip -qr "$BITRISE_DEPLOY_DIR/patrol-ios-screenshots.zip" patrol_test/screenshots 2>/dev/null || true
   if [ -d patrol_test/screenshots ]; then
     find patrol_test/screenshots -type f -name "*.png" | while read -r f; do
       python3 ".../attach_media_to_junit.py" rename --classname "<...>" --name "<...>" --media "$f" --label "<...>" --dest-dir test-results
     done
   fi
   if [ -s ".../patrol-ios.mp4" ] && [ -f test-results/patrol-ios.xml ]; then
     python3 ".../attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/patrol-ios.xml --classname PatrolIOS.zz_session_recording \
       --media ".../patrol-ios.mp4" --dest-dir test-results
   fi
   ```
   Patrol drives `xcodebuild` internally on iOS; it doesn't hand back a JUnit file directly, so
   this step finds whatever `.xcresult` bundle that run produced (newest one under Xcode's
   `DerivedData` or the repo checkout, by mtime) and converts it with fastlane's `trainer` action.
   The `.xcresult` itself is also zipped as a plain Artifacts-tab copy (so a human can download
   and open it directly in Xcode for full detail). The `xcresulttool export attachments` block is
   this repo's attempt to recover iOS screenshots: unlike Android (where Patrol pulls screenshots
   to a local `patrol_test/screenshots` folder), Patrol's `$.takeNativeScreenshot()` on iOS
   attaches straight into the `.xcresult` via XCTest's own attachment API, so the plain
   `patrol_test/screenshots` folder stays empty. `xcresulttool export attachments` (Apple's own
   tool, documented via `--schema`) exports whatever's in the `.xcresult` into a
   `manifest.json` + files; the inline Python script reads that manifest and copies any
   `.png`/`.jpg` into the same `<classname>/<name>/<label>.<ext>` layout Android uses, so the
   *existing* `rename`-mode attach loop picks them up with no further changes needed. **As of this
   writing, every live run has found nothing to export** — see §9. The video attach targets a
   synthetic `PatrolIOS.zz_session_recording` classname (unlike Android's attach, which targets
   the real `MainActivityTest`-equivalent class, because iOS's generated class/test names differ
   and a fixed synthetic name was simpler to pick consistently).
8. **`custom-test-results-export@2.0.0`**, `is_always_run: true` — `test_name: Patrol (iOS)`,
   `search_pattern: "*/patrol-ios.xml"`.
9. **`save-dart-cache@1.1.1`**, **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`).

**Recommendations from this workflow's own build history** (every one of these was hit on a real
live Bitrise build, not guessed):
- Don't assume a Flutter-generated iOS project has a `Podfile` — check for one before running
  `pod install`/`cocoapods-install`.
- A UI-testing-bundle Xcode target needs the `TargetAttributes.TestTargetID` project attribute to
  actually populate `TestBundlePath`/`TestHostPath` in a produced `.xctestrun` — the
  `TEST_TARGET_NAME` build setting alone isn't enough.
- "The build and run succeeded" is not the same claim as "the real test ran" — check the actual
  test count in a framework's own summary output, not just the exit code.
- A hand-added Xcode target doesn't automatically inherit `Runner`'s Swift Package Manager
  dependencies; link them explicitly if the new target's code needs them.

## 5. Video recording

- `flutter_integration_tests`, `flutter_patrol_android`: Android host-side
  `adb shell screenrecord` via [`start-android.sh`](../scripts/recording/start-android.sh)/
  [`stop-android.sh`](../scripts/recording/stop-android.sh), chunks concatenated by
  [`concat-chunks.sh`](../scripts/recording/concat-chunks.sh), attached as a suite-level
  (`flutter_integration_tests`) or `MainActivityTest`-classed (`flutter_patrol_android`) video.
- `flutter_patrol_ios`: iOS Simulator `simctl io recordVideo` via
  [`start-ios-sim.sh`](../scripts/recording/start-ios-sim.sh)/
  [`stop-ios-sim.sh`](../scripts/recording/stop-ios-sim.sh) (which also converts `.mov → .mp4`),
  attached to a synthetic `PatrolIOS.zz_session_recording` testcase.
- `flutter_tests`: no video — golden tests are a still-image diff, not a live screen; a diff PNG
  is attached instead (see §4).
- None of this module's scripts read `$RECORD_VIDEO` directly for the *decision to record* — every
  workflow here always starts a recording. What `$RECORD_VIDEO` (`all`/`failures`/`off`, set in the
  root `bitrise.yml`) actually gates is whether `attach_media_to_junit.py`'s `add-recording-testcase`
  mode **keeps** that recording once it's done, based on whether the JUnit XML it's about to attach
  to shows any failures — screenshots always pass `--always` and bypass this gate entirely.

## 6. Test reporting

All five workflows use the **generic** export route
([concepts §3](../docs/BITRISE_CONCEPTS.md#3-deploy-to-bitriseio-and-the-tests-tab)):
`flutter_tests`/`flutter_integration_tests` convert `flutter test --machine`'s JSON stream with
`junitreport:tojunit`; `flutter_patrol_android` merges AGP's own per-device instrumented-test XML
with `junit-report-merger`; `flutter_patrol_ios` converts the Patrol-produced `.xcresult` with
fastlane's `trainer`. `custom-test-results-export@2.0.0` then exports each workflow's XML, and
`deploy-to-bitrise-io@2.26.2` uploads it to the Tests tab.

## 7. Run it locally

```bash
cd apps/flutter

flutter test                              # flutter_tests
flutter test --update-goldens test/goldens  # flutter_record_goldens
flutter test integration_test -d <device-id>  # flutter_integration_tests (needs a running emulator)

dart pub global activate patrol_cli 4.8.0
patrol test --device <device-id>          # flutter_patrol_android / flutter_patrol_ios
                                           # (Android emulator or "Bitrise iOS default"-equivalent
                                           # simulator must already be running)
```

With the [Bitrise CLI](https://github.com/bitrise-io/bitrise) installed: `bitrise run
flutter_tests` (or any other workflow name) runs the exact same Steps locally, modulo
stack-specific tools (e.g. `avd-manager`/`xcrun simctl` need their respective platform).

## 8. Adapting this to your own project

- Minimal copy for unit/widget/golden tests: `_flutter_setup` + the `flutter_tests` workflow as-is
  (swap the working dir).
- For `integration_test`: add `avd-manager` + `wait-for-android-emulator`, and reuse
  `scripts/recording/start-android.sh`/`stop-android.sh`/`concat-chunks.sh` and
  `scripts/reporting/attach_media_to_junit.py` verbatim — they're framework-agnostic.
- For Patrol on Android: additionally copy `tool/patrol_setup_android.py` and run it once per
  checkout before `patrol test`; update its hardcoded `PACKAGE` constant to your app's package
  name.
- For Patrol on iOS: additionally copy `tool/patrol_setup_ios.rb`, update its `BUNDLE_ID`
  constant, and budget for the native-setup edge cases in §4/§9 — this is the least
  plug-and-play piece in this whole module.
- Update every `--org`/package-name/bundle-id literal (`io.bitrise.sample`,
  `counter_flutter`, `io.bitrise.sample.counterFlutter`) to your own project's identifiers.

## 9. Troubleshooting / known issues

- **`flutter-installer@1.1.1` is pinned to `version: stable`, not a specific Flutter version** —
  this means every build effectively floats to whatever the stable channel currently resolves to.
  Unlike every *Step* version in this file (all pinned exactly), the *Flutter SDK* version itself
  isn't reproducible build-to-build. Worth pinning explicitly (e.g. `version: 3.x.y`) if build
  reproducibility matters more than always having the latest stable.
- **iOS screenshots don't attach (open issue).** `$.takeNativeScreenshot()` calls in
  `patrol_test/counter_patrol_test.dart` run without error, but neither the Android-style pulled
  folder nor the `xcresulttool export attachments` fallback has found anything to export on any
  live run so far (`zip error: Nothing to do!` in the build log). The export code is a safe no-op,
  not a failure, so it doesn't break the build — but whether/how Patrol actually produces iOS
  screenshots needs further investigation (possibly a Patrol version/config issue on the
  framework's own side). Don't assume this is fixed just because the step runs cleanly.
- **The `RunnerUITests.m` / `FlutterGeneratedPluginSwiftPackage` setup in `flutter_patrol_ios` is
  inherently fragile to Flutter/Patrol upstream changes.** It depends on exact, currently-true
  facts about how Flutter and Patrol structure their generated Xcode projects (confirmed live
  against Xcode 27.2 / Flutter stable / Patrol 4.11.0 at the time this was written) — a future
  Flutter or Patrol release changing its SPM/project-generation internals could silently break
  `tool/patrol_setup_ios.rb` again. Re-verify live after any Flutter/Patrol/Xcode-stack upgrade,
  the same way this repo's other iOS workflows recommend doing after stack upgrades.
- **`flutter_patrol_ios`'s "Run Patrol tests" step uses `set -o pipefail` without `-e`**, same
  reasoning as `flutter_tests` — intentional, not an oversight, but easy to "fix" into a bug if
  someone later tidies up scripts for consistency without understanding why.
- **No retry mechanism for flaky Patrol/integration_test runs** in this module (unlike
  `maestro-test`'s built-in `num_flaky_test_attempts` elsewhere in this repo) — a flaky native
  interaction (e.g. a slow notification-shade animation) fails the whole step with no automatic
  retry.
