#!/usr/bin/env bash
# row-groups.sh — which build-plan rows go in ONE script, and the exec.sh gate that holds to it.
#
#   bin/row-groups.sh                 print the groups (plan the next script from this)
#   bin/row-groups.sh check <script>  the gate exec.sh runs before anything is locked or written
#
# Reads architecture/build-plan.md live (no group file to go stale). A BUILD row is
#   high  when its Skills column names security, agents, workflow, REST, Java or constants/secrets,
#         or its Step names roles, security, Marketplace, Java, REST/API, or extensions/changes to
#         built documents (the diff-before-apply cases). One row per script.
#   low   otherwise: domain, CRUD microflows, pages. Consecutive low rows form a group (at most
#         $MXTK_GROUP_MAX, default 4); any BRIEF/PROVE/LOOK row or high row ends the group.
# A script names its rows in a header line `-- rows: 16,17,18,19`. Its file name (16-…mdl, or
# 16-19-…mdl for 16 to 19) counts only when PROJECT.md says `Row groups: on`: brd-to-build-plan.md
# numbers scripts on their own sequence (`060-crm-page-….mdl` under row 21, `01-{module}-domain.mdl`
# per module), so on a project that has not opted in a file-name number is a script number, and a
# script with no header is not checked (exit 3). Real case: on the SampleDashboards plan
# (tests/wave2/fixtures/build-plan-claims-real.md) `16-cutover.mdl` is row 26, and reading it as
# row 16 refused it for leaving rows 14 and 15 unbuilt.
#
# check refuses (exit 1) when the script
#   - covers part of a low group and leaves other rows of it unbuilt (built = a State that starts
#     built / done / complete / verified / proven / passed / applied, the same prefixes
#     progress-report.py's classify_state counts; planned, partial, **blocked**, empty are not.
#     Or a BUILD-LOG "applied" row for a script whose `-- rows:` header names the row, or, with
#     `Row groups: on`, whose file name does), or
#   - mixes a high row with any other row, or
#   - starts past the last row of a module whose docs/progress/module-close/<Module>.md is missing
#     or does not show the close was done (module = first word of a "### Phase N — <Module> …"
#     heading that names a folder in architecture/modules/). Done = the summary line
#     bin/module-close.sh writes says `lint=0`, or the report's "Page | Role" LOOK table has at
#     least one filled row. A report with findings and an empty table is a run, not a close.
#     The remedy is never blocked: run bin/module-close.sh <Module>, fix and re-run, or fill the table.
# Override, with a reason that lands in the BUILD-LOG row: MXTK_ROWS_OVERRIDE="<why>".
# exit 0 pass, 1 refused, 3 nothing to check (no plan, no rows header and no opt-in, or no BUILD row).
# exit 4: `Row groups: on` but the script names no BUILD row; exec.sh prints the hint, never refuses.
#
# WHY (run 2, 2026-10-26, arm C). 147 build-plan rows ran as ~137 scripts and ~185 execs; each exec
# paid check, snapshot, baseline mxbuild, apply, mxbuild gate (~2 min of instruments). A prompt rule
# reaches only agents that read the prompt; this gate reaches everyone who applies through exec.sh.
set -u
mode=${1:-plan}; script=${2:-}
_rgd="${0%/*}"; [ "$_rgd" != "$0" ] || _rgd=.   # dirname without a process
root=$(cd "$_rgd/.." && pwd)
plan="$root/architecture/build-plan.md"; log="$root/docs/BUILD-LOG.md"
[ -f "$plan" ] || { echo "row-groups: no architecture/build-plan.md — nothing to check"; exit 3; }
[ "$mode" = check ] && { [ -n "$script" ] || { echo "usage: bin/row-groups.sh check <script.mdl>" >&2; exit 2; }; }

# Python via _common.sh's resolve_py (runs each candidate; a name on PATH is not an interpreter).
# No Python: exit 3, the same "nothing to check" exec.sh already passes through.
. "$_rgd/_common.sh" 2>/dev/null || true
PY=$(resolve_py 2>/dev/null) || { echo "row-groups: no Python 3 found (set PYTHON=/path/to/python3) — not checked" >&2; exit 3; }  # portability-ok: names in a diagnostic
exec "$PY" - "$mode" "$plan" "$log" "$script" "${MXTK_GROUP_MAX:-4}" <<'PY'
import os, re, sys
mode, plan, log, script, gmax = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
HIGH_SKILL = re.compile(r"security|agents?\b|mendix-agents|workflow|rest-|java|constants-and-secrets", re.I)
HIGH_STEP = re.compile(r"\broles?\b|security|marketplace|\bjava\b|\brest\b|\bapi\b|extensions?\b|changes\b", re.I)

