#!/usr/bin/env bash
#
# coverage-check.sh — make BRD coverage mechanical instead of remembered.
#
# Flattens a BRD to one JSON Pointer per scalar leaf, extracts claimed pointers
# from a coverage ledger (two markdown tables: BUILDABLE and NON-BUILDABLE), and
# reports which leaves are CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or
# DOUBLE-CLAIMED.
#
# The ledger format and the pointer-cell grammar this script parses are defined
# by the build-plan method, which has NOT landed in the toolkit yet (it is a
# per-project doc today, promotion tracked as §3 of TOOLKIT-UPGRADE-PLAN.md).
# Everything needed to run the script is documented in this header on purpose —
# do not reintroduce a path reference to a file the toolkit does not ship.
#
# Usage: bin/coverage-check.sh [--summary] <brd.json> <ledger.md>
#
# Exit 0 only when UNCLAIMED, PHANTOM, DOUBLE-CLAIMED and COUNT-MISMATCH are
# all empty; 1 for findings; 2 for a FAULT (bad arguments, or a WRONG-SHAPE
# ledger — tables present, none of them in the pointer shape below).
#
# Bash + jq only. Written for macOS/BSD userland (no GNU-only flags).
# Read-only: never touches the Mendix model.

set -euo pipefail

CAP="${COVERAGE_CHECK_CAP:-40}"

usage() {
  echo "Usage: $0 [--summary] <brd.json> <ledger.md>" >&2
  exit 2
}

SUMMARY=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --summary) SUMMARY=1 ;;
    -h|--help) usage ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
  usage
fi

BRD="${POSITIONAL[0]}"
LEDGER="${POSITIONAL[1]}"

if ! command -v jq >/dev/null 2>&1; then
  echo "coverage-check.sh: jq is required but not found" >&2
  exit 2
fi

if [[ ! -f "$BRD" ]]; then
  echo "coverage-check.sh: BRD not found: $BRD" >&2
  exit 2
fi

if [[ ! -f "$LEDGER" ]]; then
  echo "coverage-check.sh: ledger not found: $LEDGER" >&2
  exit 2
fi

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/coverage-check.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

# ---------------------------------------------------------------------------
# 4.1 Leaf enumeration
# ---------------------------------------------------------------------------
# NOT `paths(scalars)`. In jq, `paths(f)` is `paths | select(getpath(.)|f)`, and
# only `false` and `null` are falsy — so every leaf whose VALUE is false or null
# was silently dropped from the enumeration. This checker exists to prove no
# requirement is invisible, and it could not see a whole value class: F013 lost
# 44 leaves, including all three `persistent` flags and both `allowedInUrl:false`
# flags — the two most security-relevant facts in the deep-link contract.
#
# Note the obvious-looking rewrite `[paths] | map(select(getpath(.)|...))` does
# NOT work: inside map(), `.` is the path array, so getpath has no document to
# index and jq errors with "Cannot index array with string".
#
# Empty objects/arrays are intentionally not leaves — they carry no requirement.
jq -r 'paths as $p
       | select(getpath($p) | type | IN("object","array") | not)
       | "/" + ($p | map(tostring) | join("/"))' "$BRD" \
  | sort -u > "$TMPDIR/leaves.txt"

LEAF_COUNT=$(wc -l < "$TMPDIR/leaves.txt" | tr -d ' ')

