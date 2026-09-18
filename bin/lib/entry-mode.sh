# entry-mode.sh — ONE tokeniser for the register's "Entry mode:" line.
#
# WHY THIS EXISTS. Two parsers (bin/gate-check.sh and bin/lib/artifact-check.sh) each
# carried the same unanchored-glob case:
#
#     *greenfield*) ... ;; *requirement*) ... ;; *migration*) ... ;;
#
# Unanchored globs plus first-arm-wins means the token that appears EARLIEST IN THE
# CASE wins, not the one the line actually declares. "migration (not greenfield)"
# parsed as greenfield. The consumer stage_waiver() then excuses stages on that label
# with `mode` scope, and the manifest consumer marks rows N/A — so a misread here
# silently switches gates off. bin/status.sh used a third, anchored regex and so
# DISPLAYED the right mode while the gate acted on the wrong one, which is why this
# survived: the screen and the verdict disagreed and only the screen was read.
#
# The rule: match the documented multi-word phrase first, else take the FIRST word of
# the value and exact-match it against the known set.
# A value we do not recognise resolves to empty AND says so on stderr. Silence was
# the second half of the bug — a run could not tell you whether the mode had parsed.
#
# Unknown mode means every row applies and no stage is excused: louder, never quieter.

# entry_mode_token <raw> -> canonical token on stdout, "" if unrecognised.
#
# Canonical set: greenfield | requirements-driven | migration | existing-app-change
entry_mode_token() {
  local raw="${1-}" v full
  v="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  v="${v%%(*}"          # drop a trailing parenthetical: "migration (not greenfield)"
  v="${v%%,*}"          # drop anything after the first comma
  v="${v%%;*}"          # ...or semicolon
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[ \t>*_-]*//; s/[ \t.]*$//')"
  full="$v"
  # Documented multi-word phrases resolve on the WHOLE value, before the first-word
  # truncation below: the runbook's own label for the fourth mode is "Change an existing
  # app", whose first word is "change" and matches nothing. Matched as a phrase, not as a
  # bare `*existing*` glob, so "Migration from an existing Oracle Forms system" still reads
  # as migration (its own first word) rather than being waived as an existing-app change.
  case "$full" in
    *"change an existing app"*|*"existing app change"*|*"existing-app change"*)
      echo "existing-app-change"; return ;;
  esac

  v="${v%%[ 	]*}"      # first word only (space or tab)

  case "$v" in
    greenfield)                                   echo "greenfield" ;;
    requirements-driven|requirements|requirement) echo "requirements-driven" ;;
    migration)                                    echo "migration" ;;
    existing-app-change|existing-app|existing)    echo "existing-app-change" ;;
    "")                                           echo "" ;;
    *)
      printf 'entry mode "%s" not recognised; no stage is excused\n' "$raw" >&2
      echo ""
      ;;
  esac
}
