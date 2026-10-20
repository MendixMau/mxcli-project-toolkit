#!/usr/bin/env bash
# Usage: bash test-conformance-absent-marker.sh [path-to-conformance-check.sh]
#
# Fixture for project-bin/conformance-check.sh's probe(): where it looks for the two "absent"
# markers in mxcli's answer (issue #470).
#
# The defect: any "(0 " or "not found" ANYWHERE in the output scored the element ABSENT, so a
# built row went STALE when the definition merely contained those characters. The issue's field
# case: a microflow whose documentation reads "HttpStatus (0 = no response or time-out)" — five
# false STALEs in one module. The same substring match hits every `describe navigation` with a
# not-found page set, because mxcli prints that setting as "  not found page <Page>".
#
# Golden input. No mxcli binary was available when this fixture was written, so it replays
# captures already in this repo, verbatim:
#   - fixtures/design-audit-nav/describe-navigation-responsive-v025.txt — `describe navigation
#     Responsive`, mxcli v0.25.0 on mxcli's public test app testapp-views/TestApp.mpr (carries
#     "  not found page Pages.Vehicle_Overview"); replayed without its four "-- GOLDEN" header lines;
#   - fixtures/context-pack/capture/describe/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out —
#     `DESCRIBE MICROFLOW`, mxcli v0.23.0. The issue's doc text is quoted verbatim from #470 and
#     spliced into that capture's documentation line (the only edit), since #470 quotes the
#     sentence, not the whole definition.
# The empty-set reply follows mxcli's own printer (mdl/executor/format.go: the summary is
# printed as "\n%s\n" after the table, Summary = "(%d entities)", "(%d workflow group(s))", …),
# not a capture — re-capture it from a real `SHOW … IN <empty module>` when a binary is at hand.
#
# Cases, each on BOTH layouts (single-tree, and two-tree with the .mpr under app/):
#   1. a built microflow whose documentation says "(0 = …)" is PRESENT (was ABSENT -> STALE)
#   2. a built navigation profile with a not-found page is PRESENT (was ABSENT -> STALE)
#   3. the unedited microflow capture stays PRESENT
#   4. an empty result set, "(0 entities)" as the last line, stays ABSENT
#   5. an empty set whose noun has parentheses, "(0 workflow group(s))", stays ABSENT
#   6. a missing element ("Error: … not found", rc 1) stays ABSENT
#   7. an "Error:" line with rc 0 is still ABSENT
#   8. CRLF output (a Windows-built mxcli) reads the same: the doc'd microflow PRESENT, the
#      empty set ABSENT

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/conformance-check.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
[ -f "$(dirname "$SUT")/_common.sh" ] || { echo "FAIL — _common.sh not beside $SUT"; exit 1; }
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"
NAV="$FIX/design-audit-nav/describe-navigation-responsive-v025.txt"
MF="$FIX/context-pack/capture/describe/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out"
for f in "$NAV" "$MF"; do [ -f "$f" ] || { echo "FAIL — golden capture missing: $f"; exit 1; }; done

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conf-absent.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

