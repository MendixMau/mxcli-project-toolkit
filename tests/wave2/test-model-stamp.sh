#!/usr/bin/env bash
# Fixture for the verification stamp (project-bin/model-stamp.sh), the pre-commit hook
# (project-bin/install-project-hooks.sh) and the settings installer's deny + SessionStart
# hook (bin/install-claude-permissions.sh). 2026-09-17: a CE0117 reached the Team Server
# because nothing between "the model changed" and "the model was committed" ever ran the
# mxbuild gate. This proves the commit-time backstop discriminates.
#
# Runs in a throwaway git repo under /tmp with a two-tree layout (app/App.mpr + symlink at
# the root, like the two-tree field project this was proven on). No mxbuild is needed: the stamp is written by hand here, exactly
# as exec.sh / verify-model.sh write it. What mxbuild sees is verify-model.sh's job and is
# field-run, not fixtured.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/model-stamp.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/app/mprcontents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
cp "$TK/project-bin/_common.sh" "$TK/project-bin/model-stamp.sh" "$TK/project-bin/install-project-hooks.sh" "$TK/project-bin/session-check.sh" bin/
printf 'mpr' > app/App.mpr; printf 'u1' > app/mprcontents/a.mxunit; printf 'u2' > app/mprcontents/b.mxunit; ln -s app/App.mpr App.mpr
echo readme > README.md

echo "T1 fingerprint: working tree == fully staged tree"
git add -A >/dev/null
wt="$(./bin/model-stamp.sh fingerprint)"; st="$(./bin/model-stamp.sh fingerprint --staged)"
[ -n "$wt" ] && [ "$wt" = "$st" ] && ok "same fingerprint ($wt)" || bad "differ: wt=$wt staged=$st"
[ "$(./bin/model-stamp.sh paths | tr '\n' ' ')" = "app/App.mpr app/mprcontents " ] && ok "paths resolve through the root symlink to app/" || bad "paths: $(./bin/model-stamp.sh paths | tr '\n' ' ')"

echo "T2 no stamp -> check fails; hook refuses; override lets it through"
./bin/install-project-hooks.sh >/dev/null && [ -x .git/hooks/pre-commit ] && ok "hook installed" || bad "hook not installed"
./bin/install-project-hooks.sh --check >/dev/null && ok "--check sees it" || bad "--check missed it"
./bin/model-stamp.sh check --staged -q && bad "check passed with no stamp" || ok "check refuses with no stamp"
git commit -qm "m" 2>/dev/null && bad "commit went through unverified" || ok "pre-commit refused the model commit"
MODEL_UNVERIFIED_OK=1 git commit -qm "m" 2>/dev/null && ok "MODEL_UNVERIFIED_OK=1 lets it through" || bad "override did not work"

echo "T3 stamp written -> commit allowed; non-model commits never consult it"
printf 'u2b' > app/mprcontents/b.mxunit
./bin/model-stamp.sh write pass "fixture" >/dev/null
grep -q '^/.claude/.model-verified' .gitignore && ok "stamp self-gitignored" || bad "stamp not gitignored"
git add app && git commit -qm "verified" 2>/dev/null && ok "verified model commits" || bad "verified model refused"
echo x >> README.md && git add README.md && git commit -qm "docs" 2>/dev/null && ok "non-model commit unaffected" || bad "non-model commit refused"

echo "T4 model changed after the stamp -> refused; partial staging named"
printf 'u1c' > app/mprcontents/a.mxunit; printf 'new' > app/mprcontents/c.mxunit
./bin/model-stamp.sh check -q && bad "changed model still verified" || ok "changed model is unverified"
git add app/mprcontents/a.mxunit
git commit -qm "stale" 2>/dev/null && bad "stale model committed" || ok "stale model refused"
./bin/model-stamp.sh write pass "fixture2" >/dev/null   # verify the new working tree
out="$(./bin/model-stamp.sh check --staged 2>&1)"
echo "$out" | grep -q "STAGED model differs" && ok "partially staged model named as such" || bad "partial staging not named" "$out"
git add app && git commit -qm "ok" 2>/dev/null && ok "fully staged verified model commits" || bad "fully staged refused"

