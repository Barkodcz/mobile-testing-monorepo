# `bitrise.yml` (root)

Shared Bitrise concepts (workflows vs. pipelines, triggers, the Tests tab, caching, step
pinning) are covered once in [`docs/BITRISE_CONCEPTS.md`](docs/BITRISE_CONCEPTS.md) — this doc
only covers what's specific to the root config.

## 1. Overview

The root `bitrise.yml` doesn't define any workflow or pipeline logic of its own. It only:

- declares a repo-wide default stack/machine for anything that doesn't set its own,
- `include`s one YAML module per platform from `bitrise/`,
- declares app-level env vars every included module can read,
- defines one convenience pipeline, `everything_fast`, that runs every fast (no-device) suite at
  once.

Per-module details — workflows, steps, triggers — live in the five per-module docs this file
links to below, next to their respective YAML.

## 2. Prerequisites

```yaml
meta:
  bitrise.io:
    stack: ubuntu-noble-24.04-bitrise-2025-android
    machine_type_id: g2.linux.medium
```

This `meta` block is the **fallback** stack/machine for any workflow in any included module that
doesn't set its own `meta.bitrise.io` block. Linux is the default specifically because it's
cheaper than macOS — every workflow that genuinely needs a Mac (anything touching Xcode/iOS
Simulator) overrides this explicitly in its own module.

Config modules stored as files in the repo (via `include:`, as opposed to being pasted directly
into one giant `bitrise.yml` through the Bitrise web UI) require the app's Bitrise workspace to be
on an **Enterprise plan** — this is called out in the file's own top comment.

No secrets are declared or used at the root level. Each included module's own doc lists the
secrets/env vars it needs (if any).

## 3. Includes

```yaml
include:
- path: bitrise/common.yml
- path: bitrise/ios.yml
- path: bitrise/android.yml
- path: bitrise/react-native.yml
- path: bitrise/flutter.yml
- path: bitrise/e2e.yml
```

