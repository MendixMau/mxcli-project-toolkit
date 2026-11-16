#!/usr/bin/env bash
# test-install-claude-permissions.sh — bin/install-claude-permissions.sh (the safe-wrapper
# permission allow-list merged into a Claude Code project's settings files) AND its sibling
# entry point bin/install-harness-permissions.sh (the same idea for Copilot and Aider).
#
# Covers, for install-claude-permissions.sh: fresh project (no settings.json) gets both files
# + all entries, split by whether the entry embeds the absolute $TOOLKIT_ROOT path — the nine
# relative entries (plus the one deny entry, bare `mxcli exec`, and the SessionStart hook) land
# in the SHARED, committable `.claude/settings.json`, the two absolute ones land in the
# per-machine `.claude/settings.local.json` (2026-09-16 split; see that script's header for
# why — the deny entry and hook carry no absolute path, so they stay shared-only); an existing
# `mxcli init`-written settings.json gets the entries merged in, pre-existing entries kept
# exactly once, the unrelated `env` block untouched; a second run is byte-identical on both
# files (idempotent); `--check` on a project missing entries exits non-zero and names them —
# allow, deny and the hook — per file; `--uninstall` removes only the entries this script
# itself added (via the dict-shaped sidecar file, not just the allow list), from both files,
# leaving a pre-existing `Bash(./mxcli:*)` in place.
#
# Covers, for install-harness-permissions.sh: it delegates the Claude part to the script above
# (spot-checked, not re-covering every case); Copilot gets `chat.tools.terminal.autoApprove`
# merged into `.vscode/settings.json` (key name and value shape verified against VS Code's own
# docs — see install-harness-permissions.sh's header for the citation); Aider gets
# `yes-always: true` added to `.aider.conf.yml` when the file exists without it, created fresh
# when the file doesn't exist yet, and left alone (no duplicate) when already present; both are
# idempotent and both uninstall cleanly. Cursor/Windsurf are asserted to write nothing at all,
# per spec (user-level IDE settings only).
#
# The "existing settings.json" fixture below is a REAL capture from a project scaffolded by
# `mxcli init`, 2026-09-16 — no project name attached, content only. The Copilot/Aider fixtures
# further down are not captured the same way (there is no external tool output to capture —
# both are THIS repo's own new writers) but every assertion runs against the scripts' real
# output from an actual invocation on a scratch project, never a hand-typed expectation of
# what that output "should" look like.
#
# Usage: bash tests/wave2/test-install-claude-permissions.sh [path-to-install-claude-permissions.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/install-claude-permissions.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TOOLKIT_ROOT="$(cd "$(dirname "$SUBJECT")/.." && pwd)"
HARNESS_SUBJECT="$(dirname "$SUBJECT")/install-harness-permissions.sh"

# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/permtest.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"
echo "== harness subject: $HARNESS_SUBJECT"

[ -x "$SUBJECT" ] || { echo "FAIL — subject not found/executable: $SUBJECT"; echo "PASS=0 FAIL=1"; exit 1; }

# No mxbuild under a scratch HOME, so the per-version mx rules appear only where T12 adds one.
export HOME="$WORK/home"; mkdir -p "$HOME"

# The relative entries -> the SHARED, committable settings.json. These scratch projects have no
# bin/ of their own, so only the always-listed exec.sh rules and the mxcli rules (#780 shape:
# one rule per script, `*` only at the end).
EXPECTED_SHARED=(
  "Bash(./bin/exec.sh *)"
  "Bash(bin/exec.sh *)"
  "Bash(bash bin/exec.sh *)"
  "Bash(./mxcli *)"
  "Bash(mxcli *)"
)
# The entries that embed the absolute toolkit-root path -> the per-machine settings.local.json:
# two per toolkit script (exec.sh is the project's own copy, never the toolkit's; the installers
# that record a person's decision and the sourced _*.sh libraries get none — #781 review, #782).
# exec-approval.sh, interview-mode.sh and permission-profile.sh are allowed; their --set/--clear
# prompt through ask rules (#782, T12).
EXPECTED_LOCAL=()
for _f in "$TOOLKIT_ROOT"/bin/*.sh; do
  _n="${_f##*/}"
  case "$_n" in exec.sh|_*|init-project.sh|install-claude-permissions.sh|install-harness-permissions.sh|install-claude-hooks.sh) continue ;; esac
  EXPECTED_LOCAL+=( "Bash($TOOLKIT_ROOT/bin/$_n *)" "Bash(bash $TOOLKIT_ROOT/bin/$_n *)" )
done

# The one deny entry and the one SessionStart hook the script also installs — same spec,
# same script, but not exercised anywhere else once test-model-stamp.sh's T8 (which used to
# be the only place testing them) moves off this script's business.
EXPECTED_DENY=(
  "Bash(./mxcli exec:*)"
  "Bash(mxcli exec:*)"
  "Bash(./mxcli.exe exec:*)"
  "Bash(*file-bugs.sh*--file*)"
  "Bash(*file-bugs.sh*--all*)"
  "Bash(*file-bugs.py*--file*)"
  "Bash(*file-bugs.py*--all*)"
  "Bash(*file-bugs.sh*--import*)"
  "Bash(*file-bugs.py*--import*)"
  "Bash(*security-check.sh*--approve*)"
  "Bash(*security-check.sh*--accept*)"
  "Bash(*security-check.sh*--accept-file*)"
  "Edit(/docs/security/access-approved.txt)"
  "Edit(/docs/security/approvals.tsv)"
  "Edit(/.claude/loop/security-accepted.tsv)"
)
SESSION_HOOK="bash bin/session-check.sh || true"

