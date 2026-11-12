#!/usr/bin/env bash
# Stops the recording loop started by start-android.sh and pulls every chunk
# to a local directory. Never fails the build: recording problems are logged
# as warnings only. Always run this with is_always_run: true so the video is
# kept even when the test step itself failed.
#
# Usage: stop-android.sh <device-dir> <local-out-dir> [pidfile]
set -uo pipefail

RECORD_VIDEO="${RECORD_VIDEO:-failures}"
if [ "$RECORD_VIDEO" = "off" ]; then
  exit 0
fi

DEVICE_DIR="${1:-/sdcard/bitrise-recordings}"
LOCAL_DIR="${2:-recordings}"
PIDFILE="${3:-/tmp/bitrise-android-recording.pid}"

mkdir -p "$LOCAL_DIR"

if [ -f "$PIDFILE" ]; then
  LOOP_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$LOOP_PID" ]; then
    # Stop the loop first so it doesn't spawn another chunk once we interrupt
    # the current one, then SIGINT (never -9 — that corrupts the mp4) the
    # in-flight `adb shell screenrecord` so it finalizes the container.
    CHILD_PID="$(pgrep -P "$LOOP_PID" 2>/dev/null | head -n1 || true)"
    kill "$LOOP_PID" 2>/dev/null || true
    if [ -n "$CHILD_PID" ]; then
      kill -INT "$CHILD_PID" 2>/dev/null || true
    fi
    sleep 2
  fi
  rm -f "$PIDFILE"
else
  echo "[recording] WARN: no pidfile at $PIDFILE, nothing to stop."
fi

if command -v adb >/dev/null 2>&1; then
  adb pull "$DEVICE_DIR" "$LOCAL_DIR" >/tmp/bitrise-android-pull.log 2>&1 \
    || echo "[recording] WARN: adb pull failed, continuing without video (see /tmp/bitrise-android-pull.log)"
  adb shell "rm -rf $DEVICE_DIR" >/dev/null 2>&1 || true
else
  echo "[recording] WARN: adb not found, could not pull recordings."
fi

echo "[recording] Done. Recordings (if any) are under $LOCAL_DIR."
