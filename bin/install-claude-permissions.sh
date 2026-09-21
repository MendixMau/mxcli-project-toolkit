#!/usr/bin/env bash
# install-claude-permissions.sh — allow-list the toolkit's safe wrappers in a project's
# .claude/settings.json, so Claude Code's default (Manual) permission mode stops prompting
# for them one call at a time.
#
# WHY THIS EXISTS. `mxcli init` writes <project>/.claude/settings.json with
# `Bash(./mxcli:*)` allowed — but every skill and CLAUDE.md in this toolkit tells an agent to
# run the model through the SAFE WRAPPER instead (`bin/exec.sh` snapshots first and
# mxbuild-validates after; a bare `./mxcli exec` does neither). None of those wrapper
# invocations, none of the installed `project-bin` scripts, none of this toolkit's own
# `bin/*.sh` run by absolute path, and `mx check` under `~/.mxcli/mxbuild/*/modeler/mx` were
# ever allow-listed. So every exec through the safe wrapper raised a permission prompt — which
# defeated `bin/exec-approval.sh --set auto` (2026-09-15: the user asked for autonomy on execs
# specifically because the prompting was constant), because that knob resolves whether the
# AGENT asks; it has no say over whether the HARNESS itself prompts first.
#
# RULE SYNTAX, verified against https://code.claude.com/docs/en/permissions ("Wildcard
# patterns" section) before choosing these patterns:
#   - `*` stands in for any sequence of characters at that position, not just one path segment
#     — the doc's own example `Bash(git * main)` matches `git push origin main`, where `*`
#     spans two words. So `bin/*.sh` matches any script directly under bin/, and
#     `~/.mxcli/mxbuild/*/modeler/mx` matches any installed mxbuild version.
#   - A trailing `:*` is an exact equivalent of a trailing ` *` (space + wildcard), and — being
#     the rule's ONLY wildcard — also matches the bare command with nothing after it.
# The exec.sh-specific entries are listed separately even though `bin/*.sh:*` already covers
# them; that redundancy is deliberate and matches this script's spec, not an oversight.
#
# NOT ADDED, ON PURPOSE: `Bash(*)` or anything broader. This script only ever appends to
# `permissions.allow`, `permissions.deny` and `hooks.SessionStart` — never removes or reorders
# what is there.
#
# THE ONE DENY (2026-09-17): a bare `./mxcli exec` / `mxcli exec`. It is the single command the
# whole guard chain exists to wrap — no snapshot, no mxbuild gate, no BUILD-LOG row, no
# verification stamp — and on one field project nine scripts went in that way in one week, one carrying a
# CE0117 that only mxbuild can see. Deny beats allow in Claude Code, so the harness itself now
# refuses the bare form on every machine and every session; `./bin/exec.sh` stays allowed and
# runs the same mxcli underneath. A skill that genuinely needs the bare form runs it from a
# script (the rule matches the top-level command only).
#
# THE ONE HOOK: `bash bin/session-check.sh || true` on SessionStart — the project-local check
# that says at the top of every session whether the model on disk is verified, whether the
# mxbuild gate can run here, and whether the installed guard scripts are stale. It never blocks.
#
# MERGE PATTERN reused from bin/install-claude-hooks.sh (~line 112-206): Python via
# lib/portable.sh's require_py, a timestamped backup before any write, and a merge that keeps
# every entry already there — hand-written or `mxcli`-seeded — untouched. The one addition: a
# sidecar file records exactly which allow-list strings THIS script inserted, so --uninstall
# removes only those, never an identical entry that was already present before this script
# ever ran (e.g. `mxcli init` already seeds `Bash(./mxcli:*)` and `Bash(mxcli:*)`).
#
# TWO FILES, SPLIT BY WHAT THE ENTRY LEAKS (2026-09-16). Two of the eleven entries embed
# $TOOLKIT_ROOT — an absolute path under the operator's home directory (a username, routinely).
# `.claude/settings.json` is the SHARED project file, meant to be committed so every teammate
# gets the same allow-list; committing someone's home-directory path into it is exactly the
# per-machine leak this toolkit's leak guard exists to catch elsewhere. So those two entries
# alone go into `.claude/settings.local.json` — precedence level 3 in
# https://code.claude.com/docs/en/settings ("Settings files and precedence"), "You, this
# project", i.e. per-machine and never shared — and init-project.sh's .gitignore template
# ignores it the same way it ignores `.mxtk/`. The other nine entries are all relative (no
# machine-specific path) and stay in the shared `.claude/settings.json`, same as before.
#
# Usage:
#   bin/install-claude-permissions.sh <project-root>              # merge, write, back up first
#   bin/install-claude-permissions.sh <project-root> --check       # report only; exits 1 if any
#                                                                   # entry is missing; writes nothing
#   bin/install-claude-permissions.sh <project-root> --uninstall   # remove only entries this
#                                                                   # script added; back up first
#
# Idempotent: re-running --install after everything is already present changes nothing (both
# files are rewritten byte-for-byte the same). Called from bin/init-project.sh at scaffold time
# and from bin/sync-project.sh in --check mode (both non-fatal), via the shared entry point
# bin/install-harness-permissions.sh. Bash 3.2 + Python (resolved the same way as
# install-claude-hooks.sh) — no bash-4 constructs.
set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

