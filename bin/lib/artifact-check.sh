#!/usr/bin/env bash
# artifact-check.sh — the forward check over bin/lib/artifact-manifest.tsv.
#
# WHY THIS EXISTS: read the header of bin/lib/artifact-manifest.tsv. In one line —
# install-manifest.sh made a missing toolkit FILE impossible to miss, obligation-check.sh did
# the same for a missing PASS, and this does it for a missing per-stage ARTIFACT. The pattern
# it retires is the one the improvement plan saw seven times: a consumer written, routed and
# gated against an artifact no stage ever produced, discovered only by a human reading the
# failed project.
#
# WHAT IT IS NOT: a judge. It never decides whether a blueprint is right, a wireframe is
# faithful or a ledger's rows are true. Those verdicts live in the skills the manifest's
# producer column names (skills-over-scripts.md). This script fetches one fact per artifact —
# "does a non-empty file match the promised path" — and prints it. It is an instrument: it may
# report FAULT (I could not measure, or the file is an empty shell), never FAIL (this is wrong).
#
# Sourced by bin/gate-check.sh, directly after the obligation check and in its image.
# Also runnable directly for a quick read:
#     bin/lib/artifact-check.sh <project-dir>
#
# Verdicts, per manifest row:
#   PRESENT  a non-empty file matches the promised path (named in the line)
#   PENDING  absent. Two spellings of one verdict, and the message says which:
#            owed — the project's recorded position is at or past the stage; loud, with the
#                   producer to run and the consumers left waiting;
#            not begun — the register records no position at or past the stage and no
#                   stage artifact exists yet; owed later, not overdue now.
#   FAULT    a file matches the path and is EMPTY — produced-and-empty is not produced
#            (mirrors check_stage_1's "exists but is empty" stance)
#   WAIVED   the register says so, with a reason (see WAIVERS below)
#   ADOPTED  the project joined the pipeline above this artifact's stage
#   N/A      the entry mode does not run this stage, or the project is not running the
#            pipeline at all (à-la-carte; existing-app-assurance.md) — said out loud either
#            way, because silence is the failure mode this file exists to remove
#   OFFERED  an OPT-IN row (manifest absence column `optin`) nobody opted into and nobody
#            produced — optional artifacts (swimlanes, workflow design, sequence diagrams,
#            test plan …) offered at the stage open by bin/lib/closeout.sh. Summarised on ONE
#            line per run, never per row: not owed is not the same as missing. A register line
#            `Opt-in artifact <id>: <why>` turns the row into an ordinary report-only one; a
#            file that simply exists at the path is PRESENT and tracked from then on.
#
# POSITION IS READ, NEVER INFERRED (CLAUDE.md: "Never infer a project's position — read the
# register line, or ask"). The project's position is derived from exactly the records
# obligation-check.sh and gate-check.sh already read, plus the manifest's own evidence:
#   - "Adopted at stage: N"                    (written by gate-check.sh --adopt)
#   - CONFIRMED decision rows' stage fields    (the ✋ gates' own output; a stage whose gate
#                                               passed makes the NEXT stage current)
#   - "Waived stage N" lines                   (a stage declared settled is a position statement)
#   - the highest manifest stage with any artifact PRESENT — the mirror of obligation-check's
#     "opened for work": a stage that has begun leaving artifacts owes the rest of them
# Stages P and 0 are owed from scaffold time in every entry mode (init writes intake.md and
# PROJECT.md on day one; conversion-runbook.md §"Stage 0 runs in every entry mode").
#
# WAIVERS live in the decision register, same file and same shape as every other waiver —
# ONE register, never a side state file. Two lines are read, most specific first:
#     Waived artifact blueprint-html: render superseded by the client's own review deck
#     Waived stage 3: architecture was decided in the client's Confluence
# The second is what gate-check.sh --waive <stage> already writes, and it covers the stage's
# artifacts wholesale. The per-artifact spelling is written BY HAND — deliberately: the
# register line is the authority (gate-check.sh's --adopt/--waive block says exactly this),
# so a hand-written line needs no flag, and gate-check's flag vocabulary is not widened here.
# A waived artifact reports WAIVED with its reason — never PRESENT.

