#!/usr/bin/env bash
# kickoff.sh — write a project's kickoff declarations in the exact form the gates parse.
#
# usage: bin/kickoff.sh <project-root> --mode <poc|requirements-driven|migration|change>
#                       [--build-type <full|poc>] [--interview <steering|assist|auto>]
#                       [--answers <file>] [--by <person who answered>] [--dry-run]
#
# WHY (#821 point 3; two simulated builds, 2026-11-20). Kickoff was hand-assembled from prose: both
# agents wrote the 16 intake answer markers and the register lines with ad-hoc Python heredocs, and
# the POC agent read three scripts to find an `Entry mode:` value it could legally write (there was
# none). That was 13-15 calls before any project content. This writes, in one call:
#   - PROJECT.md: `Entry mode:`, `Build type:` and `Interview mode:` lines and one Stage-P Decisions
#     row each — CONFIRMED (consentBy <person> · consentAt <date>) ONLY with --by <person>, the person
#     who gave the answers; without --by the row is ASSUMED, "no person named", because nobody's
#     consent can be inferred from a command line (review of #828) — and under `Interview mode: auto`
#     one Assumptions line per intake default it assumed. Re-running with --by upgrades kickoff's
#     own rows and markers;
#   - intake.md: one answer marker per '## N.' section, in a form check_stage_P accepts —
#     Q1 (mode), Q9 (interview) and Q16 (build type) from the flags; any question in --answers as
#     answers; an unstated --build-type / --interview is left UNANSWERED under steering/assist (Q16 is
#     the question asked first; it is listed, never assumed) and assumed (full / steering) under auto
#     only; under a POC build the rest get poc-build.md's verbatim
#     `Unverified — how to verify: not asked, POC build ...`; under auto the rest get
#     `Assumed (auto-mode): <the template's default>` where the template states one, else
#     `Unverified — how to verify: not asked at kickoff (Interview mode: auto) ...`; under
#     steering/assist the rest stay unanswered and are listed (they must be asked in chat);
# then runs `gate-check.sh <project> P` and prints its verdict.
#
# IDEMPOTENT: the same call twice changes nothing the second time. It never overwrites a real
# answer with a default, and it REFUSES (exit 3) to change an Entry mode, Build type or Interview
# mode the register already declares differently: a mode change is a decision (conversion-
# runbook.md → Entry Modes, "Mode changes are decisions"), recorded by a person, not a re-run.
# (init-project.sh's `Build type: full` default line is not a declaration: it is replaced.)
#
# --answers <file>: one answer per line, `Q<N>: <text>` or `<N>: <text>` (N = 2-8, 10-15; Q1, Q9 and
# Q16 come from the flags); blank lines and #-comments ignored.
#
# Exit: 0 written (or nothing to change) · 2 usage: an unknown flag or value, with the accepted list,
#       or no init-project.sh scaffold · 3 refused: it would change a declared mode.
# Producer of what it reads: PROJECT.md and intake.md come from bin/init-project.sh (mandatory first
# step of the kick-off brief, CONVERSION-RUNBOOK.md). Bash 3.2 safe; awk only, no GNU-only flags.
set -uo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODES="poc requirements-driven migration change"
BUILDS="full poc"
INTERVIEWS="steering assist auto (aliases: attended = steering, unattended = auto)"

usage() { sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die2() { echo "kickoff: $1" >&2; exit 2; }

PROJECT=""; MODE=""; BUILD=""; IVIEW=""; ANSWERS=""; BY=""; DRY=0
BUILD_SET=0; IVIEW_SET=0   # given on the command line (CONFIRMED) or defaulted (ASSUMED)
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)       [ $# -ge 2 ] || die2 "--mode needs a value: $MODES"; MODE="$2"; shift 2 ;;
    --build-type) [ $# -ge 2 ] || die2 "--build-type needs a value: $BUILDS"; BUILD="$2"; BUILD_SET=1; shift 2 ;;
    --interview)  [ $# -ge 2 ] || die2 "--interview needs a value: $INTERVIEWS"; IVIEW="$2"; IVIEW_SET=1; shift 2 ;;
    --answers)    [ $# -ge 2 ] || die2 "--answers needs a file"; ANSWERS="$2"; shift 2 ;;
    --by)         [ $# -ge 2 ] || die2 "--by needs a name"; BY="$2"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           die2 "unknown option '$1' — accepted: --mode --build-type --interview --answers --by --dry-run --help" ;;
    *)            [ -z "$PROJECT" ] || die2 "one project root only (got '$PROJECT' and '$1')"; PROJECT="$1"; shift ;;
  esac
