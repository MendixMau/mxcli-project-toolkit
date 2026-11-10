#!/usr/bin/env bash
# test-scratch.sh — run `mxcli test` on a scratch COPY of the model, under a lock on the test ports.
#
#   ./bin/test-scratch.sh [--cold] [--no-cache] [--per-file] [--keep] [--ports "8081 8091"] -- <mxcli test args, without -p>
#   e.g. ./bin/test-scratch.sh -- tests/unit/Orders.test.mdl --local
#        ./bin/test-scratch.sh -- tests/unit --local        (every file in ONE boot; see SPEED)
#
# Exit: mxcli's own exit code · 2 usage, or bin/_common.sh older than this script · 3 refused (nothing copied or run)
#
# WHY (#278, field run 2026-10-12; testing-shape.md § "mxcli test --local does NOT leave a warm
# run --local app alone"). `mxcli test` injects a TestRunner, sets security off, builds into
# <app dir>/deployment and restores — all in the LIVE project. One unlocked run in the live repo
# broke the running app (NoClassDefFoundError) with the .mpr unchanged; the remedy that worked was
# a scratch copy of the project plus a lock around the fixed test ports, and it lived only in that
# run's private helper. This is that helper:
#   1. takes this project's exec lock (.mpr-snapshots/.exec.lock, the same file and format as
#      exec.sh) for the COPY only, so the copy is never a half-written model — a live exec.sh
#      refuses this, a dead holder is taken over;
#   2. copies the model tree to a scratch dir, leaving out .git, .mpr-snapshots, deployment and
#      .mxcli (the last holds the LIVE app's run --local record; a copy carrying it would point
#      app-restart.sh and test-stack-up.sh at the live app);
#   3. takes a MACHINE-wide lock on the test ports (they are machine-global: two test runs on one
#      machine collide on 8081/8091 whatever project they belong to), refusing while another live
#      holder has it and taking over a dead one;
#   4. runs `mxcli test <args> -p <scratch>.mpr` in the scratch dir, then releases both and deletes
#      the copy (--keep leaves it, and says where).
# Refused (exit 3, nothing copied) when the live model's after-startup is still an mxcli test injection
# (MxTest.RegisterEndpoint / MxTest.TestRunner, left by a run stopped by a signal — #244, BUG-157):
# the copy would carry it and the test runtime would recurse in its after-startup. The repair is printed.
# --attach is refused: it hot-applies into the live app and runs against its database, which is
# the opposite of a scratch run. Never touches the live model, the live app, or Studio Pro.
#
# SPEED (measured on a 2750-unit app, 4 files / 15 tests: ~95-175 s per file, 44-250 ms of tests):
#   ONE BOOT. Several test files (*.test.mdl or *.test.md, or a directory of them) in one call boot
#     once, not once per file. Default. A file with `@cleanup none`, or one that bin/rollback-scan.sh
#     (when the project has it) says reaches an effect a rollback does not undo, gets a boot of its own
#     (printed). ONE --constant set serves the whole call and the script cannot tell that two files
#     need different values: put such files in separate calls yourself. --per-file (or
#     MXTK_TEST_ONE_BOOT=0) gives every file its own boot.
#   WARM COPY. The copy lives on between runs (<scratch dir>/<App>-test-cache.<hash>) and keeps its
#     .mxcli (unit index) and deployment/ (build output), so a later run skips the ~1.5 min unit-index
#     rebuild and the full copy; the model itself is re-synced from the live project every run (rsync),
#     the live .mxcli/run-state is never copied (mprcontents/ and the .mpr are compared by checksum). It
#     is dropped and rebuilt cold when: --cold (or MXTK_TEST_COLD=1) · the mxcli or Mendix version
#     changed · userlib/, javasource/ or widgets/ changed (names + sizes) · it is older than
#     MXTK_TEST_CACHE_DAYS (7) · an earlier run on it did not finish (in-progress marker) · an
#     interrupted run left a test injection in it. deployment/model.mda is deleted before every boot,
#     so a failed build can never run the tests against an earlier one. One run at a time per copy: a second run waits
#     (MXTK_TEST_LOCK_WAIT, 300 s) and then uses a private cold copy. The gate (build complete, before
#     a deploy) runs --cold. --no-cache (or MXTK_TEST_CACHE=0) is the old behaviour: a throwaway copy, deleted after.
# Bash 3.2 / Git Bash / macOS / Linux; no flock (absent on macOS and Git Bash).
set -uo pipefail
. "$(dirname "$0")/_common.sh"

