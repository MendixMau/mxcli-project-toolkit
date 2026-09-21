#!/usr/bin/env bash
# install-project-hooks.sh — the commit-time backstop for the mxbuild gate.
#
#   ./bin/install-project-hooks.sh           # install/refresh the pre-commit hook
#   ./bin/install-project-hooks.sh --check   # exit 1 if it is missing or stale
#
# WHY (2026-09-17, field project). A model can change without the mxbuild gate ever running — a
# bare `./mxcli exec`, an exec.sh run on a machine with no mxbuild, a Studio Pro save —
# and until now every such change committed and pushed like any other. The hook refuses
# a commit that stages model files (the .mpr and mprcontents/) unless bin/model-stamp.sh
# holds a PASS stamp for exactly that staged content. Commits that touch no model file
# are untouched. It runs on every machine, cloud or laptop, with no toolkit clone needed.
#
# Guard rules (toolkit CLAUDE.md, "Shipping an instrument" rules 6/7):
#   * rule 7 — it never blocks the remedy: ./bin/verify-model.sh is not itself a commit, so
#     there is always a way to earn the stamp without going through this hook.
#   * rule 6 — a missing/stale bin/model-stamp.sh stamp is not the only evidence accepted.
#     A recent PASS row in docs/BUILD-LOG.md (written by exec.sh on every exec, independently
#     of the stamp file — the two share no code path) lets the commit through, with a warning
#     naming which row it trusted. A stale or non-pass row does not count. Absent BOTH the
#     stamp and a qualifying BUILD-LOG row, MODEL_UNVERIFIED_OK=1 lets one commit through,
#     out loud, when someone decides to.
#
# An existing pre-commit hook that is not ours is kept and chained (moved to
# pre-commit.pre-mxtk, called first). A repo with core.hooksPath set is reported, not
# edited — its hooks live somewhere this script must not write to.
set -e
. "$(dirname "$0")/_common.sh"

cd "$PROJECT_ROOT"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "install-project-hooks.sh: $PROJECT_ROOT is not in a git repository"; exit 2; }
HOOKS="$(git rev-parse --git-path hooks)"
HOOK="$HOOKS/pre-commit"
MARK="# mxtk-model-stamp hook v1"
# bin/ relative to the git top level, so the hook works when the project root is a subdir.
BIN_REL="$(git rev-parse --show-prefix)bin"

if [ -n "$(git config --get core.hooksPath 2>/dev/null)" ]; then
  echo "⚠ core.hooksPath is set ($(git config --get core.hooksPath)) — add this to that pre-commit yourself:"
  echo "    \"\$(git rev-parse --show-toplevel)/$BIN_REL/model-stamp.sh\" check --staged || exit 1"
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  if [ -f "$HOOK" ] && grep -q "^$MARK" "$HOOK"; then echo "  ✓ pre-commit hook installed ($HOOK)"; exit 0; fi
  echo "  ✗ pre-commit model-verification hook missing — run ./bin/install-project-hooks.sh"; exit 1
fi

mkdir -p "$HOOKS"
if [ -f "$HOOK" ] && ! grep -q "^$MARK" "$HOOK"; then
  mv "$HOOK" "$HOOK.pre-mxtk"
  echo "  existing pre-commit hook kept as $(basename "$HOOK").pre-mxtk and chained first"
fi
cat > "$HOOK" <<HOOKEOF
#!/usr/bin/env bash
$MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
top="\$(git rev-parse --show-toplevel)"
[ -x "\$(dirname "\$0")/pre-commit.pre-mxtk" ] && { "\$(dirname "\$0")/pre-commit.pre-mxtk" || exit 1; }
stamp="\$top/$BIN_REL/model-stamp.sh"
if [ ! -x "\$stamp" ]; then
  echo "⚠ $BIN_REL/model-stamp.sh is missing — the model-verification hook cannot check this commit (re-run the toolkit's sync-project.sh)" >&2
  exit 0
fi
if ! "\$stamp" check --staged; then
  alt=""
  blog="\$top/docs/BUILD-LOG.md"
  max_age="\${MODEL_EVIDENCE_MAX_AGE:-14400}"
  if [ -f "\$blog" ]; then
    bmtime="\$(stat -c %Y "\$blog" 2>/dev/null || stat -f %m "\$blog" 2>/dev/null || echo 0)"
    case "\$bmtime" in ''|*[!0-9]*) bmtime=0 ;; esac
    now="\$(date +%s)"
    lastrow="\$(grep '^| 20' "\$blog" 2>/dev/null | tail -1)"
    if [ "\$bmtime" -gt 0 ] && [ \$(( now - bmtime )) -le "\$max_age" ] && printf '%s' "\$lastrow" | grep -q '| pass |'; then
      alt="a recent docs/BUILD-LOG.md row (gate: pass, \$(( (now - bmtime) / 60 )) min ago)"
    fi
  fi
  if [ -n "\$alt" ]; then
    echo "⚠ no local model-stamp, but accepting \$alt as evidence the model was mxbuild-gated." >&2
    echo "  (this is NOT a guarantee the staged content matches that row — verify-model.sh is the strong check)" >&2
  elif [ "\${MODEL_UNVERIFIED_OK:-0}" = "1" ]; then
    echo "⚠ MODEL_UNVERIFIED_OK=1 — committing a model the mxbuild gate has not verified." >&2
  else
    echo "" >&2
    echo "✗ commit refused: the staged model has not passed the mxbuild gate on this machine." >&2
    echo "  Run   ./bin/verify-model.sh   (one mxbuild, stamps the model when clean), then commit again." >&2
    echo "  Deliberate override, once:   MODEL_UNVERIFIED_OK=1 git commit ..." >&2
    exit 1
  fi
fi
exit 0
HOOKEOF
chmod +x "$HOOK"
echo "  ✓ pre-commit hook installed -> $HOOK"
echo "    (refuses to commit .mpr/mprcontents changes that have no mxbuild-gate PASS stamp; ./bin/verify-model.sh writes one)"
