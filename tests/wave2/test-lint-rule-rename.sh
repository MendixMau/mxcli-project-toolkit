#!/usr/bin/env bash
# test-lint-rule-rename.sh — the toolkit's CONV020 rule is MXTK-UX003, and sync migrates projects.
#
# usage: bash tests/wave2/test-lint-rule-rename.sh bin/sync-project.sh
#
# Why (2026-10-23): mxcli v0.28.0 ships a built-in CONV020 ("Created object never persisted",
# mendixlabs/mxcli#1518) and mxcli has no duplicate-ID guard, so the toolkit's CONV020
# (user feedback) ran beside it under one id: one lint-config entry switched both, -r CONV020 ran
# both, lint-gate summed them. The rule is now MXTK-UX003 (mxtk_ux003_action_user_feedback.star),
# and bin/lib/install-lint-rules.sh (_mxtk_lint_migrate_renames) migrates synced projects.
#
# Golden input. The old rule files are read from this repo's git history (every shipped version,
# the same ones MXTK_LINT_RENAMES lists by md5); without history, the last shipped version is
# rebuilt from the new file and must hash to a listed md5 or the fixture stops. Baselines are
# written by the project's REAL bin/lint-gate.sh --update-baseline from verbatim `mxcli lint
# --format json` captures on a public model, v0.27.0 and v0.28.0 (tests/wave2/fixtures/
# lint-conv020-v028/CAPTURE.txt); the post-rename output is the v0.28.0 capture with only the
# toolkit finding's ruleId changed. T1b's baseline is the capture taken WITH the opt-out
# (lint-conv020-disabled-v0.28.0.out); its post-sync output adds the toolkit finding as MXTK-UX003
# only when the project would run that rule (installed and not disabled), since a CONV020 key no
# longer reaches it. T1c's other spellings and config locations take their verdicts from
# lint-config-variants-v0.28.0.out (mxcli v0.28.0 run once per config). Projects are scaffolded by
# the REAL bin/init-project.sh and migrated by the REAL sync-project.sh, on both layouts
# (.mpr at the root, and under app/). doctor.sh runs --quick against a stub mxcli.
set -uo pipefail
SYNC="${1:?usage: $0 bin/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
TK="$(cd "$(dirname "$SYNC")/.." && pwd)"
INIT="$TK/bin/init-project.sh"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-rename.XXXXXX")"
export MXTK_LEAKGUARD_DENYFILE="$WORK/deny" MXTK_SYNC_SKIP_CLONE_CHECK=1 MXTK_NO_GUIDE=1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

OLD=conv020_action_user_feedback.star; NEW=mxtk_ux003_action_user_feedback.star
. "$TK/bin/lib/install-manifest.sh" >/dev/null 2>&1
MD5S="$(printf '%s\n' "$MXTK_LINT_RENAMES" | awk -v o="$OLD" '$1 == o { print $5 }')"

echo "T0 the rename is complete"
# Code (not comments) in a shipped .star: no CONV020 left, so no rule reports under that id.
code="$(grep -n 'CONV020' "$TK"/lint-rules/*.star | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
[ -z "$code" ] && ok "no lint-rules/*.star code says CONV020" || bad "a shipped .star still uses CONV020" "$code"
grep -q '^RULE_ID = "MXTK-UX003"$' "$TK/lint-rules/$NEW" && ok "RULE_ID = MXTK-UX003" || bad "RULE_ID not MXTK-UX003"
[ ! -e "$TK/lint-rules/$OLD" ] && ok "old file name gone from lint-rules/" || bad "lint-rules/$OLD still shipped"
case " $MXTK_LINT_RULES $MXTK_LINT_RULES_CONFIGURABLE " in *" $NEW "*) ok "manifest installs $NEW" ;; *) bad "manifest does not install $NEW" ;; esac
case " $MXTK_LINT_RULES $MXTK_LINT_RULES_CONFIGURABLE " in *" $OLD "*) bad "manifest still installs $OLD" ;; *) ok "manifest no longer installs $OLD" ;; esac
# Every shipped line naming CONV020 must also name MXTK-UX003 or say it is mxcli's built-in.
stray="$(cd "$TK" && grep -rn 'CONV020' bin project-bin project-tests lint-rules skills templates README.md 2>/dev/null \
         | grep -v 'MXTK-UX003' | grep -vi 'built-in' \
         | grep -v '^lint-rules/conv010_act_microflow_content.star:[0-9]*:.*Same guard as CONV020\.$' || true)"
