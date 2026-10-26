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
#       --approved-in-chat              # ALSO required when a security-tier rule rises
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
# PROJECT-EDITED BUNDLED RULES (#524). A project that edits a rule mxcli seeds (example_microflow,
# conv001…) loses the edit at every session start: `mxcli init --sync-skills` re-seeds stock, and
# the next exec was charged with the stock counts. So --update-baseline also writes a receipt row
# `<file> <md5> project` for every seeded rule whose md5 is not a known stock version (toolkit
# lint-rules/STOCK-HASHES-BUNDLED.txt, found via MXTK_ROOT / CLAUDE.local.md). A later run where
# that md5 moved prints BLIND — reverted with `git checkout -- <file>` when HEAD still holds the
# receipted edit (an update is then refused; the checkout never is), or asks for a re-baseline when
# the rule changed some other way. No receipt list in reach, or an mxcli version the list has not
# captured = no project rows, with a note. md5s are taken with CRs stripped (Git Bash autocrlf).
#
# ACCEPTING DEBT IS RECORDED, NOT SILENT (2026-10-12). Three toolkit-built apps re-baselined
# 61 times in four days — every acceptance made by the agent whose script caused the rise,
# with no reason field and nothing that ever summed them: baselines grew 8 -> 757, 440 -> 677
# and 9 -> 187, and security warnings (CONV006, SEC003) went in in the same batches as naming
# info. So an update that RAISES any rule now needs --reason, and is appended to
# .claude/lint-acceptances.tsv (ts, total before/after, per-rule rises, security flag, reason)
# — commit it with the baseline. A first baseline (taken with the user right after the first
# scaffold step, #496) and a pure ratchet-down need no reason.
# A rise in a security-tier rule (default SEC* and CONV006; override, one id or glob per line,
# in .claude/lint-security-rules.txt) also needs --approved-in-chat: a claim on the record that
# the user was shown the findings and said yes, the same contract as gate-check --ack-protocol.
# Never set it on your own judgement.
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
# MPR_FILE (the user's, or _common.sh's pick from the cwd inside one apps/<X>/) names the model
# when MPR does not; without it exec.sh run from apps/A reached the "several apps" refusal (#489).
# Only when it resolves under $ROOT: a cwd-relative MPR_FILE (App.mpr from app/) or an absolute
# one through a symlinked path (/tmp vs /private/tmp) falls back to discovery, not to exit 2,
# which exec.sh logs as "lint could not run" and so turns lint off.
if [ -z "${MPR:-}" ] && [ -n "${MPR_FILE:-}" ]; then
  _m="${MPR_FILE#"$ROOT"/}"; [ -f "$ROOT/$_m" ] && MPR="$_m"
fi
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
  # Multi-app folder (apps/<X>/X.mpr, #420): one app is linted as it is found; several are not
  # guessed between (exit 2, naming MPR=apps/<X>/<X>.mpr), the same refusal as find_mpr.
  if [ -z "$MPR" ] && ls "$ROOT"/apps/*/*.mpr >/dev/null 2>&1; then
    if [ "$(ls "$ROOT"/apps/*/*.mpr | wc -l | tr -d ' ')" -gt 1 ]; then
      echo "lint-gate: several apps under $ROOT/apps — set MPR=apps/<X>/<X>.mpr to choose:" >&2
      ls "$ROOT"/apps/*/*.mpr | sed "s#^$ROOT/#  #" >&2
      exit 2
    fi
    MPR="$(cd "$ROOT" && ls apps/*/*.mpr | head -1)"
  fi
