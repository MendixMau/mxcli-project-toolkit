#!/usr/bin/env bash
# lint-gate.sh — run mxcli lint on OUR modules and fail only when a rule gets worse.
#
# Why a ratchet and not a threshold:
#   This project has ~500 pre-existing findings and 0 errors. Promoting severities to
#   "error" would fail every gate forever and the gate would be switched off within a
#   day — which is exactly how lint died here the first time. Instead we freeze today's
#   per-rule counts as a baseline and fail only on an INCREASE. Debt is tolerated;
#   adding to it is not.
#
# READ-ONLY. `mxcli lint` does not write to the .mpr (verified by md5 before/after,
# 2026-08-14). This script therefore does not need RULE 1 approval, unlike exec/test.
#
# Usage:
#   bin/lint-gate.sh                    # check against baseline; exit 1 if any rule rose
#   bin/lint-gate.sh --update-baseline  # accept current counts as the new baseline
#       --reason "<why>"                # REQUIRED when the update raises any rule's count
#       then bin/baseline-approve.sh lint  # run by the USER, in a terminal, when it rises
#   bin/lint-gate.sh --full             # ignore the vendor exclusion (rarely useful)
#
# Exit codes: 0 clean or unchanged · 1 a rule increased, or BLIND (a rule inspected nothing,
#             or the toolkit rules reverted to stock — see below) · 2 could not run (or a
#             refused update)
#
# RULES REVERTED TO STOCK ARE BLIND, NOT A RISE (#264, 2026-10-13). `mxcli init` re-seeds
# .claude/lint-rules/ and silently overwrites the toolkit's rules with stock ones. Two apps hit
# it: CONV010 went 26 -> 169 and the next exec — a pages-only script — was logged as the rise;
# in the other the re-seed sat uncommitted for five days and the baseline absorbed the noisier
# counts. bin/lib/install-lint-rules.sh already writes .claude/.mxtk-lint-receipt (md5 of each
# rule AS INSTALLED; it survives `mxcli init`), so before linting this script reads it: a rule
# whose md5 no longer matches its receipt line AND whose `# mxtk-lint-rule:` header is gone was
# re-seeded, not edited by a person — checked only for rules the receipt marks `stock` (the file
# names init seeds; toolkit-only and configurable rules are never seeded, so a headerless copy
# of one is an edit). A receipt-listed rule whose file is gone is reported for every kind. The run then prints "BLIND — lint
# rules reverted to stock", names the files, points at sync-project.sh (which restores them and
# rewrites the receipt, so the next run is clean) and exits 1 without linting; --update-baseline
# is refused, since baselining stock counts is how the five-day case went in. A rule that still
# carries the header but differs is a hand edit — install-lint-rules.sh reports those, this does
# not. No receipt, or a row without a kind = no check (the next sync writes kinds). A non-stock
# rule the user opted out of is listed, with a reason, in .claude/lint-rules-disabled.txt, and
# switched off with `enabled: false` in lint-config.yaml (see lint-rules/README.md "Opting out
# of a rule"; never delete the file). LINT_RULES_REVERTED_OK=1 runs anyway, with
# the warning (a check run only: --update-baseline stays refused).
#
# ACCEPTING DEBT IS RECORDED, NOT SILENT (2026-10-12). Three toolkit-built apps re-baselined
# 61 times in four days — every acceptance made by the agent whose script caused the rise,
# with no reason field and nothing that ever summed them: baselines grew 8 -> 757, 440 -> 677
# and 9 -> 187, and security warnings (CONV006, SEC003) went in in the same batches as naming
# info. So an update that RAISES any rule now needs --reason, and is appended to
# .claude/lint-acceptances.tsv (ts, total before/after, per-rule rises, security flag, reason)
# — commit it with the baseline. A first baseline and a pure ratchet-down need no reason.
# A rise in a security-tier rule (default SEC* and CONV006; override, one id or glob per line,
# in .claude/lint-security-rules.txt) is flagged as such in that log.
#
# A RISE NEEDS A PERSON, NOT A FLAG (#348, 2026-10-14). --approved-in-chat was the proof the user
# said yes, and the agent could type it itself. Now any update that raises a rule (or re-creates
# a deleted baseline, or follows a hand edit gate-check would FAIL) writes only content a person
# approved: the refused run saves the proposal and prints `bin/baseline-approve.sh lint` for the
# USER to run in their terminal; it records the sha256 of exactly that content, and the re-run
# writes it. A first baseline and a pure ratchet-down still need nothing. --approved-in-chat is
# accepted and ignored, so old command lines still parse. See baseline-lock.sh.
#
# PRODUCES .claude/loop/lint-ledger.tsv (append-only, one row per rule per run; read with
# project-bin/lint-trend.sh) and .claude/loop/lint-last.json on every run that actually gets as far as computing
# counts (timestamp, verdict, total, per-rule counts) — the dir is created if absent. This is
# NOT docs/BUILD-LOG.md (the exec table Studio's parseExecRows / bin/status.sh /
# project-bin/done-drift-check.sh parse) and must never become another writer of it; it is a
# separate, additive record of lint's own last verdict. Mandatory producing chain step: the
# per-module GATE pass (skills/module-review.md stage 2 — "bin/exec.sh; gate-agent confirms
# 0 mxbuild errors, lint clean", same step named in skills/iterative-build-loop.md's
# "Gate: BUILD"). Consumed by bin/status.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