py_get_allow() {  # $1 = settings.json path -> prints one allow entry per line
  "$PY" - "$1" <<'PY'
import json, sys, os
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit(0)
d = json.load(open(p))
for e in d.get("permissions", {}).get("allow", []):
    print(e)
PY
}

py_get_deny() {  # $1 = settings.json path -> prints one deny entry per line
  "$PY" - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for e in d.get("permissions", {}).get("deny", []):
    print(e)
PY
}

py_look_hook_present() {  # $1 = settings.json path -> exit 0 iff the PostToolUse(Read) LOOK hook is there
  "$PY" - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for grp in d.get("hooks", {}).get("PostToolUse", []) or []:
    if grp.get("matcher") == "Read" and any("CLAUDE_PROJECT_DIR" in (h.get("command") or "") and "bin/look-ledger.sh seen" in (h.get("command") or "") for h in grp.get("hooks", []) or []):
        sys.exit(0)
sys.exit(1)
PY
}

py_hook_present() {  # $1 = settings.json path -> exit 0 iff the SessionStart hook is there
  "$PY" - "$1" "$SESSION_HOOK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cmd = sys.argv[2]
for grp in d.get("hooks", {}).get("SessionStart", []) or []:
    for h in grp.get("hooks", []) or []:
        if h.get("command") == cmd:
            sys.exit(0)
sys.exit(1)
PY
}

py_get_env_val() {  # $1 = settings.json path, $2 = env key -> prints its value
  "$PY" - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("env", {}).get(sys.argv[2], ""))
PY
}

_check_present() {  # $1=label $2=file $3...=expected entries
  local label="$1" file="$2"; shift 2
  local allow; allow="$(py_get_allow "$file")"
  local missing=0
  for e in "$@"; do
    printf '%s\n' "$allow" | grep -qxF "$e" || { missing=1; echo "     missing: $e"; }
  done
  [ "$missing" -eq 0 ] && ok "$label: all $# entries present in $(basename "$file")" \
                        || bad "$label: some entries missing from $(basename "$file")"
}

# ══════════════════════════════════════════════════════════════════════════════════════════
# install-claude-permissions.sh
# ══════════════════════════════════════════════════════════════════════════════════════════

# ── T1: fresh project, no .claude/ at all ───────────────────────────────────────────────────
FRESH="$WORK/fresh"
mkdir -p "$FRESH"
"$SUBJECT" "$FRESH" >"$WORK/t1.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "T1: fresh install exits 0" || bad "T1: fresh install exited $RC"
[ -f "$FRESH/.claude/settings.json" ] && ok "T1: settings.json was created" \
                                       || bad "T1: settings.json was not created"
[ -f "$FRESH/.claude/settings.local.json" ] && ok "T1: settings.local.json was created" \
                                             || bad "T1: settings.local.json was not created"
_check_present "T1" "$FRESH/.claude/settings.json" "${EXPECTED_SHARED[@]}"
_check_present "T1" "$FRESH/.claude/settings.local.json" "${EXPECTED_LOCAL[@]}"
for e in "${EXPECTED_LOCAL[@]}"; do
  py_get_allow "$FRESH/.claude/settings.json" | grep -qxF "$e" \
    && bad "T1: an absolute-path entry leaked into the shared settings.json: $e" \
    || ok "T1: absolute-path entry correctly absent from settings.json"
done

DENY1="$(py_get_deny "$FRESH/.claude/settings.json")"
MISSING_DENY=0
for e in "${EXPECTED_DENY[@]}"; do
  printf '%s\n' "$DENY1" | grep -qxF "$e" || { MISSING_DENY=1; echo "     missing deny: $e"; }
done
[ "$MISSING_DENY" -eq 0 ] && ok "T1: all ${#EXPECTED_DENY[@]} deny entries present in the fresh file" \
                           || bad "T1: some deny entries missing from the fresh file"
py_hook_present "$FRESH/.claude/settings.json" && ok "T1: SessionStart hook present in the fresh file" \
                                                 || bad "T1: SessionStart hook missing from the fresh file"
py_look_hook_present "$FRESH/.claude/settings.json" && ok "T1: PostToolUse(Read) LOOK hook present in the fresh file" \
                                                      || bad "T1: PostToolUse(Read) LOOK hook missing from the fresh file"

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

_check_present "T2" "$EXIST/.claude/settings.json" "${EXPECTED_SHARED[@]}"
_check_present "T2" "$EXIST/.claude/settings.local.json" "${EXPECTED_LOCAL[@]}"

# Pre-existing entries kept exactly once each (merge, not append-blind — a naive append would
# duplicate Bash(./mxcli *), which is in EXPECTED_SHARED and already present).
ALLOW2="$(py_get_allow "$EXIST/.claude/settings.json")"
for pre in "Bash(mxcli:*)" "Bash(./mxcli:*)" "Bash(./mxcli *)" "Bash(playwright-cli:*)" "Bash(playwright-cli *)"; do
  N="$(printf '%s\n' "$ALLOW2" | grep -cxF "$pre")"
  [ "$N" -eq 1 ] && ok "T2: pre-existing '$pre' present exactly once" \
                  || bad "T2: pre-existing '$pre' appears $N times (want 1)"
done

NEW_ENV="$(py_get_env_val "$EXIST/.claude/settings.json" MXCLI_QUIET)"
[ "$NEW_ENV" = "$ORIG_ENV" ] && ok "T2: unrelated 'env' block untouched" \
                              || bad "T2: 'env' block changed (was '$ORIG_ENV', now '$NEW_ENV')"

