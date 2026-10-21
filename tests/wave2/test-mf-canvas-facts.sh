#!/usr/bin/env bash
# Fixture for project-bin/mf-canvas-facts.py (the canvas-readability instrument), on a model
# mxcli v0.27.0 wrote.
#
# usage: bash tests/wave2/test-mf-canvas-facts.sh /path/to/project-bin/mf-canvas-facts.py
#   (the fixture uses that file's directory: mxpatch.py and mxunit_bson.py beside it)
#
# Golden input is captured, never written: fixtures/canvas-facts/ holds the five units and the
# .mpr dump `mxcli v0.27.0 exec capture-canvas.mdl` produced on a copy of fixtures/mxpatch/model
# (see its CAPTURE.txt). Each fact has a negative control in the same model: a parameter column
# (no OVERLAP), a decision captioned to match its true branch (no SENSE).
#
# Positive control: against a project-bin without the script every case fails -- it does not
# exist. [guard] marks regression guards.
set -uo pipefail
SUBJ="${1:?usage: test-mf-canvas-facts.sh /path/to/project-bin/mf-canvas-facts.py}"
case "$SUBJ" in /*) ;; *) SUBJ="$PWD/$SUBJ" ;; esac
[ -f "$SUBJ" ] && BIN="$(dirname "$SUBJ")" || BIN="$SUBJ"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/canvas-facts"
BASE="$TK/tests/wave2/fixtures/mxpatch/model"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/canvasfacts.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
. "$TK/bin/lib/portable.sh"; require_py
export MXPATCH_BACKUP_DIR="$WORK/bak"

# model <dir> -- the base model's units, the captured five over them, the captured .mpr.
model() {
  rm -rf "$1"; mkdir -p "$1"; cp -r "$BASE/mprcontents" "$1/"; cp -r "$FX/overlay/mprcontents" "$1/"
  "$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.executescript(open(sys.argv[2]).read()); c.commit()' \
    "$1/TestApp.mpr" "$FX/overlay/TestApp.mpr.sql"
}
FACTS() { "$PY" -I "$BIN/mf-canvas-facts.py" "$@"; }

M="$WORK/m"; model "$M"
OUT="$("$PY" -I "$BIN/mxpatch.py" verify "$M/TestApp.mpr" 2>&1)"
printf '%s' "$OUT" | grep -q '^0 mismatch(es), 0 missing file(s), 0 orphan file(s)\.$' \
  && ok "[guard] rebuilt model verifies clean (overlay matches its .mpr dump)" || bad "rebuilt model" "$OUT"

echo "== F: the facts on the captured model =="
OUT="$(FACTS "$M" --module MyFirstModule 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0: measured" || bad "exit $RC" "$OUT"
WANT="$(grep '^  ' "$FX/facts-v0.27.0.out")"
[ "$(printf '%s\n' "$OUT" | grep '^  ')" = "$WANT" ] \
  && ok "[guard] fact lines equal the first run's capture (facts-v0.27.0.out)" || bad "fact lines drifted" "$(printf '%s\n' "$OUT" | grep '^  ')"
printf '%s' "$OUT" | grep -q '^  NOTE-SIDE note line Annotation@360,100 -> Action@360,200 leaves the note left' \
  && ok "NOTE-SIDE: mxcli's (2,0) line leaves the left of a note that sits above its activity" || bad "NOTE-SIDE" "$OUT"
printf '%s' "$OUT" | grep -q '^  OVERLAP   label "PrimaryCustomerRecord" of MicroflowP@200,53  x  label "SecondaryCustomerRecord" of MicroflowP@300,53$' \
  && ok "OVERLAP: two long parameter labels on mxcli's 100-apart row" || bad "OVERLAP" "$OUT"
printf '%s' "$OUT" | grep -A1 '^# MyFirstModule.ACT_Customer_MergeColumn  (0)$' | grep -q '^# ' \
  && ok "no OVERLAP for the same parameters in a column 80 apart (negative control)" || bad "column control" "$OUT"
printf '%s' "$OUT" | grep -q '^  SENSE     Split@360,200 "Customer found?" asks the positive question; its true branch is \$Customer = empty$' \
  && ok "SENSE: 'Customer found?' over \$Customer = empty" || bad "SENSE" "$OUT"
printf '%s' "$OUT" | grep -q 'No customer?' \
  && bad "SENSE fired on 'No customer?' (negative control)" "$OUT" || ok "no SENSE for 'No customer?' (negative control)"
# The negative-word list, on captions the captured model does not carry: a caption that asks the
# negated question (here with a word no un-/not- rule catches) must not read as the positive one.
OUT2="$("$PY" -I -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("f",sys.argv[1]); f=importlib.util.module_from_spec(s); s.loader.exec_module(f)
for c in sys.argv[2:]: print("%s=%s" % (c, bool(f.NEG.search(c))))' "$BIN/mf-canvas-facts.py" \
  "Customer inactive?" "Order incomplete?" "Link expired?" "Customer active?" "Customer found?" \
  "Unknown?" "Unsaved?" "Unset?" "Unit found?" "Unique?" "Under limit?" "Until done?" 2>&1)"
[ "$OUT2" = "$(printf '%s\n' 'Customer inactive?=True' 'Order incomplete?=True' 'Link expired?=True' 'Customer active?=False' 'Customer found?=False' \
  'Unknown?=True' 'Unsaved?=True' 'Unset?=True' 'Unit found?=False' 'Unique?=False' 'Under limit?=False' 'Until done?=False')" ] \
  && ok "[guard] 'inactive?', 'incomplete?', 'expired?', 'unknown?', 'unsaved?' read as negated questions; 'active?', 'found?', 'unit', 'unique', 'under', 'until' do not" || bad "negative-word list" "$OUT2"
printf '%s' "$OUT" | tail -1 | grep -q '^# facts: 15 flows, OVERLAP 1, LINE 1, NOTE-SIDE 1, LEFTWARD 0, TURN 0, CAPTION 0, SENSE 1$' \
  && ok "summary line counts every fact kind" || bad "summary" "$(printf '%s' "$OUT" | tail -1)"

echo "== S: selection and faults =="
OUT="$(FACTS "$M/mprcontents" MyFirstModule.ACT_Customer_Check ACT_Customer_Merge 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^# MyFirstModule\.')" = 2 ] \
  && ok "mprcontents/ path; a qualified and a plain name pick two flows" || bad "selection rc=$RC" "$OUT"
OUT="$(FACTS "$M" MyFirstModule.NoSuchFlow 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'FAULT no microflow or nanoflow named MyFirstModule.NoSuchFlow' \
  && ok "[guard] a named flow that is not there is a FAULT (exit 2), never a clean run" || bad "missing name rc=$RC" "$OUT"
OUT="$(FACTS "$WORK/nowhere" --all 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "no model: exit 2" || bad "no model rc=$RC" "$OUT"
cp "$M/mprcontents/42/8b/428b31b1-5993-442e-92a1-56a1c48639db.mxunit" "$WORK/keep.mxunit"
"$PY" -c 'import sys; p=sys.argv[1]; b=open(p,"rb").read(); open(p,"wb").write(b[:-1])' \
  "$M/mprcontents/42/8b/428b31b1-5993-442e-92a1-56a1c48639db.mxunit"
OUT="$(FACTS "$M" --all 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'FAULT could not read' && printf '%s' "$OUT" | grep -q '^# facts: 14 flows' \
  && ok "[guard] a unit that does not decode is a FAULT, and every other flow is still measured" || bad "bad unit rc=$RC" "$OUT"
cp "$WORK/keep.mxunit" "$M/mprcontents/42/8b/428b31b1-5993-442e-92a1-56a1c48639db.mxunit"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