# ---------------------------------------------------------------------------
# 4.2 Claim extraction — parse the two ledger tables.
#
# A header row is identified by its first cell being literally "pointer"
# (case-insensitive). Its column count decides which table it is:
#   7 columns -> BUILDABLE     (pointer|type|title|slice|writeMode|acceptance|status)
#   3 columns -> NONBUILDABLE  (pointer|category|reason)
# The row immediately after a header is assumed to be the "---" separator
# and is always skipped. Any non-table line ends the current table.
# ---------------------------------------------------------------------------
awk '
# Strip ALL code-quote characters, not just leading/trailing ones. A ledger
# author writes a wildcard pointer with the count OUTSIDE the quoting, so
# end-anchored stripping leaves one mid-string, the pointer never matches a
# real leaf, and the row silently becomes PHANTOM. That happened on the first
# real ledger: 71 of 74 rows phantom, 0 claimed, while the generating agent
# reported perfect coverage from its own verifier. Two tools, one written
# contract, and they still disagreed on punctuation. Be liberal here.
# NOTE: no apostrophes in these comments — this whole block is inside a
# single-quoted awk program, and one apostrophe ends it.
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/[\140]/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function is_pipe_row(s,    t) {
  t = s
  gsub(/^[ \t]+|[ \t]+$/, "", t)
  return (t ~ /^\|.*\|$/)
}
BEGIN { mode = ""; skip_sep = 0 }
{
  line = $0
  if (!is_pipe_row(line)) {
    mode = ""
    skip_sep = 0
    next
  }
  t = line
  gsub(/^[ \t]+|[ \t]+$/, "", t)
  sub(/^\|/, "", t)
  sub(/\|[ \t]*$/, "", t)
  ncols = split(t, cells, "|")
  first = trim(cells[1])
  if (tolower(first) == "pointer") {
    if (ncols == 7) { mode = "BUILDABLE" }
    else if (ncols == 3) { mode = "NONBUILDABLE" }
    else { mode = "" }
    skip_sep = 1
    next
  }
  if (skip_sep) { skip_sep = 0; next }
  if (mode == "BUILDABLE" && ncols >= 7) {
    print mode "\t" trim(cells[1]) "\t" trim(cells[7])
  } else if (mode == "NONBUILDABLE" && ncols >= 3) {
    print mode "\t" trim(cells[1]) "\t" trim(cells[2]) "\t" trim(cells[3])
  }
}
' "$LEDGER" > "$TMPDIR/rows.tsv"

# ---------------------------------------------------------------------------
# WRONG-SHAPE ledger. A ledger written one row per MODEL ELEMENT
# (| Element | Kind | Status |) instead of one row per BRD POINTER parses to zero
# rows above, so every leaf came out UNCLAIMED — a finding that reads as
# "some work left" when the truth is "this ledger cannot be measured at all".
# Real case (#208): five module ledgers in that shape, reported as ordinary
# UNCLAIMED gaps for a whole build; once rewritten, the real gaps were a fraction
# of what had been shown. So: table rows present, none of them pointer rows -> FAULT.
# ---------------------------------------------------------------------------
TABLE_ROWS=$(awk '
  { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t) }
  t !~ /^\|.*\|$/ { prev = 0; next }
  t ~ /^\|[ \t:|-]+\|$/ { if (prev) n--; prev = 0; next }
  { n++; prev = 1 }
  END { print n + 0 }
' "$LEDGER")
PARSED_ROWS=$(grep -c . "$TMPDIR/rows.tsv" || true)
POINTER_ROWS=$(awk -F'\t' '$2 ~ /^[A-Za-z0-9_.:-]*\// { n++ } END { print n + 0 }' "$TMPDIR/rows.tsv")
if [[ "$TABLE_ROWS" -gt 0 && "$POINTER_ROWS" -eq 0 ]]; then
  echo "coverage-check: $BRD"
  echo "  ledger:        $LEDGER"
  echo "  FAULT: WRONG-SHAPE LEDGER (0 of $TABLE_ROWS table rows are BRD pointers; $PARSED_ROWS in a pointer table)"
  echo "  A ledger row claims one BRD leaf pointer, not one model element. Expected tables:"
  echo "    | pointer | type | title | slice | writeMode | acceptance | status |   (BUILDABLE)"
  echo "    | pointer | category | reason |                                       (NON-BUILDABLE)"
  echo "  with pointer cells like /domainEntities/0/name or /pages/* (12)."
  echo "  This ledger cannot be measured; its UNCLAIMED count would be meaningless."
  exit 2
fi

: > "$TMPDIR/claims_buildable_raw.txt"
: > "$TMPDIR/claims_ledgered_raw.txt"
: > "$TMPDIR/rejected_bad_ledger_entry.txt"

