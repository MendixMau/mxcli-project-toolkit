#!/usr/bin/env bash
# Fixture for project-bin/module-close.sh (PR #581).
#
# usage: test-module-close.sh /path/to/module-close.sh
#
# Golden input: tests/wave2/fixtures/module-close/lint-pedapp-v0.28.0.txt, `mxcli lint` from
# mxcli v0.28.0 on a scratch copy of mxcli's testdata/pedapp with two bad microflows added in
# MyFirstModule (3 warnings; the catalog's ✓ progress lines removed). The stub mxcli replays it.
#   C1  the report carries the summary line bin/row-groups.sh reads (lint=N vm=RC), N counted from
#       the real lint format; and bin/row-groups.sh reads it (open with findings, done at 0)
#   C2  two-tree checkout (.mpr under app/, no root .mpr): the report is written, not "no .mpr here"
#   R1  reload.sh (beside module-close.sh): both layouts; .docker/ is read beside the .mpr, where
#       mxcli writes it (cmd/mxcli/docker/build.go)
set -uo pipefail
SUT="${1:?usage: test-module-close.sh /path/to/module-close.sh}"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$TK/tests/wave2/fixtures/module-close/lint-pedapp-v0.28.0.txt"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/module-close.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

mkproj() {  # $1 dir, $2 where the .mpr goes ("" = root, "app" = two-tree)
  local p="$1"
  mkdir -p "$p/bin" "$p/${2:-.}"
  cp "$SUT" "$p/bin/module-close.sh"; cp "$TK/project-bin/_common.sh" "$p/bin/"
  : > "$p/${2:-.}/App.mpr"
  # mxcli stub: `lint` replays the capture, `docker check` passes, and every call is logged.
  printf '#!/bin/sh\necho "$*" >> "%s/mxcli.calls"\ncase "$1" in lint) cat "%s" ;; docker) echo "Build succeeded" ;; esac\n' "$p" "$LINT" > "$p/mxcli"
  printf '#!/bin/sh\necho "score 71"\n' > "$p/bin/metrics-ledger.sh"
  printf '#!/bin/sh\necho "verdict CLEAN"\nexit 0\n' > "$p/bin/verify-module.sh"
  printf '#!/bin/sh\necho "owed MyFirstModule.Home_Web"\n' > "$p/bin/look-ledger.sh"
  chmod +x "$p/mxcli" "$p/bin/"*.sh
}

echo "== C1 summary line, counted from real lint output"
P="$WORK/single"; mkproj "$P" ""
out=$(cd "$P" && bash bin/module-close.sh MyFirstModule 2>&1); rc=$?
R="$P/docs/progress/module-close/MyFirstModule.md"
{ [ "$rc" = 1 ] && grep -q '<!-- mxtk-module-close: lint=3 vm=0 -->' "$R"; } \
  && ok "C1: MyFirstModule has 3 ⚠ in the capture → lint=3, exit 1" || bad "C1: rc=$rc" "$out$(cat "$R" 2>/dev/null | head -5)"
out=$(cd "$P" && bash bin/module-close.sh Administration 2>&1); rc=$?
{ [ "$rc" = 0 ] && grep -q 'mxtk-module-close: lint=0 ' "$P/docs/progress/module-close/Administration.md"; } \
  && ok "C1: a module with no ⚠ → lint=0, exit 0" || bad "C1 clean: rc=$rc" "$out"
# The consumer: bin/row-groups.sh reads the line this script wrote.
mkdir -p "$P/architecture/modules/MyFirstModule" "$P/architecture/modules/Billing" "$P/mdlsource"
cp "$TK/project-bin/row-groups.sh" "$P/bin/"
{ printf '### Phase 1 — MyFirstModule\n\n| # | Kind | Step | Produces | Depends on | Skills | State |\n|---|---|---|---|---|---|---|\n'
  printf '| 1 | BUILD | Home page | p | — | `mdl-pages.md` | done |\n\n'
  printf '### Phase 2 — Billing\n\n| # | Kind | Step | Produces | Depends on | Skills | State |\n|---|---|---|---|---|---|---|\n'
  printf '| 2 | BUILD | Invoice entity | e | 1 | `mdl-entities.md` | not built |\n'; } > "$P/architecture/build-plan.md"
printf -- '-- rows: 2\n' > "$P/mdlsource/b.mdl"
out=$(cd "$P" && bash bin/row-groups.sh check mdlsource/b.mdl 2>&1); rc=$?
{ [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'MyFirstModule (open'; } \
  && ok "C1: row-groups reads lint=3 + empty LOOK table as not closed" || bad "C1 consumer open: rc=$rc" "$out"
printf '| Home_Web | User | look/home-user.png | none | — |\n' >> "$R"
out=$(cd "$P" && bash bin/row-groups.sh check mdlsource/b.mdl 2>&1); rc=$?
[ "$rc" = 0 ] && ok "C1: one filled LOOK row in the written report → closed" || bad "C1 consumer filled: rc=$rc" "$out"

echo "== C2 two-tree checkout"
P2="$WORK/two"; mkproj "$P2" app
out=$(cd "$P2" && bash bin/module-close.sh MyFirstModule 2>&1); rc=$?
{ [ -f "$P2/docs/progress/module-close/MyFirstModule.md" ] && grep -q -- '-p .*app/App.mpr' "$P2/mxcli.calls"; } \
  && ok "C2: .mpr under app/ → report written, mxcli given app/App.mpr" || bad "C2: rc=$rc" "$out"


echo "== R1 reload.sh, both layouts (stub docker, curl, mxcli)"
RL="$(dirname "$SUT")/reload.sh"
if [ -f "$RL" ]; then
  mkdir -p "$WORK/stubs"
  printf '#!/bin/sh\n[ "$1 $2" = "compose port" ] && echo "0.0.0.0:18090"\nexit 0\n' > "$WORK/stubs/docker"
  printf '#!/bin/sh\necho "$*" >> "%s/curl.calls"\nprintf 200\n' "$WORK" > "$WORK/stubs/curl"
  chmod +x "$WORK/stubs/docker" "$WORK/stubs/curl"
  for lay in "" app; do
    P3="$WORK/rl-${lay:-root}"; mkproj "$P3" "$lay"; cp "$RL" "$P3/bin/reload.sh"; chmod +x "$P3/bin/reload.sh"
    mkdir -p "$P3/${lay:-.}/.docker"; printf 'APP_PORT=18080\n' > "$P3/${lay:-.}/.docker/.env"; : > "$WORK/curl.calls"
    out=$(cd "$P3" && PATH="$WORK/stubs:$PATH" APP_URL= bash bin/reload.sh 2>&1); rc=$?
    want="${lay:+app/}App.mpr"
    { [ "$rc" = 0 ] && grep -q -- "docker reload -p .*$want --direct --port 18090" "$P3/mxcli.calls" && grep -q 'localhost:18080/login.html' "$WORK/curl.calls"; } \
      && ok "R1 ${lay:-single tree}: reload --direct on $want, app URL from the .docker/.env beside it" \
      || bad "R1 ${lay:-single tree}: rc=$rc" "$out$(cat "$P3/mxcli.calls" 2>/dev/null)"
  done
else
  echo "  [skip] no reload.sh beside $SUT"
fi
echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
