# Google Photos Screenshot Cleanup

Free up Android storage safely: delete only the photos and screenshots **proven** to be in
Google Photos, by comparing the phone's file list with a Google Takeout. Mac + `adb`, no unzipping.

Tested on a Pixel 9 clearing tens of thousands of screenshots.

## The problem

- Google Photos says **Backup complete**, but backed-up files stay on the phone until something deletes them.
- The app's **Free up space** button offers to free gigabytes and frees a few megabytes. On Pixel,
  screenshots live in `Pictures/Screenshots`, a folder the Photos app isn't allowed to bulk-delete
  (Android scoped storage). Granting Photos the "Media management" permission doesn't fix it.
- The **Google Photos API** can no longer list your own library (since March 31, 2025), so no app
  can check what's backed up for you.

## The idea

A Google Takeout of your photos *is* a list of what Google has. Read the file names inside the Takeout
zips (without unzipping them), compare with the file names on the phone, upload the few that are
missing, then delete the confirmed ones from the phone over USB.

**Deleting a file on the phone never touches the cloud copy.** Only deleting *inside* the Google Photos
app or website removes the cloud copy. Never delete inside Photos to free space.

## Golden rules

1. **Local delete is safe; in-app delete is not.** `adb`, the Files app, or these scripts remove only
   the phone copy.
2. **Preserve file dates.** Google dates screenshots (which have no EXIF data) by their file modified
   time. Copy with `adb pull -a` or `tar`, never plain `adb pull`, or they all land on today's date.
3. **Re-uploading is safe.** Google skips files it already has, so uploading a file twice doesn't
   create a duplicate.
4. **Anything newer than the Takeout can't be in it.** That's expected, not a failed backup.
5. **Verify before you delete.** Only delete files whose names are confirmed in the Takeout.

## One-time setup (Mac)

```bash
brew install --cask android-platform-tools     # installs adb
```

On the phone: **Settings → About phone →** tap **Build number** 7 times → back → **System →
Developer options →** turn on **USB debugging**. Plug in over USB and tap **Allow** on the phone.

```bash
adb devices        # your phone should be listed as "device", not "unauthorized"
```

## Usage

Run the scripts from an empty working folder. They write their lists there (see `.gitignore`).

### 1. Request a Takeout

1. Make sure the Photos app on the phone says **Backup complete**, so recent files are included.
2. Go to **takeout.google.com** → **Deselect all** → tick **Google Photos**.
3. Click **All photo albums included** → **Deselect all** → tick only the **Photos from YYYY** years you
   want to clean up. Takeout has no date range; a whole year is the narrowest filter.
4. **Export once**, **.zip**, any file size → **Create export**.

> ⚠️ If you open Takeout from inside Google Photos, the page can open on step 2 with step 1 *collapsed*.
> Clicking **Create export** there exports your **entire** library. Reopen **Select data to include** first.

When the email arrives, download **all** parts into one folder with room (an external drive is ideal)
and check the number of files matches the number of parts listed on the download page.

### 2. List what's on the phone (copies nothing)

```bash
./phone_inventory.sh                                   # default: /sdcard/Pictures/Screenshots
./phone_inventory.sh /sdcard/DCIM/Camera               # or any other folder
```

### 3. Compare with the Takeout

```bash
./verify_takeout.sh /Volumes/MyDrive/takeout 2026      # folder with the zips, then the year(s) exported
```

```
VERIFIED (safe to delete): 1520
MISSING  (upload first)  : 6
other years (check)      : 2
```

- `verified.txt`: on the phone **and** in the Takeout. Safe to delete from the phone.
- `missing.txt`: not in the Takeout. Upload these first (step 4).
- `other_years.txt`: dated in a year you didn't export. Upload them too, or type a name into the
  search bar on photos.google.com to check.

It refuses to run while downloads are unfinished, warns if a part number is missing, stops on a damaged
zip, and saves nothing unless every phone file lands in exactly one list.

### 4. Upload the missing ones

```bash
./pull_missing.sh                  # copies missing.txt to ./upload, dates preserved
./pull_missing.sh other_years.txt  # optional
```

Drag the `upload` folder's files onto **photos.google.com**. Files Google already has are skipped.

### 5. Delete the verified files from the phone

```bash
./delete_verified.sh               # dry run: shows what would be deleted
./delete_verified.sh --delete      # delete
```

Only files in `verified.txt` that are still on the phone are deleted. The deletion runs on the phone
in a single `adb` call (seconds for thousands of files), and names with spaces or parentheses such as
`Screenshot_… (1).png` are handled. Afterwards it recounts, first checking the phone is still connected,
because a dropped USB link returns an empty listing that looks exactly like "0 files left".

After step 5 you can delete the Takeout zips.

## Do I need to copy everything off the phone first?

No. The comparison only needs the phone's **file list**. Only the few missing files are copied (step 4).
A full copy is worth it only if you want a permanent local archive so Google Photos isn't your only copy:

```bash
mkdir -p archive
adb exec-out "cd /sdcard/Pictures/Screenshots && tar -cf - *.png" | tar -xpf - -C archive   # keeps dates
```

## Limitations

- **Matching is by file name** (case-insensitive). That's reliable for uniquely named files like
  `Screenshot_20260101-120000.png` or `PXL_20260101_120000000.jpg`. For generic names like
  `IMG_0001.jpg`, a *different* photo with the same name in the Takeout would count as a match.
  Review `verified.txt` before deleting if your folder has names like that.
- A file that is backed up can still be missing from a Takeout occasionally. It then lands in
  `missing.txt`, which only means "upload it to be safe", never "it's lost".
- Year filtering uses each file's modified time. Files near midnight on New Year's Eve may land in
  `other_years.txt`. That's the safe direction: they're checked by hand, not deleted.
- Written for macOS (bash, `unzip`, `perl`, `awk`, `comm`); should also work on Linux.
- More than one phone connected? `export ANDROID_SERIAL=<serial from adb devices>`.

## Troubleshooting

- **`unauthorized` in `adb devices`:** unlock the phone, replug the cable, tap **Allow**.
  Still stuck: `adb kill-server && adb start-server`.
- **Only run one cleanup at a time.** Two runs (or two tools) comparing or deleting at once give
  confusing counts. `verify_takeout.sh` uses a lock to prevent overlapping runs.
