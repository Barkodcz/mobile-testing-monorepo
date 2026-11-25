# Android CI (`bitrise/android.yml`)

Documentation for the Bitrise config module that builds and tests the sample Android app at
[`apps/android`](../apps/android). This file is included from the root [`bitrise.yml`](../bitrise.yml)
via `include:` and is merged into the same Bitrise project as the other platform modules.

For generic Bitrise concepts (workflows vs. pipelines, triggers, step-version pinning, the Tests-tab
attachment-naming convention, `deploy-to-bitrise-io`, Gradle caching) see
[`../docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) — this doc only covers what's specific to
the Android module.

## 1. Overview

`apps/android` is a small native Jetpack Compose "counter" app (`io.bitrise.sample.counter`,
`CounterAndroid` Gradle project). `bitrise/android.yml` exercises four kinds of testing against it:

- **JVM unit tests** (JUnit, `testDebugUnitTest`) — fast, no device needed.
- **Paparazzi snapshot tests** — Compose UI rendered off-device and diffed pixel-for-pixel against
  committed reference images (`verifyPaparazziDebug`), plus a manual workflow to re-record those
  references.
- **Instrumented Compose UI tests** (`connectedDebugAndroidTest`) on a Bitrise-hosted Android emulator
  (AVD Manager), with the whole run's screen captured as video.
- **The same instrumented UI tests run through Bitrise's Virtual Device Testing add-on** (Firebase Test
  Lab) instead of a local emulator, as a manual-trigger alternative.

A reader opening a build of this module should expect to see, per workflow: a green/red result per
test case on the build's **Tests** tab (JUnit-style, one tab per `test_name`), a screen recording or
screenshot attached to the relevant test case for the UI-test workflows (subject to `RECORD_VIDEO`),
and zipped fallback artifacts (Paparazzi failure diffs, recorded snapshots) on the **Artifacts** tab.

## 2. Prerequisites

### Stack and machine type

| Workflow | Stack | Machine type | Notes |
|---|---|---|---|
| `android_unit_tests` | inherited from root `bitrise.yml` → `ubuntu-noble-24.04-bitrise-2025-android` | inherited → `g2.linux.medium` | No `meta` override; uses the project default. |
| `android_snapshot_tests` | inherited | inherited (`g2.linux.medium`) | No `meta` override. |
| `android_record_snapshots` | inherited | inherited (`g2.linux.medium`) | Manual helper, no override. |
| `android_ui_tests` | **override**: `ubuntu-noble-24.04-bitrise-2025-android` (same image, set explicitly) | **override**: `g2.linux.large` | Comment: "the emulator needs more RAM." |
| `android-espresso-vdt` | **override**: `ubuntu-noble-24.04-bitrise-2025-android` | **override**: `g2.linux.medium` | No local emulator is run (VDT/Firebase Test Lab provides the device), so a smaller machine than `android_ui_tests` is sufficient. |

The root `bitrise.yml`'s top-level `meta.bitrise.io` block (stack `ubuntu-noble-24.04-bitrise-2025-android`,
machine `g2.linux.medium`) is the default for any workflow in this module that doesn't declare its own
`meta`. Only `android_ui_tests` needs a bigger machine, because it boots an x86_64 emulator alongside
the Gradle build/test.

### Required tooling

- **JDK 17** — `apps/android/app/build.gradle.kts` sets `sourceCompatibility`/`targetCompatibility` and
  `kotlinOptions.jvmTarget` to `17`. The Bitrise Android stack ships a compatible JDK; no explicit
  "set Java version" step is present in the YAML, so it relies on the stack's default.
- **Android SDK / compileSdk 34**, `minSdk 24`, `targetSdk 34` (from `build.gradle.kts`).
- **AGP 8.7.3**, **Kotlin 2.1.0**, **Paparazzi Gradle plugin 1.3.5** (root `apps/android/build.gradle.kts`).
- **Emulator image** (for `android_ui_tests` only): AVD profile `pixel_6`, API level `34`, tag
  `google_apis`, ABI `x86_64` — set via the `avd-manager` step (see §4).
- **ffmpeg** — used by `scripts/recording/concat-chunks.sh` to stitch multi-chunk screen recordings;
  assumed preinstalled on the Bitrise stack image (the script degrades gracefully if it's missing).
- **Node/npx** — `npx --yes junit-report-merger` merges multiple per-class JUnit XML files into one
  file, used in `android_snapshot_tests` and `android_ui_tests`.
- **Python 3** — runs `scripts/reporting/attach_media_to_junit.py`.

### Env vars / secrets referenced (names only)

| Name | Purpose | Where set | Where consumed |
|---|---|---|---|
| `RECORD_VIDEO` | Controls whether screen recordings are captured/kept: `all` \| `failures` \| `off`. Root `bitrise.yml` defaults it to `all` for this repo ("showcase as much recorded evidence as possible"). | `app.envs` in root `bitrise.yml` (default `all`); overridable per-build in the Bitrise UI | `scripts/recording/start-android.sh`, `scripts/recording/stop-android.sh`, `scripts/reporting/attach_media_to_junit.py` |
| `VDT_DEVICE_LIST` | One-device-per-line list (`deviceID,version,language,orientation`) of Firebase Test Lab devices to run against. Defaults to a single cheap device to keep VDT cost low. | `app.envs` in root `bitrise.yml` (default `SmallPhone.arm,30,en,portrait`) | `android-espresso-vdt`'s `virtual-device-testing-for-android` step (`test_devices` input) |
| `ADDON_VDTESTING_API_TOKEN` | Auth token for the Virtual Device Testing add-on (Firebase Test Lab proxy); no GCP/Firebase service account needed. | Auto-provisioned by Bitrise when the VDT add-on is enabled on the app (dashboard → app → Add-ons) | `virtual-device-testing-for-android` step, internally (not referenced explicitly in the YAML — the step resolves it itself) |
| `BITRISE_SOURCE_DIR`, `BITRISE_DEPLOY_DIR`, `BITRISE_APK_PATH`, `BITRISE_TEST_APK_PATH`, `BITRISE_EMULATOR_SERIAL` | Standard Bitrise-provided build/step environment variables (clone root, deploy dir, built APK paths, emulator serial). | Exported by `git-clone`, `android-build-for-ui-testing`, `avd-manager` respectively | Various `script` steps and the VDT step |

No actual secret values appear in `android.yml` or any script referenced by it — double-checked; the
only credential-shaped input (`ADDON_VDTESTING_API_TOKEN`) is add-on-provisioned and never hardcoded
or printed.

## 3. Triggers and pipelines

`android.yml` defines its own `pipelines.android` pipeline:

```yaml
pipelines:
  android:
    workflows:
      android_unit_tests: {}
      android_snapshot_tests: {}
      android_ui_tests: {}
    triggers:
      push:
      - branch: main
        changed_files:
          regex: '^(apps/android/.*|bitrise/android\.yml)$'
      pull_request:
      - draft_enabled: false
        changed_files:
          regex: '^(apps/android/.*|bitrise/android\.yml)$'
```

- The three stages (`android_unit_tests`, `android_snapshot_tests`, `android_ui_tests`) run as
  **independent, parallel stages** of the `android` pipeline — there's no `depends_on`/`before_run`
  chaining between them; each has its own `git-clone` and runs standalone.
- Triggered automatically by: a push to `main`, or any pull request, but **only** when the changed
  files match `^(apps/android/.*|bitrise/android\.yml)$` (i.e. touching the Android app or this exact
  config file). PRs with `draft_enabled: false` means draft PRs do not trigger it.
- `android_record_snapshots` and `android-espresso-vdt` are **not** part of the `android` pipeline and
  have no `triggers` block at all — both are manual-only, started from the Bitrise dashboard ("Start
  build" → Workflow).
- The root `bitrise.yml`'s manual-only `everything_fast` pipeline also includes `android_unit_tests`
  and `android_snapshot_tests` (alongside other platforms' fast suites) so they can be run together as
  one ad hoc check; `android_ui_tests` is deliberately excluded from `everything_fast` since it needs
  the larger/emulator-equipped machine.

## 4. Workflow-by-workflow walkthrough

### 4.1 `android_unit_tests`

> Summary: JVM unit tests with JUnit (`testDebugUnitTest`).

1. **`git-clone@8.5.2`** — "Git Clone Repository." Checks out the repo (default config: whichever
   commit/PR/branch state the trigger specifies) and exports git metadata as step outputs. No inputs
   overridden.
2. **`restore-gradle-cache@3.1.2`** — "Restore Gradle Cache." Restores the Gradle dependency cache
   using Bitrise's built-in key-based caching for Gradle, to speed up dependency resolution. Must be
   paired with `save-gradle-cache` later in the same workflow (it is, at step 4).
3. **`android-unit-test@1.3.0`** — "Android Unit Test." Runs the project's unit tests via Gradle.
   Inputs: `project_location: $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: debug` → this
   runs `:app:testDebugUnitTest`. Per its StepLib description, the step also auto-exports to the Tests
   tab, and scans the project location for files matching the
   `<classname>__<name>[__run<k>]__<label>.<ext>` attachment-naming convention — committed/git-tracked
   files are excluded from that scan. (No such attachments exist for plain JUnit tests here; this
   matters more for the snapshot/UI workflows below.)
4. **`save-gradle-cache@1.6.2`** — "Save Gradle Cache." Saves the Gradle cache populated by this run
   for future builds to restore.
5. **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`) — "Deploy to Bitrise.io." Uploads anything
   in `$BITRISE_DEPLOY_DIR` as build artifacts and converts/sends test results to the Tests tab. Marked
   `is_always_run: true` so results and any partial artifacts are still uploaded even if the unit-test
   step failed.

