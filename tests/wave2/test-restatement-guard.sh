#!/usr/bin/env bash
# test-restatement-guard.sh — exec.sh's restatement warnings: #261 (a script restated from a
# stale DESCRIBE reverts an earlier exec) and #269 (re-running an older owning script reverts
# a newer one). Both used to exit 0 with no word.
#
# Usage: bash tests/wave2/test-restatement-guard.sh [path-to-exec.sh]
#        script-owners.sh and describe-baseline.sh are taken from the same directory as exec.sh.
#
# Covers
#   owners:   `docs` over REAL MDL (mxcli v0.23.0 and v0.26.0 DESCRIBE captures, the shipped
#             StyleGallery mdlsource tree, skills/agents-examples) matches a plain grep of
#             statement heads (36); StyleGallery reports 0 of 20 co-owned. `check`: an unrecorded
#             older owner, a replay of an older script, `-- supersedes:` / `-- superseded-by:`,
#             a superseded script replayed, the done- rename, two-tree app/mdlsource/.
#             `record` / `last-writer`: the ledger settles a replay without asking mxcli.
#   baseline: `stamp` writes one header per restated document; `verify` is SAME on the same
#             model, DRIFT when the live message changed (the #261 shape), DRIFT when an absent
#             doc appeared, SAME on a re-run by the last recorded writer and on a fresh model.
#             A missing document is read from the captured v0.26.0 not-found output.
#   exec.sh:  the two field shapes WARN and still write, exit 0, with the warning in the
#             BUILD-LOG row; exec approval `ask` does not turn them into a refusal; =off is
#             silent; a re-stamped script with a supersedes header is silent; a kept write is
#             recorded in the ledger. HAPPY PATH: no co-owner and no header → no WARN and zero
#             DESCRIBE calls.
#
# Against master's exec.sh every exec.sh case fails (no warning), and the owners/baseline cases
# fail because the two scripts do not exist there. NOTHING here touches a real .mpr or mxbuild.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
BIN="$(dirname "$SUBJECT")"
OWNERS="$BIN/script-owners.sh"
BASEL="$BIN/describe-baseline.sh"
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
for f in "$OWNERS" "$BASEL"; do [ -f "$f" ] || bad "[setup] $(basename "$f") not found beside exec.sh"; done