while IFS=$'\t' read -r mode pointer c2 c3; do
  [[ -z "$pointer" ]] && continue
  if [[ "$mode" == "BUILDABLE" ]]; then
    # c2 here is the "status" column (7th field) — no gate requirement on it,
    # a buildable row just needs a pointer.
    echo "$pointer" >> "$TMPDIR/claims_buildable_raw.txt"
  elif [[ "$mode" == "NONBUILDABLE" ]]; then
    category="$c2"
    reason="$c3"
    if [[ -z "$category" || -z "$reason" ]]; then
      # §4.4: a ledger entry with no reason is UNCLAIMED with extra steps.
      echo "$pointer" >> "$TMPDIR/rejected_bad_ledger_entry.txt"
      continue
    fi
    echo "$pointer" >> "$TMPDIR/claims_ledgered_raw.txt"
  fi
done < "$TMPDIR/rows.tsv"

# ---------------------------------------------------------------------------
# Expand wildcard claims (`/a/b/* (N)`) against the real leaf list, and
# validate bare pointers exist. Emits, per raw claim list, a flat file of
# expanded leaf pointers (subset of leaves.txt for wildcards that matched)
# plus separate phantom-wildcard / count-mismatch records.
# ---------------------------------------------------------------------------
: > "$TMPDIR/count_mismatch.txt"
: > "$TMPDIR/phantom_wildcard.txt"
: > "$TMPDIR/malformed_wildcard.txt"

# A ledger pointer CELL may take three shapes. The first is what the contract
# specified; the other two are what a real generating agent actually wrote, and
# rejecting them just produces false PHANTOMs:
#
#   /a/b/c                              a single literal pointer
#   /a/b/*  (N)                         a wildcard, with its expected count
#   /a/b/x, /a/b/y, /a/b/z  (3)         a comma-separated list, with its count
#
# The trailing (N) applies to the WHOLE cell, wildcard or not. Keeping the count
# mandatory is the point: it is what makes an added 8th grid column FAIL rather
# than be silently absorbed.
# A pointer may carry its BRD id instead of a leading slash: F003/domainEntities/* .
# The build-plan `claims:` convention (skills/brd-to-build-plan.md Step 5b) writes it
# that way, but leaves are enumerated as /domainEntities/..., so until this a CORRECT
# prefixed claim was PHANTOM and a wrong one looked no different (#209). Resolution:
#   own id (file name, its F001 part before the first "-", or the BRD .id) -> /rest
#   another BRD in the same directory                                      -> skipped,
#       counted as OTHER-BRD (it is measured when that BRD is)
#   anything else                                                          -> PHANTOM
BRD_DIR="$(dirname "$BRD")"
BRD_BASE="$(basename "$BRD")"; BRD_BASE="${BRD_BASE%.json}"; BRD_BASE="${BRD_BASE%.brd}"
BRD_IDS=" $BRD_BASE ${BRD_BASE%%-*} $(jq -r '.id? // empty | strings' "$BRD" 2>/dev/null || true) "
: > "$TMPDIR/other_brd.txt"
brd_is_self() { [[ "$BRD_IDS" == *" $1 "* ]]; }
brd_is_other() {
  local f
  for f in "$BRD_DIR/$1.brd.json" "$BRD_DIR/$1"-*.brd.json; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}