Outputs consumed later: none outside this workflow — it's a standalone stage.

**Pitfall note**: `android-unit-test` is pinned to an exact patch version (`1.3.0`), which is good
practice; contrast with none of the steps in this file using a floating major-only pin (e.g. `@1`) —
every step here is fully pinned, which is deliberate per the repo's version-pinning policy (see
`docs/new-test-scenarios-plan.md`, which records that floating pins were intentionally fixed to exact
versions repo-wide).

### 4.2 `android_snapshot_tests`

> Summary: Paparazzi screenshot tests, compared with the committed snapshots.

1. **`git-clone@8.5.2`** — same as above.
2. **`restore-gradle-cache@3.1.2`** — same as above.
3. **`gradle-runner@6.0.0`** — "Gradle Runner," the official Step for running an arbitrary Gradle
   task (replaced a raw `./gradlew` script — see
   [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §6). Inputs:
   `build_root_directory: $BITRISE_SOURCE_DIR/apps/android`,
   `gradle_task: ":app:verifyPaparazziDebug"`. `app_file_include_filter`/
   `mapping_file_include_filter` are left at their defaults — this task builds no APK/AAB/mapping
   file, so nothing matches either filter anyway. (An earlier attempt overrode both to `""` to make
   that explicit; the Step rejects an empty string with `"AppFileIncludeFilter: required variable
   is not present"`, confirmed live, despite documenting both inputs as optional — so the defaults
   are left as-is instead.)
   `verifyPaparazziDebug` is the Paparazzi Gradle plugin's verification task: it renders each
   `@Test`-annotated Compose snapshot off-device and diffs it against the committed golden image in
   `app/src/test/snapshots`, failing the task (and thus the step, since no `is_always_run`) if any diff
   exceeds the tolerance.
4. **`script@1.2.1`**, titled *"Merge JUnit XML and keep diff images"* (`is_always_run: true` — runs
   even if step 3 failed, since the whole point is to collect results/diagnostics from a failing run).
   `working_dir` same as above. Content, line by line:
   ```bash
   set -eo pipefail
   mkdir -p test-results
   # Gradle writes one XML per test class; the export step takes one file.
   npx --yes junit-report-merger test-results/paparazzi.xml "app/build/test-results/testDebugUnitTest/*.xml"
   # BitriseSnapshotHandler (BitrisePaparazzi.kt) already names these
   # per the <classname>__<name>__<label>.png convention; copying
   # them flat into the export base_path is enough for
   # custom-test-results-export to attach them to their test case.
   cp app/build/bitrise-snapshots/*/*.png test-results/ 2>/dev/null || true
   # Keep the full failures dir as a browsable artifact too (zipped,
   # since deploy-to-bitrise-io ignores raw copied directories).
   zip -qr "$BITRISE_DEPLOY_DIR/paparazzi-failures.zip" app/build/paparazzi/failures 2>/dev/null || true
   ```
   - `mkdir -p test-results`: creates the merge target directory under `apps/android`.
   - `npx --yes junit-report-merger ...`: Gradle's `Test` task writes one JUnit XML file per test
     class under `app/build/test-results/testDebugUnitTest/`; this merges them into a single
     `test-results/paparazzi.xml` because the downstream export step (`custom-test-results-export`)
     is pointed at one search pattern/file.
   - `cp app/build/bitrise-snapshots/*/*.png test-results/`: copies the per-test-case PNGs that
     `BitriseSnapshotHandler` (see [`BitrisePaparazzi.kt`](../apps/android/app/src/test/java/io/bitrise/sample/counter/BitrisePaparazzi.kt))
     already wrote using the `<classname>__<name>__<label>.png` naming convention, flattening them
     into the export directory so `custom-test-results-export` attaches each image to its matching
     test case. `2>/dev/null || true` swallows the "no such file" case (e.g. no Paparazzi output at
     all) without failing the build.
   - `zip -qr "$BITRISE_DEPLOY_DIR/paparazzi-failures.zip" app/build/paparazzi/failures`: zips
     Paparazzi's own HTML failure-report directory as a fallback browsable artifact. The comment
     explicitly calls out that `deploy-to-bitrise-io` **silently drops plain-copied directories** —
     only zipped files (or files matched by `custom-test-results-export`) actually show up on the
     Artifacts tab, which is why this is zipped rather than `cp -r`'d.
5. **`custom-test-results-export@2.0.0`** (`is_always_run: true`) — "Export test results to Test
   Reports." Searches `base_path: $BITRISE_SOURCE_DIR/apps/android/test-results` with
   `search_pattern: "*/paparazzi.xml"`, and exports a Tests-tab tab named `Paparazzi snapshots`
   (`test_name`). This is the generic/manual export route because Paparazzi has no native Bitrise step
   that uploads to Test Reports on its own.
6. **`save-gradle-cache@1.6.2`** — same as 4.1.
7. **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`) — uploads `paparazzi-failures.zip` and
   sends the exported test results.

**Pitfall note**: step 5's `search_pattern: "*/paparazzi.xml"` requires the merged file to sit at
exactly one directory level under `base_path` (i.e. `test-results/paparazzi.xml` matches the `*/`
prefix only if there's an intermediate folder — worth double-checking this pattern actually matches a
file placed directly in `test-results/` with no subfolder; if it doesn't, the Tests tab would silently
show no Paparazzi results even though step 4 ran fine).

### 4.3 `android_record_snapshots` (manual helper)

> Summary: Manual helper. Records Paparazzi snapshots on CI so you can download and commit them.

1. **`git-clone@8.5.2`**.
2. **`gradle-runner@6.0.0`** — same official Step as §4.2 step 3, task
   `:app:recordPaparazziDebug` this time, same `build_root_directory`, filters left at their
   defaults (see §4.2 step 3's note on why not `""`).
   `recordPaparazziDebug` is Paparazzi's recording task — it (re)writes the reference/golden images
   instead of verifying against them.
3. **`script@1.2.1`**, titled *"Zip recorded snapshots"*:
   ```bash
   set -eo pipefail
   cd app/src/test && zip -r "$BITRISE_DEPLOY_DIR/paparazzi-snapshots.zip" snapshots
   ```
   Zips the resulting `app/src/test/snapshots` directory so a human can download it from the
   Artifacts tab, extract it locally, and commit the updated golden images into the repo. Split out
   from the Gradle invocation above (which used to be one combined script) since there's no official
   Step for an arbitrary `zip` call.
4. **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`) — uploads `paparazzi-snapshots.zip`.

