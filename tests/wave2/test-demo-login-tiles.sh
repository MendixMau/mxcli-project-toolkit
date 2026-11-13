#!/usr/bin/env bash
# Fixture for project-bin/demo-login-tiles.sh (#736): demo sign-in tiles on localhost, patched between
# markers, passwords only in a git-ignored data file.
#
# usage: bash tests/wave2/test-demo-login-tiles.sh [/path/to/demo-login-tiles.sh]
#
# Golden input is captured (fixtures/demo-login-tiles/CAPTURE.txt): a real sign-in page and real
# `create/drop demo user` scripts of fictional POC apps, and a real `show demo users` table. The one
# synthetic file (multi-line / deprecated forms) is labelled as such. Run in a temp tree, both layouts.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/demo-login-tiles.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/demo-login-tiles"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/demo-tiles-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"
unset PROJECT_ROOT MPR_FILE

# mk <name> <layout single|two> <mdl files...>  -> $WORK/<name>, git repo with the page committed
mk() {
  local n="$1" lay="$2" app; shift 2
  local root="$WORK/$n"; app="$root"; [ "$lay" = two ] && app="$root/app"
  mkdir -p "$root/bin" "$app/theme/web" "$app/mdlsource"
  cp "$TOOLKIT/project-bin/_common.sh" "$SUBJECT" "$root/bin/"; : > "$app/Demo.mpr"
  cp "$FX/login.html" "$app/theme/web/login.html"
  for f in "$@"; do cp "$f" "$app/mdlsource/"; done
  ( cd "$root" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1
  echo "$root"
}
SUTN="$(basename "$SUBJECT")"
runit() { local root="$1"; shift; ( cd "$root" && bash "bin/$SUTN" "$@" 2>&1 ); }
REAL="$FX/mdl/C-excerpt-lines-41-62.mdl $FX/mdl/R-20-security-level.mdl $FX/mdl/S-02-security-production.mdl $FX/mdl/T-01-domain-security.mdl"

for LAY in single two; do
  echo "-- layout: $LAY"
  R="$(mk real-$LAY $LAY $REAL)"; APP="$R"; [ "$LAY" = two ] && APP="$R/app"
  PAGE="$APP/theme/web/login.html"; DATA="$APP/theme/web/demo-login.local.js"
  REL="${DATA#$R/}"
  cp "$PAGE" "$WORK/orig-$LAY.html"

  out="$(runit "$R" --model-users "$FX/show-demo-users.txt")"; rc=$?
  [ $rc -eq 0 ] && ok "$LAY: patch exit 0" || bad "$LAY: exit $rc" "$out"
  echo "$out" | grep -q '^10 demo users found' && ok "$LAY: 10 users found (real scripts C+R+S+T, host1 re-set by a later file, drops honoured)" || bad "$LAY: count" "$out"
  echo "$out" | grep -q "  learner1  (Learner)" && echo "$out" | grep -q "  reception2  (Reception)" && echo "$out" | grep -q "  engineer  (Engineer)" && ok "$LAY: names and roles listed" || bad "$LAY: listing" "$out"
  echo "$out" | grep -q "WARN: 'demo_user' is in the model but in no script" && echo "$out" | grep -q "WARN: 'demo_administrator' is in the model" && ok "$LAY: scripts/model disagreement warned (real show-demo-users table)" || bad "$LAY: model warn" "$out"
  echo "$out" | grep -q "WARN: 'engineer' is in the scripts but not in the model" && ok "$LAY: script-only user warned" || bad "$LAY: script-only warn" "$out"
  pw="$(grep -o '"p":"[^"]*' "$DATA" | sed 's/"p":"//' | sort -u)"
  leak=0; while IFS= read -r p; do [ -n "$p" ] && { echo "$out" | grep -Fq -- "$p" && leak=1; grep -Fq -- "$p" "$PAGE" && leak=2; }; done <<EOF
$pw
EOF
  [ "$leak" -eq 0 ] && ok "$LAY: no password in the terminal output or in login.html ($(echo "$pw" | wc -l | tr -d ' ') distinct passwords checked)" || bad "$LAY: password leaked (code $leak)"
  names="$(grep -o '"u":"[^"]*' "$DATA" | sed 's/"u":"//')"
  nn=0; while IFS= read -r u; do [ -n "$u" ] && { nn=$((nn+1)); grep -Fq "'$u'" "$PAGE" && leak=3; grep -Fq "\"$u\"" "$PAGE" && leak=3; }; done <<EOF
$names
EOF
  [ "$leak" -eq 0 ] && ok "$LAY: no user name in login.html ($nn names checked)" || bad "$LAY: user name in page"
  grep -q 'learner1' "$PAGE" && bad "$LAY: learner1 in page"
  grep -Fq '"u":"host1","p":"Visitors2026Demo"' "$DATA" && ok "$LAY: later statement wins (host1 password from file S)" || bad "$LAY: later-wins" "$(cut -c1-60 "$DATA")"
  grep -q '"u":"demo_user"' "$DATA" && bad "$LAY: dropped scaffold user present" || ok "$LAY: dropped users absent"
  grep -Fxq "/$REL" "$R/.gitignore" && ok "$LAY: data file listed in .gitignore (/$REL)" || bad "$LAY: gitignore" "$(cat "$R/.gitignore" 2>&1)"
  grep -q 'DEMO-LOGIN-BEGIN -->' "$PAGE" && grep -q 'DEMO-LOGIN-END -->' "$PAGE" && ok "$LAY: markers inserted" || bad "$LAY: markers"
  # outside the markers byte-identical: strip the block from the patched page, compare with the original
  awk '/DEMO-LOGIN-BEGIN -->/{print; skip=1; next} /DEMO-LOGIN-END -->/{skip=0; next} !skip{print}' "$PAGE" | grep -v 'DEMO-LOGIN-BEGIN -->' > "$WORK/outside-$LAY"
  grep -v 'DEMO-LOGIN-END -->' "$WORK/orig-$LAY.html" > "$WORK/orig-$LAY.cmp"
  cmp -s "$WORK/outside-$LAY" "$WORK/orig-$LAY.cmp" && ok "$LAY: everything outside the markers is byte-identical to the original page" || bad "$LAY: page changed outside markers" "$(diff "$WORK/outside-$LAY" "$WORK/orig-$LAY.cmp" | head -5)"
  for id in loginForm usernameInput passwordInput loginButton loginMessage; do grep -q "id=\"$id\"" "$PAGE" || bad "$LAY: id $id lost"; done
  cp "$PAGE" "$WORK/p1-$LAY"; cp "$DATA" "$WORK/d1-$LAY"
  out="$(runit "$R")"; rc=$?
  cmp -s "$WORK/p1-$LAY" "$PAGE" && cmp -s "$WORK/d1-$LAY" "$DATA" && [ $rc -eq 0 ] && echo "$out" | grep -q 'login.html unchanged' && ok "$LAY: second run is a no-op (cmp page and data file, 'unchanged')" || bad "$LAY: second run changed something" "$out"
  grep -q '__DEMO_LOGIN__ *= *{' "$PAGE" && bad "$LAY: page carries the data assignment"
  out="$(runit "$R" --check)"; rc=$?
  [ $rc -eq 0 ] && ok "$LAY: --check exit 0 (data file ignored, untracked)" || bad "$LAY: check rc $rc" "$out"
  # tracked data file -> --check 1, patch refuses with 3
  ( cd "$R" && git add -f "$REL" && git -c user.email=t@t -c user.name=t commit -q -m leak ) >/dev/null 2>&1
  out="$(runit "$R" --check)"; rc=$?
  [ $rc -eq 1 ] && echo "$out" | grep -q 'tracked by git' && ok "$LAY: --check exit 1 when the data file is tracked" || bad "$LAY: tracked check rc $rc" "$out"
  out="$(runit "$R")"; rc=$?
  [ $rc -eq 3 ] && echo "$out" | grep -q 'already tracked by git' && ok "$LAY: patch refuses (exit 3) when the data file is tracked" || bad "$LAY: tracked patch rc $rc" "$out"
  ( cd "$R" && git rm -q --cached "$REL" && git -c user.email=t@t -c user.name=t commit -q -m unleak ) >/dev/null 2>&1
  # --remove
  out="$(runit "$R" --remove)"; rc=$?
  [ $rc -eq 0 ] && [ ! -e "$DATA" ] && ! grep -q 'demoLogin\|demo-login.local.js' "$PAGE" && ok "$LAY: --remove deletes the data file and leaves no demo markup in the page" || bad "$LAY: remove" "$out"
  awk '/DEMO-LOGIN-BEGIN -->/{print; next}{print}' "$PAGE" | grep -v 'DEMO-LOGIN-' | cmp -s - "$WORK/orig-$LAY.cmp" && ok "$LAY: after --remove the page equals the original (but for the two empty marker lines)" || bad "$LAY: remove residue"
  out="$(runit "$R" --check)"; [ $? -eq 0 ] && echo "$out" | grep -q 'no tiles' && ok "$LAY: --check after --remove: no tiles" || bad "$LAY: check after remove" "$out"
  # existing markers: replaced, and text outside kept
  runit "$R" >/dev/null; cp "$PAGE" "$WORK/with-$LAY"
  { echo '<!-- keep me -->'; cat "$PAGE"; echo '<!-- keep me too -->'; } > "$WORK/wrapped"; cp "$WORK/wrapped" "$PAGE"
  out="$(runit "$R" --crew 8541=learner1,trainer1 --host demo.example.test)"; rc=$?
  head -1 "$PAGE" | grep -q 'keep me' && tail -1 "$PAGE" | grep -q 'keep me too' && grep -c 'DEMO-LOGIN-BEGIN -->' "$PAGE" | grep -q '^1$' && ok "$LAY: re-run replaces only the interior of existing markers" || bad "$LAY: marker reuse" "$out"
  grep -Fq '"crew": {"8541":["learner1","trainer1"]}' "$DATA" && ok "$LAY: --crew ends up in the data file" || bad "$LAY: crew" "$(tail -4 "$DATA")"
  grep -Fq 'var extra = ["demo.example.test"];' "$PAGE" && ok "$LAY: --host ends up in the loader" || bad "$LAY: host"
  mkdir -p "$R/.claude/loop"; printf '# crew\n8542\tengineer,manager\n' > "$R/.claude/loop/demo-crew.tsv"
  runit "$R" --crew 8541=learner2 >/dev/null
  grep -Fq '"8541":["learner2"]' "$DATA" && grep -Fq '"8542":["engineer","manager"]' "$DATA" && ok "$LAY: crew file and --crew merge (flag wins for its port)" || bad "$LAY: crew merge" "$(tail -4 "$DATA")"
  runit "$R" --remove >/dev/null
done

echo "-- parser, synthetic shapes"
R="$(mk syn single "$FX/mdl-synthetic.mdl")"; out="$(runit "$R")"; D="$R/theme/web/demo-login.local.js"
echo "$out" | grep -q '^3 demo users found' && ok "syn: 3 users (multi-line, deprecated form, re-created); dropped and commented-out ones absent" || bad "syn count" "$out"
grep -Fq '{"u":"multi.line","p":"Pa--ss;word'"'"'s","r":["Alpha","Beta Role"]}' "$D" && ok "syn: multi-line statement, quoted role, '' escape, -- and ; inside the password" || bad "syn multi-line" "$(cat "$D")"
grep -Fq '{"u":"old.form","p":"Old-Pass-1!","r":["Alpha","Gamma"]}' "$D" && ok "syn: deprecated clause form with two roles" || bad "syn old form" "$(cat "$D")"
grep -Fq '{"u":"back","p":"Second-1!","r":["Gamma"]}' "$D" && ! grep -q '"u":"gone"\|"u":"commented"' "$D" && ok "syn: drop then re-create wins; dropped and commented users absent" || bad "syn drop" "$(cat "$D")"

echo "-- could not run: nothing changes"
R="$(mk noids single "$FX/mdl/R-20-security-level.mdl")"; grep -v 'id="loginButton"' "$R/theme/web/login.html" > "$WORK/noids.html"; cp "$WORK/noids.html" "$R/theme/web/login.html"
( cd "$R" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m x ) >/dev/null 2>&1
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q 'no element with id="loginButton"' && cmp -s "$WORK/noids.html" "$R/theme/web/login.html" && [ ! -e "$R/theme/web/demo-login.local.js" ] && [ ! -e "$R/.gitignore" ] && ok "missing id: exit 3, message names the id, no file changed or created" || bad "missing id rc $rc" "$out"
R="$(mk nopage single "$FX/mdl/R-20-security-level.mdl")"; rm "$R/theme/web/login.html"
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q 'no sign-in page' && [ -z "$(ls "$R/theme/web")" ] && ok "no sign-in page: exit 3, nothing created" || bad "no page rc $rc" "$out"
R="$(mk nousers single)"; out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && cmp -s "$FX/login.html" "$R/theme/web/login.html" && ok "no mdl files: exit 3, page untouched" || bad "no users rc $rc" "$out"
R="$(mk nodu single "$FX/mdl/R-20-security-level.mdl")"; echo "alter app security ( SecurityLevel: PRODUCTION );" > "$R/mdlsource/R-20-security-level.mdl"
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q 'no demo users found' && ok "no demo user statements: exit 3" || bad "no du rc $rc" "$out"
out="$(runit "$R" --bogus)"; rc=$?; [ $rc -eq 2 ] && ok "unknown option: exit 2" || bad "usage rc $rc"
out="$(runit "$R" --crew abc=x)"; rc=$?; [ $rc -eq 2 ] || [ $rc -eq 3 ] && ok "bad crew port rejected (exit $rc)" || bad "crew rc $rc"

echo; echo "demo-login-tiles fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
