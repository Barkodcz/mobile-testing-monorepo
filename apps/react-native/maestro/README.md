# Maestro flows for React Native

Covers the exact same journeys as the existing Detox suite
(`apps/react-native/e2e/counter.e2e.js`), so the two can be compared side by side. Detox is
untouched -- this is a second, independent way to test the same app.

| Detox test (`e2e/counter.e2e.js`) | Maestro flow | Notes |
|---|---|---|
| `it('shows the initial count', ...)` | `counter_basic.yaml` (first half: launch + assert `Count: 0`) | Detox asserts via `element(by.id(...))`; Maestro via `assertVisible` |
| `it('increments and resets', ...)` — increment half | `counter_basic.yaml` (second half: two taps on `increment_button`, assert `Count: 2`) | |
| `it('increments and resets', ...)` — reset half | `counter_reset.yaml` | Split into its own flow since Maestro flows are meant to be short, independent journeys, not one long combined test like the Detox `it` block |

**Not covered by either suite**: the Decrement button. Neither the Detox suite nor these
Maestro flows test it — kept that way deliberately so this is a true side-by-side comparison
of the *same* coverage, not an excuse to add new coverage under one framework but not the
other.

## Running

- **Android**: `android-maestro-e2e-rn` workflow (builds a debug APK via Gradle, runs on an AVD).
- **iOS**: `ios-maestro-e2e-rn` workflow (builds via `xcodebuild`/CocoaPods, runs on a
  simulator). The flow files use `appId: ${MAESTRO_APP_ID}`; each workflow supplies its own
  platform's app id with `maestro test -e MAESTRO_APP_ID=...` via the Step's `additional_args`
  input (Android: `com.counterrn`, iOS: `org.reactjs.native.example.CounterRN`), so one set of
  flow files covers both platforms instead of maintaining two near-duplicates. (`maestro test`
  has no `--app-id` flag -- an earlier version of this tried that and failed live with "Unknown
  option: '--app-id'".)

Both are manual-trigger only (not wired into the `react_native` pipeline's automatic triggers),
to avoid adding simulator/emulator minutes to every push on top of the existing Detox workflow.
