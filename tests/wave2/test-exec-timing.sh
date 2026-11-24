#!/usr/bin/env bash
# test-exec-timing.sh - the metrics ledger carries platform + per-step seconds, and a failed exec prints its time (#841).
#
# usage: bash tests/wave2/test-exec-timing.sh [path-to-exec.sh]
#        (metrics-ledger.sh, metrics-trend.sh, progress-report.py, _common.sh are read from the same directory)
#
# WHY. "The harness is slow" could not be told from "this machine is slow": a ledger row had the
# total seconds and nothing else, the per-step seconds lived only as prose in BUILD-LOG, and a
# failed or rolled-back exec printed no time at all.
#
# Golden input (captured, not written): fixtures/exec-timing/
#   ledger-old-19col.captured.tsv   the ledger of a Mendix 11.8 probe app as exec.sh wrote it before this change
#   ledger-new-21col.captured.tsv   the ledger of a Mendix 11.12.0 probe app, six rows from real execs,
#                                   written by this change (a verified apply, refusals, an unverified apply)
#
#   A  writer: 21 columns; platform is a label; step_s only from exec rows and only if well formed
#   B  mixed ledger: an old 19-column file gets the two header names on the first new row, its old
#      rows stay byte for byte, and a customised header is left alone
#   C  every reader (metrics-trend.sh x3 modes, progress-report.py ledger_runs / load_ledgers) over the
#      old, new and mixed ledgers: exit 0, the right row count, and the same output as the new ledger
#      with its two new columns cut off
#   D  exec.sh end to end on a stub project (a --patch whose gate crashes: the costliest path):
#      the failing exec prints "elapsed: Ns · steps: ..." and the slow warning, the ledger row carries
#      step_s, the MXTK-RESULT line and exit code are what they were, and the success path prints the
#      line exactly once
#   E  step_done splits the theme seconds out of a step; mxtk_theme_check adds its seconds
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
SUBDIR="$(dirname "$SUBJECT")"
FIX="$TOOLKIT/tests/wave2/fixtures/exec-timing"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-timing.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"
. "$TOOLKIT/bin/lib/portable.sh"; require_py

mkdir -p "$WORK/p/bin" "$WORK/p/.claude/loop"
cp "$SUBDIR/metrics-ledger.sh" "$SUBDIR/metrics-trend.sh" "$SUBDIR/_common.sh" "$WORK/p/bin/"
L="$WORK/p/.claude/loop/metrics-ledger.tsv"
row() { MXTK_STEP_KV="${STEPS-}" bash "$WORK/p/bin/metrics-ledger.sh" exec --script "${1:-a.mdl}" --gate pass --result "✅ applied" --elapsed "${2:-7}" >/dev/null 2>&1; }
col() { awk -F'\t' -v n="$2" 'NR>1{print $n}' "$1" | tail -n 1; }

