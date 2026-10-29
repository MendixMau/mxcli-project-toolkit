#!/usr/bin/env bash
# test-look-ledger.sh — project-bin/look-ledger.sh (pages owed a LOOK, screenshots seen) and the
# Stage 5 check in bin/gate-check.sh that joins them.
#
# Covers: the page parser on every statement shape captured from real build scripts (CREATE /
# CREATE OR REPLACE / CREATE OR MODIFY / ALTER, either case, quoted or bare halves; comments and
# snippets skipped; duplicates once); `owe` from an INSTALLED copy on both layouts (model at the
# root, and under app/); `seen` from real hook JSON — a fresh screenshot counts, a wireframe
# render, a non-image and a screenshot older than the build do not, and a shrunk copy maps back
# to its original through the .src sidecar; `status`; and Stage 5 — FAIL naming the unseen page,
# cleared by a waiver line, and unchanged MANUAL with no ledger at all.
#
# The script lines below are the statement shapes found in real build scripts (a
# requirements-driven PoC project and this repo's own .mdl files, 2026-10-02), with the
# module and page names made generic. The hook JSON is the PostToolUse shape Claude Code sends.
#
# Usage: bash tests/wave2/test-look-ledger.sh [path-to-project-bin/look-ledger.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/look-ledger.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TOOLKIT_ROOT="$(cd "$(dirname "$SUBJECT")/.." && pwd)"
GATE="$TOOLKIT_ROOT/bin/gate-check.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/looktest.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"
[ -f "$SUBJECT" ] || { echo "FAIL — subject not found: $SUBJECT"; echo "PASS=0 FAIL=1"; exit 1; }

