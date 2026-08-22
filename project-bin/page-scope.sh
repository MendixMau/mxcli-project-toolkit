#!/usr/bin/env bash
# page-scope.sh — write the page denominator: .claude/loop/page-scope.json
#
# The scope file is what turns "everything we walked was fine" into a measurable claim —
# design-audit.js, page-audit.js and report-normalize.js all read it as THE list of pages a
# clean run must account for. Until this script existed those consumers were shipped with no
# producer anywhere (process/improvement-plan-e2e-reporting.md Finding 15 / P8), so the LOOK
# rung degraded to --static-only in every project, by construction.
#
# FACTS ONLY, NO VERDICTS. This script records what pages the model contains and which module
# roles are granted to reach each one. Whether that scope is right — which orphans are
# intentional, whether a role SHOULD see a page — is judgement, and judgement lives in skills
# (skills-over-scripts.md). Consumers grade; this file only counts.
#
# READ-ONLY. Runs only `SHOW ...` and `describe ...`; never exec, never MDL, never writes the
# .mpr. The one file it writes is the scope JSON itself.
#
# What it derives, and from where:
#   inScope   every page in the scanned modules, as Module.Page
#               ./mxcli -p <mpr> -c "SHOW PAGES IN <Module>"     (per module)
#   modules   the caller's arguments; with none given, first-party modules from
#               ./mxcli -p <mpr> -c "SHOW MODULES"               (Source column empty,
#               minus System/Administration/Atlas* — harness-architecture.md §7)
#   roles     role -> page sets, from each page's own `grant view on page ... to ...;`
#               ./mxcli -p <mpr> describe --format elk page <QN> (mdlSource grants —
#               the same statements page-audit-rules.js security/grant-view parses)
#   orphans   NOT derived — classification is judgement. Entries already present in an
#             existing page-scope.json are carried forward verbatim, never dropped.
#
# The .mpr is resolved by _common.sh: $PROJECT_ROOT/$MPR_FILE win, else the directory this
# script was installed under, else walk up from $PWD to the directory holding the .mpr. The
# .mpr does NOT have to sit at the repo root (it may live under app/) — run from anywhere
# inside the project, or set PROJECT_ROOT / MPR_FILE. Never assume the checkout root.
#
# Absence is never a pass: no mxcli, no .mpr, an unparseable SHOW MODULES, or zero pages
# overall is a FAULT (exit 2) that names what was missing — and the script then refuses to
# write, so a run that measured nothing cannot clobber a scope a previous run measured.
#
# Usage:
#   bin/page-scope.sh [<Module> ...] [--no-roles]
#     <Module> ...   scan only these modules (skips the SHOW MODULES derivation)
#     --no-roles     skip the per-page describes; roles is then [] and the file says so
# Env: PROJECT_ROOT MPR_FILE MXCLI_BIN PYTHON
#
# Exit: 0 scope written · 2 fault (could not measure — nothing written)

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || exit 2

MODULES=""
NO_ROLES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-roles) NO_ROLES=1; shift ;;
    -h|--help)  sed -n '2,46p' "$0"; exit 0 ;;
    --*) echo "unknown argument: $1" >&2; exit 2 ;;
    *)   MODULES="$MODULES $1"; shift ;;
  esac
done

MPR="$(find_mpr)" || exit 2
MXCLI="${MXCLI_BIN:-./mxcli}"
[ -x "$MXCLI" ] || { echo "FAULT: $MXCLI not found or not executable — the scope cannot be read from the model, and guessing it would be worse than not writing it" >&2; exit 2; }

# JSON assembly and table parsing are done in Python; require_py (exit 2 with a fix per OS)
# rather than bare python3, for the Store-stub reason documented in _common.sh.
require_py

OUT=".claude/loop/page-scope.json"
mkdir -p .claude/loop

MXCLI="$MXCLI" MPR="$MPR" OUT="$OUT" MODULES="$MODULES" NO_ROLES="$NO_ROLES" \
"$PY" - <<'PY'
import json, os, re, subprocess, sys, datetime

MXCLI    = os.environ["MXCLI"]
MPR      = os.environ["MPR"]
OUT      = os.environ["OUT"]
MODULES  = os.environ["MODULES"].split()
NO_ROLES = os.environ["NO_ROLES"] == "1"

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
QNAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$")
# Column labels that are table furniture, never a page or module name.
HEADER_WORDS = {"name", "page", "pages", "module", "modules", "type", "source", "title",
                "layout", "url", "documents", "count"}

