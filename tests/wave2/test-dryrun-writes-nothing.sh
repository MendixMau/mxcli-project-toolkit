#!/usr/bin/env bash
# --dry-run must write NOTHING. Not "nothing in the pass I was thinking about" — nothing.
#
# WHY THIS EXISTS, and why it checksums the whole tree instead of asserting per feature:
# --dry-run was originally enforced at each write site. Sections 1 and 4 honoured it; sections
# 2, 2b and 2c did not. The fixture that "proved" it worked ran against a freshly-initialised
# project where those sections had nothing to do, so it passed for a reason unrelated to
# --dry-run. Pointed at eight REAL projects, the same flag printed "(--dry-run: nothing will be
# written)" and created 11 agent files across 5 of them.
#
# The lesson is about the shape of the test, not the bug: a promise of "no writes" can only be
# tested by hashing everything before and after. Any assertion narrower than that is a list of
# the places you already remembered, which is exactly the set that was never broken.
set -uo pipefail

SYNC="${1:?usage: test-dryrun-writes-nothing.sh /path/to/sync-project.sh}"
TK="$(cd "$(dirname "$SYNC")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dryrun.XXXXXX")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# Hash every file's path AND content, plus the exec bit, so a chmod or a new file both show up.
treehash() { (cd "$1" && find . -type f -not -path './.git/*' | sort | while read -r f; do
                printf '%s %s %s\n' "$f" "$(shasum < "$f" | cut -d' ' -f1)" "$([ -x "$f" ] && echo x || echo -)"
              done | shasum | cut -d' ' -f1); }

# A project that gives EVERY pass something to do. A pristine project is the case that hid the
# bug — each of these degradations targets a different write site.
mkdegraded() {
  d="$WORK/$1"; mkdir -p "$d"
  "$TK/bin/init-project.sh" "$d" >/dev/null 2>&1 || return 1
  printf '\n# local hardening\n' >> "$d/bin/exec.sh"          # §4 drifted script
  rm -f "$d/bin/save-sp.sh"                                    # §4 missing script
  chmod -x "$d/bin/snapshot-mpr.sh" 2>/dev/null                # §4 lost exec bit
  rm -f "$d/.claude/agents/architect-agent.md"                 # §2 missing agent
  mkdir -p "$d/.claude/agents"
  printf 'STUB GENERATED\n{{PLACEHOLDER}}\nold stub body\n' > "$d/.claude/agents/ba-agent.md"  # §2 stale stub
  grep -v 'Session-start ritual' "$d/CLAUDE.local.md" > "$d/CLAUDE.local.md.t" 2>/dev/null \
    && mv "$d/CLAUDE.local.md.t" "$d/CLAUDE.local.md"          # §2b missing ritual
  grep -v 'Toolkit commit' "$d/PROJECT.md" > "$d/PROJECT.md.t" 2>/dev/null \
    && mv "$d/PROJECT.md.t" "$d/PROJECT.md"                    # §2b missing commit line
  echo "$d"
}

echo "== T1: --dry-run against a project where EVERY pass has work to do =="
P="$(mkdegraded t1)" || { echo "  (could not scaffold — init-project.sh failed)"; exit 1; }
BEFORE="$(treehash "$P")"
OUT="$("$SYNC" "$P" --dry-run 2>&1)"
AFTER="$(treehash "$P")"
if [ "$BEFORE" = "$AFTER" ]; then
  ok "tree byte-identical after --dry-run"
else
  bad "--dry-run MODIFIED the tree"
  (cd "$P" && find . -type f -not -path './.git/*' -mmin -1 | head -8 | sed 's/^/       touched: /')
fi

echo "== T2: it still REPORTS the work, and marks it as hypothetical =="
printf '%s' "$OUT" | grep -q 'dry-run' \
  && ok "output is labelled as a dry run" || bad "no dry-run label in output"
if printf '%s' "$OUT" | grep -qE '^(Created|Refreshed|Installed):'; then
  bad "reports a completed action in the past tense while writing nothing"
else
  ok "no bare past-tense action claims"
fi
printf '%s' "$OUT" | grep -qi 'agent' \
  && ok "still tells you the agent work it would do" || bad "silent about agent work"

echo "== T3: a REAL run does the work the dry run described =="
P2="$(mkdegraded t2)"
B2="$(treehash "$P2")"
"$SYNC" "$P2" >/dev/null 2>&1
A2="$(treehash "$P2")"
[ "$B2" != "$A2" ] && ok "real run changed the tree" || bad "real run changed nothing — dry-run proves nothing"

echo "== T4: a real run is idempotent =="
A3="$(treehash "$P2")"
"$SYNC" "$P2" >/dev/null 2>&1
A4="$(treehash "$P2")"
[ "$A3" = "$A4" ] && ok "second real run changed nothing" || bad "sync is not idempotent"

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