DENY2="$(py_get_deny "$EXIST/.claude/settings.json")"
MISSING_DENY2=0
for e in "${EXPECTED_DENY[@]}"; do
  printf '%s\n' "$DENY2" | grep -qxF "$e" || { MISSING_DENY2=1; echo "     missing deny: $e"; }
done
[ "$MISSING_DENY2" -eq 0 ] && ok "T2: all ${#EXPECTED_DENY[@]} deny entries present after merge" \
                            || bad "T2: some deny entries missing after merge"
py_hook_present "$EXIST/.claude/settings.json" && ok "T2: SessionStart hook present after merge" \
                                                 || bad "T2: SessionStart hook missing after merge"
[ -f "$EXIST/.claude/.mxtk-permissions-added.json" ] \
  && "$PY" -c "import json,sys;d=json.load(open('$EXIST/.claude/.mxtk-permissions-added.json'));sys.exit(0 if isinstance(d,dict) and 'allow' in d and 'deny' in d and 'hook' in d else 1)" \
  && ok "T2: sidecar file is the dict shape ({allow, deny, hook})" \
  || bad "T2: sidecar file missing or not the dict shape"

# ── T3: idempotent — run again, both files byte-identical ──────────────────────────────────
SNAP1="$(cat "$EXIST/.claude/settings.json")"
SNAP1L="$(cat "$EXIST/.claude/settings.local.json")"
"$SUBJECT" "$EXIST" >"$WORK/t3.out" 2>&1
SNAP2="$(cat "$EXIST/.claude/settings.json")"
SNAP2L="$(cat "$EXIST/.claude/settings.local.json")"
[ "$SNAP1" = "$SNAP2" ] && ok "T3: second run leaves settings.json byte-identical" \
                         || bad "T3: second run changed settings.json"
[ "$SNAP1L" = "$SNAP2L" ] && ok "T3: second run leaves settings.local.json byte-identical" \
                           || bad "T3: second run changed settings.local.json"
grep -q 'nothing to do' "$WORK/t3.out" \
  && ok "T3: second run reports nothing added" \
  || bad "T3: second run did not report a no-op"

# ── T4: --check on a project missing entries ────────────────────────────────────────────────
MISS="$WORK/missing"
mkdir -p "$MISS/.claude"
echo '{"permissions":{"allow":["Bash(mxcli *)"]}}' > "$MISS/.claude/settings.json"
SNAP_BEFORE="$(cat "$MISS/.claude/settings.json")"
"$SUBJECT" "$MISS" --check >"$WORK/t4.out" 2>&1
RC=$?
[ "$RC" -ne 0 ] && ok "T4: --check on a project missing entries exits non-zero" \
                 || bad "T4: --check exited 0 despite missing entries"
MISSING_NAMED=0
for e in "${EXPECTED_SHARED[@]}" "${EXPECTED_LOCAL[@]}"; do
  [ "$e" = "Bash(mxcli *)" ] && continue  # already present in this fixture, correctly not "missing"
  grep -qxF "  $e" "$WORK/t4.out" || { MISSING_NAMED=1; echo "     not named: $e"; }
done
[ "$MISSING_NAMED" -eq 0 ] && ok "T4: --check names every missing entry (both files)" \
                            || bad "T4: --check did not name every missing entry"
grep -qxF "  Bash(mxcli *)" "$WORK/t4.out" \
  && bad "T4: --check names an entry that was already present" \
  || ok "T4: --check does not name the already-present entry"
MISSING_DENY_NAMED=0
for e in "${EXPECTED_DENY[@]}"; do
  grep -qxF "  $e" "$WORK/t4.out" || { MISSING_DENY_NAMED=1; echo "     deny not named: $e"; }
done
[ "$MISSING_DENY_NAMED" -eq 0 ] && ok "T4: --check names every missing deny entry" \
                                 || bad "T4: --check did not name every missing deny entry"
grep -qF "hooks.SessionStart: $SESSION_HOOK" "$WORK/t4.out" \
  && ok "T4: --check names the missing SessionStart hook" \
  || bad "T4: --check did not name the missing SessionStart hook"
SNAP_AFTER="$(cat "$MISS/.claude/settings.json")"
[ "$SNAP_BEFORE" = "$SNAP_AFTER" ] && ok "T4: --check wrote nothing to settings.json" \
                                    || bad "T4: --check modified settings.json"
[ -e "$MISS/.claude/settings.local.json" ] \
  && bad "T4: --check created settings.local.json (should write nothing)" \
  || ok "T4: --check created no settings.local.json"
[ -e "$MISS/.claude/.mxtk-permissions-added.json" ] \
  && bad "T4: --check created a sidecar file (should write nothing)" \
  || ok "T4: --check created no sidecar file"

# ── T5: --uninstall removes only entries this script added, from BOTH files ────────────────
"$SUBJECT" "$EXIST" --uninstall >"$WORK/t5.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "T5: --uninstall exits 0" || bad "T5: --uninstall exited $RC"

ALLOW5="$(py_get_allow "$EXIST/.claude/settings.json")"
ALLOW5L="$(py_get_allow "$EXIST/.claude/settings.local.json")"
STILL_ADDED=0
for e in "${EXPECTED_SHARED[@]}"; do
  case "$e" in
    "Bash(./mxcli *)") continue ;;  # pre-existing in the T2 capture; must survive
  esac
  printf '%s\n' "$ALLOW5" | grep -qxF "$e" && { STILL_ADDED=1; echo "     still present: $e"; }
