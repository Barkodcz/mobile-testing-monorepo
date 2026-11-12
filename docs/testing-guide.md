# Testing & CI guide

A complete reference for how testing works in this repo: what runs where, how results get to
Bitrise's **Tests** tab, how screenshots/videos get attached, and every on/off switch available.

For the project history of *why* things are built this way (the debugging process, the
decisions made, what's verified vs. not), see [`test-recording-plan.md`](./test-recording-plan.md).
This doc is the reference for *how to use/operate* the system as it stands today.

---

## 1. The big picture

```
bitrise.yml                  <- root: include list, app-level envs, the "everything_fast" pipeline
├── bitrise/ios.yml          <- iOS: unit, snapshot, XCUITest (x2 approaches)
├── bitrise/android.yml      <- Android: unit, Paparazzi snapshot, instrumented UI
├── bitrise/react-native.yml <- Jest, Detox E2E (iOS)
├── bitrise/flutter.yml      <- unit/widget/golden, integration_test, Patrol
└── bitrise/e2e.yml          <- Maestro (Android emulator), Appium (BrowserStack)

scripts/
├── recording/                <- shell scripts: start/stop screen recording, screenshots
│   ├── start-android.sh
│   ├── stop-android.sh
│   ├── screenshot-android.sh
│   ├── concat-chunks.sh
│   ├── start-ios-sim.sh
│   └── stop-ios-sim.sh
└── reporting/
    └── attach_media_to_junit.py   <- attaches a file to a JUnit XML test case
```

Every workflow ends the same way: run the tests → collect/convert results to JUnit XML →
(optionally) attach screenshots/video to the right test case → `custom-test-results-export`
(or a native step) → `deploy-to-bitrise-io`. That last step is what actually populates the
**Tests** tab — without it nothing shows up there, regardless of what ran before it.

### Two independent systems

1. **Test Reports** — every suite's pass/fail/skip results show up in the Tests tab. This part
   is unconditional; it always runs.
2. **Recording** — screenshots and videos attached to test cases. This part is gated by the
   `RECORD_VIDEO` env var (see §3) and by what each framework actually supports.

---

## 2. Test reporting: native vs. generic route

Bitrise has two ways a workflow's results reach the Tests tab:

| Route | How it works | Used by |
|---|---|---|
| **Native** | An official Bitrise Step (`xcode-test`, `android-unit-test`, `maestro-test`, `flutter-test`) exports results on its own. You just need `deploy-to-bitrise-io` afterward. | `ios_unit_tests`, `android_unit_tests`, `maestro_android` |
| **Generic** | The test runner writes JUnit XML (via the framework's own reporter — jest-junit, `tojunit`, pytest's `--junitxml`, xcpretty's `--report junit`), then `custom-test-results-export` picks it up. | Everything else in this repo |

**Why so much of this repo uses the generic route even where a native Step exists:**
`android_ui_tests` and `flutter_tests` were *switched* from native Steps to the generic route
specifically so a screenshot/video could be attached to an exact test case — the native Steps'
internal result directories aren't something you can drop extra files into predictably. See
§5 for the reasoning per suite.

### The attachment-matching mechanism (the core trick this whole system relies on)

Both `custom-test-results-export@2.0.0+` and `deploy-to-bitrise-io@2.26.0+` scan the test
result directory for files matching this filename pattern:

```
<classname>__<name>[__run<k>]__<label>.<ext>
```

Example: `io.bitrise.sample.counter.CounterScreenUiTest__startsAtZero__screenshot.png`

If a file like that exists **in the same directory as the JUnit XML**, and the `<classname>` +
`<name>` match a real `<testcase classname="..." name="...">` entry in that XML, Bitrise
attaches it to that test case automatically — no special config, no manual linking. This is
the single mechanism every screenshot/video in this repo relies on.

**Rules that matter in practice:**
- Characters `" * / : < > ? \ |` in the classname/name get replaced with `_` (both when writing
  files and when Bitrise matches them) — handled by every script here via the same `clean()`
  function.
- Allowed file extensions: `.jpg .jpeg .png .txt .log .mp4 .webm .ogg` — **not `.mov`**. Every
  iOS recording gets converted `.mov` → `.mp4` via `ffmpeg` for exactly this reason.
- The file must sit **directly in the export step's `base_path`**, not in a subdirectory.
  Several bugs in this repo's history came from writing attachments one level too deep.

### The recurring gotcha: `cp -r` vs `zip`

`deploy-to-bitrise-io`'s directory-deploy mode (used for plain build artifacts, not Tests-tab
attachments) only picks up **files**, not directories copied in with `cp -r` — it silently
drops them with no error, just "No deployment files were defined" in the log. This bug was
independently hit and fixed for Detox, Patrol, Appium, and Paparazzi in this repo's history.
**Rule going forward: always `zip` a directory before depositing it in `$BITRISE_DEPLOY_DIR`,
never `cp -r`.**

---

## 3. Recording: the `RECORD_VIDEO` switch

Set in `bitrise.yml`:
```yaml
app:
  envs:
  - RECORD_VIDEO: failures   # all | failures | off
```

| Value | Effect |
|---|---|
| `all` | Keep every recording/attachment, pass or fail. |
| `failures` (default) | Keep the recording only if something in the suite failed. Screenshots are **not** gated by this (see below). |
| `off` | Don't record at all (saves time/disk; the test still runs normally). |

**How each framework maps this:**

| Framework | Mechanism |
|---|---|
| Detox | `--record-videos` CLI flag set to Detox's own `all`/`failing`/`none` modes, translated from `$RECORD_VIDEO` in a `case` statement in `rn_detox_ios` |
| Patrol | `screenshot_on_failure: true` in `pubspec.yaml` (always on, not tied to `$RECORD_VIDEO` — screenshots are cheap) |
| Android UI tests, Flutter `integration_test`, Flutter Patrol (video), Maestro, iOS (both approaches) | `attach_media_to_junit.py`'s own `$RECORD_VIDEO` read (see §6) decides whether to keep a suite-level recording, based on whether the JUnit XML it's about to attach to shows any failures |
| Appium | Read directly in `conftest.py`'s `driver` fixture: video is only base64-decoded and saved if `RECORD_VIDEO == "all"` or the specific test failed |

**Screenshots are intentionally NOT gated by `RECORD_VIDEO=failures`.** The explicit goal for
this repo is "as many screenshots as possible," so every screenshot-attaching call passes
`--always` to `attach_media_to_junit.py`, which bypasses the failure-gating entirely. Only
*video* (the more expensive artifact) respects `all`/`failures`/`off`.

### How to actually override it for one build

Setting it in `bitrise.yml` changes it for everyone. To override for a single build, **use the
Bitrise UI's "Start build" → environment variable override field** — in testing this session,
passing a custom `environments` value through the trigger API did *not* reliably override the
app-level env var, so don't rely on that path; the UI field is the known-working way.

---

## 4. The attachment script: `scripts/reporting/attach_media_to_junit.py`

One Python script, four subcommands, used throughout every workflow:

### `add-recording-testcase`
For a **suite-level** recording/screenshot (one video or image covering the whole run, not a
specific test). Adds a synthetic `<testcase>` (named `zz_session_recording` by default) to the
first `<testsuite>` in the XML if one doesn't already exist, and copies the media file in next
to it using the naming convention.

```bash
python3 scripts/reporting/attach_media_to_junit.py add-recording-testcase \
  --junit-xml test-results/instrumented.xml \
  --classname io.bitrise.sample.counter.CounterScreenUiTest \
  --name zz_session_recording \
  --media /path/to/recording.mp4 \
  --label video \
  --dest-dir test-results \
  [--always]
```
- Without `--always`: respects `$RECORD_VIDEO` — skipped entirely if `off`, skipped if
  `failures` and nothing in the suite failed.
- With `--always`: always attaches (used for screenshots).

### `rename`
For an existing **real** testcase whose classname/name you already know (e.g. Patrol's native
screenshots, where the folder structure already tells you exactly which test a screenshot
belongs to). Just copies the file in with the right name — doesn't touch the XML at all.

```bash
python3 scripts/reporting/attach_media_to_junit.py rename \
  --classname "io.bitrise.sample.counter_flutter.MainActivityTest" \
  --name "runDartTest[counter_patrol_test counter keeps its value after going to the home screen]" \
  --media patrol_test/screenshots/.../1794497159305_after_increment.png \
  --label after_increment \
  --dest-dir test-results \
  [--run 2]
```
`--run` is for attaching a *different* attempt's recording when a test was retried (appends
`__run2`, `__run3`, etc. to the filename) — not currently used anywhere in this repo but
supported.

