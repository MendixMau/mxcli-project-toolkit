#!/usr/bin/env bash
# Fixture for the test-strategy doc shift (2026-10-16): every place that sent the full suite to
# module close now says what the project strategy says, and the CAC-5 Offer carries the table.
#
# usage: bash tests/wave2/test-test-strategy-docs.sh [toolkit-root]
#
# Doc wording is behaviour for agent-read text, so this pins the facts that must agree:
#   - no skill still says the full suite runs at module close, or names a "release gate" for it
#   - testing-shape.md, the check-moments table and the Offer table carry the same three rows
#     and the same defaults (every change affected, module done module, build complete full)
#   - existing-app-change.md keeps "every gate is also a regression gate" and adds the scoping
#   - exec.sh's logic lane text points at the strategy, not at module close
# This test keeps those files, the Offer and affected-tests.sh from drifting apart. The
# maintainer waived the A/B on 2026-10-16; E3 runs after merge as a check.
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
! has project-bin/exec.sh "Full mxcli test at module close, not here" && has project-bin/exec.sh "everything runs once at build complete and before each later deploy, per PROJECT.md ## Test strategy" \
  && ok "exec.sh logic lane text" || bad "exec.sh logic lane text"

echo "== one table, three places =="
for f in skills/checkpoints/checkpoint-build.md; do
  has $f "| Every change (build and feedback) | affected, modules on only | affected |" && has $f "| Module done | module, modules on only | module |" && has $f "| Build complete, and before every later deploy | full | full |" \
    && ok "CAC-5 Offer table with the three defaults" || bad "Offer table"
done
has skills/checkpoints/checkpoint-build.md "PROJECT.md\` → \`## Test strategy\`" && has skills/checkpoints/checkpoint-build.md "CONFIRMED" \
  && ok "Offer records the choice with a Status column" || bad "Offer record line"
has skills/testing-shape.md "defaults \`affected\`, \`module\`, \`full\`" \
  && ok "testing-shape.md states the same defaults" || bad "testing-shape.md defaults sentence"

echo "== existing-app-change.md =="
has skills/existing-app-change.md "Re-run the baseline at every module gate" && ok "kept: every gate is also a regression gate" || bad "regression-gate rule lost"
has skills/existing-app-change.md "the whole baseline runs at deploy-ready" && ok "whole baseline at deploy-ready" || bad "deploy-ready baseline"
has skills/existing-app-change.md "--moment module --module <M>" && has skills/checkpoints/checkpoint-build.md "--moment module --module <M>" \
  && ok "the module-moment call names its module" || bad "module call without --module"

echo "== unit tests off by default, wired =="
has skills/checkpoints/checkpoint-build.md "\`Unit flows:\`" && has skills/checkpoints/checkpoint-build.md "Unit tests default: yes" && has skills/checkpoints/checkpoint-build.md "Unit tests: yes" \
  && ok "Offer records the three ways to turn unit on" || bad "unit-on syntax missing"
has skills/checkpoints/checkpoint-build.md "Build complete = you say the app is ready" && ok "build complete is declared by the developer" || bad "build complete undefined"
has skills/module-review.md "--moment module" && ok "module-review PROVE runs the module row" || bad "module-review not wired"
has skills/module-brief.md "Unit flows:" && ok "module brief names the Unit flows list" || bad "module brief flip line"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
