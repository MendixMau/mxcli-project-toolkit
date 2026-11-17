# entry-mode.sh — shim. The ONE tokeniser for the register's "Entry mode:" line now lives in
# project-bin/_position.sh, because the installed exec.sh needs it too and cannot reach bin/lib/
# (2026-11-17). Sourcing this file defines the same entry_mode_token() it always did, plus the
# position reader (mxtk_pos_read) and the banner. Why there is only one tokeniser: the header
# of project-bin/_position.sh.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../project-bin" && pwd)/_position.sh"
