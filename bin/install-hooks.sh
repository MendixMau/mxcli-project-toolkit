#!/usr/bin/env bash
# install-hooks.sh — wire the client-data guard in as pre-commit AND pre-push hooks.
# Run once per clone: bin/install-hooks.sh
#
# Pre-push matters as much as pre-commit: a leak that lands in a local commit is
# recoverable, one that reaches a public remote is not. Pre-push is the last gate
# before the repo becomes world-readable.
set -e
root="$(git rev-parse --show-toplevel)"

for stage in pre-commit pre-push; do
  hook="$root/.git/hooks/$stage"
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/bin/check-no-client-data.sh"
HOOK
  chmod +x "$hook"
  echo "✅ $stage hook installed -> $hook"
done

echo "   (both run bin/check-no-client-data.sh)"

if [ ! -f "$root/.leakguard-deny" ]; then
  echo
  echo "⚠️  No .leakguard-deny in this clone — name checks will be skipped."
  echo "   Create .leakguard-deny (one regex per line) — format in the header of"
  echo "   bin/check-no-client-data.sh."
fi
