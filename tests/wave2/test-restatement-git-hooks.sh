#!/usr/bin/env bash
# test-restatement-git-hooks.sh — #504: the restatement guard's last-writer ledger only saw exec.sh's
# writes, so a `git pull` / `git checkout` that brought newer model work in left it saying "05 wrote
# last" and a replay of 05 over 09's work stayed quiet. install-project-hooks.sh now installs
# post-merge + post-checkout hooks that append a RESTORE row when the operation changed the model.
#
# Usage: bash tests/wave2/test-restatement-git-hooks.sh [path-to-install-project-hooks.sh]
#        script-owners.sh and _common.sh are taken from the same directory.
# Real git (merge, fast-forward pull, branch checkout, file checkout), both layouts (.mpr at the
# root, and two-tree app/App.mpr), a pre-existing foreign hook chained. No mxcli, no mxbuild.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TK/project-bin/install-project-hooks.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
BIN="$(dirname "$SUBJECT")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/restate-hooks.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export MODEL_UNVERIFIED_OK=1   # the pre-commit gate hook is not what this fixture tests
DOC="MICROFLOW Sales.ACT_Reject"

run_layout() {  # $1 = label, $2 = model dir relative to the root ("" or "app")
  local L="$1" MD="$2" R="$WORK/$1" C="$WORK/$1-clone" lg out mdir cm
  echo "== layout: $L"
  mkdir -p "$R/bin"; cd "$R" || return
  git init -q -b main .
  cp "$BIN/_common.sh" "$BIN/install-project-hooks.sh" "$BIN/script-owners.sh" "$BIN/model-stamp.sh" bin/ 2>/dev/null
  mdir="$R${MD:+/$MD}"; mkdir -p "$mdir/mprcontents/aa"
  echo v1 > "$mdir/App.mpr"; echo u1 > "$mdir/mprcontents/aa/unit.mxunit"; echo doc > README.md
  printf '.claude/\n' > .gitignore
  git add -A >/dev/null; git commit -qm base
  # The clone is the local machine: it ran 05, so its ledger says 05 wrote last.
  git clone -q "$R" "$C"; cd "$C" || return
  git config user.name t; git config user.email t@t
  mkdir -p .claude/loop/script-owners; lg="$C/.claude/loop/script-owners/written.tsv"
  printf '100\tmdlsource/05-reject.mdl\t%s\n' "$DOC" > "$lg"
  printf '#!/usr/bin/env bash\necho foreign >> "%s/foreign.log"\n' "$WORK" > .git/hooks/post-merge; chmod +x .git/hooks/post-merge
  ./bin/install-project-hooks.sh >"$WORK/$L-install.out" 2>&1 || bad "$L: install failed" "$(cat "$WORK/$L-install.out")"
  ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && ok "$L: --check sees all hooks" || bad "$L: --check" "$(./bin/install-project-hooks.sh --check 2>&1)"
  [ -f .git/hooks/post-merge.pre-mxtk ] && ok "$L: foreign post-merge kept and chained" || bad "$L: foreign hook not kept"
  out="$(PROJECT_ROOT="$C" bash bin/script-owners.sh last-writer "$DOC")"
  [ "$out" = "mdlsource/05-reject.mdl" ] && ok "$L: precondition — ledger says 05 wrote last" || bad "$L: precondition '$out'"

  # 1. a pull that touches no model file: no marker
  cd "$R"; echo more >> README.md; git commit -qam docs; cd "$C"
  git pull -q --no-rebase origin main >/dev/null 2>&1
  grep -q RESTORE "$lg" && bad "$L: docs-only pull marked the ledger" || ok "$L: docs-only pull leaves the ledger alone"
  grep -q foreign "$WORK/foreign.log" 2>/dev/null && ok "$L: chained foreign hook ran" || bad "$L: chained foreign hook did not run"

  # 2. #504's repro: upstream carries 09's work on the model; pull brings it in
  cd "$R"; echo "v2 (09 work)" > "$mdir/mprcontents/aa/unit.mxunit"; git commit -qam "09 work"; cd "$C"
  git pull -q --no-rebase origin main >/dev/null 2>&1
  grep -q 'RESTORE	git-post-merge:' "$lg" && ok "$L: model-changing pull appends a RESTORE row" || bad "$L: no RESTORE row after pull" "$(cat "$lg")"
  out="$(PROJECT_ROOT="$C" bash bin/script-owners.sh last-writer "$DOC")"
  [ -z "$out" ] && ok "$L: last-writer forgets 05 → the next replay check asks the model" || bad "$L: last-writer still '$out'"

  # 3. branch checkout: same model → nothing; different model → marker
  printf '200\tmdlsource/05-reject.mdl\t%s\n' "$DOC" >> "$lg"; n0="$(grep -c RESTORE "$lg")"
  git checkout -q -b side; n1="$(grep -c RESTORE "$lg")"
  [ "$n0" = "$n1" ] && ok "$L: checkout to a branch at the same commit adds nothing" || bad "$L: same-commit checkout marked"
  cm="$C${MD:+/$MD}"
  echo "side" > "$cm/App.mpr"; git commit -qam side; git checkout -q main
  [ "$(grep -c RESTORE "$lg")" -gt "$n1" ] && ok "$L: checkout that changes the .mpr marks" || bad "$L: model-changing checkout did not mark"
  # 4. file checkout (the documented remedy `git checkout HEAD -- mprcontents/`): always marks
  n2="$(grep -c RESTORE "$lg")"; echo dirty > "$cm/mprcontents/aa/unit.mxunit"
  git checkout -q HEAD -- "${MD:+$MD/}mprcontents"
  [ "$(grep -c RESTORE "$lg")" -gt "$n2" ] && ok "$L: file checkout marks (hook gets no paths)" || bad "$L: file checkout did not mark"
  [ "$(cat "$cm/mprcontents/aa/unit.mxunit")" = "v2 (09 work)" ] && ok "$L: file checkout restored the unit" || bad "$L: unit not restored"
  # 5. no ledger: never created by the hook
  rm -f "$lg"; git checkout -q side; git checkout -q main
  [ ! -f "$lg" ] && ok "$L: no ledger → hook creates none" || bad "$L: hook created a ledger"
  # 6. idempotent re-install
  ./bin/install-project-hooks.sh >/dev/null 2>&1
  [ ! -f .git/hooks/post-merge.pre-mxtk.pre-mxtk ] && grep -c 'mxtk-restatement-mark' .git/hooks/post-merge | grep -qx 1 \
    && ok "$L: re-install is idempotent" || bad "$L: re-install re-chained"
}

run_layout single ""
run_layout twotree "app"
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
