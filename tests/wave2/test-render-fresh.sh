#!/usr/bin/env bash
# Fixture for bin/lib/render-fresh.sh: a rendered file is "stale" only when its SOURCE changed
# after it — never because a fresh clone wrote the files in directory order.
#
# Usage: bash test-render-fresh.sh /path/to/render-fresh.sh
#
# Field run: a multi-app Mendix build checked out on a second machine; Stage 3 FAILed
# "process-map.html is older than process-model.json" with nothing edited. Reproduced here with a
# 200-wireframe checkout, where design/process-map.html is written before its model.
set -uo pipefail
LIB="${1:?usage: test-render-fresh.sh /path/to/render-fresh.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/renderfresh.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
. "$LIB"
g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
at() { GIT_COMMITTER_DATE="$1 +0000" GIT_AUTHOR_DATE="$1 +0000"; export GIT_COMMITTER_DATE GIT_AUTHOR_DATE; }

# --- origin repo: map committed together with its model and many wireframes
O="$WORK/origin"; mkdir -p "$O/design/wireframes"; git init -q "$O"
echo map > "$O/design/process-map.html"; echo model > "$O/design/process-model.json"
for i in $(seq 1 200); do head -c 6000 /dev/urandom | base64 > "$O/design/wireframes/w$i.html"; done
at 1700000000; g "$O" add -A; g "$O" commit -qm one

# 1. fresh clones: never stale, however the checkout ordered its writes (repeat to cross ticks).
#    NEGATIVE CONTROL: on the same clones plain `-ot` must read stale at least once, or the clones
#    here did not reproduce the defect (a filesystem that stamps a checkout in one tick) -> SKIP.
bad_n=0; ot_n=0
for i in 1 2 3; do
  rm -rf "$WORK/c"; git clone -q "$O" "$WORK/c"
  C="$WORK/c/design"; mxtk_render_memo_reset
  [ "$C/process-map.html" -ot "$C/process-model.json" ] && ot_n=$((ot_n+1))
  mxtk_render_is_stale "$C/process-map.html" "$C/process-model.json" && bad_n=$((bad_n+1))
  for w in "$C"/wireframes/*.html; do
    [ "$C/process-map.html" -ot "$w" ] && ot_n=$((ot_n+1))
    mxtk_render_is_stale "$C/process-map.html" "$w" && { bad_n=$((bad_n+1)); break; }
  done
done
[ "$bad_n" -eq 0 ] && ok "fresh clone x3: map not stale vs model or any of 200 wireframes" || bad "fresh clone read stale $bad_n time(s)"
[ "$ot_n" -gt 0 ] && ok "negative control: plain -ot read stale $ot_n time(s) on these clones" \
  || echo "  SKIP negative control: this filesystem stamped the checkouts in one tick, so the defect did not reproduce here"

# 2. source edited in the working tree after the render -> stale
mxtk_render_memo_reset; sleep 1.1; echo changed > "$C/process-model.json"
mxtk_render_is_stale "$C/process-map.html" "$C/process-model.json" && ok "uncommitted source edit -> stale" || bad "uncommitted source edit not seen"

# 3. source committed in a LATER commit than the render -> stale (clean tree)
mxtk_render_memo_reset; at 1700000600; g "$WORK/c" commit -qam two
mxtk_render_is_stale "$C/process-map.html" "$C/process-model.json" && ok "source in a later commit -> stale" || bad "later-commit source not seen"

# 4. re-rendered and committed after the source -> fresh again, decided by git even though the
#    render's mtime is made OLDER than the source's (so the -ot shortcut cannot answer)
echo map2 > "$C/process-map.html"; at 1700001200; g "$WORK/c" commit -qam three
touch -d '2020-01-01 00:00:00' "$C/process-map.html"; mxtk_render_memo_reset
mxtk_render_is_stale "$C/process-map.html" "$C/process-model.json" && bad "re-rendered map still stale" || ok "render committed after source -> fresh (git path)"

# 4b. the four shapes a naive parse of `git status` / `git log` got wrong (each is stale by -ot too):
#     an untracked dir, a path with a space, a non-ASCII path committed later, a staged rename + edit.
R="$WORK/r4b"; mkdir -p "$R/d"; git init -q "$R"; echo m > "$R/d/model.json"; echo é > "$R/d/ünï.json"; echo r > "$R/d/ren-old.json"
echo map > "$R/d/map.html"; at 1700002000; g "$R" add -A; g "$R" commit -qm base
sleep 1.1
mkdir -p "$R/d/newdir"; echo n > "$R/d/newdir/src.json"                      # untracked file in an untracked dir
echo n > "$R/d/with space.json"                                              # untracked, space in the name
echo é2 > "$R/d/ünï.json"; at 1700002600; g "$R" commit -qam uni            # non-ASCII, committed after the render
git -C "$R" mv d/ren-old.json d/ren-new.json; echo edit >> "$R/d/ren-new.json"  # staged rename + edit
for src in newdir/src.json "with space.json" "ünï.json" "ren-new.json"; do
  mxtk_render_memo_reset
  mxtk_render_is_stale "$R/d/map.html" "$R/d/$src" && ok "4b: '$src' newer than the render -> stale" || bad "4b: '$src' read fresh"
done

# 5. no git at all: whole-second mtimes. Same-second writes are fresh; a later source is stale.
N="$WORK/plain"; mkdir -p "$N"; echo a > "$N/r.html"; echo b > "$N/s.md"
touch -d '2026-01-01 00:00:00.100' "$N/r.html"; touch -d '2026-01-01 00:00:00.900' "$N/s.md"
mxtk_render_is_stale "$N/r.html" "$N/s.md" && bad "same-second writes read stale (no git)" || ok "no git: same-second writes -> fresh"
touch -d '2026-01-01 01:00:00' "$N/s.md"
mxtk_render_is_stale "$N/r.html" "$N/s.md" && ok "no git: source an hour later -> stale" || bad "no git: later source not seen"

echo "render-fresh: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
