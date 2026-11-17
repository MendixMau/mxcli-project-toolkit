#!/usr/bin/env bash
# test-ready.sh — bin/ready.sh: READY only when every check passes, K of N on every row, the
# evidence written and committed; plus the tracked look summary gate-check.sh reads from a copy.
#
# Golden input is captured, not imagined: the page names are the captured lab app's
# (fixtures/look-shots/show-pages-Approval.out, a finished Purchasing/Approval app, mxcli v0.28.0),
# the screenshots are that run's real PNGs, the owed ledger is written by the real
# `look-ledger.sh owe` from a build script in the captured statement shapes, and the seen ledger
# by the real `seen` hook from Claude Code's PostToolUse JSON. Nothing in .claude/loop/ is typed.
#
# Usage: bash tests/wave2/test-ready.sh [path-to-bin/ready.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/ready.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TK="$(cd "$(dirname "$SUBJECT")/.." && pwd)"
FXS="$TK/tests/wave2/fixtures/look-shots"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/readytest.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"
[ -f "$SUBJECT" ] && [ -d "$FXS" ] || { echo "FAIL — subject or fixture missing"; echo "PASS=0 FAIL=1"; exit 1; }

# ready.sh commits with the caller's git identity; a CI runner has none
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
hook() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' "$1"; }
G() { git -C "$1" -c user.email=t@example.invalid -c user.name=t "${@:2}"; }

# mkproject <dir> <root|app> [mode] — a wired project: bin/ installed, three captured pages built
mkproject() {
  mkdir -p "$1/bin" "$1/mdlsource" "$1/shots" "$1/docs/progress"
  if [ "$2" = app ]; then mkdir -p "$1/app"; : > "$1/app/X.mpr"; else : > "$1/X.mpr"; fi
  cp "$TK/project-bin/look-ledger.sh" "$TK/project-bin/_common.sh" "$1/bin/"
  printf '# PROJECT.md\n\n## Current stage\n\n**Stage P — Kickoff**, in progress.\n\n%s\n' "${3:+Interview mode: $3}" > "$1/PROJECT.md"
  printf '.claude/loop/\n' > "$1/.gitignore"
  cat > "$1/mdlsource/20-approval-pages.mdl" <<'MDL'
CREATE PAGE "Approval"."Dashboard"
(
  Title: 'Dashboard'
) { }
create or replace page Approval.Approval_Inbox (Title: 'Approval inbox') { }
CREATE OR MODIFY PAGE Approval.Approval_Decide {
}
MDL
  (cd "$1" && bash bin/look-ledger.sh owe "$1/mdlsource/20-approval-pages.mdl" >/dev/null)
  G "$1" init -q; G "$1" add -A; G "$1" commit -qm scaffold
}
# see <dir> <page-file-stem> <captured png> — a screenshot named for its page, opened by the agent
see() { cp "$FXS/tests/e2e/artifacts/$3" "$1/shots/$2.png"; hook "$1/shots/$2.png" | (cd "$1" && bash bin/look-ledger.sh seen); }
see_all() { see "$1" dashboard-1280 J-DASH-01-step1.png; see "$1" approval_inbox-1280 J-APP-01-step1.png; see "$1" approval_decide-1280 J-APP-01-step2.png; }
# review <dir> <reviewer> <builder> <score-for-Decide>
review() {
  mkdir -p "$1/docs/progress/look-reviews"
  cat > "$1/docs/progress/look-reviews/look-review-Approval.md" <<EOF
# Look review — Approval
Reviewer: review-agent (fresh dispatch)
Builder: $3
Reviewed: $(date -u +%Y-%m-%dT%H:%M:%SZ)

| Page | Screenshot | Target | Score | Note |
|---|---|---|---|---|
| Approval.Dashboard | shots/dashboard-1280.png | design/wireframes/dashboard.html | 5 | matches |
| Approval.Approval_Inbox | shots/approval_inbox-1280.png | design/wireframes/approval-inbox.html | 4 | spacing |
| Approval.Approval_Decide | shots/approval_decide-1280.png | design/wireframes/approval-decide.html | $4 | buttons |
EOF
  [ "$2" = same ] && sed -i.bak "s/^Reviewer: .*/Reviewer: $3/" "$1/docs/progress/look-reviews/look-review-Approval.md" && rm -f "$1/docs/progress/look-reviews/"*.bak
}
run() { out="$(bash "$SUBJECT" "$@" 2>&1)"; rc=$?; }

# ── R1: owed but unseen pages → NOT READY, K of N, evidence committed ──────────────────────
P="$WORK/r1"; mkproject "$P" root
see "$P" dashboard-1280 J-DASH-01-step1.png
run "$P"
[ "$rc" = 1 ] && ok "R1: 1 of 3 seen → exit 1" || bad "R1: rc=$rc"
printf '%s\n' "$out" | grep -q 'FAIL  look      1 of 3 page(s) looked at' && ok "R1: look row says 1 of 3" || bad "R1: $out"
printf '%s\n' "$out" | grep -q '^NOT-READY — 0 of 2 checks pass' && ok "R1: verdict NOT-READY with its denominator" || bad "R1: verdict: $out"
ev="$(ls "$P"/docs/progress/ready-*-app.md 2>/dev/null | head -1)"
[ -n "$ev" ] && grep -q '^- Approval.Approval_Inbox' "$ev" && grep -q 'Approval.Dashboard: dashboard-1280.png' "$ev" \
  && ok "R1: evidence names the unseen pages and the screenshot relied on" || bad "R1: evidence $(cat "$ev" 2>/dev/null)"
