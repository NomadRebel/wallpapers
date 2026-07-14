#!/bin/bash
#
# backfill_thumbnails.sh
# One-off script: generates thumbnails for every image already in CONTENT_DIR
# that doesn't have one yet in THUMB_DIR. Run this once after adding the
# thumbnail feature, to catch up on wallpapers added before it existed.
# Also updates existing <img src="content/..."> tags in the HTML to point
# at the new thumbnails.
#
# Requires: ImageMagick (sudo apt install imagemagick)

set -euo pipefail

# ─── CONFIG — match these to watch_wallpapers.sh ────────────────────────────
CONTENT_DIR="$HOME/wallpaperss/wallpapers/content"
THUMB_DIR="$HOME/wallpaperss/wallpapers/thumbnails"
HTML_FILE="$HOME/wallpaperss/wallpapers/index.html"

THUMB_WIDTH=400
THUMB_QUALITY=75
# ──────────────────────────────────────────────────────────────────────────

if ! command -v convert &>/dev/null; then
    echo "ERROR: ImageMagick not found. Install it with: sudo apt install imagemagick"
    exit 1
fi

mkdir -p "$THUMB_DIR"

count=0
for src in "$CONTENT_DIR"/*; do
    [[ -f "$src" ]] || continue
    filename="$(basename "$src")"
    thumb="$THUMB_DIR/$filename"

    if [[ -e "$thumb" ]]; then
        continue   # already has a thumbnail
    fi

    if convert "$src" -resize "${THUMB_WIDTH}x" -strip -quality "$THUMB_QUALITY" "$thumb"; then
        echo "Created thumbnail for $filename"
        count=$((count + 1))
    else
        echo "WARNING: failed to create thumbnail for $filename"
    fi
done

echo "Done. Created $count new thumbnail(s)."

# Update the HTML: for any <img src="content/X"> where a thumbnail for X exists,
# switch it to <img src="thumbnails/X"> (href stays pointing at the full image).
if [[ -f "$HTML_FILE" ]]; then
    updated=0
    while IFS= read -r -d '' thumb_file; do
        filename="$(basename "$thumb_file")"
        if grep -qF "src=\"content/${filename}\"" "$HTML_FILE"; then
            sed -i "s|src=\"content/${filename}\"|src=\"thumbnails/${filename}\"|g" "$HTML_FILE"
            updated=$((updated + 1))
        fi
    done < <(find "$THUMB_DIR" -type f -print0)
    echo "Updated $updated <img> tag(s) in $HTML_FILE to use thumbnails."
fi
