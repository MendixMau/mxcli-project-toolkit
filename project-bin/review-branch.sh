#!/usr/bin/env bash
# review-branch.sh — review pack for a branch, and (with --run) a read-only agent review of it.
#
#   ./bin/review-branch.sh [--base REF] [--head REF] [--out DIR] [--focus TEXT]
#                          [--run] [--model M] [--max-turns N]
#   ./bin/review-branch.sh --check-review FILE
#
# Writes docs/review/<branch>-<head>/ (or --out):
#   PACK.md              base, merge base, commits, model change counts, evidence found, standard
#   model-diff.mdl       mxcli diff-local over <merge-base>..<head>: every changed unit as MDL
#   model-diff.lean.mdl  the same without layout-only lines (@position / @curve moves)
#   other.diff           non-model files (docs/review/ excluded)
#   PROMPT.md            the reviewer's instructions
#   REVIEW.md            with --run: the verdict and findings (format: skills/change-review.md)
# Exit: 0 approve|comments (or pack only) · 3 changes · 1 no valid review, or the run touched the
# checkout · 2 usage / nothing to review against.
#
# Base: --base, else origin's default branch (refs/remotes/origin/HEAD), else origin/main,
# origin/master, main, master. The change is merge-base(base, head)..head, so what landed on the
# base meanwhile is not this change's.
#
# --run starts `claude -p` (CLAUDE_BIN overrides, e.g. a launcher wrapper) in the project with Edit/Write disallowed and Bash limited to git
# diff/log/show and mxcli; mxcli itself can still write, so the checkout (status + HEAD) is
# compared before and after (mxcli's own .ai-context/ sync excluded), and a run that moved it is refused (exit 1), its output kept as
# REVIEW.rejected.md.
#
# Inputs, and which step produces them: the branch's commits (the build loop); the evidence the
# reviewer looks for (gate logs, test and journey results) comes from exec.sh, verify-module.sh
# and affected-tests.sh runs of Stages 5-6. Missing evidence is reported as a finding, not
# guessed. The standard: skills/review-checklists.md in the toolkit (find_toolkit_root), plus the
# company brain's ROUTING.md when the project carries a COMPANY-BRAIN block (wire-company-brain.sh).
#
# WHY (2026-11-24). Reviewers of agent-built Mendix branches had two routes, both by hand: Studio
# Pro's Changes pane after `git reset --soft` onto the base, or reading mxcli diff-local output.
# Neither says whether the change works or follows the team's review standard. cc-agent-harness
# (Emre Özhan Yigitbasi) showed the missing step in CI: a read-only review run against checklists
# drawn from real review remarks, with a verdict on the MR. This is that step for any project,
# local or CI. Field run: a Mendix 11.15 app, 357 commits, range c2bde7b..b578ffb (4 modified, 1
# deleted unit): diff-local 1.6 s, the lean diff dropped the @position churn.
#
# Bash 3.2 compatible (stock macOS): no mapfile, no associative arrays.

. "$(dirname "$0")/_common.sh"

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# --check-review FILE: the format contract of REVIEW.md. Prints the verdict; rc 0/3, or 1.
check_review() {
  local f=$1 v s missing=""
  [ -s "$f" ] || { echo "review-branch: no review at $f" >&2; return 1; }
  v=$(awk 'NF{print; exit}' "$f" | sed -nE 's/^[[:space:]]*VERDICT:[[:space:]]*(approve|comments|changes)[[:space:]]*$/\1/p')
  [ -n "$v" ] || { echo "review-branch: first line of $f is not 'VERDICT: approve|comments|changes'" >&2; return 1; }
  for s in "Summary" "Findings" "Evidence" "Standard applied" "Not checked"; do
    grep -q "^## $s" "$f" || missing="$missing, $s"
  done
  [ -z "$missing" ] || { echo "review-branch: $f lacks section(s): ${missing#, }" >&2; return 1; }
  echo "verdict   $v"
  [ "$v" = changes ] && return 3
  return 0
}

