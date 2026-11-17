#!/usr/bin/env bash
# register-skeleton.sh — the ONE copy of the PROJECT.md (decision register) template, by section.
#
# init-project.sh writes a fresh register from these sections. When a PROJECT.md is ALREADY there
# and lacks the register's structure, init-project.sh and sync-project.sh append the missing
# sections instead of skipping in silence (mxtk_register_fill).
#
# WHY (field run, 2026-11). The build agent hand-wrote a 10-line PROJECT.md before init-project.sh
# ran; init printed "Skip: PROJECT.md already exists — not overwritten", so the Current-stage
# readout, the Decisions table every ✋ gate reads, and the position comments were never laid
# down, and nothing said so. Same one-copy arrangement as change-log.sh and intake-template.sh.
#
# Sourced, never executed. Side-effect free except mxtk_register_fill, which appends to $1.

mxtk_reg_intro() { # mxtk_reg_intro <project-name>
  cat <<EOF
# PROJECT.md — ${1} Decision Register

Every gate decision lands here as \`CONFIRMED\` or \`ASSUMED\`, never silently decided. See
\`conversion-runbook.md\` §1 for the interview protocol this file supports.

EOF
}

mxtk_reg_current_stage() { # mxtk_reg_current_stage <"Toolkit commit: ..." line>
  cat <<EOF
## Current stage

**Stage P — Kickoff**, in progress.

${1}
Exec approval: auto
Permission profile: project
Unit tests default: no
Gate mode: check
Pipeline mode: balanced
Build type: full

<!-- Build type (intake Q16, asked FIRST at kickoff; this line is only the default until it is answered; no line = full): full | poc. poc = skills/poc-build.md. -->

<!-- Pipeline mode (intake Q15; no line = balanced): high-speed = per row the exec gate only;
     balanced = plus one LOOK at 1280 of a changed page; high-quality = journeys + LOOK at 390 and
     1280 and unit tests per row. All three run journeys and the polish loop at module close
     (skills/iterative-build-loop.md § Pipeline mode). -->

<!-- Gate mode: check (the default, also without this line) = bin/exec.sh runs \`mx check\` per
     script and the full mxbuild at module close (every push in the high-quality pipeline mode)
     and when Java/theme files change (mxcli's own advice). \`Gate mode: full\` = a full mxbuild on every exec. -->

<!-- Bug filing: auto — take this line out of the comment to let agents post this project's open
     toolkit/mxcli bugs (docs/bugs.jsonl) as public GitHub issues with your own gh login, redacted and
     deny-list checked, without a y/N per bug (bin/file-bugs.sh --auto). Left commented, a human files. -->

<!-- The bold line above is a READOUT: bin/gate-check.sh rewrites it on every full run from the
     verdicts it just produced (first stage neither PASS nor WAIVED). Do not edit it by hand.
     Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
     usual case. If work was already done outside the toolkit, record it once and the earlier
     stages report WAIVED instead of a red row nobody can clear:
       bin/gate-check.sh <project> --adopt 5 --reason "..."     every stage before 5
       bin/gate-check.sh <project> --waive 2 --reason "..."     just that one (one line per stage)
     Intake Q10 asks this. Never infer it from what happens to be on disk. (No example line is
     written out here on purpose: gate-check reads these labels back out of this file, and a
     sample value would waive stages in every project that never deleted it.) -->

EOF
}

mxtk_reg_decisions() {
  cat <<EOF
## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|

EOF
}

mxtk_reg_tail() {
  cat <<EOF

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
EOF
}

# mxtk_register_missing <PROJECT.md> — prints the register sections the file lacks, one per line
# ("Current stage", "Decisions", "Open questions"); nothing when it has them all.
mxtk_register_missing() {
  local f="$1" h
  for h in "Current stage" "Decisions" "Open questions"; do
    grep -qE "^##[[:space:]]+$h" "$f" 2>/dev/null || printf '%s\n' "$h"
  done
}

# mxtk_register_fill <PROJECT.md> <"Toolkit commit: ..." line> [writer] — appends each missing
# section, never touching what is there. writer: a command that appends stdin to the file
# (sync-project.sh passes its dry-run-aware w_app); default plain append. Prints one line per
# section added, so the caller can say so loudly.
mxtk_register_fill() {
  local f="$1" tk="$2" w="${3:-}" h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    case "$h" in
      "Current stage")  { printf '\n'; mxtk_reg_current_stage "$tk"; } ;;
      "Decisions")      { printf '\n'; mxtk_reg_decisions; } ;;
      "Open questions") { mxtk_reg_tail; } ;;
    esac | if [ -n "$w" ]; then "$w" "$f"; else cat >> "$f"; fi
    printf '%s\n' "$h"
  done <<MXTK_REG_EOF
$(mxtk_register_missing "$f")
MXTK_REG_EOF
}
