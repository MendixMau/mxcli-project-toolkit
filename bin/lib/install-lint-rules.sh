#!/usr/bin/env bash
# install-lint-rules.sh — deliver the toolkit's Starlark lint rules into a project.
#
# Sourced by bin/init-project.sh (first install) and bin/sync-project.sh (refresh). One
# implementation, two callers: the crash-net copy path is duplicated between those two
# scripts and they have already drifted once, so this one is a function from the start.
#
# WHY THIS IS NOT A PLAIN `cp`. Lint rules are the only artifact the toolkit installs that
# has an ACTIVE ADVERSARY. `mxcli init` re-seeds .claude/lint-rules/ and silently overwrites
# an edited .star — verified 2026-08-18 on mxcli v0.17.0 in an empty scratch directory: the
# edit was gone after a second init, exit 0, no warning. So a rule this toolkit fixed can
# revert to stock on its own, with no user action and nothing in any diff the user reads.
#
# That matters because of HOW these rules fail when stock. ARCH002 and ARCH003 compare
# entity_type to "PERSISTENT" while the model returns "Persistent", so they match no entity
# and report a clean pass forever. A reverted rule does not error. It goes quiet and green.
# The gate keeps saying PASS over a rule that inspected nothing.
#
# The naive repair — "overwrite anything that lacks our marker" — destroys work: a project
# may have deliberately tuned a rule, and conv020 REQUIRES editing before it runs at all.
# So every file is classified before anything is written:
#
#   missing                    -> install
#   byte-identical to ours     -> leave alone
#   md5 matches the receipt    -> ours, unedited, toolkit moved on -> refresh (safe)
#   md5 matches a STOCK hash   -> mxcli seeded or re-seeded it     -> install ours
#   anything else              -> a human edited it -> REPORT, never write
#
# The receipt (.claude/.mxtk-lint-receipt) records the md5 of each rule AS INSTALLED. It is
# load-bearing twice over, and one hash answers both questions because we install verbatim:
#   - dst md5 == receipt  ->  the PROJECT has not edited this file
#   - src md5 == receipt  ->  the TOOLKIT has not changed this file
# It also lives outside lint-rules/, which is what makes it survive `mxcli init` (verified).
# Without it a genuine revert-to-stock is indistinguishable from a first install, and the
# marker line inside the rule cannot help — init wipes every marker at the same moment.
#
# Contract for callers:
#   mxtk_install_lint_rules <toolkit_root> <project_dir> <dry_run 0|1> <upgrade_spec>
#     upgrade_spec: "" | "all" | "<rule-file.star>"  — accept the toolkit version of a
#     locally-modified rule, backing the local copy up first.
#   Sets MXTK_LINT_CHANGES. Routes warnings through the caller's warn() when it defines one
#   (sync-project.sh counts warnings and exits nonzero under --strict); falls back to a
#   plain print for init-project.sh, which has no such machinery.

# Guard against double-sourcing: both callers may source this via different paths.
[ -n "${_MXTK_LINT_LIB_LOADED:-}" ] && return 0 2>/dev/null
_MXTK_LINT_LIB_LOADED=1

# ${BASH_SOURCE[0]:-$0}: this file is SOURCED, and a caller that is not bash (or a bash in
# posix mode) leaves BASH_SOURCE unset, which under `set -u` aborts the caller mid-run.
_mxtk_lint_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# portable_md5 lives in portable.sh; neither caller sources it today, and sourcing it twice
# is harmless (its definitions are idempotent).
[ -f "$_mxtk_lint_lib_dir/portable.sh" ] && . "$_mxtk_lint_lib_dir/portable.sh"
# The rule LISTS live in install-manifest.sh. Source it here rather than making every caller
# remember to: a caller that forgets installs nothing and says nothing, which is the same
# silent-clean failure these rules exist to catch. Sourcing it twice is harmless — it only
# assigns variables and runs its own self-check.
if [ -z "${MXTK_LINT_RULES:-}" ] && [ -f "$_mxtk_lint_lib_dir/install-manifest.sh" ]; then
  . "$_mxtk_lint_lib_dir/install-manifest.sh"
fi

# warn through the caller's counter when there is one. Defining our own unconditionally
# would shadow sync-project.sh's, and its WARNINGS count is what gates --strict.
_mxtk_lint_warn() {
  if type warn >/dev/null 2>&1; then
    warn "$@"
  else
    printf '⚠️  %s\n' "$1"; shift
    while [ $# -gt 0 ]; do printf '   %s\n' "$1"; shift; done
  fi
}

# Look a rule up in lint-rules/STOCK-HASHES.txt. Returns 0 when $2 is a known stock hash of
# rule $1. Comment lines start with '#'; the third column is the mxcli version and is only
# documentation. A missing hash file is not an error — it means "no stock hash is known",
# which correctly routes every non-ours file to "report", the safe branch.
_mxtk_lint_is_stock() {
  _f="$1"; _h="$2"; _hashes="$3"
  [ -f "$_hashes" ] || return 1
  while read -r _name _md5 _rest; do
    case "$_name" in ''|'#'*) continue ;; esac
    [ "$_name" = "$_f" ] && [ "$_md5" = "$_h" ] && return 0
  done < "$_hashes"
  return 1
}