### `attach-to-first-failure`
For a file that only exists *because* something failed (a golden-test diff image) when you
don't know in advance which test will fail or what its JUnit-reported name will be. Scans the
XML for the first `<failure>`/`<error>`, and attaches there. No-op if nothing failed.

```bash
python3 scripts/reporting/attach_media_to_junit.py attach-to-first-failure \
  --junit-xml test-results/flutter.xml \
  --media test/goldens/failures/counter_screen_actual.png \
  --label golden_diff \
  --dest-dir test-results
```

### Properties of the script worth knowing
- **Never fails the build.** Every code path catches its own exceptions and prints a `WARN`
  instead of raising — a broken attachment should never break a test run.
- **Idempotent**: re-running `add-recording-testcase` with the same classname/name won't add a
  second synthetic testcase, just updates/adds the attachment file.
- Pure standard library (no pip installs needed) — works on every stack in this repo (Linux,
  macOS) without setup.

---

## 5. Per-suite reference

### Android

| Workflow | What it tests | Trigger | Reporting | Screenshots/video |
|---|---|---|---|---|
| `android_unit_tests` | JVM JUnit tests | push/PR touching `apps/android/**` | native (`android-unit-test@1`) | n/a (no UI) |
| `android_snapshot_tests` | Paparazzi screenshot diffing vs. committed baselines | same | generic | Every rendered frame is attached via `BitrisePaparazzi.kt`'s `BitriseSnapshotHandler`, named per convention, **regardless of pass/fail** (it's a render, not a failure-only diff) |
| `android_record_snapshots` | **Manual only.** Records new Paparazzi baselines for you to download/commit | manual | — | produces `paparazzi-snapshots.zip` artifact |
| `android_ui_tests` | Instrumented Compose UI tests on a real emulator | push/PR touching `apps/android/**` | generic (switched from native, see §2) | Suite-level video (`adb shell screenrecord`) + a final-state screenshot (`adb screencap`), both attached to a synthetic `zz_session_recording` testcase |

