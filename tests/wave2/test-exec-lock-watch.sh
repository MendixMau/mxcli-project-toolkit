#!/usr/bin/env bash
# test-exec-lock-watch.sh — exec.sh's per-project lock, --commit-first, and the watch-compat advisory.
#
# Usage: bash tests/wave2/test-exec-lock-watch.sh [path-to-exec.sh]
#
# WHY (field run 2026-10-12, 20 UX tasks over three apps; #287, #284, #275, #289): 57 of 148
# exec.sh runs applied nothing — 26 refused on "uncommitted model changes" — and a machine-wide
# `pgrep "mxcli exec"` guard blocked an exec because a DIFFERENT project's test run was writing.
# Watch mode then silently missed a class of changes (~26 restarts), and nobody could tell a
# stale runtime from a defect.
#
# Covers
#   lock:   a live exec.sh on this project refuses the second (nothing written); a lock from a
#           dead pid is taken over with a note (new format AND the old bare-pid format); a lock
#           whose pid was reused by an unrelated process is stale; a live exec.sh on ANOTHER
#           project does not block; a running `mxcli exec` elsewhere does not block (note only);
#           the lock is gone after the run.
#   commit: the refusal names --commit-first; --commit-first commits exactly the model paths and
#           leaves an unrelated staged file staged and an unrelated edit uncommitted; it refuses
#           while Studio Pro holds the model even under FORCE_EXEC.
#   watch:  --watch-compat over REAL MDL (the toolkit's shipped scripts and fixtures; the two
#           statements not found in any shipped script are grepped out of the bug log / pending
#           issue that recorded them verbatim); the post-exec line in a real run; theme SCSS
#           newer than the run --local record (the captured handshake fixture) means restart.
#   #686:   E1 a restart-class script that changed nothing in the model (model-scope.py: 0 real)
#           asks for no restart; E2 the same script that did change it still does; E3 a full gate
#           built in place with an app recorded asks app-restart.sh --if-client-gone and reports the
#           restart done; E4 a full gate built in the copy (.mxtk/build/) asks nothing.
#
# NOTHING here touches a real .mpr, mxcli, mxbuild or app. Throwaway git repos with stubs, as
# in test-bug07-08.sh.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/execlock.XXXXXX")" || exit 2
BG_PIDS=""
cleanup() { for p in $BG_PIDS; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -5)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"

# ── Fixture projects ─────────────────────────────────────────────────────────
mkproj() {  # $1 = dir
  local P="$1"
  mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  printf 'bson\n' > "$P/mprcontents/a.mxunit"
  printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/exec.sh"
  cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
sleep "${SNAP_SLEEP:-0}"
if [ -n "${CS_DIR:-}" ]; then   # critical-section probe for the race case: who else is in here?
  : > "$CS_DIR/in.$$"; ls "$CS_DIR" | grep -c '^in\.' >> "$CS_DIR/counts"; sleep 0.3; rm -f "$CS_DIR/in.$$"
fi
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
  cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) exit 0 ;; exec) echo "fake mxcli exec"; exit 0 ;; esac
exit 0
MXCLI
  chmod +x "$P/bin/"*.sh "$P/mxcli"
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
chmod +x "$WORK/mxbuild"
P="$WORK/proj"; Q="$WORK/other"; mkproj "$P"; mkproj "$Q"
LOCK="$P/.mpr-snapshots/.exec.lock"

run() {  # $1 = project, rest = exec.sh args; prints output, returns rc
  ( cd "$1" && shift && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "$@" ) 2>&1
}
bg_hold() {  # $1 = project — start an exec.sh that holds its lock ~8 s; echoes its pid
  ( cd "$1" && exec env SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 SNAP_SLEEP=8 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/bg.out" 2>&1 &
  echo $!
}
wait_lock() { local i; for i in $(seq 1 50); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }
dead_pid() { sh -c 'exit 0' & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }

echo "-- lock: live holder on THIS project refuses"
H="$(bg_hold "$P")"; BG_PIDS="$BG_PIDS $H"
if wait_lock "$LOCK"; then
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -ne 0 ] && ok "second exec refused while the first holds the lock (rc $RC)" || bad "second exec ran concurrently (rc 0)"
  has  "refusal names the holder pid" "$OUT" "PID $H"
  has  "refusal says no manual rm is needed" "$OUT" "no manual rm"
  hasnt "the refused run wrote nothing" "$OUT" "fake mxcli exec"
