#!/bin/bash

set -euo pipefail

# CONFIG 
WATCH_DIR="$HOME/wallpaperss/wallpapers/content"          # folder to drop new wallpapers into
CONTENT_DIR="$HOME/wallpaperss/wallpapers/content"        # where images live on your site
HTML_FILE="$HOME/wallpaperss/wallpapers/index.html"       # the HTML file to update
# ──────────────────────────────────────────────────────────────────────────

MARKER="<!-- WALLPAPER_INSERT_POINT -->"
VALID_EXT_REGEX='\.(jpe?g|png|gif|webp)$'

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
            ((n++))
        done
        filename="${base}-${n}.${ext}"
        dest="$CONTENT_DIR/$filename"
    fi

    mv "$src_path" "$dest"
    log "Moved '$filename' -> $CONTENT_DIR/"

    # Work out the next wallpaperN number by scanning the HTML file
    local last_num next_num
    last_num=$(grep -oP 'alt="wallpaper\K[0-9]+' "$HTML_FILE" | sort -n | tail -1 || true)
    if [[ -z "$last_num" ]]; then
        next_num=1
    else
        next_num=$((last_num + 1))
    fi

    # Build the new block (matches your existing indentation style)
    local block
    block=$(cat <<EOF
            <div class="content">
                <a href="content/${filename}" target="_blank">
                    <img src="content/${filename}" alt="wallpaper${next_num}">
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
