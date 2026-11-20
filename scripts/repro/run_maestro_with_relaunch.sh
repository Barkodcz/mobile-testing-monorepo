#!/usr/bin/env bash
# Rebuilds the customer's observed retry/relaunch behaviour: run the Maestro
# flows, and if the emulator process is gone afterwards, kill the adb server,
# relaunch qemu with the exact flags from their log, wait for boot, reinstall
# the APK and retry the failed flows (up to MAX_RETRIES).
set -uo pipefail

APK_PATH="${APK_PATH:-${BITRISE_APK_PATH:-}}"
FLOW_DIR="${FLOW_DIR:-$BITRISE_SOURCE_DIR/e2e/maestro-repro}"
EMULATOR_AVD="${EMULATOR_AVD:-emulator-5554}"
EMULATOR_GPU="${EMULATOR_GPU:-guest}"
EMULATOR_EXTRA_FLAGS="${EMULATOR_EXTRA_FLAGS:-}"
MAX_RETRIES="${MAX_RETRIES:-2}"
REPORT_DIR="${REPORT_DIR:-$BITRISE_DEPLOY_DIR/maestro-repro}"
DEVICE="emulator-5554"

mkdir -p "$REPORT_DIR"

echo "=== Effective emulator flags ==="
echo "EMULATOR_GPU=$EMULATOR_GPU"
echo "EMULATOR_EXTRA_FLAGS=$EMULATOR_EXTRA_FLAGS"
echo "APK_PATH=$APK_PATH"
echo "FLOW_DIR=$FLOW_DIR"
echo "================================"

device_alive() {
  adb devices | grep -q "^${DEVICE}[[:space:]]device" && pgrep -f qemu-system >/dev/null 2>&1
}

install_apk() {
  adb -s "$DEVICE" install -r -g "$APK_PATH"
}

relaunch_emulator() {
  echo "Device $DEVICE is gone; relaunching the emulator"
  adb kill-server || true
  adb start-server || true

  local emu
  emu="$(command -v emulator || echo "$ANDROID_HOME/emulator/emulator")"

  # shellcheck disable=SC2086
  nohup "$emu" "@$EMULATOR_AVD" -verbose -no-window -no-audio -no-snapshot -no-boot-anim \
    -gpu "$EMULATOR_GPU" $EMULATOR_EXTRA_FLAGS -memory 4096 -camera-back none -camera-front none \
    >> "$REPORT_DIR/emulator-restart.log" 2>&1 &

  echo "Waiting for device..."
  timeout 300 adb wait-for-device

  echo "Polling sys.boot_completed..."
  local waited=0
  while [ "$waited" -lt 300 ]; do
    boot_completed="$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [ "$boot_completed" = "1" ]; then
      echo "Boot completed after ${waited}s"
      break
    fi
    sleep 5
    waited=$((waited + 5))
  done

  adb -s "$DEVICE" shell input keyevent 82 || true
  install_apk
}

run_flows() {
  local n="$1"
  local start end dur
  start=$(date +%s 2>/dev/null || echo 0)
  maestro --device "$DEVICE" test "$FLOW_DIR" \
    --format junit \
    --output "$REPORT_DIR/junit-attempt${n}.xml" \
    --test-output-dir "$REPORT_DIR/attempt${n}"
  local rc=$?
  end=$(date +%s 2>/dev/null || echo 0)
  dur=$((end - start))
  if device_alive; then
    echo "Attempt $n finished rc=$rc after ${dur}s; emulator alive: yes"
  else
    echo "Attempt $n finished rc=$rc after ${dur}s; emulator alive: NO"
  fi
  return $rc
}

install_apk
attempt=1
run_flows "$attempt"
rc=$?

while [ $rc -ne 0 ] && [ "$attempt" -lt "$MAX_RETRIES" ]; do
  attempt=$((attempt + 1))
  echo "Run failed; recovering device and retrying failed flows (attempt $attempt)"
  if ! device_alive; then
    relaunch_emulator
  fi
  run_flows "$attempt"
  rc=$?
done

cp "$REPORT_DIR/junit-attempt${attempt}.xml" "$REPORT_DIR/junit.xml" 2>/dev/null || true

# Lets bash print the background job's "Segmentation fault" line into this
# step's log before the step exits.
sleep 2

exit $rc
