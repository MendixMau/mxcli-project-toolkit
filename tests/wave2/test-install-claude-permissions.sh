#!/usr/bin/env bash
# test-install-claude-permissions.sh — bin/install-claude-permissions.sh: the safe-wrapper
# permission allow-list merged into <project>/.claude/settings.json.
#
# Covers: fresh project (no settings.json) gets the file + all entries; an existing
# `mxcli init`-written settings.json gets the entries merged in, pre-existing entries kept
# exactly once, the unrelated `env` block untouched; a second run is byte-identical
# (idempotent); `--check` on a project missing entries exits non-zero and names them;
# `--uninstall` removes only the entries this script itself added, leaving a pre-existing
# `Bash(./mxcli:*)` in place.
#
# The "existing settings.json" fixture below is a REAL capture from a project scaffolded by
# `mxcli init`, 2026-09-16 — no project name attached, content only.
#
# Usage: bash tests/wave2/test-install-claude-permissions.sh [path-to-install-claude-permissions.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/install-claude-permissions.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TOOLKIT_ROOT="$(cd "$(dirname "$SUBJECT")/.." && pwd)"

# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/permtest.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

[ -x "$SUBJECT" ] || { echo "FAIL — subject not found/executable: $SUBJECT"; echo "PASS=0 FAIL=1"; exit 1; }

# The exact 11 entries the script is specified to install, so this fixture fails if the
# allow-list in the script drifts without a matching test update.
EXPECTED=(
  "Bash(./bin/exec.sh:*)"
  "Bash(bin/exec.sh:*)"
  "Bash(bash bin/exec.sh:*)"
  "Bash(./bin/*.sh:*)"
  "Bash(bin/*.sh:*)"
  "Bash(bash bin/*.sh:*)"
  "Bash($TOOLKIT_ROOT/bin/*.sh:*)"
  "Bash(bash $TOOLKIT_ROOT/bin/*.sh:*)"
  "Bash(~/.mxcli/mxbuild/*/modeler/mx:*)"
  "Bash(./mxcli:*)"
  "Bash(mxcli:*)"
)

py_get_allow() {  # $1 = settings.json path -> prints one allow entry per line
  "$PY" - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for e in d.get("permissions", {}).get("allow", []):
    print(e)
PY
}

py_get_env_val() {  # $1 = settings.json path, $2 = env key -> prints its value
  "$PY" - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("env", {}).get(sys.argv[2], ""))
PY
}

# ── T1: fresh project, no .claude/settings.json at all ─────────────────────────────────────
FRESH="$WORK/fresh"
mkdir -p "$FRESH"
"$SUBJECT" "$FRESH" >"$WORK/t1.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "T1: fresh install exits 0" || bad "T1: fresh install exited $RC"
[ -f "$FRESH/.claude/settings.json" ] && ok "T1: settings.json was created" \
                                       || bad "T1: settings.json was not created"

ALLOW1="$(py_get_allow "$FRESH/.claude/settings.json")"
MISSING=0
for e in "${EXPECTED[@]}"; do
  printf '%s\n' "$ALLOW1" | grep -qxF "$e" || { MISSING=1; echo "     missing: $e"; }
done
[ "$MISSING" -eq 0 ] && ok "T1: all ${#EXPECTED[@]} entries present in the fresh file" \
                      || bad "T1: some entries missing from the fresh file"

# ── T2: existing mxcli-init settings.json (real capture, 2026-09-16) ───────────────────────
EXIST="$WORK/existing"
mkdir -p "$EXIST/.claude"
cat > "$EXIST/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(mxcli:*)",
      "Bash(./mxcli:*)",
      "Bash(./mxcli *)",
      "Bash(playwright-cli:*)",
      "Bash(playwright-cli *)"
    ]
  },
  "env": {
    "MXCLI_QUIET": "1"
  }
}
JSON
ORIG_ENV="$(py_get_env_val "$EXIST/.claude/settings.json" MXCLI_QUIET)"

"$SUBJECT" "$EXIST" >"$WORK/t2.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "T2: merge into existing settings.json exits 0" \
                || bad "T2: merge exited $RC"

ALLOW2="$(py_get_allow "$EXIST/.claude/settings.json")"
MISSING=0
for e in "${EXPECTED[@]}"; do
  printf '%s\n' "$ALLOW2" | grep -qxF "$e" || { MISSING=1; echo "     missing: $e"; }
done
[ "$MISSING" -eq 0 ] && ok "T2: all ${#EXPECTED[@]} entries present after merge" \
                      || bad "T2: some entries missing after merge"

