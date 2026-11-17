#!/usr/bin/env bash
# app-scope.sh — per-app evidence for a multi-app project (apps/<App>/<App>.mpr, one
# mdlsource/ per app). Sourced by bin/status.sh and bin/gate-check.sh, so the screen and the
# gate print the same facts. Bash 3.2 safe.
#
# The app list is project-bin/_common.sh's mxtk_apps (the one resolver, read in a subshell with
# PROJECT_ROOT pinned), so single-tree and two-tree projects yield nothing and print nothing.
# The register stays ONE (PROJECT.md); only evidence that is per app is reported per app.
#
#   mxtk_scope_init <project-dir> <toolkit-dir>
#       computes the app list ONCE and exports it (MXTK_SCOPE_APPS, keyed by MXTK_SCOPE_ROOT);
#       callers run it in their own shell before the readers below (each re-source of _common.sh
#       cost ~0.1 s; a status run did it three times). gate-check sets the same pair itself.
#   mxtk_scope_apps <project-dir> <toolkit-dir>
#       prints mxtk_apps' lines ("<App><TAB><apps/App/X.mpr>", model "-" when the folder holds
#       several .mpr and none is named for it), or nothing — from the exported list when it was
#       computed for this project, else by sourcing _common.sh in a subshell
#   mxtk_app_lines <project-dir> <toolkit-dir>
#       one line per app, "<App><TAB><evidence>", only when there are two or more apps:
#       "apps/<App>/<App>.mpr · scripts N written / D done- · LOOK: K of M page(s) owed"
#       scripts count apps/<App>/mdlsource/ (gallery excluded, as status.sh counts the root);
#       LOOK is `look-ledger.sh status --app <App>` (one project ledger, keyed by app). With no
#       ledger, or no row of this app in it, it says so and counts the pages its scripts create
#       or alter: never "no pages owed" without a ledger to say it (a field run, six apps: the
#       ledger is git-ignored, so a fresh checkout with ~78 built pages read "no pages owed").

mxtk_scope_init() {
  MXTK_SCOPE_ROOT="$1"; MXTK_SCOPE_APPS=""
  MXTK_SCOPE_APPS="$(MXTK_SCOPE_ROOT=""; mxtk_scope_apps "$1" "$2")"
  export MXTK_SCOPE_APPS MXTK_SCOPE_ROOT
}

mxtk_scope_apps() {
  local pd="$1" tk="$2"
  if [ -n "${MXTK_SCOPE_ROOT:-}" ] && [ "$MXTK_SCOPE_ROOT" = "$pd" ]; then
    [ -n "${MXTK_SCOPE_APPS:-}" ] && printf '%s\n' "$MXTK_SCOPE_APPS"; return 0
  fi
  [ -d "$pd/apps" ] && [ -f "$tk/project-bin/_common.sh" ] || return 0
  ( PROJECT_ROOT="$pd"; MPR_FILE=""; MXTK_APP=""
    . "$tk/project-bin/_common.sh" >/dev/null 2>&1 || exit 0
    mxtk_apps "$pd" 2>/dev/null ) || true
}

