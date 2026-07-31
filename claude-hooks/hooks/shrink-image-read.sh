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
# Tunables: CLAUDE_IMG_MAX_BYTES (default 150000), CLAUDE_IMG_MAX_DIM (default 1024)
# Bypass entirely: CLAUDE_IMG_SHRINK=0

set -u

[ "${CLAUDE_IMG_SHRINK:-1}" = "0" ] && exit 0

MAX_BYTES=${CLAUDE_IMG_MAX_BYTES:-150000}
MAX_DIM=${CLAUDE_IMG_MAX_DIM:-1024}
CACHE="${TMPDIR:-/tmp}/claude-shrunk"

command -v jq   >/dev/null 2>&1 || exit 0
command -v sips >/dev/null 2>&1 || exit 0

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$path" ] || exit 0
[ -f "$path" ] || exit 0

# Image extensions sips can resample.
ext=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  png|jpg|jpeg|tif|tiff|bmp|gif|heic|webp) ;;
  *) exit 0 ;;
esac

bytes=$(stat -f%z "$path" 2>/dev/null) || exit 0
[ "$bytes" -gt "$MAX_BYTES" ] 2>/dev/null || exit 0

mtime=$(stat -f%m "$path" 2>/dev/null)
key=$(printf '%s:%s:%s:%s' "$path" "$mtime" "$bytes" "$MAX_DIM" | md5 -q 2>/dev/null)
[ -n "$key" ] || exit 0

mkdir -p "$CACHE" 2>/dev/null || exit 0
out="$CACHE/$key.png"

if [ ! -f "$out" ]; then
  sips --setProperty format png \
       --resampleHeightWidthMax "$MAX_DIM" \
       "$path" --out "$out" >/dev/null 2>&1 || exit 0
fi
[ -s "$out" ] || exit 0

newbytes=$(stat -f%z "$out" 2>/dev/null || echo "$bytes")
# If shrinking didn't actually help, don't bother redirecting.
[ "$newbytes" -lt "$bytes" ] 2>/dev/null || exit 0

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
exit 0
