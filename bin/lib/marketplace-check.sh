#!/usr/bin/env bash
# marketplace-check.sh — is every CONFIRMED Marketplace "Buy" in architecture/fit-gap.md
# actually installed in the model?
#
# WHY THIS EXISTS. architecture-blueprint.md Step 4 decides "Buy"; brd-to-build-plan.md Step 0
# says to install it before the first domain-model script. Both were prose. A confirmed Buy that
# never got installed was found only when an MDL script referenced the module and failed
# reference validation, or when someone noticed the capability was simply missing. Nothing
# compared the decision with the model.
#
# WHAT IT READS (and who produces it — CLAUDE.md "Shipping an instrument" rule 5):
#   architecture/fit-gap.md   written by architect-agent at Stage 3 (architecture-blueprint.md
#                             Step 4; artifact-manifest.tsv row `fit-gap`). A confirmed Buy row
#                             names the package in backticks in its "Mendix approach" cell.
#   the model's SHOW MODULES  read live: `<mxcli> -p <mpr> -c "SHOW MODULES"`, the same call
#                             project-bin/review-module.sh makes. Parsed by
#                             pipelines/mendix-mpr/lib/own-modules.awk (want=marketplace), the one
#                             parser of that table — golden input tests/wave2/fixtures/show-modules/
#                             and fixtures/rehost-list-modules/field-service-template-9.24.2.txt.
#   <model dir>/widgets/<Name>.mpk   a widget-only package never appears in SHOW MODULES.
#
# VERDICTS (one line, "Marketplace installs: <VERDICT> — ..."):
#   N/A      no PROJECT.md and no architecture/ — not a pipeline project
#   ADOPTED  the register says the project joined above Stage 5
#   PENDING  no fit-gap yet; no table in it with a verdict column (so nothing was parsed); a Buy
#            row not resolved (any verdict cell that mentions Buy but is not exactly "Buy"); a
#            confirmed Buy naming no package; no model yet; or the model could not be read (no
#            mxcli, timeout, unparseable output) — an instrument that could not measure never
#            reports FAIL. A resolved part is shown alongside ("confirmed: ...").
#   PASS     every confirmed Buy installed (or waived); "0 of 0" only when a verdict table WAS
#            parsed and holds no Buy row at all
#   WAIVED   every confirmed Buy waived: `gate-check.sh --waive marketplace/<Name> --reason ...`
#   FAIL     a Buy is confirmed AND the model exists AND SHOW MODULES was read AND the package is
#            not there. Dominates PENDING: an unresolved row elsewhere does not hide it.
# Also set: MXTK_MKT_CONF_STATUS (the confirmed rows alone: NONE/PASS/WAIVED/PENDING/FAIL).
#
# WHERE IT BLOCKS. Nowhere in a stage verdict: gate-check prints the line, Stage 5 is not
# changed by it (projects whose Stage 5 exit is recorded must not flip). It blocks BEFORE the
# build instead, where the install belongs (brd-to-build-plan.md Step 0): `gate-check.sh
# <p> build-ready` counts a FAIL, and project-bin/exec.sh refuses a domain-model script on one.
# Neither blocks `mxcli marketplace install` or `--waive marketplace/...` (guard rule 7).
#
# Model and mxcli are found by project-bin/_common.sh's own find_mpr / find_project_mxcli
# (sourced in a subshell with PROJECT_ROOT pinned, as bin/lib/artifact-check.sh does), so the
# layouts, MPR_FILE, toolkit.env and the Windows ELF probe are the crash net's, not a copy.
#
# Sourced by bin/gate-check.sh (after obligation-check.sh, whose register parser it reuses),
# bin/doctor.sh (mxtk_mkt_buys only) and project-bin/exec.sh. Bash 3.2 safe.

_MKT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_MKT_AWK="${MXTK_OWN_MODULES_AWK:-$_MKT_LIB_DIR/../../pipelines/mendix-mpr/lib/own-modules.awk}"
_MKT_COMMON="${MXTK_COMMON_SH:-$_MKT_LIB_DIR/../../project-bin/_common.sh}"

