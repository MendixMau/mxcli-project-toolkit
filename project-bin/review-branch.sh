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
# Exit: 0 approve|comments, pack only, or nothing beyond the base · 3 changes · 1 no valid
# review, or the run changed its checkout · 2 usage, or no base / head / merge base.
#
# Base: --base, else origin's default branch (refs/remotes/origin/HEAD), else origin/main,
# origin/master, main, master. The change is merge-base(base, head)..head, so what landed on the
# base meanwhile is not this change's.
#
# --run reviews in a throwaway detached worktree at <head> (git worktree add, removed after), so
# it can run in the background while the builder keeps committing, and the reviewer sees the
# head's model, not whatever the working copy holds. It starts `claude -p` there (CLAUDE_BIN
# overrides) in --permission-mode default with Edit/Write disallowed and Bash limited to git
# diff/log/show and mxcli describe/show/check. A wrapper that adds --dangerously-skip-permissions
# lifts that allow-list; the backstop holds either way: that worktree's HEAD and model (.mpr and
# mprcontents/, status plus a content hash) are compared before and after, and a run that changed
# them is refused (exit 1), its output kept as REVIEW.rejected.md and the evidence in guard.txt.
#
# Inputs, and which step produces them: the branch's commits (the build loop); the evidence the
# reviewer looks for (gate logs, test and journey results) comes from exec.sh, verify-module.sh
# and affected-tests.sh runs of Stages 5-6. Missing evidence is reported, never guessed, and
# never a request for more tests. The standard: skills/review-checklists.md in the toolkit (find_toolkit_root), plus the
# company brain's ROUTING.md when the project carries a COMPANY-BRAIN block (wire-company-brain.sh).
#
# WHY (2026-11-24). Reviewers of agent-built Mendix branches had two routes, both by hand: Studio
# Pro's Changes pane after `git reset --soft` onto the base, or reading mxcli diff-local output.
# Neither says whether the change works or follows the team's review standard. cc-agent-harness
# (Emre Özhan Yigitbasi) showed the missing step in CI: a read-only review run against checklists
# drawn from real review remarks, with a verdict on the MR. This is that step for any project,
# local or CI. Field run: a Mendix 11.15 app, 8 commits (1 new, 4 modified units): pack 2.1 s,
# lean diff 36 of 46 lines; --run 144 s, 17 turns, $0.61, in a throwaway worktree.
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