Each included file's `workflows:`/`pipelines:`/`step_bundles:` sections merge into one global
namespace (see [concepts §1](docs/BITRISE_CONCEPTS.md#1-workflows-vs-pipelines)) — workflow and
Step bundle names must stay unique across all six files. `bitrise/common.yml` carries no
workflows/pipelines of its own — it's the home for every shared Step bundle (see [concepts
§7](docs/BITRISE_CONCEPTS.md#7-step-bundles)), included first by convention since the other five
files reference its bundles. Per-module docs:

| Module | Platform | Doc |
|---|---|---|
| `bitrise/common.yml` | *(none — shared Step bundles only)* | [concepts §7](docs/BITRISE_CONCEPTS.md#7-step-bundles) |
| `bitrise/ios.yml` | iOS (native SwiftUI) | [`bitrise/ios.md`](bitrise/ios.md) |
| `bitrise/android.yml` | Android (native Jetpack Compose) | [`bitrise/android.md`](bitrise/android.md) |
| `bitrise/react-native.yml` | React Native | [`bitrise/react-native.md`](bitrise/react-native.md) |
| `bitrise/flutter.yml` | Flutter | [`bitrise/flutter.md`](bitrise/flutter.md) |
| `bitrise/e2e.yml` | Cross-platform E2E (against the native Android app) | [`bitrise/e2e.md`](bitrise/e2e.md) |

## 4. App-level env vars

```yaml
app:
  envs:
  - IOS_DIR: apps/ios
  - ANDROID_DIR: apps/android
  - RN_DIR: apps/react-native
  - FLUTTER_DIR: apps/flutter
  - RECORD_VIDEO: all
  - VDT_DEVICE_LIST: "SmallPhone.arm,30,en,portrait"
  - XCUITEST_SHARD_COUNT: "2"
  - MAESTRO_SHARD_COUNT: "3"
```

| Env var | Value | Purpose |
|---|---|---|
| `IOS_DIR` / `ANDROID_DIR` / `RN_DIR` / `FLUTTER_DIR` | each project's subfolder path | Declared here for convenience; whether any given workflow actually reads these vs. hardcoding `$BITRISE_SOURCE_DIR/apps/<platform>` directly varies per module — check that module's own doc. |
| `RECORD_VIDEO` | `all` \| `failures` \| `off` | Global switch for whether recorded video is *kept* once captured, across every UI/E2E suite that supports the concept. `all` (this repo's current default) means every run's video is kept regardless of pass/fail — the explicit goal here is to showcase as much recorded evidence as possible. Not every workflow reads this the same way; see each module's "Video recording" section. |
| `VDT_DEVICE_LIST` | one device spec | Device list for `android-espresso-vdt`'s Virtual Device Testing (Firebase Test Lab) run. Format: `deviceID,version,language,orientation`, one per line if you add more. |
| `XCUITEST_SHARD_COUNT` | `"2"` | Number of shards for the `ios_xcuitest_sharded` pipeline. |
| `MAESTRO_SHARD_COUNT` | `"3"` | Number of shards for the `android_maestro_sharded` pipeline — deliberately higher than the number of Maestro flow files that currently exist, so one shard legitimately runs zero flows by default (see [`bitrise/e2e.md`](bitrise/e2e.md) §9). |

To override any of these for a single build, use the Bitrise UI's **Start build → environment
variable override** field — this repo's own history found that passing a custom `environments`
value through the `trigger_bitrise_build` API did **not** reliably override an app-level env var;
only the UI field is confirmed working.

## 5. The `everything_fast` pipeline

```yaml
pipelines:
  everything_fast:
    workflows:
      ios_unit_tests: {}
      android_unit_tests: {}
      android_snapshot_tests: {}
      rn_jest_tests: {}
      flutter_tests: {}
```

Manual-only — it has no `triggers:` block, so start it from the Bitrise UI: **Start build →
Pipeline → everything_fast**. All five listed workflows have no `depends_on` between them, so
they all start in parallel. It intentionally only includes the *fast, no-device* suite from each
platform (unit/snapshot/JVM-only tests) — none of the emulator/simulator-based suites are
included, since the point is a quick cross-platform sanity check, not a full regression run.

## 6. Setting this up on Bitrise

1. **Add the app** in the Bitrise dashboard, connect it to this repository (GitHub/GitLab/etc.).
2. **Monorepo handling**: there is no per-project "project path" setting needed here — every
   workflow's own Steps set `working_dir` explicitly to the project subfolder they need (e.g.
   `$BITRISE_SOURCE_DIR/apps/flutter`), and config lives in versioned YAML
   (`bitrise.yml` + `bitrise/*.yml`), not the Bitrise web UI's own editor. During initial app
   setup, when Bitrise asks where your `bitrise.yml` is, point it at the repo root — the
   `include:` list above is what pulls in every platform module.
3. **Enable "stored in the repository" config** (requires an Enterprise-plan workspace, per §2
   above) so the `include:` mechanism works — this is not the default for a brand-new app. This
   is an app-wide **Workflow Editor → Configuration** toggle between "YAML stored on
   bitrise.io" and "YAML stored in your Git repository" — double-check it's set to the git
   option. Verify by editing something trivial in any `bitrise/*.yml`, pushing, and confirming
   the build log for the next run reflects it (e.g. a changed `summary:` string, or a step you
   just added/removed) — don't assume a push is being picked up just because a build runs; it
   may be building the config bitrise.io has stored on its own side instead.
4. **Stack and machine**: the root `meta` block (§2) already sets a sane Linux default; only
   override per-workflow if you add a workflow needing something different (already done for
   every Mac-only workflow in this repo).
5. **Secrets**: add `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` (for
   `appium_browserstack`, see [`bitrise/e2e.md`](bitrise/e2e.md)) under the app's **Secrets**, and
   enable the **Virtual Device Testing** add-on (for `android-espresso-vdt`, see
   [`bitrise/android.md`](bitrise/android.md)) under **Add-ons** — both are the only
   external-credential requirements anywhere in this repo.
6. **Trigger the first build**: push to `main`, or open a PR touching any `apps/<platform>/**`
   path — the matching module's pipeline fires automatically per its `changed_files.regex`
   trigger (see [concepts §2](docs/BITRISE_CONCEPTS.md#2-triggers)). Or start any workflow/pipeline
   manually from the Bitrise UI without waiting for a matching change.
7. **Verify it actually worked**: don't stop at one green build —
   [`docs/TEST_VERIFICATION_GUIDE.md`](docs/TEST_VERIFICATION_GUIDE.md) has the full
   pipeline/workflow inventory (27 execution units across 9 pipelines + 9 standalone workflows),
   exact pass criteria per workflow, and a repeatable full-sweep procedure for confirming the
   whole repo's CI, not just the one thing you changed.

## 7. Troubleshooting / known issues

- None specific to the root file itself — it's intentionally small (wiring only). See each
  included module's own doc for its specific known issues.
- Worth double-checking on initial setup: the Enterprise-plan requirement for file-based config
  modules (§2) is easy to miss if you're setting this up on a non-Enterprise workspace — Bitrise
  will reject the `include:` mechanism (or fall back to ignoring it) rather than erroring
  obviously.
