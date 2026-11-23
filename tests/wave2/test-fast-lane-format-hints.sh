#!/usr/bin/env bash
# test-fast-lane-format-hints.sh — a gate FAIL on a format the toolkit parses prints the whole
# accepted shape, and every shape printed passes its own parser (#821 point 1).
#
# usage: bash tests/wave2/test-fast-lane-format-hints.sh [toolkit-root]
#   toolkit-root defaults to this checkout; a master worktree shows the H*a cases failing there
#   (the subject is bin/gate-check.sh + bin/lib/obligation-check.sh + bin/lib/format-hints.sh).
#
# Field basis: two simulated builds, 2026-11-20 (claude -p, stubbed Mendix tools): a prototype
# LOOK took 5 gate runs, one new requirement per FAIL; build-plan row ids were rewritten by sed
# after a FAIL; 10 and 19 calls read gate source before the first model write.
#
# Each case has two halves: (a) the FAIL prints the shape — fails on master; (b) the example
# lines printed are written into a project scaffolded by the real bin/init-project.sh and the
# same gate passes them — so an example can never drift from its parser unnoticed.
#   H1 intake markers (Stage P)      H2 build plan (Stage 4)        H3 coverage ledger (engine)
#   H4 LOOK report (Stage 5)         H5 prototype LOOK (obligation)  H6 each shape once per run
set -uo pipefail

TK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TK="$(cd "$TK" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # the examples always come from this checkout
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fast-lane-hints.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== toolkit: $TK"
. "$HERE/bin/lib/format-hints.sh"
ex() { mxtk_format_hint "$1" | sed -n 's/^      //p'; }   # the example lines, indentation stripped

printf 'zz-no-client-name-zz\n' > "$WORK/deny"
MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" bash "$TK/bin/init-project.sh" "$WORK/seed" >/dev/null 2>&1 </dev/null
[ -f "$WORK/seed/intake.md" ] || { echo "init-project.sh produced no scaffold"; exit 2; }
( cd "$WORK/seed" && git init -q . 2>/dev/null; git add -A >/dev/null 2>&1 \
  && git -c user.email=t@t -c user.name=t commit -qm scaffold ) >/dev/null 2>&1
N=0
mkp() { N=$((N+1)); P="$WORK/p$N"; cp -R "$WORK/seed" "$P"; }
gc() { out="$(bash "$TK/bin/gate-check.sh" --no-html "$@" 2>&1)"; rc=$?; }
stage() { printf '%s\n' "$out" | grep -m1 "^Stage $1 "; }
# answer_all <project> <marker...> — one marker line under every '## N.' heading, round-robin
answer_all() {
  local p="$1"; shift
  printf '%s\n' "$@" > "$WORK/markers"
  awk -v mf="$WORK/markers" 'BEGIN { while ((getline l < mf) > 0) m[n++] = l }
    /^## [0-9]+\./ { print; print ""; print m[i++ % n]; next } { print }' "$p/intake.md" > "$p/intake.tmp" && mv "$p/intake.tmp" "$p/intake.md"
}
shot() { head -c 20000 /dev/urandom > "$1"; }   # a capture-sized file (the gate checks >= 10 KB)

echo "-- H1: intake markers"
mkp; gc "$P"
case "$out" in *"Accepted shape — intake.md"*) ok "H1a Stage P FAIL prints the intake shape" ;; *) bad "H1a Stage P FAIL prints the intake shape" ;; esac
markers=(); while IFS= read -r l; do case "$l" in Answered*|Unverified*|Assumed*) markers+=("$l") ;; esac; done <<<"$(ex intake)"
[ "${#markers[@]}" = 3 ] || bad "H1b three example markers in the hint" "${#markers[@]}"
answer_all "$P" "${markers[@]}"; gc "$P" P
[ "$rc" = 0 ] && ok "H1b the example markers pass Stage P (rc=0)" || bad "H1b the example markers pass Stage P" "rc=$rc $(stage P)"

