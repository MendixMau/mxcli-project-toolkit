#!/usr/bin/env bash
# Proves the skill-routing table actually reaches an agent, not just that it renders.
#
# render-routing.sh --check already proves the nine in-repo surfaces match the table. What it
# does NOT catch: two rows sharing a name (one silently shadows the other in agent:<x> views),
# a [[wikilink]] between skills pointing at a file that was never written, or — the part that
# actually matters — whether bin/lib/skill-routing.sh's routing_sync_claude_local() genuinely
# writes baseline rows into a CONSUMING PROJECT's CLAUDE.local.md, which is the only routing
# surface a project session auto-loads (see skill-routing.sh's own header comment on why that
# copy is the one that mattered).
#
# This is an instrument per skills-over-scripts.md test #2 (byte-identical, no agent needed) —
# it reports PASS/FAIL, it does not decide what a skill should say.
#
# Usage: bin/check-skill-routing.sh   (no args; always checks the current repo)
# Exit:  0 all checks pass · 1 any check fails

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/skill-routing.sh"

FAIL=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { FAIL=1; printf '  FAIL %s\n' "$1"; }

echo "== 1. group column is the closed set =="
if routing_validate_groups 2>/tmp/ckroute.groups; then
  ok "every row's group is one of the declared values"
else
  bad "invalid group(s):"; sed 's/^/       /' /tmp/ckroute.groups
fi
rm -f /tmp/ckroute.groups

echo "== 2. no two rows share a name =="
dups="$(routing_rows | awk -F'\t' '{print $1}' | sort | uniq -d)"
if [ -z "$dups" ]; then
  ok "all names unique"
else
  bad "duplicate name(s) — the later row silently shadows the earlier one in agent:<x> views:"
  printf '%s\n' "$dups" | sed 's/^/       /'
fi

echo "== 3. every routed path exists on disk =="
missing="$(routing_missing_paths "$ROOT")"
if [ -z "$missing" ]; then
  ok "no ghost rows"
else
  bad "routed but not on disk (fine for one commit while landing a new skill, not longer):"
  printf '%s\n' "$missing" | sed 's/^/       /'
fi

echo "== 4. no dangling [[wikilink]] between skills =="
dangling=0
while IFS= read -r -d '' f; do
  while IFS= read -r link; do
    [ -f "$ROOT/skills/$link.md" ] && continue
    dangling=1
    printf '  FAIL %s references [[%s]] — skills/%s.md does not exist\n' "${f#"$ROOT"/}" "$link" "$link"
  done < <(grep -oE '\[\[[a-zA-Z0-9_-]+\]\]' "$f" 2>/dev/null | tr -d '[]')
done < <(find "$ROOT/skills" -name '*.md' -print0)
[ "$dangling" -eq 0 ] && ok "no dangling cross-references" || FAIL=1

echo "== 5. the nine in-repo surfaces match the table =="
if "$SCRIPT_DIR/render-routing.sh" --check >/tmp/ckroute.render 2>&1; then
  ok "README/ROUTING.md/agent templates/gate-check.sh all in sync"
else
  bad "surfaces have drifted from the table — run bin/render-routing.sh:"
  sed 's/^/       /' /tmp/ckroute.render
fi
rm -f /tmp/ckroute.render

echo "== 6. baseline rows actually reach a consuming project's CLAUDE.local.md =="
SCRATCH="$(mktemp "${TMPDIR:-/tmp}/ckroute-cl.XXXXXX")"
printf '# CLAUDE.local.md\n\nSome pre-existing project content that must survive untouched.\n' > "$SCRATCH"
routing_sync_claude_local "$SCRATCH" "$ROOT" >/dev/null 2>&1 || true
sample="$(routing_rows | awk -F'\t' '$6=="baseline"{print $1; exit}')"
if [ -n "$sample" ] && grep -q "$sample" "$SCRATCH" && grep -q "pre-existing project content" "$SCRATCH"; then
  ok "a baseline row ($sample) landed in CLAUDE.local.md, and hand-written content survived"
else
  bad "baseline row '$sample' did not land in a synced CLAUDE.local.md, or clobbered existing content"
fi
rm -f "$SCRATCH"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "skill routing: all checks pass."
else
  echo "skill routing: at least one check failed — see FAIL lines above." >&2
fi
exit "$FAIL"