done
[ -n "$PROJECT" ] || usage
[ -n "$MODE" ] || die2 "--mode is required — accepted: $MODES"
case "$MODE" in poc|requirements-driven|migration|change) ;; *) die2 "unknown --mode '$MODE' — accepted: $MODES" ;; esac
case "$BUILD" in "") if [ "$MODE" = poc ]; then BUILD=poc; BUILD_SET=1; fi ;; full|poc) ;; *) die2 "unknown --build-type '$BUILD' — accepted: $BUILDS" ;; esac
[ "$MODE" = poc ] && [ "$BUILD" = full ] && die2 "--mode poc is a POC build; --build-type full contradicts it (a full build declares requirements-driven, migration or change)"
case "$IVIEW" in
  "") ;; steering|attended) IVIEW=steering ;; assist) ;; auto|unattended) IVIEW=auto ;;
  *) die2 "unknown --interview '$IVIEW' — accepted: $INTERVIEWS" ;;
esac
[ -d "$PROJECT" ] || die2 "not a directory: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
REG="$PROJECT/PROJECT.md"; INTAKE="$PROJECT/intake.md"
[ -f "$REG" ] && [ -f "$INTAKE" ] || die2 "no PROJECT.md / intake.md in $PROJECT — run bin/init-project.sh $PROJECT first"
case "$BY" in *"|"*|*"("*|*")"*) die2 "--by must not contain '|', '(' or ')' (it lands in a table cell and an intake marker)" ;; esac
# Under auto an unstated build type is the toolkit default, full (auto never picks poc, poc-build.md).
[ -z "$BUILD" ] && [ "$IVIEW" = auto ] && BUILD=full

case "$MODE" in
  poc) ENTRY="poc" ;; requirements-driven) ENTRY="requirements-driven" ;; migration) ENTRY="migration" ;;
  change) ENTRY="Change an existing app" ;;   # verbatim, as intake Q1 asks it to be recorded
esac
TODAY="$(date -u +%Y-%m-%d)"

# ── answers file → ANS_<N> ─────────────────────────────────────────────────────────────────
if [ -n "$ANSWERS" ]; then
  [ -f "$ANSWERS" ] || die2 "--answers file not found: $ANSWERS"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    if [[ "$line" =~ ^[[:blank:]]*[Qq]?([0-9]+)[[:blank:]]*[:.][[:blank:]]*(.+)$ ]]; then
      n="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"; n=$((10#$n))
      case "$n" in
        1|9|16) die2 "--answers line '$line': Q$n is set by $( [ "$n" = 1 ] && echo --mode || { [ "$n" = 9 ] && echo --interview || echo --build-type; } )" ;;
        2|3|4|5|6|7|8|10|11|12|13|14|15) eval "ANS_$n=\$v" ;;
        *) die2 "--answers line '$line': no intake question $n (questions 2-8 and 10-15)" ;;
      esac
    else
      die2 "--answers line not understood: '$line' — write 'Q<N>: <answer>'"
    fi
  done < "$ANSWERS"
fi

# ── the register: read what is declared ───────────────────────────────────────────────────
# reg_get <key> → the first uncommented "<key>: value" line's value (emphasis stripped), or empty.
reg_get() {
  awk -v k="$1" '
    /<!--/ { if ($0 !~ /-->/) inc = 1; next }
    inc { if ($0 ~ /-->/) inc = 0; next }
    { l = $0; gsub(/\r/, "", l); sub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l)
      i = index(l, ":"); if (i == 0) next
      key = tolower(substr(l, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
      if (key != tolower(k)) next
      v = substr(l, i + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); if (v == "") next
      print v; exit }' "$REG"
}
has_kick_row() { grep -qE "^\\|[[:blank:]]*P[[:blank:]]*\\|[[:blank:]]*$1:" "$REG"; }

. "$TOOLKIT_DIR/bin/lib/entry-mode.sh"
cur_entry="$(reg_get "entry mode")"; cur_build="$(reg_get "build type")"; cur_iv="$(reg_get "interview mode")"
refuse=""
if [ -n "$cur_entry" ] && [ "$(entry_mode_token "$cur_entry" 2>/dev/null)" != "$(entry_mode_token "$ENTRY" 2>/dev/null)" ]; then
  refuse="${refuse}  Entry mode: the register says '$cur_entry', this call says '$ENTRY'"$'\n'
fi
cb="$(printf '%s' "$cur_build" | tr '[:upper:]' '[:lower:]')"; cb="${cb%%[!a-z]*}"
if [ -n "$BUILD" ] && [ -n "$cb" ] && [ "$cb" != "$BUILD" ] && has_kick_row "Build type"; then
  refuse="${refuse}  Build type: the register says '$cur_build' (a Decisions row records it), this call says '$BUILD'"$'\n'
fi
civ="$(printf '%s' "$cur_iv" | tr '[:upper:]' '[:lower:]')"; civ="${civ%%[!a-z]*}"
case "$civ" in attended) civ=steering ;; unattended) civ=auto ;; esac
if [ -n "$IVIEW" ] && [ -n "$civ" ] && [ "$civ" != "$IVIEW" ]; then
  refuse="${refuse}  Interview mode: the register says '$cur_iv', this call says '$IVIEW'"$'\n'
