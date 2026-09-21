#!/usr/bin/env bash
# test-common-windows.sh — project-bin/_common.sh's Windows-onboarding helpers, unit-tested
# directly (not through exec.sh), on a stubbed Git Bash platform.
#
# Field origin: a Windows onboarding (2026-09-08) with Studio Pro 10.24 + 11.8 + 11.11 side by
# side, a JDK that was not the JRE on PATH, and a Dev Container's ELF mxcli left on disk beside
# Git Bash's own mxcli.exe. Three helpers came out of that incident:
#   mxtk_load_env        — toolkit.env precedence (env > project file > user file)
#   mxtk_is_elf           — tell a Linux ELF binary from a Windows/shell one
#   find_project_mxcli   — on Windows, prefer mxcli.exe and refuse an ELF mxcli outright
#
#   usage: bash tests/wave2/test-common-windows.sh project-bin/_common.sh
#
# Each case sources _common.sh fresh in its own `bash -c` subshell, because PROJECT_ROOT and
# MXTK_ENV_LOADED are resolved once at source time (top-level code, not re-run by calling a
# function again) — re-sourcing in one long-lived shell would carry the previous case's
# environment forward. HOME is redirected per-case so this machine's own (absent, but not
# guaranteed absent on every machine) ~/.mxcli-toolkit.env can never leak into a result.
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-common-windows.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

# run <label-var-unused> <extra-env-assignments...> -- <bash -c body>
# Small wrapper so each case reads as "env vars, then what we're asserting about".
run_in() {
  # $1 = PROJECT_ROOT, $2 = HOME, $3 = extra env (single string, may be empty), $4 = script body
  env -i PATH="$PATH" PROJECT_ROOT="$1" HOME="$2" ${3:+$3} \
    bash -c "set -u; source '$COMMON'; $4"
}

# ── Fixture project ──────────────────────────────────────────────────────────
P="$T/proj"
mkdir -p "$P/.claude"
: > "$P/Fixture.mpr"

# A real ELF binary to test mxtk_is_elf's positive case: any binary already on this Linux
# fixture-runner machine works, since ELF-ness is about the file header, not what it does.
# `true` is a shell builtin in most shells, so `command -v true` returns the builtin, not a
# path — `type -P` skips builtins/functions/aliases and returns the on-disk binary directly.
REAL_ELF="$(type -P true)"
if [ -z "$REAL_ELF" ] || [ ! -f "$REAL_ELF" ]; then
  echo "SKIP: no on-disk 'true' binary found to use as a real ELF fixture" >&2
  exit 0
fi

# ── 1: mxtk_load_env — env var already set wins over both files ──────────────
echo "== 1: mxtk_load_env — pre-set env var beats project and user files =="
printf 'MENDIX_APP=/from/project/file\n' > "$P/.claude/toolkit.env"
mkdir -p "$T/user-home"
printf 'MENDIX_APP=/from/user/file\n' > "$T/user-home/.mxcli-toolkit.env"
OUT=$(run_in "$P" "$T/user-home" "MENDIX_APP=/from/real/env" 'echo "$MENDIX_APP"')
[ "$OUT" = "/from/real/env" ] && ok "pre-set env wins (-> $OUT)" || fail "pre-set env did not win (-> $OUT)"

# ── 2: mxtk_load_env — project file wins over user file ──────────────────────
echo "== 2: mxtk_load_env — project file beats user file =="
OUT=$(run_in "$P" "$T/user-home" "" 'echo "$MENDIX_APP"')
[ "$OUT" = "/from/project/file" ] && ok "project file wins (-> $OUT)" || fail "project file did not win (-> $OUT)"

# ── 3: mxtk_load_env — user file used when no project file / env var ─────────
echo "== 3: mxtk_load_env — user file used as the last resort =="
rm -f "$P/.claude/toolkit.env"
OUT=$(run_in "$P" "$T/user-home" "" 'echo "$MENDIX_APP"')
[ "$OUT" = "/from/user/file" ] && ok "user file used (-> $OUT)" || fail "user file not used (-> $OUT)"
OUT=$(run_in "$P" "$T/user-home" "" 'echo "$MXTK_ENV_LOADED"')
case "$OUT" in *"user-home/.mxcli-toolkit.env"*) ok "MXTK_ENV_LOADED names the user file (-> $OUT)" ;; \
  *) fail "MXTK_ENV_LOADED does not name the user file (-> $OUT)" ;; esac

