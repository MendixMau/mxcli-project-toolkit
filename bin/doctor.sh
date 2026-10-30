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
#   bin/doctor.sh --install <project-dir>   # and, if tools are missing, offer to download
#                                           # them locally: a missing ./mxcli from the
#                                           # mendixlabs/mxcli GitHub releases, then the
#                                           # mxbuild toolchain via `./mxcli setup mxbuild`
#                                           # (same download the headless container build
#                                           # uses; cached at ~/.mxcli/mxbuild/).
#   bin/doctor.sh --install --yes <dir>     # skip the confirmation (unattended/agent runs)
#   bin/doctor.sh --no-docker [<project-dir>] # skip the container-runtime probe (or
#                                           # MXTK_DOCTOR_SKIP_DOCKER=1). The probe is bounded
#                                           # anyway: MXTK_DOCKER_PROBE_SECS (default 8) — a
#                                           # stopped Docker Desktop can make 'docker info' sit
#                                           # silent for minutes, which read as "the setup
#                                           # hangs" (field report, 2026-09-09). The probe finds
#                                           # docker OR podman, whichever is present;
#                                           # MXTK_CONTAINER_RUNTIME=<name> forces one.
#   bin/doctor.sh --quick [<project-dir>]   # ~2 s: platform, mxcli/mxbuild/java EXECUTE, spawn
#                                           # speed, path hygiene, model layout. Skips the
#                                           # once-per-machine sections (python, CRLF, script
#                                           # parse, node, docker, gate self-test). exec.sh runs
#                                           # this itself when the receipt is stale — doctor
#                                           # used to run once and never again, so a machine
#                                           # that drifted mid-project (new binary, wrong-arch
#                                           # mxbuild, a Defender policy) read as "the toolkit
#                                           # is broken".
#   bin/doctor.sh --bench [<project-dir>]   # ~1 minute, changes nothing: times 50 process starts, git status,
#                                           # python/node start, one gate-check, an mxcli check of a tiny script
#                                           # and (on a COPY of the model) mx check; prints step | this machine |
#                                           # reference | factor and one verdict line, and writes the numbers to
#                                           # <project>/.claude/loop/bench-<timestamp>.tsv to compare with colleagues.
#   bin/doctor.sh --cleanup                 # list leftover mxbuild helper processes (deno from modeler/tools/deno,
#                                           # older than 10 min, no live mxbuild parent) and stop exactly those after
#                                           # you type y. With no terminal it prints the command and stops nothing.
#                                           # Every normal run also has a "Machine health" section (same leftovers
#                                           # plus free memory): mxbuild is killed with exit 137 when memory runs out.
#   bin/doctor.sh --gate-selftest [<dir>]   # force the gate self-test section to run even
#                                           # under --quick, or on its own. See its own header
#                                           # (search "Gate self-test") for what it proves and
#                                           # why: mxbuild/java being PRESENT does not mean the
#                                           # mxbuild gate can actually SEE an error.
#   bin/doctor.sh --property-sets <dir>     # ONLY the Studio Pro merge-safety check: runs
#                                           # `mxcli fix property-sets --dry-run` (read-only)
#                                           # and records the result. Add --if-stale to skip
#                                           # the run when it already ran for this mxcli
#                                           # version (sync-project.sh does). Exit 0 clean,
#                                           # 1 units need repair (NEEDS/FAILED rows), 2 not run
#                                           # (incl. timeout), 3 this mxcli predates the command
#                                           # (v0.26.0), 4 could not check (error, unclassified
#                                           # output, a crashed probe) — a repair would not help.
#   bin/doctor.sh --fix-property-sets <dir> # the same check, then the repair — and only
#                                           # through bin/exec.sh --patch (snapshot, mxbuild
#                                           # gate, restore on failure). See "Property sets".
#
# --install never downloads silently: it prints the plan first — what, from where, how big,
# why, and the detected OS/arch — then asks [y/N] at a terminal, or requires --yes when there
# is no terminal to ask on (agents and CI: always pass --yes). $MXCLI_VERSION=vX.Y.Z pins the mxcli release; default is latest.
#
# --install is the one deliberate exception to the no-dependency rule: it needs network access
# (and curl or wget), runs only when asked, and a failed or declined download degrades to the
# same report you would have had without it.
#
# Exit: 0 = ready. 1 = warnings only, the toolkit will mostly work. 2 = something required is
# missing and a pipeline stage will fail.

set -u

# The repair step of --fix-property-sets, run BY bin/exec.sh --patch, never by hand: exec.sh
# calls a .sh patch as `bash <script> <model.mpr> [args...]`, so this file is its own patch
# script and the repair inherits exec.sh's snapshot, mxbuild gate and restore.
if [ "${2:-}" = "--property-sets-apply-step" ]; then
  { [ -n "${3:-}" ] && [ -x "$3" ]; } || { echo "--property-sets-apply-step: no runnable mxcli given" >&2; exit 2; }
  exec "$3" fix property-sets -p "$1"
fi

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR=""
INSTALL=0
ASSUME_YES=0
QUICK=0
GATE_SELFTEST=0
BENCH=0
CLEANUP=0
PS_MODE=""
PS_IF_STALE=0
NO_DOCKER="${MXTK_DOCTOR_SKIP_DOCKER:-0}"
DOCKER_PROBE_SECS="${MXTK_DOCKER_PROBE_SECS:-8}"
for _arg in "$@"; do
  case "$_arg" in
    --install) INSTALL=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --quick)   QUICK=1 ;;
    --bench)   BENCH=1 ;;
    --cleanup) CLEANUP=1 ;;
    --gate-selftest) GATE_SELFTEST=1 ;;
    --no-docker) NO_DOCKER=1 ;;
    --property-sets)     PS_MODE=check ;;
    --fix-property-sets) PS_MODE=fix ;;
    --if-stale)          PS_IF_STALE=1 ;;
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
# (Show PROBE_OUT via probe_line — real mxbuild's --help opens with a blank-lined ASCII
# banner, so a naive head -1 prints nothing.)
# Every probe runs the binary with its output on a FILE, never inside `$(...)`. Studio Pro
# 11's mxbuild.exe (11.12.4, Windows, 2026-09-14) starts modeler/tools/deno/win-x64/deno.exe,
# which inherits stdout and outlives mxbuild — on --version and --help as much as on a real
# build. A command substitution waits for EOF on the pipe, deno never closes it, and doctor
# sat in "Build toolchain" for over ten minutes on the one machine it was meant to diagnose
# (it finished the instant the stray deno was killed). Writing to a file has no reader
# waiting on EOF, so bash returns when mxbuild itself exits. stdin is closed so a console-
# attached child cannot wait on that either. probe_capture <var> <cmd...> sets <var> to the
# combined output and returns the command's exit status.
PROBE_OUT=""
PROBE_HOW=""
probe_line() { printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -1; }
probe_capture() {
  _pc_var="$1"; shift
  _pc_file=$(mktemp "${TMPDIR:-/tmp}/doctor-probe.XXXXXX")
  _pc_exit=0
  "$@" > "$_pc_file" 2>&1 < /dev/null || _pc_exit=$?
  eval "$_pc_var=\$(cat \"\$_pc_file\")"
  rm -f "$_pc_file"
  return "$_pc_exit"
}
probe_runs() {
  PROBE_OUT=""; PROBE_HOW=""
  _pr_exit=0
  # --quick: the question is only "does it START" (exit 126/127 is the wrong-platform binary,
  # and that answer arrives in milliseconds). A healthy mxbuild spends ~5-9 s in .NET start-up
  # per flag, which made "quick" take 14 s; bound it and read a timeout as "started".
  if [ "$QUICK" = 1 ] && command -v timeout >/dev/null 2>&1; then
    probe_capture PROBE_OUT timeout 2 "$1" --help || _pr_exit=$?
    case "$_pr_exit" in
      0|124) PROBE_HOW="started (quick probe, 2 s bound)"; [ -n "$PROBE_OUT" ] || PROBE_OUT="(started)"; return 0 ;;
      126|127) return "$_pr_exit" ;;
    esac
    _pr_exit=0
  fi
  probe_capture PROBE_OUT "$1" --version || _pr_exit=$?
  if [ "$_pr_exit" -eq 0 ]; then PROBE_HOW="--version"; return 0; fi
  case "$_pr_exit" in 126|127) return "$_pr_exit" ;; esac
  if probe_capture _pr_out2 "$1" --help; then
    PROBE_OUT="$_pr_out2"; PROBE_HOW="--help; this build has no --version"
    return 0
  fi
  return "$_pr_exit"
}

# --- property sets: Studio Pro merge safety (mxcli v0.26.0+) ----------------------------------
#
# WHY THIS EXISTS (#295). Studio Pro's merge and diff compare two revisions of an element by its
# property NAMES, and throw when they differ ("Objects with ID … of type … do not have the same
# properties"). mxcli up to v0.25 wrote units without Studio Pro's full property set. Such a
# model passes `mx check`, the build and the runtime — every rung exec.sh has — and breaks the
# first diff or Team Server merge after Studio Pro has saved one of those documents. mxcli
# v0.26.0 completes the set on every write it makes, but only for the units it rewrites; units
# an older mxcli wrote keep their gaps until `mxcli fix property-sets` normalizes them. Field
# case: 78 changed units written with v0.24 on a production app, and no gate could see it.
#
# REPORT FIRST. The check is always the --dry-run (read-only; mxcli opens the model with its
# reader, not its writer). The repair runs only on --fix-property-sets, and only through
# bin/exec.sh --patch, so it gets the snapshot, the mxbuild gate and the auto-restore every
# other model write gets. A repair that leaves units FAILED (a value in a key the project's
# Mendix version does not declare) exits 1, and exec.sh then restores the whole run — fix
# those units by hand first.
#
# What the dry-run prints and how it exits is mxcli's cmd/mxcli/cmd_fix_property_sets.go at
# v0.26.0: exit 0 = nothing to do; exit 1 = a `  NEEDS ` or `  FAILED ` row per unit, OR an
# error such as "project not found" (both exit 1, so the rows decide, never the code alone).
# Anything else is "could not classify", never clean. Support is read from `mxcli fix --help`
# listing the subcommand: `mxcli fix property-sets --help` exits 0 on v0.24/v0.25 too (cobra
# prints the parent's help for an unknown subcommand), so it cannot be the probe. Golden
# captures of all three versions: tests/wave2/fixtures/property-sets/.
#
# The result is recorded in <project>/.claude/.property-sets-receipt (machine-local, like the
# doctor receipt): line 1 "<date> <time> <result> <detail>", line 2 "mxcli: <--version line>".
# Line 2 is what --if-stale and --quick compare: the check is owed again when mxcli changes.
# Only a settled answer is recorded — clean, unproven, needs, failed, or unsupported (the support probe
# ran and the subcommand is absent). An error or a timeout is never written, and --if-stale
# skips the run only on a recorded clean/unproven/unsupported, so a one-off failure (locked model,
# unreadable version, a probe that crashed) is re-checked on the next sync instead of being
# repeated from the receipt until mxcli changes.
#
# The dry-run reads every unit, so it is bounded: MXTK_PROPSETS_TIMEOUT seconds (default 300),
# through `timeout` when a working one is on PATH, else a polling watchdog. A timeout is
# NOT RUN (exit 2), not cached. MXTK_PROPSETS_NO_TIMEOUT_BIN=1 forces the watchdog (fixtures).
PS_RESULT=""
PS_DETAIL=""
PS_OUT=""
PS_VER=""
ps_receipt() { printf '%s/.claude/.property-sets-receipt' "$PROJECT_DIR"; }
ps_version() { probe_capture _ps_v "$1" --version || true; printf '%s\n' "$_ps_v" | grep -v '^[[:space:]]*$' | head -1; }
# ps_supported <mxcli> — 0 supported, 1 the help ran and does not list it, 2 the probe failed.
ps_supported() {
  probe_capture _ps_help "$1" fix --help || return 2
  printf '%s\n' "$_ps_help" | grep -qE '^[[:space:]]+property-sets[[:space:]]' || return 1
}
# ps_bounded <var> <secs> <cmd...> — probe_capture with a clock; returns 124 on timeout.
ps_bounded() {
  _pb_var="$1"; _pb_t="$2"; shift 2
  _pb_f=$(mktemp "${TMPDIR:-/tmp}/doctor-ps.XXXXXX"); _pb_rc=0
  if [ "${MXTK_PROPSETS_NO_TIMEOUT_BIN:-0}" != 1 ] && timeout 5 true >/dev/null 2>&1; then
    timeout "$_pb_t" "$@" > "$_pb_f" 2>&1 < /dev/null || _pb_rc=$?
  else
    "$@" > "$_pb_f" 2>&1 < /dev/null &
    _pb_pid=$!; _pb_s=0
    while kill -0 "$_pb_pid" 2>/dev/null; do
      if [ "$_pb_s" -ge "$_pb_t" ]; then
        kill "$_pb_pid" 2>/dev/null; wait "$_pb_pid" 2>/dev/null; _pb_rc=124; break
      fi
      sleep 1; _pb_s=$((_pb_s + 1))
    done
    [ "$_pb_rc" -eq 124 ] || { wait "$_pb_pid"; _pb_rc=$?; }
  fi
  eval "$_pb_var=\$(cat \"\$_pb_f\")"
  rm -f "$_pb_f"
  return "$_pb_rc"
}
# ps_classify <exit> <output> — sets PS_RESULT (clean|needs|failed|error) and PS_DETAIL.
ps_classify() {
  _psc_checked="$(printf '%s\n' "$2" | grep -m1 -E '^Checked [0-9]+ unit' || true)"
  _psc_needs="$(printf '%s\n' "$2" | grep -c '^  NEEDS ' || true)"
  _psc_failed="$(printf '%s\n' "$2" | grep -c '^  FAILED ' || true)"
  if [ "$1" -eq 0 ] && printf '%s\n' "$2" | grep -q 'no readable Mendix version'; then
    PS_RESULT=error; PS_DETAIL="mxcli read no Mendix version from the model, so nothing was checked"
  elif [ "$1" -eq 0 ]; then
    PS_RESULT=clean; PS_DETAIL="${_psc_checked:-exit 0}"
  elif [ "$1" -eq 1 ] && [ "$_psc_needs" -gt 0 ]; then
    PS_RESULT=needs; PS_DETAIL="$_psc_needs unit(s) need their property set completed, $_psc_failed cannot be normalized"
  elif [ "$1" -eq 1 ] && [ "$_psc_failed" -gt 0 ]; then
    PS_RESULT=failed; PS_DETAIL="$_psc_failed unit(s) hold a value in a key this Mendix version does not declare"
  else
    PS_RESULT=error
    PS_DETAIL="exit $1: $(printf '%s\n' "$2" | grep -v -e '^[[:space:]]*$' -e '^WARNING: This is a' | head -1)"
  fi
}
# ps_below_floor <version> — 0 when the Mendix version is older than 10.24.24, where mxcli's
# property table starts (mendixlabs/mxcli#1595), so a clean dry-run there proves nothing. 1 when
# it is not older, or the version is not a plain a.b.c[.d].
# Deliberately not gated on the mxcli version: a later release that still has the defect must not
# go silently green. Retire this check (and the warning) when mendixlabs/mxcli#1595 is fixed.
ps_below_floor() {
  case "$1" in [0-9]*.[0-9]*.[0-9]*) ;; *) return 1 ;; esac
  _pf_a="${1%%.*}"; _pf_r="${1#*.}"; _pf_b="${_pf_r%%.*}"; _pf_r="${_pf_r#*.}"; _pf_c="${_pf_r%%.*}"
  case "$_pf_a$_pf_b$_pf_c" in *[!0-9]*) return 1 ;; esac
  [ "$_pf_a" -lt 10 ] && return 0
  [ "$_pf_a" -gt 10 ] && return 1
  [ "$_pf_b" -lt 24 ] && return 0
  [ "$_pf_b" -gt 24 ] && return 1
  [ "$_pf_c" -lt 24 ]
}
# ps_unproven_warn <detail> <version> — the warning for a clean dry-run below the floor.
ps_unproven_warn() {
  warn "property sets: $1 — NOT PROOF: this model (Mendix ${2:-?}) is below 10.24.24, where mxcli's property table starts, so units mxcli writes can still lack keys (mendixlabs/mxcli#1595)"
  note "the proof is Mendix's own: mx diff <base>.mpr <mine>.mpr out.json with this version's mx; exit 0 is clean."
}
ps_write_receipt() {
  case "$PS_RESULT" in clean|unproven|needs|failed|unsupported) ;; *) return 0 ;; esac
  [ -n "$PS_VER" ] || return 0
  [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || return 0
  mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || return 0
  { printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$PS_RESULT" "$PS_DETAIL"
    printf 'mxcli: %s\n' "$PS_VER"
  } > "$(ps_receipt)" 2>/dev/null || true
  if [ -d "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q .claude/.property-sets-receipt 2>/dev/null; then
    printf '\n# Machine-local toolkit marker (doctor.sh property-set check)\n/.claude/.property-sets-receipt\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null \
      && note "(added /.claude/.property-sets-receipt to the project's .gitignore — the receipt is machine-local)"
  fi
}
# ps_stale — 0 when no check has been recorded for the mxcli that is installed now.
ps_stale() { [ ! -f "$(ps_receipt)" ] || [ "$(sed -n '2s/^mxcli: //p' "$(ps_receipt)")" != "$PS_VER" ]; }
# ps_check — needs MPR and PMXCLI_PROBE (empty is fine: reported NOT RUN). Sets PS_RESULT.
ps_check() {
  PS_RESULT=not-run; PS_DETAIL=""
  if [ -z "${MPR:-}" ]; then note "property sets: NOT RUN — no .mpr in the project root or app/"; return 0; fi
  if [ -z "${PMXCLI_PROBE:-}" ]; then note "property sets: NOT RUN — no runnable project mxcli"; return 0; fi
  PS_VER="$(ps_version "$PMXCLI_PROBE")"
  _pss_rc=0; ps_supported "$PMXCLI_PROBE" || _pss_rc=$?
  if [ "$_pss_rc" -eq 2 ]; then
    PS_RESULT=error; PS_DETAIL="'mxcli fix --help' itself failed, so support is unknown"
    warn "property sets: could not run the check — $PS_DETAIL (not recorded; the next run re-checks)"
    return 0
  fi
  if [ "$_pss_rc" -eq 1 ]; then
    PS_RESULT=unsupported; PS_DETAIL="${PS_VER:-this mxcli} has no 'fix property-sets'"
    warn "property sets: ${PS_VER:-this mxcli} cannot check them — 'mxcli fix property-sets' arrived in v0.26.0"
    note "Units an mxcli before v0.26 wrote can make Studio Pro's merge/diff throw although mx check,"
    note "the build and the runtime all pass. Upgrade the project's mxcli, then run this check."
    ps_write_receipt; return 0
  fi
  _psk_rc=0
  _psk_t="${MXTK_PROPSETS_TIMEOUT:-300}"
  ps_bounded PS_OUT "$_psk_t" "$PMXCLI_PROBE" fix property-sets -p "$MPR" --dry-run || _psk_rc=$?
  if [ "$_psk_rc" -eq 124 ]; then
    PS_RESULT=not-run; PS_DETAIL="timed out after ${_psk_t}s"
    note "property sets: NOT RUN — the read-only check timed out after ${_psk_t}s (MXTK_PROPSETS_TIMEOUT)."
    note "Not recorded. Run it when there is time: bin/doctor.sh --property-sets ${PROJECT_DIR:-<project>}"
    return 0
  fi
  ps_classify "$_psk_rc" "$PS_OUT"
  case "$PS_RESULT" in
    clean)
      _psk_mv="$(mxtk_model_version "$MPR" 2>/dev/null || true)"
      if ps_below_floor "$_psk_mv"; then
        PS_RESULT=unproven; ps_unproven_warn "$PS_DETAIL" "$_psk_mv"
      else
        ok "property sets: $PS_DETAIL — every unit has the property names Studio Pro writes"
      fi ;;
    needs|failed)
      warn "property sets: $PS_DETAIL — Studio Pro's merge/diff can throw on these"
      printf '%s\n' "$PS_OUT" | grep -E '^  (NEEDS|FAILED) ' | head -10 | while IFS= read -r l; do note "$l"; done
      _psk_rows="$(printf '%s\n' "$PS_OUT" | grep -cE '^  (NEEDS|FAILED) ' || true)"
      [ "$_psk_rows" -gt 10 ] && note "  … $((_psk_rows - 10)) more"
      [ "$PS_RESULT" = needs ] && note "repair (snapshot + mxbuild gate + restore): bin/doctor.sh --fix-property-sets ${PROJECT_DIR:-<project>}"
      [ "$(printf '%s\n' "$PS_OUT" | grep -c '^  FAILED ' || true)" -gt 0 ] && \
        note "FAILED units are left alone by mxcli and make the guarded repair roll back — resolve them first." ;;
    *) warn "property sets: could not classify the check — $PS_DETAIL (not recorded; the next run re-checks)"
       printf '%s\n' "$PS_OUT" | grep -v '^[[:space:]]*$' | head -5 | while IFS= read -r l; do note "  $l"; done ;;
  esac
  ps_write_receipt
}
ps_apply() {
  _psa_ex="$PROJECT_DIR/bin/exec.sh"
  if [ ! -x "$_psa_ex" ] || ! grep -q 'PATCH_MODE' "$_psa_ex" 2>/dev/null; then
    bad "property sets: not repaired — this project's bin/exec.sh has no --patch, and the repair is only run through it"
    note "upgrade it first: bin/sync-project.sh $PROJECT_DIR --only-bin exec.sh --upgrade-bin exec.sh"
    return 0
  fi
  note "repairing through bin/exec.sh --patch (snapshot, fix, mxbuild gate, kept only on a verified gate)…"
  _psa_rc=0
  # MXTK_LINT_GATE=soft: under a project's `Lint gate: hard` a kept repair would exit 1 (#496).
  ( cd "$PROJECT_DIR" && MXTK_LINT_GATE=soft ./bin/exec.sh --patch "$TOOLKIT_ROOT/bin/doctor.sh" --property-sets-apply-step "$PMXCLI_PROBE" ) || _psa_rc=$?
  # exec.sh exit 4 = kept on a passed gate, lint rose (exec.sh "Exit codes"); not a failed repair.
  [ "$_psa_rc" -eq 4 ] && { note "property sets: repair kept; exec.sh reports a lint rise (see its BUILD-LOG row)"; _psa_rc=0; }
  if [ "$_psa_rc" -ne 0 ]; then
    bad "property sets: exec.sh --patch exited $_psa_rc — the repair was not kept (its output above says why)"
    return 0
  fi
  note "re-checking…"
  ps_check
}
ps_exit_code() {
  case "$PS_RESULT" in clean|unproven) echo 0 ;; not-run) echo 2 ;; unsupported) echo 3 ;; needs|failed) echo 1 ;; *) echo 4 ;; esac
}

