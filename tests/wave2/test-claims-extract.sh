#!/usr/bin/env bash
# Fixture for project-bin/_claims.sh (issue #74: build-plan `claims:` blocks inside fences,
# with a `(note)` suffix, or indented, were silently ignored by coverage-preflight.sh's own
# inline extractor).
#
# Takes the SUBJECT UNDER TEST as $1 (a path to _claims.sh), matching the other wave2 fixtures.
#
# Two independent inputs:
#
#   1. A REAL golden build plan — never hand-written, per CLAUDE.md's field-proof rule ("Golden
#      input is captured, never hand-written"). It is a workflow-migration project's build plan
#      (MendixMau), scrubbed of client-identifying content. It is dropped in separately at
#      tests/wave2/fixtures/build-plan-claims-real.md and is NOT part of this commit; set
#      CLAIMS_GOLDEN=<path> to point at a local copy for development. Its absence is not a
#      fixture failure — this SKIPs cleanly (exit 0) so CI, which never receives the golden
#      file, is never blocked on a fixture it cannot run.
#   2. A small SYNTHETIC section, hand-written here and clearly labelled as such, covering three
#      shapes the golden file happens not to use: a plain unfenced block, the `claims: (note)`
#      form, and leading-slash pointers. This supplements the real capture, it never substitutes
#      for it — see (1).
#
# Expected counts against the golden file were derived by running project-bin/_claims.sh against
# the real capture and reading the numbers off, not invented: 33 valid pointers, 4 unparsed
# lines, 0 empty blocks, every one of the 33 in "fenced" form (this file is exactly the shape
# issue #74 was filed about — a bare ``` fence with `claims:` as its first line), across 6
# `claims:` blocks (one per build phase) with per-phase pointer counts 9/9/6/3/5/1, referencing
# 5 distinct BRDs.
#
# No row text, module name, or app name from the golden file is reproduced anywhere below --
# only counts, phase numbers, and the BRD-prefixed pointer paths themselves. An entity name
# inside a pointer (e.g. "Dashboard") is fine; it is the file's own header/app name, and the
# free-text "row" cells that echo mxcli commands against that app, that must never be repeated.

set -uo pipefail

SUT="${1:-}"
if [ -z "$SUT" ]; then
  SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/_claims.sh"
fi
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi

GOLDEN="${CLAIMS_GOLDEN:-}"
if [ -z "$GOLDEN" ]; then
  GOLDEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/build-plan-claims-real.md"
fi
if [ ! -f "$GOLDEN" ]; then
  echo "SKIP: fixture missing — no golden build plan at $GOLDEN"
  echo "      drop a real, scrubbed build plan there, or set CLAIMS_GOLDEN=<path> for local dev"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/claimstest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
. "$SUT"

echo "== project-bin/_claims.sh (issue #74) =="

# ---------------------------------------------------------------------------
# Regression control: master's OLD extract_claims (project-bin/coverage-preflight.sh, before
# this change), copied verbatim, run against the same real file. This is the "before" half of
# the field-proof: it must fail, or the bug this fixture exists to catch is not reproduced.
# ---------------------------------------------------------------------------
echo "-- before: master's extract_claims on the real golden plan --"
old_extract_claims() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*claims:[ \t]*$/ { inblock = 1; next }
    /^[ \t]*claims:[ \t]*\// {
      line = $0; sub(/^[ \t]*claims:[ \t]*/, "", line)
      print row "\t" trim(line); inblock = 1; next
    }
    {
      if (inblock) {
        if ($0 ~ /^[ \t]+\//) { print row "\t" trim($0); next }
        inblock = 0
      }
      if (trim($0) != "") { row = trim($0) }
    }
  ' "$@"
}
OLD_COUNT="$(old_extract_claims "$GOLDEN" | grep -c . || true)"; : "${OLD_COUNT:=0}"
if [ "$OLD_COUNT" -eq 0 ]; then
  ok "master's extract_claims returns 0 pointers on the real plan (the bug, reproduced)"
else
  bad "master's extract_claims returns 0 pointers on the real plan (the bug, reproduced)" "$OLD_COUNT"
fi

# ---------------------------------------------------------------------------
# After: the new extractor on the same real file.
# ---------------------------------------------------------------------------
echo "-- after: mxtk_extract_claims_tsv on the real golden plan --"
OUT="$TMP/golden.tsv"
DIAG="$TMP/golden.diag"
mxtk_extract_claims_tsv "$GOLDEN" 2>"$DIAG" >"$OUT"

