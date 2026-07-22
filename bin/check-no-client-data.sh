#!/usr/bin/env bash
# check-no-client-data.sh — fail if tracked files contain client/vendor data.
#
# Guards the public toolkit repo against re-introducing the kinds of leaks
# scrubbed on 2026-07-22: real client names, CJK strings copied from a real
# app, typed OutSystems GUIDs, or local filesystem paths.
#
# Usage:
#   bin/check-no-client-data.sh            # scan tracked files, exit 1 on any hit
#   run automatically as a git pre-commit hook (see bin/install-hooks.sh)
#
# To allow a legitimate token (e.g. your own project name), add it to the
# ALLOW list below — do NOT weaken the client-name denylist.

set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

fail=0
report() { echo "❌ $1"; fail=1; }

# Only scan text files that are tracked; skip this script itself + node_modules.
FILES=$(git ls-files -- '*.md' '*.html' '*.json' '*.js' '*.txt' '*.mdl' '*.star' '*.sh' \
  ':!:*/node_modules/*' ':!:bin/check-no-client-data.sh')
[ -z "$FILES" ] && exit 0

# 1) Client / vendor name denylist (case-insensitive). These must never return.
DENY='Macnica|Omnext|HMCL|uSoner|MetaSystems'
if hits=$(printf '%s\n' $FILES | xargs grep -IilE "$DENY" 2>/dev/null); then
  [ -n "$hits" ] && report "client/vendor name found in:" && echo "$hits"
fi

# 2) Japanese / Chinese (CJK) — real-app strings are the usual source.
if hits=$(printf '%s\n' $FILES | xargs grep -IilP "[\x{3040}-\x{30ff}\x{4e00}-\x{9faf}]" 2>/dev/null); then
  [ -n "$hits" ] && report "CJK characters found (client data?) in:" && echo "$hits"
fi

# 3) Typed OutSystems GUIDs (real decrypted-module keys), e.g. ESpace:6EeWoOOi90KxAL7U5mhhbg
#    Allow the illustrative EXAMPLE* keys used in docs.
# A real OS GUID is ~22 base64 chars starting alphanumeric (e.g. 6EeWoOOi90KxAL7U5mhhbg).
# Requiring an alnum first char avoids matching code comments like "Structure:/StructureRef:".
if hits=$(printf '%s\n' $FILES | xargs grep -IinE "(ESpace|Entity|Action|WebScreen|Structure|Attribute|SystemRole|RoleReference|Permission):[A-Za-z0-9][A-Za-z0-9+/=_-]{19,}" 2>/dev/null | grep -v "EXAMPLE"); then
  [ -n "$hits" ] && report "typed OutSystems GUID found (real module key?):" && echo "$hits"
fi

# 4) Local filesystem paths.
if hits=$(printf '%s\n' $FILES | xargs grep -IilE "/Users/[a-z]" 2>/dev/null); then
  [ -n "$hits" ] && report "local /Users/ path found in:" && echo "$hits"
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ no client data detected in tracked files"
else
  echo
  echo "Commit blocked. Genericize the above before committing, or update the"
  echo "ALLOW rules in bin/check-no-client-data.sh if a hit is a false positive."
fi
exit "$fail"
