#!/usr/bin/env bash
# Concatenates the numbered mp4 chunks produced by start-android.sh's
# screenrecord loop into one file, so a long test run's recording is a
# single attachable video instead of several ~180s pieces.
#
# Usage: concat-chunks.sh <glob-of-chunks> <output.mp4>
# Prints the path of the file to actually attach (the combined file, the
# single chunk if there was only one, or empty if none were found) to stdout
# -- the caller should capture it, e.g.:
#   RECORDING="$(scripts/recording/concat-chunks.sh "$DIR/*_chunk*.mp4" "$DIR/combined.mp4")"
set -uo pipefail

PATTERN="${1:?usage: concat-chunks.sh <glob> <output.mp4>}"
OUT="${2:?usage: concat-chunks.sh <glob> <output.mp4>}"

# shellcheck disable=SC2206 -- intentional word-splitting of a glob
CHUNKS=($PATTERN)
if [ ! -e "${CHUNKS[0]:-}" ]; then
  echo "" # no chunks found
  exit 0
fi

if [ "${#CHUNKS[@]}" -eq 1 ]; then
  echo "${CHUNKS[0]}"
  exit 0
fi

if command -v ffmpeg >/dev/null 2>&1; then
  LIST_FILE="$(mktemp)"
  for f in "${CHUNKS[@]}"; do
    printf "file '%s'\n" "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" >> "$LIST_FILE"
  done
  if ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST_FILE" -c copy "$OUT" 2>/tmp/bitrise-concat.log; then
    echo "$OUT"
  else
    echo "[recording] WARN: ffmpeg concat failed (see /tmp/bitrise-concat.log), using first chunk only." >&2
    echo "${CHUNKS[0]}"
  fi
  rm -f "$LIST_FILE"
else
  echo "[recording] WARN: multiple recording chunks but no ffmpeg to concat them, using first chunk only." >&2
  echo "${CHUNKS[0]}"
fi
