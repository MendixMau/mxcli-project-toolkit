#!/usr/bin/env bash
# _position.sh — the ONE shared tokeniser for "Entry mode:" (entry_mode_token), plus exec.sh's
# in-shell reader of the register's position lines (mxtk_pos_read: Entry mode, Adopted at stage,
# Build type, the Stage-4 waivers, the Current-stage readout). gate-check.sh and status.sh keep
# their own register readers and use only the tokeniser and the banner text from here. Sourced by
# project-bin/exec.sh (installed as bin/_position.sh) and, through the shim bin/lib/entry-mode.sh,
# by bin/gate-check.sh, bin/status.sh and bin/lib/artifact-check.sh.
#
# PURE BASH, no process starts: exec.sh runs this on every model write and its per-exec budget is
# counted (tests/wave2/test-exec-process-budget.sh). Bash 3.2 safe (macOS): no ${v,,}, no
# associative arrays; case-insensitive matching is `shopt -s nocasematch` inside [[ ]] only,
# restored on every return.
#
# WHY THE TOKENISER LIVES HERE (2026-11-17). It used to be bin/lib/entry-mode.sh, which an
# installed exec.sh cannot reach. exec.sh now has to know the mode (the plan rule below), and a
# second tokeniser is exactly what the old header warned against: two parsers once disagreed on
# "migration (not greenfield)" and the gate excused stages the screen said were owed.
#
# The rule: match the documented multi-word phrase first, else take the FIRST word of the value
# and exact-match it against the known set. A value we do not recognise resolves to empty AND
# says so on stderr. Unknown mode means every row applies and no stage is excused: louder, never
# quieter.

# entry_mode_token <raw> -> canonical token on stdout, "" if unrecognised.
# Canonical set: requirements-driven | migration | existing-app-change | a-la-carte | poc, plus
# greenfield-retired (a register sync-project.sh has not yet mapped). `poc` (#819 option 3) is
# the same contract as `Build type: poc` (mxtk_pos_read sets POS_BUILD=poc for it): a demo from a
# brief has no other mode to borrow, and an agent read three scripts looking for one.
entry_mode_token() { _mxtk_emt "${1-}"; echo "$_EMT"; }

