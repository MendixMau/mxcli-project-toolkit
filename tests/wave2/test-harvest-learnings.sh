#!/usr/bin/env bash
# test-harvest-learnings.sh — pin bin/harvest-learnings.sh section 3's direction check.
#
# Field run 2026-09-14, 10 projects, 115 differing installed scripts: 84 were byte-identical to
# some OLDER shipped version of the toolkit's own project-bin/X (STALE — a stale install, fix is
# a sync, nothing to harvest) and 31 were genuine local edits (LOCAL-FIX — a fix that never
# traveled, kept as a diff). Before this fixture the harvester wrote every differing script as
# "direction undetermined" with a full diff, so 68k of the 79k words it wrote were stale diffs
# nobody needed to read. What is pinned here, in the order a triager hits it:
#
#   T1  a project script byte-identical to an OLDER historical commit of the shipped file (taken
#       from the toolkit's OWN real git history, never hand-written) renders as ONE line —
#       "STALE: identical to shipped <sha> (<date>); fix: ...--upgrade-bin <script>" — with no
#       diff block at all.
#   T2  a genuinely edited project script (never matching any commit in the toolkit's history)
#       still gets its diff block, but headed "LOCAL-FIX" and naming the closest historical base.
#   T3  the draft's closing summary line counts stale vs. local-fix items correctly when both
#       verdicts land in the same run.
#   T4  a toolkit worktree with NO .git (a tarball drop, an export with no history) falls back to
#       the original "direction is undetermined" wording for every item — never crashes, never
#       guesses a verdict it cannot support. Testable directly: TOOLKIT_ROOT is derived from the
#       invoked script's own location (dirname "$0"/..), so copying just bin/ + project-bin/ into
#       a git-free directory and invoking the copy from there IS a toolkit worktree with no
#       history — no env override needed.
#
# Usage: bash tests/wave2/test-harvest-learnings.sh /path/to/harvest-learnings.sh

set -uo pipefail

