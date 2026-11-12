#!/usr/bin/env bash
# Starts a looping `adb shell screenrecord` in the background against the
# currently connected Android emulator/device.
#
# screenrecord stops itself after ~180s by design, so this relaunches it in a
# loop to cover longer test runs, each chunk written to its own file on the
# device. Call stop-android.sh to end the loop and pull the chunks.
#
# Usage: start-android.sh <device-dir> <basename> [pidfile]
# Honors $RECORD_VIDEO (all|failures|off); "off" skips recording entirely.
set -uo pipefail

RECORD_VIDEO="${RECORD_VIDEO:-failures}"
if [ "$RECORD_VIDEO" = "off" ]; then
  echo "[recording] RECORD_VIDEO=off, not starting Android screen recording."
  exit 0
fi

DEVICE_DIR="${1:-/sdcard/bitrise-recordings}"
BASENAME="${2:-session}"
PIDFILE="${3:-/tmp/bitrise-android-recording.pid}"

if ! command -v adb >/dev/null 2>&1; then
  echo "[recording] WARN: adb not found, skipping Android screen recording."
  exit 0
fi

adb shell "mkdir -p $DEVICE_DIR" || {
  echo "[recording] WARN: could not create $DEVICE_DIR on device, skipping recording."
  exit 0
}

(
  i=0
  while :; do
    i=$((i + 1))
    adb shell screenrecord --bit-rate 2000000 "$DEVICE_DIR/${BASENAME}_chunk${i}.mp4" 2>/tmp/bitrise-android-recording.log
  done
) &
LOOP_PID=$!
echo "$LOOP_PID" > "$PIDFILE"
echo "[recording] Started Android screen recording loop (pid $LOOP_PID) -> device:$DEVICE_DIR"