# --property-sets / --fix-property-sets: only this check, then exit. Stands alone so
# sync-project.sh and an agent about to merge can run it without waiting through the rest.
if [ -n "$PS_MODE" ]; then
  if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "usage: $0 --property-sets|--fix-property-sets [--if-stale] <project-dir>" >&2; exit 2
  fi
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  PROJECT_ROOT="$PROJECT_DIR"
  # shellcheck disable=SC1091
  . "$TOOLKIT_ROOT/project-bin/_common.sh"
  MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
  [ -n "$MPR" ] || MPR="$(ls "$PROJECT_DIR"/app/*.mpr 2>/dev/null | head -1)"
  # Multi-app folder (#420): MPR_FILE picks the app; otherwise the first is checked and the
  # screen says so, naming the others, rather than silently checking one of several.
  _ps_apps=""
  if [ -z "$MPR" ] && ls "$PROJECT_DIR"/apps/*/*.mpr >/dev/null 2>&1; then
    if [ -n "${MPR_FILE:-}" ] && [ -f "$PROJECT_DIR/${MPR_FILE#"$PROJECT_DIR"/}" ]; then
      MPR="$PROJECT_DIR/${MPR_FILE#"$PROJECT_DIR"/}"
    else
      MPR="$(ls "$PROJECT_DIR"/apps/*/*.mpr | head -1)"
      [ "$(ls "$PROJECT_DIR"/apps/*/*.mpr | wc -l | tr -d ' ')" -gt 1 ] \
        && _ps_apps="$(cd "$PROJECT_DIR" && ls apps/*/*.mpr | paste -s -d, - | sed 's/,/, /g')"
    fi
  fi
  PMXCLI_PROBE="$(find_project_mxcli 2>/dev/null || true)"
  head_ "Property sets (Studio Pro merge safety): $PROJECT_DIR"
  [ -n "$_ps_apps" ] && note "multi-app folder ($_ps_apps): checking ${MPR#"$PROJECT_DIR"/} only — rerun with MPR_FILE=apps/<X>/<X>.mpr for each other app"
  if [ "$PS_IF_STALE" = 1 ] && [ "$PS_MODE" = check ] && [ -n "$PMXCLI_PROBE" ]; then
    PS_VER="$(ps_version "$PMXCLI_PROBE")"
    if [ -n "$PS_VER" ] && ! ps_stale; then
      PS_RESULT="$(sed -n '1s/^[^ ]* [^ ]* \([^ ]*\).*/\1/p' "$(ps_receipt)")"
      # Only a settled "nothing to do here" short-circuits; needs/failed re-check every time.
      case "$PS_RESULT" in
        clean|unsupported)
          ok "already checked for $PS_VER: $(sed -n 1p "$(ps_receipt)")"
          exit "$(ps_exit_code)" ;;
        unproven)
          ps_unproven_warn "already checked for $PS_VER: $(sed -n 1p "$(ps_receipt)")" "$(mxtk_model_version "$MPR" 2>/dev/null || true)"
          exit "$(ps_exit_code)" ;;
      esac
    fi
  fi
  ps_check
  [ "$PS_MODE" = fix ] && [ "$PS_RESULT" = needs ] && ps_apply
  exit "$(ps_exit_code)"
fi

# recommended_fix — ONE block that ends both the normal run and --bench: the first option that works on THIS
# machine, in this order. Read-only, cheap probes; never installs anything and never asks for IT's help.
#   0. MH_STALE (machine_health): the project runs older local copies of the speed scripts -> upgrade them
#      first; every other measurement is of the old path. Then MH_SYNC (project in a sync folder) -> move it.
#   a. PROJECT.md says `Gate mode: full` -> remove that line: `mx check` per exec is the default, with the
#      full build before every push (offered even when nothing is slow: it helps every machine).
#   b. process starts are slow AND this is Git Bash AND `wsl.exe --status` succeeds -> run the toolkit in WSL.
#   c. slow AND a docker/podman CLI is present and runs (`--version`, no daemon call) -> a dev container.
#   d. slow, none of the above -> let Claude work in the cloud (Claude Code on the web), pull with git pull.
# "slow" = RF_SPAWN_MS (ms per process start) over MXTK_SPAWN_WARN_MS (30), set by the caller.
RF_SPAWN_MS=""
recommended_fix() {
  head_ "Recommended fix"
  _rf_slow=0
  [ -n "$RF_SPAWN_MS" ] && [ "$RF_SPAWN_MS" -gt "${MXTK_SPAWN_WARN_MS:-30}" ] && _rf_slow=1
  if [ -n "${MH_STALE:-}" ]; then
    # --only-bin scopes the install to the named scripts: --upgrade-bin alone runs the FULL sync (#390).
    _rf_list="$MH_STALE"
    case " $MH_STALE " in *" exec.sh "*) case " $MH_STALE " in *" _common.sh "*) ;; *) _rf_list="$_rf_list _common.sh" ;; esac ;; esac
    _rf_up=""; for _rf_s in $_rf_list; do _rf_up="$_rf_up --only-bin $_rf_s --upgrade-bin $_rf_s"; done
    echo "  Take the toolkit's current scripts into this project; the toolkit update did not reach them,"
    echo "  because sync never overwrites a script that was edited here. Each copy is backed up first:"
    echo "    <toolkit>/bin/sync-project.sh <project>$_rf_up"
    echo "  Check with whoever edited them that the local change is no longer needed. Then run doctor --bench again."
    return 0
  fi
  _rf_pm=""
  if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/PROJECT.md" ]; then
    _rf_pm="$(sed -n 's/^[*_ ]*Gate mode:[*_ ]*\([A-Za-z]*\).*/\1/p' "$PROJECT_DIR/PROJECT.md" 2>/dev/null | head -1 | tr 'A-Z' 'a-z')"
    if [ "$_rf_pm" = full ]; then
      echo "  Remove \"Gate mode: full\" from PROJECT.md (one line). Each model write is then checked with the quick"
      echo "  mx check instead of a full build, and the full build runs before you push and at module close."
      return 0
    fi
  fi
  if [ -n "${MH_SYNC:-}" ]; then
    echo "  Move the project out of $MH_SYNC to a plain local folder (for example C:\\dev\\<project> or ~/dev/<project>),"
    echo "  then reopen it there. A sync client re-reads and uploads every file git and the build touch, which"
    echo "  slows every step and can lock the model file mid-write."
    return 0
  fi
  if [ "$_rf_slow" = 0 ] && [ "${MH_BAD:-0}" = 1 ]; then
    echo "  Free up memory first (see Machine health). Simplest: restart the computer, which also ends Mendix"
    echo "  build processes that were left running. Or, without a restart: bin/doctor.sh --cleanup, which asks"
    echo "  before it stops anything. Process starts are not slow here${RF_SPAWN_MS:+ ($RF_SPAWN_MS ms each)}."
    return 0
  fi
  # One step far slower than the reference while process starts are fine: name that step, never "None needed".
  # Threshold: the slowest step is 5x+ the reference AND costs 2 s+ extra (B_TOP_* from --bench; 0 otherwise).
  if [ "$_rf_slow" = 0 ] && [ "${B_TOP_F10:-0}" -ge 50 ] && [ "${B_TOP_EXCESS:-0}" -ge 2000 ]; then
    case "$B_TOP_ID" in
      git)
        echo "  git is slow in this project (git status: $(( (B_TOP_EXCESS + BENCH_REF_GIT_MS) / 100 / 10 )).$(( (B_TOP_EXCESS + BENCH_REF_GIT_MS) / 100 % 10 )) s; normal is well under 1 s)."
        echo "  Turn on git's own file cache for this project (no install, no admin rights):"
        echo "    git config core.untrackedCache true"
        [ "$MH_OS" != linux ] && echo "    git config core.fsmonitor true"
        echo "  Then run doctor --bench again. Still slow: check that no large build output or source dump is"
        echo "  tracked in git (git count-objects -vH)." ;;
      *)
        echo "  One step is much slower than the reference: $B_TOP_LABEL. Process starts are fine, so this is"
        echo "  probably a one-off (first run after a restart or an update). Run doctor --bench once more; if"
        echo "  the same step is still slow, send the results file to the toolkit maintainers." ;;
    esac
    return 0
  fi
  if [ "$_rf_slow" = 0 ]; then
    echo "  None needed: process starts are not slow here${RF_SPAWN_MS:+ ($RF_SPAWN_MS ms each)}."
    return 0
  fi
  if [ "$MH_OS" = gitbash ] && command -v wsl.exe >/dev/null 2>&1; then
    _rf_ok=0
    if command -v timeout >/dev/null 2>&1; then timeout 10 wsl.exe --status >/dev/null 2>&1 && _rf_ok=1
    else wsl.exe --status >/dev/null 2>&1 && _rf_ok=1; fi
    if [ "$_rf_ok" = 1 ]; then
      echo "  Run the toolkit in WSL (already on this machine). Process starts there are cheap, and the project"
      echo "  folder should live inside the WSL filesystem, not under /mnt/c."
      return 0
    fi
  fi
  _rf_rt="${MXTK_CONTAINER_RUNTIME:-}"
  if [ -z "$_rf_rt" ]; then
    if command -v docker >/dev/null 2>&1; then _rf_rt=docker; elif command -v podman >/dev/null 2>&1; then _rf_rt=podman; fi
  fi
  if [ -n "$_rf_rt" ] && "$_rf_rt" --version >/dev/null 2>&1; then
    echo "  Use a dev container ($_rf_rt is installed here). Process starts inside it are cheap."
    return 0
  fi
  echo "  Let Claude work in the cloud (Claude Code on the web), then pull the result into Studio Pro with git pull."
  echo "  Nothing needs installing on this machine, and nobody's permission is needed."
}

# --- machine health (leftover mxbuild helpers, free memory) -- and --cleanup / --bench ---------------
# WHY. Field, 2026-10-29, Linux 4 cores / 16 GB: mxbuild kept dying with exit 137. 47 orphaned
# `modeler/tools/deno` processes (parent PID 1, up to 37 min old, ~270 MB each, 13 GB in total) had eaten the
# memory. mxbuild starts one deno helper per run; when mxbuild is killed (gate timeout, `kill`, the
# out-of-memory killer itself) the helper outlives it, and every orphan makes the next kill more likely.
# A run that ends normally leaves none (checked, tools/deno helper gone within a second).
#
# A "leftover" is: a process whose program path contains modeler/tools/deno (deno / deno.exe), older than
# MXTK_LEFTOVER_MIN_AGE_S (default 600 s), whose parent is NOT a live mxbuild / mx / dotnet / Studio Pro.
# The parent test is why a long but healthy build (a big model builds longer than 10 minutes) is never
# listed, and so never stopped by --cleanup. Golden input: tests/wave2/fixtures/doctor-bench/ (a real
# `ps -eo pid,ppid,etimes,rss,args` capture that contains one live helper and four orphans).
# Platforms: Linux/WSL: ps etimes + /proc/meminfo. macOS: ps etime + vm_stat. Git Bash: wmic (tasklist as a
# count-only fallback). The Git Bash branch is written from wmic's documented /format:list output and has not
# been run on Windows; the Linux branch is the one field-proven here.
MH_MIN_AGE="${MXTK_LEFTOVER_MIN_AGE_S:-600}"
MH_LOW_MB="${MXTK_LOW_MEMORY_MB:-2048}"
case "$(uname -s 2>/dev/null)" in
  Darwin) MH_OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) MH_OS=gitbash ;;
  *) MH_OS=linux ;;
