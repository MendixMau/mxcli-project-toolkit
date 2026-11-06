#!/usr/bin/env bash
# test-marketplace-install.sh — the install check for confirmed fit-gap "Buy" rows
# (bin/lib/marketplace-check.sh), where it blocks (gate-check build-ready, exec.sh before a
# domain-model script — never a Stage 5 verdict), and `--waive marketplace/<Name>`.
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
#       build-ready counts it (✗ Marketplace); Stage 5's verdict is NOT changed by it
#   T4  Buy `MyFirstModule`, capture with Source empty -> PASS with the "imported from file?"
#       note (guard rule 6: the module is there, evidence the gate did not create)
#   T5  widget-only Buy `Charts` with widgets/Charts.mpk, no mxcli at all     -> PASS
#   T6  PENDING: no fit-gap; Buy only "decide if needed"; no .mpr; no mxcli; unnamed Buy
#   T7  0 Buy rows -> PASS "0 of 0" naming the rows and tables it parsed
#   T8  --waive marketplace/Encryption writes the register line -> T3's project PASS (1 waived);
#       bare --waive marketplace writes "Waived marketplace: ..." -> T3's project WAIVED
#   T9  --adopt 6 -> ADOPTED; --adopt 5 -> still checked (FAIL)
#   T10 two-tree layout (app/App.mpr, app/widgets/) -> same verdicts as single-tree
#   T11 `gate-check <p> 3` does not evaluate it (no Marketplace line, mxcli never called)
#   T12 bin/doctor.sh (beside the subject): a confirmed Buy prints the "Marketplace login: not
#       checked" note naming the PAT guide — a note, never WARN/FAIL; nothing under --quick or
#       with no Buy row
#   T13 REAL fit-gap shapes, rows copied verbatim from the s3ab puffin runs (a synthetic demo
#       project, not client data) — each failed on head 671c2c7b (false FAIL / false PASS):
#       a "Buy (unverified)" (PA1 §D)                  -> PENDING not resolved, never FAIL on `sandbox`
#       b "Buy + Build" (PA1 §C)                       -> PENDING not resolved
#       c "Buy decision: none, ..." (S3)               -> PENDING not resolved
#       d "**Native** if ...; otherwise **Buy**" (S1)  -> PENDING not resolved
#       e header "Build/Buy/Config/Gap" (PA3 §B, rows G1 G2 G4) -> 2 rows not resolved, not "0 of 0"
#       f header "Decision now" (PA3 summary) + PA1 DEP-05's "Buy (deferred, out of POC scope)"
#         (the nearest real cell to "deferred, not for POC") -> PENDING not resolved
#       g PA3 summary table alone (Decision header, no Buy row) -> PASS 0 of 0, 4 rows, 1 table
#       h no table with a verdict column at all        -> PENDING, never "PASS 0 of 0"
#       i mixed: confirmed `MyFirstModule` installed + PA1 "Buy (unverified)" -> PENDING with
#         "confirmed: 1 of 1 confirmed Buy installed" alongside
#       j mixed: confirmed `Encryption` missing + an unresolved row -> FAIL (dominates)
#   T14 project-bin/exec.sh (beside the subject): a domain-model script is refused on a FAIL,
#       before the snapshot; a PASS goes on and is remembered (.claude/loop/marketplace-ok.txt,
#       next exec does not read SHOW MODULES); a non-domain script is not checked;
#       PENDING warns and goes on; MXTK_MKT_OVERRIDE lets it through and lands in BUILD-LOG
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

