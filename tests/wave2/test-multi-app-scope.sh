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
#   A1 resolver: mxtk_apps lists the three apps, mxtk_app_count 3; mxtk_select_app exact and any
#      letter case, unknown refused listing apps; mxtk_app_of; MXTK_APP at source time beats the
#      cwd auto-pick, a user's MPR_FILE beats MXTK_APP; find_mpr still refuses, naming MXTK_APP
#   A2 single tree and two-tree: mxtk_apps prints nothing (rc 1) and mxtk_app_count is 0, even
#      with an apps/ folder holding a model beside the root model
#   A3 gate-check, no app chosen: "Marketplace installs: per app (3 apps", one [App] line each,
#      no "nothing checked"; per-app fit-gap missing package -> FAIL for that app only; shared
#      fit-gap missing package -> PENDING (owner unknown); build-ready counts the FAIL
#   A4 gate-check --app orders: one Marketplace line, Orders' fit-gap; no Apps section;
#      --app Nope exits 2 naming the apps; --app on a single-tree project exits 2
#   A5 gate-check "Apps:" section and status.sh: one line per app, scripts per app's mdlsource,
#      LOOK owed per app; single-tree and two-tree print neither
#   A6 look-ledger: owe writes the app as a 5th column in the multi-app tree, four columns in a
#      single tree; status --app keeps two apps' same-named page apart
#   A7 init-project scaffolds architecture/apps/<App>/intake.md + triage.md + the index and the
#      multi-app Wiring rows; sync-project re-run creates nothing and overwrites nothing
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
# Page scripts: Orders and Billing both build Administration.Account_Overview (A6).
printf 'create page Orders.Order_Overview (\n);\ncreate page Administration.Account_Overview (\n);\n' > "$P/apps/Orders/mdlsource/030-orders-pages.mdl"
printf 'create or replace page Billing.Invoice_Overview (\n);\ncreate page Administration.Account_Overview (\n);\n' > "$P/apps/Billing/mdlsource/030-billing-pages.mdl"
printf '# Project\n\n## Current stage\n**Stage 5 — build**\n' > "$P/PROJECT.md"