fi
if [ -z "$MPR" ] || [ ! -f "$ROOT/$MPR" ]; then
  echo "lint-gate: no .mpr found in $ROOT, $ROOT/app or $ROOT/apps/<X> — set MPR=<name>.mpr" >&2
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
    --approved-in-chat) APPROVED=1 ;;
    -h|--help) sed -n '2,74p' "$0"; exit 0 ;;
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
[ -n "$MXCLI" ] || { echo "lint-gate: no runnable mxcli in $ROOT (Windows: mxcli.exe) — bin/doctor.sh --install --yes <project>" >&2; exit 2; }
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
# Every stock .star `mxcli init` has seeded, per captured version (#524); tells an unedited
# bundled rule from a project edit. In the toolkit clone, never copied into a project.
STOCK_LIST="${MXTK_LINT_STOCK_LIST:-}"
if [ -z "$STOCK_LIST" ] && type find_toolkit_root >/dev/null 2>&1; then
  _tkr="$(PROJECT_ROOT="$ROOT" find_toolkit_root 2>/dev/null || true)"
  [ -n "$_tkr" ] && STOCK_LIST="$_tkr/lint-rules/STOCK-HASHES-BUNDLED.txt"
fi
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
# Kind `project` (#524): a bundled rule the project edited, receipted by --update-baseline.
# `mxcli init --sync-skills` overwrites it at session start; the md5 then moves while the
# committed edit still sits at HEAD. Two classes, third column: proj-reverted (HEAD still holds
# the receipted edit: `git checkout -- <file>` restores it) and proj-changed (the rule changed
# some other way: re-baseline if that was intended). An md5 that is a known stock hash replacing
# another known stock hash is an mxcli upgrade of an unedited rule, not an edit: skipped.
stock = set()
sl = os.environ.get("STOCK_LIST", "")
if sl and os.path.isfile(sl):
    for line in open(sl, encoding="utf-8", errors="replace"):
        w = line.split()
        if len(w) >= 2 and not w[0].startswith("#"):
            stock.add((w[0], w[1]))
def lfmd5(data):
    return hashlib.md5(data.replace(b"\r", b"")).hexdigest()   # CR-insensitive: Git Bash autocrlf
def head_md5(name):
    import subprocess
    rel = os.path.relpath(os.path.join(d, name), os.environ["ROOT"]).replace(os.sep, "/")
    try:
        r = subprocess.run(["git", "-C", os.environ["ROOT"], "show", "HEAD:./" + rel],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return ""
    return lfmd5(r.stdout) if r.returncode == 0 else ""
for name, want, k in rows:
    if name in disabled:
        continue
    path = os.path.join(d, name)
    if k == "project":
        if not os.path.isfile(path):
            print("%s\tgone (project-edited rule, receipted at the last baseline)\tproj-changed" % name)
            continue
        got = lfmd5(open(path, "rb").read())
        if got == want or ((name, got) in stock and (name, want) in stock):
            continue
        cls = "proj-reverted" if head_md5(name) == want else "proj-changed"
        print("%s\tmd5 %s != receipt %s\t%s" % (name, got[:8], want[:8], cls))
        continue
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
  ALLREV="$(RECEIPT="$RECEIPT" RULES_DIR="$ROOT/.claude/lint-rules" DISABLED="$ROOT/.claude/lint-rules-disabled.txt" \
    STOCK_LIST="$STOCK_LIST" ROOT="$ROOT" "$PY" -c "$_RCHK")"
  REVERTED="$(printf '%s\n' "$ALLREV" | grep -v "$(printf '\t')proj-" | grep . || true)"
  PROJREV="$(printf '%s\n' "$ALLREV" | grep "$(printf '\t')proj-" || true)"
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
  if [ -n "$PROJREV" ]; then
    _TAB="$(printf '\t')"
    echo "!! PROJECT-EDITED LINT RULE(S) CHANGED SINCE THE BASELINE — this run's delta is not attributable:"
    printf '%s\n' "$PROJREV" | while IFS="$_TAB" read -r _f _why _cls; do
      printf '   %s: %s\n' "$_f" "$_why"; done
    echo ""
    if printf '%s\n' "$PROJREV" | grep -q "${_TAB}proj-reverted"; then
      echo "   Overwritten on disk (mxcli init --sync-skills re-seeds stock rules at session start);"
      echo "   your edit is still committed. Restore it, then re-run:"
      printf '%s\n' "$PROJREV" | grep "${_TAB}proj-reverted" | cut -f1 | while read -r _f; do
        echo "     git checkout -- .claude/lint-rules/$_f"; done
    fi
    if printf '%s\n' "$PROJREV" | grep -q "${_TAB}proj-changed"; then
      echo "   Changed on purpose (or deleted)? Re-baseline so the receipt records the new version:"
      echo "     bin/lint-gate.sh --update-baseline --reason \"<what changed in the rule>\""
    fi
    if [ "$UPDATE" -eq 1 ]; then
      if printf '%s\n' "$PROJREV" | grep -q "${_TAB}proj-reverted"; then
        # The remedy (git checkout) is never blocked; only baselining the overwritten copy is.
        echo "lint-gate: REFUSED — --update-baseline over an overwritten rule would baseline its stock counts." >&2
        echo "           Restore it with git checkout (above). To drop your edit for good, commit the new file first." >&2
        exit 2
      fi
      echo "   --update-baseline: the receipt is rewritten for the changed rule(s) below."
      echo ""
    elif [ "${LINT_RULES_REVERTED_OK:-}" = "1" ]; then
      echo "   LINT_RULES_REVERTED_OK=1 — linting anyway; counts below are from the files on disk."
      echo ""
    else
      if printf '%s\n' "$PROJREV" | grep -q "${_TAB}proj-reverted"; then
        echo "BLIND — reverted: a project-edited lint rule was overwritten; lint not run, nothing compared against the baseline."
      else
        echo "BLIND — a lint rule changed since the baseline; lint not run, nothing compared against the baseline."
      fi
      mkdir -p "$ROOT/.claude/loop" 2>/dev/null &&
        printf '{\n  "timestamp": "%s",\n  "verdict": "BLIND-RULES-REVERTED",\n  "reverted": "%s"\n}\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s\n' "$PROJREV" | cut -f1 | paste -sd, -)" \
          > "$ROOT/.claude/loop/lint-last.json" 2>/dev/null || true
      exit 1
    fi
  fi
