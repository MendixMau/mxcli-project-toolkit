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
#   PENDING  no fit-gap yet; Buy rows not yet confirmed; no model yet; or the model could not be
#            read (no mxcli, timeout, unparseable output) — an instrument that could not measure
#            never reports FAIL
#   PASS     every confirmed Buy installed (or waived); also "0 Buy rows — nothing to install"
#   WAIVED   every confirmed Buy waived: `gate-check.sh --waive marketplace/<Name> --reason ...`
#   FAIL     a Buy is confirmed AND the model exists AND SHOW MODULES was read AND the package is
#            not there. bin/gate-check.sh folds this into Stage 5.
#
# Sourced by bin/gate-check.sh (after obligation-check.sh, whose register parser it reuses) and
# bin/doctor.sh (mxtk_mkt_buys only). Bash 3.2 safe.

_MKT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_MKT_AWK="${MXTK_OWN_MODULES_AWK:-$_MKT_LIB_DIR/../../pipelines/mendix-mpr/lib/own-modules.awk}"

# mxtk_mkt_buys <fit-gap.md> — one line per Buy row: "<state>\t<name>\t<line-no>".
#   state confirmed  verdict cell starts with Buy and carries no "decide / maybe / tbd / ?"
#         unresolved the architecture-blueprint.md example form "**Buy** — decide if needed"
#         unnamed    confirmed, but no `Name` in backticks to check against
# Columns are found by header ("Verdict", "...approach..."), per table; a table with no Verdict
# header is not a fit-gap table and is skipped.
mxtk_mkt_buys() {
  [ -s "$1" ] || return 0
  tr -d '\r' < "$1" | awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function tick(s,   t) { if (match(s, /`[^`]+`/)) { t = substr(s, RSTART + 1, RLENGTH - 2)
        sub(/^widgets\//, "", t); sub(/\.mpk$/, "", t); return trim(t) } return "" }
    !/^[ \t]*\|/ { vcol = 0; acol = 0; next }
    /^[ \t]*\|[ \t:|-]+$/ { next }
    {
      if (!vcol) {
        for (i = 2; i < NF; i++) { h = tolower(trim($i)); gsub(/[*_`]/, "", h)
          if (h == "verdict") vcol = i; else if (h ~ /approach/) acol = i }
        next
      }
      v = tolower(trim($vcol)); gsub(/[*_`]/, "", v)
      if (v !~ /^buy([^a-z]|$)/) next
      if (v ~ /decide|maybe|tbd|undecided|proposed|candidate|if needed|\?/) { print "unresolved\t-\t" NR; next }
      name = ""
      if (acol) name = tick($acol)
      if (name == "") name = tick($vcol)
      if (name == "") for (i = 3; i < NF && name == ""; i++) if (i != vcol) name = tick($i)
      if (name !~ /^[A-Za-z0-9_.-]+$/) { print "unnamed\t-\t" NR; next }
      print "confirmed\t" name "\t" NR
    }'
}

# The model: <root>/*.mpr, else app/*.mpr (two-tree), else a single apps/*/*.mpr. MPR_FILE wins.
# Prints the .mpr path; prints nothing when there is none; "AMBIGUOUS" for more than one.
_mkt_find_mpr() {
  local root="$1" f n=0 hit="" pat
  if [ -n "${MPR_FILE:-}" ]; then
    for f in "$root/$MPR_FILE" "$MPR_FILE"; do [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }; done
    return 0
  fi
  for pat in "$root"/*.mpr "$root"/app/*.mpr "$root"/apps/*/*.mpr; do
    [ -f "$pat" ] || continue
    n=$((n+1)); hit="$pat"
  done
  # Same precedence as project-bin/_common.sh find_mpr: root first, then app/, then apps/*/.
  if [ "$n" -gt 1 ]; then
    n=0; hit=""
    for f in "$root"/*.mpr; do [ -f "$f" ] && { n=$((n+1)); hit="$f"; }; done
    if [ "$n" -eq 0 ]; then for f in "$root"/app/*.mpr; do [ -f "$f" ] && { n=$((n+1)); hit="$f"; }; done; fi
    [ "$n" -eq 1 ] || { printf 'AMBIGUOUS\n'; return 0; }
  fi
  [ -n "$hit" ] && printf '%s\n' "$hit"
  return 0
}

# The project's mxcli: $MXCLI, else the project root's (mxcli.exe first under Git Bash — MSYS
# only maps foo -> foo.exe when no file "foo" exists, project-bin/_common.sh find_project_mxcli).
_mkt_find_mxcli() {
  local root="$1" mdir="$2" c
  [ -n "${MXCLI:-}" ] && { printf '%s\n' "$MXCLI"; return 0; }
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) set -- "$root/mxcli.exe" "$mdir/mxcli.exe" "$root/mxcli" ;;
    *)                    set -- "$root/mxcli" "$mdir/mxcli" ;;
  esac
  for c in "$@"; do [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }; done
  return 1
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

# mxtk_mkt_report <project-dir> <register> [fit-gap path]
# Prints one line; sets MXTK_MKT_STATUS and MXTK_MKT_NOTE.
mxtk_mkt_report() {
  local root="$1" reg="${2:-$1/PROJECT.md}" fg="${3:-}"
  MXTK_MKT_STATUS=""; MXTK_MKT_NOTE=""
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
  local rows; rows="$(mxtk_mkt_buys "$fg")"
  local n_conf n_unres n_unnamed
  n_conf="$(printf '%s\n' "$rows" | grep -c '^confirmed	')"
  n_unres="$(printf '%s\n' "$rows" | grep -c '^unresolved	')"
  n_unnamed="$(printf '%s\n' "$rows" | grep -c '^unnamed	')"
  if [ -z "$rows" ]; then
    _mkt_set PASS "0 of 0: no Buy row in ${fg#$root/}, nothing to install"; return 0
  fi
  local unnamed_note=""
  [ "$n_unnamed" -gt 0 ] && unnamed_note="; $n_unnamed confirmed Buy row(s) name no package (line $(printf '%s\n' "$rows" | awk -F'\t' '$1=="unnamed"{printf "%s%s", s, $3; s=", "}')): put the module or .mpk name in backticks in the Mendix approach cell"
  if [ "$n_conf" -eq 0 ]; then
    _mkt_set PENDING "$n_unres Buy row(s) in ${fg#$root/} not yet confirmed (\"decide if needed\")$unnamed_note"; return 0
  fi

  local mpr mdir names name reason todo="" n_waived=0 n_ok=0
  names="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="confirmed"{print $2}' | awk '!seen[tolower($0)]++')"
  n_conf="$(printf '%s\n' "$names" | sed '/^$/d' | wc -l | tr -d ' ')"
  mpr="$(_mkt_find_mpr "$root")"
  [ "$mpr" = AMBIGUOUS ] || mdir="${mpr%/*}"

  # Waivers and widget .mpk files need no model read.
  local w f lw
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if reason="$(_mkt_waived "$reg" "$name")"; then n_waived=$((n_waived+1)); continue; fi
    if [ -n "${mdir:-}" ] && [ -d "$mdir/widgets" ]; then
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

  local tail="" scoped=$((n_conf - n_waived))
  [ "$n_waived" -gt 0 ] && tail=" ($n_waived waived)"
  if [ -z "$todo" ]; then
    if [ "$scoped" -eq 0 ]; then _mkt_set WAIVED "all $n_conf confirmed Buy package(s) waived in $(basename "$reg")$unnamed_note"
    elif [ -n "$unnamed_note" ]; then _mkt_set PENDING "$n_ok of $scoped confirmed Buy installed$tail$unnamed_note"
    else _mkt_set PASS "$n_ok of $scoped confirmed Buy installed$tail"; fi
    return 0
  fi
  if [ -z "$mpr" ]; then
    _mkt_set PENDING "$n_ok of $scoped confirmed Buy installed$tail; no model yet, so not checked:$(printf '%s' "$todo" | tr '\n' ' ' | sed 's/^/ /;s/ $//')$unnamed_note"; return 0
  fi
  if [ "$mpr" = AMBIGUOUS ]; then
    _mkt_set PENDING "more than one .mpr; set MPR_FILE to choose, nothing checked$unnamed_note"; return 0
  fi
  local mx out rc tmp
  if ! mx="$(_mkt_find_mxcli "$root" "$mdir")"; then
    _mkt_set PENDING "no project mxcli (or \$MXCLI), so SHOW MODULES was not read; not checked:$(printf '%s' "$todo" | tr '\n' ' ' | sed 's/^/ /;s/ $//')$unnamed_note"; return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/mkt-mods.XXXXXX")" || { _mkt_set PENDING "could not create a temp file; nothing checked"; return 0; }
  _mkt_with_timeout "${MXTK_MKT_TIMEOUT:-60}" "$mx" -p "$mpr" -c "SHOW MODULES" > "$tmp" 2>/dev/null; rc=$?
  out="$(cat "$tmp")"; rm -f "$tmp"
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^|-'; then
    _mkt_set PENDING "SHOW MODULES could not be read (exit $rc$( [ "$rc" = 124 ] && echo ', timed out' )); nothing checked$unnamed_note"; return 0
  fi
  local mkt own missing="" n_missing=0 lname cmds=""
  mkt="$(printf '%s\n' "$out" | awk -F'|' -v want=marketplace -f "$_MKT_AWK")"
  own="$(printf '%s\n' "$out" | awk -F'|' -f "$_MKT_AWK")"
  _ob_lc "$mkt"; mkt=$'\n'"$_OB_LC"$'\n'
  _ob_lc "$own"; own=$'\n'"$_OB_LC"$'\n'
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    _ob_lc "$name"; lname="$_OB_LC"
    case "$mkt" in *$'\n'"$lname"$'\n'*) n_ok=$((n_ok+1)); continue ;; esac
    n_missing=$((n_missing+1))
    case "$own" in
      *$'\n'"$lname"$'\n'*) missing="$missing $name (in the model, but its SHOW MODULES Source is not \"Marketplace v…\": installed from a file? bug-logs/mxcli-bugs.md, SHOW MODULES Source column)," ;;
      *) missing="$missing $name," ;;
    esac
    cmds="$cmds${cmds:+; }mxcli marketplace search \"$name\""
  done <<EOF
$todo
EOF
  if [ "$n_missing" -eq 0 ]; then
    if [ -n "$unnamed_note" ]; then _mkt_set PENDING "$n_ok of $scoped confirmed Buy installed$tail$unnamed_note"
    else _mkt_set PASS "$n_ok of $scoped confirmed Buy installed$tail"; fi
    return 0
  fi
  _mkt_set FAIL "$n_ok of $scoped confirmed Buy installed$tail; NOT INSTALLED:${missing%,} — install: $cmds; then mxcli marketplace install <content-id> -p $(basename "$mpr") for each (a widget-only package lands as widgets/<Name>.mpk instead; brd-to-build-plan.md Step 0), or gate-check.sh --waive marketplace/<Name> --reason \"...\"$unnamed_note"
  return 0
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  mxtk_mkt_report "${1:-$(pwd)}" "${2:-${1:-$(pwd)}/PROJECT.md}" "${3:-}"
fi
