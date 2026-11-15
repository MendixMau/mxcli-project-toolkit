#!/usr/bin/env bash
# Usage: bash test-report-seeds-668.sh [path-to-report-render.js]
#
# Fixture for #668 (report half): the HTML report showed `Open {{order}}` for a step the runner had
# resolved to `Open SO-1001`. Stored names stay RAW on purpose (report-normalize.js joins rows to the
# journey contract by that exact string); the walk records its seeds, so report-render.js resolves
# them for DISPLAY only, on a copy. Asserted here: the page shows resolved text; an unresolvable
# placeholder (`{{ghost}}`) stays visible as written; a walk with no recorded seeds is shown raw, not
# blank; report.json (every join key, id and the raw names) is byte-identical before and after render.
#
# Golden input: fixtures/report-seeds-668/ — a findings file written by the REAL journey-runner
# runJourney() in headless Chromium against a localhost stand-in page (see its CAPTURE.txt). The
# normalize + render steps below run on that capture; no browser is needed here.

set -uo pipefail
SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/report-render.js"
if [ ! -f "$SUT" ]; then echo "SKIP: subject not found at $SUT"; echo "SCORE: 0/0 — nothing to test"; exit 0; fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLD="$HERE/fixtures/report-seeds-668"
CFG="$E2E/project.config.template.js"; [ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rseeds668.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/p"; mkdir -p "$P/tests/e2e/artifacts" "$P/tests/e2e/journeys"; : > "$P/Orders.mpr"
cp "$E2E"/*.js "$P/tests/e2e/"; cp "$CFG" "$P/tests/e2e/project.config.js"
cp "$SUT" "$P/tests/e2e/report-render.js"
cp "$GOLD/journey-findings.json" "$P/tests/e2e/artifacts/"; cp "$GOLD/Orders.journey.json" "$P/tests/e2e/journeys/"
( cd "$P/tests/e2e" && JOURNEY_DIR="$P/tests/e2e/journeys" node report-normalize.js --out docs/report.json ) >"$WORK/n.out" 2>&1
[ -s "$P/docs/report.json" ] || { bad "normalize wrote no report.json" "$(tr '\n' ' ' < "$WORK/n.out" | cut -c1-300)"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
sum() { node -e 'console.log(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }
BEFORE="$(sum "$P/docs/report.json")"
render() { ( cd "$P/tests/e2e" && node report-render.js --in "$1" --out "$2" ) >"$WORK/r.out" 2>&1; }
render "$P/docs/report.json" "$P/docs/report.html"
# one tag per line so a grep sees one text node at a time
flat() { sed 's/></>\n</g' "$1"; }

# 1. the stored names are raw (the join keys) and the walk carries the seeds
node -e 'const r=require(process.argv[1]); const w=r.walks[0];
  process.exit(w.seeds&&w.seeds.order==="SO-1001" && w.steps[0].name==="Open {{order}}" && r.checks.some(c=>c.sourceName==="Open {{order}}: reached") ? 0 : 1)' "$P/docs/report.json" \
  && ok "report.json keeps the raw names (Open {{order}}) and the walk's seeds" || bad "report.json raw names / seeds"

# 2. displayed text is resolved
flat "$P/docs/report.html" > "$WORK/h.txt"
grep -qF '<span class="wst">Open SO-1001</span>' "$WORK/h.txt" && ok "walk step name shows the seed value" || bad "walk step name not resolved"
grep -qF '<td>Open SO-1001: reached</td>' "$WORK/h.txt" && grep -qF 'Open SO-1001: page says' "$WORK/h.txt" \
  && ok "check (assertion) labels show the seed value" || bad "check labels not resolved"
grep -qF 'Ship order SO-1001' "$WORK/h.txt" && ok "journey title shows the seed value" || bad "journey title not resolved"
grep -qF '<code>SO-1001</code>' "$WORK/h.txt" && ok "the page-says expectation shows the seed value" || bad "expectation not resolved"
if grep -q 'Open {{order}}\|Ship {{order}}\|<code>{{order}}</code>' "$WORK/h.txt"; then bad "a resolvable {{order}} is still shown raw"
else ok "no resolvable placeholder is left in the page"; fi

# 3. an unresolvable placeholder stays visible as written, never blank
grep -qF 'Ship SO-1001 ({{ghost}})' "$WORK/h.txt" && ok "{{ghost}} (no seed) stays visible as written" || bad "unresolved placeholder lost or blanked"

# 4. report.json is untouched by render (ids, journey, stepIndex, sourceName stay the join keys)
[ "$(sum "$P/docs/report.json")" = "$BEFORE" ] && ok "report.json byte-identical after render" || bad "render changed report.json"

# 5. a walk that recorded NO seeds is shown as written (nothing to resolve, nothing blanked)
node -e 'const fs=require("fs"),f=process.argv[1],d=JSON.parse(fs.readFileSync(f)); d.walks[0].seeds={}; fs.writeFileSync(f,JSON.stringify(d))' "$P/tests/e2e/artifacts/journey-findings.json"
( cd "$P/tests/e2e" && JOURNEY_DIR="$P/tests/e2e/journeys" node report-normalize.js --out docs/report2.json ) >/dev/null 2>&1
render "$P/docs/report2.json" "$P/docs/report2.html"
flat "$P/docs/report2.html" > "$WORK/h2.txt"
grep -qF '<span class="wst">Open {{order}}</span>' "$WORK/h2.txt" \
  && ok "no recorded seeds -> the raw placeholder is shown, not blank" || bad "walk without seeds rendered wrongly" "$(grep -m2 'wst' "$WORK/h2.txt")"

echo ""; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
