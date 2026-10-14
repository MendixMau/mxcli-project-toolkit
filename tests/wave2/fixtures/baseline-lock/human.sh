# human.sh — sourced by fixtures: the PERSON's step for a baseline move (#348).
#
# human_approve <project> <kind> [--current]
#   Runs <project>/bin/baseline-approve.sh under a pseudo-terminal and types `approve`, which is
#   what a person does in their own terminal. util-linux and BSD `script` take different
#   arguments; both are probed. Returns 3 when neither works (the caller reports a skip — it
#   never writes the approval row by hand, which would test nothing).
human_approve() {
  _hp="$1"; shift
  if script -qec true /dev/null >/dev/null 2>&1; then
    printf 'approve\n' | script -qec "bash '$_hp/bin/baseline-approve.sh' $*" /dev/null >/dev/null 2>&1
  elif script -q /dev/null true >/dev/null 2>&1; then
    printf 'approve\n' | script -q /dev/null bash "$_hp/bin/baseline-approve.sh" "$@" >/dev/null 2>&1
  else
    return 3
  fi
}

# pty_available — exit 0 when human_approve can run here
pty_available() { script -qec true /dev/null >/dev/null 2>&1 || script -q /dev/null true >/dev/null 2>&1; }
