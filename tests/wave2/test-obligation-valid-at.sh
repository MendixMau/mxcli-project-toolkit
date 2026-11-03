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
# THE REMAINDER (#155, T4-T8): the PROOF-OF-LOOK freshness rule then compared EVERY citation
# with that one newest stamp, so the first section's honest proofs read "older than VALID AT"
# and the report FAULTed; and "newest" meant last-in-file, so an addendum prepended under the
# headline lost to the older stamp below it. Now each citation is judged by its own section's
# stamp (the nearest stamp above it) and the report's staleness by the stamp with the newest
# commit time.
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

echo "== T3b: one stamp unresolvable here (squash/rebase/shallow) -> last-in-file, unmeasurable, not STALE =="
printf '<p>ModuleX: 1 of 1 pages reviewed</p>\nVALID AT: %s\n<h2>Addendum</h2>\nVALID AT: deadbee1\n' "$OLD" > "$REP"
[ "$(stale)" -eq 0 ] && ok "unresolvable stamp falls back to last-in-file (unmeasured)" || bad "older resolvable stamp picked over an unresolvable one (STALE)"

# ── T4-T8: dated report (owes PROOF-OF-LOOK), commits and shot mtimes at fixed times ──
Q="$WORK/q"; mkdir -p "$Q/architecture/modules/ModuleX" "$Q/mdlsource" "$Q/design/ui-reviews/shots"
git -C "$Q" init -q . 2>/dev/null
git -C "$Q" config user.email t@t; git -C "$Q" config user.name t
echo a > "$Q/mdlsource/a.mdl"; git -C "$Q" add -A
GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" git -C "$Q" commit -qm one
S1="$(git -C "$Q" rev-parse --short HEAD)"
echo b >> "$Q/mdlsource/a.mdl"
GIT_AUTHOR_DATE="2026-03-01T00:00:00Z" GIT_COMMITTER_DATE="2026-03-01T00:00:00Z" git -C "$Q" commit -qam two
S2="$(git -C "$Q" rev-parse --short HEAD)"
SH="$Q/design/ui-reviews/shots"
for n in before mid after; do head -c 20000 /dev/urandom > "$SH/$n.png"; done
touch -t 202512010000 "$SH/before.png"   # older than S1
touch -t 202602010000 "$SH/mid.png"      # between S1 and S2
touch -t 202604010000 "$SH/after.png"    # newer than S2
QREP="$Q/design/ui-reviews/ui-review-2026-09-26.html"
look() { "$OBCHECK" "$Q" 2>&1 | grep 'Obligation look '; }

echo "== T4: headline section (S1, shot after S1) + addendum (S2, shot after S2) -> PASS =="
printf '<p>ModuleX: 2 of 2 pages reviewed</p>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Home = shots/mid.png</pre>\n<h2>Addendum</h2>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Edit = shots/after.png</pre>\n' "$S1" "$S2" > "$QREP"
out="$(look)"
case "$out" in *"look       PASS"*) ok "each proof judged by its own section's stamp" ;; *) bad "sectioned report not PASS: $out" ;; esac

echo "== T5: headline section cites a shot older than ITS stamp -> FAULT (control) =="
printf '<p>ModuleX: 2 of 2 pages reviewed</p>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Home = shots/before.png</pre>\n<h2>Addendum</h2>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Edit = shots/after.png</pre>\n' "$S1" "$S2" > "$QREP"
out="$("$OBCHECK" "$Q" 2>&1 | grep -A3 'Obligation look ')"
case "$out" in *FAULT*ModuleX.Home*) ok "a shot older than its own section's stamp still FAULTs" ;; *) bad "stale shot in section 1 not caught: $out" ;; esac
# #357: the FAULT names its remedy (append an addendum), or a partial re-take reads as
# "re-shoot every page" or "accept the FAULT".
case "$out" in *"keep the old section and its original stamp (restore it if bumped)"*"VALID AT: <model commit the shots were taken on>"*"PROOF-OF-LOOK for the re-shot pages"*) ok "the old-shots FAULT names the addendum remedy" ;; *) bad "old-shots FAULT gives no remedy: $out" ;; esac