else
  bad "[setup] background exec never took the lock"
fi

echo "-- other project not blocked by a live exec.sh here"
OUT="$(run "$Q" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "exec on another project ran while this one is locked" || bad "another project was blocked (rc $RC): $(printf '%s' "$OUT" | tail -3)"
kill -KILL "$H" 2>/dev/null; wait "$H" 2>/dev/null

echo "-- lock: dead holder is taken over (the SIGKILL above left it behind)"
[ -f "$LOCK" ] && ok "[setup] SIGKILLed run left its lock" || bad "[setup] no lock left behind — case proves nothing"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "exec ran over a stale lock (rc 0)" || bad "stale lock blocked (rc $RC): $(printf '%s' "$OUT" | tail -3)"
has "takeover is said out loud" "$OUT" "taking it over"
has "the run actually wrote" "$OUT" "fake mxcli exec"
[ -f "$LOCK" ] && bad "lock left behind after a clean run" || ok "lock removed after the run"

echo "-- lock: 12 contenders against one stale lock — never more than one holder (#304 review)"
# The takeover used to move the stale lock aside and put it back with mv -f when it found a
# fresh one: check-then-act. With >=3 contenders, B moved A's fresh lock aside, C's noclobber
# write landed in the gap, B saw -e $LOCK and deleted A's lock — up to 3 holders at once.
RACE_BAD=0; RACE_ENTERED=0; ROUNDS=10; N=12
for round in $(seq 1 $ROUNDS); do
  CS="$WORK/cs.$round"; mkdir -p "$CS"; GO="$WORK/go.$round"
  printf '%s 1700000000 old.mdl\n' "$(dead_pid)" > "$LOCK"
  PIDS=""
  for c in $(seq 1 $N); do
    ( cd "$P" && while [ ! -e "$GO" ]; do sleep 0.01; done
      exec env CS_DIR="$CS" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
        MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/test.mdl ) >"$CS/out.$c" 2>&1 &
    PIDS="$PIDS $!"
  done
  sleep 0.3; : > "$GO"
  for p in $PIDS; do wait "$p" 2>/dev/null; done
  [ -s "$CS/counts" ] && RACE_ENTERED=$((RACE_ENTERED+1))
  _max="$(sort -n "$CS/counts" 2>/dev/null | tail -1)"
  if [ "${_max:-0}" -gt 1 ]; then RACE_BAD=$((RACE_BAD+1)); echo "    round $round: $_max holders at once"; fi
  rm -f "$LOCK" "$LOCK.takeover"
done
[ "$RACE_ENTERED" -eq "$ROUNDS" ] && ok "[setup] a contender took the stale lock in every round" \
  || bad "[setup] only $RACE_ENTERED/$ROUNDS rounds had any holder — case proves nothing"
[ "$RACE_BAD" -eq 0 ] && ok "never more than one holder across $ROUNDS rounds of $N contenders" \
  || bad "$RACE_BAD/$ROUNDS rounds had more than one holder in the critical section"
ls "$P/.mpr-snapshots/" | grep -q '\.stale\.' && bad "a .stale.<pid> aside file was left behind" || ok "no aside files left behind"

echo "-- lock: a takeover file left by a killed contender does not block (instrument rule 7)"
printf '%s 1700000000 old.mdl\n' "$(dead_pid)" > "$LOCK"
printf '%s %s\n' "$(dead_pid)" "$(date +%s)" > "$LOCK.takeover"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "dead-pid takeover file cleared, stale lock taken over" "$OUT" "taking it over" \
  || bad "a dead contender's takeover file blocked (rc $RC): $(printf '%s' "$OUT" | tail -3)"
