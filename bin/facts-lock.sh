#!/bin/bash
# facts-lock.sh — freeze the identifiers every BRD must agree on, and fail the ones that drift.
#
# WHY THIS EXISTS. BRD generation fans out: one agent per module, each re-deriving the same
# identifiers from the same corpus. They disagree, and the disagreement surfaces as an OPEN
# QUESTION — the worst possible place for it, because it lands in front of the user as if it
# were a business decision when it is a transcription defect.
#
# Measured on PROJECT-C, from the 127-question backlog:
#   OQ-6   `QueryAISafeWIPSummary` vs `QueryAiSafeWipSummary` — same operation, two BRDs.
#   OQ-8   50 vs 46 action buttons across three sheets.
#   OQ-F011-08  104 vs 94 placeholder operations.
#   OQ-F011-09  "7 pages, or 10?"
# None of those are questions for a human. They are what happens when N agents each hold
# their own copy of a fact.
#
# THE MODEL. One pass harvests every identifier from every BRD and clusters them
# case-insensitively. A cluster with one spelling is a fact: it gets frozen as canonical. A
# cluster with several is a CONFLICT: nothing is frozen, because picking a winner silently is
# exactly the failure this file exists to stop. Once frozen, the lock wins — `check` fails any
# BRD that spells a frozen fact differently, and says which spelling to use.
#
# WHAT IT DOES NOT DO. It does not parse the source corpus. Corpus formats differ per project
# (MBR spreadsheets here, VBA elsewhere) and a parser for each would rot. It works on the BRDs
# themselves, because divergence is detectable BETWEEN them without knowing where they came
# from. That also means it is honest about its blind spot: if every BRD is wrong the same way,
# this cannot tell.
#
# Usage:
#   facts-lock.sh <project-dir> build      harvest, freeze what is unanimous, report conflicts
#   facts-lock.sh <project-dir> check      fail any BRD that deviates from the frozen lock
#   facts-lock.sh <project-dir> show       what is frozen and what is still contested
#
# Exit: 0 clean · 1 conflicts or deviations · 2 usage/no BRDs

set -u

# Portability: resolve a real Python 3 by EXECUTING candidates, not by looking one up on PATH.
# On Windows `python3` is usually the Microsoft Store alias stub, which `command -v` finds and
# which then opens the Store instead of running. See bin/lib/portable.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

PROJECT_DIR="${1:-}"
CMD="${2:-show}"

[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || {
  echo "usage: facts-lock.sh <project-dir> [build|check|show]" >&2; exit 2; }

case "$CMD" in build|check|show) ;; *)
  echo "usage: facts-lock.sh <project-dir> [build|check|show]" >&2; exit 2 ;; esac

# Discovery is SHARED, not re-derived here. This script originally had its own copy and the
# copy was wrong: it matched analysis/source (2 BRDs), silently skipped analysis/alt-source
# (18), and reported "0 contested" over a corpus it had not read. The correct logic was sitting
# in open-questions.sh under a comment that said "ALL matches, not the first", and got
# re-derived wrong anyway. A facts lock built over a different file set than the collector
# reads is worse than no lock, because it looks authoritative. See lib/discover-brds.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/lib/discover-brds.sh"

KBS=$(discover_brds "$PROJECT_DIR" | sed 's|/brd/[^/]*$||' | sort -u)
[ -n "$KBS" ] || { echo "facts-lock: no <kb>/brd directory found under $PROJECT_DIR" >&2; exit 2; }

# One lock for the project, not one per corpus. A fact that is spelled two ways in two
# knowledge-bases is exactly the conflict worth catching, and a per-corpus lock would hide it.
LOCK="$PROJECT_DIR/analysis/facts.lock.json"

require_py

PROJECT_DIR="$PROJECT_DIR" KBS="$KBS" LOCK="$LOCK" CMD="$CMD" "$PY" - <<'PYEOF'
import glob, json, os, re, sys
from datetime import datetime, timezone

LOCK, CMD = os.environ["LOCK"], os.environ["CMD"]
KBS = [k for k in os.environ["KBS"].splitlines() if k.strip()]