root = os.path.dirname(os.path.dirname(plan))
# PROJECT.md `Row groups: on` = this project's script file names carry build-plan row numbers.
optin = False
try:
    for line in open(os.path.join(root, "PROJECT.md"), encoding="utf-8"):
        m = re.match(r"^[*_ -]*Row groups:[*_ ]*`?([A-Za-z]+)", line)
        if m: optin = m.group(1).lower() in ("on", "yes", "true"); break
except OSError:
    pass
mods = {d for d in os.listdir(os.path.join(root, "architecture", "modules"))
        if os.path.isdir(os.path.join(root, "architecture", "modules", d))} if os.path.isdir(os.path.join(root, "architecture", "modules")) else set()
rows = []  # (n, kind, step, high, state)
last_row = {}  # module -> last plan row of its phases
cur_mod = None
for line in open(plan, encoding="utf-8"):
    h = re.match(r"#{2,4}\s*Phase\s+\d+\s*[—-]\s*(\w+)", line)
    if h: cur_mod = h.group(1) if h.group(1) in mods else None; continue
    if line.startswith("## "): cur_mod = None
    c = [x.strip() for x in line.strip().strip("|").split("|")]
    # A plan may format the number and Kind cells as code or bold (`BUILD`, **12**); read through it.
    # WHY (speed experiment 2026-10-28): a plan with `BUILD` in backticks read 0 BUILD rows, so with
    # `Row groups: on` grouping silently did nothing until the agent edited the plan by hand.
    if len(c) >= 7:
        c[0], c[1] = c[0].strip("`*_ "), c[1].strip("`*_ ")
    if len(c) >= 7 and c[0].isdigit() and c[1].isupper():
        n, kind, step, skills, state = int(c[0]), c[1], c[2], c[5], c[6]
        rows.append((n, kind, step, kind == "BUILD" and bool(HIGH_SKILL.search(skills) or HIGH_STEP.search(step)), state))
        if cur_mod: last_row[cur_mod] = n

groups, cur = [], []   # groups: list of (risk, [row numbers])
for n, kind, step, high, state in rows:
    if kind != "BUILD" or high or len(cur) == gmax:
        if cur: groups.append(("low", cur)); cur = []
    if kind == "BUILD":
        if high: groups.append(("high", [n]))
        else: cur.append(n)
if cur: groups.append(("low", cur))
info = {r[0]: r for r in rows}

def is_built(st):
    l = (st or "").strip().lower().replace("**", "")
    if l.startswith(("not built", "not done", "not started")): return False
    return l.startswith(("built", "done", "complete", "verified", "proven", "passed", "applied"))

def header_rows(path):
    try:
        for line in open(path, encoding="utf-8"):
            m = re.match(r"\s*--\s*rows?\s*:\s*([\d,\s–-]+)", line, re.I)
            if m:
                got = set()
                for part in re.split(r"[,\s]+", m.group(1).strip()):
                    if not part: continue
                    a, _, b = part.replace("–", "-").partition("-")
                    got.update(range(int(a), int(b or a) + 1))
                return got
    except (OSError, ValueError):
        pass
    return None

def name_rows(name):
    m = re.match(r"(\d+)(?:-(\d+)(?=-))?-", os.path.basename(name))
    if not m: return set()
    a, b = int(m.group(1)), int(m.group(2) or m.group(1))
    return set(range(a, b + 1)) if b >= a and b - a < 20 else {a}

built = {n for n, k, s, h, st in rows if is_built(st)}
if os.path.exists(log):
    scripts = {}  # basename -> path, done- prefix stripped (exec.sh's hint renames applied scripts)
    for d, _, fs in os.walk(os.path.join(root, "mdlsource")):
        for f in fs:
            if f.endswith(".mdl"): scripts.setdefault(f[5:] if f.startswith("done-") else f, os.path.join(d, f))
    for line in open(log, encoding="utf-8"):
        if "applied" not in line: continue
        for name in re.findall(r"`([^`]+\.mdl)`", line):
            b = os.path.basename(name); b = b[5:] if b.startswith("done-") else b
            got = header_rows(scripts[b]) if b in scripts else None
            if got is None and optin: got = name_rows(b)
            built.update(got or ())

if mode != "check":
    print("| Group | Rows | Risk | Steps |\n|---|---|---|---|")
    for i, (risk, ns) in enumerate(groups, 1):
        span = f"{ns[0]}–{ns[-1]}" if len(ns) > 1 else str(ns[0])
        todo = "" if any(n not in built for n in ns) else " (built)"
        print(f"| G{i} | {span}{todo} | {risk} | {'; '.join(info[n][2] for n in ns)} |")
    one = sum(1 for r, ns in groups if len(ns) == 1)
    print(f"\n{len(groups)} scripts for {sum(len(ns) for _, ns in groups)} BUILD rows ({one} single-row).")
    sys.exit(0)

