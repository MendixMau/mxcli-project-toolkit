#!/bin/bash
# appcommit.sh: commit a HAND change in the app repo with the change-ledger trailers (trust.md section 3).
#
#   appcommit.sh [--app DIR] --by agent|person --kind KIND --rule RULE --why "text" [--step S-n [--work DIR]] -- <path> [<path> ...]
#
# Every change in the app repo is labelled: Changed-By: agent|person and Upgrade-Change: KIND RULE, so bin/changelog.py can
# tell the toolkit's commits from the agent's and the person's, and CHANGES.md carries the reason. A commit without the
# trailers is listed there as "unlabelled".
#   KIND: module-update, convert, repair, replay, theme, data, config      RULE: the repair row or decision id, e.g. repair-row-22, decision P-3
#   --why  becomes the commit subject, so it must say what and why in one line
#   --step S-n  the step this change does (steps.jsonl of the run; a P-n alias is accepted and written as its S-n). Adds the trailer
#          `Upgrade-Step: S-n`, which bin/changelog.py reads and hands to `steps.py done`. An id that is not in the run's steps is refused
#          (exit 2). --work DIR is the run's work folder (default $UPG_STEPS_WORK); UPG_STEP is the default for --step.
#   paths  EXPLICIT only (git commit -- <paths>): a missing path list is refused (exit 2), and so are `-A`, `--all`, `.`, and a path
#          outside the repo. Nothing else in the index or the tree is committed.
# Exit: 0 committed (or nothing changed in the paths: says so), 2 refused or input error.
set -u
die() { echo "appcommit: $*" >&2; exit 2; }
app=.; by=""; kind=""; rule=""; why=""; paths=(); step=${UPG_STEP:-}; work=${UPG_STEPS_WORK:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --app) [ $# -ge 2 ] || die "--app needs a folder"; app=$2; shift 2;;
    --by) [ $# -ge 2 ] || die "--by needs agent or person"; by=$2; shift 2;;
    --kind) [ $# -ge 2 ] || die "--kind needs a kind"; kind=$2; shift 2;;
    --rule) [ $# -ge 2 ] || die "--rule needs a rule id"; rule=$2; shift 2;;
    --why) [ $# -ge 2 ] || die "--why needs a text"; why=$2; shift 2;;
    --step) [ $# -ge 2 ] || die "--step needs a step id (S-n)"; step=$2; shift 2;;
    --work) [ $# -ge 2 ] || die "--work needs the run's work folder"; work=$2; shift 2;;
    -A|--all|-a) die "refused: $1 commits more than the paths you name; list the files after --";;
    --) shift; paths=("$@"); break;;
    -h|--help) awk 'NR>1{if(!/^#/)exit; print}' "$0"; exit 0;;
    *) die "unknown argument '$1' (paths go after --)";;
  esac
done
case $by in agent|person) ;; *) die "--by agent|person (the toolkit's own commits are made by its scripts)";; esac
case $kind in module-update|convert|repair|replay|theme|data|config) ;; *) die "--kind: module-update, convert, repair, replay, theme, data or config";; esac
[ -n "$rule" ] || die "--rule is required (e.g. repair-row-22, decision P-3)"
[ -n "$why" ] || die "--why is required (the reason, one line)"
case $why$rule in *$'\n'*) die "--why and --rule are one line each";; esac
[ ${#paths[@]} -gt 0 ] || die "refused: no paths after -- (explicit paths only, never the whole tree)"
for p in "${paths[@]}"; do
  case $p in ''|.|./|/|-*|*'*'*) die "refused: path '$p' (name the files; no ., globs or options)";; esac
done
trailers=$(printf 'Changed-By: %s\nUpgrade-Change: %s %s' "$by" "$kind" "$rule")
if [ -n "$step" ]; then
  [ -n "$work" ] || die "--step needs the run's work folder: --work DIR (or UPG_STEPS_WORK), so the id can be checked"
  sid=$(python3 "$(dirname "$0")/steps.py" find --work "$work" --id "$step" 2> /dev/null) || die "unknown step '$step' in $work (steps.py show lists the ids); open it first, steps/decide.md"
  trailers=$(printf '%s\nUpgrade-Step: %s' "$trailers" "$sid")
fi
git -C "$app" rev-parse --git-dir > /dev/null 2>&1 || die "$app is not a git repository"
top=$(git -C "$app" rev-parse --show-toplevel)
for p in "${paths[@]}"; do
  case $p in /*) full=$p;; *) full=$(cd "$app" && pwd -P)/$p;; esac
  case $full in "$top"/*) ;; *) die "refused: $p is outside the repository $top";; esac
done
git -C "$app" add -- "${paths[@]}" || die "git add failed"
git -C "$app" diff --cached --quiet -- "${paths[@]}" && { echo "appcommit: nothing changed in the given paths; no commit"; exit 0; }
git -C "$app" -c "user.name=${GIT_AUTHOR_NAME:-$by}" -c "user.email=${GIT_AUTHOR_EMAIL:-$by@localhost}" \
  commit -q -m "$why" -m "$trailers" -- "${paths[@]}" || die "git commit failed"
echo "appcommit: committed $(git -C "$app" rev-parse --short HEAD) ($by, $kind $rule${sid:+, step $sid}): $why"
