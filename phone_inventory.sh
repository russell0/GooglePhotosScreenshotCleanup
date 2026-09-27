#!/usr/bin/env bash
# phone_inventory.sh — list the files in one phone folder over adb. Copies nothing.
#
# Writes (in the current directory):
#   phone_manifest.txt  one line per file: size|modified_time_epoch|name
#   phone_dir.txt       the phone folder, so the later steps act on the same folder
#
# Usage: ./phone_inventory.sh [PHONE_DIR]        default: /sdcard/Pictures/Screenshots
# More than one phone plugged in? export ANDROID_SERIAL=<serial from `adb devices`>
set -uo pipefail
PHONE_DIR="${1:-/sdcard/Pictures/Screenshots}"

[ "$(adb get-state 2>/dev/null)" = "device" ] || { echo "no phone connected (check: adb devices)"; exit 1; }
adb shell "test -d '$PHONE_DIR'" || { echo "no such folder on the phone: $PHONE_DIR"; exit 1; }

# one stat call for every non-hidden entry; keep regular files only (skips subfolders)
adb shell "cd '$PHONE_DIR' && stat -c '%F|%s|%Y|%n' * 2>/dev/null" | tr -d '\r' \
  | grep '^regular file|' | cut -d'|' -f2- | sort -t'|' -k3 > phone_manifest.tmp

mv phone_manifest.tmp phone_manifest.txt
printf '%s\n' "$PHONE_DIR" > phone_dir.txt
echo "files on phone: $(wc -l < phone_manifest.txt | tr -d ' ')  ($PHONE_DIR) -> phone_manifest.txt"
