#!/usr/bin/env bash
# test-status-extension-modules.sh — bin/status.sh WATCHes when an extension module
# (modules/*.mxmodule) does not travel with the model, or a project using Agent Editor has none (#778).
#
# Usage: bash tests/wave2/test-status-extension-modules.sh bin/status.sh
#
# The defect: Studio Pro reads the agenteditor.agent document type from modules/AgentEditor.mxmodule
# beside the .mpr. A model sync that copies only .mpr + mprcontents/ leaves it out of git, so the
# builder stays green and every colleague's clone shows "unknown type 'agenteditor.agent'".
#
#   T1  root layout, modules/AgentEditor.mxmodule untracked      -> WATCH names modules/AgentEditor.mxmodule
#   T2  root layout, the same file committed                     -> no extension WATCH
#   T3  two-tree (app/ inside the root repo), untracked          -> WATCH names app/modules/AgentEditor.mxmodule
#   T4  two-tree, app/ its own repo, committed there             -> no extension WATCH
#   T5  root, mdlsource has `create agent`, no .mxmodule         -> WATCH: uses Agent Editor but ... missing
#   T6  two-tree, inventory.json lists AgentEditorCommons, none  -> WATCH names app/modules/AgentEditor.mxmodule missing
#   T7  no agents, no .mxmodule, no git                          -> no extension WATCH
#   T8  the full screen carries the same WATCH
#
# GOLDEN INPUT: PROJECT.md is the real bin/init-project.sh scaffold; tracked/untracked is whatever
# this machine's git reports. inventory.json is printed in the json.dump(indent=1) shape app-facts.sh
# writes (its own output, not mxcli's). gate-check.sh is stubbed silent in the toolkit copy.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1 MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail
SUT="${1:?usage: test-status-extension-modules.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"

W="$(mktemp -d "${TMPDIR:-/tmp}/statusxm.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/tk/bin/gate-check.sh"
mkproj() {  # mkproj <name> <model subdir: "" or app> -> project root; .mpr in <root>/<subdir>
  local d="$W/proj-$1" m="$W/proj-$1${2:+/$2}"; mkdir -p "$m"; : > "$m/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  echo "$d"
}
addmod() { mkdir -p "$1/modules"; printf 'PK-fixture\n' > "$1/modules/AgentEditor.mxmodule"; }
watch() { bash "$W/tk/bin/status.sh" "$1" --brief 2>&1; }

echo "== bin/status.sh extension-module WATCH (#778) =="
P="$(mkproj t1 '')"; g "$P" init -q; addmod "$P"
out="$(watch "$P")"
case "$(grep '^WATCH' <<<"$out")" in
  *"extension module not in git: modules/AgentEditor.mxmodule"*) ok "T1 root, untracked: WATCH names modules/AgentEditor.mxmodule" ;;
  *) bad "T1 want the untracked-module WATCH" "$out" ;;
esac

P="$(mkproj t2 '')"; g "$P" init -q; addmod "$P"; g "$P" add -- modules/AgentEditor.mxmodule; g "$P" commit -qm m
out="$(watch "$P")"
if grep -qE 'extension module|uses Agent Editor' <<<"$out"; then bad "T2 committed module must not WATCH" "$out"; else ok "T2 root, committed: no extension WATCH"; fi

P="$(mkproj t3 app)"; g "$P" init -q; addmod "$P/app"
out="$(watch "$P")"
case "$(grep '^WATCH' <<<"$out")" in
  *"extension module not in git: app/modules/AgentEditor.mxmodule"*) ok "T3 two-tree, untracked: WATCH names app/modules/AgentEditor.mxmodule" ;;
  *) bad "T3 want the untracked-module WATCH under app/" "$out" ;;
esac

P="$(mkproj t4 app)"; g "$P/app" init -q; addmod "$P/app"; g "$P/app" add -- modules/AgentEditor.mxmodule; g "$P/app" commit -qm m
out="$(watch "$P")"
if grep -qE 'extension module|uses Agent Editor' <<<"$out"; then bad "T4 app/ repo with committed module must not WATCH" "$out"; else ok "T4 two-tree, app/ own repo, committed: no extension WATCH"; fi

P="$(mkproj t5 '')"; g "$P" init -q; mkdir -p "$P/mdlsource"
printf "create agent Support.HelpAgent (\n  Title: 'Help'\n);\n" > "$P/mdlsource/310-agent.mdl"
out="$(watch "$P")"
case "$(grep '^WATCH' <<<"$out")" in
  *"project uses Agent Editor but modules/AgentEditor.mxmodule is missing"*) ok "T5 root, create agent, no .mxmodule: missing WATCH" ;;
  *) bad "T5 want the missing-module WATCH" "$out" ;;
esac

P="$(mkproj t6 app)"; mkdir -p "$P/analysis/app-facts"
# the shape json.dump(indent=1, sort_keys=True) gives app-facts.sh's inventory (python3 -c prints it)
printf '{\n "modules": [\n  {\n   "kind": "own",\n   "name": "MyFirstModule"\n  },\n  {\n   "kind": "marketplace",\n   "name": "AgentEditorCommons"\n  }\n ]\n}' \
  > "$P/analysis/app-facts/inventory.json"
out="$(watch "$P")"
case "$(grep '^WATCH' <<<"$out")" in
  *"project uses Agent Editor but app/modules/AgentEditor.mxmodule is missing"*) ok "T6 two-tree, inventory lists AgentEditorCommons: missing WATCH under app/" ;;
  *) bad "T6 want the missing-module WATCH under app/" "$out" ;;
esac

P="$(mkproj t7 '')"
out="$(watch "$P")"
if grep -qE 'extension module|uses Agent Editor' <<<"$out"; then bad "T7 no agents, no git must not WATCH" "$out"; else ok "T7 no agents, no .mxmodule, no git: no extension WATCH"; fi

out="$(bash "$W/tk/bin/status.sh" "$W/proj-t1" 2>&1)"
if grep -q '^WATCH .*extension module not in git' <<<"$out"; then ok "T8 full screen: same WATCH"; else bad "T8 full screen lacks the WATCH" "$out"; fi

echo "-- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