echo "== T3: confirmed Buy missing -> FAIL naming it; build-ready counts it; Stage 5 untouched =="
P3="$(mkproj t3 "$CAP_MKT" root '| crypto helpers | `MyFirstModule` module | **Buy** | — |' '| field encryption | `Encryption` module (marketplace) | **Buy** | — |')"
V="$(lib "$P3")"
case "$V" in *"FAIL — 1 of 2 confirmed Buy installed; NOT INSTALLED: Encryption"*'mxcli marketplace search "Encryption"'*) ok "lib FAIL names Encryption and its search command" ;; *) bad "T3 lib: $V" ;; esac
OUT="$(gc "$P3" 5)"
printf '%s\n' "$OUT" | grep -q '^Marketplace installs: FAIL' && ok "gate-check prints the FAIL on its own line" || bad "T3: no Marketplace line"
S5="$(printf '%s\n' "$OUT" | grep '^Stage 5 (')"
printf '%s\n' "$S5" | grep -qi 'marketplace' && bad "T3: Stage 5 verdict carries the marketplace FAIL: $S5" || ok "Stage 5 verdict untouched by it"
P3T="$(mkproj t3twin "$CAP_MKT" root '| roles | Administration module | **Config** | — |')"
S5T="$(gc "$P3T" 5 | grep '^Stage 5 (')"
[ -n "$S5" ] && [ "$S5" = "$S5T" ] && ok "Stage 5 line identical to a twin with no Buy" || bad "T3: Stage 5 differs: [$S5] vs [$S5T]"
OUT="$(gc "$P3" build-ready)"; RC=$?
printf '%s\n' "$OUT" | grep -q '^  ✗ Marketplace: 1 of 2 confirmed Buy installed; NOT INSTALLED: Encryption' && ok "build-ready counts it (✗ Marketplace)" || bad "T3 build-ready: $(printf '%s\n' "$OUT" | grep -i marketplace)"
[ "$RC" -ne 0 ] && ok "build-ready exits non-zero ($RC)" || bad "T3: build-ready exited 0"
OUT="$(gc "$P3T" build-ready)"
printf '%s\n' "$OUT" | grep -q '^  ✓ Marketplace: PASS' && ok "build-ready: ✓ Marketplace on no Buy" || bad "T3 twin build-ready: $(printf '%s\n' "$OUT" | grep -i marketplace)"

echo "== T4: module present but Source empty (own module) =="
P="$(mkproj t4 "$CAP_SRC" root '| crypto helpers | `MyFirstModule` module | **Buy** | — |')"
V="$(lib "$P")"
case "$V" in *"PASS — 1 of 1 confirmed Buy installed; MyFirstModule present, Source empty — imported from file?"*) ok "present with empty Source: PASS with a note" ;; *) bad "T4: $V" ;; esac

echo "== T5: widget-only package by its .mpk, no mxcli =="
P="$(mkproj t5 - root '| charts | `Charts` widget (marketplace) | **Buy** | — |')"
mkdir -p "$P/widgets"; printf 'PK' > "$P/widgets/Charts.mpk"
V="$(lib "$P")"
case "$V" in *"PASS — 1 of 1 confirmed Buy installed") ok "$V" ;; *) bad "T5: $V" ;; esac

echo "== T6: PENDING cases =="
P="$(mkproj t6a "$CAP_MKT" root)"           # no fit-gap rows -> no file
V="$(lib "$P")"; case "$V" in *"PENDING — no architecture/fit-gap.md yet"*) ok "no fit-gap: PENDING" ;; *) bad "T6a: $V" ;; esac
P="$(mkproj t6b "$CAP_MKT" root '| maps | `Maps` (marketplace) | **Buy** — decide if needed | maybe |')"
V="$(lib "$P")"; case "$V" in *"PENDING — 1 Buy row(s)"*"not resolved"*"exactly **Buy**"*) ok "unresolved Buy: PENDING" ;; *) bad "T6b: $V" ;; esac
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
V="$(lib "$P")"; case "$V" in *"PASS — 0 of 0: 2 row(s) in 1 verdict table(s)"*) ok "$V" ;; *) bad "T7: $V" ;; esac

echo "== T8: waivers via gate-check --waive marketplace[/<Name>] =="
gc --waive marketplace/Encryption --reason "client admin installs it" "$P3" >/dev/null
grep -q '^Waived marketplace Encryption: client admin installs it' "$P3/PROJECT.md" && ok "register line written" || bad "T8: no register line: $(grep -i waived "$P3/PROJECT.md")"
V="$(lib "$P3")"; case "$V" in *"PASS — 1 of 1 confirmed Buy installed (1 waived)") ok "$V" ;; *) bad "T8a: $V" ;; esac
gc --waive marketplace --reason "all by the client" "$P3" >/dev/null
grep -q '^Waived marketplace: all by the client' "$P3/PROJECT.md" && ok "bare --waive marketplace: register line written" || bad "T8: no bare line: $(grep -i waived "$P3/PROJECT.md")"
V="$(lib "$P3")"; case "$V" in *"WAIVED — all 2 confirmed Buy package(s) waived"*) ok "bare --waive marketplace: T3's project WAIVED" ;; *) bad "T8 bare: $V" ;; esac
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

