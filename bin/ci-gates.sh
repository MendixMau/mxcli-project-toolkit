#!/usr/bin/env bash
# ci-gates.sh — the gate an agent cannot skip. Run by the project's CI (.github/workflows/toolkit-gates.yml,
# installed by init-project.sh / sync-project.sh from templates/ci/toolkit-gates.yml) on every push and PR,
# over the COMMITTED tree only, with the toolkit checked out at the commit PROJECT.md pins.
#
# Usage: bin/ci-gates.sh <project-root>        exit 0 clean (warnings allowed), 1 a gate failed, 2 usage
#   MXTK_CI_STRICT_LOOK=1   unseen built pages fail even with no done-claim (default: warn mid-build)
#
# WHY (field runs, 2026-11, unattended). Everything that runs inside the agent's session can be skipped
# by the agent: it can not run gate-check, commit with --no-verify, or write READY by hand — and in one
# run it did the last, with 0 of ~78 pages looked at. CI runs outside the session, on what was pushed.
#
# THE CHECKS
#   (a) stage   gate-check.sh for the stage the register's "## Current stage" line claims; FAIL fails.
#               PENDING / MANUAL do not (a stage in progress has nothing to show yet).
#   (b) ready   a READY line in a status file that bin/ready.sh did not write (bin/lib/ready-claims.sh).
#   (c) look    the committed docs/progress/look-summary.tsv shows built pages never looked at, while
#               something claims done: a READY row in docs/progress/ready.log covering them, or the
#               register at Stage 6 or later. With no claim it is a warning (mid-build is normal and an
#               always-red CI gets ignored); MXTK_CI_STRICT_LOOK=1 makes it fail. A READY with no
#               committed summary behind it fails: the claim cites evidence nobody can read.
#   (d) order   model work before its plan: docs/BUILD-LOG.md has exec rows (or mdlsource/ holds build
#               scripts outside gallery/) while gate-check Stage 4 is not PASS/WAIVED. gate-check already
#               waives Stage 4 for greenfield and for an --adopt point at or after it.
#
# WHAT IT CANNOT SEE (anything not committed): the git-ignored .claude/loop/ ledgers themselves (only
# the summary ready.sh / close-task.sh commit), screenshots, chat, a model edited without exec.sh and
# without a BUILD-LOG row, and a summary nobody committed. It reads files, never the .mpr: no Mendix
# runtime, no mxcli. It runs in seconds (three gate-check stage queries at most).
#
# Producer for every consumer (CLAUDE.md "Shipping an instrument" rule 5): look-summary.tsv and ready.log
# are written by bin/ready.sh and close-task.sh; BUILD-LOG rows by exec.sh; the register by the gates.

set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${1:-}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "usage: ci-gates.sh <project-root>" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
REG="$ROOT/PROJECT.md"; GC="$TOOLKIT_ROOT/bin/gate-check.sh"
SUMM="$ROOT/docs/progress/look-summary.tsv"; LOG="$ROOT/docs/progress/ready.log"
FAILS=0; WARNS=0
say() {  # <PASS|FAIL|WARN> <check> <detail>
  case "$1" in FAIL) FAILS=$((FAILS+1)) ;; WARN) WARNS=$((WARNS+1)) ;; esac
  printf '%-4s  %-6s %s\n' "$1" "$2" "$3"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    case "$1" in FAIL) echo "::error title=toolkit gate $2::$3" ;; WARN) echo "::warning title=toolkit gate $2::$3" ;; esac
  fi
}
# gate <stage> — sets GV (verdict word) and GL (detail), returns gate-check's exit code
gate() {
  local out rc
  out="$(MXTK_NO_GUIDE=1 bash "$GC" --no-html "$ROOT" "$1" 2>&1)"; rc=$?
  GL="$(printf '%s\n' "$out" | grep -m1 "^Stage $1 (" | sed "s/^Stage $1 ([^)]*): //")"
  GV="$(printf '%s' "$GL" | awk '{print $1}')"
  return $rc
}

echo "ci-gates — $ROOT (toolkit $(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?'))"
[ -f "$REG" ] || { say FAIL stage "no PROJECT.md: not a toolkit project, or the register was never committed"; echo "FAIL — 1 gate"; exit 1; }

# (a) the stage the register claims
pos="$(awk '/^## Current stage/{f=1;next} f && /^\*\*/{print;exit}' "$REG")"
case "$pos" in
  *"All gates passed"*) claim=7 ;;
  *) claim="$(printf '%s' "$pos" | grep -oE 'Stage [0-9P]' | head -1 | sed 's/^Stage //')" ;;
esac
if [ -z "$claim" ]; then
  say WARN stage "no \"## Current stage\" line with a stage in PROJECT.md — nothing claimed, nothing to check"
else
  gate "$claim"; rc=$?
  case "$rc" in
    1) say FAIL stage "the register claims Stage $claim and its gate FAILs: $(printf '%s' "$GL" | cut -c1-240)" ;;
    *) say PASS stage "Stage $claim: ${GV:-exit $rc}" ;;
  esac
fi

# (b) READY written by hand
. "$TOOLKIT_ROOT/bin/lib/ready-claims.sh"
if rcf="$(mxtk_ready_claim_faults "$ROOT")"; then
  say PASS ready "every READY line is backed by bin/ready.sh evidence"
