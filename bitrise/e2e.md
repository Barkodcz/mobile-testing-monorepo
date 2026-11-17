# `bitrise/e2e.yml` — Cross-platform E2E testing (native Android sample app)

This document fully describes [`bitrise/e2e.yml`](./e2e.yml), the Bitrise CI
module that runs end-to-end UI tests against the native Android sample app in
[`apps/android`](../apps/android). It is included from the root
[`bitrise.yml`](../bitrise.yml) via `include:`.

For generic Bitrise concepts (workflows vs. pipelines, pipeline intermediate
files in general, the Tests-tab attachment-naming convention, triggers,
`deploy-to-bitrise-io`, caching, step-version pinning), see
[`../docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md) — this doc only
covers what's specific to `e2e.yml`.

## 1. Overview

`e2e.yml` exercises the same tiny native Android "counter" app
(`io.bitrise.sample.counter`, source under [`apps/android`](../apps/android))
with two different end-to-end frameworks:

- **Maestro** — black-box UI flows (YAML files under
  [`e2e/maestro/`](../e2e/maestro/)) driven against an on-CI emulator.
- **Appium + pytest** — Python tests (under [`e2e/appium/tests/`](../e2e/appium/tests/))
  driven either against real devices on BrowserStack, or against a local
  emulator + local Appium server.

Beyond the two "plain" workflows (one Maestro, one Appium/BrowserStack), the
file also demonstrates a **sharded Maestro pipeline**
(`android_maestro_sharded`) that builds the APK once and fans the existing
Maestro flow files out across three parallel shard workflows, each reporting
its own entry on the build's Tests tab.

What a reader should expect to see on a build:
- `maestro_android` / `appium_browserstack`: one Tests-tab entry each, with
  screenshots and (depending on `RECORD_VIDEO`) a recording attached per test
  case.
- `android_maestro_sharded`: four workflow runs in one pipeline (`...-build`
  then three `...-shard-N` workflows in parallel), with shard 1 and shard 2
  each producing a Tests-tab entry (because, with the current two flow
  files, those are the shards that actually have flows to run), and shard 3
  running 0 flows at the default shard count (see §9).
- `android-appium-local`: a manual-only workflow that runs the exact same
  Appium test file against a local AVD + local Appium server instead of
  BrowserStack, proving the test code itself doesn't depend on BrowserStack.

## 2. Prerequisites

### Stack / machine per workflow

| Workflow | Stack | Machine type |
|---|---|---|
| `maestro_android` | `ubuntu-noble-24.04-bitrise-2025-android` | `g2.linux.large` |
| `appium_browserstack` | *(inherited default, see below)* | *(inherited default)* |
| `android-appium-local` | `ubuntu-noble-24.04-bitrise-2025-android` | `g2.linux.large` |
| `android-maestro-shard-build` | `ubuntu-noble-24.04-bitrise-2025-android` | `g2.linux.medium` |
| `android-maestro-shard-1/2/3` | `ubuntu-noble-24.04-bitrise-2025-android` | `g2.linux.large` |

`appium_browserstack` sets no `meta.bitrise.io` block of its own, so it
inherits the root [`bitrise.yml`](../bitrise.yml) default:
`ubuntu-noble-24.04-bitrise-2025-android` / `g2.linux.medium`. This is
notably smaller/cheaper than the other workflows here — reasonable since this
workflow doesn't run its own emulator (BrowserStack supplies the device); it
only builds the APK and runs the Python/pytest client that talks to
BrowserStack's API.

### Tools / versions

- **Android SDK / emulator image**: `avd-manager@2.2.0` with
  `profile: pixel_6`, `api_level: "34"`, `tag: google_apis`, `abi: x86_64`
  (used by `maestro_android`, `android-appium-local`, and all three
  `android-maestro-shard-*` workflows — `android-maestro-shard-build` itself
  needs no emulator since it only builds the APK).
- **Maestro CLI**: `maestro_android` uses whatever version the
  `maestro-test@1.2.0` step defaults to (`2.11.0` per StepLib, not pinned in
  this YAML); the three sharded `maestro-test@1.2.0` invocations explicitly
  pin `maestro_version: 2.12.1`.
- **Node.js** (for the local Appium server in `android-appium-local`): no
  explicit Node-version step — relies on whatever Node ships on the stack
  image, then installs `appium@2.11.0` globally via `npm install -g` and the
  `uiautomator2@3.7.0` driver.
- **Python** (for pytest, in both `appium_browserstack` and
  `android-appium-local`): no explicit Python-version step either; both
  workflows just call `python3 -m venv .venv` on whatever `python3` the stack
  image provides, then `pip install -q -r requirements.txt`. Pinned
  dependency ranges are in [`e2e/appium/requirements.txt`](../e2e/appium/requirements.txt):
  `Appium-Python-Client>=4.0,<6`, `pytest>=8,<9`.

### Secrets / env vars (names only)

- `BROWSERSTACK_USERNAME`, `BROWSERSTACK_ACCESS_KEY` — required by
  `appium_browserstack`. The workflow's own `summary` field states: *"Needs
  BROWSERSTACK_USERNAME and BROWSERSTACK_ACCESS_KEY secrets."* These are
  consumed both by the inline upload script (`curl -u
  "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY"`) and by
  [`e2e/appium/conftest.py`](../e2e/appium/conftest.py)'s `driver` fixture
  (`options.set_capability("bstack:options", {..., "userName":
  os.environ["BROWSERSTACK_USERNAME"], "accessKey":
  os.environ["BROWSERSTACK_ACCESS_KEY"]})`). Whether these secrets are
  actually configured in this particular Bitrise app was not something this
  doc could verify from the YAML alone — the file only documents that they
  are *required*, not whether they're currently set.
- `RECORD_VIDEO` — app-level env in the root [`bitrise.yml`](../bitrise.yml),
  default `all` ("all | failures | off"). Read by
  [`e2e/appium/conftest.py`](../e2e/appium/conftest.py) to decide whether to
  keep a BrowserStack/Appium screen recording for a passing test. Not
  consulted by the Maestro workflows at all — Maestro's own
  `startRecording`/`stopRecording` flow commands (see §5) always run,
  unconditionally, regardless of `RECORD_VIDEO`.
- `MAESTRO_SHARD_COUNT` — app-level env, default `"3"`, root
  [`bitrise.yml`](../bitrise.yml) comment: *"Scenario 3b: number of shards for
  the android_maestro_sharded pipeline. Default 3 per the task spec, even
  though e2e/maestro/ only has 2 flow files — one shard legitimately runs 0
  flows at this default."* Used by each shard's "Assign this shard's flows"
  script via `${MAESTRO_SHARD_COUNT:-3}`.
- `APPIUM_TARGET` — read by `conftest.py`, not set in `e2e.yml` itself for
  `appium_browserstack` (defaults to `browserstack`); explicitly exported as
  `local` by `android-appium-local`.
- `APPIUM_SERVER_URL`, `APPIUM_APK_PATH` — exported by `android-appium-local`
  only, consumed by `conftest.py`'s local-target branch.
- `BS_OS_VERSION`, `BS_DEVICE` — optional overrides for the BrowserStack
  device/OS, read by `conftest.py` with defaults (`14.0`, `Google Pixel 8`);
  not set anywhere in `e2e.yml`, so BrowserStack runs always use those
  defaults unless someone sets them in the Bitrise UI.
- `BITRISE_BUILD_NUMBER` — used (with a `local` fallback) as the
  BrowserStack `buildName` capability; a Bitrise-provided env, not something
  this file sets.

## 3. Triggers and pipelines

- **`maestro_android`** (via the `maestro` pipeline): `push` to `main` when
  files matching `^(apps/android/.*|e2e/maestro/.*|bitrise/e2e\.yml)$`
  change; `pull_request` (drafts excluded) when files matching
  `^(e2e/maestro/.*|bitrise/e2e\.yml)$` change. Note the asymmetry: a PR that
  only touches `apps/android/` (app code, no test-flow change) does **not**
  trigger `maestro_android`, but a push to `main` touching `apps/android/`
  does.
- **`appium_browserstack`** (via the `appium` pipeline): `push` to `main`
  only, matching `^(apps/android/.*|e2e/appium/.*|bitrise/e2e\.yml)$`. No PR
  trigger at all — the inline comment explains why: *"real devices cost
  money: main only."*
- **`android-appium-local`**: no `triggers:` block — manual-trigger only
  (per its own `summary`).
- **`android_maestro_sharded`** pipeline: no `triggers:` block either — the
  pipeline-level comment says *"Start this PIPELINE from the Bitrise UI (not
  any one of its workflows directly)."* Each of its four workflows'
  `summary` fields repeats that warning (e.g. `android-maestro-shard-build`:
  *"Part of the android_maestro_sharded pipeline — don't start this workflow
  directly."*).

### `android_maestro_sharded` pipeline wiring

```
android-maestro-shard-build
        │  (deploy-to-bitrise-io uploads BITRISE_APK_PATH
        │   as a pipeline intermediate file)
        ├──► android-maestro-shard-1  (depends_on: [android-maestro-shard-build])
        ├──► android-maestro-shard-2  (depends_on: [android-maestro-shard-build])
        └──► android-maestro-shard-3  (depends_on: [android-maestro-shard-build])
```

- **Build stage** (`android-maestro-shard-build`): runs the `android-build@1.2.0`
  Step (`project_location: apps/android`, `module: app`, `variant: debug`),
  which exports the built APK's path as `$BITRISE_APK_PATH` natively. Its
  `deploy-to-bitrise-io@2.26.2` step then sets
  `pipeline_intermediate_files: BITRISE_APK_PATH` — this tells the step
  to upload the *file at the path named by that env var's value* as a
  pipeline intermediate file (the generic mechanism is explained in
  [`../docs/BITRISE_CONCEPTS.md`](../docs/BITRISE_CONCEPTS.md)). This used to
  be a `./gradlew :app:assembleDebug` script with a manual
  `envman add --key MAESTRO_SHARD_APK_PATH` line — replaced so the APK path
  comes straight from the Step's own output instead of a hand-constructed
  one.
- **Each shard workflow** starts with `pull-intermediate-files@1.3.7` with
  `artifact_sources: android-maestro-shard-build`, which re-downloads that
  APK and re-exposes `BITRISE_APK_PATH` so `maestro-test` can use
  `app_path: $BITRISE_APK_PATH` without rebuilding.
- **Flow-file subset per shard**: each shard runs an inline script ("Assign
  this shard's flows") that does round-robin selection by alphabetically
  sorted flow filename:
  ```bash
  ls "$BITRISE_SOURCE_DIR"/e2e/maestro/counter_*.yaml | sort \
    | awk -v n="${MAESTRO_SHARD_COUNT:-3}" 'NR % n == <shard_index>' \
    | xargs -I{} cp {} /tmp/maestro-shard-<N>/
  ```
  where `<shard_index>` is `1`, `2`, `0` for shards 1, 2, 3 respectively
  (`awk`'s `NR` is the 1-based line number after sorting). It also copies
  `e2e/maestro/config.yaml` into the same temp dir, since `maestro-test`'s
  `flow_path` points at that directory, and Maestro needs the workspace
  config alongside the flow files. See §4 and §9 for the full walkthrough and
  the `wc -l`/`pipefail` subtlety.

## 4. Workflow-by-workflow, step-by-step walkthrough

### 4.1 `maestro_android`

| # | Step | Purpose (per step.yml) | Key inputs | Notes |
|---|---|---|---|---|
| 1 | `git-clone@8.5.2` — *Git Clone Repository* | Checks out the repo and exports git metadata. | *(defaults)* | Standard first step. |
| 2 | `restore-gradle-cache@3.1.2` — *Restore Gradle Cache* | Restores Gradle dependency caches via Bitrise's key-based caching. | *(defaults)* | Pairs with `save-gradle-cache` later. |
| 3 | `avd-manager@2.2.0` — *AVD Manager* | Creates and boots an Android emulator for device testing. StepLib warns emulators can't run on Apple Silicon machines — consistent with this workflow's Linux stack. | `profile: pixel_6`, `api_level: "34"`, `tag: google_apis`, `abi: x86_64` | Outputs `BITRISE_EMULATOR_SERIAL`, consumed implicitly by the next `wait-for-android-emulator` step's default input. |
| 4 | `android-build@1.2.0` — *Android Build* | Official Step: installs Gradle dependencies and builds an APK/AAB, exporting its path as `$BITRISE_APK_PATH`. Replaced a `./gradlew :app:assembleDebug` script. | `project_location: $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: debug` | Produces `apps/android/app/build/outputs/apk/debug/app-debug.apk`, matched by the Step's own default `app_path_pattern` (`*/build/outputs/apk/*.apk`) and exported as `$BITRISE_APK_PATH` — no manual path construction needed downstream. Gradle task resolution comes from the single `:app` module declared in [`settings.gradle.kts`](../apps/android/settings.gradle.kts) and the `com.android.application` plugin in [`app/build.gradle.kts`](../apps/android/app/build.gradle.kts). Confirmed working live (build #189/#199). |
| 5 | `wait-for-android-emulator@1.0.10` — *Wait for Android emulator* | Waits for the AVD to finish booting (reads `$BITRISE_EMULATOR_SERIAL` by default). | *(defaults)* | Runs after the APK build rather than right after step 3 — harmless ordering since boot and Gradle build happen in parallel wall-clock time either way, but it does mean a slow emulator boot is only waited-for once the build is already done. |
| 6 | `maestro-test@1.2.0` — *Maestro Test* | Installs the Maestro CLI, installs the app on the device, runs `maestro test`, and exports results (JUnit + screenshots + `startRecording` videos + command logs per test case) to the Test Reports page; also zips the Maestro output folder as an artifact. | `app_path: $BITRISE_APK_PATH`, `flow_path: $BITRISE_SOURCE_DIR/e2e/maestro`, `test_name: "Maestro E2E (Android)"`, `num_flaky_test_attempts: 1` | `flow_path` points at the whole `e2e/maestro/` directory, so both `counter_basic.yaml` and `counter_reset.yaml` run (per [`config.yaml`](../e2e/maestro/config.yaml)'s `flows: ["*.yaml"]` glob). `num_flaky_test_attempts: 1` means one retry of a failed flow before it's reported as failed. Maestro CLI version not pinned here (StepLib default `2.11.0`), unlike the sharded workflows which pin `2.12.1` — a minor inconsistency worth aligning if reproducibility across workflows matters. |
| 7 | `save-gradle-cache@1.6.2` — *Save Gradle Cache* | Saves the Gradle caches restored in step 2. | *(defaults)* | |
| 8 | `deploy-to-bitrise-io@2.26.2` — *Deploy to Bitrise.io* | Uploads build artifacts to the Artifacts tab and test results to the Tests tab. | `is_always_run: true` | No `pipeline_intermediate_files` input set — this workflow isn't part of a pipeline, so nothing to share forward. `is_always_run: true` ensures results/artifacts are still deployed even if `maestro-test` failed. |

### 4.2 `appium_browserstack`

| # | Step | Purpose | Key inputs | Notes |
|---|---|---|---|---|
| 1 | `git-clone@8.5.2` | Checkout. | *(defaults)* | |
| 2 | `restore-gradle-cache@3.1.2` | Restore Gradle cache. | *(defaults)* | |
| 3 | `android-build@1.2.0` — *Android Build* | Same official Step as §4.1 step 4, `variant: release` this time. Replaced a `./gradlew :app:assembleRelease` script. | `project_location: $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: release` | Builds the **release** variant (unlike `maestro_android`'s debug build) because BrowserStack needs an installable APK and the release build type is configured in [`app/build.gradle.kts`](../apps/android/app/build.gradle.kts) to self-sign with the debug key ("Sample only: sign release with the debug key so Appium/BrowserStack can install it" per its own comment) — otherwise a real release build would be unsigned/unverifiable. Exports `$BITRISE_APK_PATH`, consumed by the next step. |
| 4 | `script@1.2.1` — *Upload APK to BrowserStack and run Appium tests* | Shell script, see breakdown below. | `working_dir: $BITRISE_SOURCE_DIR/e2e/appium` | |
| 5 | `custom-test-results-export@2.0.0` — *Export test results to Test Reports* | Searches for test results and packages them (creates `test-info.json`) for the subsequent `deploy-to-bitrise-io` step to pick up — needed because `pytest --junitxml` doesn't natively export to Bitrise's Test Reports the way `maestro-test` does. | `test_name: "Appium on BrowserStack"`, `base_path: $BITRISE_SOURCE_DIR/e2e/appium/test-results`, `search_pattern: "*/appium.xml"` | `is_always_run: true`. The inline comment explains the screenshot/video attachment is automatic because `conftest.py`'s `driver` fixture already writes files into `test-results/` named `<classname>__<name>__<label>.<ext>`, matching Bitrise's attachment-naming convention — "no separate zip/copy step needed." |
| 6 | `save-gradle-cache@1.6.2` | Save Gradle cache. | *(defaults)* | |
| 7 | `deploy-to-bitrise-io@2.26.2` | Deploy artifacts + test results. | `is_always_run: true` | |

**Step 4 script, line by line:**
```bash
set -eo pipefail
export BS_APP_URL=$(curl -sf -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
  -F "file=@$BITRISE_APK_PATH" | jq -r .app_url)
echo "Uploaded app: $BS_APP_URL"
python3 -m venv .venv && . .venv/bin/activate
pip install -q -r requirements.txt
mkdir -p test-results
pytest tests --junitxml=test-results/appium.xml
```
(The `APK="..."` manual path-construction line this script used to have is
gone — `$BITRISE_APK_PATH` now comes straight from the preceding
`android-build@1.2.0` step's output.)
- `set -eo pipefail`: abort on any command failure, and make a pipeline's
  exit status the last non-zero command in it (so a failing `curl` upstream
  of `| jq` is caught, not masked by `jq`'s own success).
- Uploads the just-built release APK to BrowserStack's App Automate upload
  API using Basic Auth with the two secrets; captures the resulting
  `app_url` (a `bs://...` reference) via `jq -r .app_url` into
  `BS_APP_URL`, which `conftest.py`'s BrowserStack branch reads as
  `options.app = os.environ["BS_APP_URL"]`.
- Creates/activates a fresh Python venv, installs pinned deps from
  [`requirements.txt`](../e2e/appium/requirements.txt).
- Runs `pytest tests --junitxml=test-results/appium.xml` — discovers all
  test files under `tests/` (here: [`test_counter.py`](../e2e/appium/tests/test_counter.py);
  `test_counter_ios.py` also lives in that directory but presumably targets
  a separate iOS workflow outside this doc's scope, not invoked here since
  `pytest tests` with no path filter would normally run both — worth
  double-checking that `test_counter_ios.py` doesn't accidentally also run
  against the Android/BrowserStack target in this invocation; this file
  does not filter by platform).

### 4.3 `android-appium-local`

Summary (from the YAML): runs Appium against a local AVD + local Appium
server instead of BrowserStack, reusing `test_counter.py` unchanged via the
`APPIUM_TARGET=local` switch in `conftest.py`. Manual-trigger only.

| # | Step | Purpose | Key inputs | Notes |
|---|---|---|---|---|
| 1 | `git-clone@8.5.2` | Checkout. | *(defaults)* | |
| 2 | `restore-gradle-cache@3.1.2` | Restore Gradle cache. | *(defaults)* | |
| 3 | `avd-manager@2.2.0` | Create/boot emulator. | same as §4.1 step 3 | |
| 4 | `android-build@1.2.0` — *Android Build* | Same official Step, `variant: debug`. Replaced a `./gradlew :app:assembleDebug` script. | `project_location: $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: debug` | Debug build here (not release) since there's no BrowserStack signing/upload requirement — the local Appium driver installs the APK directly, reading its path from `$BITRISE_APK_PATH`. |
| 5 | `wait-for-android-emulator@1.0.10` | Wait for boot. | *(defaults)* | |
| 6 | `script@1.2.1` — *Start local Appium server* | Shell script, see breakdown below. | *(no working_dir override — defaults to `$BITRISE_SOURCE_DIR`)* | |
| 7 | `script@1.2.1` — *Run Appium tests (local)* | Shell script, see breakdown below. | `working_dir: $BITRISE_SOURCE_DIR/e2e/appium` | |
| 8 | `script@1.2.1` — *Stop local Appium server* | `kill "$(cat /tmp/appium-server.pid)" 2>/dev/null \|\| true` | `is_always_run: true` | Cleanup step; `\|\| true` means a missing/already-dead PID file doesn't fail the build. |
| 9 | `custom-test-results-export@2.0.0` | Export pytest results. | `test_name: "Appium on local Android emulator"`, `base_path: .../e2e/appium/test-results`, `search_pattern: "*/appium-local.xml"` | `is_always_run: true`. Distinct `test_name` and `search_pattern` from `appium_browserstack`'s step so the two don't collide if ever run in the same pipeline. |
| 10 | `save-gradle-cache@1.6.2` | Save cache. | *(defaults)* | |
| 11 | `deploy-to-bitrise-io@2.26.2` | Deploy. | `is_always_run: true` | |

**Step 6 script ("Start local Appium server"):**
```bash
set -eo pipefail
npm install -g appium@2.11.0
appium driver install uiautomator2@3.7.0
nohup appium --base-path /wd/hub --allow-insecure chromedriver_autodownload \
  > /tmp/appium-server.log 2>&1 &
echo $! > /tmp/appium-server.pid
for _ in $(seq 1 30); do curl -sf http://localhost:4723/wd/hub/status && break; sleep 1; done
```
- Installs Appium 2.11.0 globally and the UiAutomator2 driver (required for
  Android automation).
- Starts the server in the background (`nohup ... &`), redirecting all
  output to a log file, and records its PID to `/tmp/appium-server.pid` for
  the later cleanup step.
- Polls `/wd/hub/status` up to 30 times (1s apart) until the server answers,
  rather than a fixed sleep — a simple readiness-wait pattern. Note there's
  no explicit failure if the loop exhausts all 30 attempts without the
  server coming up (`curl -sf ... && break` just falls through); the next
  step would then likely fail when it can't connect.

**Step 7 script ("Run Appium tests (local)"):**
```bash
set -eo pipefail
export APPIUM_TARGET=local
export APPIUM_SERVER_URL=http://localhost:4723/wd/hub
export APPIUM_APK_PATH="$BITRISE_APK_PATH"
python3 -m venv .venv && . .venv/bin/activate
pip install -q -r requirements.txt
mkdir -p test-results
pytest tests/test_counter.py --junitxml=test-results/appium-local.xml
```
- Sets the three env vars `conftest.py`'s local branch reads:
  `APPIUM_TARGET=local` (selects the `UiAutomator2Options` + local
  `webdriver.Remote` path instead of the BrowserStack path),
  `APPIUM_SERVER_URL` (points at the just-started local server),
  `APPIUM_APK_PATH` (the just-built debug APK).
- Unlike `appium_browserstack`'s `pytest tests`, this explicitly targets
  only `tests/test_counter.py` — deliberately excluding `test_counter_ios.py`
  from this Android-only local run.

### 4.4 `android-maestro-shard-build`

| # | Step | Purpose | Key inputs | Notes |
|---|---|---|---|---|
| 1 | `git-clone@8.5.2` | Checkout. | *(defaults)* | |
| 2 | `restore-gradle-cache@3.1.2` | Restore Gradle cache. | *(defaults)* | |
| 3 | `android-build@1.2.0` — *Android Build* | Builds the debug APK, exporting `$BITRISE_APK_PATH`. Replaced a `./gradlew :app:assembleDebug` + manual `envman add --key MAESTRO_SHARD_APK_PATH` script. | `project_location: $BITRISE_SOURCE_DIR/apps/android`, `module: app`, `variant: debug` | No emulator is created in this workflow at all — it only builds the APK. |
| 4 | `save-gradle-cache@1.6.2` | Save cache. | *(defaults)* | |
| 5 | `deploy-to-bitrise-io@2.26.2` | Upload artifacts + pipeline intermediate file. | `is_always_run: true`, `pipeline_intermediate_files: BITRISE_APK_PATH` | This is the only `deploy-to-bitrise-io` invocation in `e2e.yml` that sets `pipeline_intermediate_files` — correctly, since this is the only workflow in the file that's a pipeline stage feeding others. Uses the Step's own `BITRISE_APK_PATH` output directly — no custom env var needed, unlike the previous script-based version's `MAESTRO_SHARD_APK_PATH`. |

### 4.5 `android-maestro-shard-1` / `-2` / `-3`

All three are structurally identical except for the shard index baked into
the `awk` filter, the `test_name`, and the temp directory name. Walkthrough
(using shard 1 as the representative):

| # | Step | Purpose | Key inputs | Notes |
|---|---|---|---|---|
| 1 | `git-clone@8.5.2` | Checkout. | *(defaults)* | |
| 2 | `pull-intermediate-files@1.3.7` — *Pull Pipeline intermediate files* | Downloads intermediate files produced by a prior pipeline stage. | `artifact_sources: android-maestro-shard-build` | Restores `BITRISE_APK_PATH` (both the file and, implicitly, the env var pointing at it) from the build stage. |
| 3 | `avd-manager@2.2.0` | Create/boot emulator. | same params as §4.1 | |
| 4 | `script@1.2.1` — *Assign this shard's flows* | Shell script, see below. | *(no working_dir override)* | |
| 5 | `wait-for-android-emulator@1.0.10` | Wait for boot. | *(defaults)* | |
| 6 | `maestro-test@1.2.0` | Run Maestro flows. | `app_path: $BITRISE_APK_PATH`, `flow_path: /tmp/maestro-shard-1`, `test_name: "Maestro shard 1 (Android)"`, `maestro_version: 2.12.1`, `num_flaky_test_attempts: 1`, `run_if: '{{enveq "MAESTRO_SHARD_HAS_FLOWS" "true"}}'` | `run_if` conditionally skips the whole step when no flows were assigned to this shard — see §9. Each shard's distinct `test_name` ("Maestro shard 1/2/3 (Android)") is what gives each shard its own separate Tests-tab entry (see §6). |
| 7 | `deploy-to-bitrise-io@2.26.2` | Deploy. | `is_always_run: true` | No `pipeline_intermediate_files` here — shards don't feed anything forward. |

**Step 4 script ("Assign this shard's flows"), shard 1 version:**
```bash
set -eo pipefail
mkdir -p /tmp/maestro-shard-1
cp "$BITRISE_SOURCE_DIR/e2e/maestro/config.yaml" /tmp/maestro-shard-1/
ls "$BITRISE_SOURCE_DIR"/e2e/maestro/counter_*.yaml | sort \
  | awk -v n="${MAESTRO_SHARD_COUNT:-3}" 'NR % n == 1' \
  | xargs -I{} cp {} /tmp/maestro-shard-1/
COUNT=$(find /tmp/maestro-shard-1 -maxdepth 1 -name 'counter_*.yaml' | wc -l | tr -d ' ')
echo "Shard 1: $COUNT flow(s) assigned"
envman add --key MAESTRO_SHARD_HAS_FLOWS --value "$([ "$COUNT" -gt 0 ] && echo true || echo false)"
```
- Creates a scratch dir, copies in the shared `config.yaml` (Maestro's
  workspace config declaring `flows: ["*.yaml"]`), since `maestro-test`'s
  `flow_path` will point at this directory as if it were the whole flow
  folder.
- `ls .../counter_*.yaml | sort | awk 'NR % n == 1'`: lists only files
  matching `counter_*.yaml` (explicitly excluding `config.yaml` from the
  round-robin, since that would otherwise also match a bare `*.yaml` glob),
  sorts them alphabetically, and `awk`'s `NR % n == <k>` keeps every line
  whose 1-based position modulo the shard count equals `<k>` — a classic
  round-robin partition across shards 1..n (here `n` defaults to 3 via
  `${MAESTRO_SHARD_COUNT:-3}`, and shard 1's index is `1`, shard 2's is `2`,
  shard 3's is `0` since nothing is ≡0 mod n at position n, 2n, …).
- `xargs -I{} cp {} /tmp/maestro-shard-1/`: copies each matched flow file
  into the shard's temp dir. If `awk` produces zero matching lines, `xargs`
  with no input simply does nothing — it does **not** error, so this
  particular line is safe even for a shard with no flows.
- **Why `find ... | wc -l` instead of `ls ... | wc -l` for the count**: under
  `set -e -o pipefail`, `ls` on a glob that matches **zero** files exits
  non-zero (most `ls` implementations do this) and, combined with
  `pipefail`, would abort the whole script right there — exactly the failure
  mode this script needs to avoid for a shard that's supposed to legitimately
  have 0 flows. `find /tmp/maestro-shard-1 -maxdepth 1 -name
  'counter_*.yaml'` instead always exits 0 whether or not it finds matches
  (it only fails on a real filesystem error), so `| wc -l` reliably yields
  `0` instead of aborting the build. This is a deliberate and correct
  choice — see also §9's discussion of the *first* `ls` in this same script,
  which is **not** guarded this way.
- `envman add --key MAESTRO_SHARD_HAS_FLOWS --value "$([ "$COUNT" -gt 0 ] && echo true || echo false)"`:
  exports a boolean-as-string env var that the next `maestro-test` step's
  `run_if` condition checks, so the step is skipped entirely (not merely
  run-and-ignored) when the shard has nothing to test.

Shard 2 and shard 3 differ only in: the temp dir name
(`/tmp/maestro-shard-2`, `/tmp/maestro-shard-3`), the `awk` modulus target
(`NR % n == 2`, `NR % n == 0`), the `test_name` (`Maestro shard 2/3
(Android)`), and the echoed shard number.

## 5. Video recording

Two entirely different mechanisms are used, one per framework:

- **Maestro** ([`e2e/maestro/counter_basic.yaml`](../e2e/maestro/counter_basic.yaml),
  [`counter_reset.yaml`](../e2e/maestro/counter_reset.yaml)): each flow
  brackets itself with Maestro's own built-in commands —
  `- startRecording: recording` at the top and `- stopRecording` at the
  bottom. Per the `maestro-test` step's own description, the step
  "installs the Maestro CLI, installs your app on the device, runs `maestro
  test`, and exports ... each flow's screenshots, `startRecording` videos
  and logs attached to its test case" — i.e. capture and Tests-tab
  attachment are entirely handled inside the step/CLI once the flow uses
  `startRecording`/`stopRecording`. **This needs zero custom scripting** in
  `e2e.yml` — unlike Appium below, there's no conditional logic, no
  `RECORD_VIDEO` check, and no base64 decoding anywhere in the Maestro
  workflows. Both flows also call `takeScreenshot` at a specific point
  (`after_increment`, `after_reset`) for an extra named screenshot beyond
  whatever Maestro captures automatically.
- **Appium** ([`e2e/appium/conftest.py`](../e2e/appium/conftest.py)): the
  `driver`/`ios_driver` fixtures call `drv.start_recording_screen()` right
  after creating the session (wrapped in a `try/except` so a recording
  failure never breaks the test) and, on teardown, decide whether to keep
  it:
  - If `RECORD_VIDEO == "off"`: never starts recording at all.
  - If `RECORD_VIDEO == "all"`, or the test `status == "failed"`: calls
    `drv.stop_recording_screen()`, base64-decodes the returned string, and
    writes it to `test-results/<classname>__<name>__video.mp4`.
  - Otherwise (`RECORD_VIDEO == "failures"` and the test passed): still
    calls `stop_recording_screen()` to end the session cleanly, but discards
    the result instead of writing it to disk.
  - A screenshot (`..._screenshot.png`) is taken for **every** test
    regardless of `RECORD_VIDEO` or pass/fail.
  - For BrowserStack specifically, a full session video is also always
    recorded server-side in BrowserStack's own dashboard independent of this
    logic — the comment in `conftest.py` notes this explicitly.

Contrast with the suite-level recording helper
[`scripts/reporting/attach_media_to_junit.py`](../scripts/reporting/attach_media_to_junit.py):
that script exists for frameworks that only support *one video for the
whole run* (e.g. a host-side `adb shell screenrecord`), and it injects a
synthetic `<testcase>` into the JUnit XML to hang the attachment off of. It
is **not used anywhere in `e2e.yml`** — neither Maestro (which attaches
per-flow natively) nor Appium (whose `conftest.py` fixture already produces
one recording per real test case) needs it. It's documented here only
because the task asked for it and because it's a useful contrast: it's used
elsewhere in this repo for frameworks that record at suite granularity.

## 6. Test reporting

| Workflow | Report format | Written to | Deployed by | Separate Tests-tab entry via |
|---|---|---|---|---|
| `maestro_android` | Native JUnit export built into `maestro-test@1.2.0` (per-flow test cases, with screenshots/videos/command logs attached automatically). | Internal to the step / `$BITRISE_TEST_RESULT_DIR` (`MAESTRO_JUNIT_PATH` output). | `deploy-to-bitrise-io@2.26.2` | `test_name: "Maestro E2E (Android)"` |
| `appium_browserstack` | `pytest --junitxml=test-results/appium.xml` | `e2e/appium/test-results/appium.xml` (plus the per-test screenshot/video files alongside it) | `custom-test-results-export@2.0.0` packages it for `deploy-to-bitrise-io@2.26.2` to actually upload | `test_name: "Appium on BrowserStack"` |
| `android-appium-local` | `pytest --junitxml=test-results/appium-local.xml` | `e2e/appium/test-results/appium-local.xml` | same two-step pattern | `test_name: "Appium on local Android emulator"` |
| `android-maestro-shard-1/2/3` | Native JUnit export via `maestro-test@1.2.0` (same as `maestro_android`, scoped to that shard's flow subset) | Internal to the step | `deploy-to-bitrise-io@2.26.2` | `test_name: "Maestro shard 1/2/3 (Android)"` |

The key mechanism behind "each shard reports its own separate Tests-tab
entry" is simply that **`maestro-test`'s `test_name` input becomes the
suite/report name shown on the Tests tab**, and each shard workflow sets a
distinct literal string (`"Maestro shard 1 (Android)"`,
`"Maestro shard 2 (Android)"`, `"Maestro shard 3 (Android)"`). Likewise,
`custom-test-results-export`'s `test_name` + `search_pattern` pair keeps
`appium_browserstack`'s and `android-appium-local`'s reports from colliding
even though both ultimately come from the same `pytest`/`conftest.py` code
path.

## 7. Run it locally

**Maestro** (needs a running emulator/device with Maestro CLI installed, and
the APK already built and installed, or point Maestro at the APK directly):
```bash
cd apps/android
./gradlew :app:assembleDebug
maestro test ../../e2e/maestro \
  --app-file app/build/outputs/apk/debug/app-debug.apk
```
(Maestro also accepts a single flow file instead of the whole directory,
e.g. `maestro test ../../e2e/maestro/counter_basic.yaml`.)

**Appium against BrowserStack** (needs `BROWSERSTACK_USERNAME` /
`BROWSERSTACK_ACCESS_KEY` exported, and a release APK uploaded first):
```bash
cd apps/android && ./gradlew :app:assembleRelease && cd ../../e2e/appium
APK="$(pwd)/../../apps/android/app/build/outputs/apk/release/app-release.apk"
export BS_APP_URL=$(curl -sf -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
  -F "file=@$APK" | jq -r .app_url)
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
pytest tests --junitxml=test-results/appium.xml
```

**Appium against a local emulator** (needs a booted AVD/emulator and a
running Appium server — `appium --base-path /wd/hub`):
```bash
cd apps/android && ./gradlew :app:assembleDebug && cd ../../e2e/appium
export APPIUM_TARGET=local
export APPIUM_SERVER_URL=http://localhost:4723/wd/hub
export APPIUM_APK_PATH="$(pwd)/../../apps/android/app/build/outputs/apk/debug/app-debug.apk"
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
pytest tests/test_counter.py
```

**Via Bitrise CLI**, to run any single workflow exactly as CI would (needs
`bitrise` installed and the repo's secrets available locally, e.g. via a
`.bitrise.secrets.yml`):
```bash
bitrise run maestro_android
bitrise run appium_browserstack
bitrise run android-appium-local
```
The sharded pipeline's individual workflows (`android-maestro-shard-1`,
etc.) can technically also be run standalone with `bitrise run
android-maestro-shard-1`, but doing so skips `android-maestro-shard-build`,
so `BITRISE_APK_PATH` would need to be supplied another way (e.g. by
building the APK locally first and exporting the env var) — running the full
`android_maestro_sharded` **pipeline** from the Bitrise UI is the supported
path, per the YAML's own repeated warnings (see §3).

## 8. Adapting this to your own project

**Maestro is the simplest E2E option in this repo** — the flow files
([`counter_basic.yaml`](../e2e/maestro/counter_basic.yaml),
[`counter_reset.yaml`](../e2e/maestro/counter_reset.yaml)) are a handful of
declarative YAML lines with no test-framework boilerplate, no server to
stand up, and recording/reporting built into the single `maestro-test` step.
To copy this pattern to your own project:
1. Write flow files under your own `e2e/maestro/`-equivalent directory, each
   starting with `appId: <your.app.id>` and a `name:`.
2. Change every `tapOn`/`assertVisible` selector (`id: "increment_button"`,
   text like `"Count: 0"`) to match your own app's accessibility
   IDs/testTags and on-screen text — these are app-specific and will not
   carry over.
3. Reuse the three Bitrise steps as-is: `avd-manager` (or skip it if testing
   iOS/an already-running device) → `wait-for-android-emulator` →
   `maestro-test` with `app_path` and `flow_path` pointed at your app/flows
   → `deploy-to-bitrise-io`.
4. For sharding, copy the `android-maestro-shard-*` pattern (build once,
   `envman`+`pipeline_intermediate_files` to share the APK, round-robin
   `awk 'NR % n == k'` per shard, `find | wc -l` guarded counting, `run_if`
   gating) — but note §9's caveat about picking a shard count that actually
   matches your flow-file count, or accept that some shards will run 0
   flows by design.

**Appium** requires considerably more setup and is the better fit when you
need either real-device coverage (BrowserStack) or cross-platform
(Android+iOS) reuse of the same Python test code:
1. Mirror [`e2e/appium/conftest.py`](../e2e/appium/conftest.py)'s fixture
   pattern (`driver` for Android, `ios_driver` for iOS) — adapt
   `options.app` depending on your own `APPIUM_TARGET` switch, and the
   `clean()`/naming-convention logic if you want automatic Tests-tab
   screenshot/video attachment.
2. Update every selector in your test files (this repo's
   [`test_counter.py`](../e2e/appium/tests/test_counter.py) uses
   `resource-id` XPath lookups keyed off Compose `testTag`s exposed via
   `testTagsAsResourceId = true` — your app's own accessibility tagging
   strategy will differ).
3. Set `BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY` as Bitrise
   secrets if using BrowserStack; otherwise follow the
   `android-appium-local` pattern to skip BrowserStack and stand up your own
   local Appium server step.
4. Change the hardcoded app id (`io.bitrise.sample.counter`) and any
   BrowserStack capability defaults (`BS_OS_VERSION`, `BS_DEVICE`) to match
   your target app/devices.

## 9. Troubleshooting / known issues

- **`MAESTRO_SHARD_COUNT` defaulting higher than the number of available
  flow files means a shard legitimately runs 0 flows.** At the repo's
  current default (`MAESTRO_SHARD_COUNT: "3"` in root
  [`bitrise.yml`](../bitrise.yml)) with only 2 flow files
  (`counter_basic.yaml`, `counter_reset.yaml`), `android-maestro-shard-3`'s
  `awk 'NR % n == 0'` matches neither file (positions 1 and 2, mod 3, are 1
  and 2 — never 0), so that shard assigns 0 flows. This is explicitly called
  out and accepted in both the root `bitrise.yml` comment ("one shard
  legitimately runs 0 flows at this default, see
  docs/new-test-scenarios-plan.md") and `android-maestro-shard-3`'s own
  `summary` field ("Demonstrates the sharding mechanism honestly for a
  sample app this small"). It is handled gracefully via the
  `MAESTRO_SHARD_HAS_FLOWS` env var + `run_if` gate on `maestro-test`, so the
  build doesn't fail — it just means shard 3 produces no Tests-tab entry at
  all, which could look like a silent gap to someone unfamiliar with this
  design if they're expecting three populated reports.
- **The first `ls` in each shard's "Assign this shard's flows" script is
  potentially the same `ls`-on-empty-glob-under-`pipefail` hazard the script
  explicitly works around for the *count* a few lines later** — but only
  partially mitigated. The line:
  ```bash
  ls "$BITRISE_SOURCE_DIR"/e2e/maestro/counter_*.yaml | sort \
    | awk -v n="${MAESTRO_SHARD_COUNT:-3}" 'NR % n == 0' \
    | xargs -I{} cp {} /tmp/maestro-shard-3/
  ```
  only has a problem if the `counter_*.yaml` glob itself matches **zero**
  files repo-wide (not the same as "zero files assigned to this shard" —
  that case is fine, since `awk` just emits nothing and `xargs` with no
  input is a no-op). If someone ever deletes all `counter_*.yaml` flow files
  from `e2e/maestro/`, this first `ls` would fail to expand its glob, most
  `ls` implementations exit non-zero in that case, and combined with `set
  -eo pipefail` the whole script — hence the whole shard workflow — would
  abort with a pipeline failure rather than the "0 flows assigned" graceful
  path the rest of the script is designed around. This is a latent
  inconsistency: the script guards the *count* step with `find` specifically
  to avoid this failure mode, but not the earlier `ls | sort | awk | xargs`
  pipeline that does the actual copying. In the repo's current state (2
  flow files always present) this can't trigger, but it's worth noting
  as a fragility if flow files are ever all removed.
- **`maestro_android`'s `maestro-test` step doesn't pin `maestro_version`**,
  while the three sharded workflows pin `2.12.1` explicitly. This means
  `maestro_android` silently tracks whatever version the step defaults to
  (StepLib default at time of writing: `2.11.0`) and could drift
  independently of the sharded pipeline's behavior over time.
- **`appium_browserstack`'s `pytest tests --junitxml=...` has no path
  filter**, so it would pick up both `test_counter.py` and
  `test_counter_ios.py` from [`e2e/appium/tests/`](../e2e/appium/tests/) if
  the latter is collectible in this environment (depends on whether its own
  fixtures/imports succeed without an iOS target configured) — worth
  confirming this doesn't cause unexpected collection errors or unintended
  iOS-targeted test attempts within an Android-only BrowserStack workflow.
  By contrast, `android-appium-local`'s equivalent step explicitly scopes to
  `pytest tests/test_counter.py`.
- **No explicit Python or Node version pinning** in either Appium workflow —
  both rely on whatever `python3`/`npm`/`node` ship on the
  `ubuntu-noble-24.04-bitrise-2025-android` (or inherited default) stack
  image at build time. A stack image update could shift behavior without
  any change to `e2e.yml` itself.
- **The "Start local Appium server" readiness-poll loop in
  `android-appium-local` has no explicit failure/exit on timeout** — if the
  server never responds within the 30 one-second attempts, the loop simply
  exits after exhausting its range without erroring, and the failure only
  surfaces indirectly when the next step's Appium client fails to connect.
  A clearer error message at the timeout boundary would make debugging a
  stuck server startup faster.
- **Secrets availability for `appium_browserstack` is not verifiable from
  `e2e.yml` alone.** The workflow's own `summary` states the two
  BrowserStack secrets are required, but this file cannot confirm whether
  they are actually configured as Bitrise app/workspace secrets in this
  particular app — if they are missing, the workflow will fail at the
  `curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" ...` line with
  an auth error.