echo "-- H2: build plan"
mkp; mkdir -p "$P/architecture/modules/Rooms"
printf '# Module brief — Rooms\n' > "$P/architecture/modules/Rooms/module-brief.md"
printf '| # | Kind | Step | Depends on |\n|---|---|---|---|\n| R01 | BUILD | Rooms domain model | — |\n| 2 | BUILD | Rooms pages | 1 |\n' > "$P/architecture/build-plan.md"
printf '| 4 | Build plan approved | CONFIRMED | |\n' >> "$P/PROJECT.md"
gc "$P"
case "$(stage 4)" in *FAIL*) ;; *) bad "H2 setup: Stage 4 should FAIL" "$(stage 4)" ;; esac
case "$out" in *"Accepted shape — architecture/build-plan.md"*) ok "H2a Stage 4 FAIL prints the build-plan shape" ;; *) bad "H2a Stage 4 FAIL prints the build-plan shape" ;; esac
{ printf '# Build plan\n\n'; ex build-plan | grep '^|'; } > "$P/architecture/build-plan.md"
awk '/^\| Stage \| Decision/ { print; getline; print; print "| 4 | Build plan approved | CONFIRMED | reviewed in chat |"; next } { print }' "$P/PROJECT.md" | grep -v '^| 4 | Build plan approved | CONFIRMED | |$' > "$P/PROJECT.tmp" && mv "$P/PROJECT.tmp" "$P/PROJECT.md"
gc "$P"
case "$(stage 4)" in *"PASS"*) ok "H2b the example plan passes Stage 4" ;; *) bad "H2b the example plan passes Stage 4" "$(stage 4)" ;; esac

echo "-- H3: coverage ledger"
mkp; mkdir -p "$P/architecture/modules/Rooms" "$P/analysis/rooms/knowledge-base/brd"
printf '# Module brief — Rooms\n' > "$P/architecture/modules/Rooms/module-brief.md"
{ printf '# Build plan\n\n'; ex build-plan | grep '^|'; } > "$P/architecture/build-plan.md"
awk '/^\| Stage \| Decision/ { print; getline; print; print "| 4 | Build plan approved | CONFIRMED | reviewed in chat |"; next } { print }' "$P/PROJECT.md" > "$P/PROJECT.tmp" && mv "$P/PROJECT.tmp" "$P/PROJECT.md"
printf '{"id":"F001","domainEntities":[{"name":"Room"}],"useCases":[{"id":"UC1","name":"Book","actor":"Staff"}]}\n' > "$P/analysis/rooms/knowledge-base/brd/F001.brd.json"
printf '| pointer | type | title | slice | writeMode | acceptance | status |\n|---|---|---|---|---|---|---|\n| /domainEntities/0/name | entity | Room | 1 | create | Room exists | row 2 |\n' > "$P/architecture/coverage-ledger.md"
gc "$P"
case "$(stage 4)" in *FAIL*"coverage ledger has findings"*) ;; *) bad "H3 setup: Stage 4 should FAIL on coverage" "$(stage 4)" ;; esac
case "$out" in *"Accepted shape — a coverage ledger"*) ok "H3a a coverage FAIL prints the ledger shape" ;; *) bad "H3a a coverage FAIL prints the ledger shape" ;; esac
ex coverage-ledger > "$P/architecture/coverage-ledger.md"
gc "$P"
case "$(stage 4)" in *PASS*"coverage ledger clean"*) ok "H3b the example ledger passes Stage 4's coverage measurement" ;; *) bad "H3b example ledger passes Stage 4" "$(stage 4)" ;; esac
mkdir -p "$WORK/cov"
printf '{"id":"F001","domainEntities":[{"name":"Room"}],"useCases":[{"id":"UC1","name":"Book","actor":"Staff"}]}\n' > "$WORK/cov/F001.brd.json"
ex coverage-ledger > "$WORK/cov/ledger.md"
bash "$TK/bin/coverage-check.sh" "$WORK/cov/F001.brd.json" "$WORK/cov/ledger.md" > "$WORK/cov/out" 2>&1 \
  && ok "H3c the same, straight through bin/coverage-check.sh (rc=0)" || bad "H3b example ledger clean" "$(cat "$WORK/cov/out")"
grep -q 'claims ONE element' <<<"$(mxtk_format_hint coverage-ledger)" && ok "H3 the shape states the one-element wildcard rule (SECTION-WIDE)" || bad "H3 one-element rule stated"

