#!/usr/bin/env bash
# doctor.sh — probe this machine once and say, in plain language, what the toolkit needs and
# what is missing. Run this before anything else, on any platform.
#
# WHY THIS EXISTS. The toolkit is handed to people who cannot debug a shell script. Every
# environment assumption it makes was previously discovered halfway through a pipeline stage,
# where it reads as "the toolkit is broken" rather than "my machine is missing something".
# One command, run first, moves every one of those discoveries to the front.
#
# This script deliberately depends on almost nothing: POSIX shell plus coreutils. It must be
# able to report "you have no Python" while itself having no Python. Do not add a dependency
# here without checking it against that rule.
#
#   bin/doctor.sh                           # probe the machine
#   bin/doctor.sh <project-dir>             # also probe a specific project's wiring
#   bin/doctor.sh --install <project-dir>   # and, if the mxbuild toolchain is missing,
#                                           # download it locally via the project's ./mxcli
#                                           # (same `setup mxbuild` the headless container
#                                           # build uses; cached at ~/.mxcli/mxbuild/)
#
# --install is the one deliberate exception to the no-dependency rule: it needs the project's
# own mxcli binary and network access, runs only when asked, and a failed download degrades to
# the same report you would have had without it.
#
# Exit: 0 = ready. 1 = warnings only, the toolkit will mostly work. 2 = something required is
# missing and a pipeline stage will fail.

set -u

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR=""
INSTALL=0
for _arg in "$@"; do
  case "$_arg" in
    --install) INSTALL=1 ;;
    *)         PROJECT_DIR="$_arg" ;;
  esac
done

FAIL=0
WARN=0

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; WARN=$((WARN + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
note() { printf '        %s\n' "$*"; }
head_() { printf '\n%s\n' "$*"; }

# probe_runs <binary> — does this binary actually EXECUTE on this machine?
#
# Not the same question as "does --version exit 0". Field report (2026-08-31, macOS, latest
# Studio Pro): its mxbuild dropped --version, so the flag exits non-zero while the binary is
# perfectly healthy — and this script's old probe read that as "mxbuild cannot run" on exactly
# the machine of the person we told to run doctor first. The probe the section needs is
# execute-level: try --version, and when the flag (not the binary) is what failed, try --help.
# Exit 126/127 is the binary itself failing (wrong platform / not found) — no retry can fix
# that. Both flags failing with other codes is also reported broken, with the output shown.
# On success: PROBE_OUT holds the first probe's output, PROBE_HOW names the flag that worked.
PROBE_OUT=""
PROBE_HOW=""
probe_runs() {
  PROBE_OUT=""; PROBE_HOW=""
  _pr_exit=0
  PROBE_OUT="$("$1" --version 2>&1)" || _pr_exit=$?
  if [ "$_pr_exit" -eq 0 ]; then PROBE_HOW="--version"; return 0; fi
  case "$_pr_exit" in 126|127) return "$_pr_exit" ;; esac
  if _pr_out2="$("$1" --help 2>&1)"; then
    PROBE_OUT="$_pr_out2"; PROBE_HOW="--help; this build has no --version"
    return 0
  fi
  return "$_pr_exit"
}

# --- platform -------------------------------------------------------------------------------

head_ "Platform"

UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME" in
  Darwin)             PLATFORM=macos ;;
  Linux)              PLATFORM=linux ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM=gitbash ;;
  *)                  PLATFORM=unknown ;;
esac
ok "$UNAME  (treating this as: $PLATFORM)"

# WSL reports Linux. It matters, because a WSL shell cannot see Windows applications the way
# Git Bash can — Studio Pro automation is reached differently, or not at all.
if [ "$PLATFORM" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM=wsl
  warn "This is WSL, not native Linux."
  note "WSL is a separate Linux filesystem and process space. Scripts that drive Studio Pro"
  note "or reach a locally running app on the Windows side need the Windows host, not this one."
  note "If you are on Windows, prefer Git Bash for toolkit scripts until this is settled."
fi

ok "shell: ${BASH_VERSION:-not bash}"
case "${BASH_VERSION:-0}" in
  3.*) note "bash 3.2 (the macOS system bash). Scripts here are written for it; nothing to do." ;;