G "$P" ls-files --error-unmatch docs/progress/ready.log docs/progress/look-summary.tsv "${ev#"$P"/}" >/dev/null 2>&1 \
  && ok "R1: evidence, ready.log and look-summary.tsv are committed" || bad "R1: not committed: $(G "$P" status --short)"
grep -q '^as-of.*owed 3	seen 1	unseen 2' "$P/docs/progress/look-summary.tsv" && ok "R1: look-summary.tsv says owed 3 seen 1" || bad "R1: summary $(cat "$P/docs/progress/look-summary.tsv")"

# ── R2: a copy of the repo (no ignored ledger) — gate-check reads the committed summary ────
C="$WORK/r1-copy"; git clone -q "$P" "$C" 2>/dev/null
[ ! -e "$C/.claude/loop" ] || bad "R2: the clone has the ignored ledger"
g="$(bash "$TK/bin/gate-check.sh" --no-html "$C" 5 2>&1 | grep -m1 '^Stage 5 (')"
printf '%s' "$g" | grep -q 'FAIL.*2 of 3 built page(s) never looked at.*committed docs/progress/look-summary.tsv' \
  && ok "R2: a copy reports Stage 5 FAIL 2 of 3 from git, not MANUAL" || bad "R2: $g"
run "$C" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'look      1 of 3' && ok "R2: ready.sh on the copy is NOT READY, 1 of 3" || bad "R2: rc=$rc $out"

# ── R3: all seen, steering → READY, the READY line written by the script ───────────────────
see_all "$P"
run "$P"
[ "$rc" = 0 ] && ok "R3: all 3 seen → READY exit 0" || bad "R3: rc=$rc $out"
tail -1 "$P/docs/progress/ready.log" | grep -q '	READY	app	' && ok "R3: ready.log carries the READY line" || bad "R3: log $(tail -1 "$P/docs/progress/ready.log")"
G "$P" log -1 --format=%s | grep -q '^ready: app READY (2 of 2 checks)' && ok "R3: committed as 'ready: app READY'" || bad "R3: $(G "$P" log -1 --format=%s)"
grep -q '^as-of.*owed 3	seen 3	unseen 0' "$P/docs/progress/look-summary.tsv" && ok "R3: summary refreshed to 3 of 3" || bad "R3: summary"

# ── R4: unattended (auto) needs an independent review ──────────────────────────────────────
P="$WORK/r4"; mkproject "$P" root auto; see_all "$P"
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'FAIL  review    0 of 3 page(s) scored 4+' && ok "R4: auto, no reviewer file → NOT READY, review 0 of 3" || bad "R4: rc=$rc $out"
review "$P" other mdl-agent 3
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'review    2 of 3 .*below 4: Approval.Approval_Decide=3' && ok "R4: a page scored 3 blocks, named" || bad "R4: $out"
review "$P" same mdl-agent 5
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'ignored: needs distinct Reviewer: and Builder:' && ok "R4: a self-review (Reviewer = Builder) is not read" || bad "R4: $out"
review "$P" other mdl-agent 4
run "$P" --no-commit
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'PASS  review    3 of 3' && ok "R4: all seen + independent review 4+ → READY" || bad "R4: rc=$rc $out"
# a page rebuilt after the review is owed a new score (and a new look)
sleep 1; (cd "$P" && bash bin/look-ledger.sh owe "$P/mdlsource/20-approval-pages.mdl" >/dev/null); see_all "$P"
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'review    0 of 3 .*unscored since last build' && ok "R4: a rebuild after the review voids its scores" || bad "R4: $out"

# ── R5: --module scope; another module's unseen page does not block this one ───────────────
P="$WORK/r5"; mkproject "$P" app; see_all "$P"
printf 'CREATE OR MODIFY PAGE Billing.Invoice_View {\n}\n' > "$P/mdlsource/30-billing.mdl"
(cd "$P" && bash bin/look-ledger.sh owe "$P/mdlsource/30-billing.mdl" >/dev/null)
run "$P" --module Approval --no-commit
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'look      3 of 3' && ok "R5 (two-tree): --module Approval READY, 3 of 3" || bad "R5: rc=$rc $out"
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'look      3 of 4' && ok "R5 (two-tree): the whole app is NOT READY, 3 of 4" || bad "R5: rc=$rc $out"
run "$P" --module Nope --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'look      NOT MEASURED' && ok "R5: a module with no built page is NOT MEASURED, never green" || bad "R5: $out"

# ── R6: must-have list, when present ───────────────────────────────────────────────────────
mkdir -p "$P/architecture/modules/Approval"
printf '# Must-haves — Approval\n- [x] inbox lists open requests\n- [ ] decide sends a notification\n' > "$P/architecture/modules/Approval/must-haves.md"
run "$P" --module Approval --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'must-have 1 of 2 ticked' && ok "R6: an unticked must-have blocks, 1 of 2" || bad "R6: $out"

# ── R7: no ledger at all → NOT MEASURED ────────────────────────────────────────────────────
P="$WORK/r7"; mkdir -p "$P"; printf '# PROJECT.md\n' > "$P/PROJECT.md"
run "$P" --no-commit
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'look      NOT MEASURED' && ok "R7: no ledger → NOT READY, look NOT MEASURED" || bad "R7: rc=$rc $out"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