# mxtk_mkt_buys <fit-gap.md> — one line per Buy row, tab-separated:
#   confirmed  <name> <line>   verdict cell, markup stripped and trimmed, is exactly "buy"
#                              (any case) and a `Name` in backticks names the package
#   unnamed    -      <line>   exactly "buy", but no `Name` in backticks to check against
#   unresolved -      <line>   any other verdict cell holding the word Buy: "Buy (unverified)",
#                              "Buy (deferred, not for POC)", "Buy + Build", "Buy decision: none",
#                              "**Buy** — decide if needed", "Native ... otherwise **Buy**"
#   parsed     <tables> <rows> always last: verdict tables found, data rows read in them
# A table's verdict column is found in its FIRST row (the header): "Verdict", "Decision", or a
# slash list naming Buy ("Build/Buy/Config/Gap"); the "...approach..." column holds the package.
# A table with no such header is not a fit-gap table and is skipped.
mxtk_mkt_buys() {
  [ -s "$1" ] || { printf 'parsed\t0\t0\n'; return 0; }
  tr -d '\r' < "$1" | awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function bare(s) { s = tolower(s); gsub(/[*_`]/, "", s); return trim(s) }
    function tick(s,   t) { if (match(s, /`[^`]+`/)) { t = substr(s, RSTART + 1, RLENGTH - 2)
        sub(/^widgets\//, "", t); sub(/\.mpk$/, "", t); return trim(t) } return "" }
    !/^[ \t]*\|/ { row = 0; vcol = 0; acol = 0; next }
    /^[ \t]*\|[ \t:|-]+$/ { next }
    {
      row++
      if (row == 1) {
        alt = 0
        for (i = 2; i < NF; i++) { h = bare($i)
          if (!vcol && h ~ /^verdict([^a-z]|$)/) vcol = i
          if (!alt && (h ~ /^decision([^a-z]|$)/ || h ~ /(^|\/) *buy *\/|\/ *buy *$/)) alt = i
          if (h ~ /approach/) acol = i }
        if (!vcol) vcol = alt
        if (vcol) ntab++
        next
      }
      if (!vcol) next
      nrow++
      v = bare($vcol)
      if (v != "buy") { if (v ~ /(^|[^a-z])buy([^a-z]|$)/) print "unresolved\t-\t" NR; next }
      name = ""
      if (acol) name = tick($acol)
      if (name == "") name = tick($vcol)
      if (name == "") for (i = 3; i < NF && name == ""; i++) if (i != vcol) name = tick($i)
      if (name !~ /^[A-Za-z0-9_.-]+$/) { print "unnamed\t-\t" NR; next }
      print "confirmed\t" name "\t" NR
    }
    END { printf "parsed\t%d\t%d\n", ntab, nrow }'
}

# _mkt_locate <root> — sets _MKT_MPR (the .mpr, "AMBIGUOUS", or empty) and _MKT_MX (the
# project's mxcli, or empty) through project-bin/_common.sh. $MXCLI wins for the binary, as
# before. Without _common.sh beside the toolkit (a stripped install) both stay empty -> PENDING.
_mkt_locate() {
  local root="$1" out
  _MKT_MPR=""; _MKT_MX=""
  [ -f "$_MKT_COMMON" ] || return 0
  out="$( export PROJECT_ROOT="$root"; . "$_MKT_COMMON" >/dev/null 2>&1 || exit 0
          m="$(find_mpr 2>&1)" && printf 'mpr\t%s\n' "$m" || {
            case "$m" in *"refusing to guess"*) printf 'mpr\tAMBIGUOUS\n' ;; esac; }
          x="$(find_project_mxcli 2>/dev/null)" && printf 'mx\t%s\n' "$x"
          exit 0 )"
  local IFS=$'\n' l
  for l in $out; do
    case "$l" in
      mpr$'\t'*) [ -n "$_MKT_MPR" ] || _MKT_MPR="${l#*$'\t'}" ;;
      mx$'\t'*)  [ -n "$_MKT_MX" ]  || _MKT_MX="${l#*$'\t'}" ;;
    esac
  done
  [ -n "${MXCLI:-}" ] && _MKT_MX="$MXCLI"
  return 0
}

