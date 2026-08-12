#!/usr/bin/env bash
# install-hooks.sh — wire the repo's guards in as pre-commit AND pre-push hooks.
# Run once per clone: bin/install-hooks.sh
#
# Pre-push matters as much as pre-commit: a leak that lands in a local commit is
# recoverable, one that reaches a public remote is not. Pre-push is the last gate
# before the repo becomes world-readable.
#
# Two guards, in this order:
#   check-no-client-data.sh  — leak guard. First, always: a leak is unrecoverable.
#   check-docs-numbering.sh  — doc self-consistency (wave-2 #9/#10). Runs on the
#                              commit that introduces the drift, in this repo,
#                              without anyone choosing to run it. That is the
#                              whole point: the build loop was called 12-step,
#                              13-step and 15-step at once for months.
set -e
root="$(git rev-parse --show-toplevel)"

for stage in pre-commit pre-push; do
  hook="$root/.git/hooks/$stage"
  # NB: `exec` replaces the shell, so a second check may not follow it.
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
root="$(git rev-parse --show-toplevel)"
"$root/bin/check-no-client-data.sh" || exit 1
[ -x "$root/bin/check-docs-numbering.sh" ] && { "$root/bin/check-docs-numbering.sh" || exit 1; }
exit 0
HOOK
  chmod +x "$hook"
  echo "✅ $stage hook installed -> $hook"
done

echo "   (both run bin/check-no-client-data.sh, then bin/check-docs-numbering.sh)"

if [ ! -f "$root/.leakguard-deny" ]; then
  echo
  echo "⚠️  No .leakguard-deny in this clone — name checks will be skipped."
  echo "   Create .leakguard-deny (one regex per line) — format in the header of"
  echo "   bin/check-no-client-data.sh."
fi