HARVEST="${1:?usage: bash tests/wave2/test-harvest-learnings.sh /path/to/harvest-learnings.sh}"
case "$HARVEST" in /*) ;; *) HARVEST="$PWD/$HARVEST" ;; esac
TOOLKIT="$(cd "$(dirname "$HARVEST")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harvest-fixture.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAMP="$(date +%Y-%m-%d)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# ---------------------------------------------------------------------------------------------
# T1 + T2 + T3: real toolkit worktree, one STALE item and one LOCAL-FIX item in the same project,
# so the summary line's counts are pinned against a run that actually mixes both verdicts.
#
# Run against an isolated LOCAL CLONE of the toolkit, never against $TOOLKIT itself: the harvester
# hardcodes its inbox at <toolkit-root>/contrib/inbox, and a peer session owns
# $TOOLKIT/contrib/inbox right now (mid-edit, untouchable). A clone gets full real git history
# (`git clone` of a local path copies committed objects, hardlinked when possible — no network,
# nothing written back to $TOOLKIT) plus its own, disposable contrib/inbox under $WORK. The
# harvester script itself is copied in AFTER cloning so the fixture always exercises the change
# under test, not whatever committed version the clone's HEAD happens to carry.
# ---------------------------------------------------------------------------------------------
echo "== T1/T2/T3: STALE (byte-identical to real history) vs. LOCAL-FIX (genuine edit) =="

CLONE="$WORK/toolkit-clone"
if ! git clone -q --no-hardlinks "$TOOLKIT" "$CLONE" >/dev/null 2>&1; then
  bad "control: could not clone the toolkit worktree into an isolated copy — fixture cannot run"
else
  ok "control: isolated local clone of the toolkit created (never touches \$TOOLKIT/contrib/inbox)"
  cp "$HARVEST" "$CLONE/bin/harvest-learnings.sh"
  chmod +x "$CLONE/bin/harvest-learnings.sh"

  # The toolkit's own oldest shipped snapshot-mpr.sh, pulled from real git history — golden input,
  # not hand-written. Any project whose bin/snapshot-mpr.sh is byte-identical to this has simply
  # never synced since scaffold day; this is the exact "never-synced" signature the field run
  # found for tfc-tcxgraphpoc, factory-app and approval-app-main.
  OLD_SHA="$(git -C "$CLONE" log --format=%H -- project-bin/snapshot-mpr.sh | tail -1)"
  if [ -z "$OLD_SHA" ]; then
    bad "control: clone has no history for project-bin/snapshot-mpr.sh — fixture cannot run"
  else
    OLD_SHORT="$(git -C "$CLONE" log --format=%h -- project-bin/snapshot-mpr.sh | tail -1)"
    OLD_DATE="$(git -C "$CLONE" log --format=%ad --date=short -- project-bin/snapshot-mpr.sh | tail -1)"
    CURRENT="$CLONE/project-bin/snapshot-mpr.sh"
    if [ -f "$CURRENT" ] && cmp -s <(git -C "$CLONE" show "$OLD_SHA:project-bin/snapshot-mpr.sh") "$CURRENT"; then
      bad "control: the oldest shipped snapshot-mpr.sh is byte-identical to the CURRENT one — fixture proves nothing"
    else
      ok "control: oldest shipped snapshot-mpr.sh differs from the current one (a real STALE case exists to detect)"
    fi

    P="$WORK/mixedproj"; mkdir -p "$P/bin"
    git -C "$CLONE" show "$OLD_SHA:project-bin/snapshot-mpr.sh" > "$P/bin/snapshot-mpr.sh"

    # A genuine edit on top of the CURRENT shipped exec.sh — never matches anything in history.
    cp "$CLONE/project-bin/exec.sh" "$P/bin/exec.sh"
    printf '\n# LOCAL HARDENING: a fix that never traveled upstream\nexit 0\n' >> "$P/bin/exec.sh"

    OUT="$(bash "$CLONE/bin/harvest-learnings.sh" "$P" 2>&1)"; RC=$?
    DRAFT="$CLONE/contrib/inbox/$STAMP-mixedproj-patches.md"
    [ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC, expected 0" "$OUT"
    [ -f "$DRAFT" ] || bad "no draft written at $DRAFT" "$OUT"

    if [ -f "$DRAFT" ]; then
      if grep -qF "bin/snapshot-mpr.sh — STALE: identical to shipped $OLD_SHORT ($OLD_DATE)" "$DRAFT"; then
        ok "STALE one-liner names the exact historical sha and date"
      else
        bad "STALE one-liner missing or wrong sha/date" "$(grep 'snapshot-mpr' "$DRAFT")"
      fi
      if grep -qF -- "--upgrade-bin snapshot-mpr.sh" "$DRAFT"; then
        ok "STALE line names the real sync-project.sh fix flag with the script name"
      else
        bad "STALE line does not name --upgrade-bin <script>"
      fi
      if awk '/^## bin\/snapshot-mpr\.sh/{f=1} f && /^```diff/{print "DIFFBLOCK"; exit}' "$DRAFT" | grep -q DIFFBLOCK; then
        bad "STALE item got a diff block — should be one line only"
      else
        ok "STALE item has no diff block, no ## heading at all"
      fi

      if grep -q '^## bin/exec\.sh differs from shipped .* — LOCAL-FIX$' "$DRAFT"; then
        ok "LOCAL-FIX heading says LOCAL-FIX"
      else
        bad "LOCAL-FIX heading missing or wrong" "$(grep '^## bin/exec' "$DRAFT")"
      fi
      if grep -q 'Closest historical base:' "$DRAFT"; then
        ok "LOCAL-FIX item names its closest historical base"
      else
        bad "LOCAL-FIX item does not name a closest historical base"
      fi
      if awk '/^## bin\/exec\.sh/{f=1} f && /LOCAL HARDENING/{print "HIT"; exit}' "$DRAFT" | grep -q HIT; then
        ok "LOCAL-FIX diff block carries the actual local edit"
      else
        bad "LOCAL-FIX diff block missing the local edit"
      fi
      if grep -q 'Direction is undetermined' "$DRAFT"; then
        bad "old undetermined wording leaked into a run where direction WAS determined"
      else
        ok "no leftover undetermined wording once direction is known"
      fi

      if grep -qF '1 stale (one line each) · 1 local fix(es) (diffs above)' "$DRAFT"; then
        ok "summary line counts one stale and one local fix correctly"
      else
        bad "summary line missing or miscounted" "$(tail -3 "$DRAFT")"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------------------------
# T4: a toolkit worktree with no .git falls back to the old undetermined wording, never crashes.
# ---------------------------------------------------------------------------------------------
echo "== T4: no-git toolkit worktree falls back to undetermined wording =="

NOGIT="$WORK/nogit-toolkit"
mkdir -p "$NOGIT/bin" "$NOGIT/project-bin" "$NOGIT/contrib/inbox"
cp "$HARVEST" "$NOGIT/bin/harvest-learnings.sh"
cp "$TOOLKIT/project-bin/exec.sh" "$NOGIT/project-bin/exec.sh"
if git -C "$NOGIT" rev-parse --git-dir >/dev/null 2>&1; then
  bad "control: fixture's no-git toolkit copy IS inside a git worktree — fixture invalid for this host"
else
  ok "control: fixture's toolkit copy has no reachable .git"

  P4="$WORK/nogitproj"; mkdir -p "$P4/bin"
  cp "$NOGIT/project-bin/exec.sh" "$P4/bin/exec.sh"
  printf '\n# an edit, direction unknowable with no history to walk\n' >> "$P4/bin/exec.sh"

  OUT4="$(bash "$NOGIT/bin/harvest-learnings.sh" "$P4" 2>&1)"; RC4=$?
  DRAFT4="$NOGIT/contrib/inbox/$STAMP-nogitproj-patches.md"
  [ "$RC4" -eq 0 ] && ok "no-git run still exits 0 (never crashes)" || bad "no-git run exited $RC4" "$OUT4"
  if [ -f "$DRAFT4" ] && grep -q 'Direction is undetermined: stale install' "$DRAFT4"; then
    ok "no-git run falls back to the original undetermined wording"
  else
    bad "no-git run did not fall back to undetermined wording" "$OUT4"
  fi
  if [ -f "$DRAFT4" ] && grep -qE 'STALE|LOCAL-FIX' "$DRAFT4"; then
    bad "no-git run asserted a verdict it has no history to support"
  else
    ok "no-git run asserts no verdict it cannot support"
  fi
  if [ -f "$DRAFT4" ] && grep -qE '^[0-9]+ stale .* local fix' "$DRAFT4"; then
    bad "no-git run printed a stale/local-fix summary it never computed"
  else
    ok "no-git run prints no summary line (nothing was actually determined)"
  fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
# Every draft this fixture produced lives under $WORK (the clone's contrib/inbox, or the no-git
# copy's) — never under $TOOLKIT/contrib/inbox, which a peer session owns right now — so the
# trap's `rm -rf "$WORK"` is the only cleanup needed.
[ "$FAIL" -eq 0 ]