done
for e in "${EXPECTED_LOCAL[@]}"; do
  printf '%s\n' "$ALLOW5L" | grep -qxF "$e" && { STILL_ADDED=1; echo "     still present (local): $e"; }
done
[ "$STILL_ADDED" -eq 0 ] && ok "T5: every entry this script added is gone (both files)" \
                          || bad "T5: an added entry survived --uninstall"

for pre in "Bash(mxcli:*)" "Bash(./mxcli:*)" "Bash(./mxcli *)" "Bash(playwright-cli:*)" "Bash(playwright-cli *)"; do
  N="$(printf '%s\n' "$ALLOW5" | grep -cxF "$pre")"
  [ "$N" -eq 1 ] && ok "T5: pre-existing '$pre' kept exactly once after uninstall" \
                  || bad "T5: pre-existing '$pre' appears $N times after uninstall (want 1)"
done

NEW_ENV5="$(py_get_env_val "$EXIST/.claude/settings.json" MXCLI_QUIET)"
[ "$NEW_ENV5" = "$ORIG_ENV" ] && ok "T5: 'env' block still untouched after uninstall" \
                                || bad "T5: 'env' block changed by uninstall"

DENY5="$(py_get_deny "$EXIST/.claude/settings.json")"
STILL_DENY=0
for e in "${EXPECTED_DENY[@]}"; do
  printf '%s\n' "$DENY5" | grep -qxF "$e" && { STILL_DENY=1; echo "     deny still present: $e"; }
done
[ "$STILL_DENY" -eq 0 ] && ok "T5: every deny entry this script added is gone" \
                          || bad "T5: a deny entry survived --uninstall"

py_hook_present "$EXIST/.claude/settings.json" \
  && bad "T5: SessionStart hook survived --uninstall" \
  || ok "T5: SessionStart hook removed by --uninstall"
py_look_hook_present "$EXIST/.claude/settings.json" \
  && bad "T5: PostToolUse(Read) LOOK hook survived --uninstall" \
  || ok "T5: PostToolUse(Read) LOOK hook removed by --uninstall"

[ -e "$EXIST/.claude/.mxtk-permissions-added.json" ] \
  && bad "T5: sidecar file survived --uninstall (should be removed)" \
  || ok "T5: sidecar file removed by --uninstall"

# ── T5b: profiles (bin/permission-profile.sh) — default, full, downgrade, typo ─────────────
PROF="$WORK/profiles"
mkdir -p "$PROF/.claude"
echo '{"permissions":{"allow":["Bash(git add:*)"]}}' > "$PROF/.claude/settings.json"
"$SUBJECT" "$PROF" >"$WORK/t5b.out" 2>&1
grep -qx "permission profile: project" "$WORK/t5b.out" && ok "T5b: no PROJECT.md resolves to the 'project' default" \
                                                      || bad "T5b: default profile is not 'project'"
py_get_allow "$PROF/.claude/settings.json" | grep -qxF "Edit(/**)" && ok "T5b: project profile allows edits inside the project" \
                                                                    || bad "T5b: project profile missing Edit(/**)"
"$PY" -c "import json,sys;d=json.load(open('$PROF/.claude/settings.json'));sys.exit(0 if 'Bash(sudo *)' in d['permissions'].get('ask',[]) else 1)" \
  && ok "T5b: project profile puts sudo behind an ask rule" || bad "T5b: sudo ask rule missing"
"$SUBJECT" "$PROF" --profile full >/dev/null 2>&1
py_get_allow "$PROF/.claude/settings.local.json" | grep -qx "Bash" && ok "T5b: full adds bare Bash to settings.local.json" \
                                                                   || bad "T5b: full did not add bare Bash locally"
py_get_allow "$PROF/.claude/settings.json" | grep -qx "Bash" && bad "T5b: full leaked bare Bash into the shared settings.json" \
                                                             || ok "T5b: shared settings.json never gets bare Bash"
"$SUBJECT" "$PROF" --profile wrappers >/dev/null 2>&1
ALLOWW="$(py_get_allow "$PROF/.claude/settings.json")"
printf '%s\n' "$ALLOWW" | grep -qxF "Edit(/**)" && bad "T5b: downgrade to wrappers left Edit(/**)" \
                                                 || ok "T5b: downgrade to wrappers removes the project entries"
printf '%s\n' "$ALLOWW" | grep -qxF "Bash(git add:*)" && ok "T5b: downgrade keeps a pre-existing entry it never added" \
                                                       || bad "T5b: downgrade removed a pre-existing entry"
py_get_allow "$PROF/.claude/settings.local.json" | grep -qx "Bash" && bad "T5b: downgrade left bare Bash locally" \
                                                                   || ok "T5b: downgrade removes the full entries"
TYPO="$(MXTK_PERMISSION_PROFILE=fulll "$(dirname "$SUBJECT")/permission-profile.sh" "$PROF" 2>/dev/null)"
[ "$TYPO" = wrappers ] && ok "T5b: a misspelt profile falls back to wrappers" \
                       || bad "T5b: misspelt profile resolved to '$TYPO' (want wrappers)"

