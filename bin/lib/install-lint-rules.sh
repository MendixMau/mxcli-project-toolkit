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
# may have deliberately tuned a rule, and mxtk_ux003 (MXTK-UX003) is configured per project by design.
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

# The receipt row is `<rule-file>  <md5>  <kind>`. kind is where the rule comes from, read from
# install-manifest.sh: `stock` (MXTK_LINT_RULES_STOCK — `mxcli init` also seeds this file name,
# so a headerless copy is a re-seed), `toolkit` (toolkit-only; init never writes it, so a
# headerless copy is a person's edit) or `configurable` (edited by design). lint-gate.sh reads the
# kind, since a project has no manifest; a row without one (written before kinds existed) is
# healed by the next sync and is not checked by lint-gate until then.
_mxtk_lint_kind() {
  case " ${MXTK_LINT_RULES_STOCK:-} " in *" $1 "*) echo stock; return ;; esac
  case " ${MXTK_LINT_RULES_CONFIGURABLE:-} " in *" $1 "*) echo configurable; return ;; esac
  echo toolkit
}

# Rewrite one receipt line. Read-all/write-all rather than append, so re-installing a rule
# does not leave two rows for it and let a stale one win the lookup above.
_mxtk_lint_receipt_set() {
  _receipt="$1"; _f="$2"; _md5="$3"
  _tmp="$_receipt.tmp.$$"
  {
    printf '# md5 of each toolkit lint rule AS INSTALLED, and its kind. Written by bin/lib/install-lint-rules.sh.\n'
    printf '# Do not edit. Deleting this file makes a revert-to-stock look like a first install.\n'
    if [ -f "$_receipt" ]; then
      while read -r _n _m _r; do
        case "$_n" in ''|'#'*) continue ;; esac
        [ "$_n" = "$_f" ] && continue
        printf '%s  %s%s\n' "$_n" "$_m" "${_r:+  $_r}"
      done < "$_receipt"
    fi
    printf '%s  %s  %s\n' "$_f" "$_md5" "$(_mxtk_lint_kind "$_f")"
  } > "$_tmp" && mv "$_tmp" "$_receipt"
}

# DELIBERATE OPT-OUT — a user decision, not an agent's. .claude/lint-rules-disabled.txt holds
# one rule per line, each WITH its reason:
#     txt002_non_iso_date_in_user_text.star  # reason: display standard is dd/MM/yyyy (PROJECT.md D-14)
# The decision is asked in chat and recorded in PROJECT.md; the line here is what the tools
# read. A listed rule is never installed or restored and its receipt row is pruned, and
# lint-gate.sh does not report it gone. Refused, with a warning, and the line ignored:
#   - a line with no `# reason:` text;
#   - a stock-seeded rule (MXTK_LINT_RULES_STOCK). `mxcli init` writes a stock copy of that file
#     name back, and the stock rules report a clean pass while inspecting nothing — an opt-out
#     would turn that into a permanent silent green.
# _mxtk_lint_is_disabled answers for one rule; _mxtk_lint_disabled_audit warns once per bad line.
_mxtk_lint_dis_ok() {  # $1 = rule, $2 = rest of the line -> 0 when the line is a valid opt-out
  case " ${MXTK_LINT_RULES_STOCK:-} " in *" $1 "*) return 1 ;; esac
  # Same syntax lint-gate.sh accepts (Python `#\s*reason:\s*(\S.*)`): `#`, optional blanks,
  # `reason:`, then non-blank text.
  _dis_why="$(printf '%s\n' "$2" | sed -n 's/^.*#[[:space:]]*reason:[[:space:]]*//p')"
  [ -n "$(printf '%s' "$_dis_why" | tr -d '[:space:]')" ]
}
_mxtk_lint_is_disabled() {
  # Own variable names: callers loop with _n/_m/_f, and these are not `local` (POSIX sh).
  _dis_file="$1"; _dis_want="$2"
  [ -f "$_dis_file" ] || return 1
  while read -r _dis_n _dis_rest; do
    case "$_dis_n" in ''|'#'*) continue ;; esac
    [ "$_dis_n" = "$_dis_want" ] && _mxtk_lint_dis_ok "$_dis_n" "$_dis_rest" && return 0
  done < "$_dis_file"
  return 1
}
_mxtk_lint_disabled_audit() {
  _dis_file="$1"
  [ -f "$_dis_file" ] || return 0
  while read -r _dis_n _dis_rest; do
    case "$_dis_n" in ''|'#'*) continue ;; esac
    _mxtk_lint_dis_ok "$_dis_n" "$_dis_rest" && continue
    case " ${MXTK_LINT_RULES_STOCK:-} " in
      *" $_dis_n "*) _mxtk_lint_warn \
        ".claude/lint-rules-disabled.txt: $_dis_n cannot be disabled — IGNORED." \
        "\`mxcli init\` re-seeds a stock copy of it, which reports a clean pass while inspecting" \
        "nothing. The rule stays installed. Remove the line." ;;
      *) _mxtk_lint_warn \
        ".claude/lint-rules-disabled.txt: $_dis_n has no '# reason: …' — IGNORED, the rule stays installed." \
        "Disabling a rule is the user's decision: ask in chat, record it in PROJECT.md, then write" \
        "  $_dis_n  # reason: <why, and where it is recorded>" ;;
    esac
  done < "$_dis_file"
}