# Portable timeout (macOS ships no timeout(1)); rc 124 on expiry.
_mkt_with_timeout() {
  local secs="$1"; shift
  "$@" & local child=$!
  ( sleep "$secs"; kill -9 "$child" 2>/dev/null ) & local dog=$!
  wait "$child" 2>/dev/null; local rc=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
  [ "$rc" -eq 137 ] && return 124
  return "$rc"
}

# _mkt_waived <register> <Name> — prints the reason, rc 0 when waived. Register spelling:
#     Waived marketplace Charts: the client licenses it separately   (one package)
#     Waived marketplace: installs are done by the client's admin     (all)
_mkt_waived() {
  local reg="$1" want_u want_a line key
  [ -f "$reg" ] || return 1
  type _ob_register_norm >/dev/null 2>&1 || . "$_MKT_LIB_DIR/obligation-check.sh"
  _ob_lc "waived marketplace $2"; want_u="$_OB_LC"
  _ob_lc "waived marketplace";    want_a="$_OB_LC"
  _ob_register_norm "$reg"
  local IFS=$'\n'
  for line in $_OB_REG_NORM; do
    key="${line%%$'\t'*}"
    if [ "$key" = "$want_u" ] || [ "$key" = "$want_a" ]; then printf '%s\n' "${line#*$'\t'}"; return 0; fi
  done
  return 1
}

_mkt_adopted_rank() { # rank of "Adopted at stage" (P=0, 0=1 ... 7=8), 0 when none
  local reg="$1" a
  [ -f "$reg" ] || { echo 0; return; }
  type _ob_adopted_stage >/dev/null 2>&1 || . "$_MKT_LIB_DIR/obligation-check.sh"
  a="$(_ob_adopted_stage "$reg" || true)"
  case "$a" in [0-7]) echo $((a + 1)) ;; *) echo 0 ;; esac
}

_mkt_set() { MXTK_MKT_STATUS="$1"; MXTK_MKT_NOTE="$2"; printf 'Marketplace installs: %s — %s\n' "$1" "$2"; }

# _mkt_lines <rows> <state> — the line numbers of one state, "a, b, c".
_mkt_lines() { printf '%s\n' "$1" | awk -F'\t' -v s="$2" '$1==s{printf "%s%s", sep, $3; sep=", "}'; }

# mxtk_mkt_report <project-dir> <register> [fit-gap path]
# Prints one line; sets MXTK_MKT_STATUS, MXTK_MKT_NOTE and MXTK_MKT_CONF_STATUS.
mxtk_mkt_report() {
  local root="$1" reg="${2:-$1/PROJECT.md}" fg="${3:-}"
  MXTK_MKT_STATUS=""; MXTK_MKT_NOTE=""; MXTK_MKT_CONF_STATUS=""
  type _ob_lc >/dev/null 2>&1 || . "$_MKT_LIB_DIR/obligation-check.sh"
  [ -n "$fg" ] || { [ -s "$root/architecture/fit-gap.md" ] && fg="$root/architecture/fit-gap.md"; }
  if [ ! -f "$reg" ] && [ ! -d "$root/architecture" ]; then
    _mkt_set N/A "no PROJECT.md and no architecture/; not a pipeline project"; return 0
  fi
  # Owed from Stage 5 (the build installs it, brd-to-build-plan.md Step 0). Joined above it: not owed.
  if [ "$(_mkt_adopted_rank "$reg")" -gt 6 ]; then
    _mkt_set ADOPTED "project joined above Stage 5; installs were not made here"; return 0
  fi
  if [ -z "$fg" ]; then
    _mkt_set PENDING "no architecture/fit-gap.md yet (architecture-blueprint.md Step 4)"; return 0
  fi
  local rel="${fg#$root/}" rows parsed n_tab n_row n_conf n_unres n_unnamed
  rows="$(mxtk_mkt_buys "$fg")"
  parsed="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="parsed"{print $2 " " $3}')"
  n_tab="${parsed%% *}"; n_row="${parsed##* }"
  n_conf="$(printf '%s\n' "$rows" | grep -c '^confirmed	')"
  n_unres="$(printf '%s\n' "$rows" | grep -c '^unresolved	')"
  n_unnamed="$(printf '%s\n' "$rows" | grep -c '^unnamed	')"
  if [ "${n_tab:-0}" -eq 0 ]; then
    _mkt_set PENDING "no table in $rel has a Verdict / Decision / Build/Buy/... column, so no row was read (architecture-blueprint.md Step 4 table)"; return 0
  fi
  if [ "$n_conf" -eq 0 ] && [ "$n_unres" -eq 0 ] && [ "$n_unnamed" -eq 0 ]; then
    MXTK_MKT_CONF_STATUS=NONE
    _mkt_set PASS "0 of 0: $n_row row(s) in $n_tab verdict table(s) of $rel, no Buy row, nothing to install"; return 0
  fi
  # What keeps the result open, whatever the confirmed rows say. The remedy names both ways out,
  # because "Buy (unverified)" left in place stays PENDING for ever.
  local open_note=""
  [ "$n_unres" -gt 0 ] && open_note="$n_unres Buy row(s) in $rel not resolved (line $(_mkt_lines "$rows" unresolved)): the Verdict cell must read exactly **Buy** with the package in backticks in the Mendix approach cell, or a non-Buy verdict (Build, Config, Native, Gap)"
  [ "$n_unnamed" -gt 0 ] && open_note="${open_note:+$open_note; }$n_unnamed confirmed Buy row(s) name no package (line $(_mkt_lines "$rows" unnamed)): put the module or .mpk name in backticks in the Mendix approach cell"

  _mkt_confirmed "$root" "$reg" "$rows"
  MXTK_MKT_CONF_STATUS="$_MKT_C_STATUS"
  _mkt_remember "$root" "$rows" "$_MKT_C_STATUS"
  if [ "$_MKT_C_STATUS" = FAIL ]; then
    _mkt_set FAIL "$_MKT_C_NOTE${open_note:+; also $open_note}"
  elif [ -n "$open_note" ]; then
    _mkt_set PENDING "$open_note; confirmed: ${_MKT_C_NOTE:-none}"
  else
    _mkt_set "$_MKT_C_STATUS" "$_MKT_C_NOTE"
  fi
  return 0
}

