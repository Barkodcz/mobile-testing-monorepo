# Test Verification Guide

A complete, repeatable runbook for verifying this repo's entire Bitrise CI setup end to end —
every pipeline and every workflow, how to trigger it, what "passing" actually looks like, and
what to do when it doesn't. Written so it stays useful after this specific conversation is gone:
treat it as the reference the next person (or the next *you*) reaches for before saying "CI is
green" actually means something.

This complements, not replaces, the per-module docs (`bitrise/*.md`) — those explain *how* each
workflow works; this explains *how to know it still works*.

---

## 1. How to use this guide

- **After any `bitrise/*.yml` or `bitrise.yml` change**: run the relevant subset of §4 (just the
  modules you touched) before trusting the change.
- **Before a big milestone / periodically**: run the full sweep in §5 — every pipeline and every
  manual-only workflow, in one pass. This is the same sweep used to produce the baseline in §6.
- **When something looks wrong**: jump to §7 (troubleshooting) before re-triggering blindly.
- **First time setting this app up on a new Bitrise workspace**: read
  [`../BITRISE.md`](../BITRISE.md) §6 first (app setup steps), then come back here to confirm it
  actually works.

**Prerequisite check before you trust *any* result in this guide**: confirm the Bitrise app's
config source is "stored in your Git repository," not "stored on bitrise.io" (Workflow Editor →
Configuration). If it's set to the latter, Bitrise silently builds whatever config it has on its
own side — your `git push` has no effect, and every result below would be meaningless. See
[`../BITRISE.md`](../BITRISE.md) §6 step 3 for how to verify this.

---

## 2. Full inventory

Every pipeline and every standalone workflow in this repo, one row each. "Trigger" is **auto**
(fires on push/PR automatically, per its `changed_files.regex`) or **manual** (must be started
from the Bitrise UI or the API — nothing in this repo pushes to it automatically). "Stack" is
Linux unless noted (Mac workflows cost real money/time — be deliberate about re-running them).

### Pipelines

| Pipeline | Module | Trigger | Workflows (in dependency order) | Stack |
|---|---|---|---|---|
| `ios` | ios.yml | auto (`apps/ios/**`) | `ios_unit_tests`, `ios_ui_tests` (parallel) | Mac |
| `ios_xcuitest_sharded` | ios.yml | manual | `ios-xcuitest-shard-build` → `ios-xcuitest-shard-calc` → `ios-xcuitest-shard-1`/`-2` (parallel) | Mac |
| `android` | android.yml | auto (`apps/android/**`) | `android_unit_tests`, `android_snapshot_tests`, `android_ui_tests` (parallel) | Linux |
| `maestro` | e2e.yml | auto (`apps/android/**`, `e2e/maestro/**`) | `maestro_android` | Linux |
| `appium` | e2e.yml | auto, push to `main` only | `appium_browserstack` | Linux |
| `android_maestro_sharded` | e2e.yml | manual | `android-maestro-shard-build` → `-shard-1`/`-2`/`-3` (parallel) | Linux |
| `flutter` | flutter.yml | auto (`apps/flutter/**`) | `flutter_tests` → `flutter_integration_tests`, `flutter_patrol_android`, `flutter_patrol_ios` (parallel) | Linux + Mac (patrol_ios) |
| `react_native` | react-native.yml | auto (`apps/react-native/**`) | `rn_jest_tests` → `rn_detox_ios` | Linux + Mac (detox) |
| `everything_fast` | root `bitrise.yml` | manual | `ios_unit_tests`, `android_unit_tests`, `android_snapshot_tests`, `rn_jest_tests`, `flutter_tests` (all parallel) | mixed |

### Standalone manual-only workflows (not in any pipeline)