# Python is resolved, not assumed: a bare `python3` is the Store alias stub on Windows and a
# prompt-only stub on a Mac without the CLT. Both satisfy `command -v` and neither runs anything.
#
# require_py lives in _common.sh, but this script MUST NOT assume a sibling of its own vintage.
# sync-project.sh installs a missing _common.sh and REPORTS a locally-modified one rather than
# overwriting it — deliberately, since projects harden their crash net. So every project that
# has already tuned _common.sh would receive this script and have it die on line 1 with
# "require_py: command not found". Measured on PROJECT-C before this fallback existed.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/_common.sh" ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
fi
if ! type require_py >/dev/null 2>&1; then
  require_py() {
    _c=""
    for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
      case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
      if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
        PY="$_c"; export PY; return 0
      fi
    done
    echo "lint-gate: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
require_py

# The .mpr is discovered, not hardcoded. A per-project default here is how this script
# was previously un-promotable: it named PROJECT-C.mpr and silently linted nothing anywhere
# else (mxcli exits 0 on a missing project, so the gate reported a clean PASS).
if [ -z "${MPR:-}" ]; then
  MPR="$(ls "$ROOT"/*.mpr 2>/dev/null | head -1)"
  MPR="$(basename "${MPR:-}")"
  # Two-tree layout (.mpr under app/): the same one-level-down probe as _common.sh find_mpr.
  # Without it lint-gate exited 2 ("no .mpr found") on every exec of a two-tree project and
  # exec.sh logged "lint could not run" — the ratchet was silently off for a whole build
  # (card-disbursement requirements-driven build, 2026-09-25; F-020/F-042 class).
  if [ -z "$MPR" ] && ls "$ROOT"/app/*.mpr >/dev/null 2>&1; then
    MPR="app/$(basename "$(ls "$ROOT"/app/*.mpr | head -1)")"
  fi
fi
if [ -z "$MPR" ] || [ ! -f "$ROOT/$MPR" ]; then
  echo "lint-gate: no .mpr found in $ROOT or $ROOT/app — set MPR=<name>.mpr" >&2
  exit 2
fi
if [ "$(ls "$ROOT"/*.mpr 2>/dev/null | wc -l | tr -d " ")" -gt 1 ] && [ -z "${MPR_EXPLICIT:-}" ]; then
  echo "lint-gate: several .mpr files here; linting $MPR. Set MPR=<name>.mpr to choose." >&2
fi
VENDOR_FILE="$ROOT/.claude/lint-vendor-modules.txt"
BASELINE="$ROOT/.claude/lint-baseline.json"
OUT="${TMPDIR:-/tmp}/lint-gate-$$.json"
trap 'rm -f "$OUT"' EXIT

UPDATE=0
FULL=0
REASON=""
APPROVED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update-baseline) UPDATE=1 ;;
    --full) FULL=1 ;;
    --reason) [ $# -ge 2 ] || { echo "lint-gate: --reason needs a value" >&2; exit 2; }
              REASON="$2"; shift ;;
    --reason=*) REASON="${1#--reason=}" ;;
    --approved-in-chat) APPROVED=1 ;;  # retired as evidence (#348): accepted, ignored
    -h|--help) sed -n '2,71p' "$0"; exit 0 ;;
    *) echo "lint-gate: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
SECURITY_FILE="$ROOT/.claude/lint-security-rules.txt"
ACCEPT_LOG="$ROOT/.claude/lint-acceptances.tsv"

# SEC014 not decided yet (#268 review): with no `external_roles` under SEC014 in
# lint-config.yaml the rule reports nothing, by design (a `_rule` finding would fail every exec
# of every synced project, the #229 pattern). Say so on every run, on stderr, uncounted: no
# exit-code change, no lint row. Same test as bin/lib/sec014-notice.sh (inline: a project has
# no bin/lib); `enabled: false` there is the same user decision as "none".
if [ -f "$ROOT/.claude/lint-rules/sec014_external_role_write.star" ]; then
  _sec014_cfg="$ROOT/.claude/lint-config.yaml"
  if [ ! -f "$_sec014_cfg" ] || ! awk '
    /^[[:space:]]*#/ { next }
    { match($0, /^ */); ind = RLENGTH }
    insec && NF && ind <= secind { insec = 0 }
    /^[[:space:]]*"?SEC014"?[[:space:]]*:/ {
      insec = 1; secind = ind
      if ($0 ~ /external_roles[[:space:]]*:/ || $0 ~ /enabled[[:space:]]*:[[:space:]]*false/) found = 1
      next
    }
    insec && /^[[:space:]]*external_roles[[:space:]]*:/ { found = 1 }
    insec && /^[[:space:]]*enabled[[:space:]]*:[[:space:]]*false/ { found = 1 }
    END { exit found ? 0 : 1 }' "$_sec014_cfg"; then
    echo "note: SEC014 not configured — set .claude/lint-config.yaml rules: SEC014: options: external_roles (ask the user; 'none' is their decision)" >&2
  fi
