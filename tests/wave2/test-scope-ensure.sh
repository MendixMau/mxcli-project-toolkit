#!/usr/bin/env bash
# Fixture for project-tests/e2e/scope-ensure.js: page-audit.js and design-audit.js read
# .claude/loop/page-scope.json and no mandatory step wrote it (speed experiment E2: the first
# page-audit run on a finished app was a FAULT with 0 pages until someone ran bin/page-scope.sh).
# The consumer is now its own producer: missing or older-than-the-model -> it runs the script.
#
# usage: bash tests/wave2/test-scope-ensure.sh [path-to-scope-ensure.js]
#
# The producer here is a stand-in that writes a one-page scope (the real bin/page-scope.sh needs a
# model and is covered by its own field run); what is asserted is WHEN the consumer runs it, that it
# never blanks an existing file when the run fails, and that it names the failure.
# Positive control: against master (no scope-ensure.js) every case fails.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-tests/e2e/scope-ensure.js}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
command -v node >/dev/null 2>&1 || { echo "SKIP: no node"; exit 0; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scope-ens.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"
[ -f "$SUBJECT" ] || { bad "subject not found"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

mk() {  # mk <dir> <producer: ok|fail|none>
  mkdir -p "$1/bin" "$1/.claude/loop"; : > "$1/X.mpr"
  case "$2" in
    ok)   printf '#!/usr/bin/env bash\nmkdir -p .claude/loop; echo "{\\"inScope\\":[\\"M.P\\"]}" > .claude/loop/page-scope.json\necho ran >> "$PROJECT_ROOT/.ran"\n' > "$1/bin/page-scope.sh" ;;
    fail) printf '#!/usr/bin/env bash\necho "no mxcli" >&2\nexit 2\n' > "$1/bin/page-scope.sh" ;;
  esac
}
call() {  # call <dir> -> prints JSON of the result
  node -e "
    const { ensureScope } = require('$SUBJECT');
    const d = '$1';
    console.log(JSON.stringify(ensureScope({ scopeFile: d + '/.claude/loop/page-scope.json', mprPath: d + '/X.mpr', roots: [d, require('path').dirname(d)] })));"
}
ran() { [ -f "$1/.ran" ] && wc -l < "$1/.ran" | tr -d ' ' || echo 0; }

P="$WORK/a"; mk "$P" ok
r="$(call "$P")"
echo "$r" | grep -q '"ran":true,"ok":true' && [ -s "$P/.claude/loop/page-scope.json" ] && echo "$r" | grep -q 'scope was missing' \
  && ok "missing scope: the consumer ran the producer and the file exists" || bad "missing scope" "$r"

r="$(call "$P")"
echo "$r" | grep -q '"ran":false,"ok":true' && [ "$(ran "$P")" = 1 ] && ok "fresh scope: producer not run again (it ran once in all)" || bad "fresh scope" "$r ran=$(ran "$P")"

sleep 1; touch "$P/X.mpr"
r="$(call "$P")"
echo "$r" | grep -q '"ran":true,"ok":true' && echo "$r" | grep -q 'older than the model' && [ "$(ran "$P")" = 2 ] \
  && ok "model newer than the scope: regenerated" || bad "stale scope" "$r ran=$(ran "$P")"

P="$WORK/b"; mk "$P" fail; echo '{"inScope":["Old.Page"]}' > "$P/.claude/loop/page-scope.json"; sleep 1; touch "$P/X.mpr"
r="$(call "$P")"
echo "$r" | grep -q '"ok":false' && echo "$r" | grep -q 'page-scope.sh failed (exit 2' && echo "$r" | grep -q 'no mxcli' \
  && grep -q Old.Page "$P/.claude/loop/page-scope.json" \
  && ok "stale scope + failing producer: ok=false, the failure is named, the old file is NOT blanked" || bad "failing producer" "$r"

P="$WORK/c"; mk "$P" none
r="$(call "$P")"
echo "$r" | grep -q '"ran":false,"ok":false' && echo "$r" | grep -q 'no bin/page-scope.sh' && [ ! -e "$P/.claude/loop/page-scope.json" ] \
  && ok "no producer installed: says so (run sync-project.sh), writes nothing" || bad "no producer" "$r"

# two-tree layout: the model's app/ is the root, bin/ lives one level up
P="$WORK/d"; mk "$P" ok; mkdir -p "$P/app"; rm -f "$P/.claude/loop/page-scope.json"
node -e "
  const { ensureScope } = require('$SUBJECT');
  const d = '$P';
  console.log(JSON.stringify(ensureScope({ scopeFile: d + '/.claude/loop/page-scope.json', mprPath: null, roots: [d + '/app', d] })));" > "$WORK/d.out"
grep -q '"ran":true,"ok":true' "$WORK/d.out" && ok "two-tree: bin/page-scope.sh found in the parent of the model root" || bad "two-tree" "$(cat "$WORK/d.out")"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
