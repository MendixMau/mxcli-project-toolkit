#!/usr/bin/env bash
# PreToolUse(Read) — downscale oversized images before they enter the context window.
#
# Why: a retina screenshot Read into a session is ~500KB of base64 that then rides
# along in the prefix of every subsequent turn. Measured on one Mendix project: 100 such
# reads accounted for 94% of one session's 19.7MB of tool-result mass.
#
# This rewrites the Read's file_path to point at a downscaled copy. Fail-open:
# any error passes the original Read through untouched.
#
# Resizer, first one found: sips (macOS), ImageMagick (magick / convert), python3 with
# Pillow. JSON via jq, else python3. WHY (field run 2026-10-07): this hook needed sips,
# jq and md5, all macOS-only or often absent, so on Linux and Git Bash it was a silent
# no-op — while screenshot reads were 11.5% of one run's re-read tokens.
#
# Tunables: CLAUDE_IMG_MAX_BYTES (default 150000), CLAUDE_IMG_MAX_DIM (default 1024)
# Bypass entirely: CLAUDE_IMG_SHRINK=0

set -u

[ "${CLAUDE_IMG_SHRINK:-1}" = "0" ] && exit 0

MAX_BYTES=${CLAUDE_IMG_MAX_BYTES:-150000}
MAX_DIM=${CLAUDE_IMG_MAX_DIM:-1024}
CACHE="${TMPDIR:-/tmp}/claude-shrunk"

PY=""
for c in python3 python py; do  # portability-ok: installed to ~/.claude/hooks, cannot source portable.sh; same probe list
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info[0] < 3)' 2>/dev/null \
    && { PY="$c"; break; }
done
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
[ "$HAVE_JQ" = 1 ] || [ -n "$PY" ] || exit 0

RESIZER=""
if command -v sips >/dev/null 2>&1; then RESIZER=sips
elif command -v magick >/dev/null 2>&1; then RESIZER=magick
elif command -v convert >/dev/null 2>&1 && convert -version 2>/dev/null | grep -q ImageMagick; then RESIZER=convert
elif [ -n "$PY" ] && "$PY" -c 'import PIL' 2>/dev/null; then RESIZER=pil
fi
[ -n "$RESIZER" ] || exit 0

input=$(cat)
if [ "$HAVE_JQ" = 1 ]; then
  path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  path=$(printf '%s' "$input" | "$PY" -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path") or "")' 2>/dev/null)
fi
[ -n "$path" ] || exit 0
[ -f "$path" ] || exit 0

# Image extensions the resizers can read.
ext=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  png|jpg|jpeg|tif|tiff|bmp|gif|heic|webp) ;;
  *) exit 0 ;;
esac

# `stat -f` is BSD-only. This is an installed hook, so a Linux or Git Bash user hit it in
# every session. Try BSD, then GNU, then wc -c, and only then give up.
bytes=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null \
        || wc -c < "$path" 2>/dev/null | tr -d ' ') || exit 0
[ -n "$bytes" ] || exit 0
[ "$bytes" -gt "$MAX_BYTES" ] 2>/dev/null || exit 0

mtime=$(stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null)
key=$(printf '%s:%s:%s:%s' "$path" "$mtime" "$bytes" "$MAX_DIM" \
      | { md5 -q 2>/dev/null || md5sum 2>/dev/null || cksum; } | awk '{print $1}')
[ -n "$key" ] || exit 0

mkdir -p "$CACHE" 2>/dev/null || exit 0
out="$CACHE/$key.png"

if [ ! -f "$out" ]; then
  case "$RESIZER" in
    sips) sips --setProperty format png --resampleHeightWidthMax "$MAX_DIM" \
               "$path" --out "$out" >/dev/null 2>&1 ;;
    magick|convert) "$RESIZER" "$path[0]" -resize "${MAX_DIM}x${MAX_DIM}>" "png:$out" >/dev/null 2>&1 ;;
    pil) "$PY" -c 'import sys
from PIL import Image
im = Image.open(sys.argv[1]); im.thumbnail((int(sys.argv[3]),) * 2)
(im if im.mode in ("RGB", "RGBA", "L", "LA", "P") else im.convert("RGBA")).save(sys.argv[2], "PNG", optimize=True)' \
           "$path" "$out" "$MAX_DIM" >/dev/null 2>&1 ;;
  esac || { rm -f "$out"; exit 0; }
fi
[ -s "$out" ] || exit 0

newbytes=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out" 2>/dev/null \
           || wc -c < "$out" 2>/dev/null | tr -d ' ' || echo "$bytes")
# If shrinking didn't actually help, don't bother redirecting.
[ "$newbytes" -lt "$bytes" ] 2>/dev/null || exit 0

# The Read now lands on the copy, so a PostToolUse(Read) hook sees the copy's path. Leave the
# original beside it: project-bin/look-ledger.sh reads this to record which screenshot was seen.
printf '%s\n' "$path" > "$CACHE/$key.src" 2>/dev/null || true

if [ "$HAVE_JQ" = 1 ]; then
  printf '%s' "$input" | jq -c \
    --arg p "$out" \
    --arg orig "$path" \
    --arg dim "$MAX_DIM" \
    '{
       hookSpecificOutput: {
         hookEventName: "PreToolUse",
         updatedInput: (.tool_input + {file_path: $p}),
         additionalContext: ("Downscaled copy of \($orig) (max \($dim)px). Refer to the original path in your output.")
       }
     }'
else
  printf '%s' "$input" | "$PY" -c 'import json,sys
d = json.load(sys.stdin); ti = dict(d.get("tool_input") or {}); ti["file_path"] = sys.argv[1]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti,
  "additionalContext": "Downscaled copy of %s (max %spx). Refer to the original path in your output." % (sys.argv[2], sys.argv[3])}}))' \
    "$out" "$path" "$MAX_DIM" || exit 0
fi
exit 0