KEEP=0; PORTS="${MXTK_TEST_PORTS:-8081 8091}"
CACHE="${MXTK_TEST_CACHE:-1}"; COLD="${MXTK_TEST_COLD:-0}"; ONE_BOOT="${MXTK_TEST_ONE_BOOT:-1}"
CACHE_DAYS="${MXTK_TEST_CACHE_DAYS:-7}"
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)  KEEP=1 ;;
    --cold)  COLD=1 ;;
    --no-cache) CACHE=0 ;;
    --per-file) ONE_BOOT=0 ;;
    --ports) shift; PORTS="${1:-}" ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,9p;/^# SPEED/,/^# Bash 3.2/p' "$0"; exit 0 ;;
    *) break ;;
  esac
  shift
done
# --keep is for the throwaway copy; the warm copy is kept anyway. Say so rather than ignore the flag.
[ "$KEEP" = 1 ] && [ "$CACHE" = 1 ] && echo "→ test-scratch: --keep has no effect on the warm copy (it is always kept, its path is printed); --no-cache --keep keeps a throwaway copy" >&2
[ $# -gt 0 ] || { echo "usage: $0 [--cold] [--no-cache] [--per-file] [--keep] [--ports \"8081 8091\"] -- <mxcli test args>" >&2; exit 2; }
for _a in "$@"; do
  case "$_a" in
    --attach) echo "✗ test-scratch: --attach runs against the LIVE app and its database — not a scratch run. Use mxcli test --attach directly, deliberately, and restart the app after (testing-shape.md)." >&2; exit 3 ;;
    -p|--project|-p=*|--project=*) echo "✗ test-scratch: do not pass -p; the scratch copy's .mpr is passed for you." >&2; exit 2 ;;
  esac
done

MPR="$(find_mpr)" || exit 2
MODEL_DIR="$(find_model_dir 2>/dev/null || dirname "$MPR")"
MPR_NAME="$(basename "$MPR")"
[ -f "$MODEL_DIR/$MPR_NAME" ] || MODEL_DIR="$(cd "$(dirname "$MPR")" && pwd)"
if [ -x "$PROJECT_ROOT/mxcli" ]; then MXCLI="$PROJECT_ROOT/mxcli"
elif [ -x "$MODEL_DIR/mxcli" ]; then MXCLI="$MODEL_DIR/mxcli"
elif command -v mxcli >/dev/null 2>&1; then MXCLI="$(command -v mxcli)"
else echo "✗ test-scratch: no mxcli (project root or PATH)." >&2; exit 3; fi