# ---- A: writer ------------------------------------------------------------------------------
STEPS="lint=1;check=3;exec=14;gate=2" row a.mdl
[ "$(head -n 1 "$L" | awk -F'\t' '{print NF" "$(NF-1)" "$NF}')" = "21 platform step_s" ] && ok "A: fresh ledger header is 21 columns ending platform, step_s" || bad "A: header" "$(head -n 1 "$L")"
[ "$(awk -F'\t' '{print NF}' "$L" | sort -u | tr '\n' ' ')" = "21 " ] && ok "A: header and row are 21 columns" || bad "A: column counts"
[ "$(col "$L" 21)" = "lint=1;check=3;exec=14;gate=2" ] && ok "A: step_s is the compact field as given" || bad "A: step_s" "$(col "$L" 21)"
case "$(col "$L" 20)" in macos|linux|windows-gitbash|wsl) ok "A: platform is one of the four labels ($(col "$L" 20))" ;; *) bad "A: platform label" "$(col "$L" 20)" ;; esac
grep -qE "$(hostname 2>/dev/null || echo __nohost__)|${USER:-__nouser__}|[/\\]" "$L" 2>/dev/null && bad "A: ledger holds a host, user or a path separator" || ok "A: no hostname, user or path separator in the ledger"
STEPS="evil step/with paths" row b.mdl
[ -z "$(col "$L" 21)" ] && ok "A: a malformed steps value is dropped, not stored" || bad "A: malformed steps stored" "$(col "$L" 21)"
STEPS="" row c.mdl
[ -z "$(col "$L" 21)" ] && [ "$(awk -F'\t' '{print NF}' "$L" | tail -n 1)" = 21 ] && ok "A: no steps -> empty step_s, still 21 columns" || bad "A: empty steps"
printf '{"overallScore":50,"categories":[],"summary":{"total":0}}' > "$WORK/report.json"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$WORK/report.json" > "$WORK/p/mxcli"; chmod +x "$WORK/p/mxcli"; : > "$WORK/p/X.mpr"
MXTK_STEP_KV="gate=9" bash "$WORK/p/bin/metrics-ledger.sh" record --module M >/dev/null 2>&1
[ "$(col "$L" 4)" = "module-close" ] && [ -z "$(col "$L" 21)" ] && [ -n "$(col "$L" 20)" ] && ok "A: module-close row has platform, never step_s (even with MXTK_STEP_KV in the env)" || bad "A: module-close row" "$(tail -n 1 "$L")"
# platform labels, through the MXTK_PLATFORM override (OSTYPE cannot be set from outside)
plat() { mkdir -p "$WORK/pl/bin" "$WORK/pl/.claude/loop"; cp "$SUBDIR/metrics-ledger.sh" "$SUBDIR/_common.sh" "$WORK/pl/bin/"; rm -f "$WORK/pl/.claude/loop/metrics-ledger.tsv"
  ( unset WSL_DISTRO_NAME WSL_INTEROP; env MXTK_PLATFORM="$1" "${2:-X=1}" bash "$WORK/pl/bin/metrics-ledger.sh" exec --script a --gate pass --result applied --elapsed 1 >/dev/null 2>&1 )
  awk -F'\t' 'NR==2{print $20}' "$WORK/pl/.claude/loop/metrics-ledger.tsv"; }
[ "$(plat macos)" = macos ] && ok "A: macos -> macos" || bad "A: macos label" "$(plat macos)"
[ "$(plat windows)" = windows-gitbash ] && ok "A: windows -> windows-gitbash" || bad "A: windows label" "$(plat windows)"
[ "$(plat linux WSL_DISTRO_NAME=Ubuntu)" = wsl ] && ok "A: linux with WSL_DISTRO_NAME -> wsl" || bad "A: wsl label" "$(plat linux WSL_DISTRO_NAME=Ubuntu)"
# an unsynced _common.sh (no mxtk_platform) falls back to $OSTYPE, and never fails the row
rm -f "$WORK/pl/bin/_common.sh" "$WORK/pl/.claude/loop/metrics-ledger.tsv"
( cd "$WORK/pl" && bash bin/metrics-ledger.sh exec --script a --gate pass --result applied --elapsed 1 >/dev/null 2>&1 )
[ -n "$(awk -F'\t' 'NR==2{print $20}' "$WORK/pl/.claude/loop/metrics-ledger.tsv")" ] && ok "A: no _common.sh -> OSTYPE fallback still labels the row" || bad "A: fallback label"

