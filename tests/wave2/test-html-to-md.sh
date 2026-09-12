#!/usr/bin/env bash
# test-html-to-md.sh — pin bin/html-to-md.sh against the shape that motivated it: a saved-webpage
# export (page + `_files/` sidecar) beside a Markdown file, in a project's sources/ folder.
#
# The page is SYNTHETIC — tests/wave2/fixtures/html-to-md/CAPTURE.md says why that is acceptable
# here and which structural facts of the real exports it reproduces. Every chrome region and every
# dropped block carries a `*SENTINEL-n` token, so "nav/footer/script text absent" is a grep, not
# an impression.
#
#   T1  headings, the nested list, the ordered list, the table, pre/code, bold/italic, links survive
#   T2  nav, sidebar, breadcrumbs, cookie banner, footer, script, style, noscript, svg are gone
#   T3  the inline base64 image is written to <page>_images/01.png (byte-identical to the sidecar
#       png, which is the same 1x1 PNG) and referenced from the .md; the sidecar image is referenced
#       by its existing (project-relative) path
#   T4  the header's section list is correct: every "L<n>:" line points at a line that IS that heading
#   T5  documents-index.md names EVERY file under sources/ — page, markdown, png, css, js — with roles
#   T6  idempotent: a second run skips the page and rewrites nothing under text/; --force reconverts
#   T7  the summary prints the ratio and the totals
#
#   tests/wave2/test-html-to-md.sh /path/to/html-to-md.sh

set -uo pipefail

SUT="${1:?usage: test-html-to-md.sh /path/to/html-to-md.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TOOLKIT="$(cd "$(dirname "$SUT")/.." && pwd)"
FIX="$TOOLKIT/tests/wave2/fixtures/html-to-md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/h2m.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

P="$WORK/proj"; mkdir -p "$P/sources"
cp -R "$FIX/." "$P/sources/"; rm -f "$P/sources/CAPTURE.md"
[ -f "$P/sources/Fleet Portal Requirements.html" ] || { echo "fixture missing"; exit 2; }

OUT="$("$SUT" "$P" 2>&1)"; RC=$?
MD="$P/analysis/knowledge-base/text/Fleet Portal Requirements.md"
IDX="$P/analysis/knowledge-base/documents-index.md"
[ "$RC" -eq 0 ] && ok "html-to-md exits 0" || bad "html-to-md exits 0" "rc=$RC: $OUT"
[ -f "$MD" ] && ok ".md written under analysis/knowledge-base/text/ at the mirrored path" || bad ".md written" "no $MD"
[ -f "$IDX" ] && ok "documents-index.md written" || bad "documents-index.md written"
[ -f "$MD" ] || { echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
BODY="$(cat "$MD")"

echo "== T1: structure survives =="
has "h1"                 "$BODY" "# Fleet Portal — Requirements Overview"
has "h2 inside a wrapper div with a suspicious-looking class (toc-macro) survives" "$BODY" "## 1. Scope"
has "h3"                 "$BODY" "### 3.1 Worked example"
has "unordered list"     "$BODY" "- Vehicle register (create, view, retire)"
has "nested list item indented" "$BODY" "  - one active driver per vehicle"
has "ordered list"       "$BODY" "2. Retiring a vehicle closes its active assignment"
has "table header row"   "$BODY" "| Entity | Key attributes | Notes |"
has "table separator"    "$BODY" "|---|---|---|"
has "table cell with escaped pipe" "$BODY" "Status: Active \\| Retired"
has "bold"               "$BODY" "**functional requirements**"
has "italic"             "$BODY" "*Fleet Portal*"
has "link"               "$BODY" "[the decision log](/fleet/decisions)"
hasnt "javascript: link is text only" "$BODY" "](javascript:"
has "pre block fenced"   "$BODY" '```
Vehicle AB-123-C  Active'
has "inline code"        "$BODY" '`LicencePlate`'

echo "== T2: chrome and non-content gone =="
for s in NAVSENTINEL-1 SIDEBARSENTINEL-2 BREADCRUMBSENTINEL-3 COOKIESENTINEL-4 FOOTERSENTINEL-5 NOSCRIPTSENTINEL-6 SVGSENTINEL-7 SCRIPTSENTINEL-9911 SCRIPTSENTINEL-9912 hidden-style-text; do
  hasnt "$s absent" "$BODY" "$s"
done
hasnt "the wiki's own title element is not rendered as body text twice" "$BODY" "Acme Wiki"
has "the content inside <main> is intact (last paragraph)" "$BODY" "Is the mileage report monthly or on demand?"

echo "== T3: images =="
IMG="$P/analysis/knowledge-base/text/Fleet Portal Requirements_images/01.png"
[ -f "$IMG" ] && ok "inline base64 image written to <page>_images/01.png" || bad "inline image written" "no $IMG"
if [ -f "$IMG" ] && cmp -s "$IMG" "$P/sources/Fleet Portal Requirements_files/screen-vehicle-list.png"; then
  ok "decoded image is byte-identical to the same PNG on disk (valid decode)"
else
  bad "decoded image bytes"
fi
has "inline image referenced from the .md" "$BODY" "![Target vehicle list sketch](Fleet Portal Requirements_images/01.png)"
has "sidecar image referenced by its existing path, project-relative" "$BODY" "![Vehicle list, current spreadsheet](sources/Fleet Portal Requirements_files/screen-vehicle-list.png)"
has "header counts 2 images" "$BODY" "**Images:** 2 (1 inline"

echo "== T4: section list is a correct denominator =="
has "header states the section count" "$BODY" "**Sections (7)**"
has "header states source path" "$BODY" '**Source:** `sources/Fleet Portal Requirements.html`'
has "header states raw size and words" "$BODY" "**Raw size:** "
NSEC=0; NBAD=0
while IFS= read -r line; do
  n="$(printf '%s' "$line" | sed -n 's/^- L\([0-9][0-9]*\):.*/\1/p')"
  [ -n "$n" ] || continue
  NSEC=$((NSEC+1))
  title="$(printf '%s' "$line" | sed 's/^- L[0-9]*: *//')"
  actual="$(sed -n "${n}p" "$MD")"
  case "$actual" in
    "#"*" $title") ;;
    *) NBAD=$((NBAD+1)); echo "     L$n is '$actual', section list says '$title'" ;;
  esac