# check
mine = None
try:
    for line in open(script, encoding="utf-8"):
        m = re.match(r"\s*--\s*rows?\s*:\s*([\d,\s–-]+)", line, re.I)
        if m:
            mine = set()
            for part in re.split(r"[,\s]+", m.group(1).strip()):
                if not part: continue
                a, _, b = part.replace("–", "-").partition("-")
                mine.update(range(int(a), int(b or a) + 1))
            break
except OSError:
    pass
if mine is None and not optin:
    print("row-groups: script has no `-- rows:` header and PROJECT.md does not say `Row groups: on` — not checked")
    sys.exit(3)
# Opted in, but the script names no BUILD row of the plan: exit 4, a reminder exec.sh prints and
# lets through. WHY (A/B 2026-10-27, purchase-requests app): with `Row groups: on` every script was
# numbered on its own sequence (052-…, 076-…) and none carried a header, so all 31 read "not
# checked" and the run never grouped a row; exit 3 said nothing anyone saw.
OPTIN_HINT = ("row-groups: `Row groups: on`, but this script names no build-plan BUILD row, so it was not "
              "checked or grouped. Start the script with `-- rows: N` (or `-- rows: N,M,…` for a group); "
              "bin/row-groups.sh lists the groups.")
if mine is None:
    m = re.match(r"(\d+)(?:-(\d+)(?=-))?-", os.path.basename(script))
    if not m: print(OPTIN_HINT); sys.exit(4)
    a, b = int(m.group(1)), int(m.group(2) or m.group(1))
    mine = set(range(a, b + 1)) if b >= a else {a}
mine &= {n for n, k, *_ in rows if k == "BUILD"}
if not mine:
    if optin: print(OPTIN_HINT); sys.exit(4)
    print("row-groups: script names no BUILD row — not checked"); sys.exit(3)

problems = []
for risk, ns in groups:
    hit = mine & set(ns)
    if not hit: continue
    if risk == "high" and len(mine) > 1:
        problems.append(f"row {ns[0]} ({info[ns[0]][2]}) is high-risk: one row per script, here it shares with {sorted(mine - set(ns))}")
    if risk == "low":
        left = [n for n in ns if n not in mine and n not in built]
        if left:
            problems.append(f"rows {ns[0]}–{ns[-1]} are one low-risk group; this script leaves {left} unbuilt "
                            f"({'; '.join(info[n][2] for n in left)}). Put them in this script")
# WHY (run 2, arm D): module close was a prompt rule; D closed Audit and StyleGallery but went into
# slice 2 without closing Procurement. A prompt reaches who reads it; this gate reaches every exec.
# WHY content, not presence (PR #581 review): module-close.sh writes the report even when it finds
# lint findings, and its LOOK table starts empty, so a gate on the file alone passed a module
# whose pages nobody opened (run 3 arm D: 0 of 44 pages seen).
def close_state(m):
    p = os.path.join(root, "docs", "progress", "module-close", m + ".md")
    if not os.path.exists(p): return "missing"
    txt = open(p, encoding="utf-8").read()
    s = re.search(r"mxtk-module-close:\s*lint=(\d+)", txt)
    if s and int(s.group(1)) == 0: return "done"
    in_table = False
    for line in txt.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.lstrip().startswith("|") and cells[:2] == ["Page", "Role"]: in_table = True; continue
        if in_table:
            if not line.lstrip().startswith("|"): break
            if all(set(c) <= set("-: ") for c in cells): continue
            if cells and cells[0]: return "done"
    return f"open ({'lint=' + s.group(1) if s else 'no summary line'}, LOOK table empty)"
start = min(mine)
owed = [(m, close_state(m)) for m, last in sorted(last_row.items(), key=lambda kv: kv[1]) if last < start]
owed = [(m, st) for m, st in owed if st != "done"]
if owed:
    problems.append(f"module close owed for {', '.join(m + ' (' + st + ')' for m, st in owed)} (all its rows are before row {start}). "
                    f"Run bin/module-close.sh {owed[0][0]}, fix its findings and re-run, or record the pages you looked at "
                    f"in the report's Page | Role table")
if problems:
    print("row-groups: " + "\n  ".join(problems)); sys.exit(1)
print(f"row-groups: rows {sorted(mine)} OK"); sys.exit(0)
PY
