#!/usr/bin/env bash
# test-marketplace-install.sh — the install check for confirmed fit-gap "Buy" rows
# (bin/lib/marketplace-check.sh), its Stage 5 fold in bin/gate-check.sh, and
# `--waive marketplace/<Name>`.
#
# Usage: bash tests/wave2/test-marketplace-install.sh [path-to-gate-check.sh]
#
# GOLDEN INPUT, never hand-written: the SHOW MODULES table is a verbatim mxcli capture —
# tests/wave2/fixtures/show-modules/ (v0.29.0; provenance in its CAPTURE.txt) and
# tests/wave2/fixtures/rehost-list-modules/field-service-template-9.24.2.txt (v0.26.0, 16
# Marketplace modules). The stub mxcli below only REPLAYS a capture file; it asserts it was
# asked `-p <the project's .mpr> -c "SHOW MODULES"` and exits 9 otherwise.
#
#   T1  Buy `MyFirstModule`, capture "Marketplace v2.1.0, Protected AddOn"      -> PASS
#   T2  field-service capture, Buy `Administration` + `Atlas_Core`              -> PASS 2 of 2
#   T3  Buy `Encryption`, not in the model -> FAIL naming it + its search command;
#       gate-check Stage 5 FAILs with it and `gate-check <p> 5` exits non-zero
#   T4  Buy `MyFirstModule`, capture with Source empty (own module) -> FAIL "not Marketplace"
#   T5  widget-only Buy `Charts` with widgets/Charts.mpk, no mxcli at all     -> PASS
#   T6  PENDING: no fit-gap; Buy only "decide if needed"; no .mpr; no mxcli; unnamed Buy
#   T7  0 Buy rows -> PASS "0 of 0"
#   T8  --waive marketplace/Encryption writes the register line -> T3's project PASS (1 waived);
#       bare --waive marketplace -> WAIVED
#   T9  --adopt 6 -> ADOPTED; --adopt 5 -> still checked (FAIL)
#   T10 two-tree layout (app/App.mpr, app/widgets/) -> same verdicts as single-tree
#   T11 `gate-check <p> 3` does not evaluate it (no Marketplace line, mxcli never called)
#   T12 bin/doctor.sh (beside the subject): a confirmed Buy prints the "Marketplace login: not
#       checked" note naming the PAT guide — a note, never WARN/FAIL; nothing under --quick or
#       with no Buy row
# Keep bash-3.2 compatible.
set -uo pipefail

GC="${1:-$(cd "$(dirname "$0")/../.." && pwd)/bin/gate-check.sh}"
GC="$(cd "$(dirname "$GC")" && pwd)/$(basename "$GC")"
LIB="$(dirname "$GC")/lib/marketplace-check.sh"
[ -r "$LIB" ] || { echo "test-marketplace-install: FAIL — no $LIB (the check does not exist here)"; exit 1; }
FXD="$(cd "$(dirname "$0")" && pwd)/fixtures"
CAP_MKT="$FXD/show-modules/show-modules-marketplace-protected-v0.29.0.out"
CAP_SRC="$FXD/show-modules/show-modules-source-v0.29.0.out"
CAP_FS="$FXD/rehost-list-modules/field-service-template-9.24.2.txt"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mkt-inst.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# mkproj <name> <capture|-> <layout: root|app> <fit-gap rows...>
mkproj() {
  local d="$WORK/$1" cap="$2" lay="$3" m; shift 3
  mkdir -p "$d/architecture"
  printf '# PROJECT\n\n## Current stage\n**Stage P — Kickoff**\n' > "$d/PROJECT.md"
  if [ "$#" -gt 0 ]; then
    { printf '# Fit-gap\n\n| Source capability | Mendix approach | Verdict | Open issue? |\n|---|---|---|---|\n'
      printf '| CRUD grid | Data Grid 2 (native) | **Native** | — |\n'
      for r in "$@"; do printf '%s\n' "$r"; done; } > "$d/architecture/fit-gap.md"
  fi
  m="$d"; [ "$lay" = app ] && m="$d/app"
  mkdir -p "$m"; : > "$m/App.mpr"
  if [ "$cap" != - ]; then
    printf '#!/bin/sh\n[ "$1" = "-p" ] && [ "$2" = "%s" ] && [ "$3" = "-c" ] && [ "$4" = "SHOW MODULES" ] || exit 9\ncat "%s"\n' \
      "$m/App.mpr" "$cap" > "$d/mxcli"
    chmod +x "$d/mxcli"
  fi
  printf '%s\n' "$d"
}
lib() { env -u MXCLI -u MPR_FILE bash "$LIB" "$1"; }
gc()  { env -u MXCLI -u MPR_FILE MXTK_GATE_CACHE_TTL_MIN=0 bash "$GC" --no-html "$@" 2>&1; }

