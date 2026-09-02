#!/usr/bin/env bash
# test-source-ledger.sh — pin the source ledger against the incident that motivated it.
#
# The shape (2026-09-02, a VBA-to-Mendix migration): a source folder holding .cls exports AND
# one .pptx with 22 embedded diagrams; a triage that was derived from the .cls files and named
# the deck only in passing; an intake answer saying the deck "was already used by the triage".
# Nothing checked the claim, and the deck's diagrams — the only place the workflow engine's
# semantics were written down — went unread for two months.
#
# What is pinned, in the order the failure happened:
#   T1  the inventory SEES the deck and the .cls files (no extension allowlist) and counts the
#       deck's embedded images — the earlier allowlist would have listed neither
#   T2  with no dispositions, Stage 1 is BLOCKED and names the deck
#   T3  "the triage already used it" — an artifact that never names the deck — is a FAULT, not
#       a pass; the message says the claim does not hold up
#   T4  a text-only extraction that names the deck is STILL a fault while its 22 images and 25
#       slides are unaccounted for
#   T5  images + slides accounted for, .cls files covered by a pattern disposition → Stage 1
#       no longer blocked by the ledger
#   T6  a file dropped into the folder after grading blocks Stage 1 by name (drift)
#   T7  `--waive source/<rel>` in gate-check writes the register line and the row reads WAIVED
#   T8  Stage 0 never blocks on the ledger (the inventory is Stage 0's own output)
#   T9  a project with files under sources/ and NO inventory at all blocks Stage 1; a project
#       with neither does not (legacy fixtures keep passing)
#   T10 an export-prefixed module name (Form_X.cls) is matched when the artifact says X
#
# Runs the real gate-check.sh end to end, like test-source-sufficiency-gate.sh.
#
#   tests/wave2/test-source-ledger.sh /path/to/gate-check.sh

set -uo pipefail

GATE="${1:?usage: test-source-ledger.sh /path/to/gate-check.sh}"
TOOLKIT="$(cd "$(dirname "$GATE")/.." && pwd)"
SS="$TOOLKIT/bin/source-sufficiency.sh"
SL="$TOOLKIT/bin/source-ledger.sh"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ledger.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $(printf '%s' "$2" | head -c 600)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# A project shaped like the incident. The .pptx is a real zip with 25 slide parts and 22 media
# parts, built the way a deck is built — the media count must come from the container, not
# from a hand-typed number.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/source/legacy" "$d/analysis/legacy"
  "$PY" - "$d/source/legacy" <<'PY'
import sys, zipfile, os
S = sys.argv[1]
with zipfile.ZipFile(os.path.join(S, 'Functional-Description-draft.pptx'), 'w') as z:
    z.writestr('[Content_Types].xml', '<Types/>')
    for i in range(1, 26):
        z.writestr(f'ppt/slides/slide{i}.xml', f'<p:sld><a:t>Slide {i}: WFAM X M E</a:t></p:sld>')
    for i in range(1, 23):
        z.writestr(f'ppt/media/image{i}.png', b'\x89PNG fake')
for n in ('Form_Archive-Detail-Subform', 'Form_Workflow', 'Form_Release03'):
    open(os.path.join(S, n + '.cls'), 'w').write(f'Attribute VB_Name = "{n}"\n')
os.makedirs(os.path.join(S, 'node_modules', 'x'), exist_ok=True)
open(os.path.join(S, 'node_modules', 'x', 'i.js'), 'w').write('')
PY
  # The triage names the .cls modules the way humans do — without the Form_ prefix — and never
  # names the deck. That is the artifact the false claim pointed at.
  printf '# Triage\n\nGroups A-D derived from Archive-Detail-Subform, Workflow, Release03.\n' \
    > "$d/analysis/legacy/legacy-triage.md"
  printf '# Triage\n\n## Sign-off\n\nConfirmed by: Test User on 2026-09-02\n' > "$d/triage.md"
  printf '# PROJECT\n\n## Decisions\n' > "$d/PROJECT.md"
  echo "$d"
}

stage() { "$GATE" --no-html "$1" "$2" 2>&1; }

echo "== T1: inventory sees every file and counts the deck's images =="
P="$(mkproj t1)"
OUT="$("$SS" init "$P" 2>&1)"
has "init lists 4 files (deck + 3 .cls), node_modules pruned" "$OUT" "corpus: 4 file(s)"
has "init reports the embedded images" "$OUT" "carries 22 image(s)"
MEDIA="$("$PY" -c "import json,sys; d=json.load(open(sys.argv[1])); r=[x for x in d['inventory'] if x['ext']=='pptx'][0]; print(r['media'], r['pages'], r['format'])" "$P/analysis/source-sufficiency.json")"
[ "$MEDIA" = "22 25 docs" ] && ok "row carries media=22 pages=25 format=docs" || bad "row carries media=22 pages=25 format=docs" "got '$MEDIA'"

echo "== T2: no dispositions → Stage 1 BLOCKED, deck named =="
OUT="$(stage "$P" 1)"; RC=$?
[ "$RC" -ne 0 ] && ok "stage 1 exits non-zero" || bad "stage 1 exits non-zero" "rc=0"
has "blocked by the source ledger" "$OUT" "Gate BLOCKED by the source ledger"
has "names the deck as pending" "$OUT" "PENDING   legacy/Functional-Description-draft.pptx"

echo "== T3: 'the triage already used it' — artifact never names the deck → FAULT =="
"$SL" mark "$P" legacy/Functional-Description-draft.pptx --artifact analysis/legacy/legacy-triage.md --by test >/dev/null 2>&1
OUT="$("$SL" check "$P" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "check exits 1" || bad "check exits 1" "rc=$RC"
has "the claim is called out" "$OUT" "never names Functional-Description-draft.pptx"
has "verdict is FAULT not pass" "$OUT" "FAULT     legacy/Functional-Description-draft.pptx"