fi

# This script does not source _common.sh (see header); resolve the binary the same way it
# does — mxcli.exe first on Git Bash, since the Dev Container may have left a Linux `mxcli`.
MXCLI=""
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) [ -x ./mxcli.exe ] && MXCLI=./mxcli.exe ;; esac
[ -n "$MXCLI" ] || { [ -x ./mxcli ] && MXCLI=./mxcli; }
[ -n "$MXCLI" ] || { echo "lint-gate: no runnable mxcli in $ROOT (Windows: mxcli.exe) — bin/doctor.sh --install" >&2; exit 2; }
[ -e "$MPR" ]  || { echo "lint-gate: $MPR not found" >&2; exit 2; }

# Build the --exclude list from the vendor file (comments and blanks stripped).
EXCLUDE=""
if [ "$FULL" -eq 0 ] && [ -f "$VENDOR_FILE" ]; then
  EXCLUDE="$(grep -v '^[[:space:]]*#' "$VENDOR_FILE" | grep -v '^[[:space:]]*$' | paste -sd, -)"
fi

# Receipt check (#264, see header). Runs before lint, on check AND update runs, and also under
# LINT_JSON so fixtures exercise it. Reads the receipt bin/lib/install-lint-rules.sh writes;
# never writes it — only the installer does, and that is the remedy named below.
RECEIPT="$ROOT/.claude/.mxtk-lint-receipt"
if [ -f "$RECEIPT" ]; then
  # Read into a variable first: a heredoc inside $(...) does not parse on bash 3.2.
  IFS= read -r -d '' _RCHK <<'PY' || true