_mxtk_lint_receipt_get() {
  _receipt="$1"; _f="$2"
  [ -f "$_receipt" ] || return 1
  while read -r _name _md5 _rest; do
    case "$_name" in ''|'#'*) continue ;; esac
    [ "$_name" = "$_f" ] && { printf '%s\n' "$_md5"; return 0; }
  done < "$_receipt"
  return 1
}

# Rewrite one receipt line. Read-all/write-all rather than append, so re-installing a rule
# does not leave two rows for it and let a stale one win the lookup above.
_mxtk_lint_receipt_set() {
  _receipt="$1"; _f="$2"; _md5="$3"
  _tmp="$_receipt.tmp.$$"
  {
    printf '# md5 of each toolkit lint rule AS INSTALLED. Written by bin/lib/install-lint-rules.sh.\n'
    printf '# Do not edit. Deleting this file makes a revert-to-stock look like a first install.\n'
    if [ -f "$_receipt" ]; then
      while read -r _n _m _r; do
        case "$_n" in ''|'#'*) continue ;; esac
        [ "$_n" = "$_f" ] && continue
        printf '%s  %s\n' "$_n" "$_m"
      done < "$_receipt"
    fi
    printf '%s  %s\n' "$_f" "$_md5"
  } > "$_tmp" && mv "$_tmp" "$_receipt"
}

