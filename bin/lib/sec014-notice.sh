#!/usr/bin/env bash
# sec014-notice.sh — the one place a project hears that SEC014 is not configured yet.
#
# SEC014 (lint-rules/sec014_external_role_write.star) cannot tell an external role (partner,
# customer, portal) from an internal one; the project has to name them in
# .claude/lint-config.yaml (`rules: SEC014: options: external_roles: "A, B"`). Until it does,
# the rule reports nothing on exec — a `_rule` blindness finding there would make lint-gate
# exit PASS-BLIND on every exec of every synced project until someone edits a config file,
# which is the #229 pattern (an unconfigured CONV020 logged 20 LINT BLIND rows in two apps).
# The not-yet-decided state is said HERE instead, on every sync, as a NOTE (not a counted
# warning: a fresh scaffold has not decided yet, and a pristine sync must pass --strict), until
# the option is set. A misconfigured value (a list, an unknown role) is still a `_rule` finding.
#
# Producer of the input: bin/sync-project.sh and bin/init-project.sh install the rule via
# mxtk_install_lint_rules; lint-config.yaml is written by `mxcli init`.
#
# Usage: . bin/lib/sec014-notice.sh; mxtk_sec014_notice <project_dir>
#   prints the notice lines and returns 0 when one is owed; prints nothing and returns 1 when
#   the rule is not installed, or external_roles (any value, "none" included) or
#   `enabled: false` is set under the SEC014 key.
# Keep bash-3.2 compatible.

# 0 when lint-config.yaml ($1) sets external_roles, or enabled: false, under the SEC014 key.
mxtk_sec014_decided() {
  awk '
  /^[[:space:]]*#/ { next }
  { match($0, /^ */); ind = RLENGTH }
  insec && NF && ind <= secind { insec = 0 }
  /^[[:space:]]*"?SEC014"?[[:space:]]*:/ {
    insec = 1; secind = ind
    if ($0 ~ /external_roles[[:space:]]*:/ || $0 ~ /enabled[[:space:]]*:[[:space:]]*false/) found = 1
    next
  }
  insec && /^[[:space:]]*external_roles[[:space:]]*:/ { found = 1 }
  insec && /^[[:space:]]*enabled[[:space:]]*:[[:space:]]*false/ { found = 1 }
  END { exit found ? 0 : 1 }' "$1"
}

mxtk_sec014_notice() {
  _p="${1:?project dir}"
  [ -f "$_p/.claude/lint-rules/sec014_external_role_write.star" ] || return 1
  # Decided = `external_roles:` (any value, "none" included) or `enabled: false` UNDER the
  # SEC014 key. An external_roles line anywhere else in the file (another rule, a comment)
  # does not count. lint-gate.sh carries the same awk inline (a project has no bin/lib).
  if [ -f "$_p/.claude/lint-config.yaml" ] && mxtk_sec014_decided "$_p/.claude/lint-config.yaml"; then
    return 1
  fi
  echo "SEC014 (external role can write state / audit / owner members) is installed but checks nothing:"
  echo "no external_roles in .claude/lint-config.yaml. Ask the user which user roles are external"
  echo "(partner, customer, portal), then add:"
  echo "    rules:"
  echo "      SEC014:"
  echo "        options:"
  echo "          external_roles: \"RoleA, RoleB\"   # one text, not a YAML list"
  echo "\"none\" (or SEC014 enabled: false) switches this security rule off: only on the user's answer in chat, recorded in"
  echo "PROJECT.md — never to silence this notice. The first configured run raises SEC014 0 -> N, so"
  echo "re-baseline right after: bin/lint-gate.sh --update-baseline --reason \"SEC014 configured\", then the user"
  echo "runs bin/baseline-approve.sh lint in a separate terminal (an agent cannot approve it)"
  return 0
}