| Workflow | Module | Stack | What it covers |
|---|---|---|---|
| `ios-maestro-e2e` | ios.yml | Mac | Maestro against the native iOS app |
| `ios-fastlane-scan` | ios.yml | Mac | XCUITest via fastlane `scan` |
| `ios-appium-local` | ios.yml | Mac | Appium + local iOS Simulator |
| `ios_ui_tests_manual` | ios.yml | Mac | XCUITest via manual `xcodebuild test` |
| `android_record_snapshots` | android.yml | Linux | Records new Paparazzi baselines (not a test run) |
| `android-espresso-vdt` | android.yml | Linux (dispatches to Firebase Test Lab) | Same Compose UI tests via Virtual Device Testing |
| `android-maestro-e2e-rn` | react-native.yml | Linux | Maestro against the RN app's Android build |
| `ios-maestro-e2e-rn` | react-native.yml | Mac | Maestro against the RN app's iOS build |
| `android-appium-local` | e2e.yml | Linux | Appium + local Android emulator, against the native Android app |

**27 total execution units** (9 pipelines + 9 standalone workflows, where pipelines themselves
expand to 1–4 workflows each).

---

## 3. Two ways to trigger a build

### A. Bitrise UI
**Start build** → pick either a **Pipeline** or a **Workflow** by name → **Start**. This is the
only way to run `ios_xcuitest_sharded`, `android_maestro_sharded`, and `everything_fast`
"correctly" in the sense the YAML's own comments intend (their component workflows are explicitly
documented as "don't start this workflow directly").

### B. Bitrise API (what this guide's §5 sweep actually used)
Via `POST /v0.1/apps/{app-slug}/builds`, body `{"build_params": {"branch": "main", "workflow_id":
"<name>"}}` for a workflow, or `{"build_params": {"branch": "main", "pipeline_id": "<name>"}}`
for a pipeline. If you have Claude Code with the Bitrise MCP server connected, this is
`mcp__bitrise__trigger_bitrise_build` with `workflow_id` or `pipeline_id`. Same effect as the UI
button, scriptable.

Check results with `mcp__bitrise__get_build` (single build), `mcp__bitrise__list_pipelines`
(everything on a branch, newest first — the fastest way to eyeball a whole sweep), or
`mcp__bitrise__list_builds` (filter by `workflow`). For a failure, `mcp__bitrise__get_build_steps`
with the failure-status filter tells you which step broke; `mcp__bitrise__get_build_log` with
that step's `uuid` gets the actual log text.

---

## 4. Per-workflow pass criteria

What to actually check, beyond "status: success" — what shows up on the **Tests** tab, what name
it has, and anything that's genuinely expected to look odd. "Local" gives the equivalent command
if you want to sanity-check without spending CI minutes at all.

### iOS (`bitrise/ios.yml` — full detail: [`bitrise/ios.md`](../bitrise/ios.md))

