#!/usr/bin/env bash
# harness-scan.sh — find browser test scripts that sign in without the toolkit's harness.
#
#   ./bin/harness-scan.sh [--quiet]
#
# WHY (#567, 2026-10-23). The toolkit's harness signs out correctly (tests/e2e/helpers.js
# logout(): the xas `logout` action; journey-runner.js ends its session on every exit path), and
# measured-claims.md §4 records why that matters: a Mendix session outlives the browser, and a
# trial runtime refuses every login after its session cap. But the harness is optional. In a
# cook-off two agents wrote their own acceptance scripts; neither signed out properly, and the
# runs stalled on "Maximum number of sessions exceeded" (138 refusals, ~20 min, one run retaken).
# Nothing told either agent the harness existed. This scan is that pointer.
#
# WHAT IT READS. Every *.js / *.mjs / *.cjs / *.ts file under tests/, e2e/ and acceptance/ in the
# project root, minus node_modules/, artifacts/, and the toolkit's own engine files installed in
# tests/e2e/ (MXTK_PROJECT_TESTS in the toolkit's bin/lib/install-manifest.sh — those ARE the
# harness). A file "signs in" when it opens login.html, fills #usernameInput, or posts the xas
# `login` action. A file "uses the harness" when it requires helpers.js or journey-runner.js.
#
# WHAT IT REPORTS, per hand-rolled file that signs in:
#   no-sign-out      no logout of any kind: each run holds one server session until it times out
#   get-logout-only  only a GET to /logout, which renders a page and leaves the session alive
#   own-sign-out     signs out its own way (xas logout / mx.logout): noted, not judged
# Text patterns, not a parse: a file can fool it both ways, and the line says which pattern hit.
#
# NOT A GATE. verify-module.sh runs it as an informational (note) rung: it never changes a
# module verdict. It produces nothing another step reads; its producer is the project's own
# test scripts, which no mandatory step is required to create, so an empty result is normal.
#
# Exit: 0 nothing to report · 1 at least one no-sign-out / get-logout-only file · 2 usage.
set -uo pipefail

QUIET=0
case "${1:-}" in
  --quiet) QUIET=1 ;;
  "") ;;
  -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  *) echo "usage: harness-scan.sh [--quiet]" >&2; exit 2 ;;
esac

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
ROOT="${PROJECT_ROOT:-$(pwd)}"

# The engine files the toolkit installs into tests/e2e/ — kept in step with install-manifest.sh's
# MXTK_PROJECT_TESTS. A name missing here is only a false NOTE on the toolkit's own file.
ENGINE=" config.js helpers.js settle.js otel.js journey-runner.js named-controls.js journey-runner.selftest.js journey-rung4-scope.test.js monkey.js monkey.selftest.js page-audit.js page-audit-rules.js design-audit.js full-app-walkthrough.js report-normalize.js report-render.js review-report.js demo-polish.js demo-polish.selftest.js project.config.js project.config.template.js "

files=()
for d in tests e2e acceptance; do
  [ -d "$ROOT/$d" ] || continue
  while IFS= read -r f; do files+=("$f"); done < <(
    find "$ROOT/$d" \( -name node_modules -o -name artifacts \) -prune -o \
      -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' \) -print 2>/dev/null | sort)
done

scanned=0; signin=0; flagged=0; own=0; harness=0
out=""
for f in ${files[@]+"${files[@]}"}; do
  rel="${f#$ROOT/}"
  case "$rel" in tests/e2e/*/*) ;; tests/e2e/*) case "$ENGINE" in *" ${rel#tests/e2e/} "*) continue ;; esac ;; esac
  scanned=$((scanned+1))
  grep -qE "login\.html|#usernameInput|action['\"]?[[:space:]]*:[[:space:]]*['\"]login['\"]" "$f" || continue
  signin=$((signin+1))
  if grep -qE "require\([^)]*(helpers|journey-runner)(\.js)?['\"]|from[[:space:]]+['\"][^'\"]*(helpers|journey-runner)(\.js)?['\"]" "$f"; then
    harness=$((harness+1)); continue
  fi
  if grep -qE "action['\"]?[[:space:]]*:[[:space:]]*['\"]logout['\"]|mx\.logout|mx\.session\.logout|session\.logout\(" "$f"; then
    own=$((own+1)); out="${out}own-sign-out	$rel	signs out its own way; the harness's logout() is measured (measured-claims.md §4)
"
  elif grep -qE "/logout" "$f"; then
    flagged=$((flagged+1)); out="${out}get-logout-only	$rel	a GET to /logout leaves the server session alive; use helpers.js logout() (xas logout)
"
  else
    flagged=$((flagged+1)); out="${out}no-sign-out	$rel	signs in and never signs out: each run holds a session until timeout (trial cap); require tests/e2e/helpers.js
"
  fi
done

if [ "$QUIET" -eq 0 ]; then
  printf '%s' "$out"
  echo "harness-scan: $scanned script(s) scanned, $signin sign in, $harness through the harness, $own own sign-out, $flagged at risk of the session cap"
  [ "$flagged" -gt 0 ] && echo "  why: skills/measured-claims.md §4 (a Mendix session outlives the browser). Recovery if the cap is hit: same section."
fi
[ "$flagged" -gt 0 ] && exit 1
exit 0
