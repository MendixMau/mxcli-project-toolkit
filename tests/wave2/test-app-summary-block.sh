#!/usr/bin/env bash
# Fixture for the "What this application is" block on the extraction/gap report.
#
# The block leads the dashboard with a HUMAN-AUTHORED statement and puts CODE-DERIVED
# signals beneath it, labelled as inference. The failure this guards against is a
# fabricated summary at the top of a customer-facing report, so the tests are mostly
# about what must NOT appear:
#
#   T1  statement present  → rendered verbatim, with its source file and section named
#   T2  statement absent   → says so, gives the fix, and puts NO derived guess in the
#                            statement slot
#   T3  hostile input      → module names and authored prose are HTML-escaped
#   T4  zero extraction    → "nothing examined", never a confident empty inference
#   T5  all three pipeline generators emit the same block for the same input
#
# Run against a PRE-fix generate-report.js and T1..T4 fail (no block at all) — that is
# the positive control.
#
# Usage: test-app-summary-block.sh [/path/to/generate-report.js]
#        With no argument, every pipelines/*/pipeline/generate-report.js is tested.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="$(cd "$HERE/../.." && pwd)"

# Portability: the test suite must run on the platforms the toolkit targets, or the fix for
# a Windows bug can never be verified on Windows. Resolve Python by executing candidates.
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d /tmp/appsummary.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

if [ $# -ge 1 ]; then
  GENERATORS="$1"
else
  GENERATORS="$(ls "$TOOLKIT"/pipelines/*/pipeline/generate-report.js 2>/dev/null)"
fi
[ -n "$GENERATORS" ] || { echo "no generator to test" >&2; exit 2; }

# ── helpers ──────────────────────────────────────────────────────────────────
# mkkb <case> <entities-json> <screens-json> <logics-json>  → prints the KB dir
mkkb() {
  local case_name="$1" ents="$2" scrs="$3" logs="$4"
  local proj="$WORK/$case_name/proj"
  local kb="$proj/analysis/src/knowledge-base"
  mkdir -p "$kb"
  printf '%s' "$ents" > "$kb/entities.json"
  printf '%s' "$scrs" > "$kb/screens.json"
  printf '%s' "$logs" > "$kb/logics.json"
  printf '%s' "$kb"
}

# render <generator> <kbdir> → prints the report path (empty on failure)
render() {
  local gen="$1" kb="$2"
  local run; run="$(mktemp -d "$WORK/run.XXXXXX")"
  cp "$gen" "$run/generate-report.js"
  printf '{"knowledgeBaseDir":"%s"}' "$kb" > "$run/config.json"
  node "$run/generate-report.js" >/dev/null 2>&1 || return 1
  printf '%s' "$kb/extraction-report.html"
}

# block <report.html> → the app-summary block only (one line)
block() {
  "$PY" - "$1" <<'PY'
import re, sys
h = open(sys.argv[1], encoding='utf8').read()
m = re.search(r'<div class="app-summary[ "].*?<div class="app-summary-basis">.*?</div></div>', h, re.S)
print(m.group(0).replace('\n', ' ') if m else '')
PY
}

# statement_slot <report.html> → text of the human-statement div only
statement_slot() {
  "$PY" - "$1" <<'PY'
import re, sys
h = open(sys.argv[1], encoding='utf8').read()
m = re.search(r'<div class="app-summary-statement">(.*?)</div>', h, re.S)
print(re.sub(r'<[^>]+>', ' ', m.group(1)) if m else '')
PY
}

ENTS='[{"name":"TransportOrder","module":"transport","attributes":[]},
       {"name":"TransportUnit","module":"transport","attributes":[]},
       {"name":"Location","module":"location","attributes":[]}]'
SCRS='[{"name":"OrderList","module":"transport","widgetSummary":{"hasListUI":true}}]'
LOGS='[{"name":"CreateOrder","module":"transport","logicKind":"action"}]'

STATEMENT='A warehouse management system: it tracks stock in physical locations and
plans transport orders between them.'

for GEN in $GENERATORS; do
  PIPE="$(basename "$(dirname "$(dirname "$GEN")")")"
  echo "== pipeline: $PIPE =="

  # ── T1: human statement present ───────────────────────────────────────────
  KB="$(mkkb "$PIPE-t1" "$ENTS" "$SCRS" "$LOGS")"
  cat > "$WORK/$PIPE-t1/proj/intake.md" <<EOF
# intake.md

## 1. Which source folder(s) hold the legacy application?

source/

## What this application is

$STATEMENT

## 2. Something else