fi
if [ -n "$refuse" ]; then
  echo "kickoff: REFUSED — $REG already declares something else; nothing was written:" >&2
  printf '%s' "$refuse" >&2
  echo "  A mode change is a decision (conversion-runbook.md → Entry Modes, \"Mode changes are decisions\"): a person" >&2
  echo "  records it in PROJECT.md (the line and a Decisions row with the reason); kickoff.sh only writes a first declaration." >&2
  exit 3
fi

# ── edits, applied to temp copies, then moved in one go ───────────────────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kickoff.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
cp "$REG" "$TMP/reg"; cp "$INTAKE" "$TMP/intake"
CHANGES=""

# set_line <key> <value> — replace the first uncommented "<key>:" line, else insert after the
# "Build type:" line (init writes it), else after "Toolkit commit:", else before "## Decisions".
set_line() {
  local k="$1" v="$2"
  [ "$(reg_get_tmp "$k")" = "$v" ] && return 0
  KO_K="$k" KO_V="$v" awk '
    BEGIN { k = ENVIRON["KO_K"]; v = ENVIRON["KO_V"]; lk = tolower(k) }
    /<!--/ && !inc { if ($0 !~ /-->/) inc = 1; print; next }
    inc { if ($0 ~ /-->/) inc = 0; print; next }
    { l = tolower($0); sub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l) }
    !done && index(l, lk ":") == 1 { print k ": " v; done = 1; next }
    { print }
  ' "$TMP/reg" > "$TMP/reg.1"
  if [ "$(REG="$TMP/reg.1" reg_get "$k")" != "$v" ]; then
    # Not there yet: after "Build type:" (init writes it), else "Toolkit commit:", else before "## Decisions".
    KO_K="$k" KO_V="$v" awk '
      BEGIN { k = ENVIRON["KO_K"]; v = ENVIRON["KO_V"]
              while ((getline l < ARGV[1]) > 0) { if (l ~ /^Build type:/) a = "b"; else if (!a && l ~ /^Toolkit commit:/) t = 1 }
              close(ARGV[1]); if (!a) a = (t ? "t" : "d") }
      !done && a == "b" && /^Build type:/ { print; print k ": " v; done = 1; next }
      !done && a == "t" && /^Toolkit commit:/ { print; print k ": " v; done = 1; next }
      !done && a == "d" && /^## Decisions/ { print k ": " v; print ""; done = 1 }
      { print }' "$TMP/reg.1" > "$TMP/reg.2"
    mv "$TMP/reg.2" "$TMP/reg.1"
  fi
  mv "$TMP/reg.1" "$TMP/reg"
  CHANGES="${CHANGES}  PROJECT.md: $k: $v"$'\n'
}
reg_get_tmp() { REG="$TMP/reg" reg_get "$1"; }

# add_row <decision-text> <status> <notes> — a Stage-P row in the Decisions table. A row with the
# same decision and status is left alone (idempotent, whatever its date); a different row that
# kickoff.sh wrote for the same key is replaced (an ASSUMED row upgraded by --by); a row a person
# wrote for that key is never touched.
add_row() {
  local d="$1" st="$2" notes="$3" key="${1%%:*}" old
  grep -qF "| P | $d | $st |" "$TMP/reg" && return 0
  old="$(grep -E "^\\|[[:blank:]]*P[[:blank:]]*\\|[[:blank:]]*$key:" "$TMP/reg" | head -1)"
  if [ -n "$old" ]; then
    case "$old" in *"(bin/kickoff.sh)"*) ;; *) return 0 ;; esac
    KO_OLD="$old" awk 'BEGIN { o = ENVIRON["KO_OLD"] } $0 == o && !d { d = 1; next } { print }' "$TMP/reg" > "$TMP/reg.0" && mv "$TMP/reg.0" "$TMP/reg"
  fi
  KO_ROW="| P | $d | $st | $notes |" awk '
    BEGIN { row = ENVIRON["KO_ROW"] }
    /^\| *Stage *\| *Decision/ { intab = 1; print; next }
    intab && /^\|/ { print; next }
    intab { print row; intab = 0; added = 1 }
    { print }
    END { if (intab && !added) print row }' "$TMP/reg" > "$TMP/reg.1"
  grep -qF "| P | $d |" "$TMP/reg.1" || { echo "kickoff: no '| Stage | Decision | Status | Notes |' table in PROJECT.md — run bin/sync-project.sh $PROJECT (it appends the register sections)" >&2; exit 2; }
  mv "$TMP/reg.1" "$TMP/reg"
  CHANGES="${CHANGES}  PROJECT.md: Decisions row P — $d ($st)"$'\n'
}

