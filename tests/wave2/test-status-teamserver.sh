#!/usr/bin/env bash
# test-status-teamserver.sh — bin/status.sh WATCHes when a project going live has no Team Server
# remote, or when Team Server holds commits the toolkit project does not (#765).
#
# Usage: bash tests/wave2/test-status-teamserver.sh bin/status.sh
#
# The defect: an app built with the toolkit went live through a SEPARATE Team Server working copy
# with no .mxtk, so every later change skipped the exec gate, snapshots and BUILD-LOG, and no
# toolkit screen said so (field 2026-11-13).
#
#   T1  Stage 6, git repo, no remote                 -> WATCH "no Team Server remote at Stage 6"
#   T2  Stage 5, no remote                           -> no Team Server WATCH (not going live yet)
#   T3  Stage 6, teamserver remote, ref == HEAD      -> no Team Server WATCH (the clean case)
#   T4  Stage 6, fetched Team Server ref ahead of HEAD -> WATCH "commits made outside the toolkit"
#   T5  the ref is contained in a local branch (subtree route's ts-export) -> no WATCH
#   T6  two-tree: app/ is its own repo carrying the remote -> no "no remote" WATCH
#   T7  exit code stays 0 with both WATCH items; the full screen carries them too
#
# GOLDEN INPUT: PROJECT.md is the real bin/init-project.sh scaffold; refs are real git objects in
# temp repos (a "fetch" is simulated with update-ref — no network). gate-check.sh is stubbed silent.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1 MXTK_SYNC_SKIP_CLONE_CHECK=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
set -uo pipefail
SUT="${1:?usage: test-status-teamserver.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"

W="$(mktemp -d "${TMPDIR:-/tmp}/statusts.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/tk/bin/gate-check.sh"
TS_URL="https://git.api.mendix.com/00000000-0000-0000-0000-000000000000.git"

setstage() {  # setstage <dir> <N>: replace the scaffold's **Stage ...** line under ## Current stage
  MXTK_L="**Stage $2 — fixture**" awk '/^## Current stage/{f=1} f && /^\*\*Stage/ && !d {print ENVIRON["MXTK_L"]; d=1; next} {print}' \
    "$1/PROJECT.md" > "$1/p.new" && mv "$1/p.new" "$1/PROJECT.md"
}
mkproj() {  # mkproj <name> <stage>: scaffolded project, one commit
  local d="$W/proj-$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  setstage "$d" "$2"
  git -C "$d" init -q; git -C "$d" add . >/dev/null 2>&1; git -C "$d" commit -qm base
  echo "$d"
}
tswatch() { bash "$W/tk/bin/status.sh" "$1" --brief 2>&1 | grep '^WATCH' | grep -i 'team server'; }

echo "== bin/status.sh Team Server WATCH (#765) =="
grep -q '^\*\*Stage 6 — fixture' "$(mkproj probe 6)/PROJECT.md" && ok "setup: stage line rewritten" || bad "setup: no **Stage line in the scaffold"

P1="$(mkproj noremote6 6)"
w="$(tswatch "$P1")"
case "$w" in *"no Team Server remote at Stage 6"*"platform-link.md"*) ok "T1 Stage 6, no remote: WATCH points at platform-link" ;;
  *) bad "T1 want the no-remote WATCH" "$(bash "$W/tk/bin/status.sh" "$P1" --brief 2>&1)" ;; esac

P2="$(mkproj noremote5 5)"
[ -z "$(tswatch "$P2")" ] && ok "T2 Stage 5, no remote: no Team Server WATCH" || bad "T2 Stage 5 must not WATCH" "$(tswatch "$P2")"

P3="$(mkproj clean 6)"
git -C "$P3" remote add teamserver "$TS_URL"
git -C "$P3" update-ref refs/remotes/teamserver/main HEAD
git -C "$P3" symbolic-ref refs/remotes/teamserver/HEAD refs/remotes/teamserver/main
[ -z "$(tswatch "$P3")" ] && ok "T3 remote present, ref == HEAD: no WATCH" || bad "T3 clean must not WATCH" "$(tswatch "$P3")"

P4="$(mkproj ahead 6)"
git -C "$P4" remote add origin "$TS_URL"
_tree="$(git -C "$P4" rev-parse 'HEAD^{tree}')"
_ext="$(printf 'outside\n' | git -C "$P4" commit-tree "$_tree" -p HEAD)"   # a commit made in the other copy
git -C "$P4" update-ref refs/remotes/origin/main "$_ext"                   # what a fetch would leave
w="$(tswatch "$P4")"
case "$w" in *"Team Server has commits made outside the toolkit: origin/main"*) ok "T4 fetched ref ahead of HEAD: WATCH names origin/main" ;;
  *) bad "T4 want the outside-commits WATCH" "$(bash "$W/tk/bin/status.sh" "$P4" --brief 2>&1)" ;; esac
case "$w" in *"no Team Server remote"*) bad "T4 a Team Server remote exists: no no-remote WATCH" "$w" ;; *) ok "T4 no no-remote WATCH beside it" ;; esac

git -C "$P4" branch ts-export "$_ext"
[ -z "$(tswatch "$P4")" ] && ok "T5 ref contained in a local branch: no WATCH" || bad "T5 subtree branch must silence it" "$(tswatch "$P4")"

P6="$(mkproj twotree 6)"
mkdir -p "$P6/app"; git -C "$P6/app" init -q; : > "$P6/app/App.mpr"
git -C "$P6/app" add App.mpr; git -C "$P6/app" commit -qm app
git -C "$P6/app" remote add teamserver "$TS_URL"
[ -z "$(tswatch "$P6")" ] && ok "T6 two-tree: remote on app/ counts" || bad "T6 app/ remote must count" "$(tswatch "$P6")"

P7="$(mkproj both 7)"
git -C "$P7" remote add teamserver "$TS_URL"
git -C "$P7" update-ref refs/remotes/teamserver/main "$(printf 'x\n' | git -C "$P7" commit-tree "$(git -C "$P7" rev-parse 'HEAD^{tree}')" -p HEAD)"
bash "$W/tk/bin/status.sh" "$P7" --brief >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "T7 exit 0 while warning" || bad "T7 exit code changed: $rc"
full="$(bash "$W/tk/bin/status.sh" "$P7" 2>&1)"
grep -q '^WATCH .*Team Server has commits made outside the toolkit' <<<"$full" && ok "T7 full screen carries the WATCH" || bad "T7 full screen lacks it" "$full"

echo "-- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
