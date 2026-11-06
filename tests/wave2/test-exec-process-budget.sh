#!/usr/bin/env bash
# Fixture: exec.sh's process-start budget (#687).
#
# usage: bash tests/wave2/test-exec-process-budget.sh [/path/to/exec.sh]
#
# WHY. Between two field copies, exec.sh grew from 819 to 2,289 lines, each step added after a
# real failure, and no release measured what the sum cost per exec (process/roadmap.md RM-02).
# Wall-clock is too noisy to gate in CI; the number of processes one exec starts is not. This
# runs ONE clean MDL exec on a minimal scaffold and counts every process it starts, then
# compares the count with the committed baseline in fixtures/exec-process-budget.txt.
#
#   count > baseline × 1.05   FAIL. Cut a step, move it to module close, or raise the baseline
#                             in that file: the raise is then in the diff, and the reviewer
#                             checks it against the PR body's "Time cost:" line
#                             (docs/RELEASE-PROCESS.md §4a, "Per-row budget").
#   baseline < count ≤ +5%    ok, with a note that the count rose.
#   count < baseline          ok, with a note to lower the baseline (lowering needs no review).
#
# HOW IT COUNTS. A closed PATH: a shim directory holding one forwarding script per tool in
# $FORWARD (each logs its name, then execs the real binary) and logging stubs for mxcli,
# mxbuild, java, sqlite3 and pgrep. Any other command name a bash process looks up is logged by
# an exported command_not_found_handle, so a call to a new tool counts even where the tool is
# absent. Helper scripts (`./bin/x.sh`) count through the `bash` shim their `#!/usr/bin/env bash`
# shebang resolves to. Not counted: forks with no exec (subshells, $(...) of builtins), and
# processes a Python or Node child starts by absolute path. The environment is `env -i` plus
# fixed knobs, so the count does not depend on the runner's tools, git config or other
# processes (sqlite3 and pgrep are stubbed because exec.sh branches on whether they exist and
# pgrep would see the machine's processes). MXTK_SYNC_REFRESH=1 runs exec.sh's background
# build-plan refresh in the foreground: it is a per-exec cost too, and racing it made the count
# vary. Deterministic: identical over repeated runs.
#
# Resolution: the 5% tolerance is about 6 starts. One extra process (a `date`, one `mxcli`
# call) or a whole second lint-gate pass (+6) stays inside it and prints a "rose by N" note;
# a step of 7+ starts fails. Process count is a proxy: one mxbuild is one start and minutes, so
# the reviewer still re-measures seconds for hot-path PRs (CLAUDE.md, "Merging a PR").
#
# Platform: the baseline is a Linux count (the CI runner, ubuntu-latest). On other platforms
# the fixture prints SKIP and exits 0: Git Bash and macOS resolve some tools differently, and a
# second baseline per platform is not worth its upkeep.
#
# Stub inputs: the lint output is the verbatim mxcli v0.28.0 capture in
# fixtures/lint-conv020-v028/ (so lint-gate takes its real parse path); mxbuild writes an empty
# problem list (clean gate); the lint baseline is taken in setup, uncounted; `mxcli exec`
# appends a byte to one unit file (a real write).
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
EXEC_SH="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
BUDGET_FILE="$TOOLKIT/tests/wave2/fixtures/exec-process-budget.txt"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $EXEC_SH"

if [ "$(uname -s 2>/dev/null)" != Linux ]; then
  echo "  SKIP not Linux: the baseline is a Linux count (see header)"; echo; echo "PASS=0 FAIL=0"; exit 0
fi

