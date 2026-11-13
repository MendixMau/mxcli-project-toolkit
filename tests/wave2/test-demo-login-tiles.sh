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
  grep -Fq '"u":"host1","p":"demo-pw-s1"' "$DATA" && ok "$LAY: later statement wins (host1 password from file S)" || bad "$LAY: later-wins" "$(cut -c1-60 "$DATA")"
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

for LAY in single two; do
  echo "-- deployed web folder, layout: $LAY"
  R="$(mk dep-$LAY $LAY $FX/mdl/R-20-security-level.mdl)"; APP="$R"; [ "$LAY" = two ] && APP="$R/app"
  mkdir -p "$APP/deployment/web"; cp "$FX/login.html" "$APP/deployment/web/login.html"; printf '/deployment/\n' > "$R/.gitignore"
  ( cd "$R" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m dep ) >/dev/null 2>&1
  TP="$APP/theme/web/login.html"; TD="$APP/theme/web/demo-login.local.js"; DP="$APP/deployment/web/login.html"; DD="$APP/deployment/web/demo-login.local.js"
  out="$(runit "$R")"; rc=$?
  [ $rc -eq 0 ] && cmp -s "$TP" "$DP" && cmp -s "$TD" "$DD" && grep -q 'DEMO-LOGIN-BEGIN -->' "$DP" && ok "$LAY: (a) both pages patched identically, both data files written" || bad "$LAY: (a) deployed" "$out"
  echo "$out" | grep -q 'the running app was updated.*browser reload is enough' && ok "$LAY: (a) says the running app was updated, reload is enough" || bad "$LAY: (a) message" "$out"
  grep -q 'learner\|host1\|demo-pw' "$DP" && bad "$LAY: (a) credentials in deployed page"
  cp "$TP" "$WORK/dp1-t"; cp "$DP" "$WORK/dp1-d"; cp "$DD" "$WORK/dd1"
  out="$(runit "$R")"
  cmp -s "$WORK/dp1-t" "$TP" && cmp -s "$WORK/dp1-d" "$DP" && cmp -s "$WORK/dd1" "$DD" && ok "$LAY: (a) second run is a no-op in both places" || bad "$LAY: (a) second run" "$out"
  out="$(runit "$R" --check)"; rc=$?; [ $rc -eq 0 ] && ok "$LAY: (a) --check 0 (deployment/ ignored)" || bad "$LAY: (a) check" "$out"
  ( cd "$R" && git add -f "${DD#$R/}" && git -c user.email=t@t -c user.name=t commit -q -m leak ) >/dev/null 2>&1
  out="$(runit "$R" --check)"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q 'deployment/web/demo-login.local.js is tracked' && ok "$LAY: (a) --check 1 when the DEPLOYED data file is tracked" || bad "$LAY: (a) tracked deployed rc $rc" "$out"
  ( cd "$R" && git rm -q --cached "${DD#$R/}" && git -c user.email=t@t -c user.name=t commit -q -m unleak ) >/dev/null 2>&1
  out="$(runit "$R" --remove)"; rc=$?
  [ $rc -eq 0 ] && [ ! -e "$TD" ] && [ ! -e "$DD" ] && ! grep -q 'demoLogin\|demo-login.local.js' "$TP" "$DP" && ok "$LAY: (b) --remove empties both pages and deletes both data files" || bad "$LAY: (b) remove" "$out"
  out="$(runit "$R" --check)"; echo "$out" | grep -q 'no tiles' && ok "$LAY: (b) --check after remove: no tiles" || bad "$LAY: (b) check" "$out"
  # deployment/ NOT ignored: the deployed data file gets its own ignore line
  printf '' > "$R/.gitignore"; ( cd "$R" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m noign ) >/dev/null 2>&1
  out="$(runit "$R")"
  grep -Fxq "/${DD#$R/}" "$R/.gitignore" && echo "$out" | grep -q 'to .gitignore' && ok "$LAY: deployment/ not ignored -> deployed data file added to .gitignore" || bad "$LAY: deployed gitignore" "$out"
  runit "$R" --remove >/dev/null

  R="$(mk nodep-$LAY $LAY $FX/mdl/R-20-security-level.mdl)"; APP="$R"; [ "$LAY" = two ] && APP="$R/app"
  out="$(runit "$R")"; rc=$?
  [ $rc -eq 0 ] && [ ! -e "$APP/deployment" ] && grep -q 'DEMO-LOGIN-BEGIN -->' "$APP/theme/web/login.html" && echo "$out" | grep -q 'no deployed web folder: the tiles appear after the next app start' && ok "$LAY: (c) no deployed folder: only theme files change, message says so" || bad "$LAY: (c)" "$out"
done

