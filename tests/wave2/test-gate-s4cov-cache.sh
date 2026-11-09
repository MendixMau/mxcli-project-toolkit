#!/usr/bin/env bash
# Usage: bash test-gate-s4cov-cache.sh /path/to/gate-check.sh
#
# Fixture for the Stage-4 coverage cache (bin/lib/gate-cache.sh, "Stage-4 coverage cache"):
# gate-check re-ran coverage-preflight.sh per module ledger on every round (~25 s of a Stage 5+
# query, #686 speed audit). The cache reuses the verdict only while its inputs are unchanged by
# content, so it must never replay a stale PASS.
#   T1 — second run hits, and prints the same Stage 4 line as an uncached run.
#   T2 — a ledger edit that keeps the old mtime (touch -r) is a miss, and the gap FAILs.
#   T3 — a BRD edit that keeps the old mtime is a miss, and the new leaves FAIL as UNCLAIMED.
#   T4 — no .mxtk/ in .gitignore: nothing is written (the same rule as the closeout cache).
# Hit/miss is observed through MXTK_GATE_CACHE_TRACE=1 ("s4cov-cache: hit|miss" on stderr).
# Project files are synthetic (shape of test-bug03-gates.sh T21); no tool output is parsed.
set -uo pipefail
GATE="${1:?usage: test-gate-s4cov-cache.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/s4cov.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       got: %s\n' "$2"; }
export MXTK_NO_FETCH=1 MXTK_GATE_CACHE_TRACE=1

mkproj() {
  P="$WORK/$1"; mkdir -p "$P/architecture/modules/Purchasing" "$P/analysis/src/knowledge-base/brd"
  printf '.mxtk/\n' > "$P/.gitignore"
  printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n| 4 | Build plan approved | CONFIRMED | |\n' > "$P/PROJECT.md"
  printf '# brief\n' > "$P/architecture/modules/Purchasing/module-brief.md"
  printf '%s\n' '# Plan' '' \
    '| # | Kind | Step | Produces / Proves | Depends on | Skills | State |' '|---|---|---|---|---|---|---|' \
    '| 1 | `BRIEF` | Check `architecture/modules/Purchasing/module-brief.md` | Brief | — | none | not built |' \
    '| 2 | `BUILD` | 010-domain.mdl | domain | 1 | none | not built |' \
    '| 3 | `HARNESS` | `bin/verify-module.sh Purchasing` | close | 2 | none | not built |' \
    '| 4 | `RUN` | `gate-check.sh <project> 5` | gate | 3 | none | not built |' > "$P/architecture/build-plan.md"
  printf '{"id":"F001","modules":["Purchasing"],"useCases":[{"id":"UC1","title":"Submit"}]}\n' \
    > "$P/analysis/src/knowledge-base/brd/F001.brd.json"
  printf '%s\n' '# Coverage ledger' '' '| pointer | type | title | slice | writeMode | acceptance | status |' '|---|---|---|---|---|---|---|' \
    '| /id | leaf | row 2 | 1 | exec | row 2 | not built |' '| /modules/0 | leaf | row 2 | 1 | exec | row 2 | not built |' \
    '| /useCases/0/* (2) | leaf | row 3 | 1 | exec | row 3 | not built |' > "$P/architecture/coverage-ledger.md"
}
# run [env...] — Stage 4 line in $V, trace lines in $T
run() { env "$@" "$GATE" --no-html "$P" > "$WORK/out" 2> "$WORK/err"; V="$(grep '^Stage 4 ' "$WORK/out" | head -1)"; T="$(grep 's4cov-cache' "$WORK/err")"; }
# edit_keep_mtime <file> <sed-expr> — change content, restore the old mtime
edit_keep_mtime() { cp -p "$1" "$WORK/ref"; sed -i.bak "$2" "$1"; rm -f "$1.bak"; touch -r "$WORK/ref" "$1"; }

echo "== T1: unchanged inputs -> hit, same verdict =="
mkproj t1
run; case "$T:$V" in *miss*:*PASS*'coverage ledger clean'*) ok "first run measures (miss) and PASSes clean" ;; *) bad "first run" "$T | $V" ;; esac
run; V1="$V"
case "$T" in *hit*) ok "second run hits the cache" ;; *) bad "second run did not hit" "$T" ;; esac
run MXTK_S4COV_CACHE=0
[ -n "$V1" ] && [ "$V1" = "$V" ] && [ -z "$T" ] && ok "the cached Stage 4 line equals an uncached run's (MXTK_S4COV_CACHE=0)" \
  || bad "cached and uncached verdicts differ" "cached=$V1 | uncached=$V | trace=$T"

echo "== T2: ledger change (old mtime kept) -> miss, FAIL =="
edit_keep_mtime "$P/architecture/coverage-ledger.md" '/useCases\/0/d'
run
case "$T" in *miss*) ok "a ledger edit is a miss" ;; *) bad "ledger edit replayed the cache" "$T" ;; esac
case "$V" in *FAIL*'coverage ledger has findings'*'UNCLAIMED 2'*) ok "the gap FAILs Stage 4 (UNCLAIMED 2), no stale PASS" ;; *) bad "stale verdict after a ledger edit" "$V" ;; esac

echo "== T3: BRD change (old mtime kept) -> miss, FAIL =="
mkproj t3; run; run
case "$T" in *hit*) ;; *) bad "T3 setup did not hit" "$T" ;; esac
edit_keep_mtime "$P/analysis/src/knowledge-base/brd/F001.brd.json" 's/"title":"Submit"}/"title":"Submit"},{"id":"UC2","title":"Approve"}/'
run
case "$T" in *miss*) ok "a BRD edit is a miss" ;; *) bad "BRD edit replayed the cache" "$T" ;; esac
case "$V" in *FAIL*'coverage ledger has findings'*'UNCLAIMED 2'*) ok "the new use case FAILs Stage 4 (UNCLAIMED 2), no stale PASS" ;; *) bad "stale verdict after a BRD edit" "$V" ;; esac

echo "== T4: .mxtk/ not in .gitignore -> no cache =="
mkproj t4; rm "$P/.gitignore"
run; run
[ -z "$T" ] && [ ! -e "$P/.mxtk" ] && ok "no trace and no .mxtk/ written" || bad "cache used without the .gitignore opt-in" "$T"

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