esac

# mh_rows — one line per process: pid ppid age-or-etime rss_kb program args...
mh_rows() {
  case "$MH_OS" in
    macos) ps -axo pid=,ppid=,etime=,rss=,args= 2>/dev/null ;;
    gitbash)
      command -v wmic >/dev/null 2>&1 || return 1
      wmic process where "name='deno.exe' or name='mxbuild.exe' or name='mx.exe' or name='dotnet.exe'" \
        get CommandLine,CreationDate,Name,ParentProcessId,ProcessId,WorkingSetSize /format:list 2>/dev/null \
        | tr -d '\r' | awk '
          function flush() { if (pid != "") { age = (cd != "") ? systime() - mktime(substr(cd,1,4) " " substr(cd,5,2) " " substr(cd,7,2) " " substr(cd,9,2) " " substr(cd,11,2) " " substr(cd,13,2)) : 0
            print pid, ppid, age, int(ws / 1024), nm, cl }
            pid = ppid = cd = nm = cl = ""; ws = 0 }
          { i = index($0, "="); if (i == 0) { if ($0 == "") flush(); next }
            k = substr($0, 1, i - 1); v = substr($0, i + 1)
            if (k == "ProcessId") pid = v; else if (k == "ParentProcessId") ppid = v
            else if (k == "CreationDate") cd = v; else if (k == "Name") nm = v
            else if (k == "WorkingSetSize") ws = v; else if (k == "CommandLine") cl = v }
          END { flush() }' ;;
    *) ps -eo pid,ppid,etimes,rss,args 2>/dev/null ;;
  esac
}

# mh_leftovers — the leftover helpers, one line each: pid age_seconds rss_kb
mh_leftovers() {
  mh_rows | awk -v min="$MH_MIN_AGE" '
    function secs(t,   a, p, n, d) {
      if (t !~ /[:-]/) return t + 0
      d = 0; if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
      n = split(t, p, ":"); return d * 86400 + ((n == 3) ? p[1] * 3600 + p[2] * 60 + p[3] : p[1] * 60 + p[2]) }
    $1 !~ /^[0-9]+$/ { next }
    { line = $0; gsub(/\\/, "/", line)
      pid = $1; pp[pid] = $2; age[pid] = secs($3); rss[pid] = $4; first[pid] = $5; all[pid] = line; ord[++n] = pid }
    END { for (i = 1; i <= n; i++) { p = ord[i]; f = first[p]; gsub(/\\/, "/", f)
        if (!(f ~ /modeler\/tools\/deno\/.*\/deno$/ || (f == "deno.exe" && all[p] ~ /modeler\/tools\/deno/))) continue
        if (age[p] < min) continue
        q = pp[p]
        if (q in first) { g = first[q]; gsub(/\\/, "/", g); sub(/.*\//, "", g)
          if (g ~ /^(mxbuild|mx|mxutil|dotnet|MxBuild)(\.exe)?$/ || g ~ /[Ss]tudio/) continue }
        print p, age[p], rss[p] } }'
}

# mh_free_mb — megabytes of memory a new process could get, or nothing when this platform cannot say.
mh_free_mb() {
  case "$MH_OS" in
    macos) vm_stat 2>/dev/null | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
             /^Pages free:|^Pages inactive:|^Pages speculative:/ { gsub(/\./, "", $NF); pg += $NF }
             END { if (ps > 0 && pg > 0) print int(pg * ps / 1048576) }' ;;
    gitbash) command -v wmic >/dev/null 2>&1 || return 0
             wmic OS get FreePhysicalMemory /value 2>/dev/null | tr -d '\r' | awk -F= '$1 == "FreePhysicalMemory" && $2 + 0 > 0 { print int($2 / 1024) }' ;;
    *) awk '/^MemAvailable:/ { a = $2 } /^MemFree:/ { f = $2 } /^Buffers:/ { b = $2 } /^Cached:/ { c = $2 }
            END { if (a > 0) print int(a / 1024); else if (f > 0) print int((f + b + c) / 1024) }' "${MXTK_PROC_MEMINFO:-/proc/meminfo}" 2>/dev/null ;;
  esac
}

# mh_fmt_mb <mb> — "1.9 GB" / "640 MB" into MH_FMT (no subshell: a process start costs 100 ms on Windows).
mh_fmt_mb() {
  if [ "$1" -ge 1024 ]; then MH_FMT="$(( $1 * 10 / 1024 / 10 )).$(( $1 * 10 / 1024 % 10 )) GB"; else MH_FMT="$1 MB"; fi
}

