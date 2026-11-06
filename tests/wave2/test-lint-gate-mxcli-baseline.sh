#!/usr/bin/env bash
# Usage: bash test-lint-gate-mxcli-baseline.sh [path-to-lint-gate.sh]
# Fixture for the native-baseline step of project-bin/lint-gate.sh (mxcli >= v0.30.0
# `lint --baseline`, MTA E2 follow-up, 2026-11-06): a NEW finding fails the gate even when a fix
# elsewhere in the same rule keeps the rule's count flat (a swap), which the count ratchet cannot
# see. No .mpr and no real mxcli: a stub `mxcli` answers --version, `lint --help`, and
# `lint ... --baseline f [--update-baseline]` from captured-shape JSON (keys of a real
# `mxcli lint --format json`: ruleId, severity, message, module, document, documentType,
# documentId, suggestion). T1-T3, T8 use LINT_JSON + LINT_NEW_JSON (the compare result captured).
# Keep bash-3.2 compatible.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
. "$TK/bin/lib/portable.sh"; require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-gate-mxb.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$GATE" "$P/bin/lint-gate.sh"; [ -f "$TK/project-bin/_common.sh" ] && cp "$TK/project-bin/_common.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; chmod +x "$P/bin/lint-gate.sh"
# Stub mxcli. FAKE_VERSION is the --version line; FAKE_HELP_BASELINE=1 lists --baseline in lint --help.
cat > "$P/mxcli" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in
  --version) echo "$FAKE_VERSION"; exit 0 ;;
esac
if [ "$1" = lint ]; then
  case "$*" in
    *--help*) echo "Usage: mxcli lint"; [ "${FAKE_HELP_BASELINE:-0}" = 1 ] && echo "      --baseline string   Report only findings not recorded"; exit 0 ;;
    *--update-baseline*) f=""; prev=""; for a in "$@"; do [ "$prev" = --baseline ] && f="$a"; prev="$a"; done
                         printf '{"version":1,"findings":[]}\n' > "$f"; exit 0 ;;
    *--baseline*) cat "$FAKE_NEW_JSON"; exit 0 ;;
    *) cat "$FAKE_LINT_JSON"; exit 0 ;;
  esac
fi
exit 0
STUB
chmod +x "$P/mxcli"
export STUB_LOG="$WORK/stub.log" FAKE_LINT_JSON="$WORK/lint.json" FAKE_NEW_JSON="$WORK/new.json"

# f <rule> <doc>...  -> one violation per doc
f() { r="$1"; shift; for d in "$@"; do
  printf '{"ruleId":"%s","severity":"info","message":"msg of %s","module":"Orders","document":"%s","documentType":"entity","documentId":"i","suggestion":"s"},' "$r" "$d" "$d"; done; }
mk()    { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
mknew() { printf '{"violations":[%s],"summary":{}}' "${1%,}" > "$WORK/new.json"; }
mknone(){ printf '{"violations":null,"summary":{"total":0}}' > "$WORK/new.json"; }
gate()  { (cd "$P" && bash bin/lint-gate.sh "$@" </dev/null); }
gatej() { (cd "$P" && LINT_JSON="$WORK/lint.json" LINT_NEW_JSON="$WORK/new.json" bash bin/lint-gate.sh "$@" </dev/null); }
reset() { rm -rf "$P/.claude/lint-baseline.json" "$P/.claude/lint-mxcli-baseline.json" "$P/.claude/loop" "$P/.claude/lint-acceptances.tsv" "$P/.git"; : > "$STUB_LOG"; }

echo "T1 swap: a new CONV007 finding offset by a fix in the same rule fails; the count ratchet alone passes"
export FAKE_VERSION="mxcli v0.30.0 (2026-11-02)"
reset; mk "$(f CONV007 OldA OldB OldC)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -s "$P/.claude/lint-mxcli-baseline.json" ] && ok "first --update-baseline writes both baselines" || bad "rc=$rc" "$out"
case "$out" in *"native baseline written"*) ok "says where the mxcli baseline went" ;; *) bad "no baseline-written line" "$out" ;; esac
mk "$(f CONV007 OldA OldB NewX)"           # OldC fixed, NewX added: count 3 -> 3
mknew "$(f CONV007 NewX)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "swap exits 1" || bad "swap rc=$rc" "$out"
case "$out" in *"3 -> 3  (+0)  1 new"*"+ Orders | NewX | msg of NewX"*) ok "names rule, '(+0)  1 new' and the new finding" ;; *) bad "swap not named" "$out" ;; esac
case "$out" in *"count did not rise"*) ok "says why the count missed it" ;; *) bad "no explanation" "$out" ;; esac
"$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["verdict"]=="FAIL" and d["new_findings"]["CONV007"]' "$P/.claude/loop/lint-last.json" \
  && ok "lint-last.json: FAIL with new_findings (exec.sh itemises from it)" || bad "lint-last.json wrong"
