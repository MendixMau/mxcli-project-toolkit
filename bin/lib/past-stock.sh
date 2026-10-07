#!/usr/bin/env bash
# past-stock.sh — is a project's copy of a toolkit file an UNEDITED older toolkit version?
#
# WHY. sync-project.sh refreshes what was copied into a project, and for bin/ and tests/e2e/
# it could only tell two cases apart: identical to the toolkit now, or different. "Different"
# covers both a hand-hardened exec.sh (must never be overwritten) and a copy nobody touched
# that is simply a few releases old (should just be refreshed). Both got the same warning and
# the same manual command, so in practice neither got refreshed: a project kept the engine
# it was born with until someone read the warning and typed --force. Field run 2026-10-07
# (existing project): 4 of 4 drifted bin/ scripts and the whole e2e engine reported as drift,
# none of it refreshed by the sync the session-start ritual tells everyone to run.
#
# HOW. The toolkit clone carries its own history. Every version of project-bin/<f> or
# project-tests/e2e/<f> it ever shipped is a blob in that history; a project copy whose
# content hashes to one of those blobs is provably an unedited toolkit version — the same
# test git itself uses. Hashing goes through `git hash-object --path=<rel>`, so the toolkit's
# own line-ending rules apply: a Windows checkout with core.autocrlf (CRLF on disk, LF in
# history) still matches.
#
# SAFE DIRECTION. Anything this cannot prove reports "not past stock", which keeps sync's old
# behaviour (report, never overwrite): a toolkit that is not a git checkout, a shallow clone
# missing the old version, a renamed file, a single changed byte.
#
# Same question bin/harvest-learnings.sh answers before it drafts anything (its STALE verdict);
# its field run 2026-09-14 across 10 projects found 84 of 115 differing scripts to be exactly
# that — an unedited past version — and 31 genuine local fixes.
#
# Usage:  . bin/lib/past-stock.sh
#         when="$(mxtk_past_stock <toolkit-root> <toolkit-relative-path> <file> [<older-path>...])" \
#           && echo "unedited, toolkit version of $when"
# <older-path>: where the file lived before a move (project-bin/X was bin/X before the
# project-bin split), searched after the current path.
# Prints the commit date (YYYY-MM-DD) of the toolkit version it matches; exit 0 on a match,
# 1 otherwise. Bash-3.2 compatible (stock macOS).

mxtk_past_stock() {
  _ps_tk="$1"; _ps_rel="$2"; _ps_file="$3"; shift 3
  [ -f "$_ps_file" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  git -C "$_ps_tk" rev-parse --git-dir >/dev/null 2>&1 || return 1
  # Absolute path: -C moves git's working directory, a relative file name would then miss.
  case "$_ps_file" in
    /*) _ps_abs="$_ps_file" ;;
    *)  _ps_abs="$(cd "$(dirname "$_ps_file")" && pwd)/$(basename "$_ps_file")" ;;
  esac
  _ps_h="$(git -C "$_ps_tk" hash-object --path="$_ps_rel" -- "$_ps_abs" 2>/dev/null)" || return 1
  [ -n "$_ps_h" ] || return 1
  # --raw lines are ":<mode> <mode> <old-blob> <new-blob> <status>\t<path>". A version shipped
  # by a commit is that commit's NEW blob; the OLD blob is matched too so the oldest version
  # still present in a clone whose history starts mid-file is not missed.
  for _ps_path in "$_ps_rel" "$@"; do
    _ps_when="$(git -C "$_ps_tk" log --no-abbrev --raw --format='@%cs' -- "$_ps_path" 2>/dev/null \
      | awk -v h="$_ps_h" '
          /^@/ { d = substr($0, 2); next }
          /^:/ { if ($4 == h || $3 == h) { print d; exit } }')"
    [ -n "$_ps_when" ] && { printf '%s\n' "$_ps_when"; return 0; }
  done
  return 1
}
