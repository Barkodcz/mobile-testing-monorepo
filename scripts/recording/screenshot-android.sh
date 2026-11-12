#!/usr/bin/env bash
# Takes a single screenshot of the connected Android emulator/device via
# `adb exec-out screencap`. Used where the test framework has no built-in
# per-test screenshot API, so the video recording isn't the only visual
# artifact attached to the Tests tab.
#
# Usage: screenshot-android.sh <output.png>
# Never fails the build: prints the output path on success, empty on failure.
set -uo pipefail

OUT="${1:?usage: screenshot-android.sh <output.png>}"

if ! command -v adb >/dev/null 2>&1; then
  echo ""
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
if adb exec-out screencap -p > "$OUT" 2>/tmp/bitrise-screencap.log && [ -s "$OUT" ]; then
  echo "$OUT"
else
  echo "[recording] WARN: adb screencap failed (see /tmp/bitrise-screencap.log)" >&2
  rm -f "$OUT"
  echo ""
fi
