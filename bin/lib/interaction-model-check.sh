#!/usr/bin/env bash
# interaction-model-check.sh — the Stage-3 FACTS over design/interaction-model.md (#291, part 2).
#
# WHY THIS EXISTS. Three apps built with this toolkit passed every gate while one of them had
# 8 pages rooted on a parameterless "current record" retrieve, one home page for 6 roles and 3
# process stages in the menu. Every check after Stage 3 compares the build with the wireframe,
# and the wireframes were drawn as one role looking at one record. skills/interaction-model.md
# now owns the Stage-3 artifact that says who lands where and what object each page is about;
# this file only notices when that artifact leaves a role, a user task or a wireframe out.
#
# WHAT IT IS NOT: a judge. Whether a home is the RIGHT home, whether an inbox groups its rows
# well, whether a page should take a parameter at all — those verdicts stay in the skill
# (skills-over-scripts.md). This reads three facts, and only once the artifact exists:
#   (a) roles      every actor in the BRDs' top-level `actors` (the one role list a bin/ script
#                  already reads — bin/brd-report.sh) has a row in the artifact's "Role homes"
#                  table (columns `Role` | `Home page`, interaction-model.md Step 1) with a
#                  Home page cell — a page, or `none — <reason>` for an actor that is not a
#                  user role (system actor, merged into another role). BRD actors are NOT the
#                  CONFIRMED role model (external systems, roles merged at Stage 3), so a missing
#                  row is MANUAL — "confirm it is a user role" — never FAIL (review of #332);
#   (b) user tasks every BRD use case whose title STARTS with approve / review / sign-off (after
#                  an optional id prefix such as "UC001:"), whose title contains "user task", or
#                  whose `mdlRefs` names a user task — brd-generation.md has no dedicated
#                  user-task key, and the looser /approv/ flagged "View approval history" — is
#                  mentioned, by its id or its full title, on any line (table row or bullet)
#                  under a heading that names "Inbox" (interaction-model.md Step 2), as its
#                  inbox entry or as a line stating why it needs none;
#   (c) wireframes every design/wireframes/*.html carries a `Page parameter:` line inside its
#                  `wf-contract` block (design-artifacts.md Step 3; the block ends at its own
#                  closing </div>, nested divs counted) whose value — tags stripped, so
#                  `<b>Page parameter:</b>` and `<code>Sales.Order</code>` read — is
#                  `Module.Entity` or `none — <reason>` (em dash; en dash, hyphen and `&mdash;`
#                  accepted as the same separator).
# A project that writes the interaction model mid-build gets one FAIL per legacy wireframe on
# the next gate run. That is intended: the FAIL output names the remedy (add the line, or waive
# that wireframe).
# The artifact being ABSENT is not this file's business: bin/lib/artifact-manifest.tsv's
# `interaction-model` row reports it PENDING out loud through the artifact check.
#
# PRODUCER OF WHAT IT READS (CLAUDE.md "Shipping an instrument", rule 5): design/interaction-model.md
# is produced by skills/interaction-model.md, which design-artifacts.md Step 2b makes mandatory
# before the first wireframe; the wf-contract block by design-artifacts.md Step 3; BRDs by any
# Stage-2 route, found through bin/lib/discover-brds.sh.
#
# WAIVERS live in the decision register, in the artifact check's own spelling (artifact-check.sh
# header — written by hand, no new flag):
#     Waived artifact interaction-model: decided in the client's own UX workshop      (all of it)
#     Waived artifact interaction-model/SysAdmin: technical role, never signs in       (one finding)
# The unit after the slash is the role name, the use-case id as `<BRD id>/<UC id>`, or the
# wireframe file name — the same unit the FAIL line prints. Case-insensitive.
# A project adopted ABOVE stage 3 (`Adopted at stage: 4` or later) reports ADOPTED and owes
# nothing here, same rule as artifact-check.sh and obligation-check.sh.
#
# Sourced by bin/gate-check.sh after the artifact check; check_stage_3() reads MXTK_IM_STATUS.
# Also runnable directly:  bin/lib/interaction-model-check.sh <project-dir> [register]
#
# Sets: MXTK_IM_STATUS  PASS | FAIL | PENDING | WAIVED | ADOPTED | MANUAL
#       MXTK_IM_NOTE    one-line summary with denominators
#       MXTK_IM_N_FAIL  count of un-waived findings