# add_assumption <id> <text> — one line under "## Assumptions (ASSUMED, unresolved)", by id.
add_assumption() {
  grep -qF -- "- $1:" "$TMP/reg" && return 0
  KO_LINE="- $1: $2" awk '
    BEGIN { line = ENVIRON["KO_LINE"] }
    /^## Assumptions/ { print; ina = 1; next }
    ina && /^None yet\.?[ \t]*$/ { next }
    ina && /^## / { print line; print ""; ina = 0; done = 1 }
    { print }
    END { if (ina && !done) print line }' "$TMP/reg" > "$TMP/reg.1"
  if grep -qF -- "- $1:" "$TMP/reg.1"; then mv "$TMP/reg.1" "$TMP/reg"
  else { cat "$TMP/reg"; printf '\n## Assumptions (ASSUMED, unresolved)\n\n- %s: %s\n' "$1" "$2"; } > "$TMP/reg.1"; mv "$TMP/reg.1" "$TMP/reg"; fi
  CHANGES="${CHANGES}  PROJECT.md: assumption $1"$'\n'
}

# mark <N> <marker-line> <force:1|0> — the answer marker of intake section N. A section that
# already carries a marker keeps it unless force=1 (an explicit flag or --answers line) and it
# differs; "_Not yet asked._ " is dropped from the section once it has an answer.
# marker_of <N> → section N's first marker line (lower-cased), by check_stage_P's own test.
marker_of() {
  awk -v n="$1" '
    $0 ~ "^## " n "\\." { ins = 1; next } ins && /^## / { exit }
    ins { l = $0; gsub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l); l = tolower(l)
          if (l ~ /^(answered|answer|a|decision|assumed)[ \t]*(\([^)]*\))?[ \t]*:/ || (l ~ /^unverified/ && l ~ /how to verify/)) { print l; exit } }' "$TMP/intake"
}
mark() {
  local n="$1" m="$2" force="$3" have
  have="$(marker_of "$n")"
  if [ -n "$have" ]; then
    [ "$force" = 1 ] || return 0
    [ "$have" = "$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')" ] && return 0
  fi
  KO_M="$m" awk -v n="$n" '
    BEGIN { m = ENVIRON["KO_M"] }
    $0 ~ "^## " n "\\." { print; print ""; print m; ins = 1; next }
    ins && /^## / { ins = 0 }
    ins { l = $0; gsub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l); l = tolower(l)
          if (l ~ /^(answered|answer|a|decision|assumed)[ \t]*(\([^)]*\))?[ \t]*:/ || (l ~ /^unverified/ && l ~ /how to verify/)) next
          sub(/^_Not yet asked\._ ?/, "") }
    { print }' "$TMP/intake" > "$TMP/intake.1"
  # The blank line the insert adds is not doubled on a re-run: squeeze runs of blank lines.
  awk 'NF == 0 { if (blank) next; blank = 1; print; next } { blank = 0; print }' "$TMP/intake.1" > "$TMP/intake"
  CHANGES="${CHANGES}  intake.md Q$n: $m"$'\n'
}

# CONFIRMED needs a person: --by names who gave these answers. Without it a stated value is still
# recorded, ASSUMED, "no person named" — never consent nobody gave (review of #828).
if [ -n "$BY" ]; then
  ST=CONFIRMED; NOTE="kickoff (bin/kickoff.sh) — consentBy: $BY · consentAt: $TODAY"; ANS="Answered (CONFIRMED by $BY)"
else
  ST=ASSUMED; NOTE="kickoff (bin/kickoff.sh), stated in the kickoff call, no person named — consentBy: none yet · consentAt: $TODAY; re-run with --by <name> once a person has answered"
  ANS="Answered (kickoff call, no person named)"