# Test files named in the arguments (a *.test.mdl / *.test.md, or a directory of them); everything else
# (flags, --constant) is REST and goes to every call unchanged. Collected before any lock or copy: a
# directory with no test files in it is a mistake to report, not an empty mxcli call to make.
FILES=(); REST=()
for _a in "$@"; do
  case "$_a" in
    *.test.mdl|*.test.md) if [ -f "$MODEL_DIR/$_a" ] || [ -f "$_a" ]; then FILES+=("$_a"); continue; fi ;;
    -*) ;;
    *) if [ -d "$MODEL_DIR/$_a" ]; then
         _before=${#FILES[@]}
         while IFS= read -r _f; do FILES+=("${_f#"$MODEL_DIR"/}"); done < <(find "$MODEL_DIR/$_a" -type f \( -name '*.test.mdl' -o -name '*.test.md' \) | LC_ALL=C sort)
         [ "${#FILES[@]}" -gt "$_before" ] || { echo "✗ test-scratch: $_a/ holds no *.test.mdl or *.test.md files — nothing to run." >&2; exit 2; }
         continue
       fi ;;
  esac
  REST+=("$_a")
done

# ── After-startup left on an mxcli test injection (#244, BUG-157) ───────────
# The reader and the refusal (mxtest_after_startup / mxtest_left / mxtest_refusal) live in
# _common.sh, shared with app-restart.sh. A project whose bin/_common.sh predates them stops here
# with the remedy, instead of dying on "command not found" — or, worse, reading the failed call as
# "no injection left" and copying a model that recurses in its after-startup.
command -v mxtest_left >/dev/null 2>&1 && command -v mxtest_refusal >/dev/null 2>&1 || {
  echo "test-scratch: bin/_common.sh is older than this script (no mxtest_left / mxtest_refusal)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --only-bin _common.sh --upgrade-bin _common.sh   (installs just that file; backs up a hand-edited copy first)" >&2; exit 2; }

# A model whose after-startup is an mxcli test injection must not be copied and tested: the copy
# carries it, and mxcli test then chains the injection to itself (#244 observation 1).
if mxtest_left "$MODEL_DIR" "$MODEL_DIR/$MPR_NAME"; then
  mxtest_refusal "test-scratch"
  echo "  Nothing was copied or run." >&2
  exit 3
fi

# Same liveness rule as exec.sh's lock: alive, not a zombie, and (where ps can say) one of ours.
holder_live() {
  [ -n "${1:-}" ] || return 1
  case "$1" in *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  _args="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$_args" in ""|*exec.sh*|*test-scratch.sh*) return 0 ;; esac
  return 1
}
# Taking over a stale lock is serialised through a second O_EXCL file, <lock>.takeover — the SAME
# file name and protocol as exec.sh's exec_lock_takeover (this script shares .exec.lock with it, so
# the two must exclude each other; keep the bodies in step). Under it the lock is re-read and
# removed ONLY if it still holds exactly the stale line judged; nothing else ever removes a lock
# that is not its own. WHY (independent review of #304): the old takeover here moved the lock
# aside with `mv -f` — check-then-act — so two runs that judged the same dead holder could both
# end up holding it. A takeover file left by a holder killed mid-takeover is stale once its pid is
# dead or it is older than 10 s (an EMPTY one once it is over a minute old: find -mmin +1); it is moved aside, and put
# back with `ln` (fails if a new one exists — never clobbers) if what was moved is not the one
# judged stale. The machine-wide port lock uses the same protocol.
take_over() {  # $1 = lock file (or lock dir), $2 = the stale lock line, $3 = where that line is read
               # (default $1; a lock dir passes its owner file). 0 iff it was removed (or already gone)
  local _tk="$1.takeover" _t _tpid _tsince _tstale _now _mine
  _mine="$$ $(date +%s)"
  if ! ( set -o noclobber; printf '%s\n' "$_mine" > "$_tk" ) 2>/dev/null; then
    _t="$(head -1 "$_tk" 2>/dev/null || true)"; _tpid="${_t%% *}"; _tsince="${_t#* }"
    case "$_tsince" in ''|*[!0-9]*) _tsince=0 ;; esac
    _tstale=0
    if [ -n "$_t" ]; then
      { ! kill -0 "$_tpid" 2>/dev/null || [ $(( $(date +%s) - _tsince )) -gt 10 ]; } && _tstale=1
    elif [ -n "$(find "$_tk" -mmin +1 2>/dev/null)" ]; then
      # -mmin +1, not +0: GNU find counts a 0-2 s old file as "+0" (and BSD rounds up), so +0 made a
      # FRESH empty takeover file — its creator between the create and the write — stale at once.
      _tstale=1   # empty for over a minute: its creator died between the create and the write
    fi
    if [ "$_tstale" = 1 ]; then
      if mv "$_tk" "$_tk.stale.$$" 2>/dev/null; then
        # Remove what was moved ONLY if it is what was judged stale; anything else is someone's
        # live takeover file: put it back (ln never clobbers), and if that fails leave it be.
        if [ "$(head -1 "$_tk.stale.$$" 2>/dev/null || true)" = "$_t" ]; then rm -f "$_tk.stale.$$"
        else ln "$_tk.stale.$$" "$_tk" 2>/dev/null && rm -f "$_tk.stale.$$"; fi
      fi
    fi
    return 1
  fi
  _now="$(head -1 "${3:-$1}" 2>/dev/null || true)"
  if [ "$_now" = "$2" ]; then
    # a lock dir is renamed away first (atomic), so no mkdir can land in a half-removed one
    if [ -d "$1" ]; then mv "$1" "$1.stale.$$" 2>/dev/null && rm -rf "$1.stale.$$"; else rm -f "$1"; fi
  fi
  [ "$(head -1 "$_tk" 2>/dev/null || true)" = "$_mine" ] && rm -f "$_tk"   # only our own takeover file
  return 0
}
take_lock() {  # $1 = lock file, $2 = what it guards (for messages). 0 = taken, 1 = live holder
  local f="$1" held hpid i
  for i in 1 2 3 4 5 6 7 8; do
    if ( set -o noclobber; printf '%s %s %s\n' "$$" "$(date +%s)" "test-scratch.sh" > "$f" ) 2>/dev/null; then return 0; fi
    held="$(head -1 "$f" 2>/dev/null || true)"
    if [ -z "$held" ] && [ "$i" -lt 3 ]; then sleep 1; continue; fi
    hpid="${held%% *}"
    if holder_live "$hpid"; then
      echo "✗ test-scratch: $2 is held by PID $hpid ($(printf '%s' "$held" | cut -d' ' -f3-)) — wait for it to finish." >&2
      return 1
    fi
    if take_over "$f" "$held"; then
      echo "  (stale lock on $2 from PID ${hpid:-?}, not running — taking it over)"
    else
      sleep 1   # another run is taking the same stale lock over; see who won
    fi
  done
  echo "✗ test-scratch: could not take the lock on $2 after 8 attempts." >&2; return 1
}
# The warm copy's lock is a directory (mkdir is atomic; <dir>/owner names the holder). A dead holder's
# lock goes through take_over above: re-read under <dir>.takeover and removed only if the owner line is
# still the one judged stale. WHY (independent review of #690): the first version read the owner and
# then `mv`'d the dir aside without re-reading it, so two runs that judged the same dead holder could
# both end up holding the warm copy (#304's port-lock race, a second time). 0 = taken; 1 = still held
# by a live run after $2 seconds (DIR_LOCK_HOLDER names it).
take_dir_lock() {
  local d="$1" max="$2" w=0 said=0 h
  DIR_LOCK_HOLDER=""
  while :; do
    if mkdir "$d" 2>/dev/null; then
      printf '%s %s %s\n' "$$" "$(date +%s)" "test-scratch.sh" > "$d/owner"; return 0
    fi
    h="$(head -1 "$d/owner" 2>/dev/null || true)"
    if [ -n "$h" ] && ! holder_live "${h%% *}"; then
      if take_over "$d" "$h" "$d/owner"; then
        echo "  (stale cache lock from PID ${h%% *}, not running, taking it over)"; continue
      fi
    elif [ "$said" = 0 ] && [ "$max" -gt 0 ]; then
      echo "→ test-scratch: another run uses the warm copy (PID ${h%% *}); waiting up to ${max}s"; said=1
    fi
    [ "$w" -ge "$max" ] && { DIR_LOCK_HOLDER="${h%% *}"; return 1; }
    sleep 1; w=$((w+1))
  done
}
release() { local f="$1" own; own="$(head -1 "$f" 2>/dev/null || true)"; [ "${own%% *}" = "$$" ] && rm -f "$f"; return 0; }