# ── T12 (#780): rule shape — bare script calls match, no startup warning, old entries migrate ──
# Matcher per https://code.claude.com/docs/en/permissions ("Wildcard patterns"): `*` is any run of
# characters; a trailing ` *` (or legacy `:*`) also matches the bare command ONLY when it is the
# rule's only wildcard (`Bash(* --help *)` does not match `npm --help`). A `*` before the rest of
# the command raises a startup warning (https://code.claude.com/docs/en/errors).
py_rules() {  # $1 = mode (shape|match|has) $2... = settings files, then "--" and commands
  "$PY" - "$@" <<'PY'
import json, os, re, sys
mode, args = sys.argv[1], sys.argv[2:]
cut = args.index("--") if "--" in args else len(args)
files, cmds = args[:cut], args[cut + 1:]
rules, asks = [], []
for f in files:
    if os.path.exists(f):
        perms = json.load(open(f)).get("permissions", {})
        rules += [r for r in perms.get("allow", []) if r.startswith("Bash")]
        asks += [r for r in perms.get("ask", []) if r.startswith("Bash")]
def match(rule, cmd):
    if rule == "Bash":
        return True
    inner = rule[5:-1]
    if inner.endswith(":*"):
        inner = inner[:-2] + " *"
    if inner.count("*") == 1 and inner.endswith(" *"):
        return cmd == inner[:-2] or cmd.startswith(inner[:-2] + " ")
    return re.fullmatch(re.escape(inner).replace(r"\*", ".*"), cmd) is not None
if mode == "shape":
    badr = [r for r in rules if r != "Bash" and "*" in r[5:-1][:-1]]
    for r in badr:
        print("     wildcard before the end: " + r)
    sys.exit(1 if badr else 0)
if mode == "match":
    miss = [c for c in cmds if not any(match(r, c) for r in rules)]
    for c in miss:
        print("     no rule matches: " + c)
    sys.exit(1 if miss else 0)
if mode in ("runs", "asks"):  # an ask rule beats an allow rule (docs: deny > ask > allow)
    def runs(c):
        return any(match(r, c) for r in rules) and not any(match(r, c) for r in asks)
    def asked(c):
        return any(match(r, c) for r in asks)
    wrong = [c for c in cmds if not (runs(c) if mode == "runs" else asked(c))]
    for c in wrong:
        print("     " + ("prompts: " if mode == "runs" else "no ask rule matches: ") + c)
    sys.exit(1 if wrong else 0)
PY
}
P12="$WORK/p780"; mkdir -p "$P12/bin" "$HOME/.mxcli/mxbuild/11.12.0/modeler"
: > "$HOME/.mxcli/mxbuild/11.12.0/modeler/mx"
for s in exec.sh gate-check.sh status.sh doctor.sh interview-mode.sh exec-approval.sh _common.sh; do : > "$P12/bin/$s"; done
"$SUBJECT" "$P12" --profile wrappers >"$WORK/t12.out" 2>&1
MX="$HOME/.mxcli/mxbuild/11.12.0/modeler/mx"
py_rules shape "$P12/.claude/settings.json" "$P12/.claude/settings.local.json" \
  && ok "T12: no allow rule has a * before its final ' *' (no startup warning rows)" \
  || bad "T12: allow rules with a * before the end (each one a startup warning)"
py_rules match "$P12/.claude/settings.json" -- ./bin/gate-check.sh bin/status.sh "bash bin/doctor.sh" ./bin/exec.sh \
  && ok "T12: bare ./bin/gate-check.sh, bin/status.sh, bash bin/doctor.sh, ./bin/exec.sh are allowed (shared)" \
  || bad "T12: a bare project-script call still prompts"
py_rules match "$P12/.claude/settings.json" -- "./bin/gate-check.sh $P12 3" "bin/exec.sh --patch x.mdl" \
  && ok "T12: the same scripts with arguments are allowed" || bad "T12: a script call with arguments prompts"
py_rules match "$P12/.claude/settings.local.json" -- "$TOOLKIT_ROOT/bin/doctor.sh" "bash $TOOLKIT_ROOT/bin/status.sh $P12" \
     "~/.mxcli/mxbuild/11.12.0/modeler/mx" "$MX check App.mpr" "~/.mxcli/mxbuild/11.12.0/modeler/mx check App.mpr" \
  && ok "T12: toolkit scripts by absolute path and the installed mx (both spellings) are allowed (local)" \
  || bad "T12: a toolkit-script or mx call prompts"
py_get_allow "$P12/.claude/settings.json" | grep -qF "mxbuild" \
  && bad "T12: a per-machine mxbuild rule leaked into the shared settings.json" \
  || ok "T12: mxbuild rules stay in settings.local.json"
{ py_get_allow "$P12/.claude/settings.json"; py_get_allow "$P12/.claude/settings.local.json"; } \
  | grep -E 'init-project\.sh|install-claude-permissions\.sh|install-harness-permissions\.sh|install-claude-hooks\.sh|/_[a-z]+\.sh' \
  && bad "T12: an allow rule lets the agent run an installer that records a person's decision, or a sourced library" \
  || ok "T12: init-project, the permission and hooks installers, and _*.sh libraries keep prompting (#781 review, #782)"
# #782: the decision scripts' reads run unprompted (exec-approval.sh is read before every exec);
# their writers --set/--clear prompt in every spelling, under every profile.
TK="$TOOLKIT_ROOT/bin"
py_rules runs "$P12/.claude/settings.json" "$P12/.claude/settings.local.json" -- \
     "$TK/exec-approval.sh $P12" "$TK/exec-approval.sh $P12 --explain" "bash $TK/exec-approval.sh $P12" \
     "$TK/interview-mode.sh $P12 --explain" "$TK/interview-mode.sh $P12 --remote" "bash $TK/interview-mode.sh $P12" \
     "$TK/permission-profile.sh $P12" "$TK/permission-profile.sh $P12 --explain" \
     "./bin/exec-approval.sh ." "bin/interview-mode.sh . --explain" \
  && ok "T12: exec-approval/interview-mode/permission-profile reads are allowed (#782)" \
  || bad "T12: a read-only exec-approval/interview-mode/permission-profile call prompts (#782)"