# advise — prints like warn but does not count toward the exit code: machine health is about this
# machine's state right now, not about the toolkit install, and doctor's exit code is read by
# callers (#591 review). session-check still shows the line, because it greps for WARN.
advise() { printf '  WARN  %s\n' "$*"; }
MH_BAD=0
machine_health() {
  head_ "Machine health"
  _mh_free="$(mh_free_mb)"
  _mh_can=1
  if [ "$MH_OS" = gitbash ]; then command -v wmic >/dev/null 2>&1 || _mh_can=0; else command -v ps >/dev/null 2>&1 || _mh_can=0; fi
  _mh_left=""; [ "$_mh_can" = 1 ] && _mh_left="$(mh_leftovers)"
  _mh_n=0; _mh_kb=0; _mh_old=0
  if [ -n "$_mh_left" ]; then
    _mh_sum="$(printf '%s\n' "$_mh_left" | awk '{ n++; kb += $3; if ($2 > old) old = $2 } END { print n, kb, old }')"
    set -- $_mh_sum; _mh_n=$1; _mh_kb=$2; _mh_old=$3
  fi
  _mh_bad=0
  if [ -z "$_mh_free" ]; then
    note "free memory: not measured on this platform"
  elif [ "$_mh_free" -lt "$MH_LOW_MB" ]; then
    mh_fmt_mb "$_mh_free"; advise "free memory: $MH_FMT (under $((MH_LOW_MB / 1024)) GB)"; _mh_bad=1
  else
    mh_fmt_mb "$_mh_free"; ok "free memory: $MH_FMT"
  fi
  if [ "$_mh_n" -gt 0 ]; then
    mh_fmt_mb "$((_mh_kb / 1024))"
    advise "$_mh_n leftover mxbuild helper process(es) (deno), $MH_FMT in total, oldest $((_mh_old / 60)) min"
    _mh_bad=1
  elif [ "$_mh_can" = 0 ]; then
    note "leftover mxbuild helpers: not checked (this machine has no ps / wmic to list processes)"
  else
    ok "no leftover mxbuild helper processes"
  fi
  # Project inside a file-sync folder (OneDrive is where Windows puts Documents and Desktop by default).
  MH_SYNC=""; _mh_pd=""
  [ -n "${PROJECT_DIR:-}" ] && _mh_pd="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)"
  # Whole path components only: ~/dev/dropbox-client or a repo named OneDrive-connector must not match.
  case "$_mh_pd/" in
    */OneDrive/*|*/"OneDrive - "*/*) MH_SYNC=OneDrive ;;
    */Dropbox/*|*/"Dropbox ("*/*) MH_SYNC=Dropbox ;;
    */"Google Drive"/*|*/GoogleDrive/*|*/"My Drive"/*) MH_SYNC="Google Drive" ;;
    */"Mobile Documents"/*|*/"iCloud Drive"/*) MH_SYNC=iCloud ;;
  esac
  [ -n "$MH_SYNC" ] && advise "the project is in a folder synced by $MH_SYNC: $_mh_pd"
  # Speed fixes not active: the project's bin/ holds an OLDER local copy of a script the 2026-10-29 speed
  # work changed. sync-project.sh never overwrites a hand-edited copy, so after a toolkit pull these keep
  # running the slow path (field, 2026-10-30: 15 drifted scripts, every change still ran a full mxbuild).
  # Marker per file = a function or file name the fixed version has; absent file = not this check's business.
  MH_STALE=""
  if [ -n "$_mh_pd" ]; then
    for _mh_s in "exec.sh:gate_kind_decide" "_common.sh:mxtk_mx_check_to_mxbuild" "lint-gate.sh:lint-receipt-ok"; do
      _mh_f="$_mh_pd/bin/${_mh_s%%:*}"
      [ -f "$_mh_f" ] && ! grep -q "${_mh_s#*:}" "$_mh_f" 2>/dev/null && MH_STALE="$MH_STALE ${_mh_s%%:*}"
    done
    MH_STALE="${MH_STALE# }"
  fi
  [ -n "$MH_STALE" ] && advise "speed fixes not active in this project: older local copy of bin/$(printf '%s' "$MH_STALE" | sed 's/ /, bin\//g')"
  MH_BAD="$_mh_bad"
  if [ "$_mh_bad" = 1 ]; then
    note "When memory runs out the operating system kills mxbuild (exit 137), and the build gate then reads"
    note "as a failure that is not about your model. Each mxbuild that is killed leaves its deno helper"
    note "running, holding ~270 MB, so the problem grows by itself."
    [ "$_mh_n" -gt 0 ] && note "Stop exactly those helpers (asks first):  bin/doctor.sh --cleanup"
    [ "$_mh_n" -eq 0 ] && note "Close other programs, or run the toolkit on a machine with more memory."
  fi
}

# --cleanup: list the leftovers machine_health counts, stop them ONLY after a typed y at a terminal.
if [ "$CLEANUP" = 1 ]; then
  head_ "Cleanup: leftover mxbuild helpers (deno)"
  if [ "$MH_OS" = gitbash ]; then command -v wmic >/dev/null 2>&1 || { bad "cannot list processes: wmic is missing. Use Task Manager (deno.exe under modeler\\tools\\deno)."; exit 1; }
  else command -v ps >/dev/null 2>&1 || { bad "cannot list processes: no ps on this machine."; exit 1; }; fi
  _cl="$(mh_leftovers)"
  if [ -z "$_cl" ]; then ok "nothing to clean up: no deno helper from modeler/tools/deno older than $((MH_MIN_AGE / 60)) min without a live mxbuild"; exit 0; fi
  _cl_pids="$(printf '%s\n' "$_cl" | awk '{ printf "%s%s", sep, $1; sep = " " }')"
  printf '%s\n' "$_cl" | awk '{ printf "        pid %-7s %4d min  %4d MB\n", $1, $2 / 60, $3 / 1024 }'
  case "$MH_OS" in
    gitbash) _cl_cmd="taskkill //F$(for _p in $_cl_pids; do printf ' //PID %s' "$_p"; done)" ;;
    *)       _cl_cmd="kill $_cl_pids" ;;
  esac
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    note "No terminal to ask on, so nothing was stopped. To stop exactly these yourself:"
    note "  $_cl_cmd"
    exit 0
  fi
  printf '  Stop these %s process(es)? Type y to confirm, anything else cancels: ' "$(printf '%s\n' "$_cl" | wc -l | tr -d ' ')"
  _cl_ans=""; read -r _cl_ans || true
  if [ "$_cl_ans" != "y" ] && [ "$_cl_ans" != "Y" ]; then note "Cancelled. Nothing was stopped."; exit 0; fi
  # Re-read the list: only a pid that is STILL a leftover is touched (pids get reused).
  _cl_now=" $(mh_leftovers | awk '{ printf "%s ", $1 }')"
  _cl_done=0
  for _p in $_cl_pids; do
    case "$_cl_now" in *" $_p "*) ;; *) note "pid $_p is gone or no longer a leftover: left alone"; continue ;; esac
    if [ "$MH_OS" = gitbash ]; then taskkill //F //PID "$_p" >/dev/null 2>&1 || true; else kill "$_p" 2>/dev/null || true; fi
    _cl_done=$((_cl_done + 1))
  done
  sleep 2
  _cl_left=" $(mh_leftovers | awk '{ printf "%s ", $1 }')"
  _cl_alive=""
  for _p in $_cl_pids; do case "$_cl_left" in *" $_p "*) _cl_alive="$_cl_alive $_p" ;; esac; done
  ok "asked $_cl_done process(es) to stop"
  if [ -n "$_cl_alive" ]; then
    warn "still running after 2 s:$_cl_alive"
    note "Not forced. If you want them gone anyway:  kill -9$_cl_alive"
  fi
  exit 0
fi

# --bench: ~1 minute, changes nothing in the project (only git's own stat cache, via the warm-up below). Times the things every toolkit script is made of,
# against this table's reference column, so "the toolkit is slow here" becomes a number a colleague can
# compare. Writes <project>/.claude/loop/bench-<timestamp>.tsv (one row per step, concatenable).
#
# REFERENCE (BENCH_REF_*, milliseconds): measured on 2026-10-29 on Linux 6.18 (Firecracker VM, 4 cores,
# 16 GB, local disk), project = a copy of the purchase-requests test app (PurchaseApp, mxcli v0.28.0, mx 11.13.0, git with 6.5k
# files): the median of 5 `bin/doctor.sh --bench` runs. Honest caveat: the machine was not freshly idle; it
# held 46 leftover deno helpers and ~1.4 GB free memory during those runs (CPU-bound steps do not care, and
# no step swapped: there is no swap), so treat the reference as "a Linux box, a bit loaded", not a lab figure.
# For scale, a Windows 11 / Git Bash laptop in the field measured 103 ms per process start against ~2 ms
# here: that one number is what makes every step below that is built from process starts (git, gate-check,
# mxcli, the doctor itself) many times slower there.
BENCH_REF_SPAWN50_MS=86
BENCH_REF_GIT_MS=34
BENCH_REF_PY_MS=28
BENCH_REF_NODE_MS=74
BENCH_REF_GATE_MS=3237
BENCH_REF_MXCLI_MS=606
BENCH_REF_MX_MS=6902
BENCH_FIELD_SPAWN_MS=103
BENCH_MX_MIN_MB="${MXTK_BENCH_MX_MIN_MB:-1024}"

# b_clock — sets B_MS to a millisecond clock reading, or "" when this shell has none. EPOCHREALTIME (bash 5,
# Git Bash) costs no process; `date +%s%N` does (GNU date only: macOS prints a literal N, bash 3.2 has neither).
b_clock() {
  B_MS=""
  if [ -n "${EPOCHREALTIME:-}" ]; then
    B_MS="${EPOCHREALTIME/[.,]/}"; B_MS=$((B_MS / 1000)); return 0
  fi
  _bc="$(date +%s%N 2>/dev/null || true)"
  case "$_bc" in ""|*[!0-9]*) return 0 ;; esac
  B_MS=$((_bc / 1000000))
}

# b_bounded <seconds> <cmd...> — run with output discarded, stdin closed, killed after <seconds>. B_RC = exit
# code, 124 on timeout. No timeout(1) assumed (macOS has none). Polls every 0.2 s.
b_bounded() {
  _bb_max=$(( $1 * 5 )); shift
  "$@" >/dev/null 2>&1 < /dev/null &
  _bb_pid=$!; _bb_w=0
  while kill -0 "$_bb_pid" 2>/dev/null; do
    if [ "$_bb_w" -ge "$_bb_max" ]; then kill "$_bb_pid" 2>/dev/null; wait "$_bb_pid" 2>/dev/null; B_RC=124; return 0; fi
    sleep 0.2 2>/dev/null || sleep 1
    _bb_w=$((_bb_w + 1))
  done
  B_RC=0; wait "$_bb_pid" || B_RC=$?
}

b_fmt_ms() {
  if [ "$1" -ge 10000 ]; then B_FMT="$(( $1 / 1000 )).$(( $1 % 1000 / 100 )) s"
  elif [ "$1" -ge 1000 ]; then B_FMT="$(( $1 / 1000 )).$(( $1 % 1000 / 10 / 10 ))$(( $1 % 1000 / 10 % 10 )) s"
  else B_FMT="$1 ms"; fi
}

# b_row <id> <label> <this-ms|""> <ref-ms> <note> — print the table row, append the TSV row, feed the verdict.
B_SPAWN_FAC=""; B_TOP_ID=""; B_TSV=""; B_TOT_THIS=0; B_TOT_REF=0; B_NMEAS=0; B_TOP_EXCESS=0; B_TOP_LABEL=""; B_TOP_F10=0; B_SPAWN_THIS=""; B_NOTES=""
b_row() {
  _r_id="$1"; _r_label="$2"; _r_this="$3"; _r_ref="$4"; _r_note="$5"
  b_fmt_ms "$_r_ref"; _r_reffmt="$B_FMT"
  if [ -n "$_r_this" ]; then
    b_fmt_ms "$_r_this"; _r_thisfmt="$B_FMT"
    _r_f10=0
    if [ "$_r_ref" -gt 0 ]; then _r_f10=$(( _r_this * 10 / _r_ref )); _r_fac="$((_r_f10 / 10)).$((_r_f10 % 10))"; else _r_fac="-"; fi
    B_TOT_THIS=$((B_TOT_THIS + _r_this)); B_TOT_REF=$((B_TOT_REF + _r_ref)); B_NMEAS=$((B_NMEAS + 1))
    if [ $((_r_this - _r_ref)) -gt "$B_TOP_EXCESS" ]; then B_TOP_EXCESS=$((_r_this - _r_ref)); B_TOP_LABEL="$_r_label"; B_TOP_ID="$_r_id"; B_TOP_F10="${_r_f10:-0}"; fi
    [ "$_r_id" = spawn50 ] && B_SPAWN_THIS="$_r_this" && B_SPAWN_FAC="$_r_fac"
  else
    _r_thisfmt="not measured"; _r_fac="-"
  fi
  printf '  %-30s %13s %11s %8s\n' "$_r_label" "$_r_thisfmt" "$_r_reffmt" "${_r_fac}$([ "$_r_fac" = "-" ] || printf x)"
  [ -n "$_r_note" ] && B_NOTES="$B_NOTES        $_r_label: $_r_note
"
  B_TSV="$B_TSV$B_STAMP	$B_PLAT	$B_CORES	${_mh_free:-NA}	$_r_id	${_r_this:-NA}	$_r_ref	$_r_fac	$_r_note
"
}

if [ "$BENCH" = 1 ]; then
  machine_health
  head_ "Benchmark (changes nothing; about a minute)"
  B_STAMP="$(date '+%Y%m%d-%H%M%S')"
  B_PLAT="$(uname -s 2>/dev/null)-$(uname -m 2>/dev/null)"
  B_CORES="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf '%s' "${NUMBER_OF_PROCESSORS:-NA}") | head -1)"
  B_P="$PROJECT_DIR"
  b_clock
  if [ -z "$B_MS" ]; then note "no sub-second clock in this shell (bash 3.2 / BSD date): short steps print \"not measured\""; fi
  printf '  %-30s %13s %11s %8s\n' "step" "this machine" "reference" "factor"

  # 1. process starts
  _bt="$(command -v true 2>/dev/null)"; case "$_bt" in /*) ;; *) _bt=/bin/true ;; esac
  b_clock; _t0="$B_MS"; _i=0
  while [ $_i -lt 50 ]; do "$_bt"; _i=$((_i + 1)); done
  b_clock; _t1="$B_MS"
  if [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row spawn50 "50 process starts" "$((_t1 - _t0))" "$BENCH_REF_SPAWN50_MS" ""
  else b_row spawn50 "50 process starts" "" "$BENCH_REF_SPAWN50_MS" "no sub-second clock"; fi

  # 2. git status. One untimed warm-up first: a copied or freshly cloned project has a stale index, and the
  # first git status there pays a one-off full re-read (field, 2026-10-29: 18.3 s, then 0.03 s). The warm-up
  # is an ordinary `git status`, which only refreshes git's own file-stat cache (.git/index), exactly as
  # the user's next git status would; no tracked or untracked project file changes. The timed run is warm.
  if [ -z "$B_P" ]; then b_row git "git status" "" "$BENCH_REF_GIT_MS" "no project given"
  elif ! command -v git >/dev/null 2>&1; then b_row git "git status" "" "$BENCH_REF_GIT_MS" "git not installed"
  elif ! git -C "$B_P" rev-parse --git-dir >/dev/null 2>&1; then b_row git "git status" "" "$BENCH_REF_GIT_MS" "project is not a git repository"
  else
    git -C "$B_P" status --porcelain >/dev/null 2>&1 < /dev/null
    b_clock; _t0="$B_MS"; GIT_OPTIONAL_LOCKS=0 git -C "$B_P" status --porcelain >/dev/null 2>&1 < /dev/null; b_clock; _t1="$B_MS"
    if [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row git "git status" "$((_t1 - _t0))" "$BENCH_REF_GIT_MS" ""
    else b_row git "git status" "" "$BENCH_REF_GIT_MS" "no sub-second clock"; fi
  fi

  # 3. python, node
  _bpy=""; for _c in python3 python; do command -v "$_c" >/dev/null 2>&1 && { _bpy="$_c"; break; }; done
  if [ -z "$_bpy" ]; then b_row python "python start" "" "$BENCH_REF_PY_MS" "python not installed"
  else
    b_clock; _t0="$B_MS"; "$_bpy" -c pass >/dev/null 2>&1 < /dev/null; b_clock; _t1="$B_MS"
    if [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row python "python start" "$((_t1 - _t0))" "$BENCH_REF_PY_MS" ""
    else b_row python "python start" "" "$BENCH_REF_PY_MS" "no sub-second clock"; fi
  fi
  if ! command -v node >/dev/null 2>&1; then b_row node "node start" "" "$BENCH_REF_NODE_MS" "node not installed"
  else
    b_clock; _t0="$B_MS"; node -e 0 >/dev/null 2>&1 < /dev/null; b_clock; _t1="$B_MS"
    if [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row node "node start" "$((_t1 - _t0))" "$BENCH_REF_NODE_MS" ""
    else b_row node "node start" "" "$BENCH_REF_NODE_MS" "no sub-second clock"; fi
  fi

  # 4. gate-check, no stage. --no-html: the dashboard is not rewritten. It still refreshes
  # analysis/source-sufficiency.html in some projects, so that one file is put back after the run.
  if [ -z "$B_P" ]; then b_row gate "gate-check (no stage)" "" "$BENCH_REF_GATE_MS" "no project given"
  elif [ ! -f "$TOOLKIT_ROOT/bin/gate-check.sh" ]; then b_row gate "gate-check (no stage)" "" "$BENCH_REF_GATE_MS" "gate-check.sh not found"
  else
    _bs="$B_P/analysis/source-sufficiency.html"; _bsave=""
    if [ -f "$_bs" ]; then _bsave="$(mktemp "${TMPDIR:-/tmp}/doctor-bench.XXXXXX")" && cp "$_bs" "$_bsave"; fi
    b_clock; _t0="$B_MS"; b_bounded 120 env MXTK_NO_FETCH=1 bash "$TOOLKIT_ROOT/bin/gate-check.sh" --no-html "$B_P"; b_clock; _t1="$B_MS"
    if [ -n "$_bsave" ]; then cmp -s "$_bs" "$_bsave" || cp "$_bsave" "$_bs"; rm -f "$_bsave"; fi
    if [ "$B_RC" = 124 ]; then b_row gate "gate-check (no stage)" "" "$BENCH_REF_GATE_MS" "gave up after 120 s"
    elif [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row gate "gate-check (no stage)" "$((_t1 - _t0))" "$BENCH_REF_GATE_MS" ""
    else b_row gate "gate-check (no stage)" "" "$BENCH_REF_GATE_MS" "no sub-second clock"; fi
  fi

  # 5/6. mxcli check (read-only on the model) and mx check (on a COPY: mx writes into the project it checks)
  _bmpr=""
  if [ -n "$B_P" ]; then for _f in "$B_P"/*.mpr "$B_P"/app/*.mpr; do [ -f "$_f" ] && { _bmpr="$_f"; break; }; done; fi
  _bmxcli=""
  if [ -n "$B_P" ] && [ -x "$B_P/mxcli" ]; then _bmxcli="$B_P/mxcli"; elif command -v mxcli >/dev/null 2>&1; then _bmxcli="$(command -v mxcli)"; fi
  _btmp="$(mktemp -d "${TMPDIR:-/tmp}/doctor-bench.XXXXXX")"
  trap 'rm -rf "$_btmp"' EXIT
  if [ -z "$_bmpr" ]; then b_row mxcli "mxcli check (tiny script)" "" "$BENCH_REF_MXCLI_MS" "no .mpr in the project"
  elif [ -z "$_bmxcli" ]; then b_row mxcli "mxcli check (tiny script)" "" "$BENCH_REF_MXCLI_MS" "mxcli not found"
  else
    printf 'create module MxtkBenchProbe;\ncreate persistent entity MxtkBenchProbe.Probe (Name: String(20));\n' > "$_btmp/probe.mdl"
    b_clock; _t0="$B_MS"; b_bounded 60 "$_bmxcli" check "$_btmp/probe.mdl" -p "$_bmpr"; b_clock; _t1="$B_MS"
    if [ "$B_RC" = 124 ]; then b_row mxcli "mxcli check (tiny script)" "" "$BENCH_REF_MXCLI_MS" "gave up after 60 s"
    elif [ "$B_RC" != 0 ]; then b_row mxcli "mxcli check (tiny script)" "" "$BENCH_REF_MXCLI_MS" "mxcli exited $B_RC"
    elif [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row mxcli "mxcli check (tiny script)" "$((_t1 - _t0))" "$BENCH_REF_MXCLI_MS" ""
    else b_row mxcli "mxcli check (tiny script)" "" "$BENCH_REF_MXCLI_MS" "no sub-second clock"; fi
  fi

  PROJECT_ROOT="${PROJECT_DIR:-$TOOLKIT_ROOT}"
  # shellcheck disable=SC1091
  . "$TOOLKIT_ROOT/project-bin/_common.sh"
  _bmx="$(mxtk_find_mx 2>/dev/null || true)"
  if [ -z "$_bmpr" ]; then b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "no .mpr in the project"
  elif [ -z "$_bmx" ]; then b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "mx not installed (it ships beside mxbuild)"
  elif [ -n "$_mh_free" ] && [ "$_mh_free" -lt "$BENCH_MX_MIN_MB" ]; then
    b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "not run: only ${_mh_free} MB free (needs ~${BENCH_MX_MIN_MB}); at this level mxbuild is killed with exit 137"
  else
    _bcp="$_btmp/model"; mkdir -p "$_bcp"; cp "$_bmpr" "$_bcp/" 2>/dev/null
    [ -d "$(dirname "$_bmpr")/mprcontents" ] && cp -R "$(dirname "$_bmpr")/mprcontents" "$_bcp/" 2>/dev/null
    b_clock; _t0="$B_MS"; b_bounded 180 "$_bmx" check "$_bcp/$(basename "$_bmpr")" -j "$_btmp/mx.json"; b_clock; _t1="$B_MS"
    if [ "$B_RC" = 124 ]; then b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "gave up after 180 s (a killed mx can leave its deno helper: bin/doctor.sh --cleanup)"
    elif [ "$B_RC" = 137 ]; then b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "KILLED (exit 137): out of memory. This is the failure Machine health warns about"
    elif [ -n "$_t0" ] && [ -n "$_t1" ]; then b_row mx "mx check (copy of model)" "$((_t1 - _t0))" "$BENCH_REF_MX_MS" "mx exit $B_RC (errors in the copy are fine; only the time counts)"
    else b_row mx "mx check (copy of model)" "" "$BENCH_REF_MX_MS" "no sub-second clock"; fi
  fi

  # verdict
  [ -n "$B_NOTES" ] && printf '%s' "$B_NOTES"
  echo
  if [ -n "$B_SPAWN_THIS" ]; then
    _bper10=$(( B_SPAWN_THIS * 10 / 50 ))
    echo "  process start: $((_bper10 / 10)).$((_bper10 % 10)) ms each here; ~$((BENCH_REF_SPAWN50_MS * 10 / 50 / 10)).$((BENCH_REF_SPAWN50_MS * 10 / 50 % 10)) ms on the reference; $BENCH_FIELD_SPAWN_MS ms on the slow Windows 11 / Git Bash laptop in the field."
  fi
  if [ "$B_NMEAS" -lt 1 ] || [ "$B_TOT_REF" -le 0 ]; then
    echo "  Verdict: nothing could be measured here, so there is nothing to compare."
  else
    _bfac=$(( (B_TOT_THIS * 10 + B_TOT_REF / 2) / B_TOT_REF ))
    _bwhy="$B_TOP_LABEL"
    case "$B_SPAWN_FAC" in ""|-) ;; *) _bsf="${B_SPAWN_FAC%%.*}"; [ "$_bsf" -ge 5 ] && [ "$_bfac" -ge 20 ] && _bwhy="process starts" ;; esac
    b_fmt_ms "$B_TOT_THIS"; _bth="$B_FMT"; b_fmt_ms "$B_TOT_REF"; _brf="$B_FMT"
    if [ "$_bfac" -le 12 ]; then
      echo "  Verdict: this machine is about as fast as the reference ($_bth vs $_brf over $B_NMEAS measured steps)."
    elif [ "$_bfac" -lt 20 ]; then
      echo "  Verdict: this machine is $((_bfac / 10)).$((_bfac % 10))x slower than the reference ($_bth vs $_brf over $B_NMEAS steps), mainly ${_bwhy:-the first step}."
    else
      echo "  Verdict: this machine is $(( (_bfac + 5) / 10 ))x slower than the reference ($_bth vs $_brf over $B_NMEAS steps), mainly ${_bwhy:-the first step}."
    fi
  fi
  [ -n "$B_SPAWN_THIS" ] && RF_SPAWN_MS=$(( B_SPAWN_THIS / 50 ))
  if [ -n "$B_P" ] && [ -d "$B_P" ]; then
    mkdir -p "$B_P/.claude/loop" 2>/dev/null || true
    _btsv="$B_P/.claude/loop/bench-$B_STAMP.tsv"
    { printf 'timestamp\tplatform\tcores\tfree_mb\tstep\tthis_ms\treference_ms\tfactor\tnote\n'; printf '%s' "$B_TSV"; } > "$_btsv" 2>/dev/null \
      && echo "  Results: $_btsv  (send it to colleagues to compare; untracked, do not commit it)" || echo "  Results: could not write $_btsv"
  else
    echo "  Results: not saved (pass a project directory: bin/doctor.sh --bench <project>)."
  fi
  recommended_fix
  exit 0
fi

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

# Process-start cost (#584/#585). Every toolkit script is many small process starts; exec.sh
# alone makes hundreds. On a Windows machine whose antivirus scans each start, one start cost
# 58-94 ms (vs ~1-3 ms on Linux/macOS), about 69 s of bookkeeping per exec before any build.
# 20 starts of /bin/true (or `true` on PATH) measured with one clock read each side.
_spawn_ms=""
if command -v date >/dev/null 2>&1 && _t0=$(date +%s%N 2>/dev/null) && [ "${_t0%N}" = "$_t0" ]; then
  _i=0; _tbin="$(command -v true 2>/dev/null)"; case "$_tbin" in /*) ;; *) _tbin=/bin/true ;; esac
  while [ $_i -lt 20 ]; do "$_tbin"; _i=$((_i + 1)); done
  _t1=$(date +%s%N); _spawn_ms=$(( (_t1 - _t0) / 20000000 ))
elif [ -n "${EPOCHREALTIME:-}" ]; then
  _t0=${EPOCHREALTIME/[.,]/}; _i=0
  while [ $_i -lt 20 ]; do /bin/true 2>/dev/null || true; _i=$((_i + 1)); done
  _t1=${EPOCHREALTIME/[.,]/}; _spawn_ms=$(( (_t1 - _t0) / 20000 ))
fi
if [ -z "$_spawn_ms" ]; then
  note "process start cost: not measured (no sub-second clock in this shell)"
elif [ "$_spawn_ms" -gt "${MXTK_SPAWN_WARN_MS:-30}" ]; then
  warn "process start cost: ${_spawn_ms} ms each (fast machines: under 5 ms). Toolkit scripts start many"
  note "processes, so each exec spends roughly a minute just starting them. Usual cause on Windows:"
  note "antivirus scanning every start. That cannot be fixed from here; the \"Recommended fix\" at the end of"
  note "this report names a way around it that needs nobody's permission."
else
  ok "process start cost: ${_spawn_ms} ms each"
fi

# --- performance (measured, not just "is it installed") ----------------------------------------------
# Doctor used to answer only "is it there". A machine where everything is installed can still spend
# 64-234 s on a 1 s model write (#584/#585), and nobody saw it until a user profiled it by hand.
# So, from the project's own docs/BUILD-LOG.md (exec.sh writes `steps: guards 0s check 1s … gate 20s
# lint 3s score 3s` on every row): the median exec time and its slowest step over the last 20 execs,
# against what a normal machine shows (measured 2026-10-28 on Linux: 17-34 s per exec, gate 9-20 s).
# Thresholds: MXTK_PERF_EXEC_WARN (default 60 s per exec), MXTK_PERF_GATE_WARN (default 45 s gate).
head_ "Performance (measured)"
_perf_log="${PROJECT_DIR:+$PROJECT_DIR/docs/BUILD-LOG.md}"
if [ -n "$_perf_log" ] && [ -f "$_perf_log" ] && grep -q 'steps: ' "$_perf_log" 2>/dev/null; then
  _perf=$(grep 'steps: ' "$_perf_log" | tail -20 | awk '
    { line=$0; sub(/.*steps: /, "", line); sub(/ *\|.*/, "", line)
      n=split(line, w, " "); tot=0
      for (i=1; i+1<=n; i+=2) { v=w[i+1]; sub(/s$/, "", v); if (v ~ /^[0-9]+$/) { tot+=v; st[w[i]]=st[w[i]] " " v } }
      T[++rows]=tot }
    function med(str,   a, k, m, i, j, t) { m=split(str, a, " "); for (i=1;i<=m;i++) for (j=i+1;j<=m;j++) if (a[j]+0<a[i]+0) { t=a[i]; a[i]=a[j]; a[j]=t }
      return m ? a[int((m+1)/2)] : 0 }
    END { all=""; for (i=1;i<=rows;i++) all=all " " T[i]
      top=""; tv=-1; for (k in st) { v=med(st[k]); if (v+0>tv) { tv=v+0; top=k } }
      printf "%d %d %s %d %d\n", rows, med(all), top, tv, med(st["gate"]) }')
  set -- $_perf
  _pn=${1:-0}; _pmed=${2:-0}; _ptop=${3:-?}; _ptopv=${4:-0}; _pgate=${5:-0}
  _pmsg="last $_pn execs: median ${_pmed} s per exec (gate ${_pgate} s; slowest step: $_ptop ${_ptopv} s). Normal: 17-34 s, gate 9-20 s."
  if [ "$_pmed" -gt "${MXTK_PERF_EXEC_WARN:-60}" ] || [ "$_pgate" -gt "${MXTK_PERF_GATE_WARN:-45}" ]; then
    warn "slow execs — $_pmsg"
    [ "$_pgate" -gt "${MXTK_PERF_GATE_WARN:-45}" ] && note "The gate (mxbuild) dominates: 'Gate mode: full' in PROJECT.md forces a full build per exec; without it, exec runs mx check and the full build before push."
    [ -n "$_spawn_ms" ] && [ "$_spawn_ms" -gt "${MXTK_SPAWN_WARN_MS:-30}" ] && note "Process starts are slow too (above): that is the machine, not the model — see the advice there."
    note "Per-command profile of one exec: MXTK_PROFILE=1 ./bin/exec.sh <script> (prints the 15 slowest lines; MXTK_PROFILE=2 traces the scripts it starts too)."
  else
    ok "$_pmsg"
  fi