expand_claims() {
  local rawfile="$1" outfile="$2"
  : > "$outfile"
  while IFS= read -r cell; do
    [[ -z "$cell" ]] && continue

    local declared="" body="$cell"
    if [[ "$cell" =~ ^(.*[^[:space:]])[[:space:]]*\(([0-9]+)\)[[:space:]]*$ ]]; then
      body="${BASH_REMATCH[1]}"
      declared="${BASH_REMATCH[2]}"
    fi

    # split the cell on commas
    local -a tokens=()
    local IFS_SAVE="$IFS"; IFS=','
    read -r -a tokens <<< "$body"
    IFS="$IFS_SAVE"

    local produced=0 other=0
    local tok orig
    for tok in "${tokens[@]}"; do
      tok="$(printf '%s' "$tok" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z "$tok" ]] && continue

      # A count may also be attached to an INDIVIDUAL token inside a comma
      # list, not just to the cell as a whole:
      #    /a/b, /c/d/* (4), /e/f  (12)
      #               ^token count      ^cell count
      # Strip the token-level count here; the cell-level one was already taken
      # off above. Without this the token still ends in ")" , never matches the
      # wildcard test, and the row is reported PHANTOM while its leaves show up
      # as UNCLAIMED — which is exactly how it presented on the first real ledger.
      local tok_declared=""
      if [[ "$tok" =~ ^(.*[^[:space:]])[[:space:]]*\(([0-9]+)\)$ ]]; then
        tok="${BASH_REMATCH[1]}"
        tok_declared="${BASH_REMATCH[2]}"
      fi

      orig="$tok"
      if [[ "$tok" != /* && "$tok" == */* ]]; then
        if brd_is_self "${tok%%/*}"; then
          tok="/${tok#*/}"
        elif brd_is_other "${tok%%/*}"; then
          echo "$orig" >> "$TMPDIR/other_brd.txt"
          other=1
          continue
        fi
      fi

      if [[ "$tok" == */\* ]]; then
        local prefix="${tok%/\*}" esc matches actual=0
        esc=$(printf '%s' "$prefix" | sed -e 's/[.[\*^$]/\\&/g')
        matches=$(grep -E "^${esc}/" "$TMPDIR/leaves.txt" || true)
        [[ -n "$matches" ]] && actual=$(printf '%s\n' "$matches" | grep -c .)
        if [[ "$actual" -eq 0 ]]; then
          echo "$orig" >> "$TMPDIR/phantom_wildcard.txt"
        else
          printf '%s\n' "$matches" >> "$outfile"
          produced=$(( produced + actual ))
        fi
      elif [[ "$tok" == *"*"* ]]; then
        echo "$orig" >> "$TMPDIR/malformed_wildcard.txt"
      else
        if grep -qxF "$tok" "$TMPDIR/leaves.txt"; then
          echo "$tok" >> "$outfile"
          produced=$(( produced + 1 ))
        else
          echo "$orig" >> "$TMPDIR/phantom_wildcard.txt"
        fi
      fi
    done

    # A cell that also names another BRD has a count spanning both; it cannot be checked here.
    if [[ -n "$declared" && "$other" -eq 0 && "$produced" -gt 0 && "$produced" -ne "$declared" ]]; then
      echo "$cell (declared $declared, actual $produced)" >> "$TMPDIR/count_mismatch.txt"
    fi
  done < "$rawfile"
}

expand_claims "$TMPDIR/claims_buildable_raw.txt" "$TMPDIR/claims_buildable.txt"
expand_claims "$TMPDIR/claims_ledgered_raw.txt" "$TMPDIR/claims_ledgered.txt"

cat "$TMPDIR/claims_buildable.txt" "$TMPDIR/claims_ledgered.txt" > "$TMPDIR/claims_all.txt"

# ---------------------------------------------------------------------------
# 4.3 The verdicts
# ---------------------------------------------------------------------------
sort -u "$TMPDIR/claims_all.txt" > "$TMPDIR/claims_sorted_u.txt"

comm -23 "$TMPDIR/leaves.txt" "$TMPDIR/claims_sorted_u.txt" > "$TMPDIR/unclaimed.txt"
comm -13 "$TMPDIR/leaves.txt" "$TMPDIR/claims_sorted_u.txt" > "$TMPDIR/phantom_bare.txt"
sort "$TMPDIR/claims_all.txt" | uniq -d > "$TMPDIR/double_claimed.txt"

# combine bare phantoms with wildcard phantoms and malformed wildcards
cat "$TMPDIR/phantom_bare.txt" "$TMPDIR/phantom_wildcard.txt" "$TMPDIR/malformed_wildcard.txt" \
  | sort -u > "$TMPDIR/phantom_all.txt"

# UNCLAIMED must also exclude leaves ledgered under a rejected (reasonless) entry —
# those are already absent from claims_sorted_u.txt, so they correctly show as UNCLAIMED.