echo "-- H4: LOOK report"
mkp; mkdir -p "$P/docs/progress"
printf 'as-of\t2026-11-20T10:00:00Z\nmodule\tRooms\t2\t0\nunseen\tRooms.Room_Overview\t1000000000\nunseen\tRooms.Booking_New\t1000000000\n' > "$P/docs/progress/look-summary.tsv"
gc "$P"
case "$(stage 5)" in *FAIL*) ;; *) bad "H4 setup: Stage 5 should FAIL" "$(stage 5)" ;; esac
case "$out" in *"Accepted shape — a LOOK report"*) ok "H4a Stage 5 look FAIL prints the LOOK-report shape" ;; *) bad "H4a Stage 5 look FAIL prints the LOOK-report shape" ;; esac
mkdir -p "$P/design/ui-reviews/shots/2026-11-20"
head_sha="$(git -C "$P" rev-parse --short HEAD 2>/dev/null)"
ex look-report | sed "s/1a2b3c4/$head_sha/" | sed 's/$/<br>/' > "$P/design/ui-reviews/ui-review-2026-11-20-Rooms.html"
for f in $(ex look-report | sed -n 's/^PROOF-OF-LOOK:.*= *//p'); do shot "$P/design/ui-reviews/$f"; done
gc "$P"
case "$(stage 5)" in *"MANUAL"*"2 of 2 built page(s) accounted for"*"2 by PROOF-OF-LOOK"*) ok "H4b the example report clears both pages" ;; *) bad "H4b the example report clears both pages" "$(stage 5)" ;; esac

echo "-- H5: prototype LOOK"
mkp; mkdir -p "$P/design/ui-reviews/shots/2026-11-20"
printf '<!doctype html><title>prototype</title><p>rooms</p>\n' > "$P/design/prototype.html"
printf '4 of 4 screen-widths captured\nPROOF-OF-LOOK: rooms@390 = shots/2026-11-20/rooms-390.png\n' > "$P/design/ui-reviews/prototype-look-2026-11-20.html"
gc "$P"
ob="$(printf '%s\n' "$out" | grep -m1 '^Obligation prototype-look')"
case "$ob" in *FAULT*) ;; *) bad "H5 setup: prototype-look should FAULT" "$ob" ;; esac
case "$out" in *"Accepted shape — design/ui-reviews/prototype-look"*) ok "H5a the prototype-look FAULT prints its shape" ;; *) bad "H5a the prototype-look FAULT prints its shape" "$ob" ;; esac
sha="$(tr -d '\r' < "$P/design/prototype.html" | { sha256sum 2>/dev/null || shasum -a 256; } | awk '{print $1}')"
ex prototype-look | sed "s/<the sha256 [^>]*>/$sha/" > "$P/design/ui-reviews/prototype-look-2026-11-20.html"
for f in $(ex prototype-look | sed -n 's/^PROOF-OF-LOOK:.*= *//p'); do shot "$P/design/ui-reviews/$f"; done
gc "$P"
ob="$(printf '%s\n' "$out" | grep -m1 '^Obligation prototype-look')"
case "$ob" in *"PASS — 1 of 1"*) ok "H5b the example prototype report discharges the obligation" ;; *) bad "H5b the example prototype report discharges" "$ob" ;; esac

echo "-- H6: once per run"
mkp; mkdir -p "$P/docs/progress" "$P/design/ui-reviews" "$P/architecture/modules/Rooms"
printf '# Module brief — Rooms\n' > "$P/architecture/modules/Rooms/module-brief.md"   # opens Rooms: the look obligation FAULTs too
printf 'as-of\t2026-11-20T10:00:00Z\nunseen\tRooms.Room_Overview\t1000000000\n' > "$P/docs/progress/look-summary.tsv"
printf 'Rooms · 1 of 1 pages reviewed\n' > "$P/design/ui-reviews/ui-review-2026-11-20-Rooms.html"
gc "$P"
grep -q '^Obligation look .*FAULT' <<<"$out" || bad "H6 setup: the look obligation should FAULT" "$(printf '%s\n' "$out" | grep -m1 '^Obligation look')"
n="$(printf '%s\n' "$out" | grep -c 'Accepted shape — a LOOK report')"
[ "$n" = 1 ] && ok "H6 the LOOK-report shape prints once although Stage 5 and the look obligation both fail on it" || bad "H6 printed once" "n=$n"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