elif [ -n "$PROJECT_DIR" ]; then
  note "no exec timings yet (docs/BUILD-LOG.md has no 'steps:' rows) — re-run doctor after a few execs"
else
  note "exec timings: pass a project dir (bin/doctor.sh <project>) to compare its execs with a normal machine"
fi
# Windows advice lives in recommended_fix (end of the report). No step in it may need IT: antivirus
# exclusions are not on offer, so doctor never asks for them.

machine_health

# --- environment lane -------------------------------------------------------------------------
# Where this session runs decides the write modes available (CONVERSION-RUNBOOK.md → "Where you
# run this"). It is DETECTED, never asked: the agent records the answer in PROJECT.md and moves on.
#   cloud        Claude Code on the web/mobile: CLAUDE_CODE_REMOTE=true. Ephemeral — push at
#                every gate. Headless lane: CLI write mode only, mxcli run --local(--hub) to see it.
#   devcontainer VS Code devcontainer / Codespaces / any Docker container on Linux. Same headless
#                lane as cloud, on your own disk.
#   local        macOS or Windows with Studio Pro reachable: all three write modes.
#   local-linux  native Linux, no container markers: headless lane, nothing ephemeral.

head_ "Environment lane (detected)"

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  ENV_LANE=cloud
elif [ -n "${REMOTE_CONTAINERS:-}${CODESPACES:-}${DEVCONTAINER:-}" ] || [ -f /.dockerenv ]; then
  ENV_LANE=devcontainer
else
  case "$PLATFORM" in
    macos|gitbash|wsl) ENV_LANE=local ;;
    *)                 ENV_LANE=local-linux ;;
  esac
fi
ok "$ENV_LANE"
case "$ENV_LANE" in
  cloud)
    note "Ephemeral container: the git remote is the workspace — commit and push at every gate."
    note "Headless: CLI write mode (exec.sh + mxbuild gate); see the app with mxcli run --local --hub."
    note "mxcli run --local CONSOLIDATES a split-model .mpr (CRITICAL, bug-logs): snapshot first, git status after."
    note "Setup order for a new project: skills/cloud-dev-environment.md." ;;
  devcontainer|local-linux)
    note "Headless lane: CLI write mode (exec.sh + mxbuild gate); mxcli run --local to see the app."
    note "Nothing is ephemeral here. Studio Pro modes (--mcp) are not available HERE — open the same"
    note ".mpr from a Mac terminal / Git Bash when you need them; lanes mix, one .mpr writer at a time." ;;
  local)
    note "Studio Pro lane: all three write modes (CLI, --mcp, hand-rolled MCP) when SP is installed." ;;
esac
note "Agents: record this once in PROJECT.md as 'Environment: $ENV_LANE' — do not ask the user."

if [ "$QUICK" != 1 ]; then
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
  note "Either the toolkit path is wrong, or the clone is incomplete — re-clone the toolkit."
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
  note "git pull inside the toolkit clone restores it (or re-clone the toolkit)."
fi

fi

# --- installed Claude hooks: copies that call a toolkit script which is gone ------------------
#
# install-claude-hooks.sh writes COPIES into ~/.claude/hooks with the toolkit path filled in.
# When a toolkit update removes a script (bin/questions-report.sh was retired in v1.0), an old
# copy keeps calling it: the hook still runs but silently loses its output. A warning only,
# never a failure: the hooks are user-global and optional.
if [ -d "$HOME/.claude/hooks" ]; then
  head_ "Installed Claude hooks (~/.claude/hooks)"
  STALE_HOOKS=0
  HOOKS_SEEN=0
  for hf in "$HOME"/.claude/hooks/*.sh; do
    [ -f "$hf" ] || continue
    HOOKS_SEEN=$((HOOKS_SEEN + 1))
    # The toolkit root the installer wrote, e.g. TOOLKIT="/path/to/toolkit".
    HOOK_ROOT="$(sed -n 's/^[A-Z_]*TOOLKIT[A-Z_]*="\(\/[^"]*\)".*/\1/p' "$hf" | head -1)"
    HOOK_REFS=""
    if [ -n "$HOOK_ROOT" ]; then
      HOOK_REFS="$(grep -oE '[$][{]?[A-Z_]*TOOLKIT[A-Z_]*[}]?/[A-Za-z0-9_./-]+[.](sh|py|js|tsv)' "$hf" 2>/dev/null \
        | sed -e 's/^[$][{]*[A-Z_]*[}]*//' -e "s|^|$HOOK_ROOT|" | sort -u)"
    fi
    HOOK_GONE=""
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$ref" ] || HOOK_GONE="$HOOK_GONE ${ref##*/}"
    done <<EOF_REFS
$HOOK_REFS
EOF_REFS
    if [ -n "$HOOK_GONE" ]; then
      STALE_HOOKS=$((STALE_HOOKS + 1))
      warn "installed hook $(basename "$hf") calls a toolkit script that no longer exists:$HOOK_GONE"
    fi
  done
  if [ "$STALE_HOOKS" -gt 0 ]; then
    note "The installed copy is older than this toolkit. Re-run: $TOOLKIT_ROOT/bin/install-claude-hooks.sh --full"
  elif [ "$HOOKS_SEEN" -gt 0 ]; then
    ok "installed hooks only call toolkit scripts that exist"
  fi
fi

# --- command line tools ---------------------------------------------------------------------

head_ "Command line tools"

CORE_MISSING=0
for c in git sed grep awk find sort tr cut; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || { bad "$c is missing — it is used by nearly every script"; CORE_MISSING=$((CORE_MISSING + 1)); }
done
if [ "$CORE_MISSING" -gt 0 ]; then
  note "These all arrive together: Windows — install Git for Windows and use its Git Bash;"
  note "macOS — xcode-select --install; Linux — apt install git (coreutils ships with the distro)."
fi

command -v sqlite3 >/dev/null 2>&1 && ok "sqlite3" || {
  warn "sqlite3 is missing. project-bin/graph-sweep.sh reads the mxcli catalog with it."
  note "macOS: preinstalled. Linux: apt install sqlite3. Windows: winget install SQLite.SQLite"; }

command -v shellcheck >/dev/null 2>&1 && ok "shellcheck (optional, for editing toolkit scripts)" \
  || note "shellcheck not installed — only needed if you edit toolkit scripts"

if [ "$QUICK" != 1 ]; then
# --- studio pro -------------------------------------------------------------------------

head_ "Studio Pro automation"

case "$PLATFORM" in
  macos)
    if ls -d /Applications/Mendix\ Studio\ Pro*.app >/dev/null 2>&1; then
      ok "found: $(ls -d /Applications/Mendix\ Studio\ Pro*.app | tr '\n' ' ')"
    else
      warn "no 'Mendix Studio Pro *.app' in /Applications — project-bin/restart-sp.sh cannot run"
      note "Install Studio Pro (Mendix Marketplace) if you want SP automation; everything"
      note "else works without it — the mxbuild gate can run on the downloaded toolchain."
    fi
    ;;
  gitbash|wsl|linux|unknown)
    # Informational only. Nobody needs these scripts to use the toolkit — Studio Pro is
    # opened and saved by hand at the points where they would run — so on the platforms
    # they do not exist for, this is not a warning. (It was one; a Windows onboarding
    # counted it among "6 warnings" and asked what to do about it. Nothing.)
    note "save-sp.sh / restart-sp.sh (macOS conveniences) are not on this platform — you open"
    note "and save Studio Pro yourself at those points. Nothing else depends on them."
    ;;
esac

fi

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

_jnote="$(find_java_note 2>/dev/null || true)"

# toolkit.env — the human-editable answer to "doctor guessed the wrong Studio Pro / Java".
# _common.sh already loaded it (project file, then ~/.mxcli-toolkit.env; a variable set in
# the shell wins over both). Say what was read, so a stale value is findable.
if [ -n "${MXTK_ENV_LOADED:-}" ]; then
  ok "toolkit.env loaded: $MXTK_ENV_LOADED"
else
  note "No toolkit.env — discovery guesses below. To pin tool locations for this machine, create"
  note "  ${PROJECT_DIR:-<project>}/.claude/toolkit.env  (this project)  or  ~/.mxcli-toolkit.env  (every project)"
  note "  with lines like:  MENDIX_APP=C:\\Program Files\\Mendix\\11.11.0    JAVA_HOME=C:\\Software\\Java\\jdk-21"
  note "  (Windows paths can be pasted as-is; MXBUILD_PATH, MXCLI_VERSION and PYTHON work too.)"
fi

# --install: when no runnable mxbuild was discovered, download the standalone toolchain
# through the project's own mxcli — `./mxcli setup mxbuild -p <app>.mpr`, the exact download
# the headless container build runs, cached at ~/.mxcli/mxbuild/<version>/ and shared across
# projects. find_mxbuild/find_java (project-bin/_common.sh) discover that cache, so after a
# successful download the exec.sh mxbuild gate runs from it too — no Studio Pro required.
# This happens BEFORE the reporting below, so the report describes the machine as it now is.

# The setup step itself, shared by the had-mxcli and just-fetched-mxcli paths. Re-runs the
# toolchain discovery on success — the cache did not exist the first time around.
install_toolchain() {
  INSTALL_MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
  if [ -z "$INSTALL_MPR" ]; then
    bad "--install: no .mpr in $PROJECT_DIR — setup mxbuild needs the model to pick a version."
    return
  fi
  note "downloading the mxbuild toolchain (mxcli setup mxbuild — same as the container build)..."
  if (cd "$PROJECT_DIR" && "$PMXCLI" setup mxbuild -p "$(basename "$INSTALL_MPR")"); then
    SP_APP="$(find_sp_app 2>/dev/null || true)"
    MXBUILD="$(find_mxbuild 2>/dev/null || true)"
    JAVA_HOME_FOUND="$(find_java 2>/dev/null || true)"
    JAVA_EXE="$(find_java_exe 2>/dev/null || true)"
    ok "toolchain downloaded to ~/.mxcli/mxbuild/ (shared cache, reused by every project)"
  else
    bad "'mxcli setup mxbuild' failed — see its output above."
    note "A blocked network/proxy is the usual cause; the download comes from the Mendix CDN."
  fi
}

