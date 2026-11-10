#!/usr/bin/env bash
# test-link-proxy.sh: runs the link-proxy / exactly-once selftest (client abort survival, count-less
# modes, empty-expected failure) so it is part of the suite, and checks it is installed into projects.
# usage: test-link-proxy.sh
HERE="$(cd "$(dirname "$0")" && pwd)"; TK="$HERE/../.."
command -v node >/dev/null || { echo "SKIP node not installed"; exit 0; }
out=$(node "$TK/project-tests/e2e/link-proxy.selftest.js" 2>&1); rc=$?
printf '%s\n' "$out" | grep -E 'FAIL' 
[ $rc -eq 0 ] && echo "PASS selftest: $(printf '%s\n' "$out" | grep -c '^PASS') checks" || { echo "FAIL selftest rc=$rc"; exit 1; }
. "$TK/bin/lib/install-manifest.sh"
for f in link-proxy.js exactly-once.js link-proxy.selftest.js; do
  case " $MXTK_PROJECT_TESTS " in *" $f "*) echo "PASS $f is in MXTK_PROJECT_TESTS";; *) echo "FAIL $f not installed into projects"; exit 1;; esac
done
