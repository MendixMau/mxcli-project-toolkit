#!/usr/bin/env bash
# test-images-to-md.sh — pin bin/images-to-md.sh against every corner a picture hides in.
# The corpus is BUILT, never committed — see tests/wave2/fixtures/images-to-md/CAPTURE.md for
# why that is the right call here, and exactly what each piece of it proves.
#
#   T1  unique content count folds the pptx duplicate (two zip entries, one sha256)
#   T2  the 16x16 loose image is chrome, not content — the size floor
#   T3  the pptx slide->image mapping and each slide's <a:t> text land in the worklist as context
#   T4  per-slide Markdown + slides.json are written, one per slide, images linked
#   T5  the docx image is found, mapped to its nearest preceding heading
#   T6  the html sidecar image is found once — not double-counted with html-to-md's own index row
#   T7  the PDF's /DCTDecode image object is extracted as a real .jpg
#   T8  --check exits 1 before any description exists, and lists every missing id
#   T9  once every description file is written (this fixture writes them): --check exits 0,
#       "described N of N", the ledger command per owning file with the right --media count,
#       the description inlined under the page's image line, documents-index gains `described`
#   T10 a second --check is idempotent: manifest.json and worklist.md are byte-identical
#
#   tests/wave2/test-images-to-md.sh /path/to/images-to-md.sh

set -uo pipefail

SUT="${1:?usage: test-images-to-md.sh /path/to/images-to-md.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TOOLKIT="$(cd "$(dirname "$SUT")/.." && pwd)"
FIX="$TOOLKIT/tests/wave2/fixtures/images-to-md"
HTML_TO_MD="$TOOLKIT/bin/html-to-md.sh"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
[ -f "$HTML_TO_MD" ] || { echo "test-images-to-md: $HTML_TO_MD missing"; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/i2m.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

P="$WORK/proj"; mkdir -p "$P/sources"
"$PY" "$FIX/gen-fixture.py" "$P/sources" >/dev/null || { echo "fixture generator failed"; exit 2; }
[ -f "$P/sources/Deck.pptx" ] || { echo "fixture missing"; exit 2; }

# images-to-md reads html-to-md's output (sidecar/inline conventions) — run it first, as the
# runbook wires them.
H2M_OUT="$("$HTML_TO_MD" "$P" 2>&1)"
[ -f "$P/analysis/knowledge-base/text/page.md" ] || { echo "html-to-md prerequisite failed: $H2M_OUT"; exit 2; }

OUT1="$("$SUT" "$P" 2>&1)"; RC1=$?
MANIFEST="$P/analysis/knowledge-base/images/manifest.json"
WORKLIST="$P/analysis/knowledge-base/images/worklist.md"
[ "$RC1" -eq 0 ] && ok "plain run exits 0" || bad "plain run exits 0" "rc=$RC1: $OUT1"
[ -f "$MANIFEST" ] && ok "manifest.json written" || bad "manifest.json written"
[ -f "$WORKLIST" ] && ok "worklist.md written" || bad "worklist.md written"
[ -f "$MANIFEST" ] || { echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
MJSON="$(cat "$MANIFEST")"
WLIST="$(cat "$WORKLIST")"

echo "== T1: dedup folds the pptx duplicate =="
has "counts: 7 unique total" "$MJSON" '"unique": 7'
has "counts: 6 content" "$MJSON" '"content": 6'
has "counts: 1 duplicate folded" "$MJSON" '"duplicates_folded": 1'
has "summary line reports the same" "$OUT1" "7 unique image(s) — content 6, chrome 1, vector 0, needs-render 0 (duplicates folded: 1)"

echo "== T2: the size floor =="
has "the 16x16 loose image is chrome, not content" "$MJSON" '"role": "chrome"'
"$PY" - "$MANIFEST" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1]))
tiny = [i for i in m['images'] if i['width'] == 16 and i['height'] == 16]
assert tiny and tiny[0]['role'] == 'chrome', tiny
print("ok tiny image role")
PYEOF
[ $? -eq 0 ] && ok "16x16 image's own row says role=chrome" || bad "16x16 image role"

echo "== T3: pptx slide mapping and text land in the worklist =="
has "slide 1 text as context" "$WLIST" "slide 1: Welcome to Harbour Ops"
has "slide 3 text as context, same image id as slide 1 (folded)" "$WLIST" "slide 3: Welcome to Harbour Ops"
has "slide 2's distinct image has its own section" "$WLIST" "slide 2: Booking a berth"
# slide 1 and slide 3 must be TWO locations of the SAME worklist section (one id), not two ids
DEDUP_ID="$(printf '%s\n' "$WLIST" | awk '/slide 1: Welcome to Harbour Ops/{print h} {if ($0 ~ /^## img-/) h=$0}')"
DEDUP_ID3="$(printf '%s\n' "$WLIST" | awk '/slide 3: Welcome to Harbour Ops/{print h} {if ($0 ~ /^## img-/) h=$0}')"
[ -n "$DEDUP_ID" ] && [ "$DEDUP_ID" = "$DEDUP_ID3" ] && ok "slide 1 and slide 3 share one worklist section" || bad "slide 1/3 sections differ" "'$DEDUP_ID' vs '$DEDUP_ID3'"

