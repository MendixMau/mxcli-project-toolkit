#!/usr/bin/env bash
# test-exec-check-refusal.sh - a pre-exec `mxcli check` refusal puts its reason in the BUILD-LOG row.
#
# usage: bash tests/wave2/test-exec-check-refusal.sh [path-to-exec.sh]
#
# Field (#445, a migration project, 2026-10-16/17): three 🚫 rows said only "mxcli check failed
# pre-exec". Their check output was not kept, so what refused them is unknown; the issue quotes
# MDL-PAGEARG01 (in mxcli since about v0.19, see BUG-70) as the likely rule.
#
# Golden input, captured verbatim from mxcli v0.26.0 (not hand-written), in
# fixtures/exec-check-refusal/. Both captures ran `mxcli check <file>` without `-p --references`;
# exec.sh adds those flags, and a reference-tier violation prints the same "✗ ... [RULE]" line,
# which the parser reads first:
#   pagearg-v0.26.0.out  `mxcli check` of mendixlabs/mxcli
#                        mdl-examples/bug-tests/1029-showpage-arg-without-context.fail.mdl:
#                        three warnings first, then the error line, ANSI colour though piped
#   syntax-v0.26.0.out   a parse failure ("Syntax errors found:" / "- line 4:0 ...", has pipes)
#
#   A  the MDL-PAGEARG01 row carries the rule id and the error line, not a warning's id
#   B  the syntax row carries the parse error, with its pipes escaped: the row keeps 5 cells
#   C  the screen still shows mxcli's own output, and mxcli check ran exactly once
#   D  a plain one-line refusal (no rule bracket) is recorded too
#   E  a reason in non-Latin text longer than 160 bytes is cut on a character boundary, not to "..."
#
# Synthetic project, stub mxcli replaying the capture. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
GOLD="$TOOLKIT/tests/wave2/fixtures/exec-check-refusal"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-chkref.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
printf '#!/usr/bin/env bash\necho "Snapshot saved: none"\n' > "$P/bin/snapshot-mpr.sh"
# check: replay $CHECK_OUT to stderr and refuse; count the calls. exec must never be reached.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in
  check) echo x >> "$CHECK_N"; cat "$CHECK_OUT" >&2; exit 1 ;;
  exec)  echo "EXEC REACHED" >> "$CHECK_N"; exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$P/bin/"*.sh "$P/mxcli"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

run() {  # run <capture-file> -> sets ROW, OUT, CALLS
  rm -rf "$P/docs" "$P/.claude" "$WORK/n"
  ( cd "$P" && CHECK_OUT="$1" CHECK_N="$WORK/n" SP_RESTART=0 MXTK_NO_INSTALL=1 TMPDIR="$WORK" \
      ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out" 2>&1
  ROW="$(grep '^| ' "$P/docs/BUILD-LOG.md" 2>/dev/null | tail -1)"
  OUT="$(cat "$WORK/out")"; CALLS="$(cat "$WORK/n" 2>/dev/null)"
}
cells() { printf '%s' "$1" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' '; }

# A
run "$GOLD/pagearg-v0.26.0.out"
case "$ROW" in *"🚫 blocked"*"check: MDL-PAGEARG01: page Probe1029.List: show page Probe1029.Detail: argument Item"*)
  ok "A: PAGEARG01 row names the rule and the error line" ;;
  *) bad "A: PAGEARG01 row names the rule and the error line" "$ROW" ;; esac
case "$ROW" in *MPR010*|*MDL-DEPR007*) bad "A: a warning's rule id leaked into the row" "$ROW" ;;
  *) ok "A: no warning rule id in the row" ;; esac
case "$ROW" in *"$(printf '\033')"*) bad "A: ANSI escape in the row" ;; *) ok "A: ANSI colour stripped" ;; esac

# B
run "$GOLD/syntax-v0.26.0.out"
case "$ROW" in *'check: line 4:0 missing'*'entity \| microflow \| page'*) ok "B: syntax error recorded, pipes escaped" ;;
  *) bad "B: syntax error recorded, pipes escaped" "$ROW" ;; esac
[ "$(cells "$ROW")" = 6 ] && ok "B: row still has 5 cells" || bad "B: row still has 5 cells" "$(cells "$ROW") bars: $ROW"

# C
case "$OUT" in *"Syntax errors found:"*) ok "C: mxcli's output still on screen" ;;
  *) bad "C: mxcli's output still on screen" ;; esac
[ "$CALLS" = x ] && ok "C: one check call, exec never reached" || bad "C: one check call, exec never reached" "$CALLS"

# D
printf 'error MDL-PAGEARG01: show page with two parameters\n' > "$WORK/plain.out"
run "$WORK/plain.out"
case "$ROW" in *"check: error MDL-PAGEARG01: show page with two parameters"*) ok "D: one-line refusal recorded" ;;
  *) bad "D: one-line refusal recorded" "$ROW" ;; esac

# E
{ printf '  \033[31m✗\033[0m '; for i in $(seq 10); do printf 'परीक्षण'; done; printf ' [MDL-REF01]\r\n'; } > "$WORK/long.out"
run "$WORK/long.out"
case "$ROW" in *"check: MDL-REF01: परीक्षणपरीक्षण"*"..."*) ok "E: long multibyte reason kept, cut with ..." ;;
  *) bad "E: long multibyte reason kept, cut with ..." "$ROW" ;; esac
_why="${ROW#*check: }"; _why="${_why%%...*}"
if printf '%s' "$_why" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && [ "$(printf '%s' "$_why" | wc -c)" -le 160 ] \
   && [ "$(printf '%s' "$_why" | wc -c)" -ge 157 ]; then ok "E: cut is valid UTF-8, 157-160 bytes"
else bad "E: cut is valid UTF-8, 157-160 bytes" "$(printf '%s' "$_why" | wc -c) bytes"; fi

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