if [ "$INSTALL" -eq 1 ]; then
  # What is actually missing? --install covers two tools: the project's ./mxcli (which every
  # MDL session needs anyway) and the mxbuild toolchain (which the gate needs).
  NEED_TOOLCHAIN=1
  if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ] && probe_runs "$MXBUILD"; then NEED_TOOLCHAIN=0; fi
  NEED_MXCLI=0
  PMXCLI="$(find_project_mxcli 2>/dev/null || true)"
  if [ -n "$PROJECT_DIR" ] && [ -z "$PMXCLI" ]; then
    NEED_MXCLI=1
  fi

  if [ "$NEED_TOOLCHAIN" -eq 0 ] && [ "$NEED_MXCLI" -eq 0 ]; then
    ok "--install: nothing to download — a runnable mxbuild and the project mxcli are in place"
  elif [ -z "$PROJECT_DIR" ]; then
    bad "--install needs a project directory: bin/doctor.sh --install <project-dir>"
    note "The download runs through that project's own ./mxcli, which reads the model's"
    note "Mendix version and fetches the matching toolchain."
  elif [ "$NEED_MXCLI" -eq 1 ] && [ "$PLATFORM" = gitbash ] && mxtk_is_elf "$PROJECT_DIR/mxcli"; then
    # Not a permissions problem, and chmod cannot fix it (Git Bash derives the executable bit
    # from the extension/header, so `chmod +x` looks like it "reverts"). The file is the Linux
    # build the Dev Container uses on this same folder. Windows needs mxcli.exe beside it.
    note "--install: $PROJECT_DIR/mxcli is the Linux build (the Dev Container's) — fine, leave it."
    note "Git Bash needs mxcli.exe next to it; fetching that now, the two coexist."
    NEED_MXCLI=1; PMXCLI=""
  elif [ -f "$PROJECT_DIR/mxcli" ] && [ ! -x "$PROJECT_DIR/mxcli" ] && [ "$PLATFORM" != gitbash ]; then
    bad "--install: mxcli in $PROJECT_DIR is present but not executable — chmod +x mxcli, re-run."
  else
    # The release assets follow one naming scheme (verified against the published releases,
    # 2026-08-31): mxcli-{darwin|linux}-{amd64|arm64}, mxcli-windows-amd64.exe. Windows gets
    # the .exe name so Git Bash's transparent foo -> foo.exe mapping serves the project
    # convention ./mxcli unchanged. $MXCLI_VERSION pins a release tag (e.g. v0.16.0) for
    # teams that standardise; default is latest. v0.25.0 froze `mdl 1`: DESCRIBE output and
    # `-c` input changed shape (navigation, DynamicClasses, `show entity` refused). The
    # toolkit's instruments read both shapes, so a project mid-build may stay on its version
    # (MXCLI_VERSION=v0.24.0) and move when it chooses.
    # Git Bash on Windows ARM64 runs emulated, so `uname -m` says x86_64 there. On Windows the
    # real hardware shows in the `uname -s` suffix (...-ARM64) and in PROCESSOR_ARCHITEW6432
    # (set for emulated processes) / PROCESSOR_ARCHITECTURE; those win over `uname -m`.
    MXCLI_ARCH="$(uname -m 2>/dev/null || echo unknown)"
    case "$MXCLI_ARCH" in
      x86_64|amd64) MXCLI_ARCH=amd64 ;;
      arm64|aarch64) MXCLI_ARCH=arm64 ;;
    esac
    if [ "$PLATFORM" = gitbash ]; then
      case "$UNAME:${PROCESSOR_ARCHITEW6432:-}:${PROCESSOR_ARCHITECTURE:-}" in
        *-ARM64:*|*:ARM64:*|*:*:ARM64) MXCLI_ARCH=arm64 ;;
      esac
    fi
    MXCLI_FALLBACK_ASSET=""
    case "$PLATFORM-$MXCLI_ARCH" in
      macos-amd64)   MXCLI_ASSET="mxcli-darwin-amd64";      MXCLI_DEST="mxcli" ;;
      macos-arm64)   MXCLI_ASSET="mxcli-darwin-arm64";      MXCLI_DEST="mxcli" ;;
      linux-amd64|wsl-amd64) MXCLI_ASSET="mxcli-linux-amd64"; MXCLI_DEST="mxcli" ;;
      linux-arm64|wsl-arm64) MXCLI_ASSET="mxcli-linux-arm64"; MXCLI_DEST="mxcli" ;;
      gitbash-amd64) MXCLI_ASSET="mxcli-windows-amd64.exe"; MXCLI_DEST="mxcli.exe" ;;
      # Windows ARM64: native build; releases before it existed fall back to the amd64 .exe,
      # which Windows on ARM runs under emulation.
      gitbash-arm64) MXCLI_ASSET="mxcli-windows-arm64.exe"; MXCLI_DEST="mxcli.exe"
                     MXCLI_FALLBACK_ASSET="mxcli-windows-amd64.exe" ;;
      *)             MXCLI_ASSET=""; MXCLI_DEST="" ;;
    esac
    if [ -n "${MXCLI_VERSION:-}" ]; then
      MXCLI_URL="https://github.com/mendixlabs/mxcli/releases/download/$MXCLI_VERSION/${MXCLI_ASSET:-<asset>}"
    else
      MXCLI_URL="https://github.com/mendixlabs/mxcli/releases/latest/download/${MXCLI_ASSET:-<asset>}"
    fi
    if command -v curl >/dev/null 2>&1; then MXCLI_FETCH="curl -fsSL -o"
    elif command -v wget >/dev/null 2>&1; then MXCLI_FETCH="wget -q -O"
    else MXCLI_FETCH=""; fi

    if [ "$NEED_MXCLI" -eq 1 ] && { [ -z "$MXCLI_ASSET" ] || [ -z "$MXCLI_FETCH" ]; }; then
      bad "--install: no mxcli in $PROJECT_DIR and cannot auto-fetch one here"
      [ -z "$MXCLI_ASSET" ] && note "(no published mxcli build detected for $PLATFORM/$MXCLI_ARCH — if that"
      [ -z "$MXCLI_ASSET" ] && note " detection is wrong, pick your asset at github.com/mendixlabs/mxcli/releases)"
      [ -z "$MXCLI_FETCH" ] && note "(neither curl nor wget on this machine)"
      note "Download it yourself into the project root, then re-run:"
      note "  $MXCLI_URL"
      note "  chmod +x mxcli"
    else
      # ---- the plan, before anything is downloaded ------------------------------------
      # Downloading executables onto someone's machine is not a silent act: say what, from
      # where, how big, why, and what was detected — then get a yes. A wrong OS/arch guess,
      # a metered connection, or a company policy against fetching binaries are all things
      # only the human in front of the machine can judge.
      note ""
      note "--install plan — this machine is missing tools the toolkit needs, and doctor can"
      note "download them now. Nothing has been downloaded yet. The plan:"
      _STEP=0
      if [ "$NEED_MXCLI" -eq 1 ]; then
        _STEP=$((_STEP + 1))
        note "  $_STEP. mxcli (~90 MB) -> $PROJECT_DIR/$MXCLI_DEST"
        note "     the MDL CLI every session here uses; from $MXCLI_URL"
        [ -z "${MXCLI_VERSION:-}" ] && note "     (latest release — set MXCLI_VERSION=vX.Y.Z to pin the team's version;"
        [ -z "${MXCLI_VERSION:-}" ] && note "      a project already building on v0.24 can stay there: MXCLI_VERSION=v0.24.0)"
      fi
      if [ "$NEED_TOOLCHAIN" -eq 1 ]; then
        _STEP=$((_STEP + 1))
        note "  $_STEP. mxbuild toolchain (~800 MB, one-time) -> ~/.mxcli/mxbuild/<version>/"
        note "     verifies every model write (the exec.sh gate); from cdn.mendix.com, exact"
        note "     version read from the project's .mpr — the same download the container build uses."
        if [ "$NEED_MXCLI" -eq 0 ] && [ -n "$PMXCLI" ]; then
          _PLAN_MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
          [ -n "$_PLAN_MPR" ] && (cd "$PROJECT_DIR" && "$PMXCLI" setup mxbuild -p "$(basename "$_PLAN_MPR")" --dry-run 2>/dev/null) \
            | grep -E 'Version:|URL:' | while IFS= read -r l; do note "     $l"; done
        fi
      fi
      note "  Detected machine: $PLATFORM/$MXCLI_ARCH — if that looks wrong, answer no and use the"
      note "  URLs above by hand (a wrong-platform binary downloads fine and then cannot run)."
      note "  If your company restricts downloading executables, route these same URLs through"
      note "  your approved channel instead."
      # ---- consent --------------------------------------------------------------------
      CONSENT=0
      if [ "$ASSUME_YES" -eq 1 ]; then
        note "  (--yes given: proceeding)"
        CONSENT=1
      elif [ -t 0 ]; then
        printf '        Proceed with the download(s)? [y/N] '
        IFS= read -r _REPLY || _REPLY=""
        case "$_REPLY" in y|Y|yes|Yes|YES) CONSENT=1 ;; *) CONSENT=0 ;; esac
      else
        warn "--install: no terminal to ask on and no --yes — nothing downloaded."
        note "An unattended run needs the explicit flag: bin/doctor.sh --install --yes $PROJECT_DIR"
      fi

      if [ "$CONSENT" -eq 0 ]; then
        [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && note "Understood — nothing downloaded. The URLs above work by hand too."
      else
        MXCLI_READY=1
        if [ "$NEED_MXCLI" -eq 1 ]; then
          note "fetching $MXCLI_ASSET from the mxcli releases..."
          if ! $MXCLI_FETCH "$PROJECT_DIR/$MXCLI_DEST" "$MXCLI_URL" && [ -n "$MXCLI_FALLBACK_ASSET" ]; then
            warn "$MXCLI_ASSET is not published for this mxcli version; trying $MXCLI_FALLBACK_ASSET (runs emulated)."
            MXCLI_URL="${MXCLI_URL%/*}/$MXCLI_FALLBACK_ASSET"
            $MXCLI_FETCH "$PROJECT_DIR/$MXCLI_DEST" "$MXCLI_URL" || true
          fi
          if [ -s "$PROJECT_DIR/$MXCLI_DEST" ] && chmod +x "$PROJECT_DIR/$MXCLI_DEST" \
             && probe_runs "$PROJECT_DIR/$MXCLI_DEST"; then
            ok "mxcli fetched into the project root: $(probe_line)"
            PMXCLI="$PROJECT_DIR/$MXCLI_DEST"
          else
            rm -f "$PROJECT_DIR/$MXCLI_DEST" 2>/dev/null
            MXCLI_READY=0
            bad "--install: fetching mxcli failed (network/proxy, or the binary would not run here)."
            note "Download it yourself into the project root, then re-run:  $MXCLI_URL"
          fi
        fi
        if [ "$NEED_TOOLCHAIN" -eq 1 ] && [ "$MXCLI_READY" -eq 1 ]; then
          install_toolchain
        fi
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
    ok "mxbuild runs ($PROBE_HOW): $(probe_line)"
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
  note "Have Studio Pro? Point at it: MENDIX_APP=<its version folder> in toolkit.env (see above)."
  note "No Studio Pro: bin/doctor.sh --install <project-dir> downloads a standalone mxbuild,"
  note "like the container build. MXBUILD_PATH=<path to mxbuild> also works."
fi

# Java: mxbuild is invoked with an explicit --java-exe-path; if none resolves, the gate skips.
if [ -n "$JAVA_EXE" ] && [ -x "$JAVA_EXE" ]; then
  # -version writes to stderr, and wrappers can prepend noise (JAVA_TOOL_OPTIONS pickup
  # lines); take the line that actually names a version, not merely the first.
  JV="$("$JAVA_EXE" -version 2>&1 | grep -i 'version' | head -1)" || JV=""
  if [ -n "$JV" ]; then
    ok "java runs: $JV  ($JAVA_EXE)"
    [ -z "${_jnote:-}" ] || warn "$_jnote"
    # The JDK major must match the model (#576): 11.14+ builds need JDK 25, 11.13 and below
    # JDK 21 (the same rule as find_java's _mxtk_java_want, read off the model doctor resolved). A JAVA_HOME exported in the shell
    # profile wins over that rule AND over toolkit.env, and the mismatch then surfaces only as
    # mxbuild stopping before it checks anything. Mendix 11 only — the rule is documented
    # there; Studio Pro's bundled runtime is paired with its mxbuild and never flagged.
    JAVA_WANT=""
    _mver="$(mxtk_model_version "${MPR:-}" 2>/dev/null || true)"
    case "$_mver" in
      11.*)
        _mmin="${_mver#11.}"; _mmin="${_mmin%%.*}"
        JAVA_WANT=21; [ "$_mmin" -ge 14 ] 2>/dev/null && JAVA_WANT=25
        _jmaj="$(printf '%s\n' "$JV" | sed -n 's/.*version "\(1\.\)\{0,1\}\([0-9][0-9]*\).*/\2/p' | head -1)"
        case "$JAVA_HOME_FOUND" in
          "${SP_APP:-<none>}"/*) ;;
          *) if [ -n "$_jmaj" ] && [ "$_jmaj" != "$JAVA_WANT" ]; then
               warn "Java $_jmaj, but this model (Mendix $_mver) builds with JDK $JAVA_WANT — mxbuild will stop before checking the model"
               # Which env file JAVA_HOME came from, in the loader's order (project file, then user
               # file; the shell beats both). The first file that sets it decides: its value equal
               # to JAVA_HOME means it was loaded from there; otherwise the shell had set it already.
               _jenv=""
               for _ef in ${MXTK_ENV_LOADED:-}; do
                 _jl="$(grep -E '^[[:space:]]*(export[[:space:]]+)?JAVA_HOME[[:space:]]*=' "$_ef" 2>/dev/null | head -1)"
                 [ -n "$_jl" ] || continue
                 _jv="$(printf '%s' "${_jl#*=}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/')"
                 type mxtk_posix_path >/dev/null 2>&1 && _jv="$(mxtk_posix_path "$_jv")"
                 [ "$_jv" = "${JAVA_HOME:-}" ] && _jenv="$_ef"
                 break
               done
               if [ -n "$_jenv" ]; then
                 note "JAVA_HOME comes from $_jenv: change it there to a JDK $JAVA_WANT folder."
               elif [ -n "${JAVA_HOME:-}" ]; then
                 note "JAVA_HOME is set in your environment, which wins over the toolkit's per-model JDK choice and over toolkit.env."
                 note "Point it at JDK $JAVA_WANT (macOS: export JAVA_HOME=\$(/usr/libexec/java_home -v $JAVA_WANT)) or unset it in your shell profile."
               else
                 note "Install JDK $JAVA_WANT, or set JAVA_HOME=<a JDK $JAVA_WANT folder> in .claude/toolkit.env."
               fi
             fi ;;
        esac ;;
    esac
    # mxbuild compiles the model's Java actions, which takes javac — a JRE has none. Studio
    # Pro's bundled runtime is a JRE that mxbuild is paired with, so only flag a system Java.
    case "$JAVA_HOME_FOUND" in
      "${SP_APP:-<none>}"/*) ;;
      *) if [ ! -x "$(dirname "$JAVA_EXE")/javac" ] && [ ! -x "$(dirname "$JAVA_EXE")/javac.exe" ]; then
           note "this Java is a JRE (no javac). Java actions in the model need a JDK to compile:"
           note "set JAVA_HOME=<a JDK 21 folder> in toolkit.env if a build complains about javac."
         fi ;;
    esac
  else
    GATE_OK=0
    bad "java exists but produced no version output: $JAVA_EXE"
  fi
else
  GATE_OK=0
  if [ "$PLATFORM" = linux ] && [ -z "$SP_APP" ]; then
    warn "java not found (looked for JAVA_HOME, Studio Pro's bundled JRE, then PATH)."
    note "The downloaded mxbuild toolchain needs a system Java: apt install openjdk-21-jre"
    note "(or your distro's equivalent), or set JAVA_HOME=<jdk/jre root>."
  else
    bad "java not found/executable: ${JAVA_EXE:-<none>}"
    note "Studio Pro ships its own JRE and that is the preferred one; if discovery missed it,"
    note "set JAVA_HOME=<jdk/jre root> explicitly. No Studio Pro? Install a JDK/JRE 21:"
    note "macOS: brew install --cask temurin@21   Windows: winget install EclipseAdoptium.Temurin.21.JRE"
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
    bad "the mxbuild gate would be skipped on this machine — sort out the mxbuild/java lines"
    note "above before the first model write, so every write gets verified."
  fi
  note "Why it matters: without mxbuild, MDL execs report gate=skipped and consistency errors"
  note "go uncaught until Studio Pro opens the model. Usually one of these fixes it:"
  note "  - Studio Pro is installed: put its folder in toolkit.env, e.g."
  note "      MENDIX_APP=C:\\Program Files\\Mendix\\11.11.0   (pick the version your .mpr uses)"
  note "  - No Studio Pro here: bin/doctor.sh --install <project-dir> downloads a standalone"
  note "    mxbuild (the same one the container build uses)."
fi

if [ "$QUICK" != 1 ]; then
# --- node -----------------------------------------------------------------------------------

head_ "Node.js (pipelines, page fidelity, e2e)"

NODE_V="$(node --version 2>/dev/null)" || NODE_V=""
if [ -n "$NODE_V" ]; then
  ok "node $NODE_V"
else
  warn "node is missing. Needed by the extraction pipelines (npm install per pipeline),"
  note "project-bin/page-fidelity.js, and Playwright e2e (project-bin/test-stack-up.sh)."
  note "Not needed for a pure MDL-writing session. To install: an LTS from nodejs.org,"
  note "or brew install node / winget install OpenJS.NodeJS.LTS / apt install nodejs npm."
fi
note "e2e additionally needs a Playwright browser in the project: npx playwright install chromium"

# --- self-verification (container runtime) ---------------------------------------------------

head_ "Self-verification stack (container runtime — recommended)"

# With a container runtime, the loop closes without a human: after a build the agent runs a
# Linux build of the app, brings up Postgres + the app (project-bin/test-stack-up.sh), drives
# it with Playwright, screenshots the pages, and verifies its own work — nobody has to open
# Studio Pro to find out whether a page renders. Without one the mxbuild gate still verifies
# the MODEL, but nothing verifies the RUNNING APP unless a human does. Recommended, never
# required — hence WARN, not FAIL.
#
# DOCKER *OR* PODMAN. This section used to advertise Podman in its advice text while every
# probe ran `docker` only — so a machine running Podman without the docker shim was told
# "docker is not installed", and on a team that cannot licence Docker Desktop that reads as
# "go install software you are not allowed to have". (Field data point: a colleague's
# machine-ready status carried "Docker not installed" as a known issue; they may well have had
# Podman all along.) Detection order: docker first when present — including when it IS a Podman
# shim, which is transparent and correct — then podman.
CONTAINER_RUNTIME="${MXTK_CONTAINER_RUNTIME:-}"
if [ -z "$CONTAINER_RUNTIME" ]; then
  if command -v docker >/dev/null 2>&1; then CONTAINER_RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then CONTAINER_RUNTIME=podman
  fi
fi
# What to call it in the report. Docker has a daemon; podman normally does not, so "podman
# daemon" would be wrong — the label carries that difference, and the runtime is NAMED in the
# output so a user can tell which one doctor actually found.
case "$CONTAINER_RUNTIME" in
  docker)
    RUNTIME_LABEL="docker daemon"
    RUNTIME_PROBING="the docker daemon"
    RUNTIME_DOWN="docker is installed but the docker daemon is not responding." ;;
  *)
    RUNTIME_LABEL="$CONTAINER_RUNTIME"
    RUNTIME_PROBING="$CONTAINER_RUNTIME"
    RUNTIME_DOWN="$CONTAINER_RUNTIME is installed but not responding." ;;
esac

# container_daemon_up — `<runtime> info`, bounded. When Docker Desktop is installed but not
# running, the CLI can sit on its socket/named pipe with no output for minutes (macOS and Git
# Bash both reported, 2026-09-09) — and since init-project.sh runs doctor last, the whole
# scaffold read as hung. A stopped `podman machine` stalls the same way, so podman goes through
# the same bound. No `timeout` on stock macOS, so: background the probe, poll once a second,
# kill it at the bound. Returns 0 up · 1 down (answered quickly) · 2 no answer within the bound.
container_daemon_up() {
  "$CONTAINER_RUNTIME" info >/dev/null 2>&1 &
  _dd_pid=$!
  _dd_waited=0
  while kill -0 "$_dd_pid" 2>/dev/null; do
    if [ "$_dd_waited" -ge "$DOCKER_PROBE_SECS" ]; then
      kill "$_dd_pid" 2>/dev/null; wait "$_dd_pid" 2>/dev/null
      return 2
    fi
    sleep 1; _dd_waited=$((_dd_waited + 1))
  done
  wait "$_dd_pid"
}

# container_start_hint — the one command that starts this runtime on this platform, or the
# closest thing to it. Printed instead of "start Docker", which sent people to look for a
# button — and a Podman user must never be sent to look for Docker Desktop at all.
container_start_hint() {
  if [ "$CONTAINER_RUNTIME" = podman ]; then
    case "$PLATFORM" in
      macos|gitbash)
        note "  podman machine start    # the VM podman runs containers in; ~15-60 s"
        note "  (podman machine init first, if this machine has never had one)" ;;
      linux|wsl)
        note "  systemctl --user start podman.socket   # rootless; or sudo systemctl start podman.socket"
        note "  (rootless podman often needs no service at all — check 'podman info' by hand)" ;;
      *) note "  start the podman machine/service, then re-run this script" ;;
    esac
  else
    case "$PLATFORM" in
      macos)
        if [ -d /Applications/Docker.app ]; then note "  open -a Docker          # Docker Desktop; the daemon needs ~30-90 s after launch"
        elif command -v colima >/dev/null 2>&1; then note "  colima start"
        else note "  open -a Docker (Docker Desktop) or colima start — whichever is installed"; fi ;;
      gitbash)
        note '  start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"   # then wait ~30-90 s'
        note "  (or Rancher Desktop / Podman Desktop from the Start menu)" ;;
      linux|wsl)
        note "  sudo systemctl start docker     # or, on WSL, start Docker Desktop on the Windows side" ;;
      *) note "  start Docker Desktop / the docker service, then re-run this script" ;;
    esac
  fi
  note "Then re-run: bin/doctor.sh${PROJECT_DIR:+ $PROJECT_DIR}   (this section is skipped by --quick)"
  note "Not required, if you would rather not run one: the build check (exec.sh's mxbuild gate) needs no"
  note "container, and Studio Pro's Run Locally or ./mxcli run --local runs the app without one."
}

# cloud_no_daemon — the Claude Code on the web container ships the docker CLI but no running
# daemon, and the agent cannot start one there. Telling it "sudo systemctl start docker" sent
# sessions off trying, then reporting "cannot start the docker daemon" as a blocker — while the
# mxbuild gate (exec.sh) and `mxcli run --local` both work with no Docker at all. So in the cloud
# lane a missing daemon is reported as the normal state, with the Docker-free route, not a WARN.
cloud_no_daemon() {
  ok "no $RUNTIME_LABEL in this cloud container — normal here, and not a blocker. Do not try to start it."
  note "Build check: exec.sh's mxbuild gate — mxbuild is a plain binary, no Docker needed."
  note "Run the app: ./mxcli run --local (add --hub for a preview URL) — skills/cloud-dev-environment.md."
  note "Snapshot first: mxcli run --local consolidates a split-model .mpr (bug-logs, CRITICAL)."
}

if [ "$NO_DOCKER" = 1 ]; then
  note "docker probe skipped (--no-docker / MXTK_DOCTOR_SKIP_DOCKER=1). Self-verification stack not checked."
elif [ -n "$CONTAINER_RUNTIME" ]; then
  note "probing $RUNTIME_PROBING (bounded: ${DOCKER_PROBE_SECS} s — a stopped runtime can otherwise hang here)..."
  DOCKER_STATE=0
  container_daemon_up || DOCKER_STATE=$?
  case "$DOCKER_STATE" in
    0)
      ok "$RUNTIME_LABEL responding — mxcli docker run + test-stack-up.sh (app up, e2e, screenshots) available" ;;
    *) [ "$ENV_LANE" = cloud ] && DOCKER_STATE=cloud ;;
  esac
  case "$DOCKER_STATE" in
    0) ;;
    cloud) cloud_no_daemon ;;
    2)
      warn "$CONTAINER_RUNTIME is installed but '$CONTAINER_RUNTIME info' gave no answer within ${DOCKER_PROBE_SECS} s — treated as not running."
      note "That silent wait is what makes a setup look hung. Raise the bound with"
      note "MXTK_DOCKER_PROBE_SECS=30 if it is merely slow to answer here. To start it:"
      container_start_hint ;;
    *)
      warn "$RUNTIME_DOWN"
      note "Until it runs: no app container, no throwaway Postgres, no agent-driven e2e/screenshots."
      note "To start it:"
      container_start_hint ;;
  esac
  # --install is the "do it for me" mode: on macOS with Docker Desktop present, launch it.
  # Never elsewhere — Windows launch paths vary and Linux needs sudo. Podman is left alone:
  # `podman machine start` on a machine that has never run `podman machine init` is not a safe
  # guess to make on someone's behalf.
  if [ "$DOCKER_STATE" != 0 ] && [ "$DOCKER_STATE" != cloud ] && [ "$INSTALL" = 1 ] && [ "$CONTAINER_RUNTIME" = docker ] && [ "$PLATFORM" = macos ] && [ -d /Applications/Docker.app ]; then
    if open -a Docker 2>/dev/null; then
      note "--install: launched Docker Desktop (open -a Docker). Give it ~30-90 s, then re-run doctor."
    fi
  fi
elif [ "$ENV_LANE" = cloud ]; then
  cloud_no_daemon
else
  warn "no container runtime found — neither docker nor podman. One is recommended for new builders."
  note "The build check does NOT need it: exec.sh's mxbuild gate is a plain binary. What it adds"
  note "is the running app in a container: project-bin/test-stack-up.sh (Postgres + the app up,"
  note "Playwright e2e, page screenshots)."
  note "No-container route for running the app: 'mxcli run --local' against a native"
  note "PostgreSQL (host:PORT) — the same route the cloud lane uses."
  note "Docker Desktop needs a paid licence at larger companies, and is NOT required: Podman is"
  note "the licence-free option (docker-CLI compatible; doctor probes it directly, so no docker"
  note "shim is needed). Rancher Desktop and colima (macOS) are the other common substitutes."
fi

fi

# --- spawn speed (git bash) -----------------------------------------------------------------

# gate-check.sh + the obligation check fork over a thousand subprocesses per run. On a healthy
# machine a fork is ~1-3 ms and the run takes seconds; observed on a managed Windows laptop:
# 152 ms per fork, which turns the same run into a 5-15 minute "hang" (see the header of
# bin/lib/obligation-check.sh). Measure it once here so slow reads as "this machine", not
# "the toolkit is broken".
# In --quick mode measure on every platform: a corporate endpoint agent on macOS, or an
# overloaded container, shows the same symptom, and the number is what makes "slow" actionable.
if [ "$PLATFORM" = gitbash ] || [ "$QUICK" = 1 ]; then
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
        note "  - Antivirus scanning every process start (not something you can change yourself;"
        note "    see \"Recommended fix\" at the end)."
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
    # Two-tree checkout (cloud-dev-environment.md: `mxcli new --output-dir ./app`) — the app
    # lives under app/. Reported "no .mpr found" on a healthy pilot, 2026-09-04.
    [ -n "$MPR" ] || MPR="$(ls "$PROJECT_DIR"/app/*.mpr 2>/dev/null | head -1)"
    # Multi-app folder (apps/<X>/X.mpr, #420): report every app, not "no .mpr found".
    if [ -z "$MPR" ] && ls "$PROJECT_DIR"/apps/*/*.mpr >/dev/null 2>&1; then
      MPR="$(ls "$PROJECT_DIR"/apps/*/*.mpr | head -1)"
      _apps="$(cd "$PROJECT_DIR" && ls apps/*/*.mpr | paste -s -d, - | sed 's/,/, /g')"
      [ "$(ls "$PROJECT_DIR"/apps/*/*.mpr | wc -l | tr -d ' ')" -gt 1 ] && note "multi-app folder: $_apps — instruments need MPR_FILE=apps/<X>/<X>.mpr to pick one"
    fi
    [ -n "$MPR" ] && ok "model: ${MPR#$PROJECT_DIR/}" || {
      warn "no .mpr found in the project root"
      note "If the model lives elsewhere, point doctor at the folder that contains it;"
      note "a brand-new project gets its .mpr from 'mxcli init' or a Studio Pro export."; }
    PMXCLI_PROBE="$(find_project_mxcli 2>/dev/null || true)"
    if [ -n "$PMXCLI_PROBE" ]; then
      # Present is not enough — a wrong-platform binary is present, executable, and exits 126.
      MXCLI_EXIT=0
      probe_runs "$PMXCLI_PROBE" || MXCLI_EXIT=$?
      if [ "$MXCLI_EXIT" -eq 0 ]; then
        ok "mxcli runs ($PROBE_HOW): $(probe_line)"
        note "at: $PMXCLI_PROBE"
      else
        bad "mxcli exists but cannot run (exit $MXCLI_EXIT): $PMXCLI_PROBE"
        printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -3 | while IFS= read -r l; do note "  $l"; done
        note "Exit 126 usually means a binary built for another platform/architecture —"
        note "re-download the mxcli build for this OS."
      fi
    elif [ "$PLATFORM" = gitbash ] && mxtk_is_elf "$PROJECT_DIR/mxcli"; then
      warn "the project's mxcli is the Linux build (the Dev Container's) — Git Bash needs mxcli.exe beside it."
      note "Not a permissions problem: chmod cannot make a Linux binary run here, which is why it"
      note "looked like it 'reverted'. Leave the file for the container and add the Windows build:"
      note "  bin/doctor.sh --install $PROJECT_DIR      (fetches mxcli.exe; the two coexist)"
      note "  or copy the mxcli.exe you already have on PATH into the project root."
    elif [ -f "$PROJECT_DIR/mxcli" ]; then bad "mxcli is present but not executable — chmod +x mxcli"
    else
      warn "no mxcli in the project root"
      note "bin/doctor.sh --install $PROJECT_DIR fetches the right build for this OS/arch"
      note "(from github.com/mendixlabs/mxcli/releases) and then the mxbuild toolchain with it."
    fi

    # Claude Code permissions (2026-10-06): which profile intake Q12 picked, whether the
    # settings files carry it, and what a project file cannot do. Greps only — no Python here.
    head_ "Claude Code permissions: $PROJECT_DIR"
    PERM_PROFILE="$("$TOOLKIT_ROOT/bin/permission-profile.sh" "$PROJECT_DIR" 2>/dev/null)"
    PERM_FROM="$("$TOOLKIT_ROOT/bin/permission-profile.sh" "$PROJECT_DIR" --explain 2>/dev/null | sed -n 's/^from: //p')"
    ok "profile: ${PERM_PROFILE:-?} (from: ${PERM_FROM:-?})"
    PSET="$PROJECT_DIR/.claude/settings.json"
    PLOCAL="$PROJECT_DIR/.claude/settings.local.json"
    PERM_GAP=""
    grep -qF '"Bash(./bin/exec.sh:*)"' "$PSET" 2>/dev/null || PERM_GAP="the safe-wrapper entries"
    case "$PERM_PROFILE" in
      project|full) grep -qF '"Edit(/**)"' "$PSET" 2>/dev/null || PERM_GAP="${PERM_GAP:-the project-folder entries}" ;;
    esac
    [ "$PERM_PROFILE" = full ] && { grep -qE '^[[:space:]]*"Bash",?[[:space:]]*$' "$PLOCAL" 2>/dev/null || PERM_GAP="${PERM_GAP:-the full-access entries}"; }
    if [ -n "$PERM_GAP" ]; then
      warn "the settings files are missing $PERM_GAP for this profile, so Claude Code will prompt for them"
      note "fix: $TOOLKIT_ROOT/bin/install-harness-permissions.sh $PROJECT_DIR"
    else
      ok "settings files match the profile"
    fi
    # The two hooks. Without the PostToolUse(Read) look-ledger hook seen.tsv is never written, so the
    # ledger says "0 seen" for pages whose screenshots were opened (field: a lab project, 22 of 31).
    HOOK_GAP=""
    grep -qF 'bin/session-check.sh' "$PSET" 2>/dev/null || HOOK_GAP="session-check (SessionStart)"
    grep -qF 'bin/look-ledger.sh seen' "$PSET" 2>/dev/null || HOOK_GAP="${HOOK_GAP:+$HOOK_GAP and }look-ledger seen (PostToolUse Read)"
    # #446: the pre-2026-10-21 relative form records nothing from any cwd but the project root.
    # Any look hook not in the root-resolving form. Each "command" string is split onto its own
    # line first, so a single-line settings.json holding both forms is still caught (#502).
    grep -F 'look-ledger.sh seen' "$PSET" 2>/dev/null | awk '{gsub(/"command"/, "\n\"command\""); print}' | grep -F 'look-ledger.sh seen' | grep -vqF 'CLAUDE_PROJECT_DIR' && HOOK_GAP="${HOOK_GAP:+$HOOK_GAP and }look-ledger seen run from the project root (a look hook that does not cd to \$CLAUDE_PROJECT_DIR first records nothing from any other cwd)"
    # The installer rewrites only its own old form (`bash bin/look-ledger.sh seen || true`); a
    # hand-written variant it leaves alone, so naming --hooks-only for it would be a dead end.
    LOOK_CUSTOM=0
    case "$HOOK_GAP" in *"project root"*)
      grep -F 'look-ledger.sh seen' "$PSET" 2>/dev/null | awk '{gsub(/"command"/, "\n\"command\""); print}' \
        | grep -F 'look-ledger.sh seen' | grep -vF 'CLAUDE_PROJECT_DIR' | grep -vqF '"bash bin/look-ledger.sh seen || true"' && LOOK_CUSTOM=1 ;;
    esac
    if [ -n "$HOOK_GAP" ] && [ -f "$PROJECT_DIR/.mxtk/no-hook-repair" ]; then
      ok "hook gap ($HOOK_GAP) accepted: .mxtk/no-hook-repair is set"
    elif [ -n "$HOOK_GAP" ]; then
      warn "the project's .claude/settings.json has no hook for $HOOK_GAP, so the look ledger will read 0 seen however many screenshots were opened"
      note "fix: $TOOLKIT_ROOT/bin/install-claude-permissions.sh $PROJECT_DIR --hooks-only   (or bin/sync-project.sh $PROJECT_DIR)"
      [ "$LOOK_CUSTOM" = 1 ] && note "the look hook is a hand-written variant the installer will not rewrite: edit it by hand in .claude/settings.json to cd to \$CLAUDE_PROJECT_DIR first (the installed form is in bin/install-claude-permissions.sh, LOOK_HOOK)"
    else
      ok "session-check and look-ledger hooks are in .claude/settings.json"
    fi
    for _pf in "$PSET" "$PLOCAL"; do
      if grep -qE '"defaultMode"[[:space:]]*:[[:space:]]*"(auto|bypassPermissions)"' "$_pf" 2>/dev/null; then
        warn "${_pf#$PROJECT_DIR/} sets defaultMode to auto/bypassPermissions — Claude Code ignores that in a project file"
      fi
    done
    _um="$(grep -oE '"defaultMode"[[:space:]]*:[[:space:]]*"[A-Za-z]+"' "$HOME/.claude/settings.json" 2>/dev/null | sed -E 's/.*"([A-Za-z]+)"$/\1/' | head -1)"
    note "your own default mode (~/.claude/settings.json): ${_um:-not set, so the Claude Code built-in default applies}"
    note "No prompts at all is your call, not the project's: set it in ~/.claude/settings.json, or start"
    note "'claude --dangerously-skip-permissions' only inside a container/VM. Deny/ask rules still apply."

    # Property sets (#295) — see the header above ps_check. A full run checks (read-only);
    # --quick (what exec.sh runs when the mxcli version changes) only compares the receipt
    # with the installed mxcli, so an upgrade surfaces as a WARN at the next exec.
    head_ "Property sets (Studio Pro merge safety): $PROJECT_DIR"
    if [ "$QUICK" != 1 ]; then
      ps_check
    elif [ -n "${MPR:-}" ] && [ -n "${PMXCLI_PROBE:-}" ]; then
      PS_VER="$(ps_version "$PMXCLI_PROBE")"
      if ps_stale; then
        _psq_rc=0; ps_supported "$PMXCLI_PROBE" || _psq_rc=$?
        case "$_psq_rc" in
          0) warn "property sets not checked for this mxcli (${PS_VER:-?}) — Studio Pro merge/diff can throw on units an older mxcli wrote"
             note "read-only check: bin/doctor.sh --property-sets $PROJECT_DIR" ;;
          1) note "${PS_VER:-this mxcli} predates 'mxcli fix property-sets' (v0.26.0) — upgrade before a Team Server merge" ;;
          *) warn "property sets: could not probe this mxcli for 'fix property-sets' ('mxcli fix --help' failed)" ;;
        esac
      else
        _psq="$(sed -n 1p "$(ps_receipt)")"
        case "$_psq" in
          *" clean "*|*" clean") ok "property sets: last check for this mxcli was clean ($_psq)" ;;
          *" unproven "*) warn "property sets: last check for this mxcli was clean, but the model is below Mendix 10.24.24, so that proves nothing (mendixlabs/mxcli#1595)"
                          note "run: mx diff <base>.mpr <mine>.mpr out.json; exit 0 is clean" ;;
          *" unsupported "*) note "property sets: this mxcli cannot check them (v0.26.0+ needed)" ;;
          *) warn "property sets: last check for this mxcli: $_psq"
             note "repair: bin/doctor.sh --fix-property-sets $PROJECT_DIR" ;;
        esac
      fi
    else
      note "property sets: NOT RUN — no .mpr or no runnable project mxcli (see above)"
    fi
  fi
