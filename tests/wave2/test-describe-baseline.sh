#!/usr/bin/env bash
# test-describe-baseline.sh — #261: a script restated from a DESCRIBE taken before an earlier
# script ran reverted that script's work (exit 0, no word). exec.sh now WARNs through
# describe-baseline.sh when the script carries a `-- baseline:` header.
#
# Usage: bash tests/wave2/test-describe-baseline.sh [path-to-exec.sh]
#        describe-baseline.sh and script-owners.sh are taken from the same directory as exec.sh.
#
# Covers
#   stamp:   one header per restated document plus `-- baseline-mxcli: <version>` (version from
#            the CAPTURED `mxcli --version` output); absent documents from the captured v0.26.0
#            not-found output; re-stamp replaces.
#   verify:  SAME on the same model; DRIFT with a diff when the live message changed (the #261
#            shape); DRIFT when an absent document appeared; SAME for a re-run by the last
#            recorded writer and on a fresh model; STALEHEADER alone is a warn (exit 1); after an
#            mxcli upgrade a changed hash is RESTAMP, not DRIFT.
#   exec.sh: WARN + BUILD-LOG cell, exit 0; `ask` approval stays exit 0; =off silent; a script
#            without a header costs zero DESCRIBE calls.
# NOTHING here touches a real .mpr, mxcli or mxbuild.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
BIN="$(dirname "$SUBJECT")"
CAP="$TOOLKIT/tests/wave2/fixtures/context-pack/capture/describe"
CAP26="$TOOLKIT/tests/wave2/fixtures/restatement-guard"
REJ="$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
APP="$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dbl.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -4)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"
for f in describe-baseline.sh script-owners.sh; do [ -f "$BIN/$f" ] || bad "[setup] $f not found beside exec.sh"; done

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$P/live"
printf 'not a real model\n' > "$P/Fixture.mpr"; printf 'bson\n' > "$P/mprcontents/a.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
for f in describe-baseline.sh script-owners.sh; do [ -f "$BIN/$f" ] && cp "$BIN/$f" "$P/bin/"; done
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# Fake mxcli: --version replays the CAPTURED v0.26.0 line (FAKE_VERSION rewrites its number);
# exec appends to the model (FAKE_APPLY="<src>=<dst>" also puts a body into live/); DESCRIBE answers
# live/<KIND>__<Name>.out, else the CAPTURED v0.26.0 not-found stderr + exit code. Bad.Parse answers
# the verbatim v0.24.0 refusal. Every DESCRIBE is logged to describe.log.
cat > "$P/mxcli" <<MXCLI
#!/usr/bin/env bash
CAP26="$CAP26"
MXCLI
cat >> "$P/mxcli" <<'MXCLI'
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --version) sed "s/v0\.26\.0/${FAKE_VERSION:-v0.26.0}/" "$CAP26/mxcli-version-v0.26.0.txt"; exit 0 ;;
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
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\ndescribe.log\nlive/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
commit_model() { ( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm m ) >/dev/null 2>&1; }
db() { ( cd "$P" && bash bin/describe-baseline.sh "$@" ) 2>&1; }

echo "-- stamp and verify"
S="$P/mdlsource/10-reject-msg.mdl"
cp "$REJ" "$S"; cat "$APP" >> "$S"
sed 's/ACT_ApprovalStep_Approve/ACT_ApprovalStep_Hold/g' "$APP" >> "$S"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 2 ] && has "no header: NOBASELINE with the restated count" "$OUT" "NOBASELINE	3" || bad "verify without header rc $RC: $OUT"
OUT="$(db stamp "$S")"; RC=$?
[ "$RC" -eq 0 ] && ok "stamp rc 0" || bad "stamp rc $RC: $OUT"
[ "$(grep -c '^-- baseline: ' "$S")" = 3 ] && ok "three header lines" || bad "header lines: $(grep -c '^-- baseline: ' "$S")"
grep -q '^-- baseline-mxcli: v0.26.0$' "$S" && ok "mxcli version recorded from the captured --version line" || bad "no baseline-mxcli line"
grep -q '^-- baseline: Sales.ACT_ApprovalStep_Hold absent' "$S" && ok "missing document (captured not-found) stamped absent" || bad "no absent line"
grep -qE '^-- baseline: Sales.ACT_ApprovalStep_Reject sha256=[0-9a-f]{64}' "$S" && ok "existing document stamped with a sha256" || bad "no sha256 line"
db stamp "$S" >/dev/null
[ "$(grep -c '^-- baseline' "$S")" = 4 ] && ok "re-stamp replaces, never duplicates" || bad "re-stamp duplicated headers"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 0 ] && ok "unchanged model: verify rc 0" || bad "verify on unchanged model rc $RC: $OUT"
sed "s/A comment is required to reject./Please add a comment before rejecting./" "$REJ" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
cp "$APP" "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"
OUT="$(db verify "$S")"; RC=$?
[ "$RC" -eq 1 ] && ok "changed live body: verify rc 1" || bad "verify rc $RC after drift"
has "DRIFT row names the changed microflow" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Reject	changed since the script was drafted"
has "the diff shows the live message the script would revert" "$OUT" "+    validation feedback \$ApprovalStep/Comments message 'Please add a comment before rejecting.'"
has "absent at draft, present now" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Hold	created since the script was drafted"
hasnt "the unchanged microflow is not reported" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Approve"
OUT="$(FAKE_VERSION=v0.27.0 db verify "$S")"; RC=$?
[ "$RC" -eq 1 ] && has "after an mxcli upgrade: RESTAMP, not DRIFT" "$OUT" "RESTAMP	Sales.ACT_ApprovalStep_Reject	re-stamp after mxcli upgrade (v0.26.0 → v0.27.0)" || bad "upgrade rc $RC: $OUT"
hasnt "  no DRIFT row then" "$OUT" "DRIFT"
rm -f "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"
H="$P/mdlsource/13-header-only.mdl"
{ grep '^-- baseline' "$S"; cat "$APP"; } > "$H"; cp "$APP" "$P/live/"
OUT="$(db verify "$H")"; RC=$?
[ "$RC" -eq 1 ] && has "STALEHEADER alone is a warn (rc 1)" "$OUT" "STALEHEADER	Sales.ACT_ApprovalStep_Reject" || bad "STALEHEADER rc $RC: $OUT"
rm -f "$H"

