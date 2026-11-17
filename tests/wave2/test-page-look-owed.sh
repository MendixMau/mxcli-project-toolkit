#!/usr/bin/env bash
# test-page-look-owed.sh — pages built means a LOOK is owed, whatever the pipeline position.
#
#   usage: bash tests/wave2/test-page-look-owed.sh bin/gate-check.sh
#     (the obligation lib, exec.sh and page-fidelity.js are derived from the same toolkit)
#
# THE BUG (field run 2026-11-17, fixtures/page-look-owed/CAPTURE.md). A requirements-driven
# project started at the build stage with six apps under apps/<App>/, page scripts, a supplied
# prototype folder, and no briefs, build plan, wireframes or verify runs. Every page-review
# safeguard was silent: _ob_modules() had no scope, so look and fidelity read "PASS — nothing
# owed"; exec.sh's brief advisory says nothing without a build plan; prototype-look knew only
# design/prototype.html and read N/A; page-fidelity.js found no .mpr two levels down and never
# logged. The project reached its last level with 0 pages looked at.
#
# Golden input: real captured / exec'd MDL arranged in the field layout (CAPTURE.md). The
# denominator asserted below — 6 pages in 4 modules — is counted from those sources by hand.
#
#   L1  multi-app, no briefs: look and fidelity PENDING with "6 page(s) built, 0 reviewed", never PASS
#   L2  the field's before-lines are gone from gate-check.sh <project> 5 (end to end)
#   L3  commented-out page statements do not count (StyleGallery header)
#   L4  model resolves, nothing lists pages → FAULT with "?", not PASS; a register waiver → WAIVED
#   L5  existing-app change with only a model → unchanged PASS (its pages were not built here);
#       derived Current stage before 5 with only a model → unchanged PASS (a starter model)
#   L6  both layouts: single tree (mdlsource/ at the root) and two-tree (app/mdlsource/)
#   L7  briefs present → the brief scope wins, no fallback SCOPE line (unchanged behaviour)
#   L8  prototype-look: supplied prototypes/ → PENDING; `Prototype folder:` line → PENDING; none → N/A;
#       a LOOK report with PROOF-OF-LOOK discharges a supplied folder without a PROTOTYPE-SHA
#   L9  exec.sh, no build plan: a page script warns once (no review, no target screen), exit 0;
#       a reviewed module with a matching prototype screen is silent; a non-page script is silent
#   L10 page-fidelity.js: a prototype FOLDER resolves the screen; in apps/<X>/ the score logs to
#       the project root's docs/PAGE-FIDELITY.tsv, and that discharges fidelity for the module
#
# Platform: bash 3.2 / BSD userland safe; node optional (L10 SKIPs without it).
set -uo pipefail

ARG="${1:?usage: test-page-look-owed.sh /path/to/bin/gate-check.sh}"
GATE="$(cd "$(dirname "$ARG")" && pwd)/$(basename "$ARG")"
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
OBCHECK="$TK/bin/lib/obligation-check.sh"
EXEC_SH="$TK/project-bin/exec.sh"
PFJS="$TK/project-bin/page-fidelity.js"
FX="$TK/tests/wave2/fixtures"
for f in "$OBCHECK" "$EXEC_SH" "$FX/page-look-owed/CAPTURE.md"; do
  [ -r "$f" ] || { echo "test-page-look-owed: missing $f"; exit 2; }
done

W="$(mktemp -d "${TMPDIR:-/tmp}/page-look-owed.XXXXXX")"; W="$(cd "$W" && pwd)"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
has() { case "$2" in *"$1"*) return 0 ;; esac; return 1; }

# The field layout, from verbatim sources (CAPTURE.md table).
mkfield() {  # $1 = dir
  local P="$1"
  mkdir -p "$P/apps/Procure/mdlsource" "$P/apps/Shop/mdlsource" "$P/apps/Catalog/mdlsource" \
           "$P/apps/Gallery/mdlsource" "$P/prototypes/procure" "$P/docs"
  for a in Procure Shop Catalog Gallery; do : > "$P/apps/$a/$a.mpr"; done
  cp "$FX/affected-tests/field-describe-Purchasing.Request_Edit.out" "$P/apps/Procure/mdlsource/10-request-edit.mdl"
  cp "$FX/affected-tests/field-describe-Purchasing.Request_List.out" "$P/apps/Procure/mdlsource/11-request-list.mdl"
  cp "$FX/affected-tests/shop.mdl" "$P/apps/Shop/mdlsource/10-shop.mdl"
  cp "$FX/page-fidelity-popup/product-newedit-describe-v023.mdl" "$P/apps/Catalog/mdlsource/20-product.mdl"
  cp "$TK/examples/stylegallery/mdlsource/gallery/90-gallery-home.mdl" "$P/apps/Gallery/mdlsource/90-gallery-home.mdl"
  cp "$FX/page-fidelity-mocks/grouped-overview.html" "$P/prototypes/procure/request-list.html"
  printf '# Project\n\n## Decision register\n\nEntry mode: requirements-driven — CONFIRMED\n' > "$P/PROJECT.md"
}
ob()  { bash "$OBCHECK" "$1" 2>/dev/null; }
row() { printf '%s\n' "$2" | grep -E "^Obligation $1 " | head -1; }
scope_line() { printf '%s\n' "$2" | grep -E "^Obligation $1 +SCOPE:" | head -1; }