not the summary
EOF
  R="$(render "$GEN" "$KB")"
  if [ -z "$R" ]; then bad "T1 generator failed to run"; else
    B="$(block "$R")"
    case "$B" in
      *"A warehouse management system"*) ok "T1 renders the human statement" ;;
      *) bad "T1 human statement missing from the block" ;;
    esac
    case "$B" in
      *"Stated by a human in"*"intake.md"*) ok "T1 attributes the statement to intake.md" ;;
      *) bad "T1 no source attribution" ;;
    esac
    case "$B" in
      *"What this application is"*) ok "T1 names the section it read" ;;
      *) bad "T1 does not name the section" ;;
    esac
    # It must not swallow the NEXT section's prose.
    case "$B" in
      *"not the summary"*) bad "T1 bled into the following section" ;;
      *) ok "T1 stops at the next heading" ;;
    esac
    # Ordering: the block must precede the stat grid.
    POS_B="$(grep -bo 'class="app-summary' "$R" | head -1 | cut -d: -f1)"
    POS_S="$(grep -bo 'class="stat-grid"' "$R" | head -1 | cut -d: -f1)"
    if [ -n "$POS_B" ] && [ -n "$POS_S" ] && [ "$POS_B" -lt "$POS_S" ]; then
      ok "T1 block sits above the stat grid"
    else
      bad "T1 block is not above the stat grid (block=$POS_B grid=$POS_S)"
    fi
    # Inference must be labelled as inference, and show its basis.
    case "$B" in
      *"not a statement of fact"*) ok "T1 derived half is labelled as inference" ;;
      *) bad "T1 derived half is not labelled" ;;
    esac
    case "$B" in
      *"Derived from 3 entities, 1 screens, 1 logic items"*) ok "T1 reports what it examined" ;;
      *) bad "T1 does not report what it examined" ;;
    esac
  fi

  # ── T2: no human statement anywhere ───────────────────────────────────────
  KB="$(mkkb "$PIPE-t2" "$ENTS" "$SCRS" "$LOGS")"
  printf '# PROJECT.md\n\n## Decisions\n\nnone\n' > "$WORK/$PIPE-t2/proj/PROJECT.md"
  R="$(render "$GEN" "$KB")"
  if [ -z "$R" ]; then bad "T2 generator failed to run"; else
    B="$(block "$R")"
    case "$B" in
      *"No one has stated what this application is"*) ok "T2 says plainly that nobody stated it" ;;
      *) bad "T2 does not admit the statement is missing" ;;
    esac
    case "$B" in
      *"## What this application is"*"intake.md"*"re-run this report"*)
        ok "T2 gives the concrete fix (file, section, re-run)" ;;
      *) bad "T2 call to action is not actionable" ;;
    esac
    SLOT="$(statement_slot "$R")"
    # The statement slot must hold ONLY the admission — no derived noun may leak in.
    if printf '%s' "$SLOT" | grep -qiE 'transport|location|warehouse|crud|application type'; then
      bad "T2 FABRICATED a summary in the statement slot: $SLOT"
    else
      ok "T2 statement slot carries no fabricated summary"
    fi
    # The derived half still renders, below, and stays hedged.
    case "$B" in
      *"Reading only the extracted code"*"transport"*) ok "T2 still shows derived signals, hedged" ;;
      *) bad "T2 lost the derived half" ;;
    esac
  fi

  # ── T3: hostile source data is escaped ────────────────────────────────────
  HOSTILE_MOD='<img src=x onerror=alert(1)>'
  KB="$(mkkb "$PIPE-t3" \
    '[{"name":"Order","module":"<img src=x onerror=alert(1)>","attributes":[]}]' '[]' '[]')"
  cat > "$WORK/$PIPE-t3/proj/intake.md" <<'EOF'
## What this application is

Sells <script>alert("xss")</script> widgets & things.
EOF
  R="$(render "$GEN" "$KB")"
  if [ -z "$R" ]; then bad "T3 generator failed to run"; else
    B="$(block "$R")"
    case "$B" in
      *"$HOSTILE_MOD"*) bad "T3 raw <img> from a module name reached the HTML" ;;
      *) ok "T3 hostile module name did not reach the HTML raw" ;;
    esac
    case "$B" in
      *'<script>alert('*) bad "T3 raw <script> from the authored statement reached the HTML" ;;
      *) ok "T3 authored prose did not reach the HTML raw" ;;
    esac
    case "$B" in
      *'&lt;script&gt;'*) ok "T3 authored prose is escaped, not dropped" ;;
      *) bad "T3 escaped form of the authored prose is absent" ;;
    esac
    case "$B" in
      *'&lt;img src=x'*) ok "T3 module name is escaped, not dropped" ;;
      *) bad "T3 escaped form of the module name is absent" ;;
    esac
  fi

  # ── T4: an extraction that examined nothing ───────────────────────────────
  KB="$(mkkb "$PIPE-t4" '[]' '[]' '[]')"
  printf '# PROJECT.md\n' > "$WORK/$PIPE-t4/proj/PROJECT.md"
  R="$(render "$GEN" "$KB")"
  if [ -z "$R" ]; then bad "T4 generator failed to run"; else
    B="$(block "$R")"
    case "$B" in
      *"Nothing was examined"*) ok "T4 says it examined nothing" ;;
      *) bad "T4 did not admit it examined nothing" ;;
    esac
    case "$B" in
      *"Reading only the extracted code"*) bad "T4 asserted an inference over zero input" ;;
      *) ok "T4 asserts no inference over zero input" ;;
    esac
    case "$B" in
      *"0 entities, 0 screens, 0 logic items"*) ok "T4 reports the zero counts" ;;
      *) bad "T4 does not report the zero counts" ;;
    esac
  fi
done

# ── T5: the block is identical across the three generators ──────────────────
if [ $# -lt 1 ]; then
  echo "== consistency across pipelines =="
  SIG=""; CONSISTENT=1; N=0
  for GEN in $GENERATORS; do
    PIPE="$(basename "$(dirname "$(dirname "$GEN")")")"
    KB="$(mkkb "$PIPE-t5" "$ENTS" "$SCRS" "$LOGS")"
    cat > "$WORK/$PIPE-t5/proj/intake.md" <<EOF
## What this application is

$STATEMENT
EOF
    R="$(render "$GEN" "$KB")"
    [ -n "$R" ] || { CONSISTENT=0; continue; }
    THIS="$(block "$R")"
    N=$((N+1))
    if [ -z "$SIG" ]; then SIG="$THIS"
    elif [ "$SIG" != "$THIS" ]; then CONSISTENT=0; fi
  done
  if [ "$N" -ge 2 ] && [ "$CONSISTENT" -eq 1 ]; then
    ok "T5 all $N pipelines emit an identical block"
  else
    bad "T5 pipelines disagree on the block (n=$N)"
  fi
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