# Tools forwarded to the real binary. Everything exec.sh's clean path starts today, plus the
# common tools a new step would plausibly add, so adding one costs a count, not a failure.
FORWARD="bash sh env git python3 node awk sed grep egrep tr sort uniq head tail cut wc cat cp mv rm
mkdir rmdir mktemp ls touch uname cksum sha256sum shasum md5sum dirname basename readlink realpath
date sleep find xargs tee chmod ln stat od diff cmp comm tac rev paste printf expr seq id hostname
du df file gzip tar unzip jq perl curl ps kill timeout flock"
REAL_PATH="$PATH"
for t in bash git python3 awk sed grep; do
  command -v "$t" >/dev/null 2>&1 || { echo "  SKIP required tool missing: $t"; echo; echo "PASS=0 FAIL=0"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-pb.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
SHIM="$WORK/shim"; LOG="$WORK/starts.log"; mkdir -p "$SHIM" "$WORK/home" "$WORK/tmp"
REAL_BASH="$(command -v bash)"
for t in $FORWARD; do
  r="$(PATH="$REAL_PATH" command -v "$t" 2>/dev/null)" || continue
  case "$r" in /*) ;; *) continue ;; esac   # a builtin or function, not a binary
  printf '#!%s\nprintf "%%s\\n" %s >> "$MXTK_PCOUNT_LOG"\nexec %s "$@"\n' "$REAL_BASH" "$t" "$r" > "$SHIM/$t"
done
# Logging stubs. sqlite3 answers like a model with an 11.x product version; pgrep finds nothing.
printf '#!%s\nprintf "%%s\\n" sqlite3 >> "$MXTK_PCOUNT_LOG"\necho 11.6.0\n' "$REAL_BASH" > "$SHIM/sqlite3"
printf '#!%s\nprintf "%%s\\n" pgrep >> "$MXTK_PCOUNT_LOG"\nexit 1\n' "$REAL_BASH" > "$SHIM/pgrep"
chmod +x "$SHIM"/*

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude" "$P/mprcontents/84/77" "$P/mdlsource" "$WORK/jdk/bin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
cp "$TOOLKIT"/project-bin/* "$P/bin/" 2>/dev/null
cp "$EXEC_SH" "$P/bin/exec.sh"; chmod +x "$P/bin/"*
printf 'CREATE ENTITY Mod.Thing (Name: String);\n' > "$P/mdlsource/01-Mod-thing.mdl"
LINT_OUT="$TOOLKIT/tests/wave2/fixtures/lint-conv020-v028/lint-conv020-v0.28.0.out"
cat > "$P/mxcli" <<MXCLI
#!$REAL_BASH
printf '%s\n' mxcli >> "\$MXTK_PCOUNT_LOG"
case "\$1" in
  exec) echo "stub exec"; printf 'x\n' >> mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit ;;
  lint) while IFS= read -r l; do printf '%s\n' "\$l"; done < "$LINT_OUT" ;;
esac
exit 0
MXCLI
cat > "$WORK/mxbuild" <<MXB
#!$REAL_BASH
printf '%s\n' mxbuild >> "\$MXTK_PCOUNT_LOG"
for a in "\$@"; do case "\$a" in --write-errors=*) printf '{"problems":[]}' > "\${a#--write-errors=}" ;; esac; done
exit 0
MXB
printf '#!%s\nprintf "%%s\\n" java >> "$MXTK_PCOUNT_LOG"\nexit 0\n' "$REAL_BASH" > "$WORK/jdk/bin/java"
chmod +x "$P/mxcli" "$WORK/mxbuild" "$WORK/jdk/bin/java"
# A lint baseline, as every project has after its first exec: the count is of the steady-state
# path (lint compared against a baseline), not the one-off "no baseline yet" path.
( cd "$P" && MXTK_PCOUNT_LOG=/dev/null ./bin/lint-gate.sh --update-baseline ) > "$WORK/lint-base.out" 2>&1 \
  || { echo "  setup: lint baseline failed"; sed 's/^/       /' "$WORK/lint-base.out"; }
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

run_once() {
  : > "$LOG"
  ( cd "$P" && env -i PATH="$SHIM" HOME="$WORK/home" TMPDIR="$WORK/tmp" LANG=C LC_ALL=C \
      GIT_CONFIG_NOSYSTEM=1 MXTK_PCOUNT_LOG="$LOG" MXTK_ROOT="$TOOLKIT" \
      SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_DOCTOR=1 MXTK_SYNC_REFRESH=1 \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" \
      "$SHIM/bash" -c '
        command_not_found_handle() { printf "%s\n" "?$1" >> "$MXTK_PCOUNT_LOG"; printf "%s: command not found\n" "$1" >&2; return 127; }
        export -f command_not_found_handle
        : > "$MXTK_PCOUNT_LOG"
        exec ./bin/exec.sh mdlsource/01-Mod-thing.mdl' ) > "$WORK/out" 2>&1
}

echo "== one clean MDL exec, process starts counted =="
T0=$SECONDS
run_once; RC=$?
COUNT=$(grep -c . "$LOG")
[ "$RC" -eq 0 ] && ok "exec exit 0 (a clean apply, so the full chain ran)" || bad "exec rc=$RC — the count is of a short path" "$(tail -15 "$WORK/out")"
grep -q '✓ Script applied' "$WORK/out" && ok "script applied" || bad "no 'Script applied' line" "$(tail -15 "$WORK/out")"
grep -q '^mxbuild$' "$LOG" && ok "mxbuild gate ran" || bad "mxbuild never started"

BASELINE="$(grep -E '^[0-9]+$' "$BUDGET_FILE" 2>/dev/null | head -1)"
if [ -z "$BASELINE" ]; then
  bad "no baseline number in $BUDGET_FILE (measured: $COUNT)"
else
  LIMIT=$(( BASELINE + BASELINE * 5 / 100 ))
  echo "  process starts: $COUNT (baseline $BASELINE, fail above $LIMIT); run took $((SECONDS-T0))s"
  if [ "$COUNT" -gt "$LIMIT" ]; then
    bad "process starts $COUNT > $LIMIT (baseline $BASELINE + 5%). Per tool:" \
        "$(sort "$LOG" | uniq -c | sort -rn | head -12)
Cut a step or move it to module close; or raise the number in tests/wave2/fixtures/exec-process-budget.txt
and state the cost in the PR body's 'Time cost:' line (docs/RELEASE-PROCESS.md §4a, Per-row budget)."
  else
    ok "process starts $COUNT within budget ($BASELINE + 5% = $LIMIT)"
    [ "$COUNT" -gt "$BASELINE" ] && echo "  note: rose by $((COUNT-BASELINE)) over the baseline, inside the 5% tolerance"
    [ "$COUNT" -lt "$BASELINE" ] && echo "  note: $((BASELINE-COUNT)) fewer than the baseline — lower it to $COUNT in exec-process-budget.txt (no review needed)"
  fi
fi
[ "${MXTK_PCOUNT_VERBOSE:-0}" = 1 ] && sort "$LOG" | uniq -c | sort -rn

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
