# Test Reports + video recording plan

Every test suite in this monorepo reports into Bitrise's **Tests** tab, and every suite that
drives a real UI (emulator/simulator) attaches a screen recording to its test case there too.
This doc records the discovery pass, the decisions made, and the final status per project.

## Final status

| # | Project / suite | Reporting route | Attachment method | Recording status |
|---|---|---|---|---|
| 1 | `apps/android` unit (`CounterTest.kt`) | native (`android-unit-test@1`) | n/a | n/a — no UI |
| 2 | `apps/android` Paparazzi (`CounterScreenSnapshotTest.kt`) | generic (`custom-test-results-export`) | **implemented** — `BitrisePaparazzi.kt`'s `BitriseSnapshotHandler` writes each rendered frame as `<classname>__<name>__<label>.png` directly into the export dir; **verified live** (attached to `counterScreenDefault`'s passing run) | n/a — still-image diff, not a live screen. Also kept as a `paparazzi-failures.zip` artifact fallback |
| 3 | `apps/android` instrumented UI (`CounterScreenUiTest.kt`) | **switched to generic** (was native `android-instrumented-test@0`) so we control where the video lands | **implemented**, synthetic `zz_session_recording` testcase via `attach_media_to_junit.py add-recording-testcase`; **verified live** (correctly skipped attaching since `RECORD_VIDEO=failures` default + both tests passed) | **implemented** — suite-level `adb shell screenrecord` (host-side only; instrumented test code can't exec `screenrecord` itself, SELinux blocks it from an app-process UID) |
| 4 | `apps/ios` unit (Swift Testing) | native (`xcode-test@6`) | automatic via `.xcresult` | n/a — no UI |
| 5 | `apps/ios` snapshot (swift-snapshot-testing) | native (`xcode-test@6`) | automatic via `.xcresult` | n/a — still-image diff |
| 6 | `apps/ios` XCUITest (`CounterUITests.swift`) | **both approaches implemented as separate workflows** | Approach A: artifact only (xcresult doesn't match externally-recorded files). Approach B: real JUnit + attached video | **implemented, both verified live**: `ios_ui_tests` (Approach A, pre-booted sim + native step) produced `ios-ui-tests-recording.mp4` as a plain artifact; `ios_ui_tests_manual` (Approach B, manual `xcodebuild test` + `xcpretty`) ran clean with real JUnit output (no video attached since nothing failed, by design) |
| 7 | `apps/react-native` Jest | generic (`custom-test-results-export`) | n/a | n/a — no UI |
| 8 | `apps/react-native` Detox | generic (`custom-test-results-export`) | **implemented** — `bitrisePathBuilder.js` names every screenshot/video/log per convention; **verified live**: `initial_count.png`, `after_increment.png`, `after_reset.png` all attached to their test cases, plus Detox's own automatic `testStart`/`testDone` screenshots | **implemented** — `--record-videos` mapped from `$RECORD_VIDEO` to Detox's own `all/failing/none` modes; not yet seen a video attachment live (no failing run triggered) but the screenshot path proves the pathBuilder + attachment mechanism works end to end |
| 9 | `apps/flutter` unit/widget/golden | **switched to generic** (was native `flutter-test@1`) so a golden failure's diff image can be attached to its exact test case | **implemented** — `attach-to-first-failure` mode finds whichever testcase failed without needing to guess tojunit's naming scheme; **verified live** that the reporting pipeline itself is correct (same 7 tests, same names, as before the switch) | n/a — still-image diff |
| 10 | `apps/flutter` `integration_test` | generic (`custom-test-results-export`) | **implemented**, synthetic recording testcase, same mechanism as row 3; **verified live** (build passed, correctly attached nothing since nothing failed) | **implemented** — suite-level `adb shell screenrecord`, same scripts as row 3 |
| 11 | `apps/flutter` Patrol | generic (`custom-test-results-export`) | **implemented**, same mechanism as row 3; **verified live** | **implemented** — suite-level `adb shell screenrecord` |
| 12 | `e2e/maestro` | native (`maestro-test@1`) | **automatic**, Maestro's own `startRecording`/`stopRecording` + the Step's built-in attachment matching | **implemented and verified live** — every test case (including an actual failing retry attempt) has its `recording.mp4` attached |
| 13 | `e2e/appium` (BrowserStack) | generic (`custom-test-results-export`) | **implemented** — `driver.start_recording_screen()`/`stop_recording_screen()` in `conftest.py`, decoded straight to the filename convention; screenshot path also fixed (was writing to a nested dir that was never actually scanned for attachments) | **implemented, NOT verified** — blocked on missing `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` secrets (flagged earlier in this engagement) |

## What's genuinely unverified

- **Appium / BrowserStack (row 13)**: can't run at all without the two secrets. The code is
  written and locally reviewed but has never executed against a real BrowserStack session.
- **The actual "keep video on failure" branch**: every live build in this session had passing
  tests, so the `RECORD_VIDEO=failures` + *something failed* → *video attached* path was only
  exercised by Maestro (which had a real flaky failure) and by local unit tests of
  `attach_media_to_junit.py` (which explicitly construct a failing-testcase XML fixture and
  confirm the attachment gets added). Triggering `android_ui_tests` with a build-time
  `RECORD_VIDEO=all` override via the trigger API did not seem to actually override the
  app-level env var in testing — worth double-checking directly in the Bitrise UI ("Start
  build" → env var override field) rather than via API, next time this needs verifying.
- **Detox's own video recording** (as opposed to screenshots, which are verified): `--record-videos`
  is wired up and the screenshot path proves the underlying pathBuilder/attachment mechanism
  works, but no live build has actually produced and attached a Detox *video* yet.
- **Patrol/integration_test/Android UI test video attachment** when something actually fails:
  same caveat as above — the "nothing failed, correctly skip" path is verified; the "something
  failed, attach it" path is not, live.

## How to use

### Finding results and videos
Open a build on Bitrise → **Tests** tab. Each test case lists its attachments (screenshots,
logs, video) inline. For the two cases that can only produce a plain build artifact instead of
a true attachment (`ios_ui_tests`'s recording, and the `*-failures.zip` / `*-screenshots.zip`
fallbacks), check the **Artifacts** tab instead.

### Toggling recording
Set the `RECORD_VIDEO` env var — `all`, `failures` (default), or `off` — either in
`bitrise.yml`'s `app.envs`, or per build via **Start build** → env vars in the Bitrise UI (the
programmatic `trigger_bitrise_build` API's `environments` param did not reliably override it in
testing — use the UI field instead). Frameworks with a native keep-on-failure mode (Detox,
Patrol's screenshots) map directly to their own flag; everywhere else (Android/Flutter
suite-level recordings) the `attach_media_to_junit.py add-recording-testcase` logic decides
whether to keep the video based on whether the JUnit XML shows any failures.

### Known limitations
- **Android `screenrecord`'s ~180s cap**: `start-android.sh` loops in chunks to cover longer
  runs; `concat-chunks.sh` stitches them back together with `ffmpeg` if more than one chunk
  exists (falls back to the first chunk with a warning if `ffmpeg` isn't on the image).
- **Virtual Device Testing / Firebase Test Lab is not used anywhere in this repo** — all
  Android/iOS UI tests run on Bitrise-hosted emulators/simulators, so this doesn't apply here,
  but if it's added later: VDT records video automatically, don't add custom recording on top
  of it, and set `download_test_results: true` so it surfaces in the Tests tab.
  Also note VDT's own ~30 minute per-test cap if adopted.
- **Emulators need hardware acceleration**: Bitrise's hosted Android emulators already have it;
  this only matters if these workflows are ever run on self-hosted/bare-metal runners.
  `screenrecord` and `simctl recordVideo` both work fine without hardware-accelerated *video
  encode* specifically, but a slow/software-rendered emulator will produce a choppier capture.
  Not an issue encountered in this session's live runs.
  `.mov`→`.mp4` conversion: Bitrise Test Reports only accept `.mp4`/`.webm`/`.ogg`, not `.mov`;
  `stop-ios-sim.sh` always converts via `ffmpeg` and keeps the `.mov` (with a warning) only if
  `ffmpeg` isn't available or the conversion itself fails.
- **iOS has two parallel implementations on purpose**: `ios_ui_tests` (native Step, artifact-only
  video) runs on every push via the `ios` pipeline; `ios_ui_tests_manual` (manual `xcodebuild`,
  true Tests-tab video attachment) is manual-trigger only, to demonstrate the trade-off without
  doubling every push's macOS minutes.
- **No credentials ever appear in a recording**: none of these test suites display secrets,
  tokens, or credentials on screen (confirmed by reading every test file touched in this task —
  they're all driving a sample counter app's UI).

## Decisions made along the way

1. **iOS XCUITest**: implemented both approaches side by side rather than picking one (see row 6).
2. **Paparazzi**: implemented both the filename-convention attachment *and* kept the zip-artifact
   fallback, to show multiple techniques in this example repo.
3. **Espresso-style per-test video**: attempted, but instrumented test code can't actually exec
   `screenrecord` (SELinux blocks it from an app-process UID) — recording ended up suite-level,
   host-side, same as `integration_test`/Patrol, attached via a synthetic test case instead.
4. **Detox `pathBuilder`**: implemented and verified against the actual installed `detox@20.51.4`
   type definitions and Bitrise's documented example.
5. **Appium**: implemented in code per the task's instruction to verify later.

A recurring bug found and fixed **four separate times** across this session (Detox, Patrol,
Appium, and again here for Paparazzi/golden): `deploy-to-bitrise-io`'s directory-deploy mode
silently drops anything copied in with `cp -r` — only `zip`-ed files or files picked up by
`custom-test-results-export`'s own attachment-matching actually show up. Every "keep this as a
zip artifact" step in this repo now zips rather than copies.