| Workflow | Tests-tab entry | Pass looks like | Local equivalent |
|---|---|---|---|
| `ios_unit_tests` | native, named from scheme `CounterApp-Unit` | Swift Testing + XCTest + snapshot tests all pass; no video (unit tests) | `xcodebuild test -project apps/ios/CounterApp.xcodeproj -scheme CounterApp-Unit -destination 'platform=iOS Simulator,name=Bitrise iOS default'` |
| `ios_ui_tests` | native, named from scheme `CounterApp-UI` | XCUITest suite passes; video recorded but **only as an Artifacts-tab file**, not a Tests-tab attachment (see `bitrise/ios.md` §5 for why) | same, scheme `CounterApp-UI` |
| `ios-maestro-e2e` | `Maestro E2E (iOS)` | Both flows (`counter_basic`, `counter_reset`) pass; video + screenshots auto-attached per test case | `maestro test apps/ios/maestro` (built app, booted simulator) |
| `ios-fastlane-scan` | `XCUITest UI tests (fastlane scan)` | Same `CounterApp-UI` suite passes; **true Tests-tab video attachment** (distinguishing feature of this workflow) | `cd apps/ios && fastlane scan_xcuitest` |
| `ios-appium-local` | `Appium on local iOS Simulator` | pytest suite passes; per-test screenshot always, video per `$RECORD_VIDEO` | `cd e2e/appium && APPIUM_TARGET=local pytest tests/test_counter_ios.py` (local Appium server + booted simulator) |
| `ios_ui_tests_manual` | `XCUITest UI tests (manual xcodebuild)` | Same suite as `ios_ui_tests`; true Tests-tab video attachment (the point of this workflow's existence) | `xcodebuild test ... \| xcpretty --report junit` |
| `ios_xcuitest_sharded` | two separate entries, one per shard | Both shards together cover the same 2 test methods `CounterApp-UI` has; each shard's entry shows only its own subset | n/a — sharding is pipeline-only |

### Android (`bitrise/android.yml` — full detail: [`bitrise/android.md`](../bitrise/android.md))

| Workflow | Tests-tab entry | Pass looks like | Local equivalent |
|---|---|---|---|
| `android_unit_tests` | native, module `app` | JUnit tests pass | `cd apps/android && ./gradlew testDebugUnitTest` |
| `android_snapshot_tests` | `Paparazzi snapshots` | No pixel diffs against committed baselines; every rendered frame attached regardless of pass/fail (it's a render, not failure-only) | `./gradlew verifyPaparazziDebug` |
| `android_ui_tests` | `Compose UI tests (Android)` | Instrumented tests pass; suite-level video + final screenshot attached to a synthetic `zz_session_recording` test case | `./gradlew connectedDebugAndroidTest` (needs a running emulator) |
| `android-espresso-vdt` | same suite, via VDT | Same tests, same pass bar, but device is Firebase Test Lab (needs the **Virtual Device Testing add-on enabled** — see `../BITRISE.md` §6) | n/a (cloud-only) |
| `android_record_snapshots` | — (not a test run) | Produces a `paparazzi-snapshots.zip` Artifacts-tab download; "pass" = the zip exists, nothing to assert | `./gradlew recordPaparazziDebug` |

### React Native (`bitrise/react-native.yml` — full detail: [`bitrise/react-native.md`](../bitrise/react-native.md))

| Workflow | Tests-tab entry | Pass looks like | Local equivalent |
|---|---|---|---|
| `rn_jest_tests` | `Jest (React Native)` | All Jest specs pass | `cd apps/react-native && npm test` |
| `rn_detox_ios` | `Detox E2E (iOS)` | Detox E2E suite passes; per-test screenshot + video, named via the custom path-builder to match jest-junit's own test names | `detox test` (after `detox build`, needs a built Release app) |
| `android-maestro-e2e-rn` | `Maestro E2E (React Native / Android)` | Flows pass against the RN app's **Release** Android build (Debug won't render anything — Metro dependency) | `maestro test apps/react-native/maestro -e MAESTRO_APP_ID=com.counterrn` |
| `ios-maestro-e2e-rn` | `Maestro E2E (React Native / iOS)` | Same flows against the RN app's iOS build | same, with the iOS bundle id |

### Flutter (`bitrise/flutter.yml` — full detail: [`bitrise/flutter.md`](../bitrise/flutter.md))

| Workflow | Tests-tab entry | Pass looks like | Local equivalent |
|---|---|---|---|
| `flutter_tests` | `Flutter tests` | Unit/widget/golden tests pass; on a golden failure, a diff PNG attaches to the failing test case (no video — stills, not a live screen) | `cd apps/flutter && flutter test` |
| `flutter_integration_tests` | `Flutter integration tests` | `integration_test` suite passes; suite-level video + final screenshot | `flutter test integration_test -d <device>` |
| `flutter_patrol_android` | `Patrol (Android)` | **2 Patrol tests** pass ("counter keeps its value after going to the home screen", "notification shade can be opened over the app"); per-test native screenshots **and** suite-level video — richest screenshot coverage in this repo | `patrol test --device <emulator>` |
| `flutter_patrol_ios` | `Patrol (iOS)` | Same 2 Patrol tests pass, run through the XCUITest-based runner; suite-level video attaches. **Known gap: screenshots do not currently attach on iOS** (see `bitrise/flutter.md` §9) — don't treat their absence as a failure, but don't assume they'll suddenly appear either. | `patrol test --device "Bitrise iOS default"` |
| `flutter_record_goldens` | — (not a test run) | Golden PNGs land in the Artifacts tab | `flutter test --update-goldens test/goldens` |

### Cross-platform E2E (`bitrise/e2e.yml` — full detail: [`bitrise/e2e.md`](../bitrise/e2e.md))

| Workflow | Tests-tab entry | Pass looks like | Local equivalent |
|---|---|---|---|
| `maestro_android` | `Maestro E2E (Android)` | Both flows pass against the native Android app | `maestro test e2e/maestro` |
| `appium_browserstack` | `Appium on BrowserStack` | **Expected to fail without `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` secrets** — see §6. With secrets present, pytest suite passes on a real BrowserStack device. | n/a (needs BrowserStack account) |
| `android-appium-local` | `Appium on local Android emulator` | pytest suite passes against a local AVD + local Appium server | `cd e2e/appium && APPIUM_TARGET=local pytest tests/test_counter.py` |
| `android_maestro_sharded` | 3 separate entries, `Maestro shard 1/2/3 (Android)` | Flows split round-robin across 3 shards; with only 2 flow files and `MAESTRO_SHARD_COUNT=3` (default), **shard 3 legitimately has 0 flows** — its entry shows as passing-with-nothing-to-run, not a failure | n/a — sharding is pipeline-only |

---

## 5. Full sweep procedure

Use this when you want to confirm the *entire* repo's CI, not just one module — e.g. after a
repo-wide config change, a Bitrise stack upgrade, or (as happened once) discovering the app's
config source was pointed at the wrong place.

1. **Confirm config source** (§1 prerequisite). If in doubt, push a trivial, easily-greppable
   change to any `bitrise/*.yml` comment first and confirm it shows up in the next build's log
   before trusting anything else.
2. **Trigger every pipeline** (9 total, §2): `ios`, `ios_xcuitest_sharded`, `android`, `maestro`,
   `appium`, `android_maestro_sharded`, `flutter`, `react_native`, `everything_fast`.
3. **Trigger every standalone manual workflow** (9 total, §2): `ios-maestro-e2e`,
   `ios-fastlane-scan`, `ios-appium-local`, `ios_ui_tests_manual`, `android_record_snapshots`,
   `android-espresso-vdt`, `android-maestro-e2e-rn`, `ios-maestro-e2e-rn`, `android-appium-local`.
4. **Wait and poll**. Mac builds (anything simulator-based) run 3–10 minutes each; Linux
   unit/snapshot workflows finish in under a minute. `list_pipelines`/`list_builds` filtered by
   branch is the fastest way to see everything's current status in one call.
5. **Triage every non-success**:
   - Matches §6's known expected failure (BrowserStack secrets missing)? → not a regression,
     move on.
   - New/unexpected? → pull `get_build_steps` (failed-status filter) then `get_build_log` for the
     failing step's `uuid`. Diagnose against the relevant `bitrise/*.md`'s own §9 (Troubleshooting)
     first — many failure modes are already documented there with their root cause.
   - If it's a genuine regression from a recent config change: fix, commit, push, re-trigger
     *just that one* workflow to confirm, don't re-run the whole sweep again until you've
     confirmed the fix.
6. **Record the result** — update §6 below with the date and what you found, so the next sweep
   has a point of comparison.

This exact procedure (18 triggers: 9 pipelines + 9 standalone workflows) is what produced the
baseline in §6.

---

## 6. Last known-good baseline

**2026-11-17**, full sweep run immediately after confirming the Bitrise app's config source was
corrected to read from git (previously it may have been reading a stale bitrise.io-stored copy —
see §1's prerequisite check), and after replacing several custom scripts with native Steps
(`xcodegen@0.0.5`, `fastlane@3.5.3`, `android-build@1.2.0` — see `bitrise/ios.md`,
`bitrise/e2e.md`, `bitrise/react-native.md` for exactly which workflows).

**Result: 17/18 green.**

| # | Pipeline/workflow | Result |
|---|---|---|
| 1 | `ios` | ✅ |
| 2 | `ios_xcuitest_sharded` | ✅ |
| 3 | `android` | ✅ |
| 4 | `maestro` | ✅ |
| 5 | `appium` | ❌ **expected** — missing `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` secrets. Confirmed via `get_build_steps`: the `android-build@1.2.0` step (the thing that changed that day) succeeded; the failure is purely in the "Upload APK to BrowserStack and run Appium tests" script, at the BrowserStack upload call. Same failure reproduced on a build from 2026-11-13, well before that day's changes — not a regression. |
| 6 | `android_maestro_sharded` | ✅ (confirms the `BITRISE_APK_PATH` pipeline-intermediate-file handoff works with the new `android-build` Step) |
| 7 | `flutter` | ✅ (covers `flutter_tests`, `flutter_integration_tests`, `flutter_patrol_android`, `flutter_patrol_ios`) |
| 8 | `react_native` | ✅ |
| 9 | `everything_fast` | ✅ |
| 10 | `ios-maestro-e2e` | ✅ |
| 11 | `ios-fastlane-scan` | ✅ (confirms the `fastlane@3.5.3` lane swap) |
| 12 | `ios-appium-local` | ✅ |
| 13 | `ios_ui_tests_manual` | ✅ |
| 14 | `android_record_snapshots` | ✅ |
| 15 | `android-espresso-vdt` | ✅ (VDT add-on still enabled and working) |
| 16 | `android-maestro-e2e-rn` | ✅ (confirms `android-build` swap in `react-native.yml`) |
| 17 | `ios-maestro-e2e-rn` | ✅ |
| 18 | `android-appium-local` | ✅ |

**Known, accepted gaps (not failures, but not fully solved either)** — carried forward from
earlier verification, still true as of this baseline:
- `flutter_patrol_ios`: Patrol screenshots don't attach on iOS (video and test execution do).
  See `bitrise/flutter.md` §9.
- `appium_browserstack`: blocked entirely until `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY`
  secrets are added.

> **Maintenance note**: when you run a future full sweep, replace this section's table and date
> rather than appending a second one — this should always reflect the *most recent* sweep, so
> anyone reading it knows how current the "last known good" claim actually is. If you want
> history, that's what `git log -p -- docs/TEST_VERIFICATION_GUIDE.md` is for.

---

## 7. Troubleshooting a failed sweep

Work through these in order — cheapest/most-likely first.

1. **Is this the BrowserStack failure?** (`appium`/`appium_browserstack`) — check for
   `BROWSERSTACK_USERNAME`/`BROWSERSTACK_ACCESS_KEY` in the app's Secrets. If absent, this is
   expected, not a bug. If present and it still fails, something's actually wrong — check the
   BrowserStack upload response in the log.
2. **Is this `android-espresso-vdt`?** — confirm the **Virtual Device Testing** add-on is still
   enabled (Bitrise dashboard → app → Add-ons). It needs no separate credential once enabled
   (`api_token` defaults to the auto-provisioned `$ADDON_VDTESTING_API_TOKEN`) — don't go looking
   for a Firebase/GCP service account, there isn't one here.
3. **Did a Mac/Xcode stack upgrade happen recently?** Several real bugs in this repo's history
   were purely stack-upgrade fallout (hardcoded simulator names, `xcodebuild archive`'s
   platform-tagging behavior, Appium's Simulator.app GUI path) — see `bitrise/ios.md` §9 and
   `bitrise/react-native.md` §9 for the exact symptoms and fixes already applied once. Re-check
   those same classes of issue first before assuming something new.
4. **Is the failure in a `script@1.2.1` step or a named/native Step?** For a named Step, check its
   real inputs/behavior against StepLib before assuming a config mistake:
   ```bash
   curl -s "https://raw.githubusercontent.com/bitrise-io/bitrise-steplib/master/steps/<step-id>/<version>/step.yml"
   ```
   (see [`../docs/BITRISE_CONCEPTS.md`](BITRISE_CONCEPTS.md) §6). For a `script@1.2.1` step, the
   actual bash is right there in the YAML — reproduce it locally against the same inputs if the
   failure isn't obvious from the log alone.
5. **Config-source check, again.** If a fix you just pushed doesn't seem to change behavior *at
   all* on the next build (not even a different error), stop and re-verify §1's prerequisite —
   this has happened before and wastes much more time than the 30 seconds it takes to check.
6. **Still stuck?** Check the relevant module's `bitrise/*.md` §9 (Troubleshooting / known issues)
   — most non-obvious failure modes in this repo were hit once, root-caused, and documented
   there, including the exact error text to grep for.
