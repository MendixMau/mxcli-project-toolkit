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
# A script names its rows in its file name (16-…mdl, or 16-19-…mdl for 16 to 19) or in a header
# line `-- rows: 16,17,18,19`, which wins.
#
# check refuses (exit 1) when the script
#   - covers part of a low group and leaves other rows of it unbuilt (built = State not "not built",
#     or a BUILD-LOG "applied" row for a script with that row number), or
#   - mixes a high row with any other row, or
#   - starts past the last row of a module that has no docs/progress/module-close/<Module>.md
#     (module = first word of a "### Phase N — <Module> …" heading that names a folder in
#     architecture/modules/). Run bin/module-close.sh <Module> first.
# Override, with a reason that lands in the BUILD-LOG row: MXTK_ROWS_OVERRIDE="<why>".
# exit 0 pass, 1 refused, 3 nothing to check (no plan, or the script names no row).
#
# WHY (run 2, 2026-10-26, arm C). 147 build-plan rows ran as ~137 scripts and ~185 execs; each exec
# paid check, snapshot, baseline mxbuild, apply, mxbuild gate (~2 min of instruments). A prompt rule
# reaches only agents that read the prompt; this gate reaches everyone who applies through exec.sh.
set -u
mode=${1:-plan}; script=${2:-}
root=$(cd "$(dirname "$0")/.." && pwd)
plan="$root/architecture/build-plan.md"; log="$root/docs/BUILD-LOG.md"
[ -f "$plan" ] || { echo "row-groups: no architecture/build-plan.md — nothing to check"; exit 3; }
[ "$mode" = check ] && { [ -n "$script" ] || { echo "usage: bin/row-groups.sh check <script.mdl>" >&2; exit 2; }; }

exec python3 - "$mode" "$plan" "$log" "$script" "${MXTK_GROUP_MAX:-4}" <<'PY'
import os, re, sys
mode, plan, log, script, gmax = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
HIGH_SKILL = re.compile(r"security|agents?\b|mendix-agents|workflow|rest-|java|constants-and-secrets", re.I)
HIGH_STEP = re.compile(r"\broles?\b|security|marketplace|\bjava\b|\brest\b|\bapi\b|extensions?\b|changes\b", re.I)

root = os.path.dirname(os.path.dirname(plan))
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

built = {n for n, k, s, h, st in rows if st and st.lower() != "not built"}
if os.path.exists(log):
    for line in open(log, encoding="utf-8"):
        if "applied" not in line: continue
        for name in re.findall(r"`([^`]+\.mdl)`", line):
            m = re.match(r"(\d+)(?:-(\d+)(?=-))?-", os.path.basename(name))
            if m:
                a, b = int(m.group(1)), int(m.group(2) or m.group(1))
                built.update(range(a, b + 1) if b >= a and b - a < 20 else [a])

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
if mine is None:
    m = re.match(r"(\d+)(?:-(\d+)(?=-))?-", os.path.basename(script))
    if not m: print("row-groups: script names no row — not checked"); sys.exit(3)
    a, b = int(m.group(1)), int(m.group(2) or m.group(1))
    mine = set(range(a, b + 1)) if b >= a else {a}
mine &= {n for n, k, *_ in rows if k == "BUILD"}
if not mine: print("row-groups: script names no BUILD row — not checked"); sys.exit(3)

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
start = min(mine)
owed = [m for m, last in sorted(last_row.items(), key=lambda kv: kv[1])
        if last < start and not os.path.exists(os.path.join(root, "docs", "progress", "module-close", m + ".md"))]
if owed:
    problems.append(f"module close owed for {', '.join(owed)} (all its rows are before row {start}). "
                    f"Run bin/module-close.sh {owed[0]} and act on its report first")
if problems:
    print("row-groups: " + "\n  ".join(problems)); sys.exit(1)
print(f"row-groups: rows {sorted(mine)} OK"); sys.exit(0)
PY
