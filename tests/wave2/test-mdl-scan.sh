#!/usr/bin/env bash
# test-mdl-scan.sh — bin/mdl-scan.sh, its rules, and its wiring into project-bin/exec.sh (#349).
#
# Usage: bash tests/wave2/test-mdl-scan.sh [path-to-mdl-scan.sh] [path-to-exec.sh]
#
# Field-proof (CLAUDE.md "Shipping an instrument", rule 1): every rule's bad MDL comes from the
# bug-log entry that captured its failure. Each fixture under fixtures/mdl-scan/ carries
# `-- key:` lines (the captured MDL, verbatim) and `-- evidence:` lines (the captured CE /
# mxbuild output, verbatim); this file proves both are really in the ledger, so a fixture
# cannot drift into something nobody saw fail. No live mxcli or mxbuild run backs this PR:
# the proof is the bug log's captured output.
#
#   R  every rules-file row has <id>.bad.mdl + <id>.good.mdl; bad fires that id, on the key
#      line, exit 1; good is silent, exit 0; keys and evidence are verbatim in the ledger
#   P  every rule id is marked as scanner-enforced in learned-mdl-preflight.md, and only those
#   C  clean corpus: the StyleGallery example (applied, 0 errors in mx check) — no hit
#   L  lexer: comments are not scanned, `--` inside a string literal is not a comment,
#      a multi-line ContentParams list is read whole, a body-less customContent column
#      does not capture the next column's body
#   U  usage: exit 2 on no script, unreadable script, unknown flag, -p with no model
#   S  speed: a 2,000-line script scans in under 1 s
#   W  every shipped rule is `warn` (no field run yet); severity is warn|block only
#   E  exec.sh: a warn hit is printed, noted in BUILD-LOG, and the exec goes on. Through a
#      test-only rules file with one `block` rule: a hit refuses before the lock and the snapshot; FORCE_EXEC/SKIP_CHECK do not
#      skip it; MXTK_SCAN_OVERRIDE=1 does not; MXTK_SCAN_OVERRIDE="<reason>" does, and the
#      BUILD-LOG row says so; a clean script goes through; no toolkit or a scan error (exit 2)
#      warns and goes on
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="${1:-$TOOLKIT/bin/mdl-scan.sh}"
EXEC_SH="${2:-$TOOLKIT/project-bin/exec.sh}"
case "$SCAN" in /*) ;; *) SCAN="$PWD/$SCAN" ;; esac
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/mdl-scan"
RULES="$TOOLKIT/bin/lib/mdl-scan-rules.tsv"
LEDGER="$TOOLKIT/bug-logs/mxcli-bugs.md"
PREFLIGHT="$TOOLKIT/skills/learned-mdl-preflight.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mdlscan.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
scan() { bash "$SCAN" "$@" >"$WORK/out" 2>"$WORK/err"; echo $?; }

echo "== R: one bad + one good fixture per rule, proven from the ledger"
IDS="$(grep -v '^#' "$RULES" | cut -f1 | grep . )"
NR=0
for id in $IDS; do
  NR=$((NR+1))
  b="$FX/$id.bad.mdl"; g="$FX/$id.good.mdl"
  [ -f "$b" ] && [ -f "$g" ] || { bad "$id: missing $id.bad.mdl or $id.good.mdl"; continue; }
  nk=0; miss=""
  while IFS= read -r k; do
    nk=$((nk+1))
    grep -qF -- "$k" "$LEDGER" || grep -qF -- "$k" "$PREFLIGHT" || miss="$miss [$k]"
  done <<EOF
$(sed -n 's/^-- key: //p' "$b" "$g")
EOF
  ne=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    ne=$((ne+1)); grep -qF -- "$e" "$LEDGER" || miss="$miss [evidence: $e]"
  done <<EOF
$(sed -n 's/^-- evidence: //p' "$b")
EOF
  [ "$ne" -ge 1 ] && [ -z "$miss" ] && ok "$id: $nk key(s) + $ne evidence line(s) verbatim in the ledger" \
    || bad "$id: not captured (evidence lines: $ne) —$miss"
  sev="$(awk -F'\t' -v id="$id" '$1 == id { print $3 }' "$RULES")"
  want=3; [ "$sev" = block ] && want=1
  rc=$(scan "$b")
  ids_hit="$(cut -d' ' -f1 "$WORK/out" | sort -u | tr '\n' ' ')"
  [ "$rc" = "$want" ] && [ "$ids_hit" = "$id " ] && ok "$id fires on the captured bad MDL (exit $rc for $sev, only $id)" \
    || bad "$id bad: exit $rc (want $want for '$sev'), ids [$ids_hit]"
  # the hit names a line holding code, not a comment line
  ln="$(sed -n "s/^$id [^:]*:\([0-9]*\) .*/\1/p" "$WORK/out" | head -1)"
  case "$(sed -n "${ln:-0}p" "$b")" in
    ""|--*) bad "$id hit points at line '${ln:-?}', which is not code" ;;
    *) ok "$id hit is reported at line $ln, the offending statement" ;;
  esac
  grep -q "^$id .*:$ln .* → .* \[$sev\]\$" "$WORK/out" && ok "$id output is 'STOP-<n> <file>:<line> <message> → <fix> [$sev]'" \
    || bad "$id output shape: $(head -1 "$WORK/out")"
  rc=$(scan "$g")
  [ "$rc" = 0 ] && [ ! -s "$WORK/out" ] && ok "$id is silent on the corrected form" \
    || bad "$id good: exit $rc — $(head -1 "$WORK/out")"
