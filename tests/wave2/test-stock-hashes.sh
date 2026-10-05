#!/usr/bin/env bash
# test-stock-hashes.sh — fixture for lint-rules/STOCK-HASHES.txt, the list that lets
# sync-project.sh tell an untouched stock lint rule (safe to replace) from a hand-edited one
# (report, never write). See bin/lib/install-lint-rules.sh.
#
# Why this exists: test-lint-delivery.sh forges its own hash file, so nothing checked the REAL
# list. A typo there fails silently in the safe direction — a stock rule is reported as
# hand-edited on every sync — and nobody notices until a project wonders why its rules never
# refresh. Until 2026-10-05 the list knew only v0.17.0, so that is exactly what v0.24/v0.25
# projects saw.
#
#   T1  every entry is <rule-file>  <32-hex md5>  <vX.Y.Z>, no duplicate (rule, version)
#   T2  every rule named is one the toolkit owns (MXTK_LINT_RULES), and every listed
#       version covers all of them — a half-captured version is caught here
#   T3  the real reader (_mxtk_lint_is_stock) accepts every entry and rejects a foreign hash
#   T4  live, only with a binary: `mxcli init` into an EMPTY dir, every seeded rule's md5 is
#       listed. This is the capture procedure in the file's own header, run as a check.
#       Without a binary it prints SKIP — CI has no mxcli.
#
# Usage: bash tests/wave2/test-stock-hashes.sh [mxcli-binary]   (or MXCLI=<binary>)
# Keep bash-3.2 compatible: stock macOS `env bash` is 3.2.57.

set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HASHES="$TK/lint-rules/STOCK-HASHES.txt"
MX="${1:-${MXCLI:-}}"
. "$TK/bin/lib/portable.sh"
. "$TK/bin/lib/install-manifest.sh" >/dev/null 2>&1
. "$TK/bin/lib/install-lint-rules.sh"

PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

entries() { grep -vE '^[[:space:]]*(#|$)' "$HASHES"; }

echo "== T1 format =="
[ -f "$HASHES" ] && ok "STOCK-HASHES.txt present" || { no "STOCK-HASHES.txt missing"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
bad=$(entries | awk 'NF!=3 || $2 !~ /^[0-9a-f]{32}$/ || $3 !~ /^v[0-9]+\.[0-9]+\.[0-9]+$/')
[ -z "$bad" ] && ok "every entry is <file> <md5> <vX.Y.Z>" || no "malformed: $bad"
grep -q "$(printf '\r')" "$HASHES" && no "CRLF line endings — the reader would miss every hash" \
                                  || ok "LF line endings"
dup=$(entries | awk '{print $1" "$3}' | sort | uniq -d)
[ -z "$dup" ] && ok "no duplicate (rule, version)" || no "duplicate: $dup"

echo "== T2 coverage =="
[ -n "${MXTK_LINT_RULES:-}" ] && ok "MXTK_LINT_RULES loaded" || no "MXTK_LINT_RULES empty — manifest not loaded"
for f in $(entries | awk '{print $1}' | sort -u); do
  case " $MXTK_LINT_RULES " in *" $f "*) ok "listed rule is toolkit-owned: $f" ;;
    *) no "$f is listed but not in MXTK_LINT_RULES — nothing ever looks it up" ;; esac
done
for v in $(entries | awk '{print $3}' | sort -u); do
  missing=""
  for f in $MXTK_LINT_RULES; do
    entries | awk -v f="$f" -v v="$v" '$1==f && $3==v {x=1} END {exit !x}' || missing="$missing $f"
  done
  [ -z "$missing" ] && ok "$v covers all toolkit-owned rules" || no "$v is missing:$missing"
done

echo "== T3 the real reader agrees =="
miss=""
while read -r f h _v; do
  _mxtk_lint_is_stock "$f" "$h" "$HASHES" || miss="$miss $f@$_v"
done <<EOF
$(entries)
EOF
[ -z "$miss" ] && ok "_mxtk_lint_is_stock accepts every entry" || no "reader rejects:$miss"
_mxtk_lint_is_stock conv010_act_microflow_content.star 00000000000000000000000000000000 "$HASHES" \
  && no "reader accepts a foreign hash" || ok "reader rejects a foreign hash"
for f in $MXTK_LINT_RULES; do
  [ -f "$TK/lint-rules/$f" ] || continue
  _mxtk_lint_is_stock "$f" "$(portable_md5 "$TK/lint-rules/$f")" "$HASHES" \
    && no "the toolkit's own $f is listed as stock" || ok "toolkit's own $f is not 'stock'"
done

echo "== T4 live capture =="
if [ -z "$MX" ]; then
  echo "  SKIP no mxcli binary given (pass one as \$1 or MXCLI=) — T1–T3 still ran"
elif [ ! -x "$MX" ]; then
  no "mxcli binary not executable: $MX"
else
  W=$(mktemp -d "${TMPDIR:-/tmp}/stockhash.XXXXXX"); trap 'rm -rf "$W"' EXIT
  ( cd "$W" && "$MX" init . >/dev/null 2>&1 )
  seeded=0
  for f in $MXTK_LINT_RULES; do
    s="$W/.claude/lint-rules/$f"
    [ -f "$s" ] || continue
    seeded=$((seeded+1))
    h=$(portable_md5 "$s")
    _mxtk_lint_is_stock "$f" "$h" "$HASHES" && ok "seeded $f is listed" \
      || no "seeded $f ($h) is NOT listed — add it with this mxcli's version"
  done
  [ "$seeded" -gt 0 ] && ok "init seeded $seeded toolkit-owned rule(s)" \
                      || no "init seeded none of: $MXTK_LINT_RULES — did it run?"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