DECIDE_WRITES=()
for _s in exec-approval.sh interview-mode.sh permission-profile.sh; do
  DECIDE_WRITES+=( "$TK/$_s $P12 --set auto" "bash $TK/$_s $P12 --set full" "$TK/$_s $P12 --clear" \
                   "./bin/$_s . --set auto" "bin/$_s . --clear" "bash bin/$_s . --set unattended" )
done
py_rules asks "$P12/.claude/settings.json" "$P12/.claude/settings.local.json" -- "${DECIDE_WRITES[@]}" \
  && ok "T12: every --set/--clear of the three decision scripts hits an ask rule (#782)" \
  || bad "T12: a --set/--clear of a decision script is not behind an ask rule (#782)"
PF="$WORK/p782full"; mkdir -p "$PF"
"$SUBJECT" "$PF" --profile full >/dev/null 2>&1
py_get_allow "$PF/.claude/settings.local.json" | grep -qxF 'Bash' \
  && py_rules asks "$PF/.claude/settings.json" -- "${DECIDE_WRITES[@]}" \
  && ok "T12: under the full profile (bare Bash allowed) --set/--clear still ask (#782)" \
  || bad "T12: under the full profile an ask rule is missing (#782)"
"$SUBJECT" "$P12" --hooks-only --check >"$WORK/t12-hooks.out" 2>&1
grep -q "the next install removes" "$WORK/t12-hooks.out" \
  && bad "T12: --hooks-only --check lists allow entries as stale (it never prunes)" \
  || ok "T12: --hooks-only --check lists no stale allow entries"
py_rules match "$P12/.claude/settings.json" -- ./bin/gate-check.shx >/dev/null \
  && bad "T12: a rule matches a different program (./bin/gate-check.shx)" \
  || ok "T12: rules end at the script name (./bin/gate-check.shx is not allowed)"

# Migration: a project installed by the pre-#780 script (entries and sidecars copied from its
# output on master c3c8a303), plus entries someone else wrote. Re-install removes only ours.
M12="$WORK/m780"; mkdir -p "$M12/bin" "$M12/.claude"; : > "$M12/bin/gate-check.sh"
cat > "$M12/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(npm test *)",
      "Bash(./bin/exec.sh:*)",
      "Bash(bin/exec.sh:*)",
      "Bash(bash bin/exec.sh:*)",
      "Bash(./bin/*.sh:*)",
      "Bash(bin/*.sh:*)",
      "Bash(bash bin/*.sh:*)",
      "Bash(~/.mxcli/mxbuild/*/modeler/mx:*)",
      "Bash(./mxcli:*)",
      "Bash(mxcli:*)"
    ]
  }
}
JSON
cat > "$M12/.claude/.mxtk-permissions-added.json" <<'JSON'
{"allow": ["Bash(./bin/*.sh:*)", "Bash(./bin/exec.sh:*)", "Bash(./mxcli:*)", "Bash(bash bin/*.sh:*)", "Bash(bash bin/exec.sh:*)", "Bash(bin/*.sh:*)", "Bash(bin/exec.sh:*)", "Bash(mxcli:*)", "Bash(~/.mxcli/mxbuild/*/modeler/mx:*)"], "deny": [], "hook": false}
JSON
printf '{"permissions": {"allow": ["Bash(make *)", "Bash(%s/bin/*.sh:*)", "Bash(bash %s/bin/*.sh:*)"]}}\n' "$TOOLKIT_ROOT" "$TOOLKIT_ROOT" > "$M12/.claude/settings.local.json"
printf '{"allow": ["Bash(%s/bin/*.sh:*)", "Bash(bash %s/bin/*.sh:*)"], "deny": []}\n' "$TOOLKIT_ROOT" "$TOOLKIT_ROOT" > "$M12/.claude/.mxtk-permissions-added-local.json"
"$SUBJECT" "$M12" --profile wrappers --check >"$WORK/t12c.out" 2>&1
grep -qxF '  - Bash(./bin/*.sh:*)' "$WORK/t12c.out" && grep -qxF "  - Bash($TOOLKIT_ROOT/bin/*.sh:*)" "$WORK/t12c.out" \
  && ok "T12: --check names the old wildcard entries the next install removes" \
  || bad "T12: --check does not name the old wildcard entries"
"$SUBJECT" "$M12" --profile wrappers >"$WORK/t12m.out" 2>&1
LEFT="$( { py_get_allow "$M12/.claude/settings.json"; py_get_allow "$M12/.claude/settings.local.json"; } | grep -F '*.sh:*' ; py_get_allow "$M12/.claude/settings.json" | grep -F 'mxbuild/*/' )"
[ -z "$LEFT" ] && ok "T12: re-install removes the old wildcard entries it added (both files)" \
               || bad "T12: old wildcard entries survived re-install: $(echo $LEFT)"
py_get_allow "$M12/.claude/settings.json" | grep -qxF 'Bash(npm test *)' && py_get_allow "$M12/.claude/settings.local.json" | grep -qxF 'Bash(make *)' \
  && ok "T12: entries someone else wrote survive the migration" || bad "T12: a foreign entry was removed"
py_rules match "$M12/.claude/settings.json" -- ./bin/gate-check.sh && py_rules shape "$M12/.claude/settings.json" "$M12/.claude/settings.local.json" \
  && ok "T12: after migration a bare ./bin/gate-check.sh is allowed and no rule warns" \
  || bad "T12: after migration a bare call prompts or a rule still warns"