# mkraw <name> <capture|-> — a project whose fit-gap.md is stdin, verbatim.
mkraw() {
  local d="$WORK/$1" cap="$2"
  mkdir -p "$d/architecture"
  printf '# PROJECT\n\n## Current stage\n**Stage P — Kickoff**\n' > "$d/PROJECT.md"
  cat > "$d/architecture/fit-gap.md"
  : > "$d/App.mpr"
  if [ "$cap" != - ]; then
    printf '#!/bin/sh\n[ "$1" = "-p" ] && [ "$2" = "%s" ] && [ "$3" = "-c" ] && [ "$4" = "SHOW MODULES" ] || exit 9\ncat "%s"\n' \
      "$d/App.mpr" "$cap" > "$d/mxcli"
    chmod +x "$d/mxcli"
  fi
  printf '%s\n' "$d"
}
# Header and rows copied verbatim from the s3ab puffin runs' architecture/fit-gap.md.
H_V='| Source capability | Mendix approach | Verdict | Note |
|---|---|---|---|'
R_UNVER='| Iframe widget choice | Marketplace iframe pluggable widget supporting the `sandbox` attribute; verify with `mxcli marketplace search` in build-plan Step 0; fall back to a small custom pluggable widget | Buy (unverified) | OI-02, DEP-04 |'
R_BB='| SecurePreview | Version_Preview snippet containing the sandboxed iframe widget | Buy + Build | widget choice is OI-02 |'
R_NONE='| Sandboxed HTML viewer (iframe sandbox=allow-scripts) | HTML/JavaScript snippet widget with iframe, sandbox attribute | Buy decision: none, small custom snippet | ASSUMED F004-Q1 (scroll auto-hide nice-to-have) |'
R_OTHERWISE='| Sandboxed iframe render | HTML/JavaScript snippet widget with `sandbox` attribute, no same-origin | **Native** if a widget allows `sandbox`; otherwise **Buy** (marketplace HTML element) | open: widget choice at Stage 4 |'
H_BBCG='| # | Source capability | Mendix approach | Build/Buy/Config/Gap | Notes |
|---|---|---|---|---|'
R_G1='| G1 | F001 Dashboard management: list, create, open, delete (UC001-UC004) | Entity `Dashboard`, pages `Dashboard_Overview`, `Dashboard_New`, `Dashboard_Detail`; microflows from E01-E04 | Build | Native list view / Data Grid 2 and Atlas page templates; no marketplace import. Delete is new UI (F001-Q1). |'
R_G2='| G2 | F002 Version publishing: upload, preview, delete (UC005-UC007) | Entity `DashboardVersion` specialising System.FileDocument; `Version_Upload`, `Version_Preview` | Build + Buy (decide) | Marketplace candidate: a file-upload widget (e.g. "File Uploader") for drag-and-drop and size pre-check; the built-in File Manager / Document widget is sufficient for the POC, so default is Config, no import. |'
R_G4='| G4 | F004 Dashboard viewing: sandboxed render, version picker, no-access page (UC011-UC013) | Page `Dashboard_View` with an iframe/HTML-viewer widget bound to the content URL, `sandbox="allow-scripts"`; version picker; error state for UC013 | Buy (decide) / Gap | Marketplace candidates: an iframe widget (e.g. "Iframe", "HTML Element" / "Html Viewer") that exposes the sandbox attribute. |'
H_DEC='| Candidate | For | Decision now | Confirm at |
|---|---|---|---|'
R_SUMMARY='| Iframe / HTML-viewer widget exposing `sandbox` | G4, E09 | Needed - candidate search required; custom pluggable widget is the fallback | Stage 4 Step 0 |
| File-upload widget | G2, E07 | Not needed for POC (built-in File Manager / Document widget); optional | Stage 4 Step 0 |
| OIDC SSO module | G5 (production only) | Deferred, out of scope (F005-Q2) | After POC |
| Data Grid 2, Atlas, Administration | G1, G6 | Ship with Mendix; no import | - |'
R_DEFER='| OIDC SSO module | G5 (production only) | Buy (deferred, out of POC scope) | After POC |'
unres() { case "$2" in *"PENDING — $3 Buy row(s) in architecture/fit-gap.md not resolved"*"exactly **Buy**"*"non-Buy verdict"*) ok "$1: PENDING, $3 not resolved, says how to resolve" ;; *) bad "$1: $2" ;; esac; }

