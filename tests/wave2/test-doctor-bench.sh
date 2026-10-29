#!/usr/bin/env bash
# test-doctor-bench.sh: bin/doctor.sh --bench (table, verdict, TSV, read-only), the "Machine health"
# section (leftover mxbuild deno helpers + free memory) and --cleanup (never stops anything without a
# typed y at a terminal).
#
#   usage: bash tests/wave2/test-doctor-bench.sh [bin/doctor.sh]
#
# GOLDEN INPUT (captured, not hand-written; tests/wave2/fixtures/doctor-bench/):
#   ps-eo-pid-ppid-etimes-rss-args.txt  `ps -eo pid,ppid,etimes,rss,args` on a Linux box that really had 46
#       orphaned deno helpers (parent 1) and, at capture time, one LIVE mxbuild with its own deno child
#       (pid 4376 -> 12146, age 1 s), trimmed to those 2+4+2 rows. Expected from it: 4 leftovers (pids
#       2665 8592 8824 28379), 1104860 KB in total, oldest 3421 s.
#   proc-meminfo-head.txt               `head -5 /proc/meminfo` from the same machine (MemAvailable 1824480 kB).
# A fake `ps` on PATH replays the capture and refuses any other argument list, so this also proves doctor
# calls ps exactly the way the capture was taken. The kill path is tested on real throw-away processes
# (copies of sleep named .../modeler/tools/deno/linux-x64/deno), never on anything else.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${1:-$ROOT/bin/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
GOLD="$ROOT/tests/wave2/fixtures/doctor-bench"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doctor-bench.XXXXXX")"
SPAWNED=""
cleanup() { for p in $SPAWNED; do kill "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
export MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" MXTK_DOCTOR_SKIP_DOCKER=1
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
has() { grep -q -- "$2" "$1"; }
chk() { if has "$2" "$3"; then ok "$1"; else bad "$1 (missing: $3)"; sed 's/^/        | /' "$2" | head -25; fi; }
chkno() { if grep -q ${4:-} -- "$3" "$2" 2>/dev/null; then bad "$1 (unexpected: $3)"; else ok "$1"; fi; }

mkdir -p "$WORK/bin" "$WORK/home"
export HOME="$WORK/home"

# fake ps: replays the capture (or, with FAKE_PS_PIDS, the real rows of those throw-away processes)
cat > "$WORK/bin/ps" <<EOS
#!/usr/bin/env bash
if [ "\$*" != "-eo pid,ppid,etimes,rss,args" ]; then echo "fake ps: unexpected arguments: \$*" >&2; exit 1; fi
if [ -n "\${FAKE_PS_PIDS:-}" ]; then exec /bin/ps -o pid,ppid,etimes,rss,args -p "\$FAKE_PS_PIDS"; fi
cat "\${FAKE_PS_FILE:-$GOLD/ps-eo-pid-ppid-etimes-rss-args.txt}"
EOS
chmod +x "$WORK/bin/ps"
# meminfo variants: the captured one (1.7 GB available) and a roomy one built by changing only that number
cp "$GOLD/proc-meminfo-head.txt" "$WORK/meminfo-low"
sed 's/^MemAvailable:.*/MemAvailable:   9000000 kB/' "$GOLD/proc-meminfo-head.txt" > "$WORK/meminfo-high"
sed 's/^MemAvailable:.*/MemAvailable:    400000 kB/' "$GOLD/proc-meminfo-head.txt" > "$WORK/meminfo-tiny"
head -3 "$GOLD/ps-eo-pid-ppid-etimes-rss-args.txt" > "$WORK/ps-clean.txt"

# ---------------------------------------------------------------- fake project and tools for --bench
P="$WORK/proj"; mkdir -p "$P/mprcontents" "$P/.claude" "$WORK/mxdir"
: > "$P/App.mpr"; : > "$P/mprcontents/x"
printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
for t in git python3 node; do printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/$t"; chmod +x "$WORK/bin/$t"; done   # portability-ok: fixture names the tool it fakes / probes, Linux-only pty driver
printf '#!/bin/sh\nexit 0\n' > "$WORK/mxdir/mxbuild"; printf '#!/bin/sh\nexit 3\n' > "$WORK/mxdir/mx"; chmod +x "$WORK/mxdir/mxbuild" "$WORK/mxdir/mx"
export MXBUILD_PATH="$WORK/mxdir/mxbuild"
SAFEPATH="$WORK/bin:/usr/bin:/bin"
snap() { (cd "$1" && find . -type f -not -path './.claude/loop/bench-*' | sort | xargs cksum); }

echo "doctor --bench / machine health / --cleanup: $DOCTOR"

# 1. --bench: table, verdict, TSV, project untouched
snap "$P" > "$WORK/snap.before"
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-high" FAKE_PS_FILE="$WORK/ps-clean.txt" \
  bash "$DOCTOR" --bench "$P" > "$WORK/bench.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "bench: exits 0" || bad "bench: exit $rc"
chk "bench: table header" "$WORK/bench.out" "step  *this machine  *reference  *factor"
for s in "50 process starts" "git status" "python start" "node start" "gate-check (no stage)" "mxcli check (tiny script)" "mx check (copy of model)"; do
  chk "bench: row '$s' with a factor" "$WORK/bench.out" "$s .*[0-9]x\$"
done
chk "bench: verdict line" "$WORK/bench.out" "Verdict: this machine is "
chk "bench: process-start line names the field figure" "$WORK/bench.out" "103 ms on the slow Windows 11"
chk "bench: has the Machine health section" "$WORK/bench.out" "Machine health"
chk "bench: healthy memory is ok" "$WORK/bench.out" "ok    free memory: 8.5 GB"
TSV="$(ls "$P"/.claude/loop/bench-*.tsv 2>/dev/null | head -1)"
if [ -n "$TSV" ]; then
  ok "bench: TSV written to .claude/loop/bench-<timestamp>.tsv"
  [ "$(wc -l < "$TSV" | tr -d ' ')" -eq 8 ] && ok "bench: TSV is header + 7 step rows" || bad "bench: TSV rows: $(wc -l < "$TSV")"
  awk -F'\t' '{ if (NF != 9) exit 1 }' "$TSV" && ok "bench: every TSV row has 9 columns" || bad "bench: ragged TSV"
  for id in spawn50 git python node gate mxcli mx; do cut -f5 "$TSV" | grep -qx "$id" || bad "bench: TSV lacks step $id"; done   # portability-ok: fixture names the tool it fakes / probes, Linux-only pty driver
  head -1 "$TSV" | grep -q '^timestamp.platform.cores.free_mb.step.this_ms.reference_ms.factor.note$' && ok "bench: TSV header" || bad "bench: TSV header"
else bad "bench: no TSV written"; fi
snap "$P" > "$WORK/snap.after"
cmp -s "$WORK/snap.before" "$WORK/snap.after" && ok "bench: project files unchanged (no fresh index.html, no model write)" || { bad "bench: project files changed"; diff "$WORK/snap.before" "$WORK/snap.after" | head; }

# 2. --bench with tools missing and memory too low for mx check
rm -f "$P/mxcli" "$WORK/mxdir/mx"
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-tiny" FAKE_PS_FILE="$WORK/ps-clean.txt" \
  bash "$DOCTOR" --bench "$P" > "$WORK/bench2.out" 2>&1
chk "skip: missing mxcli is said, not hidden" "$WORK/bench2.out" "mxcli check (tiny script): mxcli not found"
chk "skip: missing mx is said" "$WORK/bench2.out" "mx check (copy of model): mx not installed"
printf '#!/bin/sh\nexit 3\n' > "$WORK/mxdir/mx"; chmod +x "$WORK/mxdir/mx"
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-tiny" FAKE_PS_FILE="$WORK/ps-clean.txt" \
  bash "$DOCTOR" --bench "$P" > "$WORK/bench3.out" 2>&1
chk "low memory: mx check not run, and why" "$WORK/bench3.out" "not run: only 390 MB free"
chk "low memory: names the exit 137 failure" "$WORK/bench3.out" "exit 137"
chk "low memory: health WARN" "$WORK/bench3.out" "WARN  free memory: 390 MB"
PATH="$SAFEPATH" bash "$DOCTOR" --bench > "$WORK/bench4.out" 2>&1
chk "no project: says nothing was saved" "$WORK/bench4.out" "Results: not saved"
chk "no project: project steps skipped with a reason" "$WORK/bench4.out" "git status: no project given"

# 3. Machine health from the captured ps: 4 leftovers, the live mxbuild helper is NOT one of them
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-low" bash "$DOCTOR" --bench "$P" > "$WORK/health.out" 2>&1
chk "health: 4 leftovers from the golden capture" "$WORK/health.out" "WARN  4 leftover mxbuild helper process(es) (deno), 1.0 GB in total, oldest 57 min"
chk "health: low memory warning from the golden meminfo" "$WORK/health.out" "WARN  free memory: 1.7 GB (under 2 GB)"
chk "health: explains exit 137" "$WORK/health.out" "kills mxbuild (exit 137)"
chk "health: points at --cleanup" "$WORK/health.out" "bin/doctor.sh --cleanup"
MXTK_LEFTOVER_MIN_AGE_S=0 PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-low" bash "$DOCTOR" --bench "$P" > "$WORK/health0.out" 2>&1
chk "health: age 0 still excludes the helper of a live mxbuild (parent 4376)" "$WORK/health0.out" "WARN  4 leftover"
MXTK_LEFTOVER_MIN_AGE_S=2000 PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-low" bash "$DOCTOR" --bench "$P" > "$WORK/health2.out" 2>&1
chk "health: the age threshold is honoured (2000 s keeps 2 of 4)" "$WORK/health2.out" "WARN  2 leftover"
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-high" FAKE_PS_FILE="$WORK/ps-clean.txt" bash "$DOCTOR" --bench "$P" > "$WORK/healthy.out" 2>&1
chk "health: clean machine says so" "$WORK/healthy.out" "ok    no leftover mxbuild helper processes"
chkno "health: clean machine has no health WARN" "$WORK/healthy.out" "WARN  .*leftover\|WARN  free memory"
# the normal (non-bench) run carries the section too
PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-low" bash "$DOCTOR" --quick "$P" > "$WORK/quick.out" 2>&1
chk "normal run: Machine health section present" "$WORK/quick.out" "^Machine health"
chk "normal run: leftovers warned" "$WORK/quick.out" "WARN  4 leftover mxbuild helper"

# 4. --cleanup, no terminal: prints the command, stops nothing
PATH="$SAFEPATH" bash "$DOCTOR" --cleanup < /dev/null > "$WORK/clean.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "cleanup (no tty): exits 0" || bad "cleanup (no tty): exit $rc"
chk "cleanup (no tty): lists exactly the 4 orphans" "$WORK/clean.out" "pid 28379"
chkno "cleanup (no tty): does not list the live mxbuild's helper" "$WORK/clean.out" "pid 12146"
chk "cleanup (no tty): says nothing was stopped" "$WORK/clean.out" "nothing was stopped"
chk "cleanup (no tty): prints the command" "$WORK/clean.out" "kill 2665 8592 8824 28379\$"

# 5. kill path on real throw-away processes: no tty, 'n' and 'y' at a pty. A bystander must survive.
D="$WORK/fake/modeler/tools/deno/linux-x64"; mkdir -p "$D"; cp "$(command -v sleep)" "$D/deno"; cp "$(command -v sleep)" "$WORK/bystander"
"$D/deno" 300 & P1=$!; "$D/deno" 300 & P2=$!; "$WORK/bystander" 300 & PB=$!; SPAWNED="$P1 $P2 $PB"
sleep 1
# alive: a killed child of this shell stays a zombie until waited for; a zombie is dead for our purposes
alive() { kill -0 "$1" 2>/dev/null && case "$(/bin/ps -o stat= -p "$1" 2>/dev/null)" in Z*|"") return 1 ;; *) return 0 ;; esac; }
export FAKE_PS_PIDS="$P1,$P2,$PB" MXTK_LEFTOVER_MIN_AGE_S=0
PATH="$SAFEPATH" bash "$DOCTOR" --cleanup < /dev/null > "$WORK/k1.out" 2>&1
chk "real procs: no tty lists both helpers" "$WORK/k1.out" "pid $P1 "
chkno "real procs: never lists the bystander" "$WORK/k1.out" "pid $PB "
{ alive $P1 && alive $P2 && alive $PB; } && ok "real procs: no tty stopped nothing" || bad "real procs: no tty stopped something"
cat > "$WORK/ttydrive.py" <<'PYEOF'
import os, pty, select, sys
ans, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf, sent = b"", False
while True:
    r, _, _ = select.select([fd], [], [], 30)
    if not r: break
    try: d = os.read(fd, 4096)
    except OSError: break
    if not d: break
    buf += d
    if b"confirm" in buf and not sent:
        os.write(fd, (ans + "\n").encode()); sent = True