setup() {  # setup <single|two> <crlf|lf> -> sets P
  P="$WORK/$1-$2"
  rm -rf "$P"; mkdir -p "$P/architecture/modules/Sales" "$P/cap"
  if [ "$1" = two ]; then mkdir -p "$P/app"; : > "$P/app/App.mpr"; else : > "$P/App.mpr"; fi
  grep -v '^-- GOLDEN\|^-- built from\|^-- testdata/\|^-- the same text' "$NAV" > "$P/cap/nav.out"
  cp "$MF" "$P/cap/mf.out"
  # The one edit: the issue's verbatim documentation text in place of the capture's.
  sed 's#^ \* Page button: approve the current step with the comment typed on it\.$# * Page button: approve. HttpStatus (0 = no response or time-out).#' \
    "$MF" > "$P/cap/mfdoc.out"
  printf '| Name |\n|------|\n\n(0 entities)\n' > "$P/cap/empty.out"
  printf '| Name |\n|------|\n\n(0 workflow group(s))\n' > "$P/cap/emptyparen.out"
  if [ "$2" = crlf ]; then
    for f in "$P"/cap/*.out; do sed 's/$/\r/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
  fi
  cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
c="$(dirname "$0")/cap"
case "$cmd" in
  "DESCRIBE NAVIGATION Responsive")   cat "$c/nav.out" ;;
  "DESCRIBE MICROFLOW Sales.ACT_Plain") cat "$c/mf.out" ;;
  "DESCRIBE MICROFLOW Sales.ACT_Doc")   cat "$c/mfdoc.out" ;;
  "SHOW ENTITIES IN Empty")           cat "$c/empty.out" ;;
  "SHOW WORKFLOWS IN Empty")          cat "$c/emptyparen.out" ;;
  "DESCRIBE MICROFLOW Sales.ACT_Rc0") echo "Error: microflow not found: Sales.ACT_Rc0" ;;
  *) echo "Error: microflow not found: ${cmd##* }" >&2; exit 1 ;;
esac
EOF
  chmod +x "$P/mxcli"
  cat > "$P/architecture/modules/Sales/coverage-ledger.md" <<'EOF'
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| `/microflows/1` | microflow | ACT_Doc | 1.1 | exec.sh | `DESCRIBE MICROFLOW Sales.ACT_Doc` | built |
| `/navigation/0` | navigation | Responsive | 1.2 | exec.sh | `DESCRIBE NAVIGATION Responsive` | built |
| `/microflows/0` | microflow | ACT_Plain | 1.3 | exec.sh | `DESCRIBE MICROFLOW Sales.ACT_Plain` | built |
| `/entities/0` | entity | Nothing | 1.4 | exec.sh | `SHOW ENTITIES IN Empty` | not-built |
| `/workflows/0` | workflow | Nothing | 1.5 | exec.sh | `SHOW WORKFLOWS IN Empty` | not-built |
| `/microflows/2` | microflow | ACT_Gone | 1.6 | exec.sh | `DESCRIBE MICROFLOW Sales.ACT_Gone` | not-built |
| `/microflows/3` | microflow | ACT_Rc0 | 1.7 | exec.sh | `DESCRIBE MICROFLOW Sales.ACT_Rc0` | not-built |
EOF
}

observed() {  # observed <pointer> -> the observed column of today's report
  P_PTR="\`$1\`" awk -F'\t' '$2==ENVIRON["P_PTR"] {print $4}' "$P"/docs/conformance/report-*.tsv 2>/dev/null | head -1
}

for layout in single two; do
  for eol in lf crlf; do
    setup "$layout" "$eol"
    ( cd "$P" && PROJECT_ROOT="$P" bash "$SUT" --quiet ) > "$WORK/out" 2>&1; rc=$?
    tag="[$layout/$eol]"
    if [ "$eol" = lf ]; then
      [ "$rc" = 0 ] && ok "$tag run exits 0" || bad "$tag run exit $rc" "$(tr '\n' ' ' < "$WORK/out" | cut -c1-300)"
      [ "$(observed /microflows/1)" = PRESENT ] && ok "$tag 1. doc with '(0 = …)' is PRESENT" \
        || bad "$tag 1. doc with '(0 = …)' read as $(observed /microflows/1) (the #470 false STALE)"
      [ "$(observed /navigation/0)" = PRESENT ] && ok "$tag 2. navigation with a not-found page is PRESENT" \
        || bad "$tag 2. navigation read as $(observed /navigation/0)"
      [ "$(observed /microflows/0)" = PRESENT ] && ok "$tag 3. unedited capture PRESENT" \
        || bad "$tag 3. unedited capture read as $(observed /microflows/0)"
      [ "$(observed /entities/0)" = ABSENT ] && ok "$tag 4. '(0 entities)' is ABSENT" \
        || bad "$tag 4. '(0 entities)' read as $(observed /entities/0)"
      [ "$(observed /workflows/0)" = ABSENT ] && ok "$tag 5. '(0 workflow group(s))' is ABSENT" \
        || bad "$tag 5. '(0 workflow group(s))' read as $(observed /workflows/0)"
      [ "$(observed /microflows/2)" = ABSENT ] && ok "$tag 6. Error + rc 1 is ABSENT" \
        || bad "$tag 6. missing element read as $(observed /microflows/2)"
      [ "$(observed /microflows/3)" = ABSENT ] && ok "$tag 7. Error line with rc 0 is ABSENT" \
        || bad "$tag 7. rc-0 Error read as $(observed /microflows/3)"
    else
      [ "$(observed /microflows/1)" = PRESENT ] && [ "$(observed /entities/0)" = ABSENT ] \
        && ok "$tag 8. CRLF: doc'd microflow PRESENT, empty set ABSENT" \
        || bad "$tag 8. CRLF misread" "mf=$(observed /microflows/1) empty=$(observed /entities/0)"
    fi
  done
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