echo "== T4: per-slide markdown + slides.json =="
DECKDIR="$P/analysis/knowledge-base/text/Deck"
for n in 01 02 03; do
  [ -f "$DECKDIR/slide$n.md" ] && ok "slide$n.md written" || bad "slide$n.md written"
done
has "slide01.md names its source and slide number" "$(cat "$DECKDIR/slide01.md" 2>/dev/null)" '`sources/Deck.pptx` — slide 1'
has "slide01.md links its image under images/" "$(cat "$DECKDIR/slide01.md" 2>/dev/null)" '](../../images/img-'
[ -f "$DECKDIR/slides.json" ] && ok "slides.json written" || bad "slides.json written"
"$PY" - "$DECKDIR/slides.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert len(data) == 3, data
assert data[0]['text'] == ['Welcome to Harbour Ops'], data[0]
assert data[0]['images'] == data[2]['images'], (data[0], data[2])
assert data[1]['images'] != data[0]['images']
PYEOF
[ $? -eq 0 ] && ok "slides.json: 3 slides, slide1/slide3 share an image id, slide2 differs" || bad "slides.json shape"

echo "== T5: docx image mapped to its nearest preceding heading =="
has "docx image's worklist entry cites the heading" "$WLIST" "under heading: Vehicle Screens"
has "docx image's location is Spec.docx" "$WLIST" "sources/Spec.docx"

echo "== T6: html sidecar image found once =="
SIDECAR_HITS="$(printf '%s' "$MJSON" | grep -c 'sidecar image of page.html')"
[ "$SIDECAR_HITS" -eq 1 ] && ok "sidecar image appears in exactly one location (not double-counted)" || bad "sidecar image location count" "got $SIDECAR_HITS"
has "sidecar image worklist entry" "$WLIST" "sources/page.html"

echo "== T7: PDF DCTDecode image extracted as a real jpg =="
"$PY" - "$MANIFEST" "$P" <<'PYEOF'
import json, os, sys
manifest_path, project = sys.argv[1], sys.argv[2]
m = json.load(open(manifest_path))
pdf_rows = [i for i in m['images'] if any(l['kind'] == 'pdf' for l in i['locations'])]
assert len(pdf_rows) == 1, pdf_rows
row = pdf_rows[0]
assert row['ext'] == 'jpg', row
assert row['role'] == 'content', row
img_path = os.path.join(project, row['path'])
with open(img_path, 'rb') as f:
    head = f.read(3)
assert head[:2] == b'\xff\xd8', head
print("ok pdf jpg")
PYEOF
[ $? -eq 0 ] && ok "PDF image row is a real .jpg (SOI marker present) at its manifest path" || bad "PDF image extraction"

echo "== T8: --check fails loudly before any description exists =="
OUT_CHECK1="$("$SUT" "$P" --check 2>&1)"; RC_CHECK1=$?
[ "$RC_CHECK1" -eq 1 ] && ok "--check exits 1 with nothing described" || bad "--check exit code" "rc=$RC_CHECK1"
has "reports described 0 of 6" "$OUT_CHECK1" "described 0 of 6"
"$PY" - "$MANIFEST" "$WORK/content_ids.txt" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1]))
ids = sorted(i['id'] for i in m['images'] if i['role'] == 'content')
assert len(ids) == 6, ids
open(sys.argv[2], 'w').write('\n'.join(ids))
PYEOF
CONTENT_IDS="$(cat "$WORK/content_ids.txt" 2>/dev/null)"
ALL_LISTED=1
for id in $CONTENT_IDS; do
  case "$OUT_CHECK1" in *"$id"*) ;; *) ALL_LISTED=0 ;; esac
done
[ "$ALL_LISTED" -eq 1 ] && ok "every one of the 6 content ids is listed as missing" || bad "missing-id list incomplete" "$OUT_CHECK1"

echo "== T9: write every description (this fixture writes them), then --check passes =="
IMAGES_DIR="$P/analysis/knowledge-base/images"
for id in $CONTENT_IDS; do
  cat > "$IMAGES_DIR/$id.md" <<EOF
# $id — synthetic test description

Source: fixture

## Kind
screenshot

## Verbatim text
"Verbatim text for $id"