[ -e "$LOCK.takeover" ] && bad "takeover file left behind" || ok "takeover file gone after the run"
printf '%s 1700000000 old.mdl\n' "$(dead_pid)" > "$LOCK"
: > "$LOCK.takeover"; touch -t 202601010000 "$LOCK.takeover"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "an empty takeover file older than a minute is stale too" || bad "empty old takeover file blocked (rc $RC)"
rm -f "$LOCK.takeover"
# A FRESH empty takeover file is a live contender between its create and its write, NOT stale.
# `find -mmin +0` judged it stale within a second, so a third contender got in (review of #324).
printf '%s 1700000000 old.mdl\n' "$(dead_pid)" > "$LOCK"
: > "$LOCK.takeover"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && ok "a fresh empty takeover file is respected: the run waits, then refuses (rc $RC)" \
  || bad "a fresh empty takeover file was judged stale and the run went ahead"
hasnt "  and it did not execute" "$OUT" "fake mxcli exec"
[ -e "$LOCK.takeover" ] && [ ! -s "$LOCK.takeover" ] && ok "  and the contender's takeover file was left in place" \
  || bad "the fresh takeover file was moved or replaced"
rm -f "$LOCK" "$LOCK.takeover"

echo "-- lock: old bare-pid format, dead pid"
dead_pid > "$LOCK"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "pre-change lock format taken over" "$OUT" "taking it over" || bad "old-format stale lock blocked (rc $RC)"

echo "-- lock: pid reused by an unrelated live process"
sleep 30 & S=$!; BG_PIDS="$BG_PIDS $S"
if [ -n "$(ps -o args= -p "$S" 2>/dev/null)" ]; then
  printf '%s 1700000000 old.mdl\n' "$S" > "$LOCK"
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && has "a live non-exec.sh pid is a stale lock" "$OUT" "taking it over" || bad "reused pid blocked (rc $RC)"
else
  ok "[skip] ps -o args= unavailable here — kill -0 alone decides (Git Bash path)"
fi
kill -KILL "$S" 2>/dev/null; wait "$S" 2>/dev/null

echo "-- a raw 'mxcli exec' elsewhere on the machine is a note, not a refusal"
bash -c 'exec -a "mxcli exec /elsewhere/other.mdl" sleep 20' & R=$!; BG_PIDS="$BG_PIDS $R"
sleep 0.3
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "not blocked by another project's raw mxcli exec" || bad "machine-wide block still active (rc $RC)"
if pgrep -f "mxcli exec" >/dev/null 2>&1; then has "  and it is mentioned as a note" "$OUT" "not blocking"; fi   # portability-ok: guarded by its own exit status; no pgrep, no assertion
kill -KILL "$R" 2>/dev/null; wait "$R" 2>/dev/null

echo "-- commit-first"
printf 'edited by studio pro\n' >> "$P/mprcontents/a.mxunit"
printf 'new unit\n' > "$P/mprcontents/b.mxunit"
printf 'unrelated edit\n' > "$P/notes.txt"; ( cd "$P" && git add notes.txt && git -c user.email=t@t -c user.name=t commit -qm notes && printf 'more\n' >> notes.txt )
printf 'unrelated staged\n' > "$P/staged.txt"; ( cd "$P" && git add staged.txt )
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && ok "default unchanged: dirty model refused" || bad "dirty model no longer refused by default"
has "the refusal points at --commit-first" "$OUT" "--commit-first"
HEAD0="$(git -C "$P" rev-parse HEAD)"
OUT="$(run "$P" --commit-first mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "--commit-first committed and executed (rc 0)" || bad "--commit-first failed (rc $RC): $(printf '%s' "$OUT" | tail -4)"
has "prints what it will commit" "$OUT" "mprcontents/b.mxunit"
has "says the other staged path stays out" "$OUT" "1 other staged path"
FILES="$(git -C "$P" diff --name-only "$HEAD0" HEAD | sort | tr '\n' ' ')"
[ "$FILES" = "mprcontents/a.mxunit mprcontents/b.mxunit " ] && ok "commit holds exactly the model paths" || bad "commit holds: $FILES"
git -C "$P" diff --cached --name-only | grep -qx staged.txt && ok "unrelated staged file still staged, not committed" || bad "staged.txt lost its staged state"
git -C "$P" status --porcelain notes.txt | grep -q . && ok "unrelated edit left uncommitted" || bad "notes.txt was committed"
git -C "$P" log -1 --format=%s | grep -q 'before exec.sh test.mdl' && ok "commit message names the script" || bad "commit message: $(git -C "$P" log -1 --format=%s)"

