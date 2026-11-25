# Bitrise concepts used throughout this repo

Explained once here; every per-module doc (`bitrise/*.md`, root `BITRISE.md`) links back to this
file instead of repeating it.

## 1. Workflows vs. pipelines

A **workflow** is an ordered list of Steps — the basic unit of execution in Bitrise. A **pipeline**
groups workflows together and controls how they run relative to each other:

```yaml
pipelines:
  flutter:
    workflows:
      flutter_tests: {}
      flutter_integration_tests:
        depends_on: [flutter_tests]        # waits for flutter_tests to finish first
      flutter_patrol_android:
        depends_on: [flutter_tests]        # runs in parallel with flutter_integration_tests
```

Workflows with no `depends_on` start immediately; workflows that declare `depends_on` wait for
every listed workflow to finish (successfully) first. Two workflows with the same dependency (or
none) run **in parallel**, each on its own machine. This repo uses `depends_on` purely to gate
slower/more expensive suites (emulator/simulator-based) behind the fast, no-device `_tests`
workflow for the same platform, so a basic compile/lint/unit failure doesn't waste emulator boot
time.

A workflow can also be run standalone (not as part of any pipeline) — most of this repo's
`manual`-only workflows are like this. You start them from the Bitrise UI: **Start build → select
the workflow (or pipeline) by name**.

One root `bitrise.yml` can `include:` several YAML files (this repo splits one per platform —
see the root [`BITRISE.md`](../BITRISE.md)); included files' `workflows:`/`pipelines:` sections
merge into one global namespace, so workflow names must be unique across the whole repo.

## 2. Triggers

A `triggers:` block (set at the pipeline level in every module here) wires push/PR events to a
pipeline automatically:

```yaml
triggers:
  push:
  - branch: main
    changed_files:
      regex: '^(apps/flutter/.*|bitrise/flutter\.yml)$'
  pull_request:
  - draft_enabled: false
    changed_files:
      regex: '^(apps/flutter/.*|bitrise/flutter\.yml)$'
```

`changed_files.regex` means the pipeline only fires when the push/PR's diff touches a path
matching that pattern — this is what makes each platform module independent: pushing an
Android-only change never triggers the Flutter pipeline. `draft_enabled: false` means draft PRs
don't trigger a build. Workflows/pipelines with no `triggers:` block are **manual-only**: they
never fire automatically, regardless of what changed.

## 3. Deploy to Bitrise.io and the Tests tab

Bitrise's build page has two separate, unrelated tabs:

| | **Tests tab** | **Artifacts tab** |
|---|---|---|
| What it shows | Pass/fail/skip per test case, grouped by suite/class, with inline attachments (screenshots, video, logs) per test case | Flat files you explicitly deployed — zips, APKs, raw recordings, HTML reports |
| How a file lands there | The file must be **co-located with the JUnit XML** and named per the attachment convention (§4 below) *before* the export step runs, and `deploy-to-bitrise-io` must run afterward | Anything placed in `$BITRISE_DEPLOY_DIR`, as long as it's a real file (zip a directory first — see the gotcha below) |

**Two routes populate the Tests tab:**

- **Native route**: an official Step (`xcode-test`, `android-unit-test`, `maestro-test`,
  `virtual-device-testing-for-android`, …) exports JUnit results itself. You only need
  `deploy-to-bitrise-io` after it.
