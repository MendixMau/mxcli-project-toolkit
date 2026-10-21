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
# PROFILES (2026-10-06): bin/permission-profile.sh resolves `wrappers` | `project` (default) |
# `full`, picked at intake Q12. `wrappers` is exactly the list below. `project` adds edits inside
# the project folder (`Edit(/**)` — `/` anchors at the project, per the permissions doc's path
# table) and the everyday project commands, plus `ask` rules so destructive git and sudo still
# prompt in every mode. `full` adds bare `Bash`/`Edit`/`Read`/`WebFetch`/`WebSearch` — ONLY to the
# per-machine settings.local.json, so one person's opt-in is never committed for a whole team.
# Deny and ask rules beat allow rules in every mode, `full` included. This script never removes
# an entry it did not add (the sidecar below is the record); switching to a smaller profile
# removes the entries THIS script added for the bigger one.
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
# THE SECOND HOOK (2026-10-02): `bin/look-ledger.sh seen`, run from $CLAUDE_PROJECT_DIR (#446,
# see LOOK_HOOK below), on PostToolUse, matcher `Read`. Two unattended builds built every page and never opened a screenshot of one; nothing
# could tell, because the only record of a LOOK was a report nobody had to write. This hook
# writes one ledger row per image the agent actually opens, and gate-check.sh's Stage 5 check
# joins it against the pages bin/exec.sh built. It ignores every non-image Read, never blocks,
# and exits 0 even when look-ledger.sh is not installed yet (it logs that once).
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
# NOT WRITTEN, ON PURPOSE: `autoMode` (2026-09-27). In auto permission mode a second gate, the
# safety classifier, runs after these rules and can refuse a command they allow (field: a Python
# BSON patch of a git-tracked, snapshotted .mpr refused as "Irreversible Local Destruction").
# `autoMode.environment` is the documented way to give it trusted context, so this script was
# going to merge some. It cannot, from here. https://code.claude.com/docs/en/auto-mode-config
# ("Where the classifier reads configuration", fetched 2026-09-27): the classifier reads
# `autoMode` only from ~/.claude/settings.json, managed settings and the --settings flag / Agent
# SDK, and "doesn't read `autoMode` from project settings in `.claude/settings.json` or
# `.claude/settings.local.json`", because a checked-in repo or a build step could otherwise
# inject its own allow rules. https://code.claude.com/docs/en/settings-reference (`autoMode`,
# same date) agrees: Scope "User or managed". Writing it here would be inert, and writing the
# operator's user-wide ~/.claude/settings.json from a per-project installer is not this script's
# business. The per-user route is Claude Code's own `/auto-mode-setup`, which writes that file
# after the user accepts. The project-level route that works is the command's shape: a model
# patch goes through `./bin/exec.sh --patch <script>`, which the allow rules above already cover
# and which snapshots, gates and restores. See skills/agent-permission-friction.md.
#
# Usage:
#   bin/install-claude-permissions.sh <project-root>              # merge, write, back up first
#   bin/install-claude-permissions.sh <project-root> --check       # report only; exits 1 if any
#                                                                   # entry is missing; writes nothing
#   bin/install-claude-permissions.sh <project-root> --uninstall   # remove only entries this
#                                                                   # script added; back up first
#   bin/install-claude-permissions.sh <project-root> --hooks-only [--check]
#                                                                   # only the two hooks: no allow,
#                                                                   # deny or ask key created, nothing
#                                                                   # pruned, no .bak, a hand-formatted
#                                                                   # file is not rewritten (exit 3,
#                                                                   # the lines are printed instead)
#   bin/install-claude-permissions.sh <project-root> --consent-check
#                                                                   # exit 0 if this project installed
#                                                                   # the profile before (sidecar with a
#                                                                   # non-empty allow, or
#                                                                   # .mxtk/permission-profile); sync
#                                                                   # repairs hooks only when it is 0
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

USAGE="Usage: $0 <project-root> [--check|--uninstall|--hooks-only] [--profile wrappers|project|full]"

MODE="install"
PROJECT_DIR=""
PROFILE_ARG=""
HOOKS_ONLY=0
CONSENT_CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --uninstall) MODE="uninstall" ;;
    --hooks-only) HOOKS_ONLY=1 ;;
    --consent-check) CONSENT_CHECK=1 ;;
    --profile)   PROFILE_ARG="${2:-}"; shift ;;
    --profile=*) PROFILE_ARG="${1#--profile=}" ;;
    -h|--help)   echo "$USAGE"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; echo "$USAGE" >&2; exit 2 ;;
    *)  PROJECT_DIR="$1" ;;
  esac
  shift
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

