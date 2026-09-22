#!/usr/bin/env bash
# leak-check.sh — privacy guard for a company brain.
#
#   bin/leak-check.sh                 # exit 1 on a hit, 0 when clean
#   MXTK_TOOLKIT_ROOT=/path/to/mxcli-project-toolkit bin/leak-check.sh
#
# A company brain MAY name clients, apps and projects — that is the point of the tier. It may
# NOT carry personal data: a person's name on a file, an email address, a phone number, a
# credential, or an absolute path off someone's machine.
#
# Three layers, because the first real drop (2026-09-20) defeated a wrapper that had only one:
#   1. FILENAMES. A brand guide arrived as "<Company> UI Guide -v2.0 <Person Name> 1 (4).pdf".
#      Nothing scans a filename, so a person's name sailed through. Renaming on intake is the
#      fix; this flags it so somebody does.
#   2. TEXT CONTENT via the toolkit's own guard when one is reachable, probes-only (no name
#      denylist required here).
#   3. BINARIES ARE REPORTED, NEVER SILENTLY PASSED. The same drop's PDF contains a corporate
#      email address inside a compressed stream. The toolkit guard scans tracked text files, so
#      on that folder it printed "no scannable tracked files" — a green light over an unread
#      700 KB document. Worse, in a brain that is not yet a git repo it printed git errors and
#      still exited 0. A guard that cannot see something must say so.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT="$(pwd)"
fail=0; warn=0

# ---- 1. filenames -----------------------------------------------------------------------
# Two capitalised words separated by a SPACE are usually a person ("Elma Chang"). Underscore-
# and hyphen-joined words are identifiers (USI_Theme_Module, Routing-Overview), so they are not
# matched — that distinction was added after the first run flagged the module package itself.
NAME_RE='(^|[ (])[A-Z][a-z]{2,} [A-Z][a-z]{2,}([ .)_-]|$)'
MAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
while IFS= read -r f; do
  base="$(basename "$f")"
  if printf '%s' "$base" | grep -qE "$MAIL_RE"; then
    echo "❌ filename contains an email address: $f"; fail=1
  elif printf '%s' "$base" | grep -qE "$NAME_RE"; then
    echo "⚠️  filename may contain a person's name: $f"
    echo "    rename it on intake (the manifest records provenance, the filename does not)"
    warn=$((warn+1))
  fi
done < <(find . -type f -not -path './.git/*' | sed 's|^\./||')

# ---- 2. text content --------------------------------------------------------------------
TOOLKIT="${MXTK_TOOLKIT_ROOT:-{{TOOLKIT_ROOT}}}"
GUARD="$TOOLKIT/bin/check-no-client-data.sh"
if [ -f "$GUARD" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  DENY="$ROOT/.leakguard-deny"
  if [ -f "$DENY" ]; then LEAKGUARD_DENYFILE="$DENY" bash "$GUARD" || fail=1
  else LEAKGUARD_ALLOW_NO_DENYLIST=1 bash "$GUARD" || fail=1; fi
elif [ -f "$GUARD" ]; then
  echo "ℹ️  not a git repository yet — the toolkit's text guard scans tracked files, so it is"
  echo "    skipped. Run 'git init' and commit, then re-run this. Scanning by hand below."
  # Best-effort inline text scan so a pre-git brain is not simply unguarded.
  while IFS= read -r f; do
    file "$f" 2>/dev/null | grep -qi 'text' || continue
    if grep -qE "$MAIL_RE" "$f" 2>/dev/null; then echo "❌ email address in $f"; fail=1; fi
    # The brain's own wiring legitimately names the toolkit clone; anything ELSE under a home
    # directory is somebody's machine leaking in.
    if grep -E '/(Users|home)/[a-z][a-z0-9_-]+/' "$f" 2>/dev/null | grep -qvF "$TOOLKIT"; then
      echo "❌ absolute home path (other than the wired toolkit root) in $f"; fail=1
    fi
  done < <(find . -type f -not -path './.git/*' -size -2M | sed 's|^\./||')
else
  echo "⚠️  toolkit guard not found at $GUARD — text content NOT scanned."
  echo "    set MXTK_TOOLKIT_ROOT to your mxcli-project-toolkit clone."
  warn=$((warn+1))
fi

# ---- 3. unscannable binaries ------------------------------------------------------------
BIN_LIST="$(find . -type f -not -path './.git/*' \( -iname '*.pdf' -o -iname '*.mpk' -o -iname '*.docx' \
  -o -iname '*.pptx' -o -iname '*.xlsx' -o -iname '*.zip' -o -iname '*.mpr' \) | sed 's|^\./||' | sort)"
if [ -n "$BIN_LIST" ]; then
  n="$(printf '%s\n' "$BIN_LIST" | wc -l | tr -d ' ')"
  echo "⚠️  $n binary/document file(s) NOT scanned — no automated check can read inside them:"
  printf '%s\n' "$BIN_LIST" | sed 's/^/      /'
  echo "    A human confirms each one carries no personal data before it is committed."
  echo "    (The first real drop's PDF held a corporate email inside a compressed stream.)"
  warn=$((warn+1))
fi

echo
if [ "$fail" -ne 0 ]; then echo "leak-check: FAILED — fix the ❌ lines above."; exit 1; fi
if [ "$warn" -ne 0 ]; then echo "leak-check: no hard failures, but $warn thing(s) need a human. Read the ⚠️ lines."; exit 0; fi
echo "leak-check: clean"; exit 0