[ -z "$stray" ] && ok "every CONV020 mention in shipped code/docs names MXTK-UX003 or the built-in" || bad "toolkit CONV020 left" "$stray"
# Every shipped version of the old file is in MXTK_LINT_RENAMES (captured from git, not typed).
VERS="$WORK/versions"; mkdir -p "$VERS"
if git -C "$TK" rev-parse --is-shallow-repository 2>/dev/null | grep -qx false; then
  for c in $(git -C "$TK" log --format=%h -- "lint-rules/$OLD"); do git -C "$TK" show "$c:lint-rules/$OLD" > "$VERS/$c.star" 2>/dev/null || rm -f "$VERS/$c.star"; done
fi
if [ -n "$(ls "$VERS")" ]; then
  miss=""; for f in "$VERS"/*.star; do case ",$MD5S," in *",$(portable_md5 "$f"),"*) ;; *) miss="$miss $(basename "$f")" ;; esac; done
  [ -z "$miss" ] && ok "all $(ls "$VERS" | wc -l | tr -d ' ') shipped versions of $OLD are listed by md5" || bad "shipped versions missing from MXTK_LINT_RENAMES:$miss"
else
  echo "  note shallow clone: no git history; rebuilding the last shipped version from $NEW"
fi
LAST="$WORK/last-old.star"
sed '/^# MXTK-UX003 was CONV020 (conv020_action_user_feedback.star) until/,/^# migrates an unedited project copy/d' "$TK/lint-rules/$NEW" \
  | sed '11{/^#$/d;}' | sed 's/^# mxtk-lint-rule: mxtk_ux003_action_user_feedback$/# mxtk-lint-rule: conv020_action_user_feedback/; s/MXTK-UX003/CONV020/g' > "$LAST"
case ",$MD5S," in *",$(portable_md5 "$LAST"),"*) ok "rebuilt last old version hashes to a listed md5" ;;
  *) bad "rebuilt old version $(portable_md5 "$LAST") is not a listed md5 — fixture input broken"; echo "pass=$PASS fail=$FAIL"; exit 1 ;; esac
EMPTY_OLD=""   # a pre-2026-10-09 version (PROJECT_MODULES = ()), from history when available
for f in "$VERS"/*.star; do [ -f "$f" ] && grep -q '^PROJECT_MODULES = ()' "$f" && { EMPTY_OLD="$f"; break; }; done

# --- golden captures: real mxcli lint output (tests/wave2/fixtures/lint-conv020-v028/CAPTURE.txt) ---
CAP="$TK/tests/wave2/fixtures/lint-conv020-v028"
echo "T0b the captures show the collision, and the migration tells the two rules apart"
ids() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(sorted(v["ruleId"] for v in d["violations"])))' "$1"; }
[ "$(ids "$CAP/lint-conv020-v0.27.0.out")" = "CONV020 SEC001" ] && ok "v0.27.0: one CONV020 (the toolkit's)" || bad "v0.27 capture unexpected"
[ "$(ids "$CAP/lint-conv020-v0.28.0.out")" = "CONV020 CONV020 SEC001" ] && ok "v0.28.0: two CONV020 findings, one per rule" || bad "v0.28 capture unexpected"
[ "$(ids "$CAP/lint-conv020-only-v0.28.0.out")" = "CONV020 CONV020" ] && ok "v0.28.0 -r CONV020 runs both" || bad "-r capture unexpected"
[ "$(ids "$CAP/lint-conv020-disabled-v0.28.0.out")" = "SEC001" ] && ok "v0.28.0 CONV020 enabled:false switches both off" || bad "disabled capture unexpected"
[ "$(grep -c '^ *CONV020 (' "$CAP/lint-list-rules-v0.28.0.out")" = 2 ] && ok "v0.28.0 lint -l lists CONV020 twice" || bad "list-rules capture unexpected"
grep -qE '^ *MXTK-' "$CAP/lint-list-rules-v0.28.0.out" && bad "MXTK- id already taken in v0.28.0" || ok "no MXTK- id among v0.28.0's rules: MXTK-UX003 is free"
RE="$(printf '%s\n' "$MXTK_LINT_RENAMES" | awk -v o="$OLD" '$1 == o { $1=$2=$3=$4=$5=""; sub(/^ +/, ""); print }')"
cls="$(RE="$RE" "$PY" -c '
import json, os, re, sys
pat = re.compile(os.environ["RE"])
for v in json.load(open(sys.argv[1]))["violations"]:
    if v["ruleId"] == "CONV020": print("toolkit" if pat.search(v["message"]) else "builtin", v["document"])
' "$CAP/lint-conv020-v0.28.0.out" | sort | paste -sd, -)"
[ "$cls" = "builtin SUB_Seed,toolkit Shop.ACT_SaveItem" ] && ok "migration regex: ACT_SaveItem = toolkit, SUB_Seed = built-in" || bad "regex misclassifies the captured findings" "$cls"

# Post-rename v0.28.0 output: the capture with the toolkit finding's ruleId renamed (the only change
# the rename makes to what mxcli prints for that rule).
"$PY" -c '
import json, sys
d = json.load(open(sys.argv[1]))
for v in d["violations"]:
    if v["document"] == "Shop.ACT_SaveItem": v["ruleId"] = "MXTK-UX003"
json.dump(d, open(sys.argv[2], "w"), indent=2)
' "$CAP/lint-conv020-v0.28.0.out" "$WORK/after.json"
cp "$CAP/lint-conv020-v0.28.0.out" "$WORK/before.json"
stub_mxcli() { printf '#!/bin/sh\n[ "$1" = --version ] && echo "mxcli version %s (2026-10-23T14:29:27Z)"\nexit 0\n' "$2" > "$1/mxcli"; chmod +x "$1/mxcli"; }
count() { "$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["counts"].get(sys.argv[2], 0))' "$1/.claude/lint-baseline.json" "$2"; }
lintstate() { (cd "$1" && for f in .claude/lint-baseline.json .claude/.mxtk-lint-receipt .claude/lint-rules-disabled.txt .claude/lint-rules/*; do
               [ -f "$f" ] && printf '%s %s\n' "$f" "$(portable_md5 "$f")"; done); }
# put_old <proj> <old file content>: the project as it was before the rename — old file in place,
# new one absent, receipt row for the old name (md5 as installed).
put_old() {
  cp "$2" "$1/.claude/lint-rules/$OLD"; rm -f "$1/.claude/lint-rules/$NEW"
  grep -v "^$NEW " "$1/.claude/.mxtk-lint-receipt" > "$1/.r"; mv "$1/.r" "$1/.claude/.mxtk-lint-receipt"
  printf '%s  %s  configurable\n' "$OLD" "$(portable_md5 "$2")" >> "$1/.claude/.mxtk-lint-receipt"
}
baseline_with() { (cd "$1" && LINT_JSON="$2" bash bin/lint-gate.sh --update-baseline >/dev/null 2>&1); }

# One scaffold per layout, copied per case (init-project.sh takes ~10 s).
for L in root app; do
  S="$WORK/scaffold-$L"; mkdir -p "$S"
  if [ "$L" = app ]; then mkdir -p "$S/app"; : > "$S/app/Fixture.mpr"; else : > "$S/Fixture.mpr"; fi
  "$INIT" "$S" >/dev/null 2>&1
  [ -f "$S/.claude/lint-rules/$NEW" ] && [ -f "$S/bin/lint-gate.sh" ] || { bad "[$L] init-project.sh did not install $NEW / bin/lint-gate.sh"; continue; }
  stub_mxcli "$S" v0.27.0
  mk() { rm -rf "$WORK/$1"; cp -R "$WORK/scaffold-$L" "$WORK/$1"; echo "$WORK/$1"; }

  echo "T1 [$L] unedited old copy: renamed, baseline rekeyed, built-in finding kept, notices once"
  P="$(mk "t1-$L")"; put_old "$P" "$LAST"
  baseline_with "$P" "$WORK/before.json"
  grep -q '"mxcli_version": "v0.27.0"' "$P/.claude/lint-baseline.json" && ok "[$L] lint-gate --update-baseline records mxcli_version" || bad "[$L] mxcli_version not recorded" "$(cat "$P/.claude/lint-baseline.json")"
  [ "$(count "$P" CONV020)" = 2 ] && ok "[$L] pre-rename baseline (v0.28 capture): CONV020 2 (toolkit + built-in)" || bad "[$L] setup baseline wrong"
  printf 'rules:\n  CONV020:\n    severity: error\n' > "$P/.claude/lint-config.yaml"
  echo "- D-9: CONV020 opted out, no ACT_ convention. CONFIRMED" >> "$P/PROJECT.md"
  out="$("$SYNC" "$P" 2>&1)"
  [ ! -e "$P/.claude/lint-rules/$OLD" ] && cmp -s "$TK/lint-rules/$NEW" "$P/.claude/lint-rules/$NEW" \
    && ok "[$L] $OLD replaced by the current $NEW" || bad "[$L] file not migrated" "$out"
  grep -q "^$NEW  [0-9a-f]\{32\}  configurable$" "$P/.claude/.mxtk-lint-receipt" && ! grep -q "^$OLD " "$P/.claude/.mxtk-lint-receipt" \
    && ok "[$L] receipt row moved to $NEW" || bad "[$L] receipt wrong" "$(cat "$P/.claude/.mxtk-lint-receipt")"
  { [ "$(count "$P" MXTK-UX003)" = 1 ] && [ "$(count "$P" CONV020)" = 1 ]; } \
    && ok "[$L] baseline: MXTK-UX003 1, CONV020 1 (the built-in's)" || bad "[$L] baseline not mapped" "$(cat "$P/.claude/lint-baseline.json")"
  grep -q '"CONV020|Shop|SUB_Seed|' "$P/.claude/lint-baseline.json" && grep -q '"MXTK-UX003|Shop|Shop.ACT_SaveItem|' "$P/.claude/lint-baseline.json" \
    && ok "[$L] findings rekeyed by message, built-in key untouched" || bad "[$L] findings keys wrong"
  printf '%s' "$out" | grep -q "Lint rule renamed: .claude/lint-rules/$OLD -> $NEW" && ok "[$L] sync says it renamed" || bad "[$L] no rename line" "$out"
  printf '%s' "$out" | grep -q "lint-config.yaml has settings under CONV020" && ok "[$L] NOTE for the lint-config CONV020 key" || bad "[$L] no lint-config note" "$out"
  printf '%s' "$out" | grep -q "PROJECT.md names CONV020 on line" && ok "[$L] NOTE for PROJECT.md" || bad "[$L] no PROJECT.md note" "$out"
  grep -q 'CONV020:' "$P/.claude/lint-config.yaml" && grep -q 'D-9: CONV020' "$P/PROJECT.md" && ok "[$L] lint-config.yaml and PROJECT.md not rewritten" || bad "[$L] a user file was rewritten"
  out="$(cd "$P" && LINT_JSON="$WORK/after.json" bash bin/lint-gate.sh 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "[$L] lint-gate PASS on post-rename output (no false rise)" || bad "[$L] lint-gate rc $rc after the rename" "$out"

  echo "T2 [$L] a second sync is a no-op"
  before="$(lintstate "$P")"; out="$("$SYNC" "$P" 2>&1)"
  [ "$(lintstate "$P")" = "$before" ] && ok "[$L] no lint file changed" || bad "[$L] second sync changed files" "$(diff <(echo "$before") <(lintstate "$P"))"
  printf '%s' "$out" | grep -qE "renamed|rekeyed|CONV020|carried over" && bad "[$L] second sync still talks about the rename" "$out" || ok "[$L] second sync silent about it"

  echo "T1b [$L] lint-config CONV020 enabled: false (README's preferred opt-out): carried over, rule stays off"
  P="$(mk "t1b-$L")"; put_old "$P" "$LAST"
  printf 'rules:\n  CONV020:\n    enabled: false   # no ACT_ convention, PROJECT.md D-9\n' > "$P/.claude/lint-config.yaml"
  cp "$P/.claude/lint-config.yaml" "$WORK/cfg-$L"
  # What mxcli printed with that config (both rules off): no toolkit finding to baseline.
  baseline_with "$P" "$CAP/lint-conv020-disabled-v0.28.0.out"
  [ "$(count "$P" CONV020)" = 0 ] && ok "[$L] opt-out baseline holds no CONV020 finding" || bad "[$L] opt-out baseline wrong"
  out="$("$SYNC" "$P" 2>&1)"
  [ ! -e "$P/.claude/lint-rules/$OLD" ] && [ ! -e "$P/.claude/lint-rules/$NEW" ] \
    && ok "[$L] old copy retired, $NEW NOT installed" || bad "[$L] opt-out lost: $NEW installed" "$out"
  grep -qE "^$NEW  # reason: carried over from lint-config.yaml CONV020: enabled: false \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$" "$P/.claude/lint-rules-disabled.txt" 2>/dev/null \
    && ok "[$L] lint-rules-disabled.txt names $NEW with the carried-over reason" || bad "[$L] no disabled line" "$(cat "$P/.claude/lint-rules-disabled.txt" 2>&1)"
  cmp -s "$P/.claude/lint-config.yaml" "$WORK/cfg-$L" && ok "[$L] lint-config.yaml CONV020 key left alone" || bad "[$L] lint-config.yaml rewritten"
  printf '%s' "$out" | grep -q "enabled: false was carried over" && ok "[$L] NOTE says the opt-out was carried over" || bad "[$L] NOTE does not say carried over" "$out"
  # mxcli v0.28 on the synced project: the CONV020 key switches off only the built-in; MXTK-UX003
  # reports whenever the project would run it.
  "$PY" -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
p = sys.argv[3]
run = os.path.isfile(p + "/.claude/lint-rules/mxtk_ux003_action_user_feedback.star") and not any(
    l.split()[:1] == ["mxtk_ux003_action_user_feedback.star"] and "reason:" in l
    for l in (open(p + "/.claude/lint-rules-disabled.txt") if os.path.isfile(p + "/.claude/lint-rules-disabled.txt") else []))
if run:
    for v in json.load(open(sys.argv[2]))["violations"]:
        if v["document"] == "Shop.ACT_SaveItem": v["ruleId"] = "MXTK-UX003"; d["violations"].append(v)
json.dump(d, open(sys.argv[4], "w"), indent=2)
' "$CAP/lint-conv020-disabled-v0.28.0.out" "$CAP/lint-conv020-v0.28.0.out" "$P" "$WORK/after-optout-$L.json"
  out="$(cd "$P" && LINT_JSON="$WORK/after-optout-$L.json" bash bin/lint-gate.sh 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "[$L] lint-gate PASS after sync (no MXTK-UX003 0 -> 1)" || bad "[$L] lint-gate rc $rc after sync" "$out"
  before="$(lintstate "$P")"; out="$("$SYNC" "$P" 2>&1)"
  { [ "$(lintstate "$P")" = "$before" ] && ! printf '%s' "$out" | grep -qE "renamed|carried over|CONV020"; } \
    && ok "[$L] second sync: no change, silent" || bad "[$L] second sync not a no-op" "$out"

  echo "T1c [$L] other spellings of the opt-out, and where mxcli reads the config: carried over exactly when mxcli v0.28.0 switches CONV020 off"
  # Expected verdicts are mxcli v0.28.0's own: each case's name is a line of the capture
  # lint-config-variants-v0.28.0.out (that config on the pedapp capture model), and the fixture
  # stops if the column below disagrees with it: SEC001 only = both CONV020 off.
  # id | capture label | file(s) under the project, first gets the text | config text | 1 = mxcli switched CONV020 off
  while IFS='|' read -r cid cn cf ct coff <&3; do
    [ -n "$cid" ] || continue
    capids="$(awk -v l="$cn" '{ k = substr($0, 1, 35); sub(/ +$/, "", k) } k == l { sub(/^[^]]*][ ]*/, ""); print; exit }' "$CAP/lint-config-variants-v0.28.0.out")"
    case "$coff:$capids" in 1:SEC001|0:*"CONV020 CONV020 SEC001") ;;
      *) bad "[$L] $cn: expected verdict $coff disagrees with the v0.28.0 capture ('$capids')"; continue ;; esac
    P="$(mk "t1c-$cid-$L")"; put_old "$P" "$LAST"; rm -f "$P/.claude/lint-config.yaml"
    for x in $cf; do printf "$ct" > "$P/$x"; ct='rules: {}\n'; done
    if [ "$coff" = 1 ]; then baseline_with "$P" "$CAP/lint-conv020-disabled-v0.28.0.out"; else baseline_with "$P" "$WORK/before.json"; fi
    out="$("$SYNC" "$P" 2>&1)"
    if [ "$coff" = 1 ]; then
      { [ ! -e "$P/.claude/lint-rules/$NEW" ] && grep -q "^$NEW  # reason: carried over from " "$P/.claude/lint-rules-disabled.txt" 2>/dev/null; } \
        && ok "[$L] $cn: carried over, $NEW not installed" || bad "[$L] $cn: opt-out lost" "$out"
    else
      { [ -f "$P/.claude/lint-rules/$NEW" ] && ! grep -q "^$NEW " "$P/.claude/lint-rules-disabled.txt" 2>/dev/null; } \
        && ok "[$L] $cn: mxcli runs CONV020, so no carry-over; $NEW installed" || bad "[$L] $cn: carried over an opt-out mxcli ignores" "$out"
    fi
    # What mxcli v0.28.0 prints on the synced project: the built-in CONV020 as the config leaves it,
    # plus the toolkit finding as MXTK-UX003 whenever the project would run that rule.
    "$PY" -c '