# --profile on an install persists (per machine, .mxtk/), so a later sync --check agrees with it.
if [ -n "$PROFILE_ARG" ] && [ "$MODE" = install ]; then
  "$SCRIPT_DIR/permission-profile.sh" "$PROJECT_DIR" --set "$PROFILE_ARG" || exit 2
fi
if [ -n "$PROFILE_ARG" ] && [ "$MODE" != install ]; then
  PROFILE="$(MXTK_PERMISSION_PROFILE="$PROFILE_ARG" "$SCRIPT_DIR/permission-profile.sh" "$PROJECT_DIR")"
else
  PROFILE="$("$SCRIPT_DIR/permission-profile.sh" "$PROJECT_DIR")"
fi
echo "permission profile: $PROFILE"

# The `wrappers` allow-list. Broader rules belong to the profiles below, never here — see this
# repo's CLAUDE.md "Shipping an instrument" rules.
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
# deny entries and the python side treats an empty hook list as "nothing to check/add").
DENY=(
  "Bash(./mxcli exec:*)"
  "Bash(mxcli exec:*)"
  "Bash(./mxcli.exe exec:*)"
  "Bash(*file-bugs.sh*--file*)"
  "Bash(*file-bugs.sh*--all*)"
  "Bash(*file-bugs.py*--file*)"
  "Bash(*file-bugs.py*--all*)"
)
ASK=()

# `project` profile: relative, committable, shared. mkdir/cp/mv/rm are not here — a Bash rule
# cannot be scoped to a folder; in Manual mode they prompt, in acceptEdits/auto mode Claude Code
# already allows them inside the project.
if [ "$PROFILE" = project ] || [ "$PROFILE" = full ]; then
  ENTRIES_SHARED+=(
    "Edit(/**)"
    "Bash(node tests/*)"
    "Bash(npx playwright *)"
    "Bash(npm install:*)"
    "Bash(npm ci:*)"
    "Bash(docker compose:*)"
    "Bash(docker ps:*)"
    "Bash(docker logs:*)"
    "Bash(git add:*)"
    "Bash(git commit:*)"
    "Bash(git mv:*)"
    "Bash(python3 bin/*)"  # portability-ok: a permission-rule string, not an interpreter call
    "Bash(python3 tests/*)"  # portability-ok: a permission-rule string, not an interpreter call
  )
  # Prompt even in auto/bypass mode and even under `full`: hard to undo, or outside the project.
  ASK=(
    "Bash(git push*--force*)"
    "Bash(git push* -f*)"
    "Bash(git reset --hard*)"
    "Bash(git clean *)"
    "Bash(sudo *)"
  )
fi
# `full` profile: one person's opt-in — per-machine settings.local.json only.
if [ "$PROFILE" = full ]; then
  ENTRIES_LOCAL+=( "Bash" "Edit" "Read" "WebFetch" "WebSearch" )
fi

SESSION_HOOK="bash bin/session-check.sh || true"
# The look hook runs from the project root, not from the cwd of whoever did the Read (#446). The
# old form, `bash bin/look-ledger.sh seen || true`, exited 127 from any other cwd (a subagent in
# a private copy, a shell in app/javasource) and `|| true` hid it: 30 pages owed, 1 seen.
# Claude Code sets $CLAUDE_PROJECT_DIR for every hook; PROJECT_ROOT is $PWD after the cd, so a
# Windows-form value reaches look-ledger.sh as Git Bash spells it. A missing script or a failed
# run is logged ONCE per distinct message to .claude/loop/look/hook.log and printed to stderr.
LOOK_HOOK='d="${CLAUDE_PROJECT_DIR:-$PWD}"; l="$d/.claude/loop/look/hook.log"; w() { grep -qsF "$1" "$l" && return 0; if [ -d "$d/.claude" ] && mkdir -p "${l%/*}" && printf "%s\t%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$l"; then echo "look hook: $1 (logged once to $l)" >&2; else echo "look hook: $1" >&2; fi; }; if [ -f "$d/bin/look-ledger.sh" ]; then (cd "$d" && PROJECT_ROOT="$PWD" bash bin/look-ledger.sh seen) || w "bin/look-ledger.sh seen failed (exit $?)"; else w "no bin/look-ledger.sh under $d"; fi; exit 0'
LOOK_HOOK_OLD="bash bin/look-ledger.sh seen || true"
# event <TAB> matcher ("" = none) <TAB> command [<TAB> older form this replaces in place], one per line.
HOOKS="SessionStart		$SESSION_HOOK
PostToolUse	Read	$LOOK_HOOK	$LOOK_HOOK_OLD"

