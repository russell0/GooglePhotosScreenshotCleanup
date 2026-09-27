#!/usr/bin/env bash
# delete_verified.sh — delete from the phone ONLY the files listed in verified.txt.
# Deleting a file on the phone never touches the Google Photos copy.
#
#   ./delete_verified.sh            dry run: shows what would happen, deletes nothing
#   ./delete_verified.sh --delete   delete
set -uo pipefail
LIST="verified.txt"
[ -d .verify_takeout.lock ] && { echo "verify_takeout.sh is still running; wait for it"; exit 1; }
[ -s "$LIST" ] || { echo "$LIST is missing or empty; run ./verify_takeout.sh first"; exit 1; }
[ -s phone_dir.txt ] || { echo "phone_dir.txt not found; run ./phone_inventory.sh first"; exit 1; }
PHONE_DIR=$(cat phone_dir.txt)

connected() { [ "$(adb get-state 2>/dev/null)" = "device" ]; }
list_phone() { adb shell "cd '$PHONE_DIR' && ls -1p" | tr -d '\r' | { grep -v '/$' || true; } | sort; }   # files only
free_space() { adb shell df -h /sdcard | tail -1 | awk '{print $4}' | tr -d '\r'; }

connected || { echo "no phone connected (check: adb devices)"; exit 1; }
list_phone > .phone_now.txt || { echo "could not list $PHONE_DIR"; exit 1; }
sort -u "$LIST" > .verified_sorted.txt
comm -12 .phone_now.txt .verified_sorted.txt > .to_delete.txt

echo "phone folder   : $PHONE_DIR"
echo "files on phone : $(wc -l < .phone_now.txt | tr -d ' ')"
echo "will delete    : $(wc -l < .to_delete.txt | tr -d ' ')  (verified in the Takeout)"
echo "will keep      : $(comm -23 .phone_now.txt .verified_sorted.txt | wc -l | tr -d ' ')"
echo "phone free     : $(free_space)"

if [ "${1:-}" != "--delete" ]; then
  echo; echo "Dry run: nothing deleted. Run with --delete to delete."; exit 0
fi
[ -s .to_delete.txt ] || { echo "nothing to delete"; exit 0; }

# Delete ON the phone in one adb call: seconds for thousands of files, and names with spaces
# or parentheses are safe because each line of the list is one name.
cat > .ondevice_delete.sh <<'EOF'
# $1 = phone folder, $2 = list of names to delete (one per line)
cd "$1" || exit 1
n=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -e "$f" ] && rm -f -- "$f" && n=$((n + 1))
done < "$2"
echo "deleted $n"
rm -f "$2" "$0"
EOF
adb push .to_delete.txt /data/local/tmp/cleanup_delete.txt >/dev/null || { echo "adb push failed"; exit 1; }
adb push .ondevice_delete.sh /data/local/tmp/cleanup_delete.sh >/dev/null || { echo "adb push failed"; exit 1; }
adb shell "sh /data/local/tmp/cleanup_delete.sh '$PHONE_DIR' /data/local/tmp/cleanup_delete.txt" | tr -d '\r'
rm -f .ondevice_delete.sh

# If the USB link dropped, `ls` returns nothing, which would look like "0 left". Check first.
connected || { echo "PHONE DISCONNECTED: can't confirm the result. Reconnect and run the dry run again."; exit 1; }
list_phone > .phone_after.txt || { echo "could not list $PHONE_DIR after deleting"; exit 1; }
echo "verified files still on phone (want 0): $(comm -12 .phone_after.txt .verified_sorted.txt | wc -l | tr -d ' ')"
echo "files left in folder                  : $(wc -l < .phone_after.txt | tr -d ' ')"
echo "phone free now                        : $(free_space)"