# Pre-existing entries kept exactly once each (merge, not append-blind — a naive append would
# duplicate Bash(./mxcli:*) and Bash(mxcli:*), which are both in EXPECTED and already present).
for pre in "Bash(mxcli:*)" "Bash(./mxcli:*)" "Bash(./mxcli *)" "Bash(playwright-cli:*)" "Bash(playwright-cli *)"; do
  N="$(printf '%s\n' "$ALLOW2" | grep -cxF "$pre")"
  [ "$N" -eq 1 ] && ok "T2: pre-existing '$pre' present exactly once" \
                  || bad "T2: pre-existing '$pre' appears $N times (want 1)"
done

NEW_ENV="$(py_get_env_val "$EXIST/.claude/settings.json" MXCLI_QUIET)"
[ "$NEW_ENV" = "$ORIG_ENV" ] && ok "T2: unrelated 'env' block untouched" \
                              || bad "T2: 'env' block changed (was '$ORIG_ENV', now '$NEW_ENV')"

# ── T3: idempotent — run again, file byte-identical ─────────────────────────────────────────
SNAP1="$(cat "$EXIST/.claude/settings.json")"
"$SUBJECT" "$EXIST" >"$WORK/t3.out" 2>&1
SNAP2="$(cat "$EXIST/.claude/settings.json")"
[ "$SNAP1" = "$SNAP2" ] && ok "T3: second run leaves settings.json byte-identical" \
                         || bad "T3: second run changed settings.json"
grep -q 'nothing to do' "$WORK/t3.out" \
  && ok "T3: second run reports nothing added" \
  || bad "T3: second run did not report a no-op"

# ── T4: --check on a project missing entries ────────────────────────────────────────────────
MISS="$WORK/missing"
mkdir -p "$MISS/.claude"
echo '{"permissions":{"allow":["Bash(mxcli:*)"]}}' > "$MISS/.claude/settings.json"
SNAP_BEFORE="$(cat "$MISS/.claude/settings.json")"
"$SUBJECT" "$MISS" --check >"$WORK/t4.out" 2>&1
RC=$?
[ "$RC" -ne 0 ] && ok "T4: --check on a project missing entries exits non-zero" \
                 || bad "T4: --check exited 0 despite missing entries"
MISSING_NAMED=0
for e in "${EXPECTED[@]}"; do
  [ "$e" = "Bash(mxcli:*)" ] && continue  # already present in this fixture, correctly not "missing"
  grep -qxF "  $e" "$WORK/t4.out" || { MISSING_NAMED=1; echo "     not named: $e"; }
done
[ "$MISSING_NAMED" -eq 0 ] && ok "T4: --check names every missing entry" \
                            || bad "T4: --check did not name every missing entry"
grep -qxF "  Bash(mxcli:*)" "$WORK/t4.out" \
  && bad "T4: --check names an entry that was already present" \
  || ok "T4: --check does not name the already-present entry"
SNAP_AFTER="$(cat "$MISS/.claude/settings.json")"
[ "$SNAP_BEFORE" = "$SNAP_AFTER" ] && ok "T4: --check wrote nothing" \
                                    || bad "T4: --check modified settings.json"
[ -e "$MISS/.claude/.mxtk-permissions-added.json" ] \
  && bad "T4: --check created a sidecar file (should write nothing)" \
  || ok "T4: --check created no sidecar file"

# ── T5: --uninstall removes only entries this script added ─────────────────────────────────
"$SUBJECT" "$EXIST" --uninstall >"$WORK/t5.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "T5: --uninstall exits 0" || bad "T5: --uninstall exited $RC"

ALLOW5="$(py_get_allow "$EXIST/.claude/settings.json")"
STILL_ADDED=0
for e in "${EXPECTED[@]}"; do
  case "$e" in
    "Bash(./mxcli:*)"|"Bash(mxcli:*)") continue ;;  # pre-existing; must survive
  esac
  printf '%s\n' "$ALLOW5" | grep -qxF "$e" && { STILL_ADDED=1; echo "     still present: $e"; }
done
[ "$STILL_ADDED" -eq 0 ] && ok "T5: every entry this script added is gone" \
                          || bad "T5: an added entry survived --uninstall"

for pre in "Bash(mxcli:*)" "Bash(./mxcli:*)" "Bash(./mxcli *)" "Bash(playwright-cli:*)" "Bash(playwright-cli *)"; do
  N="$(printf '%s\n' "$ALLOW5" | grep -cxF "$pre")"
  [ "$N" -eq 1 ] && ok "T5: pre-existing '$pre' kept exactly once after uninstall" \
                  || bad "T5: pre-existing '$pre' appears $N times after uninstall (want 1)"
done

NEW_ENV5="$(py_get_env_val "$EXIST/.claude/settings.json" MXCLI_QUIET)"
[ "$NEW_ENV5" = "$ORIG_ENV" ] && ok "T5: 'env' block still untouched after uninstall" \
                                || bad "T5: 'env' block changed by uninstall"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
