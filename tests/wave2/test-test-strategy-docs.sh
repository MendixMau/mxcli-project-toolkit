#!/usr/bin/env bash
# Fixture for the test-strategy doc shift (2026-10-16): every place that sent the full suite to
# module close now says what the project strategy says, and the CAC-5 Offer carries the table.
#
# usage: bash tests/wave2/test-test-strategy-docs.sh [toolkit-root]
#
# Doc wording is behaviour for agent-read text, so this pins the facts that must agree:
#   - no skill still says the full suite runs at module close, or names a "release gate" for it
#   - testing-shape.md, the check-moments table and the Offer table carry the same three rows
#     and the same defaults (every change affected, module close module, deploy-ready full)
#   - existing-app-change.md keeps "every gate is also a regression gate" and adds the scoping
#   - exec.sh's logic lane text points at the strategy, not at module close
# The held PR that carries these edits is gated on the A/B (E3); this test only keeps the
# files from drifting apart while it is held.
#
# Positive control: on master 9 of 10 checks fail; only the "kept" regression-gate guard passes.
set -uo pipefail
T="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; return 0; }
has()  { grep -qF -- "$2" "$T/$1"; }
echo "== subject: $T"

echo "== the old full-suite-at-module-close wording is gone =="
! has skills/testing-shape.md "| Module close | The full suite, once" && ! has skills/testing-shape.md "| Release gate (before UAT/production)" \
  && ok "testing-shape.md event table" || bad "testing-shape.md event table still has module-close full suite or Release gate"
! has skills/testing-shape.md "The module's full suite and journeys" && ! has skills/testing-shape.md "| **Release gate** |" \
  && ok "testing-shape.md check-moments table" || bad "testing-shape.md check-moments table"
! has skills/iterative-build-loop.md "(module close only, never batch close)" && has skills/iterative-build-loop.md "PROJECT.md \`## Test strategy\`" \
  && ok "iterative-build-loop.md points at the strategy" || bad "iterative-build-loop.md"
! has skills/conversion-runbook.md "the release gate owes" && has skills/conversion-runbook.md "deploy-ready owes" \
  && ok "conversion-runbook.md says deploy-ready" || bad "conversion-runbook.md"
! has project-bin/exec.sh "Full mxcli test at module close, not here" && has project-bin/exec.sh "The full suite runs at deploy-ready, per PROJECT.md ## Test strategy" \
  && ok "exec.sh logic lane text" || bad "exec.sh logic lane text"

echo "== one table, three places =="
for f in skills/checkpoints/checkpoint-build.md; do
  has $f "| Every change | affected | affected |" && has $f "| Module close | module | module |" && has $f "| Deploy-ready | full | full |" \
    && ok "CAC-5 Offer table with the three defaults" || bad "Offer table"
done
has skills/checkpoints/checkpoint-build.md "PROJECT.md\` → \`## Test strategy\`" && has skills/checkpoints/checkpoint-build.md "CONFIRMED" \
  && ok "Offer records the choice with a Status column" || bad "Offer record line"
has skills/testing-shape.md "Defaults: every change \`affected\`, module close \`module\`, deploy-ready" \
  && ok "testing-shape.md states the same defaults" || bad "testing-shape.md defaults sentence"

echo "== existing-app-change.md =="
has skills/existing-app-change.md "Re-run the baseline at every module gate" && ok "kept: every gate is also a regression gate" || bad "regression-gate rule lost"
has skills/existing-app-change.md "the whole baseline runs at deploy-ready" && ok "whole baseline at deploy-ready" || bad "deploy-ready baseline"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
