#!/usr/bin/env bash
# pull_missing.sh — copy the files that aren't in the Takeout off the phone, keeping their dates,
# so you can upload them on photos.google.com.
# Google dates screenshots (no EXIF) by file modified time: `adb pull -a` keeps it, plain
# `adb pull` resets it to today and every screenshot would land on today's date.
#
# Usage: ./pull_missing.sh [LIST]          default: missing.txt   (other_years.txt works too)
set -uo pipefail
LIST="${1:-missing.txt}"
[ -f "$LIST" ] || { echo "$LIST not found; run ./verify_takeout.sh first"; exit 1; }
[ -s phone_dir.txt ] || { echo "phone_dir.txt not found; run ./phone_inventory.sh first"; exit 1; }
PHONE_DIR=$(cat phone_dir.txt)
[ "$(adb get-state 2>/dev/null)" = "device" ] || { echo "no phone connected (check: adb devices)"; exit 1; }

mkdir -p upload
ok=0; failed=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if adb pull -a "$PHONE_DIR/$f" "upload/$f" </dev/null >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    echo "failed: $f"; failed=$((failed + 1))
  fi
done < "$LIST"

echo "copied $ok file(s) to ./upload ($failed failed)"
echo "Drag them onto photos.google.com. Files Google already has are skipped, so no duplicates."
[ "$ok" -gt 0 ] && command -v open >/dev/null && open upload
exit 0