EXEC_LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
PORT_LOCK="${TMPDIR:-/tmp}/mxtk-test-ports-$(printf '%s' "$PORTS" | tr -c '0-9' '-').lock"
SCRATCH=""; CLOCK=""
cleanup() {
  release "$EXEC_LOCK"; release "$PORT_LOCK"
  if [ -n "$CLOCK" ]; then release "$CLOCK/owner" ; rm -rf "$CLOCK" 2>/dev/null; fi
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    if [ "$CACHE" = 1 ]; then :   # the warm copy stays for the next run (dropped by --cold, a new mxcli, or age)
    elif [ "$KEEP" = 1 ]; then echo "  scratch copy kept: $SCRATCH"
    else rm -rf "$SCRATCH"; fi
  fi
}
trap cleanup EXIT

# 1+3. Port lock first (machine-wide, cheap to fail), then the project lock for the copy.
take_lock "$PORT_LOCK" "test ports $PORTS" || exit 3
for _p in $PORTS; do
  if curl -s -o /dev/null --max-time 2 "http://localhost:$_p/" 2>/dev/null; then
    echo "✗ test-scratch: :$_p already answers — another test runtime (or app) is up there. Not starting a second." >&2
    exit 3
  fi
done
# The warm copy is ONE directory: two runs (different ports, say) must not rebuild it at once.
# Lock the cache folder itself (mkdir is atomic; <cache>.lock/owner names the holder), for the whole run
# including mxcli. A dead holder's lock is moved aside and taken. Waiting is out loud; after
# MXTK_TEST_LOCK_WAIT seconds this run gives up the cache and builds a private cold copy instead.
if [ "$CACHE" = 1 ]; then
  _key="$(printf '%s' "$MODEL_DIR" | cksum | cut -d' ' -f1)"
  CACHE_DIR="${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}/$(basename "$MPR_NAME" .mpr)-test-cache.$_key"
  mkdir -p "$(dirname "$CACHE_DIR")"
  _max="${MXTK_TEST_LOCK_WAIT:-300}"; case "$_max" in ''|*[!0-9]*) _max=300 ;; esac
  if take_dir_lock "$CACHE_DIR.lock" "$_max"; then CLOCK="$CACHE_DIR.lock"
  else
    echo "→ test-scratch: the warm copy is still in use by PID ${DIR_LOCK_HOLDER:-?} after ${_max}s; this run uses a private cold copy"
    CACHE=0
  fi
