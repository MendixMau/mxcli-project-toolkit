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