LINT_MXCLI_BASELINE=0 gate >"$WORK/o" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "switched off" "$WORK/o" && ok "LINT_MXCLI_BASELINE=0: ratchet alone passes the same swap, with a note" || bad "opt-out rc=$rc" "$(cat "$WORK/o")"

echo "T2 unchanged tree: clean pass, one native compare"
mk "$(f CONV007 OldA OldB OldC)"; mknone; : > "$STUB_LOG"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "rc 0" || bad "rc=$rc" "$out"
case "$out" in *"0 new finding(s)"*) ok "reports 0 new" ;; *) bad "no 0-new line" "$out" ;; esac
[ "$(grep -c -- '--baseline' "$STUB_LOG")" -eq 1 ] && ok "one --baseline compare run" || bad "stub log" "$(cat "$STUB_LOG")"

echo "T3 a rise in a rule still reports through the ratchet (new findings once, no duplicate block)"
mk "$(f CONV007 OldA OldB OldC NewX)"; mknew "$(f CONV007 NewX)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "rise exits 1" || bad "rc=$rc" "$out"
n=$(printf '%s\n' "$out" | grep -c "msg of NewX"); [ "$n" -eq 1 ] && ok "NewX listed once" || bad "NewX listed $n times" "$out"
case "$out" in *"count did not rise"*) bad "swap block printed for a plain rise" "$out" ;; *) ok "no swap block" ;; esac

echo "T4 older mxcli: count ratchet only, with a note, no --baseline call"
for v in "mxcli v0.29.2 (2026-10-20)" "mxcli 0.26.0"; do
  export FAKE_VERSION="$v"; export FAKE_HELP_BASELINE=1   # help is not consulted when a semver is present
  reset; mk "$(f CONV007 OldA OldB OldC)"
  out=$(gate --update-baseline 2>&1); rc=$?
  [ ! -f "$P/.claude/lint-mxcli-baseline.json" ] && [ "$rc" -eq 0 ] && ok "[$v] no mxcli baseline written" || bad "[$v] rc=$rc" "$out"
  mk "$(f CONV007 OldA OldB NewX)"; mknew "$(f CONV007 NewX)"
  out=$(gate 2>&1); rc=$?
  [ "$rc" -eq 0 ] && ok "[$v] swap passes (the gap, on the record)" || bad "[$v] rc=$rc" "$out"
  case "$out" in *"needs v0.30.0 or newer"*) ok "[$v] note names the minimum version" ;; *) bad "[$v] no note" "$out" ;; esac
  grep -q -- '--baseline' "$STUB_LOG" && bad "[$v] --baseline was called" "$(cat "$STUB_LOG")" || ok "[$v] --baseline never called"
done