fi
mkdir -p "$(dirname "$EXEC_LOCK")"
take_lock "$EXEC_LOCK" "this project's model (an exec.sh is writing it)" || exit 3

# 2. The copy.
# Warm (default): one persistent copy per project that keeps .mxcli (unit index) and deployment/ (build
# output) between runs; the model is re-synced from the live tree each time. Cold, or --no-cache: a fresh
# copy of the model tree without them, as before.
MXCLI_VER="$("$MXCLI" --version 2>/dev/null | head -1)"
WARM=0
# What else makes a kept build wrong: the Mendix version of the model, and the jars/widgets that go into
# the build (a listing of names + sizes of userlib/, javasource/, widgets/).
MX_VER=""
if [ -n "${MXTK_MODEL_VERSION:-}" ]; then MX_VER="$MXTK_MODEL_VERSION"
elif command -v mxtk_model_version >/dev/null 2>&1; then MX_VER="$(mxtk_model_version "$MPR" 2>/dev/null || true)"; fi
LIBS_SIG="$(for _d in userlib javasource widgets; do
  [ -d "$MODEL_DIR/$_d" ] && find "$MODEL_DIR/$_d" -type f | LC_ALL=C sort | while IFS= read -r _f; do printf '%s %s\n' "${_f#"$MODEL_DIR"/}" "$(wc -c < "$_f" | tr -d ' ')"; done
