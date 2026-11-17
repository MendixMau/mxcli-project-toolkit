#!/usr/bin/env bash
# test-multi-app-scope.sh — a repo holding several apps (apps/<App>/<App>.mpr) is scoped per app.
#
#   usage: bash tests/wave2/test-multi-app-scope.sh project-bin/_common.sh
#
# Field runs (2026-11): six apps under apps/<App>/ printed "more than one .mpr; set MPR_FILE to
# choose, nothing checked" for the Marketplace check; CLAUDE.local.md had to hand-write the
# MPR_FILE workaround; a second run dropped per-app planning for one free-form brief.
#
# The tree is materialised from fixtures/multi-app/tree.txt (see PROVENANCE.txt there); SHOW
# MODULES is replayed from the captures in fixtures/show-modules/ by a stub mxcli keyed on -p.
#
#   A1 resolver: mxtk_apps lists the six apps, mxtk_app_count 6; mxtk_select_app exact and any
#      letter case, unknown refused listing apps; mxtk_app_of; MXTK_APP at source time beats the
#      cwd auto-pick, a user's MPR_FILE beats MXTK_APP; find_mpr still refuses, naming MXTK_APP;
#      an app folder with its own .claude/ + PROJECT.md resolves to the outer project when that
#      has two or more app folders (any PROJECT.md, a hand-written one too) or, for one app, a
#      register (refinement of #489), keeps its own root otherwise; status.sh with no argument
#      finds the project from an app subfolder; one line per app
#      folder (a second .mpr is not a second app; "-" and a refusal when none is <App>.mpr)
#   A2 single tree and two-tree: mxtk_apps prints nothing (rc 1) and mxtk_app_count is 0, even
#      with an apps/ folder holding a model beside the root model
#   A3 gate-check, no app chosen: "Marketplace installs: per app (6 apps", one [App] line each,
#      no "nothing checked"; per-app fit-gap missing package -> FAIL for that app only; shared
#      fit-gap missing package -> PENDING (owner unknown); build-ready counts the FAIL; with
#      every app on the shared fit-gap, the one finding prints once ("all 6 apps"); with no
#      fit-gap at all, no "from the shared" label
#   A4 gate-check --app appa: one Marketplace line, AppA's fit-gap, no Apps section; --app Nope
#      exits 2 naming the apps; --app on a single-tree project exits 2; an env MXTK_APP there is
#      dropped (exit 0)
#   A5 gate-check "Apps:" section and status.sh: one line per app, scripts per app's mdlsource,
#      LOOK owed per app, and "no ledger here (N pages ...)" before any ledger exists — never
#      "no pages owed" by absence; single-tree and two-tree print neither
#   A6 look-ledger: owe writes the app as a 5th column in the multi-app tree, four columns in a
#      single tree; nothing lands in an app's own .claude/ (one ledger); status --app keeps two
#      apps' same-named page apart
#   A7 init-project scaffolds architecture/apps/<App>/intake.md + triage.md + the index and the
#      multi-app Wiring rows; sync-project re-run creates nothing and overwrites nothing
#   A8 an app's own PROJECT.md (mxcli init per app; the field repo had seven) holding register
#      lines is warned in gate-check's Apps section and status WATCH; a plain one is silent
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
TK="$(cd "$(dirname "$COMMON")/.." && pwd)"
FX="$TK/tests/wave2/fixtures"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-multiapp.XXXXXX")"; T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }
has()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok "$1"; else fail "$1 (no '$3' in: $(printf '%s' "$2" | head -c 600))"; fi; }
hasnt(){ if printf '%s\n' "$2" | grep -qF -- "$3"; then fail "$1 (unexpected '$3')"; else ok "$1"; fi; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want '$3', got '$2')"; fi; }
clean_env() { env -u MPR_FILE -u MXTK_APP -u MXTK_MPR_PICKED -u PROJECT_ROOT -u MXCLI "$@"; }

# --- the multi-app tree ---------------------------------------------------------------------
P="$T/multi"; mkdir -p "$P"
while IFS= read -r l; do
  l="${l#./}"; [ -n "$l" ] || continue
  case "$l" in */) mkdir -p "$P/$l" ;; *) mkdir -p "$P/$(dirname "$l")"; : > "$P/$l" ;; esac