echo "== T13: real fit-gap shapes (s3ab puffin runs) =="
P="$(printf '%s\n%s\n' "$H_V" "$R_UNVER" | mkraw t13a "$CAP_MKT")"; V="$(lib "$P")"
unres "T13a Buy (unverified)" "$V" 1
case "$V" in *sandbox*NOT*|*FAIL*) bad "T13a: read \`sandbox\` as a package: $V" ;; *) ok "T13a: \`sandbox\` is not taken for a package" ;; esac
P="$(printf '%s\n%s\n' "$H_V" "$R_BB" | mkraw t13b "$CAP_MKT")"; unres "T13b Buy + Build" "$(lib "$P")" 1
P="$(printf '%s\n%s\n' "$H_V" "$R_NONE" | mkraw t13c "$CAP_MKT")"; unres "T13c Buy decision: none" "$(lib "$P")" 1
P="$(printf '%s\n%s\n' "$H_V" "$R_OTHERWISE" | mkraw t13d "$CAP_MKT")"; unres "T13d Native ... otherwise Buy" "$(lib "$P")" 1
P="$(printf '%s\n%s\n%s\n%s\n' "$H_BBCG" "$R_G1" "$R_G2" "$R_G4" | mkraw t13e "$CAP_MKT")"; unres "T13e Build/Buy/Config/Gap header" "$(lib "$P")" 2
P="$(printf '%s\n%s\n%s\n' "$H_DEC" "$R_SUMMARY" "$R_DEFER" | mkraw t13f "$CAP_MKT")"; unres "T13f Decision header + deferred Buy" "$(lib "$P")" 1
P="$(printf '%s\n%s\n' "$H_DEC" "$R_SUMMARY" | mkraw t13g "$CAP_MKT")"; V="$(lib "$P")"
case "$V" in *"PASS — 0 of 0: 4 row(s) in 1 verdict table(s)"*) ok "T13g Decision table, no Buy: $V" ;; *) bad "T13g: $V" ;; esac
P="$(printf '# Fit-gap\n\nMarketplace: **Buy** nothing for the POC.\n\n| ID | Item | Type |\n|---|---|---|\n| FG-1 | Response headers | Gap / Buy decision |\n' | mkraw t13h "$CAP_MKT")"; V="$(lib "$P")"
case "$V" in *"PENDING — no table in architecture/fit-gap.md has a Verdict / Decision"*) ok "T13h no verdict table: PENDING" ;; *) bad "T13h: $V" ;; esac
P="$(printf '%s\n%s\n%s\n' "$H_V" '| crypto helpers | `MyFirstModule` module (marketplace) | **Buy** | — |' "$R_UNVER" | mkraw t13i "$CAP_MKT")"; V="$(lib "$P")"
case "$V" in *"PENDING — 1 Buy row(s)"*"not resolved"*"; confirmed: 1 of 1 confirmed Buy installed") ok "T13i mixed: PENDING with the confirmed result alongside" ;; *) bad "T13i: $V" ;; esac
P="$(printf '%s\n%s\n%s\n' "$H_V" '| field encryption | `Encryption` module (marketplace) | **Buy** | — |' "$R_BB" | mkraw t13j "$CAP_MKT")"; V="$(lib "$P")"
case "$V" in *"FAIL — 0 of 1 confirmed Buy installed; NOT INSTALLED: Encryption"*"also 1 Buy row(s)"*"not resolved"*) ok "T13j mixed with a missing confirmed Buy: FAIL dominates" ;; *) bad "T13j: $V" ;; esac