## Structure
A labelled box.

## Implied requirements and rules
None found in this synthetic image.

## Uncertain
Nothing uncertain.

## Summary
Synthetic description written by the test fixture for $id.
EOF
done
OUT_CHECK2="$("$SUT" "$P" --check 2>&1)"; RC_CHECK2=$?
[ "$RC_CHECK2" -eq 0 ] && ok "--check exits 0 once every content image is described" || bad "--check exit code" "rc=$RC_CHECK2: $OUT_CHECK2"
has "reports described 6 of 6" "$OUT_CHECK2" "described 6 of 6"
has "prints a ledger mark command for Deck.pptx with --media 2" "$OUT_CHECK2" "mark <p> 'sources/Deck.pptx' --artifact analysis/knowledge-base/images/manifest.json --evidence \"<fill in>\" --media 2"
has "prints a ledger mark command for Doc.pdf with --media 1" "$OUT_CHECK2" "mark <p> 'sources/Doc.pdf' --artifact analysis/knowledge-base/images/manifest.json --evidence \"<fill in>\" --media 1"
has "prints a ledger mark command for Spec.docx with --media 1" "$OUT_CHECK2" "mark <p> 'sources/Spec.docx' --artifact analysis/knowledge-base/images/manifest.json --evidence \"<fill in>\" --media 1"
has "prints a ledger mark command for page.html with --media 1" "$OUT_CHECK2" "mark <p> 'sources/page.html' --artifact analysis/knowledge-base/images/manifest.json --evidence \"<fill in>\" --media 1"
has "prints a ledger mark command for photo.jpg with --media 1" "$OUT_CHECK2" "mark <p> 'sources/photo.jpg' --artifact analysis/knowledge-base/images/manifest.json --evidence \"<fill in>\" --media 1"
has "the commands are printed, not run (source-ledger.sh script itself untouched)" "$OUT_CHECK2" "bin/source-ledger.sh mark"

PAGE_MD="$(cat "$P/analysis/knowledge-base/text/page.md")"
has "the description is inlined right under the page's image line" "$PAGE_MD" "![Vehicle list screenshot](sources/page_files/shot.png)"
has "inlined marker names the description file" "$PAGE_MD" "description: analysis/knowledge-base/images/img-"
has "inlined verbatim text" "$PAGE_MD" "Verbatim text"
has "inlined summary" "$PAGE_MD" "Synthetic description written by the test fixture"

DECK_SLIDE1="$(cat "$DECKDIR/slide01.md")"
has "slide01.md also gets the inlined description (per-slide files covered too)" "$DECK_SLIDE1" "<!-- image: img-"

IDX="$P/analysis/knowledge-base/documents-index.md"
IDXB="$(cat "$IDX" 2>/dev/null)"
has "documents-index.md gains a described column header" "$IDXB" "| described |"
has "the sidecar image row reports yes" "$IDXB" "page_files/shot.png | image of page.html |"
"$PY" - "$IDX" <<'PYEOF'
import sys
lines = open(sys.argv[1]).read().splitlines()
row = [l for l in lines if 'page_files/shot.png' in l]
assert row and row[0].rstrip().endswith('| yes |'), row
PYEOF
[ $? -eq 0 ] && ok "sidecar image row's described value is yes (not its owning page's)" || bad "sidecar described value"

echo "== T10: idempotent =="
M1="$(cat "$MANIFEST")"; W1="$(cat "$WORKLIST")"
OUT_CHECK3="$("$SUT" "$P" --check 2>&1)"; RC_CHECK3=$?
M2="$(cat "$MANIFEST")"; W2="$(cat "$WORKLIST")"
[ "$RC_CHECK3" -eq 0 ] && ok "third run (--check again) still exits 0" || bad "third run exit code" "rc=$RC_CHECK3"
[ "$M1" = "$M2" ] && ok "manifest.json byte-identical across the idempotent rerun" || bad "manifest.json changed on rerun"
[ "$W1" = "$W2" ] && ok "worklist.md byte-identical across the idempotent rerun" || bad "worklist.md changed on rerun"
PAGE_MD_AGAIN="$(cat "$P/analysis/knowledge-base/text/page.md")"
[ "$PAGE_MD" = "$PAGE_MD_AGAIN" ] && ok "inlined page.md unchanged on rerun (no duplicate markers)" || bad "page.md changed on rerun"
MARKER_COUNT="$(printf '%s' "$PAGE_MD_AGAIN" | grep -c '<!-- image: img-')"
[ "$MARKER_COUNT" -eq 1 ] && ok "exactly one marker for the page's one image, not duplicated" || bad "marker count" "got $MARKER_COUNT"

rm -f "$WORK/content_ids.txt"
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