done < "$FX/multi-app/tree.txt"
# Page scripts: AppA and AppB both build Administration.Account_Overview (A6).
printf 'create page AppA.Order_Overview (\n);\ncreate page Administration.Account_Overview (\n);\n' > "$P/apps/AppA/mdlsource/030-step.mdl"
printf 'create or replace page AppB.Invoice_Overview (\n);\ncreate page Administration.Account_Overview (\n);\n' > "$P/apps/AppB/mdlsource/030-step.mdl"
printf '# Project\n\n## Current stage\n**Stage 5 — build**\n' > "$P/PROJECT.md"

# stub mxcli: replays a captured SHOW MODULES per app (-p <model>)
STUB="$T/stub-mxcli"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do case "\$1" in -p) shift; m="\$1" ;; esac; shift; done
case "\$m" in
  */AppA/*) cat "$FX/show-modules/show-modules-marketplace-protected-v0.29.0.out" ;;
  *)          cat "$FX/show-modules/show-modules-source-v0.29.0.out" ;;
esac
EOF
chmod +x "$STUB"

echo "A1 resolver"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_apps; echo n=\$(mxtk_app_count)")"
has "A1 lists AppA" "$r" "AppA	apps/AppA/AppA.mpr"
has "A1 lists AppC" "$r" "AppC	apps/AppC/AppC.mpr"
has "A1 lists AppF" "$r" "AppF	apps/AppF/AppF.mpr"
has "A1 count 6" "$r" "n=6"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_select_app appb && echo \"\$MXTK_APP|\$MPR_FILE\"")"
eq "A1 select any case" "$r" "AppB|$P/apps/AppB/AppB.mpr"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_select_app Nope; echo rc=\$?" 2>&1)"
has "A1 unknown refused" "$r" "rc=1"; has "A1 unknown lists apps" "$r" "AppC  (apps/AppC/AppC.mpr)"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_app_of '$P/apps/AppA/mdlsource/x.mdl'; mxtk_app_of docs/x || echo none")"
eq "A1 app_of" "$r" "AppA
none"
r="$(clean_env MXTK_APP=AppA bash -c "cd '$P/apps/AppB'; . '$COMMON'; find_mpr")"
eq "A1 MXTK_APP beats cwd pick" "$r" "$P/apps/AppA/AppA.mpr"
r="$(clean_env MXTK_APP=AppA MPR_FILE=apps/AppC/AppC.mpr bash -c "cd '$P'; . '$COMMON'; find_mpr")"
eq "A1 user MPR_FILE beats MXTK_APP" "$r" "$P/apps/AppC/AppC.mpr"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; find_mpr" 2>&1)"
has "A1 find_mpr refuses" "$r" "refusing to guess"; has "A1 refusal names MXTK_APP" "$r" "MXTK_APP=<X>"
# Each captured app folder carries its own .claude/ + PROJECT.md (mxcli init per app). Under an
# outer project with a register they resolve to the OUTER project (refinement of #489).
r="$(clean_env bash -c "cd '$P/apps/AppB/docs'; . '$COMMON'; echo \"\$PROJECT_ROOT|\$MPR_FILE\"")"
eq "A1 app folder with its own .claude/ resolves to the outer project" "$r" "$P|$P/apps/AppB/AppB.mpr"
# ... also under a HAND-WRITTEN outer register (the field root: "- Mode: requirements-driven",
# none of the toolkit's sections): two or more app folders make it the multi-app project
cp "$P/PROJECT.md" "$T/root-register"
printf '# Project\n\n- Owner: someone\n- Mode: requirements-driven (from specs)\n' > "$P/PROJECT.md"
r="$(clean_env bash -c "cd '$P/apps/AppD'; . '$COMMON'; echo \"\$PROJECT_ROOT|\$MPR_FILE\"")"
eq "A1 hand-written outer register: an app cwd resolves to the outer root" "$r" "$P|$P/apps/AppD/AppD.mpr"
st="$(cd "$P/apps/AppB/docs" && clean_env bash "$TK/bin/status.sh" --brief 2>&1)"
has "A1 status.sh with no argument, from an app subfolder, finds the project" "$st" "APP     AppF: apps/AppF/AppF.mpr"
cp "$T/root-register" "$P/PROJECT.md"
# ... and keep their own root when the outer folder holds ONE app and no register lines (#489 unchanged)
N="$T/nested"; mkdir -p "$N/apps/X/.claude" "$N/.claude"; : > "$N/PROJECT.md"; : > "$N/apps/X/PROJECT.md"; : > "$N/apps/X/X.mpr"
r="$(clean_env bash -c "cd '$N/apps/X'; . '$COMMON'; echo \"\$PROJECT_ROOT\"")"
eq "A1 no outer register: the app folder keeps its own root" "$r" "$N/apps/X"
# one line per app FOLDER: a second .mpr does not make a second app
: > "$P/apps/AppC/Copy.mpr"; mv "$P/apps/AppD/AppD.mpr" "$P/apps/AppD/Zz.mpr"; : > "$P/apps/AppD/Other.mpr"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_apps | grep -E '^App[CD]'; echo n=\$(mxtk_app_count)")"
eq "A1 one line per folder, <App>.mpr preferred, '-' when ambiguous" "$r" "AppC	apps/AppC/AppC.mpr
AppD	-
n=6"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_select_app AppD; echo rc=\$?" 2>&1)"
has "A1 ambiguous folder refused" "$r" "apps/AppD/ holds more than one .mpr and none is named AppD.mpr"; has "A1 ambiguous rc" "$r" "rc=1"
rm -f "$P/apps/AppC/Copy.mpr" "$P/apps/AppD/Other.mpr"; mv "$P/apps/AppD/Zz.mpr" "$P/apps/AppD/AppD.mpr"

echo "A2 single tree and two-tree are never multi-app"
S1="$T/single"; mkdir -p "$S1/apps/Other" "$S1/.claude"; : > "$S1/Single.mpr"; : > "$S1/apps/Other/Other.mpr"
printf '# Project\n\n## Current stage\n**Stage 5 — build**\n' > "$S1/PROJECT.md"
S2="$T/twotree"; mkdir -p "$S2/app" "$S2/.claude"; : > "$S2/app/Two.mpr"
printf '# Project\n\n## Current stage\n**Stage 5 — build**\n' > "$S2/PROJECT.md"
for d in "$S1" "$S2"; do
  r="$(clean_env bash -c "cd '$d'; . '$COMMON'; mxtk_apps; echo rc=\$? n=\$(mxtk_app_count)")"
  eq "A2 $(basename "$d"): nothing listed" "$r" "rc=1 n=0"
done

echo "A3 gate-check per-app Marketplace (no app chosen)"
mkdir -p "$P/architecture/apps/AppA" "$P/architecture/apps/AppB"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Module | `MyFirstModule` | Buy |\n' > "$P/architecture/apps/AppA/fit-gap.md"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Grid | `DataWidgets` | Buy |\n' > "$P/architecture/apps/AppB/fit-gap.md"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Grid | `DataWidgets` | Buy |\n' > "$P/architecture/fit-gap.md"
gc() { clean_env MXCLI="$STUB" MXTK_NO_FETCH=1 MXTK_GATE_CACHE_TTL_MIN=0 bash "$TK/bin/gate-check.sh" --no-html "$@" 2>&1; }
out="$(gc "$P")"
has "A3 header" "$out" "Marketplace installs: per app (6 apps"
has "A3 AppA installed" "$out" "  [AppA] PASS — 1 of 1 confirmed Buy installed"
has "A3 AppB own fit-gap FAIL" "$out" "  [AppB] FAIL — 0 of 1 confirmed Buy installed; NOT INSTALLED: DataWidgets"
has "A3 shared fit-gap PENDING, grouped" "$out" "  [AppC, AppD, AppE, AppF, from the shared architecture/fit-gap.md] PENDING — the shared architecture/fit-gap.md does not say which app owes this Buy"
hasnt "A3 no nothing-checked" "$out" "nothing checked"
br="$(gc "$P" build-ready)"
has "A3 build-ready counts the FAIL" "$br" "✗ Marketplace: AppA: PASS; AppB: FAIL; AppC: PENDING; AppD: PENDING"
# every app on the shared fit-gap: one finding, printed once (a field run, six apps, printed it six times)
mv "$P/architecture/apps" "$T/apps-fitgaps"
out="$(gc "$P")"
has "A3 shared finding printed once" "$out" "  [all 6 apps, from the shared architecture/fit-gap.md] PENDING"
mv "$P/architecture/fit-gap.md" "$T/shared-fitgap"
out="$(gc "$P")"
has "A3 no fit-gap at all: one line, no 'from the shared'" "$out" "  [all 6 apps] PENDING — no architecture/fit-gap.md yet"
mv "$T/shared-fitgap" "$P/architecture/fit-gap.md"
eq "A3 no per-app repeat" "$(printf '%s\n' "$out" | grep -c '^  \[AppA\] PENDING')" "0"
mv "$T/apps-fitgaps" "$P/architecture/apps"

echo "A4 gate-check --app"
out="$(gc --app appa "$P")"
has "A4 one line, AppA' fit-gap" "$out" "Marketplace installs: PASS — 1 of 1 confirmed Buy installed"
hasnt "A4 no per-app header" "$out" "per app ("
hasnt "A4 no Apps section" "$out" "Apps: 6"
out="$(gc --app Nope "$P")"; rc=$?
eq "A4 unknown app exits 2" "$rc" "2"; has "A4 names the apps" "$out" "AppA  (apps/AppA/AppA.mpr)"
out="$(gc --app AppA "$S1")"; rc=$?
eq "A4 --app on single tree exits 2" "$rc" "2"
out="$(clean_env MXTK_APP=AppA MXCLI="$STUB" MXTK_NO_FETCH=1 MXTK_GATE_CACHE_TTL_MIN=0 bash "$TK/bin/gate-check.sh" --no-html "$S1" 2>&1)"; rc=$?
eq "A4 env MXTK_APP on a single tree is dropped (exit 0)" "$rc" "0"

echo "A5 Apps section and status lines"
# no ledger yet (it is git-ignored: a fresh checkout has none) is never "no pages owed"
st="$(clean_env bash "$TK/bin/status.sh" "$P" 2>&1)"
has "A5 no ledger is said" "$st" "APP       AppA: apps/AppA/AppA.mpr · scripts 69 written / 0 done- · LOOK: no ledger here (2 page(s) in its scripts)"
hasnt "A5 no pass-by-absence" "$st" "no pages owed"
for a in AppA AppB; do
  (cd "$P/apps/$a" && clean_env bash "$TK/project-bin/look-ledger.sh" owe "$P/apps/$a/mdlsource/030-step.mdl" >/dev/null)
done
out="$(gc "$P")"
has "A5 Apps header" "$out" "Apps: 6 (one register, PROJECT.md"
has "A5 AppB line" "$out" "  [AppB] apps/AppB/AppB.mpr · scripts 34 written / 0 done- · LOOK: 2 of 2 page(s) owed"
has "A5 AppC line" "$out" "  [AppC] apps/AppC/AppC.mpr · scripts 28 written / 0 done- · LOOK: no page in its scripts"
st="$(clean_env bash "$TK/bin/status.sh" "$P" 2>&1)"
has "A5 status AppA" "$st" "APP       AppA: apps/AppA/AppA.mpr · scripts 69 written / 0 done- · LOOK: 2 of 2 page(s) owed"
stb="$(clean_env bash "$TK/bin/status.sh" "$P" --brief 2>&1)"
has "A5 status --brief AppC" "$stb" "APP     AppC: apps/AppC/AppC.mpr"
for d in "$S1" "$S2"; do
  out="$(gc "$d")"; st="$(clean_env bash "$TK/bin/status.sh" "$d" 2>&1)"
  hasnt "A5 $(basename "$d"): no Apps section" "$out" "Apps: "
  hasnt "A5 $(basename "$d"): no per-app Marketplace" "$out" "per app ("
  hasnt "A5 $(basename "$d"): no APP status line" "$st" "APP "
done

echo "A6 look-ledger keyed by app"
cols="$(awk -F'\t' '{print NF ":" $5}' "$P/.claude/loop/look/owed.tsv" | sort -u | tr '\n' ' ')"
eq "A6 multi-app rows carry the app" "$cols" "5:AppA 5:AppB "
[ -e "$P/apps/AppA/.claude/loop/look/owed.tsv" ] && fail "A6 ledger split into apps/AppA/.claude/" || ok "A6 one ledger: nothing under apps/AppA/.claude/loop/"
printf 'create page Single.Home (\n);\n' > "$S1/p.mdl"
(cd "$S1" && clean_env bash "$TK/project-bin/look-ledger.sh" owe "$S1/p.mdl" >/dev/null)
eq "A6 single tree keeps four columns" "$(awk -F'\t' '{print NF}' "$S1/.claude/loop/look/owed.tsv")" "4"
r="$(cd "$P" && clean_env PROJECT_ROOT="$P" bash "$TK/project-bin/look-ledger.sh" status --app AppA | cut -f1,2 | tr '\n' ' ')"
eq "A6 status --app AppA" "$r" "OWED	Administration.Account_Overview OWED	AppA.Order_Overview "
r="$(cd "$P" && clean_env PROJECT_ROOT="$P" MXTK_APP=AppB bash "$TK/project-bin/look-ledger.sh" status | cut -f2 | tr '\n' ' ')"
eq "A6 MXTK_APP scopes status" "$r" "Administration.Account_Overview AppB.Invoice_Overview "

echo "A7 init-project and sync-project scaffold per app"
I="$T/init"; mkdir -p "$I"
while IFS= read -r l; do
  l="${l#./}"; case "$l" in apps/*) ;; *) continue ;; esac   # the apps only: init writes the root
  case "$l" in */) mkdir -p "$I/$l" ;; *) mkdir -p "$I/$(dirname "$l")"; : > "$I/$l" ;; esac
