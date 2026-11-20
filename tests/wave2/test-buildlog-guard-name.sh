#!/usr/bin/env bash
# test-buildlog-guard-name.sh - every refusal / rollback / blocked BUILD-LOG row names its guard.
#
# usage: bash tests/wave2/test-buildlog-guard-name.sh [path-to-exec.sh]
#        (metrics-trend.sh and metrics-ledger.sh are read from the same directory)
#
# WHY (overengineering audit, 2026-11-20). A field metrics file had 13 of 136 execs "blocked or
# refused" and no row said which guard refused, so nobody could weigh a guard's catches against
# its false refusals. exec.sh's log_build now takes the guard id as $3 and writes " · guard=<id>"
# right after the detail text; metrics-trend.sh counts those per guard.
#
#   A  static, over the subject: every log_build call whose status is a stop (🚫, ✗ refused, ❌,
#      ↩) passes a guard id from the known set; the denominator (25 calls on 2026-11-20) is
#      printed, and a call with none fails. No applied/PARTIAL row passes one.
#   B  three real refusals, run end to end on a stub project (pre-exec `mxcli check`, uncommitted
#      model, mxbuild absent): the row carries guard=<id>; result cell, exit code and 5-cell
#      shape unchanged. mxbuild-missing is its own id, apart from mxbuild-gate (review of #813:
#      an absent toolchain is the environment, not a catch).
#   A also checks the split: pre-existing errors and gate crashes carry their own ids, and
#      patch-exit (the script failing, not a guard) stays out of "blocked by guard".
#   C  metrics-trend.sh over the ledger + BUILD-LOG exactly as B's runs wrote them (not
#      hand-written), plus the captured verify-446 applied row and the same refusals with their
#      token stripped (the shape a pre-change exec.sh writes): "blocked by guard:" names each
#      guard with its count and counts the old rows as unnamed; --since filters it.
#
# Synthetic project, stub mxcli. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
SUBDIR="$(dirname "$SUBJECT")"
TREND="$SUBDIR/metrics-trend.sh"; [ -f "$TREND" ] || TREND="$TOOLKIT/project-bin/metrics-trend.sh"
LEDGER_SH="$SUBDIR/metrics-ledger.sh"; [ -f "$LEDGER_SH" ] || LEDGER_SH="$TOOLKIT/project-bin/metrics-ledger.sh"
CAPTURED="$TOOLKIT/tests/wave2/fixtures/verify-446/BUILD-LOG.captured.md"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/bl-guard.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"
echo "== trend:   $TREND"

# ---- A: static -----------------------------------------------------------------------------
KNOWN="plan-rule stop-row-scan row-group-gate lock-studio-pro commit-first uncommitted-model marketplace-gate mxcli-check mxbuild-missing pre-existing-errors mxbuild-crash mxbuild-gate patch-exit hash-verify"
n_stop=0; n_named=0; n_bad_applied=0; missing=""
while IFS= read -r line; do
  st="${line#*log_build \"}"; st="${st%%\"*}"
  last="${line##*\" }"; case "$line" in *'"') last="" ;; esac
  case "$st" in
    "🚫"*|"✗ refused"*|"❌"*|"↩"*)
      n_stop=$((n_stop+1))
      case " $KNOWN " in *" $last "*) [ -n "$last" ] && n_named=$((n_named+1)) || missing="$missing|$line" ;;
        *) missing="$missing|$line" ;; esac ;;
    *) [ -n "$last" ] && n_bad_applied=$((n_bad_applied+1)) ;;
  esac
done < <(grep -E '^[^#]*log_build "' "$SUBJECT" | grep -v '^ *log_build() ')
echo "  (stop-row log_build calls: $n_stop, naming a known guard: $n_named)"
[ "$n_stop" -ge 20 ] && ok "A: found the stop-row calls ($n_stop)" || bad "A: found the stop-row calls" "only $n_stop"
[ "$n_named" = "$n_stop" ] && ok "A: all $n_stop stop rows name a known guard" \
  || bad "A: all stop rows name a known guard" "$((n_stop - n_named)) without:$(printf '%s' "$missing" | cut -c1-300)"