echo "== T14: exec.sh refuses a domain-model script on a FAIL, before the snapshot =="
TK="$(cd "$(dirname "$GC")/.." && pwd)"
EXEC_SH="$TK/project-bin/exec.sh"
mkexec() {  # $1 = dir, $2 = capture, $3 = fit-gap Buy row
  local E="$1"; mkdir -p "$E/bin" "$E/mprcontents/84/77" "$E/architecture" "$E/.claude" "$WORK/jdk/bin"
  printf 'not a real model\n' > "$E/Fixture.mpr"
  printf 'bson\n' > "$E/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
  cp "$TK/project-bin/_common.sh" "$TK/project-bin/restore-mpr.sh" "$EXEC_SH" "$E/bin/"
  cat > "$E/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/Fixture.mpr"; cp -r mprcontents "$D/mprcontents"
echo "Snapshot saved: $D"
SNAP
  chmod +x "$E/bin/"*.sh
  # Replays the SHOW MODULES capture (and counts the reads); every other mxcli call succeeds.
  printf '#!/bin/sh\nif [ "$3" = "-c" ] && [ "$4" = "SHOW MODULES" ]; then echo x >> "%s/SHOWN"; cat "%s"; exit 0; fi\nexit 0\n' "$E" "$2" > "$E/mxcli"
  chmod +x "$E/mxcli"
  printf 'CREATE PERSISTENT ENTITY Orders.Thing (Name: String(50));\n' > "$E/domain.mdl"
  printf 'CREATE MODULE "Orders";\n' > "$E/scaffold.mdl"
  printf '# Build plan\n\n## Module brief - Orders\n' > "$E/architecture/build-plan.md"
  printf '%s\n%s\n' "$H_V" "$3" > "$E/architecture/fit-gap.md"
  printf '# PROJECT\n' > "$E/PROJECT.md"
}
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
mkdir -p "$WORK/jdk/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"
runx() {  # $1 = project dir, rest = exec.sh args; output in $WORK/xout
  local E="$1"; shift
  ( cd "$E" && { [ -d .git ] || git init -q . 2>/dev/null; }; git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm fx >/dev/null 2>&1
    mkdir -p "$WORK/tmp"
    env -u MXCLI -u MPR_FILE MXTK_ROOT="$TK" TMPDIR="$WORK/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
      JAVA_HOME="$WORK/jdk" "$@" ) > "$WORK/xout" 2>&1
}
snaps() { find "$1/.mpr-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
if [ ! -f "$EXEC_SH" ]; then
  bad "T14: no $EXEC_SH beside the subject"
else
  E="$WORK/x1"; mkexec "$E" "$CAP_MKT" '| field encryption | `Encryption` module (marketplace) | **Buy** | — |'
  runx "$E" ./bin/exec.sh domain.mdl; RC=$?
  grep -q '✗ Marketplace install gate: refusing' "$WORK/xout" && ok "FAIL: domain-model script refused" || bad "T14 not refused (rc $RC)" 
  [ "$RC" -ne 0 ] && ok "refusal exits non-zero ($RC)" || bad "T14: refusal exited 0"
  [ "$(snaps "$E")" = 0 ] && ok "nothing snapshotted" || bad "T14: a snapshot was taken"
  grep -q 'gate-check.sh --waive marketplace/<Name>' "$WORK/xout" && ok "remedy names the waiver" || bad "T14: no waiver in the remedy"
  grep -q 'marketplace install gate' "$E/docs/BUILD-LOG.md" 2>/dev/null && ok "BUILD-LOG row written" || bad "T14: no BUILD-LOG row"
  runx "$E" ./bin/exec.sh scaffold.mdl; RC=$?
  grep -q 'Marketplace install gate' "$WORK/xout" && bad "T14: a non-domain script was checked" || ok "non-domain script not checked (rc $RC)"
  runx "$E" env MXTK_MKT_OVERRIDE="client installs it on Monday" ./bin/exec.sh domain.mdl; RC=$?
  grep -q 'Marketplace install gate OVERRIDDEN' "$WORK/xout" && ok "override lets it through" || bad "T14: override not honoured: $(tail -5 "$WORK/xout")"
  grep -q 'marketplace override: client installs it on Monday' "$E/docs/BUILD-LOG.md" 2>/dev/null && ok "override reason in BUILD-LOG" || bad "T14: override reason not logged"

  E="$WORK/x2"; mkexec "$E" "$CAP_MKT" '| crypto helpers | `MyFirstModule` module (marketplace) | **Buy** | — |'
  runx "$E" ./bin/exec.sh domain.mdl; RC=$?
  grep -q 'Marketplace install gate' "$WORK/xout" && bad "T14 PASS: refused" || ok "PASS: domain-model script goes on (rc $RC)"
  [ "$(snaps "$E")" -ge 1 ] && ok "PASS: the exec reached its snapshot" || bad "T14 PASS: never reached the snapshot: $(tail -5 "$WORK/xout")"
  [ "$(cat "$E/.claude/loop/marketplace-ok.txt" 2>/dev/null)" = "myfirstmodule " ] && ok "PASS remembered for this confirmed list" || bad "T14: no marketplace-ok.txt"
  n1="$(wc -l < "$E/SHOWN" 2>/dev/null | tr -d ' ')"
  runx "$E" ./bin/exec.sh domain.mdl
  n2="$(wc -l < "$E/SHOWN" 2>/dev/null | tr -d ' ')"
  [ "${n1:-0}" -ge 1 ] && [ "$n1" = "$n2" ] && ok "second exec: SHOW MODULES not read again ($n1 read)" || bad "T14: SHOW MODULES reads $n1 -> $n2"

  E="$WORK/x3"; mkexec "$E" "$CAP_MKT" "$R_UNVER"
  runx "$E" ./bin/exec.sh domain.mdl; RC=$?
  grep -q 'Marketplace install gate: refusing' "$WORK/xout" && bad "T14 PENDING: refused" || ok "PENDING (unresolved row only): not refused"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
