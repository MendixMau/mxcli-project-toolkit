#!/usr/bin/env bash
# Fixture for project-bin/review-branch.sh: the review pack, the REVIEW.md contract, and the
# read-only guard of --run.
#
# usage: bash tests/wave2/test-review-branch.sh [/path/to/review-branch.sh]
#
# Golden input is captured, never written: the stub mxcli replays fixtures/review-branch/
# diff-local.txt, the verbatim `mxcli diff-local` output of a field run (names changed only;
# provenance: fixtures/review-branch/CAPTURE.txt). The stub claude prints the JSON envelope
# `claude -p --output-format json` returns (a "result" string plus num_turns/total_cost_usd).
# The git history is project content: it only needs a model file and a non-model file to change.
#
# Both layouts: the model at the root (A-E) and under app/ (F, two-tree).
#
# Positive control: against master (no review-branch.sh) every case but A5 fails. With the lean
# filter's @(position|curve) pattern dropped, A3 fails; with state() widened from the model to
# every tracked file, E3 fails; with the guard removed, E2 fails; without clearing the old REVIEW.md
# before a run, E7 fails.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/review-branch.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/review-branch"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-branch-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"

# Stub mxcli: diff-local replays the capture (with mxcli's banner, which the pack strips).
cat > "$WORK/mxcli" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$WORK/mxcli.args"
case " \$* " in *" diff-local "*) echo "WARNING: This is a vibe-coded tool"; cat "$FX/diff-local.txt" ;; esac
EOF
chmod +x "$WORK/mxcli"

# mkproj DIR SUBDIR: git repo, model under SUBDIR ("" = root); main has one commit, branch feat two.
mkproj() {
  local p=$1 sub=$2 m
  m="$p${sub:+/$sub}"
  mkdir -p "$p/bin" "$m/mprcontents/ab" "$p/docs"
  cp "$TOOLKIT/project-bin/_common.sh" "$p/bin/"; cp "$SUBJECT" "$p/bin/review-branch.sh"
  chmod +x "$p/bin/"*.sh
  printf 'mpr\n' > "$m/App.mpr"; printf 'v1\n' > "$m/mprcontents/ab/unit.mxunit"
  printf 'readme\n' > "$p/README.md"; mkdir -p "$p/.ai-context"; printf 'a\n' > "$p/.ai-context/x.md"
  ( cd "$p" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm base \
    && git checkout -qb feat \
    && printf 'v2\n' > "${sub:+$sub/}mprcontents/ab/unit.mxunit" && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm "change the unit" \
    && printf 'readme 2\n' > README.md && printf 'pass 3/3\n' > docs/affected-tests.log && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm "docs and evidence" )
}
rb() { local p=$1; shift; ( cd "$p" && PROJECT_ROOT="$p" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh "$@" ); }

# ── A: pack, root layout, base resolved without --base ──
P="$WORK/root"; mkproj "$P" ""
out=$(rb "$P" --out "$P/docs/review/t" 2>&1); rc=$?
O="$P/docs/review/t"
[ $rc -eq 0 ] && ok "A1 pack exits 0" || bad "A1 pack exits 0 (rc $rc)" "$out"
grep -q 'vs main: 2 commits' <<<"$out" && ok "A2 base resolves to main, 2 commits" || bad "A2 base resolves to main" "$out"
n=$(wc -l < "$O/model-diff.lean.mdl" | tr -d ' ')
[ "$n" = 36 ] && ! grep -qE '^[+-][[:space:]]*@(position|curve)\(' "$O/model-diff.lean.mdl" \
  && ok "A3 lean diff drops the 10 changed layout lines (36 of 46)" || bad "A3 lean diff 36 lines, no +/- layout lines (got $n)"
grep -qE '^ +@position\(360, 200\)' "$O/model-diff.lean.mdl" && ok "A4 unchanged context layout lines stay" || bad "A4 context layout lines stay"
grep -q 'vibe-coded' "$O/model-diff.mdl" && bad "A5 mxcli banner stripped" || ok "A5 mxcli banner stripped"
grep -q '| Model | 1 new, 4 modified, 0 deleted (1 model files) |' "$O/PACK.md" && ok "A6 PACK.md carries diff-local's Summary" \
  || bad "A6 PACK.md Summary row" "$(grep '| Model' "$O/PACK.md")"
