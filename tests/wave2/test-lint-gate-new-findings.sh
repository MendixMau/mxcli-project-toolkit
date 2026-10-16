#!/usr/bin/env bash
# Usage: bash test-lint-gate-new-findings.sh [path-to-lint-gate.sh]
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
case "$out" in *"+ Orders | NewX"*"+ Orders | NewY"*) ok "NewX and NewY listed" ;; *) bad "new findings not listed" "$out" ;; esac
case "$out" in *OldA*) bad "old finding OldA shown as an example" "$out" ;; *) ok "old findings not shown" ;; esac

echo "T3 an old counts-only baseline falls back and says so"
printf '{"counts":{"CONV009":4,"MPR001":1},"total":5}\n' > "$P/.claude/lint-baseline.json"
out=$(gate 2>&1)
case "$out" in *"baseline holds counts only"*OldA*) ok "fallback labelled, first three shown" ;; *) bad "no labelled fallback" "$out" ;; esac

echo "T4 reworded message: new-or-changed count differs from the net rise and says so"
mk "$(f CONV009 OldA OldB OldC OldD)"
gate --update-baseline >/dev/null 2>&1
mk "$(f CONV009 OldA OldB OldC OldD | sed 's/msg of OldA/msg of OldA reworded/') $(f CONV009 NewX)"
out=$(gate 2>&1)
case "$out" in *"new or changed findings (2); net rise +1"*) ok "labelled N vs net rise" ;; *) bad "no N vs net rise label" "$out" ;; esac

echo "T5 17 risen rules: compact view, 60-line window shows all rules, full list in lint-last"
docs=""; base=""; i=1
while [ $i -le 17 ]; do
  r=$(printf 'RULE%03d' $i)
  base="$base$(f $r OldA OldB)"
  docs="$docs$(f $r OldA OldB N1 N2 N3 N4 N5 N6 N7)"
  i=$((i+1))
done
mk "$base"; rm -f "$P/.claude/lint-baseline.json"; gate --update-baseline >/dev/null 2>&1
mk "$docs"
out=$(gate 2>&1)
vis=$(printf '%s\n' "$out" | sed -n '/^FAIL/,$p' | head -60 | grep -c ' -> ')
[ "$vis" -ge 12 ] && ok "$vis rules visible in 60 lines (master: 12)" || bad "only $vis rules visible" "$out"
case "$out" in *"more in .claude/loop/lint-last.json"*) ok "overflow line names the file" ;; *) bad "no overflow pointer" ;; esac
"$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));assert len(d["new_findings"])==17 and all(len(v)==7 for v in d["new_findings"].values())' "$P/.claude/loop/lint-last.json" \
  && ok "lint-last holds the full 7 per rule" || bad "lint-last.json lacks new_findings"

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