# _mkt_remember <root> <rows> <confirmed-status> — project-bin/exec.sh's install gate skips the
# SHOW MODULES read when .claude/loop/marketplace-ok.txt holds exactly the current confirmed list
# (lower case, sorted, space-separated). Written on PASS/WAIVED by whichever caller ran the check,
# removed on FAIL; a project with no .claude/ gets no file (nothing is created for it).
_mkt_remember() {
  local f="$1/.claude/loop/marketplace-ok.txt" list
  [ -d "$1/.claude" ] || return 0
  case "$3" in
    PASS|WAIVED)
      list="$(printf '%s\n' "$2" | awk -F'\t' '$1=="confirmed"{print tolower($2)}' | sort -u | tr '\n' ' ')"
      mkdir -p "${f%/*}" 2>/dev/null && printf '%s' "$list" > "$f" 2>/dev/null ;;
    FAIL) rm -f "$f" 2>/dev/null ;;
  esac
  return 0
}

_mkt_c() { _MKT_C_STATUS="$1"; _MKT_C_NOTE="$2"; }

# _mkt_confirmed <root> <register> <rows> — the confirmed rows alone. Sets _MKT_C_STATUS
# (NONE/PASS/WAIVED/PENDING/FAIL) and _MKT_C_NOTE; prints nothing.
_mkt_confirmed() {
  local root="$1" reg="$2" rows="$3"
  _MKT_C_STATUS=NONE; _MKT_C_NOTE=""
  local names n_conf name reason todo="" n_waived=0 n_ok=0 mpr="" mdir=""
  names="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="confirmed"{print $2}' | awk '!seen[tolower($0)]++')"
  n_conf="$(printf '%s\n' "$names" | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "$n_conf" -gt 0 ] || return 0
  _mkt_locate "$root"; mpr="$_MKT_MPR"
  [ -n "$mpr" ] && [ "$mpr" != AMBIGUOUS ] && mdir="${mpr%/*}"

  # Waivers and widget .mpk files need no model read.
  local f lw
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if reason="$(_mkt_waived "$reg" "$name")"; then n_waived=$((n_waived+1)); continue; fi
    if [ -n "$mdir" ] && [ -d "$mdir/widgets" ]; then
      _ob_lc "$name.mpk"; lw="$_OB_LC"
      for f in "$mdir"/widgets/*.mpk; do
        [ -f "$f" ] || continue
        _ob_lc "${f##*/}"
        [ "$_OB_LC" = "$lw" ] && { n_ok=$((n_ok+1)); continue 2; }
      done
    fi
    todo="$todo$name