Paparazzi internals: `apps/android/app/src/test/java/.../BitrisePaparazzi.kt` wraps the
standard `Paparazzi` JUnit rule; `app/build.gradle.kts` re-enables real-JDK access for unit test
compilation (needed for `ImageIO`) and points each `Test` task's output at
`build/bitrise-snapshots/<task-name>/`.

Android UI test recording is host-side only: instrumented test code running on-device can't
`exec()` the `screenrecord` binary itself (SELinux blocks it from an app-process UID), so there
is no way to get a recording scoped to a single `@Test` method — it's always the whole run.

### iOS

| Workflow | What it tests | Trigger | Reporting | Screenshots/video |
|---|---|---|---|---|
| `ios_unit_tests` | Swift Testing unit tests + swift-snapshot-testing | push/PR touching `apps/ios/**` | native (`xcode-test@6`) | automatic via `.xcresult` (XCTest's own captured attachments) |
| `ios_ui_tests` | XCUITest, **Approach A** | same | native (`xcode-test@6`), simulator pre-booted by us | Video recorded via `simctl`, but only deployable as a plain **Artifacts-tab** file (`ios-ui-tests-recording.mp4`) — xcresult's attachment matching doesn't cover externally recorded files |
| `ios_ui_tests_manual` | Same tests, **Approach B** | **manual only** | generic (`xcodebuild test` + `xcpretty`) | Real Tests-tab video attachment, since we control the JUnit XML directly |

**Why two iOS UI test workflows exist:** `xcode-test@6` owns the simulator's entire lifecycle
internally, so wrapping an external recorder around it (Approach A) can only ever produce a
loose artifact. Getting a true Tests-tab attachment requires giving up the native Step entirely
and driving `xcodebuild` by hand (Approach B). Both are kept as a deliberate side-by-side
demonstration of the trade-off — Approach A runs on every push (simpler, cheaper); Approach B
is manual-trigger only so it doesn't double every push's macOS minutes.

### React Native

| Workflow | What it tests | Trigger | Reporting | Screenshots/video |
|---|---|---|---|---|
| `rn_jest_tests` | Jest unit/component tests | push/PR touching `apps/react-native/**` | generic (jest-junit) | n/a (no UI) |
| `rn_detox_ios` | Detox E2E on iOS simulator | same, `depends_on: [rn_jest_tests]` | generic (Detox's own jest-junit reporter) | Per-test screenshots **and** video, named by `apps/react-native/e2e/bitrisePathBuilder.js` to match jest-junit's own naming |

Detox config: `apps/react-native/.detoxrc.js` sets `artifacts.rootDir: './test-results'` (must
be co-located with `detox-junit.xml`, since attachment matching only scans the export step's
`base_path`) and `artifacts.pathBuilder` pointing at `bitrisePathBuilder.js`.

### Flutter

| Workflow | What it tests | Trigger | Reporting | Screenshots/video |
|---|---|---|---|---|
| `flutter_tests` | Unit, widget, and golden (image-diff) tests | push/PR touching `apps/flutter/**` | generic (switched from native, see §2) | Golden-test diff image attached to whichever test actually failed, via `attach-to-first-failure` — no video (still-image diff, not a live screen) |
| `flutter_record_goldens` | **Manual only.** Records new golden baselines | manual | — | — |
| `flutter_integration_tests` | `integration_test` package on a real emulator, `depends_on: [flutter_tests]` | same | generic | Suite-level video + final-state screenshot, same mechanism as `android_ui_tests` |
| `flutter_patrol_android` | Patrol (Flutter + native interactions), `depends_on: [flutter_tests]` | same | generic | **Per-test** native screenshots (Patrol's own `$.takeNativeScreenshot()` calls, attached via `rename` since the folder structure already matches the JUnit testcase exactly) **plus** suite-level video |

Patrol screenshots are the richest in this repo: because Patrol itself knows which test it's
running when it saves a screenshot, the folder layout
(`patrol_test/screenshots/<classname>/<name>/<timestamp>_<label>.png`) already encodes the
exact classname/name needed — no guessing required, unlike the synthetic-testcase approach used
for `integration_test` and Android UI tests (which have no native per-test screenshot API).

### E2E (Maestro + Appium)

| Workflow | What it tests | Trigger | Reporting | Screenshots/video |
|---|---|---|---|---|
| `maestro_android` | Maestro flows against the native Android app | push (main)/PR touching `e2e/maestro/**` or `apps/android/**` | native (`maestro-test@1`) | **Fully automatic** — `startRecording`/`stopRecording` commands in the flow YAML, the Step attaches the resulting video + any `takeScreenshot:` calls to their test case on its own |
| `appium_browserstack` | Appium on real BrowserStack devices | push (main only — real devices cost money) touching `e2e/appium/**` or `apps/android/**` | generic (pytest `--junitxml`) | Per-test screenshot (always) + video (gated by `$RECORD_VIDEO`), both written directly by `conftest.py`'s `driver` fixture using the naming convention — **requires `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` secrets, not yet configured, so this workflow currently can't run at all** |

Maestro is the simplest case in the whole repo: the `maestro-test` Bitrise Step does
*everything* — running the flow, exporting JUnit, and attaching screenshots/videos — as long as
the flow file itself calls `startRecording`/`takeScreenshot`. No scripts, no Python, no
XML-editing needed.

---

## 6. Turning things on and off

| What | How |
|---|---|
| **Recording globally** | `RECORD_VIDEO: off` in `bitrise.yml`'s `app.envs` |
| **Recording for one build** | Bitrise UI → Start build → env var override (see §3's caveat about the trigger API) |
| **A whole workflow's auto-trigger** | Remove/comment its entry from the relevant `pipelines: <name>: workflows:` block, or narrow/remove its `triggers:` section, in the matching `bitrise/*.yml` |
| **Appium entirely** | Can't run until `BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY` are added as secrets on the app (Bitrise dashboard → App settings → Secrets) |
| **`ios_ui_tests_manual`** | Already manual-trigger only by design — nothing to turn off |
| **`android_record_snapshots` / `flutter_record_goldens`** | Already manual-trigger only — run from the Bitrise UI only when you need to re-baseline |
| **Flaky-test retry on Maestro** | `num_flaky_test_attempts: 1` on the `maestro-test@1` step in `bitrise/e2e.yml` — set to `0` to disable, or higher to allow more retries |
| **Which emulator/simulator profile** | `avd-manager@1`'s `profile`/`api_level`/`tag`/`abi` inputs (Android), or the `destination:` string on `xcode-test@6` / `xcodebuild` calls (iOS) |

---

## 7. Troubleshooting

**"My screenshot/video isn't showing up on the Tests tab."**
1. Check the step's log for `[attach]` lines — the script always prints why it skipped
   (`RECORD_VIDEO=off`, `RECORD_VIDEO=failures and the suite passed`, a `WARN` about a missing
   file, etc).
2. Confirm the file actually landed in the **same directory** as the JUnit XML passed to
   `custom-test-results-export`'s `base_path` — not a subdirectory.
3. Confirm the filename's `<classname>__<name>` segment exactly matches a real `<testcase>` in
   that XML (character-for-character, after the `clean()` substitution).
4. Confirm the extension is one of `.jpg .jpeg .png .txt .log .mp4 .webm .ogg` — `.mov` will
   never attach.

**"My build artifact zip is empty / missing."**
You're almost certainly hitting the `cp -r` vs `zip` issue from §2 — check whether the step
that produces it uses `cp -r` into `$BITRISE_DEPLOY_DIR` instead of `zip`.

**"A test is flaky."**
Only Maestro has retry wired up (`num_flaky_test_attempts`). Everywhere else, a flaky test will
simply fail the step — there's no blanket retry mechanism in this repo outside Maestro.

**"I want to see what a specific script does without running a full CI build."**
Every script in `scripts/recording/` and `scripts/reporting/` is a standalone shell/Python
script you can run locally (modulo having `adb`/`xcrun`/`ffmpeg` available) — see the `Usage:`
comment at the top of each file.