echo "-- a re-run by the last recorded writer, and a fresh model, are not drift"
B="$P/mdlsource/11-reject-own.mdl"
sed "s/A comment is required to reject./A reason is required./" "$REJ" > "$B"
db stamp "$B" >/dev/null
LIVE_BEFORE="$(cat "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out")"
grep -v '^-- baseline' "$B" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
OUT="$(db verify "$B")"; RC=$?
[ "$RC" -eq 1 ] && ok "[control] without a ledger row the script's own write reads as drift" || bad "[control] rc $RC"
( cd "$P" && PROJECT_ROOT="$P" bash bin/script-owners.sh record "$B" )
OUT="$(db verify "$B")"; RC=$?
[ "$RC" -eq 0 ] && has "re-run: this script is the last recorded writer → SAME" "$OUT" "last recorded writer" || bad "re-run rc $RC: $OUT"
mv "$B" "$P/mdlsource/done-11-reject-own.mdl"
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 0 ] && ok "  still SAME after the done- rename" || bad "done- rename rc $RC: $OUT"
rm -f "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 0 ] && has "fresh model: absent → SAME" "$OUT" "absent: this script creates it" || bad "rebuild rc $RC: $OUT"
cp "$REJ" "$P/live/"
( cd "$P" && PROJECT_ROOT="$P" bash bin/script-owners.sh record "$S" )
OUT="$(db verify "$P/mdlsource/done-11-reject-own.mdl")"; RC=$?
[ "$RC" -eq 1 ] && ok "someone else's later write is still drift" || bad "foreign body rc $RC: $OUT"
rm -f "$P/mdlsource/done-11-reject-own.mdl" "$P/.claude/loop/script-owners/written.tsv"
OUT="$(db live MICROFLOW Bad.Parse)"; RC=$?
[ "$RC" -eq 3 ] && ok "'no describable document' is a failed call, never absent" || bad "refusal rc $RC: $OUT"
printf '%s\n' "$LIVE_BEFORE" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"

# ── exec.sh ──────────────────────────────────────────────────────────────────
run() {
  commit_model
  ( cd "$P" && SKIP_BASELINE=1 SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "$1" ) > "$WORK/out" 2>&1
  echo $? > "$WORK/rc"; cat "$WORK/out"
}
echo "-- exec.sh"
printf 'create or modify microflow "Sales"."ACT_Solo" ()\nbegin\nend;\n/\n' > "$P/mdlsource/01-solo.mdl"
rm -f "$P/describe.log"
OUT="$(run mdlsource/01-solo.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "no header: exit 0, no stale-draft WARN" "$OUT" "WARN: stale draft" || bad "rc $RC"
[ ! -s "$P/describe.log" ] && ok "no header: zero DESCRIBE calls" || bad "$(wc -l < "$P/describe.log") DESCRIBE call(s)"
OUT="$(run mdlsource/10-reject-msg.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "stale draft: exit 0 (warn-first)" || bad "rc $RC: $(tail -3 "$WORK/out")"
has "stale-draft WARN line" "$OUT" "WARN: stale draft"
has "  names the drifted microflow" "$OUT" "Sales.ACT_ApprovalStep_Reject — changed since the script was drafted"
has "the write happened" "$OUT" "fake mxcli exec"
has "BUILD-LOG cell" "$(grep '10-reject-msg.mdl' "$LOG" | tail -1)" "WARN stale baseline: Sales.ACT_ApprovalStep_Reject"
OUT="$(MXTK_ROOT="$TOOLKIT" CLAUDE_EXEC_APPROVAL=ask run mdlsource/10-reject-msg.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "ask: WARN and written, exit 0" "$OUT" "fake mxcli exec" || bad "ask rc $RC"
OUT="$(MXTK_RESTATE_GUARD=off run mdlsource/10-reject-msg.mdl)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "off: silent" "$OUT" "WARN: stale draft" || bad "off rc $RC"
db stamp "$S" >/dev/null
grep -v '^--' "$S" | sed -n '/ACT_ApprovalStep_Reject/,/^\/$/p' > "$WORK/10.body"
OUT="$(FAKE_APPLY="$WORK/10.body=MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" run mdlsource/10-reject-msg.mdl)"
hasnt "re-stamped: no stale-draft WARN" "$OUT" "WARN: stale draft"
OUT="$(run mdlsource/10-reject-msg.mdl)"
hasnt "re-run after its own write (ledger): no stale-draft WARN" "$OUT" "WARN: stale draft"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
