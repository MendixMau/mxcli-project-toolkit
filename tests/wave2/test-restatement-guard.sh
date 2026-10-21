#!/usr/bin/env bash
# test-restatement-guard.sh — #269: re-running an older script that owns the same document as a
# newer one silently reverted the newer work (exit 0, no word). exec.sh now WARNs through
# script-owners.sh; a new owner without a supersedes header gets one NOTE line, first run only.
#
# Usage: bash tests/wave2/test-restatement-guard.sh [path-to-exec.sh]
#        script-owners.sh and restore-mpr.sh are taken from the same directory as exec.sh.
#
# Covers
#   parser:  `docs` over REAL MDL (mxcli v0.23.0 and v0.26.0 DESCRIBE captures, StyleGallery,
#            skills/agents-examples) matches a grep of statement heads (36); StyleGallery 0 of 20.
#   order:   2-core/ runs before 11-fixes/, 9-a before 10-b, done- ignored (a byte sort had them
#            backwards and called a forward exec a replay).
#   check:   NOTE for a new owner (first run only), REVERT for a replay over a newer owner's live
#            write, quiet when neither ran (S is new), supersedes / superseded-by, two-tree.
#   ledger:  record + last-writer, compaction, its own .gitignore, RESTORE marker (restore-mpr.sh),
#            DESCRIBE cap of 5 per check (the rest UNCHECKED), the captured v0.26.0 not-found output.
#   exec.sh: happy path = no WARN and zero DESCRIBE; replay WARN + BUILD-LOG cell, exit 0; NOTE
#            stays out of BUILD-LOG; `ask` approval still exit 0; =off silent; the F3 scenario
#            05, 09 supersedes 05, replay 05, restore, replay 05 → WARN both times.
# NOTHING here touches a real .mpr, mxcli or mxbuild.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
BIN="$(dirname "$SUBJECT")"
OWNERS="$BIN/script-owners.sh"
CAP="$TOOLKIT/tests/wave2/fixtures/context-pack/capture/describe"
CAP26="$TOOLKIT/tests/wave2/fixtures/restatement-guard"
REJ="$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
APP="$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/restate.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -4)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"
[ -f "$OWNERS" ] || bad "[setup] script-owners.sh not found beside exec.sh"
fix() { sed "s/A comment is required to reject./$1/" "$REJ"; }

