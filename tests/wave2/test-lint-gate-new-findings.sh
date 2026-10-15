#!/usr/bin/env bash
# Fixture for #239: a ratchet rise names the findings that are NEW, not three arbitrary ones.
# LINT_JSON mode, generic names, no mxcli or .mpr needed.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
. "$TK/bin/lib/portable.sh"; require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-gate-new.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$GATE" "$P/bin/lint-gate.sh"; [ -f "$TK/project-bin/_common.sh" ] && cp "$TK/project-bin/_common.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/lint-gate.sh"
# f <rule> <doc>...  -> one violation per doc
f() { r="$1"; shift; for d in "$@"; do
  printf '{"ruleId":"%s","severity":"info","message":"msg of %s","module":"Orders","document":"%s","documentType":"microflow","documentId":"i","suggestion":"s"},' "$r" "$d" "$d"; done; }
mk() { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@"); }

echo "T1 baseline stores findings"
mk "$(f CONV009 OldA OldB OldC OldD)"
gate --update-baseline >/dev/null 2>&1
"$PY" -c 'import json,sys;b=json.load(open(sys.argv[1]));assert "CONV009|Orders|OldA|msg of OldA" in b["findings"] and b["counts"]["CONV009"]==4' "$P/.claude/lint-baseline.json" \
  && ok "findings multiset present, counts unchanged" || bad "baseline lacks findings"

echo "T2 a rise lists the new findings, not the first three in model order"
mk "$(f CONV009 OldA OldB OldC OldD NewX NewY)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "rise exits 1" || bad "rc=$rc" "$out"
case "$out" in *"NEW since baseline (2)"*NewX*NewY*) ok "NewX and NewY listed" ;; *) bad "new findings not listed" "$out" ;; esac
case "$out" in *OldA*) bad "old finding OldA shown as an example" "$out" ;; *) ok "old findings not shown" ;; esac

echo "T3 an old counts-only baseline falls back and says so"
printf '{"counts":{"CONV009":4,"MPR001":1},"total":5}\n' > "$P/.claude/lint-baseline.json"
out=$(gate 2>&1)
case "$out" in *"baseline holds counts only"*OldA*) ok "fallback labelled, first three shown" ;; *) bad "no labelled fallback" "$out" ;; esac

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