require_py

# One process, one JSON file, one entry group — called twice (shared, local) so a single
# implementation stays correct for both instead of two near-identical copies. hooks is ""
# for the local call (no hook, no deny entries belong in settings.local.json).
_merge_group() {
  local settings_path="$1" sidecar_path="$2" mode="$3" hooks="$4" n_allow="$5" n_deny="$6"; shift 6
  "$PY" - "$settings_path" "$sidecar_path" "$mode" "$hooks" "$n_allow" "$n_deny" "$@" <<'PY'
import json, os, shutil, sys

settings_path, sidecar_path, mode, hooks_arg, n_allow, n_deny, *rest = sys.argv[1:]
n_allow, n_deny = int(n_allow), int(n_deny)
entries, deny_entries, ask_entries = rest[:n_allow], rest[n_allow:n_allow + n_deny], rest[n_allow + n_deny:]
# (event, matcher, command) per line; matcher "" means the group carries no matcher.
hook_specs, legacy = [], {}
for l in hooks_arg.splitlines():
    if l.strip():
        f = l.split("\t", 3)
        hook_specs.append(tuple(f[:3]))
        if len(f) > 3 and f[3]:
            legacy[f[2]] = f[3]


def hook_present(d, spec):
    ev, matcher, cmd = spec
    for grp in d.get("hooks", {}).get(ev, []) or []:
        if (grp.get("matcher") or "") != matcher:
            continue
        for h in grp.get("hooks", []) or []:
            if h.get("command") == cmd:
                return True
    return False


def extra_copies(d, spec):
    """Look hooks beyond the one wanted: the older form, or a second copy of the current one."""
    ev, matcher, cmd = spec
    old = legacy.get(cmd)
    if not old:
        return 0
    hs = [h for grp in d.get("hooks", {}).get(ev, []) or [] if (grp.get("matcher") or "") == matcher
          for h in grp.get("hooks", []) or [] if h.get("command") in (cmd, old)]
    return max(len(hs) - 1, 0) if any(h.get("command") == cmd for h in hs) else 0


def hook_label(spec):
    ev, matcher, cmd = spec
    return "hooks.%s%s: %s" % (ev, "[%s]" % matcher if matcher else "", cmd)


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def detect_indent(text):
    for line in text.splitlines():
        if line[:1] in (" ", "\t") and line.strip().startswith('"'):
            return line[:len(line) - len(line.lstrip())]
    return "  "


# Sidecar: a plain list (pre-2026-09-17: allow strings only), {"allow", "deny", "hook": bool}
# (pre-2026-10-02: "hook" = the SessionStart hook), or that plus "hooks": [command, ...] naming
# every hook this script added. All three are read; the newest form is written, "hook" kept.
_side = load_json(sidecar_path, [])
if isinstance(_side, list):
    _side = {"allow": _side, "deny": [], "hook": False}
added = set(_side.get("allow", []))
added_deny = set(_side.get("deny", []))
added_ask = set(_side.get("ask", []))
added_hooks = set(_side.get("hooks", []))
if _side.get("hook") and hook_specs:
    added_hooks.add(hook_specs[0][2])  # the SessionStart hook, the only one before 2026-10-02

if mode == "check":
    d = load_json(settings_path, {})
    allow = d.get("permissions", {}).get("allow", [])
    deny = d.get("permissions", {}).get("deny", [])
    missing = [e for e in entries if e not in allow]
    missing_deny = [e for e in deny_entries if e not in deny]
    missing_ask = [e for e in ask_entries if e not in d.get("permissions", {}).get("ask", [])]
    missing_hooks = [h for h in hook_specs if not hook_present(d, h) or extra_copies(d, h)]
    if missing or missing_deny or missing_ask or missing_hooks:
        print("Missing entries in %s:" % settings_path)
        for m in missing:
            print("  " + m)
        if missing_deny:
            print("Missing deny entries (permissions.deny):")
            for m in missing_deny:
                print("  " + m)
        if missing_ask:
            print("Missing ask entries (permissions.ask):")
            for m in missing_ask:
                print("  " + m)
        for h in missing_hooks:
            print("  " + hook_label(h))
        sys.exit(1)
    if hook_specs:
        print("All %d allow, %d deny, %d ask entries and %d hook(s) present in %s" % (len(entries), len(deny_entries), len(ask_entries), len(hook_specs), settings_path))
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
    removed += [e for e in perms.get("ask", []) if e in added_ask]
    if "permissions" in d:
        d["permissions"]["allow"] = kept
        if "deny" in d["permissions"]:
            d["permissions"]["deny"] = kept_deny
        if "ask" in d["permissions"]:
            d["permissions"]["ask"] = [e for e in perms["ask"] if e not in added_ask]
    for spec in hook_specs:
        ev, _m, cmd = spec
        mine = {c for c in (cmd, legacy.get(cmd)) if c and c in added_hooks}
        if not mine or "hooks" not in d or ev not in d["hooks"]:
            continue
        groups = d["hooks"].get(ev, []) or []
        for grp in groups:
            grp["hooks"] = [h for h in grp.get("hooks", []) if h.get("command") not in mine]
        d["hooks"][ev] = [g for g in groups if g.get("hooks")]
        if not d["hooks"][ev]:
            del d["hooks"][ev]
        removed.append(hook_label(spec))
    write_json(settings_path, d)
    if os.path.exists(sidecar_path):
        os.remove(sidecar_path)
    print("Removed %d entry(ies) from %s (backup: %s)" % (
        len(removed), settings_path, settings_path + ".bak-permissions-uninstall"))
    for r in removed:
        print("  - " + r)
    sys.exit(0)

# mode == install
HOOKS_ONLY = os.environ.get("MXTK_HOOKS_ONLY") == "1"
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
orig_text = None
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as f:
        orig_text = f.read()
    # --hooks-only is a pure insertion of two hook lines, so it leaves no .bak behind (the file
    # is untouched otherwise, and a stray untracked backup is noise in a project's git status).
    if not HOOKS_ONLY:
        shutil.copy(settings_path, settings_path + ".bak-permissions-install")
    d = load_json(settings_path, {})
else:
    d = {}

if HOOKS_ONLY:
    perms = d.get("permissions") or {}   # read-only view: --hooks-only never creates permission keys
else:
    perms = d.get("permissions")
    if perms is None:
        perms = {}
        d["permissions"] = perms
allow = perms.get("allow")
if allow is None:
    allow = []
    if not HOOKS_ONLY:
        perms["allow"] = allow

# A smaller profile than last time: drop what THIS script added that the profile no longer
# wants. Entries someone else wrote are never in the sidecar, so never touched.
pruned = []
for key, want, mine in (("allow", entries, added), ("deny", deny_entries, added_deny), ("ask", ask_entries, added_ask)):
    if os.environ.get("MXTK_HOOKS_ONLY") == "1":
        break  # --hooks-only: add the hooks, never prune what an earlier full install wrote
    gone = [e for e in perms.get(key, []) if e in mine and e not in want]
    if gone:
        perms[key] = [e for e in perms[key] if e not in gone]
        pruned += ["%s %s" % (key, e) for e in gone]
    mine.difference_update(set(mine) - set(want))

newly_added = [e for e in entries if e not in allow]
for e in newly_added:
    allow.append(e)

deny = perms.get("deny")
if deny is None:
    deny = []
    if not HOOKS_ONLY:
        perms["deny"] = deny
newly_denied = [e for e in deny_entries if e not in deny]
for e in newly_denied:
    deny.append(e)

newly_asked = []
if ask_entries or "ask" in perms:
    ask = perms.setdefault("ask", [])
    newly_asked = [e for e in ask_entries if e not in ask]
    ask.extend(newly_asked)

new_hooks, replaced = [], []
for spec in hook_specs:
    if hook_present(d, spec):
        # Already current: drop any older form and any second copy beside it, so one look hook
        # runs per Read (an earlier install could leave the old form next to the new one).
        ev, matcher, cmd = spec
        if extra_copies(d, spec):
            seen = False
            groups = d["hooks"][ev]
            for grp in groups:
                if (grp.get("matcher") or "") != matcher:
                    continue
                keep = []
                for h in grp.get("hooks", []) or []:
                    c = h.get("command")
                    if c == legacy.get(cmd) or (c == cmd and seen):
                        if c != cmd:
                            replaced.append(c)
                        continue
                    seen = seen or c == cmd
                    keep.append(h)
                grp["hooks"] = keep
            d["hooks"][ev] = [g for g in groups if g.get("hooks")]
            new_hooks.append(spec)
        continue
    ev, matcher, cmd = spec
    old_cmd = legacy.get(cmd)
    # The older form of this hook, written by an earlier run: rewrite it in place, so the project
    # keeps one look hook rather than gaining a second that writes a duplicate row from the root.
    olds = [h for grp in d.get("hooks", {}).get(ev, []) or [] if (grp.get("matcher") or "") == matcher
            for h in grp.get("hooks", []) or [] if old_cmd and h.get("command") == old_cmd]
    if olds:
        for h in olds:
            h["command"] = cmd
        replaced.append(old_cmd)
    else:
        grp = {"matcher": matcher} if matcher else {}
        grp["hooks"] = [{"type": "command", "command": cmd}]
        d.setdefault("hooks", {}).setdefault(ev, []).append(grp)
    new_hooks.append(spec)

if HOOKS_ONLY and not new_hooks:
    pass  # nothing to insert: leave the file byte for byte as it is
elif HOOKS_ONLY and orig_text is not None:
    # Do not reformat a hand-edited file beyond the inserted entries. Rewrite only when the
    # file is exactly what json.dump would have produced with its own indent; otherwise leave
    # it alone and print the lines to add by hand.
    ind = detect_indent(orig_text)
    canon = json.dumps(load_json(settings_path, {}), indent=ind, ensure_ascii=False)
    if canon == orig_text.rstrip():
        tail = orig_text[len(orig_text.rstrip()):]  # keep the file's own trailing newline (or none)
        with open(settings_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(d, indent=ind, ensure_ascii=False) + tail)
    else:
        print("%s has hand-edited formatting; not rewriting it. Add these hook(s) yourself:" % settings_path)
        for h in new_hooks:
            print("  " + hook_label(h))
        sys.exit(3)
else:
    write_json(settings_path, d)

if newly_added or newly_denied or newly_asked or new_hooks or pruned:
    added.update(newly_added)
    added_deny.update(newly_denied)
    added_ask.update(newly_asked)
    added_hooks.update(h[2] for h in new_hooks)
    added_hooks.difference_update(replaced)
    side = {"allow": sorted(added), "deny": sorted(added_deny)}
    if added_ask:
        side["ask"] = sorted(added_ask)
    if hook_specs:
        side["hook"] = hook_specs[0][2] in added_hooks
        side["hooks"] = sorted(added_hooks)
    write_json(sidecar_path, side)
    print("Added %d, removed %d entry(ies) in %s" % (len(newly_added) + len(newly_denied) + len(newly_asked) + len(new_hooks), len(pruned), settings_path))
    for e in newly_added:
        print("  + allow " + e)
    for e in newly_denied:
        print("  + deny  " + e)
    for e in newly_asked:
        print("  + ask   " + e)
    for e in pruned:
        print("  - " + e)
    for h in new_hooks:
        print("  + " + hook_label(h))
    for c in replaced:
        print("  - hook (older form, replaced or removed): " + c)
else:
    print("All permission entries already present in %s -- nothing to do" % settings_path)
PY
}

