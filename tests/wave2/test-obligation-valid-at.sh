#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-valid-at.sh [path-to-gate-check.sh | path-to-obligation-check.sh]
#
# test-obligation-valid-at.sh — the LOOK obligation's staleness check must judge a review report
# by its NEWEST "VALID AT: <hash>" stamp, wherever in the file it sits.
#
# THE BUG (#155): _ob_stale and the proof check picked `head -c 8000 | grep ... | head -1` — the
# FIRST stamp in the first 8000 bytes. A report that keeps one dated headline and appends an
# addendum per build row (each with its own VALID AT) was judged by the headline's original
# stamp and went STALE after later model commits, though every page was re-looked-at.
# Subject: obligation-check.sh. Producer of the stamp: module-review.md stage 5 (the reviewer).
set -uo pipefail
ARG="${1:?usage: test-obligation-valid-at.sh /path/to/bin/gate-check.sh (or lib/obligation-check.sh)}"
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "no obligation-check.sh at $OBCHECK"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-validat.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

P="$WORK/p"; mkdir -p "$P/architecture/modules/ModuleX" "$P/mdlsource" "$P/design/ui-reviews"
git -C "$P" init -q . 2>/dev/null
git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/mdlsource/a.mdl"; git -C "$P" add -A; git -C "$P" commit -qm one
OLD="$(git -C "$P" rev-parse --short HEAD)"
echo b >> "$P/mdlsource/a.mdl"; git -C "$P" commit -qam two
NEW="$(git -C "$P" rev-parse --short HEAD)"
REP="$P/design/ui-reviews/ui-review-2026-01-01.html"
stale() { "$OBCHECK" "$P" 2>&1 | grep -c 'STALE'; }

echo "== T1: only the old stamp, model built past it -> STALE (control) =="
printf '<p>ModuleX: 1 of 1 pages reviewed</p>\nVALID AT: %s\n' "$OLD" > "$REP"
[ "$(stale)" -gt 0 ] && ok "old-only stamp reports STALE" || bad "control: expected STALE"

echo "== T2: old stamp, then an addendum stamped at HEAD -> newest wins, not STALE =="
printf '<p>ModuleX: 1 of 1 pages reviewed</p>\nVALID AT: %s\n<h2>Addendum</h2>\nVALID AT: %s\n' "$OLD" "$NEW" > "$REP"
[ "$(stale)" -eq 0 ] && ok "later stamp wins" || bad "first stamp was used (STALE)"

echo "== T3: newest stamp sits past byte 8000 -> still seen =="
{ printf '<p>ModuleX: 1 of 1 pages reviewed</p>\nVALID AT: %s\n' "$OLD"; head -c 9000 /dev/zero | tr '\0' 'x'; printf '\nVALID AT: %s\n' "$NEW"; } > "$REP"
[ "$(stale)" -eq 0 ] && ok "stamp past 8000 bytes seen" || bad "stamp past 8000 bytes ignored (STALE)"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
