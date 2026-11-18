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
# Producer: none needed — this is a pure predicate over files already on disk.
# Consumer: bin/gate-check.sh (blueprint.html and process-map.html freshness at Stage 3).

# _rf_git_clean_time <file> -> prints last-commit epoch if tracked+unmodified, else nothing (rc 1)
_rf_git_clean_time() {
  local f="$1" d t
  d="$(dirname "$f")"
  command -v git >/dev/null 2>&1 || return 1
  git -C "$d" ls-files --error-unmatch -- "$(basename "$f")" >/dev/null 2>&1 || return 1
  git -C "$d" diff --quiet HEAD -- "$(basename "$f")" >/dev/null 2>&1 || return 1
  t="$(git -C "$d" log -1 --format=%ct -- "$(basename "$f")" 2>/dev/null)"
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$t"
}

_rf_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# mxtk_render_is_stale <render> <source>: exit 0 when the render predates its source.
mxtk_render_is_stale() {
  local r="$1" s="$2" rt st
  if rt="$(_rf_git_clean_time "$r")" && st="$(_rf_git_clean_time "$s")"; then
    [ "$st" -gt "$rt" ]
    return
  fi
  [ "$(_rf_mtime "$s")" -gt "$(_rf_mtime "$r")" ]
}
