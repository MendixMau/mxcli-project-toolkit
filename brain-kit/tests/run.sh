#!/usr/bin/env bash
# Offline checks, no model calls: scripts compile, lint catches a broken note and passes a good one, index writes QUALITY.md.
# Usage: tests/run.sh   (PYTHON=<python with pyyaml> to override)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; kit="$here/.."; py="${PYTHON:-python3}"; fx="$here/fixture-brain"; fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

"$py" -c 'import yaml' 2>/dev/null || { echo "FAIL $py has no PyYAML (pip install pyyaml, or PYTHON=...)"; exit 1; }
check "scripts compile" "'$py' -m py_compile '$kit'/bin/*.py"
out="$("$py" "$kit/bin/gate.py" --brain "$fx" --checks lint 2>&1)"; rc=$?
check "lint exits 1 on a broken note" "[ $rc -eq 1 ]"
check "lint flags a bad kind" "grep -q 'bad-note: error kind opinion' <<<\"\$out\""
check "lint flags missing sources" "grep -q 'bad-note: error no sources' <<<\"\$out\""
check "lint flags a dangling link" "grep -q 'good-note: warn dangling link' <<<\"\$out\""
check "good note has no lint errors" "! grep -q 'good-note: error' <<<\"\$out\""
"$py" "$kit/bin/index.py" --brain "$fx" >/dev/null
check "index writes QUALITY.md" "grep -q '| demo | 2 |' '$fx/QUALITY.md'"
rm -f "$fx"/internal/demo/_gate.* "$fx/INDEX.md" "$fx/QUALITY.md"
exit $fail
