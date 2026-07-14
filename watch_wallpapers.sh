#!/bin/bash
#
# watch_wallpapers.sh
# Watches a folder for new wallpaper images and automatically:
#   1. Moves the image into your site's content/ folder
#   2. Appends a matching <div class="content">...</div> block to index.html
#
# Requires: inotify-tools  (install with: sudo apt install inotify-tools)

set -euo pipefail

# ─── CONFIG — edit these paths for your setup ───────────────────────────────
WATCH_DIR="$HOME/wallpaperss/wallpapers/content"                        # folder you drop new wallpapers into
CONTENT_DIR="$HOME/wallpaperss/wallpapers/content"        # full-res images live here
THUMB_DIR="$HOME/wallpaperss/wallpapers/thumbnails"       # compressed thumbnails go here
HTML_FILE="$HOME/wallpaperss/wallpapers/index.html"       # the HTML file to update

THUMB_WIDTH=400        # thumbnail width in pixels (height auto-scales)
THUMB_QUALITY=75       # JPEG/WebP quality, 0-100 (lower = smaller file)
# ──────────────────────────────────────────────────────────────────────────

MARKER="<!-- WALLPAPER_INSERT_POINT -->"
VALID_EXT_REGEX='\.(jpe?g|png|gif|webp)$'

# Make sure ImageMagick is installed
if ! command -v convert &>/dev/null; then
    echo "ERROR: ImageMagick not found. Install it with: sudo apt install imagemagick"
    exit 1
fi

mkdir -p "$THUMB_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

declare -A RECENTLY_PROCESSED   # guards against duplicate events for the same file

add_wallpaper() {
    local src_path="$1"
    local filename
    filename="$(basename "$src_path")"

    # Skip non-image files
    if ! [[ "$filename" =~ $VALID_EXT_REGEX ]]; then
        return
    fi

    # Some browsers/downloaders fire multiple events (close_write + moved_to,
    # or several close_write's while flushing) for what is really one download.
    # If we've already handled this exact filename in this run, skip it.
    if [[ -n "${RECENTLY_PROCESSED[$filename]:-}" ]]; then
        return
    fi

    # If the source file no longer exists, it was already moved by an earlier
    # (duplicate) event — nothing to do.
    if [[ ! -e "$src_path" ]]; then
        return
    fi

    # Belt-and-suspenders: if this filename is already referenced in the HTML,
    # don't add it again.
    if grep -qF "content/${filename}\"" "$HTML_FILE" 2>/dev/null; then
        RECENTLY_PROCESSED["$filename"]=1
        return
    fi

    RECENTLY_PROCESSED["$filename"]=1

    # Wait until the file is fully written (size stops changing)
    local prev_size=-1 cur_size=0
    while [[ "$prev_size" != "$cur_size" ]]; do
        prev_size="$cur_size"
        sleep 0.5
        cur_size=$(stat -c%s "$src_path" 2>/dev/null || echo -1)
    done

    # Avoid overwriting an existing file with the same name
    local dest="$CONTENT_DIR/$filename"
    if [[ -e "$dest" ]]; then
        local base="${filename%.*}" ext="${filename##*.}"
        local n=1
        while [[ -e "$CONTENT_DIR/${base}-${n}.${ext}" ]]; do
            n=$((n + 1))
        done
        filename="${base}-${n}.${ext}"
        dest="$CONTENT_DIR/$filename"
    fi

    mv "$src_path" "$dest"
    log "Moved '$filename' -> $CONTENT_DIR/"

    # Generate a compressed thumbnail (resized to THUMB_WIDTH, quality THUMB_QUALITY)
    local thumb_path="$THUMB_DIR/$filename"
    if convert "$dest" -resize "${THUMB_WIDTH}x" -strip -quality "$THUMB_QUALITY" "$thumb_path" 2>/tmp/thumb_err.log; then
        log "Created thumbnail -> $THUMB_DIR/$filename"
    else
        log "WARNING: thumbnail generation failed for $filename ($(cat /tmp/thumb_err.log)); falling back to full image in grid"
        thumb_path=""   # fall back to full-res image below if thumbnail failed
    fi

    # Work out the next wallpaperN number by scanning the HTML file
    local last_num next_num
    last_num=$(grep -oP 'alt="wallpaper\K[0-9]+' "$HTML_FILE" | sort -n | tail -1 || true)
    if [[ -z "$last_num" ]]; then
        next_num=1
    else
        next_num=$((last_num + 1))
    fi

    # img src uses the thumbnail (fast-loading grid); href/click still opens the full-res original
    local img_src="content/${filename}"
    if [[ -n "$thumb_path" ]]; then
        img_src="thumbnails/${filename}"
    fi

    # Build the new block (matches your existing indentation style)
    local block
    block=$(cat <<EOF
            <div class="content">
                <a href="content/${filename}" target="_blank">
                    <img src="${img_src}" alt="wallpaper${next_num}">
                </a>
            </div>
EOF
)

    if ! grep -qF "$MARKER" "$HTML_FILE"; then
        log "ERROR: Marker '$MARKER' not found in $HTML_FILE."
        log "Add it just before the closing </div> of <div class=\"body\"> and try again."
        return
    fi

    # Insert the block right before the marker, using awk (safe with multi-line content)
    awk -v block="$block" -v marker="$MARKER" '
        index($0, marker) { print block }
        { print }
    ' "$HTML_FILE" > "${HTML_FILE}.tmp" && mv "${HTML_FILE}.tmp" "$HTML_FILE"

    log "Added wallpaper${next_num} (${filename}) to $HTML_FILE"
}

log "Watching $WATCH_DIR for new wallpapers... (Ctrl+C to stop)"

inotifywait -m -e close_write -e moved_to --format '%w%f' "$WATCH_DIR" | while read -r filepath; do
    add_wallpaper "$filepath"
done