import hashlib, os, re, sys
rec, d, dis = os.environ["RECEIPT"], os.environ["RULES_DIR"], os.environ["DISABLED"]
# Receipt rows: <rule-file> <md5> <kind>. kind (stock | toolkit | configurable) is written by
# bin/lib/install-lint-rules.sh from install-manifest.sh, which a project does not have. A row
# with no kind predates kinds and is not checked; the next sync writes it.
rows = []
for line in open(rec, encoding="utf-8", errors="replace"):
    parts = line.split()
    if len(parts) < 3 or parts[0].startswith("#"):
        continue
    rows.append((parts[0], parts[1], parts[2]))
kind = {n: k for n, _, k in rows}
# Opt-out: `<rule>  # reason: <text>` — the same rule the installer applies. No reason, or a
# stock-seeded rule (init writes a stock copy back that passes clean while inspecting nothing):
# the line is ignored, with a warning.
disabled = set()
if os.path.isfile(dis):
    for line in open(dis, encoding="utf-8", errors="replace"):
        w = line.split(None, 1)
        if not w or w[0].startswith("#"):
            continue
        rest = w[1] if len(w) > 1 else ""
        m = re.search(r"#\s*reason:\s*(\S.*)", rest)
        if kind.get(w[0]) == "stock":
            print("lint-gate: lint-rules-disabled.txt: %s is stock-seeded and cannot be disabled — ignored" % w[0], file=sys.stderr)
        elif not m:
            print("lint-gate: lint-rules-disabled.txt: %s has no '# reason: ...' — ignored" % w[0], file=sys.stderr)
        else:
            disabled.add(w[0])
HEADER = re.compile(rb"^# mxtk-lint-rule:", re.M)   # the installer's test: grep '^# mxtk-lint-rule:'
for name, want, k in rows:
    if name in disabled:
        continue
    path = os.path.join(d, name)
    if not os.path.isfile(path):
        print("%s\tgone (installed per the receipt, missing now)" % name)
        continue
    if k != "stock":
        continue  # init never seeds toolkit-only or configurable rules: an edit, the installer reports it
    data = open(path, "rb").read()
    got = hashlib.md5(data).hexdigest()
    if got == want or HEADER.search(data):
        continue  # unchanged, or header kept: a hand edit, which install-lint-rules.sh reports
    print("%s\theader gone, md5 %s != receipt %s" % (name, got[:8], want[:8]))
PY
  REVERTED="$(RECEIPT="$RECEIPT" RULES_DIR="$ROOT/.claude/lint-rules" DISABLED="$ROOT/.claude/lint-rules-disabled.txt" "$PY" -c "$_RCHK")"
  if [ -n "$REVERTED" ]; then
    TKR=""
    type find_toolkit_root >/dev/null 2>&1 && TKR="$(PROJECT_ROOT="$ROOT" find_toolkit_root 2>/dev/null || true)"
    echo "!! LINT RULES REVERTED TO STOCK (mxcli init?) — this run's delta is not attributable:"
    printf '%s\n' "$REVERTED" | while IFS="$(printf '\t')" read -r _f _why; do
      printf '   %s: %s\n' "$_f" "$_why"; done
    echo ""
    echo "   Restore the toolkit rules (rewrites .claude/.mxtk-lint-receipt), then re-run:"
    echo "     ${TKR:-<toolkit-root>}/bin/sync-project.sh $ROOT"
    echo "   If sync reports a rule LOCALLY MODIFIED instead of restoring it:"
    echo "     ${TKR:-<toolkit-root>}/bin/sync-project.sh $ROOT --upgrade-lint-rules all"
    if [ "$UPDATE" -eq 1 ]; then
      # Refused even under LINT_RULES_REVERTED_OK: the override is for looking at counts, and
      # baselining stock counts is exactly how the five-day field case went in.
      echo "lint-gate: REFUSED — --update-baseline over reverted rules would baseline stock counts." >&2
      exit 2
    elif [ "${LINT_RULES_REVERTED_OK:-}" = "1" ]; then
      echo "   LINT_RULES_REVERTED_OK=1 — linting anyway; counts below are from the files on disk."
      echo ""
    else
      echo "BLIND — lint rules reverted to stock; lint not run, nothing compared against the baseline."
      # lint-last.json gets the verdict but no total: lint did not run, and a stale total from
      # the previous run would be read as this run's by metrics-ledger.sh. No ledger row either.
      mkdir -p "$ROOT/.claude/loop" 2>/dev/null &&
        printf '{\n  "timestamp": "%s",\n  "verdict": "BLIND-RULES-REVERTED",\n  "reverted": "%s"\n}\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s\n' "$REVERTED" | cut -f1 | paste -sd, -)" \
          > "$ROOT/.claude/loop/lint-last.json" 2>/dev/null || true
      exit 1
    fi
  fi