esac

# --- python ---------------------------------------------------------------------------------

head_ "Python 3"

# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/bin/lib/portable.sh"

if PY_FOUND="$(resolve_py)"; then
  ok "$PY_FOUND -> $($PY_FOUND -c 'import sys,platform; print(sys.executable or "?", platform.python_version())' 2>/dev/null)"
else
  bad "No working Python 3 found. Tried, by running each: python3, python, py."
  note "macOS  : brew install python3"
  note "Linux  : apt install python3   (or your distro's equivalent)"
  note "Windows: install from python.org and tick 'Add python.exe to PATH'."
  # The py launcher can default to Python 2 while a perfectly good Python 3 sits behind -3.
  if py -3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
    note "NOTE: 'py -3' works on this machine but 'py' does not default to it. The scripts need"
    note "a single-word command, so set one: py -3 -m ensurepip, or reinstall with PATH ticked."
  fi
fi

# The Store alias stub is worth naming even when a real interpreter was found later on PATH:
# it is the thing that will confuse the reader when they type python3 themselves.
for c in python3 python; do
  case "$(command -v "$c" 2>/dev/null)" in
    *WindowsApps*|*windowsapps*)
      warn "'$c' on your PATH is the Microsoft Store alias stub, not an interpreter."
      note "The toolkit skips it. You should still turn it off:"
      note "Settings > Apps > Advanced app settings > App execution aliases."
      ;;
  esac
done

# --- line endings ------------------------------------------------------------------------

head_ "Line endings"

