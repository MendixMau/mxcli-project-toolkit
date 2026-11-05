#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-prototype-look.sh [path-to-gate-check.sh | path-to-obligation-check.sh]
#
# test-obligation-prototype-look.sh — the `prototype-look` row in bin/lib/obligations.tsv (#632):
# the assembled design/prototype.html, LOOKed at in a browser at device widths before the Stage 3
# sign-off question, re-owed whenever the prototype is re-assembled.
#
# WHY: a 15-screen prototype went to its product owner twice (v1, v2) with every input overflowing
# its card by 17-18 px at phone width; the user found it. Nothing owed a look at the assembled
# page — only at the per-screen wireframes, which rendered fine.
#
# The prototype here is built by the REAL project-bin/assemble-prototype.js (the producer), and the
# PROTOTYPE-SHA the report stamps is the one that script prints — so the producer and the consumer
# are checked against each other, not against a hash this test computed the same way the checker
# does. Producer of the report: skills/design-artifacts.md Step 3d (review-agent).
#
# Positive control: against master's obligations.tsv there is no prototype-look row; T1 fails.
set -uo pipefail
ARG="${1:?usage: test-obligation-prototype-look.sh /path/to/bin/gate-check.sh (or lib/obligation-check.sh)}"
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "no obligation-check.sh at $OBCHECK"; exit 2; }
TK="$(cd "$(dirname "$OBCHECK")/../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "test-obligation-prototype-look: node not available, skipping"; exit 0; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-proto.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

P="$WORK/p"; mkdir -p "$P/design/wireframes" "$P/design/ui-reviews/shots"
printf '# PROJECT.md\n\nToolkit commit: none\n' > "$P/PROJECT.md"
printf '<html><body data-route="home"><main><h1>Home</h1><a href="#/list">List</a></main></body></html>\n' > "$P/design/wireframes/Home.html"
printf '<html><body><main><h1>List</h1><a href="#/home">Home</a></main></body></html>\n' > "$P/design/wireframes/List.html"
assemble() { (cd "$P" && node "$TK/project-bin/assemble-prototype.js" 2>/dev/null) | grep -oE 'sha256 [0-9a-f]{64}' | cut -d' ' -f2; }
SHA="$(assemble)"
[ -n "$SHA" ] && ok "assemble-prototype.js prints the sha256 the report stamps" || bad "assemble-prototype.js printed no sha256"

REP="$P/design/ui-reviews/prototype-look-2026-11-05.html"
line()  { "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation prototype-look ' | head -1; }
stale() { "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation prototype-look ' | grep -c 'STALE'; }
proofs() { local r w; for r in home list; do for w in 390 360 320 1280; do
  head -c 12000 /dev/urandom > "$P/design/ui-reviews/shots/$r@$w.png"
  printf 'PROOF-OF-LOOK: %s@%s = shots/%s@%s.png\n' "$r" "$w" "$r" "$w"; done; done; }
PROOF="$(proofs)"
HEAD8='<p>8 of 8 screen-widths captured (2 screens x 390/360/320/1280); overflow 0 of 14 elements</p>'

echo "== T1: no report -> PENDING, owed by review-agent =="
l="$(line)"
case "$l" in *PENDING*review-agent*design-artifacts.md*) ok "no report is PENDING" ;; *) bad "expected PENDING, got: $l" ;; esac

echo "== T2: a per-module ui-review report does not discharge it =="
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA" "$PROOF" > "$P/design/ui-reviews/ui-review-2026-11-05.html"
l="$(line)"
case "$l" in *PENDING*) ok "module LOOK report ignored" ;; *) bad "ui-review discharged prototype-look: $l" ;; esac
rm -f "$P/design/ui-reviews/ui-review-2026-11-05.html"

echo "== T3: denominator + proofs but no PROTOTYPE-SHA -> FAULT naming the stamp =="
printf '%s\n%s\n' "$HEAD8" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *FAULT*"NO PROTOTYPE-SHA"*) ok "unstamped prototype LOOK is FAULT" ;; *) bad "expected FAULT (no sha), got: $l" ;; esac

echo "== T4: no denominator -> FAULT =="
printf '<p>Looked at the prototype, all fine.</p>\nPROTOTYPE-SHA: %s\n%s\n' "$SHA" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *FAULT*DENOMINATOR*) ok "no denominator is FAULT" ;; *) bad "expected FAULT (denominator), got: $l" ;; esac

echo "== T5: claims 8 screen-widths, cites 4 -> FAULT (pixel rule) =="
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA" "$(printf '%s\n' "$PROOF" | head -4)" > "$REP"
l="$(line)"
case "$l" in *FAULT*PROOF-OF-LOOK*) ok "fewer citations than screen-widths is FAULT" ;; *) bad "expected FAULT (proof), got: $l" ;; esac