USAGE="Usage: $0 <project-root> [--check|--uninstall]"

MODE="install"
PROJECT_DIR=""
for a in "$@"; do
  case "$a" in
    --check)     MODE="check" ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)   echo "$USAGE"; exit 0 ;;
    -*) echo "unknown option: $a" >&2; echo "$USAGE" >&2; exit 2 ;;
    *)  PROJECT_DIR="$a" ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  echo "$USAGE" >&2
  exit 2
fi
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 2
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

SETTINGS="$PROJECT_DIR/.claude/settings.json"
SIDECAR="$PROJECT_DIR/.claude/.mxtk-permissions-added.json"
SETTINGS_LOCAL="$PROJECT_DIR/.claude/settings.local.json"
SIDECAR_LOCAL="$PROJECT_DIR/.claude/.mxtk-permissions-added-local.json"

# The fixed allow-list. Do NOT widen this to Bash(*) or anything broader — see this repo's
# CLAUDE.md "Shipping an instrument" rules; a permission allow-list is exactly the kind of
# instrument a field-proof bar exists for.
#
# SHARED: relative invocations only, safe to commit — everyone on the project gets the same
# allow-list regardless of where they cloned the toolkit.
ENTRIES_SHARED=(
  "Bash(./bin/exec.sh:*)"
  "Bash(bin/exec.sh:*)"
  "Bash(bash bin/exec.sh:*)"
  "Bash(./bin/*.sh:*)"
  "Bash(bin/*.sh:*)"
  "Bash(bash bin/*.sh:*)"
  "Bash(~/.mxcli/mxbuild/*/modeler/mx:*)"
  "Bash(./mxcli:*)"
  "Bash(mxcli:*)"
)
# LOCAL: embeds $TOOLKIT_ROOT, an absolute path under this machine's home directory — per-machine
# only, never committed. See the header note above.
ENTRIES_LOCAL=(
  "Bash($TOOLKIT_ROOT/bin/*.sh:*)"
  "Bash(bash $TOOLKIT_ROOT/bin/*.sh:*)"
)

# THE ONE DENY and THE ONE HOOK (2026-09-17, see header notes above) are global, not
# per-machine — they carry no $TOOLKIT_ROOT path — so they are only ever merged into the
# SHARED settings.json, never into settings.local.json (the local call below passes "" / no
# deny entries and the python side treats an empty hook_cmd as "nothing to check/add").
DENY=(
  "Bash(./mxcli exec:*)"
  "Bash(mxcli exec:*)"
  "Bash(./mxcli.exe exec:*)"
)
SESSION_HOOK="bash bin/session-check.sh || true"

require_py