fi
# Under auto only: a build type the call did not state is the default, full, ASSUMED by auto-mode.
DEF="kickoff (bin/kickoff.sh), the default because the call did not state it — consentBy: auto-mode · consentAt: $TODAY; a person confirms or overturns it"
set_line "Entry mode" "$ENTRY"
[ -n "$BUILD" ] && set_line "Build type" "$BUILD"
[ -n "$IVIEW" ] && set_line "Interview mode" "$IVIEW"
add_row "Entry mode: $ENTRY" "$ST" "$NOTE"
if [ "$BUILD_SET" = 1 ]; then add_row "Build type: $BUILD" "$ST" "$NOTE"
elif [ -n "$BUILD" ]; then add_row "Build type: $BUILD" ASSUMED "$DEF"; fi
[ -n "$IVIEW" ] && add_row "Interview mode: $IVIEW" "$ST" "$NOTE"

case "$MODE" in poc) Q1="poc — a demo (Build type: poc, skills/poc-build.md)" ;; *) Q1="$ENTRY" ;; esac
mark 1 "$ANS: $Q1" 1
POC_MARK="Unverified — how to verify: not asked, POC build (Build type: poc, skills/poc-build.md); ask it if the build continues as a full build"
# A POC asks no question but Q16 (poc-build.md "Who asks"): an unstated Q9 takes the POC marker.
if [ -n "$IVIEW" ]; then mark 9 "$ANS: $IVIEW" 1
elif [ "$BUILD" = poc ]; then mark 9 "$POC_MARK" 0; fi
if [ "$BUILD" = poc ]; then mark 16 "$ANS: POC build" 1
elif [ "$BUILD_SET" = 1 ]; then mark 16 "$ANS: Full build" 1
elif [ -n "$BUILD" ]; then mark 16 "Assumed (auto-mode): Full build (the default; not stated at kickoff)" 0; fi

# Defaults the intake template states (bin/lib/intake-template.sh): assumed under auto only.
default_for() {
  case "$1" in
    10) echo "starting from scratch here — nothing done outside the toolkit" ;;
    11) echo "auto" ;; 12) echo "project" ;; 13) echo "no" ;; 15) echo "balanced" ;;
    *) echo "" ;;
  esac
}
UNASKED=""
for n in 2 3 4 5 6 7 8 10 11 12 13 14 15; do
  eval "a=\${ANS_$n:-}"
  if [ -n "$a" ]; then mark "$n" "$ANS: $a" 1; continue; fi
  if [ "$BUILD" = poc ]; then mark "$n" "$POC_MARK" 0; continue; fi
  if [ "$IVIEW" = auto ]; then
    d="$(default_for "$n")"
    if [ -n "$d" ]; then
      mark "$n" "Assumed (auto-mode): $d (the intake template's default)" 0
      add_assumption "Intake Q$n" "$d — ASSUMED at kickoff under Interview mode: auto (the template's default); consentBy: auto-mode · consentAt: $TODAY; a person confirms or overturns it"
    else
      mark "$n" "Unverified — how to verify: not asked at kickoff (Interview mode: auto); a person answers it before Stage 6" 0
    fi
    continue
  fi
  [ -n "$(marker_of "$n")" ] || UNASKED="$UNASKED Q$n"
done

# Q9 / Q16 not stated (steering/assist only): asked first, listed first, never assumed.
[ -n "$BUILD" ] || [ -n "$(marker_of 16)" ] || UNASKED=" Q16$UNASKED"
[ -n "$IVIEW" ] || [ -n "$(marker_of 9)" ] || UNASKED=" Q9$UNASKED"
if [ -z "$CHANGES" ]; then
  echo "kickoff: nothing to change — $PROJECT already declares Entry mode: $ENTRY, Build type: ${BUILD:-(not stated)}, Interview mode: ${IVIEW:-(not stated)}"
else
  if [ "$DRY" = 1 ]; then echo "kickoff: DRY RUN — would write:"; printf '%s' "$CHANGES"; exit 0; fi
  cp "$TMP/reg" "$REG"; cp "$TMP/intake" "$INTAKE"
  echo "kickoff: wrote"; printf '%s' "$CHANGES"
fi
if [ -n "$UNASKED" ]; then
  echo "Still to ask in chat (Interview mode: ${IVIEW:-not stated, so steering}):$UNASKED — record each answer in intake.md, or put them in a file and re-run with --answers <file>."
fi
GC_OUT="$(bash "$TOOLKIT_DIR/bin/gate-check.sh" --no-html "$PROJECT" P 2>&1)"; GC_RC=$?
echo "Stage P: $(printf '%s\n' "$GC_OUT" | grep -m1 '^Stage P ' | sed 's/^Stage P ([^)]*): //' | cut -c1-200) (bin/gate-check.sh $PROJECT P exit $GC_RC)"
exit 0
