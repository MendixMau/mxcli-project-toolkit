#!/usr/bin/env bash
# Refreshes the toolkit artifacts that were COPIED into a project (everything referenced
# from the toolkit clone updates by git pull alone — this handles only the copies).
#
# Safe by construction:
#   - intake.md: appends questions that exist in the current template but not in the file.
#     Never rewrites existing answers, and offers — never performs unprompted — a replacement
#     of a template question whose boilerplate is provably untouched (--repair-intake).
#   - bin/ crash net: installs what is MISSING and repairs a lost exec bit. A locally modified
#     script is REPORTED, never overwritten, unless --upgrade-bin names it (and then the local
#     copy is backed up first). Six of this machine's projects have hand-hardened their
#     exec.sh; a blind-overwrite sync would have destroyed all six.
#   - agent stubs: refreshes only PURE stubs (still carry the STUB marker and at least one
#     {{PLACEHOLDER}} — i.e. nobody completed them). Completed agents are never touched;
#     they get a "review against current template" note instead.
#   - CLAUDE.md baseline routing: report-only (merging prose is an LLM job — see
#     bootstrap-project.md audit mode).
#
# Run after every `git pull` of the toolkit:  bin/sync-project.sh <project-root>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../agents"

# THE agent list. Explicit, NOT a glob over agents/*.md — a glob installs any doc that
# happens to sit in agents/ as an extra agent, and one without YAML frontmatter is
# silently broken in the target project. Adding an agent to the toolkit is a one-word
# change here; both the sync loop and --diff-completed read this list.
AGENTS="ba-agent.md architect-agent.md mdl-agent.md gate-agent.md test-agent.md"

DIFF_COMPLETED=0
DRY_RUN=0
STRICT=0
UPGRADE_BIN=""
REPAIR_INTAKE=0
PROJECT_DIR=""
USAGE="Usage: $0 <project-root> [--diff-completed] [--dry-run] [--strict]
                          [--upgrade-bin <script.sh|all>] [--repair-intake]"
while [ $# -gt 0 ]; do
  case "$1" in
    --diff-completed) DIFF_COMPLETED=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --strict)         STRICT=1; shift ;;
    --repair-intake)  REPAIR_INTAKE=1; shift ;;
    --upgrade-bin)
      shift
      [ $# -gt 0 ] || { echo "--upgrade-bin needs a script name or 'all'" >&2; exit 1; }
      UPGRADE_BIN="$1"; shift ;;
    -h|--help)
      echo "$USAGE"
      echo
      echo "  (default)          refresh copied artifacts; never touches a completed agent,"
      echo "                     a locally-modified bin/ script, or an edited intake answer"
      echo "  --diff-completed   report-only: show how each COMPLETED agent has diverged from"
      echo "                     its template, in both directions. Nothing is written."
      echo "  --dry-run          report every action that would be taken; write nothing"
      echo "  --strict           exit 3 if any warning was emitted (for CI / gate-check)"
      echo "  --upgrade-bin X    accept the toolkit version of a LOCALLY MODIFIED bin/ crash-net"
      echo "                     script (or 'all'). The project copy is backed up first."
      echo "  --repair-intake    accept the offered repair of a stale, still-verbatim intake"
      echo "                     question (see the OFFER printed by a plain run). Only ever"
      echo "                     rewrites boilerplate nobody has edited."
      exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *)  PROJECT_DIR="$1"; shift ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  echo "$USAGE" >&2
  exit 1
fi
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$(cd "$PROJECT_DIR" && pwd)")"