def mx(*args, timeout=120):
    """Run one read-only mxcli command. Returns (stdout, error) — error is None on success."""
    try:
        p = subprocess.run([MXCLI, "-p", MPR] + list(args),
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"timed out after {timeout}s"
    if p.returncode != 0:
        tail = (p.stderr.strip() or p.stdout.strip() or "mxcli failed").splitlines()[-1]
        return None, tail[:300]
    return p.stdout, None

def fault(msg):
    print(f"FAULT: {msg}", file=sys.stderr)
    print(f"       Nothing was written to {OUT} — a run that measured nothing must not",
          file=sys.stderr)
    print("       overwrite facts a previous run measured.", file=sys.stderr)
    sys.exit(2)

RULE = re.compile(r"^[\s|+\-─━═┌┐└┘├┤┬┴┼╔╗╚╝╠╣╦╩╬=]*$")

def data_lines(text):
    """Table lines with content: box-drawing verticals normalised to '|', rules dropped."""
    out = []
    for line in text.splitlines():
        t = line.replace("│", "|").replace("┃", "|").replace("║", "|").rstrip()
        if not t or RULE.match(t):
            continue
        out.append(t)
    return out

# ── modules: the caller's list, or SHOW MODULES with an empty Source column ─────────────────
# The Source-column rule is harness-architecture.md §7 verbatim: first-party = no Source,
# minus the Mendix-shipped set (System, Administration, Atlas/theme modules). Column values
# are read by HEADER OFFSET, not by splitting on whitespace — an empty Source cell vanishes
# under a split and silently shifts every column after it.
def first_party_modules():
    raw, err = mx("-c", "SHOW MODULES")
    if err:
        fault(f'`{MXCLI} -p {MPR} -c "SHOW MODULES"` failed: {err}')
    lines = data_lines(raw)
    header, hi = None, None
    for i, l in enumerate(lines):
        if re.search(r"\b(Name|Module)\b", l) and re.search(r"\bSource\b", l):
            header, hi = l, i
            break
    if header is None:
        fault("could not locate the Name and Source columns in SHOW MODULES output — "
              "pass the first-party module names as arguments instead: "
              "bin/page-scope.sh <Module> [<Module> ...]")
    m_name = re.search(r"\b(Name|Module)\b", header)
    m_src  = re.search(r"\bSource\b", header)
    # Slice each row at the header words' character offsets (fixed-width and pipe tables both).
    cols = sorted([m_name.start(), m_src.start()] +
                  [m.start() for m in re.finditer(r"\|", header)])
    def cell(line, start):
        ends = [c for c in cols if c > start] + [len(line)]
        return line[start:ends[0]].strip(" |") if len(line) > start else ""
    mods = []
    for l in lines[hi + 1:]:
        name = cell(l, m_name.start())
        src  = cell(l, m_src.start())
        if not IDENT.match(name) or name.lower() in HEADER_WORDS:
            continue
        if src:
            continue                          # marketplace/import — carries a source
        if name in ("System", "Administration") or name.startswith("Atlas"):
            continue                          # Mendix-shipped
        mods.append(name)
    return mods

module_source = "arguments"
if not MODULES:
    MODULES = first_party_modules()
    module_source = ("SHOW MODULES — rows with an empty Source column, minus "
                     "System/Administration/Atlas* (harness-architecture.md §7)")
if not MODULES:
    fault("SHOW MODULES yielded no first-party module — every row carries a Source or is "
          "Mendix-shipped. Name the modules to scan as arguments if this model has any.")

# ── pages per module ─────────────────────────────────────────────────────────────────────────
# The page name is the first identifier-shaped cell on each data row (pure-digit index cells
# and known column labels are skipped). A row that yields nothing identifier-shaped is table
# furniture and is dropped — dropped rows are counted in provenance so a parse that ate real
# rows is visible, not silent.
per_module = {}
in_scope = set()
dropped_rows = 0
for mod in MODULES:
    raw, err = mx("-c", f"SHOW PAGES IN {mod}")
    if err:
        fault(f'`{MXCLI} -p {MPR} -c "SHOW PAGES IN {mod}"` failed: {err}')
    pages = set()
    for l in data_lines(raw):
        cand = None
        for tok in re.split(r"\||\s{2,}", l):
            tok = tok.strip()
            if not tok or tok.isdigit():
                continue
            if QNAME.match(tok):
                cand = tok
                break
            if IDENT.match(tok) and tok.lower() not in HEADER_WORDS:
                cand = f"{mod}.{tok}"
                break
        if cand is None:
            dropped_rows += 1
            continue
        pages.add(cand)
    per_module[mod] = sorted(pages)
    in_scope.update(pages)

if not in_scope:
    fault(f"zero pages parsed across {len(MODULES)} module(s) ({', '.join(MODULES)}). "
          "Either these modules genuinely have no pages, or the SHOW PAGES output shape "
          "was not recognised — read one raw output with "
          f'`{MXCLI} -p {MPR} -c "SHOW PAGES IN {MODULES[0]}"` and compare.')

# ── roles: who is granted to reach each page ────────────────────────────────────────────────
# Read from each page's own mdlSource via `describe --format elk page` — the same
# `grant view on page <QN> to <Role>, ...;` statements page-audit-rules.js (security/
# grant-view) parses, so the two tools cannot disagree about what a grant looks like. A page
# whose describe fails is recorded in provenance.describeFailed and stays in inScope — the
# page exists; only its grants are unread.
GRANT = re.compile(r"grant view on page\s+([\w.]+)\s+to\s+([^;]+);", re.I)
roles_map = {}
describe_failed = []
if not NO_ROLES:
    for qn in sorted(in_scope):
        raw, err = mx("describe", "--format", "elk", "page", qn)
        if err:
            describe_failed.append({"page": qn, "error": err})
            continue
        try:
            mdl = json.loads(raw).get("mdlSource") or ""
        except json.JSONDecodeError:
            describe_failed.append({"page": qn, "error": "describe returned non-JSON"})
            continue
        for m in GRANT.finditer(mdl):
            target = m.group(1) if "." in m.group(1) else qn
            for role in (r.strip() for r in m.group(2).split(",")):
                if role:
                    roles_map.setdefault(role, set()).add(target)
    if in_scope and len(describe_failed) == len(in_scope):
        fault(f"roles requested but describe failed on all {len(in_scope)} page(s) "
              f"(first: {describe_failed[0]['page']}: {describe_failed[0]['error']}). "
              "An all-empty roles list would be a false fact. Fix the describes, or "
              "re-run with --no-roles to record that roles were deliberately not derived.")

roles = [{"role": r,
          "pages": sorted(p & in_scope),
          "inScopePages": len(p & in_scope)}
         for r, p in sorted(roles_map.items())]
# Distinct page SETS across roles, the empty set included — computed exactly the way
# report-normalize.js collectPageScope() recomputes it, so its cross-check cannot fire on
# arithmetic this file did differently.
distinct_sets = len({tuple(r["pages"]) for r in roles})

# ── orphans: carried forward, never derived ─────────────────────────────────────────────────
# Classifying an out-of-scope page ("runtime-only entry, opened by microflow X") is a
# judgement someone records by hand or via a skill. Regenerating the scope must not eat it.
orphans = []
try:
    with open(OUT, encoding="utf-8") as f:
        prev = json.load(f)
    if isinstance(prev.get("orphans"), list):
        orphans = prev["orphans"]
except (OSError, json.JSONDecodeError):
    pass

doc = {
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                     .strftime("%Y-%m-%dT%H:%M:%SZ"),
    "inScope": sorted(in_scope),
    "orphans": orphans,
    "roles": roles,
    "counts": {
        "pagesTotal": len(in_scope),
        "modules": len(MODULES),
        "perModule": {m: len(p) for m, p in sorted(per_module.items())},
    },
    "provenance": {
        "generator": "bin/page-scope.sh",
        "moduleSource": module_source,
        "modulesScanned": sorted(MODULES),
        "commands": {
            "pages": f'{MXCLI} -p {MPR} -c "SHOW PAGES IN <Module>"',
            "roles": (None if NO_ROLES
                      else f"{MXCLI} -p {MPR} describe --format elk page <QN> — "
                           "`grant view on page ... to ...;` in mdlSource"),
        },
        "rolesDerived": not NO_ROLES,
        "describeFailed": describe_failed,
        "droppedTableRows": dropped_rows,
    },
}
if not NO_ROLES:
    doc["distinctRolePageSets"] = distinct_sets

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")

print(f"page-scope → {OUT}")
print(f"  modules  {len(MODULES)}  ({module_source.split(' — ')[0]})")
print(f"  inScope  {len(in_scope)} page(s)  " +
      " ".join(f"{m}={len(p)}" for m, p in sorted(per_module.items())))
if NO_ROLES:
    print("  roles    NOT DERIVED (--no-roles) — recorded as such in the file")
else:
    print(f"  roles    {len(roles)} role(s) → {distinct_sets} distinct page set(s)"
          + (f"  ({len(describe_failed)} page describe(s) FAILED — see provenance)"
             if describe_failed else ""))
if orphans:
    print(f"  orphans  {len(orphans)} carried forward from the previous scope")
PY