# ---- B: mixed ledger -------------------------------------------------------------------------
mkdir -p "$WORK/m/bin" "$WORK/m/.claude/loop"; cp "$WORK/p/bin/"* "$WORK/m/bin/"
M="$WORK/m/.claude/loop/metrics-ledger.tsv"; cp "$FIX/ledger-old-19col.captured.tsv" "$M"
old_n=$(grep -c '' "$M")
[ "$(head -n 1 "$M" | awk -F'\t' '{print NF}')" = 19 ] && ok "B: the captured old ledger is 19 columns" || bad "B: old ledger shape"
( cd "$WORK/m" && MXTK_STEP_KV="exec=4;gate=9" bash bin/metrics-ledger.sh exec --script n.mdl --gate pass --result applied --elapsed 13 >/dev/null 2>&1 )
[ "$(head -n 1 "$M" | awk -F'\t' '{print NF" "$NF}')" = "21 step_s" ] && ok "B: first new-format row upgrades the header to 21 names" || bad "B: header not upgraded" "$(head -n 1 "$M")"
[ "$(grep -c '' "$M")" = $((old_n + 1)) ] && ok "B: exactly one row added" || bad "B: row count" "$(grep -c '' "$M")"
if [ "$(sed -n "2,${old_n}p" "$M" | cksum)" = "$(sed -n "2,${old_n}p" "$FIX/ledger-old-19col.captured.tsv" | cksum)" ]; then ok "B: the $((old_n - 1)) old rows are byte for byte unchanged"; else bad "B: old rows changed"; fi
[ "$(awk -F'\t' 'NR==2{print NF}' "$M")" = 19 ] && [ "$(tail -n 1 "$M" | awk -F'\t' '{print NF}')" = 21 ] && ok "B: old rows stay 19 fields, the new row is 21 (mixed widths, documented)" || bad "B: widths"
( cd "$WORK/m" && MXTK_STEP_KV="exec=1" bash bin/metrics-ledger.sh exec --script n2.mdl --gate pass --result applied --elapsed 2 >/dev/null 2>&1 )
[ "$(head -n 1 "$M" | awk -F'\t' '{print NF}')" = 21 ] && [ "$(grep -c '^ts	' "$M")" = 1 ] && ok "B: a second append leaves the header alone" || bad "B: header touched twice"
mkdir -p "$WORK/c/bin" "$WORK/c/.claude/loop"; cp "$WORK/p/bin/"* "$WORK/c/bin/"
printf 'ts\tscript\tcustom\n2026-01-01T00:00:00Z\tx\ty\n' > "$WORK/c/.claude/loop/metrics-ledger.tsv"
( cd "$WORK/c" && bash bin/metrics-ledger.sh exec --script n.mdl --gate pass --result applied --elapsed 1 >/dev/null 2>&1 )
[ "$(head -n 1 "$WORK/c/.claude/loop/metrics-ledger.tsv")" = "$(printf 'ts\tscript\tcustom')" ] && ok "B: a header that is not the old shape is never rewritten" || bad "B: custom header rewritten"
[ -z "$(ls "$WORK/m/.claude/loop" | grep '\.tmp$')" ] && ok "B: no temp file left behind" || bad "B: temp left"

# ---- C: readers ------------------------------------------------------------------------------
mkdir -p "$WORK/r"; cp "$FIX/ledger-old-19col.captured.tsv" "$WORK/r/old.tsv"; cp "$FIX/ledger-new-21col.captured.tsv" "$WORK/r/new.tsv"
cut -f1-19 "$FIX/ledger-new-21col.captured.tsv" > "$WORK/r/new-cut.tsv"; cp "$M" "$WORK/r/mixed.tsv"
trend() { MXTK_METRICS_LEDGER="$1" MXTK_BUILD_LOG="$WORK/none.md" bash "$WORK/p/bin/metrics-trend.sh" "${@:2}" 2>&1; }
for f in old new mixed new-cut; do
  for mode in "" --runs --score; do
    out="$(trend "$WORK/r/$f.tsv" $mode)"; rc=$?
    case "$out" in *Traceback*) bad "C: metrics-trend ${mode:-summary} on $f" "$(printf '%s' "$out" | tail -n 2)" ;; *) [ "$rc" = 0 ] && ok "C: metrics-trend ${mode:-summary} reads the $f ledger" || bad "C: metrics-trend $mode on $f rc=$rc" ;; esac
  done
done
for mode in "" --runs --score; do
  [ "$(trend "$WORK/r/new.tsv" $mode)" = "$(trend "$WORK/r/new-cut.tsv" $mode)" ] && ok "C: metrics-trend ${mode:-summary}: the two new columns change nothing" || bad "C: metrics-trend ${mode:-summary} differs with the new columns"