else
  while IFS= read -r l; do [ -n "$l" ] && say FAIL ready "$l"; done <<EOF
$rcf
EOF
fi

# (c) committed evidence of built pages never looked at
claims="$( [ -f "$LOG" ] && awk -F'\t' 'NF >= 4 { last[$3] = $2 } END { for (s in last) if (last[s] == "READY") print s }' "$LOG")"
late=0; case "$claim" in 6|7) late=1 ;; esac
if [ -s "$SUMM" ]; then
  unseen="$(awk -F'\t' '$1 == "unseen" { print $2 }' "$SUMM")"
  asof="$(awk -F'\t' '$1 == "as-of" { print $2 " (" $3 ", " $4 ")"; exit }' "$SUMM")"
  # "look: K of N pages seen" — shown on every run that does not fail, so the number is in front of people
  kn="$(awk -F'\t' '$1 == "as-of" { o=$3; s=$4; sub(/^owed /, "", o); sub(/^seen /, "", s); print "look: " s " of " o " pages seen"; exit }' "$SUMM")"
  if [ -z "$unseen" ]; then
    say PASS look "$kn — committed look summary, as of ${asof%% (*}"
  else
    n="$(printf '%s\n' "$unseen" | wc -l | tr -d ' ')"
    hit=""
    while IFS= read -r sc; do
      [ -n "$sc" ] || continue
      case "$sc" in
        "module "*) m="${sc#module }"; printf '%s\n' "$unseen" | grep -q "^$m\." && hit="$hit${hit:+; }$sc" ;;
        *) hit="$hit${hit:+; }$sc" ;;
      esac
    done <<EOF
$claims
EOF
    list="$(printf '%s\n' "$unseen" | head -8 | tr '\n' ' ')"
    if [ -n "$hit" ]; then say FAIL look "$kn — READY ($hit) while the committed look summary shows $n built page(s) never looked at: $list"
    elif [ "$late" = 1 ]; then say FAIL look "$kn — the register is at Stage $claim while $n built page(s) were never looked at: $list"
    elif [ "${MXTK_CI_STRICT_LOOK:-0}" = 1 ]; then say FAIL look "$kn — $n built page(s) never looked at (strict): $list"
    else say WARN look "$kn — $n built page(s) not looked at yet (as of ${asof%% (*}): $list — fine mid-build, a FAIL once READY or Stage 6 is claimed"; fi
  fi
elif [ -n "$claims" ]; then
  say FAIL look "READY claimed ($(printf '%s' "$claims" | tr '\n' ';')) but no docs/progress/look-summary.tsv is committed: the look behind the claim is invisible"
elif [ -f "$ROOT/docs/BUILD-LOG.md" ] && grep -qE '^\| *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$ROOT/docs/BUILD-LOG.md"; then
  say WARN look "look: not measured — docs/BUILD-LOG.md has exec rows but no docs/progress/look-summary.tsv is committed (bin/ready.sh and close-task.sh write it)"
else
  say PASS look "no look summary committed, no exec row, nothing claims done"
fi

# (d) model work before Stage 4 passed
execs=0
[ -f "$ROOT/docs/BUILD-LOG.md" ] && execs="$(grep -cE '^\| *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$ROOT/docs/BUILD-LOG.md" 2>/dev/null)"
# Script dirs: mdlsource/ at the root, plus one per app in a multi-app project (apps/<App>/mdlsource/,
# through the multi-app resolver mxtk_apps when this toolkit has it, else the apps/*/ glob). A field
# copy kept all 234 of its scripts per app, and the root-only count said 0.
dirs="$ROOT/mdlsource"
appdirs="$( ( PROJECT_ROOT="$ROOT"; . "$TOOLKIT_ROOT/project-bin/_common.sh" >/dev/null 2>&1
              type mxtk_apps >/dev/null 2>&1 && mxtk_apps "$ROOT" 2>/dev/null | cut -f2 ) < /dev/null 2>/dev/null )"
if [ -n "$appdirs" ]; then
  for m in $appdirs; do case "$m" in /*) d="${m%/*}" ;; *) d="$ROOT/${m%/*}" ;; esac; dirs="$dirs $d/mdlsource"; done
else
  for d in "$ROOT"/apps/*/mdlsource; do [ -d "$d" ] && dirs="$dirs $d"; done
fi
scripts=0
for d in $dirs; do
  [ -d "$d" ] || continue
  scripts=$((scripts + $(find "$d" -name '*.mdl' ! -path '*/gallery/*' 2>/dev/null | wc -l | tr -d ' ')))
done
if [ "${execs:-0}" -gt 0 ] || [ "${scripts:-0}" -gt 0 ]; then
  gate 4; rc=$?
  if [ "$rc" = 0 ]; then say PASS order "model work ($execs exec row(s), $scripts script(s)) after Stage 4: $GV"
  else say FAIL order "model work ($execs exec row(s) in docs/BUILD-LOG.md, $scripts build script(s) in mdlsource/ dirs) while Stage 4 is ${GV:-not passed}: build before the plan. Pass Stage 4, or record the adoption point (gate-check.sh --adopt 5 --reason \"...\")"; fi
else
  say PASS order "no model work committed yet"
fi

if [ "$FAILS" -gt 0 ]; then echo "FAIL — $FAILS gate(s) failed, $WARNS warning(s)"; exit 1; fi
echo "PASS — $WARNS warning(s)"
exit 0
