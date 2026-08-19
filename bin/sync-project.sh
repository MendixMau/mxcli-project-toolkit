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

# THE install manifest — agents and project-bin scripts — lives in ONE file that
# init-project.sh and init-agents.sh read too. It used to be duplicated here, and the
# copies drifted: sync installed review-agent.md + conformance-check.sh + graph-sweep.sh
# and init did not, so a freshly scaffolded project never got them. Add new agents/scripts
# to bin/lib/install-manifest.sh, never to a per-script list.
. "$SCRIPT_DIR/lib/install-manifest.sh"
AGENTS="$MXTK_AGENTS"

# The OTHER thing that was copied into a project and could never be refreshed: the baseline
# skill-routing table inside CLAUDE.local.md. Everything else in this script had at least a
# warning; routing had one too ("add them from README.md"), and a warning nobody can act on
# in one command is how facts-lock.sh reached 1 of 6 projects and agent-roles.md reached 1.
# Now it is rendered from bin/lib/skill-routing.tsv and rewritten IN PLACE between markers.
. "$SCRIPT_DIR/lib/skill-routing.sh"

# Starlark lint rules. Same "missing -> install, drifted -> report, never blind-overwrite"
# contract as the crash net, plus one case the crash net does not have: `mxcli init` can
# silently revert a rule to stock, and the two rules that matter report a clean pass when
# stock. See bin/lib/install-lint-rules.sh for the full classification.
. "$SCRIPT_DIR/lib/install-lint-rules.sh"

# The intake.md template — the same one init-project.sh writes from. This file used to carry
# its own hand-kept copy of Q9 under a comment reading "MUST stay byte-identical to Q9 in
# bin/init-project.sh's intake heredoc". It did not stay identical: init's Q9 was fixed to
# drop the false-green marker and this copy kept it, so --repair-intake would have written a
# passing marker into a question nobody had asked.
. "$SCRIPT_DIR/lib/intake-template.sh"

# Is this agent file an UNTOUCHED stub (safe to overwrite), or completed work?
# Two conditions, both required: it still carries the STUB GENERATED banner AND it still
# has at least one genuinely unfilled {{PLACEHOLDER}}.
#
# {{DOUBLE_BRACE}} is EXCLUDED, and the exclusion is load-bearing. Every agent template
# carries "If any {{DOUBLE_BRACE}} placeholder remains in this file, refuse to proceed" —
# that token is PROSE standing in for "double brace", not an unfilled slot, and it survives
# completion by design. Without the strip, a fully completed 8 KB agent still matched
# `{{[A-Z_]*[^}]*}}`, was judged a pure stub, and was overwritten with the 4.6 KB template.
# Measured: this would have destroyed ~33 KB of finished agent files in one project.
# bin/gate-check.sh's build-ready placeholder scan already carries the same exclusion.
is_pure_stub() {
  local f="$1"
  grep -q "STUB GENERATED" "$f" || return 1
  sed 's/{{DOUBLE_BRACE}}//g' "$f" | grep -q '{{[A-Z_]*[^}]*}}'
}

DIFF_COMPLETED=0
DRY_RUN=0

# EVERY write in this script must go through one of these. Enforcing --dry-run at each write
# site was tried and failed within a day: sections 1 and 4 honoured it, sections 2, 2b and 2c
# did not, so a run that printed "(--dry-run: nothing will be written)" created 11 agent files
# across 5 real projects. A promise a caller cannot verify is worse than no promise, and a flag
# enforced per-site is one new pass away from lying again.
#
# Usage:  w_to <dst>   — reads stdin, writes the file (truncating)
#         w_app <dst>  — reads stdin, appends
#         w_mkdir <d>  — creates a directory
# Each is a no-op under --dry-run, and each still CONSUMES stdin so pipelines behave identically.
w_to() {
  if [ "$DRY_RUN" -eq 1 ]; then cat >/dev/null; return 0; fi
  cat > "$1"
}
w_app() {
  if [ "$DRY_RUN" -eq 1 ]; then cat >/dev/null; return 0; fi
  cat >> "$1"
}
w_mkdir() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  mkdir -p "$1"
}
STRICT=0
UPGRADE_BIN=""
UPGRADE_LINT=""
REPAIR_INTAKE=0
ADOPT_ROUTING=0
PROJECT_DIR=""
USAGE="Usage: $0 <project-root> [--diff-completed] [--dry-run] [--strict]
                          [--upgrade-bin <script.sh|all>] [--upgrade-lint-rules <rule.star|all>]
                          [--repair-intake] [--adopt-routing]"