# CLAIMED / LEDGERED counts only count claims that actually resolve to a real
# leaf; ones that do not are reported under PHANTOM instead.
comm -12 "$TMPDIR/leaves.txt" <(sort -u "$TMPDIR/claims_buildable.txt") > "$TMPDIR/claims_buildable_valid.txt"
comm -12 "$TMPDIR/leaves.txt" <(sort -u "$TMPDIR/claims_ledgered.txt") > "$TMPDIR/claims_ledgered_valid.txt"
CLAIMED_COUNT=$(grep -c . "$TMPDIR/claims_buildable_valid.txt" || true)
LEDGERED_COUNT=$(grep -c . "$TMPDIR/claims_ledgered_valid.txt" || true)
UNCLAIMED_COUNT=$(grep -c . "$TMPDIR/unclaimed.txt" || true)
PHANTOM_COUNT=$(grep -c . "$TMPDIR/phantom_all.txt" || true)
DOUBLE_COUNT=$(grep -c . "$TMPDIR/double_claimed.txt" || true)
MISMATCH_COUNT=$(grep -c . "$TMPDIR/count_mismatch.txt" || true)
REJECTED_LEDGER_COUNT=$(grep -c . "$TMPDIR/rejected_bad_ledger_entry.txt" || true)
OTHER_BRD_COUNT=$(grep -c . "$TMPDIR/other_brd.txt" || true)

print_capped() {
  local file="$1" total="$2"
  local shown=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    shown=$((shown + 1))
    if [[ "$shown" -le "$CAP" ]]; then
      echo "    $line"
    fi
  done < "$file"
  if [[ "$total" -gt "$CAP" ]]; then
    echo "    ... ($((total - CAP)) more, capped at $CAP)"
  fi
}

echo "coverage-check: $BRD"
echo "  ledger:        $LEDGER"
echo "  leaves:        $LEAF_COUNT"
echo "  CLAIMED:       $CLAIMED_COUNT"
echo "  LEDGERED:      $LEDGERED_COUNT"
echo "  UNCLAIMED:     $UNCLAIMED_COUNT"
echo "  PHANTOM:       $PHANTOM_COUNT"
echo "  DOUBLE-CLAIMED:$DOUBLE_COUNT"
echo "  COUNT-MISMATCH:$MISMATCH_COUNT"
if [[ "$REJECTED_LEDGER_COUNT" -gt 0 ]]; then
  echo "  REJECTED (ledger entry missing category/reason): $REJECTED_LEDGER_COUNT"
fi
if [[ "$OTHER_BRD_COUNT" -gt 0 ]]; then
  echo "  OTHER-BRD:     $OTHER_BRD_COUNT (claims naming another BRD; measured there, not here)"
fi

if [[ "$SUMMARY" -eq 0 ]]; then
  if [[ "$UNCLAIMED_COUNT" -gt 0 ]]; then
    echo "  -- UNCLAIMED pointers --"
    print_capped "$TMPDIR/unclaimed.txt" "$UNCLAIMED_COUNT"
  fi
  if [[ "$PHANTOM_COUNT" -gt 0 ]]; then
    echo "  -- PHANTOM pointers --"
    print_capped "$TMPDIR/phantom_all.txt" "$PHANTOM_COUNT"
  fi
  if [[ "$DOUBLE_COUNT" -gt 0 ]]; then
    echo "  -- DOUBLE-CLAIMED pointers --"
    print_capped "$TMPDIR/double_claimed.txt" "$DOUBLE_COUNT"
  fi
  if [[ "$MISMATCH_COUNT" -gt 0 ]]; then
    echo "  -- COUNT-MISMATCH wildcards --"
    print_capped "$TMPDIR/count_mismatch.txt" "$MISMATCH_COUNT"
  fi
  if [[ "$REJECTED_LEDGER_COUNT" -gt 0 ]]; then
    echo "  -- REJECTED ledger entries (missing category/reason) --"
    print_capped "$TMPDIR/rejected_bad_ledger_entry.txt" "$REJECTED_LEDGER_COUNT"
  fi
fi

if [[ "$UNCLAIMED_COUNT" -gt 0 || "$PHANTOM_COUNT" -gt 0 || "$DOUBLE_COUNT" -gt 0 || "$MISMATCH_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
