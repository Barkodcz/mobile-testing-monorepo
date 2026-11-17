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

## 6. Step version pinning

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