done | cksum | cut -d' ' -f1)"
stamp_new() { printf 'mxcli=%s\nmendix=%s\nlibs=%s\ncreated=%s\n' "$MXCLI_VER" "$MX_VER" "$LIBS_SIG" "$(date +%s)" > "$SCRATCH/.mxcli/test-scratch.stamp"; }
if [ "$CACHE" = 1 ]; then
  SCRATCH="$CACHE_DIR"
  if [ -d "$SCRATCH" ]; then
    _st="$SCRATCH/.mxcli/test-scratch.stamp"
    _cv="$(sed -n 's/^mxcli=//p' "$_st" 2>/dev/null | head -1)"; _ce="$(sed -n 's/^created=//p' "$_st" 2>/dev/null | head -1)"
    _cm="$(sed -n 's/^mendix=//p' "$_st" 2>/dev/null | head -1)"; _cl="$(sed -n 's/^libs=//p' "$_st" 2>/dev/null | head -1)"
    case "$_ce" in ''|*[!0-9]*) _ce=0 ;; esac
    _why=""
    if   [ "$COLD" = 1 ]; then _why="--cold"
    elif [ ! -f "$_st" ]; then _why="no stamp: not made by this script"
    elif [ -e "$SCRATCH/.mxcli/test-scratch.running" ]; then _why="an earlier run on it did not finish"
    elif [ "$_cv" != "$MXCLI_VER" ]; then _why="mxcli changed: $_cv -> $MXCLI_VER"
    elif [ "$_cm" != "$MX_VER" ]; then _why="Mendix version changed: ${_cm:-?} -> ${MX_VER:-?}"
    elif [ "$_cl" != "$LIBS_SIG" ]; then _why="userlib/javasource/widgets changed"
    elif [ $(( $(date +%s) - _ce )) -gt $(( CACHE_DAYS * 86400 )) ]; then _why="older than $CACHE_DAYS days"
    else WARM=1; fi
    [ "$WARM" = 1 ] || { echo "→ test-scratch: dropping the warm copy ($_why); this run builds cold"; rm -rf "$SCRATCH"; }
  fi
  mkdir -p "$SCRATCH/.mxcli" || exit 3
  if [ "$WARM" = 1 ]; then
    # the live app's run record is never in the copy; a record from an interrupted run is removed
    rm -f "$SCRATCH/.mxcli/run-state.json" "$SCRATCH/.mxcli/run-local.json"
    echo "→ test-scratch: warm copy $SCRATCH (model re-synced; .mxcli + deployment kept)"
  else
    stamp_new
    echo "→ test-scratch: cold copy of $(basename "$MODEL_DIR")/ → $SCRATCH (kept for the next run)"
  fi
  copy_model() {
    if command -v rsync >/dev/null 2>&1; then
      # Size + mtime is not proof a model file is unchanged (a same-size rewrite in the same second):
      # the model itself, mprcontents/ and the .mpr, is compared by checksum; the rest by size + time.
      rsync -a --delete --exclude=/.git --exclude=/.mpr-snapshots --exclude=/deployment --exclude=/.mxcli --exclude=/.mxtk \
            --exclude=/node_modules --exclude=/mprcontents --exclude="/$MPR_NAME" "$MODEL_DIR/" "$SCRATCH/" || return 1
      if [ -d "$MODEL_DIR/mprcontents" ]; then rsync -ac --delete "$MODEL_DIR/mprcontents/" "$SCRATCH/mprcontents/" || return 1
      else rm -rf "$SCRATCH/mprcontents"; fi
      rsync -ac "$MODEL_DIR/$MPR_NAME" "$SCRATCH/" || return 1
    else   # no rsync (Git Bash): clear the model tree, keep .mxcli + deployment, copy again
      find "$SCRATCH" -mindepth 1 -maxdepth 1 ! -name .mxcli ! -name deployment -exec rm -rf {} + &&
      tar -C "$MODEL_DIR" --exclude=./.git --exclude=./.mpr-snapshots --exclude=./deployment \
          --exclude=./.mxcli --exclude=./.mxtk --exclude=./node_modules -cf - . | tar -C "$SCRATCH" -xf -
    fi
  }
  if ! copy_model; then echo "✗ test-scratch: copy failed." >&2; exit 3; fi
  # An interrupted run leaves a test injection in its copy. The re-sync overwrites it; if it is still
  # there, this copy is not trusted.
  if [ "$WARM" = 1 ] && mxtest_left "$SCRATCH" "$SCRATCH/$MPR_NAME"; then
    echo "→ test-scratch: the warm copy still holds a test injection; dropping it and building cold"
    rm -rf "$SCRATCH"; WARM=0; mkdir -p "$SCRATCH/.mxcli"; stamp_new
    copy_model || { echo "✗ test-scratch: copy failed." >&2; exit 3; }
  fi
else
  SCRATCH="$(mktemp -d "${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}/$(basename "$MPR_NAME" .mpr)-test.XXXXXX")" || exit 3
  echo "→ test-scratch: copying $(basename "$MODEL_DIR")/ → $SCRATCH (no .git, .mpr-snapshots, deployment, .mxcli, .mxtk)"
  if ! tar -C "$MODEL_DIR" --exclude=./.git --exclude=./.mpr-snapshots --exclude=./deployment \
         --exclude=./.mxcli --exclude=./.mxtk --exclude=./node_modules -cf - . | tar -C "$SCRATCH" -xf -; then
    echo "✗ test-scratch: copy failed." >&2; exit 3
  fi
fi
release "$EXEC_LOCK"
[ -f "$SCRATCH/$MPR_NAME" ] || { echo "✗ test-scratch: $MPR_NAME missing from the copy." >&2; exit 3; }