echo "-- commit-first refuses while Studio Pro holds the model"
printf 'sp edit\n' >> "$P/mprcontents/a.mxunit"
sleep 30 & SP=$!; BG_PIDS="$BG_PIDS $SP"
printf '{"ProcessId":%s}\n' "$SP" > "$P/Fixture.mpr.lock"
HEAD1="$(git -C "$P" rev-parse HEAD)"
OUT="$(FORCE_EXEC=1 run "$P" --commit-first mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && ok "refused under FORCE_EXEC (rc $RC)" || bad "committed/executed while SP holds the model"
has "says why" "$OUT" "Studio Pro holds"
[ "$(git -C "$P" rev-parse HEAD)" = "$HEAD1" ] && ok "nothing committed" || bad "a commit was made while SP held the model"
hasnt "nothing executed" "$OUT" "fake mxcli exec"
kill -KILL "$SP" 2>/dev/null; wait "$SP" 2>/dev/null; rm -f "$P/Fixture.mpr.lock"
( cd "$P" && git checkout -q -- mprcontents )

echo "-- leading flags in any order (#306 review): --commit-first --cr CR-NN <script>"
printf 'cr edit\n' >> "$P/mprcontents/a.mxunit"
HEAD2="$(git -C "$P" rev-parse HEAD)"
OUT="$(run "$P" --commit-first --cr CR-07 mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "documented order ran (rc 0)" || bad "--commit-first --cr failed (rc $RC): $(printf '%s' "$OUT" | tail -4)"
has "the CR tag was honoured" "$OUT" "Change request: CR-07"
has "the script that ran is the real one" "$OUT" "fake mxcli exec"
tail -1 "$P/docs/BUILD-LOG.md" 2>/dev/null | grep -q 'cr: CR-07' && ok "BUILD-LOG row carries cr: CR-07" \
  || bad "BUILD-LOG row: $(tail -1 "$P/docs/BUILD-LOG.md" 2>/dev/null)"
[ "$(git -C "$P" rev-list --count "$HEAD2"..HEAD)" = 1 ] && ok "exactly one model commit made" || bad "commits made: $(git -C "$P" rev-list --count "$HEAD2"..HEAD)"
printf 'flag edit\n' >> "$P/mprcontents/a.mxunit"
HEAD3="$(git -C "$P" rev-parse HEAD)"; NSNAP="$(ls "$P/.mpr-snapshots" | grep -c .)"
OUT="$(run "$P" --commit-first --bogus mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 2 ] && ok "a script name starting with -- is refused (rc 2)" || bad "misplaced flag: rc $RC"
has "  and named" "$OUT" "'--bogus'"
[ "$(git -C "$P" rev-parse HEAD)" = "$HEAD3" ] && ok "  before commit-first committed anything" || bad "commit-first committed before the refusal"
[ "$(ls "$P/.mpr-snapshots" | grep -c .)" = "$NSNAP" ] && ok "  and before any snapshot" || bad "a snapshot was taken before the refusal"
hasnt "  and nothing executed" "$OUT" "fake mxcli exec"
( cd "$P" && git checkout -q -- mprcontents )

echo "-- two-tree checkout (.mpr under app/): lock and --commit-first (#304 review; CLAUDE.md field-proof rule 2)"
T="$WORK/twotree"; mkproj "$T"
( cd "$T" && mkdir app && git mv Fixture.mpr app/ && git mv mprcontents app/ \
  && git -c user.email=t@t -c user.name=t commit -qm two-tree ) >/dev/null 2>&1
