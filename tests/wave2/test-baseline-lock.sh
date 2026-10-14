#!/usr/bin/env bash
# test-baseline-lock.sh — a ratchet baseline moves only on a person's approval (#348).
#
# Usage: bash tests/wave2/test-baseline-lock.sh [toolkit-root]
#   The subject is a toolkit tree: its project-bin/lint-gate.sh, conformance-check.sh,
#   baseline-lock.sh, baseline-approve.sh and bin/gate-check.sh. Run against origin/master's
#   tree, the L/C/G cases fail — that is the hole: the agent typed --approved-in-chat itself.
#
#   L1  lint: a rise with --reason AND --approved-in-chat, no person → refused, baseline unchanged
#   L2  baseline-approve.sh with no terminal (an agent's tool call) → refused, no approval row
#   L3  after the person approves → the update lands, exactly the approved content
#   L4  the approval binds to content: counts change after approval → refused again
#   L5  deleting the baseline and re-creating it lower is refused (no laundering by delete)
#   C1  conformance: --update-baseline accepting a regression, no person → refused, unchanged
#   C2  after the person approves → it lands
#   G1  gate-check: a hand-moved baseline reports FAIL, and Stage 5 is BLOCKED (exit 1)
#   G2  after the person approves the file as it is (--current) → PASS
#   G3  a baseline with no record at all (predates the lock) → MANUAL, not PASS
#   --- #375 review ---
#   F1  forge: hand-edit the baseline looser, then run `baseline-lock.sh record … tighten`
#       directly → gate-check still FAIL (the record is checked against its content)
#   X1  a CRLF checkout of a recorded baseline (Windows autocrlf) → PASS, not FAIL
#   X2  a looser baseline, uncommitted → FAIL; committed in a one-parent commit → still FAIL
#   X3  a real merge of two branches that each ratcheted a different rule down → MANUAL (blocks)
#   --- #375 confirmation review ---
#   M2  after that merge, the user's approve --current clears it → PASS
#   H1  rm the log + snapshots, or truncate a committed row, then hand-edit → FAIL, and
#       lint-gate refuses to re-record over it
#   M1  a forged mid-log row: the user's approve --current supersedes it → PASS (rule 7)
#   M3  an old approval does not cover a return to its state after a tighter write → FAIL
#   L1  a missing snapshot: the user's approve --current re-anchors → PASS
#   G4  a baseline that predates the lock: lint-gate refuses even a ratchet-down until approved
#
# Synthetic lint JSON and a stub mxcli, as in test-lint-gate-accept.sh and
# test-conformance-baseline-scope.sh: nothing here parses tool output; the assertions are
# about which baseline writes land. The person's step runs baseline-approve.sh under a
# pseudo-terminal (fixtures/baseline-lock/human.sh); the fixture never writes an approval row.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "${1:-$HERE/../..}" && pwd)"
. "$HERE/fixtures/baseline-lock/human.sh"
command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python  # portability-ok: fixture probe
WORK="$(mktemp -d "${TMPDIR:-/tmp}/baseline-lock.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/       /'; }
pty_available || { echo "SKIP: no usable \`script\` for a pseudo-terminal"; exit 0; }

newproj() {  # newproj <dir> — a project with the toolkit's scripts installed in bin/
  mkdir -p "$1/bin" "$1/.claude"
  for f in _common.sh lint-gate.sh conformance-check.sh baseline-lock.sh baseline-approve.sh; do
    [ -f "$TK/project-bin/$f" ] && cp "$TK/project-bin/$f" "$1/bin/"
  done
  printf 'mpr' > "$1/App.mpr"
}
lintjson() {  # lintjson RULE=n ... > $WORK/lint.json
  "$PY" - "$@" > "$WORK/lint.json" <<'PY'
import json, sys
v = []
for a in sys.argv[1:]:
    r, n = a.split("=")
    v += [{"ruleId": r, "severity": "warning", "message": "f%d" % i, "module": "Orders",
           "document": "D%d" % i, "documentType": "microflow", "documentId": "%s-%d" % (r, i),
           "suggestion": "s"} for i in range(int(n))]
print(json.dumps({"violations": v, "summary": {}}))
PY
}
P="$WORK/p"; newproj "$P"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
LB="$P/.claude/lint-baseline.json"
counts() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["counts"])' "$1" 2>/dev/null; }

