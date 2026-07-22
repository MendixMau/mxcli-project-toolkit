#!/usr/bin/env bash
# install-hooks.sh — wire the client-data guard in as a git pre-commit hook.
# Run once per clone: bin/install-hooks.sh
set -e
root="$(git rev-parse --show-toplevel)"
hook="$root/.git/hooks/pre-commit"
cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/bin/check-no-client-data.sh"
HOOK
chmod +x "$hook"
echo "✅ pre-commit hook installed -> $hook"
echo "   (runs bin/check-no-client-data.sh before every commit)"
