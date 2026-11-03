#!/usr/bin/env bash
# Fixture for the gate-check verdict cache (bin/lib/gate-cache.sh): `gate-check.sh <dir> N` then
# `gate-check.sh --closeout <dir> N` reuses the evaluation only while the project is unchanged.
# Added with the #589 review fix: freshness used `find -newer` alone, which an overwrite that
# keeps an old mtime (`cp -p`, rsync -t, tar x, unzip, touch -d) escaped — a signed file copied
# over a FAIL one still replayed the cached FAIL. The content signature closes that.
#
#   tests/wave2/test-gate-cache.sh /path/to/gate-check.sh
#
# Hit/miss is observed through MXTK_GATE_CACHE_TRACE=1, which makes --closeout print
# "gate-cache: hit|miss" on stderr. Field run: see the commit that adds this file.
set -uo pipefail
GATE="${1:?usage: test-gate-cache.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/gatecache.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
export MXTK_NO_FETCH=1 MXTK_GATE_CACHE_TRACE=1

mkproj() {
  d="$WORK/$1"; mkdir -p "$d/architecture" "$d/design/wireframes" "$d/knowledge-base/brd"
  printf '.mxtk/\n' > "$d/.gitignore"
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md — fixture
Toolkit commit: none
Entry mode: requirements-driven

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Module structure: one module | CONFIRMED 2026-09-02 | matches the BRD |
| 3 | Cross-module strategy: none | CONFIRMED | single module |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
MD
  printf '{"openQuestions":[]}\n' > "$d/knowledge-base/brd/F001.brd.json"
  printf '# fit-gap\nrow\n' > "$d/architecture/fit-gap.md"
  echo "$d"
}
# query then closeout; sets Q_ERR (closeout stderr) and Q_OUT (closeout stdout)
run() { "$GATE" --no-html "$1" 3 >/dev/null 2>&1; Q_OUT="$("$GATE" --closeout "$1" 3 2>"$WORK/err")"; Q_ERR="$(cat "$WORK/err")"; }
hit()  { case "$Q_ERR" in *"gate-cache: hit"*) return 0 ;; esac; return 1; }
miss() { case "$Q_ERR" in *"gate-cache: miss"*) return 0 ;; esac; return 1; }

echo "== T1: unchanged tree -> hit =="
P="$(mkproj t1)"
run "$P"; hit && ok "closeout right after the query hits" || bad "no hit: $Q_ERR"
"$GATE" --closeout "$P" 3 >/dev/null 2>"$WORK/err"; grep -q 'gate-cache: hit' "$WORK/err" && ok "second closeout still hits" || bad "second closeout: $(cat "$WORK/err")"

echo "== T2: edit / deletion / waiver line -> miss =="
P="$(mkproj t2)"; run "$P"; hit || bad "T2 setup did not hit"
sleep 1; printf 'extra\n' >> "$P/architecture/fit-gap.md"
"$GATE" --closeout "$P" 3 >/dev/null 2>"$WORK/err"; grep -q 'gate-cache: miss' "$WORK/err" && ok "edit -> miss" || bad "edit: $(cat "$WORK/err")"
P="$(mkproj t2d)"; printf 'x\n' > "$P/architecture/other.md"; run "$P"; hit || bad "T2d setup did not hit"
sleep 1; rm "$P/architecture/other.md"
"$GATE" --closeout "$P" 3 >/dev/null 2>"$WORK/err"; grep -q 'gate-cache: miss' "$WORK/err" && ok "deletion -> miss" || bad "deletion: $(cat "$WORK/err")"
P="$(mkproj t2w)"; run "$P"; hit || bad "T2w setup did not hit"
sleep 1; printf 'Opt-in artifact test-plan: demo needs it\n' >> "$P/PROJECT.md"
"$GATE" --closeout "$P" 3 >/dev/null 2>"$WORK/err"; grep -q 'gate-cache: miss' "$WORK/err" && ok "waiver/opt-in line in PROJECT.md -> miss" || bad "waiver: $(cat "$WORK/err")"

echo "== T3: cp -p overwrite with an old mtime must miss and give the right verdict =="
P="$(mkproj t3)"
cp -p "$P/PROJECT.md" "$WORK/good.md"; touch -d '2020-01-01' "$WORK/good.md"
sed -i.bak 's/| 3 | Module structure: one module | CONFIRMED 2026-09-02 |/| 3 | Module structure: one module | RAISED |/' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
run "$P"; hit || bad "T3 setup did not hit"
BEFORE="$Q_OUT"
sleep 1; cp -p "$WORK/good.md" "$P/PROJECT.md"
"$GATE" --closeout "$P" 3 >"$WORK/out" 2>"$WORK/err"
grep -q 'gate-cache: miss' "$WORK/err" && ok "old-mtime overwrite -> miss" || bad "old-mtime overwrite hit: $(cat "$WORK/err")"
[ "$(cat "$WORK/out")" != "$BEFORE" ] && ok "verdict changed with the content" || bad "stale verdict replayed"
MXTK_GATE_CACHE_TTL_MIN=0 "$GATE" --closeout "$P" 3 >"$WORK/out0" 2>/dev/null
cmp -s "$WORK/out" "$WORK/out0" && ok "matches an uncached evaluation" || bad "differs from uncached"

echo "== T4: MXTK_GATE_CACHE_TTL_MIN=0 turns the cache off =="
P="$(mkproj t4)"; "$GATE" --no-html "$P" 3 >/dev/null 2>&1
MXTK_GATE_CACHE_TTL_MIN=0 "$GATE" --closeout "$P" 3 >/dev/null 2>"$WORK/err"
grep -q 'gate-cache: miss' "$WORK/err" && ok "TTL 0 -> miss even on a clean tree" || bad "TTL 0: $(cat "$WORK/err")"

echo "== T5: a stage query prints the 'not evaluated' line =="
P="$(mkproj t5)"
"$GATE" --no-html "$P" 3 >"$WORK/o5" 2>&1
grep -q 'for stages after 3 not evaluated' "$WORK/o5" && ok "N … not evaluated line present" || bad "line missing: $(grep -c . "$WORK/o5") lines"

echo; echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
