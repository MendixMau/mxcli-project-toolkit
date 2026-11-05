#!/bin/bash
# test-metrics-ledger.sh — the per-exec metrics ledger and its reader.
#
# Golden input: tests/wave2/fixtures/mxcli-report-0.26.0.json is a redacted verbatim capture of
# `mxcli report --format json` from mxcli 0.26.0 on a 21-module Mendix 11.12 model (violations
# and topActions stripped, project name neutralised; scores, categories and summary as emitted).
# A fake ./mxcli serves it, with the real binary's banner on stderr, so the parser is proven
# against the shape the field produces: 7 categories ("Other" included), integer category
# scores, float overall, JSON from byte 0.
#
# Covers: score mode (writes report-last.json, strips violations, exit 3 without mxcli);
# exec mode (header once, 19 columns, result classification, lint_total only when lint ran,
# score columns only when --scored 1); the reader's summary, --runs, --score, --since; and
# that exec.sh is actually wired (every log_build row records, score taken in log_applied).
# Score cadence (2026-11-05): take_score, extracted from exec.sh, does NOT score by default; the
# opt-in (`Score: every exec` in PROJECT.md, MXTK_SCORE=exec) restores it; `record --module`
# (what module-close.sh calls) appends a module-close row carrying the score, which the reader
# counts as a score point and never as an exec.
#
# Usage: bash test-metrics-ledger.sh [path-to-metrics-ledger.sh]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/metrics-ledger.sh}"
TREND="$(dirname "$SUBJECT")/metrics-trend.sh"
EXEC="$(dirname "$SUBJECT")/exec.sh"
GOLD="$TOOLKIT/tests/wave2/fixtures/mxcli-report-0.26.0.json"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mled.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude/loop"
cp "$SUBJECT" "$P/bin/metrics-ledger.sh"; cp "$TREND" "$P/bin/metrics-trend.sh"
: > "$P/Example.mpr"
L="$P/.claude/loop/metrics-ledger.tsv"

# --- score: no mxcli → exit 3, nothing written ---------------------------------------------
bash "$P/bin/metrics-ledger.sh" score >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && ok "score without ./mxcli exits 3" || bad "score without ./mxcli exited $rc"
[ ! -f "$P/.claude/loop/report-last.json" ] && ok "no report-last.json written" || bad "report-last.json written without mxcli"

# --- fake mxcli: golden JSON on stdout, banner on stderr (as 0.26.0 does) ------------------
cat > "$P/mxcli" <<FAKE
#!/bin/bash
echo "WARNING: vibe-coded banner" >&2
echo "Connected to Example.mpr" >&2
[ "\$1" = report ] || exit 1
cat "$GOLD"
FAKE
chmod +x "$P/mxcli"
out=$(bash "$P/bin/metrics-ledger.sh" score 2>&1); rc=$?
[ "$rc" = 0 ] && ok "score with fake mxcli exits 0" || bad "score exited $rc: $out"
case "$out" in *"score=41.3"*"categories=7"*) ok "score prints overall and category count" ;; *) bad "score output: $out" ;; esac
[ -f "$P/.claude/loop/report-last.json" ] && ok "report-last.json written" || bad "report-last.json missing"
grep -q '"violations"' "$P/.claude/loop/report-last.json" && bad "violations not stripped" || ok "violations stripped from report-last.json"

# --- exec: bad invocation -------------------------------------------------------------------
bash "$P/bin/metrics-ledger.sh" exec --script a.mdl >/dev/null 2>&1; [ $? = 2 ] && ok "exec without required args exits 2" || bad "exec accepted missing args"
[ ! -f "$L" ] && ok "no ledger on bad invocation" || bad "ledger written on bad invocation"

# --- exec rows ------------------------------------------------------------------------------
printf '{"timestamp":"x","verdict":"PASS","total":302,"rule_count":9,"counts":{}}\n' > "$P/.claude/loop/lint-last.json"
bash "$P/bin/metrics-ledger.sh" exec --script 010-domain.mdl --gate pass --result "✅ applied" --elapsed 42 --mxbuild-errors 0 --lint-rc 0 --restored 0 --scored 1 \
  && ok "applied row appended" || bad "applied row failed"
bash "$P/bin/metrics-ledger.sh" exec --script 020-flows.mdl --gate fail --result "❌ gate failed" --elapsed 61 --mxbuild-errors 3 --restored 1 --scored 0 \
  && ok "gate-failed row appended" || bad "gate-failed row failed"
bash "$P/bin/metrics-ledger.sh" exec --script 020-flows.mdl --gate pass --result "⚠️ applied, LINT ROSE" --elapsed 55 --mxbuild-errors 0 --lint-rc 1 --scored 1 \
  && ok "lint-rose row appended" || bad "lint-rose row failed"
bash "$P/bin/metrics-ledger.sh" exec --script 030-pages.mdl --gate not-run --result "🚫 blocked" --elapsed 2 >/dev/null 2>&1 \
  && ok "blocked row appended" || bad "blocked row failed"