# ── parser over real MDL ─────────────────────────────────────────────────────
echo "-- parser"
GREP_N=0; DOCS_N=0
for f in "$CAP"/*.out "$CAP26"/*.out "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl "$TOOLKIT"/skills/agents-examples/*.mdl; do
  g="$(grep -ciE '^[[:space:]]*create[[:space:]]+(or[[:space:]]+(modify|replace)[[:space:]]+)?(microflow|nanoflow|page|snippet)[[:space:]]' "$f" || true)"
  d="$(bash "$OWNERS" docs "$f" 2>/dev/null | grep -c . || true)"
  GREP_N=$((GREP_N + g)); DOCS_N=$((DOCS_N + d))
done
[ "$GREP_N" -eq 36 ] && ok "[setup] 36 statement heads in the golden files" || bad "[setup] golden grep found $GREP_N, expected 36"
[ "$DOCS_N" -eq "$GREP_N" ] && ok "docs lists every head ($DOCS_N)" || bad "docs listed $DOCS_N, grep $GREP_N"
has "a v0.26.0 page capture ('page X folder ...') parses" "$(bash "$OWNERS" docs "$CAP26/PAGE__Administration.ChangePasswordForm.out" 2>&1)" "PAGE	Administration.ChangePasswordForm	2	modify"
OUT="$(bash "$OWNERS" count "$TOOLKIT/examples/stylegallery" 2>&1)"
[ "$OUT" = "0 20" ] && ok "StyleGallery tree: 0 of 20 co-owned" || bad "StyleGallery count '$OUT'"

# ── run order ────────────────────────────────────────────────────────────────
echo "-- run order: digit runs compare as numbers"
R="$WORK/order"; mkdir -p "$R/mdlsource/2-core" "$R/mdlsource/11-fixes" "$R/mdlsource/ph"
cp "$REJ" "$R/mdlsource/2-core/a.mdl"; fix "x" > "$R/mdlsource/11-fixes/b.mdl"
cp "$APP" "$R/mdlsource/ph/9-a.mdl"; cp "$APP" "$R/mdlsource/ph/done-10-b.mdl"
rchk() { ( cd "$R" && PROJECT_ROOT="$R" bash "$OWNERS" check "$1" "$R" ) 2>&1; }
OUT="$(bash "$OWNERS" report "$R")"
has "report: 2-core before 11-fixes" "$OUT" "2 scripts: mdlsource/2-core/a.mdl, mdlsource/11-fixes/b.mdl"
has "report: 9-a before done-10-b" "$OUT" "2 scripts: mdlsource/ph/9-a.mdl, mdlsource/ph/done-10-b.mdl"
OUT="$(rchk mdlsource/11-fixes/b.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "forward exec of 11-fixes: NOTE, older owner 2-core" "$OUT" "NOTE	MICROFLOW Sales.ACT_ApprovalStep_Reject	mdlsource/2-core/a.mdl	older owner" || bad "11-fixes rc $RC: $OUT"
hasnt "  not called a replay" "$OUT" "REVERT"
OUT="$(rchk mdlsource/ph/done-10-b.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "forward exec of 10-b: older owner 9-a" "$OUT" "older owner mdlsource/ph/9-a.mdl" || bad "10-b rc $RC: $OUT"

# ── check + ledger, without an mxcli ─────────────────────────────────────────
echo "-- check and ledger"
O="$WORK/own"; mkdir -p "$O/mdlsource"
cp "$REJ" "$O/mdlsource/05-reject.mdl"; cp "$APP" "$O/mdlsource/06-approve.mdl"; fix "x" > "$O/mdlsource/09-reject-fix.mdl"
chk() { ( cd "$O" && PROJECT_ROOT="$O" bash "$OWNERS" check "$1" "$O" ) 2>&1; }
rec() { ( cd "$O" && PROJECT_ROOT="$O" bash "$OWNERS" record "$1" ) 2>&1; }
LG="$O/.claude/loop/script-owners/written.tsv"
OUT="$(bash "$OWNERS" report "$O")"
has "report names the co-owned microflow" "$OUT" "MICROFLOW Sales.ACT_ApprovalStep_Reject — 2 scripts: mdlsource/05-reject.mdl, mdlsource/09-reject-fix.mdl"
OUT="$(chk mdlsource/06-approve.mdl)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "a sole owner: nothing" || bad "sole owner rc $RC: $OUT"
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "neither 05 nor 09 ever ran: 05 is new, nothing (no DESCRIBE)" || bad "new 05 rc $RC: $OUT"
rec mdlsource/05-reject.mdl
[ -f "$O/.claude/loop/script-owners/.gitignore" ] && ok "ledger folder carries its own .gitignore (machine-local)" || bad "no ledger .gitignore"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "09 first run: NOTE, older owner 05" "$OUT" "NOTE	MICROFLOW Sales.ACT_ApprovalStep_Reject	mdlsource/05-reject.mdl" || bad "09 first rc $RC: $OUT"
rec mdlsource/09-reject-fix.mdl
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "09 re-run: no NOTE (it has a ledger row)" || bad "09 re-run rc $RC: $OUT"
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "replay 05 over 09's write (no ./mxcli to ask): REVERT" "$OUT" "REVERT	MICROFLOW Sales.ACT_ApprovalStep_Reject	mdlsource/09-reject-fix.mdl	newer owner" || bad "replay rc $RC: $OUT"
rec mdlsource/05-reject.mdl
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "05 is the last writer now: re-running 05 reverts nothing" || bad "rc $RC: $OUT"
{ echo "-- supersedes: 05-reject.mdl"; fix "x"; } > "$O/mdlsource/09-reject-fix.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "-- supersedes: settles it" || bad "supersedes rc $RC: $OUT"
rec mdlsource/09-reject-fix.mdl
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "replaying a superseded script over the live newer write: REVERT" "$OUT" "superseded: mdlsource/09-reject-fix.mdl supersedes this script" || bad "superseded replay rc $RC"
cp "$REJ" "$O/mdlsource/09-reject-fix.mdl"; { echo "-- superseded-by: 09-reject-fix.mdl"; cat "$REJ"; } > "$O/mdlsource/05-reject.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "-- superseded-by: in the old script settles it too" || bad "superseded-by rc $RC: $OUT"
OUT="$( ( cd "$O" && PROJECT_ROOT="$O" bash "$OWNERS" last-writer "MICROFLOW Sales.ACT_ApprovalStep_Reject" ) )"
[ "$OUT" = "mdlsource/09-reject-fix.mdl" ] && ok "last-writer: 09" || bad "last-writer '$OUT'"
N="$(grep -c 'mdlsource/05-reject.mdl	MICROFLOW Sales.ACT_ApprovalStep_Reject' "$LG")"
[ "$N" = 1 ] && [ "$(wc -l < "$LG" | tr -d ' ')" = 2 ] && ok "compaction: one row per (script, document) after 5 records" || bad "ledger not compacted: $(cat "$LG")"
printf '1\tRESTORE\tsnapA\n2\tRESTORE\tsnapB\n' >> "$LG"; rec mdlsource/06-approve.mdl
[ "$(grep -c RESTORE "$LG")" = 1 ] && grep -q 'RESTORE	snapB' "$LG" && ok "compaction keeps only the last RESTORE row" || bad "RESTORE rows: $(grep RESTORE "$LG")"
OUT="$( ( cd "$O" && PROJECT_ROOT="$O" bash "$OWNERS" last-writer "MICROFLOW Sales.ACT_ApprovalStep_Reject" ) )"
[ -z "$OUT" ] && ok "last-writer ignores rows before the last RESTORE" || bad "last-writer after RESTORE '$OUT'"
T="$WORK/twotree"; mkdir -p "$T/app/mdlsource"; cp "$REJ" "$T/app/mdlsource/05-reject.mdl"; cp "$REJ" "$T/app/mdlsource/09-reject-fix.mdl"
OUT="$(bash "$OWNERS" count "$T" 2>&1)"
[ "$OUT" = "1 1" ] && ok "two-tree: app/mdlsource/ found (1 of 1 co-owned)" || bad "two-tree count '$OUT'"

# ── fixture project for live + exec.sh ───────────────────────────────────────
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$P/live"
printf 'not a real model\n' > "$P/Fixture.mpr"; printf 'bson\n' > "$P/mprcontents/a.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"
cp "$BIN/restore-mpr.sh" "$P/bin/" 2>/dev/null || cp "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"; [ -f "$OWNERS" ] && cp "$OWNERS" "$P/bin/"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# Fake mxcli. exec copies the script into live/ (what DESCRIBE then answers for its document) and
# appends to the model; DESCRIBE answers live/<KIND>__<Name>.out, else replays the CAPTURED v0.26.0
# not-found stderr + exit code with this name. Bad.Parse answers the verbatim v0.24.0
# "no describable document named" refusal. Every DESCRIBE is logged to describe.log.
cat > "$P/mxcli" <<MXCLI
#!/usr/bin/env bash
CAP26="$CAP26"
MXCLI
cat >> "$P/mxcli" <<'MXCLI'
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  exec)  echo "fake mxcli exec"; echo "written by $2" >> "$D/Fixture.mpr"
         n="$(grep -oE 'microflow "?Sales"?\."?[A-Za-z_]+' "$2" | head -1 | sed -E 's/.*\."?//')"
         [ -n "$n" ] && cp "$2" "$D/live/MICROFLOW__Sales.$n.out"; exit 0 ;;
esac
q="${4:-}"; echo "$q" >> "$D/describe.log"; q="${q#DESCRIBE }"; name="${q##* }"; kind="${q% *}"
f="$D/live/${kind}__${name}.out"
[ -f "$f" ] && { cat "$f"; exit 0; }
if [ "$name" = Bad.Parse ]; then
  echo "Error: no describable document named \"Bad.Parse\" found in the project; specify the type explicitly" >&2; exit 1
fi
sed -E "s/not found: [A-Za-z_.]+/not found: $name/" "$CAP26/notfound-$kind.stderr" >&2; exit "$(cat "$CAP26/notfound-$kind.rc")"
MXCLI
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
OUT=""; for a in "$@"; do case "$a" in --write-errors=*) OUT="${a#--write-errors=}" ;; esac; done
[ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT"; exit 0
MXB
chmod +x "$P/bin/"*.sh "$P/mxcli" "$WORK/mxbuild"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\ndescribe.log\nlive/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
commit_model() { ( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm m ) >/dev/null 2>&1; }
pso() { ( cd "$P" && PROJECT_ROOT="$P" bash bin/script-owners.sh "$@" ) 2>&1; }

echo "-- live: the captured not-found output"
for k in MICROFLOW NANOFLOW PAGE SNIPPET; do
  OUT="$(pso live $k Sales.Nope)"; RC=$?
  [ "$RC" -eq 0 ] && [ "$OUT" = absent ] && ok "captured v0.26.0 $k not-found reads absent" || bad "$k not-found rc $RC: $OUT"
done
OUT="$(pso live MICROFLOW Bad.Parse)"; RC=$?
[ "$RC" -eq 3 ] && ok "'no describable document' is a failed call, never absent" || bad "refusal rc $RC: $OUT"
cp "$REJ" "$P/live/"
OUT="$(pso live MICROFLOW Sales.ACT_ApprovalStep_Reject)"
[ "$OUT" = present ] && ok "an existing document reads present" || bad "present '$OUT'"
rm -f "$P/live/"*

echo "-- DESCRIBE cap: at most 5 per check, the rest UNCHECKED"
C="$P/mdlsource"; : > "$C/01-many.mdl"; : > "$C/02-many.mdl"
for i in 1 2 3 4 5 6 7; do
  printf 'create or modify microflow "Sales"."M%s" ()\nbegin\nend;\n/\n' "$i" >> "$C/01-many.mdl"
  printf 'create or modify microflow "Sales"."M%s" ()\nbegin\nend;\n/\n' "$i" >> "$C/02-many.mdl"
  printf 'x\n' > "$P/live/MICROFLOW__Sales.M$i.out"
done
pso record mdlsource/01-many.mdl >/dev/null; pso record mdlsource/02-many.mdl >/dev/null; rm -f "$P/describe.log"
OUT="$(pso check mdlsource/01-many.mdl "$P")"; RC=$?
[ "$RC" -eq 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^REVERT')" = 5 ] && ok "5 documents checked by DESCRIBE → REVERT" || bad "cap rc $RC: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^UNCHECKED.*CONFLICT (not checked')" = 2 ] && ok "the other 2: CONFLICT (not checked)" || bad "unchecked rows: $OUT"
[ "$(wc -l < "$P/describe.log" | tr -d ' ')" = 5 ] && ok "exactly 5 DESCRIBE calls" || bad "$(wc -l < "$P/describe.log") DESCRIBE calls"
rm -f "$C/01-many.mdl" "$C/02-many.mdl" "$P/live/"* "$P/.claude/loop/script-owners/written.tsv"

# ── exec.sh ──────────────────────────────────────────────────────────────────
run() {  # runs exec.sh on $1; output on stdout; rc in $WORK/rc
  commit_model
  ( cd "$P" && SKIP_BASELINE=1 SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "$1" ) > "$WORK/out" 2>&1
  echo $? > "$WORK/rc"; cat "$WORK/out"
}
row() { grep "\`$1\`" "$LOG" 2>/dev/null | tail -1; }

echo "-- exec.sh: happy path (sole owner) — no WARN, no DESCRIBE, ledger row"
printf 'create or modify microflow "Sales"."ACT_Solo" ()\nbegin\nend;\n/\n' > "$C/01-solo.mdl"
rm -f "$P/describe.log"
OUT="$(run mdlsource/01-solo.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "happy path: exit 0" || bad "happy path rc $RC: $(tail -3 "$WORK/out")"
hasnt "happy path: no WARN/NOTE" "$OUT" "WARN: restatement"
[ ! -s "$P/describe.log" ] && ok "happy path: zero DESCRIBE calls" || bad "happy path ran $(wc -l < "$P/describe.log") DESCRIBE call(s)"
grep -q "mdlsource/01-solo.mdl	MICROFLOW Sales.ACT_Solo" "$P/.claude/loop/script-owners/written.tsv" 2>/dev/null \
  && ok "a kept write is recorded in the ledger" || bad "no ledger row for the kept write"

echo "-- exec.sh: 05, then 09 (supersedes 05), replay 05, restore, replay 05"
cp "$REJ" "$C/05-reject.mdl"
{ echo "-- supersedes: 05-reject.mdl"; fix "A reason is required."; } > "$C/09-reject-fix.mdl"
OUT="$(run mdlsource/05-reject.mdl)"; hasnt "05 first run: no WARN" "$OUT" "WARN: restatement"
OUT="$(run mdlsource/09-reject-fix.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "09 (supersedes 05): no WARN, no NOTE" "$OUT" "restatement" || bad "09 rc $RC"
SNAP09="$(ls -dt "$P/.mpr-snapshots"/*/ | head -1)"
OUT="$(run mdlsource/05-reject.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "replay 05: exit 0 (warn-first)" || bad "replay rc $RC"
has "replay 05: WARN names 09" "$OUT" "superseded: mdlsource/09-reject-fix.mdl supersedes this script"
has "  BUILD-LOG cell" "$(row 05-reject.mdl)" "WARN reverts: Sales.ACT_ApprovalStep_Reject"
SNAPR="$(ls -dt "$P/.mpr-snapshots"/*/ | head -1)"   # taken before the replay: holds 09's work
( cd "$P" && bash bin/restore-mpr.sh "$SNAPR" ) >/dev/null 2>&1
fix "A reason is required." > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"   # the model again holds 09's body
grep -q 'RESTORE' "$P/.claude/loop/script-owners/written.tsv" && ok "restore-mpr.sh appended a RESTORE row" || bad "no RESTORE row"
OUT="$(run mdlsource/05-reject.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "replay 05 after the restore: WARN again (ledger alone said 05 wrote last)" "$OUT" "WARN: restatement" || bad "after-restore rc $RC"

echo "-- exec.sh: a new owner without a header — NOTE once, not in BUILD-LOG"
fix "Say why." > "$C/12-reject-again.mdl"
OUT="$(run mdlsource/12-reject-again.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "first run: one NOTE line" "$OUT" "NOTE: new owner of Sales.ACT_ApprovalStep_Reject" || bad "12 rc $RC: $(tail -3 "$WORK/out")"
hasnt "  no WARN" "$OUT" "WARN: restatement"
hasnt "  not in BUILD-LOG" "$(row 12-reject-again.mdl)" "WARN"
OUT="$(run mdlsource/12-reject-again.mdl)"
hasnt "second run: no NOTE" "$OUT" "NOTE: new owner"

echo "-- exec.sh: exec approval ask stays warn-first; =off is silent"
OUT="$(MXTK_ROOT="$TOOLKIT" CLAUDE_EXEC_APPROVAL=ask run mdlsource/05-reject.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "ask: WARN and written, exit 0" "$OUT" "fake mxcli exec" || bad "ask rc $RC"
OUT="$(MXTK_RESTATE_GUARD=off run mdlsource/05-reject.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "off: no warning" "$OUT" "restatement" || bad "off rc $RC"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