done
[ "$NR" -ge 1 ] && ok "rules file has $NR rule(s)" || bad "rules file has no rules — the scan would pass everything"

echo "== P: the preflight table marks exactly the enforced rows"
MARKED="$(grep -oE '^\| [0-9]+[a-z]? 🔎' "$PREFLIGHT" | sed -E 's/^\| ([0-9a-z]+) .*/STOP-\1/' | sort | tr '\n' ' ')"
WANT="$(printf '%s\n' $IDS | sort | tr '\n' ' ')"
[ "$MARKED" = "$WANT" ] && ok "preflight marks [$MARKED]" || bad "preflight marks [$MARKED], rules file has [$WANT]"

echo "== W: warn-only until a field run (review of #355)"
NB="$(grep -v '^#' "$RULES" | awk -F'\t' 'NF >= 6 && $3 != "warn"' | wc -l | tr -d ' ')"
[ "$NB" = 0 ] && ok "every shipped rule is severity warn" || bad "$NB shipped rule(s) not warn — a flip to block needs a cited field run (rules-file header)"
grep -v '^#' "$RULES" | awk -F'\t' 'NF >= 6 && $3 != "warn" && $3 != "block" { bad = 1 } END { exit bad }' \
  && ok "severity column holds only warn/block" || bad "unknown severity in the rules file"

echo "== C: clean corpus"
CLEAN=0; CHITS=0
for f in "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl "$FX"/clean/*.mdl; do
  CLEAN=$((CLEAN+1)); rc=$(scan "$f"); [ "$rc" = 0 ] || CHITS=$((CHITS+1))
done
[ "$CLEAN" -ge 10 ] && [ "$CHITS" = 0 ] && ok "StyleGallery + review cases: $CLEAN files, 0 hits" \
  || bad "clean corpus: $CLEAN files, $CHITS with hits ($(cat "$WORK/out" | head -1))"

echo "== L: lexer"
cat > "$WORK/l1.mdl" <<'EOF'
-- grant Module.User on Module.Order (read *) where '[Assoc = ''[%CurrentUser/Module.OtherAssoc%]'']';
/* column colX (Attribute: "Assoc_A_B/Name", Caption: 'B')
   still a comment */
create or modify page Module.P (Title: 'a -- b', Layout: Atlas_Core.Atlas_Default) { }
EOF
rc=$(scan "$WORK/l1.mdl"); [ "$rc" = 0 ] && ok "patterns inside -- and /* */ comments are not scanned" || bad "comment scanned: $(cat "$WORK/out")"
cat > "$WORK/l2.mdl" <<'EOF'
dynamictext t (Caption: 'a -- b', ContentParams: [{1} = if IsUrgent then 'x' else 'y'])
EOF
rc=$(scan "$WORK/l2.mdl"); grep -q '^STOP-12 ' "$WORK/out" && ok "'--' inside a string literal does not end the line" || bad "string '--' cut the line (exit $rc)"
cat > "$WORK/l3.mdl" <<'EOF'
dynamictext t (
  Content: '{1} {2}',
  ContentParams: [
    {1} = CaseRef,
    {2} = toString($currentObject/CreditLimit)
  ]
)
EOF
rc=$(scan "$WORK/l3.mdl"); grep -q ':3 ' "$WORK/out" && ok "multi-line ContentParams is read whole, hit at its opening line" || bad "multi-line ContentParams: exit $rc $(cat "$WORK/out")"
cat > "$WORK/l4.mdl" <<'EOF'
datagrid dg (DataSource: database Module.E) {
  column colA (ShowContentAs: customContent, Caption: 'A')
  column colB (Caption: 'B') {
    container c (Visible: [IsOpen])
  }
}
EOF
rc=$(scan "$WORK/l4.mdl"); [ "$rc" = 0 ] && ok "a body-less customContent column does not capture the next column's body" || bad "pending customContent leaked: $(cat "$WORK/out")"
printf '%s\n' "dynamictext t (Content:'{1}', ContentParams: [{1} = Name], Visible: [IsActive])" > "$WORK/l5.mdl"
rc=$(scan "$WORK/l5.mdl"); [ "$rc" = 0 ] && ok "review: ContentParams [{1} = Name], Visible: [...] on one line is clean (list ends at its own ])" || bad "review case 1 flagged: $(cat "$WORK/out")"
printf '%s\n' "dynamictext t (Content: '{1}', ContentParams: [" "  {1} = Name" "], Visible: [IsActive])" > "$WORK/l6.mdl"
rc=$(scan "$WORK/l6.mdl"); [ "$rc" = 0 ] && ok "review: multi-line list closed by '], Visible: [...]' is clean" || bad "review case 2 flagged: $(cat "$WORK/out")"
cat > "$WORK/l7.mdl" <<'EOF'
datagrid dg (DataSource: database Module.E) {
  column colA (Caption: 'A')
  column colB (ShowContentAs: customContent, Caption: 'B')
}
container ctnFooter {
  container c (Visible: [IsOpen])
}
EOF
rc=$(scan "$WORK/l7.mdl"); [ "$rc" = 0 ] && ok "review: a body-less customContent LAST column is forgotten at the grid's }" || bad "last-column pending leaked: $(cat "$WORK/out")"
cat > "$WORK/l8.mdl" <<'EOF'
column colB (ShowContentAs: customContent, Caption: 'B') {
  dynamictext t (Content: 'visible: [never] is just text')
}
EOF
rc=$(scan "$WORK/l8.mdl"); [ "$rc" = 0 ] && ok "customcontent rules ignore text inside string literals" || bad "string literal matched STOP-1: $(cat "$WORK/out")"

