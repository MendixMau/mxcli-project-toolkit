#!/usr/bin/env bash
# ci-template.sh — install the project's CI gate (templates/ci/toolkit-gates.yml) as
# .github/workflows/toolkit-gates.yml. ONE copy, sourced by bin/init-project.sh and bin/sync-project.sh,
# for the same reason as ritual-template.sh: two hand-kept installers drift.
#
# Contract: CREATE-IF-ABSENT, never overwrite. The file is the project's once it exists (it may have
# been adapted: a fork's repo URL, a token, a runner); a copy that differs from the template is only
# reported. Other workflows in .github/workflows/ are left untouched: this is a separate workflow,
# not an edit of an existing one, so it sits beside whatever CI the repo already has.
#
# Sourced, never executed. Side-effect free until called.

# mxtk_ci_install <toolkit-root> <project-root> [dry-run 0|1] — prints one line; returns 0 when it
# created the file (a change), 1 otherwise.
mxtk_ci_install() {
  local tk="$1" pr="$2" dry="${3:-0}" src dst other
  src="$tk/templates/ci/toolkit-gates.yml"; dst="$pr/.github/workflows/toolkit-gates.yml"
  [ -f "$src" ] || return 1
  if [ -f "$dst" ]; then
    cmp -s "$src" "$dst" || echo "Kept: .github/workflows/toolkit-gates.yml differs from the toolkit template (yours, not overwritten; compare with $src)"
    return 1
  fi
  other="$(ls "$pr/.github/workflows" 2>/dev/null | grep -E '\.ya?ml$' | tr '\n' ' ')"
  if [ "$dry" = 1 ]; then echo "Would create: .github/workflows/toolkit-gates.yml (the CI gate an agent cannot skip)"; return 0; fi
  mkdir -p "$pr/.github/workflows" && cp "$src" "$dst" || return 1
  echo "Created: .github/workflows/toolkit-gates.yml — the CI gate an agent cannot skip (bin/ci-gates.sh on every push and PR)${other:+; existing workflows left untouched: $other}"
  return 0
}