N_PTR=$(grep -c . "$OUT" 2>/dev/null || true); : "${N_PTR:=0}"
N_UNPARSED=$(grep -c '^claims-line-unparsed' "$DIAG" 2>/dev/null || true); : "${N_UNPARSED:=0}"
N_EMPTY=$(grep -c '^claims-block-empty' "$DIAG" 2>/dev/null || true); : "${N_EMPTY:=0}"

[ "$N_PTR" -eq 33 ] && ok "33 valid pointers extracted" || bad "33 valid pointers extracted" "$N_PTR"
[ "$N_UNPARSED" -eq 4 ] && ok "4 unparsed lines reported on stderr" || bad "4 unparsed lines reported on stderr" "$N_UNPARSED"
[ "$N_EMPTY" -eq 0 ] && ok "0 empty-block diagnostics" || bad "0 empty-block diagnostics" "$N_EMPTY"

N_FENCED=$(awk -F'\t' '$8=="fenced"' "$OUT" | grep -c . || true); : "${N_FENCED:=0}"
if [ "$N_FENCED" -eq 33 ]; then
  ok "all 33 pointers report form=fenced (this is the exact issue #74 shape)"
else
  bad "all 33 pointers report form=fenced (this is the exact issue #74 shape)" "$N_FENCED"
fi

# Per-phase pointer counts — one claims block per build phase in this file.
for pc in 1:9 2:9 3:6 4:3 5:5 6:1; do
  ph="${pc%%:*}"; want="${pc##*:}"
  got=$(awk -F'\t' -v p="$ph" '$3==p' "$OUT" | grep -c . || true); : "${got:=0}"
  if [ "$got" -eq "$want" ]; then
    ok "phase $ph carries $want pointer(s)"
  else
    bad "phase $ph carries $want pointer(s)" "$got"
  fi
done

N_BRD=$(cut -f7 "$OUT" | sort -u | grep -c . || true); : "${N_BRD:=0}"
if [ "$N_BRD" -eq 5 ]; then
  ok "5 distinct BRDs referenced across the plan"
else
  bad "5 distinct BRDs referenced across the plan" "$N_BRD"
fi

# ---------------------------------------------------------------------------
# SYNTHETIC section — hand-written, clearly labelled, not a real build plan. Covers three
# shapes the real golden file does not happen to use: a plain unfenced block, the
# `claims: (note)` form, and leading-slash pointers with a parsed wildcard count.
# ---------------------------------------------------------------------------
echo "-- synthetic: shapes not present in the golden file (hand-written, labelled) --"
SYN="$TMP/synthetic.md"
cat >"$SYN" <<'EOF'
# SYNTHETIC fixture — hand-written for this test, not a real build plan.

## Phase 1

1 · plain unfenced block, leading-slash pointers
claims:
  /pages/0/buildComposition/rowClick
  /pages/0/buildComposition/gridColumns/* (4)

2 · claims: (note) form, leading-slash pointer
claims: (existing widget swap only, no new leaves)
  /pages/1/buildComposition/footer
EOF

SYN_OUT="$TMP/synthetic.tsv"
SYN_DIAG="$TMP/synthetic.diag"
mxtk_extract_claims_tsv "$SYN" 2>"$SYN_DIAG" >"$SYN_OUT"

SYN_N=$(grep -c . "$SYN_OUT" 2>/dev/null || true); : "${SYN_N:=0}"
if [ "$SYN_N" -eq 3 ]; then
  ok "synthetic: 3 pointers across the plain+note blocks"
else
  bad "synthetic: 3 pointers across the plain+note blocks" "$SYN_N"
fi

SYN_FORMS="$(cut -f8 "$SYN_OUT" | sort -u | tr '\n' ',')"
if [ "$SYN_FORMS" = "note,plain," ]; then
  ok "synthetic: forms present are exactly plain and note"
else
  bad "synthetic: forms present are exactly plain and note" "$SYN_FORMS"
fi

SYN_COUNT_CELL=$(awk -F'\t' '$5=="/pages/0/buildComposition/gridColumns/*"{print $6}' "$SYN_OUT")
if [ "$SYN_COUNT_CELL" = "4" ]; then
  ok "synthetic: wildcard count (4) parsed off the leading-slash pointer"
else
  bad "synthetic: wildcard count (4) parsed off the leading-slash pointer" "$SYN_COUNT_CELL"
fi

SYN_DIAG_N=$(grep -c . "$SYN_DIAG" 2>/dev/null || true); : "${SYN_DIAG_N:=0}"
if [ "$SYN_DIAG_N" -eq 0 ]; then
  ok "synthetic: no diagnostics — every synthetic line parsed"
else
  bad "synthetic: no diagnostics — every synthetic line parsed" "$SYN_DIAG_N"
fi

echo ""
TOTAL=$((PASS + FAIL))
echo "SCORE: $PASS/$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