# One process, one JSON file, one entry group — called twice (shared, local) so a single
# implementation stays correct for both instead of two near-identical copies. hook_cmd is ""
# for the local call (no hook, no deny entries belong in settings.local.json).
_merge_group() {
  local settings_path="$1" sidecar_path="$2" mode="$3" hook_cmd="$4" n_allow="$5"; shift 5
  "$PY" - "$settings_path" "$sidecar_path" "$mode" "$hook_cmd" "$n_allow" "$@" <<'PY'
import json, os, shutil, sys

settings_path, sidecar_path, mode, hook_cmd, n_allow, *rest = sys.argv[1:]
n_allow = int(n_allow)
entries, deny_entries = rest[:n_allow], rest[n_allow:]


def hook_present(d):
    if not hook_cmd:
        return True
    for grp in d.get("hooks", {}).get("SessionStart", []) or []:
        for h in grp.get("hooks", []) or []:
            if h.get("command") == hook_cmd:
                return True
    return False


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


# Sidecar: a plain list (pre-2026-09-17: allow strings only) or {"allow": [...], "deny": [...],
# "hook": bool}. Both are read; the dict form is written.
_side = load_json(sidecar_path, [])
if isinstance(_side, list):
    _side = {"allow": _side, "deny": [], "hook": False}
added = set(_side.get("allow", []))
added_deny = set(_side.get("deny", []))
added_hook = bool(_side.get("hook", False))

if mode == "check":
    d = load_json(settings_path, {})
    allow = d.get("permissions", {}).get("allow", [])
    deny = d.get("permissions", {}).get("deny", [])
    missing = [e for e in entries if e not in allow]
    missing_deny = [e for e in deny_entries if e not in deny]
    if missing or missing_deny or not hook_present(d):
        print("Missing entries in %s:" % settings_path)
        for m in missing:
            print("  " + m)
        if missing_deny:
            print("Missing deny entries (permissions.deny):")
            for m in missing_deny:
                print("  " + m)
        if not hook_present(d):
            print("  hooks.SessionStart: " + hook_cmd)
        sys.exit(1)
    if hook_cmd:
        print("All %d allow, %d deny entries and the SessionStart hook present in %s" % (len(entries), len(deny_entries), settings_path))
    else:
        print("All %d allow entries present in %s" % (len(entries), settings_path))
    sys.exit(0)

if mode == "uninstall":
    if not os.path.exists(settings_path):
        print("No settings.json at %s -- nothing to uninstall" % settings_path)
        if os.path.exists(sidecar_path):
            os.remove(sidecar_path)
        sys.exit(0)
    shutil.copy(settings_path, settings_path + ".bak-permissions-uninstall")
    d = load_json(settings_path, {})
    perms = d.get("permissions", {})
    allow = perms.get("allow", [])
    removed = [e for e in allow if e in added]
    kept = [e for e in allow if e not in added]
    deny = perms.get("deny", [])
    removed += [e for e in deny if e in added_deny]
    kept_deny = [e for e in deny if e not in added_deny]
    if "permissions" in d:
        d["permissions"]["allow"] = kept
        if "deny" in d["permissions"]:
            d["permissions"]["deny"] = kept_deny
    if added_hook and "hooks" in d:
        groups = d["hooks"].get("SessionStart", []) or []
        for grp in groups:
            grp["hooks"] = [h for h in grp.get("hooks", []) if h.get("command") != hook_cmd]
        d["hooks"]["SessionStart"] = [g for g in groups if g.get("hooks")]
        if not d["hooks"]["SessionStart"]:
            del d["hooks"]["SessionStart"]
        removed.append("hooks.SessionStart: " + hook_cmd)
    write_json(settings_path, d)
    if os.path.exists(sidecar_path):
        os.remove(sidecar_path)
    print("Removed %d entry(ies) from %s (backup: %s)" % (
        len(removed), settings_path, settings_path + ".bak-permissions-uninstall"))
    for r in removed:
        print("  - " + r)
    sys.exit(0)

# mode == install
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".bak-permissions-install")
    d = load_json(settings_path, {})
else:
    d = {}

perms = d.get("permissions")
if perms is None:
    perms = {}
    d["permissions"] = perms
allow = perms.get("allow")
if allow is None:
    allow = []
    perms["allow"] = allow

newly_added = [e for e in entries if e not in allow]
for e in newly_added:
    allow.append(e)

deny = perms.get("deny")
if deny is None:
    deny = []
    perms["deny"] = deny
newly_denied = [e for e in deny_entries if e not in deny]
for e in newly_denied:
    deny.append(e)

new_hook = False
if not hook_present(d):
    hooks = d.setdefault("hooks", {})
    groups = hooks.setdefault("SessionStart", [])
    groups.append({"hooks": [{"type": "command", "command": hook_cmd}]})
    new_hook = True

write_json(settings_path, d)

if newly_added or newly_denied or new_hook:
    added.update(newly_added)
    added_deny.update(newly_denied)
    write_json(sidecar_path, {"allow": sorted(added), "deny": sorted(added_deny), "hook": added_hook or new_hook})
    print("Added %d entry(ies) to %s" % (len(newly_added) + len(newly_denied) + (1 if new_hook else 0), settings_path))
    for e in newly_added:
        print("  + allow " + e)
    for e in newly_denied:
        print("  + deny  " + e)
    if new_hook:
        print("  + hooks.SessionStart: " + hook_cmd)
else:
    print("All permission entries already present in %s -- nothing to do" % settings_path)
PY
}

RC=0
_merge_group "$SETTINGS" "$SIDECAR" "$MODE" "$SESSION_HOOK" "${#ENTRIES_SHARED[@]}" "${ENTRIES_SHARED[@]}" "${DENY[@]}" || RC=$?
_merge_group "$SETTINGS_LOCAL" "$SIDECAR_LOCAL" "$MODE" "" "${#ENTRIES_LOCAL[@]}" "${ENTRIES_LOCAL[@]}" || {
  RC2=$?
  [ "$RC2" -gt "$RC" ] && RC=$RC2
}
exit "$RC"