# --- 0. --diff-completed: the reverse path ----------------------------------------------
# Sync only ever flowed downhill. A completed agent was cut off from its template in BOTH
# directions: the project never saw template improvements, and the toolkit never saw what
# the project learned. The old code said "review it manually if the template changed",
# which nobody can act on without knowing WHAT changed. This makes that concrete.
#
# Report-only, always. Promotion is a human decision, per the toolkit's own rule that work
# lands in a project first and moves upstream only on explicit instruction.
if [ "$DIFF_COMPLETED" -eq 1 ]; then
  echo "=== Completed-agent divergence for $PROJECT_DIR ==="
  echo "Report-only; nothing is written."
  echo
  AGENT_DIR="$PROJECT_DIR/.claude/agents"
  if [ ! -d "$AGENT_DIR" ]; then
    echo "No .claude/agents/ here — nothing to compare."
    exit 0
  fi
  any=0
  for a in $AGENTS; do
    src="$TEMPLATE_DIR/$a"
    dst="$AGENT_DIR/$a"
    [ -f "$src" ] && [ -f "$dst" ] || continue
    # Pure stubs are handled by the normal sync path; only completed agents are interesting.
    if grep -q "STUB GENERATED" "$dst" && grep -q "{{[A-Z_]*[^}]*}}" "$dst"; then
      continue
    fi
    any=1
    TMPL=$(mktemp "${TMPDIR:-/tmp}/synctmpl.XXXXXX") || exit 2
    sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$TMPL"
    tonly=$(diff "$TMPL" "$dst" | grep -c '^<' || true)
    ponly=$(diff "$TMPL" "$dst" | grep -c '^>' || true)
    echo "--- $a"
    echo "    $tonly line(s) only in TEMPLATE  → this project may be missing a template improvement"
    echo "    $ponly line(s) only in PROJECT   → candidate for promotion upstream"
    if [ "$tonly" -gt 0 ] || [ "$ponly" -gt 0 ]; then
      # `|| true` is load-bearing: diff exits 1 whenever it finds differences, which under
      # `set -e` + `pipefail` killed the loop after the FIRST diverging agent. The report
      # looked fine — it just silently stopped at 1 of 5.
      diff -u --label "template/$a" "$TMPL" --label "project/$a" "$dst" | sed 's/^/      /' || true
    fi
    rm -f "$TMPL"
    echo
  done
  [ "$any" -eq 1 ] || echo "No completed agents — all still pure stubs."
  echo "Placeholder-substitution noise is expected on project-fact lines (glossary, paths,"
  echo "commands). What matters is PROTOCOL that exists on one side only."
  exit 0
fi

echo "=== Toolkit sync for $PROJECT_DIR ==="
[ "$DRY_RUN" -eq 1 ] && echo "(--dry-run: nothing will be written)"
CHANGES=0
WARNINGS=0

# Every warning goes through here. Before this, a warning printed and the script still exited 0
# AND still closed with "All copied artifacts up to date" — the caller could not tell a clean
# sync from a broken one.
warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "⚠️  $1"; shift
  while [ $# -gt 0 ]; do echo "   $1"; shift; done
}

# --- 1. intake.md: add questions this file lacks, and OFFER to repair stale boilerplate --
# Absence is not the only failure mode. Projects scaffolded before 12828e4 carry a Q9 whose
# body has neither an "Answered" nor an "Unverified — how to verify" line, so gate-check.sh's
# Stage P check fails on the toolkit's own scaffold — forever, because an absence-only guard
# (`! grep -q "^## 9\."`, testing the HEADING when 12828e4 changed the BODY) can add a missing
# question but can never repair a stale one.
#
# Repair is OFFERED, never forced, and only when the section is still the untouched pre-fix
# boilerplate (byte-identical — the same criterion gate-check.sh's hint uses before it names
# this command). If the user has written anything of their own there, we say so and stop:
# silently rewriting an answered intake question is data loss, and the stale text reads enough
# like an answer that someone may well have edited it into one.
q9_current_text() {
  cat <<'EOF'
## 9. Interview mode: attended (default) or unattended?

Unverified — how to verify: ask the user; default is attended. Attended = every gate question
is asked in chat and the agent waits for the answer. Unattended (opt-in only, explicit request
required) = recommended options are applied as ASSUMED and logged for later reconciliation.
EOF
}
# Byte-for-byte the pre-12828e4 body. MUST stay identical to gate-check.sh's function of the
# same name: that one decides whether to PRINT the hint, this one decides whether to ACT on it.
# If they drift, the gate points at a command that refuses.
q9_stale_scaffold_text() {
  cat <<'EOF'
## 9. Interview mode: attended (default) or unattended?

Attended unless the user explicitly says otherwise. Attended = every gate question is asked
in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options
are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.
EOF
}
# Print section "## 9." up to the next "## " heading, trailing blank lines stripped.
q9_section() {
  awk '/^## 9\./{insec=1} insec && /^## /&&!/^## 9\./{insec=0} insec{print}' "$1" \
    | awk '{a[NR]=$0} END{last=NR; while(last>0 && a[last]~/^[ \t]*$/) last--; for(i=1;i<=last;i++) print a[i]}'
}