echo "L1 the agent's own flags do not move the lint baseline"
lintjson CONV009=2 SEC003=1; gate --update-baseline >/dev/null
before="$(cat "$LB" 2>/dev/null)"
lintjson CONV009=5 SEC003=2
out="$(gate --update-baseline --reason "cleanup later" --approved-in-chat)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$LB")" = "$before" ] && ok "refused (rc $rc), baseline unchanged" \
  || bad "the agent moved the baseline on its own flag (rc $rc): $(counts "$LB")" "$out"

echo "L2 the approve command refuses without a terminal"
out="$(bash "$P/bin/baseline-approve.sh" lint </dev/null 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -s "$P/.claude/baseline-approvals.tsv" ] && ok "no terminal → refused, no approval row" \
  || bad "approved without a terminal (rc $rc)" "$out"

echo "L3 with the person's approval the update lands"
human_approve "$P" lint
out="$(gate --update-baseline --reason "cleanup later")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(counts "$LB")" = "{'CONV009': 5, 'SEC003': 2}" ] && ok "accepted: $(counts "$LB")" \
  || bad "approved update did not land (rc $rc)" "$out"

echo "L4 an approval covers exactly what the person saw"
lintjson CONV009=7 SEC003=2; gate --update-baseline --reason r >/dev/null
human_approve "$P" lint
lintjson CONV009=9 SEC003=2
out="$(gate --update-baseline --reason r)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(counts "$LB")" = "{'CONV009': 5, 'SEC003': 2}" ] && ok "counts moved after approval → refused" \
  || bad "a stale approval moved the baseline (rc $rc): $(counts "$LB")" "$out"

echo "L5 deleting the baseline does not launder a rise"
rm -f "$LB"; lintjson CONV009=9 SEC003=2
out="$(gate --update-baseline)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -f "$LB" ] && ok "re-creation needs a person (rc $rc)" \
  || bad "a deleted baseline was re-created at 9 with no approval (rc $rc)" "$out"

echo "C1/C2 conformance: accepting a regression needs the person"
C="$WORK/c"; newproj "$C"; mkdir -p "$C/architecture/modules/Orders"
printf 'Orders.Order\nOrders.ACT_Save\n' > "$C/PRESENT"
cat > "$C/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
if grep -qx "$name" "$(dirname "$0")/PRESENT"; then echo "-- $name"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
chmod +x "$C/mxcli"
cat > "$C/architecture/modules/Orders/coverage-ledger.md" <<'EOF'
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| `/domainEntities/0` | entity | Order | 1.1 | exec.sh | `DESCRIBE ENTITY Orders.Order` | built |
| `/microflows/0` | microflow | ACT_Save | 1.2 | exec.sh | `DESCRIBE MICROFLOW Orders.ACT_Save` | built |
EOF
conf() { ( cd "$C" && PROJECT_ROOT="$C" bash bin/conformance-check.sh --quiet "$@" ) 2>&1; }
CB="$C/docs/conformance/baseline.tsv"
conf >/dev/null
printf 'Orders.Order\n' > "$C/PRESENT"
before="$(cat "$CB")"
out="$(conf --update-baseline)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$CB")" = "$before" ] && ok "C1 regression not baselined without the person (rc $rc)" \
  || bad "C1 the agent baselined a regression (rc $rc)" "$out"