echo "== T1: confirmed Buy present as a Marketplace module =="
P="$(mkproj t1 "$CAP_MKT" root '| crypto helpers | `MyFirstModule` module (marketplace) | **Buy** | — |')"
V="$(lib "$P")"
case "$V" in "Marketplace installs: PASS — 1 of 1 confirmed Buy installed") ok "$V" ;; *) bad "T1: $V" ;; esac

echo "== T2: field-service capture (16 Marketplace modules) =="
P="$(mkproj t2 "$CAP_FS" root '| admin | `Administration` module | **Buy** | — |' '| theme | `Atlas_Core` module | **Buy** | — |')"
V="$(lib "$P")"
case "$V" in *"PASS — 2 of 2 confirmed Buy installed") ok "$V" ;; *) bad "T2: $V" ;; esac

echo "== T3: confirmed Buy missing -> FAIL naming it; Stage 5 FAILs =="
P3="$(mkproj t3 "$CAP_MKT" root '| crypto helpers | `MyFirstModule` module | **Buy** | — |' '| field encryption | `Encryption` module (marketplace) | **Buy** | — |')"
V="$(lib "$P3")"
case "$V" in *"FAIL — 1 of 2 confirmed Buy installed; NOT INSTALLED: Encryption"*'mxcli marketplace search "Encryption"'*) ok "lib FAIL names Encryption and its search command" ;; *) bad "T3 lib: $V" ;; esac
OUT="$(gc "$P3" 5)"; RC=$?
printf '%s\n' "$OUT" | grep -q '^Stage 5 (.*): FAIL.*marketplace: 1 of 2 confirmed Buy installed; NOT INSTALLED: Encryption' \
  && ok "Stage 5 FAILs with the install message" || bad "T3 Stage 5 line: $(printf '%s\n' "$OUT" | grep '^Stage 5')"
[ "$RC" -ne 0 ] && ok "gate-check <p> 5 exits non-zero ($RC)" || bad "T3: gate-check <p> 5 exited 0"

echo "== T4: module present but Source empty (own module) =="
P="$(mkproj t4 "$CAP_SRC" root '| crypto helpers | `MyFirstModule` module | **Buy** | — |')"
V="$(lib "$P")"
case "$V" in *"FAIL — 0 of 1"*"MyFirstModule (in the model, but its SHOW MODULES Source is not"*) ok "own-module copy is not an install" ;; *) bad "T4: $V" ;; esac

echo "== T5: widget-only package by its .mpk, no mxcli =="
P="$(mkproj t5 - root '| charts | `Charts` widget (marketplace) | **Buy** | — |')"
mkdir -p "$P/widgets"; printf 'PK' > "$P/widgets/Charts.mpk"
V="$(lib "$P")"
case "$V" in *"PASS — 1 of 1 confirmed Buy installed") ok "$V" ;; *) bad "T5: $V" ;; esac

echo "== T6: PENDING cases =="
P="$(mkproj t6a "$CAP_MKT" root)"           # no fit-gap rows -> no file
V="$(lib "$P")"; case "$V" in *"PENDING — no architecture/fit-gap.md yet"*) ok "no fit-gap: PENDING" ;; *) bad "T6a: $V" ;; esac
P="$(mkproj t6b "$CAP_MKT" root '| maps | `Maps` (marketplace) | **Buy** — decide if needed | maybe |')"
V="$(lib "$P")"; case "$V" in *"PENDING — 1 Buy row(s)"*"not yet confirmed"*) ok "unresolved Buy: PENDING" ;; *) bad "T6b: $V" ;; esac
P="$(mkproj t6c "$CAP_MKT" root '| crypto | `Encryption` module | **Buy** | — |')"; rm -f "$P/App.mpr"
V="$(lib "$P")"; case "$V" in *"PENDING — 0 of 1"*"no model yet"*Encryption*) ok "no model: PENDING, names it" ;; *) bad "T6c: $V" ;; esac
P="$(mkproj t6d - root '| crypto | `Encryption` module | **Buy** | — |')"
V="$(lib "$P")"; case "$V" in *"PENDING — no project mxcli"*Encryption*) ok "no mxcli: PENDING, not FAIL" ;; *) bad "T6d: $V" ;; esac
P="$(mkproj t6e "$CAP_MKT" root '| crypto | Encryption module | **Buy** | — |')"
V="$(lib "$P")"; case "$V" in *PENDING*"name no package"*) ok "unnamed Buy: PENDING with the naming rule" ;; *) bad "T6e: $V" ;; esac
OUT="$(gc "$P" 5)"
printf '%s\n' "$OUT" | grep '^Stage 5 (' | grep -q 'marketplace' && bad "T6e: a PENDING install check leaked into Stage 5" || ok "PENDING leaves Stage 5 alone"