grep -q 'README.md' "$O/other.diff" && ! grep -q 'mprcontents' "$O/other.diff" \
  && ok "A7 other.diff: non-model files only" || bad "A7 other.diff: non-model files only"
grep -q '`docs/affected-tests.log`' "$O/PACK.md" && ok "A8 evidence file listed" || bad "A8 evidence file listed"
grep -q 'review-checklists.md' "$O/PROMPT.md" && grep -q 'Never' "$O/PROMPT.md" && grep -q 'ALL' "$O/PROMPT.md" \
  && ok "A9 prompt: standard, no-new-tests rule, whole range" || bad "A9 prompt contents"

# ── B: nothing beyond the base ──
out=$(rb "$P" --head main 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q 'nothing to review' <<<"$out" && ok "B1 head = base: 'nothing to review', rc 0" || bad "B1 nothing to review" "$out"

# ── C: no mxcli → NOT MEASURED, never a silent empty diff ──
out=$( cd "$P" && PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/none" PATH=/usr/bin:/bin ./bin/review-branch.sh --out "$WORK/c" 2>&1 )
grep -q 'NOT MEASURED' "$WORK/c/model-diff.mdl" && grep -q 'NOT MEASURED' "$WORK/c/PACK.md" \
  && ok "C1 no mxcli: NOT MEASURED in diff and PACK" || bad "C1 no mxcli: NOT MEASURED" "$out"

# ── D: the REVIEW.md contract ──
sec='## Summary\nx\n## Findings\nNone.\n## Evidence\nx\n## Standard applied\nC\n## Not checked\nNothing.\n'
printf "VERDICT: comments\n$sec" > "$WORK/r1"; printf "VERDICT: changes\n$sec" > "$WORK/r2"
printf 'VERDICT: approve\n## Summary\n' > "$WORK/r3"; printf "Looks good\n$sec" > "$WORK/r4"
rb "$P" --check-review "$WORK/r1" >/dev/null 2>&1; [ $? -eq 0 ] && ok "D1 comments → 0" || bad "D1 comments → 0"
rb "$P" --check-review "$WORK/r2" >/dev/null 2>&1; [ $? -eq 3 ] && ok "D2 changes → 3" || bad "D2 changes → 3"
rb "$P" --check-review "$WORK/r3" >/dev/null 2>&1; [ $? -eq 1 ] && ok "D3 missing sections → 1" || bad "D3 missing sections → 1"
rb "$P" --check-review "$WORK/r4" >/dev/null 2>&1; [ $? -eq 1 ] && ok "D4 no verdict line → 1" || bad "D4 no verdict line → 1"

# ── E: --run through a stub claude ──
# stubclaude NAME ACTION: prints a valid review envelope after running ACTION in the project.
stubclaude() {
  cat > "$WORK/$1" <<EOF
#!/usr/bin/env bash
$2
printf '%s\n' "\$@" > "$WORK/\$(basename "\$0").args"
python3 -c 'import json,sys; print(json.dumps({"result":"Here is the review.\\n\\n"+open(sys.argv[1]).read(),"num_turns":3,"total_cost_usd":0.01}))' "$WORK/r1"
EOF
  chmod +x "$WORK/$1"
}
stubclaude ok-claude ':'
stubclaude dirty-claude 'echo touched >> mprcontents/ab/unit.mxunit'
stubclaude sync-claude 'echo synced >> .ai-context/x.md; echo synced >> README.md'
stubclaude busy-claude "git -C '$P' -c user.email=t@t -c user.name=t commit -q --allow-empty -m 'next CR'"
cat > "$WORK/broken-claude" <<'EOF'
#!/usr/bin/env bash
echo "not json"
EOF
chmod +x "$WORK/broken-claude"
out=$(cd "$P" && CLAUDE_BIN="$WORK/ok-claude" PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh --run --out "$WORK/e1" 2>&1); rc=$?
[ $rc -eq 0 ] && head -1 "$WORK/e1/REVIEW.md" | grep -q '^VERDICT: comments' \
  && ok "E1 --run: REVIEW.md starts at the verdict, rc 0" || bad "E1 --run" "$out"
out=$(cd "$P" && CLAUDE_BIN="$WORK/dirty-claude" PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh --run --out "$WORK/e2" 2>&1); rc=$?
[ $rc -eq 1 ] && [ -f "$WORK/e2/REVIEW.rejected.md" ] && [ ! -f "$WORK/e2/REVIEW.md" ] && grep -q unit.mxunit "$WORK/e2/guard.txt" \
  && ok "E2 a run that edits the model is refused (rc 1, REVIEW.rejected.md, guard.txt)" || bad "E2 guard (rc $rc)" "$out"
out=$(cd "$P" && CLAUDE_BIN="$WORK/sync-claude" PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh --run --out "$WORK/e3" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "E3 tool-file syncs in the review worktree (.ai-context, non-model files) do not trip the guard" || bad "E3 .ai-context excluded (rc $rc)" "$out"

[ "$(git -C "$P" worktree list | wc -l | tr -d ' ')" = 1 ] && [ -z "$(git -C "$P" status --porcelain --untracked-files=no)" ] \
  && ok "E4 the review worktree is removed and the project checkout untouched" || bad "E4 worktree cleanup" "$(git -C "$P" worktree list)"
a="$WORK/ok-claude.args"
grep -qx -- '--permission-mode' "$a" && grep -qx default "$a" && grep -qx Edit "$a" && grep -qx -- '--add-dir' "$a" \
  && grep -qx "$WORK/e1" "$a" && grep -qx 'Bash(git diff --output\*)' "$a" && ! grep -qx 'Bash(mxcli:\*)' "$a" \
  && ok "E5 claude args: permission-mode default, Edit off, pack dir added, no blanket mxcli" || bad "E5 claude args" "$(cat "$a")"
out=$(cd "$P" && CLAUDE_BIN="$WORK/busy-claude" PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh --run --out "$WORK/e6" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "E6 the builder committing during a background run does not void it" || bad "E6 background run (rc $rc)" "$out"
git -C "$P" reset -q --hard HEAD~1
out=$(cd "$P" && CLAUDE_BIN="$WORK/broken-claude" PROJECT_ROOT="$P" MXTK_ROOT="$TOOLKIT" MXCLI="$WORK/mxcli" ./bin/review-branch.sh --run --out "$WORK/e1" 2>&1); rc=$?
[ $rc -eq 1 ] && [ ! -f "$WORK/e1/REVIEW.md" ] && ok "E7 a failed rerun never reports the previous REVIEW.md" || bad "E7 stale review (rc $rc)" "$out"

# ── G: a branch name with a slash names the default pack folder safely ──
git -C "$P" branch -q feature/x-1 feat
out=$(rb "$P" --head feature/x-1 2>&1); rc=$?
h=$(git -C "$P" rev-parse --short=8 feature/x-1)
[ $rc -eq 0 ] && [ -f "$P/docs/review/feature-x-1-$h/PACK.md" ] && ok "G1 feature/x-1 → docs/review/feature-x-1-<sha>/" || bad "G1 slash branch" "$out"

# ── F: two-tree layout (model under app/) ──
P2="$WORK/two"; mkproj "$P2" app
: > "$WORK/mxcli.args"
out=$(rb "$P2" --out "$WORK/f" 2>&1); rc=$?
grep -q -- '-p app/App.mpr --ref [0-9a-f]\{40\}\.\.[0-9a-f]\{40\}' "$WORK/mxcli.args" \
  && ok "F2 two-tree: diff-local gets app/App.mpr and merge-base..head" || bad "F2 diff-local args" "$(cat "$WORK/mxcli.args")"
[ $rc -eq 0 ] && grep -q '(1 model files)' "$WORK/f/PACK.md" && ! grep -q 'mprcontents' "$WORK/f/other.diff" \
  && ok "F1 two-tree: model files counted, kept out of other.diff" || bad "F1 two-tree" "$out$(grep '| Model' "$WORK/f/PACK.md")"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