# _mxtk_emt <raw> — the tokeniser itself; sets _EMT instead of printing, so exec.sh's reader
# below needs no command substitution (a fork is ~100 ms on Git Bash).
_mxtk_emt() {
  local raw="${1-}" v full _nc=0
  shopt -q nocasematch && _nc=1; shopt -s nocasematch
  v="${raw//$'\r'/}"
  # gate-check.sh's intake fallback passes the WHOLE answer line ("answered: migration",
  # "assumed (2026-09-01): greenfield"). Strip the question-answer prefix and the qualifier's own
  # parenthetical first, so the trailing-parenthetical cut below cannot eat the value with it.
  if [[ "$v" =~ ^[[:blank:]\>*_-]*(answered|answer|a|decision|assumed)[[:blank:]]*(\([^\)]*\))?[[:blank:]]*:[[:blank:]]*(.*)$ ]]; then
    v="${BASH_REMATCH[3]}"
  fi
  v="${v%%(*}"; v="${v%%,*}"; v="${v%%;*}"   # "migration (not greenfield)", "x, y", "x; y"
  # Trim markdown emphasis and noise on both ends ("**migration**", "_greenfield_").
  [[ "$v" =~ ^[[:blank:]\>*_-]*(.*)$ ]] && v="${BASH_REMATCH[1]}"
  if [[ "$v" =~ ^(.*[^[:blank:].*_-])[[:blank:].*_-]*$ ]]; then v="${BASH_REMATCH[1]}"; else v=""; fi
  full="$v"
  # Phrases on the WHOLE value, before the first-word cut: "Change an existing app" starts with
  # "change", which matches nothing; "a la carte" starts with "a". Phrases, not bare globs, so
  # "Migration from an existing Oracle Forms system" still reads as migration.
  if [[ "$full" == *"change an existing app"* || "$full" == *"existing app change"* || "$full" == *"existing-app change"* ]]; then
    [ "$_nc" = 1 ] || shopt -u nocasematch; _EMT="existing-app-change"; return 0
  fi
  if [[ "$full" == "a la carte"* || "$full" == "à la carte"* ]]; then
    [ "$_nc" = 1 ] || shopt -u nocasematch; _EMT="a-la-carte"; return 0
  fi
  # First word only — space, tab or "/" ("migration/brownfield" reads as migration) — then trim
  # emphasis/punctuation off THAT word ("**Migration**. Evidence: 409 .java files", #634).
  v="${v%%[ 	/]*}"
  [[ "$v" =~ ^[*_]*(.*)$ ]] && v="${BASH_REMATCH[1]}"
  if [[ "$v" =~ ^(.*[^.:!*_-])[.:!*_-]*$ ]]; then v="${BASH_REMATCH[1]}"; else v=""; fi
  local tok="" known=1
  # greenfield was RETIRED on 2026-11-17 (conversion-runbook.md → Entry Modes, "Two doors"):
  # it reads as its own token so every caller can say "run sync" instead of either honouring it
  # or dropping it in silence. sync-project.sh maps it to requirements-driven.
  if   [[ "$v" == greenfield ]]; then tok="greenfield-retired"
  elif [[ "$v" == requirements-driven || "$v" == requirements || "$v" == requirement ]]; then tok="requirements-driven"
  elif [[ "$v" == migration ]]; then tok="migration"
  elif [[ "$v" == existing-app-change || "$v" == existing-app || "$v" == existing ]]; then tok="existing-app-change"
  elif [[ "$v" == a-la-carte || "$v" == à-la-carte || "$v" == alacarte || "$v" == ala-carte ]]; then tok="a-la-carte"
  elif [[ "$v" == poc ]]; then tok="poc"
  elif [ -n "$v" ]; then known=0; fi
  [ "$_nc" = 1 ] || shopt -u nocasematch
  [ "$known" = 1 ] || printf 'entry mode "%s" not recognised; no stage is excused\n' "$raw" >&2
  _EMT="$tok"
}

# mxtk_auto_word <text> — true when the text's first word is `auto` or `unattended`, any case, with
# markdown emphasis, backticks and trailing punctuation ignored ("**Auto** (questions to
# questions.md)", "unattended — logged"). THE one reading of an Interview mode value as unattended:
# exec.sh (through mxtk_pos_read), gate-check.sh's --adopt ✋ check and ready.sh all call it, so the
# three cannot drift apart again (ready.sh had the first-word rule; the other two read exact values).
mxtk_auto_word() {
  local w="${1-}"
  w="${w//[\`*_]/}"
  [[ "$w" =~ ^[[:blank:]\>-]*([A-Za-z]+) ]] || return 1
  w="${BASH_REMATCH[1]}"
  case "$w" in [Aa][Uu][Tt][Oo]|[Uu][Nn][Aa][Tt][Tt][Ee][Nn][Dd][Ee][Dd]) return 0 ;; esac
  return 1
}

