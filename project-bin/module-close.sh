#!/usr/bin/env bash
# module-close.sh <Module> — the checks that run once per module, not once per script.
#
#   bin/module-close.sh Procurement
#
# Runs, in order, and writes one report: docs/progress/module-close/<Module>.md
#   1. mxcli lint, whole model; the ⚠ lines that name this module are the module's findings
#   2. model score (bin/metrics-ledger.sh score → mxcli report), once
#   3. mxcli docker check (= mx check), plus a full mxbuild (bin/verify-model.sh) under `Gate mode: check`
#      when the model has not had one since its last change
#   4. bin/verify-module.sh <Module> --quick (conformance, graph sweep, coverage; diagnostic only)
#   5. bin/look-ledger.sh status: pages of this module still owed a LOOK
# Then the lead does what no script can: open each owed page as each role that can reach it,
# run the module's unhappy paths, and fix every ⚠ that is real. Record those in the same report.
#
# WHY (run 2, 2026-10-26, arm C). Lint and score ran after every exec (18.3 min) and the ratchet read
# ROSE on 123 of 147 rows, because the baseline cannot be refreshed unattended. Nobody read it. Yet
# the model at row 124 held 6 SEC010 ⚠ (agent-evidence lists empty for the roles that open the page).
# Meanwhile verify-module, gate-check and the LOOK ledger ran 0 times: nothing called them.
# One command at the module boundary makes the per-module pass cheap enough to actually run.
#
# Exit: 0 report written, no ⚠ for this module · 1 report written, findings to act on · 2 usage.
# The report's first lines carry `<!-- mxtk-module-close: lint=N vm=RC -->`. bin/row-groups.sh (the
# exec.sh row-group gate) lets the next module's scripts run when lint=0, or when the lead has filled
# at least one row of section 6's Page | Role table. Findings and an empty table = not closed.
set -u
mod=${1:?usage: bin/module-close.sh <Module>}
# The .mpr and mxcli resolve through _common.sh like every project-bin script, so a two-tree
# checkout (.mpr under app/) and a multi-app folder work; `ls ./*.mpr` found neither (PR #581 review).
. "$(dirname "$0")/_common.sh"
cd "$PROJECT_ROOT" || exit 2
MPR=$(find_mpr) || exit 2
MX=$(find_project_mxcli 2>/dev/null || command -v mxcli) || { echo "module-close: no mxcli (project root or PATH)" >&2; exit 2; }
out=docs/progress/module-close; mkdir -p "$out"; rep="$out/$mod.md"
MXB=${MXTK_MXBUILD_PATH:-}
t0=$(date +%s); now() { date '+%F %H:%M'; }

lint=$("$MX" lint -p "$MPR" 2>&1 | grep -v WARNING)
mine=$(printf '%s\n' "$lint" | grep -A1 '⚠' | grep -B1 -E "\b$mod\." | grep '⚠' || true)
nmine=$(printf '%s' "$mine" | grep -c '⚠' || true)
score=$(bash bin/metrics-ledger.sh score 2>&1 | tail -1)
chk=$("$MX" docker check -p "$MPR" ${MXB:+--mxbuild-path "$MXB"} 2>&1 | grep -v WARNING | tail -3)
# `Gate mode: check` (exec.sh): the module's execs were `mx check`ed, which compiles no Java. The
# module boundary is one of the natural places for the full build, so run it here when the stamp
# says the model has not had one (bin/verify-model.sh: mxbuild deploy build, stamps when clean).
if [ -f .claude/loop/gate-kind.state ] && ! bash bin/model-stamp.sh check -q --full >/dev/null 2>&1; then
  chk="$chk
full build (bin/verify-model.sh): $(bash bin/verify-model.sh 2>&1 | grep -E '^(✓|✗)' | tail -2)"
fi
vm=$(bash bin/verify-module.sh "$mod" --quick 2>&1); vm_rc=$?; vm=$(printf '%s\n' "$vm" | tail -15)
look=$(bash bin/look-ledger.sh status 2>/dev/null | grep -E "\b$mod\." || true)

{
  echo "# Module close: $mod ($(now), $(( $(date +%s) - t0 )) s of instruments)"
  echo
  # Read by bin/row-groups.sh: lint=0, or a filled row in section 6, lets the next module's scripts run.
  echo "<!-- mxtk-module-close: lint=$nmine vm=$vm_rc -->"
  echo
  echo "## 1. Lint ⚠ in $mod: $nmine"
  echo; [ -n "$mine" ] && printf '%s\n' "$mine" | sed 's/^ */- /' || echo "none"
  echo; echo "Whole model: $(printf '%s\n' "$lint" | grep -c '⚠') ⚠, $(printf '%s\n' "$lint" | grep -c 'ℹ') ℹ."
  echo; echo "## 2. Score"; echo; echo "$score"
  echo; echo "## 3. mx check"; echo; echo '```'; echo "$chk"; echo '```'
  echo; echo "## 4. verify-module --quick (exit $vm_rc)"; echo; echo '```'; echo "$vm"; echo '```'
  echo; echo "## 5. LOOK owed in $mod"; echo; [ -n "$look" ] && printf '%s\n' "$look" | sed 's/^/- /' || echo "none recorded"
  echo; echo "## 6. Lead: roles × pages, unhappy paths, fixes"; echo
  echo "| Page | Role | Seen (screenshot path) | Defect | Fixed in row/script |"
  echo "|---|---|---|---|---|"
} > "$rep"
echo "module-close $mod: $nmine lint ⚠, verify-module exit $vm_rc, report $rep"
[ "$nmine" -eq 0 ] || exit 1