No `restore-gradle-cache`/`save-gradle-cache` here — reasonable for an infrequent manual workflow,
though it does mean every run re-downloads Gradle dependencies from scratch.

### 4.4 `android_ui_tests`

> Summary: Compose UI tests (instrumented) on an Android emulator, with the whole run's screen
> recording attached to a synthetic test case in the Tests tab. Switched from the native
> `android-instrumented-test` Step to a Gradle script + the generic export route, so the recording can
> be wrapped around the run and attached by filename convention.

`meta.bitrise.io`: stack `ubuntu-noble-24.04-bitrise-2025-android`, `machine_type_id: g2.linux.large`
(explicit override — "the emulator needs more RAM").

1. **`git-clone@8.5.2`**.
2. **`restore-gradle-cache@3.1.2`**.
3. **`bundle::android_avd_create`** (comment: "boots in the background while we build") — the Step
   bundle defined in the [`bitrise/common.yml`](../bitrise/common.yml) (see
   [`docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) §7), wrapping `avd-manager@2.2.0` with
   `profile: pixel_6`, `api_level: "34"`, `tag: google_apis`, `abi: x86_64`. Per StepLib, Android
   emulators cannot run on Apple Silicon machines — consistent with this workflow's Linux
   (`ubuntu-noble...`) stack. By default the step disables animations and waits for boot itself, but
   this workflow still runs a separate `wait-for-android-emulator` step next (belt-and-braces /
   explicit boot gate before tests start) — not folded into the bundle, since other workflows using
   the same bundle need to run different Steps between AVD creation and the boot wait (see
   `docs/BITRISE_CONCEPTS.md` §7).
4. **`wait-for-android-emulator@1.0.10`** — "Wait for Android emulator." Confirms the emulator (serial
   from `$BITRISE_EMULATOR_SERIAL`, exported by `avd-manager`) has finished booting before proceeding;
   no inputs overridden (uses the default serial/timeout/SDK path).
5. **`script@1.2.1`**, titled *"Start screen recording"*:
   ```
   content: $BITRISE_SOURCE_DIR/scripts/recording/start-android.sh /sdcard/bitrise-recordings ui-tests
   ```
   Calls [`scripts/recording/start-android.sh`](../scripts/recording/start-android.sh) with
   `device-dir=/sdcard/bitrise-recordings`, `basename=ui-tests`. The script honors `$RECORD_VIDEO`
   (exits immediately, doing nothing, if `off`); otherwise it backgrounds a loop that repeatedly calls
   `adb shell screenrecord --bit-rate 2000000 <device-dir>/ui-tests_chunk<N>.mp4`, writing the looping
   process's PID to `/tmp/bitrise-android-recording.pid` so `stop-android.sh` can find and kill it
   later. The loop exists because Android's `screenrecord` self-terminates after ~180 seconds.
6. **`gradle-runner@6.0.0`** — same official Step as §4.2 step 3 and §4.3 step 2, task
   `:app:connectedDebugAndroidTest`, filters left at their defaults (this task builds no new
   APK/AAB either, same reasoning as §4.2 step 3). Runs the instrumented Compose UI test suite
   (`CounterScreenUiTest.kt`) against the
   emulator started in step 3. No `is_always_run`, so a test failure here will mark the
   step/workflow failed — but every step after this one is `is_always_run: true` so
   recording/results still get collected.
7. **`script@1.2.1`**, titled *"Stop screen recording"* (`is_always_run: true`):
   ```bash
   SCREENSHOT="$($BITRISE_SOURCE_DIR/scripts/recording/screenshot-android.sh \
     $BITRISE_SOURCE_DIR/recordings/ui-tests-final.png)"
   [ -n "$SCREENSHOT" ] && echo "Took a final-state screenshot: $SCREENSHOT"
   $BITRISE_SOURCE_DIR/scripts/recording/stop-android.sh /sdcard/bitrise-recordings $BITRISE_SOURCE_DIR/recordings
   ```
   First takes one final `adb exec-out screencap` screenshot of the emulator's current screen via
   [`screenshot-android.sh`](../scripts/recording/screenshot-android.sh) (never fails the build; prints
   the output path on success or an empty string on failure). Then calls
   [`stop-android.sh`](../scripts/recording/stop-android.sh), which: kills the background loop PID from
   the pidfile, sends `SIGINT` (never `-9`, which would corrupt the mp4 container) to the in-flight
   `screenrecord` child so it finalizes its file, sleeps 2s, removes the pidfile, then `adb pull`s the
   whole `/sdcard/bitrise-recordings` device directory down to `$BITRISE_SOURCE_DIR/recordings` locally
   and deletes the device-side copy. Recording problems are only ever logged as warnings — this step
   must never fail the build over a flaky recording.
8. **`script@1.2.1`**, titled *"Merge JUnit XML and attach the recording"* (`is_always_run: true`),
   `working_dir: $BITRISE_SOURCE_DIR/apps/android`:
   ```bash
   set -eo pipefail
   mkdir -p test-results
   npx --yes junit-report-merger test-results/instrumented.xml \
     "app/build/outputs/androidTest-results/connected/**/TEST-*.xml"
   if [ -s "$BITRISE_SOURCE_DIR/recordings/ui-tests-final.png" ]; then
     python3 "$BITRISE_SOURCE_DIR/scripts/reporting/attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/instrumented.xml \
       --classname io.bitrise.sample.counter.CounterScreenUiTest \
       --media "$BITRISE_SOURCE_DIR/recordings/ui-tests-final.png" \
       --label screenshot --always \
       --dest-dir test-results
   fi
   RECORDING="$("$BITRISE_SOURCE_DIR/scripts/recording/concat-chunks.sh" \
     "$BITRISE_SOURCE_DIR/recordings/bitrise-recordings/ui-tests_chunk*.mp4" \
     "$BITRISE_SOURCE_DIR/recordings/ui-tests_combined.mp4")"
   if [ -n "$RECORDING" ]; then
     python3 "$BITRISE_SOURCE_DIR/scripts/reporting/attach_media_to_junit.py" add-recording-testcase \
       --junit-xml test-results/instrumented.xml \
       --classname io.bitrise.sample.counter.CounterScreenUiTest \
       --media "$RECORDING" \
       --dest-dir test-results
   else
     echo "No recording found, exporting test results without a video attachment."
   fi
   ```
   - Merges the instrumented test run's per-class JUnit XMLs (`androidTest-results/connected/**/TEST-*.xml`)
     into one `test-results/instrumented.xml`.
   - If the final screenshot exists and is non-empty, calls
     [`attach_media_to_junit.py add-recording-testcase`](../scripts/reporting/attach_media_to_junit.py)
     with `--label screenshot --always`: `--always` means this attaches regardless of `$RECORD_VIDEO`
     (cheap artifact, unconditional), adding a synthetic passing `<testcase>` named
     `io.bitrise.sample.counter.CounterScreenUiTest#zz_session_recording` (the script's default
     `--name`) to the first `<testsuite>` if one doesn't already exist, and copying the PNG into
     `test-results/` using the `<classname>__<name>__<label>.<ext>` naming convention.
   - Concatenates all `ui-tests_chunk*.mp4` files pulled off-device via
     [`concat-chunks.sh`](../scripts/recording/concat-chunks.sh) into one combined `.mp4` (via
     `ffmpeg concat`, falling back to the first chunk with a warning if `ffmpeg` is unavailable or
     concatenation fails, or printing nothing if no chunks exist).
   - If a combined recording was produced, attaches it the same way (no `--always` this time, so it's
     gated by `$RECORD_VIDEO`: `attach_media_to_junit.py`'s `add-recording-testcase` only keeps/attaches
     the video when `RECORD_VIDEO=all`, or when `RECORD_VIDEO=failures` **and** the merged JUnit XML
     shows at least one failure/error; `off` skips entirely). Both calls target the *same* synthetic
     testcase name, so the idempotent "skip if testcase already exists" check in the script means only
     the first call (the screenshot) actually creates the `<testcase>` element — the video call reuses
     it and just adds its own file into `test-results/`.
9. **`custom-test-results-export@2.0.0`** (`is_always_run: true`) — `test_name: Compose UI tests
   (Android)`, `base_path: $BITRISE_SOURCE_DIR/apps/android/test-results`,
   `search_pattern: "*/instrumented.xml"`. Exports the merged+attachment-augmented JUnit file to its
   own Tests-tab tab.
10. **`save-gradle-cache@1.6.2`**.
11. **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`).

**Why the generic export route instead of the native step**: the workflow's own summary explains the
native `android-instrumented-test` step was deliberately replaced by this Gradle-script + generic-export
combination specifically so the suite-level screen recording could be wrapped around the whole test run
and attached via the synthetic-testcase convention — the native step doesn't give that hook. See
[`../docs/test-recording-plan.md`](../docs/test-recording-plan.md).

### 4.5 `android-espresso-vdt` (manual-trigger only)

> Summary: Runs the existing Espresso/Compose UI tests (`CounterScreenUiTest.kt`, same tests as
> `android_ui_tests`) through Bitrise's Virtual Device Testing add-on (Firebase Test Lab) instead of a
> local emulator. `android_ui_tests` is untouched.

`meta.bitrise.io`: stack `ubuntu-noble-24.04-bitrise-2025-android`, `machine_type_id: g2.linux.medium`.

1. **`git-clone@8.5.2`**.
2. **`restore-gradle-cache@3.1.2`**.
3. **`android-build-for-ui-testing@1.0.0`** — "Android Build for UI Testing." Builds both the app APK
   and its matching instrumentation-test APK via Gradle (e.g. `:app:assembleDebug` +
   `:app:assembleDebugAndroidTest`). Inputs: `project_location:
   $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: debug`. Exports
   `$BITRISE_APK_PATH`/`$BITRISE_TEST_APK_PATH` (consumed by the next step).
4. **`virtual-device-testing-for-android@1.3.6`** — "Virtual Device Testing for Android." Uploads the
   two APKs to Firebase Test Lab (via Bitrise's VDT add-on proxy) and runs instrumentation tests on
   real/virtual cloud devices. Inputs: `test_type: instrumentation`, `app_path: $BITRISE_APK_PATH`,
   `test_apk_path: $BITRISE_TEST_APK_PATH`, `test_devices: $VDT_DEVICE_LIST` (defaults to
   `SmallPhone.arm,30,en,portrait` from the root `bitrise.yml`, "one cheap device by default to keep
   VDT cost low"), `download_test_results: "true"` (pulls the device-run results/artifacts back into
   the build so they can be deployed). Auth is handled internally by the step via the add-on-provisioned
   `$ADDON_VDTESTING_API_TOKEN` — no explicit Firebase/GCP service account input is set.
5. **`save-gradle-cache@1.6.2`**.
6. **`deploy-to-bitrise-io@2.26.2`** (`is_always_run: true`).

Per the workflow's own comment, this requires the Virtual Device Testing add-on to be enabled on the
Bitrise app (dashboard → app → Add-ons); the YAML comment states the add-on has been enabled and a run
verified passing.

## 5. Video recording

For the instrumented-UI workflow (`android_ui_tests`), video is captured **host-side**, not from inside
the test process: `adb shell screenrecord` is invoked from the Bitrise build machine against the
connected emulator, not by the instrumented test code itself. Per
[`docs/new-test-scenarios-plan.md`](../docs/test-recording-plan.md) ("Decisions made along the way",
item 3), a per-test, in-process recording via `screenrecord` was attempted first but **instrumented
test code cannot exec `screenrecord` itself — SELinux blocks it from an app-process UID**. The fallback
is the suite-level, host-side loop seen in §4.4 (steps 5–8): `start-android.sh` loops `adb shell
screenrecord` chunks (working around the ~180s per-invocation cap) for the whole run, `stop-android.sh`
cleanly interrupts and pulls the chunks locally, and `concat-chunks.sh` stitches multi-chunk runs into
one `.mp4` with `ffmpeg`.

Because this is a suite-level recording rather than a true per-test-case one, it's attached using the
**synthetic testcase trick**: `attach_media_to_junit.py`'s `add-recording-testcase` mode (see §4.4 step
8) injects a fake passing `<testcase classname="io.bitrise.sample.counter.CounterScreenUiTest"
name="zz_session_recording">` into the merged JUnit XML (only if one doesn't already exist, making the
script idempotent across its two invocations in the same step) and copies the media file into the
export directory using the `<classname>__<name>__<label>.<ext>` attachment-naming convention so
`custom-test-results-export` → `deploy-to-bitrise-io` attach it to that synthetic test case on the Tests
tab. A final-state screenshot (via `screenshot-android.sh`) is attached unconditionally (`--always`);
the combined video is attached according to `$RECORD_VIDEO` (see §6).

`android-espresso-vdt` (Virtual Device Testing) does not use any of this custom recording machinery —
Firebase Test Lab records video automatically for instrumentation runs; `download_test_results: "true"`
is what pulls that (and other result artifacts) back into the Bitrise build.

## 6. Test reporting

| Workflow | Report format | Written to | Export route | Why |
|---|---|---|---|---|
| `android_unit_tests` | JUnit XML (Gradle's own `testDebugUnitTest` output) | `app/build/test-results/testDebugUnitTest/` | **native** `android-unit-test@1.3.0` (auto-exports) | The native step already understands Gradle's unit-test output and the attachment convention; no generic export step needed. |
| `android_snapshot_tests` | JUnit XML, merged from Paparazzi's per-class test output, plus per-test-case PNGs | `apps/android/test-results/paparazzi.xml` + flattened PNGs | **generic** `custom-test-results-export@2.0.0` | Paparazzi has no Bitrise-native step that uploads to Test Reports; the YAML explicitly merges/prepares files for this manual route. |
| `android_record_snapshots` | n/a (not a test workflow) | — | — | Just a zip artifact of new golden images. |
| `android_ui_tests` | JUnit XML, merged from the instrumented-test run, plus a synthetic recording testcase | `apps/android/test-results/instrumented.xml` | **generic** `custom-test-results-export@2.0.0` (switched off the native `android-instrumented-test` step, per the workflow's own summary comment) | Needed because the native instrumented-test step doesn't give a hook for wrapping a whole-suite video recording around the run; the manual route lets the script control exactly which files end up where before export. |
| `android-espresso-vdt` | Firebase Test Lab's own result format, downloaded via `download_test_results: "true"` | wherever `virtual-device-testing-for-android` stages it | the step's own export path (no `custom-test-results-export` call in this workflow) | The VDT step handles Test Reports integration itself when `download_test_results` is enabled. |

`deploy-to-bitrise-io@2.26.2` is the step in every workflow that actually ships results from
`$BITRISE_DEPLOY_DIR`/the Bitrise CLI's test-result directory to the build's **Tests** and
**Artifacts** tabs; `custom-test-results-export` only prepares/stages data for it.

## 7. Run it locally

```bash
cd apps/android

# Unit tests (same as android_unit_tests)
./gradlew :app:testDebugUnitTest

# Paparazzi snapshot verification (same as android_snapshot_tests)
./gradlew :app:verifyPaparazziDebug

# Re-record Paparazzi golden images (same as android_record_snapshots)
./gradlew :app:recordPaparazziDebug

# Instrumented Compose UI tests — needs a running emulator/device first
# (e.g. `avdmanager`/Android Studio AVD, API 34, google_apis, x86_64 to match CI)
./gradlew :app:connectedDebugAndroidTest

# Build the APK + test APK for VDT-style instrumentation testing
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
```

With the [Bitrise CLI](https://github.com/bitrise-io/bitrise) installed and a local `bitrise.yml`
context (run from the repo root, since `android.yml` is `include`d from the root config):

```bash
bitrise run android_unit_tests
bitrise run android_snapshot_tests
bitrise run android_ui_tests        # needs an emulator available locally too
```

Screen recording and attachment scripts (`scripts/recording/*.sh`, `attach_media_to_junit.py`) are
plain shell/Python and can also be exercised directly against a locally running emulator with `adb`
available on `PATH`.

## 8. Adapting this to your own project

Minimal set to copy for a similar native Android app:

- `restore-gradle-cache` / `save-gradle-cache` pair, and `android-unit-test` for JVM unit tests — works
  unmodified for any Gradle Android project; just change `project_location`/`module`/`variant`.
- For Paparazzi: add the `app.cash.paparazzi` Gradle plugin, copy
  [`BitrisePaparazzi.kt`](../apps/android/app/src/test/java/io/bitrise/sample/counter/BitrisePaparazzi.kt)'s
  `BitriseSnapshotHandler` pattern (naming each rendered frame per the attachment convention) and the
  `verifyPaparazziDebug`/`recordPaparazziDebug` `gradle-runner` steps + `custom-test-results-export`
  wiring.
- For instrumented UI tests with video: copy the `bundle::android_avd_create` Step bundle +
  `wait-for-android-emulator` steps (update the bundle's `avd_profile`/`avd_api_level`/`avd_tag`/
  `avd_abi` inputs to match your target device/API, or just inline `avd-manager` yourself if you'd
  rather not pull in the shared bundle), the three
  `scripts/recording/*.sh` scripts (platform-agnostic beyond the `adb`/Android assumptions),
  [`attach_media_to_junit.py`](../scripts/reporting/attach_media_to_junit.py) (fully generic — only
  needs a `--classname`/`--name` matching your test suite), and the merge/export steps — update
  `--classname io.bitrise.sample.counter.CounterScreenUiTest` to your own test class, and the Gradle
  task name (`connectedDebugAndroidTest`) and output glob to your module/variant.
- For VDT: enable the add-on, copy `android-build-for-ui-testing` +
  `virtual-device-testing-for-android`, set your own `VDT_DEVICE_LIST`.

What must change for a different app: `project_location`/`module` (if not `app`), `applicationId`/
`namespace` (`io.bitrise.sample.counter` here), the instrumented test class's fully-qualified name used
in the `--classname` argument, the AVD `profile`/`api_level`/`tag`/`abi` to match your `minSdk`/
`targetSdk`, and `VDT_DEVICE_LIST` to the device matrix you actually want to pay for.

## 9. Troubleshooting / known issues

- **On-device screen recording is impossible from instrumented test code**: SELinux blocks
  `screenrecord` from an app-process UID, which is why recording had to move to a host-side,
  suite-level `adb shell screenrecord` loop wrapped around the whole test run instead of a per-test
  recording triggered by the test code itself (see §5 and `docs/test-recording-plan.md`).
- **`deploy-to-bitrise-io`'s directory-deploy mode silently drops plain `cp -r`'d directories** — only
  zipped files, or files matched by `custom-test-results-export`'s own attachment-matching, actually
  show up on the Artifacts/Tests tabs. The YAML comment in `android_snapshot_tests` calls this out
  explicitly and is why `paparazzi-failures.zip` is zipped rather than copied; per
  `docs/new-test-scenarios-plan.md` this same bug was independently rediscovered and fixed four times
  across different platforms in this repo, suggesting it's an easy trap to fall back into if this
  pattern is copied without the surrounding comment.
- **`RECORD_VIDEO=all` override via the trigger API was unreliable** — per
  `docs/new-test-scenarios-plan.md`, triggering `android_ui_tests` with a build-time `RECORD_VIDEO=all`
  override through the programmatic `trigger_bitrise_build` API did not actually take effect in
  testing; overriding it via the Bitrise UI's "Start build" env-var field is the documented workaround.
  This means CI-triggered builds with a non-default `RECORD_VIDEO` cannot currently be fully automated
  through that API path.
- **The "something failed → video attached" path is unverified for Android instrumented UI tests**: per
  `docs/new-test-scenarios-plan.md`'s "What's genuinely unverified" section, every live run of
  `android_ui_tests` so far has had passing tests, so only the "nothing failed → correctly skip
  attaching" branch of `attach_media_to_junit.py`'s `$RECORD_VIDEO=failures` gating has been exercised
  live for this workflow (as opposed to the script's own unit tests, which do construct a
  failing-testcase fixture).
- **`custom-test-results-export`'s `search_pattern: "*/paparazzi.xml"` requires an intermediate path
  segment** — worth confirming this glob actually matches `apps/android/test-results/paparazzi.xml`
  (written directly under `test-results/`, with no extra subdirectory) given the pattern's leading
  `*/`; if the Step's glob semantics don't treat that as "any prefix including none," the Paparazzi
  Tests-tab tab could end up silently empty even on a successful merge.
- **`android_record_snapshots` has no Gradle cache steps** — every run downloads dependencies from
  scratch. Likely an acceptable tradeoff for an infrequent manual workflow, but worth noting as an
  asymmetry versus the other workflows.
- **`android-espresso-vdt`'s device list override is manual-only** — `VDT_DEVICE_LIST` must be changed
  in the Bitrise UI per the inline comment; there is no mechanism in the YAML itself to vary the device
  matrix per trigger/branch.
- **Two parallel instrumented-UI-test implementations exist on purpose** (`android_ui_tests` vs.
  `android-espresso-vdt`) — both run the exact same `CounterScreenUiTest.kt` suite, by design, to
  demonstrate the local-emulator vs. Virtual Device Testing trade-off; this isn't a bug, but a reader
  diffing the two workflows should know the duplication is intentional, not drift.