# mxtk_pos_read <project-root> — reads <root>/PROJECT.md once (HTML comments skipped: the
# scaffold's own comments name these labels) and, when the register has no Entry mode line, the
# intake.md §1 answer. Sets, never prints:
#   POS_REG       1 when PROJECT.md exists
#   POS_ENTRY     canonical token, or "" (none declared / not recognised)
#   POS_ADOPTED   the "Adopted at stage:" stage (P|0-7), or ""
#   POS_BUILD     "poc" when "Build type: poc" or "Entry mode: poc", else "full"
#   POS_WAIVED4   1 when a "Waived stage 4:" line carries a reason, or a "Waived stages:" line lists 4
#                 before its dash with a reason after it (the two spellings gate-check.sh reads)
#   POS_READOUT   the stage in gate-check.sh's "## Current stage" readout ("**Stage 5 — ..."), or ""
#   POS_AUTO      1 when ANY of $CLAUDE_INTERVIEW_MODE, .claude/.interview-mode or the register's
#                 "Interview mode:" line starts with auto / unattended (mxtk_auto_word). The strictest
#                 reading wins, as in ready.sh: a field register read `Interview mode: auto (gate
#                 questions go to questions.md ...)`, the exact-value read called that attended, and the
#                 second write of an unattended run got past the plan rule on refuse-once.
mxtk_pos_read() {
  local root="$1" reg line key val in_c=0 in_cur=0 entry_raw="" ad="" bt="" im="" _nc=0
  POS_REG=0; POS_ENTRY=""; POS_ADOPTED=""; POS_BUILD="full"; POS_WAIVED4=0; POS_READOUT=""; POS_AUTO=0
  reg="$root/PROJECT.md"
  shopt -q nocasematch && _nc=1; shopt -s nocasematch
  if [ -f "$reg" ]; then
    POS_REG=1
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line//$'\r'/}"
      if [ "$in_c" = 1 ]; then [[ "$line" == *"-->"* ]] && in_c=0; continue; fi
      if [[ "$line" == *"<!--"* ]]; then [[ "${line#*<!--}" == *"-->"* ]] || in_c=1; continue; fi
      if [[ "$line" == "## "* ]]; then [[ "$line" == "## Current stage"* ]] && in_cur=1 || in_cur=0; continue; fi
      if [ "$in_cur" = 1 ] && [ -z "$POS_READOUT" ] && [[ "$line" =~ ^\*\*Stage[[:blank:]]+([Pp0-7])([^0-9]|$) ]]; then
        POS_READOUT="${BASH_REMATCH[1]}"; continue
      fi
      [[ "$line" =~ ^[[:blank:]\>*_-]*([^:]+):[[:blank:]]*(.*)$ ]] || continue
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      key="${key%"${key##*[!*[:blank:]]}"}"; val="${val//\*/}"
      [ -n "${val//[[:blank:]]/}" ] || continue
      if   [ -z "$entry_raw" ] && [[ "$key" == "entry mode" ]]; then entry_raw="$val"
      elif [ -z "$ad" ] && [[ "$key" == "adopted at stage" ]]; then ad="$val"
      elif [ -z "$bt" ] && [[ "$key" == "build type" ]]; then bt="$val"
      elif [ -z "$im" ] && [[ "$key" == "interview mode" ]]; then im="$val"
      elif [[ "$key" == "waived stage 4" ]]; then POS_WAIVED4=1
      elif [[ "$key" == "waived stages" ]]; then
        # The aggregate spelling gate-check.sh also honours ("Waived stages: 1, 2, 3, 4 — reason"):
        # 4 must be listed BEFORE the dash, and a reason must follow it (no reason, no waiver).
        local _wh="" _wr=""
        case "$val" in *—*) _wh="${val%%—*}"; _wr="${val#*—}" ;; *–*) _wh="${val%%–*}"; _wr="${val#*–}" ;;
                       *" - "*) _wh="${val%% - *}"; _wr="${val#* - }" ;; esac
        [[ ",${_wh//[[:blank:]]/}," == *",4,"* && -n "${_wr//[[:blank:]]/}" ]] && POS_WAIVED4=1
      fi
    done < "$reg"
  fi
  # The intake answer is where the mode is decided and the only copy a young project has
  # (gate-check.sh reads it the same way).
  if [ -z "$entry_raw" ] && [ -f "$root/intake.md" ]; then
    local in_q=0
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ ^##[[:blank:]]*1\. ]] && [[ "$line" == *"entry mode"* ]]; then in_q=1; continue; fi
      [ "$in_q" = 1 ] || continue
      [[ "$line" == "##"* ]] && break
      if [[ "$line" =~ ^[[:blank:]\>*_-]*(answered|answer|a|decision|assumed)[[:blank:]]*(\([^\)]*\))?[[:blank:]]*: ]]; then
        entry_raw="$line"; break
      fi
    done < "$root/intake.md"
  fi
  [[ "$bt" =~ ^[[:blank:]]*poc([^a-z]|$) ]] && POS_BUILD="poc"
  local _imf=""
  [ -f "$root/.claude/.interview-mode" ] && { IFS= read -r _imf < "$root/.claude/.interview-mode" || true; }
  if mxtk_auto_word "${CLAUDE_INTERVIEW_MODE:-}" || mxtk_auto_word "$_imf" || mxtk_auto_word "$im"; then POS_AUTO=1; fi
  [[ "$ad" =~ ^[[:blank:]]*([Pp0-7])([^0-9]|$) ]] && POS_ADOPTED="${BASH_REMATCH[1]}"
  [ "$_nc" = 1 ] || shopt -u nocasematch
  if [ -n "$entry_raw" ]; then _mxtk_emt "$entry_raw" 2>/dev/null; POS_ENTRY="$_EMT"; fi
  [ "$POS_ENTRY" = poc ] && POS_BUILD="poc"
  return 0
}