set -uo pipefail

_IM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_IM_LIB_DIR/discover-brds.sh"
# Reuse the artifact check's register readers (_art_field, _art_adopted_stage, _art_rank) rather
# than a fourth copy of the "Label: value" parser. Its direct-run guard keeps it inert here.
type _art_field >/dev/null 2>&1 || . "$_IM_LIB_DIR/artifact-check.sh"

# _im_waivers <register> — every "Waived artifact interaction-model[/unit]: reason" line, once,
# as "unit<TAB>reason" (unit empty for the whole-artifact line, lowercased). One awk pass so a
# project with fifty findings does not fork fifty times (the Git Bash cost obligation-check.sh
# documents).
_im_waivers() {
  [ -f "$1" ] || return 0
  awk '
    /<!--/ { c = 1 } c { if ($0 ~ /-->/) c = 0; next }
    {
      l = $0; sub(/\r$/, "", l); gsub(/^[ \t>*_-]+/, "", l); gsub(/\*/, "", l)
      i = index(l, ":"); if (i == 0) next
      key = tolower(substr(l, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
      val = substr(l, i + 1);              gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (val == "") next
      p = "waived artifact interaction-model"
      if (key == p) { print "\t" val; next }
      if (index(key, p "/") == 1) print substr(key, length(p) + 2) "\t" val
    }' "$1"
}

# _im_waived <unit> — reason on stdout and rc 0 when the unit (or the whole artifact) is waived.
_im_waived() {
  local want line u
  want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [ -n "$_IM_WAIVERS" ] || return 1
  while IFS= read -r line; do
    u="${line%%$'\t'*}"
    if [ "$u" = "$want" ]; then printf '%s\n' "${line#*$'\t'}"; return 0; fi
  done <<IM_EOF
$_IM_WAIVERS
IM_EOF
  return 1
}

# _im_tables <interaction-model.md> — one awk pass over the artifact:
#   HOME<TAB>role<TAB>home     rows of the table under a "Role homes" heading
#   INBOX<TAB>line             every non-blank line (table row, bullet, prose) under any heading
#                              naming "Inbox" — the skill's own Step 2 writes inboxes as bullets
# Cells are trimmed and stripped of backticks and bold. CRLF files read like LF ones. The Role /
# Home page columns are found by header name, so a reordered table still reads.
_im_tables() {
  awk '
    function clean(s) { gsub(/`/, "", s); gsub(/\*\*/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { sub(/\r$/, "") }
    /^#+[ \t]/ {
      h = tolower($0)
      sec = ""
      if (h ~ /role homes/) sec = "home"
      else if (h ~ /inbox/) sec = "inbox"
      hdr = 0; next
    }
    sec == "" { next }
    sec == "inbox" { if ($0 ~ /[^ \t]/) printf "INBOX\t%s\n", clean($0); next }
    !/^[ \t]*\|/ { hdr = 0; next }
    {
      line = $0
      n = split(line, cell, "|")
      if (hdr == 0) {
        hdr = 1; rc = 0; hc = 0
        for (i = 2; i < n; i++) {
          c = tolower(clean(cell[i]))
          if (c == "role") rc = i
          if (c == "home page") hc = i
        }
        next
      }
      if (line ~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) next
      if (rc == 0) next
      printf "HOME\t%s\t%s\n", clean(cell[rc]), (hc ? clean(cell[hc]) : "")
    }' "$1"
}

# _im_wireframes <file>... — "file<TAB>STATE<TAB>value" per wireframe, one awk pass over all:
#   NOBLOCK   no element whose class names wf-contract
#   NOLINE    a wf-contract block, but no "Page parameter:" inside it
#   VALUE     the text after "Page parameter:" up to the next block-level tag, with inline tags
#             (b, strong, i, em, code, span, a) and comments removed and entities decoded
# The block ends at the </div> that closes the wf-contract div — nested <div>s are counted,
# so a contract with an inner row div is read whole (review of #332).
_im_wireframes() {
  awk '
    function flush(   low, s, t, rest, blk, depth, od, cd, p, v, e, off) {
      if (fname == "") return
      gsub(/\r/, "", buf)
      low = tolower(buf)
      s = match(low, /class=[^>]*wf-contract/)
      if (s == 0) { printf "%s\tNOBLOCK\t\n", fname; return }
      # back up to the opening "<" of this tag, then step past its ">"
      t = s; while (t > 1 && substr(buf, t, 1) != "<") t--
      rest = substr(buf, t); off = index(rest, ">"); if (off == 0) off = length(rest)
      blk = ""; rest = substr(rest, off + 1); depth = 1
      while (depth > 0 && rest != "") {
        od = index(tolower(rest), "<div"); cd = index(tolower(rest), "</div")
        if (cd == 0) { blk = blk rest; rest = ""; break }
        if (od > 0 && od < cd) { depth++; blk = blk substr(rest, 1, od + 3); rest = substr(rest, od + 4); continue }
        depth--
        if (depth == 0) { blk = blk substr(rest, 1, cd - 1); break }
        blk = blk substr(rest, 1, cd + 4); rest = substr(rest, cd + 5)
      }
      # comments out, inline tags out, every other tag becomes a line break (\001)
      while ((e = index(blk, "<!--")) > 0) {
        v = substr(blk, e); p = index(v, "-->")
        blk = substr(blk, 1, e - 1) (p ? substr(v, p + 3) : "")
      }
      gsub(/<\/?([bBiIaA]|[sS][tT][rR][oO][nN][gG]|[eE][mM]|[cC][oO][dD][eE]|[sS][pP][aA][nN])([ \t][^>]*)?>/, "", blk)
      gsub(/<[^>]*>/, "\001", blk)
      p = index(blk, "Page parameter:")
      if (p == 0) { printf "%s\tNOLINE\t\n", fname; return }
      v = substr(blk, p + length("Page parameter:"))
      e = index(v, "\001"); if (e > 0) v = substr(v, 1, e - 1)
      gsub(/&mdash;|&#8212;|&#x2014;|&#X2014;/, "\342\200\224", v)
      gsub(/&ndash;|&#8211;|&#x2013;|&#X2013;/, "\342\200\223", v)
      gsub(/&nbsp;/, " ", v)
      gsub(/[ \t]+/, " ", v); gsub(/^ | $/, "", v)
      printf "%s\tVALUE\t%s\n", fname, v
    }
    FNR == 1 { flush(); fname = FILENAME; buf = "" }
    { buf = buf " " $0 }
    END { flush() }' "$@"
}

# mxtk_interaction_model_check <project-dir> [register] [analysis-base]
mxtk_interaction_model_check() {
  local root="$1" reg="${2:-$1/PROJECT.md}" base="${3:-$1}"
  MXTK_IM_STATUS="PASS"; MXTK_IM_NOTE=""; MXTK_IM_N_FAIL=0
  local im="" b
  for b in "$root" "$base"; do
    [ -s "$b/design/interaction-model.md" ] && { im="$b/design/interaction-model.md"; base="$b"; break; }
  done
  if [ -z "$im" ]; then
    MXTK_IM_STATUS="PENDING"
    MXTK_IM_NOTE="design/interaction-model.md absent — nothing to check; the Artifacts block says whether it is owed yet (skills/interaction-model.md)"
    printf 'Interaction model (stage 3 facts): PENDING — %s\n' "$MXTK_IM_NOTE"
    return 0
  fi

  local adopted
  adopted="$(_art_adopted_stage "$reg" 2>/dev/null || true)"
  if [ -n "$adopted" ] && [ "$(_art_rank 3)" -lt "$(_art_rank "$adopted")" ]; then
    MXTK_IM_STATUS="ADOPTED"
    MXTK_IM_NOTE="project joined at stage $adopted, above stage 3 — the interaction model is not checked here"
    printf 'Interaction model (stage 3 facts): ADOPTED — %s\n' "$MXTK_IM_NOTE"
    return 0
  fi

  _IM_WAIVERS="$(_im_waivers "$reg")"
  local r
  if r="$(_im_waived "")"; then
    MXTK_IM_STATUS="WAIVED"; MXTK_IM_NOTE="$r (register: Waived artifact interaction-model)"
    printf 'Interaction model (stage 3 facts): WAIVED — %s\n' "$MXTK_IM_NOTE"
    return 0
  fi

  local lines="" n_fail=0 n_waived=0 manual=""
  local tables; tables="$(_im_tables "$im")"
  local rel="${im#"$root"/}"

  # ── (a) and (b): roles and user tasks, from the BRDs ──────────────────────────────────────
  local brds roles="" tasks="" n_roles=0 n_roles_ok=0 n_roles_open=0 n_tasks=0 n_tasks_ok=0
  brds="$(discover_brds "$root")"
  if [ -n "$brds" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      manual="jq not installed — roles and user tasks could not be read from the BRDs; cannot evaluate, which is not a pass"
    else
      local f files=()
      while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done <<IM_EOF
$brds
IM_EOF
      if ! roles="$(jq -r '(.actors // []) | (if type == "array" then .[] else . end)
                 | if type == "string" then . elif type == "object" then (.name // empty) else empty end' \
                 "${files[@]}" 2>/dev/null | awk 'NF && !seen[tolower($0)]++')"; then
        manual="a BRD did not parse as JSON — roles could not be read; cannot evaluate, which is not a pass"
      fi
      if ! tasks="$(jq -r '. as $b | (.useCases // [])[]
                 | select(
                     ((.title // "") | tostring
                        | test("^\\s*([A-Za-z]*[0-9][A-Za-z0-9._-]*\\s*[:.)-]?\\s+)?(approves?|reviews?|sign[- ]offs?)\\b"; "i")
                          or test("user ?task"; "i"))
                     or ([(.mdlRefs // [])[]? | tostring | select(test("user ?task"; "i"))] | length > 0))
                 | [($b.id // (input_filename | split("/") | last | sub("\\.brd\\.json$"; ""))), (.id // ""), (.title // "")]
                 | @tsv' "${files[@]}" 2>/dev/null)"; then
        manual="a BRD did not parse as JSON — user tasks could not be read; cannot evaluate, which is not a pass"
      fi
    fi
  fi

  local role home row found
  if [ -z "$manual" ]; then
    while IFS= read -r role; do
      [ -n "$role" ] || continue
      n_roles=$((n_roles+1))
      home="$(printf '%s\n' "$tables" | awk -F'\t' -v r="$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]')" \
        '$1 == "HOME" && tolower($2) == r { print $3; exit }')"
      case "$home" in ""|"—"|"-"|"–"|none|None|NONE) found="" ;; *) found=1 ;; esac
      if [ -n "$found" ]; then n_roles_ok=$((n_roles_ok+1))
      elif r="$(_im_waived "$role")"; then
        n_waived=$((n_waived+1))
        lines="$lines  WAIVED role $role — $r"$'\n'
      else
        n_roles_open=$((n_roles_open+1))
        lines="$lines  MANUAL role $role — BRD actor with no row in the \"Role homes\" table of $rel: confirm it is a user role and give it a home, or add a row \`| $role | none — <reason> |\` (system actor / merged into <role>) (interaction-model.md Step 1)"$'\n'
      fi
    done <<IM_EOF
$roles
IM_EOF

    local inbox brd_id uc_id title unit
    inbox="$(printf '%s\n' "$tables" | awk -F'\t' '$1 == "INBOX" { print $2 }')"
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      brd_id="${row%%$'\t'*}"; row="${row#*$'\t'}"
      uc_id="${row%%$'\t'*}"; title="${row#*$'\t'}"
      n_tasks=$((n_tasks+1))
      found=""
      if [ -n "$inbox" ]; then
        { [ -n "$uc_id" ] && printf '%s\n' "$inbox" | grep -Fqwi -- "$uc_id"; } && found=1
        [ -z "$found" ] && [ -n "$title" ] && printf '%s\n' "$inbox" | grep -Fqi -- "$title" && found=1
      fi
      unit="$brd_id/$uc_id"
      if [ -n "$found" ]; then n_tasks_ok=$((n_tasks_ok+1))
      elif r="$(_im_waived "$unit")"; then
        n_waived=$((n_waived+1))
        lines="$lines  WAIVED task $unit — $r"$'\n'
      else
        n_fail=$((n_fail+1))
        lines="$lines  FAIL   task $unit \"$title\" — not named on any line (row or bullet) under an Inbox heading of $rel (interaction-model.md Step 2)"$'\n'
      fi
    done <<IM_EOF
$tasks
IM_EOF
  fi

  # ── (c): every wireframe carries its page-parameter line ──────────────────────────────────
  local wfs=() wf n_wf=0 n_wf_ok=0 n_wf_fail=0 state val name why
  for wf in "$base"/design/wireframes/*.html; do [ -s "$wf" ] && wfs+=("$wf"); done
  if [ "${#wfs[@]}" -gt 0 ]; then
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      wf="${row%%$'\t'*}"; row="${row#*$'\t'}"
      state="${row%%$'\t'*}"; val="${row#*$'\t'}"
      name="$(basename "$wf")"
      n_wf=$((n_wf+1)); why=""
      case "$state" in
        NOBLOCK) why="no wf-contract block" ;;
        NOLINE)  why="its wf-contract block has no \"Page parameter:\" line" ;;
        VALUE)
          if printf '%s' "$val" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$'; then :
          elif printf '%s' "$val" | grep -Eq '^none (—|–|-) [^ ]'; then :
          else why="\"Page parameter: $val\" is neither Module.Entity nor \"none — <reason>\""
          fi ;;
      esac
      if [ -z "$why" ]; then n_wf_ok=$((n_wf_ok+1))
      elif r="$(_im_waived "$name")"; then
        n_waived=$((n_waived+1))
        lines="$lines  WAIVED wireframe $name — $r"$'\n'
      else
        n_fail=$((n_fail+1))
        lines="$lines  FAIL   wireframe $name — $why (design-artifacts.md Step 3)"$'\n'
        n_wf_fail=$((n_wf_fail+1))
      fi
    done <<IM_EOF
$(_im_wireframes "${wfs[@]}")
IM_EOF
  fi

  if [ "$n_wf_fail" -gt 0 ]; then
    lines="$lines  remedy: add <p>Page parameter: Module.Entity</p> (or: none — <reason>) to each wireframe's wf-contract block (design-artifacts.md Step 3), or waive one in the register: \"Waived artifact interaction-model/<file>.html: <reason>\" — wireframes drawn before the interaction model existed are expected to land here"$'\n'
  fi

  local counts
  if [ -n "$manual" ]; then
    counts="roles/user tasks: NOT CHECKED ($manual); $n_wf_ok of $n_wf wireframes carry a valid Page parameter line"
  else
    counts="$n_roles_ok of $n_roles BRD actors have a Role homes row, $n_tasks_ok of $n_tasks BRD approval/user-task use cases are named under an Inbox heading, $n_wf_ok of $n_wf wireframes carry a valid Page parameter line"
  fi
  [ "$n_waived" -gt 0 ] && counts="$counts, $n_waived waived"
  MXTK_IM_N_FAIL="$n_fail"
  if [ "$n_fail" -gt 0 ]; then
    MXTK_IM_STATUS="FAIL"; MXTK_IM_NOTE="$n_fail finding(s) in $rel — $counts"
  elif [ -n "$manual" ]; then
    MXTK_IM_STATUS="MANUAL"; MXTK_IM_NOTE="$counts"
  elif [ "$n_roles_open" -gt 0 ]; then
    MXTK_IM_STATUS="MANUAL"; MXTK_IM_NOTE="$n_roles_open BRD actor(s) with no Role homes row — confirm each is a user role or add a 'none — <reason>' row; $counts"
  else
    MXTK_IM_NOTE="$counts"
  fi
  printf 'Interaction model (stage 3 facts): %s — %s\n' "$MXTK_IM_STATUS" "$MXTK_IM_NOTE"
  [ -n "$lines" ] && printf '%s' "$lines"
  return 0
}

# Direct invocation: run the check against a project dir.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  mxtk_interaction_model_check "${1:-$(pwd)}" "${2:-}"
fi