# A project with the ledger installed the way init-project.sh installs it: bin/ beside the model.
mkproject() {  # $1 = dir, $2 = "root" | "app"
  mkdir -p "$1/bin" "$1/mdlsource" "$1/shots" "$1/design/wireframes"
  if [ "$2" = app ]; then mkdir -p "$1/app"; : > "$1/app/X.mpr"; else : > "$1/X.mpr"; fi
  cp "$SUBJECT" "$TOOLKIT_ROOT/project-bin/_common.sh" "$1/bin/"
  cat > "$1/mdlsource/10-pages.mdl" <<'MDL'
/**
 * CREATE PAGE Orders.Commented_Out
 */
-- CREATE PAGE Orders.Also_Commented (
CREATE PAGE "Orders"."Order_Overview"
(
  Title: 'Orders'
) { }
create or replace page Orders.Order_Edit (Title: 'Edit order') { }
CREATE OR MODIFY PAGE Billing.Invoice_View {
}
ALTER PAGE Orders.Order_Edit {
  SET Title = 'Edit'
};
CREATE SNIPPET Orders.Order_Header { }
MDL
}
hook() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' "$1"; }

# ── L1: the parser ─────────────────────────────────────────────────────────────────────────
P="$WORK/p-root"; mkproject "$P" root
got="$(bash "$P/bin/look-ledger.sh" pages "$P/mdlsource/10-pages.mdl" | tr '\n' ' ')"
[ "$got" = "Orders.Order_Overview Orders.Order_Edit Billing.Invoice_View " ] \
  && ok "L1: parser finds the 3 pages, skips comments and the snippet, dedupes the ALTER" \
  || bad "L1: parser got '$got'"

# ── L2: owe, from an installed copy, on both layouts ───────────────────────────────────────
for layout in root app; do
  P="$WORK/p-$layout"; [ -d "$P" ] || mkproject "$P" "$layout"
  out="$(cd "$P" && bash bin/look-ledger.sh owe "$P/mdlsource/10-pages.mdl")"
  n="$(wc -l < "$P/.claude/loop/look/owed.tsv" 2>/dev/null | tr -d ' ')"
  [ "$n" = 3 ] && ok "L2 ($layout): owe wrote 3 rows under the project's .claude/loop/look/" \
               || bad "L2 ($layout): owed.tsv has '${n:-no}' rows"
  printf '%s' "$out" | grep -q '3 page(s) built' && ok "L2 ($layout): owe tells the agent what it owes" \
                                                 || bad "L2 ($layout): owe printed no notice"
done

# ── L3: seen ───────────────────────────────────────────────────────────────────────────────
P="$WORK/p-app"
printf 'png' > "$P/shots/order-overview.png"
printf 'png' > "$P/shots/Invoice_View.png"; touch -t 202001010000 "$P/shots/Invoice_View.png"
printf 'png' > "$P/design/wireframes/order-edit.png"
printf 'md'  > "$P/shots/order-edit.md"
for f in shots/order-overview.png shots/Invoice_View.png design/wireframes/order-edit.png shots/order-edit.md; do
  hook "$P/$f" | (cd "$P" && bash bin/look-ledger.sh seen)
done
n="$(wc -l < "$P/.claude/loop/look/seen.tsv" 2>/dev/null | tr -d ' ')"
[ "$n" = 2 ] && ok "L3: 2 image reads logged; the wireframe render and the .md were not" \
             || bad "L3: seen.tsv has '${n:-no}' rows, expected 2"

# ── L4: a shrunk copy maps back to its original through the .src sidecar ──────────────────
mkdir -p "$WORK/cache"; printf 'png' > "$P/shots/order-edit-1280.png"
printf 'small' > "$WORK/cache/abc123.png"; printf '%s\n' "$P/shots/order-edit-1280.png" > "$WORK/cache/abc123.src"
hook "$WORK/cache/abc123.png" | (cd "$P" && bash bin/look-ledger.sh seen)
grep -qF "$P/shots/order-edit-1280.png" "$P/.claude/loop/look/seen.tsv" \
  && ok "L4: the Read of the shrunk copy is logged under the original screenshot" \
  || bad "L4: the shrunk copy was not mapped back to its original"

# ── L5: status ─────────────────────────────────────────────────────────────────────────────
st="$(cd "$P" && bash bin/look-ledger.sh status | awk -F'\t' '{printf "%s=%s ", $2, $1}')"
[ "$st" = "Billing.Invoice_View=OWED Orders.Order_Edit=SEEN Orders.Order_Overview=SEEN " ] \
  && ok "L5: status — two pages seen, the one with only a stale screenshot still owed" \
  || bad "L5: status got '$st'"

# ── S: journey screenshots as LOOK evidence (speed experiment E2) ──────────────────────────
# Golden input is a real journey run: fixtures/look-shots/journey-findings.json and its PNGs were
# written by journey-runner.js against a finished Purchasing/Approval lab app (mxcli v0.28.0), and
# the stub mxcli replays that app's captured `SHOW PAGES IN Approval` / `DESCRIBE PAGE` output.
FXS="$TOOLKIT_ROOT/tests/wave2/fixtures/look-shots"
if [ -d "$FXS" ] && command -v node >/dev/null 2>&1; then
  P="$WORK/p-shots"; mkproject "$P" root
  cp "$TOOLKIT_ROOT/project-bin/look-shots.js" "$P/bin/"
  mkdir -p "$P/tests/e2e/artifacts"; cp "$FXS"/tests/e2e/artifacts/*.png "$P/tests/e2e/artifacts/"; cp "$FXS/journey-findings.json" "$P/tests/e2e/artifacts/"
  cat > "$P/mxcli" <<STUB
#!/usr/bin/env bash
q=""; while [ \$# -gt 0 ]; do [ "\$1" = -c ] && q="\$2"; shift; done
case "\$q" in "SHOW PAGES IN Approval") cat "$FXS/show-pages-Approval.out"; exit 0 ;; "SHOW PAGES IN "*) exit 0 ;; esac
printf '%s\n' "\$q" | tr ';' '\n' | sed -n 's/^ *DESCRIBE PAGE \([^ ]*\) *\$/\1/p' | while IFS= read -r n; do cat "$FXS/describe-\$n.out"; done
exit 0
STUB
  chmod +x "$P/mxcli"
  mkdir -p "$P/.claude/loop/look"
  past=$(( $(date +%s) - 3600 ))
  for pg in Approval.Approval_Decide Approval.Approval_Inbox Approval.Dashboard Approval.Approval_Ghost; do
    printf '%s\t2026-01-01T00:00:00Z\t%s\tmdlsource/x.mdl\n' "$past" "$pg" >> "$P/.claude/loop/look/owed.tsv"
  done
  out="$(cd "$P" && bash bin/look-ledger.sh shots 2>&1)"
  printf '%s\n' "$out" | grep -q '^owed 4 = 3 OPEN .* + 1 UNREACHED' \
    && ok "S1: denominator — 4 owed = 3 OPEN + 1 UNREACHED (the page no journey reached is listed, not dropped)" \
    || bad "S1: got: $out"
  printf '%s\n' "$out" | grep -q 'UNREACHED.Approval.Approval_Ghost' && ok "S1: the unreached page is named" || bad "S1: ghost not listed: $out"
  printf '%s\n' "$out" | grep -q 'OPEN.Approval.Dashboard.*J-DASH-01-step1.png' && printf '%s\n' "$out" | grep -q 'OPEN.Approval.Approval_Decide.*J-APP-01-step2.png' \
    && ok "S1: a popup/parameter page (Approval_Decide, url decide/{Request}) is attributed to the step that landed on it" || bad "S1: attribution: $out"
  # nothing is SEEN merely because a journey took the shot: the agent has to open it
  st="$(cd "$P" && bash bin/look-ledger.sh status | awk -F'\t' '{printf "%s=%s ", $2, $1}')"
  [ "$st" = "Approval.Approval_Decide=OWED Approval.Approval_Ghost=OWED Approval.Approval_Inbox=OWED Approval.Dashboard=OWED " ] \
    && ok "S2: before any Read every page is still OWED (a shot on disk is not a LOOK)" || bad "S2: status '$st'"
  hook "$P/tests/e2e/artifacts/J-DASH-01-step1.png" | (cd "$P" && bash bin/look-ledger.sh seen)
  hook "$P/tests/e2e/artifacts/J-APP-01-step2.png" | (cd "$P" && bash bin/look-ledger.sh seen)
  st="$(cd "$P" && bash bin/look-ledger.sh status | awk -F'\t' '{printf "%s=%s ", $2, $1}')"
  [ "$st" = "Approval.Approval_Decide=SEEN Approval.Approval_Ghost=OWED Approval.Approval_Inbox=OWED Approval.Dashboard=SEEN " ] \
    && ok "S3: opening a journey shot (file name carries no page name) marks exactly its page SEEN" || bad "S3: status '$st'"
  # a read of a shot that is NOT attributed to the page does not clear it
  hook "$P/tests/e2e/artifacts/J-APP-01-step2.png" | (cd "$P" && bash bin/look-ledger.sh seen)
  [ "$(cd "$P" && bash bin/look-ledger.sh status | awk -F'\t' '$2 == "Approval.Approval_Inbox" {print $1}')" = OWED ] \
    && ok "S3b: reading the Decide shot does not clear Approval_Inbox" || bad "S3b: Inbox cleared by another page's shot"
  # a page rebuilt after the shot: the shot shows the previous build, so it is UNREACHED again
  printf '%s\t2026-01-01T00:00:00Z\tApproval.Dashboard\tmdlsource/y.mdl\n' "$(( $(date +%s) + 3600 ))" >> "$P/.claude/loop/look/owed.tsv"
  out="$(cd "$P" && bash bin/look-ledger.sh shots 2>&1)"
  printf '%s\n' "$out" | grep -q 'UNREACHED.Approval.Dashboard' && ok "S4: a shot older than the page's last build is not evidence (UNREACHED)" || bad "S4: $out"
  # no mxcli: say NOT MEASURED, every owed page listed
  mv "$P/mxcli" "$P/mxcli.off"
  out="$(cd "$P" && MXCLI=/nonexistent bash bin/look-ledger.sh shots 2>&1)"
  printf '%s\n' "$out" | grep -q 'NOT MEASURED' && printf '%s\n' "$out" | grep -q '^owed [0-9]* = 0 OPEN' \
    && ok "S5: no model to read widgets from — NOT MEASURED, all owed pages UNREACHED, never a silent pass" || bad "S5: $out"
  mv "$P/mxcli.off" "$P/mxcli"
  # look-shots.js directly: a widget shared by two pages is claimed only when the URL picks one
  W="$WORK/ls"; mkdir -p "$W/img"; head -c 20000 /dev/zero > "$W/img/a.png"
  printf 'M.A\tdgList\nM.B\tdgList\n' > "$W/widgets.tsv"
  mkfind() { printf '{"walks":[{"journey":"J","steps":[{"n":1,"reached":true,"expects":{"landsOn":".mx-name-dgList"},"shot":{"file":"%s","url":"%s"}}]}]}' "$W/img/a.png" "$1" > "$W/f.json"; }
  printf 'M.A\ta\nM.B\tb\n' > "$W/pages.tsv"; mkfind "http://h/p/a"
  node "$P/bin/look-shots.js" --root "$W" --widgets "$W/widgets.tsv" --pages "$W/pages.tsv" --out "$W/o.tsv" "$W/f.json" >/dev/null
  [ "$(cut -f3 "$W/o.tsv")" = "M.A" ] && ok "S6: two pages share the widget; the shot's URL (/p/a) picks M.A" || bad "S6: $(cat "$W/o.tsv")"
  mkfind "http://h/p/zzz"
  node "$P/bin/look-shots.js" --root "$W" --widgets "$W/widgets.tsv" --pages "$W/pages.tsv" --out "$W/o.tsv" "$W/f.json" >/dev/null
  [ ! -s "$W/o.tsv" ] && ok "S6b: ambiguous and the URL picks none — claimed for no page (when unsure, do not claim)" || bad "S6b: $(cat "$W/o.tsv")"
else
  bad "S: fixtures/look-shots or node missing"
fi
P="$WORK/p-app"   # G1-G3 below run on the L-section project

# ── G1-G3: Stage 5 in gate-check.sh ────────────────────────────────────────────────────────
if [ -x "$GATE" ] || [ -f "$GATE" ]; then
  printf '# PROJECT\n\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$P/PROJECT.md"
  out="$(bash "$GATE" "$P" 5 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep -E '^Stage 5 ')"
  { [ "$rc" = 1 ] && printf '%s' "$line" | grep -q 'FAIL' && printf '%s' "$line" | grep -q 'Billing.Invoice_View' \
      && ! printf '%s' "$line" | grep -q 'Orders.Order_Edit'; } \
    && ok "G1: Stage 5 FAILs (exit 1) and names only the unseen page" \
    || bad "G1: expected FAIL naming Billing.Invoice_View, got rc=$rc: $line"

  printf '\nWaived obligation look/Billing: no client-facing page in this module\n' >> "$P/PROJECT.md"
  out="$(bash "$GATE" "$P" 5 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep -E '^Stage 5 ')"
  { [ "$rc" = 2 ] && printf '%s' "$line" | grep -q '3 of 3 built page(s) accounted for'; } \
    && ok "G2: a look/<Module> waiver line clears it — MANUAL, 3 of 3 accounted for" \
    || bad "G2: expected MANUAL after the waiver, got rc=$rc: $line"

  P="$WORK/p-none"; mkproject "$P" root; cp "$WORK/p-app/PROJECT.md" "$P/"
  out="$(bash "$GATE" "$P" 5 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep -E '^Stage 5 ')"
  { [ "$rc" = 2 ] && printf '%s' "$line" | grep -q 'not file-existence-checkable'; } \
    && ok "G3: no ledger — Stage 5 stays the plain MANUAL it was" \
    || bad "G3: expected plain MANUAL with no ledger, got rc=$rc: $line"
else
  bad "gate-check.sh not found at $GATE — cannot run G1-G3"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