mxtk_app_lines() {
  local pd="$1" tk="$2" apps facts look="" own=0
  apps="$(mxtk_scope_apps "$pd" "$tk")"
  [ "$(printf '%s' "$apps" | grep -c . || true)" -ge 2 ] || return 0
  # Per app, in ONE find and ONE awk (a process per app per fact cost ~0.2 s on six apps):
  # "<App> <scripts> <done-> <pages>", pages = distinct Module.Page its scripts create or alter.
  facts="$(find "$pd"/apps/*/mdlsource -name '*.mdl' -not -path '*/gallery/*' 2>/dev/null | awk -v root="$pd/apps/" '
    { f = $0; a = substr(f, length(root) + 1); sub(/\/.*$/, "", a); n[a]++
      b = f; sub(/.*\//, "", b); if (b ~ /^done-/) dn[a]++
      while ((getline line < f) > 0) {
        if (line ~ /^[[:space:]]*--/) continue
        u = toupper(line)
        if (u !~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER)[[:space:]]+PAGE[[:space:]]/) continue
        k = split(line, w, /[[:space:]]+/); x = ""
        for (i = 1; i < k; i++) if (toupper(w[i]) == "PAGE") { x = w[i+1]; break }
        sub(/[(;{].*$/, "", x); gsub(/"/, "", x)
        if (x ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/ && !((a SUBSEP x) in seen)) { seen[a SUBSEP x] = 1; np[a]++ }
      }
      close(f) }
    END { for (a in n) print a, n[a], dn[a] + 0, np[a] + 0 }')"
  # The LOOK ledger once, every app (look-ledger.sh status --by-app: one project ledger, keyed by app).
  if [ -s "$pd/.claude/loop/look/owed.tsv" ] && [ -f "$tk/project-bin/look-ledger.sh" ]; then
    own=1
    look="$(PROJECT_ROOT="$pd" MPR_FILE="" MXTK_APP="" bash "$tk/project-bin/look-ledger.sh" status --by-app 2>/dev/null)"
  fi
  # One join, one awk: apps (in mxtk_apps order) x facts x LOOK counts.
  { printf '%s\n' "$apps" | awk '{ print "A\t" $0 }'
    printf '%s\n' "$facts" | sed 's/^/F /'
    printf '%s\n' "$look" | awk -F'\t' 'NF >= 4 { t[$4]++; if ($1 == "OWED") o[$4]++ } END { for (a in t) print "L", a, t[a], o[a] + 0 }'
  } | awk -v own="$own" '
    /^A\t/ { split($0, x, "\t"); if (x[2] == "") next; ord[++na] = x[2]; mdl[x[2]] = x[3]; next }
    $1 == "F" { n[$2] = $3; dn[$2] = $4; np[$2] = $5; next }
    $1 == "L" { lt[$2] = $3; lo[$2] = $4; next }
    END {
      for (i = 1; i <= na; i++) {
        a = ord[i]; m = mdl[a]
        if (lt[a] + 0 > 0) lk = "LOOK: " lo[a] " of " lt[a] " page(s) owed"
        else if (np[a] + 0 == 0) lk = "LOOK: no page in its scripts"
        else if (own == 1) lk = "LOOK: no ledger row for this app (" np[a] " page(s) in its scripts)"
        else lk = "LOOK: no ledger here (" np[a] " page(s) in its scripts) — .claude/loop/look/ is written by bin/exec.sh on this machine"
        if (m == "-") m = "apps/" a "/ (several .mpr, none named " a ".mpr: set MPR_FILE)"
        printf "%s\t%s · scripts %d written / %d done- · %s\n", a, m, n[a], dn[a], lk
      }
    }'
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

# mxtk_app_register_notes <project-dir> <toolkit-dir> — one line per app whose OWN PROJECT.md
# (apps/<App>/PROJECT.md, e.g. from `mxcli init` run per app) holds register lines: an Entry mode,
# a "## Current stage" **Stage line, an "Adopted at stage:" line, or CONFIRMED / ASSUMED table
# rows. The register is the ROOT PROJECT.md (gate-check never reads an app's); a second register
# per app is where decisions go to be lost. Warn-only, never a verdict. An app PROJECT.md with
# none of those lines (a plain mxcli template) says nothing. Field run (six apps): seven
# PROJECT.md files, one per app plus the root.
mxtk_app_register_notes() {
  local pd="$1" tk="$2" apps a m files=""
  apps="$(mxtk_scope_apps "$pd" "$tk")"
  [ "$(printf '%s' "$apps" | grep -c . || true)" -ge 2 ] || return 0
  while IFS='	' read -r a m; do
    [ -n "$a" ] && [ -f "$pd/apps/$a/PROJECT.md" ] && files="$files$a
"
  done <<EOF
$apps
EOF
  [ -n "$files" ] || return 0
  # One awk: the root PROJECT.md first (its Entry mode), then each app's, in app order.
  printf '%s' "$files" | { set --; while IFS= read -r a; do set -- "$@" "$pd/apps/$a/PROJECT.md"; done
    awk -v root="$pd/PROJECT.md" '
      function em(line,   l, w) { l = tolower(line); gsub(/[*_>]/, "", l); sub(/^[ \t-]+/, "", l)
        if (l !~ /^entry mode[ \t]*:/) return ""; sub(/^entry mode[ \t]*:[ \t]*/, "", l); split(l, w, /[ \t(,;]+/); return w[1] }
      function flush(   a, f) {
        if (cur == "") return
        a = cur; sub(/\/PROJECT\.md$/, "", a); sub(/.*\//, "", a); f = ""
        if (e != "") { if (rem != "" && e != rem) f = "Entry mode: " e ", the root says " rem
                       else if (rem == "") f = "Entry mode: " e ", the root has none"; else f = "Entry mode" }
        if (st) f = f (f != "" ? "; " : "") "Current stage"
        if (ad) f = f (f != "" ? "; " : "") "Adopted at stage"
        if (nd) f = f (f != "" ? "; " : "") nd " decision row(s)"
        if (f != "") printf "%s\tapps/%s/PROJECT.md holds register lines (%s): the register is the root PROJECT.md, which gate-check reads; move them there and leave the app file a pointer\n", a, a, f
      }
      BEGIN { while ((getline line < root) > 0) if (rem == "" && (x = em(line)) != "") rem = x; close(root) }
      FNR == 1 { flush(); cur = FILENAME; e = ""; st = 0; ad = 0; nd = 0; cs = 0 }
      { if (e == "") e = em($0)
        if ($0 ~ /^## Current stage/) cs = 1; else if ($0 ~ /^## /) cs = 0
        if (cs && $0 ~ /^\*\*Stage/) st = 1
        if (tolower($0) ~ /^adopted at stage:/) ad = 1
        if ($0 ~ /^\|.*\|[[:space:]]*\**(CONFIRMED|ASSUMED)/) nd++ }
      END { flush() }' "$@"; }
}