cat > "$T/bin/snapshot-mpr.sh" <<'SNAP2'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
sleep "${SNAP_SLEEP:-0}"
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$D"; cp app/Fixture.mpr "$D/"; cp -r app/mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP2
chmod +x "$T/bin/snapshot-mpr.sh"
TLOCK="$T/.mpr-snapshots/.exec.lock"
[ -f "$T/app/Fixture.mpr" ] && [ ! -e "$T/Fixture.mpr" ] && ok "[setup] model only under app/" || bad "[setup] two-tree layout not built"
H2="$(bg_hold "$T")"; BG_PIDS="$BG_PIDS $H2"
if wait_lock "$TLOCK"; then
  ok "the lock lives at the project root (.mpr-snapshots/.exec.lock), not under app/"
  OUT="$(run "$T" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -ne 0 ] && has "a second exec is refused on a two-tree checkout" "$OUT" "PID $H2" || bad "two-tree: second exec ran concurrently"
else
  bad "two-tree: background exec never took the lock at $TLOCK"
fi
kill -KILL "$H2" 2>/dev/null; wait "$H2" 2>/dev/null
OUT="$(run "$T" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "two-tree: the SIGKILLed holder's lock is taken over" "$OUT" "taking it over" || bad "two-tree stale lock blocked (rc $RC)"
printf 'edited\n' >> "$T/app/mprcontents/a.mxunit"; printf 'new\n' > "$T/app/mprcontents/b.mxunit"
printf 'unrelated staged\n' > "$T/staged.txt"; ( cd "$T" && git add staged.txt )
OUT="$(run "$T" mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && has "two-tree: a dirty app/ model is refused by default" "$OUT" "app/mprcontents" || bad "two-tree: dirty model under app/ not refused"
TH="$(git -C "$T" rev-parse HEAD)"
OUT="$(run "$T" --commit-first mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "two-tree: --commit-first committed and executed" || bad "two-tree --commit-first failed (rc $RC): $(printf '%s' "$OUT" | tail -4)"
FILES="$(git -C "$T" diff --name-only "$TH" HEAD | sort | tr '\n' ' ')"
[ "$FILES" = "app/mprcontents/a.mxunit app/mprcontents/b.mxunit " ] && ok "two-tree: commit holds exactly app/'s model paths" || bad "two-tree commit holds: $FILES"
git -C "$T" diff --cached --name-only | grep -qx staged.txt && ok "two-tree: unrelated staged file still staged" || bad "two-tree: staged.txt lost its staged state"
[ -e "$TLOCK" ] && bad "two-tree: lock left behind" || ok "two-tree: lock removed after the run"

echo "-- watch-compat over real MDL"
AG="$TOOLKIT/skills/agents-examples"; GAL="$TOOLKIT/examples/stylegallery/mdlsource/gallery"
PFM="$TOOLKIT/tests/wave2/fixtures/page-fidelity-mocks"
wc_() { (cd "$WORK" && bash "$SUBJECT" --watch-compat "$1" 2>&1); }
expect() {  # $1 file  $2 expected prefix  $3 reason substring (or "")  $4 label
  [ -f "$1" ] || { bad "$4 — golden input missing: ${1#$TOOLKIT/}"; return; }
  local o; o="$(wc_ "$1")"
  case "$o" in "$2"*) ;; *) bad "$4 → expected '$2', got: $o"; return ;; esac
  [ -z "$3" ] || case "$o" in *"$3"*) ;; *) bad "$4 → reason '$3' missing: $o"; return ;; esac
  ok "$4 → ${o%% (*}"
}
expect "$AG/tool-write.example.mdl"   "restart needed" "microflow created or recreated" "create or modify microflow (tool-write)"
expect "$GAL/05-demo-data.mdl"        "restart needed" "entity created or changed"      "non-persistent entities + microflows + grants (05-demo-data)"
expect "$GAL/05-demo-data.mdl"        "restart needed" "access rule changed (GRANT)"    "  and names the grants"
expect "$GAL/00-module.mdl"           "restart needed" "module/user role"               "create module role (00-module)"
expect "$GAL/90-gallery-home.mdl"     "restart needed" "new page"                       "plain create page (90-gallery-home)"
expect "$PFM/bind-contract-alter.mdl" "watch can apply this" "" "alter page set ImageUrl — not a page Url (bind-contract-alter)"
expect "$GAL/13-badges-chips.mdl"     "watch can apply this" "" "create snippet (13-badges-chips)"
expect "$AG/agent-snippet.example.mdl" "watch can apply this" "" "create or modify snippet with comments (agent-snippet)"
# Statements no shipped script contains, taken verbatim from where a real run recorded them.
grep -m1 -oE 'alter entity M\.Item add attribute Flag: Boolean;' \
  "$TOOLKIT/bug-logs/pending-github-issues/exec-non-transactional-silent-skip.md" > "$WORK/attr.mdl"