while [ $# -gt 0 ]; do
  case "$1" in
    --diff-completed) DIFF_COMPLETED=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --strict)         STRICT=1; shift ;;
    --repair-intake)  REPAIR_INTAKE=1; shift ;;
    --adopt-routing)  ADOPT_ROUTING=1; shift ;;
    --upgrade-bin)
      shift
      [ $# -gt 0 ] || { echo "--upgrade-bin needs a script name or 'all'" >&2; exit 1; }
      UPGRADE_BIN="$1"; shift ;;
    --upgrade-lint-rules)
      shift
      [ $# -gt 0 ] || { echo "--upgrade-lint-rules needs a rule file name or 'all'" >&2; exit 1; }
      UPGRADE_LINT="$1"; shift ;;
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
      echo "  --upgrade-lint-rules X  accept the toolkit version of a LOCALLY MODIFIED"
      echo "                     .claude/lint-rules/ rule (or 'all'), backing the copy up first."
      echo "  --repair-intake    accept the offered repair of a stale, still-verbatim intake"
      echo "                     question (see the OFFER printed by a plain run). Only ever"
      echo "                     rewrites boilerplate nobody has edited."
      echo "  --adopt-routing    accept the offered conversion of a hand-written, UNMARKED"
      echo "                     '## Baseline routing' section in CLAUDE.local.md into the"
      echo "                     generated, marked block. The file is backed up first, and"
      echo "                     everything outside that one section is untouched."
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
    if is_pure_stub "$dst"; then
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
# Prefix every would-be-action line under --dry-run. Without it the run printed "Created: …"
# in the past tense for files it had not created — indistinguishable from a real sync in a log.
DRY=""
[ "$DRY_RUN" -eq 1 ] && { DRY="[dry-run] would be — "; echo "(--dry-run: nothing will be written)"; }
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
#
# MUST stay byte-identical to Q9 in bin/init-project.sh's intake heredoc. It used to open with
# "Unverified — how to verify: ...", which gate-check ACCEPTS as an answer — so --repair-intake
# would have written a passing marker into a question nobody had asked, and appending a missing
# Q9 (below) shipped the same false-green. See the long comment in init-project.sh.
q9_current_text() {
  mxtk_intake_question_section 'Interview mode: attended (default) or unattended?'
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

    # Q9 stopped carrying a marker on purpose: the CURRENT template is unanswered by design, so
    # that a generated scaffold cannot pass Stage P. Recognise that case first and say nothing
    # alarming — it is the expected state of a project whose interview has not happened yet.
    # Without this branch every freshly-scaffolded project drew the "text has been edited, NOT
    # touching it" warning below, which is both false and --strict-failing.
    q9_current_text > "$Q9_REF"
    if cmp -s "$Q9_TMP" "$Q9_REF"; then
      echo "Note: $INTAKE Q9 is the current template, still unanswered — Stage P will FAIL until"
      echo "      the kickoff interview happens. That is correct; nothing to repair."

    elif q9_stale_scaffold_text > "$Q9_REF"; cmp -s "$Q9_TMP" "$Q9_REF"; then
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

  # --- questions the CURRENT template asks that this intake never did ---------------------
  #
  # The kickoff set was rewritten on 2026-08-19: four of the nine questions were things the
  # agent could derive for itself (which source folder, which Mendix version, fresh-or-
  # continuation, stray documents), and the ones that actually decide how the pipeline runs —
  # the ENTRY MODE above all — were asked nowhere gate-check could see. Projects scaffolded
  # before that keep the old nine, so a migration and a greenfield build sit in the same
  # workspace having answered different questions, and nothing says so.
  #
  # WHY THIS REPORTS RATHER THAN ACTS. Appending an unanswered question flips Stage P from
  # PASS to FAIL. That is HONEST — the project genuinely never answered it — but a sync is
  # something people run after every toolkit `git pull`, and having that silently fail the
  # kickoff gate of a project at Stage 4 is the kind of surprise that gets a tool routed
  # around instead of fixed. So it follows the same contract as every other drift this script
  # finds: say what is missing, print the exact command to accept it, change nothing.
  #
  # Matching is on the question TEXT, not its number. "Are there licence/security constraints
  # on storing this client's source in this workspace?" was Q2 and is now Q6, word for word; a
  # number-sensitive comparison would call it missing and append a duplicate of a question the
  # user has already answered.
  #
  # Appended questions continue from the highest number present — they do NOT renumber, and in
  # particular Q9 does not move. "## 9." is the hardcoded locator for the interview-mode
  # question in gate-check.sh, in this script, and in four places across tests/wave2/; a
  # repaired old project ends up numbered 1-9 then 10+, which is untidy and correct, in that
  # order of priority.
  MISSING_Q=""
  MISSING_N=0
  while IFS= read -r _q; do
    [ -n "$_q" ] || continue
    if ! sed -n 's/^## [0-9][0-9]*\. //p' "$INTAKE" | grep -Fxq "$_q"; then
      MISSING_Q="$MISSING_Q$_q
"
      MISSING_N=$((MISSING_N + 1))
    fi
  done <<MXTK_Q_EOF
$(mxtk_intake_question_texts)
MXTK_Q_EOF

  if [ "$MISSING_N" -gt 0 ]; then
    if [ "$REPAIR_INTAKE" -eq 1 ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "Would update: $INTAKE — append $MISSING_N question(s) from the current template."
      else
        _next=$(sed -n 's/^## \([0-9][0-9]*\)\..*/\1/p' "$INTAKE" | sort -n | tail -1)
        [ -n "$_next" ] || _next=0
        while IFS= read -r _q; do
          [ -n "$_q" ] || continue
          _next=$((_next + 1))
          printf '\n' >> "$INTAKE"
          mxtk_intake_question_section "$_q" \
            | sed "1s/^## [0-9][0-9]*\. /## $_next. /" >> "$INTAKE"
          printf '\n' >> "$INTAKE"
        done <<MXTK_APPEND_EOF
$MISSING_Q
MXTK_APPEND_EOF
        echo "Updated: $INTAKE — appended $MISSING_N question(s) from the current template,"
        echo "         numbered from $((_next - MISSING_N + 1)). Existing answers untouched."
        echo "         Stage P now FAILS until these are answered. That is the point: they were"
        echo "         never asked, and until today nothing in the gate could tell."
      fi
    else
      echo "Note: $INTAKE predates the current kickoff question set — $MISSING_N question(s)"
      echo "      the template now asks were never asked here:"
      printf '%s' "$MISSING_Q" | sed 's/^/        - /'
      echo "      Your existing answers are fine and would not be touched. Appending these will"
      echo "      make Stage P FAIL until they are answered — honest, but it is your call:"
      echo "         $0 $PROJECT_DIR --repair-intake"
    fi
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
      sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" | w_to "$dst"
      echo "${DRY:-}Created: .claude/agents/$a (new since this project was scaffolded)"
      CHANGES=$((CHANGES + 1))
    elif is_pure_stub "$dst"; then
      # Pure stub, never completed — safe to refresh with the current template.
      if ! sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" | cmp -s - "$dst"; then
        sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" | w_to "$dst"
        echo "${DRY:-}Refreshed: .claude/agents/$a (was an untouched stub; template has changed)"
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
  w_app "$CL" <<EOF

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
  printf '\nToolkit commit: (set at session start — see CLAUDE.local.md ritual)\n' | w_app "$PROJECT_DIR/PROJECT.md"
  echo "Updated: PROJECT.md — added the Toolkit commit acknowledgement line."
  CHANGES=$((CHANGES + 1))
fi

# --- 2c. CLAUDE.local.md: append the Wiring block if this project predates it -----------
# Agents resolve all paths from this block; a project scaffolded before it has none.
if [ -f "$CL" ] && ! grep -q "## Wiring" "$CL"; then
  MPR_NAME="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1 | xargs -r basename || echo "<name>.mpr")"
  w_app "$CL" <<EOF

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
# --- 2d. CLAUDE.local.md: rewrite the baseline routing block from the one routing table ----
#
# This is the seventh copy — the one inside each project, which no script could update. The
# previous code here could only WARN ("add them from README.md 'Baseline routing'"), and a
# warning that costs a human a manual merge is a warning that gets ignored: measured across
# the six wired projects on this machine on 2026-08-18, bin/facts-lock.sh was routed in 1,
# agent-roles.md in 1, source-triage.md in 1, and 17 of 43 skills in none.
#
# Only the marked block is touched. A project's CLAUDE.local.md carries hand-written wiring —
# real paths, local conventions, the session ritual — and all of it is copied byte-for-byte.
# Three cases, and the third refuses rather than guesses:
#   markers present            -> rewrite between them (idempotent; no-op when already current)
#   no markers, no such heading-> append the section, markers included
#   no markers, but a hand-written "## Baseline routing" heading exists -> REFUSE and offer
#                                 --adopt-routing, which backs the file up first. Appending a
#                                 second table would leave two disagreeing tables in the file
#                                 an agent reads first, which is worse than the drift.
if [ -f "$CL" ]; then
  if [ "$ADOPT_ROUTING" -eq 1 ] && ! grep -q 'ROUTING:BEGIN[[:space:]]\{1,\}baseline' "$CL" \
     && grep -q '^##.*[Bb]aseline routing' "$CL"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "Would adopt: CLAUDE.local.md '## Baseline routing' section -> generated marked block."
    else
      RBAK="$(routing_adopt_claude_local "$CL" "$TOOLKIT_ROOT")"
      echo "Adopted: CLAUDE.local.md baseline routing is now generated from the routing table."
      echo "         Your previous file is kept at $(basename "$RBAK")."
    fi
    CHANGES=$((CHANGES + 1))
  else
    RRC=0; routing_sync_claude_local "$CL" "$TOOLKIT_ROOT" "$DRY_RUN" || RRC=$?
    case "$RRC" in
      0)  : ;;  # already current
      10) echo "${DRY:-}Updated: CLAUDE.local.md baseline routing block (rendered from bin/lib/skill-routing.tsv)."
          CHANGES=$((CHANGES + 1)) ;;
      11) echo "${DRY:-}Added: CLAUDE.local.md baseline routing block — this project predates it."
          CHANGES=$((CHANGES + 1)) ;;
      12) warn "CLAUDE.local.md has a hand-written '## Baseline routing' section with no" \
               "<!-- ROUTING:BEGIN baseline --> markers, so sync cannot refresh it and will not" \
               "append a second, disagreeing table. Convert it (your file is backed up first):" \
               "  $0 $PROJECT_DIR --adopt-routing" \
               "Everything outside that one section is left byte-for-byte alone." ;;
      *)  warn "could not sync CLAUDE.local.md's routing block (routing_sync_claude_local -> $RRC)." ;;
    esac
  fi
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
# The list comes from bin/lib/install-manifest.sh (sourced at the top), the same one
# init-project.sh copies from. Beyond the crash net it also carries the two read-only
# review instruments (conformance-check.sh, graph-sweep.sh) that review-agent.md depends
# on — not crash-net per se, but "missing -> install, drifted -> report, never
# blind-overwrite" applies identically to a project's tuned copy of either.
CRASHNET_FILES="$MXTK_PROJECT_BIN"
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