echo "T5 nightly build (no semver): decided by lint --help"
export FAKE_VERSION="mxcli nightly-20261105-f3c4d531d (2026-11-05T06:58:16Z)"
export FAKE_HELP_BASELINE=1; reset; mk "$(f CONV007 OldA)"
out=$(gate --update-baseline 2>&1); [ -s "$P/.claude/lint-mxcli-baseline.json" ] && ok "help lists --baseline: native baseline written" || bad "not written" "$out"
export FAKE_HELP_BASELINE=0; reset; mk "$(f CONV007 OldA)"
out=$(gate --update-baseline 2>&1); [ ! -f "$P/.claude/lint-mxcli-baseline.json" ] && ok "help without --baseline: ratchet only" || bad "written" "$out"

echo "T6 no mxcli baseline file yet: a note, not a failure; --update-baseline creates it"
export FAKE_VERSION="mxcli v0.30.0"; unset FAKE_HELP_BASELINE
reset; mk "$(f CONV007 OldA)"; gate --update-baseline >/dev/null 2>&1; rm -f "$P/.claude/lint-mxcli-baseline.json"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "rc 0" || bad "rc=$rc" "$out"
case "$out" in *"no .claude/lint-mxcli-baseline.json yet"*) ok "note says how to create it" ;; *) bad "no note" "$out" ;; esac

echo "T7 deleted from the tree: git HEAD's copy is still the bar"
reset; mk "$(f CONV007 OldA OldB)"; gate --update-baseline >/dev/null 2>&1
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -q -m base ) >/dev/null 2>&1
rm -f "$P/.claude/lint-mxcli-baseline.json"
mk "$(f CONV007 OldA NewX)"; mknew "$(f CONV007 NewX)"; : > "$STUB_LOG"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "swap still fails after rm of the baseline" || bad "rc=$rc" "$out"
case "$out" in *"deleted from the tree"*) ok "says it used HEAD's copy" ;; *) bad "no note" "$out" ;; esac

echo "T8 _rule self-reports and crashed rules in the compare are not findings"
reset; mk "$(f CONV007 OldA)"; gate --update-baseline >/dev/null 2>&1
mknew '{"ruleId":"CONV007","severity":"warning","message":"CONV007 is blind","module":"_rule","document":"CONV007","documentType":"Entity","documentId":"","suggestion":"s"},{"ruleId":"X1","severity":"error","message":"Starlark rule error: boom","module":"","document":"","documentType":"","documentId":"","suggestion":""}'
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "rc 0: the blind logic owns those, the compare does not double-count" || bad "rc=$rc" "$out"

echo "T9 accepting a swap is a loosening: refused without --reason, refused for the agent, baseline untouched"
reset; mk "$(f CONV007 OldA OldB OldC)"; gate --update-baseline >/dev/null 2>&1
before=$(cksum "$P/.claude/lint-baseline.json" "$P/.claude/lint-mxcli-baseline.json")
mk "$(f CONV007 OldA OldB NewX)"; mknew "$(f CONV007 NewX)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "no reason: rc 2" || bad "rc=$rc" "$out"
case "$out" in *"CONV007 +1 new, count unchanged"*) ok "refusal names the swap" ;; *) bad "swap not named" "$out" ;; esac
out=$(gate --update-baseline --reason "x" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "with a reason but no terminal: rc 2" || bad "rc=$rc" "$out"
case "$out" in *"security-tier"*CONV007*) ok "CONV007 is in the default security tier" ;; *) bad "CONV007 not flagged security-tier" "$out" ;; esac
[ "$before" = "$(cksum "$P/.claude/lint-baseline.json" "$P/.claude/lint-mxcli-baseline.json")" ] && ok "both baselines untouched" || bad "a baseline changed"

echo "T10 MXTK-SEC015 is in the default security tier too"
reset; mk "$(f MXTK-SEC015 OldA)"; gate --update-baseline >/dev/null 2>&1
mk "$(f MXTK-SEC015 OldA NewX)"; mknone
out=$(gate --update-baseline --reason "x" 2>&1)
case "$out" in *"security-tier: MXTK-SEC015"*) ok "MXTK-SEC015 rise flagged security-tier" ;; *) bad "not flagged" "$out" ;; esac

echo; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