echo "== T6: denominator, matching sha, 8 proofs -> PASS =="
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *PASS*) ok "current prototype LOOK is PASS" ;; *) bad "expected PASS, got: $l" ;; esac
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "${SHA:0:12}" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *PASS*) ok "a 12-char prefix of the sha is accepted" ;; *) bad "prefix stamp not accepted: $l" ;; esac
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA" "$PROOF" > "$REP"

echo "== T7: a wireframe edit + re-assembly -> owed again (STALE): a v1 LOOK cannot discharge v2 =="
printf '<html><body><main><h1>List v2</h1><a href="#/home">Home</a></main></body></html>\n' > "$P/design/wireframes/List.html"
SHA2="$(assemble)"
[ -n "$SHA2" ] && [ "$SHA2" != "$SHA" ] && ok "re-assembly changes the sha" || bad "sha did not change: $SHA / $SHA2"
l="$(line)"
case "$l" in *PENDING*) ok "LOOK of the previous prototype is PENDING" ;; *) bad "expected PENDING, got: $l" ;; esac
[ "$(stale)" -gt 0 ] && ok "STALE line names it" || bad "no STALE line for prototype-look"
SHA3="$(assemble)"
[ "$SHA3" = "$SHA2" ] && ok "assembling the same input twice gives the same sha (deterministic)" || bad "sha not deterministic"

echo "== T8: a register waiver -> not owed =="
printf '# PROJECT.md\n\nToolkit commit: none\nWaived obligation prototype-look: integration-only app, no screens\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *PASS*"1 waived"*) ok "waived prototype-look reads PASS (1 waived)" ;; *) bad "expected waived, got: $l" ;; esac

echo "== T9: adopted above stage 3 -> ADOPTED =="
printf '# PROJECT.md\n\nToolkit commit: none\nAdopted at stage: 5\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *ADOPTED*) ok "a project that joined at stage 5 owes no prototype LOOK" ;; *) bad "expected ADOPTED, got: $l" ;; esac

echo "== T10: two-tree layout (design/ under app/) -> the sha is read there =="
Q="$WORK/q"; mkdir -p "$Q/app/design" "$Q/design/ui-reviews/shots"
printf '# PROJECT.md\n\nToolkit commit: none\n' > "$Q/PROJECT.md"
cp "$P/design/prototype.html" "$Q/app/design/prototype.html"
cp "$P/design/ui-reviews/shots/"*.png "$Q/design/ui-reviews/shots/"
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA" "$PROOF" > "$Q/design/ui-reviews/prototype-look-2026-11-05.html"
l="$("$OBCHECK" "$Q" 2>&1 | grep -E '^Obligation prototype-look ' | head -1)"
case "$l" in *PENDING*) ok "an app/design prototype is hashed: the old-sha report is STALE there" ;; *) bad "app/design prototype not read: $l" ;; esac

echo "== T11: no prototype in either layout -> N/A, and status.sh does not list it as next =="
R="$WORK/r"; mkdir -p "$R/architecture/modules/Orders"
printf '# PROJECT.md\n\nToolkit commit: none\n' > "$R/PROJECT.md"
l="$("$OBCHECK" "$R" 2>&1 | grep -E '^Obligation prototype-look ' | head -1)"
case "$l" in *"N/A"*"no design/prototype.html"*) ok "no prototype is N/A, not PENDING" ;; *) bad "expected N/A, got: $l" ;; esac
if [ -x "$TK/bin/status.sh" ] && [ "$(basename "$OBCHECK")" = obligation-check.sh ] && [ -f "$TK/bin/gate-check.sh" ]; then
  st="$("$TK/bin/status.sh" "$R" 2>&1 || true)"
  case "$st" in *prototype-look*) bad "status.sh lists prototype-look for a project with no prototype" ;; *) ok "status.sh says nothing about prototype-look with no prototype" ;; esac
fi

echo "== T12: a CRLF checkout of the same prototype (Windows autocrlf) is not STALE =="
C="$WORK/c"; mkdir -p "$C/design/ui-reviews/shots"
printf '# PROJECT.md\n\nToolkit commit: none\n' > "$C/PROJECT.md"
sed 's/$/\r/' "$P/design/prototype.html" > "$C/design/prototype.html"
cmp -s "$C/design/prototype.html" "$P/design/prototype.html" && bad "CRLF copy is byte-identical (fixture broken)"
cp "$P/design/ui-reviews/shots/"*.png "$C/design/ui-reviews/shots/"
printf '%s\nPROTOTYPE-SHA: %s\n%s\n' "$HEAD8" "$SHA3" "$PROOF" > "$C/design/ui-reviews/prototype-look-2026-11-05.html"
l="$("$OBCHECK" "$C" 2>&1 | grep -E '^Obligation prototype-look ' | head -1)"
case "$l" in *PASS*) ok "CRLF prototype hashes like the LF one the assembler printed" ;; *) bad "CRLF checkout misread: $l" ;; esac

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