echo "T5 stamp state != pass is refused; clear forgets"
./bin/model-stamp.sh write fail "fixture" >/dev/null
./bin/model-stamp.sh check -q && bad "fail stamp accepted" || ok "non-pass stamp refused"
./bin/model-stamp.sh clear >/dev/null; [ ! -f .claude/.model-verified ] && ok "clear removes the stamp" || bad "stamp still there"

echo "T6 existing foreign pre-commit hook is chained, not destroyed"
printf '#!/bin/sh\necho FOREIGN-HOOK-RAN >&2\nexit 0\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
./bin/install-project-hooks.sh >/dev/null
[ -x .git/hooks/pre-commit.pre-mxtk ] && ok "foreign hook kept as pre-commit.pre-mxtk" || bad "foreign hook lost"
echo y >> README.md && git add README.md
out="$(git commit -qm "chain" 2>&1)"; echo "$out" | grep -q FOREIGN-HOOK-RAN && ok "foreign hook still runs" || bad "foreign hook did not run" "$out"
./bin/install-project-hooks.sh >/dev/null; [ ! -f .git/hooks/pre-commit.pre-mxtk.pre-mxtk ] && ok "re-install is idempotent" || bad "re-install re-chained"

echo "T7 session-check never fails and names the unverified model"
out="$(MXTK_ROOT="$TK" ./bin/session-check.sh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "exit $rc" "$out"
echo "$out" | grep -q "UNVERIFIED" && ok "reports the unverified model" || bad "did not report" "$out"
echo "$out" | grep -q "guard scripts" && ok "reports guard-script status" || bad "no guard-script line" "$out"

echo "T8 settings installer: deny + SessionStart hook, idempotent, uninstall restores"
mkdir -p .claude; printf '{"permissions":{"allow":["Bash(./mxcli:*)"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"sh .claude/bootstrap-mxcli.sh || true"}]}]}}\n' > .claude/settings.json
"$TK/bin/install-claude-permissions.sh" "$P" >/dev/null
. "$TK/bin/lib/portable.sh"; require_py; py="$PY"
"$py" -c "import json,sys;d=json.load(open('.claude/settings.json'));sys.exit(0 if 'Bash(./mxcli exec:*)' in d['permissions']['deny'] else 1)" && ok "bare mxcli exec denied" || bad "deny missing"
"$py" -c "import json,sys;d=json.load(open('.claude/settings.json'));cmds=[h['command'] for g in d['hooks']['SessionStart'] for h in g['hooks']];sys.exit(0 if cmds==['sh .claude/bootstrap-mxcli.sh || true','bash bin/session-check.sh || true'] else 1)" && ok "session hook appended after the existing one" || bad "hook wrong: $(cat .claude/settings.json)"
"$TK/bin/install-claude-permissions.sh" "$P" --check >/dev/null && ok "--check passes" || bad "--check fails after install"
before="$(cat .claude/settings.json)"; "$TK/bin/install-claude-permissions.sh" "$P" >/dev/null; [ "$before" = "$(cat .claude/settings.json)" ] && ok "second install is a no-op" || bad "second install changed the file"
"$TK/bin/install-claude-permissions.sh" "$P" --uninstall >/dev/null
"$py" -c "import json,sys;d=json.load(open('.claude/settings.json'));cmds=[h['command'] for g in d['hooks']['SessionStart'] for h in g['hooks']];sys.exit(0 if d['permissions'].get('deny',[])==[] and cmds==['sh .claude/bootstrap-mxcli.sh || true'] and d['permissions']['allow'][0]=='Bash(./mxcli:*)' else 1)" && ok "uninstall removes only what it added" || bad "uninstall wrong: $(cat .claude/settings.json)"

echo; echo "model-stamp: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