# The banner (conversion-runbook.md → Entry Modes). One sentence, printed by status.sh,
# gate-check.sh's summary and every exec.sh run while the register declares no position.
MXTK_POS_RETIRED='Entry mode greenfield is retired: run bin/sync-project.sh <project> (maps the register line to requirements-driven, adopted at the current stage), or re-answer intake Q1 — Build type: poc for a demo.'
MXTK_POS_BANNER='No entry mode declared: the toolkit treats this project as Stage P, not started. Declare the mode (kickoff) or adopt a stage with a reason: gate-check.sh --adopt <stage> --reason ...'

# mxtk_pos_undeclared — true when nothing in the register (or intake) says where the project is.
# The bold Current-stage readout does not count: the scaffold writes it and gate-check rewrites it;
# it is a measurement, not a declaration.
mxtk_pos_undeclared() { [ -z "$POS_ENTRY" ] && [ -z "$POS_ADOPTED" ]; }

# mxtk_plan_evidence <root> — sets POS_EVIDENCE to what proves a plan exists before a
# pipeline-mode model write, returns 1 when nothing does (no fork: exec.sh calls it per write). Guard rule 6: evidence the toolkit did not create counts.
#   - Adopted at stage 5+ (the register line --adopt writes)
#   - Waived stage 4, with a reason
#   - gate-check's readout at Stage 5+ (every stage before it PASS or WAIVED)
#   - a build plan plus at least one module brief (architecture/ at the root or under apps/<App>/)
mxtk_plan_evidence() {
  local root="$1" d f
  POS_EVIDENCE=""
  case "$POS_ADOPTED" in 5|6|7) POS_EVIDENCE="Adopted at stage: $POS_ADOPTED"; return 0 ;; esac
  [ "$POS_WAIVED4" = 1 ] && { POS_EVIDENCE="Waived stage 4"; return 0; }
  case "$POS_READOUT" in 5|6|7) POS_EVIDENCE="gate-check readout: Stage $POS_READOUT"; return 0 ;; esac
  for d in "$root/architecture" "$root"/apps/*/architecture; do
    [ -s "$d/build-plan.md" ] || continue
    for f in "$d"/modules/*/module-brief.md; do
      [ -s "$f" ] && { POS_EVIDENCE="${d#"$root"/}/build-plan.md + module briefs"; return 0; }
    done
    local _bp; IFS= read -r -d '' _bp < "$d/build-plan.md" || true
    [[ "$_bp" =~ (^|$'\n')#+[[:blank:]]*[Mm]odule[[:blank:]]+[Bb]rief ]] && { POS_EVIDENCE="${d#"$root"/}/build-plan.md (briefs inline)"; return 0; }
  done
  return 1
}