echo "== T6: addendum cites a shot older than the addendum's stamp -> FAULT (not judged by the min stamp) =="
printf '<p>ModuleX: 2 of 2 pages reviewed</p>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Home = shots/mid.png</pre>\n<h2>Addendum</h2>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Edit = shots/mid.png</pre>\n' "$S1" "$S2" > "$QREP"
out="$("$OBCHECK" "$Q" 2>&1 | grep -A3 'Obligation look ')"
case "$out" in *FAULT*ModuleX.Edit*) ok "addendum's shot judged by the addendum's stamp" ;; *) bad "addendum's stale shot not caught: $out" ;; esac

echo "== T7: the T4 report minified onto one line -> PASS =="
printf '<p>ModuleX: 2 of 2 pages reviewed</p> VALID AT: %s <pre>PROOF-OF-LOOK: ModuleX.Home = shots/mid.png</pre><h2>Addendum</h2> VALID AT: %s <pre>PROOF-OF-LOOK: ModuleX.Edit = shots/after.png</pre>' "$S1" "$S2" > "$QREP"
out="$(look)"
case "$out" in *"look       PASS"*) ok "one-line report sectioned left to right" ;; *) bad "one-line report not PASS: $out" ;; esac

echo "== T8: addendum PREPENDED above the older stamp -> newest by commit time, not STALE =="
rm -f "$QREP"
printf '<p>ModuleX: 1 of 1 pages reviewed</p>\nVALID AT: %s\n<h2>Original</h2>\nVALID AT: %s\n' "$S2" "$S1" \
  > "$Q/design/ui-reviews/ui-review-2026-01-01.html"
n="$("$OBCHECK" "$Q" 2>&1 | grep -c 'STALE')"
[ "$n" -eq 0 ] && ok "newest stamp chosen by commit time" || bad "last-in-file stamp was used (STALE)"

echo "== T9: addendum stamped with a LATER commit that only adds the shots -> FAULT stays (#357 review) =="
# The trap the FAULT's remedy must not set: stamp the commit that adds the screenshots and the
# shots predate their own stamp. The remedy says "the model commit the shots were taken on".
rm -f "$Q/design/ui-reviews/ui-review-2026-01-01.html"   # T8's pre-rule report would be judged instead
mkdir -p "$Q/docs"; echo shots > "$Q/docs/shots-added.txt"; git -C "$Q" add docs/shots-added.txt
GIT_AUTHOR_DATE="2026-05-01T00:00:00Z" GIT_COMMITTER_DATE="2026-05-01T00:00:00Z" git -C "$Q" commit -qm "add shots"
S3="$(git -C "$Q" rev-parse --short HEAD)"
printf '<p>ModuleX: 2 of 2 pages reviewed</p>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Home = shots/mid.png</pre>\n<h2>Addendum</h2>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Edit = shots/after.png</pre>\n' "$S1" "$S3" > "$QREP"
out="$("$OBCHECK" "$Q" 2>&1 | grep -A3 'Obligation look ')"
case "$out" in *FAULT*ModuleX.Edit*) ok "stamping the shots-adding commit still FAULTs" ;; *) bad "addendum stamped after its shots was accepted: $out" ;; esac
printf '<p>ModuleX: 2 of 2 pages reviewed</p>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Home = shots/mid.png</pre>\n<h2>Addendum</h2>\nVALID AT: %s\n<pre>PROOF-OF-LOOK: ModuleX.Edit = shots/after.png</pre>\n' "$S1" "$S2" > "$QREP"
out="$(look)"
case "$out" in *"look       PASS"*) ok "the same addendum stamped with the model commit PASSes" ;; *) bad "model-commit stamp not PASS after a shots-only commit: $out" ;; esac

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
