#!/usr/bin/env bash
# render-fresh.sh — "is this rendered file older than the source it was rendered from?",
# stated so a fresh clone does not answer yes.
#
# WHY (field run: a multi-app Mendix build, checked out fresh on a second machine). Stage 3's
# blueprint.html / process-map.html gates asked `[ render -ot source ]`. `-ot` compares
# modification times to the nanosecond, and a checkout stamps every file with the moment it
# was WRITTEN, in directory order: design/process-map.html lands before
# design/process-model.json, so the map reads "older than its model" and the gate FAILs
# "stale render" on a project nobody had edited. Reproduced on a 200-file checkout: the false
# positive fired on every clone. The same happens after tar/unzip/rsync.
#
# THE SIGNAL. If both files are git-tracked and unmodified, compare the commit time of the
# last commit touching each (clone-stable: the same commit gives the same time anywhere, in a
# shallow clone too). If either is untracked or has uncommitted edits, the working copy is
# what the human is editing, so compare mtimes — in WHOLE seconds, so a same-second write
# order (checkout, unzip) never reads as stale.
#
# COST (review of the first version: 12.7 s per pass on a 200-wireframe checkout, against 0.001 s for
# `-ot`; status.sh runs the full gate at every session start). So the old mtime test stays the
# first word: a render NOT older than its source by `-ot` is fresh at once and git is never asked,
# so a passing verdict cannot flip. Git is consulted only where `-ot` would have FAILED, and then
# ONCE PER RENDER, not once per source: one `git log -1` finds the commit that last touched the
# render, one `git log --name-only <that>..HEAD` lists every path committed after it, one
# `git status --porcelain` lists every dirty or untracked path. A source is stale when it is in the
# first list, or dirty with a newer whole-second mtime. No git call per source.
#
# LIMIT (stated, not fixed): in a depth-1 shallow clone there is no history after the render's
# commit, so a render that is genuinely stale (its source was committed after it) reads fresh there.
# Fetch history (`git fetch --deepen`) to see it. A source that is git-ignored is not in either list
# and reads fresh.
#
# Producer: none needed — this is a pure predicate over files already on disk.
# Consumer: bin/gate-check.sh (blueprint.html and process-map.html freshness at Stage 3).

_rf_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
_rf_abs() { ( cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")" ); }

_RF_MEMO_PATH=""; _RF_TOP=""; _RF_AFTER=""; _RF_DIRTY=""; _RF_GIT=0
_RF_NL='
'
# A long-lived shell that edits or commits the render between calls must forget the memo.
mxtk_render_memo_reset() { _RF_MEMO_PATH=""; _RF_TOP=""; _RF_AFTER=""; _RF_DIRTY=""; _RF_GIT=0; }

# _rf_load <render>: fill the per-render memo (_RF_GIT=1 only when the render is tracked and clean).
_rf_load() {
  local r="$1" ra rd rb rel c
  _RF_MEMO_PATH="$r"; _RF_GIT=0; _RF_TOP=""; _RF_AFTER=""; _RF_DIRTY=""
  command -v git >/dev/null 2>&1 || return 0
  ra="$(_rf_abs "$r")" || return 0; rd="$(dirname "$ra")"; rb="$(basename "$ra")"
  _RF_TOP="$(git -C "$rd" rev-parse --show-toplevel 2>/dev/null)" || { _RF_TOP=""; return 0; }
  _RF_TOP="$(cd "$_RF_TOP" && pwd -P)"
  rel="${ra#"$_RF_TOP"/}"
  c="$(git -C "$_RF_TOP" log -1 --format=%H -- "$rel" 2>/dev/null)"
  [ -n "$c" ] || return 0                                   # render untracked
  _RF_DIRTY="$(git -C "$_RF_TOP" status --porcelain 2>/dev/null | sed 's/^...//')"
  case "$_RF_NL$_RF_DIRTY$_RF_NL" in *"$_RF_NL$rel$_RF_NL"*) return 0 ;; esac   # render dirty
  _RF_AFTER="$(git -C "$_RF_TOP" log --name-only --format= "$c..HEAD" 2>/dev/null)"
  _RF_GIT=1
}

# mxtk_render_is_stale <render> <source>: exit 0 when the render predates its source.
mxtk_render_is_stale() {
  local r="$1" s="$2" sa rel
  [ "$r" -ot "$s" ] || return 1                             # not older by mtime: fresh, no git
  [ "$_RF_MEMO_PATH" = "$r" ] || _rf_load "$r"
  if [ "$_RF_GIT" = 1 ]; then
    # Fast path, no forks: an absolute (or $PWD-relative) path already under the physical top.
    case "$s" in /*) sa="$s" ;; *) sa="$PWD/$s" ;; esac
    rel="${sa#"$_RF_TOP"/}"
    case "$rel$sa" in "$sa$sa"|*/./*|*/../*) sa="$(_rf_abs "$s")"; rel="${sa#"$_RF_TOP"/}" ;; esac
    case "$_RF_NL$_RF_AFTER$_RF_NL" in *"$_RF_NL$rel$_RF_NL"*) return 0 ;; esac   # committed after the render
    case "$_RF_NL$_RF_DIRTY$_RF_NL" in *"$_RF_NL$rel$_RF_NL"*) ;; *) return 1 ;; esac  # clean and not later: fresh
  fi
  [ "$(_rf_mtime "$s")" -gt "$(_rf_mtime "$r")" ]           # dirty / untracked / no git: whole seconds
}