fi

# The mxcli version a baseline was taken with, so bin/doctor.sh can say "re-baseline" after an
# upgrade (new built-in rules raise counts on the next exec with no model change). One --version
# call, on --update-baseline only; a check run never pays for it.
MXCLI_VER=""
if [ "$UPDATE" -eq 1 ]; then
  MXCLI_VER="$("$MXCLI" --version 2>/dev/null | head -1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
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

BASELINE="$BASELINE" OUT="$OUT" UPDATE="$UPDATE" REASON="$REASON" APPROVED="$APPROVED" \
  SECURITY_FILE="$SECURITY_FILE" ACCEPT_LOG="$ACCEPT_LOG" MXCLI_VER="$MXCLI_VER" "$PY" - <<'PY'
import json, os, sys, collections, datetime, fnmatch

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
            **({"new_findings": new_by_rule} if new_by_rule else {}),
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
#   1. Self-reported blindness: CONV010/MXTK-UX003 emit module="_rule" when they inspect
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
# "CONV020 0 -> 1 (+1)" (the toolkit rule, now MXTK-UX003) — a rise — and exec.sh logged LINT ROSE for an instrument fault.
viol = [v for v in viol if v.get("module") != "_rule"]
counts = collections.Counter(v["ruleId"] for v in viol)

# FINDING IDENTITY (#239). The baseline stores per-rule counts, so on a rise the gate could only
# show three arbitrary members of the rule (first in model order = oldest documents), and agents
# read those as "my" findings. The baseline now also keeps a multiset of findings keyed by
# (rule, module, document, message); a rise lists the findings that are NOT in that multiset.
def fkey(v):
    return "|".join((v.get("ruleId") or "", v.get("module") or "", v.get("document") or "",
                     (v.get("message") or "").replace("\n", " ")))
fcounts = collections.Counter(fkey(v) for v in viol)
new_by_rule = {}  # rule -> every new-or-changed finding; the FAIL view caps it, lint-last.json keeps all

