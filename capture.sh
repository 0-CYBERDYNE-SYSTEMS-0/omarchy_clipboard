#!/bin/bash

# Captures the current clipboard as a JSON entry on stdout. In watch mode,
# wl-paste invokes this with the payload on stdin and the mime as $1. Without
# arguments, it snapshots the current selection itself.
#
# Oversize clips are dropped, not truncated: 16 KiB text, 10 MiB per image,
# 50 MiB image-cache total. Stdin ingest is also time-bounded.

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
TEXT_MAX=16384
IMAGE_MAX=10485760
IMAGE_CACHE_MAX=52428800

mkdir -p -m 700 "$STATE_DIR" "$IMAGE_DIR"

# Application-controlled MIME lists can hang or flood. Bound the producer
# itself and fail closed on timeout or overflow.
TYPES_MAX=4096
types_tmp=$(mktemp --tmpdir="$STATE_DIR" clipboard-types.XXXXXX) || exit 0
if ! timeout 2s wl-paste --list-types 2>/dev/null | head -c "$((TYPES_MAX + 1))" >"$types_tmp"; then
  rm -f "$types_tmp"
  exit 0
fi
types_size=$(stat -c '%s' -- "$types_tmp" 2>/dev/null) || types_size=0
if (( types_size == 0 || types_size > TYPES_MAX )); then
  rm -f "$types_tmp"
  exit 0
fi
types=$(<"$types_tmp")
rm -f "$types_tmp"

if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

captured_at=$(date -Iseconds)

read_capped() {
  local dest="$1" max="$2"
  if ! timeout 2s head -c "$((max + 1))" >"$dest"; then
    rm -f "$dest"
    return 1
  fi
  local size
  size=$(stat -c '%s' -- "$dest" 2>/dev/null) || size=0
  if (( size == 0 || size > max )); then
    rm -f "$dest"
    return 1
  fi
  return 0
}

emit_image() {
  local mime="$1"
  local ext tmp hash file cache

  ext=${mime#image/}
  [[ $ext == jpeg ]] && ext=jpg

  tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
  read_capped "$tmp" "$IMAGE_MAX" || return 0

  cache=$(du -sb "$IMAGE_DIR" 2>/dev/null | awk '{print $1}')
  cache=${cache:-0}
  if (( cache > IMAGE_CACHE_MAX )); then
    rm -f "$tmp"
    return 0
  fi

  hash=$(sha256sum "$tmp" | awk '{print $1}')
  file="$IMAGE_DIR/$hash.$ext"
  if [[ -e $file ]]; then
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
  fi

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$captured_at" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text() {
  local tmp
  tmp=$(mktemp --tmpdir="$STATE_DIR" clipboard-text.XXXXXX) || return 0
  if ! read_capped "$tmp" "$TEXT_MAX"; then
    return 0
  fi
  jq -cRs --arg captured_at "$captured_at" \
    'select(length > 0) | {type:"text", text:., capturedAt:$captured_at}' <"$tmp"
  rm -f "$tmp"
}

case "${1:-}" in
text) emit_text; exit 0 ;;
image/*) emit_image "$1"; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  timeout 2s wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