# 3. Plan the boots. The test files (FILES, collected above) run in ONE `mxcli test` call = one injection,
# one build, one boot; per-test rollback still isolates each test's main transaction. A file with
# `@cleanup none` (rows kept on purpose) would leak into every later test of the boot, so it gets a boot
# of its own. One file, or none at all, is passed through exactly as given.
# Own boot when the file keeps its rows on purpose (@cleanup none, in a .test.mdl or a .test.md), or when
# the project's rollback-scan.sh (it lands with another change; absent = skipped) finds an effect a rollback
# does not undo and others would see (an A line: REST, file, separate commit, queue, mail, workflow).
# B lines (autonumber, log) and U lines (unclassified Java) share the boot. Read from `--json`; the
# scan always exits 0 and prints a summary, so a scan that cannot run means shared boot. About 0.3 s a file.
# The JSON is read with _common.sh's resolve_py (probe by executing; the project-side twin of the
# toolkit's portable.sh, which is not installed into projects). No Python 3 = the scan's answer cannot
# be read, so the file gets its own boot: fail safe, never a silent shared boot.
LEAK_WHY=""; PY=""; PY_PROBED=0
SCAN=""; for _s in "$PROJECT_ROOT/bin/rollback-scan.sh" "$PROJECT_ROOT/project-bin/rollback-scan.sh"; do [ -f "$_s" ] && { SCAN="$_s"; break; }; done
leaky() {
  local _p="$1" _o
  [ -f "$MODEL_DIR/$_p" ] && _p="$MODEL_DIR/$_p"
  if grep -Eq '@cleanup[[:space:]]+none' "$_p" 2>/dev/null; then LEAK_WHY="has @cleanup none"; return 0; fi
  if [ -n "$SCAN" ]; then
    if [ "$PY_PROBED" = 0 ]; then
      PY_PROBED=1; command -v resolve_py >/dev/null 2>&1 && PY="$(resolve_py 2>/dev/null)" || PY=""
    fi
    if [ -z "$PY" ]; then LEAK_WHY="cannot be checked by rollback-scan.sh (no Python 3 to read its answer)"; return 0; fi
    _o="$(cd "$PROJECT_ROOT" && bash "$SCAN" --json "$_p" 2>/dev/null)" || _o=""
    if printf '%s' "$_o" | "$PY" -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
sys.exit(0 if any(e.get("cls")=="A" for e in d.get("effects",[])) else 1)' 2>/dev/null; then
      LEAK_WHY="reaches an effect a rollback does not undo (rollback-scan A line)"; return 0
    fi
  fi
  return 1
}
LEAKY_CALLS=(); CALLS=()   # one entry per boot: its test files, one per line
if [ "${#FILES[@]}" -le 1 ]; then
  CALLS+=("${FILES[0]:-}")
else
  _grp=""
  for _f in "${FILES[@]}"; do
    if [ "$ONE_BOOT" != 1 ]; then CALLS+=("$_f")
    elif leaky "$_f"; then LEAKY_CALLS+=("$_f"); echo "  $_f $LEAK_WHY: its own boot, so its rows cannot reach the other files"
    else _grp="${_grp:+$_grp
}$_f"; fi
  done
  [ -n "$_grp" ] && CALLS+=("$_grp")
  CALLS+=(${LEAKY_CALLS[@]+"${LEAKY_CALLS[@]}"})
  echo "→ test-scratch: ${#FILES[@]} test files → ${#CALLS[@]} boot(s)$( [ "$ONE_BOOT" != 1 ] && echo ' (--per-file)')"
fi

# 4. Run. An in-progress marker in the copy says a run started and did not end: the next run builds cold.
[ "$CACHE" = 1 ] && date +%s > "$SCRATCH/.mxcli/test-scratch.running"
RC=0; _n=0
for _call in "${CALLS[@]}"; do
  _n=$((_n+1)); _args=()
  # A kept build must never stand in for this one: a failed mxbuild would otherwise leave the previous
  # run's model.mda (warm copy, or an earlier boot of this call) for the tests to run against.
  rm -f "$SCRATCH/deployment/model.mda"
  while IFS= read -r _f; do [ -n "$_f" ] && _args+=("$_f"); done <<<"$_call"
  echo "→ $(basename "$MXCLI") test ${_args[@]+"${_args[@]}"} ${REST[@]+"${REST[@]}"} -p $SCRATCH/$MPR_NAME   (ports $PORTS locked$( [ "${#CALLS[@]}" -gt 1 ] && echo "; boot $_n of ${#CALLS[@]}" ))"
  ( cd "$SCRATCH" && "$MXCLI" test ${_args[@]+"${_args[@]}"} ${REST[@]+"${REST[@]}"} -p "$SCRATCH/$MPR_NAME" )
  _rc=$?
  [ "$_rc" -gt "$RC" ] && RC=$_rc
done
rm -f "$SCRATCH/.mxcli/test-scratch.running"
echo "← mxcli test exit $RC — the live model and the live app were not touched."
exit "$RC"