os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
PYEOF
REALPY="$(command -v python3 2>/dev/null || true)"   # before any fake python3 is on PATH: resolved from the caller's PATH   # portability-ok: fixture names the tool it fakes / probes, Linux-only pty driver
if [ -n "$REALPY" ] && "$REALPY" -c 'import pty' 2>/dev/null; then
  PATH="$SAFEPATH" "$REALPY" "$WORK/ttydrive.py" n bash "$DOCTOR" --cleanup > "$WORK/k2.out" 2>&1
  chk "real procs: answering n cancels" "$WORK/k2.out" "Cancelled. Nothing was stopped"
  { alive $P1 && alive $P2 && alive $PB; } && ok "real procs: n stopped nothing" || bad "real procs: n stopped something"
  PATH="$SAFEPATH" "$REALPY" "$WORK/ttydrive.py" y bash "$DOCTOR" --cleanup > "$WORK/k3.out" 2>&1
  sleep 1
  { ! alive $P1 && ! alive $P2; } && ok "real procs: y stopped both helpers" || { bad "real procs: y left a helper running"; cat "$WORK/k3.out" | head; }
  alive $PB && ok "real procs: y left the bystander alone" || bad "real procs: y killed the bystander"
else
  echo "  SKIP: no python3 pty here: confirm path not exercised"   # portability-ok: fixture names the tool it fakes / probes, Linux-only pty driver