human_approve "$C" conformance
out="$(conf --update-baseline)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "ACT_Save\|/microflows/0.*STALE" "$CB" && grep -q STALE "$CB" && ok "C2 accepted after approval" \
  || bad "C2 approved rewrite did not land (rc $rc)" "$out"

echo "G1-G3 gate-check reports a baseline that moved without approval"
GC="$TK/bin/gate-check.sh"
gline() { bash "$GC" "$1" --no-html 2>/dev/null | grep '^Baselines'; }
printf '{\n  "counts": {"CONV009": 40, "SEC003": 2}\n}\n' > "$LB"   # a hand edit
l="$(gline "$P")"
case "$l" in *FAIL*lint*) ok "G1 hand-moved lint baseline: FAIL" ;; *) bad "G1 hand edit not flagged" "${l:-<no Baselines line>}" ;; esac
bash "$GC" "$P" 5 --no-html >/dev/null 2>"$WORK/g.err"; rc=$?
[ "$rc" -eq 1 ] && grep -q "BLOCKED by a baseline" "$WORK/g.err" && ok "G1 Stage 5 BLOCKED (exit 1)" \
  || bad "G1 Stage 5 not blocked by the hand edit (rc $rc)" "$(tail -3 "$WORK/g.err")"
human_approve "$P" lint --current
l="$(gline "$P")"
case "$l" in *PASS*) ok "G2 after the person approves the file as it is: PASS" ;; *) bad "G2 not PASS after --current approval" "$l" ;; esac
L="$WORK/legacy"; mkdir -p "$L/.claude"; cp "$LB" "$L/.claude/lint-baseline.json"
l="$(gline "$L")"
case "$l" in *MANUAL*) ok "G3 a baseline with no record: MANUAL" ;; *) bad "G3 unrecorded baseline not MANUAL" "${l:-<no Baselines line>}" ;; esac

echo "F1 a direct record after a hand edit does not launder it"
F="$WORK/f"; newproj "$F"; cp "$P/mxcli" "$F/mxcli"
fgate() { (cd "$F" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
lintjson CONV009=3; fgate --update-baseline >/dev/null
printf '{\n  "counts": {"CONV009": 30}\n}\n' > "$F/.claude/lint-baseline.json"
# The review's exact command: `record <root> <kind> <sha> tighten` (extra args are ignored now).
bash "$F/bin/baseline-lock.sh" record "$F" lint "$(bash "$F/bin/baseline-lock.sh" sha "$F/.claude/lint-baseline.json")" tighten >/dev/null 2>&1
l="$(gline "$F")"
case "$l" in *FAIL*) ok "F1 forged record detected: FAIL" ;; *) bad "F1 a direct 'record … tighten' turned a hand edit green" "${l:-<no Baselines line>}" ;; esac
lintjson CONV009=30
out="$(fgate --update-baseline --reason x)"; rc=$?
[ "$rc" -ne 0 ] && ok "F1 lint-gate refuses to build on the forged state (rc $rc)" || bad "F1 lint-gate wrote over a forged baseline" "$out"