echo "== L1: multi-app field layout, no briefs/plan/reviews: look + fidelity owed with a denominator"
P="$W/field"; mkfield "$P"
OUT="$(ob "$P")"
L="$(row look "$OUT")"
has "PENDING" "$L" && has "[6 page(s) built, 0 reviewed]" "$L" && ok "look PENDING, 6 built, 0 reviewed" || bad "look" "$L"
has "NOT DONE: Purchasing Sales Shop StyleGallery" "$L" && ok "scope = the 4 modules holding pages" || bad "look scope" "$L"
F="$(row fidelity "$OUT")"
has "PENDING" "$F" && has "[6 page(s) built]" "$F" && ok "fidelity PENDING, 6 built" || bad "fidelity" "$F"
has "visual target: prototypes" "$(scope_line look "$OUT")" && ok "SCOPE names the supplied prototype folder" || bad "scope line" "$(scope_line look "$OUT")"
printf '%s\n' "$OUT" | grep -E '^Obligation (look|fidelity) .*nothing owed' >/dev/null \
  && bad "a page row still reads 'nothing owed'" "$OUT" || ok "no page row reads 'nothing owed'"

echo "== L2: gate-check.sh <project> 5, end to end: the field's three before-lines are gone"
GC="$(bash "$GATE" "$P" 5 2>&1)"
while IFS= read -r before; do
  [ -n "$before" ] || continue
  printf '%s\n' "$GC" | grep -qxF -- "$before" && bad "before-line still printed: $before" || ok "gone: ${before:0:60}…"
done < "$FX/page-look-owed/field-gate-check-5.before.txt"
has "prototype-look PENDING" "$GC" && ok "prototype-look PENDING (not N/A) with a supplied folder" || bad "prototype-look" "$(printf '%s\n' "$GC" | grep prototype-look)"
has "Obligation look       PENDING" "$GC" && ok "gate-check prints look PENDING" || bad "gate-check look" "$(printf '%s\n' "$GC" | grep '^Obligation look')"

echo "== L3: comment-only page statements are not pages"
grep -q 'create or replace' "$P/apps/Gallery/mdlsource/90-gallery-home.mdl" && ok "the StyleGallery header does mention create or replace (control)" || bad "control lost"
has "Gallery_Home" "$(. "$OBCHECK" >/dev/null 2>&1; _ob_built_pages "$P" 0)" && ok "the real Gallery_Home counts" || bad "Gallery_Home missing"

echo "== L4: a model resolves, nothing lists its pages → FAULT, not PASS; a waiver → WAIVED"
P4="$W/mpronly"; mkdir -p "$P4/apps/A" "$P4/apps/B"; : > "$P4/apps/A/A.mpr"; : > "$P4/apps/B/B.mpr"
printf '# P\n\nEntry mode: greenfield\n' > "$P4/PROJECT.md"
L="$(row look "$(ob "$P4")")"
has "FAULT — ? page(s) built, 0 of ? reviewed: 2 model(s) resolve (apps/A/A.mpr, apps/B/B.mpr)" "$L" && ok "FAULT names both models" || bad "mpr-only" "$L"
printf 'Waived obligation look: pages reviewed in the client test tool\n' >> "$P4/PROJECT.md"
L="$(row look "$(ob "$P4")")"
has "WAIVED — pages reviewed in the client test tool" "$L" && ok "whole-row waiver honoured" || bad "waiver" "$L"

echo "== L5: existing-app change, or derived stage before 5, with only a model → unchanged PASS"
P5="$W/existing"; mkdir -p "$P5"; : > "$P5/Live.mpr"
printf '# P\n\nEntry mode: change an existing app\n' > "$P5/PROJECT.md"
L="$(row look "$(ob "$P5")")"
has "PASS — no module has been opened" "$L" && ok "existing app: its pages were not built here" || bad "existing app" "$L"
P5b="$W/early"; mkdir -p "$P5b"; : > "$P5b/Starter.mpr"
printf '# P\n\n## Current stage\n**Stage 2 — Enrichment** (derived by gate-check, 2026-11-17)\n\nEntry mode: greenfield\n' > "$P5b/PROJECT.md"
L="$(row look "$(ob "$P5b")")"
has "PASS — no module has been opened" "$L" && ok "derived stage 2: a starter model is not a build" || bad "early stage" "$L"

