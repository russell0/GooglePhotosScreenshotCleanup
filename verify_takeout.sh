#!/usr/bin/env bash
# verify_takeout.sh — check which phone files are in a Google Takeout of Google Photos.
# Reads only each zip's table of contents (unzip -Z1): nothing is extracted.
# Needs phone_manifest.txt from ./phone_inventory.sh.
#
# Usage: ./verify_takeout.sh TAKEOUT_DIR [YEAR ...]
#   TAKEOUT_DIR  folder holding ALL the takeout-*.zip parts (and nothing else)
#   YEAR ...     the "Photos from YYYY" albums you exported, e.g. 2026. Phone files dated in other
#                years can't be in the export, so they go to other_years.txt rather than missing.txt.
#                Omit to treat every file as covered by the export.
#
# Writes (in the current directory):
#   verified.txt     on the phone AND in the Takeout   -> safe to delete from the phone
#   missing.txt      on the phone, NOT in the Takeout  -> upload these first
#   other_years.txt  dated outside YEAR ...            -> check by hand on photos.google.com
set -uo pipefail
DIR="${1:?usage: $0 TAKEOUT_DIR [YEAR ...]}"; shift
YEARS="$*"
MANIFEST="phone_manifest.txt"
[ -s "$MANIFEST" ] || { echo "$MANIFEST is missing or empty; run ./phone_inventory.sh first"; exit 1; }

# one run at a time: two overlapping runs writing the same lists produce double counts
LOCK=".verify_takeout.lock"
mkdir "$LOCK" 2>/dev/null || { echo "verify_takeout.sh is already running here (stale lock? rmdir $LOCK)"; exit 1; }
trap 'rmdir "$LOCK"' EXIT
# clear old results first, so a failed run can't leave a stale verified.txt behind
rm -f verified.txt missing.txt other_years.txt

shopt -s nullglob
zips=("$DIR"/takeout-*.zip)
[ ${#zips[@]} -gt 0 ] || { echo "no takeout-*.zip files in $DIR"; exit 1; }
partial=("$DIR"/*.crdownload "$DIR"/*.download "$DIR"/*.part)
[ ${#partial[@]} -eq 0 ] || { echo "downloads still in progress in $DIR; wait for them to finish"; exit 1; }

# parts are numbered -001, -002, ...; a gap means a part was never downloaded
nums=$(for z in "${zips[@]}"; do basename "$z" .zip | sed -nE 's/.*-([0-9]{3})$/\1/p'; done | sed 's/^0*//' | sort -n)
if [ -n "$nums" ]; then
  have=$(printf '%s\n' "$nums" | wc -l | tr -d ' '); top=$(printf '%s\n' "$nums" | tail -1)
  [ "$have" -eq "$top" ] || echo "WARNING: $have parts found but numbering reaches $top; a part may be missing"
fi

: > takeout_names.tmp
for z in "${zips[@]}"; do
  unzip -Z1 "$z" 2>/dev/null | sed 's#.*/##' >> takeout_names.tmp \
    || { echo "unreadable zip (re-download it): $(basename "$z")"; exit 1; }
done
# a very large video can arrive as its own non-zip part
for f in "$DIR"/*; do
  case "$f" in *.zip) ;; *) [ -f "$f" ] && basename "$f" >> takeout_names.tmp ;; esac
done
sort -u takeout_names.tmp > takeout_names.txt && rm -f takeout_names.tmp

# year of each phone file from its modified time (how Google files screenshots without EXIF)
perl -F'\|' -lane 'print +(localtime($F[1]))[5] + 1900, "|", join("|", @F[2..$#F])' "$MANIFEST" > .phone_years.tmp

: > verified.tmp; : > missing.tmp; : > other_years.tmp
awk -F'|' -v years=" $YEARS " '
  NR == FNR { have[tolower($0)] = 1; next }
  {
    y = $1; name = substr($0, length(y) + 2)
    if (years != "  " && index(years, " " y " ") == 0) print name > "other_years.tmp"
    else if (tolower(name) in have)                    print name > "verified.tmp"
    else                                               print name > "missing.tmp"
  }' takeout_names.txt .phone_years.tmp
rm -f .phone_years.tmp

# every phone file must land in exactly one list, exactly once; otherwise save nothing
n_phone=$(wc -l < "$MANIFEST" | tr -d ' ')
n_lists=$(cat verified.tmp missing.tmp other_years.tmp | wc -l | tr -d ' ')
n_unique=$(cat verified.tmp missing.tmp other_years.tmp | sort -u | wc -l | tr -d ' ')
if [ "$n_lists" -ne "$n_phone" ] || [ "$n_unique" -ne "$n_phone" ]; then
  echo "SANITY CHECK FAILED: lists hold $n_lists ($n_unique unique) but the phone has $n_phone; nothing saved"
  rm -f verified.tmp missing.tmp other_years.tmp verified.txt missing.txt other_years.txt; exit 1
fi
mv verified.tmp verified.txt; mv missing.tmp missing.txt; mv other_years.tmp other_years.txt

echo "================ TAKEOUT CHECK ================"
echo "zip parts read           : ${#zips[@]}"
echo "names in Takeout         : $(wc -l < takeout_names.txt | tr -d ' ')"
echo "files on phone           : $n_phone"
echo "-----------------------------------------------"
echo "VERIFIED (safe to delete): $(wc -l < verified.txt | tr -d ' ')"
echo "MISSING  (upload first)  : $(wc -l < missing.txt | tr -d ' ')"
[ -n "$YEARS" ] && echo "other years (check)      : $(wc -l < other_years.txt | tr -d ' ')"
echo "==============================================="
exit 0
