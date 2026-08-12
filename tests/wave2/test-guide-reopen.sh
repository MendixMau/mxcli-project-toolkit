#!/bin/bash
# test-guide-reopen.sh — the visual guide must open at most ONCE per project.
#
# Bug (2026-08-12): the guide reopened on essentially every session. Two independent causes:
#   (a) bin/init-project.sh opened it unconditionally on every run, and
#   (b) skills/conversion-runbook.md — the one file every session is required to read FIRST —
#       carried an unconditional "open it at Stage P kickoff", while the once-per-project
#       wording lived only in CLAUDE.md/README.md, which a session need not read.
#
# Both halves are tested here: the script guard by execution, the doc instructions by grep.
# The doc half matters more than it looks — the agent, not the script, was opening the tab.
#
# Usage: bash test-guide-reopen.sh [path-to-init-project.sh]
# Verified to FAIL against the pre-fix init-project.sh (git show HEAD:bin/init-project.sh).

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)/init-project.sh}"
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/guidereopen.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

# A fake `open`/`xdg-open` on PATH that records each invocation instead of launching a browser.
# Without this the test would be untestable: a real `open` succeeds silently and leaves no trace.
mkdir -p "$WORK/fakebin"
for stub in open xdg-open; do
  cat > "$WORK/fakebin/$stub" <<'STUB'
#!/bin/bash
echo "$*" >> "$OPEN_LOG"
exit 0
STUB
  chmod +x "$WORK/fakebin/$stub"
done

run_init() {   # $1 = project dir; echoes the number of guide-opens it performed
  local proj="$1"
  export OPEN_LOG="$WORK/openlog.$$"
  : > "$OPEN_LOG"
  PATH="$WORK/fakebin:$PATH" bash "$SUBJECT" "$proj" >/dev/null 2>&1
  # NB: `grep -c` prints 0 AND exits 1 on no-match, so `|| echo 0` would emit "0\n0"
  # and every downstream [ -eq ] would die with "integer expression expected".
  grep -c 'toolkit-guide.html' "$OPEN_LOG" 2>/dev/null | head -1
}

echo "== subject: $SUBJECT"

# --- 1. Cold project: opens exactly once, and records the sentinel -------------------
P1="$WORK/cold"; mkdir -p "$P1"
n=$(run_init "$P1")
[ "$n" -eq 1 ] && ok "cold project opens the guide once (got $n)" \
               || bad "cold project should open the guide exactly once, got $n"
[ -e "$P1/.claude/.guide-shown" ] && ok "cold run writes .claude/.guide-shown" \
                                  || bad "cold run did NOT write .claude/.guide-shown — nothing stops the next session"

# --- 2. Second run on the SAME project: must not open at all -------------------------
# This is the case the pre-fix script fails: it reopened every single time.
n=$(run_init "$P1")
[ "$n" -eq 0 ] && ok "second run on the same project opens nothing (got $n)" \
               || bad "second run reopened the guide $n time(s) — this is the reported bug"

# --- 3. Pre-existing sentinel, never scaffolded before: must not open ----------------
# Covers the backfill path for the 10 projects that predate the sentinel.
P2="$WORK/backfilled"; mkdir -p "$P2/.claude"; : > "$P2/.claude/.guide-shown"
n=$(run_init "$P2")
[ "$n" -eq 0 ] && ok "pre-existing sentinel suppresses the open (got $n)" \
               || bad "pre-existing sentinel ignored — opened $n time(s)"

# --- 4. MXTK_NO_GUIDE=1 still suppresses (pre-existing contract, must not regress) ---
P3="$WORK/headless"; mkdir -p "$P3"
export OPEN_LOG="$WORK/openlog.headless"; : > "$OPEN_LOG"
PATH="$WORK/fakebin:$PATH" MXTK_NO_GUIDE=1 bash "$SUBJECT" "$P3" >/dev/null 2>&1
n=$(grep -c 'toolkit-guide.html' "$OPEN_LOG" 2>/dev/null | head -1)
[ "$n" -eq 0 ] && ok "MXTK_NO_GUIDE=1 still suppresses (got $n)" \
               || bad "MXTK_NO_GUIDE=1 no longer suppresses — opened $n time(s)"

# --- 5. No doc may tell an agent to open the guide unconditionally -------------------
# The script guard is the smaller half. These four files each carried an unconditional
# instruction; the runbook one fired every session because every session must read it.
for f in skills/conversion-runbook.md CONVERSION-RUNBOOK.md toolkit-guide.html README.md; do
  [ -f "$TOOLKIT/$f" ] || { bad "missing file: $f"; continue; }
  # Match only an open-verb aimed AT THE GUIDE — "open the stage's owning skill file"
  # in the same paragraph as a toolkit-guide.html mention is not an offender.
  # Such a line must then carry the sentinel or defer to the rule in CLAUDE.md.
  offenders=$(grep -nEi 'open[^.]{0,40}(toolkit-guide|this page)|open it (in|for) (the )?(a )?(user|brows)' "$TOOLKIT/$f" \
              | grep -vi 'guide-shown\|first-touch\|CLAUDE\.md' \
              | grep -vi 'Opened the visual guide')
  if [ -n "$offenders" ]; then
    bad "$f still instructs an unconditional open:"
    echo "$offenders" | sed 's/^/         /'
  else
    ok "$f defers to the first-touch rule"
  fi
done

# --- 6. The rule is stated mechanically in exactly one place -------------------------
grep -q 'guide-shown' "$TOOLKIT/CLAUDE.md" \
  && ok "CLAUDE.md states the sentinel-based rule" \
  || bad "CLAUDE.md no longer states the sentinel rule — the single source is gone"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