set -uo pipefail

_ART_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ARTIFACT_TSV="${ARTIFACT_TSV:-$_ART_LIB_DIR/artifact-manifest.tsv}"

# ── helpers ─────────────────────────────────────────────────────────────────
# Deliberately self-contained, same stance as obligation-check.sh: gate-check.sh's reg_field()
# may be defined after this file is sourced, and a lib that only works at one source position
# is a wiring bug waiting.
_art_register_lines() {
  [ -f "$1" ] || return 0
  awk '/<!--/{c=1} c{if($0~/-->/)c=0;next}
       {l=$0; gsub(/^[ \t>*_-]+/,"",l); gsub(/\*/,"",l); print l}' "$1"
}

# _art_field <register> <lowercased label> — value of the first "Label: value" line.
#
# One awk pass, not a bash loop. The loop form spawned `tr` and `sed` per register line, and
# this function is called two or three times per manifest row — on a real register (TFC,
# ~300 lines, cells running to 2,000 characters) that was ~60,000 subprocesses per gate-check
# run, i.e. the "Stage 2 hangs" report of 2026-09-02 that was not a hang but a ninety-second
# lookup. Same contract: first match wins, label compared lower-cased and trimmed, empty
# values skipped, HTML comments ignored (as _art_register_lines does).
_art_field() {
  local reg="$1" want="$2" out
  [ -f "$reg" ] || return 1
  out="$(awk -v want="$want" '
    /<!--/ { c = 1 } c { if ($0 ~ /-->/) c = 0; next }
    {
      l = $0; gsub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l)
      i = index(l, ":"); if (i == 0) next
      key = tolower(substr(l, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
      val = substr(l, i + 1);              gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (val == "") next
      if (key == want) { print val; exit }
    }' "$reg")"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# _art_waiver <register> <artifact-id> <stage> — prints the reason, exits 0 if waived.
# Case-insensitive for the same reason obligation-check documents: a waiver that silently
# missed on capitalisation is one the author believes is in force and the gate does not.
_art_waiver() {
  local reg="$1" id="$2" st="$3" r
  r="$(_art_field "$reg" "$(printf 'waived artifact %s' "$id" | tr '[:upper:]' '[:lower:]')")" \
    && { printf '%s\n' "$r"; return 0; }
  r="$(_art_field "$reg" "$(printf 'waived stage %s' "$st" | tr '[:upper:]' '[:lower:]')")" \
    && { printf 'with its whole stage (Waived stage %s: %s)\n' "$st" "$r"; return 0; }
  return 1
}

_art_adopted_stage() {
  local v
  v="$(_art_field "$1" "adopted at stage")" || return 1
  printf '%s\n' "$(printf '%s' "$v" | awk '{print $1}' | tr -d '.,;')"
}

_art_rank() { case "$1" in P|p) echo 0 ;; [0-7]) echo $(( $1 + 1 )) ;; *) echo 99 ;; esac; }
# The inverse, for messages: ranks are the script's arithmetic, stages are the runbook's
# vocabulary, and a message that says "rank 5" makes the reader do the subtraction.
_art_stage_of_rank() { case "$1" in 0) echo P ;; [1-8]) echo $(( $1 - 1 )) ;; *) echo "?" ;; esac; }

# Entry mode: the register's own line, normalised to the manifest's tokens. NOT the intake
# fallback gate-check.sh performs — this lib refuses to grow a second copy of that parser
# (discover-brds.sh's header is the standing warning about second copies). Unknown mode means
# every row applies: louder, never quieter.
_art_entry_mode() {
  local raw
  raw="$(_art_field "$1" "entry mode" 2>/dev/null || true)"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    *greenfield*)  echo "greenfield" ;;
    *requirement*) echo "requirements" ;;
    *migration*)   echo "migration" ;;
    *)             echo "" ;;
  esac
}