echo "== U: usage"
[ "$(scan)" = 2 ] && ok "no script: exit 2" || bad "no script did not exit 2"
[ "$(scan "$WORK/nope.mdl")" = 2 ] && ok "unreadable script: exit 2" || bad "missing script did not exit 2"
[ "$(scan --bogus "$FX/STOP-1.good.mdl")" = 2 ] && ok "unknown flag: exit 2" || bad "unknown flag did not exit 2"
[ "$(scan "$FX/STOP-1.good.mdl" -p "$WORK/nope.mpr")" = 2 ] && ok "-p with no model: exit 2" || bad "-p missing model did not exit 2"
: > "$WORK/App.mpr"
[ "$(scan "$FX/STOP-26.bad.mdl" -p "$WORK/App.mpr")" = 3 ] && ok "-p with a model: scans as usual" || bad "-p broke the scan"

echo "== S: speed"
: > "$WORK/big.mdl"
while [ "$(wc -l < "$WORK/big.mdl")" -lt 2000 ]; do cat "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl >> "$WORK/big.mdl"; done
cat "$FX/STOP-16.bad.mdl" >> "$WORK/big.mdl"
LINES=$(wc -l < "$WORK/big.mdl" | tr -d ' ')
TIMEFORMAT=%R
T=$( { time bash "$SCAN" "$WORK/big.mdl" >/dev/null 2>&1; } 2>&1 )
awk -v t="$T" 'BEGIN { exit !(t + 0 < 1.0) }' && ok "$LINES lines scanned in ${T}s (< 1 s)" || bad "$LINES lines took ${T}s"

echo "== E: exec.sh integration"
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
cp "$FX/STOP-26.bad.mdl" "$P/mdlsource/bad.mdl"
cp "$FX/STOP-26.good.mdl" "$P/mdlsource/good.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/_common.sh"
cp "$EXEC_SH" "$P/bin/exec.sh"
cp "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/restore-mpr.sh"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"; mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) exit 0 ;; exec) echo "fake mxcli exec"; echo x >> "$(dirname "$0")/.exec-ran" ;; esac
exit 0
MXCLI
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
chmod +x "$P/bin/"*.sh "$P/mxcli" "$WORK/mxbuild"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
xrun() {  # xrun <label> <script> [VAR=value ...]
  local label="$1" s="$2"; shift 2
  ( cd "$P" && env MXTK_ROOT="$TOOLKIT" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
      MXBUILD_PATH="$WORK/mxbuild" "$@" ./bin/exec.sh "$s" ) >"$WORK/x.$label" 2>&1
  echo $?
}
snaps() { ls -d "$P/.mpr-snapshots"/[0-9]*/ 2>/dev/null | wc -l | tr -d ' '; }

# warn path: the shipped rules (all warn) print, note and go on
rm -f "$P/.exec-ran"
rc=$(xrun warn mdlsource/bad.mdl)
[ "$rc" = 0 ] && [ -f "$P/.exec-ran" ] && grep -q '^⚠ STOP-26 mdlsource/bad.mdl:6 .*\[warn\]$' "$WORK/x.warn" \
  && ok "warn rule: the hit is printed as a warning and the exec goes on" || bad "warn: exit $rc — $(grep -i stop "$WORK/x.warn" | head -2)"