BASE="" HEAD_REF="HEAD" OUT="" FOCUS="" RUN="" MODEL="" MAX_TURNS=25
while [ $# -gt 0 ]; do
  case $1 in
    --check-review) [ $# -ge 2 ] || usage; check_review "$2"; exit $? ;;
    --base) BASE=${2:-}; shift ;;
    --head) HEAD_REF=${2:-}; shift ;;
    --out) OUT=${2:-}; shift ;;
    --focus) FOCUS=${2:-}; shift ;;
    --run) RUN=1 ;;
    --model) MODEL=${2:-}; shift ;;
    --max-turns) MAX_TURNS=${2:-25}; shift ;;
    -h|--help) usage ;;
    *) echo "review-branch: unknown argument $1" >&2; usage ;;
  esac
  shift
done

REPO=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null) \
  || { echo "review-branch: $PROJECT_ROOT is not in a git repository" >&2; exit 2; }
MPR=$(find_mpr) || exit 2
MPR_DIR_REL=$(cd "$(dirname "$MPR")" && pwd -P); REPO_P=$(cd "$REPO" && pwd -P)
MPR_DIR_REL=${MPR_DIR_REL#"$REPO_P"}; MPR_DIR_REL=${MPR_DIR_REL#/}
MPR_REL=${MPR_DIR_REL:+$MPR_DIR_REL/}$(basename "$MPR")

if [ -z "$BASE" ]; then
  BASE=$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  for c in origin/main origin/master main master; do
    [ -n "$BASE" ] && break
    git -C "$REPO" rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1 && BASE=$c
  done
fi
[ -n "$BASE" ] || { echo "review-branch: no base branch found; pass --base REF" >&2; exit 2; }
HEAD_SHA=$(git -C "$REPO" rev-parse -q --verify "$HEAD_REF^{commit}" 2>/dev/null) \
  || { echo "review-branch: no commit '$HEAD_REF'" >&2; exit 2; }
MB=$(git -C "$REPO" merge-base "$BASE" "$HEAD_SHA" 2>/dev/null) \
  || { echo "review-branch: '$HEAD_REF' has no merge base with '$BASE'" >&2; exit 2; }
if [ "$MB" = "$HEAD_SHA" ]; then
  echo "review-branch: nothing to review: $HEAD_REF has no commits beyond $BASE"; exit 0
fi

BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref "$HEAD_REF" 2>/dev/null || true)
case $BRANCH in ""|HEAD) BRANCH=$HEAD_REF ;; esac
[ "$BRANCH" = HEAD ] && BRANCH=detached
ID=$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '-')-$(printf '%s' "$HEAD_SHA" | cut -c1-8)
OUT=${OUT:-$PROJECT_ROOT/docs/review/$ID}
mkdir -p "$OUT" || exit 2

# ── the diff ──
MODEL_PATHS=0
git -C "$REPO" diff --name-only "$MB" "$HEAD_SHA" > "$OUT/.files"
while IFS= read -r f; do
  case $f in "${MPR_DIR_REL:+$MPR_DIR_REL/}mprcontents/"*|"$MPR_REL") MODEL_PATHS=$((MODEL_PATHS + 1)) ;; esac
done < "$OUT/.files"
MX="${MXCLI:-$(find_project_mxcli 2>/dev/null || command -v mxcli 2>/dev/null || true)}"
SUMMARY="no model change"
if [ "$MODEL_PATHS" -gt 0 ]; then
  if [ -n "$MX" ] && [ -x "$MX" ]; then
    (cd "$REPO" && "$MX" diff-local -p "$MPR_REL" --ref "$MB..$HEAD_SHA") 2>&1 \
      | grep -v '^WARNING: This is a vibe-coded' > "$OUT/model-diff.mdl"
    SUMMARY=$(sed -nE 's/^Summary: (.*)$/\1/p' "$OUT/model-diff.mdl" | tail -1)
    [ -n "$SUMMARY" ] || SUMMARY="NOT MEASURED (diff-local printed no Summary line; see model-diff.mdl)"
  else
    echo "NOT MEASURED: no mxcli (set MXCLI or put ./mxcli in the project root)" > "$OUT/model-diff.mdl"
    SUMMARY="NOT MEASURED (no mxcli)"
  fi
  grep -vE '^[+-][[:space:]]*@(position|curve)\(' "$OUT/model-diff.mdl" > "$OUT/model-diff.lean.mdl"
