#!/usr/bin/env bash
# Stops the recording started by start-ios-sim.sh with SIGINT (never -9 —
# that corrupts the .mov's moov atom), waits for simctl to finalize the file,
# then converts to .mp4 since Bitrise Test Reports only accepts
# .jpg/.jpeg/.png/.txt/.log/.mp4/.webm/.ogg, not .mov.
#
# Usage: stop-ios-sim.sh <recording.mov> <output.mp4> [pidfile]
set -uo pipefail

RECORD_VIDEO="${RECORD_VIDEO:-failures}"
if [ "$RECORD_VIDEO" = "off" ]; then
  exit 0
fi

MOV="${1:-recording.mov}"
MP4="${2:-recording.mp4}"
PIDFILE="${3:-/tmp/bitrise-ios-recording.pid}"

if [ -f "$PIDFILE" ]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$PID" ]; then
    kill -INT "$PID" 2>/dev/null || true
    for _ in $(seq 1 15); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 1
    done
  fi
  rm -f "$PIDFILE"
fi

if [ ! -s "$MOV" ]; then
  echo "[recording] WARN: no recording found at $MOV, skipping conversion."
  exit 0
fi

if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -y -loglevel error -i "$MOV" -c:v libx264 -an "$MP4" \
    && rm -f "$MOV" \
    || echo "[recording] WARN: ffmpeg conversion of $MOV failed, keeping the .mov (won't be attachable)."
else
  echo "[recording] WARN: ffmpeg not available, cannot convert $MOV to mp4."
fi