[ -s "$WORK/attr.mdl" ] && expect "$WORK/attr.mdl" "restart needed" "attribute added" "alter entity ... add attribute (pending issue, verbatim)" \
                        || bad "golden 'alter entity ... add attribute' line not found in the pending issue"
grep -q 'alter page … { set Url = '"'"'…'"'"'; }' "$TOOLKIT/bug-logs/mxcli-bugs.md" \
  && ok "[golden] bug log records 'alter page … { set Url = '…'; }' as a working statement" \
  || bad "[golden] the set Url row is gone from bug-logs/mxcli-bugs.md"
printf "alter page Shop.Order_Overview { set Url = 'orders'; }\n" > "$WORK/url.mdl"
expect "$WORK/url.mdl" "restart needed" "page URL" "alter page { set Url = ... } (bug-log shape)"
printf -- "-- create microflow Shop.ACT_X in a comment\nalter page Shop.P { set Caption = 'create microflow X; grant' on t1 }\n" > "$WORK/noise.mdl"
expect "$WORK/noise.mdl" "watch can apply this" "" "comments and string literals never count"
# Only ui-loop.md's watch-safe list may say "watch can apply this" (#304 review). Statements on
# neither column are `unknown`. Real MDL where the repo has it: a shipped repro script, the
# workflow example, a bug-log transcript, a captured DESCRIBE NAVIGATION.
UNK="unknown — restart if behaviour looks stale"
expect "$TOOLKIT/fixtures/import-mapping-range-repro/flip.mdl" "restart needed" "microflow" \
  "associations + import mapping + microflow (flip.mdl) → the microflow still wins"
grep -m1 -E '^create association RenA\.Item_Owner from RenA\.Item to RenA\.Owner;' \
  "$TOOLKIT/bug-logs/pending-github-issues/rename-module-leaves-xpath.md" > "$WORK/assoc.mdl"
[ -s "$WORK/assoc.mdl" ] && expect "$WORK/assoc.mdl" "$UNK" "create association" "create association (pending issue, verbatim)" \
                         || bad "golden 'create association' line not found"
awk '/^CREATE ENUMERATION /{p=1} p{print} p&&/^\);/{exit}' "$TOOLKIT/skills/build/workflow-example.mdl" > "$WORK/enum.mdl"
[ -s "$WORK/enum.mdl" ] && expect "$WORK/enum.mdl" "$UNK" "CREATE ENUMERATION" "create enumeration (workflow-example.mdl)" \
                        || bad "golden CREATE ENUMERATION block not found"
awk '/^create java action Test\.JA_WithTypeParam/{p=1} p{print} p&&/^\$\$;/{exit}' \
  "$TOOLKIT/bug-logs/pending-github-issues/bug87-describe-java-action-type-param-name.md" > "$WORK/ja.mdl"
[ -s "$WORK/ja.mdl" ] && expect "$WORK/ja.mdl" "$UNK" "create java action" "create java action with a \$\$ body (bug87, verbatim)" \
                      || bad "golden create java action block not found"
expect "$TOOLKIT/tests/wave2/fixtures/design-audit-nav/describe-navigation-responsive.txt" "$UNK" "navigation" \
  "create or replace navigation (captured DESCRIBE NAVIGATION output)"
# No shipped file holds these two; written from the statement grammar in mxcli's generated
# project CLAUDE.md (ALTER ENTITY ... MODIFY, CREATE CONSTANT) — no capture exists to take them from.
printf 'alter entity Shop.Order modify attribute Note: String(500);\n' > "$WORK/modattr.mdl"
expect "$WORK/modattr.mdl" "$UNK" "modify attribute" "alter entity ... modify attribute (no ADD) is not watch-safe"
printf "create constant Shop.ApiBase type String default 'https://example.invalid';\n" > "$WORK/const.mdl"
expect "$WORK/const.mdl" "$UNK" "create constant" "create constant"
# Neutral for the watch verdict: a move into a folder (verbatim from a pending issue) next to a
# watch-safe page edit stays "watch can apply this".
{ grep -m1 -E "^move page RenA\.Other to folder 'Pages/Same';" \
    "$TOOLKIT/bug-logs/pending-github-issues/rename-page-renames-folder.md"; cat "$PFM/bind-contract-alter.mdl"; } > "$WORK/movefolder.mdl"