fi
git -C "$REPO" diff "$MB" "$HEAD_SHA" -- . \
  ":(exclude)${MPR_DIR_REL:+$MPR_DIR_REL/}mprcontents" ":(exclude)$MPR_REL" \
  ":(exclude)*docs/review/*" > "$OUT/other.diff"
OTHER_N=$(grep -c '^diff --git' "$OUT/other.diff" || true)

# ── evidence the branch carries (changed in range; the reviewer looks for more) ──
EVIDENCE=$(grep -iE '(test|journey|e2e|gate|evidence|ui-review|screenshot|\.png$)' "$OUT/.files" \
  | grep -v 'mprcontents/' | head -40 | sed 's/^/- `/; s/$/`/')
NOTELESS=0; COMMITS=0
for c in $(git -C "$REPO" rev-list "$MB..$HEAD_SHA"); do
  COMMITS=$((COMMITS + 1))
  git -C "$REPO" notes --ref mx_metadata show "$c" >/dev/null 2>&1 || NOTELESS=$((NOTELESS + 1))
done

# ── the standard ──
TK=$(find_toolkit_root 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))
CHECKLISTS="$TK/skills/review-checklists.md"
[ -f "$CHECKLISTS" ] || CHECKLISTS="NOT FOUND (no toolkit root; set MXTK_ROOT)"
BRAIN=""
for f in "$PROJECT_ROOT/CLAUDE.local.md" "$PROJECT_ROOT/CLAUDE.md"; do
  [ -f "$f" ] || continue
  BRAIN=$(awk '/<!-- COMPANY-BRAIN:BEGIN -->/{b=1} /<!-- COMPANY-BRAIN:END -->/{b=0} b' "$f" \
    | grep -oE '`[^`]*ROUTING\.md`' | head -1 | tr -d '`')
  [ -n "$BRAIN" ] && break
done
STANDARD="- \`$CHECKLISTS\`"
[ -n "$BRAIN" ] && STANDARD="- \`$BRAIN\` (company brain: follow every row the change fires)
$STANDARD"

DIFF_FILE="model-diff.lean.mdl"; [ "$MODEL_PATHS" -gt 0 ] || DIFF_FILE="(none: no model change)"
cat > "$OUT/PACK.md" <<EOF
# Review pack — $BRANCH

