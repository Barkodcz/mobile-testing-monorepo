#!/usr/bin/env bash
# Starts `xcrun simctl io <device> recordVideo` in the background against a
# booted iOS Simulator. Call stop-ios-sim.sh to finalize and convert it.
#
# Usage: start-ios-sim.sh <udid-or-booted> <output.mov> [pidfile]
# Honors $RECORD_VIDEO (all|failures|off); "off" skips recording entirely.
set -uo pipefail

RECORD_VIDEO="${RECORD_VIDEO:-failures}"
if [ "$RECORD_VIDEO" = "off" ]; then
  echo "[recording] RECORD_VIDEO=off, not starting iOS simulator recording."
  exit 0
fi

DEVICE="${1:-booted}"
OUT="${2:-recording.mov}"
PIDFILE="${3:-/tmp/bitrise-ios-recording.pid}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "[recording] WARN: xcrun not found, skipping iOS simulator recording."
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$OUT" &
PID=$!
echo "$PID" > "$PIDFILE"
# Give recordVideo a moment to actually attach to the simulator's renderer
# before the test step starts driving the UI.
sleep 1
echo "[recording] Started iOS simulator recording (pid $PID) -> $OUT"