fi

# --- gate self-test ---------------------------------------------------------------------------
#
# WHY THIS SECTION EXISTS. exec.sh's mxbuild gate has, in the field, silently reported "?" and
# applied real errors with exit 0 — a wrong-architecture mxbuild once reported 0 errors for
# several commits before anyone noticed (merge desk, after Marco Keijsers' #59 and the July
# wrong-arch mxbuild incident). Every section above this one answers "is mxbuild present and
# does it run" — none of them answers "if the model actually had an error, would the gate SEE
# it". This one does: it runs the exact function exec.sh's gate and pre-flight baseline both
# trust (mxtk_mxbuild_error_count, project-bin/_common.sh — the mandatory chain step producing
# every count this section reads) against a SCRATCH COPY of the real project model, first
# clean, then with a deliberately-broken microflow injected via the project's own mxcli, and
# requires the count to go from a real 0 to a real >=1. A gate that cannot tell those two states
# apart is worse than no gate at all: it reports green on a broken build.
#
# The project's own .mpr/mprcontents are never touched — this runs entirely inside a scratch
# directory, removed on every exit path via a RETURN trap (bash), not just the happy path.
#
# THE SCRATCH COPY IS THE WHOLE MODEL DIRECTORY, NOT JUST .mpr + mprcontents/. Two field
# reports (an Atlas project on Mendix 11.14.0 with mxcli v0.23.0, Windows 11; and a project
# with a custom theme on Mendix 11.12.4, macOS) both saw this self-test FAIL with a dirty
# baseline — 1000+ `Could not find widget ...` / design-property errors, every one of them
# from Atlas_Web_Content page templates or the custom theme — while the real gate (exec.sh /
# verify-model.sh, which run mxbuild --target=deploy IN PLACE against the project as it sits
# on disk) passed with 0 errors on the identical model. A --target=deploy build resolves
# widget/theme/design-property references out of theme/, resources/, widgets/ and javasource/
# sitting BESIDE the .mpr; a copy of only .mpr + mprcontents/ cannot see any of them, so it
# fails on resources that were never actually broken. Options weighed and why they lost:
#   A. mxbuild --target=check (skip resource resolution). No evidence this target exists —
#      grepped bin/, project-bin/, skills/, bug-logs/: every real gate in this toolkit runs
#      --target=deploy, and nothing here has ever invoked --target=check.
#   B. A sibling .mpr copied into the project's OWN directory. Unsafe, not chosen: MPR v2
#      stores its content in mprcontents/ beside the .mpr, so a second .mpr dropped next to
#      the real one collides with the project's own mprcontents/ — this would risk corrupting
#      the very model it is meant to leave untouched.
#   (Symlinks into the project tree instead of copying were also considered and rejected:
#   Git Bash on Windows silently COPIES through a symlink instead of linking it, unless
#   MSYS=winsymlinks is set on that machine — nothing here can assume it is.)
#   C. Copy the whole project tree. Chosen, scoped down: copy the directory that holds the
#   .mpr (dirname "$MPR" — the project root on a single-tree checkout, app/ on a two-tree one,
#   CLAUDE.md "Shipping an instrument" rule 2), minus .git/, deployment/, node_modules/ and
#   .mpr-snapshots/ — none of which mxbuild reads, and the last of which can itself hold
#   several full mprcontents/ copies. The model's real basename is preserved automatically,
#   because every sibling is copied as-is (a renamed .mpr makes mxbuild bail before it writes
#   an error file at all — reported 2026-09-22, the basename fix below). This measures nothing
#   it cannot afford: the copied size is printed (du -sh) so a user sees the cost before the
#   next run, not after.
#
# Skipped under --quick (two extra mxbuild runs); force it with `bin/doctor.sh --gate-selftest
# [project-dir]`, which also works stood alone without waiting through the rest of doctor.
# Bounded by DOCTOR_GATE_TIMEOUT (default 300s) via mxtk_mxbuild_error_count. exec.sh's own
# gate is unbounded by default (MXTK_GATE_TIMEOUT) — a slow real build must never be mistaken
# for a failed one and restored; only this throwaway copy gets a clock.

