#!/usr/bin/env bash
# install-claude-hooks.sh — install the context-cost hooks into ~/.claude.
#
# READ THIS BEFORE RUNNING IT. These hooks are USER-GLOBAL: they fire in every
# repo and every concurrent Claude Code session on the machine, including
# projects that have nothing to do with Mendix. That is a far larger blast radius
# than anything else this toolkit installs. A bad skill wastes tokens; a bad
# global hook blocks work everywhere.
#
# Why any of this exists — see README.md "Context cost". Short version: a 1M
# context window removed the cost governor that a 200k window was providing for
# free. On one measured project, 89% of cache-read spend came from context above
# 200k — territory that was structurally impossible on the older model.
#
#   bin/install-claude-hooks.sh --basic     # tier 1: safe for anyone
#   bin/install-claude-hooks.sh --full      # tier 1 + 2: advisory nudges
#   bin/install-claude-hooks.sh --full --ceiling
#                                           # + tier 3: BLOCKS tool calls. Read the tier table.
#   bin/install-claude-hooks.sh --dry-run --full
#   bin/install-claude-hooks.sh --uninstall
#
# Not sure? Run it with no arguments. It prints the tier table and installs nothing.
set -euo pipefail

# Portability: resolve a real Python 3 by EXECUTING candidates, not by looking one up on PATH.
# On Windows `python3` is usually the Microsoft Store alias stub, which `command -v` finds and
# which then opens the Store instead of running. See bin/lib/portable.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$TOOLKIT_ROOT/claude-hooks"
DEST="$HOME/.claude"
CLAUDE_BIN="$DEST/bin"
UNINSTALL="$TOOLKIT_ROOT/bin/install-claude-hooks.sh --uninstall"

basic=0; full=0; ceiling=0; dryrun=0; uninstall=0
for a in "$@"; do
  case "$a" in
    --basic)     basic=1 ;;
    --full)      full=1 ;;
    --ceiling)   ceiling=1 ;;
    --dry-run|-n) dryrun=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help)   basic=0; full=0; break ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

tiers() {
cat <<'EOF'
Context-cost hooks — three tiers, because the blast radius differs.

TIER 1  --basic        Safe for anyone, including a day-one user. Non-blocking,
                       nothing to understand, pure win.
  shrink-image-read    Downscales screenshots before they enter the context.
                       Invisible; no failure mode.
  checkpoint.sh        Not hooks — two scripts installed to ~/.claude/bin.
  close-task.sh        They make a /clear cheap instead of costing 100k tokens
                       of re-orientation on the next session.

TIER 2  --full         Changes your working rhythm. Useful after a bad bill;
                       noise before one.
  context-watch        Tells you (and the model) what the session now costs per
                       tool call, once per threshold. Advisory only.
  work-boundary        Notices when a write is owed and says so at the next
                       natural stopping point.
  precompact-guard     Warns once before a compaction discards unfiled work.
  interview-gate       BLOCKS the end of a turn while questions the pipeline
                       generated have never been put to you, and writes
                       docs/open-questions.html for you to review. Only fires on
                       projects that actually have BRDs; never blocks the same
                       question set twice, so it cannot trap a session.

TIER 3  --ceiling      A DELIBERATE, INFORMED CHOICE. Not on by default, ever.
  context-ceiling      BLOCKS tool calls above a context limit. The session goes
                       write-only: Read/Grep/WebFetch/Agent and most Bash are
                       refused; Write/Edit/checkpoint/git stay open, so the way
                       out is open by construction.

                       Do not install this for someone else. Install it after
                       you have seen your own numbers. Someone new to the tool
                       reads "Context ceiling reached", concludes it is broken,
                       and stops using the toolkit.

Every hook has an env-var escape that needs no reinstall:
  CLAUDE_CTX_WATCH=0  CLAUDE_CTX_CEILING=0  CLAUDE_PRECOMPACT_GUARD=0
  CLAUDE_WORK_BOUNDARY=0  CLAUDE_INTERVIEW_GATE=0

What a beginner needs is visibility, not enforcement: --basic, then --full once
context cost has actually bitten.
EOF
}

if [ "$uninstall" = 0 ] && [ "$basic" = 0 ] && [ "$full" = 0 ]; then
  tiers
  echo
  echo "Nothing installed. Re-run with --basic or --full (add --ceiling only deliberately)."
  exit 0
fi

# file : event : matcher ("" = every tool) : tier
ALL=(
  "shrink-image-read.sh:PreToolUse:Read:1"
  "context-watch.sh:PostToolUse::2"
  "work-boundary.sh:PostToolUse:Bash:2"
  "interview-gate.sh:Stop::2"
  "precompact-guard.sh:PreCompact::2"
  "context-ceiling.sh:PreToolUse::3"
)

# Both the install and the uninstall path rewrite settings.json through Python.
require_py