echo "== T7: no Buy row at all =="
P="$(mkproj t7 "$CAP_MKT" root '| roles | Administration module | **Config** | — |')"
V="$(lib "$P")"; case "$V" in *"PASS — 0 of 0"*) ok "$V" ;; *) bad "T7: $V" ;; esac

echo "== T8: waivers via gate-check --waive marketplace[/<Name>] =="
gc --waive marketplace/Encryption --reason "client admin installs it" "$P3" >/dev/null
grep -q '^Waived marketplace Encryption: client admin installs it' "$P3/PROJECT.md" && ok "register line written" || bad "T8: no register line: $(grep -i waived "$P3/PROJECT.md")"
V="$(lib "$P3")"; case "$V" in *"PASS — 1 of 1 confirmed Buy installed (1 waived)") ok "$V" ;; *) bad "T8a: $V" ;; esac
gc --waive marketplace --reason "all by the client" "$P3" >/dev/null
P8="$(mkproj t8 - root '| crypto | `Encryption` module | **Buy** | — |')"
printf 'Waived marketplace: all by the client\n' >> "$P8/PROJECT.md"
V="$(lib "$P8")"; case "$V" in *"WAIVED — all 1 confirmed Buy package(s) waived"*) ok "bare waiver: WAIVED" ;; *) bad "T8b: $V" ;; esac

echo "== T9: adoption =="
P="$(mkproj t9a "$CAP_MKT" root '| crypto | `Encryption` module | **Buy** | — |')"
gc --adopt 6 --reason "joined at Stage 6" "$P" >/dev/null
V="$(lib "$P")"; case "$V" in *"ADOPTED"*) ok "adopted at 6: ADOPTED" ;; *) bad "T9a: $V" ;; esac
P="$(mkproj t9b "$CAP_MKT" root '| crypto | `Encryption` module | **Buy** | — |')"
gc --adopt 5 --reason "joined at the build" "$P" >/dev/null
V="$(lib "$P")"; case "$V" in *"FAIL"*Encryption*) ok "adopted at 5: still owed (FAIL)" ;; *) bad "T9b: $V" ;; esac

echo "== T10: two-tree layout (app/App.mpr) =="
P="$(mkproj t10 "$CAP_MKT" app '| crypto helpers | `MyFirstModule` module | **Buy** | — |' '| charts | `Charts` widget | **Buy** | — |' '| pdf | `Encryption` module | **Buy** | — |')"
mkdir -p "$P/app/widgets"; printf 'PK' > "$P/app/widgets/Charts.mpk"
V="$(lib "$P")"; case "$V" in *"FAIL — 2 of 3 confirmed Buy installed; NOT INSTALLED: Encryption"*"-p App.mpr"*) ok "two-tree: module + widget found, Encryption missing" ;; *) bad "T10: $V" ;; esac

echo "== T11: a stage query below 5 does not evaluate it =="
P="$(mkproj t11 - root '| crypto | `Encryption` module | **Buy** | — |')"
printf '#!/bin/sh\ntouch "%s/CALLED"\nexit 1\n' "$P" > "$P/mxcli"; chmod +x "$P/mxcli"
OUT="$(gc "$P" 3)"
printf '%s\n' "$OUT" | grep -q '^Marketplace installs:' && bad "T11: evaluated on a Stage 3 query" || ok "no Marketplace line on gate-check <p> 3"
[ -e "$P/CALLED" ] && bad "T11: mxcli was called" || ok "mxcli not called"

echo "== T12: doctor names the PAT guide for a confirmed Buy; note only, never WARN; not under --quick =="
DOC="$(dirname "$GC")/doctor.sh"
OUT="$(MXTK_DOCTOR_SKIP_DOCKER=1 bash "$DOC" --no-docker "$P3" 2>&1)"
printf '%s\n' "$OUT" | grep -q '^        Marketplace login: not checked' && ok "full run: 'Marketplace login: not checked' note" || bad "T12: no login note"
printf '%s\n' "$OUT" | grep -q 'learned-constants-and-secrets.md § "Creating a PAT for Marketplace installs"' && ok "names the guide" || bad "T12: guide not named"
printf '%s\n' "$OUT" | grep -E '^  (WARN|FAIL) ' | grep -qi 'marketplace' && bad "T12: a WARN/FAIL about marketplace" || ok "no WARN/FAIL line about marketplace"
OUT="$(bash "$DOC" --quick "$P3" 2>&1)"
printf '%s\n' "$OUT" | grep -q 'Marketplace login' && bad "T12: printed under --quick" || ok "skipped under --quick"
P="$(mkproj t12 - root '| roles | Administration module | **Config** | — |')"
OUT="$(MXTK_DOCTOR_SKIP_DOCKER=1 bash "$DOC" --no-docker "$P" 2>&1)"
printf '%s\n' "$OUT" | grep -q 'Marketplace login' && bad "T12: printed with no Buy row" || ok "silent with no Buy row"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