"
  done <<EOF
$names
EOF

  local tail="" scoped=$((n_conf - n_waived)) list
  [ "$n_waived" -gt 0 ] && tail=" ($n_waived waived)"
  list="$(printf '%s' "$todo" | tr '\n' ' ' | sed 's/^/ /;s/ $//')"
  if [ -z "$todo" ]; then
    if [ "$scoped" -eq 0 ]; then _mkt_c WAIVED "all $n_conf confirmed Buy package(s) waived in $(basename "$reg")"
    else _mkt_c PASS "$n_ok of $scoped confirmed Buy installed$tail"; fi
    return 0
  fi
  if [ -z "$mpr" ]; then
    _mkt_c PENDING "$n_ok of $scoped confirmed Buy installed$tail; no model yet, so not checked:$list"; return 0
  fi
  if [ "$mpr" = AMBIGUOUS ]; then
    _mkt_c PENDING "more than one .mpr; set MPR_FILE to choose, nothing checked"; return 0
  fi
  local mx="$_MKT_MX" out rc tmp
  if [ -z "$mx" ]; then
    _mkt_c PENDING "no project mxcli (or \$MXCLI), so SHOW MODULES was not read; not checked:$list"; return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/mkt-mods.XXXXXX")" || { _mkt_c PENDING "could not create a temp file; nothing checked"; return 0; }
  _mkt_with_timeout "${MXTK_MKT_TIMEOUT:-60}" "$mx" -p "$mpr" -c "SHOW MODULES" > "$tmp" 2>/dev/null; rc=$?
  out="$(cat "$tmp")"; rm -f "$tmp"
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^|-'; then
    _mkt_c PENDING "SHOW MODULES could not be read (exit $rc$( [ "$rc" = 124 ] && echo ', timed out' )); nothing checked"; return 0
  fi
  local mkt own missing="" n_missing=0 lname cmds="" fromfile=""
  mkt="$(printf '%s\n' "$out" | awk -F'|' -v want=marketplace -f "$_MKT_AWK")"
  own="$(printf '%s\n' "$out" | awk -F'|' -f "$_MKT_AWK")"
  _ob_lc "$mkt"; mkt=$'\n'"$_OB_LC"$'\n'
  _ob_lc "$own"; own=$'\n'"$_OB_LC"$'\n'
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    _ob_lc "$name"; lname="$_OB_LC"
    case "$mkt" in *$'\n'"$lname"$'\n'*) n_ok=$((n_ok+1)); continue ;; esac
    # Present by name with an empty Source: the module IS there — imported from a .mpk file,
    # or an older mxcli that leaves Source blank. That is evidence the gate did not create
    # (guard rule 6), so it counts, with a note, rather than failing an install that happened.
    case "$own" in *$'\n'"$lname"$'\n'*) n_ok=$((n_ok+1)); fromfile="$fromfile${fromfile:+, }$name"; continue ;; esac
    n_missing=$((n_missing+1))
    missing="$missing $name,"
    cmds="$cmds${cmds:+; }mxcli marketplace search \"$name\""
  done <<EOF
$todo
EOF
  local fnote=""
  [ -n "$fromfile" ] && fnote="; $fromfile present, Source empty — imported from file? (counted as installed)"
  if [ "$n_missing" -eq 0 ]; then
    _mkt_c PASS "$n_ok of $scoped confirmed Buy installed$tail$fnote"; return 0
  fi
  _mkt_c FAIL "$n_ok of $scoped confirmed Buy installed$tail; NOT INSTALLED:${missing%,} — install: $cmds; then mxcli marketplace install <content-id> -p $(basename "$mpr") for each (a widget-only package lands as widgets/<Name>.mpk instead; brd-to-build-plan.md Step 0), or gate-check.sh --waive marketplace/<Name> --reason \"...\"$fnote"
  return 0
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  mxtk_mkt_report "${1:-$(pwd)}" "${2:-${1:-$(pwd)}/PROJECT.md}" "${3:-}"
fi
