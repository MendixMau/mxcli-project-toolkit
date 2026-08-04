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
#
# NUL-delimited into an array, not a whitespace-split string: a tracked path
# containing a space silently truncated the old scan, and a path beginning with
# '-' was read by grep/perl as a flag (a stray file literally named '--help'
# aborted a whole-tree scan this way on 2026-08-03). Every probe below passes
# `--` before the file list for the same reason.
#
# A NUL-delimited temp file, not a bash array: `env bash` on stock macOS is
# 3.2.57, which has no `mapfile`. The array form failed silently there — zero
# files collected, `exit 0`, "✅ no client data detected". A guard that scans
# nothing and reports clean is the exact bug this script exists to not be.
# Keep this bash-3.2 compatible; do not reintroduce mapfile or `readarray`.
LIST=$(mktemp "${TMPDIR:-/tmp}/leakguard.XXXXXX") || exit 2
trap 'rm -f "$LIST"' EXIT
git ls-files -z --cached --others --exclude-standard -- \
  '*.md' '*.html' '*.json' '*.js' '*.ts' '*.txt' '*.mdl' '*.star' '*.sh' \
  '*.yml' '*.yaml' '*.css' '*.py' \
  ':!:*/node_modules/*' > "$LIST"

# Count is reported with the final verdict: a pass over 0 files looks identical
# to a pass over 400 unless you print it.
NFILES=$(tr -cd '\0' < "$LIST" | wc -c | tr -d ' ')
[ "$NFILES" -eq 0 ] && { echo "✅ no scannable tracked files"; exit 0; }

# Run a probe over every file. Captures output and tests THAT, never the exit
# status of the pipeline: xargs returns 123 when any batch's grep found nothing,
# so `if hits=$(... | xargs grep ...)` discards real hits from a later batch once
# the file list exceeds one batch. Latent for years, then live the day the repo
# grows past ARG_MAX.
scan() { xargs -0 "$@" < "$LIST" 2>/dev/null || true; }

# A probe that cannot detect its own positive control is a silent no-op, not a
# pass. Every check below is self-tested before it runs — this is precisely how
# the CJK check failed: `grep -P` is GNU-only, BSD grep errored into /dev/null,
# and the guard printed ✅ over real client strings for as long as it existed.
selftest_failed() {
  echo "❌ INSTRUMENT BROKEN: the $1 probe did not match its own positive control."
  echo "   This is a broken check, not a clean repo. Refusing to report a pass."
  exit 2
}

# 1) Client / vendor / person name denylist (case-insensitive).
#    Sourced from, in order of precedence: $LEAKGUARD_DENY, then .leakguard-deny.
DENY="${LEAKGUARD_DENY:-}"
if [ -z "$DENY" ] && [ -f .leakguard-deny ]; then
  # One pattern per line; blank lines and # comments ignored; joined with |.
  DENY=$(grep -vE '^\s*(#|$)' .leakguard-deny | paste -sd '|' -)
fi

if [ -z "$DENY" ]; then
  # Hard failure, not a warning. .leakguard-deny is gitignored by design, so it
  # is absent on every clone but the author's — the old code warned and then
  # printed ✅ and exited 0, meaning the name check was off by default for
  # everyone else while still reporting a pass. If you genuinely have no names
  # to suppress yet, set the escape hatch explicitly so the choice is greppable.
  if [ -z "${LEAKGUARD_ALLOW_NO_DENYLIST:-}" ]; then
    echo "❌ No denylist found (.leakguard-deny missing and \$LEAKGUARD_DENY unset)."
    echo "   Refusing to report a pass with the name check disabled."
    echo "   Create .leakguard-deny (one regex per line) with the names this repo"
    echo "   must never publish — see the header of this script — or set"
    echo "   LEAKGUARD_ALLOW_NO_DENYLIST=1 to accept the gap deliberately."
    exit 2
  fi
  echo "⚠️  No denylist; name check skipped by LEAKGUARD_ALLOW_NO_DENYLIST."