GATE_SELFTEST_LINE=""

if [ "$QUICK" != 1 ] || [ "$GATE_SELFTEST" = 1 ]; then

head_ "Gate self-test (can the mxbuild gate actually see an error?)"

# A JDK/model mismatch is the commonest reason mxbuild stops before checking (#576): name the
# fix next to mxbuild's own words.
gate_selftest_java_hint() {
  case "$1" in
    *"release version"*"not supported"*|*"Unsupported class file major version"*)
      note "the model needs JDK ${JAVA_WANT:-?}; this run used ${JAVA_HOME_FOUND:-?} — see the Java line under 'Build toolchain'" ;;
  esac
}

gate_selftest() {
  local scratch scratch_mpr t0 t1 elapsed mdl model_dir base_count bad_count rc timeout_s
  local copy_excl copy_ok entry entry_name x copy_size why
  timeout_s="${DOCTOR_GATE_TIMEOUT:-300}"
  t0=$(date +%s)

  if [ -z "$PROJECT_DIR" ] || [ -z "${MPR:-}" ]; then
    note "NOT RUN — no project / no .mpr given (pass a project dir to doctor.sh to enable this)"
    GATE_SELFTEST_LINE="not-run (no project/.mpr)"
    return 0
  fi
  if [ ! -x "$MXBUILD" ] || [ ! -x "$JAVA_EXE" ]; then
    note "NOT RUN — mxbuild/java not resolved (see 'Build toolchain' above)"
    GATE_SELFTEST_LINE="not-run (no mxbuild)"
    return 0
  fi
  if [ -z "${PMXCLI_PROBE:-}" ]; then
    note "NOT RUN — no project mxcli resolved (see 'Project' above)"
    GATE_SELFTEST_LINE="not-run (no mxcli)"
    return 0
  fi

  scratch="$(mktemp -d /tmp/doctor-gate-selftest.XXXXXX)" || {
    bad "gate self-test: could not create a scratch directory"
    GATE_SELFTEST_LINE="fail (no scratch dir)"
    return 0
  }
  trap 'rm -rf "$scratch" 2>/dev/null' RETURN

  # Copy the WHOLE model directory — .mpr, mprcontents/, theme/, resources/, widgets/,
  # javasource/, everything a --target=deploy build reads off disk beside the .mpr — minus
  # what it never reads. See the section header above ("THE SCRATCH COPY IS THE WHOLE MODEL
  # DIRECTORY") for the two field reports this fixes and the options it was weighed against.
  # The model's REAL basename is preserved automatically because every sibling, the .mpr
  # included, is copied as itself: mprcontents/ carries an internal record of the .mpr's own
  # name, and a renamed copy makes mxbuild bail BEFORE it writes any error file at all — which
  # this self-test would then report as "gate cannot read mxbuild's error file", a false FAIL
  # on a healthy gate (reported 2026-09-22 by Yvann).
  model_dir="$(dirname "$MPR")"
  copy_excl=".git deployment node_modules .mpr-snapshots"
  copy_ok=1
  for entry in "$model_dir"/* "$model_dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    entry_name="$(basename "$entry")"
    for x in $copy_excl; do
      [ "$entry_name" = "$x" ] && continue 2
    done
    # Studio Pro's lock file: copied along, it makes mxcli refuse the known-bad injection
    # into the throwaway copy ("Studio Pro has this project open"), the normal case during
    # setup (#577). The lock belongs to the real model, never to the scratch copy.
    case "$entry_name" in *.mpr.lock) continue ;; esac
    cp -R "$entry" "$scratch/" 2>/dev/null || copy_ok=0
  done
  scratch_mpr="$scratch/$(basename "$MPR")"
  if [ "$copy_ok" -ne 1 ] || [ ! -e "$scratch_mpr" ]; then
    bad "gate self-test: could not copy the model directory into the scratch dir"
    GATE_SELFTEST_LINE="fail (copy failed)"
    return 0
  fi
  copy_size="$(du -sh "$scratch" 2>/dev/null | awk '{print $1}')"
  note "copied ${copy_size:-?} of project resources into the scratch dir (excluding .git, deployment/, node_modules/, .mpr-snapshots/, *.mpr.lock)"

  # (a) Baseline: the gate must resolve SOME integer off this model, clean or not — "?" here
  # means the gate cannot read mxbuild's own output, which is the original F-042-class defect.
  # The errors file is kept so a "?" can say WHY: the count runs in a $(...) subshell, so
  # MXTK_MXBUILD_WHY never reaches this function (#576 — "cannot read mxbuild's error file"
  # when mxbuild had in fact said "release version 25 not supported").
  base_count=$(mxtk_mxbuild_error_count "$scratch_mpr" "$timeout_s" "$scratch/errors-base.json")
  rc=$?
  if [ "$rc" -eq 3 ]; then
    bad "gate self-test: mxbuild did not return within ${timeout_s}s (baseline run)"
    GATE_SELFTEST_LINE="fail (timeout)"
    return 0
  fi
  if [ "$base_count" = "?" ]; then
    why=$(mxtk_mxbuild_why "$scratch/errors-base.json")
    if [ -n "$why" ]; then
      bad "gate self-test: mxbuild stopped before checking the model (baseline run): $why"
      gate_selftest_java_hint "$why"
      GATE_SELFTEST_LINE="fail (mxbuild did not check: ${why:0:80})"
      return 0
    fi
    bad "gate self-test: gate cannot read mxbuild's error file (baseline run) — a real error would go unseen"
    GATE_SELFTEST_LINE="fail (unreadable error file)"
    return 0
  fi
  ok "baseline: gate read $base_count error(s) off the scratch copy"

  # A dirty baseline makes the known-bad control meaningless: if the untouched copy already
  # reports errors, a self-test that later sees a HIGHER (but still nonzero) count on the
  # deliberately-broken copy proves nothing — the delta could be noise, not the injected error.
  if [ "$base_count" -ne 0 ] 2>/dev/null; then
    bad "gate self-test: baseline copy already reports $base_count error(s) — dirty model, the known-bad control cannot prove anything against it"
    GATE_SELFTEST_LINE="fail (dirty baseline: $base_count)"
    return 0
  fi

  # (b) Known-bad control: inject a deliberate type mismatch (CE0117 shape — assigning a String
  # literal to an Integer) via the project's OWN mxcli, throwaway module/microflow name, quoted
  # identifiers per this toolkit's MDL convention, and require the gate to see >=1 error. Zero
  # here means the gate is blind: it would report a genuinely broken model as clean.
  mdl="$scratch/gate-selftest.mdl"
  cat > "$mdl" <<'MDL'
CREATE MODULE "DrGateSelftest";
CREATE MICROFLOW "DrGateSelftest"."MF_GateSelftest" ()
BEGIN
  DECLARE $Bad Integer = 0;
  SET $Bad = 'not-a-number';
END;
MDL
  # If mxcli refuses the injection (syntax rejected by a newer grammar, model locked, ...),
  # the copy is still clean and a 0 below would be a FALSE "blind" verdict — say NOT RUN.
  if ! "$PMXCLI_PROBE" exec "$mdl" -p "$scratch_mpr" >"$scratch/inject.out" 2>&1; then
    warn "gate self-test: NOT RUN — the project's mxcli refused the known-bad injection:"
    sed 's/^/      /' "$scratch/inject.out" | head -5
    GATE_SELFTEST_LINE="not-run (injection refused)"
    return 0
  fi

  bad_count=$(mxtk_mxbuild_error_count "$scratch_mpr" "$timeout_s" "$scratch/errors-bad.json")
  rc=$?
  if [ "$rc" -eq 3 ]; then
    bad "gate self-test: mxbuild did not return within ${timeout_s}s (known-bad run)"
    GATE_SELFTEST_LINE="fail (timeout)"
    return 0
  fi
  if [ "$bad_count" = "?" ]; then
    why=$(mxtk_mxbuild_why "$scratch/errors-bad.json")
    if [ -n "$why" ]; then
      bad "gate self-test: mxbuild stopped before checking the model (known-bad run): $why"
      GATE_SELFTEST_LINE="fail (mxbuild did not check: ${why:0:80})"
      return 0
    fi
    bad "gate self-test: gate cannot read mxbuild's error file (known-bad run) — a real error would go unseen"
    GATE_SELFTEST_LINE="fail (unreadable error file)"
    return 0
  fi
  if [ "$bad_count" -eq 0 ] 2>/dev/null; then
    bad "gate self-test: gate is blind — a known-bad model (CE0117 type mismatch) reports clean"
    GATE_SELFTEST_LINE="fail (blind)"
    return 0
  fi
  # The count must have actually MOVED off the (already-verified-zero) baseline — a gate that
  # reports the same constant nonzero count on both the clean and the deliberately-broken copy
  # would pass an `-eq 0` check by luck while never having read the injected error at all.
  if [ "$bad_count" -le "$base_count" ] 2>/dev/null; then
    bad "gate self-test: gate is blind — known-bad copy reports $bad_count error(s), no higher than the $base_count baseline"
    GATE_SELFTEST_LINE="fail (blind: bad=$bad_count base=$base_count)"
    return 0
  fi

  t1=$(date +%s); elapsed=$(( t1 - t0 ))
  ok "known-bad control: gate read $bad_count error(s) off the deliberately-broken copy (${elapsed}s)"
  GATE_SELFTEST_LINE="pass (baseline=$base_count known-bad=$bad_count ${elapsed}s)"
  return 0
}

gate_selftest

fi

# --- verdict ---------------------------------------------------------------------------------

# Line 2 of the receipt below: the installed mxcli's --version line. Read here, once (it was read
# inside the receipt block before), so the lint-baseline hint below needs no extra mxcli call.
FP_MXCLI="none"
[ -n "$PROJECT_DIR" ] && [ -x "$PROJECT_DIR/mxcli" ] && FP_MXCLI="$("$PROJECT_DIR/mxcli" --version 2>/dev/null | head -1)"

# Lint baseline vs this mxcli. A new mxcli can add built-in rules (v0.28.0: CONV020) that raise
# lint on the next exec with no model change. lint-gate.sh --update-baseline records
# mxcli_version. Notes only: the exit code does not change, the gate's behaviour does not either.
_lb="${PROJECT_DIR:-.}/.claude/lint-baseline.json"
_lb_now="$(printf '%s\n' "$FP_MXCLI" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ -n "$PROJECT_DIR" ] && [ -f "$_lb" ] && [ -n "$_lb_now" ]; then
  _lb_was="$(sed -n 's/.*"mxcli_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_lb" | head -1)"
  if [ "$_lb_was" != "$_lb_now" ]; then
    head_ "Lint baseline: $PROJECT_DIR"
    # No recorded version is no evidence of a rise: name no command (a reflex re-baseline is what
    # skills/lint-that-actually-runs.md warns against). A recorded, different one is evidence.
    if [ -z "$_lb_was" ]; then
      note "lint baseline records no mxcli version; if mxcli was upgraded since it was taken, new built-in rules can raise lint."
      note "  the next bin/lint-gate.sh --update-baseline records it; nothing to do until lint actually rises."
    else
      note "lint baseline was taken with mxcli $_lb_was; this is $_lb_now. New built-in rules can raise lint."
      note "  after reviewing the new findings: bin/lint-gate.sh --update-baseline --reason \"mxcli $_lb_now built-in rules\""
    fi
  fi
fi

head_ "Verdict"

# Leave a dated receipt in the project so gate-check can tell "doctor ran and passed" from
# "nobody ever ran doctor here". Informational only — nothing gates on it, because a machine
# check must never turn into a stage verdict.
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
  if [ "$FAIL" -gt 0 ]; then RECEIPT_VERDICT=fail
  elif [ "$WARN" -gt 0 ]; then RECEIPT_VERDICT=warn
  else RECEIPT_VERDICT=ok; fi
  mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || true
  # Line 2 is the environment fingerprint: mxcli version, mxbuild path, arch. exec.sh re-runs
  # `doctor.sh --quick` when it changes or the receipt is over a day old (warn-only).
  { printf '%s %s fail=%s warn=%s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$RECEIPT_VERDICT" "$FAIL" "$WARN" "$( [ "$QUICK" = 1 ] && echo ' quick')"
    printf 'fingerprint: %s | %s | %s\n' "$FP_MXCLI" "${MXBUILD:-no-mxbuild}" "$(uname -sm)"
    [ -n "$GATE_SELFTEST_LINE" ] && printf 'gate-selftest: %s\n' "$GATE_SELFTEST_LINE"
  } > "$PROJECT_DIR/.claude/.doctor-receipt" 2>/dev/null || true
  # The receipt is MACHINE-LOCAL by design (like .guide-shown): committing one machine's
  # receipt would satisfy gate-check's doctor-ran probe on every other machine. Since this
  # script creates the file, it also keeps it out of git — otherwise every wired project
  # trips clean-tree hooks on an untracked file doctor itself wrote (field case: a stop
  # hook demanding it be committed, 2026-09-02).
  if [ -d "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q .claude/.doctor-receipt 2>/dev/null; then
    printf '\n# Machine-local toolkit marker (doctor.sh preflight receipt)\n/.claude/.doctor-receipt\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null || true
    note "(added /.claude/.doctor-receipt to the project's .gitignore — the receipt is machine-local)"
  fi
  # toolkit.env holds this machine's paths — never something to commit.
  if [ -d "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q .claude/toolkit.env 2>/dev/null; then
    printf '\n# Machine-local tool locations (bin/doctor.sh / project-bin/_common.sh)\n/.claude/toolkit.env\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null || true
    note "(added /.claude/toolkit.env to the project's .gitignore — it holds this machine's paths)"
  fi
  # The progress report's session cache holds absolute session-log paths (user name, session ids).
  # -e, not -d: in a git worktree .git is a file. --no-index: a tracked file is never "ignored" otherwise,
  # and the line would be appended again on every run.
  if [ -e "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q --no-index .claude/progress-report-sessions.txt 2>/dev/null; then
    printf '\n# Machine-local progress report session cache (absolute session-log paths)\n/.claude/progress-report-sessions.txt\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null || true
    note "(added /.claude/progress-report-sessions.txt to the project's .gitignore — the cache is machine-local)"
  fi
  if [ -e "$PROJECT_DIR/.git" ] && git -C "$PROJECT_DIR" ls-files --error-unmatch .claude/progress-report-sessions.txt >/dev/null 2>&1; then
    note "(.claude/progress-report-sessions.txt is already tracked by git; untrack it with: git rm --cached .claude/progress-report-sessions.txt)"
  fi
fi

RF_SPAWN_MS="$_spawn_ms"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s thing(s) to sort out before the first model write (FAIL lines), %s note(s) worth reading (WARN).\n' "$FAIL" "$WARN"
  printf '  Analysis and planning stages run fine meanwhile; each FAIL line says what fixes it.\n'
  _vexit=2
elif [ "$WARN" -gt 0 ]; then
  printf '  Ready. %s warning(s) above — read each one: some are optional, a missing .mpr or CLAUDE.local.md is not.\n' "$WARN"
  _vexit=1
else
  printf '  Ready.\n'
  _vexit=0
fi
recommended_fix
exit "$_vexit"
