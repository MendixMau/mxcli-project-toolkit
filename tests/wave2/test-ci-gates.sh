#!/usr/bin/env bash
# test-ci-gates.sh — bin/ci-gates.sh, the CI gate an agent cannot skip, run the way CI runs it: on a
# fresh clone of the committed tree, without the git-ignored .claude/loop/ ledgers. One project tree per
# failure case, plus a clean one and the installer's never-overwrite contract.
#
# Golden input is produced by the real producers, never typed: page names and screenshots from the
# captured lab app (fixtures/look-shots, mxcli v0.28.0), the owed/seen ledgers by look-ledger.sh owe and
# the seen hook, ready.log / evidence / look-summary.tsv by bin/ready.sh, the "## Current stage" line in
# the exact form gate-check.sh derives, and the BUILD-LOG header and row in the shape exec.sh log_build()
# writes (bin/lib/build-log-read.sh quotes a real row: `| 2026-10-21T05:41:52+0000 | `x.mdl` | … |`).
#
# Usage: bash tests/wave2/test-ci-gates.sh [path-to-bin/ci-gates.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/ci-gates.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TK="$(cd "$(dirname "$SUBJECT")/.." && pwd)"
FXS="$TK/tests/wave2/fixtures/look-shots"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/citest.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"
[ -f "$SUBJECT" ] && [ -d "$FXS" ] || { echo "FAIL — subject or fixture missing"; echo "PASS=0 FAIL=1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export MXTK_NO_GUIDE=1
G() { git -C "$1" "${@:2}"; }
hook() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' "$1"; }

# mkproject <dir> <entry-mode> — wired, three captured pages built through the real owe path
mkproject() {
  mkdir -p "$1/bin" "$1/mdlsource" "$1/shots" "$1/docs/progress"; : > "$1/X.mpr"
  cp "$TK/project-bin/look-ledger.sh" "$TK/project-bin/_common.sh" "$1/bin/"
  printf '# PROJECT.md\n\n## Current stage\n\n**Stage P — Kickoff**, in progress.\n\nEntry mode: %s\n' "$2" > "$1/PROJECT.md"
  printf '.claude/loop/\n' > "$1/.gitignore"
  mkdir -p "$1/docs/progress/must-haves"   # T1's mark, all rows TICKED: READY must not hinge on whether that skill has landed
  printf 'Approval · 2 of 2 rows ticked or NOT DONE with a reason · pages 3 of 3\n1 TICKED — inbox lists open requests\n2 TICKED — decide records the decision\n' > "$1/docs/progress/must-haves/Approval.md"
  printf 'CREATE PAGE "Approval"."Dashboard"\n(\n  Title: %s\n) { }\ncreate or replace page Approval.Approval_Inbox (Title: %s) { }\nCREATE OR MODIFY PAGE Approval.Approval_Decide {\n}\n' "'Dashboard'" "'Approval inbox'" > "$1/mdlsource/20-approval-pages.mdl"
  (cd "$1" && bash bin/look-ledger.sh owe "$1/mdlsource/20-approval-pages.mdl" >/dev/null)
  G "$1" init -q; G "$1" add -A; G "$1" commit -qm scaffold
}
see_all() {
  local s
  for s in dashboard-1280:J-DASH-01-step1.png approval_inbox-1280:J-APP-01-step1.png approval_decide-1280:J-APP-01-step2.png; do
    cp "$FXS/tests/e2e/artifacts/${s#*:}" "$1/shots/${s%%:*}.png"; hook "$1/shots/${s%%:*}.png" | (cd "$1" && bash bin/look-ledger.sh seen)
  done
}
commit_all() { G "$1" add -A; G "$1" commit -qm "$2"; }
ci() { rm -rf "$WORK/ci"; git clone -q "$1" "$WORK/ci"; out="$(bash "$SUBJECT" "$WORK/ci" 2>&1)"; rc=$?; }

# ── C0: clean — every page seen, READY by ready.sh, greenfield ────────────────────────────
P="$WORK/c0"; mkproject "$P" greenfield; see_all "$P"
bash "$TK/bin/gate-check.sh" --no-html --waive P --reason "fixture: kickoff held elsewhere" "$P" >/dev/null 2>&1   # READY needs P-4 passed or waived
commit_all "$P" "kickoff waived"
bash "$TK/bin/ready.sh" "$P" >/dev/null 2>&1 || bad "C0: ready.sh did not pass on a clean project"
ci "$P"
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^PASS  ready' && printf '%s\n' "$out" | grep -q '^PASS  look   look: 3 of 3 pages seen' \
  && ok "C0: clean tree, READY written by ready.sh → CI passes" || bad "C0: rc=$rc $out"
[ ! -e "$WORK/ci/.claude/loop" ] && ok "C0: CI saw no ledger, only the committed summary" || bad "C0: the clone carries the ignored ledger"

# ── C1 (b): READY written by hand ──────────────────────────────────────────────────────────
printf '# Progress\n\n| Module | State |\n|---|---|\n| Approval | READY |\n' > "$P/docs/progress/STATUS.md"; commit_all "$P" "hand status"
ci "$P"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  ready  docs/progress/STATUS.md:5:' \
  && ok "C1: a hand-written READY table cell fails CI, file:line named" || bad "C1: rc=$rc $out"
G "$P" rm -q docs/progress/STATUS.md; G "$P" commit -qm "drop hand status"
# the field shape, verbatim but for the target and date (a field status file carried it five times,
# and the first version of the check passed it): a heading, READY followed by words
printf '# READY FOR BENCH (fix round 6, 2026-11-16 15:34 UTC)\n\nAll pages built.\n\n## READY FOR REVIEW\n' > "$P/docs/progress/status.md"; commit_all "$P" "heading claims"
ci "$P"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  ready  docs/progress/status.md:1: # READY FOR BENCH' \
  && printf '%s\n' "$out" | grep -q '^FAIL  ready  docs/progress/status.md:5: ## READY FOR REVIEW' \
  && ok "C1: heading claims (# READY FOR BENCH ...) fail CI — the field shape" || bad "C1c: rc=$rc $out"
G "$P" rm -q docs/progress/status.md; G "$P" commit -qm "drop heading claims"
# same claim in a lowercase status.md at the ROOT (where the field copy kept it; the first scan matched STATUS*.md only)
printf '# READY FOR BENCH (fix round 6, 2026-11-16 15:34 UTC)\n' > "$P/status.md"; commit_all "$P" "root status"
ci "$P"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  ready  status.md:1: # READY FOR BENCH' \
  && ok "C1: a lowercase status.md at the root is scanned too" || bad "C1d: rc=$rc $out"
G "$P" rm -q status.md; G "$P" commit -qm "drop root status"
# a hand-appended ready.log row with no evidence behind it
printf '2026-11-17T09:00:00Z\tREADY\tmodule Billing\tdocs/progress/ready-2026-11-17-Billing.md\t3 of 3\n' >> "$P/docs/progress/ready.log"; commit_all "$P" "forged log"
ci "$P"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'FAIL  ready  docs/progress/ready.log: READY module Billing' \
  && ok "C1: a READY row appended to ready.log by hand fails CI" || bad "C1b: rc=$rc $out"
G "$P" checkout -q HEAD~1 -- docs/progress/ready.log; G "$P" commit -qm "undo forged log"

# ── C2 (c): READY, then a page built and never looked at ───────────────────────────────────
sleep 1; printf 'CREATE OR MODIFY PAGE Approval.Approval_Archive {\n}\n' > "$P/mdlsource/21-archive.mdl"
(cd "$P" && bash bin/look-ledger.sh owe "$P/mdlsource/21-archive.mdl" >/dev/null && bash bin/look-ledger.sh summary --write >/dev/null)
commit_all "$P" "archive page"
ci "$P"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  look   look: 3 of 4 pages seen — READY (app) while the committed look summary shows 1 built page(s) never looked at: Approval.Approval_Archive' \
  && ok "C2: READY standing over a committed unseen page fails CI" || bad "C2: rc=$rc $out"
# the same tree without a done-claim is a warning mid-build, a FAIL when strict
P2="$WORK/c2b"; mkproject "$P2" greenfield; (cd "$P2" && bash bin/look-ledger.sh summary --write >/dev/null); commit_all "$P2" summary
ci "$P2"
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^WARN  look   look: 0 of 3 pages seen — 3 built page(s) not looked at yet' && ok "C2: no claim → WARN, exit 0 (mid-build)" || bad "C2b: rc=$rc $out"
rm -rf "$WORK/ci"; git clone -q "$P2" "$WORK/ci"; out="$(MXTK_CI_STRICT_LOOK=1 bash "$SUBJECT" "$WORK/ci" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  look   look: 0 of 3 pages seen — 3 built page(s) never looked at (strict)' && ok "C2: MXTK_CI_STRICT_LOOK=1 → FAIL" || bad "C2c: rc=$rc $out"

# ── C3 (a): the register claims Stage 5 and Stage 5 FAILs ──────────────────────────────────
sed -i.bak 's/^\*\*Stage P — Kickoff\*\*, in progress\./**Stage 5 — Build**, in progress (manual gate: its verdict is a Decisions row, not a file) — gates passed: P, 0, 1, 2, 3, 4 (derived by gate-check on 2026-11-17; re-run it rather than editing this line)./' "$P2/PROJECT.md"; rm -f "$P2/PROJECT.md.bak"
commit_all "$P2" "claims stage 5"
ci "$P2"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  stage  the register claims Stage 5 and its gate FAILs: .*3 of 3 built page(s) never looked at' \
  && ok "C3: a claimed stage whose gate FAILs fails CI (from the committed summary)" || bad "C3: rc=$rc $out"

# ── C4 (d): model work before Stage 4, requirements-driven ─────────────────────────────────
P3="$WORK/c4"; mkproject "$P3" requirements-driven
cat > "$P3/docs/BUILD-LOG.md" <<'LOG'
# Build log — auto-appended by bin/exec.sh

One line per exec against the model. Written by the script, not by hand, so it is
true even when someone forgets. Read this before assuming the model builds.

| when (ISO-8601 local) | script | gate | result | detail |
|---|---|---|---|---|
| 2026-10-21T05:41:52+0000 | `20-approval-pages.mdl` | pass | ok | 3 pages |
LOG
commit_all "$P3" "built early"
ci "$P3"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  order  model work (1 exec row(s) in docs/BUILD-LOG.md, 1 build script(s) in mdlsource/) while Stage 4 is' \
  && ok "C4: requirements-driven model work before Stage 4 fails CI" || bad "C4: rc=$rc $out"

bash "$TK/bin/gate-check.sh" --no-html --adopt 5 --reason "joined at build; stages before it were done elsewhere" "$P3" >/dev/null 2>&1
commit_all "$P3" adopt
ci "$P3"
printf '%s\n' "$out" | grep -q '^PASS  order' && ok "C4: an --adopt 5 point clears it" || bad "C4b: $out"

# ── C5 (d): multi-app — build scripts per app, apps/<App>/mdlsource/ ───────────────────────
P6="$WORK/c5"; mkdir -p "$P6/docs"
for a in Sales Stock; do mkdir -p "$P6/apps/$a/mdlsource"; : > "$P6/apps/$a/$a.mpr"
  printf 'CREATE PAGE %s.Overview () { }\n' "$a" > "$P6/apps/$a/mdlsource/10-pages.mdl"; done
printf '# PROJECT.md\n\n## Current stage\n\n**Stage P — Kickoff**, in progress.\n\nEntry mode: requirements-driven\n' > "$P6/PROJECT.md"
G "$P6" init -q; commit_all "$P6" multi
ci "$P6"
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL  order  model work (0 exec row(s) in docs/BUILD-LOG.md, 2 build script(s) in mdlsource/ dirs)' \
  && ok "C5: per-app scripts (apps/<App>/mdlsource/) count as model work" || bad "C5: rc=$rc $out"

# ── I: installer — create if absent, never overwrite ───────────────────────────────────────
. "$TK/bin/lib/ci-template.sh"
P4="$WORK/inst"; mkdir -p "$P4/.github/workflows"; printf 'name: build\n' > "$P4/.github/workflows/build.yml"
m="$(mxtk_ci_install "$TK" "$P4" 0)"
cmp -s "$TK/templates/ci/toolkit-gates.yml" "$P4/.github/workflows/toolkit-gates.yml" && printf '%s' "$m" | grep -q 'existing workflows left untouched: build.yml' \
  && [ "$(cat "$P4/.github/workflows/build.yml")" = "name: build" ] && ok "I1: installed beside the repo's own CI, which is untouched" || bad "I1: $m"
printf '# adapted\n' >> "$P4/.github/workflows/toolkit-gates.yml"
m="$(mxtk_ci_install "$TK" "$P4" 0)"; tail -1 "$P4/.github/workflows/toolkit-gates.yml" | grep -q '^# adapted' && printf '%s' "$m" | grep -q '^Kept:' \
  && ok "I2: an adapted copy is kept and reported, never overwritten" || bad "I2: $m"
P5="$WORK/inst2"; mkdir -p "$P5"; m="$(mxtk_ci_install "$TK" "$P5" 1)"
[ ! -e "$P5/.github" ] && printf '%s' "$m" | grep -q '^Would create' && ok "I3: dry run writes nothing" || bad "I3: $m"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