echo "-- whitespace inside a quoted password is kept byte-exact (synthetic)"
R="$(mk ws single)"; P="$(printf '  lead  dbl\tTab trail  ')"
printf "create demo user 'ws.user' ( Password: '%s', UserRoles: (Alpha) );\n" "$P" > "$R/mdlsource/ws.mdl"
out="$(runit "$R")"; D="$R/theme/web/demo-login.local.js"
grep -Fq -- "\"p\":\"$P\"" "$D" && ok "password with leading/trailing/double spaces and a tab round-trips byte-exact" || bad "whitespace password changed" "$(grep ws.user "$D" | od -c | head -4)"

echo "-- .gitignore must really ignore the data file, or nothing is written"
R="$(mk gi1 single $FX/mdl/R-20-security-level.mdl)"; mkdir "$R/.gitignore"; cp "$R/theme/web/login.html" "$WORK/gi1.html"
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && [ ! -e "$R/theme/web/demo-login.local.js" ] && cmp -s "$WORK/gi1.html" "$R/theme/web/login.html" && ! echo "$out" | grep -q '^added' && ok ".gitignore unwritable (a directory): exit 3, no data file, page untouched, no 'added' line" || bad "gi dir rc $rc" "$out"
R="$(mk gi2 single $FX/mdl/R-20-security-level.mdl)"; printf '/theme/web/demo-login.local.js\n!/theme/web/demo-login.local.js\n' > "$R/.gitignore"
out="$(runit "$R")"; rc=$?
git -C "$R" check-ignore -q -- theme/web/demo-login.local.js && [ $rc -eq 0 ] && echo "$out" | grep -q '^added' && ok "a matching line defeated by a later ! negation is not trusted: the line is re-added and git then says ignored" || bad "gi negation repair rc $rc" "$out"
R="$(mk gi2b single $FX/mdl/R-20-security-level.mdl)"; printf '!demo-login.local.js\n' > "$R/theme/web/.gitignore"
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && [ ! -e "$R/theme/web/demo-login.local.js" ] && ok "a nested .gitignore negation the append cannot beat: exit 3, no data file" || bad "gi nested negation rc $rc" "$out"
R="$(mk gi3 single $FX/mdl/R-20-security-level.mdl)"; mkdir -p "$R/deployment/web"; cp "$FX/login.html" "$R/deployment/web/login.html"
printf '/theme/web/demo-login.local.js\n' > "$R/.gitignore"; printf '!demo-login.local.js\n' > "$R/deployment/web/.gitignore"
out="$(runit "$R")"; rc=$?
[ $rc -eq 3 ] && [ ! -e "$R/theme/web/demo-login.local.js" ] && [ ! -e "$R/deployment/web/demo-login.local.js" ] && ok "deployed location not ignorable: exit 3 BEFORE the theme data file is written either" || bad "gi deployed rc $rc" "$out"
R="$(mk gi4 single $FX/mdl/R-20-security-level.mdl)"; rm -rf "$R/.git"
out="$(runit "$R")"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q 'not a git repository' && [ -e "$R/theme/web/demo-login.local.js" ] && ok "not a git repository: one line saying so, continues" || bad "no git rc $rc" "$out"

echo "-- --check --strict / --predeploy"
R="$(mk st single $FX/mdl/R-20-security-level.mdl)"; runit "$R" >/dev/null
out="$(runit "$R" --check)"; rc=$?; [ $rc -eq 0 ] && ok "plain --check 0 with tiles present (ignored, untracked)" || bad "plain check rc $rc" "$out"
out="$(runit "$R" --check --strict)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'STRICT FAIL: theme/web/demo-login.local.js exists' && echo "$out" | grep -q 'STRICT FAIL: the demo block in theme/web/login.html is not empty' && ok "--check --strict: exit 1, names the data file and the block" || bad "strict rc $rc" "$out"
out="$(runit "$R" --predeploy)"; rc=$?; [ $rc -eq 1 ] && ok "--predeploy alias: exit 1" || bad "predeploy rc $rc" "$out"
rm "$R/theme/web/demo-login.local.js"; out="$(runit "$R" --predeploy)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'block in theme/web/login.html is not empty' && ok "--strict: exit 1 on a non-empty block alone" || bad "strict block-only rc $rc" "$out"
runit "$R" >/dev/null; runit "$R" --remove >/dev/null
out="$(runit "$R" --check --strict)"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q 'no tiles' && ok "--strict after --remove: exit 0" || bad "strict after remove rc $rc" "$out"

echo "-- --remove refuses damaged markers like the patch run"
R="$(mk dm single $FX/mdl/R-20-security-level.mdl)"; runit "$R" >/dev/null
grep -v 'DEMO-LOGIN-END -->' "$R/theme/web/login.html" > "$WORK/dm.html"; cp "$WORK/dm.html" "$R/theme/web/login.html"
out="$(runit "$R" --remove)"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q 'broken marker pair' && cmp -s "$WORK/dm.html" "$R/theme/web/login.html" && [ -e "$R/theme/web/demo-login.local.js" ] && ok "--remove on damaged markers: exit 3, nothing changed" || bad "remove damaged rc $rc" "$out"

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