fi
unset FAKE_PS_PIDS MXTK_LEFTOVER_MIN_AGE_S

# 6. Recommended fix: ONE block, first option that works here, no IT-dependent step
rf() { PATH="$SAFEPATH" MXTK_PROC_MEMINFO="$WORK/meminfo-high" FAKE_PS_FILE="$WORK/ps-clean.txt" "$@" > "$WORK/rf.out" 2>&1; }
printf '# P\n\nGate mode: full\n' > "$P/PROJECT.md"
rf bash "$DOCTOR" --bench "$P"
chk "fix a: Gate mode: full -> remove it" "$WORK/rf.out" 'Remove "Gate mode: full" from PROJECT.md'
[ "$(grep -c '^Recommended fix' "$WORK/rf.out")" -eq 1 ] && ok "fix: exactly one block" || bad "fix: block count"
printf '# P\n' > "$P/PROJECT.md"
rf bash "$DOCTOR" --bench "$P"
chk "fix: fast machine with the line set -> none needed" "$WORK/rf.out" "None needed"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/fakedocker"; chmod +x "$WORK/bin/fakedocker"
rf env MXTK_SPAWN_WARN_MS=0 MXTK_CONTAINER_RUNTIME=fakedocker bash "$DOCTOR" --bench "$P"
chk "fix c: slow starts + working container CLI -> dev container" "$WORK/rf.out" "Use a dev container (fakedocker"
rf env MXTK_SPAWN_WARN_MS=0 MXTK_CONTAINER_RUNTIME=no-such-runtime bash "$DOCTOR" --bench "$P"
chk "fix d: slow starts, nothing else -> cloud" "$WORK/rf.out" "Let Claude work in the cloud"
chk "fix d: names git pull" "$WORK/rf.out" "git pull"
# b: pretend Git Bash with WSL present (fake uname + wsl.exe); falls through to c when --status fails
printf '#!/bin/sh\ncase "$1" in -m) echo x86_64 ;; *) echo MINGW64_NT-10.0-26200 ;; esac\n' > "$WORK/bin/uname"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/wsl.exe"; chmod +x "$WORK/bin/uname" "$WORK/bin/wsl.exe"
rf env MXTK_SPAWN_WARN_MS=0 MXTK_CONTAINER_RUNTIME=fakedocker bash "$DOCTOR" --bench "$P"
chk "fix b: Git Bash + wsl.exe --status ok -> WSL (before dev container)" "$WORK/rf.out" "Run the toolkit in WSL"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/wsl.exe"
rf env MXTK_SPAWN_WARN_MS=0 MXTK_CONTAINER_RUNTIME=fakedocker bash "$DOCTOR" --bench "$P"
chk "fix b: wsl.exe --status failing -> next option" "$WORK/rf.out" "Use a dev container"
rm -f "$WORK/bin/uname" "$WORK/bin/wsl.exe"
chkno "no IT-dependent advice anywhere in the output" "$WORK/rf.out" "exclusion\|ask IT" -i

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
