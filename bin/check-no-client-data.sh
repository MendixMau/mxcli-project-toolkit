#!/usr/bin/env bash
# check-no-client-data.sh — fail if tracked files contain client/vendor data.
#
# Guards the public toolkit repo against re-introducing the kinds of leaks
# scrubbed on 2026-07-22 and again on 2026-08-03: real client names, CJK
# strings copied from a real app, typed OutSystems GUIDs, local filesystem
# paths, and contact details.
#
# THE DENYLIST IS NOT IN THIS FILE, AND MUST NEVER BE.
# A tracked denylist publishes exactly the names it exists to suppress — that
# was the 2026-08-03 finding: five client names sat in this script, which also
# excluded itself from its own scan, so it reported clean while leaking.
# Names live in .leakguard-deny (gitignored), or $LEAKGUARD_DENY.
#
# .leakguard-deny format: one extended-regex pattern per line; blank lines and
# # comments ignored; matching is case-insensitive. What belongs in it —
#   client and vendor company names; engagement codenames and internal project
#   codes; person names; internal hostnames and domains; real .mpr/app names.
# What does NOT — generic technology names (Mendix, OutSystems, Angular, SAP),
#   public sample apps, and public Marketplace module names (e.g. Teamcenter
#   connector, GenAI Commons): denylisting those only produces false positives
#   that tempt the next person to mangle a legitimate line.
# Use word boundaries (\bFoo\b) for short tokens that occur inside identifiers.
#
# Usage:
#   bin/check-no-client-data.sh            # scan tracked files, exit 1 on any hit
#   LEAKGUARD_DENY='Foo|Bar' bin/check-no-client-data.sh   # override for CI
#   runs automatically as a git pre-commit and pre-push hook (bin/install-hooks.sh)

set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

fail=0
report() { echo "❌ $1"; fail=1; }

# Scan tracked text files. This script is NOT excluded — a guard that cannot
# see itself is how the last leak survived four months of clean exits.
# --others --exclude-standard includes new, not-yet-staged files: a leak should be
# caught when it lands in the tree, not only once someone remembers to `git add`.
FILES=$(git ls-files --cached --others --exclude-standard -- \
  '*.md' '*.html' '*.json' '*.js' '*.ts' '*.txt' '*.mdl' '*.star' '*.sh' \
  '*.yml' '*.yaml' '*.css' '*.py' \
  ':!:*/node_modules/*')
[ -z "$FILES" ] && exit 0

# 1) Client / vendor / person name denylist (case-insensitive).
#    Sourced from, in order of precedence: $LEAKGUARD_DENY, then .leakguard-deny.
DENY="${LEAKGUARD_DENY:-}"
if [ -z "$DENY" ] && [ -f .leakguard-deny ]; then
  # One pattern per line; blank lines and # comments ignored; joined with |.
  DENY=$(grep -vE '^\s*(#|$)' .leakguard-deny | paste -sd '|' -)
fi

if [ -z "$DENY" ]; then
  echo "⚠️  No denylist found (.leakguard-deny missing and \$LEAKGUARD_DENY unset)."
  echo "   Name checks are SKIPPED. Create .leakguard-deny (one regex per line) with"
  echo "   the names this repo must never publish — see the header of this script."
else
  if hits=$(printf '%s\n' $FILES | xargs grep -IilE "$DENY" 2>/dev/null); then
    [ -n "$hits" ] && report "denylisted client/vendor/person name found in:" && echo "$hits"
  fi
fi

# 2) Japanese / Chinese (CJK) — real-app strings are the usual source.
if hits=$(printf '%s\n' $FILES | xargs grep -IilP "[\x{3040}-\x{30ff}\x{4e00}-\x{9faf}]" 2>/dev/null); then
  [ -n "$hits" ] && report "CJK characters found (client data?) in:" && echo "$hits"
fi

# 3) Typed OutSystems GUIDs (real decrypted-module keys).
#    Allow the illustrative EXAMPLE* keys used in docs, e.g. ESpace:EXAMPLEkey0000000001
# A real OS GUID is ~22 base64 chars starting alphanumeric.
# Requiring an alnum first char avoids matching code comments like "Structure:/StructureRef:".
if hits=$(printf '%s\n' $FILES | xargs grep -IinE "(ESpace|Entity|Action|WebScreen|Structure|Attribute|SystemRole|RoleReference|Permission):[A-Za-z0-9][A-Za-z0-9+/=_-]{19,}" 2>/dev/null | grep -v "EXAMPLE"); then
  [ -n "$hits" ] && report "typed OutSystems GUID found (real module key?):" && echo "$hits"
fi

# 4) Local filesystem paths.
if hits=$(printf '%s\n' $FILES | xargs grep -IilE "/Users/[a-z]|/home/[a-z]" 2>/dev/null | grep -v '^bin/check-no-client-data.sh$'); then
  [ -n "$hits" ] && report "local home-directory path found in:" && echo "$hits"
fi

# 5) Contact details. Public/vendor addresses are allowed; anything else is a hit.
EMAIL_ALLOW='@example\.(com|org)|@localhost|noreply@|@users\.noreply\.github\.com|i@izs\.me'
if hits=$(printf '%s\n' $FILES | xargs grep -IinE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" 2>/dev/null \
          | grep -vE "$EMAIL_ALLOW" | grep -v '^bin/check-no-client-data.sh:'); then
  [ -n "$hits" ] && report "email address found in:" && echo "$hits"
fi

# 6) Credential-shaped strings.
if hits=$(printf '%s\n' $FILES | xargs grep -IinE "(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['\"][^'\"]{12,}" 2>/dev/null \
          | grep -v '^bin/check-no-client-data.sh:'); then
  [ -n "$hits" ] && report "possible hard-coded credential in:" && echo "$hits"
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ no client data detected in tracked files"
else
  echo
  echo "Blocked. Genericize the above before committing/pushing. If a hit is a"
  echo "false positive, narrow the pattern here — do NOT add real names to this"
  echo "file, and do NOT re-add a self-exclusion."
fi
exit "$fail"
