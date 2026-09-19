#!/usr/bin/env bash
# install-harness-permissions.sh — ONE entry point that wires "stop asking me before every
# wrapper command" into every harness that has a way to say it, per-project.
#
# WHY THIS EXISTS (2026-09-16, same owner ask as bin/exec-approval.sh's default flip: "too much
# approval clicking ... not all will have Claude"). exec-approval.sh's `auto` default only
# controls whether the AGENT asks; on Claude Code the HARNESS itself still prompts on every
# ./bin/exec.sh unless bin/install-claude-permissions.sh's allow-list is in place. The same
# problem exists, with a different setting in a different file, on every other harness this
# toolkit wires (bin/wire-agents.sh's tool set: claude copilot cursor continue windsurf aider).
# This script is the one place that knows all of them, so init-project.sh and sync-project.sh
# call one thing instead of drifting five near-identical call sites.
#
# PER HARNESS:
#   claude    delegates to bin/install-claude-permissions.sh (unchanged behaviour, two files —
#             see that script's header for the settings.json / settings.local.json split).
#   copilot   merges the wrapper commands into <project>/.vscode/settings.json under
#             `chat.tools.terminal.autoApprove` — VERIFIED key name and value shape against
#             https://code.visualstudio.com/docs/agents/run/approvals (mirrored source:
#             raw.githubusercontent.com/microsoft/vscode-docs/main/docs/agents/run/approvals.md,
#             fetched 2026-09-16, since code.visualstudio.com itself was not reachable from this
#             environment) and cross-checked against microsoft/vscode-docs
#             docs/agents/reference/ai-settings.md: a plain string key is an EXACT match on the
#             command name (the executed program, not the full command line — same semantics as
#             the doc's own default-value example, which lists bare names like "rm", "curl");
#             `true` auto-approves, `false` requires approval. Only relative invocations are
#             written (`./mxcli`, `mxcli`, `./bin/exec.sh`, `bin/exec.sh`, plus a regex for any
#             other `bin/*.sh`) — the absolute-$TOOLKIT_ROOT entries Claude needs are
#             deliberately NOT mirrored here, because `.vscode/settings.json` is a normal
#             committed file in this toolkit's projects and an absolute home-directory path has
#             no business landing in it (same reasoning as the settings.local.json split above).
#   aider     ensures `yes-always: true` is present in <project>/.aider.conf.yml — Aider's own
#             documented key for "don't ask before every write/run". bin/wire-agents.sh is what
#             WRITES this file (via `mxcli init`) and stamps a comment block into it; this
#             script only adds the one YAML key, once, above that stamped block, and never
#             touches the file if the key is already there under any spacing.
#   cursor    no write. Cursor's auto-run allow-list lives in the user's own IDE settings, not
#             a project file this toolkit could commit — see .cursorrules' own pointer role.
#   windsurf  no write, same reasoning as cursor.
#
# Usage:
#   bin/install-harness-permissions.sh <project-root>              # merge, write, back up first
#   bin/install-harness-permissions.sh <project-root> --check       # report only; exits 1 if any
#                                                                    # per-harness file/key is
#                                                                    # missing; writes nothing
#   bin/install-harness-permissions.sh <project-root> --uninstall   # undo what THIS script (and
#                                                                    # install-claude-permissions.sh)
#                                                                    # added; back up first
#
# Idempotent. Bash 3.2 + Python (via lib/portable.sh, same resolver every installer here uses)
# — no bash-4 constructs. Never widens anything to a bare wildcard; see this repo's CLAUDE.md
# "Shipping an instrument" rules.
set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

RC=0

echo "=== claude ==="
if [ -x "$SCRIPT_DIR/install-claude-permissions.sh" ]; then
  "$SCRIPT_DIR/install-claude-permissions.sh" "$PROJECT_DIR" $( [ "$MODE" = install ] || echo "--$MODE" ) || {
    ec=$?; [ "$ec" -gt "$RC" ] && RC=$ec
  }
else
  echo "install-claude-permissions.sh not found/executable at $SCRIPT_DIR — skipping claude."
fi

echo "=== copilot ==="
require_py
VSCODE_SETTINGS="$PROJECT_DIR/.vscode/settings.json"
COPILOT_SIDECAR="$PROJECT_DIR/.vscode/.mxtk-autoapprove-added.json"
# Only relative, committable entries — see the header note above for why the two absolute
# $TOOLKIT_ROOT entries Claude gets are deliberately not mirrored here.
COPILOT_ENTRIES_JSON='{
  "./mxcli": true,
  "mxcli": true,
  "./bin/exec.sh": true,
  "bin/exec.sh": true,
  "/^\\.?\\/?bin\\/[^ ]+\\.sh$/": true
}'
"$PY" - "$VSCODE_SETTINGS" "$COPILOT_SIDECAR" "$MODE" "$COPILOT_ENTRIES_JSON" <<'PY' || { ec=$?; [ "$ec" -gt "$RC" ] && RC=$ec; }
import json, os, shutil, sys