echo "== L6: both layouts — single tree and two-tree"
P6="$W/single"; mkdir -p "$P6/mdlsource"; : > "$P6/Shop.mpr"; cp "$FX/affected-tests/shop.mdl" "$P6/mdlsource/"
printf '# P\n' > "$P6/PROJECT.md"
L="$(row look "$(ob "$P6")")"
has "[2 page(s) built, 0 reviewed]; NOT DONE: Shop" "$L" && ok "single tree: 2 pages, Shop owed" || bad "single tree" "$L"
P6b="$W/twotree"; mkdir -p "$P6b/app/mdlsource"; : > "$P6b/app/Shop.mpr"; cp "$FX/affected-tests/shop.mdl" "$P6b/app/mdlsource/"
printf '# P\n' > "$P6b/PROJECT.md"
L="$(row look "$(ob "$P6b")")"
has "[2 page(s) built, 0 reviewed]; NOT DONE: Shop" "$L" && ok "two-tree: 2 pages, Shop owed" || bad "two-tree" "$L"

echo "== L7: briefs present → brief scope, no fallback"
P7="$W/briefed"; mkfield "$P7"; mkdir -p "$P7/architecture/modules/Shop"
OUT="$(ob "$P7")"; L="$(row look "$OUT")"
has "0 of 1 discharged; NOT DONE: Shop" "$L" && ok "brief scope (Shop only)" || bad "brief scope" "$L"
[ -z "$(scope_line look "$OUT")" ] && ok "no SCOPE fallback line" || bad "fallback fired with briefs" "$(scope_line look "$OUT")"

echo "== L8: prototype-look recognises a supplied prototype"
P8="$W/proto"; mkdir -p "$P8"; printf '# P\n' > "$P8/PROJECT.md"
L="$(row prototype-look "$(ob "$P8")")"
has "N/A — no design/prototype.html assembled and no prototype folder supplied" "$L" && ok "none → N/A" || bad "none" "$L"
mkdir -p "$P8/spec/screens/a"; cp "$FX/page-fidelity-mocks/grouped-overview.html" "$P8/spec/screens/a/overview.html"
printf 'Prototype folder: `spec/screens/`\n' >> "$P8/PROJECT.md"
L="$(row prototype-look "$(ob "$P8")")"
has "PENDING — 0 of 1 discharged [1 screen(s) supplied]" "$L" && ok "register line → PENDING" || bad "register line" "$L"
mkdir -p "$P8/design/ui-reviews/shots"
head -c 20000 /dev/zero | tr '\0' 'x' > "$P8/design/ui-reviews/shots/overview.png"
printf '<p>1 of 1 screens reviewed</p>\nPROOF-OF-LOOK: Proto.Overview = shots/overview.png\n' > "$P8/design/ui-reviews/prototype-look-2026-11-17.html"
L="$(row prototype-look "$(ob "$P8")")"
has "PASS — 1 of 1 discharged" "$L" && ok "supplied folder: PROOF-OF-LOOK discharges it, no PROTOTYPE-SHA owed" || bad "discharge" "$L"