# Rewrite the receipt to the current manifest: rows for rules no longer shipped, or validly
# disabled here, are dropped (a stale row would make lint-gate.sh report the rule "gone" on every
# run, forever), and every kept row carries its kind. Written only when something changed.
_mxtk_lint_receipt_finalize() {
  _receipt="$1"; _keep=" $2 "; _dis="$3"
  [ -f "$_receipt" ] || return 0
  _pruned=""; _tmp="$_receipt.tmp.$$"
  {
    printf '# md5 of each toolkit lint rule AS INSTALLED, and its kind. Written by bin/lib/install-lint-rules.sh.\n'
    printf '# Do not edit. Deleting this file makes a revert-to-stock look like a first install.\n'
    while read -r _n _m _r; do
      case "$_n" in ''|'#'*) continue ;; esac
      case "$_keep" in *" $_n "*) ;; *) _pruned="$_pruned $_n"; continue ;; esac
      if _mxtk_lint_is_disabled "$_dis" "$_n"; then _pruned="$_pruned $_n"; continue; fi
      printf '%s  %s  %s\n' "$_n" "$_m" "$(_mxtk_lint_kind "$_n")"
    done < "$_receipt"
  } > "$_tmp"
  if cmp -s "$_tmp" "$_receipt"; then
    rm -f "$_tmp"
  else
    mv "$_tmp" "$_receipt"
  fi
  [ -z "$_pruned" ] || echo "Lint receipt: dropped row(s) for rules no longer shipped or disabled here:$_pruned"
}

# _mxtk_lint_cfg_file <project>: the lint config mxcli reads, in its own order
# (mdl/linter/config.go FindConfigFile): .claude/lint-config.yaml, lint-config.yaml,
# .lint-config.yaml. The first that exists wins; the others are not read. Prints nothing if none.
_mxtk_lint_cfg_file() {
  for _cf in "$1/.claude/lint-config.yaml" "$1/lint-config.yaml" "$1/.lint-config.yaml"; do
    [ -f "$_cf" ] && { printf '%s\n' "$_cf"; return 0; }
  done
  return 1
}