done
[ "$(trend "$WORK/r/old.tsv" --runs | grep -c '')" = "$(grep -c '' "$WORK/r/old.tsv")" ] && ok "C: --runs on the old ledger lists every row" || bad "C: --runs old row count"
[ "$(trend "$WORK/r/mixed.tsv" --runs | grep -c '')" = "$(grep -c '' "$WORK/r/mixed.tsv")" ] && ok "C: --runs on the mixed ledger lists every row (old and new)" || bad "C: --runs mixed row count"
[ "$(trend "$WORK/r/mixed.tsv" --runs | head -n "$old_n" | cksum)" = "$(trend "$WORK/r/old.tsv" --runs | cksum)" ] && ok "C: mixed --runs starts with exactly the old ledger's --runs" || bad "C: mixed --runs prefix differs"
pr() {  # ledger -> "ledger_runs-count exec_s exec_n"
  mkdir -p "$WORK/pr/.claude/loop"; cp "$1" "$WORK/pr/.claude/loop/metrics-ledger.tsv"
  "$PY" -I - "$SUBDIR/progress-report.py" "$WORK/pr" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d = m.load_ledgers(sys.argv[2]) or {}
print(len(m.ledger_runs(sys.argv[2])), d.get("exec_s"), d.get("exec_n"))
PYEOF
}
for f in old new mixed new-cut; do
  r="$(pr "$WORK/r/$f.tsv" 2>&1)"
  case "$r" in [0-9]*" "*) ok "C: progress-report.py reads the $f ledger ($r)" ;; *) bad "C: progress-report.py on $f" "$(printf '%s' "$r" | tail -n 2)" ;; esac
done
[ "$(pr "$WORK/r/new.tsv")" = "$(pr "$WORK/r/new-cut.tsv")" ] && ok "C: progress-report.py: the two new columns change nothing" || bad "C: progress-report.py differs with the new columns"
[ "$(pr "$WORK/r/old.tsv" | cut -d' ' -f1)" = 15 ] && ok "C: progress-report.py counts the 15 old rows" || bad "C: old count" "$(pr "$WORK/r/old.tsv")"
[ "$(pr "$WORK/r/mixed.tsv" | cut -d' ' -f1)" = 17 ] && ok "C: progress-report.py counts old + 2 new rows in the mixed file" || bad "C: mixed count" "$(pr "$WORK/r/mixed.tsv")"
# harvest-learnings.sh only counts the ledger's lines and hands it to metrics-trend.sh (covered above)

# ---- D: exec.sh end to end -------------------------------------------------------------------
Q="$WORK/patchproj"
mkdir -p "$Q/bin" "$Q/mprcontents" "$WORK/jdk/bin" "$WORK/tq"
printf 'not a real model\n' > "$Q/Fixture.mpr"; printf 'bson\n' > "$Q/mprcontents/a.mxunit"
cp "$SUBDIR/_common.sh" "$SUBDIR/restore-mpr.sh" "$SUBDIR/metrics-ledger.sh" "$Q/bin/"; cp "$SUBJECT" "$Q/bin/exec.sh"
cat > "$Q/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
printf '#!/usr/bin/env bash\necho "written by the patch" >> "$1"\nexit 0\n' > "$Q/patch.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$Q/mxcli"
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
if [ "${MXB_FAIL:-1}" = 1 ] && [ "$n" -ge 2 ]; then echo "Unhandled exception: loader died" >&2; exit 137; fi
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$Q/bin/"*.sh "$Q/patch.sh" "$Q/mxcli" "$WORK/mxbuild" "$WORK/jdk/bin/java"
( cd "$Q" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
runq() {  # extra env as args; sets RC, OUT
  rm -f "$WORK/mxb-n"; ( cd "$Q" && git checkout -q -- Fixture.mpr mprcontents 2>/dev/null; env TMPDIR="$WORK/tq" SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MXB_N="$WORK/mxb-n" \
    MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" "$@" ./bin/exec.sh --patch patch.sh ) >"$WORK/out.q" 2>&1
  RC=$?; OUT="$(cat "$WORK/out.q")"; }
runq MXTK_TIME_SHOW_MIN=0 MXTK_SLOW_S=-1
[ "$RC" = 1 ] && ok "D: failing exec: exit code is still 1" || bad "D: exit code" "$RC"
printf '%s\n' "$OUT" | grep -q '^MXTK-RESULT exec verdict=[a-z-]* applied=[a-z]* verified=[a-z]* lint_new=[a-z]* exit=1$' && ok "D: failing exec: MXTK-RESULT line has the same fields" || bad "D: MXTK-RESULT shape" "$(printf '%s\n' "$OUT" | grep MXTK-RESULT)"
printf '%s\n' "$OUT" | grep -qE '^  elapsed: [0-9]+s · steps: .*gate [0-9]+s' && ok "D: failing exec prints elapsed + steps (gate step included)" || bad "D: no elapsed/steps line on the failing exec" "$(printf '%s\n' "$OUT" | tail -n 4)"
printf '%s\n' "$OUT" | grep -q 'slower than a healthy run' && ok "D: failing exec prints the slow warning when over the threshold" || bad "D: no slow warning on the failing exec"
[ "$(printf '%s\n' "$OUT" | grep -c '^  elapsed: ')" = 1 ] && ok "D: the line is printed once" || bad "D: elapsed line count"
[ "$(printf '%s\n' "$OUT" | tail -n 1 | cut -c1-11)" != "MXTK-RESULT" ] && ok "D: MXTK-RESULT is not the last line" || bad "D: MXTK-RESULT last"
LQ="$Q/.claude/loop/metrics-ledger.tsv"
case "$(col "$LQ" 21)" in *gate=*) ok "D: the failing exec's ledger row carries step_s ($(col "$LQ" 21))" ;; *) bad "D: ledger step_s on the failing exec" "$(tail -n 1 "$LQ")" ;; esac
runq
printf '%s\n' "$OUT" | grep -q '^  elapsed: ' && bad "D: a fast failing exec printed a time line under the default 10 s threshold" || ok "D: under 10 s a failing exec prints no time line (default)"
runq MXB_FAIL=0 MXTK_TIME_SHOW_MIN=0
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^  elapsed: ')" = 1 ] && ok "D: success path: one elapsed line, exit 0" || bad "D: success path" "rc=$RC lines=$(printf '%s\n' "$OUT" | grep -c '^  elapsed: ')"
printf '%s\n' "$OUT" | grep -q '^  elapsed: [0-9]*s (check + snapshot + exec + mxbuild gate)$' && ok "D: success path text unchanged" || bad "D: success path text changed"