# The highest-value check in this file. If git checked these scripts out with CRLF, bash fails
# on line 1 of every one of them with a message ($'\r': command not found) that names nothing
# a reader can act on. It happens before any other check in this script would ever run.
CRLF_HITS=0
CRLF_FIRST=""
CRLF_SEEN=0
for f in "$TOOLKIT_ROOT"/bin/*.sh "$TOOLKIT_ROOT"/bin/lib/*.sh "$TOOLKIT_ROOT"/project-bin/*.sh \
         "$TOOLKIT_ROOT"/claude-hooks/hooks/*.sh "$TOOLKIT_ROOT"/claude-hooks/bin/*.sh; do
  [ -f "$f" ] || continue
  CRLF_SEEN=$((CRLF_SEEN + 1))
  # Strip CR and compare with the original: any difference means the file carries CRs.
  if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
    CRLF_HITS=$((CRLF_HITS + 1))
    [ -n "$CRLF_FIRST" ] || CRLF_FIRST="$f"
  fi
done

# Zero scripts found is not "all your scripts are fine" — it means the probe looked in the
# wrong place and would report LF over an empty set. Say so instead.
if [ "$CRLF_SEEN" -eq 0 ]; then
  bad "found no shell scripts under $TOOLKIT_ROOT to check — this is not a pass"
  note "Either the toolkit path is wrong, or the clone is incomplete."
elif [ "$CRLF_HITS" -gt 0 ]; then
  bad "$CRLF_HITS script(s) have Windows line endings (CRLF). They will not run."
  note "first one: $CRLF_FIRST"
  note "Every one fails on its first line with: \$'\\r': command not found"
  note "Fix, from the toolkit root:"
  note "  git config core.autocrlf false"
  note "  git rm --cached -r . && git reset --hard"
  note "The .gitattributes in this repo prevents it happening again on a fresh clone."
else
  ok "shell scripts are LF, as required ($CRLF_SEEN checked)"
fi

AUTOCRLF="$(git -C "$TOOLKIT_ROOT" config --get core.autocrlf 2>/dev/null || echo unset)"
case "$AUTOCRLF" in
  true) warn "git core.autocrlf=true. .gitattributes overrides it for *.sh, but set it false." ;;
  *)    ok "git core.autocrlf=$AUTOCRLF" ;;
esac

# --- the toolkit's own scripts --------------------------------------------------------------

head_ "Do the toolkit's own scripts load here?"

# CRLF above catches one way a script cannot run; this catches the rest of the parse-level
# class (a bashism this bash rejects, a syntax error that shipped, a mangled installed copy)
# by running every shipped script through its interpreter's parse step. check-scripts.sh is
# standalone so sync-project.sh can run the same probe after every refresh.
if [ -x "$TOOLKIT_ROOT/bin/check-scripts.sh" ]; then
  CS_EXIT=0
  "$TOOLKIT_ROOT/bin/check-scripts.sh" ${PROJECT_DIR:+"$PROJECT_DIR"} || CS_EXIT=$?
  case "$CS_EXIT" in
    0) ok "every shipped script parses under this machine's bash and node" ;;
    1) warn "shell scripts parse; Node instruments unchecked (no node — see the Node section)" ;;
    *) bad "script(s) that will not run on this machine — see the FAIL lines above" ;;
  esac
else
  bad "bin/check-scripts.sh is missing — the clone is incomplete or predates it"
fi

# --- command line tools ---------------------------------------------------------------------

head_ "Command line tools"

for c in git sed grep awk find sort tr cut; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || bad "$c is missing — it is used by nearly every script"
done

command -v sqlite3 >/dev/null 2>&1 && ok "sqlite3" || {
  warn "sqlite3 is missing. project-bin/graph-sweep.sh reads the mxcli catalog with it."
  note "macOS: preinstalled. Linux: apt install sqlite3. Windows: winget install SQLite.SQLite"; }

command -v shellcheck >/dev/null 2>&1 && ok "shellcheck (optional, for editing toolkit scripts)" \
  || note "shellcheck not installed — only needed if you edit toolkit scripts"

# --- studio pro -------------------------------------------------------------------------

head_ "Studio Pro automation"

case "$PLATFORM" in
  macos)
    if ls -d /Applications/Mendix\ Studio\ Pro*.app >/dev/null 2>&1; then
      ok "found: $(ls -d /Applications/Mendix\ Studio\ Pro*.app | tr '\n' ' ')"
    else
      warn "no 'Mendix Studio Pro *.app' in /Applications — project-bin/restart-sp.sh cannot run"
    fi
    ;;
  gitbash|wsl|linux|unknown)
    warn "The Studio Pro scripts (save-sp.sh, restart-sp.sh, and the SP handling in exec.sh)"
    note "are macOS-only: they are built on osascript, lsof and 'open -a', and Studio Pro is"
    note "discovered by looking in /Applications. There is no Windows port yet."
    note "Everything else in the toolkit works here. Drive Studio Pro by hand on this platform."
    ;;
esac

# --- build toolchain -----------------------------------------------------------------------

head_ "Build toolchain (mxbuild model verification)"

# WHY THIS SECTION EXISTS. exec.sh verifies every model write with mxbuild. When mxbuild or
# its Java cannot be resolved, the gate does not fail — it reports `skipped` and the exec goes
# through UNVERIFIED. Real incident (Windows training round, 2026-08): machines where mxbuild
# could not run went whole exercises without a single consistency error being captured,
# because nobody reads a skip as a problem. This section answers, before any work starts,
# the one question that decided that: will the mxbuild gate actually run on this machine?
#
# Discovery is deliberately the SAME code exec.sh uses (project-bin/_common.sh), so a green
# line here predicts the gate's behaviour instead of approximating it.

# _common.sh resolves PROJECT_ROOT by walking up from $PWD when unset; pin it first so
# sourcing it from an arbitrary directory stays inert. (It also redefines resolve_py with its
# project-side twin — harmless, the Python probe above already ran.)
PROJECT_ROOT="${PROJECT_DIR:-$TOOLKIT_ROOT}"
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/project-bin/_common.sh"

SP_APP="$(find_sp_app 2>/dev/null || true)"
MXBUILD="$(find_mxbuild 2>/dev/null || true)"
JAVA_HOME_FOUND="$(find_java 2>/dev/null || true)"
JAVA_EXE="$(find_java_exe 2>/dev/null || true)"

# --install: when no runnable mxbuild was discovered, download the standalone toolchain
# through the project's own mxcli — `./mxcli setup mxbuild -p <app>.mpr`, the exact download
# the headless container build runs, cached at ~/.mxcli/mxbuild/<version>/ and shared across
# projects. find_mxbuild/find_java (project-bin/_common.sh) discover that cache, so after a
# successful download the exec.sh mxbuild gate runs from it too — no Studio Pro required.
# This happens BEFORE the reporting below, so the report describes the machine as it now is.
if [ "$INSTALL" -eq 1 ]; then
  if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ] && probe_runs "$MXBUILD"; then
    ok "--install: a runnable mxbuild is already discovered — nothing to download"
  elif [ -z "$PROJECT_DIR" ]; then
    bad "--install needs a project directory: bin/doctor.sh --install <project-dir>"
    note "The download runs through that project's own ./mxcli, which reads the model's"
    note "Mendix version and fetches the matching toolchain."
  elif [ ! -x "$PROJECT_DIR/mxcli" ]; then
    bad "--install: no executable mxcli in $PROJECT_DIR — cannot download the toolchain."
    note "Get the mxcli build for this OS into the project root first (chmod +x mxcli)."
  else
    INSTALL_MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
    if [ -z "$INSTALL_MPR" ]; then
      bad "--install: no .mpr in $PROJECT_DIR — setup mxbuild needs the model to pick a version."
    else
      note "downloading the mxbuild toolchain (./mxcli setup mxbuild — same as the container build)..."
      if (cd "$PROJECT_DIR" && ./mxcli setup mxbuild -p "$(basename "$INSTALL_MPR")"); then
        # Re-run the discovery: the cache did not exist the first time around.
        SP_APP="$(find_sp_app 2>/dev/null || true)"
        MXBUILD="$(find_mxbuild 2>/dev/null || true)"
        JAVA_HOME_FOUND="$(find_java 2>/dev/null || true)"
        JAVA_EXE="$(find_java_exe 2>/dev/null || true)"
        ok "toolchain downloaded to ~/.mxcli/mxbuild/ (shared cache, reused by every project)"
      else
        bad "'./mxcli setup mxbuild' failed — see its output above."
        note "A blocked network/proxy is the usual cause; the download comes from the Mendix CDN."
      fi
    fi
  fi
fi

GATE_OK=1

# Studio Pro install (the root mxbuild and the bundled JRE are discovered under).
if [ -n "$SP_APP" ]; then
  ok "Studio Pro install: $SP_APP"
elif [ "$PLATFORM" = linux ]; then
  warn "no Studio Pro install (none exists for Linux)."
  note "A standalone mxbuild works instead: bin/doctor.sh --install <project-dir> downloads"
  note "one to ~/.mxcli (the container build's toolchain), or set MXBUILD_PATH=/path/to/mxbuild."
else
  # Severity depends on whether the standalone toolchain covers for it below.
  if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
    warn "no Studio Pro install found — running on the downloaded toolchain instead (fine for"
    note "the mxbuild gate; you still need Studio Pro to open the model yourself)."
  else
    bad "no Studio Pro install found — mxbuild and its bundled Java live inside it."
    note "Two ways out:"
    note "  1. No Studio Pro needed for the gate: bin/doctor.sh --install <project-dir>"
    note "     downloads the standalone toolchain (same one the headless container build uses)."
    note "  2. Install Mendix Studio Pro, or point past the discovery:"
    note "     MENDIX_APP=<install root>   (macOS: /Applications/Mendix Studio Pro X.Y.Z.app,"
    note "                                  Windows: C:/Program Files/Mendix/X.Y.Z)"
    note "     MXBUILD_PATH=<mxbuild binary>   JAVA_HOME=<jdk/jre root>"
  fi
fi

# mxbuild: present, executable, AND RUNS. Presence alone has lied before — a wrong-platform
# binary sits at the right path, exits 126 on invocation, and a careless reading of "0 errors
# reported" becomes a false green. Execute it and read the exit code (probe_runs above — a
# failed --version alone is NOT "cannot run").
if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
  MXB_EXIT=0
  probe_runs "$MXBUILD" || MXB_EXIT=$?
  if [ "$MXB_EXIT" -eq 0 ]; then
    ok "mxbuild runs ($PROBE_HOW): $(printf '%s' "$PROBE_OUT" | head -1)"
    note "at: $MXBUILD"
  else
    GATE_OK=0
    bad "mxbuild exists but cannot run (exit $MXB_EXIT): $MXBUILD"
    printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -3 | while IFS= read -r l; do note "  $l"; done
    note "Exit 126 usually means a binary built for another platform/architecture."
  fi
else
  GATE_OK=0
  if [ "$PLATFORM" = linux ]; then
    warn "mxbuild not found/executable: ${MXBUILD:-<none>}"
  else
    bad "mxbuild not found/executable: ${MXBUILD:-<none>}"
  fi
  note "Fix without Studio Pro: bin/doctor.sh --install <project-dir>   (downloads it locally,"
  note "like the container build). Or set MXBUILD_PATH=/path/to/mxbuild."
fi

# Java: mxbuild is invoked with an explicit --java-exe-path; if none resolves, the gate skips.
if [ -n "$JAVA_EXE" ] && [ -x "$JAVA_EXE" ]; then
  # -version writes to stderr, and wrappers can prepend noise (JAVA_TOOL_OPTIONS pickup
  # lines); take the line that actually names a version, not merely the first.
  JV="$("$JAVA_EXE" -version 2>&1 | grep -i 'version' | head -1)" || JV=""
  if [ -n "$JV" ]; then
    ok "java runs: $JV  ($JAVA_EXE)"
  else
    GATE_OK=0
    bad "java exists but produced no version output: $JAVA_EXE"
  fi
else
  GATE_OK=0
  if [ "$PLATFORM" = linux ] && [ -z "$SP_APP" ]; then
    warn "java not found (looked for JAVA_HOME, Studio Pro's bundled JRE, then PATH)."
  else
    bad "java not found/executable: ${JAVA_EXE:-<none>}"
    note "Studio Pro ships its own JRE and that is the preferred one; if discovery missed it,"
    note "set JAVA_HOME=<jdk/jre root> explicitly."
  fi
fi

if [ "$GATE_OK" -eq 1 ] && [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
  ok "exec.sh mxbuild gate WILL RUN on this machine — model writes get verified."
else
  # Same fact, platform-matched severity: on Linux there is no Studio Pro to install, so a
  # skipping gate is expected (WARN) unless the user provides a standalone mxbuild. On the
  # platforms Studio Pro runs on, a skipping gate is the training-round failure itself.
  if [ "$PLATFORM" = linux ] && [ -z "$SP_APP" ] && [ -z "${MXBUILD_PATH:-}" ]; then
    warn "exec.sh mxbuild gate WILL BE SKIPPED on this machine."
  else
    bad "exec.sh mxbuild gate WILL BE SKIPPED on this machine. Fix the FAIL lines above"
    note "before writing to any model from this machine."
  fi
  note "Every MDL exec here will report gate=skipped and go through UNVERIFIED: consistency"
  note "errors (CE) are never captured, and BSON corruption — which mxbuild is the only"
  note "reliable detector for — reaches Studio Pro undetected."
  note "Fastest fix on ANY platform: bin/doctor.sh --install <project-dir> — downloads the"
  note "toolchain locally through the project's ./mxcli, exactly like the container build."
fi

# --- node -----------------------------------------------------------------------------------

head_ "Node.js (pipelines, page fidelity, e2e)"

NODE_V="$(node --version 2>/dev/null)" || NODE_V=""
if [ -n "$NODE_V" ]; then
  ok "node $NODE_V"
else
  warn "node is missing. Needed by the extraction pipelines (npm install per pipeline),"
  note "project-bin/page-fidelity.js, and Playwright e2e (project-bin/test-stack-up.sh)."
  note "Not needed for a pure MDL-writing session."
fi
note "e2e additionally needs a Playwright browser in the project: npx playwright install chromium"

# --- self-verification (docker) -------------------------------------------------------------

head_ "Self-verification stack (Docker — recommended)"

# With Docker, the loop closes without a human: after a build the agent runs a Linux build of
# the app, brings up Postgres + the app (project-bin/test-stack-up.sh), drives it with
# Playwright, screenshots the pages, and verifies its own work — nobody has to open Studio
# Pro to find out whether a page renders. Without Docker the mxbuild gate still verifies the
# MODEL, but nothing verifies the RUNNING APP unless a human does. Recommended, never
# required — hence WARN, not FAIL.
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "docker daemon responding — mxcli docker check + test-stack-up.sh (app up, e2e, screenshots) available"
  else
    warn "docker is installed but the daemon is not responding."
    note "Start Docker Desktop (or colima / Rancher Desktop). Until it runs: no app container,"
    note "no throwaway Postgres, no agent-driven e2e/screenshots."
  fi
else
  warn "docker is not installed — recommended for new builders."
  note "It is what lets the agent verify its own build: 'mxcli docker check' (deep model+build"
  note "verification) and project-bin/test-stack-up.sh (Postgres + the app up, Playwright e2e,"
  note "page screenshots) both need it. Without it, only mxbuild verifies the model and a human"
  note "must open Studio Pro to see whether anything actually renders."
  note "No-Docker fallback for just running the app: 'mxcli run --local' against a native"
  note "PostgreSQL (host:PORT)."
  note "Corporate machines: Docker Desktop needs a paid licence at larger companies — Rancher"
  note "Desktop or Podman (docker-CLI compatible) and colima (macOS) are common substitutes."
fi

# --- spawn speed (git bash) -----------------------------------------------------------------

# gate-check.sh + the obligation check fork over a thousand subprocesses per run. On a healthy
# machine a fork is ~1-3 ms and the run takes seconds; observed on a managed Windows laptop:
# 152 ms per fork, which turns the same run into a 5-15 minute "hang" (see the header of
# bin/lib/obligation-check.sh). Measure it once here so slow reads as "this machine", not
# "the toolkit is broken".
if [ "$PLATFORM" = gitbash ]; then
  head_ "Process spawn speed"
  T0="$(date +%s%N 2>/dev/null || echo x)"
  case "$T0" in
    *[!0-9]*) note "cannot measure spawn speed (no nanosecond clock in this date)" ;;
    *)
      i=0
      while [ "$i" -lt 25 ]; do _="$(true)"; i=$((i + 1)); done
      T1="$(date +%s%N)"
      MS_PER_FORK=$(( (T1 - T0) / 25 / 1000000 ))
      if [ "$MS_PER_FORK" -le 40 ]; then
        ok "~${MS_PER_FORK} ms per subprocess — gate-check will run in normal time"
      else
        warn "~${MS_PER_FORK} ms per subprocess — gate-check.sh will feel HUNG (minutes, not seconds)."
        note "The usual causes, in order:"
        note "  - Windows Defender real-time scanning every process start. Ask IT to exclude"
        note "    the Git Bash install directory and this repo's folder."
        note "  - The repo living under OneDrive/Dropbox (every file touch syncs)."
        note "  - Corporate endpoint agents hooking process creation."
      fi
      ;;
  esac
fi

# --- path hygiene ---------------------------------------------------------------------------

for p in "$TOOLKIT_ROOT" "${PROJECT_DIR:+$PROJECT_DIR}"; do
  [ -n "$p" ] || continue
  case "$p" in
    *OneDrive*|*onedrive*)
      head_ "Path hygiene"
      warn "$p is under OneDrive. Sync fights every model write and slows every script;"
      note "move the folder outside OneDrive." ;;
  esac
  case "$p" in
    *" "*)
      warn "path contains a space: $p"
      note "Most toolkit scripts quote correctly, but tooling invoked underneath (npm, java"
      note "launchers) has a long history of not doing so. A space-free path avoids the class." ;;
  esac
done

# --- project ------------------------------------------------------------------------------

if [ -n "$PROJECT_DIR" ]; then
  head_ "Project: $PROJECT_DIR"
  if [ ! -d "$PROJECT_DIR" ]; then
    bad "not a directory"
  else
    [ -f "$PROJECT_DIR/CLAUDE.local.md" ] && ok "CLAUDE.local.md (toolkit wiring) present" \
      || warn "no CLAUDE.local.md — run bin/init-project.sh '$PROJECT_DIR'"
    MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
    [ -n "$MPR" ] && ok "model: $(basename "$MPR")" || warn "no .mpr found in the project root"
    if [ -x "$PROJECT_DIR/mxcli" ]; then
      # Present is not enough — a wrong-platform binary is present, executable, and exits 126.
      MXCLI_EXIT=0
      probe_runs "$PROJECT_DIR/mxcli" || MXCLI_EXIT=$?
      if [ "$MXCLI_EXIT" -eq 0 ]; then
        ok "mxcli runs ($PROBE_HOW): $(printf '%s' "$PROBE_OUT" | head -1)"
      else
        bad "mxcli exists but cannot run (exit $MXCLI_EXIT)"
        printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -3 | while IFS= read -r l; do note "  $l"; done
        note "Exit 126 usually means a binary built for another platform/architecture —"
        note "re-download the mxcli build for this OS."
      fi
    elif [ -f "$PROJECT_DIR/mxcli" ]; then bad "mxcli is present but not executable — chmod +x mxcli"
    else warn "no mxcli in the project root"; fi
  fi
fi

# --- verdict ---------------------------------------------------------------------------------

head_ "Verdict"

# Leave a dated receipt in the project so gate-check can tell "doctor ran and passed" from
# "nobody ever ran doctor here". Informational only — nothing gates on it, because a machine
# check must never turn into a stage verdict.
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
  if [ "$FAIL" -gt 0 ]; then RECEIPT_VERDICT=fail
  elif [ "$WARN" -gt 0 ]; then RECEIPT_VERDICT=warn
  else RECEIPT_VERDICT=ok; fi
  mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || true
  printf '%s %s fail=%s warn=%s\n' "$(date '+%Y-%m-%d %H:%M')" "$RECEIPT_VERDICT" "$FAIL" "$WARN" \
    > "$PROJECT_DIR/.claude/.doctor-receipt" 2>/dev/null || true
fi

if [ "$FAIL" -gt 0 ]; then
  printf '  %s problem(s) that will break a pipeline stage, %s warning(s).\n' "$FAIL" "$WARN"
  printf '  Fix the FAIL lines above before running anything else.\n'
  exit 2
elif [ "$WARN" -gt 0 ]; then
  printf '  Ready, with %s warning(s). Read them — each one names something that will not work.\n' "$WARN"
  exit 1
else
  printf '  Ready.\n'
  exit 0
fi