# stub mxcli: replays a captured SHOW MODULES per app (-p <model>)
STUB="$T/stub-mxcli"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do case "\$1" in -p) shift; m="\$1" ;; esac; shift; done
case "\$m" in
  */Orders/*) cat "$FX/show-modules/show-modules-marketplace-protected-v0.29.0.out" ;;
  *)          cat "$FX/show-modules/show-modules-source-v0.29.0.out" ;;
esac
EOF
chmod +x "$STUB"

echo "A1 resolver"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_apps; echo n=\$(mxtk_app_count)")"
has "A1 lists Orders" "$r" "Orders	apps/Orders/Orders.mpr"
has "A1 lists Portal" "$r" "Portal	apps/Portal/Portal.mpr"
has "A1 count 3" "$r" "n=3"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_select_app billing && echo \"\$MXTK_APP|\$MPR_FILE\"")"
eq "A1 select any case" "$r" "Billing|$P/apps/Billing/Billing.mpr"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_select_app Nope; echo rc=\$?" 2>&1)"
has "A1 unknown refused" "$r" "rc=1"; has "A1 unknown lists apps" "$r" "Portal  (apps/Portal/Portal.mpr)"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; mxtk_app_of '$P/apps/Orders/mdlsource/x.mdl'; mxtk_app_of docs/x || echo none")"
eq "A1 app_of" "$r" "Orders
none"
r="$(clean_env MXTK_APP=Orders bash -c "cd '$P/apps/Billing'; . '$COMMON'; find_mpr")"
eq "A1 MXTK_APP beats cwd pick" "$r" "$P/apps/Orders/Orders.mpr"
r="$(clean_env MXTK_APP=Orders MPR_FILE=apps/Portal/Portal.mpr bash -c "cd '$P'; . '$COMMON'; find_mpr")"
eq "A1 user MPR_FILE beats MXTK_APP" "$r" "$P/apps/Portal/Portal.mpr"
r="$(clean_env bash -c "cd '$P'; . '$COMMON'; find_mpr" 2>&1)"
has "A1 find_mpr refuses" "$r" "refusing to guess"; has "A1 refusal names MXTK_APP" "$r" "MXTK_APP=<X>"

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
mkdir -p "$P/architecture/apps/Orders" "$P/architecture/apps/Billing"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Module | `MyFirstModule` | Buy |\n' > "$P/architecture/apps/Orders/fit-gap.md"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Grid | `DataWidgets` | Buy |\n' > "$P/architecture/apps/Billing/fit-gap.md"
printf '| Capability | Mendix approach | Verdict |\n|---|---|---|\n| Grid | `DataWidgets` | Buy |\n' > "$P/architecture/fit-gap.md"
gc() { clean_env MXCLI="$STUB" MXTK_NO_FETCH=1 MXTK_GATE_CACHE_TTL_MIN=0 bash "$TK/bin/gate-check.sh" --no-html "$@" 2>&1; }
out="$(gc "$P")"
has "A3 header" "$out" "Marketplace installs: per app (3 apps"
has "A3 Orders installed" "$out" "  [Orders] PASS — 1 of 1 confirmed Buy installed"
has "A3 Billing own fit-gap FAIL" "$out" "  [Billing] FAIL — 0 of 1 confirmed Buy installed; NOT INSTALLED: DataWidgets"
has "A3 Portal shared fit-gap PENDING" "$out" "  [Portal] PENDING — the shared architecture/fit-gap.md does not say which app owes this Buy"
hasnt "A3 no nothing-checked" "$out" "nothing checked"
br="$(gc "$P" build-ready)"
has "A3 build-ready counts the FAIL" "$br" "✗ Marketplace: Billing: FAIL; Orders: PASS; Portal: PENDING"

echo "A4 gate-check --app"
out="$(gc --app orders "$P")"
has "A4 one line, Orders' fit-gap" "$out" "Marketplace installs: PASS — 1 of 1 confirmed Buy installed"
hasnt "A4 no per-app header" "$out" "per app ("
hasnt "A4 no Apps section" "$out" "Apps: 3"
out="$(gc --app Nope "$P")"; rc=$?
eq "A4 unknown app exits 2" "$rc" "2"; has "A4 names the apps" "$out" "Orders  (apps/Orders/Orders.mpr)"
out="$(gc --app Orders "$S1")"; rc=$?
eq "A4 --app on single tree exits 2" "$rc" "2"

echo "A5 Apps section and status lines"
for a in Orders Billing; do
  (cd "$P/apps/$a" && clean_env bash "$TK/project-bin/look-ledger.sh" owe "$P/apps/$a/mdlsource/030-$(echo "$a" | tr '[:upper:]' '[:lower:]')-pages.mdl" >/dev/null)
done
out="$(gc "$P")"
has "A5 Apps header" "$out" "Apps: 3 (one register, PROJECT.md"
has "A5 Billing line" "$out" "  [Billing] apps/Billing/Billing.mpr · scripts 3 written / 1 done- · LOOK: 2 of 2 page(s) owed"
has "A5 Portal line" "$out" "  [Portal] apps/Portal/Portal.mpr · scripts 0 written / 0 done- · LOOK: no pages owed"
st="$(clean_env bash "$TK/bin/status.sh" "$P" 2>&1)"
has "A5 status Orders" "$st" "APP       Orders: apps/Orders/Orders.mpr · scripts 2 written / 0 done- · LOOK: 2 of 2 page(s) owed"
stb="$(clean_env bash "$TK/bin/status.sh" "$P" --brief 2>&1)"
has "A5 status --brief Portal" "$stb" "APP     Portal: apps/Portal/Portal.mpr"
for d in "$S1" "$S2"; do
  out="$(gc "$d")"; st="$(clean_env bash "$TK/bin/status.sh" "$d" 2>&1)"
  hasnt "A5 $(basename "$d"): no Apps section" "$out" "Apps: "
  hasnt "A5 $(basename "$d"): no per-app Marketplace" "$out" "per app ("
  hasnt "A5 $(basename "$d"): no APP status line" "$st" "APP "
done

echo "A6 look-ledger keyed by app"
cols="$(awk -F'\t' '{print NF ":" $5}' "$P/.claude/loop/look/owed.tsv" | sort -u | tr '\n' ' ')"
eq "A6 multi-app rows carry the app" "$cols" "5:Billing 5:Orders "
printf 'create page Single.Home (\n);\n' > "$S1/p.mdl"
(cd "$S1" && clean_env bash "$TK/project-bin/look-ledger.sh" owe "$S1/p.mdl" >/dev/null)
eq "A6 single tree keeps four columns" "$(awk -F'\t' '{print NF}' "$S1/.claude/loop/look/owed.tsv")" "4"
r="$(cd "$P" && clean_env PROJECT_ROOT="$P" bash "$TK/project-bin/look-ledger.sh" status --app Orders | cut -f1,2 | tr '\n' ' ')"
eq "A6 status --app Orders" "$r" "OWED	Administration.Account_Overview OWED	Orders.Order_Overview "
r="$(cd "$P" && clean_env PROJECT_ROOT="$P" MXTK_APP=Billing bash "$TK/project-bin/look-ledger.sh" status | cut -f2 | tr '\n' ' ')"
eq "A6 MXTK_APP scopes status" "$r" "Administration.Account_Overview Billing.Invoice_Overview "

echo "A7 init-project and sync-project scaffold per app"
I="$T/init"; mkdir -p "$I"
while IFS= read -r l; do
  l="${l#./}"; case "$l" in ''|PROJECT.md|intake.md|.claude/|architecture/) continue ;; esac
  case "$l" in */) mkdir -p "$I/$l" ;; *) mkdir -p "$I/$(dirname "$l")"; : > "$I/$l" ;; esac
done < "$FX/multi-app/tree.txt"
(cd "$I" && git init -q .)
out="$(clean_env MXTK_NO_GUIDE=1 MXTK_NO_FETCH=1 bash "$TK/bin/init-project.sh" "$I" 2>&1)"
for a in Orders Billing Portal; do
  [ -f "$I/architecture/apps/$a/intake.md" ] && ok "A7 $a intake" || fail "A7 $a intake missing"
  [ -f "$I/architecture/apps/$a/triage.md" ] && ok "A7 $a triage" || fail "A7 $a triage missing"
done
has "A7 index lists Portal" "$(cat "$I/architecture/apps/README.md" 2>/dev/null)" "| Portal | \`apps/Portal/Portal.mpr\` |"
has "A7 Wiring names MXTK_APP" "$(cat "$I/CLAUDE.local.md")" "Select with \`MXTK_APP=<App>\`"
echo "own words" >> "$I/architecture/apps/Orders/intake.md"
out="$(clean_env MXTK_NO_FETCH=1 bash "$TK/bin/sync-project.sh" "$I" 2>&1)"
hasnt "A7 sync creates nothing new" "$out" "Created: architecture/apps/"
has "A7 sync kept the edit" "$(tail -1 "$I/architecture/apps/Orders/intake.md")" "own words"
rm -f "$I/architecture/apps/Portal/intake.md"
out="$(clean_env MXTK_NO_FETCH=1 bash "$TK/bin/sync-project.sh" "$I" 2>&1)"
has "A7 sync restores a missing app intake" "$out" "Created: architecture/apps/Portal/intake.md"

echo ""
echo "multi-app scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