# Grade the file gate-check.sh grades. Root first, then the documented analysis/<name>/ layout —
# otherwise the hint gate-check prints ("sync-project.sh <dir> --repair-intake") lands on a
# project where sync says "no intake.md" and the user has no path from the tool to the cause.
INTAKE=""
for cand in "$PROJECT_DIR/intake.md" "$PROJECT_DIR"/analysis/*/intake.md "$PROJECT_DIR/analysis/intake.md"; do
  [ -f "$cand" ] || continue
  if [ -z "$INTAKE" ]; then
    INTAKE="$cand"
  elif ! cmp -s "$INTAKE" "$cand"; then
    INTAKE="AMBIGUOUS"
    break
  fi
done

if [ "$INTAKE" = "AMBIGUOUS" ]; then
  warn "two different intake.md files exist under $PROJECT_DIR — gate-check.sh refuses to grade" \
       "either, and this script will not guess which one to repair. Delete or merge the stale" \
       "copy (the analysis/<name>/ one is normally the live one), then re-run."
elif [ -n "$INTAKE" ]; then
  if ! grep -q "^## 9\." "$INTAKE"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "Would update: $INTAKE — append Q9 (interview mode)."
    else
      printf '\n' >> "$INTAKE"
      q9_current_text >> "$INTAKE"
      echo "Updated: $INTAKE — appended Q9 (interview mode). Answer it this session."
    fi
    CHANGES=$((CHANGES + 1))
  elif ! q9_section "$INTAKE" | grep -q 'Answered\|Unverified'; then
    # Present, but ungradeable by gate-check's Stage P check.
    Q9_TMP=$(mktemp "${TMPDIR:-/tmp}/q9sec.XXXXXX") || exit 2
    Q9_REF=$(mktemp "${TMPDIR:-/tmp}/q9ref.XXXXXX") || exit 2
    q9_section "$INTAKE" > "$Q9_TMP"
    q9_stale_scaffold_text > "$Q9_REF"
    if cmp -s "$Q9_TMP" "$Q9_REF"; then
      if [ "$REPAIR_INTAKE" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "Would repair: $INTAKE — Q9 replaced with the current template text."
        else
          Q9_NEW=$(mktemp "${TMPDIR:-/tmp}/q9new.XXXXXX") || exit 2
          q9_current_text > "$Q9_NEW"
          AWK_OUT=$(mktemp "${TMPDIR:-/tmp}/intake.XXXXXX") || exit 2
          # BSD awk (stock macOS) rejects a newline inside -v ("awk: newline in string"), so the
          # replacement text is streamed from a file rather than passed as a variable. GNU awk
          # accepts the naive form — this breaks only on the target platform.
          awk -v repl="$Q9_NEW" '
            /^## 9\./ { insec=1; while ((getline l < repl) > 0) print l; close(repl); next }
            insec && /^## / { insec=0 }
            insec { next }
            { print }' "$INTAKE" > "$AWK_OUT"
          cat "$AWK_OUT" > "$INTAKE"
          rm -f "$Q9_NEW" "$AWK_OUT"
          echo "Repaired: $INTAKE — Q9 replaced with the current template text (it was untouched"
          echo "          pre-12828e4 boilerplate that could never pass gate-check's Stage P)."
        fi
        CHANGES=$((CHANGES + 1))
      else
        echo "OFFER: intake.md Q9 is the pre-12828e4 boilerplate — it has no 'Answered' or"
        echo "       'Unverified — how to verify' line, so gate-check.sh <dir> P can never pass."
        echo "       The text is untouched, so replacing it loses nothing. Accept with:"
        echo "         $0 $PROJECT_DIR --repair-intake"
      fi
    else
      warn "$INTAKE Q9 has no 'Answered'/'Unverified — how to verify' line, so Stage P will" \
           "FAIL — but the text has been edited, so this may be a real answer. NOT touching it." \
           "Prefix your answer with 'Answered (verified by inspection):'."
    fi
    rm -f "$Q9_TMP" "$Q9_REF"
  fi
else
  echo "Note: no intake.md — run bin/init-project.sh first if this project uses the pipeline."
fi

# --- 2. Agent stubs: refresh pure stubs, report completed ones --------------------------
AGENT_DIR="$PROJECT_DIR/.claude/agents"
if [ -d "$AGENT_DIR" ]; then
  for a in $AGENTS; do
    src="$TEMPLATE_DIR/$a"
    [ -f "$src" ] || { echo "Error: template missing: $src" >&2; continue; }
    dst="$AGENT_DIR/$a"
    if [ ! -f "$dst" ]; then
      sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$dst"
      echo "Created: .claude/agents/$a (new since this project was scaffolded)"
      CHANGES=$((CHANGES + 1))
    elif grep -q "STUB GENERATED" "$dst" && grep -q "{{[A-Z_]*[^}]*}}" "$dst"; then
      # Pure stub, never completed — safe to refresh with the current template.
      if ! sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" | cmp -s - "$dst"; then
        sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$dst"
        echo "Refreshed: .claude/agents/$a (was an untouched stub; template has changed)"
        CHANGES=$((CHANGES + 1))
      fi
    else
      echo "Kept: .claude/agents/$a is completed — see what diverged with: $0 $PROJECT_DIR --diff-completed"
    fi
  done
else
  echo "Note: no .claude/agents/ here — run bin/init-agents.sh $PROJECT_DIR if sessions run from this directory."
fi

# --- 2b. CLAUDE.local.md: append the session-start ritual if this project predates it ---
CL="$PROJECT_DIR/CLAUDE.local.md"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$CL" ] && ! grep -q "Session-start ritual" "$CL"; then
  cat >> "$CL" <<EOF

## Session-start ritual (mandatory, before any pipeline work)

1. \`git -C $TOOLKIT_ROOT pull --ff-only\` then \`git -C $TOOLKIT_ROOT rev-parse --short HEAD\`
2. If the commit differs from \`PROJECT.md\`'s \`Toolkit commit:\` line: re-read
   \`$TOOLKIT_ROOT/skills/conversion-runbook.md\` in full, then update that line.
3. State in chat which commit you're working from. gate-check blocks all gates on a mismatch.
EOF
  echo "Updated: CLAUDE.local.md — appended the session-start ritual."
  CHANGES=$((CHANGES + 1))
fi
if [ -f "$PROJECT_DIR/PROJECT.md" ] && ! grep -q "Toolkit commit:" "$PROJECT_DIR/PROJECT.md"; then
  printf '\nToolkit commit: (set at session start — see CLAUDE.local.md ritual)\n' >> "$PROJECT_DIR/PROJECT.md"
  echo "Updated: PROJECT.md — added the Toolkit commit acknowledgement line."
  CHANGES=$((CHANGES + 1))
fi

# --- 2c. CLAUDE.local.md: append the Wiring block if this project predates it -----------
# Agents resolve all paths from this block; a project scaffolded before it has none.
if [ -f "$CL" ] && ! grep -q "## Wiring" "$CL"; then
  MPR_NAME="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1 | xargs -r basename || echo "<name>.mpr")"
  cat >> "$CL" <<EOF

## Wiring — single source of truth for all paths (agents read THIS block, not per-agent copies)

Paths below are the toolkit conventions — **confirm each exists and correct any that differ**; a path
that doesn't resolve is a wiring failure the \`build-ready\` gate catches. Refresh after a toolkit pull.

| Key | Path | Notes |
|---|---|---|
| Toolkit root | \`$TOOLKIT_ROOT\` | The process authority |
| Toolkit commit | see \`PROJECT.md\` \`Toolkit commit:\` | Authoritative there; ritual keeps it fresh |
| Project MPR | \`$MPR_NAME\` | The model file |
| MDL source dir | \`mdlsource/\` | Numbered build scripts |
| Module briefs | \`architecture/modules/<Module>/\` | one \`module-brief.md\` per module |
| Wireframes | \`design/wireframes/\` | one annotated HTML per screen |
| Design system | \`design/ds.css\` + \`design/design-system.html\` | tokens + component showcase |
| StyleGallery MDL | \`mdlsource/gallery/\` | or "not built yet" |
| Architecture | \`architecture/blueprint.md\` | blueprint + fit-gap |
| Build plan | \`architecture/build-plan.md\` | numbered, dependency-ordered |
| Business rules | \`analysis/<source>/knowledge-base/\` | BRDs (\`F<NNN>.brd.json\`) |
| UI review reports | \`design/ui-reviews/\` | \`ui-review-<date>.html\` (\`ui-review-loop.md\`) |
EOF
  echo "Updated: CLAUDE.local.md — appended the Wiring block. CONFIRM its paths this session."
  CHANGES=$((CHANGES + 1))
fi
# Baseline routing must include the UI-quality skills (added after the WMS UI audit).
# Test ui-preflight-pages, NOT ui-review-loop: the Wiring block §2c appends just above contains
# the literal "ui-review-loop.md" in its "UI review reports" row, so the old test was
# permanently satisfied by sync's OWN output — silent forever, on projects with no Baseline
# routing table at all.
if [ -f "$CL" ] && ! grep -q "ui-preflight-pages" "$CL"; then
  warn "CLAUDE.local.md baseline routing is missing the UI-quality rows (ui-review-loop.md," \
       "ui-preflight-pages.md, module-brief.md, learned-stylegallery.md) — add them from" \
       "README.md 'Baseline routing'; the mdl-agent won't route to the UI gates without them."
fi

# --- 3. Baseline routing / runbook-first wiring -----------------------------------------
if [ ! -f "$PROJECT_DIR/CLAUDE.local.md" ] && { [ ! -f "$PROJECT_DIR/CLAUDE.md" ] || ! grep -q "conversion-runbook" "$PROJECT_DIR/CLAUDE.md"; }; then
  warn "No runbook-first wiring found (no CLAUDE.local.md, and CLAUDE.md doesn't reference" \
       "conversion-runbook.md). Run: $SCRIPT_DIR/init-project.sh $PROJECT_DIR" \
       "(idempotent — it will only add the missing CLAUDE.local.md, never overwrite files)."
fi
for cm in "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.local.md"; do
  if [ -f "$cm" ] && ! grep -q "query-the-model" "$cm"; then
    warn "$(basename "$cm") does not reference the Baseline routing set — audit it per bootstrap-project.md."
  fi
done

# --- 4. Crash net: refresh bin/ guard scripts (OFFER, never force) ----------------------
# init-project.sh installs seven project-local guard scripts into bin/. Sync did not look at
# bin/ at all, so a project kept whatever crash net it was BORN with — including versions with
# the `set -e` gap and the "restores over every successful build" bug — and the documented
# "refresh this project after a toolkit pull" command healed none of it, then printed
# "All copied artifacts up to date".
#
# It cannot simply copy over them either. Census of the 8 crash-net projects on this machine:
# 56 slots, 13 identical, 25 locally modified, 18 missing — and exec.sh is locally modified in
# ALL 6 projects that have one (WMS-Demo-main's carries a build-rollback fix that never went
# upstream). A blind-overwrite sync destroys real work in six projects at once. So:
#   missing          -> install (nothing local to destroy)
#   identical        -> leave alone; repair the exec bit if it was lost
#   locally modified -> REPORT the drift, print how to see it and how to accept it.
#                       Never overwritten without --upgrade-bin, which backs the copy up first.
CRASHNET_SRC="$(cd "$SCRIPT_DIR/.." && pwd)/project-bin"
CRASHNET_FILES="_common.sh snapshot-mpr.sh restore-mpr.sh exec.sh save-sp.sh restart-sp.sh check-sp-health.sh"
# Only manage bin/ in a directory that is actually a wired project. Otherwise a mistyped path
# (`sync-project.sh ~/Downloads`) scatters seven executables into somebody's folder.
WIRED=0
for m in bin PROJECT.md intake.md CLAUDE.local.md; do
  [ -e "$PROJECT_DIR/$m" ] && WIRED=1
done
if [ "$WIRED" -eq 0 ]; then
  warn "$PROJECT_DIR has no PROJECT.md, intake.md, CLAUDE.local.md or bin/ — this does not look" \
       "like a wired project, so the crash net was not touched. Run bin/init-project.sh first."
elif [ -d "$CRASHNET_SRC" ]; then
  DRIFTED=""
  if [ ! -d "$PROJECT_DIR/bin" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then echo "Would create: bin/"; else mkdir -p "$PROJECT_DIR/bin"; fi
  fi
  for s in $CRASHNET_FILES; do
    src="$CRASHNET_SRC/$s"
    dst="$PROJECT_DIR/bin/$s"
    [ -f "$src" ] || continue
    if [ ! -f "$dst" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "Would install: bin/$s (missing from this project's crash net)"
      else
        cp "$src" "$dst"; chmod +x "$dst"
        echo "Installed: bin/$s (was missing from this project's crash net)"
      fi
      CHANGES=$((CHANGES + 1))
    elif cmp -s "$src" "$dst"; then
      if [ ! -x "$dst" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "Would chmod +x: bin/$s (matches the template but is not executable)"
        else
          chmod +x "$dst"
          echo "Repaired: bin/$s exec bit (matched the template but was not executable)"
        fi
        CHANGES=$((CHANGES + 1))
      fi
    else
      DRIFTED="$DRIFTED $s"
      add=$(diff "$src" "$dst" | grep -c '^>' || true)
      del=$(diff "$src" "$dst" | grep -c '^<' || true)
      if [ "$UPGRADE_BIN" = "all" ] || [ "$UPGRADE_BIN" = "$s" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "Would upgrade: bin/$s (+$add/-$del local) — local copy would be backed up first"
        else
          bak="$dst.local-$(date +%Y%m%d%H%M%S)"
          cp "$dst" "$bak"; chmod -x "$bak"   # keep it readable, not runnable by mistake
          cp "$src" "$dst"; chmod +x "$dst"
          echo "Upgraded: bin/$s to the toolkit version. Your copy is kept at $(basename "$bak")."
        fi
        CHANGES=$((CHANGES + 1))
      else
        warn "bin/$s is LOCALLY MODIFIED (+$add lines here / -$del lines only in the template)." \
             "Not overwritten. It may be missing crash-net fixes shipped since." \
             "See what differs:  diff -u $src $dst" \
             "Accept the toolkit version (your copy is backed up):" \
             "  $0 $PROJECT_DIR --upgrade-bin $s"
        if [ ! -x "$dst" ]; then
          warn "  ...and bin/$s is not executable."
        fi
      fi
    fi
  done
  if [ -n "$DRIFTED" ] && [ -z "$UPGRADE_BIN" ]; then
    echo "   (upgrade everything drifted at once with: $0 $PROJECT_DIR --upgrade-bin all)"
  fi
else
  warn "Toolkit has no project-bin/ — cannot check this project's crash net."
fi

echo ""
VERB="updated"; [ "$DRY_RUN" -eq 1 ] && VERB="would be updated"
if [ "$CHANGES" -gt 0 ]; then
  echo "$CHANGES artifact(s) $VERB. Also tell the active session: 'the toolkit changed —"
  echo "re-read README.md and skills/conversion-runbook.md before acting.'"
elif [ "$WARNINGS" -eq 0 ]; then
  echo "All copied artifacts up to date. Referenced skills update via git pull alone —"
  echo "just have the session re-read the runbook if it started before the pull."
fi
# Never close with "up to date" while warnings are on screen — that line is what made a stale
# crash net read as a clean sync.
if [ "$WARNINGS" -gt 0 ]; then
  echo "$WARNINGS warning(s) — this project is NOT fully in sync. Resolve them above."
  [ "$STRICT" -eq 1 ] && exit 3
fi
exit 0