# ── owners: parser over real MDL ─────────────────────────────────────────────
echo "-- owners: docs over real MDL"
GREP_N=0; DOCS_N=0
for f in "$CAP"/*.out "$CAP26"/*.out "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl "$TOOLKIT"/skills/agents-examples/*.mdl; do
  g="$(grep -ciE '^[[:space:]]*create[[:space:]]+(or[[:space:]]+(modify|replace)[[:space:]]+)?(microflow|nanoflow|page|snippet)[[:space:]]' "$f" || true)"
  d="$(bash "$OWNERS" docs "$f" 2>/dev/null | grep -c . || true)"
  GREP_N=$((GREP_N + g)); DOCS_N=$((DOCS_N + d))
done
[ "$GREP_N" -eq 36 ] && ok "[setup] 36 statement heads in the golden files" || bad "[setup] golden grep found $GREP_N, expected 36"
[ "$DOCS_N" -eq "$GREP_N" ] && ok "docs lists every head ($DOCS_N)" || bad "docs listed $DOCS_N, grep $GREP_N"
OUT="$(bash "$OWNERS" docs "$REJ" 2>&1)"
has "a v0.23.0 DESCRIBE capture parses as a modify of its microflow" "$OUT" "MICROFLOW	Sales.ACT_ApprovalStep_Reject	"
OUT="$(bash "$OWNERS" docs "$CAP26/PAGE__Administration.ChangePasswordForm.out" 2>&1)"
has "a v0.26.0 page capture ('page X folder ...') parses" "$OUT" "PAGE	Administration.ChangePasswordForm	2	modify"
OUT="$(bash "$OWNERS" count "$TOOLKIT/examples/stylegallery" 2>&1)"
[ "$OUT" = "0 20" ] && ok "StyleGallery tree: 0 of 20 co-owned" || bad "StyleGallery count '$OUT', expected '0 20'"

# ── owners: check ────────────────────────────────────────────────────────────
echo "-- owners: check"
O="$WORK/own"; mkdir -p "$O/mdlsource"
cp "$REJ" "$O/mdlsource/05-reject.mdl"; cp "$APP" "$O/mdlsource/06-approve.mdl"; cp "$REJ" "$O/mdlsource/09-reject-fix.mdl"
chk() { ( cd "$O" && PROJECT_ROOT="$O" bash "$OWNERS" check "$1" "$O" ) 2>&1; }
OUT="$(bash "$OWNERS" report "$O" 2>&1)"
has "report names the co-owned microflow and both scripts" "$OUT" "MICROFLOW Sales.ACT_ApprovalStep_Reject — 2 scripts: mdlsource/05-reject.mdl, mdlsource/09-reject-fix.mdl"
has "report summary" "$OUT" "multi-owner: 1 of 2"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "new restatement without a header: older owner named" "$OUT" "older owner mdlsource/05-reject.mdl" || bad "check rc $RC on an unrecorded older owner"
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "replaying the older script (no ledger, no mxcli): newer owner named" "$OUT" "newer owner mdlsource/09-reject-fix.mdl" || bad "check rc $RC on a replay"
OUT="$(chk mdlsource/06-approve.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "a sole owner passes" || bad "sole owner rc $RC: $OUT"
printf 'create microflow "Sales"."ACT_ApprovalStep_Reject" ()\nbegin\nend;\n/\n' > "$O/mdlsource/12-plain.mdl"
OUT="$(chk mdlsource/12-plain.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "a plain create restates nothing (mxcli refuses an existing name)" || bad "plain create rc $RC: $OUT"
rm -f "$O/mdlsource/12-plain.mdl"
{ echo "-- supersedes: 05-reject.mdl"; cat "$REJ"; } > "$O/mdlsource/09-reject-fix.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "-- supersedes: settles it for the new owner" || bad "supersedes ignored (rc $RC): $OUT"
OUT="$(chk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "replaying a superseded script is a conflict" "$OUT" "superseded: mdlsource/09-reject-fix.mdl supersedes this script" || bad "superseded replay rc $RC"
cp "$REJ" "$O/mdlsource/09-reject-fix.mdl"
{ echo "-- superseded-by: 09-reject-fix.mdl"; cat "$REJ"; } > "$O/mdlsource/05-reject.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "-- superseded-by: in the old script settles it too" || bad "superseded-by ignored (rc $RC): $OUT"
# iterative-build-loop.md renames an executed script done-<name>; run order and header names
# must survive that (a raw sort put done-05 after 09 and called the NEW script a replay).
cp "$REJ" "$O/mdlsource/done-05-reject.mdl"; rm -f "$O/mdlsource/05-reject.mdl"; cp "$REJ" "$O/mdlsource/09-reject-fix.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "done-05 still runs before 09: older owner, not 'newer'" "$OUT" "older owner mdlsource/done-05-reject.mdl" || bad "done- ordering rc $RC: $OUT"
hasnt "  and the new script is not called a replay" "$OUT" "newer owner"
OUT="$(bash "$OWNERS" report "$O" 2>&1)"
has "report keeps run order across the rename" "$OUT" "2 scripts: mdlsource/done-05-reject.mdl, mdlsource/09-reject-fix.mdl"
{ echo "-- supersedes: 05-reject.mdl"; cat "$REJ"; } > "$O/mdlsource/09-reject-fix.mdl"
OUT="$(chk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "'-- supersedes: 05-reject.mdl' still names done-05-reject.mdl" || bad "supersedes lost after rename (rc $RC): $OUT"
# Two-tree checkout: the .mpr and mdlsource/ under app/.
T="$WORK/twotree"; mkdir -p "$T/app/mdlsource"; cp "$REJ" "$T/app/mdlsource/05-reject.mdl"; cp "$REJ" "$T/app/mdlsource/09-reject-fix.mdl"
OUT="$(bash "$OWNERS" count "$T" 2>&1)"
[ "$OUT" = "1 1" ] && ok "two-tree: app/mdlsource/ is found (1 of 1 co-owned)" || bad "two-tree count '$OUT', expected '1 1'"
OUT="$( ( cd "$T" && PROJECT_ROOT="$T" bash "$OWNERS" check app/mdlsource/09-reject-fix.mdl "$T" ) 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "two-tree: check names the older owner" "$OUT" "older owner app/mdlsource/05-reject.mdl" || bad "two-tree check rc $RC: $OUT"

echo "-- owners: the last-writer ledger settles a replay without mxcli"
L="$WORK/ledger"; mkdir -p "$L/mdlsource"
cp "$REJ" "$L/mdlsource/05-reject.mdl"
{ echo "-- supersedes: 05-reject.mdl"; sed "s/A comment is required to reject./A reason is required./" "$REJ"; } > "$L/mdlsource/09-reject-fix.mdl"
lchk() { ( cd "$L" && PROJECT_ROOT="$L" bash "$OWNERS" check "$1" "$L" ) 2>&1; }
lrec() { ( cd "$L" && PROJECT_ROOT="$L" bash "$OWNERS" record "$1" ) 2>&1; }
OUT="$(lchk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && ok "[control] no ledger and no ./mxcli: replaying superseded 05 stays a conflict" || bad "[control] rc $RC — the ledger cases prove nothing"
lrec mdlsource/05-reject.mdl >/dev/null
OUT="$( ( cd "$L" && PROJECT_ROOT="$L" bash "$OWNERS" last-writer "MICROFLOW Sales.ACT_ApprovalStep_Reject" ) 2>&1)"
[ "$OUT" = "mdlsource/05-reject.mdl" ] && ok "record + last-writer: 05 is the last writer" || bad "last-writer '$OUT'"
OUT="$(lchk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "rebuild in run order: 05's own write is the last, re-running 05 is quiet" || bad "re-run of 05 warned (rc $RC): $OUT"
OUT="$(lchk mdlsource/09-reject-fix.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "then 09 (supersedes 05) is quiet" || bad "09 warned (rc $RC): $OUT"
lrec mdlsource/09-reject-fix.mdl >/dev/null
OUT="$(lchk mdlsource/05-reject.mdl)"; RC=$?
[ "$RC" -eq 1 ] && has "09's write is the last: replaying 05 now is the conflict (#269)" "$OUT" "superseded: mdlsource/09-reject-fix.mdl" || bad "replay over 09 rc $RC: $OUT"
mv "$L/mdlsource/09-reject-fix.mdl" "$L/mdlsource/done-09-reject-fix.mdl"
OUT="$( ( cd "$L" && PROJECT_ROOT="$L" bash "$OWNERS" last-writer "MICROFLOW Sales.ACT_ApprovalStep_Reject" ) 2>&1)"
[ "$OUT" = "mdlsource/09-reject-fix.mdl" ] && ok "  ledger key survives the done- rename" || bad "ledger key '$OUT'"

# ── fixture project for baseline + exec.sh ───────────────────────────────────
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$P/live"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
for f in "$OWNERS" "$BASEL"; do [ -f "$f" ] && cp "$f" "$P/bin/"; done
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# Fake mxcli: check passes, exec appends to the model (and, with FAKE_APPLY="<src>=<dst>", puts
# the script's body into live/ the way a real exec changes what DESCRIBE prints). DESCRIBE replays
# live/<KIND>__<Name>.out. A missing document replays the CAPTURED v0.26.0 not-found output
# (fixtures/restatement-guard/notfound-<KIND>.stderr + .rc, nothing on stdout) with this name;
# Bad.Parse answers the verbatim v0.24.0 "no describable document named" refusal
# (conformance-check.sh). Every DESCRIBE is logged to describe.log.
cat > "$P/mxcli" <<MXCLI
#!/usr/bin/env bash
CAP26="$CAP26"
MXCLI
cat >> "$P/mxcli" <<'MXCLI'
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  exec)  echo "fake mxcli exec"; echo "written by the script" >> "$D/Fixture.mpr"
         [ -n "${FAKE_APPLY:-}" ] && cp "${FAKE_APPLY%%=*}" "$D/live/${FAKE_APPLY#*=}"; exit 0 ;;
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
cp "$REJ" "$APP" "$P/live/"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\ndescribe.log\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
commit_model() { ( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm m ) >/dev/null 2>&1; }
db() { ( cd "$P" && bash bin/describe-baseline.sh "$@" ) 2>&1; }

# ── baseline: stamp / verify ─────────────────────────────────────────────────
echo "-- baseline: stamp and verify"
S="$P/mdlsource/10-reject-msg.mdl"
cp "$REJ" "$S"; cat "$APP" >> "$S"
sed 's/ACT_ApprovalStep_Approve/ACT_ApprovalStep_Hold/g' "$APP" >> "$S"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 2 ] && has "no header: NOBASELINE with the restated count" "$OUT" "NOBASELINE	3" || bad "verify without header rc $RC: $OUT"
OUT="$(db stamp "$S")"; RC=$?
[ "$RC" -eq 0 ] && ok "stamp rc 0" || bad "stamp rc $RC: $OUT"
[ "$(grep -c '^-- baseline: ' "$S" 2>/dev/null)" = 3 ] && ok "three header lines" || bad "header lines: $(grep -c '^-- baseline: ' "$S" 2>/dev/null)"
grep -q '^-- baseline: Sales.ACT_ApprovalStep_Hold absent' "$S" && ok "a document missing from the model (captured not-found) is stamped absent" || bad "no absent line"
grep -qE '^-- baseline: Sales.ACT_ApprovalStep_Reject sha256=[0-9a-f]{64}' "$S" && ok "existing document stamped with a sha256" || bad "no sha256 line"
db stamp "$S" >/dev/null
[ "$(grep -c '^-- baseline: ' "$S" 2>/dev/null)" = 3 ] && ok "re-stamp replaces, never duplicates" || bad "re-stamp duplicated headers"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 0 ] && ok "unchanged model: verify rc 0" || bad "verify on unchanged model rc $RC: $OUT"
# The #261 shape: an earlier script changed the live message after this one was drafted.
sed "s/A comment is required to reject./Please add a comment before rejecting./" "$REJ" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
cp "$APP" "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 1 ] && ok "changed live body: verify rc 1" || bad "verify rc $RC after drift"
has "DRIFT row names the changed microflow" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Reject	changed since the script was drafted"
has "the diff shows the live message the script would revert" "$OUT" "+    validation feedback \$ApprovalStep/Comments message 'Please add a comment before rejecting.'"
has "absent at draft, present now" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Hold	created since the script was drafted"
hasnt "the unchanged microflow is not reported" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Approve"
rm -f "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"

echo "-- baseline: a re-run by the last recorded writer, and a fresh model, are not drift"
B="$P/mdlsource/11-reject-own.mdl"
sed "s/A comment is required to reject./A reason is required./" "$REJ" > "$B"
db stamp "$B" >/dev/null
LIVE_BEFORE="$(cat "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out")"
grep -v '^-- baseline:' "$B" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"   # the exec wrote B's body
OUT="$(db verify "$B")"; RC=$?
[ "$RC" -eq 1 ] && ok "[control] without a ledger row the script's own write reads as drift" || bad "[control] rc $RC — the ledger cases below prove nothing"
( cd "$P" && PROJECT_ROOT="$P" bash bin/script-owners.sh record "$B" )
OUT="$(db verify "$B")"; RC=$?
[ "$RC" -eq 0 ] && has "re-run: this script is the last recorded writer → SAME" "$OUT" "last recorded writer" || bad "re-run after exec rc $RC: $OUT"
mv "$B" "$P/mdlsource/done-11-reject-own.mdl"
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 0 ] && ok "  still SAME after the done- rename" || bad "done- rename broke the ledger match (rc $RC): $OUT"
rm -f "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 0 ] && has "fresh model: absent → SAME (the script creates it)" "$OUT" "absent: this script creates it" || bad "rebuild rc $RC: $OUT"
cp "$REJ" "$P/live/"   # neither the draft-time body nor B's, and B is no longer the last writer
( cd "$P" && PROJECT_ROOT="$P" bash bin/script-owners.sh record "$S" )
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 1 ] && ok "someone else's later write is still drift" || bad "foreign body rc $RC: $OUT"
rm -f "$P/mdlsource/done-11-reject-own.mdl" "$P/.claude/loop/script-owners/written.tsv"
OUT="$(db live MICROFLOW Bad.Parse)"; RC=$?
[ "$RC" -eq 3 ] && ok "'no describable document' is a failed call, never 'absent'" || bad "refusal read as rc $RC: $OUT"
for k in MICROFLOW NANOFLOW PAGE SNIPPET; do
  OUT="$(db live $k Sales.Nope)"; RC=$?
  [ "$RC" -eq 0 ] && [ "$OUT" = absent ] && ok "captured v0.26.0 $k not-found reads absent" || bad "$k not-found rc $RC: $OUT"
done
printf '%s\n' "$LIVE_BEFORE" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"   # the drifted body again

# ── exec.sh ──────────────────────────────────────────────────────────────────
run() {  # env... ; runs exec.sh on $RUN_SCRIPT; prints output; rc in $WORK/rc
  ( cd "$P" && SKIP_BASELINE=1 SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "${RUN_SCRIPT:-mdlsource/10-reject-msg.mdl}" ) > "$WORK/out" 2>&1
  echo $? > "$WORK/rc"; cat "$WORK/out"
}
reset_model() { ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents ) 2>/dev/null; }

echo "-- exec.sh: happy path (sole owner, no header) — no WARN, no DESCRIBE"
printf 'create or modify microflow "Sales"."ACT_Solo" ()\nbegin\nend;\n/\n' > "$P/mdlsource/01-solo.mdl"; commit_model
rm -f "$P/describe.log"
OUT="$(RUN_SCRIPT=mdlsource/01-solo.mdl run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "happy path: exit 0" || bad "happy path rc $RC: $(tail -3 "$WORK/out")"
hasnt "happy path: no WARN line" "$OUT" "WARN: "
[ ! -s "$P/describe.log" ] && ok "happy path: zero DESCRIBE calls" || bad "happy path ran $(wc -l < "$P/describe.log") DESCRIBE call(s)"
grep -q "mdlsource/01-solo.mdl	MICROFLOW Sales.ACT_Solo" "$P/.claude/loop/script-owners/written.tsv" 2>/dev/null \
  && ok "a kept write is recorded in the last-writer ledger" || bad "no ledger row for the kept write"
reset_model

echo "-- exec.sh: the #261 + #269 shapes warn and still write"
cp "$REJ" "$P/mdlsource/05-reject.mdl"; commit_model
OUT="$(run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "warn-first: exit 0" || bad "warn mode rc $RC: $(tail -3 "$WORK/out")"
has "co-owner WARN line" "$OUT" "WARN: restatement: 1 document(s) this script restates are also owned"
has "  names the older owner" "$OUT" "older owner mdlsource/05-reject.mdl"
has "stale-draft WARN line" "$OUT" "WARN: stale draft"
has "  names the drifted microflow" "$OUT" "Sales.ACT_ApprovalStep_Reject — changed since the script was drafted"
has "the write happened" "$OUT" "fake mxcli exec"
ROW="$(grep '10-reject-msg.mdl' "$LOG" 2>/dev/null | tail -1)"
has "BUILD-LOG row carries the stale-baseline warning" "$ROW" "WARN stale baseline: Sales.ACT_ApprovalStep_Reject"
has "BUILD-LOG row carries the co-owner warning" "$ROW" "WARN co-owned: Sales.ACT_ApprovalStep_Reject"
has "BUILD-LOG row is still an applied row" "$ROW" "✅ applied"
reset_model

echo "-- exec.sh: exec approval ask does not make it a refusal"
OUT="$(MXTK_ROOT="$TOOLKIT" CLAUDE_EXEC_APPROVAL=ask run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "ask: warned and written, exit 0" "$OUT" "fake mxcli exec" || bad "ask mode rc $RC"
reset_model

echo "-- exec.sh: MXTK_RESTATE_GUARD=off is silent"
OUT="$(MXTK_RESTATE_GUARD=off run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "off: no warning" "$OUT" "WARN: " || bad "off rc $RC"
reset_model

echo "-- exec.sh: replay of an older owner after the newer one landed (#269)"
OUT="$(RUN_SCRIPT=mdlsource/05-reject.mdl run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "replay: WARN names the newer owner, exit 0" "$OUT" "newer owner mdlsource/10-reject-msg.mdl — replaying this script reverts it" || bad "replay rc $RC: $(tail -3 "$WORK/out")"
reset_model

echo "-- exec.sh: re-stamped, with a supersedes header, then re-run after its own write: quiet"
db stamp "$S" >/dev/null
{ echo "-- supersedes: 05-reject.mdl"; cat "$S"; } > "$S.tmp" && mv "$S.tmp" "$S"
grep -v '^--' "$S" | sed -n '/ACT_ApprovalStep_Reject/,/^\/$/p' > "$WORK/10.body"
commit_model
OUT="$(FAKE_APPLY="$WORK/10.body=MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "re-stamped + supersedes: no WARN" "$OUT" "WARN: " || bad "rc $RC: $(tail -3 "$WORK/out")"
commit_model
OUT="$(run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "re-run after its own write (ledger): no stale-draft WARN" "$OUT" "WARN: stale draft" || bad "re-run rc $RC: $(tail -3 "$WORK/out")"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