fi

# LINT_JSON=<file> skips mxcli entirely and reads pre-captured lint output. This makes
# the comparison logic testable against fixtures with no .mpr, no mxcli and no catalog
# (a full cold run costs ~12 min on a project whose catalog needs rebuilding).
if [ -n "${LINT_JSON:-}" ]; then
  [ -f "$LINT_JSON" ] || { echo "lint-gate: LINT_JSON=$LINT_JSON not found" >&2; exit 2; }
  echo "==> using captured lint output: $LINT_JSON"
  cp "$LINT_JSON" "$OUT"
else
  echo "==> linting $MPR${EXCLUDE:+ (excluding vendor modules)}"
  # First run on a cold catalog can take MINUTES (measured: 717s on PROJECT-A, 2s warm) --
  # the catalog rebuild dominates, not the lint. Do not treat a slow first run as a hang.
  if [ -n "$EXCLUDE" ]; then
    "$MXCLI" lint -p "$MPR" -e "$EXCLUDE" --format json > "$OUT" 2>/dev/null
  else
    "$MXCLI" lint -p "$MPR" --format json > "$OUT" 2>/dev/null
  fi
fi
[ -s "$OUT" ] || { echo "lint-gate: lint produced no output" >&2; exit 2; }

if [ "$APPROVED" -eq 1 ] && [ "$UPDATE" -eq 1 ]; then
  echo "lint-gate: note — --approved-in-chat is no longer evidence (#348); a rise needs bin/baseline-approve.sh, run by the user." >&2
fi
LOCK="$(dirname "${BASH_SOURCE[0]}")/baseline-lock.sh"
[ -f "$LOCK" ] || LOCK=""
BASELINE="$BASELINE" OUT="$OUT" UPDATE="$UPDATE" REASON="$REASON" LOCK="$LOCK" ROOT="$ROOT" \
  SECURITY_FILE="$SECURITY_FILE" ACCEPT_LOG="$ACCEPT_LOG" "$PY" - <<'PY'
import json, os, sys, collections, datetime, fnmatch, hashlib, subprocess, tempfile

out_path  = os.environ["OUT"]
base_path = os.environ["BASELINE"]
update    = os.environ["UPDATE"] == "1"

# .claude/loop/ is the existing per-project state/loop-artifact convention (page-scope.json,
# sweep/, etc.) -- lint-last.json joins it. Written on every run that gets far enough to have
# counts; never on the earlier exit-2 paths (no mxcli, no .mpr, unparsable output) where there
# is nothing real to record. Best-effort: a write failure here must never turn a lint PASS/FAIL
# into a crash, so it is swallowed.
def write_last(verdict, viol_list, counts_now):
    try:
        loop_dir = os.path.join(os.path.dirname(base_path), "loop")
        os.makedirs(loop_dir, exist_ok=True)
        last_path = os.path.join(loop_dir, "lint-last.json")
        json.dump({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "verdict": verdict,
            "total": len(viol_list),
            "rule_count": len(counts_now),
            "counts": dict(sorted(counts_now.items())),
        }, open(last_path, "w"), indent=2)
        open(last_path, "a").write("\n")
    except OSError as e:
        print("lint-gate: could not write %s: %s" % (last_path, e), file=sys.stderr)
    write_ledger(verdict, viol_list, counts_now)

