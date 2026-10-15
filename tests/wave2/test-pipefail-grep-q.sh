#!/usr/bin/env bash
# Fixture for the `producer | grep -q` + `set -o pipefail` false negative.
#
# usage: test-pipefail-grep-q.sh /path/to/bin/lib/skill-routing.sh
#
# The defect: `grep -q` exits on its first match. If the producer on the left of the pipe
# still has output to write, that write hits a closed pipe, the producer dies of SIGPIPE
# (status 141), and under `set -o pipefail` the PIPELINE reports failure — so "found it"
# reads as "not found". Whether the producer had finished writing before grep exited is a
# scheduling race, which is why `bin/render-routing.sh --check` intermittently reported
# `UNROUTED skills/iterative-build-loop.md` although its row exists (the routed-path list is
# ~4.8 KB, more than one stdio buffer, so `printf` writes it in two chunks). Measured on the
# real table before the fix: 15 of 100 calls of routing_unrouted_skills named a routed skill.
#
# The fix is a here-string (`grep -q -- "$x" <<<"$list"`): bash writes the whole input
# before grep starts, so nothing can be killed mid-write. This fixture makes the race
# deterministic instead of probabilistic: the matching line comes FIRST and is followed by
# ~1 MB of padding — far beyond the 64 KB pipe buffer — so on the old code the producer is
# always still writing when grep exits.
#
# T1  routing_unrouted_skills: a routed skill must not be reported unrouted.
# T2  routing_stale_exemptions: an exempted-AND-routed file must still be reported.
# T3  static guard: the scripts fixed alongside (all run under pipefail, directly or via the
#     script that sources them) carry no `... | grep -q` pipeline again.

set -uo pipefail

LIB="${1:?usage: test-pipefail-grep-q.sh /path/to/bin/lib/skill-routing.sh}"
case "$LIB" in /*) ;; *) LIB="$PWD/$LIB" ;; esac
TK="$(cd "$(dirname "$LIB")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pipefail-grepq.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# A scratch root with one skill, and a routing table whose FIRST row routes it, then ~16,000
# padding rows (about 1 MB of routed paths).
ROOT="$WORK/root"
mkdir -p "$ROOT/skills"
printf '# Early\n' > "$ROOT/skills/early.md"
TSV="$WORK/skill-routing.tsv"
{
  printf 'Early skill\tskills/early.md\tany\tall\t5\tsituational\tverify\n'
  i=0
  while [ "$i" -lt 16000 ]; do
    printf 'Padding row %d\tskills/padding/a-long-padding-path-to-overflow-the-pipe-buffer-%05d.md\tany\tall\t5\tsituational\tverify\n' "$i" "$i"
    i=$((i+1))
  done
} > "$TSV"
EMPTY_EX="$WORK/exempt-empty.tsv"; : > "$EMPTY_EX"
STALE_EX="$WORK/exempt-stale.tsv"; printf 'skills/early.md\tfixture: exempted and routed\n' > "$STALE_EX"

# Sourced in a subshell with pipefail on, as bin/render-routing.sh runs it (set -euo pipefail).
run_lib() { # <exempt-file> <function>
  ( set -o pipefail
    MXTK_ROUTING_TSV="$TSV" MXTK_ROUTING_EXEMPT="$1"
    # shellcheck source=/dev/null
    . "$LIB"
    "$2" "$ROOT" )
}

echo "== T1: a routed skill is not reported UNROUTED (match first, 1 MB after it) =="
bad1=0
for n in 1 2 3; do
  out="$(run_lib "$EMPTY_EX" routing_unrouted_skills 2>&1)"
  [ -z "$out" ] || { bad1=1; bad "run $n: routed skill reported unrouted" "$out"; break; }
done
[ "$bad1" = 0 ] && ok "routing_unrouted_skills is empty on 3 of 3 runs"

echo "== T2: an exempted-AND-routed file is still reported (same race, opposite sign) =="
out="$(run_lib "$STALE_EX" routing_stale_exemptions 2>&1)"
case "$out" in
  *'skills/early.md — exempted AND routed'*) ok "stale exemption reported" ;;
  *) bad "stale exemption missed" "$out" ;;
esac

echo "== T3: no '| grep -q' pipeline left in the scripts fixed for this defect =="
# gate-check.sh's `find_artifact ... | grep -q .` lines are exempt: find_artifact ends in
# `-print -quit`, so its producer writes at most one line and is finished before grep exits.
hits=""
for f in bin/lib/skill-routing.sh bin/lib/obligation-check.sh bin/lib/triage-template.sh \
         bin/gate-check.sh bin/check-portability.sh \
         project-bin/_common.sh project-bin/check-design-portability.sh project-bin/check-page-shell.sh \
         project-bin/close-task.sh project-bin/check-sp-health.sh project-bin/app-restart.sh \
         project-bin/test-stack-up.sh \
         bin/sync-project.sh project-bin/review-module.sh project-bin/conformance-check.sh; do
  [ -f "$TK/$f" ] || { hits="$hits
$f: missing"; continue; }
  h="$(grep -nE '(^|[^|])\|[[:space:]]*grep[[:space:]]+(-[A-Za-z]*q|[^|]*[[:space:]]-[A-Za-z]*q)' "$TK/$f" \
       | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'find_artifact' | sed "s|^|$f:|")"
  [ -n "$h" ] && hits="$hits
$h"
done
if [ -z "$hits" ]; then ok "0 pipelines into grep -q across 15 scripts"
else bad "pipeline into grep -q found (use a here-string: grep -q -- PAT <<<\"\$x\")" "${hits#?}"; fi

echo
echo "pipefail-grep-q: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
