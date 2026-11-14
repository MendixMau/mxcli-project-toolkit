# gitignore-ensure.sh — "make sure this entry is in that .gitignore", CRLF-safe. Source, do not execute.
#
#   mxtk_gitignore_ensure <gitignore-file> <entry> [<line> ...]
#     <entry>   the pattern to find, e.g. .mxtk/ — a line counts as present when, with a trailing CR,
#               a leading "/" and a trailing "/" ignored, it equals the entry (the same spellings
#               `grep -qE '^/?entry/?$'` accepted, plus CRLF).
#     <line>... the block to append when it is missing, one argument per line (comment lines, then
#               the entry itself). An empty argument is a blank line.
#   mxtk_gitignore_has <file> <entry> is the presence test alone (0 = present).
#   ensure returns 0 = appended, 1 = already present (file untouched), 2 = could not write.
#   Appends in the file's own line ending (CRLF if any CR is in it, else LF), first completing a last
#   line that has no newline. A missing file is created with LF. An LF file gets byte-for-byte what the
#   old `printf '\n'; printf '<block>'` code gave it.
#
# WHY (follow-up to the snapshot-mpr fix): a Windows-made .gitignore is CRLF. `grep -qE '^/?x/?$'`
# never matches `x\r`, so init-project.sh re-appended an entry that was already there, and every
# appender wrote LF lines into a CRLF file (mixed endings).
#
# TWO COPIES, ON PURPOSE: this file serves bin/ scripts; project-bin/_common.sh carries the same
# function for the scripts installed into projects (they cannot reach bin/lib/, and a new installed
# file would need new install plumbing). tests/wave2/test-gitignore-crlf.sh runs both copies through
# the same cases — change one, change the other. Bash 3.2 safe: no process starts on the read path.
# mxtk_gitignore_has: 0 iff <entry> is already a line of the file (also what ensure asks first).
mxtk_gitignore_has() {
  local _f="$1" _e="$2" _txt="" _l
  [ -f "$_f" ] || return 1
  _e="${_e#/}"; _e="${_e%/}"
  IFS= read -r -d '' _txt < "$_f" || true
  while IFS= read -r _l || [ -n "$_l" ]; do
    _l="${_l%$'\r'}"; _l="${_l#/}"; _l="${_l%/}"
    [ "$_l" != "$_e" ] || return 0
  done <<EOT
$_txt
EOT
  return 1
}
mxtk_gitignore_ensure() {
  local _f="$1" _entry="$2" _txt="" _eol=$'\n' _n
  shift 2
  mxtk_gitignore_has "$_f" "$_entry" && return 1
  if [ -f "$_f" ]; then
    IFS= read -r -d '' _txt < "$_f" || true
    case "$_txt" in *$'\r'*) _eol=$'\r\n' ;; esac
  fi
  {
    if [ -f "$_f" ] && [ -s "$_f" ] && [ -n "$(tail -c 1 "$_f")" ]; then printf '%s' "$_eol"; fi
    for _n in "$@"; do printf '%s%s' "$_n" "$_eol"; done
  } 2>/dev/null >> "$_f" || return 2
  return 0
}