| | |
|---|---|
| Head | \`$BRANCH\` at \`$(printf '%s' "$HEAD_SHA" | cut -c1-8)\` |
| Base | \`$BASE\`, merge base \`$(printf '%s' "$MB" | cut -c1-8)\` |
| Commits | $COMMITS ($NOTELESS without an mx_metadata note) |
| Model | $SUMMARY ($MODEL_PATHS model files) |
| Other files | $OTHER_N |
| Written | $(date '+%Y-%m-%d %H:%M') |

## Commits
$(git -C "$REPO" log --reverse --format='- `%h` %s' "$MB..$HEAD_SHA" | head -60)

## Evidence files changed on the branch
${EVIDENCE:-_none: no test, journey, gate or screenshot file changed in this range_}

## Standard
$STANDARD
EOF

cat > "$OUT/PROMPT.md" <<EOF
You are reviewing a Mendix change, read-only. Change nothing: no MDL execution, no edits, no
commits, no app start, no builds. Your final message is the review itself and nothing else.

The change: \`$BRANCH\` (\`$HEAD_SHA\`) against \`$BASE\`, merge base \`$MB\`. Project: \`$PROJECT_ROOT\`,
model \`$MPR_REL\`. Pack: \`$OUT/\`: read PACK.md, then $DIFF_FILE (model-diff.mdl has the layout lines
too), then other.diff. For context on any changed document, describe it on both sides
(\`git show <rev>:<path>\`, \`mxcli -p $MPR_REL -c "describe ..."\`, \`mxcli check\`). The change is ALL
$COMMITS commits in $MB..$HEAD_SHA, not the last one alone. Review only this
change; what was already on the base is not its to fix unless the change depends on it or makes it worse.

The standard: read these first, then walk the sections the change touches, and name the section
(C1, S1, ...) or brain row on every finding. Never guess a checklist's content.
$STANDARD

Evidence: note what the build already produced that proves the change works (gate and mx check
output, the affected tests and journeys with their pass counts, screenshots of changed pages) in
the pack, the project's docs/, tests/ and journeys/. Report what is there and what is not. Never
ask for more tests or the full suite; missing evidence alone is not a finding above minor.
${FOCUS:+
The person who asked for this review wants attention on: $FOCUS
}
Write the review in exactly this shape (GitLab/GitHub Markdown):

VERDICT: approve | comments | changes
## Summary
<at most 5 lines: what the change does, and your judgement>
## Findings
1. **<blocker|major|minor|nit>** <title> — \`<Module.Document or file:line>\`
   <what is wrong, why it matters, the fix> (<section>)
## Evidence
<what proves it works, with denominators ("journeys 12/12"); what is missing>
## Standard applied
<each checklist section or brain row that fired>
## Not checked
<what you could not verify here and why; "Nothing." if nothing>

VERDICT: approve = nothing above minor; comments = minor and nits only; changes = any blocker
or major. "None." under Findings when
there are none. No praise, no restating the diff, no findings on toolkit scaffolding or docs/review/.
EOF
rm -f "$OUT/.files"

echo "pack      $OUT"
echo "change    $BRANCH vs $BASE: $COMMITS commits · model: $SUMMARY · other files: $OTHER_N"
[ -n "$RUN" ] || { echo "next      read PACK.md, or add --run for the agent review"; exit 0; }

# ── the agent review ──
CLAUDE=${CLAUDE_BIN:-claude}
command -v "$CLAUDE" >/dev/null 2>&1 || { echo "review-branch: --run needs the claude CLI on PATH (or CLAUDE_BIN)" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "review-branch: --run needs python3" >&2; exit 1; }
state() { git -C "$REPO" rev-parse HEAD; git -C "$REPO" status --porcelain --untracked-files=no | grep -vE 'docs/review/|\.ai-context/'; }
BEFORE=$(state)
T0=$(date +%s)
(cd "$PROJECT_ROOT" && "$CLAUDE" -p "$(cat "$OUT/PROMPT.md")" --output-format json \
  --max-turns "$MAX_TURNS" ${MODEL:+--model "$MODEL"} \
  --allowedTools Read Grep Glob "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" \
                 "Bash(mxcli:*)" "Bash(./mxcli:*)" \
  --disallowedTools Edit Write NotebookEdit < /dev/null) > "$OUT/run.json" 2> "$OUT/run.err"
RC=$?
SECS=$(( $(date +%s) - T0 ))
python3 -I - "$OUT/run.json" "$OUT/REVIEW.md" <<'PY' || true
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
text = (r.get("result") or "").strip()
i = text.find("VERDICT:")
if i > 0:
    text = text[i:]
open(sys.argv[2], "w").write(text + "\n")
print(f"run       {r.get('num_turns')} turns · ${r.get('total_cost_usd', 0):.2f}")
PY
echo "time      ${SECS}s (claude exit $RC)"
if [ "$(state)" != "$BEFORE" ]; then
  [ -f "$OUT/REVIEW.md" ] && mv "$OUT/REVIEW.md" "$OUT/REVIEW.rejected.md"
  echo "review-branch: the review run changed the checkout (HEAD or tracked files); its output is refused" >&2
  exit 1
fi
check_review "$OUT/REVIEW.md"; rc=$?
[ $rc -eq 1 ] || echo "review    $OUT/REVIEW.md"
exit $rc