if update:
    # Accepting a rise is a decision; record it. See the header ("ACCEPTING DEBT ...").
    reason   = os.environ.get("REASON", "").strip()
    approved = os.environ.get("APPROVED") == "1"
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
    if sec_raised and not approved:
        print("lint-gate: REFUSED — security-tier rule(s) rose: %s" % ", ".join(
              "%s %d->%d" % x for x in sec_raised), file=sys.stderr)
        print("           Show the user these findings in chat. Only after they say yes, re-run with", file=sys.stderr)
        print("           --approved-in-chat (a claim on the record). Otherwise fix the grant.", file=sys.stderr)
        for v in [x for x in viol if x["ruleId"] in {r for r, _, _ in sec_raised}][:10]:
            print("             %s | %s | %s" % (v["ruleId"], v.get("document") or v.get("module") or "",
                  (v.get("message") or "")[:110]), file=sys.stderr)
        sys.exit(2)
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
    json.dump({"counts": dict(sorted(counts.items())),
               "total": len(viol),
               "findings": dict(sorted(fcounts.items())),
               "note": "Per-rule finding counts on OUR modules, plus a multiset of findings "
                       "(rule|module|document|message) so a rise can name the new ones. "
                       "Gate fails when any count rises.",
               **({"mxcli_version": os.environ["MXCLI_VER"]} if os.environ.get("MXCLI_VER") else {})},
              open(base_path, "w"), indent=2)
    open(base_path, "a").write("\n")
    print("==> baseline written: %d findings across %d rules" % (len(viol), len(counts)))
    for r, c in counts.most_common():
        print("      %5d  %-8s %s" % (c, sev[r], r))
    write_last("BASELINE-UPDATED", viol, counts)
    sys.exit(0)

if not os.path.exists(base_path):
    # The first exec of a build is usually the scaffold, and this is where it lands (#496).
    print("lint-gate: no baseline yet (%s)." % os.path.relpath(base_path), file=sys.stderr)
    print("  Take the first baseline now, after the scaffold, with the user, so later rises", file=sys.stderr)
    print("  measure the build, not the template:  bin/lint-gate.sh --update-baseline", file=sys.stderr)
    write_last("ERROR-NO-BASELINE", viol, counts)
    sys.exit(2)

_b = json.load(open(base_path))
base = _b.get("counts", {})
base_findings = _b.get("findings")  # None on a baseline written before #239
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
# Work out every rule's new findings first, so the top of the output can be a SUMMARY: one
# line per rule (rule, severity, base -> now, net rise, new findings). In one field build ~90%
# of runs rose (#496), and with the findings interleaved the rule list was lost in the detail.
# The summary lines keep the shape exec.sh parses for its BUILD-LOG row (rule sev N -> M (+K));
# the detail headers below deliberately do not, so each rule is read once.
new_lists = {}
for r, was, now in rose:
    if base_findings is None:
        continue
    # New = findings beyond what the baseline holds, per key (multiset surplus).
    left = collections.Counter(base_findings)
    new = []
    for x in (x for x in viol if x["ruleId"] == r):
        k = fkey(x)
        if left[k] > 0: left[k] -= 1
        else: new.append(x)
    new_lists[r] = new
    new_by_rule[r] = ["%s | %s | %s" % (v.get("module") or "(project)", v.get("document") or "-", v["message"][:120]) for v in new]
for r, was, now in rose:
    tail = ("  %d new" % len(new_lists[r])) if r in new_lists else ""
    print("   %-8s %-8s %d -> %d  (+%d)%s" % (r, sev.get(r, "?"), was, now, now - was, tail))
print("   detail: up to 3 new findings per rule below; all of them in .claude/loop/lint-last.json (new_findings)\n"
      if base_findings is not None else "")
for r, was, now in rose:
    print("   %s:" % r)
    if r in new_lists:
        new = new_lists[r]
        # Compact on purpose: exec.sh shows only the first 60 lines of this block.
        if len(new) != now - was:
            print("        new or changed findings (%d); net rise +%d (reworded messages, earlier swaps or un-baselined drift count here)" % (len(new), now - was))
        shown = new if len(new) <= 3 else new[:2]
        for line in new_by_rule[r][:len(shown)]:
            print("        + " + line)
        if len(new) > 3:
            print("        + ... %d more in .claude/loop/lint-last.json (new_findings)" % (len(new) - 2))
    else:
        print("        (baseline holds counts only: these 3 are the FIRST in model order, not necessarily new.")
        print("         Re-baseline once on a clean tree to enable listing the new findings.)")
        for v in [x for x in viol if x["ruleId"] == r][:3]:
            print("        %s | %s" % (v.get("module") or "(project)", v["message"][:120]))
    print()
