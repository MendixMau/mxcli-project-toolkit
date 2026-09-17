#!/usr/bin/env bash
# session-check.sh — three questions at session start, answered in under three seconds.
#
#   ./bin/session-check.sh        # wired as a Claude Code SessionStart hook by
#                                 # bin/install-claude-permissions.sh; safe to run by hand
#
#   1. Is the model on disk verified? (bin/model-stamp.sh check — the stamp exec.sh or
#      verify-model.sh left, against the model as it is now)
#   2. Can the mxbuild gate run here? (bin/doctor.sh --quick when its receipt is missing,
#      older than a day, or from a different mxcli/mxbuild/arch — same test exec.sh makes)
#   3. Are the installed guard scripts current? (the toolkit clone's project-bin/ vs this
#      project's bin/, by the functions a known fix introduced — a wrong answer here is
#      why a cloud session ran a crash net that could not find its own mxbuild)
#
# Never blocks, never exits non-zero: it is a hook, and a hook that fails at session
# start reads as "the toolkit is broken". It prints, and the session goes on.
. "$(dirname "$0")/_common.sh" 2>/dev/null || exit 0
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

echo "mxcli-project-toolkit session check ($(basename "$PROJECT_ROOT")):"

# 1. model verification stamp
if [ -x ./bin/model-stamp.sh ] && ls ./*.mpr ./app/*.mpr >/dev/null 2>&1; then
  ./bin/model-stamp.sh check 2>/dev/null || echo "    → model writes go through ./bin/exec.sh; any other change needs ./bin/verify-model.sh before it can be committed"
fi

# 2. machine preflight receipt (doctor)
TK="$(find_toolkit_root 2>/dev/null || true)"
DR="$PROJECT_ROOT/.claude/.doctor-receipt"
if [ -n "$TK" ] && [ -x "$TK/bin/doctor.sh" ]; then
  why=""
  if [ ! -f "$DR" ]; then why="doctor has never run in this clone"
  elif [ -n "$(find "$DR" -mmin +1440 2>/dev/null)" ]; then why="doctor receipt is older than a day"
  else
    mxb="$(find_mxbuild 2>/dev/null || true)"
    now="$( [ -x ./mxcli ] && ./mxcli --version 2>/dev/null | head -1 || echo none) | ${mxb:-no-mxbuild} | $(uname -sm)"
    [ "$now" = "$(sed -n '2s/^fingerprint: //p' "$DR")" ] || why="environment changed since doctor last ran"
  fi
  if [ -n "$why" ]; then
    echo "  → $why — running doctor --quick"
    "$TK/bin/doctor.sh" --quick "$PROJECT_ROOT" 2>&1 | grep -E '^\s+(WARN|FAIL)|^\s+Ready|^\s+NOT ready' | sed 's/^/    /' || true
  else
    echo "  ✓ machine preflight current ($(sed -n '1p' "$DR" 2>/dev/null))"
  fi
else
  echo "  ⚠ toolkit clone not found (MXTK_ROOT or the 'Toolkit root' row in CLAUDE.local.md) — doctor and staleness checks skipped"
fi

# 3. installed guard scripts vs the toolkit's project-bin
if [ -n "$TK" ]; then
  stale=""
  grep -q 'mxtk_ensure_mxbuild' ./bin/_common.sh 2>/dev/null || stale="$stale _common.sh"
  grep -q 'model-stamp' ./bin/exec.sh 2>/dev/null || stale="$stale exec.sh"
  for f in model-stamp.sh verify-model.sh install-project-hooks.sh; do [ -f "./bin/$f" ] || stale="$stale $f(missing)"; done
  if [ -n "$stale" ]; then
    echo "  ⚠ installed guard scripts predate the 2026-09-17 gate fix:$stale"
    echo "    → run: $TK/bin/sync-project.sh $PROJECT_ROOT   (installs missing scripts, reports drifted ones)"
  else
    echo "  ✓ guard scripts current"
  fi
  [ -x ./bin/install-project-hooks.sh ] && ./bin/install-project-hooks.sh --check 2>/dev/null | grep -v '✓' || true
fi
exit 0