import json, os, sys
cap, off, p = json.load(open(sys.argv[1])), sys.argv[2] == "1", sys.argv[3]
dis = p + "/.claude/lint-rules-disabled.txt"
run = os.path.isfile(p + "/.claude/lint-rules/mxtk_ux003_action_user_feedback.star") and not any(
    l.split()[:1] == ["mxtk_ux003_action_user_feedback.star"] and "reason:" in l
    for l in (open(dis) if os.path.isfile(dis) else []))
out = []
for v in cap["violations"]:
    if v["document"] == "Shop.ACT_SaveItem":
        if run: v["ruleId"] = "MXTK-UX003"; out.append(v)
    elif not (off and v["ruleId"] == "CONV020"):
        out.append(v)
cap["violations"] = out
json.dump(cap, open(sys.argv[4], "w"), indent=2)
' "$CAP/lint-conv020-v0.28.0.out" "$coff" "$P" "$WORK/t1c.json"
    o2="$(cd "$P" && LINT_JSON="$WORK/t1c.json" bash bin/lint-gate.sh 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "[$L] $cn: lint-gate PASS after sync" || bad "[$L] $cn: lint-gate rc $rc after sync" "$o2"
  done 3<<'CASES'
False|enabled: False|.claude/lint-config.yaml|rules:\n  CONV020:\n    enabled: False\n|1
no|severity+enabled: no|.claude/lint-config.yaml|rules:\n  CONV020:\n    severity: info\n    enabled: no\n|1
sqkey|single-quoted key|.claude/lint-config.yaml|rules:\n  'CONV020':\n    enabled: false\n|1
flow|flow { enabled: False, severity }|.claude/lint-config.yaml|rules:\n  CONV020: { enabled: False, severity: info }\n|1
nested|options: enabled: false (nested)|.claude/lint-config.yaml|rules:\n  CONV020:\n    options:\n      enabled: false\n|0
qfalse|enabled: "false"|.claude/lint-config.yaml|rules:\n  CONV020:\n    enabled: "false"\n|0
root|root lint-config.yaml|lint-config.yaml|rules:\n  CONV020:\n    enabled: false\n|1
precedence|.claude empty, root off|lint-config.yaml .claude/lint-config.yaml|rules:\n  CONV020:\n    enabled: false\n|0
crlf|enabled: false|.claude/lint-config.yaml|rules:\r\n  CONV020:\r\n    enabled: false\r\n|1
CASES

  echo "T1d [$L] dry run with the opt-out: says it would carry over, not that it would install $NEW"
  P="$(mk "t1d-$L")"; put_old "$P" "$LAST"
  printf 'rules:\n  CONV020:\n    enabled: false\n' > "$P/.claude/lint-config.yaml"
  out="$("$SYNC" "$P" --dry-run 2>&1)"
  { printf '%s' "$out" | grep -q "Would carry over: .claude/lint-config.yaml CONV020 enabled: false" \
    && ! printf '%s' "$out" | grep -q "Would install: .claude/lint-rules/$NEW"; } \
    && ok "[$L] dry run: carry-over only" || bad "[$L] dry run also announces installing $NEW" "$out"
  printf '%s' "$out" | grep -q "move them" && bad "[$L] NOTE still says to move the key under MXTK-UX003" "$out" || ok "[$L] no move-the-key advice when the rule stays off"

  echo "T2b [$L] baseline taken on v0.27.0: rename maps it; the v0.28 upgrade then rises in CONV020 only"
  P="$(mk "t2b-$L")"; put_old "$P" "$LAST"
  baseline_with "$P" "$CAP/lint-conv020-v0.27.0.out"
  "$SYNC" "$P" >/dev/null 2>&1
  { [ "$(count "$P" MXTK-UX003)" = 1 ] && [ "$(count "$P" CONV020)" = 0 ]; } && ok "[$L] v0.27 baseline: CONV020 1 -> MXTK-UX003 1" || bad "[$L] v0.27 baseline not mapped" "$(cat "$P/.claude/lint-baseline.json")"
  out="$(cd "$P" && LINT_JSON="$WORK/after.json" bash bin/lint-gate.sh 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE '^ +CONV020 +warning +0 -> 1' && ! printf '%s' "$out" | grep -qE '^ +MXTK-UX003 +warning'; } \
    && ok "[$L] after the upgrade only the built-in CONV020 rises (the re-baseline the doctor hint is for)" || bad "[$L] post-upgrade rise wrong (rc $rc)" "$out"

  echo "T3 [$L] edited old copy: left alone, new rule held back, warning, baseline untouched"
  P="$(mk "t3-$L")"; put_old "$P" "$LAST"
  sed 's/^PROJECT_MODULES = "\*"$/PROJECT_MODULES = ("Orders",)/' "$LAST" > "$P/.claude/lint-rules/$OLD"
  baseline_with "$P" "$WORK/before.json"; em="$(portable_md5 "$P/.claude/lint-rules/$OLD")"; bm="$(portable_md5 "$P/.claude/lint-baseline.json")"
  out="$("$SYNC" "$P" 2>&1)"
  [ "$(portable_md5 "$P/.claude/lint-rules/$OLD")" = "$em" ] && ok "[$L] edited $OLD byte-identical" || bad "[$L] edited copy touched"
  [ ! -e "$P/.claude/lint-rules/$NEW" ] && ok "[$L] $NEW not installed beside it" || bad "[$L] $NEW installed: the rule would run twice"
  [ "$(portable_md5 "$P/.claude/lint-baseline.json")" = "$bm" ] && ok "[$L] baseline untouched" || bad "[$L] baseline mapped while CONV020 still runs"
  printf '%s' "$out" | grep -q "$OLD is edited here, so it was NOT renamed" && printf '%s' "$out" | grep -q "cp .*$NEW" \
    && ok "[$L] manual-migration warning with steps" || bad "[$L] no manual-migration warning" "$out"
  before="$(lintstate "$P")"; "$SYNC" "$P" >/dev/null 2>&1
  [ "$(lintstate "$P")" = "$before" ] && ok "[$L] second sync changes nothing" || bad "[$L] second sync changed the held project"
  # The user follows the steps: next sync maps the baseline.
  cp "$TK/lint-rules/$NEW" "$P/.claude/lint-rules/"; sed -i.b 's/^PROJECT_MODULES = "\*"$/PROJECT_MODULES = ("Orders",)/' "$P/.claude/lint-rules/$NEW"
  rm -f "$P/.claude/lint-rules/$NEW.b" "$P/.claude/lint-rules/$OLD"
  out="$("$SYNC" "$P" 2>&1)"
  [ "$(count "$P" MXTK-UX003)" = 1 ] && grep -q 'PROJECT_MODULES = ("Orders",)' "$P/.claude/lint-rules/$NEW" \
    && ok "[$L] after the manual steps: baseline rekeyed, configured copy kept" || bad "[$L] manual path not completed" "$out"

  echo "T3b [$L] edited old copy + lint-config opt-out: the warning says how to keep it, and following it works"
  P="$(mk "t3b-$L")"; put_old "$P" "$LAST"
  sed 's/^PROJECT_MODULES = "\*"$/PROJECT_MODULES = ("Orders",)/' "$LAST" > "$P/.claude/lint-rules/$OLD"
  printf 'rules:\n  CONV020:\n    enabled: false\n' > "$P/.claude/lint-config.yaml"
  out="$("$SYNC" "$P" 2>&1)"
  { printf '%s' "$out" | grep -q "To keep that opt-out" && printf '%s' "$out" | grep -qF "$NEW  # reason: <why>"; } \
    && ok "[$L] hold warning names the lint-rules-disabled.txt line" || bad "[$L] hold warning silent about the opt-out" "$out"
  printf '%s  # reason: no ACT_ convention\n' "$NEW" >> "$P/.claude/lint-rules-disabled.txt"; rm -f "$P/.claude/lint-rules/$OLD"
  out="$("$SYNC" "$P" 2>&1)"
  [ ! -e "$P/.claude/lint-rules/$NEW" ] && ok "[$L] after the steps: $NEW stays uninstalled" || bad "[$L] $NEW installed despite the opt-out" "$out"

  echo "T4 [$L] opt-out line names the old file: carried over, rule stays uninstalled"
  P="$(mk "t4-$L")"; rm -f "$P/.claude/lint-rules/$NEW"
  printf '%s  # reason: no ACT_ convention (PROJECT.md D-9)\n' "$OLD" > "$P/.claude/lint-rules-disabled.txt"
  printf 'rules:\n  "CONV020":\n    severity: error\n' > "$P/.claude/lint-config.yaml"
  out="$("$SYNC" "$P" 2>&1)"
  { printf '%s' "$out" | grep -q 'lint-config.yaml has settings under CONV020' && printf '%s' "$out" | grep -q 'which is off here through' \
    && ! printf '%s' "$out" | grep -q 'move them'; } \
    && ok "[$L] NOTE (double-quoted key) says the rule is off, no move-the-key advice" || bad "[$L] NOTE wrong for an opted-out rule" "$out"
  grep -q "^$NEW  # reason: no ACT_ convention (PROJECT.md D-9)$" "$P/.claude/lint-rules-disabled.txt" && ok "[$L] disabled line rewritten, reason kept" || bad "[$L] disabled line" "$(cat "$P/.claude/lint-rules-disabled.txt")"
  [ ! -e "$P/.claude/lint-rules/$NEW" ] && ok "[$L] opted-out rule not installed under its new name" || bad "[$L] opt-out lost: $NEW installed" "$out"

  echo "T5 [$L] counts-only baseline (pre-#239): NOTE, not a guess"
  P="$(mk "t5-$L")"; put_old "$P" "$LAST"
  printf '{\n  "counts": {\n    "CONV020": 3\n  },\n  "total": 3\n}\n' > "$P/.claude/lint-baseline.json"; bm="$(portable_md5 "$P/.claude/lint-baseline.json")"
  out="$("$SYNC" "$P" 2>&1)"
  [ "$(portable_md5 "$P/.claude/lint-baseline.json")" = "$bm" ] && ok "[$L] counts-only baseline unchanged" || bad "[$L] counts-only baseline rewritten"
  printf '%s' "$out" | grep -q "holds CONV020 as a count only" && ok "[$L] NOTE says it cannot split the count" || bad "[$L] no count-only NOTE" "$out"
  out="$("$SYNC" "$P" 2>&1)"
  printf '%s' "$out" | grep -q "as a count only" && bad "[$L] count-only NOTE printed again on the second sync" "$out" || ok "[$L] count-only NOTE printed once (second sync silent)"
  [ "$(portable_md5 "$P/.claude/lint-baseline.json")" = "$bm" ] && ok "[$L] counts-only baseline still unchanged" || bad "[$L] second sync rewrote the baseline"

  echo "T6 [$L] CRLF copy of a shipped version, and the empty-PROJECT_MODULES template"
  P="$(mk "t6-$L")"; awk '{ printf "%s\r\n", $0 }' "$LAST" > "$WORK/crlf.star"; put_old "$P" "$WORK/crlf.star"
  sed -i.b "s/^$OLD  [0-9a-f]*  /$OLD  00000000000000000000000000000000  /" "$P/.claude/.mxtk-lint-receipt"; rm -f "$P/.claude/.mxtk-lint-receipt.b"
  out="$("$SYNC" "$P" 2>&1)"
  [ ! -e "$P/.claude/lint-rules/$OLD" ] && [ -f "$P/.claude/lint-rules/$NEW" ] && ok "[$L] CRLF unedited copy migrated (no receipt match needed)" || bad "[$L] CRLF copy not migrated" "$out"
  if [ -n "$EMPTY_OLD" ]; then
    P="$(mk "t6b-$L")"; put_old "$P" "$EMPTY_OLD"; out="$("$SYNC" "$P" 2>&1)"
    [ -f "$P/.claude/lint-rules/$NEW" ] && printf '%s' "$out" | grep -q "PROJECT_MODULES empty, so it inspected nothing" \
      && ok "[$L] empty-PROJECT_MODULES template migrated, with the will-report note" || bad "[$L] old empty template" "$out"
  else
    echo "  note [$L] no git history: empty-PROJECT_MODULES case skipped"
  fi

  echo "T7 [$L] doctor: hint when the baseline's mxcli differs, quiet when it matches"
  D="$WORK/doc-$L"; mkdir -p "$D/.claude" "$WORK/home"
  if [ "$L" = app ]; then mkdir -p "$D/app"; : > "$D/app/App.mpr"; else : > "$D/App.mpr"; fi
  stub_mxcli "$D" v0.28.0
  dr() { HOME="$WORK/home" bash "$TK/bin/doctor.sh" --quick "$D" 2>&1; }
  printf '{\n  "counts": {},\n  "total": 0,\n  "mxcli_version": "v0.27.0"\n}\n' > "$D/.claude/lint-baseline.json"
  out="$(dr)"
  printf '%s' "$out" | grep -q "lint baseline was taken with mxcli v0.27.0; this is v0.28.0" \
    && printf '%s' "$out" | grep -qF -- "--update-baseline --reason \"mxcli v0.28.0 built-in rules\"" && ok "[$L] doctor prints the re-baseline hint" || bad "[$L] no hint" "$out"
  printf '{\n  "counts": {},\n  "total": 0,\n  "mxcli_version": "v0.28.0"\n}\n' > "$D/.claude/lint-baseline.json"
  out="$(dr)"
  printf '%s' "$out" | grep -q "lint baseline" && bad "[$L] hint printed when versions match" "$out" || ok "[$L] quiet when versions match"
  printf '{\n  "counts": {},\n  "total": 0\n}\n' > "$D/.claude/lint-baseline.json"
  out="$(dr)"
  printf '%s' "$out" | grep -q "lint baseline records no mxcli version" && ok "[$L] says so when the baseline predates the field" || bad "[$L] no note for an unversioned baseline" "$out"
  printf '%s' "$out" | grep -qF -- "--update-baseline --reason" && bad "[$L] unversioned baseline: re-baseline command printed with no evidence of a rise" "$out" \
    || ok "[$L] unversioned baseline: no re-baseline command, says the next one records it"
done

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