# #782 migration: a project installed by #781 (master 1e0c38a0) has an allow rule for
# install-claude-hooks.sh, recorded in the local sidecar, and no decision ask rules. Re-install
# removes the hooks rule it added, keeps an identical-looking foreign one in a second project,
# and adds the ask rules; --check names the stale rule and reports the ask rules missing.
M2="$WORK/m782"; mkdir -p "$M2/.claude"
HK="Bash($TOOLKIT_ROOT/bin/install-claude-hooks.sh *)"; HKB="Bash(bash $TOOLKIT_ROOT/bin/install-claude-hooks.sh *)"
printf '{"permissions": {"allow": ["Bash(make *)", "%s", "%s"]}}\n' "$HK" "$HKB" > "$M2/.claude/settings.local.json"
printf '{"allow": ["%s", "%s"], "deny": []}\n' "$HK" "$HKB" > "$M2/.claude/.mxtk-permissions-added-local.json"
"$SUBJECT" "$M2" --profile wrappers --check >"$WORK/t782c.out" 2>&1; rc782=$?
[ "$rc782" -ne 0 ] && grep -qxF "  - $HK" "$WORK/t782c.out" && grep -qxF '  Bash(*exec-approval.sh*--set*)' "$WORK/t782c.out" \
  && ok "T12: --check on a #781 install names the stale hooks rule and the missing ask rules (#782)" \
  || bad "T12: --check on a #781 install does not name the stale hooks rule / missing ask rules (#782)"
"$SUBJECT" "$M2" --profile wrappers >"$WORK/t782m.out" 2>&1
py_get_allow "$M2/.claude/settings.local.json" | grep -qF 'install-claude-hooks.sh' \
  && bad "T12: re-install left the install-claude-hooks.sh allow rule it added (#782)" \
  || ok "T12: re-install removes the install-claude-hooks.sh allow rule it added (#782)"
py_get_allow "$M2/.claude/settings.local.json" | grep -qxF 'Bash(make *)' \
  && py_rules asks "$M2/.claude/settings.json" -- "$TK/exec-approval.sh $M2 --set auto" >/dev/null \
  && ok "T12: after the #782 migration foreign entries survive and --set asks" \
  || bad "T12: after the #782 migration a foreign entry is gone or --set does not ask"
F2="$WORK/f782"; mkdir -p "$F2/.claude"
printf '{"permissions": {"allow": ["%s"]}}\n' "$HK" > "$F2/.claude/settings.local.json"
"$SUBJECT" "$F2" --profile wrappers >/dev/null 2>&1
py_get_allow "$F2/.claude/settings.local.json" | grep -qxF "$HK" \
  && ok "T12: a hooks-installer rule someone else wrote (no sidecar record) is left alone (#782)" \
  || bad "T12: a foreign hooks-installer rule was removed (#782)"