# _mxtk_lint_cfg_disabled <lint-config.yaml> <RULE_ID>: 0 when the file switches that rule off.
# Same reading as mxcli v0.28.0 (RuleConfigYAML.Enabled *bool, gopkg.in/yaml.v3 v3.0.1): false is
# a plain false|False|FALSE (YAML 1.2 core; a quoted "false" is a string, the config fails to load
# and every rule runs) or n|N|no|No|NO|off|Off|OFF, plain or quoted (yaml.v3's YAML 1.1 fallback
# for a typed bool, decode.go). Other spellings (fAlse, nO, 0) are not false. The rule key may be
# bare, 'single' or "double" quoted; `enabled` counts only as its DIRECT child: the first indent
# level under it, or a top-level key of a flow map on the key's own line. Verified per spelling
# on mxcli v0.28.0 (tests/wave2/test-lint-rule-rename.sh T1b).
_mxtk_lint_cfg_disabled() {
  [ -f "$1" ] || return 1
  awk -v id="$2" -v sq="'" '
    function isoff(v,   q) {
      sub(/^[ \t]+/, "", v); sub(/[ \t]*(#.*)?$/, "", v)
      if (v ~ /^(false|False|FALSE)$/) return 1
      q = substr(v, 1, 1)
      if ((q == "\"" || q == sq) && length(v) > 1 && substr(v, length(v)) == q) v = substr(v, 2, length(v) - 2)
      return v ~ /^(n|N|no|No|NO|off|Off|OFF)$/
    }
    function enabledkv(kv) {   # "enabled: <v>" (key optionally quoted) -> isoff(v); else 0
      if (!match(kv, "^[ \t]*(\"enabled\"|" sq "enabled" sq "|enabled)[ \t]*:")) return 0
      return isoff(substr(kv, RLENGTH + 1))
    }
    function flow(s,   i, c, d, piece) {   # top-level pairs of the flow map that opens s
      i = index(s, "{"); if (!i) return 0
      d = 1; piece = ""
      for (i++; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "{" || c == "[") d++
        else if (c == "}" || c == "]") { d--; if (d == 0) break }
        if (d == 1 && c == ",") { if (enabledkv(piece)) return 1; piece = ""; continue }
        piece = piece c
      }
      return enabledkv(piece)
    }
    { sub(/\r$/, "") }   # a CRLF file (Git Bash, core.autocrlf): mxcli reads it, so must we
    /^[[:space:]]*(#|$)/ { next }
    { match($0, /^ */); ind = RLENGTH }
    insec && ind <= secind { insec = 0 }
    insec {
      if (childind < 0) childind = ind
      if (ind == childind && enabledkv($0)) found = 1
      next
    }
    match($0, "^[ \t]*(\"" id "\"|" sq id sq "|" id ")[ \t]*:") {
      rest = substr($0, RLENGTH + 1)
      if (rest ~ /^[ \t]*\{/) { if (flow(rest)) found = 1 }
      else { insec = 1; secind = ind; childind = -1 }
    }
    END { exit found ? 0 : 1 }' "$1"
}

# RENAMED RULES (MXTK_LINT_RENAMES in install-manifest.sh). First case: CONV020 -> MXTK-UX003,
# because mxcli v0.28.0 ships a built-in CONV020 and runs both rules under that one id. Per rename:
#   1. lint-rules-disabled.txt naming the old FILE -> rewritten to the new file (a file name is
#      unambiguous, and leaving it would install the new rule over the user's opt-out).
#   2. the old file: an unedited copy (md5, CR-insensitive, equals a shipped version or the
#      receipt row) is deleted; the loop below then installs the new one, unless the lint config
#      mxcli reads (_mxtk_lint_cfg_file) switched the old id off (_mxtk_lint_cfg_disabled): that
#      opt-out is written to lint-rules-disabled.txt under the new file, so the rule stays off (the
#      config key is left as it is). An edited copy is left alone with a warning (saying how to keep
#      such an opt-out), and the new file is held back (MXTK_LINT_RENAME_HOLD), since installing it
#      beside the edited one would run the rule twice. A dry run lists a carried-over rule in
#      MXTK_LINT_RENAME_DRYOFF so the loop does not also say it would install it.
#   3. lint-baseline.json, once no old copy remains: findings whose message matches the toolkit
#      rule's are rekeyed to the new id and the counts moved with them. A finding with another
#      message stays (mxcli's built-in). A counts-only baseline (pre-#239) cannot be split: NOTE,
#      once (marker line in .claude/.mxtk-lint-notes). Python runs only when a finding under the
#      old id looks like the toolkit rule's (grep pre-filter), so a baselined built-in costs nothing.
#   4. On a run that changed something: a NOTE for lint-config.yaml settings under the old id
#      (saying so when its enabled: false was carried over in 2) and for PROJECT.md lines naming it.
#      Neither file is rewritten: their text cannot say which rule it meant. A second run finds nothing to do and prints nothing.
_mxtk_lint_migrate_renames() {
  _rn_proj="$1"; _rn_dry="$2"; _rn_src_dir="$3"
  MXTK_LINT_RENAME_HOLD=""; MXTK_LINT_RENAME_DRYOFF=""
  [ -n "${MXTK_LINT_RENAMES:-}" ] || return 0
  _rn_dir="$_rn_proj/.claude/lint-rules"
  _rn_dis="$_rn_proj/.claude/lint-rules-disabled.txt"
  _rn_base="$_rn_proj/.claude/lint-baseline.json"
  _rn_cfg="$(_mxtk_lint_cfg_file "$_rn_proj" || true)"; _rn_cfgrel="${_rn_cfg#"$_rn_proj"/}"
  # Committed on purpose, team-shared like .mxtk-lint-receipt: it records a NOTE about the committed
  # lint-baseline.json as said, so one teammate re-baselining settles it for all.
  _rn_notes="$_rn_proj/.claude/.mxtk-lint-notes"
  while read -r _rn_old _rn_oid _rn_new _rn_nid _rn_md5s _rn_re; do
    [ -n "$_rn_old" ] && [ -n "$_rn_re" ] || continue
    _rn_did=0; _rn_hold=0; _rn_cfgoff=0

    # 1. opt-out line
    if [ -f "$_rn_dis" ] && awk -v o="$_rn_old" '$1 == o { f = 1 } END { exit f ? 0 : 1 }' "$_rn_dis"; then
      if [ "$_rn_dry" -eq 1 ]; then
        echo "Would carry over: .claude/lint-rules-disabled.txt $_rn_old -> $_rn_new"
        MXTK_LINT_RENAME_DRYOFF="$MXTK_LINT_RENAME_DRYOFF $_rn_new"
      else
        awk -v o="$_rn_old" -v n="$_rn_new" '
          $1 == o { i = index($0, o); $0 = substr($0, 1, i - 1) n substr($0, i + length(o)) } { print }' \
          "$_rn_dis" > "$_rn_dis.tmp.$$" && mv "$_rn_dis.tmp.$$" "$_rn_dis"
        echo "Lint opt-out carried over: .claude/lint-rules-disabled.txt now names $_rn_new (was $_rn_old)"
      fi
      _rn_did=1; MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
    fi

    # 2. the old file
    _rn_f="$_rn_dir/$_rn_old"
    if [ -f "$_rn_f" ]; then
      _rn_m="$(portable_md5 "$_rn_f")"
      tr -d '\r' < "$_rn_f" > "$_rn_f.lf.$$"; _rn_ml="$(portable_md5 "$_rn_f.lf.$$")"; rm -f "$_rn_f.lf.$$"
      _rn_rec="$(_mxtk_lint_receipt_get "$_rn_proj/.claude/.mxtk-lint-receipt" "$_rn_old" 2>/dev/null || true)"
      _rn_clean=0
      case ",$_rn_md5s," in *",$_rn_m,"*|*",$_rn_ml,"*) _rn_clean=1 ;; esac
      [ -n "$_rn_rec" ] && [ "$_rn_rec" = "$_rn_m" ] && _rn_clean=1
      if [ "$_rn_clean" -eq 1 ]; then
        if [ "$_rn_dry" -eq 1 ]; then
          echo "Would rename: .claude/lint-rules/$_rn_old -> $_rn_new ($_rn_oid -> $_rn_nid; your copy is an unedited toolkit version)"
        else
          echo "Lint rule renamed: .claude/lint-rules/$_rn_old -> $_rn_new (RULE_ID $_rn_oid -> $_rn_nid)."
          echo "   mxcli v0.28.0 ships a built-in $_rn_oid. Your copy was an unedited toolkit version, so the"
          echo "   current template replaces it."
          if grep -q '^PROJECT_MODULES = ()' "$_rn_f"; then
            echo "   It was the old template with PROJECT_MODULES empty, so it inspected nothing. The new one"
            echo "   defaults to \"*\" and will report: review its findings, then"
            echo "   bin/lint-gate.sh --update-baseline --reason \"$_rn_nid now configured\""
          fi
          rm -f "$_rn_f"
        fi
        # The project switched the old id off in lint-config.yaml (README's preferred opt-out).
        # On mxcli v0.28.0+ that key reaches only the built-in, so carry the opt-out to the file.
        if _mxtk_lint_cfg_disabled "$_rn_cfg" "$_rn_oid" && ! _mxtk_lint_is_disabled "$_rn_dis" "$_rn_new"; then
          _rn_cfgoff=1
          if [ "$_rn_dry" -eq 1 ]; then
            echo "Would carry over: $_rn_cfgrel $_rn_oid enabled: false -> .claude/lint-rules-disabled.txt $_rn_new"
            MXTK_LINT_RENAME_DRYOFF="$MXTK_LINT_RENAME_DRYOFF $_rn_new"
          else
            [ -s "$_rn_dis" ] && [ -n "$(tail -c 1 "$_rn_dis")" ] && echo >> "$_rn_dis"
            printf '%s  # reason: carried over from %s %s: enabled: false (%s)\n' \
              "$_rn_new" "${_rn_cfg##*/}" "$_rn_oid" "$(date +%Y-%m-%d)" >> "$_rn_dis"
            echo "Lint opt-out carried over: $_rn_cfgrel has $_rn_oid enabled: false, so"
            echo "   .claude/lint-rules-disabled.txt now names $_rn_new and it is not installed."
          fi
        fi
        _rn_did=1; MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
      else
        _rn_hold=1; MXTK_LINT_RENAME_HOLD="$MXTK_LINT_RENAME_HOLD $_rn_new"
        _mxtk_lint_warn \
          ".claude/lint-rules/$_rn_old is edited here, so it was NOT renamed to $_rn_new ($_rn_nid)." \
          "It still reports as $_rn_oid, the id mxcli v0.28.0 also gives a built-in rule. On that mxcli" \
          "both run under one id: one lint-config entry switches both, -r $_rn_oid runs both, lint-gate" \
          "sums them. $_rn_new was not installed beside it (the rule would run twice). By hand:" \
          "  1. cp $_rn_src_dir/$_rn_new $_rn_dir/" \
          "  2. copy your settings (PROJECT_MODULES, ACTION_PREFIX, any other edit) from $_rn_old into it" \
          "  3. delete $_rn_old, then re-run sync-project.sh: it rekeys lint-baseline.json"
        if _mxtk_lint_cfg_disabled "$_rn_cfg" "$_rn_oid" && ! _mxtk_lint_is_disabled "$_rn_dis" "$_rn_new"; then
          _mxtk_lint_warn \
            "$_rn_cfgrel switches $_rn_oid off; on mxcli v0.28.0 that key no longer reaches $_rn_new." \
            "To keep that opt-out, skip 1-2: add the line" \
            "  $_rn_new  # reason: <why>" \
            "to .claude/lint-rules-disabled.txt (a listed rule is not installed; a copy left in" \
            ".claude/lint-rules/ would still run), then do 3."
        fi
      fi
    fi

    # 3. the baseline
    # Pre-filter: a findings baseline needs Python only when a key under the old id carries a
    # message like the toolkit rule's (the regex with its anchors dropped: a superset, Python
    # decides); a counts-only one only until its NOTE has printed.
    _rn_need=0
    if [ "$_rn_hold" -eq 0 ] && [ -f "$_rn_base" ] && grep -q "\"$_rn_oid[|\"]" "$_rn_base"; then
      if grep -q '"findings"' "$_rn_base"; then
        grep -qE "\"$_rn_oid[|][^\"]*($(printf '%s' "$_rn_re" | tr -d '^'))" "$_rn_base" && _rn_need=1
      elif ! grep -qx "$_rn_oid counts-only" "$_rn_notes" 2>/dev/null; then
        _rn_need=1
      fi
    fi
    if [ "$_rn_need" -eq 1 ]; then
      if ! _rn_py="$(resolve_py 2>/dev/null)"; then
        _mxtk_lint_warn "lint-baseline.json still keys findings as $_rn_oid and Python 3 was not found to" \
                        "rekey the toolkit rule's to $_rn_nid. Install Python 3 and re-run sync-project.sh."
      else
        IFS= read -r -d '' _rn_pysrc <<'PY' || true
import json, os, re, sys
p, old, new = os.environ["RN_BASE"], os.environ["RN_OLD"], os.environ["RN_NEW"]
pat = re.compile(os.environ["RN_RE"])
try:
    d = json.load(open(p, encoding="utf-8"))
    counts = d.get("counts") or {}
except (ValueError, OSError, AttributeError) as e:
    print("ERR %s" % e); sys.exit(0)
f = d.get("findings")
if f is None:
    print("NOFINDINGS %d" % counts.get(old, 0)); sys.exit(0)
moved = other = 0
nf = {}
for k, n in f.items():
    if k.startswith(old + "|"):
        parts = k.split("|", 3)
        if len(parts) == 4 and pat.search(parts[3]):
            k = new + k[len(old):]
            moved += n
        else:
            other += n
    nf[k] = nf.get(k, 0) + n
if moved and os.environ.get("RN_DRY") != "1":
    left = counts.get(old, 0) - moved
    counts.pop(old, None)
    if left > 0:
        counts[old] = left
    counts[new] = counts.get(new, 0) + moved
    d["counts"] = dict(sorted(counts.items()))
    d["findings"] = dict(sorted(nf.items()))
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
print("MOVED %d %d" % (moved, other))
PY
        _rn_out="$(RN_BASE="$(native_path "$_rn_base")" RN_OLD="$_rn_oid" RN_NEW="$_rn_nid" RN_RE="$_rn_re" \
                   RN_DRY="$_rn_dry" "$_rn_py" -c "$_rn_pysrc" 2>&1)"
        read -r _rn_k _rn_a _rn_b _rn_rest <<RNEOF
$_rn_out
RNEOF
        case "$_rn_k" in
          MOVED)
            if [ "${_rn_a:-0}" -gt 0 ]; then
              if [ "$_rn_dry" -eq 1 ]; then
                echo "Would rekey: $_rn_a $_rn_oid finding(s) in .claude/lint-baseline.json -> $_rn_nid"
              else
                echo "Lint baseline: $_rn_a $_rn_oid finding(s) of the toolkit rule rekeyed to $_rn_nid (.claude/lint-baseline.json; commit it)."
              fi
              [ "${_rn_b:-0}" -gt 0 ] && echo "   $_rn_b $_rn_oid finding(s) kept: their message is not the toolkit rule's (mxcli's built-in $_rn_oid)."
              _rn_did=1; MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
            fi ;;
          NOFINDINGS)
            if [ "${_rn_a:-0}" -gt 0 ]; then
              echo "NOTE: .claude/lint-baseline.json holds $_rn_oid as a count only ($_rn_a; written before findings were"
              echo "      recorded), so the toolkit rule's findings cannot be told from mxcli's built-in $_rn_oid. Not"
              echo "      changed. Re-baseline: bin/lint-gate.sh --update-baseline --reason \"$_rn_oid renamed $_rn_nid\""
              echo "      (Said once.)"
              [ "$_rn_dry" -eq 1 ] || echo "$_rn_oid counts-only" >> "$_rn_notes"
            fi ;;
          *) _mxtk_lint_warn "could not rekey $_rn_oid in .claude/lint-baseline.json: ${_rn_out:-no output}" ;;
        esac
      fi
    fi

    # 4. one-time notices
    if [ "$_rn_did" -eq 1 ]; then
      if [ -n "$_rn_cfg" ] &&
         grep -qE "^[[:space:]]*(\"$_rn_oid\"|'$_rn_oid'|$_rn_oid)[[:space:]]*:" "$_rn_cfg"; then
        echo "NOTE: $_rn_cfgrel has settings under $_rn_oid. On mxcli v0.28.0+ they reach mxcli's"
        if [ "$_rn_cfgoff" -eq 1 ]; then
          echo "      built-in $_rn_oid, not the toolkit rule. Its enabled: false was carried over: the"
          echo "      toolkit rule stays off through .claude/lint-rules-disabled.txt ($_rn_new)."
          echo "      The key now switches off only the built-in. Not changed: keep it, or remove it to run"
          echo "      the built-in."
        elif _mxtk_lint_is_disabled "$_rn_dis" "$_rn_new" ||
             case " $MXTK_LINT_RENAME_DRYOFF " in *" $_rn_new "*) true ;; *) false ;; esac; then
          echo "      built-in $_rn_oid, not the toolkit rule, which is off here through"
          echo "      .claude/lint-rules-disabled.txt ($_rn_new). Not changed automatically."
        else
          echo "      built-in $_rn_oid, not the toolkit rule. If they were meant for the toolkit rule, move them"
          echo "      under $_rn_nid. Not changed automatically."
        fi
      fi
      if [ -f "$_rn_proj/PROJECT.md" ] && grep -q "$_rn_oid" "$_rn_proj/PROJECT.md"; then
        echo "NOTE: PROJECT.md names $_rn_oid on line(s) $(grep -n "$_rn_oid" "$_rn_proj/PROJECT.md" | cut -d: -f1 | head -8 | paste -sd, -)."
        echo "      A decision about the toolkit's user-feedback rule now refers to $_rn_nid; one about"
        echo "      \"created object never persisted\" is mxcli's built-in. Not changed: the register is yours."
      fi
    fi
  done <<EOF