else
  hits=$(scan grep -IilE "$DENY" --)
  [ -n "$hits" ] && { report "denylisted client/vendor/person name found in:"; echo "$hits"; }
fi

# 2) CJK + Hangul — real-app strings are the usual source.
#    Hangul is in range because this toolkit's engagements have included Korean
#    stacks (WebSquare, Korean MES); the old probe covered only Kana and Han and
#    would have passed Korean client text even had it worked.
#    perl, not `grep -P`: BSD grep has no -P at all. Note -CSD — without it perl
#    reads UTF-8 as latin1 and \x{4e00} can never match, which is a second,
#    quieter way to get the same false green.
cjk_probe() { perl -CSD -ne 'if (/[\x{3040}-\x{30ff}\x{4e00}-\x{9faf}\x{ac00}-\x{d7af}]/) { print "$ARGV\n"; close ARGV }' "$@"; }
printf '\xe6\xa0\xaa\xe5\xbc\x8f\xe4\xbc\x9a\xe7\xa4\xbe\n' > "${TMPDIR:-/tmp}/.leakguard-probe.$$"
cjk_probe "${TMPDIR:-/tmp}/.leakguard-probe.$$" | grep -q . || selftest_failed "CJK/Hangul"
rm -f "${TMPDIR:-/tmp}/.leakguard-probe.$$"
hits=$(scan perl -CSD -ne 'if (/[\x{3040}-\x{30ff}\x{4e00}-\x{9faf}\x{ac00}-\x{d7af}]/) { print "$ARGV\n"; close ARGV }' --)
[ -n "$hits" ] && { report "CJK/Hangul characters found (client data?) in:"; echo "$hits"; }

# 3) Typed OutSystems GUIDs (real decrypted-module keys).
#    Allow the illustrative EXAMPLE* keys used in docs, e.g. ESpace:EXAMPLEkey0000000001
# A real OS GUID is ~22 base64 chars starting alphanumeric.
# Requiring an alnum first char avoids matching code comments like "Structure:/StructureRef:".
hits=$(scan grep -IinE "(ESpace|Entity|Action|WebScreen|Structure|Attribute|SystemRole|RoleReference|Permission):[A-Za-z0-9][A-Za-z0-9+/=_-]{19,}" -- | grep -v "EXAMPLE" || true)
[ -n "$hits" ] && { report "typed OutSystems GUID found (real module key?):"; echo "$hits"; }

# 4) Local filesystem paths.
hits=$(scan grep -IilE "/Users/[a-z]|/home/[a-z]" -- | grep -v '^bin/check-no-client-data.sh$' || true)
[ -n "$hits" ] && { report "local home-directory path found in:"; echo "$hits"; }

# 5) Contact details. Public/vendor addresses are allowed; anything else is a hit.
EMAIL_ALLOW='@example\.(com|org)|@localhost|noreply@|@users\.noreply\.github\.com|i@izs\.me'
hits=$(scan grep -IinE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" -- \
       | grep -vE "$EMAIL_ALLOW" | grep -v '^bin/check-no-client-data.sh:' || true)
[ -n "$hits" ] && { report "email address found in:"; echo "$hits"; }

# 6) Credential-shaped strings.
hits=$(scan grep -IinE "(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['\"][^'\"]{12,}" -- \
       | grep -v '^bin/check-no-client-data.sh:' || true)
[ -n "$hits" ] && { report "possible hard-coded credential in:"; echo "$hits"; }

if [ "$fail" -eq 0 ]; then
  echo "✅ no client data detected in $NFILES tracked files"
else
  echo
  echo "Blocked. Genericize the above before committing/pushing. If a hit is a"
  echo "false positive, narrow the pattern here — do NOT add real names to this"
  echo "file, and do NOT re-add a self-exclusion."
fi
exit "$fail"