[ "$n_bad_applied" = 0 ] && ok "A: no applied/PARTIAL row names a guard" || bad "A: applied/PARTIAL rows naming a guard" "$n_bad_applied"

# ---- B: real refusals ----------------------------------------------------------------------
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
cp "$LEDGER_SH" "$P/bin/metrics-ledger.sh"; cp "$TREND" "$P/bin/metrics-trend.sh"
printf '#!/usr/bin/env bash\necho "Snapshot saved: none"\n' > "$P/bin/snapshot-mpr.sh"
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in
  check) [ -n "${CHECK_OK:-}" ] && exit 0
         echo "error MDL-PAGEARG01: show page with two parameters" >&2; exit 1 ;;
  exec)  echo "EXEC REACHED" >> "$EXEC_N"; exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$P/bin/"*.sh "$P/mxcli"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

run() {  # -> RC, ROW
  ( cd "$P" && MXBUILD_PATH="$WORK/no-mxbuild" EXEC_N="$WORK/n" SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 TMPDIR="$WORK" \
      ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out" 2>&1
  RC=$?
  ROW="$(grep '^| ' "$P/docs/BUILD-LOG.md" 2>/dev/null | tail -1)"
}
cells() { printf '%s' "$1" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' '; }

run   # 1: pre-exec mxcli check refuses
case "$ROW" in *"| 🚫 blocked | mxcli check failed pre-exec — nothing written to the model; check: "*" two parameters · guard=mxcli-check · change: "*)
  ok "B: mxcli check refusal row carries guard=mxcli-check after the detail text" ;;
  *) bad "B: mxcli check refusal row carries guard=mxcli-check" "$ROW" ;; esac
case "$ROW" in *"check: error MDL-PAGEARG01"*) ok "B: check reason still in the row" ;; *) bad "B: check reason still in the row" "$ROW" ;; esac
[ "$RC" = 1 ] && ok "B: exit code still 1" || bad "B: exit code still 1" "$RC"
[ "$(cells "$ROW")" = 6 ] && ok "B: row keeps 5 cells" || bad "B: row keeps 5 cells" "$ROW"

printf 'bson changed\n' > "$P/mprcontents/a.mxunit"
run   # 2: uncommitted model refuses (before check)
case "$ROW" in *"| 🚫 blocked | uncommitted model changes — refusing exec to prevent snapshot regression · guard=uncommitted-model"*)
  ok "B: uncommitted-model row carries guard=uncommitted-model" ;;
  *) bad "B: uncommitted-model row carries guard=uncommitted-model" "$ROW" ;; esac
[ "$RC" = 1 ] && ok "B: exit code still 1" || bad "B: exit code still 1" "$RC"
[ ! -f "$WORK/n" ] && ok "B: exec never reached" || bad "B: exec reached"

( cd "$P" && git checkout -q -- mprcontents )
export CHECK_OK=1
run   # 3: mxcli check passes, mxbuild absent -> refused before any write
unset CHECK_OK
case "$ROW" in *"| ✗ refused | mxbuild gate cannot run (mxbuild: missing"*"nothing written · guard=mxbuild-missing"*)
  ok "B: absent mxbuild row carries guard=mxbuild-missing, not mxbuild-gate" ;;
  *) bad "B: absent mxbuild row carries guard=mxbuild-missing" "$ROW" ;; esac
[ "$RC" = 1 ] && ok "B: exit code still 1" || bad "B: exit code still 1" "$RC"
[ ! -f "$WORK/n" ] && ok "B: exec never reached" || bad "B: exec reached"