done < "$FX/multi-app/tree.txt"
(cd "$I" && git init -q .)
out="$(clean_env MXTK_NO_GUIDE=1 MXTK_NO_FETCH=1 bash "$TK/bin/init-project.sh" "$I" 2>&1)"
for a in AppA AppB AppC; do
  [ -f "$I/architecture/apps/$a/intake.md" ] && ok "A7 $a intake" || fail "A7 $a intake missing"
  [ -f "$I/architecture/apps/$a/triage.md" ] && ok "A7 $a triage" || fail "A7 $a triage missing"
done
has "A7 index lists AppC" "$(cat "$I/architecture/apps/README.md" 2>/dev/null)" "| AppC | \`apps/AppC/AppC.mpr\` |"
has "A7 Wiring names MXTK_APP" "$(cat "$I/CLAUDE.local.md")" "Select with \`MXTK_APP=<App>\`"
echo "own words" >> "$I/architecture/apps/AppA/intake.md"
out="$(clean_env MXTK_NO_FETCH=1 bash "$TK/bin/sync-project.sh" "$I" 2>&1)"
hasnt "A7 sync creates nothing new" "$out" "Created: architecture/apps/"
has "A7 sync kept the edit" "$(tail -1 "$I/architecture/apps/AppA/intake.md")" "own words"
rm -f "$I/architecture/apps/AppC/intake.md"
out="$(clean_env MXTK_NO_FETCH=1 bash "$TK/bin/sync-project.sh" "$I" 2>&1)"
has "A7 sync restores a missing app intake" "$out" "Created: architecture/apps/AppC/intake.md"

echo "A8 an app's own PROJECT.md is not a register"
printf '# AppA\n\nEntry mode: greenfield\n\n## Current stage\n**Stage 2 — x**\n\n| Stage | Decision | Status |\n|---|---|---|\n| 1 | x | CONFIRMED |\n' > "$P/apps/AppA/PROJECT.md"
printf '# AppB\n\nA plain template, no register lines.\n' > "$P/apps/AppB/PROJECT.md"
out="$(gc "$P")"
has "A8 register lines in AppA warned" "$out" "⚠ [AppA] apps/AppA/PROJECT.md holds register lines (Entry mode: greenfield, the root has none; Current stage; 1 decision row(s))"
hasnt "A8 plain AppB file is silent" "$out" "⚠ [AppB]"
st="$(clean_env bash "$TK/bin/status.sh" "$P" 2>&1)"
has "A8 status WATCH" "$st" "apps/AppA/PROJECT.md holds register lines"

echo ""
echo "multi-app scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
