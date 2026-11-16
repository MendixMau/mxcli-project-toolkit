#!/usr/bin/env bash
# Read-time checks over docs/BUILD-LOG.md (issue #767) — ONE copy, sourced by bin/gate-check.sh
# and bin/status.sh. Nothing here runs per exec row: project-bin/exec.sh is not touched, and both
# checks cost one awk over the log, only when a person or agent READS the position.
#
# WHY (field report, 2026-11-13, a greenfield build in auto mode). 1) The build finished and
# PROJECT.md still said "Stage P — needs attention": "## Current stage" is written only by a
# gate-check run, nobody re-ran it after the last exec, and nothing compared the readout's
# stamp with the exec rows written after it. 2) Late asks ("add an admin account") went
# straight into a numbered script with no change-intake row, so the change log stayed empty and
# its gate line read PASS on 0 rows.
#
# PRODUCER for the consumer (CLAUDE.md "Shipping an instrument" rule 5): the BUILD-LOG rows are
# written by project-bin/exec.sh log_build() on every exec (the mandatory build step); the stamp
# by gate-check.sh's own "## Current stage" rewrite; the plan by Stage 4 (architecture/build-plan.md).
#
# WARN-ONLY. Neither function changes a verdict or an exit code.
#
# Sourced, never executed. Side-effect free.

# mxtk_build_log_last_date <build-log> → the date (YYYY-MM-DD) of the newest exec row, or nothing.
# Exec rows are the table rows exec.sh writes: `| 2026-10-21T05:41:52+0000 | `x.mdl` | … |`.
# gate-check's own ack/bypass lines (`2026-…Z  PROTOCOL-BYPASS`) are not table rows, not counted.
mxtk_build_log_last_date() {
  [ -f "${1:-}" ] || return 0
  awk '/^\| *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
         s = $0; sub(/^\| */, "", s); d = substr(s, 1, 10); if (d > m) m = d }
       END { if (m != "") print m }' "$1" 2>/dev/null
}

# mxtk_stage_stale_note <register> <build-log> → one line, or nothing.
#   "Current stage line is from <date>; N exec rows since — re-run bin/gate-check.sh"
# Only for gate-check's own derived line (a hand-written line has no stamp to be stale against).
# The reference date is the stamp's "· last exec <date>" when present — a date the log itself
# wrote, so no UTC-vs-local skew — else the "derived by gate-check on <date>" date (lines written
# before #767). Day granularity: rows on the reference day itself are not counted, which can miss
# a same-day exec but never warns on a readout that is current.
mxtk_stage_stale_note() {
  local reg="${1:-}" log="${2:-}" line derived ref n
  [ -f "$reg" ] && [ -f "$log" ] || return 0
  line="$(awk '/^## Current stage/{f=1;next} f && /^## /{exit} f && /^\*\*/{print;exit}' "$reg" 2>/dev/null | tr -d '\r')"
  case "$line" in *"(derived by gate-check on "*) ;; *) return 0 ;; esac
  derived="$(printf '%s' "$line" | sed -nE 's/.*\(derived by gate-check on ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p')"
  ref="$(printf '%s' "$line" | sed -nE 's/.*· last exec ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p')"
  [ -n "$ref" ] || ref="$derived"
  [ -n "$ref" ] || return 0
  n="$(MXTK_REF="$ref" awk '/^\| *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
         s = $0; sub(/^\| */, "", s); if (substr(s, 1, 10) > ENVIRON["MXTK_REF"]) n++ }
       END { print n + 0 }' "$log" 2>/dev/null)"
  [ "${n:-0}" -gt 0 ] 2>/dev/null || return 0
  printf 'Current stage line is from %s; %s exec rows since — re-run bin/gate-check.sh\n' "${derived:-$ref}" "$n"
}

# mxtk_unlogged_execs <build-log> <build-plan> → one script name per line (first-seen order,
# deduplicated), or nothing.
# A script run after Stage 5 started that carries no `cr:` tag in its detail cell and that the
# build plan does not name is an ask nobody logged (skills/change-intake.md).
# "Stage 5 started" = the first exec row whose script the plan names: the BUILD-LOG is what was
# built, and the stage readout is the very thing #767 found stale. A log where no row matches the
# plan prints nothing — the plan may name scripts in a shape this cannot read, and flagging every
# row would be noise, not a nudge.
# Plan matching: the basename verbatim, or the plan's abbreviated form
# "060-…-customer_overview.mdl" (brd-to-build-plan.md) — prefix before the ellipsis, suffix after.
mxtk_unlogged_execs() {
  local log="${1:-}" plan="${2:-}"
  [ -f "$log" ] && [ -f "$plan" ] || return 0
  awk '
    FNR == NR {
      plan = plan "\n" $0
      line = $0
      while (match(line, /[A-Za-z0-9_.-]*(…|\.\.\.)[A-Za-z0-9_.-]*\.(mdl|py)/)) {
        tok = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        e = index(tok, "…"); el = length("…")
        if (e == 0) { e = index(tok, "..."); el = 3 }
        npre++; pre[npre] = substr(tok, 1, e - 1); suf[npre] = substr(tok, e + el)
      }
      next
    }
    /^\| *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
      n = split($0, c, "|"); if (n < 6) next
      name = c[3]; gsub(/[` \t]/, "", name); sub(/^patch:/, "", name)
      if (name == "") next
      inplan = (index(plan, name) > 0)
      for (i = 1; !inplan && i <= npre; i++)
        if (length(name) >= length(pre[i]) + length(suf[i]) \
            && substr(name, 1, length(pre[i])) == pre[i] \
            && substr(name, length(name) - length(suf[i]) + 1) == suf[i]) inplan = 1
      if (inplan) { started = 1; next }
      if (!started) next
      if ($0 ~ /cr: *CR-[0-9]/) next
      if (!(name in seen)) { seen[name] = 1; print name }
    }
  ' "$plan" "$log" 2>/dev/null
}