mxtk_install_lint_rules() {
  _tk="$1"; _proj="$2"; _dry="${3:-0}"; _upg="${4:-}"

  MXTK_LINT_CHANGES=0

  _src_dir="$_tk/lint-rules"
  _dst_dir="$_proj/.claude/lint-rules"
  _hashes="$_src_dir/STOCK-HASHES.txt"
  _receipt="$_proj/.claude/.mxtk-lint-receipt"

  if [ ! -d "$_src_dir" ]; then
    _mxtk_lint_warn "Toolkit has no lint-rules/ — this project's lint rules were not checked."
    return 0
  fi
  # No manifest, no work. Sourcing order is the caller's job; say so rather than silently
  # installing nothing, which is the exact failure mode this whole file exists to prevent.
  if [ -z "${MXTK_LINT_RULES:-}${MXTK_LINT_RULES_CONFIGURABLE:-}" ]; then
    _mxtk_lint_warn "the lint-rule lists are empty and bin/lib/install-manifest.sh could not" \
                    "be loaded — no lint rules were installed."
    return 0
  fi
  if ! type portable_md5 >/dev/null 2>&1; then
    _mxtk_lint_warn "portable_md5 unavailable (bin/lib/portable.sh missing?) — lint rules" \
                    "were NOT touched. Classifying them without a hash would risk" \
                    "overwriting a rule this project tuned."
    return 0
  fi

  if [ ! -d "$_dst_dir" ]; then
    if [ "$_dry" -eq 1 ]; then
      echo "Would create: .claude/lint-rules/"
    else
      mkdir -p "$_dst_dir" || {
        _mxtk_lint_warn "Could not create $_dst_dir — lint rules not installed."; return 0; }
    fi
  fi

  _drifted=""
  for _kind in managed configurable; do
    if [ "$_kind" = managed ]; then _list="${MXTK_LINT_RULES:-}"; else _list="${MXTK_LINT_RULES_CONFIGURABLE:-}"; fi
    for _f in $_list; do
      _src="$_src_dir/$_f"; _dst="$_dst_dir/$_f"
      [ -f "$_src" ] || continue
      _srcmd5="$(portable_md5 "$_src")" || continue
      _rec="$(_mxtk_lint_receipt_get "$_receipt" "$_f" 2>/dev/null || true)"

      # ---- missing -------------------------------------------------------------------
      if [ ! -f "$_dst" ]; then
        if [ -n "$_rec" ]; then
          _why="restored — it was installed before and is gone now (\`mxcli init\` removes rules it does not know)"
        else
          _why="installed"
        fi
        if [ "$_dry" -eq 1 ]; then
          echo "Would install: .claude/lint-rules/$_f ($_why)"
        else
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          echo "Lint rule $_why: .claude/lint-rules/$_f"
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
        continue
      fi

      # ---- byte-identical to what we ship --------------------------------------------
      if cmp -s "$_src" "$_dst"; then
        # Heal a receipt that was lost or never written (pre-receipt installs exist).
        [ "$_rec" = "$_srcmd5" ] || [ "$_dry" -eq 1 ] || _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
        continue
      fi

      _dstmd5="$(portable_md5 "$_dst")" || continue

      # ---- ours, unedited, and the toolkit has moved on ------------------------------
      # dst still matches what we last wrote, so nothing local is at risk. This is the
      # branch that lets a rule FIX reach existing projects at all.
      if [ -n "$_rec" ] && [ "$_dstmd5" = "$_rec" ]; then
        if [ "$_dry" -eq 1 ]; then
          echo "Would refresh: .claude/lint-rules/$_f (toolkit version changed; local copy unedited)"
        else
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          echo "Lint rule refreshed: .claude/lint-rules/$_f (toolkit version changed; your copy was unedited)"
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
        continue
      fi

      # ---- ours, minus the provenance header -----------------------------------------
      # An early-adopter project has our FIXED rule with no header: the fixes were applied
      # by hand before this copy path existed. Byte-compare fails, no receipt exists, and no
      # stock hash matches, so without this branch every such project is told three of its
      # rules are "LOCALLY MODIFIED" — a warning that is false, that it cannot clear, and
      # that trains people to ignore the real one two lines down.
      #
      # Safe because it is an identity test, not a guess: strip our header from OUR copy and
      # compare the entire remainder. Equal means the rule bodies are the same file. This is
      # what the explicit `# --- end mxtk-lint-rule header ---` terminator is for — an
      # earlier heuristic cut to the first bare `#` and silently ate two lines of real rule.
      if grep -q '^# --- end mxtk-lint-rule header ---$' "$_src" &&
         [ "$(sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$_src")" = "$(cat "$_dst")" ]; then
        if [ "$_dry" -eq 1 ]; then
          echo "Would refresh: .claude/lint-rules/$_f (same rule, adding the provenance header)"
        else
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          echo "Lint rule headered: .claude/lint-rules/$_f (identical rule; added the toolkit provenance header)"
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
        continue
      fi

      # ---- stock: mxcli seeded it, or re-seeded over ours ----------------------------
      if _mxtk_lint_is_stock "$_f" "$_dstmd5" "$_hashes"; then
        if [ -n "$_rec" ]; then
          _why="REVERTED TO STOCK — \`mxcli init\` overwrote the toolkit version. Restoring it"
        else
          _why="replacing the stock mxcli rule with the toolkit's fixed version"
        fi
        if [ "$_dry" -eq 1 ]; then
          echo "Would install: .claude/lint-rules/$_f ($_why)"
        else
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          echo "Lint rule: $_why — .claude/lint-rules/$_f"
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
        continue
      fi

      # ---- configurable and edited: this is the EXPECTED state, not drift ------------
      # conv020 ships with PROJECT_MODULES empty and refuses to run until it is filled in.
      # Refreshing it would silently un-configure the rule and send it back to inspecting
      # nothing. Stay quiet unless the TEMPLATE moved, which is the only case where the
      # project has a decision to make.
      if [ "$_kind" = configurable ]; then
        if [ -n "$_rec" ] && [ "$_srcmd5" != "$_rec" ]; then
          echo "Note: .claude/lint-rules/$_f is configured locally (as intended) and the toolkit"
          echo "      template has since changed. Your copy was NOT touched. To see what moved:"
          echo "        diff -u $_src $_dst"
        fi
        continue
      fi

      # ---- foreign: a human edited a toolkit-owned rule ------------------------------
      _drifted="$_drifted $_f"
      _add=$(diff "$_src" "$_dst" | grep -c '^>' || true)
      _del=$(diff "$_src" "$_dst" | grep -c '^<' || true)
      if [ "$_upg" = "all" ] || [ "$_upg" = "$_f" ]; then
        if [ "$_dry" -eq 1 ]; then
          echo "Would upgrade: .claude/lint-rules/$_f (+$_add/-$_del local) — local copy backed up first"
        else
          _bak="$_dst.local-$(date +%Y%m%d%H%M%S)"
          cp "$_dst" "$_bak"
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          echo "Lint rule upgraded: .claude/lint-rules/$_f — your copy is kept at $(basename "$_bak")."
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
      else
        _mxtk_lint_warn \
          ".claude/lint-rules/$_f is LOCALLY MODIFIED (+$_add lines here / -$_del only in the template)." \
          "Not overwritten — but it is also not the version the toolkit tests, and two of these" \
          "rules report a clean pass when broken, so a stale copy here is invisible." \
          "See what differs:  diff -u $_src $_dst" \
          "Accept the toolkit version (your copy is backed up first):" \
          "  bin/sync-project.sh $_proj --upgrade-lint-rules $_f"
      fi
    done
  done

  if [ -n "$_drifted" ] && [ -z "$_upg" ]; then
    echo "   (upgrade every drifted lint rule at once with: --upgrade-lint-rules all)"
  fi
  return 0
}