# ---- E: step_done / theme --------------------------------------------------------------------
if [ -n "${EPOCHSECONDS:-}" ]; then
  eval "$(sed -n '/^step_done() {/,/^}/p' "$SUBJECT")"
  _T0=$EPOCHSECONDS; _TLAST=$((EPOCHSECONDS - 10)); STEP_TIMES=""; STEP_KV=""; MXTK_THEME_SECS=3
  step_done gate
  [ "$STEP_TIMES" = "gate 7s theme 3s" ] && [ "$STEP_KV" = "gate=7;theme=3" ] && [ "$MXTK_THEME_SECS" = 0 ] && ok "E: step_done splits 3 theme seconds out of a 10 s mark" || bad "E: split" "$STEP_TIMES / $STEP_KV / $MXTK_THEME_SECS"
  _TLAST=$((EPOCHSECONDS - 2)); MXTK_THEME_SECS=9; STEP_TIMES=""; STEP_KV=""
  step_done baseline
  [ "$STEP_KV" = "baseline=0;theme=2" ] && ok "E: theme seconds never exceed the step (clamped)" || bad "E: clamp" "$STEP_KV"
  _TLAST=$EPOCHSECONDS; MXTK_THEME_SECS=0; STEP_TIMES=""; STEP_KV=""; step_done lint
  [ "$STEP_KV" = "lint=0" ] && ok "E: no theme time -> no theme entry" || bad "E: plain step" "$STEP_KV"
  if ( . "$SUBDIR/_common.sh"
       _mxtk_theme_check_run() { sleep 2; MXTK_THEME_STATE=fail; return 1; }
       MXTK_THEME_SECS=0; mxtk_theme_check; rc=$?
       [ "$rc" = 1 ] && [ "$MXTK_THEME_SECS" -ge 2 ] && [ "$MXTK_THEME_SECS" -le 4 ] && [ "$MXTK_THEME_STATE" = fail ] ); then
    ok "E: mxtk_theme_check keeps its return code and adds its seconds"
  else bad "E: mxtk_theme_check wrapper"; fi
else
  echo "  skip - E: no EPOCHSECONDS in this bash (3.2): the theme split is a no-op there, by design"
fi

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
