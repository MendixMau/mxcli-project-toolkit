#!/usr/bin/env bash
# Usage: bash tests/wave2/test-must-haves-advisory.sh /path/to/bin/sync-project.sh
#   (bin/init-project.sh and bin/lib/obligation-check.sh are derived from its directory)
#
# The must-haves row (#787) owes a per-module mark from Stage 5. A project already past Stage 5
# when the row arrived is recorded ONCE as `Must-haves: advisory` by sync-project.sh: the row is
# shown, never counted. Everyone else is `Must-haves: bound` (init-project.sh, or the first sync).
# Keyed on the written line, never on position — a position check would silence a NEW project the
# day it passed Stage 5 without the marks.
#
# Positive control: against #787 without this change, T1-T4 fail (no line written, no ADVISORY).
set -uo pipefail
SYNC="${1:?usage: test-must-haves-advisory.sh /path/to/bin/sync-project.sh}"
SYNC="$(cd "$(dirname "$SYNC")" && pwd)/$(basename "$SYNC")"
INIT="$(dirname "$SYNC")/init-project.sh"
OBCHECK="$(dirname "$SYNC")/lib/obligation-check.sh"
for f in "$INIT" "$OBCHECK"; do [ -r "$f" ] || { echo "missing $f"; exit 2; }; done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mh-adv.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
export MXTK_NO_GUIDE=1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
mhline() { grep -E '^Must-haves:' "$1/PROJECT.md"; }

echo "== T1: a new project is bound from birth =="
bash "$INIT" "$WORK/fresh" </dev/null >/dev/null 2>&1
case "$(mhline "$WORK/fresh")" in "Must-haves: bound") ok "init writes bound" ;; *) bad "init: $(mhline "$WORK/fresh")" ;; esac

echo "== T2: a project adopted at Stage 6 with no line is made advisory, once =="
bash "$INIT" "$WORK/old" </dev/null >/dev/null 2>&1
sed -i.bak '/^Must-haves:/d' "$WORK/old/PROJECT.md" && rm -f "$WORK/old/PROJECT.md.bak"
printf '\nAdopted at stage: 6\n' >> "$WORK/old/PROJECT.md"
bash "$SYNC" "$WORK/old" </dev/null >/dev/null 2>&1
case "$(mhline "$WORK/old")" in "Must-haves: advisory"*"stage 6"*) ok "sync writes advisory" ;; *) bad "sync: $(mhline "$WORK/old")" ;; esac
bash "$SYNC" "$WORK/old" </dev/null >/dev/null 2>&1
[ "$(mhline "$WORK/old" | wc -l | tr -d ' ')" = 1 ] && ok "second sync writes nothing more" || bad "line duplicated"

echo "== T3: a project not past Stage 5 with no line is made bound =="
bash "$INIT" "$WORK/mid" </dev/null >/dev/null 2>&1
sed -i.bak '/^Must-haves:/d' "$WORK/mid/PROJECT.md" && rm -f "$WORK/mid/PROJECT.md.bak"
bash "$SYNC" "$WORK/mid" </dev/null >/dev/null 2>&1
case "$(mhline "$WORK/mid")" in "Must-haves: bound") ok "sync writes bound" ;; *) bad "sync: $(mhline "$WORK/mid")" ;; esac

echo "== T4: advisory is shown, not counted; bound is PENDING and counted =="
Q="$WORK/q"; mkdir -p "$Q/architecture/modules/Orders"
printf 'Must-haves: advisory — joined at stage 6 before the must-haves row existed\n' > "$Q/PROJECT.md"
l="$(MXTK_ROWS_UPTO=5 "$OBCHECK" "$Q" 2>/dev/null | grep '^Obligation must-haves ')"
case "$l" in *ADVISORY*"0 of 1"*Orders*) ok "$l" ;; *) bad "expected ADVISORY: $l" ;; esac
a="$( . "$OBCHECK"; mxtk_obligations_report "$Q" >/dev/null; echo "$MXTK_OB_N_PENDING")"
printf 'Must-haves: bound\n' > "$Q/PROJECT.md"
l="$(MXTK_ROWS_UPTO=5 "$OBCHECK" "$Q" 2>/dev/null | grep '^Obligation must-haves ')"
case "$l" in *PENDING*"0 of 1"*) ok "bound reads PENDING" ;; *) bad "expected PENDING: $l" ;; esac
b="$( . "$OBCHECK"; mxtk_obligations_report "$Q" >/dev/null; echo "$MXTK_OB_N_PENDING")"
[ "$b" = $((a+1)) ] && ok "advisory row not in the pending count ($a vs $b)" || bad "counts: advisory $a, bound $b"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