done < "$MD"
[ "$NSEC" -eq 7 ] && ok "7 section lines listed" || bad "7 section lines listed" "got $NSEC"
[ "$NBAD" -eq 0 ] && ok "every listed line number holds exactly that heading" || bad "line numbers" "$NBAD wrong"
# heading count in the body equals the header's count
NH="$(sed -n '15,$p' "$MD" | grep -c '^#\{1,6\} ')"
[ "$NH" -eq 7 ] && ok "body holds 7 headings (h1 + 5 h2 + 1 h3) — none inside the pre block counted" || bad "body headings" "got $NH"

echo "== T5: the index names EVERY file =="
IDXB="$(cat "$IDX")"
for f in "Fleet Portal Requirements.html" glossary.md app.js site.css screen-vehicle-list.png; do
  has "index names $f" "$IDXB" "$f"
done
has "page row with role and md path" "$IDXB" '| Fleet Portal Requirements.html | page | `analysis/knowledge-base/text/Fleet Portal Requirements.md` | 7 | 2 | '
has "markdown row listed, not converted" "$IDXB" "| glossary.md | markdown | — (read as is) | 3 | 0 | "
has "css is chrome of the page" "$IDXB" "| Fleet Portal Requirements_files/site.css | chrome of Fleet Portal Requirements.html |"
has "js is chrome of the page" "$IDXB" "| Fleet Portal Requirements_files/app.js | chrome of Fleet Portal Requirements.html |"
has "png is image of the page" "$IDXB" "| Fleet Portal Requirements_files/screen-vehicle-list.png | image of Fleet Portal Requirements.html |"
has "vision denominator stated" "$IDXB" "Images to read (vision) before Stage 2 closes: 2"
[ ! -f "$P/analysis/knowledge-base/text/glossary.md" ] && ok "markdown source NOT copied/converted" || bad "glossary.md was converted"

echo "== T6: idempotent, and --force reconverts =="
fingerprint() { find "$1" -type f | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "${f#$1}" "$(md5sum "$f" 2>/dev/null | cut -d' ' -f1 || md5 -q "$f")"; done; }
B="$(fingerprint "$P/analysis/knowledge-base/text")"
OUT2="$("$SUT" "$P" 2>&1)"
A="$(fingerprint "$P/analysis/knowledge-base/text")"
[ "$B" = "$A" ] && ok "second run rewrote nothing under text/" || bad "second run rewrote text/"
has "second run reports the skip" "$OUT2" "up to date, skipped"
has "second run still reports the page's numbers (read back from the header)" "$OUT2" "265"
IDX1="$(grep -v '^Written by' "$IDX")"
OUT3="$("$SUT" "$P" --force 2>&1)"
has "--force reconverts" "$OUT3" "1 converted, 0 skipped"
hasnt "--force reports no skip" "$OUT3" "up to date, skipped"
[ "$IDX1" = "$(grep -v '^Written by' "$IDX")" ] && ok "index identical across runs (sidecar ownership stable)" || bad "index differs between runs"
A2="$(fingerprint "$P/analysis/knowledge-base/text")"
[ "$B" = "$A2" ] && ok "--force output is byte-identical to the first run (deterministic)" || bad "--force output differs"

echo "== T7: summary =="
has "summary column header" "$OUT" "raw KB  md words   ratio"
printf '%s' "$OUT" | grep -qE 'Fleet Portal Requirements\.html +[0-9.]+ +265 +[0-9.]+×' \
  && ok "per-page row: raw KB, md words, ratio" || bad "per-page row" "$OUT"
printf '%s' "$OUT" | grep -qE 'TOTAL +[0-9.]+ +265 +[0-9.]+×  1 converted' \
  && ok "TOTAL row with ratio and converted count" || bad "TOTAL row" "$OUT"
has "index line names its path and row count" "$OUT" "documents-index.md — 5 row(s): 1 page, 1 markdown, 1 image, 2 chrome, 0 other"

echo "== T8: usage and root detection =="
"$SUT" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no args → exit 2" || bad "no args exit code"
E="$WORK/empty"; mkdir -p "$E"
"$SUT" "$E" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no sources/ and no --source → exit 2, not a silent zero" || bad "empty project exit code"
P2="$WORK/p2"; mkdir -p "$P2/source"; cp "$FIX/Fleet Portal Requirements.html" "$P2/source/"
"$SUT" "$P2" >/dev/null 2>&1 && [ -f "$P2/analysis/knowledge-base/text/Fleet Portal Requirements.md" ] \
  && ok "source/ (singular) is detected too" || bad "source/ detection"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