[ "$(grep -c '^ts	script	gate' "$L")" = 1 ] && ok "exactly one header" || bad "header count $(grep -c '^ts' "$L")"
[ "$(wc -l < "$L" | tr -d ' ')" = 5 ] && ok "4 rows + header" || bad "line count $(wc -l < "$L")"
[ "$(awk -F'\t' '{print NF}' "$L" | sort -u | tr '\n' ' ')" = "19 " ] && ok "every line has 19 columns" || bad "column counts: $(awk -F'\t' '{print NF}' "$L" | sort -u | tr '\n' ' ')"
r1=$(sed -n 2p "$L"); r2=$(sed -n 3p "$L"); r3=$(sed -n 4p "$L"); r4=$(sed -n 5p "$L")
f() { printf '%s' "$1" | cut -f"$2"; }
[ "$(f "$r1" 4)" = applied ]           && ok "✅ applied → applied" || bad "row1 result $(f "$r1" 4)"
[ "$(f "$r2" 4)" = gate-failed ]       && ok "❌ gate failed → gate-failed" || bad "row2 result $(f "$r2" 4)"
[ "$(f "$r3" 4)" = applied-lint-rose ] && ok "LINT ROSE → applied-lint-rose" || bad "row3 result $(f "$r3" 4)"
[ "$(f "$r4" 4)" = blocked ]           && ok "🚫 blocked → blocked" || bad "row4 result $(f "$r4" 4)"
[ "$(f "$r1" 8)" = 302 ]   && ok "lint_total read from lint-last.json when lint ran" || bad "row1 lint_total '$(f "$r1" 8)'"
[ -z "$(f "$r2" 8)" ]      && ok "lint_total empty when lint did not run (never 0)" || bad "row2 lint_total '$(f "$r2" 8)'"
[ "$(f "$r1" 10)" = 41.3 ] && ok "score column from report-last.json" || bad "row1 score '$(f "$r1" 10)'"
[ "$(f "$r1" 13)" = 0 ] && [ "$(f "$r1" 14)" = 94 ] && [ "$(f "$r1" 17)" = 0 ] && ok "architecture 0, performance 94, other 0 (7th category kept)" || bad "category columns: $(f "$r1" 11-17)"
[ "$(f "$r1" 18)" = 302 ]  && ok "violations column" || bad "violations '$(f "$r1" 18)'"
[ -z "$(f "$r2" 10)" ]     && ok "score empty on unscored row" || bad "row2 score '$(f "$r2" 10)'"
[ "$(f "$r2" 9)" = 1 ]     && ok "restored flag" || bad "row2 restored '$(f "$r2" 9)'"

# --- reader ---------------------------------------------------------------------------------
s=$(bash "$P/bin/metrics-trend.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "trend summary exits 0" || bad "trend exited $rc: $s"
case "$s" in *"4 execs"*) ok "counts 4 execs" ;; *) bad "exec count: $s" ;; esac
case "$s" in *"applied, clean gate+lint   1 (25%)"*) ok "clean share" ;; *) bad "clean share line missing" ;; esac
case "$s" in *"gate failed / rolled back  1 (25%)"*) ok "gate-failed share" ;; *) bad "gate-failed line missing" ;; esac
case "$s" in *"snapshot restores          1"*) ok "restore count" ;; *) bad "restore line missing" ;; esac
case "$s" in *"overall"*"41.3"*) ok "score line" ;; *) bad "score line missing: $s" ;; esac
case "$s" in *"architecture"*"0 →"*) ok "category line" ;; *) bad "category line missing" ;; esac
case "$s" in *"010-domain"*) bad "summary leaks script names" ;; *) ok "summary carries no script names" ;; esac
r=$(bash "$P/bin/metrics-trend.sh" --runs); [ "$(printf '%s\n' "$r" | wc -l | tr -d ' ')" = 5 ] && ok "--runs prints 4 rows + header" || bad "--runs: $r"
sc=$(bash "$P/bin/metrics-trend.sh" --score); [ "$(printf '%s\n' "$sc" | wc -l | tr -d ' ')" = 3 ] && ok "--score prints 2 scored rows + header" || bad "--score: $sc"
z=$(bash "$P/bin/metrics-trend.sh" --since 2999-01-01); case "$z" in *"no rows since"*) ok "--since filters" ;; *) bad "--since: $z" ;; esac
mkdir -p "$WORK/empty/bin" "$WORK/empty/.claude"; cp "$TREND" "$WORK/empty/bin/"
bash "$WORK/empty/bin/metrics-trend.sh" >/dev/null 2>&1; [ $? = 2 ] && ok "no ledger → exit 2" || bad "no-ledger exit"

# --- record: the module-close row ------------------------------------------------------------
out=$(bash "$P/bin/metrics-ledger.sh" record --module Billing 2>&1); rc=$?
[ "$rc" = 0 ] && ok "record --module exits 0 with mxcli" || bad "record exited $rc: $out"
case "$(printf '%s\n' "$out" | tail -1)" in *"score=41.3"*) ok "record prints the score line last (module-close.sh keeps tail -1)" ;; *) bad "record last line: $out" ;; esac
r5=$(tail -1 "$L")
[ "$(f "$r5" 2)" = "module-close: Billing" ] && [ "$(f "$r5" 4)" = module-close ] && [ "$(f "$r5" 10)" = 41.3 ] \
  && ok "record row: script 'module-close: Billing', result module-close, score 41.3" || bad "record row: $r5"