echo "== L9: exec.sh page-review advisory, no build plan"
mkexec() {  # $1 = dir; minimal single-tree project exec.sh can run (stub mxcli/mxbuild/java)
  local P="$1"; mkdir -p "$P/bin" "$P/mprcontents/84/77" "$W/jdk/bin"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  printf 'bson\n' > "$P/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
  cp "$TK/project-bin/_common.sh" "$TK/project-bin/restore-mpr.sh" "$P/bin/"
  cp "$EXEC_SH" "$P/bin/exec.sh"
  cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/Fixture.mpr"; cp -r mprcontents "$D/mprcontents"
echo "Snapshot saved: $D"
SNAP
  chmod +x "$P/bin/"*.sh
  printf '#!/usr/bin/env bash\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
  printf '# P\n' > "$P/PROJECT.md"
}
cat > "$W/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
mkdir -p "$W/jdk/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$W/jdk/bin/java"; chmod +x "$W/mxbuild" "$W/jdk/bin/java"
runx() {  # $1 = project, $2 = script; output in $W/out
  local P="$1"
  ( cd "$P" && git init -q . 2>/dev/null; git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm fx >/dev/null 2>&1
    mkdir -p "$W/tmp"
    TMPDIR="$W/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$W/mxbuild" \
      JAVA_HOME="$W/jdk" ./bin/exec.sh "$2" ) > "$W/out" 2>&1
}
PX="$W/x1"; mkexec "$PX"; cp "$FX/affected-tests/shop.mdl" "$PX/shop.mdl"
runx "$PX" shop.mdl; RC=$?
O="$(cat "$W/out")"
has "LOOK owed: this script builds 2 page(s)" "$O" && ok "page script warns, with the page count" || bad "no warn" "$(head -40 "$W/out")"
has "no review yet for: Shop" "$O" && ok "names the unreviewed module" || bad "module not named" "$(grep -A3 'LOOK owed' "$W/out")"
has "no wireframe or prototype screen named for: Shop.Order_Edit Shop.Order_Overview" "$O" && ok "names the pages with no target" || bad "targets" "$(grep -A3 'LOOK owed' "$W/out")"
[ "$(grep -c 'LOOK owed: this script' "$W/out")" = 1 ] && ok "warns once" || bad "warned $(grep -c 'LOOK owed: this script' "$W/out") times"
[ "$RC" -eq 0 ] && ok "never blocks (exit 0)" || bad "rc=$RC" "$(tail -15 "$W/out")"
[ -e "$PX/architecture/build-plan.md" ] && bad "fixture has a build plan" || ok "no build plan (the case block 5 is silent on)"

PX2="$W/x2"; mkexec "$PX2"; cp "$FX/affected-tests/shop.mdl" "$PX2/shop.mdl"
mkdir -p "$PX2/prototypes/shop" "$PX2/design/ui-reviews"
cp "$FX/page-fidelity-mocks/grouped-overview.html" "$PX2/prototypes/shop/order-overview.html"
cp "$FX/page-fidelity-mocks/grouped-overview.html" "$PX2/prototypes/shop/Order_Edit.html"
printf '<p>2 of 2 pages reviewed</p> Shop.Order_Edit Shop.Order_Overview\n' > "$PX2/design/ui-reviews/ui-review-2026-11-17.html"
runx "$PX2" shop.mdl
grep -q "LOOK owed" "$W/out" && bad "warned although reviewed and mapped" "$(grep -A3 'LOOK owed' "$W/out")" || ok "reviewed + mapped: silent"
grep -q "Snapshot saved\|exec" "$W/out" && ok "advisory path reached (exec ran)" || bad "exec did not run" "$(head -20 "$W/out")"

PX3="$W/x3"; mkexec "$PX3"; printf 'CREATE ENTITY Orders.Thing (Name: String(50));\n' > "$PX3/e.mdl"
runx "$PX3" e.mdl
grep -q "LOOK owed" "$W/out" && bad "non-page script warned" || ok "non-page script: silent"

echo "== L10: page-fidelity.js — a prototype folder, multi-app logging, fidelity discharged"
if ! command -v node >/dev/null 2>&1; then
  echo "  SKIP no node on PATH"
else
  PF="$W/pf"; mkfield "$PF"
  ( cd "$PF" && node "$PFJS" prototypes Request_List apps/Procure/mdlsource/11-request-list.mdl ) > "$W/pf.out" 2>&1; RC=$?
  [ "$RC" -eq 0 ] && ok "folder target scored (exit 0)" || bad "rc=$RC" "$(cat "$W/pf.out")"
  if [ -s "$PF/docs/PAGE-FIDELITY.tsv" ]; then
    tail -1 "$PF/docs/PAGE-FIDELITY.tsv" | grep -q $'\tPurchasing\t.*prototypes/procure/request-list.html$' \
      && ok "logged at the project root: module Purchasing, screen prototypes/procure/request-list.html" \
      || bad "logged row" "$(tail -1 "$PF/docs/PAGE-FIDELITY.tsv")"
  else
    bad "not logged at the project root (apps/<X>/ layout)" "$(cat "$W/pf.out")"
  fi
  F="$(row fidelity "$(ob "$PF")")"
  has "1 of 4 discharged" "$F" && ! has "Purchasing Sales" "$F" && ok "fidelity: Purchasing discharged by the real row" || bad "fidelity after run" "$F"
  ( cd "$PF" && node "$PFJS" --no-log prototypes Nope apps/Shop/mdlsource/10-shop.mdl ) > "$W/pf2.out" 2>&1; RC=$?
  [ "$RC" -eq 2 ] && grep -q "no screen named Nope" "$W/pf2.out" && ok "unknown screen: exit 2, names the folder's screens" || bad "unknown screen rc=$RC" "$(cat "$W/pf2.out")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
