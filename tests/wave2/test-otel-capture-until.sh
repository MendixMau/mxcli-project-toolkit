#!/usr/bin/env bash
# Usage: bash test-otel-capture-until.sh [path-to-otel.js]
#
# Fixture for project-tests/e2e/otel.js capture()'s stopping condition, and the journey
# runner's rung-2 use of it.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): rung 2 called
# capture(t0, { min: 1 }), which stops at the FIRST poll holding any span at all. The batch
# exporter routinely flushes a step's HTTP/xas spans before its microflow spans, so 2 of 6
# `spans.ordered` claims failed "actual (none)" over sequences Jaeger held a second later
# (verified by querying Jaeger directly); the next run of the same journey was green. capture()
# now takes `until(spans)`, and the runner waits for the claimed microflows.
#
# Golden input is a real Jaeger /api/traces response (fixtures/otel-capture/
# jaeger-trace-refused-arm.json: one trace, 8 spans, Mendix 11.13.0 runtime → Jaeger v1.76 OTLP),
# verbatim except `processes` dropped (capture() never reads it; it carries the host command
# line) and the checkout path replaced by /work/app. The flush ORDER is the synthetic part: a
# stubbed fetch serves the non-microflow spans on poll 1 and the whole trace from poll 2 —
# the shape observed in the field, reproduced deterministically.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/otel.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLDEN="$HERE/fixtures/otel-capture/jaeger-trace-refused-arm.json"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }
RUNNER="$(dirname "$SUT")/journey-runner.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/otel-until.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$SUT" "$WORK/otel.js"
# otel.js reads only otelService from the config at require time.
echo "module.exports = { otelService: 'Fixture' };" > "$WORK/project.config.js"

OUT="$(node - "$WORK/otel.js" "$GOLDEN" <<'EOF'
const fs = require('fs');
const [sut, golden] = process.argv.slice(2);
const full = JSON.parse(fs.readFileSync(golden, 'utf8'));
const isMf = s => s.tags.some(t => t.key === 'mx.microflow.name');
const firstFlush = { ...full, data: full.data.map(t => ({ ...t, spans: t.spans.filter(s => !isMf(s)) })) };
let polls = 0;
global.fetch = async () => { polls++; const body = polls === 1 ? firstFlush : full; return { json: async () => body }; };
const O = require(sut);
const claimed = ['MockServices.ACT_MockScenario_Arm', 'MockServices.VAL_MockScenario_Arm', 'MockServices.VAL_MockScenario_Payload'];
const names = sp => O.microflowNames(sp).sort().join(',');
(async () => {
  const opts = { retries: 5, waitMs: 1 };
  polls = 0; let sp = await O.capture(0, { ...opts, min: 1 });
  console.log(`MIN1 polls=${polls} spans=${sp.length} mf=${names(sp) || '-'}`);
  polls = 0; sp = await O.capture(0, { ...opts, min: 1, until: s => claimed.every(n => O.microflowNames(s).includes(n)) });
  console.log(`UNTIL polls=${polls} spans=${sp.length} mf=${names(sp) || '-'}`);
  polls = 0; sp = await O.capture(0, { ...opts, min: 1, until: s => O.microflowNames(s).includes('MockServices.NEVER') });
  console.log(`NEVER polls=${polls} spans=${sp.length}`);
})().catch(e => { console.log(`ERR ${e.message}`); process.exit(3); });
EOF
)"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL — harness could not drive capture() from $SUT (rc=$rc)"; echo "$OUT"; exit 1; }
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }

L="$(line MIN1)"
case "$L" in "polls=1 spans=5 mf=-") ok "min:1 alone stops at the first flush with 0 microflow spans (the race, characterised)" ;;
  *) bad "golden replay did not reproduce the first-flush shape" "$L" ;; esac
L="$(line UNTIL)"
case "$L" in "polls=2 spans=8 mf="*VAL_MockScenario_Payload*) ok "until: keeps polling until the claimed microflows are present (poll 2, 8 spans)" ;;
  *) bad "until: did not wait for the claimed microflows (the 2026-09-26 false red)" "$L" ;; esac
L="$(line NEVER)"
case "$L" in "polls=5 spans=8") ok "an until that never holds returns what it has after the retry window — no hang, no fake pass" ;;
  *) bad "unsatisfiable until misbehaved" "$L" ;; esac

if [ -f "$RUNNER" ]; then
  if awk '/RUNG 2: ordered spans/{f=1} f&&/O\.capture\(/{c=1} c&&/until:/{print "yes"; exit} /RUNG 3/{exit}' "$RUNNER" | grep -q yes; then
    ok "journey-runner.js rung 2 passes until: to capture()"
  else
    bad "journey-runner.js rung 2 still captures with min:1 alone"
  fi
else
  echo "  skip — journey-runner.js not beside $SUT"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