write_last("FAIL", viol, counts)
sys.exit(1)
PY
_RC=$?

# Receipt project-edited bundled rules (#524). After a baseline is written, every
# seeded .claude/lint-rules/*.star (a name in STOCK-HASHES-BUNDLED) that has no receipt row and is
# not a known stock version (md5 with CRs stripped) gets a row; only when the running mxcli is a
# captured version there
# `<file> <md5> project`, so the check above can tell an overwrite from a rise next time. Toolkit
# rows are the installer's and are left untouched; it keeps `project` rows on sync. No mxcli call.
if [ "$UPDATE" -eq 1 ] && [ "$_RC" -eq 0 ] && [ -d "$ROOT/.claude/lint-rules" ]; then
  if [ -z "$STOCK_LIST" ] || [ ! -f "$STOCK_LIST" ]; then
    echo "note: edited bundled lint rules not receipted — no STOCK-HASHES-BUNDLED.txt (set MXTK_ROOT to the toolkit clone)" >&2
  else
    IFS= read -r -d '' _RWR <<'PY' || true
import hashlib, os, sys
rec, d, sl = os.environ["RECEIPT"], os.environ["RULES_DIR"], os.environ["STOCK_LIST"]
stock, seeded, versions = set(), set(), set()
for line in open(sl, encoding="utf-8", errors="replace"):
    w = line.split()
    if len(w) >= 2 and not w[0].startswith("#"):
        stock.add((w[0], w[1])); seeded.add(w[0])
        if len(w) >= 3:
            versions.add(w[2].lstrip("v"))
# Only on a captured mxcli version: on any other, that version's unedited stock rules would look
# edited, and the next upgrade would read them as "reverted" and name the wrong remedy.
ver = os.environ.get("MXCLI_VER", "").lstrip("v")
if ver not in versions:
    print("note: edited bundled lint rules not receipted — mxcli %s is not a captured version in "
          "STOCK-HASHES-BUNDLED.txt (captured: %s)" % (ver or "(version unreadable)", ", ".join(sorted(versions))),
          file=sys.stderr)
    raise SystemExit(0)
keep, owned = [], set()
if os.path.isfile(rec):
    for line in open(rec, encoding="utf-8", errors="replace"):
        w = line.split()
        if not w or w[0].startswith("#"):
            continue
        if len(w) >= 3 and w[2] == "project":
            continue  # rewritten below from the files on disk
        keep.append(line.rstrip("\n"))
        owned.add(w[0])
proj = []
for name in sorted(os.listdir(d)):
    if not name.endswith(".star") or name in owned or name not in seeded:
        continue  # a project's own rule is never overwritten by mxcli: nothing to receipt
    md5 = hashlib.md5(open(os.path.join(d, name), "rb").read().replace(b"\r", b"")).hexdigest()
    if (name, md5) not in stock:
        proj.append("%s  %s  project" % (name, md5))
if not keep and not proj and not os.path.isfile(rec):
    raise SystemExit(0)
tmp = rec + ".tmp"
with open(tmp, "w", encoding="utf-8", newline="\n") as f:
    f.write("# md5 of each toolkit lint rule AS INSTALLED, and its kind. Written by bin/lib/install-lint-rules.sh.\n")
    f.write("# Do not edit. Deleting this file makes a revert-to-stock look like a first install.\n")
    for l in keep + proj:
        f.write(l + "\n")
os.replace(tmp, rec)
for l in proj:
    print("==> receipted project-edited lint rule: %s" % l.split()[0])
PY
    RECEIPT="$RECEIPT" RULES_DIR="$ROOT/.claude/lint-rules" STOCK_LIST="$STOCK_LIST" MXCLI_VER="$MXCLI_VER" "$PY" -c "$_RWR" ||
      echo "lint-gate: could not write project rows into $RECEIPT" >&2
  fi
fi
exit "$_RC"