# ══════════════════════════════════════════════════════════════════════════════════════════
# install-harness-permissions.sh — Copilot and Aider (Claude delegated, spot-checked only)
# ══════════════════════════════════════════════════════════════════════════════════════════
if [ -x "$HARNESS_SUBJECT" ]; then

  py_get_autoapprove() {  # $1 = .vscode/settings.json path -> prints "key\tvalue" per entry
    "$PY" - "$1" <<'PY'
import json, sys, os
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit(0)
d = json.load(open(p))
for k, v in d.get("chat.tools.terminal.autoApprove", {}).items():
    print("%s\t%s" % (k, json.dumps(v)))
PY
  }

  # ── T6: fresh scratch project — actually run the harness installer, assert on real output ──
  HP="$WORK/harnessproj"; mkdir -p "$HP"
  "$HARNESS_SUBJECT" "$HP" >"$WORK/t6.out" 2>&1
  RC=$?
  [ "$RC" -eq 0 ] && ok "T6: install-harness-permissions.sh fresh install exits 0" \
                   || bad "T6: fresh install exited $RC"

  # Claude side delegated correctly (spot check, not the full T1-T5 above).
  _check_present "T6" "$HP/.claude/settings.json" "${EXPECTED_SHARED[@]}"

  # Copilot: chat.tools.terminal.autoApprove exists, wrapper commands are auto-approved (true),
  # and the absolute-path entries are NOT mirrored here (see script header for why).
  [ -f "$HP/.vscode/settings.json" ] && ok "T6: Copilot .vscode/settings.json was created" \
                                       || bad "T6: Copilot .vscode/settings.json was not created"
  AA="$(py_get_autoapprove "$HP/.vscode/settings.json")"
  printf '%s\n' "$AA" | grep -qxF "$(printf './mxcli\ttrue')" \
    && ok "T6: Copilot autoApprove has ./mxcli: true" \
    || bad "T6: Copilot autoApprove missing ./mxcli: true"
  printf '%s\n' "$AA" | grep -qxF "$(printf 'bin/exec.sh\ttrue')" \
    && ok "T6: Copilot autoApprove has bin/exec.sh: true" \
    || bad "T6: Copilot autoApprove missing bin/exec.sh: true"
  printf '%s\n' "$AA" | grep -q "$TOOLKIT_ROOT" \
    && bad "T6: Copilot .vscode/settings.json leaked the absolute toolkit-root path" \
    || ok "T6: Copilot .vscode/settings.json carries no absolute toolkit-root path"

  # Aider: file did not exist -> created with yes-always: true.
  [ -f "$HP/.aider.conf.yml" ] && ok "T6: .aider.conf.yml was created" \
                                 || bad "T6: .aider.conf.yml was not created"
  grep -qE '^yes-always:[[:space:]]*true[[:space:]]*$' "$HP/.aider.conf.yml" \
    && ok "T6: .aider.conf.yml has yes-always: true" \
    || bad "T6: .aider.conf.yml missing yes-always: true"

  # Cursor/Windsurf: no project file written.
  [ -e "$HP/.cursorrules" ] && bad "T6: .cursorrules was written (should be user-level only)" \
                             || ok "T6: no .cursorrules written for Cursor"
  [ -e "$HP/.windsurfrules" ] && bad "T6: .windsurfrules was written (should be user-level only)" \
                               || ok "T6: no .windsurfrules written for Windsurf"

  # ── T7: idempotent re-run — all three files byte-identical ─────────────────────────────────
  S1C="$(cat "$HP/.claude/settings.json")"; S1V="$(cat "$HP/.vscode/settings.json")"; S1A="$(cat "$HP/.aider.conf.yml")"
  "$HARNESS_SUBJECT" "$HP" >"$WORK/t7.out" 2>&1
  S2C="$(cat "$HP/.claude/settings.json")"; S2V="$(cat "$HP/.vscode/settings.json")"; S2A="$(cat "$HP/.aider.conf.yml")"
  [ "$S1C" = "$S2C" ] && ok "T7: re-run leaves Claude settings.json byte-identical" \
                       || bad "T7: re-run changed Claude settings.json"
  [ "$S1V" = "$S2V" ] && ok "T7: re-run leaves Copilot settings.json byte-identical" \
                       || bad "T7: re-run changed Copilot settings.json"
  [ "$S1A" = "$S2A" ] && ok "T7: re-run leaves .aider.conf.yml byte-identical" \
                       || bad "T7: re-run changed .aider.conf.yml"

  # ── T8: Aider — file already exists with unrelated content and no key -> key added, content kept ──
  AP="$WORK/aiderproj"; mkdir -p "$AP"
  printf '# aider config\nmodel: gpt-4\n' > "$AP/.aider.conf.yml"
  "$HARNESS_SUBJECT" "$AP" >"$WORK/t8.out" 2>&1
  grep -qE '^yes-always:[[:space:]]*true[[:space:]]*$' "$AP/.aider.conf.yml" \
    && ok "T8: yes-always: true added to an existing .aider.conf.yml" \
    || bad "T8: yes-always: true was not added to an existing .aider.conf.yml"
  grep -qxF 'model: gpt-4' "$AP/.aider.conf.yml" \
    && ok "T8: pre-existing .aider.conf.yml content (model: gpt-4) preserved" \
    || bad "T8: pre-existing .aider.conf.yml content was disturbed"

  # ── T9: Aider — key already present under different spacing -> no duplicate ────────────────
  AP2="$WORK/aiderproj2"; mkdir -p "$AP2"
  printf 'yes-always:   true\nmodel: gpt-4\n' > "$AP2/.aider.conf.yml"
  "$HARNESS_SUBJECT" "$AP2" >"$WORK/t9.out" 2>&1
  N="$(grep -cE '^[[:space:]]*yes-always[[:space:]]*:' "$AP2/.aider.conf.yml")"
  [ "$N" -eq 1 ] && ok "T9: yes-always: already present under different spacing -> not duplicated" \
                  || bad "T9: yes-always: appears $N times (want 1) when already present"

  # ── T10: --check reports missing across Claude + Copilot + Aider, writes nothing ───────────
  CHK="$WORK/checkproj"; mkdir -p "$CHK"
  "$HARNESS_SUBJECT" "$CHK" --check >"$WORK/t10.out" 2>&1
  RC=$?
  [ "$RC" -ne 0 ] && ok "T10: --check on an untouched project exits non-zero" \
                   || bad "T10: --check exited 0 on an untouched project"
  [ -e "$CHK/.claude/settings.json" ] && bad "T10: --check wrote .claude/settings.json" \
                                       || ok "T10: --check wrote no .claude/settings.json"
  [ -e "$CHK/.vscode/settings.json" ] && bad "T10: --check wrote .vscode/settings.json" \
                                       || ok "T10: --check wrote no .vscode/settings.json"
  [ -e "$CHK/.aider.conf.yml" ] && bad "T10: --check wrote .aider.conf.yml" \
                                 || ok "T10: --check wrote no .aider.conf.yml"

  # ── T11: --uninstall removes what this script added (Copilot + Aider), leaves rest ─────────
  "$HARNESS_SUBJECT" "$HP" --uninstall >"$WORK/t11.out" 2>&1
  AA_AFTER="$(py_get_autoapprove "$HP/.vscode/settings.json")"
  [ -z "$AA_AFTER" ] && ok "T11: Copilot autoApprove entries removed by --uninstall" \
                      || bad "T11: Copilot autoApprove entries survived --uninstall: $AA_AFTER"
  grep -qE '^[[:space:]]*yes-always[[:space:]]*:' "$HP/.aider.conf.yml" 2>/dev/null \
    && bad "T11: yes-always: true survived --uninstall" \
    || ok "T11: yes-always: true removed by --uninstall"

  "$HARNESS_SUBJECT" "$AP" --uninstall >"$WORK/t11b.out" 2>&1
  grep -qxF 'model: gpt-4' "$AP/.aider.conf.yml" \
    && ok "T11: --uninstall on Aider kept pre-existing content (model: gpt-4)" \
    || bad "T11: --uninstall on Aider disturbed pre-existing content"
else
  bad "install-harness-permissions.sh not found/executable at $HARNESS_SUBJECT — cannot run T6-T11"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