settings_path, sidecar_path, mode, entries_json = sys.argv[1:]
entries = json.loads(entries_json)
KEY = "chat.tools.terminal.autoApprove"


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


added = set(load_json(sidecar_path, []))

if mode == "check":
    d = load_json(settings_path, {})
    approve = d.get(KEY, {})
    missing = [k for k, v in entries.items() if approve.get(k) != v]
    if missing:
        print("Missing/mismatched %s entries in %s:" % (KEY, settings_path))
        for m in missing:
            print("  " + m)
        sys.exit(1)
    print("All %d %s entries present in %s" % (len(entries), KEY, settings_path))
    sys.exit(0)

if mode == "uninstall":
    if not os.path.exists(settings_path):
        print("No settings.json at %s -- nothing to uninstall" % settings_path)
        if os.path.exists(sidecar_path):
            os.remove(sidecar_path)
        sys.exit(0)
    shutil.copy(settings_path, settings_path + ".bak-autoapprove-uninstall")
    d = load_json(settings_path, {})
    approve = d.get(KEY, {})
    removed = [k for k in list(approve.keys()) if k in added]
    for k in removed:
        del approve[k]
    if KEY in d:
        d[KEY] = approve
    write_json(settings_path, d)
    if os.path.exists(sidecar_path):
        os.remove(sidecar_path)
    print("Removed %d %s entry(ies) from %s (backup: %s)" % (
        len(removed), KEY, settings_path, settings_path + ".bak-autoapprove-uninstall"))
    for r in removed:
        print("  - " + r)
    sys.exit(0)

# mode == install
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".bak-autoapprove-install")
    d = load_json(settings_path, {})
else:
    d = {}

approve = d.get(KEY)
if approve is None:
    approve = {}
    d[KEY] = approve

newly_added = [k for k, v in entries.items() if approve.get(k) != v]
for k in newly_added:
    approve[k] = entries[k]

write_json(settings_path, d)

if newly_added:
    added.update(newly_added)
    write_json(sidecar_path, sorted(added))
    print("Added %d %s entry(ies) to %s" % (len(newly_added), KEY, settings_path))
    for k in newly_added:
        print("  + %s: %s" % (k, json.dumps(entries[k])))
else:
    print("All %s entries already present in %s -- nothing to do" % (KEY, settings_path))
PY

echo "=== aider ==="
AIDER_CONF="$PROJECT_DIR/.aider.conf.yml"
_aider_has_key() {
  grep -qE '^[[:space:]]*yes-always[[:space:]]*:' "$AIDER_CONF" 2>/dev/null
}
case "$MODE" in
  check)
    if [ ! -f "$AIDER_CONF" ]; then
      echo "Missing: $AIDER_CONF does not exist yet (run bin/wire-agents.sh $PROJECT_DIR first)."
      RC=1
    elif _aider_has_key; then
      echo "yes-always: already present in $AIDER_CONF"
    else
      echo "Missing: yes-always: true in $AIDER_CONF"
      RC=1
    fi
    ;;
  install)
    if [ ! -f "$AIDER_CONF" ]; then
      printf 'yes-always: true\n' > "$AIDER_CONF"
      echo "Created: $AIDER_CONF (yes-always: true)"
    elif _aider_has_key; then
      echo "yes-always: already present in $AIDER_CONF -- nothing to do"
    else
      # Prepend, never touch the wire-agents.sh stamped comment block below — same
      # never-clobber rule as everything else this toolkit writes into that file.
      TMP="$(mktemp "${TMPDIR:-/tmp}/aiderconf.XXXXXX")"
      { printf 'yes-always: true\n'; cat "$AIDER_CONF"; } > "$TMP"
      mv "$TMP" "$AIDER_CONF"
      echo "Added: yes-always: true to $AIDER_CONF"
    fi
    ;;
  uninstall)
    if [ -f "$AIDER_CONF" ] && _aider_has_key; then
      TMP="$(mktemp "${TMPDIR:-/tmp}/aiderconf.XXXXXX")"
      grep -vE '^[[:space:]]*yes-always[[:space:]]*:[[:space:]]*true[[:space:]]*$' "$AIDER_CONF" > "$TMP" || true
      mv "$TMP" "$AIDER_CONF"
      echo "Removed: yes-always: true from $AIDER_CONF"
    else
      echo "yes-always: not present in $AIDER_CONF -- nothing to remove"
    fi
    ;;
esac

echo "=== cursor / windsurf ==="
echo "No project file written — Cursor and Windsurf's auto-run allow-lists are user-level IDE"
echo "settings, not something a project checkout can carry. Flip it once per machine in the IDE."

exit "$RC"