RC=0
if [ "$CONSENT_CHECK" -eq 1 ]; then
  # A --hooks-only run writes a sidecar with allow: [], so file presence proves nothing; only a
  # non-empty allow list shows the full installer ran here.
  [ -f "$PROJECT_DIR/.mxtk/permission-profile" ] && exit 0
  [ -f "$SIDECAR" ] || exit 1
  "$PY" - "$SIDECAR" <<'PYC'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
allow = d if isinstance(d, list) else d.get("allow", [])
sys.exit(0 if allow else 1)
PYC
  exit $?
fi
if [ "$HOOKS_ONLY" -eq 1 ]; then
  # Hooks alone: no allow, deny or ask entries, nothing in settings.local.json, no pruning. A
  # project whose settings predate the hooks (or whose `mxcli init` rewrote the file) gets the
  # two hook lines back without its profile or its hand-edited allow-list being touched.
  export MXTK_HOOKS_ONLY=1
  _merge_group "$SETTINGS" "$SIDECAR" "$MODE" "$HOOKS" 0 0
  exit $?
fi
_merge_group "$SETTINGS" "$SIDECAR" "$MODE" "$HOOKS" "${#ENTRIES_SHARED[@]}" "${#DENY[@]}" "${ENTRIES_SHARED[@]}" "${DENY[@]}" ${ASK[@]+"${ASK[@]}"} || RC=$?
_merge_group "$SETTINGS_LOCAL" "$SIDECAR_LOCAL" "$MODE" "" "${#ENTRIES_LOCAL[@]}" 0 "${ENTRIES_LOCAL[@]}" || {
  RC2=$?
  [ "$RC2" -gt "$RC" ] && RC=$RC2
}
exit "$RC"