grep -q '^move page' "$WORK/movefolder.mdl" && expect "$WORK/movefolder.mdl" "watch can apply this" "" "move page ... to folder + alter page is not 'unknown'" \
  || bad "golden 'move page ... to folder' line not found"

echo "-- watch-compat in a real run"
cp "$GAL/05-demo-data.mdl" "$P/mdlsource/demo.mdl"
OUT="$(run "$P" mdlsource/demo.mdl)"; RC=$?
has "post-exec line says restart needed" "$OUT" "→ Watch: restart needed"
has "post-exec line points at the scoped restart helper" "$OUT" "./bin/app-restart.sh"
has "and at ui-loop.md for the table and the symptoms" "$OUT" "skills/ui-loop.md"
OUT="$(run "$P" mdlsource/test.mdl)"
hasnt "a module-only script is not called restart" "$OUT" "restart needed"
# Theme SCSS newer than the running app's boot (handshake = the captured run-local.json).
mkdir -p "$P/.mxcli" "$P/themesource/shop/web"
sed -e "s|^  \"pid\": [0-9]*|  \"pid\": $$|" -e 's/^  "adminPass": "[^"]*"/  "adminPass": "x"/' \
  "$TOOLKIT/tests/wave2/fixtures/run-local/run-local.json" > "$P/.mxcli/run-local.json"
touch -t 202601010000 "$P/.mxcli/run-local.json"
printf '.x{color:red}\n' > "$P/themesource/shop/web/main.scss"
cp "$PFM/bind-contract-alter.mdl" "$P/mdlsource/page.mdl"
( cd "$P" && git add mdlsource themesource && git -c user.email=t@t -c user.name=t commit -qm s ) >/dev/null 2>&1
OUT="$(run "$P" mdlsource/page.mdl)"
has "a page-only script after an SCSS edit → restart, naming the file" "$OUT" "themesource/shop/web/main.scss"
touch "$P/.mxcli/run-local.json"
OUT="$(run "$P" mdlsource/page.mdl)"
has "same script, SCSS older than the boot → watch applies it" "$OUT" "→ Watch: watch can apply this"

echo "-- #686: restart only when the change needs it"
# model-scope.py counts what this exec changed against HEAD (the model was committed when it
# started). The stub `mxcli exec` writes nothing unless FAKE_WRITE=1, so a GRANT-carrying script
# re-applied (the second run of "exec every change twice") changed nothing: no restart for it.
cp "$TOOLKIT/project-bin/model-scope.py" "$TOOLKIT/project-bin/mxpatch.py" "$TOOLKIT/project-bin/mxunit_bson.py" "$P/bin/"
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) exit 0 ;; exec) echo "fake mxcli exec"; [ -n "${FAKE_WRITE:-}" ] && printf 'x' >> mprcontents/a.mxunit; exit 0 ;; esac
exit 0
MXCLI
chmod +x "$P/mxcli"
cp "$GAL/05-demo-data.mdl" "$P/mdlsource/grant.mdl"
( cd "$P" && git add mdlsource bin && git -c user.email=t@t -c user.name=t commit -qm grant ) >/dev/null 2>&1
OUT="$(run "$P" mdlsource/grant.mdl)"
has "E1 restart-class script that changed nothing → no restart for it" "$OUT" "→ Watch: no restart for this exec — it changed nothing in the model (0 unit file(s) changed, 0 real"
hasnt "E1   and no restart prompt" "$OUT" "restart needed"
has "E1   an earlier exec's restart still stands" "$OUT" "A restart an earlier exec asked for still stands"
OUT="$(FAKE_WRITE=1 run "$P" mdlsource/grant.mdl)"
has "E2 the same script when it did change the model → restart needed, naming the grants" "$OUT" "→ Watch: restart needed: "
has "E2   (the grants)" "$OUT" "access rule changed (GRANT)"
hasnt "E2   no 'nothing changed'" "$OUT" "changed nothing in the model"
( cd "$P" && git add -A mprcontents && git -c user.email=t@t -c user.name=t commit -qm w ) >/dev/null 2>&1
# A full gate with an app recorded: exec asks app-restart.sh --if-client-gone (stubbed here; its
# own behaviour is tests/wave2/test-app-readiness.sh). When it restarted the app, the restart this
# script needs is done and exec says so instead of asking for another.
cat > "$P/bin/app-restart.sh" <<'AR'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/../.ar-calls"
echo "→ app-restart: after the full build :8180 is not serving (client bundle → HTTP 404)."
echo "  The toolkit started this app (pid 4242), so it restarts it now."
echo "✓ app-restart: serving on :8180 after 3s — bundle http://127.0.0.1:8180/dist/index.js answers"
AR
chmod +x "$P/bin/app-restart.sh"
OUT="$(FAKE_WRITE=1 run "$P" mdlsource/grant.mdl)"
if grep -q -- '--if-client-gone' "$P/.ar-calls" 2>/dev/null; then
  ok "E3 a full gate with an app recorded asks app-restart.sh --if-client-gone"
  has "E3   its answer is shown" "$OUT" "so it restarts it now"
  has "E3   the script's own restart is reported done, not asked again" "$OUT" "done: the app was restarted after the full build"
  hasnt "E3   no second restart prompt" "$OUT" "Restart this app only"
