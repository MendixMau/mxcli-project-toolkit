# portable.sh — cross-platform primitives for toolkit shell scripts. Source, do not execute.
#
# WHY THIS EXISTS. The toolkit is handed to customers, partners and colleagues who run it on
# their own machines. Every script here was authored on macOS, so every macOS assumption in
# them is invisible to us and fatal to them — and it lands as "the toolkit is broken", not as
# "my machine is missing something", because the failure happens partway into a pipeline stage
# rather than at the start.
#
# Two rules for anything added here:
#   1. Probe by EXECUTING, never by `command -v`. On Windows, `python3` usually resolves to the
#      Microsoft Store App Execution Alias stub: `command -v python3` succeeds, and the script
#      then opens the Store instead of running. A name on PATH is not an interpreter.
#   2. Fail loudly and in plain language. The reader cannot debug a shell script.
#
# Usage:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"
#   require_py            # sets $PY or exits 2 with an actionable message
#   ... "$PY" -c '...'
#
# Keep this bash-3.2 compatible: macOS ships 3.2.57. No mapfile, no readarray, no associative
# arrays, no ${var,,}.

# --- Python 3 ------------------------------------------------------------------------------

# A candidate that lives under WindowsApps is the Store alias stub. Executing it can launch the
# Store UI, so it is rejected on its path before it is ever run.
_py_is_store_stub() {
  case "$(command -v "$1" 2>/dev/null)" in
    *WindowsApps*|*windowsapps*) return 0 ;;
    *) return 1 ;;
  esac
}

# Echoes the name of a working Python 3 on stdout, or returns 1. Single token by design: call
# sites use "$PY", and a two-word value like `py -3` would word-split at every one of them.
resolve_py() {
  _c=""
  for _c in python3 python py; do
    _py_is_store_stub "$_c" && continue
    if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      echo "$_c"; return 0
    fi
  done
  return 1
}

# The form every script should use. Sets PY, or exits 2 saying how to fix it per platform.
require_py() {
  PY="$(resolve_py)" || {
    echo "$(basename "${0:-script}"): Python 3 is required and was not found." >&2
    echo "  Tried, by running each one: python3, python, py." >&2
    echo "  macOS  : brew install python3" >&2
    echo "  Linux  : apt install python3   (or your distro's equivalent)" >&2
    echo "  Windows: install from python.org and tick 'Add python.exe to PATH'." >&2
    echo "           A 'python3' that only opens the Microsoft Store is the Store alias stub," >&2
    echo "           not an interpreter — turn it off under Settings > App execution aliases." >&2
    echo "  Then run: bin/doctor.sh" >&2
    exit 2
  }
  export PY
}

# --- stat(1) -------------------------------------------------------------------------------
#
# `stat -f` is BSD, `stat -c` is GNU coreutils. Neither is a Windows/Linux/macOS common subset,
# so every use goes through these. Both echo empty and return 1 when they cannot tell, so a
# caller can distinguish "unknown" from a real value instead of silently comparing against "".

portable_file_size() {
  [ -f "$1" ] || return 1
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || wc -c < "$1" 2>/dev/null | tr -d ' ' || return 1
}

portable_file_mtime_epoch() {
  [ -e "$1" ] || return 1
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || return 1
}

# ISO-8601 to the second, no timezone suffix: 2026-08-18T09:41:07
portable_file_mtime_iso() {
  [ -e "$1" ] || return 1
  stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$1" 2>/dev/null && return 0
  _v="$(stat -c "%y" "$1" 2>/dev/null)" || return 1
  [ -n "$_v" ] || return 1
  printf '%s\n' "$_v" | cut -c1-19 | tr ' ' 'T'
}
