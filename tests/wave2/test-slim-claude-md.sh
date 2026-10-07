#!/usr/bin/env bash
# Fixture for bin/lib/slim-claude-md.sh — moving a pre-v0.22 `mxcli init` CLAUDE.md's reference
# sections out of the always-loaded context.
#
# Usage: bash test-slim-claude-md.sh [path-to-sync-project.sh]
#
# The subject is sync-project.sh, its caller (init-project.sh is the other), because the suite
# runner resolves subjects under bin/; the lib is located next to it, at lib/slim-claude-md.sh.
#
# Golden input (field-proof rule 1 — captured, never hand-written), both in
# fixtures/slim-claude-md/: `mxcli init` output from v0.21.0 built at its tag (the fat shape),
# and from a v0.25 dev build (the slim shape with the mxcli:begin marker, which must be left alone).

set -uo pipefail

SYNC="${1:-}"
if [ -z "$SYNC" ]; then
  SYNC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/sync-project.sh"
fi
SUT="$(dirname "$SYNC")/lib/slim-claude-md.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT (pre-change baseline has no slimmer)"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/slim-claude-md"
FAT="$FIX/mxcli-v0.21.0-init.CLAUDE.md"
SLIM="$FIX/mxcli-v0.25-dev-init.CLAUDE.md"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/slimtest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Run the subject in a subshell so its globals never leak between cases.
run() { ( . "$SUT"; slim_claude_md "$1" ); }
h2s() { grep '^## ' "$1" | tr '\n' '|'; }

# --- 1. The fat capture is slimmed to the expected section set -----------------------------
P="$TMP/fat"; mkdir -p "$P"; cp "$FAT" "$P/CLAUDE.md"
out="$(run "$P")"; rc=$?
[ "$rc" -eq 0 ] && ok "fat v0.21 file: slim returns 0" || bad "fat v0.21 file: slim returned $rc" "$out"
want='## Project Brain — read this first|## Communication Style|## Important: mxcli Location|## Reference moved out of the always-loaded context|## IMPORTANT: Before Writing MDL Scripts or Working with Data|## Script Validation (mxcli check)|## MDL Syntax Quick Reference|'
got="$(h2s "$P/CLAUDE.md")"
[ "$got" = "$want" ] && ok "kept exactly the bench-proven sections, in order" || bad "unexpected section set" "$got"
before="$(wc -c < "$FAT" | tr -d ' ')"; after="$(wc -c < "$P/CLAUDE.md" | tr -d ' ')"
[ "$before" -eq 27656 ] && ok "golden input is the captured 27656 bytes" || bad "golden input changed size" "$before"
[ "$after" -lt 10000 ] && ok "CLAUDE.md is under 10k bytes after ($after)" || bad "CLAUDE.md still $after bytes"
printf '%s' "$out" | grep -q "Slimmed: CLAUDE.md $before → $after bytes" && ok "reports the before/after size" || bad "report line missing" "$out"

# --- 2. Nothing is lost: kept + moved reproduce every original line ------------------------
REF="$P/docs/mxcli-reference.md"
[ -f "$REF" ] && ok "reference file written to docs/" || bad "no docs/mxcli-reference.md"
cmp -s "$FAT" "$P/.mxtk-backup/CLAUDE.md.pre-slim" && ok "byte-identical backup in .mxtk-backup/" || bad "backup missing or altered"
missing=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qxF -- "$line" "$P/CLAUDE.md" || grep -qxF -- "$line" "$REF" || missing=$((missing+1))
done < "$FAT"
[ "$missing" -eq 0 ] && ok "every original line is in CLAUDE.md or the reference" || bad "$missing original line(s) in neither file"
grep -qx '## MDL Commands by Domain' "$REF" && ok "the command tables are in the reference" || bad "command tables not in the reference"

# --- 3. Idempotent ---------------------------------------------------------------------------
cp "$P/CLAUDE.md" "$TMP/after1"
out="$(run "$P")"; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$P/CLAUDE.md" "$TMP/after1" && [ -z "$out" ] \
  && ok "second run is a silent no-op" || bad "second run changed something (rc=$rc)" "$out"

# --- 4. A current mxcli file (marker present) is never touched -------------------------------
P="$TMP/slim"; mkdir -p "$P"; cp "$SLIM" "$P/CLAUDE.md"
out="$(run "$P")"; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$SLIM" "$P/CLAUDE.md" && [ ! -e "$P/docs" ] \
  && ok "v0.25 file with mxcli:begin marker left alone" || bad "v0.25 file was touched (rc=$rc)" "$out"

# A fat file that has since been wrapped in the marker is mxcli's to manage, not ours.
P="$TMP/marked"; mkdir -p "$P"; { echo '<!-- mxcli:begin -->'; cat "$FAT"; } > "$P/CLAUDE.md"
cp "$P/CLAUDE.md" "$TMP/marked.orig"
run "$P" >/dev/null; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$TMP/marked.orig" "$P/CLAUDE.md" && ok "marker wins over the signature heading" || bad "marked fat file was slimmed"

# --- 5. Off switch ---------------------------------------------------------------------------
P="$TMP/off"; mkdir -p "$P"; cp "$FAT" "$P/CLAUDE.md"
( export MXTK_SLIM_CLAUDE_MD=off; . "$SUT"; slim_claude_md "$P" ) >/dev/null; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$FAT" "$P/CLAUDE.md" && ok "MXTK_SLIM_CLAUDE_MD=off leaves it alone" || bad "off switch ignored (rc=$rc)"

# --- 6. A section the project added survives, even with the same name inside a fence -------
P="$TMP/added"; mkdir -p "$P"
{ cat "$FAT"; printf '\n## mxcli-project-toolkit Integration\n\nkeep me\n\n```\n## Linting\n```\n'; } > "$P/CLAUDE.md"
run "$P" >/dev/null
grep -qx '## mxcli-project-toolkit Integration' "$P/CLAUDE.md" && grep -qx 'keep me' "$P/CLAUDE.md" \
  && ok "project-added section kept" || bad "project-added section lost"
[ "$(grep -cx '## Linting' "$P/CLAUDE.md")" -eq 1 ] && ok "a heading inside a code fence is not treated as a section" \
  || bad "fenced '## Linting' handled as a heading"

# --- 7. No CLAUDE.md at all ------------------------------------------------------------------
P="$TMP/none"; mkdir -p "$P"
run "$P" >/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$P/CLAUDE.md" ] && ok "no CLAUDE.md: nothing created" || bad "created something without a CLAUDE.md"

echo ""
TOTAL=$((PASS+FAIL))
echo "SCORE: $PASS/$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