# ── 4: mxtk_load_env — a Windows-form path is converted for Git Bash ─────────
echo "== 4: mxtk_load_env — Windows-form path (C:\\...) converted to /c/... =="
printf 'MENDIX_APP=C:\\Program Files\\Mendix\\11.11.0\n' > "$P/.claude/toolkit.env"
OUT=$(run_in "$P" "$T/user-home" "" 'echo "$MENDIX_APP"')
[ "$OUT" = "/c/Program Files/Mendix/11.11.0" ] && ok "converted (-> $OUT)" || fail "not converted (-> $OUT)"
rm -f "$P/.claude/toolkit.env"

# ── 5: mxtk_is_elf — a real ELF binary is reported true ──────────────────────
echo "== 5: mxtk_is_elf — a real ELF binary =="
OUT=$(run_in "$P" "$T/user-home" "" "mxtk_is_elf '$REAL_ELF' && echo yes || echo no")
[ "$OUT" = "yes" ] && ok "real ELF detected" || fail "real ELF not detected (-> $OUT)"

# ── 6: mxtk_is_elf — a shell-script mxcli.exe stand-in is reported false ─────
echo "== 6: mxtk_is_elf — a shell script (Git Bash's own mxcli.exe shape) =="
printf '#!/usr/bin/env bash\necho stub\n' > "$T/script-mxcli"
chmod +x "$T/script-mxcli"
OUT=$(run_in "$P" "$T/user-home" "" "mxtk_is_elf '$T/script-mxcli' && echo yes || echo no")
[ "$OUT" = "no" ] && ok "shell script not flagged as ELF" || fail "shell script wrongly flagged as ELF (-> $OUT)"

# ── 7: find_project_mxcli — on stubbed Git Bash, prefers mxcli.exe over an ELF mxcli ─
echo "== 7: find_project_mxcli — Windows platform prefers mxcli.exe over a same-dir ELF mxcli =="
cp "$REAL_ELF" "$P/mxcli"; chmod +x "$P/mxcli"                 # the Dev Container's leftover ELF
cp "$T/script-mxcli" "$P/mxcli.exe"; chmod +x "$P/mxcli.exe"    # Git Bash's own build
OUT=$(run_in "$P" "$T/user-home" "OSTYPE=msys" 'find_project_mxcli')
[ "$OUT" = "$P/mxcli.exe" ] && ok "mxcli.exe preferred (-> $OUT)" || fail "wrong binary chosen (-> $OUT)"

# ── 8: find_project_mxcli — on stubbed Git Bash, an ELF-only mxcli is refused ────────
echo "== 8: find_project_mxcli — Windows platform refuses an ELF-only mxcli (no .exe present) =="
rm -f "$P/mxcli.exe"
OUT=$(run_in "$P" "$T/user-home" "OSTYPE=msys" 'find_project_mxcli && echo "FOUND:$?" || echo NOTFOUND')
[ "$OUT" = "NOTFOUND" ] && ok "ELF-only mxcli refused on Windows (exit 126 class failure avoided)" \
                         || fail "ELF-only mxcli was NOT refused (-> $OUT)"

# ── 9: find_project_mxcli — same ELF-only mxcli is accepted on Linux ─────────────────
echo "== 9: find_project_mxcli — the same ELF mxcli is fine on a real Linux/container platform =="
OUT=$(run_in "$P" "$T/user-home" "OSTYPE=linux-gnu" 'find_project_mxcli')
[ "$OUT" = "$P/mxcli" ] && ok "ELF mxcli accepted on Linux (-> $OUT)" || fail "ELF mxcli wrongly refused on Linux (-> $OUT)"

echo; echo "$PASS passed, $FAIL failed   ($T)"
[ "$FAIL" -eq 0 ]
