#!/usr/bin/env bash
# app-scope.sh — per-app evidence for a multi-app project (apps/<App>/<App>.mpr, one
# mdlsource/ per app). Sourced by bin/status.sh and bin/gate-check.sh, so the screen and the
# gate print the same facts. Bash 3.2 safe.
#
# The app list is project-bin/_common.sh's mxtk_apps (the one resolver, read in a subshell with
# PROJECT_ROOT pinned), so single-tree and two-tree projects yield nothing and print nothing.
# The register stays ONE (PROJECT.md); only evidence that is per app is reported per app.
#
#   mxtk_scope_apps <project-dir> <toolkit-dir>
#       prints mxtk_apps' lines ("<App><TAB><apps/App/X.mpr>"), or nothing
#   mxtk_app_lines <project-dir> <toolkit-dir>
#       one line per app, "<App><TAB><evidence>", only when there are two or more apps:
#       "apps/<App>/<App>.mpr · scripts N written / D done- · LOOK: K of M page(s) owed"
#       scripts count apps/<App>/mdlsource/ (gallery excluded, as status.sh counts the root);
#       LOOK is `look-ledger.sh status --app <App>` (one project ledger, keyed by app). With no
#       ledger, or no row of this app in it, it says so and counts the pages its scripts create
#       or alter: never "no pages owed" without a ledger to say it (a field run, six apps: the
#       ledger is git-ignored, so a fresh checkout with ~78 built pages read "no pages owed").

mxtk_scope_apps() {
  local pd="$1" tk="$2"
  [ -d "$pd/apps" ] && [ -f "$tk/project-bin/_common.sh" ] || return 0
  ( PROJECT_ROOT="$pd"; MPR_FILE=""; MXTK_APP=""
    . "$tk/project-bin/_common.sh" >/dev/null 2>&1 || exit 0
    mxtk_apps "$pd" 2>/dev/null ) || true
}