# LEDGER. lint-last.json is overwritten every run, so it can answer "what did lint say last
# time" and nothing else. The ledger is append-only: one row per rule per run, so a rule's
# count can be read ACROSS runs — did the thing we shipped ever fire, and did its count go
# down once people saw it. That is the question the rollout plan in process/lint-backlog.md
# asks before promoting a warning to an error ("two clean projects"), and until this file
# existed nobody could answer it without a git archaeology of lint-baseline.json.
#
#   .claude/loop/lint-ledger.tsv   ts  verdict  rule  count  severity  blind
#
# `blind` is 1 when the rule emitted a `_rule` finding that run (it inspected nothing), so a
# zero next to a 1 is never read as clean. Rules with zero findings are NOT written: a rule's
# absence on a date means "ran, found nothing" only if the run row (rule `_run`) is there —
# which it always is, carrying the total. Read it with project-bin/lint-trend.sh.
def write_ledger(verdict, viol_list, counts_now):
    try:
        loop_dir = os.path.join(os.path.dirname(base_path), "loop")
        os.makedirs(loop_dir, exist_ok=True)
        ledger = os.path.join(loop_dir, "lint-ledger.tsv")
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        blind_rules = {v["ruleId"] for v in viol_list if v.get("module") == "_rule"}
        sev_now = {v["ruleId"]: v.get("severity", "") for v in viol_list}
        new_file = not os.path.exists(ledger)
        with open(ledger, "a") as f:
            if new_file:
                f.write("ts\tverdict\trule\tcount\tseverity\tblind\n")
            f.write("%s\t%s\t_run\t%d\t\t%d\n" % (ts, verdict, len(viol_list), 1 if blind_rules else 0))
            for r in sorted(counts_now):
                f.write("%s\t%s\t%s\t%d\t%s\t%d\n" % (
                    ts, verdict, r, counts_now[r], sev_now.get(r, ""), 1 if r in blind_rules else 0))
    except OSError as e:
        print("lint-gate: could not append %s: %s" % (ledger, e), file=sys.stderr)

# mxcli prints a plaintext progress banner before the JSON; slice from the first brace.
raw = open(out_path).read()
try:
    data = json.loads(raw[raw.index("{"):])
except (ValueError, IndexError):
    print("lint-gate: could not parse lint JSON", file=sys.stderr)
    sys.exit(2)

viol = data.get("violations") or []
counts = collections.Counter(v["ruleId"] for v in viol)
sev    = {v["ruleId"]: v["severity"] for v in viol}

# A rule that did not actually run is a false PASS, not a clean result. Two forms,
# and keying on only the first was a real bug in this script:
#   1. Self-reported blindness: CONV010/CONV020 emit module="_rule" when they inspect
#      documents but activities_for() hands back nothing.
#   2. A hard Starlark crash: mxcli reports these as severity=error with an EMPTY
#      module and a "Starlark rule error:" message prefix -- NOT as "_rule". Observed
#      on PROJECT-E 2026-08-14: CONV018 died with '"page" struct has no .widgets
#      attribute'. Keying only on "_rule" meant the gate baselined a crashed rule as a
#      legitimate error-severity finding and then reported PASS while CONV018 saw
#      nothing at all. A crashed rule must never be ratcheted.
blind = [v for v in viol
         if v.get("module") == "_rule"
         or "Starlark rule error" in (v.get("message") or "")]

# Crashed rules are excluded from the ratchet counts entirely: baselining a crash
# would make the crash the expected state.
crashed = {v["ruleId"] for v in viol if "Starlark rule error" in (v.get("message") or "")}
if crashed:
    viol = [v for v in viol if v["ruleId"] not in crashed]
    counts = collections.Counter(v["ruleId"] for v in viol)

# Self-reported blindness (module "_rule") is likewise never counted: a rule that said it
# inspected nothing would otherwise be ratcheted as accepted debt (#229). It is reported as
# PASS-BLIND via `blind` above, which was computed before this filter. The filter applies to
# check runs too, not only --update-baseline: when it ran on updates alone, the blind finding
# was missing from the baseline but present in every check, so each later run reported it as
# "CONV020 0 -> 1 (+1)" — a rise — and exec.sh logged LINT ROSE for an instrument fault.
viol = [v for v in viol if v.get("module") != "_rule"]
counts = collections.Counter(v["ruleId"] for v in viol)