BASE="" HEAD_REF="HEAD" OUT="" FOCUS="" RUN="" MODEL="" MAX_TURNS=40
while [ $# -gt 0 ]; do
  case $1 in
    --check-review) [ $# -ge 2 ] || usage; check_review "$2"; exit $? ;;
    --base|--head|--out|--focus|--model|--max-turns)
      [ -n "${2:-}" ] || { echo "review-branch: $1 needs a value" >&2; usage; }
      case $1 in
        --base) BASE=$2 ;; --head) HEAD_REF=$2 ;; --out) OUT=$2 ;;
        --focus) FOCUS=$2 ;; --model) MODEL=$2 ;; --max-turns) MAX_TURNS=$2 ;;
      esac
      shift ;;
    --run) RUN=1 ;;
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
EVIDENCE=$(grep -iE '(^|[/_.-])(tests?|e2e|journeys?|gates?|evidence|screenshots?|ui-review)([/_.-]|$)|\.png$' "$OUT/.files" \
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
# --run: the reviewer's own checkout, a detached worktree at the head (see the header).
RUN_ROOT=$PROJECT_ROOT; WT=""
if [ -n "$RUN" ]; then
  WT=$(mktemp -d "${TMPDIR:-/tmp}/review-wt.XXXXXX") && rmdir "$WT" \
    && git -C "$REPO" worktree add -q --detach "$WT" "$HEAD_SHA" >/dev/null 2>&1 \
    || { echo "review-branch: could not create a review worktree at $HEAD_SHA" >&2; exit 1; }
  trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1' EXIT
  PR_P=$(cd "$PROJECT_ROOT" && pwd -P); PR_REL=${PR_P#"$REPO_P"}; PR_REL=${PR_REL#/}
  RUN_ROOT=$WT${PR_REL:+/$PR_REL}
  [ -n "$MX" ] && [ -x "$MX" ] && ln -s "$MX" "$RUN_ROOT/mxcli.review" 2>/dev/null
fi
MXR=mxcli; [ -n "$WT" ] && MXR=./mxcli.review
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

The change: \`$BRANCH\` (\`$HEAD_SHA\`) against \`$BASE\`, merge base \`$MB\`. Project: \`$RUN_ROOT\`
(checked out at the head), model \`${MPR_REL#"${PR_REL:-}"/}\`. Pack: \`$OUT/\`: read PACK.md, then $DIFF_FILE (model-diff.mdl has the layout lines
too), then other.diff. For context on any changed document, describe it on both sides
(\`git show <rev>:<path>\`, \`$MXR -p <model> -c "describe ..."\`, \`$MXR check <model>\`). The change is ALL
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

VERDICT: approve = no findings, or nits only; comments = at least one minor, nothing above;
changes = any blocker or major. "None." under Findings when
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
# The worktree is thrown away, so only the model matters: mxcli re-syncs its own files there
# (.ai-context/, .claude/skills, vendorlib/; field run 2026-11-24, 116 files) and that is harmless.
MODEL_SPEC="${MPR_DIR_REL:+$MPR_DIR_REL/}mprcontents"
state() {
  git -C "$WT" rev-parse HEAD
  git -C "$WT" status --porcelain --untracked-files=no -- "$MPR_REL" "$MODEL_SPEC"
  git -C "$WT" diff --binary HEAD -- "$MPR_REL" "$MODEL_SPEC" | cksum
}
BEFORE=$(state)
rm -f "$OUT/REVIEW.md" "$OUT/REVIEW.rejected.md" "$OUT/run.json"
T0=$(date +%s)
(cd "$RUN_ROOT" && "$CLAUDE" -p "$(cat "$OUT/PROMPT.md")" --output-format json \
  --permission-mode default --max-turns "$MAX_TURNS" ${MODEL:+--model "$MODEL"} \
  --add-dir "$OUT" ${TK:+--add-dir "$TK"} \
  --allowedTools Read Grep Glob "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" \
                 "Bash($MXR -p * -c describe*)" "Bash($MXR -p * -c \"describe*)" \
                 "Bash($MXR -p * -c DESCRIBE*)" "Bash($MXR -p * -c \"DESCRIBE*)" \
                 "Bash($MXR -p * -c show*)" "Bash($MXR -p * -c \"show*)" \
                 "Bash($MXR -p * -c SHOW*)" "Bash($MXR -p * -c \"SHOW*)" "Bash($MXR check*)" \
                 "Bash($MXR help*)" "Bash(grep:*)" "Bash(head:*)" "Bash(wc:*)" \
  --disallowedTools Edit Write NotebookEdit "Bash(git diff --output*)" "Bash(git log --output*)" \
                    "Bash(git show --output*)" < /dev/null) > "$OUT/run.json" 2> "$OUT/run.err"
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
AFTER=$(state)
if [ "$AFTER" != "$BEFORE" ]; then
  [ -f "$OUT/REVIEW.md" ] && mv "$OUT/REVIEW.md" "$OUT/REVIEW.rejected.md"
  { echo "before:"; echo "$BEFORE"; echo "after:"; echo "$AFTER"
    echo "changed:"; git -C "$WT" diff --stat HEAD -- "$MPR_REL" "$MODEL_SPEC" 2>&1 | tail -20; } > "$OUT/guard.txt"
  echo "review-branch: the review run changed the model (HEAD, the .mpr or mprcontents/); its output is refused, see guard.txt" >&2
  exit 1
fi
check_review "$OUT/REVIEW.md"; rc=$?
[ $rc -eq 1 ] || echo "review    $OUT/REVIEW.md"
exit $rc