echo "== T4: text-only extraction that names the deck → still FAULT on 25 slides / 22 images =="
printf '# Deck extraction\n\nSource: Functional-Description-draft.pptx — WFAM X M E semantics.\n' > "$P/analysis/legacy/pptx-extraction.md"
"$SL" mark "$P" legacy/Functional-Description-draft.pptx --artifact analysis/legacy/pptx-extraction.md --by test >/dev/null 2>&1
OUT="$("$SL" check "$P" 2>&1)"
has "pages unaccounted is a fault" "$OUT" "25 page(s)/slide(s)/sheet(s) inside"
"$SL" mark "$P" legacy/Functional-Description-draft.pptx --artifact analysis/legacy/pptx-extraction.md --pages 25 --by test >/dev/null 2>&1
OUT="$("$SL" check "$P" 2>&1)"
has "images unaccounted is a fault" "$OUT" "22 embedded image(s) inside"
"$SL" mark "$P" legacy/Functional-Description-draft.pptx --artifact analysis/legacy/pptx-extraction.md --pages 25 --media 3 --by test >/dev/null 2>&1
OUT="$("$SL" check "$P" 2>&1)"
has "3 of 22 images read is a fault" "$OUT" "22 embedded image(s) inside, 3 accounted for"

echo "== T5: everything accounted for → ledger PASS, Stage 1 not blocked by it =="
"$SL" mark "$P" legacy/Functional-Description-draft.pptx --artifact analysis/legacy/pptx-extraction.md --pages 25 --media 22 --by test >/dev/null 2>&1
"$SL" mark "$P" 'legacy/*.cls' --artifact analysis/legacy/legacy-triage.md --by test >/dev/null 2>&1
OUT="$("$SL" check "$P" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "check exits 0" || bad "check exits 0" "rc=$RC $OUT"
has "4 extracted" "$OUT" "4 extracted"
OUT="$(stage "$P" 1)"
hasnt "stage 1 no longer blocked by the ledger" "$OUT" "Gate BLOCKED by the source ledger"
has "gate line reads PASS" "$OUT" "Source ledger (every file consumed?): PASS"

echo "== T10: Form_-prefixed module matched when the artifact says the bare name =="
J="$("$SL" check "$P" --json 2>/dev/null)"
NV="$("$PY" -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['counts']['nameVerified'])" <<<"$J")"
[ "$NV" = "4" ] && ok "all 4 rows name-verified (3 .cls via bare name, deck via its own)" || bad "all 4 rows name-verified" "nameVerified=$NV"

echo "== T6: a file dropped in later blocks Stage 1 by name =="
echo x > "$P/source/legacy/late-arrival.pdf"
OUT="$(stage "$P" 1)"; RC=$?
[ "$RC" -ne 0 ] && ok "stage 1 exits non-zero on drift" || bad "stage 1 exits non-zero on drift" "rc=0"
has "drift row names the file" "$OUT" "DRIFT     legacy/late-arrival.pdf"
OUT="$("$SS" init "$P" --refresh 2>&1)"
has "refresh appends it as unopened" "$OUT" "NEW (unopened): legacy/late-arrival.pdf"
has "refresh keeps the filled rows" "$OUT" "4 kept as filled"

echo "== T7: --waive source/<rel> records the decision and the row reads WAIVED =="
OUT="$("$GATE" "$P" --waive source/legacy/late-arrival.pdf --reason "arrived after cutover, out of scope per user" 2>&1)"
has "gate-check records the waiver" "$OUT" "Waived source legacy/late-arrival.pdf: arrived after cutover"
grep -q "^Waived source legacy/late-arrival.pdf:" "$P/PROJECT.md" && ok "register carries the line" || bad "register carries the line"
OUT="$("$SL" check "$P" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "ledger passes with the waiver" || bad "ledger passes with the waiver" "rc=$RC $OUT"
has "1 waived" "$OUT" "1 waived"
OUT="$(stage "$P" 1)"
hasnt "stage 1 not blocked after the waiver" "$OUT" "Gate BLOCKED by the source ledger"

echo "== T8: Stage 0 never blocks on the ledger =="
P8="$(mkproj t8)"; "$SS" init "$P8" >/dev/null 2>&1
OUT="$(stage "$P8" 0)"
hasnt "stage 0 not blocked by the ledger" "$OUT" "Gate BLOCKED by the source ledger"
has "stage 0 still shows the ledger FAIL line" "$OUT" "Source ledger (every file consumed?): FAIL"

echo "== T9: no inventory at all =="
P9="$WORK/t9"; mkdir -p "$P9/sources"; echo x > "$P9/sources/spec.docx"; printf '# P\n' > "$P9/PROJECT.md"
OUT="$(stage "$P9" 1)"; RC=$?
[ "$RC" -ne 0 ] && ok "files under sources/ and no inventory blocks stage 1" || bad "files under sources/ and no inventory blocks stage 1" "rc=0"
has "says nobody listed the corpus" "$OUT" "no inventory — nobody has listed the corpus"
P9b="$WORK/t9b"; mkdir -p "$P9b"; printf '# P\n' > "$P9b/PROJECT.md"
OUT="$(stage "$P9b" 1)"
hasnt "no sources and no inventory does not block (legacy fixtures)" "$OUT" "Gate BLOCKED by the source ledger"
has "reads NOT CHECKED, never a pass" "$OUT" "Source ledger (every file consumed?): MANUAL"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