$MXTK_LINT_RENAMES
EOF
  return 0
}

mxtk_install_lint_rules() {
  _tk="$1"; _proj="$2"; _dry="${3:-0}"; _upg="${4:-}"

  MXTK_LINT_CHANGES=0

  _src_dir="$_tk/lint-rules"
  _dst_dir="$_proj/.claude/lint-rules"
  _hashes="$_src_dir/STOCK-HASHES.txt"
  _receipt="$_proj/.claude/.mxtk-lint-receipt"
  _disabled="$_proj/.claude/lint-rules-disabled.txt"

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

  _mxtk_lint_migrate_renames "$_proj" "$_dry" "$_src_dir"
  _mxtk_lint_disabled_audit "$_disabled"
  _drifted=""
  for _kind in managed configurable; do
    if [ "$_kind" = managed ]; then _list="${MXTK_LINT_RULES:-}"; else _list="${MXTK_LINT_RULES_CONFIGURABLE:-}"; fi
    for _f in $_list; do
      _src="$_src_dir/$_f"; _dst="$_dst_dir/$_f"
      [ -f "$_src" ] || continue
      _mxtk_lint_is_disabled "$_disabled" "$_f" && continue
      case " ${MXTK_LINT_RENAME_DRYOFF:-} " in *" $_f "*) continue ;; esac
      # An edited copy under a renamed rule's old file name is still in place: do not run it twice.
      case " ${MXTK_LINT_RENAME_HOLD:-} " in *" $_f "*) [ -f "$_dst" ] || continue ;; esac
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

      # ---- stock-seedable, installed by us, header gone, stock hash not on file --------
      # Only for MXTK_LINT_RULES_STOCK: `mxcli init` seeds those file names, so with the receipt
      # saying we installed it and the provenance header gone, this is a re-seed by an mxcli
      # version STOCK-HASHES.txt does not list yet (an upgrade, then init) — not a hand edit.
      # Without this branch it was reported LOCALLY MODIFIED and never written, and lint-gate.sh,
      # which applies the same test, stayed BLIND forever (#264 review). Toolkit-only and
      # configurable rules are never seeded by init: a headerless copy of one is a person's edit
      # and falls through to the LOCALLY MODIFIED / configured branches below, never overwritten.
      # The found file is kept beside it; lint loads *.star only.
      if [ -n "$_rec" ] && [ "$(_mxtk_lint_kind "$_f")" = stock ] && ! grep -q '^# mxtk-lint-rule:' "$_dst"; then
        # Not "REVERTED TO STOCK": its body matches no known stock hash, so it is either a
        # newer mxcli's seed or a hand edit that also lost the header. The two look the same
        # from here, which is why the copy is kept. Backups are capped at the newest 3 per rule
        # (the name sorts by time), so a project that re-seeds on every init does not pile up.
        if [ "$_dry" -eq 1 ]; then
          echo "Would install: .claude/lint-rules/$_f (header missing — would restore from toolkit and keep your copy)"
        else
          _bak="$_dst.reseeded-$(date +%Y%m%d%H%M%S)"
          cp "$_dst" "$_bak"
          cp "$_src" "$_dst" && _mxtk_lint_receipt_set "$_receipt" "$_f" "$_srcmd5"
          ls "$_dst".reseeded-* 2>/dev/null | sort -r | sed -n '4,$p' | while IFS= read -r _old; do rm -f "$_old"; done
          echo "Lint rule: .claude/lint-rules/$_f — header missing — restored from toolkit, your copy kept as $(basename "$_bak")"
        fi
        MXTK_LINT_CHANGES=$((MXTK_LINT_CHANGES + 1))
        continue
      fi

      # ---- configurable and edited: this is the EXPECTED state, not drift ------------
      # mxtk_ux003 (MXTK-UX003) is configured per project (PROJECT_MODULES, ACTION_PREFIX).
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
  [ "$_dry" -eq 1 ] || _mxtk_lint_receipt_finalize "$_receipt" \
    "${MXTK_LINT_RULES:-} ${MXTK_LINT_RULES_CONFIGURABLE:-}" "$_disabled"
  return 0
}
