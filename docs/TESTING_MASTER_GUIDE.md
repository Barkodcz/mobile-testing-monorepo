# The Mobile Testing Monorepo — Master Reference Guide

A single, exhaustive reference for how CI testing is built in this repository: every
framework, every workflow, exactly what Bitrise shows for each one, how the
screenshot/video-attachment trick works under the hood, every bug that was hit and fixed
while building this, and a step-by-step playbook for reproducing this setup in a brand new
project.

This document intentionally overlaps with `testing-guide.md`, `test-recording-plan.md`, and
`new-test-scenarios-plan.md` in this same `docs/` folder — those are the "as it happened"
working notes; this one is the single consolidated reference meant to outlive this specific
repo and be reused as a template for the next one.

---

## Table of contents

1. [The big picture](#1-the-big-picture)
2. [The two systems Bitrise gives you](#2-the-two-systems-bitrise-gives-you)
3. [The attachment-naming trick (the one mechanism everything relies on)](#3-the-attachment-naming-trick)
4. [The `RECORD_VIDEO` switch](#4-the-record_video-switch)
5. [What you actually see in the Bitrise UI](#5-what-you-actually-see-in-the-bitrise-ui)
6. [Per-framework deep dive](#6-per-framework-deep-dive)
   - [6.1 Android](#61-android)
   - [6.2 iOS](#62-ios)
   - [6.3 React Native](#63-react-native)
   - [6.4 Flutter](#64-flutter)
   - [6.5 Cross-platform E2E: Maestro](#65-cross-platform-e2e-maestro)
   - [6.6 Cross-platform E2E: Appium](#66-cross-platform-e2e-appium)
   - [6.7 Sharded / parallel pipelines](#67-sharded--parallel-pipelines)
   - [6.8 Virtual Device Testing (Firebase Test Lab)](#68-virtual-device-testing-firebase-test-lab)
7. [Every bug found and fixed, and why](#7-every-bug-found-and-fixed-and-why)
8. [Secrets, add-ons, and manual setup steps](#8-secrets-add-ons-and-manual-setup-steps)
9. [How to reproduce this in a brand new project](#9-how-to-reproduce-this-in-a-brand-new-project)
10. [Reference tables](#10-reference-tables)

---

## 1. The big picture

```
bitrise.yml                  <- root: include list, app-level envs, pipeline wiring
├── bitrise/ios.yml          <- iOS: unit, snapshot, XCUITest (x2 approaches), fastlane,
│                               Maestro, Appium-local, sharded XCUITest pipeline
├── bitrise/android.yml      <- Android: unit, Paparazzi snapshot, instrumented UI, VDT
├── bitrise/react-native.yml <- Jest, Detox E2E (iOS), Maestro (Android+iOS)
├── bitrise/flutter.yml      <- unit/widget/golden, integration_test, Patrol
└── bitrise/e2e.yml          <- Maestro (Android, + sharded pipeline), Appium (BrowserStack
                                 + local emulator)

apps/
├── android/      <- native Kotlin/Compose counter app
├── ios/          <- native Swift/SwiftUI counter app (XcodeGen-generated project)
├── react-native/ <- React Native counter app (same UI, cross-platform)
└── flutter/      <- Flutter counter app (same UI, cross-platform)

e2e/
├── maestro/      <- Maestro flows against the native Android app
└── appium/       <- pytest + Appium, BrowserStack or local emulator/simulator

scripts/
├── recording/    <- shell scripts: start/stop screen recording, screenshots
│   ├── start-android.sh / stop-android.sh / screenshot-android.sh
│   ├── concat-chunks.sh
│   └── start-ios-sim.sh / stop-ios-sim.sh
└── reporting/
    └── attach_media_to_junit.py   <- the one script that attaches media to JUnit XML
```

**Every workflow ends the same way**: run the tests → collect/convert results to JUnit XML
→ (optionally) attach screenshots/video to the right test case → export to Bitrise (either
a native Step that does this itself, or `custom-test-results-export` + `deploy-to-bitrise-io`
for everything else). That last `deploy-to-bitrise-io` call is what actually populates the
**Tests** tab — without it, nothing shows up there no matter what ran before it.

The repo deliberately has **one native counter app per platform/framework** (Android,
iOS, React Native, Flutter) with **identical element IDs** across all four
(`count_label`, `decrement_button`, `increment_button`, `reset_button`, exposed as
`accessibilityIdentifier`/`testTag`/`testID`/`Key(...)` respectively), so the exact same E2E
journeys (Maestro flows, Appium tests) can be written once and reused with minimal
per-platform changes.

---

## 2. The two systems Bitrise gives you

It's critical to keep these two mentally separate — they are unrelated systems with
unrelated UI surfaces:

| | **Test Reports** (the **Tests** tab) | **Build Artifacts** (the **Artifacts** tab) |
|---|---|---|
| What it shows | Pass/fail/skip per test case, organized by suite/class, with inline attachments (screenshots, videos, logs) per test case | Flat files you explicitly deployed — zips, APKs, raw recordings, HTML reports |
| How a file gets there | The file must be **co-located with the JUnit XML** and named following the attachment convention (§3) before `custom-test-results-export` or a native Step runs, and `deploy-to-bitrise-io` is called afterward | Anything placed in `$BITRISE_DEPLOY_DIR`, as long as it's a real **file** (zipped if it started as a directory) |
| Example in this repo | A Patrol test's `after_increment.png`, attached directly to its test case | `patrol-screenshots.zip` — the same screenshots, but as one flat browsable archive, not linked to any specific test case |

**A file can be in neither, either, or both.** The two zip artifacts next to every
screenshot-producing workflow in this repo exist purely as a convenience "browse everything
at once" fallback — the real per-test-case story is always on the Tests tab.

### The two reporting *routes* into the Tests tab

| Route | How it works | Used by (in this repo) |
|---|---|---|
| **Native** | An official Bitrise Step (`xcode-test`, `android-unit-test`, `maestro-test`, `virtual-device-testing-for-android`) exports results on its own. You only need `deploy-to-bitrise-io` after it. | `ios_unit_tests`, `android_unit_tests`, `maestro_android` (and all Maestro variants), `android-espresso-vdt` |
| **Generic** | The test runner writes JUnit XML itself (via the framework's own reporter — jest-junit, `tojunit`, pytest's `--junitxml`, xcpretty's `--report junit`, AGP's instrumented-test XML), then `custom-test-results-export` picks it up. | Everything else |

**Why so much of this repo uses the generic route even where a native Step exists:**
`android_ui_tests` and `flutter_tests` were *switched* from native Steps to the generic route
specifically so a screenshot/video/diff-image could be attached to an exact test case — a
native Step's internal result directory isn't something you can reliably drop extra files
into. If you don't need custom attachments, prefer the native route — it's less code.

---

## 3. The attachment-naming trick

This is the single mechanism every screenshot/video in this entire repo relies on. Both
`custom-test-results-export@2.0.0+` and `deploy-to-bitrise-io@2.26.0+` scan the test-result
directory for files matching this filename pattern:

```
<classname>__<name>[__run<k>]__<label>.<ext>
```

Example: `io.bitrise.sample.counter.CounterScreenUiTest__startsAtZero__screenshot.png`

If a file like that exists **in the same directory as the JUnit XML**, and the
`<classname>` + `<name>` match a real `<testcase classname="..." name="...">` entry in that
XML, Bitrise attaches it to that test case automatically — **no special config, no manual
linking, no API call.**

Reference: https://docs.bitrise.io/en/bitrise-ci/testing/test-reports/test-attachments/naming-attachments-after-test-cases

### Rules that matter in practice

- **Character cleaning**: `" * / : < > ? \ |` in the classname/name get replaced with `_` —
  both when *writing* the attachment filename and when Bitrise *matches* it. Every script in
  this repo implements the exact same `clean()` function (see `attach_media_to_junit.py`,
  `BitrisePaparazzi.kt`, `bitrisePathBuilder.js`, `e2e/appium/conftest.py`) — if yours
  diverges even slightly, the match silently fails.
- **Allowed extensions**: `.jpg .jpeg .png .txt .log .mp4 .webm .ogg` — **not `.mov`**. Every
  iOS recording in this repo gets converted `.mov` → `.mp4` via `ffmpeg` for exactly this
  reason (see `scripts/recording/stop-ios-sim.sh`).
- **Flat directory only**: the attachment file must sit directly in the export step's
  `base_path`, not in a subdirectory. Several historical bugs in this repo came from writing
  attachments one level too deep.
- **Suite-level vs per-test attachments**: if the test framework already reports a real
  per-test JUnit entry and you know its exact classname+name (Patrol, Detox,
  jest-junit-backed suites), just copy the file in with the right name — no XML editing
  needed (`attach_media_to_junit.py rename` mode). If you only have *one* recording covering
  an entire suite (a host-side `adb shell screenrecord` wrapped around an instrumented test
  run, for example), you have to **synthesize** a passing testcase entry yourself so there's
  something to attach to (`attach_media_to_junit.py add-recording-testcase` mode, which adds
  a `zz_session_recording` testcase to the XML if one doesn't exist).
- **Golden/diff images**: when you don't know in advance *which* test will fail or what its
  JUnit name will be (a golden-test pixel diff), scan the XML for the first
  `<failure>`/`<error>` and attach there instead
  (`attach_media_to_junit.py attach-to-first-failure` mode). No-op if nothing failed.

### The `attach_media_to_junit.py` script

One Python script (pure standard library, no pip installs, works on Linux and macOS
unmodified), three subcommands, used throughout every workflow that needs custom
attachments:

```bash
# Suite-level recording, synthesize a testcase if needed
python3 scripts/reporting/attach_media_to_junit.py add-recording-testcase \
  --junit-xml test-results/instrumented.xml \
  --classname io.bitrise.sample.counter.CounterScreenUiTest \
  --name zz_session_recording \
  --media /path/to/recording.mp4 \
  --label video \
  --dest-dir test-results \
  [--always]          # bypass $RECORD_VIDEO gating entirely (used for screenshots)

# Attach to a real, already-known testcase (Patrol's native per-test screenshots)
python3 scripts/reporting/attach_media_to_junit.py rename \
  --classname "io.bitrise.sample.counter_flutter.MainActivityTest" \
  --name "runDartTest[... the exact test name ...]" \
  --media patrol_test/screenshots/.../1794497159305_after_increment.png \
  --label after_increment \
  --dest-dir test-results \
  [--run 2]            # for a retried attempt: appends __run2, __run3, ...

# Attach to whichever test failed, without knowing which in advance
python3 scripts/reporting/attach_media_to_junit.py attach-to-first-failure \
  --junit-xml test-results/flutter.xml \
  --media test/goldens/failures/counter_screen_actual.png \
  --label golden_diff \
  --dest-dir test-results
```

Properties worth copying into any new project's version of this script:
- **Never fails the build.** Every code path catches its own exceptions and prints a `WARN`
  instead of raising.
- **Idempotent.** Re-running `add-recording-testcase` with the same classname/name won't add
  a second synthetic testcase, just updates the attachment file.

### The recurring `cp -r` vs `zip` gotcha

`deploy-to-bitrise-io`'s directory-deploy mode (for plain build artifacts, not Tests-tab
attachments) only picks up **files**, not directories copied in with `cp -r` — it silently
drops them with no error, just `"No deployment files were defined"` in the log. This bug was
independently hit and fixed **four separate times** across this repo's build history (Detox,
Patrol, Appium, Paparazzi/golden). **Rule going forward: always `zip` a directory before
depositing it in `$BITRISE_DEPLOY_DIR`, never `cp -r`.**

---

## 4. The `RECORD_VIDEO` switch

One app-level env var, set once in `bitrise.yml`:

```yaml
app:
  envs:
  - RECORD_VIDEO: all   # all | failures | off
```

| Value | Effect |
|---|---|
| `all` | **Current default in this repo.** Keep every recording/attachment, pass or fail — the explicit goal here is to showcase as much recorded evidence as possible. |
| `failures` | Keep the recording only if something in the suite failed. (This was the original default; changed to `all` after confirming it was silently dropping video from every green run — see §7.) |
| `off` | Don't record at all (saves CI time/disk; the test still runs normally). |

**Screenshots are never gated by this at all** — every screenshot-attaching call passes
`--always` to `attach_media_to_junit.py`, bypassing the gate entirely, because screenshots
are cheap and the goal is more of them, not fewer. Only *video* (the more expensive artifact)
respects `all`/`failures`/`off`.

### How each framework maps the switch

| Framework | Mechanism |
|---|---|
| Detox | `--record-videos` CLI flag set to Detox's own `all`/`failing`/`none` modes, translated from `$RECORD_VIDEO` in a shell `case` statement |
| Patrol | `screenshot_on_failure: true` in `pubspec.yaml` (always on for screenshots, not tied to `$RECORD_VIDEO`) |
| Android UI tests, Flutter `integration_test`, Flutter Patrol (video), iOS (both approaches) | `attach_media_to_junit.py`'s own `$RECORD_VIDEO` read decides whether to keep a suite-level recording, based on whether the JUnit XML it's about to attach to shows any failures |
| Maestro | **Not gated at all** — Maestro's own `startRecording`/`stopRecording` flow commands always record, and the `maestro-test` Step always attaches the result |
| Appium | Read directly in `conftest.py`'s driver fixtures: video is only base64-decoded and saved if `RECORD_VIDEO == "all"` or the specific test failed |

### Overriding for one build

Setting `RECORD_VIDEO` in `bitrise.yml` changes it for everyone. To override for a single
build: **use the Bitrise UI's "Start build" → environment variable override field.** Passing
a custom `environments` value through the `trigger_bitrise_build` API did **not** reliably
override the app-level env var in testing during this project — the UI field is the
confirmed-working path.

---

## 5. What you actually see in the Bitrise UI

For a concrete, already-executed example, see `flutter_patrol_android` build #166 in this
app's history (triggered to verify the `RECORD_VIDEO: all` fix):

- **Tests tab** → `Patrol (Android)` suite → `io.bitrise.sample.counter_flutter.MainActivityTest`
  class → 3 test case rows:
  - `runDartTest[counter_patrol_test counter keeps its value after going to the home screen]`
    — status **passed**, 2 screenshot attachments (`after_increment.png`, `after_reset.png`)
    visible inline, click to view full-size.
  - `runDartTest[counter_patrol_test notification shade can be opened over the app]` —
    status **passed**, 1 screenshot attachment.
  - `zz_session_recording` (the synthetic testcase) — status **passed**, 1 **video**
    attachment (`.mp4`), playable inline in the browser.
- **Artifacts tab** → `patrol-screenshots.zip`, `patrol-html-report.zip` — same screenshots
  plus Patrol's own HTML report, as flat downloadable files, for browsing outside the
  per-test-case view.
- **Build log** → each step's own stdout, including `[attach]`/`[recording]`-prefixed lines
  explaining exactly what the attachment scripts decided and why (e.g.
  `[attach] RECORD_VIDEO=failures and the suite passed, not attaching the recording.`).

This same shape (Tests tab test cases with inline attachments + a couple of convenience zip
artifacts) repeats across every suite in this repo — Android, iOS, React Native, and
Flutter alike — just with different classnames/suite names.

---

## 6. Per-framework deep dive

### 6.1 Android

| Workflow | What it tests | Trigger | Reporting route | Screenshots/video |
|---|---|---|---|---|
| `android_unit_tests` | JVM JUnit tests (`CounterTest.kt`) via `testDebugUnitTest` | push/PR touching `apps/android/**` | native (`android-unit-test@1.3.0`) | n/a — no UI |
| `android_snapshot_tests` | Paparazzi screenshot diffing vs. committed baselines (`CounterScreenSnapshotTest.kt`) | same | generic | every rendered frame attached via `BitrisePaparazzi.kt`'s `BitriseSnapshotHandler`, **regardless of pass/fail** (it's a render, not a failure-only diff) |
| `android_record_snapshots` | **Manual only.** Records new Paparazzi baselines to download/commit | manual, not wired into any pipeline | — | produces a `paparazzi-snapshots.zip` artifact |
| `android_ui_tests` | Instrumented Compose UI tests (`CounterScreenUiTest.kt`) on a real emulator | push/PR touching `apps/android/**` | generic (switched from native, see §2) | suite-level video (`adb shell screenrecord`) + a final-state screenshot (`adb screencap`), both attached to a synthetic `zz_session_recording` testcase |
| `android-espresso-vdt` | Same Espresso/Compose UI tests as `android_ui_tests`, but run through **Virtual Device Testing** (Firebase Test Lab) instead of a local emulator | manual only | native (`virtual-device-testing-for-android`) | VDT records video automatically; see §6.8 |

**Setup pieces to copy into a new project:**
- `BitrisePaparazzi.kt` wraps the standard `Paparazzi` JUnit rule with a custom
  `SnapshotHandler` that writes each frame using the attachment-naming convention.
- `app/build.gradle.kts` needs: the Paparazzi Gradle plugin applied, `animationsDisabled =
  true` in `testOptions` (for stable UI tests), real-JDK access re-enabled for unit test
  compilation (`ImageIO`/`BufferedImage` aren't on the Kotlin JVM test classpath by default),
  and each `Test` task's snapshot output pointed at `build/bitrise-snapshots/<task-name>/`
  with the task name exposed as a system property — both read by `BitriseSnapshotHandler`.
- **Why recording is suite-level, not per-test, on Android instrumented tests**: the
  instrumented test code runs on-device and can't `exec()` the `screenrecord` binary itself
  — SELinux blocks it from an app-process UID. So recording always has to be host-side
  (`adb shell screenrecord` from the CI runner), covering the whole run, attached via a
  synthetic testcase rather than to each real one.

### 6.2 iOS

| Workflow | What it tests | Trigger | Reporting route | Screenshots/video |
|---|---|---|---|---|
| `ios_unit_tests` | Swift Testing unit tests (`CounterTests.swift`) + classic XCTest (`CounterXCTests.swift`, same target/scheme, proving the two frameworks coexist) + swift-snapshot-testing (`CounterSnapshotTests.swift`) | push/PR touching `apps/ios/**` | native (`xcode-test@6.6.1`) | automatic via `.xcresult` (XCTest's own captured attachments) |
| `ios_ui_tests` | XCUITest (`CounterUITests.swift`), **Approach A** | same | native (`xcode-test@6.6.1`), simulator pre-booted by us | Video recorded via `simctl`, but only deployable as a plain **Artifacts-tab** file — xcresult's attachment matching doesn't cover externally-recorded files |
| `ios_ui_tests_manual` | Same tests, **Approach B** | manual only | generic (`xcodebuild test` + `xcpretty`) | Real Tests-tab video attachment, since we control the JUnit XML directly |
| `ios-fastlane-scan` | Same `CounterApp-UI` scheme, run via fastlane's `scan` — a third way to run the same tests | manual only | generic (`scan`'s own `output_types: junit`) | Real Tests-tab video attachment, same mechanism as Approach B |
| `ios-maestro-e2e` | Maestro flows (`apps/ios/maestro/`) against the native app | manual only | native (`maestro-test@1.2.0`) | fully automatic, same as Android Maestro |
| `ios-appium-local` | Appium (XCUITest driver) against a local simulator + local Appium server (`e2e/appium/tests/test_counter_ios.py`) | manual only | generic (pytest `--junitxml`) | per-test screenshot (always) + video (gated by `$RECORD_VIDEO`) |
| `ios_xcuitest_sharded` (pipeline) | `CounterApp-UI`'s 2 test methods, sharded across N parallel workflows | manual pipeline start | native, one `deploy-to-bitrise-io` per shard | each shard its own Tests tab entry |

**Why two iOS UI-test approaches exist side by side:** `xcode-test@6` owns the simulator's
entire lifecycle internally, so wrapping an external recorder around it (Approach A) can only
ever produce a loose artifact — xcresult only auto-attaches files the test process captured
*through XCTest's own API*, not files recorded from outside it. Getting a true Tests-tab
attachment requires giving up the native Step entirely and driving `xcodebuild` by hand
(Approach B). Both are kept deliberately: Approach A runs on every push (simpler, cheaper, no
JUnit plumbing to maintain); Approach B is manual-trigger only, to demonstrate the trade-off
without doubling every push's macOS minutes. `ios-fastlane-scan` is a third variant of
Approach B's idea (full control, real video attachment) via a different tool (`fastlane
scan` instead of raw `xcodebuild`).

**Setup pieces to copy into a new project:**
- **Build for simulator the right way.** `xcode-build-for-simulator`'s `xcodebuild archive`
  action tags its output for the iOS **device** platform regardless of `-destination`/`-sdk`
  flags passed to it (confirmed live, repeatedly, in this repo's history) — `simctl install`
  then refuses it. Use a raw `xcodebuild build -sdk iphonesimulator ...` script instead;
  export the built `.app`'s path manually via `envman` for downstream steps.
- **Ad-hoc codesign the built app.** `xcode-build-for-simulator`/raw `xcodebuild build` both
  leave `CODE_SIGNING_ALLOWED=NO`. `xcodebuild test`'s own harness tolerates an unsigned app,
  but a bare `simctl launch` (what Maestro and Appium do) is denied by SpringBoard on iOS
  18.x+ simulators — `codesign --force --deep --sign - "$APP_PATH"` fixes it.
- **Boot the simulator and wait for it properly.** `xcrun simctl boot "<device>"` returns
  before SpringBoard is actually ready to accept launches; follow it with `xcrun simctl
  bootstatus "<device>" -b` to actually wait.
- **Appium needs `appium:isHeadless=true`** when attaching to an already-booted simulator by
  `udid` on a headless CI Mac — otherwise it tries to bring the Simulator.app GUI to the
  foreground itself, which can fail if that binary isn't where Appium expects it on your
  Xcode stack. The simulator doesn't need the GUI app running at all for `simctl`-driven
  interaction/recording — every other simctl-based workflow in this repo (XCUITest, Maestro,
  fastlane scan) proves that.
- **Use Bitrise's stack-provided default simulator name**, not a hardcoded model (`"iPhone
  16"`) — annual device-lineup changes and Xcode stack upgrades both break literal model
  names. `"Bitrise iOS default"` is guaranteed present on every `osx-xcode-*` stack.

### 6.3 React Native

| Workflow | What it tests | Trigger | Reporting route | Screenshots/video |
|---|---|---|---|---|
| `rn_jest_tests` | Jest unit/component tests | push/PR touching `apps/react-native/**` | generic (jest-junit) | n/a — no UI |
| `rn_detox_ios` | Detox E2E on an iOS simulator (Release build), `depends_on: [rn_jest_tests]` | same | generic (Detox's own jest-junit reporter) | per-test screenshots **and** video, named by `bitrisePathBuilder.js` to match jest-junit's own naming |
| `android-maestro-e2e-rn` | Maestro flows against the RN app's **Android** build | manual only | native (`maestro-test@1.2.0`) | fully automatic |
| `ios-maestro-e2e-rn` | Same Maestro flows against the RN app's **iOS** build | manual only | native (`maestro-test@1.2.0`) | fully automatic |

**Setup pieces to copy into a new project:**
- **Detox config** (`.detoxrc.js`): `artifacts.rootDir` must be the **same directory**
  jest-junit writes `detox-junit.xml` to, since attachment matching only scans the export
  step's `base_path`. `artifacts.pathBuilder` points at a custom path builder
  (`bitrisePathBuilder.js`) that names every screenshot/video/log per the attachment
  convention — built from the same `testSummary.fullName`/`title` jest-junit itself uses, so
  the names line up exactly.
- **Build Release, not Debug, for anything driven externally** (Maestro, Appium, a bare
  `xcodebuild build`/Gradle assemble outside the RN CLI). Debug builds need the Metro bundler
  running to render anything — a debug APK/simulator build in this repo's history showed
  neither the counter label nor the buttons until switched to Release, which embeds the JS
  bundle.
- **One flow folder, two platforms, via env var substitution.** Since the counter apps share
  element IDs, one set of Maestro flow files covers both Android and iOS RN builds — but the
  `appId` differs per platform. `maestro test` has **no `--app-id` CLI flag** (confirmed live:
  `Unknown option: '--app-id'`) — the correct pattern is to parameterize the flow file's
  `appId:` field as `${MAESTRO_APP_ID}` and supply the value per-workflow via `maestro test -e
  MAESTRO_APP_ID=<platform appId>` (the Bitrise Step's `additional_args` input).

### 6.4 Flutter

| Workflow | What it tests | Trigger | Reporting route | Screenshots/video |
|---|---|---|---|---|
| `flutter_tests` | Unit, widget, and golden (image-diff) tests | push/PR touching `apps/flutter/**` | generic (switched from native, see §2) | golden-test diff image attached to whichever test actually failed, via `attach-to-first-failure` — no video, it's a still-image diff |
| `flutter_record_goldens` | **Manual only.** Records new golden baselines | manual, not wired into any pipeline | — | — |
| `flutter_integration_tests` | `integration_test` package on a real emulator, `depends_on: [flutter_tests]` | same | generic | suite-level video + final-state screenshot, same mechanism as `android_ui_tests` |
| `flutter_patrol_android` | Patrol (Flutter + native interactions), `depends_on: [flutter_tests]` | same | generic | **per-test** native screenshots (Patrol's own `$.takeNativeScreenshot()` calls) **plus** suite-level video |

**Patrol has the richest screenshots in this repo**: because Patrol itself knows which test
it's running when it saves a screenshot, the folder layout it produces —
`patrol_test/screenshots/<classname>/<name>/<timestamp>_<label>.png` — already encodes the
exact classname/name needed, no guessing required (unlike the synthetic-testcase approach
needed for `integration_test` and Android UI tests, which have no native per-test screenshot
API).

**Setup pieces to copy into a new project:**
- `pubspec.yaml`: `patrol: ^4.10.0` + a `patrol:` config block with `app_name`,
  `test_directory: patrol_test`, and `screenshot_on_failure: true` (needs `patrol_cli
  4.8.0+` and `patrol 4.10.0+` together — pin both).
- The golden test's "Attach golden diff image" script step must run with `is_always_run:
  true` so it fires even when `flutter test` itself failed.
- **A subtle `set -e` + pipe bug to avoid**: don't wrap `flutter test | tojunit` with
  `set -eo pipefail` if a failing test run needs to still produce a JUnit XML — `-e` aborts
  the script the moment `flutter test`'s piped exit code is non-zero, before `tojunit` ever
  gets to convert the JSON, so a failing suite silently produces *no* JUnit XML at all. Use
  `set -o pipefail` alone (no `-e`) for that specific line.

### 6.5 Cross-platform E2E: Maestro

| Workflow | Platform/app | Trigger | Notes |
|---|---|---|---|
| `maestro_android` | native Android app | push/PR touching `apps/android/**` or `e2e/maestro/**` | the simplest, most automatic workflow in the whole repo |
| `ios-maestro-e2e` | native iOS app | manual only | ports of the Android flows into `apps/ios/maestro/` |
| `android-maestro-e2e-rn` / `ios-maestro-e2e-rn` | React Native app, both platforms | manual only | shared flow files, `appId` parameterized (see §6.3) |
| `android-maestro-shard-*` (pipeline) | native Android app | manual pipeline start | sharded across N parallel workflows, see §6.7 |

**Maestro is the simplest case in this whole repo**: the `maestro-test` Bitrise Step does
*everything* — running the flow, exporting JUnit, and attaching screenshots/videos — as long
as the flow file itself calls `startRecording`/`takeScreenshot`. No custom scripts, no
Python, no XML-editing needed. If you're bootstrapping E2E testing for a new app from
scratch and don't have a specific reason to need Appium, **start with Maestro** — it needs
the least custom plumbing by far.

A minimal flow file:
```yaml
appId: com.example.myapp
name: Increments and resets
---
- startRecording: recording
- launchApp:
    clearState: true
- assertVisible: "Count: 0"
- tapOn:
    id: "increment_button"
- assertVisible: "Count: 1"
- takeScreenshot: after_increment
- tapOn:
    id: "reset_button"
- assertVisible: "Count: 0"
- stopRecording
```

A minimal Bitrise step invocation:
```yaml
- maestro-test@1.2.0:
    inputs:
    - app_path: $BITRISE_APK_PATH   # or $BITRISE_APP_DIR_PATH on iOS
    - flow_path: $BITRISE_SOURCE_DIR/e2e/maestro
    - test_name: Maestro E2E
    - maestro_version: 2.12.1
    - num_flaky_test_attempts: 1    # the only built-in retry mechanism anywhere in this repo
```

### 6.6 Cross-platform E2E: Appium

| Workflow | Target | Trigger | Notes |
|---|---|---|---|
| `appium_browserstack` | real BrowserStack devices, Android | push (main only — real devices cost money) | **needs `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` secrets** — without them this workflow cannot run at all |
| `android-appium-local` | local AVD + local Appium server | manual only | reuses the exact same test file as BrowserStack via an `APPIUM_TARGET=local` switch |
| `ios-appium-local` | local simulator + local Appium server | manual only | separate test file/fixture (`ios_driver`), same conventions |

**Setup pieces to copy into a new project:**
- `conftest.py` pattern: one pytest fixture per target (`driver` for Android, switching
  internally on `APPIUM_TARGET`; `ios_driver` for iOS), each handling its own
  start/stop-recording and per-test screenshot, writing directly into the same
  `<classname>__<name>__<label>.<ext>` convention so `custom-test-results-export` picks them
  up with zero extra attachment code.
- **BrowserStack-vs-local as an additive branch, not a fork.** `APPIUM_TARGET` defaults to
  `browserstack` so the existing behavior is preserved byte-for-byte; the `local` branch is
  purely additive (points `webdriver.Remote` at `http://localhost:4723` instead of
  BrowserStack's hub, skips the `bstack:options`/session-status calls).
- **A local Appium server needs Node**, regardless of whether your test client is Python —
  Appium's server itself is Node-based. `npm install -g appium@<pinned> && appium driver
  install <uiautomator2|xcuitest>@<pinned>`, run in the background, poll `/wd/hub/status`
  until it's up before running tests against it.
- **For iOS specifically**: capture the *exact* UDID of the simulator you already booted (via
  `xcrun simctl list devices booted -j`) and pass it to Appium as `appium:udid`, instead of
  letting Appium re-resolve a device by `platformVersion` — a hardcoded OS version drifts
  across Xcode stack upgrades and breaks ("`'18.0' does not exist in the list of simctl
  SDKs`"). Also set `appium:isHeadless=true` (see §6.2's iOS setup notes).

### 6.7 Sharded / parallel pipelines

Two sharding demonstrations exist, both using **Bitrise pipeline intermediate files** to
build once and fan out to parallel workflows that each report their own Tests tab entry:

**`ios_xcuitest_sharded`** (`bitrise/ios.yml`):
1. `ios-xcuitest-shard-build` — `xcode-build-for-test@3.6.0` produces the `.xctestrun`/test
   bundle, shared downstream as a pipeline intermediate file.
2. `ios-xcuitest-shard-calc` — `xcode-test-shard-calculation@0.2.1` reads the bundle, computes
   N shards.
3. `ios-xcuitest-shard-1`, `ios-xcuitest-shard-2`, ... — each pulls the intermediate files,
   runs `xcode-test-without-building@1.0.1` with its shard's `Test Selection` input, each with
   its own `deploy-to-bitrise-io`.

**Two sharp edges hit live, worth remembering for any future sharded pipeline:**
- `xcode-test-shard-calculation`'s `product_path` input wants the **`.xctestrun` file**
  specifically (formats: `xctestrun`/`xctestproducts`), not the raw test bundle directory.
- **Pipeline intermediate files break relative paths inside the thing you're passing.** The
  `.xctestrun` file lives *inside* the test bundle directory and references the built `.app`
  via a path relative to that directory. If you list the `.xctestrun` file and the bundle
  directory as two *separate* pipeline intermediate files, `pull-intermediate-files` extracts
  them into two different, isolated directories downstream — breaking that relative
  reference. **Fix: pass only the containing directory through the pipeline, and
  re-`find` the file you need inside it at each downstream stage.**

**`android_maestro_sharded`** (`bitrise/e2e.yml`):
1. `android-maestro-shard-build` — `./gradlew :app:assembleDebug` once, APK shared via
   pipeline intermediate files.
2. `android-maestro-shard-1/2/3` — each assigns itself a subset of flow files by round-robin
   (`ls e2e/maestro/*.yaml | sort | awk 'NR % SHARD_COUNT == <index>'`), then runs
   `maestro-test@1` against only its assigned files, with a distinct `test_name` so each shows
   up as a separate Tests tab entry.

**One more sharp edge, worth remembering for any shell-based sharding script:** `ls
nonexistent-glob | wc -l` inside a `$(...)` with `set -e -o pipefail` aborts the whole script
when a shard legitimately has zero matching files — `ls` exits non-zero on no match, and
`pipefail` propagates that even though the downstream `wc -l` itself would have succeeded.
**Use `find`, which doesn't error on zero matches, and gate the actual test step on the
resulting count via `run_if` instead of letting it fail outright.**

### 6.8 Virtual Device Testing (Firebase Test Lab)

`android-espresso-vdt` (`bitrise/android.yml`) runs the exact same Espresso/Compose UI tests
as `android_ui_tests`, but through Bitrise's **Virtual Device Testing** add-on (which wraps
Firebase Test Lab) instead of a Bitrise-hosted local emulator.

```yaml
- android-build-for-ui-testing@1.0.0:
    inputs:
    - project_location: $BITRISE_SOURCE_DIR/apps/android
    - module: app
    - variant: debug
- virtual-device-testing-for-android@1.3.6:
    inputs:
    - test_type: instrumentation
    - app_path: $BITRISE_APK_PATH
    - test_apk_path: $BITRISE_TEST_APK_PATH
    - test_devices: $VDT_DEVICE_LIST    # e.g. "SmallPhone.arm,30,en,portrait"
    - download_test_results: "true"
```

**No Firebase/GCP service account is needed.** `virtual-device-testing-for-android`'s
`api_token` input already defaults to `$ADDON_VDTESTING_API_TOKEN`, which Bitrise
auto-provisions the moment the **Virtual Device Testing add-on** is enabled on the app
(Bitrise dashboard → app → Add-ons). This was initially assumed to be a Firebase-credential
blocker and corrected after actually checking the Step's inputs via `step_inputs` — don't
assume a Step needs an external credential without checking its actual input defaults first.
Confirmed working end-to-end in this repo once the add-on was enabled.

VDT records video **automatically** — don't layer this repo's custom `adb
screenrecord`-based recording on top of it. Also note VDT's own ~30 minute per-test cap if
you adopt it for a real (non-toy) app's test suite.

---

## 7. Every bug found and fixed, and why

In rough chronological order across this repo's build history — useful both as a changelog
and as a "things that will probably bite you too" list for a new project:

1. **`deploy-to-bitrise-io`'s `cp -r` vs `zip` gap** (hit 4 separate times: Detox, Patrol,
   Appium, Paparazzi). See §3.
2. **Hardcoded `"iPhone 16"` simulator name** broke across an Xcode stack upgrade — switched
   every destination string, `simctl boot`/`bootstatus` call, UDID lookup, and Appium default
   device name to Bitrise's stack-provided `"Bitrise iOS default"`.
3. **`xcode-build-for-simulator`'s `xcodebuild archive` mistags its output for the device
   platform**, not the simulator, regardless of `-destination`/`-sdk` flags — `simctl install`
   then refuses it (`"has code for platforms: [iOS, arm64]... device can run:
   iOS-simulator"`). `archive` is fundamentally a device-distribution action in Xcode; it
   doesn't reliably resolve to simulator no matter what flags you pass. **Fixed by building
   directly with a raw `xcodebuild build -sdk iphonesimulator` script** instead of the Step,
   in every workflow that feeds a built `.app` to Maestro/Appium.
4. **Unsigned-app launch denial.** `xcode-build-for-simulator`/raw `xcodebuild build` leave
   `CODE_SIGNING_ALLOWED=NO`. `xcodebuild test`'s own harness tolerates this (it does the
   launching itself), but a bare `simctl launch` (Maestro, Appium) was denied by SpringBoard
   on iOS 18.x+ simulators for an unsigned app — surfaced as two *different*, misleading
   error messages depending on the tool: Maestro's `SBMainWorkspace`/
   `FBSOpenApplicationServiceErrorDomain`, Appium's `"Simulator architecture is not
   supported"`. Both were actually the same root cause. **Fixed with ad-hoc codesigning**
   (`codesign --force --deep --sign - "$APP_PATH"`). Earlier attempts that did *not* fix it,
   for the record: pinning `ARCHS`/`EXCLUDED_ARCHS` in `project.yml` (plausible but wrong —
   this was never actually an architecture mismatch), `open -a Simulator` to force the GUI
   process up (unnecessary once codesigning was the actual fix).
5. **`simctl boot` returns before SpringBoard is actually ready** — a race that intermittently
   caused the same launch-denial symptom even with everything else fixed. **Fixed** by
   following boot with `xcrun simctl bootstatus "<device>" -b`, which actually blocks until
   ready.
6. **`ios-appium-local`'s hardcoded `platform_version` default (`"18.0"`)** didn't match any
   simulator SDK actually installed on a given stack. **Fixed** by capturing the exact UDID of
   the simulator CI had already booted and built into, and attaching Appium to it directly by
   `udid` instead of re-resolving by version.
7. **`xcode-test-shard-calculation`'s `product_path` input wants the `.xctestrun` file**, not
   the raw test bundle directory — see §6.7.
8. **Pipeline intermediate files breaking a relative path inside the thing being passed** —
   see §6.7.
9. **Sharding script abort on zero matches** (`ls | wc -l` + `pipefail`) — see §6.7.
10. **Classic RN Metro-bundler gotcha**: a Debug build (Android Gradle or iOS
    `xcode-build-for-simulator`) showed no UI at all under Maestro/Appium, because Debug needs
    Metro running to render anything. **Fixed by building Release**, which embeds the JS
    bundle.
11. **`maestro test` has no `--app-id` CLI flag.** An attempt to override the RN flow files'
    Android-default `appId` at runtime via `additional_args: --app-id <ios bundle id>` failed
    live with `"Unknown option: '--app-id'"`. **Fixed** by parameterizing `appId:` in the flow
    files themselves as `${MAESTRO_APP_ID}` and passing the actual value per-workflow via
    `maestro test -e MAESTRO_APP_ID=<value>` (still through `additional_args`, just the
    correct flag this time).
12. **Appium trying to open the Simulator.app GUI itself and failing** on a stack where that
    binary wasn't where Appium expected it (`"Got an unexpected error while opening Simulator
    UI: .../Simulator.app does not exist"`) — this surfaced specifically after an Xcode
    16.4 → 27.2 stack upgrade. **Fixed** by setting `appium:isHeadless=true` on the
    `XCUITestOptions` capabilities: the simulator is already booted headlessly via `simctl`
    beforehand (same as every other simctl-driven workflow in this repo), so Appium doesn't
    need to, and shouldn't try to, bring up a GUI window itself.
13. **`RECORD_VIDEO: failures` (the original default) was silently dropping every passing
    run's video** — confirmed live: a `flutter_patrol_android` run with 0 failures logged
    `"RECORD_VIDEO=failures and the suite passed, not attaching the recording"` and genuinely
    had zero video attachments on the Tests tab, only screenshots. Since this repo's explicit
    goal is to showcase as much recorded evidence as possible, **the default was changed to
    `RECORD_VIDEO: all`** — a single app-level env var, so one change fixed every gated
    framework at once (Detox, Patrol, Android UI tests, Flutter `integration_test`, iOS both
    approaches, Appium) with no per-workflow script edits needed. Re-verified live
    afterward: the same `flutter_patrol_android` workflow, run again with no code changes
    other than the env var, produced a real `zz_session_recording` video attachment on a
    still-100%-passing run.
14. **A VDT-add-on credential assumption that turned out to be wrong.** It was initially
    assumed `virtual-device-testing-for-android` needed a Firebase/GCP service account JSON
    as a Bitrise secret, mirroring the BrowserStack pattern. Checking the Step's actual inputs
    via `step_inputs` showed `api_token` already defaults to `$ADDON_VDTESTING_API_TOKEN`,
    auto-provisioned the moment the Virtual Device Testing add-on is enabled — no separate
    credential needed. **Lesson: check a Step's actual input defaults before assuming it needs
    an external credential.**

---

## 8. Secrets, add-ons, and manual setup steps

| What | Where | Status in this repo |
|---|---|---|
| `BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY` | Bitrise dashboard → App settings → Secrets | **Still missing** — `appium_browserstack` cannot run at all without these |
| Virtual Device Testing add-on | Bitrise dashboard → App → Add-ons | **Enabled and verified** — `android-espresso-vdt` runs successfully |
| `RECORD_VIDEO` override for a single build | Bitrise dashboard → Start build → env var override field | Use this, not the trigger API's `environments` param (unreliable, confirmed in testing) |

Toggle points for anything else:

| What | How |
|---|---|
| Recording globally | `RECORD_VIDEO` in `bitrise.yml`'s `app.envs` |
| A whole workflow's auto-trigger | Remove/comment its entry from the relevant `pipelines: <name>: workflows:` block, or narrow/remove its `triggers:` section, in the matching `bitrise/*.yml` |
| Flaky-test retry on Maestro | `num_flaky_test_attempts` on the `maestro-test@1` step — `0` disables it, higher allows more retries. The **only** built-in retry mechanism in this entire repo; everywhere else a flaky test simply fails the step. |
| Which emulator/simulator profile | `avd-manager`'s `profile`/`api_level`/`tag`/`abi` inputs (Android), or the `destination:` string on `xcode-test`/raw `xcodebuild` calls (iOS) |

---

## 9. How to reproduce this in a brand new project

A condensed playbook, in the order that minimizes wasted work:

1. **Pick one UI framework's testing stack and get the native route working first**
   (`xcode-test`/`android-unit-test` + `deploy-to-bitrise-io`, nothing custom). Confirm the
   Tests tab populates at all before adding any custom attachment logic on top.
2. **Write (or port) `attach_media_to_junit.py`** (§3) before touching any specific
   framework — every other piece depends on it. Keep its three modes
   (`add-recording-testcase`, `rename`, `attach-to-first-failure`) and its "never fails the
   build" property.
3. **Start E2E with Maestro, not Appium**, if you have no existing reason to need Appium
   specifically. It needs the least custom code by a wide margin (§6.5) — you get automatic
   video + screenshot attachment for free, with zero lines of attachment script.
4. **Give every platform's app the same element IDs/test tags for the same UI elements.**
   This is what let this repo write one set of Maestro flows and reuse them across Android,
   iOS, and the RN build with only an `appId` swap.
5. **Add screenshot/video recording per framework**, cheapest first: anything with a native
   screenshot API (Patrol-style) before anything needing a synthetic testcase (Android/Flutter
   instrumented tests, which need the suite-level host-side `adb screenrecord` + synthesized
   XML entry trick).
6. **Decide your `RECORD_VIDEO` default up front** based on what you actually want to
   showcase/keep — `all` if the point is maximum visible evidence (as in this repo), `failures`
   if you're optimizing for CI minutes/storage on a real, frequently-green project.
7. **Pin every Step and CLI version explicitly** (`@<exact version>`, not `@1` floating-major)
   — check `step_inputs` for the exact input names before bumping a major version, since
   inputs do get renamed/removed across majors.
8. **If/when you add sharding or multi-stage pipelines**, read §6.7 first — the pipeline
   intermediate-files relative-path trap and the shard-calculation input-format trap are easy
   to lose an hour to otherwise.
9. **Budget for at least one simulator/emulator-launch-denial-style bug on iOS** the first
   time you wire up Maestro/Appium against a *built* (not Xcode-test-harness-launched) app —
   codesigning and boot-readiness races (§7, items 3-5) are close to guaranteed on any
   sufficiently new iOS simulator version.
10. **Re-verify live after every stack upgrade**, not just after your own code changes.
    Several of the bugs in §7 were purely Xcode/stack-upgrade fallout (hardcoded simulator
    names, the archive-vs-build platform tagging, the Simulator.app-GUI path) that had nothing
    to do with any change to this repo's own code.

---

## 10. Reference tables

### Pinned step/tool versions (as of this repo's latest upgrade pass)

| Step/tool | Version |
|---|---|
| `xcode-test` | 6.6.1 |
| `android-unit-test` | 1.3.0 |
| `avd-manager` | 2.2.0 |
| `cocoapods-install` | 3.1.1 |
| `flutter-installer` | 1.1.1 |
| `npm` (step) | 3.1.0 |
| `restore-gradle-cache` | 3.1.2 |
| `restore-dart-cache` | 3.0.2 |
| `restore-npm-cache` | 3.0.2 |
| `maestro-test` | 1.2.0 |
| Maestro CLI (`maestro_version` input) | 2.12.1 |
| `custom-test-results-export` | 2.0.0 |
| `deploy-to-bitrise-io` | 2.26.2 |
| `xcode-build-for-test` | 3.6.0 |
| `xcode-test-shard-calculation` | 0.2.1 |
| `xcode-test-without-building` | 1.0.1 |
| `virtual-device-testing-for-android` | 1.3.6 |
| `android-build-for-ui-testing` | 1.0.0 |
| Appium server | 2.11.0 |
| `appium-xcuitest-driver` | 7.29.0 |
| `appium-uiautomator2-driver` | 3.7.0 |
| `patrol` (pubspec) | ^4.10.0 |
| `patrol_cli` | 4.8.0 |

### Every workflow at a glance (this repo, latest state)

| Workflow | Platform | Trigger | Status |
|---|---|---|---|
| `android_unit_tests` | Android | push/PR | ✅ passing |
| `android_snapshot_tests` | Android | push/PR | ✅ passing |
| `android_record_snapshots` | Android | manual | by design, not in any pipeline |
| `android_ui_tests` | Android | push/PR | ✅ passing |
| `android-espresso-vdt` | Android | manual | ✅ passing (VDT add-on enabled) |
| `ios_unit_tests` | iOS | push/PR | ✅ passing |
| `ios_ui_tests` | iOS | push/PR | ✅ passing |
| `ios_ui_tests_manual` | iOS | manual | by design |
| `ios-fastlane-scan` | iOS | manual | ✅ passing |
| `ios-maestro-e2e` | iOS | manual | ✅ passing |
| `ios-appium-local` | iOS | manual | ✅ passing |
| `ios_xcuitest_sharded` (pipeline) | iOS | manual | ✅ passing |
| `rn_jest_tests` | React Native | push/PR | ✅ passing |
| `rn_detox_ios` | React Native | push/PR | ✅ passing |
| `android-maestro-e2e-rn` | React Native | manual | ✅ passing |
| `ios-maestro-e2e-rn` | React Native | manual | ✅ passing |
| `flutter_tests` | Flutter | push/PR | ✅ passing |
| `flutter_record_goldens` | Flutter | manual | by design |
| `flutter_integration_tests` | Flutter | push/PR | ✅ passing |
| `flutter_patrol_android` | Flutter | push/PR | ✅ passing |
| `maestro_android` | E2E | push/PR | ✅ passing |
| `android_maestro_sharded` (pipeline) | E2E | manual | ✅ passing |
| `appium_browserstack` | E2E | push (main) | ❌ blocked — missing secrets |
| `android-appium-local` | E2E | manual | ✅ passing |

---

*This document consolidates and supersedes the day-to-day working notes in
`testing-guide.md`, `test-recording-plan.md`, and `new-test-scenarios-plan.md` for anyone
who wants the full picture in one place. Those three remain as historical/operational detail
if you need the blow-by-blow discovery process for a specific decision.*