if update:
    # Accepting a rise is a decision; record it. See the header ("ACCEPTING DEBT ...").
    reason   = os.environ.get("REASON", "").strip()
    lock, root = os.environ.get("LOCK", ""), os.environ.get("ROOT", ".")
    def run_lock(*a):
        return subprocess.run(["bash", lock] + list(a), capture_output=True, text=True)
    sec_pats = ["SEC*", "CONV006"]
    sec_file = os.environ.get("SECURITY_FILE", "")
    if sec_file and os.path.exists(sec_file):
        sec_pats = [l.strip() for l in open(sec_file)
                    if l.strip() and not l.lstrip().startswith("#")]
    is_sec = lambda r: any(fnmatch.fnmatchcase(r, p) for p in sec_pats)
    old_base = None
    if os.path.exists(base_path):
        try:
            old_base = json.load(open(base_path)).get("counts", {})
        except ValueError:
            old_base = None
    raised = []
    if old_base is not None:
        raised = [(r, old_base.get(r, 0), c) for r, c in sorted(counts.items())
                  if c > old_base.get(r, 0)]
    sec_raised = [x for x in raised if is_sec(x[0])]
    if raised and not reason:
        print("lint-gate: REFUSED — this update raises %d rule(s): %s" % (len(raised),
              ", ".join("%s %d->%d" % x for x in raised)), file=sys.stderr)
        print("           Accepting debt needs a reason on the record:", file=sys.stderr)
        print("           bin/lint-gate.sh --update-baseline --reason \"<why each rise is acceptable>\"",
              file=sys.stderr)
        sys.exit(2)
    # The exact bytes this update would write; an approval is for these and nothing else.
    content = json.dumps({"counts": dict(sorted(counts.items())),
                          "total": len(viol),
                          "note": "Per-rule finding counts on OUR modules. Gate fails when any rises."},
                         indent=2) + "\n"
    sha = hashlib.sha256(content.encode("utf-8")).hexdigest()
    prior = run_lock("verify", root, "lint").stdout.split("\t")[0] if lock else ""
    why = []
    if raised:
        why.append("raises %s" % ", ".join("%s %d->%d" % x for x in raised))
    if prior == "GONE":
        why.append("re-creates a baseline that was deleted")
    if prior == "FAIL":
        why.append("follows a baseline that moved without approval")
    if prior == "MANUAL":
        why.append("follows a baseline with no verifiable record (predates the lock, or came in by a merge)")
    basis = "first" if old_base is None else "tighten"
    if why:
        basis = "approved"
        if not lock:
            print("lint-gate: REFUSED — this update %s and needs a person's approval, but" % "; ".join(why), file=sys.stderr)
            print("           bin/baseline-lock.sh is not installed. Run the toolkit's bin/sync-project.sh.", file=sys.stderr)
            sys.exit(2)
        if run_lock("approved", root, "lint", sha).returncode != 0:
            print("lint-gate: REFUSED — this update %s." % "; ".join(why), file=sys.stderr)
            for v in [x for x in viol if x["ruleId"] in {r for r, _, _ in sec_raised}][:10]:
                print("             %s | %s | %s" % (v["ruleId"], v.get("document") or v.get("module") or "",
                      (v.get("message") or "")[:110]), file=sys.stderr)
            summary = "lint: %s%s. Reason: %s" % ("; ".join(why),
                      " (SECURITY-TIER: %s)" % ", ".join(r for r, _, _ in sec_raised) if sec_raised else "",
                      reason or "-")
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as t:
                t.write(content)
            r = run_lock("propose", root, "lint", t.name, summary)
            os.unlink(t.name)
            sys.stderr.write(r.stderr)
            sys.exit(2)
        print("==> human approval found for this exact baseline (sha %s)" % sha[:12])
    if raised:
        log = os.environ.get("ACCEPT_LOG", "")
        try:
            new_log = not os.path.exists(log)
            with open(log, "a") as f:
                if new_log:
                    f.write("ts\ttotal_before\ttotal_after\trises\tsecurity_approved_in_chat\treason\n")
                f.write("%s\t%d\t%d\t%s\t%s\t%s\n" % (
                    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    sum(old_base.values()), len(viol),
                    " ".join("%s+%d" % (r, n - w) for r, w, n in raised),
                    "yes" if sec_raised else "-",
                    reason.replace("\t", " ").replace("\n", " ")))
            print("==> acceptance recorded in %s — commit it with the baseline" % os.path.relpath(log))
        except OSError as e:
            print("lint-gate: could not append %s: %s" % (log, e), file=sys.stderr)
            sys.exit(2)
    open(base_path, "w").write(content)
    if lock:
        run_lock("record", root, "lint", basis)
    else:
        print("lint-gate: bin/baseline-lock.sh not installed — this write is unrecorded (sync-project.sh)", file=sys.stderr)
    print("==> baseline written: %d findings across %d rules" % (len(viol), len(counts)))
    for r, c in counts.most_common():
        print("      %5d  %-8s %s" % (c, sev[r], r))
    write_last("BASELINE-UPDATED", viol, counts)
    sys.exit(0)

