#!/usr/bin/env bash
# THE install manifest — what a wired project gets, in ONE place.
#
# WHY THIS FILE EXISTS. init-project.sh, init-agents.sh and sync-project.sh each carried
# their own hardcoded list of what to install. They agreed on the day they were written and
# drifted afterwards, silently, because nothing compares them:
#
#   - init-agents.sh installed 5 agents; sync-project.sh installed 6. Net effect:
#     review-agent.md NEVER reached a freshly scaffolded project. It only appeared if
#     somebody happened to run sync-project.sh later.
#   - init-project.sh copied 7 project-bin scripts; sync-project.sh copied 9. The two it
#     omitted — conformance-check.sh and graph-sweep.sh — are exactly the instruments
#     review-agent.md depends on. So the agent that was missing also had its tools missing.
#
# Anything a project should receive is named here ONCE and read by all three scripts. Adding
# a new agent or a new project-bin script is a one-word change in this file, and no installer
# can be a version behind another again.
#
# Sourced, never executed. Callers are `set -euo pipefail`, so keep this side-effect free.

# Agents installed into <project>/.claude/agents/. Explicit, NOT a glob over agents/*.md —
# a glob installs any doc that happens to sit in agents/ as an extra agent, and one without
# YAML frontmatter is silently broken in the target project.
MXTK_AGENTS="ba-agent.md architect-agent.md mdl-agent.md gate-agent.md test-agent.md review-agent.md"

# Stage subsets for init-agents.sh. Their union MUST equal MXTK_AGENTS — asserted below,
# so a new agent added to MXTK_AGENTS and forgotten here fails loudly at source time
# instead of quietly never being scaffolded (the exact failure this file was written for).
MXTK_AGENTS_STAGE_P="ba-agent.md architect-agent.md"
MXTK_AGENTS_STAGE_BUILD="mdl-agent.md gate-agent.md test-agent.md review-agent.md"

# Scripts copied from toolkit project-bin/ into <project>/bin/, in three groups:
#   1-7  the crash net            snapshot / restore / guarded exec / SP handling
#   8-9  review instruments       the read-only model-side checks review-agent.md invokes
#  10-13 verification + hygiene   the module-end deep pass, the stack precondition it depends
#                                 on, the journey-fixture probe, and the root-cleanliness
#                                 backstop the gate runs
# The same install rule applies to all three: missing -> install, already present -> keep (a
# project may have hardened its copy), never blind-overwrite.
#
# verify-module.sh and test-stack-up.sh are a pair — verify-module's rung 0 IS test-stack-up
# --check, and without it every runtime rung below runs against a guessed port. Never install
# one without the other.
#
# fixture-manifest.sh is the executable step 1-3 of skills/fixture-seeding.md. It sat in
# project-bin/ unnamed here and therefore installed into NO project at all, while the skill
# documented it as the entry point — the reverse self-check below exists because of it.
MXTK_PROJECT_BIN="_common.sh snapshot-mpr.sh restore-mpr.sh exec.sh save-sp.sh restart-sp.sh check-sp-health.sh conformance-check.sh graph-sweep.sh verify-module.sh test-stack-up.sh fixture-manifest.sh check-root-clean.sh"

# Files in project-bin/ that are deliberately NOT installed into projects. Empty today, and that
# is the point: the reverse check below flags anything named by NEITHER list, so a new file in
# project-bin/ has to be either installed or declared unwanted. "Nobody noticed" stops being a
# third option. Add a name here only with a one-line reason on the same line as a comment.
MXTK_PROJECT_BIN_NOINSTALL=""

# --- self-check: subsets must cover the whole agent list -------------------------------
_mxtk_manifest_check() {
  local union all
  union="$(printf '%s\n' $MXTK_AGENTS_STAGE_P $MXTK_AGENTS_STAGE_BUILD | sort -u)"
  all="$(printf '%s\n' $MXTK_AGENTS | sort -u)"
  if [ "$union" != "$all" ]; then
    echo "install-manifest.sh: stage subsets do not cover MXTK_AGENTS." >&2
    echo "  only in MXTK_AGENTS:  $(comm -23 <(printf '%s\n' "$all") <(printf '%s\n' "$union") | tr '\n' ' ')" >&2
    echo "  only in the subsets:  $(comm -13 <(printf '%s\n' "$all") <(printf '%s\n' "$union") | tr '\n' ' ')" >&2
    return 1
  fi
}

# --- self-check: every named project-bin script must actually exist ---------------------
# The manifest's whole job is to be TRUE. A name here that has no file installs nothing and warns
# nobody — the same silent-drift failure one level down from the one this file was written for.
# Only runs when project-bin/ is reachable, i.e. when sourced from inside the toolkit; a wired
# project sources this file too and has no project-bin/ of its own.
_mxtk_manifest_check_bin() {
  local here dir f missing=""
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  dir="$here/../../project-bin"
  [ -d "$dir" ] || return 0
  for f in $MXTK_PROJECT_BIN; do
    [ -f "$dir/$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    echo "install-manifest.sh: MXTK_PROJECT_BIN names files that do not exist in project-bin/:" >&2
    echo "  $missing" >&2
    echo "  Either add the script or remove the name — a manifest that lies installs nothing." >&2
    return 1
  fi
}

# --- self-check, the other direction: every existing project-bin script must be named --------
# The forward check above proves the manifest does not LIE. It cannot prove the manifest is
# COMPLETE, and completeness is the failure that actually happened: fixture-manifest.sh sat in
# project-bin/ for weeks, documented by skills/fixture-seeding.md as the entry point, installed
# into zero projects, and every check in this file passed the whole time.
#
# WARNING, NOT FAILURE — deliberately, and the reasoning matters because the wrong choice here
# reintroduces the bug:
#   * The forward check hard-fails because a named-but-absent file breaks the installer that is
#     running right now. An unnamed-but-present file breaks nothing at install time; it only
#     means a capability never travels. Aborting init-project.sh over it would take a working
#     scaffold down for a scratch file somebody left in project-bin/, and a check that can brick
#     the installer over an unrelated stray is a check that gets commented out within a week.
#   * The reason it stays honest anyway is MXTK_PROJECT_BIN_NOINSTALL: a genuinely
#     not-for-install file is silenced by DECLARING it, not by ignoring the message. So the
#     warning only ever fires on an undecided file, which is exactly the condition worth naming,
#     and it cannot decay into background noise that everyone learns to scroll past.
# If a caller wants this fatal (a CI gate, say), call the function and check its output — it
# prints the offending names to stderr and always returns 0.
_mxtk_manifest_check_bin_unnamed() {
  local here dir p f unnamed=""
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  dir="$here/../../project-bin"
  [ -d "$dir" ] || return 0
  for p in "$dir"/*; do
    [ -f "$p" ] || continue
    f="$(basename "$p")"
    case " $MXTK_PROJECT_BIN $MXTK_PROJECT_BIN_NOINSTALL " in *" $f "*) continue ;; esac
    unnamed="$unnamed $f"
  done
  if [ -n "$unnamed" ]; then
    echo "install-manifest.sh: project-bin/ holds file(s) named by NEITHER list:" >&2
    echo " $unnamed" >&2
    echo "  They install into no project at all. Add each to MXTK_PROJECT_BIN, or to" >&2
    echo "  MXTK_PROJECT_BIN_NOINSTALL with a reason. This is a warning, not a failure." >&2
  fi
  return 0
}

_mxtk_manifest_check
_mxtk_manifest_check_bin
_mxtk_manifest_check_bin_unnamed