if [ "$uninstall" = 1 ]; then
  for entry in "${ALL[@]}"; do rm -f "$DEST/hooks/${entry%%:*}"; done
  rm -f "$CLAUDE_BIN/checkpoint.sh" "$CLAUDE_BIN/close-task.sh"
  "$PY" - "$DEST/settings.json" "${ALL[@]}" <<'PY'
import json, os, shutil, sys
p, *reg = sys.argv[1:]
if not os.path.exists(p):
    sys.exit(0)
shutil.copy(p, p + ".bak-hooks-uninstall")
d = json.load(open(p))
hooks = d.get("hooks", {})
# Only OUR hook files, by basename. Hooks the user added by hand are left alone.
mine = {e.split(":")[0] for e in reg}
for event in list(hooks):
    hooks[event] = [b for b in hooks[event]
                    if not any(os.path.basename(h.get("command", "")) in mine
                               for h in b.get("hooks", []))]
    if not hooks[event]:
        del hooks[event]
if not hooks:
    d.pop("hooks", None)
open(p, "w").write(json.dumps(d, indent=2) + "\n")
print("settings.json cleaned (backup: settings.json.bak-hooks-uninstall)")
PY
  echo "✅ uninstalled. Hook scripts and ~/.claude/bin helpers removed."
  exit 0
fi

# --full implies --basic. --ceiling on its own also implies it.
[ "$full" = 1 ] && basic=1
[ "$ceiling" = 1 ] && basic=1

want=()
for entry in "${ALL[@]}"; do
  IFS=: read -r f event matcher tier <<<"$entry"
  case "$tier" in
    1) keep=$basic ;;
    2) keep=$full ;;
    3) keep=$ceiling ;;
  esac
  [ "$keep" = 1 ] && want+=("$f:$event:$matcher")
done

rewrite() {  # rewrite <src> <dst>
  sed -e "s|__CLAUDE_BIN__|$CLAUDE_BIN|g" -e "s|__TOOLKIT_ROOT__|$TOOLKIT_ROOT|g" "$1" > "$2"
  chmod +x "$2"
}

if [ "$dryrun" = 1 ]; then
  echo "Would install into $DEST:"
  for entry in "${want[@]}"; do echo "   hooks/${entry%%:*}"; done
  echo "   bin/checkpoint.sh"
  echo "   bin/close-task.sh"
  echo "and register ${#want[@]} hook(s) in settings.json (backed up first)."
  [ "$ceiling" = 1 ] && echo "   ⚠ INCLUDING context-ceiling.sh, which blocks tool calls."
  exit 0
fi

mkdir -p "$DEST/hooks" "$CLAUDE_BIN"
for entry in "${want[@]}"; do
  f="${entry%%:*}"
  rewrite "$SRC/hooks/$f" "$DEST/hooks/$f"
done
rewrite "$SRC/bin/checkpoint.sh" "$CLAUDE_BIN/checkpoint.sh"
rewrite "$SRC/bin/close-task.sh" "$CLAUDE_BIN/close-task.sh"

"$PY" - "$DEST/settings.json" "$DEST/hooks" "${want[@]}" <<'PY'
import json, os, shutil, sys
settings, hookdir, *reg = sys.argv[1:]
if os.path.exists(settings):
    shutil.copy(settings, settings + ".bak-hooks-install")
    d = json.load(open(settings))
else:
    d = {}
hooks = d.get("hooks", {})
# Drop only OUR registrations, so hooks the user added by hand survive a re-run.
mine = {f.split(":")[0] for f in reg}
for event in list(hooks):
    hooks[event] = [b for b in hooks[event]
                    if not any(os.path.basename(h.get("command", "")) in mine
                               for h in b.get("hooks", []))]
    if not hooks[event]:
        del hooks[event]
for entry in reg:
    f, event, matcher = entry.split(":")
    block = {"hooks": [{"type": "command", "command": os.path.join(hookdir, f)}]}
    if matcher:
        block = {"matcher": matcher, **block}
    hooks.setdefault(event, []).append(block)
d["hooks"] = hooks
open(settings, "w").write(json.dumps(d, indent=2) + "\n")
print("registered %d hook(s) in %s (backup: settings.json.bak-hooks-install)" % (len(reg), settings))
PY

echo
echo "✅ installed $((${#want[@]})) hook(s) + checkpoint.sh/close-task.sh in $CLAUDE_BIN"
[ "$ceiling" = 1 ] && cat <<'EOF'

⚠ context-ceiling.sh is active. Above the limit this session refuses Read, Grep,
  WebFetch, Agent and most Bash, and allows Write/Edit/checkpoint/git so you can
  file your work and /clear. Turn it off for one session with CLAUDE_CTX_CEILING=0.
EOF
cat <<EOF

   These hooks are USER-GLOBAL — every repo, every concurrent session.
   Per-hook escapes need no reinstall:
     CLAUDE_CTX_WATCH=0  CLAUDE_CTX_CEILING=0  CLAUDE_PRECOMPACT_GUARD=0  CLAUDE_WORK_BOUNDARY=0

   Uninstall:  $UNINSTALL
EOF
