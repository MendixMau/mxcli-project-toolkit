#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-due-and-noise.sh /path/to/bin/gate-check.sh
#
# Two obligation-check defects from one field run (requirements-driven, stopped at Stage 4 by
# design, 2026-11-05):
#
#   #627  design-reaches-app was owed from stage 3, but its only producer
#         (check-design-reaches-app.sh against the BUILT stylesheet, ui-preflight-pages.md) runs
#         at the first build, Stage 5. Every Stage 3/4 gate carried a PENDING nothing honest
#         could clear. Owed from 5 now: a Stage 3/4 query does not evaluate it; Stage 5 still does.
#   #623  the obligations "reverse check" — "give it an obligation row in obligations.tsv" — is a
#         message to the toolkit maintainer, and it printed in every consumer project's gate
#         output. It now prints only when gate-check targets the toolkit itself or under
#         MXTK_AUTHORING=1 (and from render-routing.sh --check, which CI runs).
#
# Positive control: against master's gate-check.sh and obligations.tsv, T1 and T3 fail.
set -uo pipefail
GATE="${1:?usage: test-obligation-due-and-noise.sh /path/to/bin/gate-check.sh}"
GATE="$(cd "$(dirname "$GATE")" && pwd)/$(basename "$GATE")"
OBCHECK="$(dirname "$GATE")/lib/obligation-check.sh"
[ -r "$OBCHECK" ] || { echo "no obligation-check.sh at $OBCHECK"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-due.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

P="$WORK/p"; mkdir -p "$P/architecture/modules/Core" "$P/knowledge-base/brd"
printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$P/PROJECT.md"

dra() { MXTK_ROWS_UPTO="$1" "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation design-reaches-app ' | head -1; }

echo "== T1: a Stage 3 query does not owe design-reaches-app (#627) =="
l="$(dra 3)"
case "$l" in '') ok "not evaluated at Stage 3" ;; *) bad "evaluated at Stage 3: $l" ;; esac
l="$(dra 4)"
case "$l" in '') ok "not evaluated at Stage 4" ;; *) bad "evaluated at Stage 4: $l" ;; esac

echo "== T2: from Stage 5 it is owed, and a real report still discharges it =="
l="$(dra 5)"
case "$l" in *PENDING*) ok "owed at Stage 5 with no report" ;; *) bad "expected PENDING at Stage 5, got: $l" ;; esac
mkdir -p "$P/docs"
printf 'design-reaches-app: 35 of 35 knobs bound, 18 of 18 tokens arrived, 20 of 20 classes arrived\n' > "$P/docs/design-reaches-app.md"
l="$(dra 5)"
case "$l" in *PASS*) ok "a report with denominators discharges it" ;; *) bad "expected PASS, got: $l" ;; esac

echo "== T3: a consumer project's gate output carries no reverse-check line (#623) =="
out="$("$GATE" --no-html "$P" 3 2>&1)"
case "$out" in *'reverse check'*) bad "reverse check shown to a consumer: $(printf '%s' "$out" | grep -m1 'reverse check')" ;;
               *) ok "no toolkit-authoring message in a consumer project" ;; esac

echo "== T4: MXTK_AUTHORING=1 still runs it (the check was moved, not deleted) =="
out="$(MXTK_AUTHORING=1 "$GATE" --no-html "$P" 3 2>&1)"
case "$out" in *'Obligations reverse check'*) ok "reverse check runs under MXTK_AUTHORING=1" ;;
               *) bad "reverse check missing under MXTK_AUTHORING=1" ;; esac

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