echo "X1-X3 no false FAIL from line endings or git"
X="$WORK/x"; newproj "$X"; cp "$P/mxcli" "$X/mxcli"
xgate() { (cd "$X" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
lintjson CONV009=5 SEC003=5; xgate --update-baseline >/dev/null
XB="$X/.claude/lint-baseline.json"
"$PY" -c 'import sys;p=sys.argv[1];b=open(p,"rb").read();open(p,"wb").write(b.replace(b"\n",b"\r\n"))' "$XB"
l="$(gline "$X")"
case "$l" in *PASS*) ok "X1 CRLF checkout of the recorded baseline: PASS" ;; *) bad "X1 CRLF read as a move" "$l" ;; esac
"$PY" -c 'import sys;p=sys.argv[1];b=open(p,"rb").read();open(p,"wb").write(b.replace(b"\r\n",b"\n"))' "$XB"
if command -v git >/dev/null 2>&1; then
  gx() { git -C "$X" -c user.name=t -c user.email=fixture "$@" >/dev/null 2>&1; }
  gx init -q; gx checkout -q -b main; gx add -A; gx commit -q -m base
  printf '{\n  "counts": {"CONV009": 9, "SEC003": 5}\n}\n' > "$XB"
  l="$(gline "$X")"
  case "$l" in *FAIL*) ok "X2 uncommitted looser edit: FAIL" ;; *) bad "X2 uncommitted looser edit not FAIL" "$l" ;; esac
  gx commit -q -am "loosen in git"
  l="$(gline "$X")"
  case "$l" in *FAIL*) ok "X2 the same content in a one-parent commit: still FAIL" ;; *) bad "X2 a plain git commit laundered the loosening" "$l" ;; esac
  gx reset -q --hard HEAD~1
  gx checkout -q -b a; lintjson CONV009=3 SEC003=5; xgate --update-baseline >/dev/null; gx add -A; gx commit -q -m a
  gx checkout -q main; gx checkout -q -b b; lintjson CONV009=5 SEC003=2; xgate --update-baseline >/dev/null; gx add -A; gx commit -q -m b
  gx checkout -q a; gx merge -q --no-edit b
  # The two logs and the baseline conflict; a person resolves them the obvious way: both log
  # rows kept, the baseline taking each side's own ratchet (CONV009 3 from a, SEC003 2 from b).
  # That content was never written by any instrument, so its hash is in no record — the case
  # the review raised.
  printf '{\n  "counts": {\n    "CONV009": 3,\n    "SEC003": 2\n  },\n  "total": 5\n}\n' > "$XB"
  { git -C "$X" show a:.claude/baseline-writes.tsv; git -C "$X" show b:.claude/baseline-writes.tsv | tail -1; } > "$X/.claude/baseline-writes.tsv"
  gx add -A; gx commit -q -m merge
  [ "$(git -C "$X" rev-list --count HEAD)" -ge 4 ] || bad "X3 the merge was not built" "$(git -C "$X" log --oneline | head -5)"
  l="$(gline "$X")"
  case "$l" in *MANUAL*) ok "X3 merged baselines: MANUAL, not FAIL" ;; *) bad "X3 a committed two-branch merge not MANUAL" "${l:-<no Baselines line>}" ;; esac
  human_approve "$X" lint --current
  l="$(gline "$X")"
  case "$l" in *PASS*) ok "M2 the user's approve --current clears the merge" ;; *) bad "M2 merge MANUAL did not clear" "$l" ;; esac

  echo "H1 removing or truncating committed records does not launder a loosening"
  H="$WORK/h"; newproj "$H"; cp "$P/mxcli" "$H/mxcli"
  hgate() { (cd "$H" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
  gh() { git -C "$H" -c user.name=t -c user.email=fixture "$@" >/dev/null 2>&1; }
  lintjson CONV009=5; hgate --update-baseline >/dev/null
  lintjson CONV009=3; hgate --update-baseline >/dev/null
  gh init -q; gh add -A; gh commit -q -m base
  rm -rf "$H/.claude/baseline-writes.tsv" "$H/.claude/baseline-history"
  printf '{\n  "counts": {"CONV009": 9}\n}\n' > "$H/.claude/lint-baseline.json"
  l="$(gline "$H")"
  case "$l" in *FAIL*) ok "H1 rm of the log: FAIL (committed records missing)" ;; *) bad "H1 rm of the log read as 'predates the lock'" "$l" ;; esac
  lintjson CONV009=9; out="$(hgate --update-baseline --reason x)"; rc=$?
  [ "$rc" -ne 0 ] && ok "H1 lint-gate refuses to re-record over it (rc $rc)" || bad "H1 lint-gate re-recorded a laundered log" "$out"
  gh checkout -q -- .
  "$PY" -c 'import sys;p=sys.argv[1];l=open(p).read().splitlines(True);open(p,"w").write("".join(l[:-1]))' "$H/.claude/baseline-writes.tsv"
  printf '{\n  "counts": {"CONV009": 5}\n}\n' > "$H/.claude/lint-baseline.json"
  l="$(gline "$H")"
  case "$l" in *FAIL*) ok "H1 truncating the last committed row: FAIL" ;; *) bad "H1 truncation laundered CONV009 3 -> 5" "$l" ;; esac