[ -z "$(f "$r5" 5)" ] && [ -z "$(f "$r5" 8)" ] && ok "record row: elapsed and lint_total empty (not an exec)" || bad "record row elapsed/lint: $r5"
[ "$(awk -F'\t' '{print NF}' "$L" | sort -u | tr '\n' ' ')" = "19 " ] && ok "record row keeps 19 columns" || bad "record columns"
mv "$P/mxcli" "$P/mxcli.off"
out=$(bash "$P/bin/metrics-ledger.sh" record 2>&1); rc=$?
r6=$(tail -1 "$L")
{ [ "$rc" = 3 ] && [ "$(f "$r6" 4)" = score-only ] && [ -z "$(f "$r6" 10)" ]; } \
  && ok "record without mxcli: exit 3, score-only row lands with empty score" || bad "record no mxcli rc=$rc: $r6"
mv "$P/mxcli.off" "$P/mxcli"
s=$(bash "$P/bin/metrics-trend.sh" 2>&1)
case "$s" in *"4 execs"*) ok "trend: record rows are not counted as execs" ;; *) bad "trend exec count with record rows: $s" ;; esac
case "$s" in *"3 points: 2 at exec, 1 at module close"*) ok "trend: score points labelled by where they were taken" ;; *) bad "score label: $s" ;; esac
case "$s" in *Billing*) bad "summary leaks the module name" ;; *) ok "summary carries no module name" ;; esac
case "$s" in *"blocked / refused          1 (25%)"*) ok "trend: shares still over 4 execs" ;; *) bad "shares: $s" ;; esac
sc=$(bash "$P/bin/metrics-trend.sh" --score)
{ [ "$(printf '%s\n' "$sc" | wc -l | tr -d ' ')" = 4 ] && printf '%s\n' "$sc" | tail -1 | grep -q 'module close$'; } \
  && ok "--score: 3 points, last one taken at module close" || bad "--score with record: $sc"

# --- take_score cadence (extracted from exec.sh) ---------------------------------------------
TS="$WORK/take_score.sh"
sed -n '/^_first_match() {/,/^}/p; /^take_score() {/,/^}/p' "$EXEC" > "$TS"
SP="$WORK/sproj"; mkdir -p "$SP/bin"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\necho "score=50 categories=7 violations=1"\n' "$SP" > "$SP/bin/metrics-ledger.sh"; chmod +x "$SP/bin/metrics-ledger.sh"
ts_run() { : > "$SP/calls"; (cd "$SP" && env "$@" bash -c "_NL=\$'\n'; PROJECT_ROOT='$SP'; SCORED=0; . '$TS'; take_score >/dev/null; echo SCORED=\$SCORED") 2>&1; }
o=$(ts_run MXTK_SCORE= MXTK_NO_SCORE=)
{ [ "$o" = SCORED=0 ] && [ ! -s "$SP/calls" ]; } && ok "exec does not score by default (no PROJECT.md line)" || bad "default scored: $o $(cat "$SP/calls")"
printf '# P\n\n- **Score:** every exec\n' > "$SP/PROJECT.md"
o=$(ts_run MXTK_SCORE= MXTK_NO_SCORE=)
{ [ "$o" = SCORED=1 ] && grep -q '^score$' "$SP/calls"; } && ok "PROJECT.md 'Score: every exec' restores per-exec scoring" || bad "opt-in: $o"
o=$(ts_run MXTK_SCORE=module MXTK_NO_SCORE=)
[ "$o" = SCORED=0 ] && ok "MXTK_SCORE=module wins over the PROJECT.md opt-in" || bad "env module: $o"
o=$(ts_run MXTK_SCORE= MXTK_NO_SCORE=1)
[ "$o" = SCORED=0 ] && ok "MXTK_NO_SCORE=1 skips even with the opt-in" || bad "no-score: $o"
rm -f "$SP/PROJECT.md"; o=$(ts_run MXTK_SCORE=exec MXTK_NO_SCORE=)
[ "$o" = SCORED=1 ] && ok "MXTK_SCORE=exec restores per-exec scoring" || bad "env exec: $o"

# --- exec.sh wiring ---------------------------------------------------------------------------
grep -q 'record_metrics "\$1"' "$EXEC" && ok "exec.sh log_build records a ledger row" || bad "exec.sh log_build does not call record_metrics"
grep -q '^  take_score$' "$EXEC" && ok "exec.sh log_applied takes the score" || bad "exec.sh does not call take_score"
grep -q 'MXTK_NO_SCORE' "$EXEC" && ok "MXTK_NO_SCORE opt-out present" || bad "no MXTK_NO_SCORE"
grep -q 'metrics-ledger.sh metrics-trend.sh' "$TOOLKIT/bin/lib/install-manifest.sh" && ok "both scripts in the install manifest" || bad "manifest missing the scripts"

echo; echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