# ── Starlark lint rules ──────────────────────────────────────────────────────────────────
# Gated on WIRED for the same reason as the crash net: a mistyped path must not scatter
# .star files into an unrelated directory. Unlike the crash net this is also a REPAIR path,
# not only a first install — `mxcli init` reverts these rules on its own, so re-running sync
# is the documented way to get a project's lint back after anyone re-inits it.
if [ "$WIRED" -eq 1 ]; then
  mxtk_install_lint_rules "$(cd "$SCRIPT_DIR/.." && pwd)" "$PROJECT_DIR" "$DRY_RUN" "$UPGRADE_LINT"
  CHANGES=$((CHANGES + ${MXTK_LINT_CHANGES:-0}))
fi

# ── Agent entry points ───────────────────────────────────────────────────────────────────
# Same story as the lint rules directly above, for the same reason: `mxcli init` regenerates
# AGENTS.md, CLAUDE.md and the per-tool pointer files, dropping the block that routes an agent
# to RESUME.md. Without this call the wiring only ever reached projects created AFTER it
# existed — and the projects most likely to be opened in Copilot or Cursor are the ones already
# in flight, not the ones scaffolded today. WMS-Demo-main sat unwired for exactly that reason.
#
# Safe by construction, matching this script's contract: wire-agents.sh preserves every file
# that already exists, backs up to .mxtk-backup/, and reports what it suppressed rather than
# adopting it. It is a no-op on a project that is already wired.
#
# Gated on WIRED like the two blocks above, so a mistyped path cannot scatter tool config into
# an unrelated directory.
if [ "$WIRED" -eq 1 ] && [ -x "$SCRIPT_DIR/wire-agents.sh" ]; then
  WA_ARGS=""
  [ "$DRY_RUN" -eq 1 ] && WA_ARGS="--dry-run"
  if ! "$SCRIPT_DIR/wire-agents.sh" "$PROJECT_DIR" $WA_ARGS; then
    warn "Agent wiring did not complete. Everything else in this sync stands; re-run:"
    warn "  $SCRIPT_DIR/wire-agents.sh $PROJECT_DIR"
  fi
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