else
  echo "  skip X2-X3, M2, H1 (no git)"
fi

echo "M1 M3 L1 G4 the user's approval is the remedy, and only for the state it saw"
M="$WORK/m"; newproj "$M"; cp "$P/mxcli" "$M/mxcli"
mgate() { (cd "$M" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
ML="$M/.claude/lint-baseline.json"; MLOCK="$M/bin/baseline-lock.sh"
lintjson CONV009=5; mgate --update-baseline >/dev/null
lintjson CONV009=3; mgate --update-baseline >/dev/null
printf '{\n  "counts": {"CONV009": 7}\n}\n' > "$ML"
bash "$MLOCK" record "$M" lint "$(bash "$MLOCK" sha "$ML")" tighten >/dev/null 2>&1
# ...and the file goes back to 3, recorded on top: the forged 7 sits mid-log, and the state the
# user will approve is not the forged one.
printf '{\n  "counts": {"CONV009": 3}\n}\n' > "$ML"
bash "$MLOCK" record "$M" lint "$(bash "$MLOCK" sha "$ML")" tighten >/dev/null 2>&1
l="$(gline "$M")"
case "$l" in *FAIL*) ok "M1 forged mid-log row: FAIL" ;; *) bad "M1 forged mid-log row not caught" "$l" ;; esac
human_approve "$M" lint --current
l="$(gline "$M")"
case "$l" in *PASS*) ok "M1 the user's approve --current supersedes it" ;; *) bad "M1 approve --current did not clear the forged row (rule 7)" "$l" ;; esac
lintjson CONV009=8; mgate --update-baseline --reason r >/dev/null 2>&1
human_approve "$M" lint; mgate --update-baseline --reason r >/dev/null 2>&1
old="$(cat "$ML")"
lintjson CONV009=6; mgate --update-baseline >/dev/null 2>&1
printf '%s\n' "$old" > "$ML"
l="$(gline "$M")"
case "$l" in *FAIL*) ok "M3 returning to an old approved state after a tighter write: FAIL" ;; *) bad "M3 an expired approval still covered its old state" "$l" ;; esac
lintjson CONV009=8; out="$(mgate --update-baseline --reason r)"; rc=$?
[ "$rc" -ne 0 ] && ok "M3 lint-gate does not reuse the expired approval (rc $rc)" || bad "M3 lint-gate reused an old approval" "$out"
human_approve "$M" lint --current
rm -f "$M/.claude/baseline-history/lint/"*
lintjson CONV009=6; mgate --update-baseline >/dev/null 2>&1
l="$(gline "$M")"
case "$l" in *FAIL*) ok "L1 missing snapshots: FAIL" ;; *) bad "L1 missing snapshots not reported" "$l" ;; esac
human_approve "$M" lint --current
l="$(gline "$M")"
case "$l" in *PASS*) ok "L1 the user's approve --current re-anchors" ;; *) bad "L1 approve --current could not clear a missing snapshot" "$l" ;; esac
Lg="$WORK/legacy2"; newproj "$Lg"; cp "$P/mxcli" "$Lg/mxcli"
printf '{\n  "counts": {"CONV009": 5}\n}\n' > "$Lg/.claude/lint-baseline.json"
lintjson CONV009=4; out="$( (cd "$Lg" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh --update-baseline) 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "G4 unrecorded baseline: even a ratchet-down waits for the user (rc $rc)" || bad "G4 lint-gate recorded over an unverified baseline" "$out"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
