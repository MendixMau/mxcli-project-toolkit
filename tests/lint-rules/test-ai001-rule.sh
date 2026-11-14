#!/usr/bin/env bash
# test-ai001-rule.sh -- unit tests for lint-rules/mxtk_ai001_genai_without_commons.star (MXTK-AI001),
# run under the real Go Starlark interpreter with the mxcli builtins mocked from JSON
# (tests/lint-rules/starrun).
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/ai001-*.json is a HAND-WRITTEN unit
# fixture. The projection field names were read from the mxcli source (v0.31.0); the rows are
# invented. These tests prove the rule logic and its self-check, not the vocabulary of YOUR
# model. The field run is in the rule's header and the CHANGELOG line.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-ai001-rule.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R="$TK/lint-rules/mxtk_ai001_genai_without_commons.star"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py

W=$(mktemp -d "${TMPDIR:-/tmp}/ai001.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0; FAILED=0
ok(){ printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

OUT="$W/out.json"; ERR="$W/err.txt"; RC=0
BIN="$W/starrun"
if ! (cd "$HERE/starrun" && GOFLAGS=-mod=mod go build -o "$BIN" . 2>"$ERR"); then
  echo "FAIL could not build tests/lint-rules/starrun: $(head -c 400 "$ERR")"; exit 1
fi
run(){ "$BIN" -rule "$R" -fixture "$FX/$1.json" >"$OUT" 2>"$ERR"; RC=$?; }
check(){
  local label="$1" expr="$2"
  if [ "$RC" -ne 0 ]; then no "$label (harness exit $RC: $(head -c 300 "$ERR"))"; return; fi
  if "$PY" - "$OUT" "$expr" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$label"; else no "$label (got: $(head -c 400 "$OUT"))"; fi
}

echo "== MXTK-AI001 =="
run ai001-a-clean
check "a ordinary REST client and constants, no GenAI -> 0" 'len(v)==0'
run ai001-b-constant-converse
check "b constant holding a /converse URL, no GenAI Commons -> 1 on the constant" 'len(v)==1 and v[0]["document_name"]=="Sales.LlmEndpoint" and v[0]["document_type"]=="Constant" and "marketplace-catalogue.md" in v[0]["suggestion"]'
run ai001-c-present-graph
check "c same constant, GenAICommons in the module graph -> 0" 'len(v)==0'
run ai001-d-present-module
check "d same, GenAICommons among the app modules (imported from file) -> 0" 'len(v)==0'
run ai001-e-all-sources
check "e constant value, REST client, REST operation, Java action, jar -> 5, client and its operation folded" 'len(v)==5 and sorted(x["document_name"] for x in v)==sorted(["Triage.ModelEndpoint","Triage.ModelApi","Triage.EmbedApi","Triage.JA_CallLlm","Triage"])'
run ai001-f-near-miss
check "f Algorithm, conversation(s), Openair, Allmode, a connector-named constant -> 0" 'len(v)==0'
run ai001-g-no-graph
check "g evidence but no module graph -> one _rule finding, nothing decided" 'len(v)==1 and v[0]["module"]=="_rule"'
run ai001-h-camel
check "h camel-case OpenAIApiKey, JA_CallLlm flagged; Ballmer/Gallmo not" 'sorted(x["document_name"] for x in v)==["Sales.JA_CallLlm","Sales.OpenAIApiKey"]'

echo ""
echo "test-ai001-rule: $PASS passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