else
  bad "E3 app-restart.sh --if-client-gone was not called after the full gate: $(printf '%s' "$OUT" | grep -iE 'gate|watch|full' | tail -4)"
fi
( cd "$P" && git add -A mprcontents && git -c user.email=t@t -c user.name=t commit -qm w2 ) >/dev/null 2>&1
# E3 is the in-place case (no bin/build-tree.py here). Installed, the gate builds a copy under
# .mxtk/build/ and the app's deployment/ is not touched, so there is no client to check (#686).
rm -f "$P/.ar-calls"; cp "$TOOLKIT/project-bin/build-tree.py" "$P/bin/"
( cd "$P" && git add bin && git -c user.email=t@t -c user.name=t commit -qm bt ) >/dev/null 2>&1
OUT="$(FAKE_WRITE=1 run "$P" mdlsource/grant.mdl)"
has "E4 with build-tree.py the full gate builds the copy" "$OUT" "full build ran in .mxtk/build/"
[ -f "$P/.ar-calls" ] && bad "E4 app-restart.sh was asked about a client the build never touched" || ok "E4 no client check, no restart after a build in the copy"
has "E4 the script's own restart need is still reported" "$OUT" "→ Watch: restart needed: "
[ ! -e "$P/.mpr-snapshots/.build.lock" ] && ok "E4 the copy's build lock is gone after the exec" || bad "E4 exec left .mpr-snapshots/.build.lock behind"
rm -f "$P/bin/app-restart.sh" "$P/.ar-calls" "$P/bin/build-tree.py"
( cd "$P" && git add -A mprcontents bin && git -c user.email=t@t -c user.name=t commit -qm w3 ) >/dev/null 2>&1

echo "-- lint-gate's SEC014 note reaches a clean exec (#312)"
# The note line is lint-gate.sh's own text in PR #312 (project-bin/lint-gate.sh, stderr, rc 0).
cat > "$P/bin/lint-gate.sh" <<'LG'
#!/usr/bin/env bash
echo "note: SEC014 not configured — set .claude/lint-config.yaml rules: SEC014: options: external_roles (ask the user; 'none' is their decision)" >&2
echo "PASS: no rule rose vs baseline"
exit 0
LG
chmod +x "$P/bin/lint-gate.sh"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "clean lint run still exits 0" || bad "lint note changed the exit code (rc $RC)"
has "the SEC014 note is shown on a clean run" "$OUT" "    note: SEC014 not configured"
has "  and the run still reports lint clean" "$OUT" "lint: no rule rose"
rm -f "$P/bin/lint-gate.sh"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