if not os.path.exists(base_path):
    print("lint-gate: no baseline at %s — run: bin/lint-gate.sh --update-baseline" % base_path,
          file=sys.stderr)
    write_last("ERROR-NO-BASELINE", viol, counts)
    sys.exit(2)

base = json.load(open(base_path)).get("counts", {})
rose, fell = [], []
for r in sorted(set(counts) | set(base)):
    now, was = counts.get(r, 0), base.get(r, 0)
    if now > was: rose.append((r, was, now))
    elif now < was: fell.append((r, was, now))

print("==> %d findings on our modules (baseline %d)" % (len(viol), sum(base.values())))

if blind:
    print("\n!! A RULE COULD NOT READ THE MODEL — a clean result here means nothing:")
    for v in blind:
        print("   %s: %s" % (v["ruleId"], v["message"][:160]))

if fell:
    print("\n   improved:")
    for r, was, now in fell:
        print("      %-8s %d -> %d" % (r, was, now))

# COLLAPSE GUARD. A ratchet that only watches for increases treats "lint saw nothing"
# as the best possible result. If the catalog is empty, the module filter is wrong, or
# the .star rules failed to load, every count drops to zero and the gate prints
# "PASS -- 28 rule(s) improved". Silence is not success. A drop this broad is a
# malfunction until proven otherwise; a genuine cleanup that large is deliberate and
# its author can re-baseline explicitly.
zeroed = [r for r, was, now in fell if now == 0 and was > 0]
base_total = sum(base.values())
collapsed = (len(zeroed) >= 5 and base_total > 0
             and len(viol) < base_total * 0.5)

if collapsed:
    print("\nFAIL — IMPLAUSIBLE DROP. %d rules went to zero and the total fell %d -> %d."
          % (len(zeroed), base_total, len(viol)))
    print("       This is what a broken lint run looks like, not a cleanup. Check that")
    print("       the catalog is populated, the .star rules loaded, and the module")
    print("       filter is not excluding everything, before you believe this.")
    print("       Rules zeroed: %s" % ", ".join(zeroed[:12]) + (" ..." if len(zeroed) > 12 else ""))
    print("       If the cleanup is real, re-baseline deliberately: --update-baseline")
    write_last("FAIL-COLLAPSE", viol, counts)
    sys.exit(1)

if not rose:
    print("\nPASS — nothing got worse.")
    if fell:
        print("       %d rule(s) improved. Run --update-baseline to lock the gain in." % len(fell))
    write_last("PASS-BLIND" if blind else "PASS", viol, counts)
    sys.exit(1 if blind else 0)

print("\nFAIL — %d rule(s) got worse:\n" % len(rose))
for r, was, now in rose:
    print("   %-8s %-8s %d -> %d  (+%d)" % (r, sev.get(r, "?"), was, now, now - was))
    for v in [x for x in viol if x["ruleId"] == r][:3]:
        print("        %s | %s" % (v.get("module") or "(project)", v["message"][:120]))
    print()
write_last("FAIL", viol, counts)
sys.exit(1)
PY