# Highest stage rank the register itself attests: CONFIRMED decision rows (field-exact, the
# same test as gate-check.sh's has_confirmed_decision) and "Waived stage N" lines.
_art_register_rank() {
  local reg="$1" max=-1 r line st
  [ -f "$reg" ] || { echo -1; return 0; }
  while IFS= read -r st; do
    [ -n "$st" ] || continue
    r="$(_art_rank "$st")"
    [ "$r" -lt 99 ] && [ "$r" -gt "$max" ] && max="$r"
  done < <(awk -F'|' '
    /<!--/ { incomment = 1 }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^\|/ {
      s = $2; gsub(/^[ \t]+|[ \t]+$/, "", s); sub(/^[Ss]tage[ \t]*/, "", s)
      if (s !~ /^[Pp0-7]$/) next
      for (i = 3; i <= NF; i++) {
        f = toupper($i); gsub(/^[ \t]+|[ \t]+$/, "", f)
        if (f == "CONFIRMED") { print toupper(s); break }
      }
    }
    { line = $0
      gsub(/^[ \t>*_-]+/, "", line); gsub(/\*/, "", line)
      i = index(line, ":"); if (i == 0) next
      key = tolower(substr(line, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
      if (key ~ /^waived stage[ \t]+[p0-7]$/) print toupper(substr(key, length(key)))
    }' "$reg")
  echo "$max"
}

# Does any file match this row's paths? Sets ART_HIT (first non-empty match) and ART_EMPTY
# (a match exists but every match is empty). Patterns are |-separated project-relative globs,
# tried under the project root and under analysis/<name>/ — the two bases gate-check.sh's
# _art_newer <a> <b> — is a newer than b? Filename date first (the modern artifact schema
# names it), mtime as the fallback for dateless names. Returns 0 for yes.
_art_newer() {
  local ad bd am bm
  ad="$(basename "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"; ad="${ad:-0000-00-00}"
  bd="$(basename "$2" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"; bd="${bd:-0000-00-00}"
  [[ "$ad" > "$bd" ]] && return 0
  [[ "$ad" < "$bd" ]] && return 1
  # GNU first, BSD second — on GNU `stat -f` succeeds with the wrong meaning.
  am="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)"
  bm="$(stat -c %Y "$2" 2>/dev/null || stat -f %m "$2" 2>/dev/null || echo 0)"
  [ "${am:-0}" -gt "${bm:-0}" ]
}

# resolve_artifact() already serves.
_art_find() {
  local root="$1" paths="$2" pat base f rest
  ART_HIT=""; ART_EMPTY=""
  rest="$paths"
  while [ -n "$rest" ]; do
    pat="${rest%%|*}"
    case "$rest" in *\|*) rest="${rest#*|}" ;; *) rest="" ;; esac
    [ -n "$pat" ] || continue
    # Within one pattern, prefer the NEWEST match; across patterns, the earlier pattern still
    # wins, because the `|` list is a preference order the manifest author wrote deliberately.
    #
    # Glob order is alphabetical, and the review-report schema is `ui-review-<YYYY-MM-DD>*.html`,
    # so first-match meant OLDEST. That never changed a verdict here — this check is file
    # presence only — but it named a superseded file as the artifact satisfying the row, and a
    # reader who opens it to see what the stage produced is reading last month's work. Same
    # defect, same day, as the one fixed in obligation-check.sh's `_ob_find`, where it DID
    # change the verdict.
    local newest_hit=""
    for base in "$root" "$root"/analysis/*; do
      [ -d "$base" ] || continue
      # base quoted, pattern not: the base must survive spaces, the pattern must glob.
      for f in "$base"/$pat; do
        [ -e "$f" ] || continue
        if [ -s "$f" ]; then
          if [ -z "$newest_hit" ] || _art_newer "$f" "$newest_hit"; then newest_hit="$f"; fi
        else
          ART_EMPTY="$f"
        fi
      done
    done
    if [ -n "$newest_hit" ]; then ART_HIT="$newest_hit"; return 0; fi
  done
  return 0
}

# ── the forward check ───────────────────────────────────────────────────────
# mxtk_artifacts_report <project-dir> [register-path]
# Prints one line per manifest row. Sets MXTK_ART_STATUS to the worst verdict seen.
mxtk_artifacts_report() {
  local root="$1" reg="${2:-$1/PROJECT.md}"
  MXTK_ART_STATUS="PASS"
  MXTK_ART_N_PENDING=0; MXTK_ART_N_FAULT=0

  if [ ! -f "$ARTIFACT_TSV" ]; then
    # The table is the thing this check IS. A missing table says so rather than printing a
    # clean sheet — the exact failure mode the table exists to retire.
    printf 'Artifacts: FAULT — %s not found; no artifact was checked (this is the checker failing, not the project)\n' \
      "$ARTIFACT_TSV"
    MXTK_ART_STATUS="FAULT"; return 0
  fi

  # À-la-carte: no register and no module briefs means no pipeline. Same test, same sentence
  # shape, as obligation-check.sh — the two checks must agree on what "not a pipeline project"
  # means or their disagreement becomes a third thing to debug.
  if [ ! -f "$reg" ] && [ ! -d "$root/architecture/modules" ]; then
    printf 'Artifacts: N/A — no PROJECT.md and no architecture/modules/; this is not a pipeline project (existing-app-assurance.md)\n'
    return 0
  fi

  local adopted adopted_rank=0 mode
  adopted="$(_art_adopted_stage "$reg" 2>/dev/null || true)"
  [ -n "$adopted" ] && adopted_rank="$(_art_rank "$adopted")"
  mode="$(_art_entry_mode "$reg")"

  # Position (see header): baseline rank 1 (stages P and 0 owed from scaffold time), the
  # register's own attested rank + 1 (a passed gate makes the next stage current), the
  # adoption rank, and the highest stage already leaving artifacts.
  local owed_rank=1 reg_rank present_rank=-1 pos_src="scaffold baseline (stages P and 0)"
  reg_rank="$(_art_register_rank "$reg")"
  if [ "$reg_rank" -ge 0 ] && [ $((reg_rank + 1)) -gt "$owed_rank" ]; then
    owed_rank=$((reg_rank + 1))
    pos_src="register decisions through stage $(_art_stage_of_rank "$reg_rank"), so stage $(_art_stage_of_rank "$owed_rank") is current"
  fi
  if [ "$adopted_rank" -gt "$owed_rank" ]; then
    owed_rank="$adopted_rank"; pos_src="adopted at stage $adopted"
  fi

  local id stage paths producer consumers modes absence r
  # First pass: the highest manifest stage with any artifact present. Presence of work is
  # scope evidence, exactly as a module directory is for obligation-check.sh — it never
  # DOWNGRADES a verdict, it only makes more artifacts owed.
  while IFS=$'\t' read -r id stage paths producer consumers modes absence; do
    case "$id" in ''|'#'*|artifact) continue ;; esac
    r="$(_art_rank "$stage")"; [ "$r" -lt 99 ] || continue
    [ "$r" -le "$present_rank" ] && continue
    # An optional artifact is never position evidence: a swimlane sketched early must not
    # make a whole stage's mandatory artifacts owed.
    [ "$absence" = "optin" ] && continue
    _art_find "$root" "$paths"
    [ -n "$ART_HIT" ] && present_rank="$r"
  done < "$ARTIFACT_TSV"
  if [ "$present_rank" -gt "$owed_rank" ]; then
    owed_rank="$present_rank"
    pos_src="stage-$(_art_stage_of_rank "$present_rank") artifacts already present"
  fi

  # Second pass: the report.
  local _art_offered=""
  while IFS=$'\t' read -r id stage paths producer consumers modes absence; do
    case "$id" in ''|'#'*|artifact) continue ;; esac

    r="$(_art_rank "$stage")"
    if [ "$r" -ge 99 ]; then
      printf 'Artifact %-24s FAULT — unknown stage "%s" in %s\n' "$id" "$stage" "$ARTIFACT_TSV"
      MXTK_ART_STATUS="FAULT"; MXTK_ART_N_FAULT=$((MXTK_ART_N_FAULT+1)); continue
    fi

    # Entry mode: excused stages are said out loud, never skipped silently. An unknown mode
    # (young register, no line yet) excuses nothing.
    if [ -n "$mode" ]; then
      case ",$modes," in
        *",$mode,"*) ;;
        *) printf 'Artifact %-24s N/A — entry mode %s does not owe it (manifest modes: %s)\n' \
             "$id" "$mode" "$modes"
           continue ;;
      esac
    fi

    # Opt-in rows: offered, not owed. Opted in (register line) or already produced → fall
    # through and be tracked like any report-only row. Neither → one summary line at the end.
    if [ "$absence" = "optin" ]; then
      _art_find "$root" "$paths"
      if [ -z "$ART_HIT" ] && [ -z "$ART_EMPTY" ] \
         && ! _art_field "$reg" "opt-in artifact $id" >/dev/null 2>&1; then
        _art_offered="$_art_offered${_art_offered:+, }$id (stage $stage)"
        continue
      fi
      absence="report"
    fi

    # Adoption never covers Stage P — same exception, same reason, as gate-check.sh's
    # stage_waiver(): intake is how the toolkit learns what the project IS, it costs one
    # conversation, and the adoption decision is itself a Stage-P answer. `Waived stage P` /
    # `Waived artifact intake` still can.
    if [ "$r" -lt "$adopted_rank" ] && [ "$r" -gt 0 ]; then
      printf 'Artifact %-24s ADOPTED — project joined at stage %s, above this artifact'"'"'s stage %s (%s)\n' \
        "$id" "$adopted" "$stage" "$producer"
      continue
    fi

    local reason
    if reason="$(_art_waiver "$reg" "$id" "$stage")"; then
      printf 'Artifact %-24s WAIVED — %s\n' "$id" "$reason"
      continue
    fi

    _art_find "$root" "$paths"
    if [ -n "$ART_HIT" ]; then
      printf 'Artifact %-24s PRESENT — %s\n' "$id" "$ART_HIT"
      continue
    fi
    if [ -n "$ART_EMPTY" ]; then
      printf 'Artifact %-24s FAULT — %s exists but is EMPTY; produced-and-empty is not produced (producer: %s)\n' \
        "$id" "$ART_EMPTY" "$producer"
      MXTK_ART_STATUS="FAULT"; continue
    fi

    if [ "$r" -le "$owed_rank" ]; then
      # The loud case, and the whole point: a stage the project has reached promised this
      # file, named readers are waiting on it, and nothing has produced it.
      printf 'Artifact %-24s PENDING — owed at stage %s (position: %s) and absent; produce it: %s. Read by: %s%s\n' \
        "$id" "$stage" "$pos_src" "$producer" "$consumers" \
        "$( [ "$absence" = "gate" ] && printf ' [absence holds a mechanical gate shut]' || printf ' [report-only]' )"
      # Only the LOUD case is counted for the run summary — a stage not begun owes nothing yet.
      MXTK_ART_N_PENDING=$((MXTK_ART_N_PENDING+1))
      [ "$MXTK_ART_STATUS" = "PASS" ] && MXTK_ART_STATUS="PENDING"
    else
      # Not begun. Still printed — silence is the failure mode — but quietly, and it never
      # moves MXTK_ART_STATUS: nothing is wrong, nothing has been done yet.
      printf 'Artifact %-24s PENDING — stage %s not begun (position: %s); owed when it starts (%s)\n' \
        "$id" "$stage" "$pos_src" "$producer"
    fi
  done < "$ARTIFACT_TSV"

  # The one line for everything on offer and untaken — said once so it is not silent, said
  # once so eight optional rows do not read as eight things missing.
  if [ -n "$_art_offered" ]; then
    printf 'Artifacts optional, not opted in: %s — offered at each stage open by gate-check.sh --closeout; opt in with a register line "Opt-in artifact <id>: <why>"\n' "$_art_offered"
  fi

  return 0
}

# Direct invocation: run the check against a project dir.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  mxtk_artifacts_report "${1:-$(pwd)}" "${2:-}"
fi