# A, the split (review of #813): each mxbuild stop names what stopped it.
gid() { grep -F "$1" "$SUBJECT" | grep 'log_build' | sed 's/.*" \([a-z0-9-]*\)$/\1/' | sort -u | tr '\n' ' '; }
[ "$(gid 'PRE-EXISTING $BASE_CODES')" = "pre-existing-errors " ] && ok "A: pre-existing errors -> pre-existing-errors" \
  || bad "A: pre-existing errors id" "$(gid 'PRE-EXISTING $BASE_CODES')"
[ "$(gid '"❌ gate could not run"')" = "mxbuild-crash " ] && ok "A: gate could not run -> mxbuild-crash (all sites)" \
  || bad "A: gate could not run id" "$(gid '"❌ gate could not run"')"
[ "$(gid '"❌ gate failed"')" = "mxbuild-gate " ] && ok "A: script-introduced errors -> mxbuild-gate (all sites)" \
  || bad "A: gate failed id" "$(gid '"❌ gate failed"')"

# ---- C: metrics-trend per-guard line -------------------------------------------------------
L="$P/.claude/loop/metrics-ledger.tsv"
[ "$(grep -c . "$L" 2>/dev/null)" = 4 ] && ok "C: the three refusals landed in the ledger" || bad "C: ledger rows" "$(cat "$L" 2>/dev/null)"
# The captured applied row, and the same two refusals as a pre-change exec.sh wrote them.
grep '^| 2026-' "$CAPTURED" >> "$P/docs/BUILD-LOG.md"
grep '🚫' "$P/docs/BUILD-LOG.md" | sed 's/ · guard=[a-z0-9-]*//' >> "$P/docs/BUILD-LOG.md"
# A token-less old row whose detail text quotes a bare "guard=" (mxcli or CE text) stays unnamed,
# and a --patch script failure is counted apart from the guards. Both derived from B's real row.
b="$(grep 'guard=mxcli-check' "$P/docs/BUILD-LOG.md" | head -1)"
printf '%s\n' "$b" | sed 's/ · guard=mxcli-check/ (mxcli: guard=row-group-gate)/' >> "$P/docs/BUILD-LOG.md"
printf '%s\n' "$b" | sed 's/| 🚫 blocked | mxcli check failed pre-exec/| ❌ patch failed | script exit 3 — rolled back, gate not run/; s/guard=mxcli-check/guard=patch-exit/' >> "$P/docs/BUILD-LOG.md"
s="$(bash "$P/bin/metrics-trend.sh" 2>&1)"
case "$s" in *"blocked by guard: mxbuild-missing 1, mxcli-check 1, uncommitted-model 1, unnamed 3"*) ok "C: per-guard counts, old rows (and a bare guard= in detail text) as unnamed" ;;
  *) bad "C: per-guard counts" "$(printf '%s' "$s" | tr '\n' '~')" ;; esac
case "$s" in *"script failed (--patch exit, not a guard): 1"*) ok "C: patch-exit counted as script failed, not a guard" ;;
  *) bad "C: patch-exit counted apart" "$(printf '%s' "$s" | tr '\n' '~')" ;; esac
case "$s" in *"blocked / refused          3 (100%)"*) ok "C: ledger outcome counts unchanged" ;;
  *) bad "C: ledger outcome counts unchanged" "$(printf '%s' "$s" | tr '\n' '~')" ;; esac
s2="$(bash "$P/bin/metrics-trend.sh" --since 2999-01-01 2>&1)"
case "$s2" in *"blocked by guard"*) bad "C: --since 2999 printed a guard line" "$s2" ;; *) ok "C: --since filters (no rows, no line)" ;; esac
rm -f "$P/docs/BUILD-LOG.md"
s3="$(bash "$P/bin/metrics-trend.sh" 2>&1)"
case "$s3" in *"blocked by guard: not counted (no docs/BUILD-LOG.md beside the ledger)"*) ok "C: missing BUILD-LOG said, not silent" ;;
  *) bad "C: missing BUILD-LOG said" "$(printf '%s' "$s3" | tr '\n' '~')" ;; esac

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