grep -q 'scan warn: STOP-26' "$LOG" 2>/dev/null && ok "BUILD-LOG row notes the warning" || bad "no 'scan warn' note in BUILD-LOG"
! grep -q 'blocked.*STOP-row' "$LOG" 2>/dev/null && ok "a warn hit writes no blocked row" || bad "a warn hit was logged as blocked"
# block path: kept and exercised through a test-only rules file with STOP-26 as block
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "STOP-26" { $3 = "block" } { print }' "$RULES" > "$WORK/block-rules.tsv"
B="MDL_SCAN_RULES=$WORK/block-rules.tsv"
rm -f "$P/.exec-ran"; ( cd "$P" && git -c user.email=t@t -c user.name=t commit -qam reset ) >/dev/null 2>&1
S0=$(snaps)
rc=$(xrun hit mdlsource/bad.mdl "$B")
[ "$rc" = 1 ] && grep -q '^STOP-26 mdlsource/bad.mdl:6 ' "$WORK/x.hit" && ok "a hit refuses the exec (exit 1) and prints the scan line" \
  || bad "hit: exit $rc — $(tail -3 "$WORK/x.hit")"
[ "$(snaps)" = "$S0" ] && [ ! -f "$P/.exec-ran" ] && [ ! -f "$P/.mpr-snapshots/.exec.lock" ] \
  && ok "refused before the snapshot, the lock and mxcli exec" || bad "something ran before the refusal (snapshots $S0 -> $(snaps))"
grep -q '🚫 blocked.*STOP-row scan: 1 blocking hit(s), STOP-26' "$LOG" 2>/dev/null && ok "BUILD-LOG row: blocked, names STOP-26" || bad "no blocked BUILD-LOG row"
rc=$(xrun force mdlsource/bad.mdl "$B" FORCE_EXEC=1 SKIP_CHECK=1)
[ "$rc" = 1 ] && [ ! -f "$P/.exec-ran" ] && ok "FORCE_EXEC=1 SKIP_CHECK=1 do not skip the scan" || bad "FORCE_EXEC/SKIP_CHECK bypassed the scan (exit $rc)"
rc=$(xrun one mdlsource/bad.mdl "$B" MXTK_SCAN_OVERRIDE=1)
[ "$rc" = 1 ] && [ ! -f "$P/.exec-ran" ] && ok "MXTK_SCAN_OVERRIDE=1 (no reason) does not override" || bad "a bare override went through (exit $rc)"
rc=$(xrun ovr mdlsource/bad.mdl "$B" "MXTK_SCAN_OVERRIDE=user approved | ticket 12")
[ "$rc" = 0 ] && [ -f "$P/.exec-ran" ] && grep -q 'STOP-row scan OVERRIDDEN' "$WORK/x.ovr" \
  && ok "MXTK_SCAN_OVERRIDE=\"<reason>\" runs the exec, with a warning" || bad "override: exit $rc — $(tail -3 "$WORK/x.ovr")"
grep -q 'scan overridden (STOP-26): user approved / ticket 12' "$LOG" && ok "BUILD-LOG row carries the override reason (| escaped)" || bad "override reason not in BUILD-LOG"
rm -f "$P/.exec-ran"; ( cd "$P" && git checkout -q -- . 2>/dev/null; git -c user.email=t@t -c user.name=t commit -qam reset ) >/dev/null 2>&1
rc=$(xrun clean mdlsource/good.mdl)
[ "$rc" = 0 ] && [ -f "$P/.exec-ran" ] && ! grep -q '^STOP-' "$WORK/x.clean" && ok "a clean script goes through" || bad "clean: exit $rc — $(tail -3 "$WORK/x.clean")"
rm -f "$P/.exec-ran"
rc=$( ( cd "$P" && env -u MXTK_ROOT SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MXBUILD_PATH="$WORK/mxbuild" \
        ./bin/exec.sh mdlsource/good.mdl ) >"$WORK/x.noscan" 2>&1; echo $? )
grep -q 'STOP-row scan skipped' "$WORK/x.noscan" && [ "$rc" = 0 ] && ok "no toolkit found: one warning, the exec goes on" || bad "no-toolkit: exit $rc — $(grep -i scan "$WORK/x.noscan")"
rm -f "$P/.exec-ran"
rc=$(xrun broken mdlsource/bad.mdl MDL_SCAN_RULES="$WORK/no-rules.tsv")
grep -q 'STOP-row scan could not run (exit 2)' "$WORK/x.broken" && [ "$rc" = 0 ] && ok "scan error (exit 2): one warning, the exec goes on" || bad "scan error: exit $rc — $(grep -i scan "$WORK/x.broken")"

echo
echo "mdl-scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