brds = []
for kb in KBS:
    brds.extend(glob.glob(os.path.join(kb, "brd", "*.brd.json")))
brds = sorted(set(brds))
if not brds:
    print("facts-lock: no *.brd.json under %d knowledge-base dir(s)" % len(KBS), file=sys.stderr)
    sys.exit(2)

# --- what counts as a fact ----------------------------------------------------------------
# Keyed harvesting, not free-text scraping. A string only becomes a fact if it appears under a
# key that MEANS "this is an identifier". Scraping prose would cluster ordinary English words
# and bury the real conflicts in noise.
KEYED = {
    "operations": ("operationid", "operationids", "operation"),
    "entities":   ("entity", "entityname", "targetentity", "aggregate"),
    "pages":      ("page", "pagename", "pageid"),
}
# Code sets are recognised by shape wherever they appear — the naming convention is load-bearing
# in these corpora and the key varies too much to enumerate.
CODESET_RE = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*_CODE_SET\b")

def walk(node, key, out, src):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, k.lower(), out, src)
    elif isinstance(node, list):
        for v in node:
            walk(v, key, out, src)
    elif isinstance(node, str):
        s = node.strip()
        if not s:
            return
        for ns, keys in KEYED.items():
            # Identifiers only: a sentence under an `entity` key is prose, not a name.
            if key in keys and len(s) <= 80 and " " not in s:
                out.setdefault(ns, {}).setdefault(s.lower(), {}).setdefault(s, set()).add(src)
        for m in CODESET_RE.findall(s):
            out.setdefault("codeSets", {}).setdefault(m.lower(), {}).setdefault(m, set()).add(src)

harvest = {}
unreadable = []
loaded = []
for path in brds:
    src = os.path.basename(path)
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        loaded.append((src, doc))
        walk(doc, "", harvest, src)
    except Exception as e:
        unreadable.append((src, str(e)))

# --- second pass: the same identifier, spelled differently somewhere else -------------------
# Pass one only sees a string sitting under a key that declares it an identifier. That missed
# the very conflict this tool was built for: on PROJECT-C, `QueryAISafeWIPSummary` (71 uses) and
# `QueryAiSafeWipSummary` (78) both exist, but never both under `operationId` — one spelling
# hides in a `path`, a `returns`, a prose `note`. Pass one alone reported "0 contested" over a
# corpus with a 149-occurrence disagreement in it.
#
# So: pass one establishes WHICH tokens are identifiers; pass two then looks for case-variants
# of exactly those tokens anywhere at all. Scanning prose is safe here precisely because the
# search set is closed — an English word is never matched unless it is already a known
# identifier.
TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]{2,}")
known = {}
for ns, clusters in harvest.items():
    for ck in clusters:
        known.setdefault(ck, ns)

def rescan(node, src):
    if isinstance(node, dict):
        for v in node.values():
            rescan(v, src)
    elif isinstance(node, list):
        for v in node:
            rescan(v, src)
    elif isinstance(node, str):
        for tok in TOKEN_RE.findall(node):
            ns = known.get(tok.lower())
            if ns:
                harvest[ns][tok.lower()].setdefault(tok, set()).add(src)

for src, doc in loaded:
    rescan(doc, src)

# --- load an existing lock ------------------------------------------------------------------
lock = {"version": 1, "frozenAt": None, "facts": {}, "conflicts": []}
if os.path.exists(LOCK):
    try:
        with open(LOCK, encoding="utf-8") as fh:
            lock = json.load(fh)
    except Exception as e:
        print("facts-lock: %s is unreadable (%s) — refusing to overwrite it" % (LOCK, e), file=sys.stderr)
        sys.exit(2)
lock.setdefault("facts", {})
lock.setdefault("conflicts", [])

frozen = lock["facts"]

def canonical_of(ns, ck):
    return (frozen.get(ns, {}).get(ck) or {}).get("canonical")

# --- classify ---------------------------------------------------------------------------------
new_facts, conflicts, deviations = [], [], []