mxtk_app_lines() {
  local pd="$1" tk="$2" apps a m d n dn lk ls lt lo
  apps="$(mxtk_scope_apps "$pd" "$tk")"
  [ "$(printf '%s' "$apps" | grep -c . || true)" -ge 2 ] || return 0
  while IFS='	' read -r a m; do
    [ -n "$a" ] || continue
    d="$pd/apps/$a/mdlsource"; n=0; dn=0
    if [ -d "$d" ]; then
      n="$(find "$d" -name '*.mdl' -not -path '*/gallery/*' | wc -l | tr -d ' ')"
      dn="$(find "$d" -name 'done-*.mdl' | wc -l | tr -d ' ')"
    fi
    np=0
    [ -d "$d" ] && np="$(find "$d" -name '*.mdl' -not -path '*/gallery/*' -exec cat {} + 2>/dev/null | awk '
      /^[[:space:]]*--/ { next }
      { l = toupper($0) }
      l ~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER)[[:space:]]+PAGE[[:space:]]/ {
        n = split($0, w, /[[:space:]]+/); for (i = 1; i < n; i++) if (toupper(w[i]) == "PAGE") { x = w[i+1]; break }
        sub(/[(;{].*$/, "", x); gsub(/"/, "", x); if (x ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/) seen[x] = 1 }
      END { k = 0; for (x in seen) k++; print k }')"
    if [ "$np" -eq 0 ]; then lk="LOOK: no page in its scripts"
    elif [ -s "$pd/.claude/loop/look/owed.tsv" ]; then lk="LOOK: no ledger row for this app ($np page(s) in its scripts)"
    else lk="LOOK: no ledger here ($np page(s) in its scripts) — .claude/loop/look/ is written by bin/exec.sh on this machine"; fi
    if [ -s "$pd/.claude/loop/look/owed.tsv" ] && [ -f "$tk/project-bin/look-ledger.sh" ]; then
      ls="$(PROJECT_ROOT="$pd" MPR_FILE="" MXTK_APP="" bash "$tk/project-bin/look-ledger.sh" status --app "$a" 2>/dev/null)"
      lt="$(printf '%s' "$ls" | grep -c . || true)"; lo="$(printf '%s\n' "$ls" | grep -c '^OWED' || true)"
      [ "$lt" -gt 0 ] && lk="LOOK: $lo of $lt page(s) owed"
    fi
    printf '%s\t%s · scripts %s written / %s done- · %s\n' "$a" "$m" "$n" "$dn" "$lk"
  done <<EOF
$apps
EOF
}

# mxtk_scaffold_apps <project-dir> <toolkit-dir> — the per-app planning folders, one convention
# (skills/module-folder-convention.md § Several apps in one repo):
#
#   architecture/apps/README.md               the index: every app, its model, its folders, and
#                                             the rule that the build plan is ONE file
#   architecture/apps/<App>/intake.md         this app's answers; shared answers stay in ./intake.md
#   architecture/apps/<App>/triage.md         Stage 0 per app — only when the project has a root
#                                             triage.md (migration entry mode)
#
# Module briefs do NOT move: they stay architecture/modules/<Module>/module-brief.md, with an
# "**App:** <App>" line, because gate-check build-ready, the artifact manifest, the obligation
# check's module scope, status.sh and the coverage-ledger readers all look there — a per-app
# brief folder would make each of them blind, which is the field run's "no module in scope".
# Under architecture/, not apps/<App>/: apps/<App>/ is the Mendix project folder — what Studio Pro
# commits to Team Server and mxbuild packages — and planning documents do not belong in it.
# Never overwrites; a file that exists is the project's own. Two or more apps only. Prints one
# "Created: ..." line per file it writes. Field reason (2026-11): faced with four apps and a kit
# with no multi-app mode, a lead dropped per-app intake, triage and the register for one
# free-form brief, and that brief carried the spec violation that blocked the first grading.
mxtk_scaffold_apps() {
  local pd="$1" tk="$2" apps a m dir idx n
  apps="$(mxtk_scope_apps "$pd" "$tk")"
  n="$(printf '%s' "$apps" | grep -c . || true)"
  [ "$n" -ge 2 ] || return 0
  mkdir -p "$pd/architecture/apps" || return 0
  while IFS='	' read -r a m; do
    [ -n "$a" ] || continue
    dir="$pd/architecture/apps/$a"
    mkdir -p "$dir"
    if [ ! -f "$dir/intake.md" ]; then
      cat > "$dir/intake.md" <<EOF
# Intake — app $a

Model: \`$m\` · MDL scripts: \`apps/$a/mdlsource/\` · module briefs: \`architecture/modules/<Module>/module-brief.md\` with \`**App:** $a\`

Answers that hold for every app (entry mode, interview mode, sources shared by all apps, NFRs,
security model) live in the project's \`intake.md\` and are not repeated here. Decisions go to
the ONE register, \`PROJECT.md\`, naming the app in the row (\`$a: ...\`). Write each answer as
\`Answered (CONFIRMED): ...\`, \`Assumed: ... — rejected: ...\` or \`Unverified — how to verify: ...\`.

## 1. What this app is for, and who uses it (roles)

## 2. Sources for this app only (code, documents, SME) — and which shared sources it does not use

## 3. Modules it owns, and modules it shares with or calls in a sibling app

## 4. Integrations: what it publishes to or consumes from the other apps (one row each)

## 5. What is out of scope for this app
EOF
      echo "Created: architecture/apps/$a/intake.md"
    fi
    if [ -f "$pd/triage.md" ] && [ ! -f "$dir/triage.md" ] && type mxtk_triage_template >/dev/null 2>&1; then
      { printf '<!-- Stage 0 triage for app %s (model %s). The project triage.md stays the gate; this sheet is the app'"'"'s evidence. -->\n' "$a" "$m"
        mxtk_triage_template; } > "$dir/triage.md"
      echo "Created: architecture/apps/$a/triage.md"
    fi
  done <<EOF
$apps
EOF
  idx="$pd/architecture/apps/README.md"
  if [ ! -f "$idx" ]; then
    { echo "# Apps in this project ($n)"
      echo
      echo "One register (\`PROJECT.md\`), one shared build plan (\`architecture/build-plan.md\`), per-app"
      echo "planning under \`architecture/apps/<App>/\` (skills/module-folder-convention.md § Several apps in one repo)."
      echo "Tools take one app with \`--app <App>\` (gate-check, look-ledger) or \`MXTK_APP=<App>\` (every"
      echo "bin/ script); without one, gate-check and status report one line per app."
      echo
      echo "Module briefs stay in \`architecture/modules/<Module>/module-brief.md\`; each names its app (\`**App:** <App>\`)."
      echo
      echo "| App | Model | MDL scripts | Intake | Modules (filled at Stage 3) |"
      echo "|---|---|---|---|---|"
      printf '%s\n' "$apps" | while IFS='	' read -r a m; do
        [ -n "$a" ] && echo "| $a | \`$m\` | \`apps/$a/mdlsource/\` | \`architecture/apps/$a/intake.md\` | |"
      done
      echo
      echo "## Build plan — one file, every app"
      echo
      echo "\`architecture/build-plan.md\` is shared: one \`## App: <App>\` section per app, in build order,"
      echo "plus one section for the cross-app integrations (the publisher's row before the consumer's)."
      echo "Apps not yet planned:"
      printf '%s\n' "$apps" | while IFS='	' read -r a m; do [ -n "$a" ] && echo "- [ ] $a"; done
    } > "$idx"
    echo "Created: architecture/apps/README.md (index of $n apps)"
  fi
  return 0
}

# mxtk_wiring_rows <project-dir> <toolkit-dir> — for a multi-app project, the two CLAUDE.local.md
# Wiring rows that differ (Project MPR, MDL source dir), as "<mpr cell><TAB><mdl cell>"; nothing
# otherwise, and the caller keeps its single-app rows byte for byte. Field run (2026-11): the
# generated file said nothing about apps, so the project hand-wrote the MPR_FILE workaround.
mxtk_wiring_rows() {
  local apps n names
  apps="$(mxtk_scope_apps "$1" "$2")"
  n="$(printf '%s' "$apps" | grep -c . || true)"
  [ "$n" -ge 2 ] || return 0
  names="$(printf '%s\n' "$apps" | awk -F'\t' 'NF{printf "%s%s", s, $1; s=", "}')"
  printf '%s\t%s\n' \
    "\`apps/<App>/<App>.mpr\` — $n apps: $names | One model per app. Select with \`MXTK_APP=<App>\` (any bin/ script) or \`--app <App>\` (gate-check, look-ledger); with none, gate-check and status report per app. Index: \`architecture/apps/README.md\`" \
    "\`apps/<App>/mdlsource/\` | Numbered build scripts, per app"
}
