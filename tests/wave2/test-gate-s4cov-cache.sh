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
#   T5-T8 — the four stale PASSes the independent review of #715 reproduced on its first head:
#   T5 a symlinked architecture/ dir, T6 a symlinked ledger file, T7 BRD_FILE set in
#   .claude/toolkit.env (then repointed), T8 BRD_FILE outside the project with its content edited.
#   Each one: an uncached run FAILs (UNCLAIMED 2) and the cache must miss, never replay PASS.
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
# A user's ~/.mxcli-toolkit.env must not leak into the fixture (mxtk_load_env reads it).
export HOME="$WORK/home"; mkdir -p "$HOME"

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

# stale_check <label> — after an edit that makes the uncached verdict FAIL: miss + FAIL, never PASS
stale_check() {
  run
  case "$T" in *miss*) ok "$1: the cache misses" ;; *) bad "$1: the cache replayed" "$T" ;; esac
  case "$V" in *FAIL*'UNCLAIMED 2'*) ok "$1: Stage 4 FAILs (UNCLAIMED 2), no stale PASS" ;; *) bad "$1: stale verdict" "$V" ;; esac
}
primed() { run; run; case "$T:$V" in *hit*:*PASS*) return 0 ;; esac; bad "$1 setup: no cached PASS" "$T | $V"; return 1; }
BRD2='{"id":"F001","modules":["Purchasing"],"useCases":[{"id":"UC1","title":"Submit"},{"id":"UC2","title":"Approve"}]}'

echo "== T5: symlinked architecture/ dir, ledger edited in the target =="
mkproj t5; mv "$P/architecture" "$WORK/t5-arch"; ln -s "$WORK/t5-arch" "$P/architecture"
primed T5 && { edit_keep_mtime "$WORK/t5-arch/coverage-ledger.md" '/useCases\/0/d'; stale_check T5; }

echo "== T6: symlinked ledger file, target edited =="
mkproj t6; mv "$P/architecture/coverage-ledger.md" "$WORK/t6-ledger.md"; ln -s "$WORK/t6-ledger.md" "$P/architecture/coverage-ledger.md"
primed T6 && { edit_keep_mtime "$WORK/t6-ledger.md" '/useCases\/0/d'; stale_check T6; }

echo "== T7: BRD_FILE in .claude/toolkit.env, repointed =="
mkproj t7; mkdir -p "$P/.claude" "$P/specs"
cp "$P/analysis/src/knowledge-base/brd/F001.brd.json" "$P/specs/F001.brd.json"
printf '%s\n' "$BRD2" > "$P/specs/F001-v2.brd.json"
printf 'BRD_FILE=specs/F001.brd.json\n' > "$P/.claude/toolkit.env"
primed T7 && { edit_keep_mtime "$P/.claude/toolkit.env" 's#specs/F001.brd.json#specs/F001-v2.brd.json#'; stale_check T7; }

echo "== T8: BRD_FILE outside the project, content edited (old mtime kept) =="
mkproj t8; mkdir -p "$WORK/ext"; cp "$P/analysis/src/knowledge-base/brd/F001.brd.json" "$WORK/ext/F001.brd.json"
export BRD_FILE="$WORK/ext/F001.brd.json"
primed T8 && { edit_keep_mtime "$BRD_FILE" 's/"title":"Submit"}/"title":"Submit"},{"id":"UC2","title":"Approve"}/'; stale_check T8; }
unset BRD_FILE

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