- **Generic route**: the test runner writes JUnit XML itself (via its own reporter — `tojunit`,
  jest-junit, pytest's `--junitxml`, fastlane's `trainer`, xcpretty's `--report junit`, …), then
  [`custom-test-results-export`](https://github.com/bitrise-steplib/step-custom-test-results-export)
  picks it up. Its key inputs: **Test result base path** (where to look) and **Test result search
  pattern** (a glob under that path) — by default it reads `$BITRISE_TEST_RESULT_DIR`, a directory
  the Bitrise CLI exposes for exactly this purpose. Whichever workflow uses this route, `custom-test-results-export`
  must run *before* `deploy-to-bitrise-io`, which is what actually uploads the exported result to
  the Tests tab UI.

Several workflows in this repo were deliberately switched from the native route to the generic
route specifically so a screenshot/video/diff image could be attached to an exact test case — a
native Step's internal result directory isn't something you can reliably drop extra files into.
If you don't need custom attachments, prefer the native route; it's less code.

## 4. The attachment-naming convention

Both `custom-test-results-export` and `deploy-to-bitrise-io` scan the test-result directory for
files matching:

```
<classname>__<name>[__run<k>]__<label>.<ext>
```

e.g. `io.bitrise.sample.counter.CounterScreenUiTest__startsAtZero__screenshot.png`. If a file like
that sits in the **same flat directory** as the JUnit XML, and `<classname>`/`<name>` match a real
`<testcase classname="..." name="...">` entry in that XML, Bitrise attaches it to that test case
automatically — no manual linking, no API call. Rules that matter in practice:

- **Character cleaning**: `" * / : < > ? \ |` in the classname/name get replaced with `_`, both
  when the attachment filename is written and when Bitrise matches it against the JUnit XML.
- **Allowed extensions**: `.jpg .jpeg .png .txt .log .mp4 .webm .ogg` — not `.mov`. Every iOS
  recording in this repo gets converted `.mov → .mp4` with `ffmpeg` for exactly this reason.
- **Flat directory only**: the attachment must sit directly in the export step's base path, not a
  subdirectory.
- **Synthesizing a testcase**: if you only have one recording covering an entire suite (e.g. a
  host-side screen recording wrapped around an instrumented test run), there's no real per-test
  JUnit entry to attach to — you have to add a synthetic passing `<testcase>` to the XML yourself
  first. This repo's [`scripts/reporting/attach_media_to_junit.py`](../scripts/reporting/attach_media_to_junit.py)
  implements this (`add-recording-testcase` mode, idempotent, adds a `zz_session_recording`
  testcase if one isn't already there) alongside two other modes: `rename` (attach to an
  already-known real testcase) and `attach-to-first-failure` (attach to whichever test failed,
  when you don't know in advance which one will).

### The `cp -r` vs. `zip` gotcha

`deploy-to-bitrise-io`'s artifact-deployment mode only picks up **files** placed in
`$BITRISE_DEPLOY_DIR`, not directories copied there with `cp -r` — it silently drops them with no
error, just `"No deployment files were defined"` in the log. Always `zip` a directory before
depositing it, never `cp -r`.

## 5. Caching

Bitrise's key-based cache Steps come in `restore-*-cache`/`save-*-cache` pairs, one family per
package manager (`restore-gradle-cache`/`save-gradle-cache`,
`restore-npm-cache`/`save-npm-cache`, `restore-dart-cache`/`save-dart-cache`, …). They compute
their own cache key and path automatically from the project's lockfiles — you don't configure
either in this repo. `restore-*` runs early in a workflow (right after cloning); `save-*` runs
near the end, after dependencies have actually been resolved/built, usually with
`is_always_run: true` so a failing test run still saves whatever got downloaded. If you need a
custom cache key or path, use the generic `restore-cache`/`save-cache` Steps instead of the
package-manager-specific ones.

## 6. Official Steps vs. `script`

Every `script@1.2.1` Step in this repo was audited against the Bitrise StepLib looking for an
**official** (`maintainer: bitrise`) Step that does the same thing. The audit's outcome, in order
of how often each case actually applies here:

- **Swapped**: three raw `./gradlew <task>` invocations in [`bitrise/android.yml`](../bitrise/android.yml)
  (`android_snapshot_tests`'s `:app:verifyPaparazziDebug`, `android_record_snapshots`'s
  `:app:recordPaparazziDebug`, `android_ui_tests`'s `:app:connectedDebugAndroidTest`) now run via
  the official `gradle-runner@6.0.0` Step instead of a bare script — it runs "the specified Gradle
  task" generically, so it's a drop-in replacement with no behavior change. (The
  `app_file_include_filter`/`mapping_file_include_filter` inputs are set to `""` on all three,
  since none of these tasks build an APK/AAB/mapping file worth exporting — leaving the Step's
  defaults would opportunistically copy stale ones.)
- **Evaluated and deliberately rejected — confirmed bug**: `xcode-build-for-simulator@3.0.3` exists
  and looks like the obvious replacement for the raw `xcodebuild build -sdk iphonesimulator …`
  scripts in `ios-maestro-e2e`, `ios-appium-local`, `ios-maestro-e2e-rn`, and `android-maestro-e2e-rn`'s
  iOS counterpart. It was **not** adopted: the Step always runs `xcodebuild archive` internally,
  which tags its output for the device platform regardless of `-destination`/`-sdk` flags — `simctl`
  then refuses to install it ("has code for platforms: [iOS, arm64]... device can run:
  iOS-simulator"). Confirmed live, independently, on two different apps (see
  [`bitrise/ios.md`](../bitrise/ios.md) and [`bitrise/react-native.md`](../bitrise/react-native.md)
  §9). The raw `xcodebuild build` script is the one genuinely working approach — don't "fix" this
  back to the official Step without re-confirming the bug is gone in a newer Step version first.
- **No official Step exists**: the large majority of remaining scripts — ad hoc `codesign` (no
  official Step wraps bare `codesign --sign -`; the certificate/provisioning-profile Steps target
  real distribution signing, the wrong tool for a simulator-only test build), starting/stopping a
  background Appium server and polling its readiness, the `scripts/recording/*.sh` family (custom
  `adb`/`simctl` screen-recording wrappers), `scripts/reporting/attach_media_to_junit.py` (bespoke
  JUnit-attachment glue, see §4), Patrol/Flutter-specific setup
  (`tool/patrol_setup_android.py`/`patrol_setup_ios.rb`, `flutter create`, `dart pub global run
  junitreport`), Detox build/test invocation, and the BrowserStack upload+pytest script. None of
  these map to a generic, officially-maintained Step — several were in fact *already* migrated the
  other direction on purpose (see §3: several workflows switched from a native Step **to** a script
  specifically to get fine-grained Tests-tab attachment a native Step can't produce).
- **Community (non-official) Step exists, not adopted**: `browserstack-upload@0.1.4` wraps
  `appium_browserstack`'s inline `curl` upload, but its `maintainer` is `community`, not `bitrise`
  — i.e. not vetted/maintained by Bitrise itself. Left as a script rather than trading a
  fully-auditable 6-line `curl`+`jq` call for an unaudited third-party Step. Worth reconsidering if
  this repo's policy on community Steps ever changes.

## 7. Step bundles

A **Step bundle** (`step_bundles:`, top-level key) is a named, reusable list of Steps, referenced
from any workflow's `steps:` list as `bundle::<name>`. Unlike a utility workflow pulled in via
`before_run:` (see `_ios_setup`/`_flutter_setup` in `ios.yml`/`flutter.yml`), a bundle can be
inserted **anywhere** inside a workflow's step list, not just at the start — this is what makes it
usable here, since several of this repo's workflows need other Steps to run *between* the bundle's
own steps and later ones.

This repo defines two bundles in the root [`bitrise.yml`](../bitrise.yml) (shared across every
included module, since both are used by workflows in more than one `bitrise/*.yml` file):

- **`android_avd_create`** — wraps just `avd-manager@2.2.0` (with `avd_profile`/`avd_api_level`/
  `avd_tag`/`avd_abi` inputs, defaulted to this repo's standard `pixel_6`/`"34"`/`google_apis`/
  `x86_64` emulator image). Deliberately does **not** also wrap `wait-for-android-emulator` — several
  call sites (the `android-maestro-shard-*` workflows, `flutter_integration_tests`,
  `flutter_patrol_android`) run another Step (assigning a shard's flows, preparing the Flutter/Patrol
  project) *between* creating the AVD and waiting for it to finish booting, specifically to overlap
  emulator boot time with that other work. Bundling the wait in too would force the two adjacent and
  silently serialize away that overlap. Used by: `maestro_android`, `maestro_android_parallel_copy`,
  `android-appium-local`, all three `android-maestro-shard-*` workflows (`bitrise/e2e.yml`),
  `android_ui_tests` (`bitrise/android.yml`), `flutter_integration_tests`, `flutter_patrol_android`
  (`bitrise/flutter.yml`), and `android-maestro-e2e-rn` (`bitrise/react-native.yml`) — 9 call sites
  in total, each previously a hand-copied 4-line `avd-manager` input block.
- **`ios_simulator_boot`** — wraps the two-line `xcrun simctl boot "Bitrise iOS default" ||
  true` + `xcrun simctl bootstatus "Bitrise iOS default" -b` sequence (boot, then block until fully
  booted — the fix for a real race where Maestro/Appium/Patrol try to interact with a simulator
  that `simctl boot` returned from but hadn't actually finished booting). Used by: `ios-maestro-e2e`,
  `ios-appium-local` (`bitrise/ios.yml`), `flutter_patrol_ios` (`bitrise/flutter.yml`), and
  `ios-maestro-e2e-rn` (`bitrise/react-native.yml`). Applying this bundle to
  `ios-xcuitest-shard-1`/`-2` also **fixed** a previously-documented inconsistency: those two
  workflows used to boot with no `bootstatus` wait at all (see
  [`bitrise/ios.md`](../bitrise/ios.md) §9) — they now get the same wait as every other
  simulator-based workflow, for free, just by adopting the bundle.
  - **Deliberately not bundled**: `ios_ui_tests`, `ios_ui_tests_manual`, and `ios-fastlane-scan`'s
    "Boot simulator and start recording" scripts also boot the simulator, but combine it with
    starting the external `simctl io recordVideo` capture in the same script, and (in `ios_ui_tests`'s
    case) skip the `bootstatus` wait entirely — these three were left untouched rather than
    decomposed, since splitting them risks a timing/behavior change in already-confirmed-working
    workflows for no real benefit (they don't share duplicated code with each other the way the two
    bundles above do).

Step bundle inputs can only be the ones declared in the bundle's own definition — you can't add a
new ad hoc input at the call site (`bundle::android_avd_create: {}` uses every default; override
e.g. `avd_api_level` by passing `inputs: [- avd_api_level: "35"]` at a specific call site if ever
needed).

## 8. Parallel pipeline copies

Bitrise pipelines have a native `parallel: <N>` property (max `200`) you can set on a workflow
entry inside a pipeline's `workflows:` block — it runs **N copies of that one workflow** as N
separate builds, rather than requiring N hand-duplicated workflow definitions:

```yaml
pipelines:
  maestro_android_parallel:
    workflows:
      maestro_android_parallel_copy:
        parallel: 3
```

Each copy gets two Bitrise-provided env vars to tell itself apart: `$BITRISE_IO_PARALLEL_INDEX`
(zero-based: `0`, `1`, `2`, …) and `$BITRISE_IO_PARALLEL_TOTAL` (`3`). This repo's
`maestro_android_parallel_copy` workflow (`bitrise/e2e.yml`) uses the index inside a Step input —
`test_name: Maestro parallel copy $BITRISE_IO_PARALLEL_INDEX (Android)` — so each copy still gets
its own distinct Tests-tab entry, the same outcome as 3 separately-named workflows would have
produced, without the duplication. (Test-sharding tools that support an explicit shard
index/fraction, e.g. `jest --shard=$((BITRISE_IO_PARALLEL_INDEX + 1))/$BITRISE_IO_PARALLEL_TOTAL`,
can use these same two env vars to split work *across* copies instead of repeating it on each —
this repo's `android_maestro_sharded`/`ios_xcuitest_sharded` pipelines predate this property and
shard a different way (round-robin `awk`/an explicit shard-calculation Step), but `parallel` would
be the more idiomatic mechanism for a new from-scratch sharded pipeline.)

A workflow that `depends_on` a `parallel`-configured workflow only runs once **every** copy has
succeeded.

## 9. Step version pinning

Every Step in this repo is pinned to an exact version (`step-id@X.Y.Z`), never a floating major
(`step-id@1`). This is deliberate: a Step's inputs *do* get renamed or removed across major
versions, and a floating pin can silently break a workflow on Bitrise's next automatic Step
update. Before bumping any pinned version, check the target version's real `step.yml` — either via
`bitrise step-info` (Bitrise CLI) or directly:

```bash
curl -s "https://raw.githubusercontent.com/bitrise-io/bitrise-steplib/master/steps/<step-id>/<version>/step.yml"
```

That's also the canonical source every per-module doc in this repo cites when describing what a
given step version actually does and which inputs it accepts.
