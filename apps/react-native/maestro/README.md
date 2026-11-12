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
  simulator). The flow files default to the Android `appId` (`com.counterrn`); the iOS workflow
  overrides it at runtime with `maestro test --app-id org.reactjs.native.example.CounterRN` via
  the Step's `additional_args` input, so one set of flow files covers both platforms instead of
  maintaining two near-duplicates.

Both are manual-trigger only (not wired into the `react_native` pipeline's automatic triggers),
to avoid adding simulator/emulator minutes to every push on top of the existing Detox workflow.