def contestable(variants):
    """Which spellings could actually be a disagreement rather than a convention.

    `genealogy` and `Genealogy` are not two opinions about one name — they are a SQL table
    and a Mendix entity, and flagging that pair buries the real findings in noise (it was 22
    conflicts, 16 of them this shape). An all-lower or all-upper spelling is a CONVENTION:
    snake/lower for table and column names, SCREAMING for constants and code-set tokens.

    Two *mixed-case* spellings cannot both be a convention, so that is the signal — and it is
    exactly the shape of the defect this tool was built for: QueryAISafeWIPSummary against
    QueryAiSafeWipSummary. Someone typed one of them from memory.
    """
    mixed = [v for v in variants if not v.islower() and not v.isupper()]
    return mixed if mixed else variants

for ns, clusters in sorted(harvest.items()):
    for ck, spellings in sorted(clusters.items()):
        variants = contestable(sorted(spellings.keys()))
        canon = canonical_of(ns, ck)
        if canon:
            # Frozen. The lock wins; anything else is a deviation to be fixed in the BRD.
            for v in variants:
                if v != canon:
                    for src in sorted(spellings[v]):
                        deviations.append((ns, src, v, canon))
        elif len(variants) == 1:
            new_facts.append((ns, ck, variants[0], sorted(spellings[variants[0]])))
        else:
            conflicts.append((ns, ck, {v: sorted(spellings[v]) for v in variants}))

# --- act ----------------------------------------------------------------------------------------
if CMD == "build":
    for ns, ck, canon, srcs in new_facts:
        frozen.setdefault(ns, {})[ck] = {"canonical": canon, "sources": srcs}
    lock["conflicts"] = [
        {"namespace": ns, "key": ck,
         "spellings": {v: s for v, s in sp.items()},
         "resolve": "set facts.%s.%s.canonical in this file to the correct spelling, then re-run build" % (ns, ck)}
        for ns, ck, sp in conflicts
    ]
    lock["frozenAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lock["version"] = lock.get("version", 1)
    with open(LOCK, "w", encoding="utf-8") as fh:
        json.dump(lock, fh, indent=2, sort_keys=True)
        fh.write("\n")
    total = sum(len(v) for v in frozen.values())
    print("facts-lock: %d fact(s) frozen across %d namespace(s), from %d BRD(s)" % (total, len(frozen), len(brds)))
    print("            %s" % LOCK)

for src, err in unreadable:
    print("  UNREADABLE  %s — %s (its facts are NOT in the lock)" % (src, err))

if CMD in ("build", "show"):
    if CMD == "show":
        total = sum(len(v) for v in frozen.values())
        print("facts-lock: %d frozen, %d contested, %d BRD(s) read" % (total, len(conflicts), len(brds)))
        print("            %s" % (LOCK if os.path.exists(LOCK) else "(no lock yet — run build)"))
    for ns, ck, sp in conflicts:
        print("")
        print("  CONFLICT  %s/%s — %d spellings, nothing frozen:" % (ns, ck, len(sp)))
        for v, srcs in sorted(sp.items()):
            print("      %-44s %s" % (v, ", ".join(srcs)))
        print("      -> pick one, set it as canonical in the lock, re-run build.")
        print("         Do NOT ask the user which; verify against the source corpus.")

if CMD == "check":
    for ns, src, got, want in deviations:
        print("  DEVIATION  %s: %s spelled '%s', lock says '%s'" % (src, ns, got, want))
    for ns, ck, sp in conflicts:
        print("  UNFROZEN   %s/%s is contested (%s) — build has not resolved it" % (ns, ck, "/".join(sorted(sp))))
    if not deviations and not conflicts:
        total = sum(len(v) for v in frozen.values())
        print("facts-lock: %d BRD(s) agree with all %d frozen fact(s)" % (len(brds), total))

if unreadable:
    sys.exit(1)
if CMD == "check":
    sys.exit(1 if (deviations or conflicts) else 0)
sys.exit(1 if conflicts else 0)
PYEOF
