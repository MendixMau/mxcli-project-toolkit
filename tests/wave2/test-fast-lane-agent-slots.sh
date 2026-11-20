#!/usr/bin/env bash
# test-fast-lane-agent-slots.sh — build-ready WARNs on {{…}} slots in agent stubs no role was
# dispatched with, and FAILs on mdl-agent's own slots once its dispatch log exists (#821 point 2).
#
# usage: bash tests/wave2/test-fast-lane-agent-slots.sh [path-to-gate-check.sh]
#   pass a master checkout's bin/gate-check.sh to see S1 fail there.
#
# Field basis: two simulated builds, 2026-11-20 (claude -p, stubbed Mendix tools): 0 subagents
# dispatched in either, yet build-ready FAILed on the six stubs' slots (POC once, requirements-
# driven twice, the second for a multi-line slot), costing 3 and 6 calls before the first write.
# The stubs are the real ones bin/init-project.sh installs.
#
#   S1  a scaffold whose only open build-ready item is the stubs' slots: verdict PASS, the slot
#       line is a ⚠ that still names the slots (multi-line {{PROJECT_LOCAL_SOURCES_OF_TRUTH…}} too)
#   S2  mdl-agent's dispatch log exists (.claude/loop/dispatch/<Module>/scripts.tsv): FAIL naming
#       mdl-agent and its slots
#   S3  mdl-agent filled, log present, the other five still unfilled: PASS, ⚠ for the rest
#   S4  every stub filled: the ✓ line, unchanged
set -uo pipefail

TK0="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK0/bin/gate-check.sh}"
case "$GATE" in /*) ;; *) GATE="$PWD/$GATE" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fast-lane-slots.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $GATE"

printf 'zz-no-client-name-zz\n' > "$WORK/deny"
MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" bash "$TK0/bin/init-project.sh" "$WORK/seed" >/dev/null 2>&1 </dev/null
[ -f "$WORK/seed/.claude/agents/mdl-agent.md" ] || { echo "init-project.sh installed no agent stubs"; exit 2; }
# Everything else build-ready asks for, so the slots are the only open item.
mkdir -p "$WORK/seed/architecture/modules/Rooms" "$WORK/seed/design/wireframes"
printf '# Module brief — Rooms\n\nScope: Room, Booking.\n' > "$WORK/seed/architecture/modules/Rooms/module-brief.md"
printf '<html><body>Rooms</body></html>\n' > "$WORK/seed/design/wireframes/Rooms_Overview.html"
printf ':root { --mxt-accent: #0a5; }\n' > "$WORK/seed/design/ds.css"

N=0
mkp() { N=$((N+1)); P="$WORK/p$N"; cp -R "$WORK/seed" "$P"; }
gc() { out="$(bash "$GATE" --no-html "$P" build-ready 2>&1)"; rc=$?; slot="$(printf '%s\n' "$out" | grep 'unfilled')"; }
fill() { perl -0777 -pi -e 's/\{\{(?!DOUBLE_BRACE\}\})[A-Z][^{}]*?\}\}/filled/sg' "$@"; }
log_dispatch() { mkdir -p "$P/.claude/loop/dispatch/Rooms"; printf '2026-11-20\tmdlsource/01-domain.mdl\tcheck ok\n' > "$P/.claude/loop/dispatch/Rooms/scripts.tsv"; }

echo "-- S1: no role dispatched"
mkp; gc
grep -q '^BUILD-READY: PASS' <<<"$out" && ok "S1 verdict PASS with only the stubs' slots open" || bad "S1 verdict PASS" "$(printf '%s\n' "$out" | grep '^BUILD-READY')"
case "$slot" in *"⚠ agent(s) still have unfilled placeholders: {{"*) ok "S1 the slot line is a warning" ;; *) bad "S1 the slot line is a warning" "$slot" ;; esac
case "$slot" in *"{{PROJECT_LOCAL_SOURCES_OF_TRUTH…}}"*) ok "S1 the multi-line slot is still named" ;; *) bad "S1 the multi-line slot is still named" "$slot" ;; esac

echo "-- S2: mdl-agent dispatched, its stub unfilled"
mkp; log_dispatch; gc
grep -q '^BUILD-READY: FAIL' <<<"$out" && ok "S2 verdict FAIL once mdl-agent's dispatch log exists" || bad "S2 verdict FAIL" "$(printf '%s\n' "$out" | grep '^BUILD-READY')"
case "$slot" in *"✗ mdl-agent is dispatched"*"{{PROJECT_LOCAL_SOURCES_OF_TRUTH…}}"*) ok "S2 the FAIL names mdl-agent and its slots" ;; *) bad "S2 the FAIL names mdl-agent" "$slot" ;; esac

echo "-- S3: mdl-agent filled, the rest not"
mkp; log_dispatch; fill "$P/.claude/agents/mdl-agent.md"; gc
grep -q '^BUILD-READY: PASS' <<<"$out" && ok "S3 PASS: the dispatched role is filled" || bad "S3 PASS" "$(printf '%s\n' "$out" | grep -E '^BUILD-READY|✗')"
case "$slot" in *"⚠ agent(s) still have unfilled"*) ok "S3 the other roles' slots still warn" ;; *) bad "S3 the other roles' slots still warn" "$slot" ;; esac

echo "-- S4: every stub filled"
mkp; fill "$P"/.claude/agents/*.md; gc
case "$out" in *"✓ all 6 agents present, no unfilled placeholders"*) ok "S4 a filled set reads clean" ;; *) bad "S4 a filled set reads clean" "$slot" ;; esac

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
