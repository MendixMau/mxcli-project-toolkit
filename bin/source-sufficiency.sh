#!/bin/bash
# source-sufficiency.sh — say what an intake source can and cannot support, BEFORE generating from it.
#
# WHY THIS EXISTS. Measured on the toolkit as it stood 2026-08-12: every instrument reads BRDs
# or ledgers (facts-lock, coverage-check, open-questions, gate-check). Not one reads a source.
# So a two-page epic deck and a 300-page validated spec enter the pipeline indistinguishably,
# and the difference only surfaces at the interview gate — as a question backlog. PROJECT-C's
# 127 questions were largely that: the source was silent, so the collector asked. By then the
# thinness has been laundered into BRD prose that reads as authoritative because it is JSON.
#
# The cost of the current behaviour is not wasted stages. It is that nobody is ever told
# "this document supports your domain model and three of nine processes; the rest is
# interpretation" — which is the one sentence that makes a thin source safe to build from.
#
# WHAT THIS IS NOT. It is not a quality gate that refuses thin input. Colleagues will keep
# bringing epic decks because that is frequently all that exists, and a pipeline that answers
# "come back with better requirements" gets routed around, not fixed. A thin source is a
# legitimate input; presenting its output as a faithful conversion is the only actual failure.
# So: exit 0 for a thin source. The verdict is information, not a refusal.
#
# WHY THE GRADING IS NOT IN THIS SCRIPT. Sources are PNGs, PDFs, Confluence exports and
# screenshots of screenshots. The reference case that motivated this tool is a one-page
# poster: word-frequency over it would score the palette hexes and miss that no business rule
# exists anywhere on the page. Any text heuristic honest enough to be useful here is a reader,
# and we already have one. So the split is:
#
#   init    this script writes a two-pass rubric skeleton: an `inventory` row per source file
#           (what is this thing about) and the `dimensions` rows (is it good enough to build
#           from). `report` refuses to score until pass 1 is filled.
#   (you)   an agent READS the sources and fills in a rating + evidence + consequence per row
#   report  this script validates the filled rubric, computes the verdict, recommends an
#           interview mode, and renders the HTML
#
# Judgement stays with the reader; arithmetic, consistency and rendering stay here, where they
# are reproducible. This is the same division open-questions.sh uses and for the same reason.
#
# DENOMINATOR DISCIPLINE. Four false-green bugs were found in this toolkit's own instruments
# in a single session, all one shape: a clean report over data the instrument never read.
# Every count this script prints carries what it was counted against, and an unfilled rubric
# is exit 3 (nothing assessed) — never a pass.
#
# Usage:
#   source-sufficiency.sh init   <project-dir> [--sources DIR] [--refresh]
#   source-sufficiency.sh report <project-dir> [--html PATH] [--json] [--quiet]
#   source-sufficiency.sh show   <project-dir>
#
# Bash 3.2 + any Python 3 (resolved by lib/portable.sh, not assumed to be named `python3`).
# No BSD-only userland. Read-only with respect to the Mendix model.

set -u

# Portability: resolve a real Python 3 by EXECUTING candidates, not by looking one up on PATH.
# On Windows `python3` is usually the Microsoft Store alias stub, which `command -v` finds and
# which then opens the Store instead of running. See bin/lib/portable.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

CMD="${1:-}"
PROJECT_DIR="${2:-}"
shift 2 2>/dev/null || true

usage() {
  cat >&2 <<'USAGE'
usage: source-sufficiency.sh <init|report|show> <project-dir> [options]

  init    [--sources DIR]   write analysis/source-sufficiency.json skeleton (never overwrites)
                            two passes: fill `inventory` first, then `dimensions`.
                            EVERY file under the root is a row (bin/lib/source-inventory.py)
          --refresh         add files that appeared since init as unopened rows; keep
                            every filled row; mark vanished ones `missing`
  report  [--html PATH] [--json] [--quiet]
  show                      print the current rubric's verdict without re-rendering

exit 0 assessed (any verdict, including thin)   2 usage   3 nothing assessed   4 rubric invalid
USAGE
  exit 2
}

case "$CMD" in init|report|show) ;; *) usage ;; esac
[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "source-sufficiency: not a directory: $PROJECT_DIR" >&2; exit 2; }

SOURCES_DIR=""
HTML_OUT=""
AS_JSON=0
QUIET=0
REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sources) SOURCES_DIR="${2:-}"; shift 2 ;;
    --refresh) REFRESH=1; shift ;;
    --html)    HTML_OUT="${2:-}";    shift 2 ;;
    --json)    AS_JSON=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "source-sufficiency: unknown option: $1" >&2; usage ;;
  esac
done

RUBRIC="$PROJECT_DIR/analysis/source-sufficiency.json"
DEFAULT_HTML="$PROJECT_DIR/analysis/source-sufficiency.html"

# Was: `command -v python3` — which succeeds on the Windows Store alias stub. require_py
# probes by running the interpreter, so a stub fails here instead of halfway through a stage.
require_py

# --- the rubric -------------------------------------------------------------------------
#
# Ten dimensions, chosen as what a Mendix BUILD PLAN needs rather than what a requirements
# textbook lists. Two of them exist because of specific, repeated, expensive misses:
#
#   tenancy         PROJECT-C shipped every module hardcoding SiteId because multi-site was
#                   one bullet under a scalability heading. The BJJ reference source files
#                   "multiple academies and locations" in exactly the same place. A source
#                   can score well everywhere else and still be missing the decision that
#                   reshapes every entity in the model, so it gets its own row.
#   security_model  actors being NAMED is not a permission model. Three actors and nine
#                   feature groups is 27 cells nobody has filled in, and a role denial is
#                   the failure mode that reaches production intact.
#
# RATINGS. Deliberately four, not five: no neutral middle to park a judgement in.
#   absent     the source does not address it at all
#   named      it is mentioned; nothing is decided (a vendor name, a heading, one bullet)
#   specified  decided in enough detail to build from without inventing
#   verified   specified AND traceable to something authoritative (signed-off spec, live
#              system behaviour, a rule the SME confirmed) rather than to the author's intent

read -r -d '' DIMENSIONS <<'DIMS' || true
actors|Who uses the system, and where one role's authority stops
domain|Entities, their attributes, and the relationships between them
processes|Flows and sequences: what happens after what, and what state it leaves behind
rules|Business rules, validations, thresholds, calculations, eligibility criteria
ui|Screens, navigation, layout, and which data appears on which
integrations|External systems, protocols, credentials, and behaviour when they fail
nfr|Security, performance, availability, retention, data volumes
tenancy|Whether one deployment serves many organisations, and how their data is isolated
security_model|The actor-to-permission mapping: who may do each thing, and who may not
data_migration|Existing data, its volume and shape, and how cutover happens
DIMS

# --- init -------------------------------------------------------------------------------

if [ "$CMD" = "init" ]; then
  mkdir -p "$PROJECT_DIR/analysis"
  if [ -f "$RUBRIC" ] && [ "$REFRESH" = "0" ]; then
    echo "source-sufficiency: $RUBRIC already exists; refusing to overwrite an assessment." >&2
    echo "  edit it, or delete it first if you mean to start over." >&2
    echo "  New files dropped into the source folder since? Run: $0 init $PROJECT_DIR --refresh" >&2
    echo "  (appends the new files as unopened rows; never touches a row already filled in)" >&2
    exit 2
  fi
  [ -f "$RUBRIC" ] || REFRESH=0   # a refresh over nothing is an init

  # Enumerate what is actually there, so the assessment names its own corpus and a later
  # reader can tell whether a file was added after the grading.
  #
  # EVERY FILE IS A ROW (2026-09-02). This block listed files by an extension allowlist, and
  # the allowlist grew one incident at a time: .yaml on 08-19 (an OpenAPI contract went
  # unlisted), code extensions on 08-31 (a Node app's ~40 .ts files went unlisted), and then
  # a .pptx — the only functional description of a workflow engine, 25 slides, 22 diagrams —
  # went unlisted for two months on a VBA migration while every downstream artifact was
  # derived from the .cls exports alone. A COVERAGE instrument that cannot see a source does
  # not under-report it; it reports a corpus that never contained it. An allowlist is only
  # ever as complete as the last incident, so the enumeration is now a denylist: everything
  # under the root minus VCS/dependency/build trees and the project's own generated outputs.
  # The prune list and the walk live in bin/lib/source-inventory.py, shared with
  # bin/source-ledger.sh so the two can never disagree about what "on disk" means.
  #
  # Each row is stamped with what bin/lib/source-formats.tsv knows about its extension —
  # `format`, the extraction `route` that consumes it whole, and for Office/PDF containers
  # the count of embedded `media` (diagrams a text-only extraction leaves behind) and `pages`.
  # An extension the table does not know is `format: unknown`, still a row, still opened.
  #
  # ROOT. --sources wins; on --refresh the rubric's own sourceRoot wins next (a refresh must
  # walk the same tree the inventory was built from); then the drop folders init-project.sh
  # scaffolds (sources/, or source/ — both spellings are in the field); then analysis/, the
  # pre-2026-09-02 default, kept so older projects re-init identically.
  SRC_ROOT="$SOURCES_DIR"
  if [ -z "$SRC_ROOT" ] && [ "$REFRESH" = "1" ]; then
    SRC_ROOT="$("$PY" -c 'import json,sys; print((json.load(open(sys.argv[1])).get("sourceRoot") or ""))' "$RUBRIC" 2>/dev/null || true)"
  fi
  if [ -z "$SRC_ROOT" ]; then
    if   [ -d "$PROJECT_DIR/sources" ]; then SRC_ROOT="$PROJECT_DIR/sources"
    elif [ -d "$PROJECT_DIR/source"  ]; then SRC_ROOT="$PROJECT_DIR/source"
    else SRC_ROOT="$PROJECT_DIR/analysis"; fi
  fi
  INVENTORY_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/source-inventory.py"
  [ -f "$INVENTORY_PY" ] || { echo "source-sufficiency: $INVENTORY_PY missing — cannot enumerate the corpus" >&2; exit 2; }

  DIMENSIONS="$DIMENSIONS" SRC_ROOT="$SRC_ROOT" RUBRIC="$RUBRIC" REFRESH="$REFRESH" \
  INVENTORY_PY="$INVENTORY_PY" "$PY" <<'PY'
import json, os, sys, datetime, subprocess

dims = [l.split('|', 1) for l in os.environ['DIMENSIONS'].strip().splitlines() if l.strip()]
root = os.environ['SRC_ROOT']
rubric = os.environ['RUBRIC']
refresh = os.environ['REFRESH'] == '1'
today = datetime.datetime.now().strftime("%Y-%m-%d")

# The walk is the shared enumerator's, not a second copy of its prune rules.
raw = subprocess.run([sys.executable, os.environ['INVENTORY_PY'], 'enumerate', root],
                     capture_output=True, text=True)
if raw.returncode != 0:
    print(raw.stderr, file=sys.stderr); sys.exit(2)
disk = [json.loads(l) for l in raw.stdout.splitlines() if l.strip()]

def fresh_row(e):
    return {"path": e['path'], "rel": e['rel'], "bytes": e.get('bytes'),
            "ext": e.get('ext'), "format": e.get('format'), "route": e.get('route'),
            "media": e.get('media'), "pages": e.get('pages'),
            "kind": None, "answers": None, "statedScope": "", "components": []}

readme = [
    "TWO PASSES, IN ORDER. Pass 1 is `inventory` — what is this source even about.",
    "Pass 2 is `dimensions` — is it good enough to build from. Do not start pass 2 until",
    "every inventory row is filled: a grade over a corpus you have not identified is a",
    "grade of your own assumptions.",
    "",
    "INVENTORY (pass 1), one row per file — EVERY file under sourceRoot, no format skipped —",
    "filled by OPENING it:",
    "  kind:        docs | code | data | ui | contract | unknown",
    "  answers:     which dimension keys this source can speak to, e.g. [\"domain\",\"rules\"].",
    "               Empty list is a real answer — say so rather than leaving it null.",
    "  statedScope: if the source declares its own boundary, quote it VERBATIM. Sources",
    "               that say what they do not cover are the cheapest scope signal there is.",
    "  components:  named modules/components/aggregates this source defines, one string each.",
    "  format/route/media/pages are stamped by init from bin/lib/source-formats.tsv — what the",
    "               file is by extension, the extraction route that consumes it whole, and how",
    "               many embedded images/diagrams a text-only read would leave behind. A row",
    "               with media > 0 is not consumed until its disposition accounts for them.",
    "",
    "DISPOSITIONS (Stage 1) — one entry per inventory row (or a glob covering several), read",
    "by bin/source-ledger.sh, which blocks the Stage 1 and 2 gates while any row has none:",
    "  {\"path\": \"<rel>\" | \"pattern\": \"<glob over rel>\", \"state\": \"extracted\",",
    "   \"artifact\": \"<project-relative file or dir that carries what was extracted>\",",
    "   \"media\": <images described, must equal the row's media count, or \"mediaWaived\": \"why\">,",
    "   \"by\": \"who\", \"date\": \"YYYY-MM-DD\"}",
    "  The artifact must exist, be non-empty, and NAME the source file — a disposition that",
    "  says 'the triage already used it' is checked by grepping the triage for the file, and",
    "  fails if it never mentions it. Write them with: bin/source-ledger.sh mark ...",
    "  A file deliberately not extracted is a register line, not a disposition:",
    "     bin/gate-check.sh <project> --waive source/<rel> --reason \"...\"",
    "",
    "DIMENSIONS (pass 2). Fill in every dimension by READING the sources. Do not infer a",
    "rating from file size.",
    "  rating: absent | named | specified | verified",
    "  evidence: where you saw it (page, section, screen) — or why you concluded absent.",
    "  consequence: what the BUILD has to invent if this stays as-is. Be concrete.",
    "Leave rating null for any dimension you did not actually check; the report will",
    "refuse to score rather than treat unchecked as absent.",
]

if refresh:
    with open(rubric) as f:
        doc = json.load(f)
    inv = doc.get('inventory')
    if inv is None:
        print("source-sufficiency: this rubric predates the inventory pass; --refresh cannot", file=sys.stderr)
        print("  add rows to an inventory that does not exist. Delete it and re-init.", file=sys.stderr)
        sys.exit(4)
    def norm(p): return os.path.normpath(p)
    by_path = {norm(r.get('path') or ''): r for r in inv}
    by_rel  = {r.get('rel'): r for r in inv if r.get('rel')}
    added, restamped = [], 0
    seen = set()
    for e in disk:
        r = by_path.get(norm(e['path'])) or by_rel.get(e['rel'])
        if r is None:
            row = fresh_row(e); row['addedAt'] = today
            inv.append(row); added.append(e['rel']); seen.add(id(row))
            continue
        seen.add(id(r))
        r.pop('missing', None)
        # Older rows carry no format stamp; give them one without touching what was filled in.
        if 'format' not in r:
            for k in ('rel', 'ext', 'format', 'route', 'media', 'pages'):
                r[k] = e.get(k)
            restamped += 1
    gone = []
    for r in inv:
        if id(r) not in seen:
            r['missing'] = True; gone.append(r.get('rel') or r.get('path'))
    doc['inventory'] = inv
    doc['sources'] = [e['path'] for e in disk]
    doc['sourceCount'] = len(disk)
    doc['sourceRoot'] = root
    doc['refreshedAt'] = today
    doc['_readme'] = readme
    doc.setdefault('dispositions', [])
    with open(rubric, 'w') as f:
        json.dump(doc, f, indent=2); f.write("\n")
    print(f"source-sufficiency: refreshed {rubric}")
    print(f"  corpus: {len(disk)} file(s) under {root} — {len(added)} new, {len(gone)} gone, "
          f"{len(inv) - len(added)} kept as filled")
    for a in added: print(f"    NEW (unopened): {a}")
    for g in gone:  print(f"    GONE (row kept, marked missing): {g}")
    if added:
        print("  next: open each NEW file and fill its inventory row, then re-run report; the")
        print("        ledger (bin/source-ledger.sh) will want a disposition for each at Stage 1.")
    sys.exit(0)

doc = {
    "_readme": readme,
    "assessedAt": today,
    "sourceRoot": root,
    "sources": [e['path'] for e in disk],
    "sourceCount": len(disk),
    # INVENTORY — pass 1. Pre-populated with what a script can know (path, size, format by
    # extension, embedded media count); every judgement field is left null so an unopened
    # file is visibly unopened. This section exists because conversion-runbook.md Stage 0
    # already instructs the agent to "present the source/requirements map... discuss openly",
    # and nothing produced that map — so the agent skipped to the rubric and asked
    # rubric-shaped closed questions about a corpus nobody had characterised. (Live run,
    # 2026-08-19.)
    "inventory": [fresh_row(e) for e in disk],
    # DISPOSITIONS — Stage 1. What consumed each row. Empty at init on purpose: the ledger
    # reports every row PENDING until somebody says which artifact carries it.
    "dispositions": [],
    "dimensions": {
        k: {"demands": v, "rating": None, "evidence": "", "consequence": ""}
        for k, v in dims
    },
    # Conflicts are counted separately from gaps because they route differently: a gap can be
    # assumed by an agent and recorded, a contradiction cannot — somebody has to choose.
    "conflicts": [],
    # CHOICES: silences that change the SHAPE of the model rather than fill in a detail.
    # Kept separate from `conflicts` because they route differently (see question-kinds.sh),
    # and separate from the dimension rows so nine good rows cannot average one away.
    "choices": [],
    "notes": ""
}

with open(rubric, 'w') as f:
    json.dump(doc, f, indent=2)
    f.write("\n")

n = len(disk)
unknown = [e['rel'] for e in disk if e.get('format') == 'unknown']
with_media = [(e['rel'], e['media']) for e in disk if (e.get('media') or 0) > 0]
print(f"source-sufficiency: wrote {rubric}")
print(f"  corpus: {n} file(s) under {root}")
if n == 0:
    print("  NOTE: zero source files found. Either --sources points elsewhere, or the sources")
    print("        are not on disk yet. An empty corpus is not a thin source; it is no source.", file=sys.stderr)
kinds = {}
for e in disk:
    kinds[e.get('format') or 'unknown'] = kinds.get(e.get('format') or 'unknown', 0) + 1
if n:
    print("  by format: " + ', '.join(f"{v} {k}" for k, v in sorted(kinds.items())))
for rel, m in with_media:
    print(f"  embedded media: {rel} carries {m} image(s) — a text-only read is not the file")
if unknown:
    print(f"  unknown format ({len(unknown)}): " + ', '.join(unknown[:10]) + (' ...' if len(unknown) > 10 else ''))
    print("    not skipped — open each, set kind, and route it (custom extractor or a waiver)")
print("  next, IN ORDER:")
print("    pass 1 — open each file and fill its inventory row (kind, answers, statedScope,")
print("             components). What is this source about, before whether it is any good.")
print("    pass 2 — fill in every dimension rating.")
print("    then: bin/source-sufficiency.sh report <project>")
print("    at Stage 1: a disposition per row — bin/source-ledger.sh mark ... — before the gate")
PY
  exit $?
fi

# --- report / show ------------------------------------------------------------------------

[ -f "$RUBRIC" ] || {
  echo "source-sufficiency: no rubric at $RUBRIC" >&2
  echo "  run: $0 init $PROJECT_DIR" >&2
  exit 3
}

[ "$CMD" = "report" ] && [ -z "$HTML_OUT" ] && HTML_OUT="$DEFAULT_HTML"
[ "$CMD" = "show" ] && HTML_OUT=""

RUBRIC="$RUBRIC" HTML_OUT="$HTML_OUT" AS_JSON="$AS_JSON" QUIET="$QUIET" \
PROJECT_DIR="$PROJECT_DIR" "$PY" <<'PY'
import json, os, sys, html, datetime

rubric_path = os.environ['RUBRIC']
html_out    = os.environ['HTML_OUT']
as_json     = os.environ['AS_JSON'] == '1'
quiet       = os.environ['QUIET'] == '1'

try:
    with open(rubric_path) as f:
        doc = json.load(f)
except Exception as e:
    print(f"source-sufficiency: {rubric_path} is not valid JSON: {e}", file=sys.stderr)
    sys.exit(4)

dims = doc.get('dimensions') or {}
if not dims:
    print("source-sufficiency: rubric has no dimensions", file=sys.stderr)
    sys.exit(4)

# --- pass 1: inventory ---------------------------------------------------------------------
#
# Blocking, and deliberately blocking BEFORE the dimension check, so the failure a reader hits
# first is "you have not said what these files are" rather than "you have not graded them".
# Grading an unidentified corpus is how a documents-only source got scored against a rubric
# built for legacy code.
#
# A rubric written before the two-pass format has no `inventory` key at all. That is not the
# same as an unfilled one — it is an older instrument, and failing it would strand every
# in-flight project. It warns and scores; only a PRESENT-but-unfilled inventory blocks.
inventory = doc.get('inventory')
legacy_rubric = inventory is None

if legacy_rubric:
    print("source-sufficiency: this rubric predates the inventory pass — scoring it anyway.",
          file=sys.stderr)
    print("  Its grade is not backed by a characterised corpus. Delete it and re-init to get",
          file=sys.stderr)
    print("  the two-pass form.", file=sys.stderr)
    inventory = []
else:
    unopened = [e.get('path') or '(unnamed)' for e in inventory
                if e.get('kind') is None or e.get('answers') is None]
    if unopened:
        print(f"source-sufficiency: {len(unopened)} of {len(inventory)} source file(s) have no "
              f"inventory entry — nothing graded.", file=sys.stderr)
        for p in unopened[:20]:
            print(f"    unopened: {p}", file=sys.stderr)
        if len(unopened) > 20:
            print(f"    ... and {len(unopened) - 20} more", file=sys.stderr)
        print("  Open each one and set `kind` and `answers` (an empty answers list is a valid",
              file=sys.stderr)
        print("  answer). Pass 1 before pass 2.", file=sys.stderr)
        sys.exit(3)

VALID = ('absent', 'named', 'specified', 'verified')
# Weights are build-readiness, not quality. `named` scores 0 on purpose: a vendor name with no
# integration contract behind it buys the build exactly nothing, and scoring it 0.25 lets nine
# name-drops add up to a passing grade. That is the failure this instrument exists to prevent.
WEIGHT = {'absent': 0.0, 'named': 0.0, 'specified': 1.0, 'verified': 1.0}

unchecked, bad = [], []
for k, v in dims.items():
    r = v.get('rating')
    if r is None:
        unchecked.append(k)
    elif r not in VALID:
        bad.append((k, r))

if bad:
    for k, r in bad:
        print(f"source-sufficiency: dimension '{k}' has rating '{r}', not one of {'/'.join(VALID)}",
              file=sys.stderr)
    sys.exit(4)

total = len(dims)
if unchecked:
    # Unchecked is not absent. Scoring it as absent would let an unread source look merely
    # thin, which is the exact false-green shape this toolkit keeps producing.
    print(f"source-sufficiency: {len(unchecked)} of {total} dimensions unrated "
          f"({', '.join(sorted(unchecked))})", file=sys.stderr)
    print("  nothing scored. Rate every dimension, or state absent with a reason.", file=sys.stderr)
    sys.exit(3)

# --- coverage: the join between pass 1 and pass 2 -------------------------------------------
#
# Which source claims to answer which dimension. This turns "what is missing" from a judgement
# into arithmetic, and it is the material for the OPEN scope question the runbook asks for:
# an uncovered dimension is a real gap to put to a human, not a low rating to average away.
#
# Worth reading the two lists against each other. A dimension that is `specified` but claimed
# by NO source was graded from something outside the corpus — the agent's own knowledge, or a
# conversation nobody wrote down. That is exactly the kind of confident invention this
# instrument exists to catch, so it gets called out rather than quietly passing.
claims = {k: [] for k in dims}
for e in inventory:
    for k in (e.get('answers') or []):
        if k in claims:
            claims[k].append(e.get('path') or '(unnamed)')

uncovered   = sorted(k for k, v in claims.items() if not v)
unsourced   = sorted(k for k in uncovered
                     if (dims[k].get('rating') in ('specified', 'verified')))
kind_counts = {}
for e in inventory:
    kind_counts[e.get('kind') or 'unknown'] = kind_counts.get(e.get('kind') or 'unknown', 0) + 1
stated_scopes = [(e.get('path'), e.get('statedScope')) for e in inventory if e.get('statedScope')]
components    = sorted({c for e in inventory for c in (e.get('components') or [])})

counts = {r: 0 for r in VALID}
for v in dims.values():
    counts[v['rating']] += 1

score = sum(WEIGHT[v['rating']] for v in dims.values())
pct = int(round(100.0 * score / total))

conflicts = doc.get('conflicts') or []
# `choices` is the vocabulary word (see question-kinds.sh: gap / conflict / choice). `landmines`
# was the original key and is still read, because rubrics written before the rename exist and
# silently scoring one of them as zero shape-changing gaps is the worst possible failure here.
landmines = doc.get('choices') or doc.get('landmines') or []
sources   = doc.get('sources') or []

buildable   = sorted(k for k, v in dims.items() if v['rating'] in ('specified', 'verified'))
interpreted = sorted(k for k, v in dims.items() if v['rating'] in ('absent', 'named'))

# --- verdict --------------------------------------------------------------------------
# The recommendation turns on the GAP/CONFLICT split, not on the score. A source can be very
# thin and still safe to run fast, provided it does not contradict itself: an agent can take a
# position on silence and record it, but it cannot resolve a contradiction without choosing
# between two stakeholders, which is not its call to make.

if conflicts:
    mode, mode_why = 'steering', (
        f"{len(conflicts)} contradiction(s) in the source. A contradiction cannot be assumed "
        "away — resolving one means overruling somebody, and the pipeline does not know whom.")
elif landmines:
    mode, mode_why = 'assist', (
        f"No contradictions, but {len(landmines)} silence(s) that change the SHAPE of the model "
        "rather than fill in a detail. Batch those at the gate; assume the rest and record it.")
elif pct >= 70:
    mode, mode_why = 'assist', (
        "Well specified and self-consistent. Batch the remaining questions at gates rather "
        "than asking as you go.")
else:
    mode, mode_why = 'auto', (
        "Thin but self-consistent — gaps, not contradictions. Asking a human questions the "
        "source could never have answered is theatre. Take positions, record every one.")

if pct >= 70:
    band, honest = 'SPECIFICATION', (
        "Output can reasonably be called a conversion of this source.")
elif pct >= 35:
    band, honest = 'OUTLINE', (
        "Output is a PROPOSAL informed by this source, not a conversion of it. Say so when "
        "presenting it, every time.")
else:
    band, honest = 'SKETCH', (
        "Output is substantially the pipeline's own design, with this source as a brief. "
        "Presenting it as a conversion would misrepresent who made the decisions.")

if not sources:
    print("source-sufficiency: rubric lists zero source files — a verdict over no named corpus "
          "is not checkable by anyone else.", file=sys.stderr)

result = {
    'score': score, 'total': total, 'pct': pct, 'band': band,
    'counts': counts, 'recommendedMode': mode, 'modeWhy': mode_why,
    'honest': honest, 'buildable': buildable, 'interpreted': interpreted,
    'conflicts': len(conflicts), 'landmines': len(landmines),
    'sourceCount': len(sources),
}

if as_json:
    print(json.dumps(result, indent=2))
elif not quiet:
    # Pass 1 prints FIRST and unconditionally. The order is the point: a reader (and an agent
    # about to open its mouth in chat) should know what the corpus is before it sees a grade,
    # because the grade is the thing that suggests closed questions and the inventory is the
    # thing that suggests open ones.
    if inventory:
        print(f"Source overview: {len(inventory)} file(s) — "
              f"{', '.join(f'{n} {k}' for k, n in sorted(kind_counts.items()))}")
        for e in inventory:
            ans = ', '.join(e.get('answers') or []) or 'nothing in the rubric'
            print(f"    {e.get('path')}  [{e.get('kind')}] → {ans}")
        if components:
            print(f"  components the sources define ({len(components)}): {', '.join(components)}")
        for p, s in stated_scopes:
            print(f"  scope stated by {p}: {s}")
        print(f"  dimensions no source claims ({len(uncovered)}): {', '.join(uncovered) or 'none'}")
        if unsourced:
            print(f"  WARNING — graded specified/verified but claimed by NO source: "
                  f"{', '.join(unsourced)}")
            print("    that rating came from outside the corpus. Cite a source or drop it.")
        print("")
    print(f"Source sufficiency: {band} — {pct}% build-ready "
          f"({score:g} of {total} dimensions specified or better, across {len(sources)} source file(s))")
    print(f"  specified/verified : {counts['specified'] + counts['verified']}  ({', '.join(buildable) or 'none'})")
    print(f"  named/absent       : {counts['named'] + counts['absent']}  ({', '.join(interpreted) or 'none'})")
    print(f"  contradictions     : {len(conflicts)}")
    print(f"  shape-changing gaps: {len(landmines)}")
    print(f"  recommended interview mode: {mode}")
    print(f"    {mode_why}")
    print(f"  {honest}")

# --- html -------------------------------------------------------------------------------

def esc(s):
    return html.escape(str(s or ''))

if html_out:
    RATING_ORDER = {'absent': 0, 'named': 1, 'specified': 2, 'verified': 3}
    rows = sorted(dims.items(), key=lambda kv: (RATING_ORDER[kv[1]['rating']], kv[0]))

    # The bar is the thesis of the page, so its segments are labelled rather than decorative:
    # a reader should see WHICH dimensions are missing before reading a word of prose.
    bar = ''.join(
        f'<div class="seg r-{esc(v["rating"])}" title="{esc(k)}: {esc(v["rating"])}">'
        f'<span>{esc(k.replace("_", " "))}</span></div>'
        for k, v in rows)

    dim_rows = '\n'.join(
        f'<tr class="r-{esc(v["rating"])}">'
        f'<td class="dim"><strong>{esc(k)}</strong><span class="demands">{esc(v.get("demands"))}</span></td>'
        f'<td><span class="pill p-{esc(v["rating"])}">{esc(v["rating"])}</span></td>'
        f'<td>{esc(v.get("evidence")) or "<em>—</em>"}</td>'
        f'<td>{esc(v.get("consequence")) or "<em>—</em>"}</td>'
        f'</tr>' for k, v in rows)

    def listing(items, empty, cls):
        if not items:
            return f'<p class="none">{esc(empty)}</p>'
        out = []
        for it in items:
            if isinstance(it, dict):
                t = it.get('title') or it.get('what') or ''
                d = it.get('detail') or it.get('why') or it.get('question') or ''
                out.append(f'<li class="{cls}"><strong>{esc(t)}</strong>'
                           + (f'<span>{esc(d)}</span>' if d else '') + '</li>')
            else:
                out.append(f'<li class="{cls}">{esc(it)}</li>')
        return '<ul class="items">' + ''.join(out) + '</ul>'

    src_list = ''.join(f'<li><code>{esc(os.path.basename(s))}</code></li>' for s in sources) \
               or '<li>no source files named</li>'

    page = f"""<title>Source sufficiency — {esc(os.path.basename(os.environ.get('PROJECT_DIR','')))}</title>
<style>
  /* Neutrals are slate-biased rather than pure grey so the four semantic hues read as data.
     The accent is used ONLY for the recommendation; severity never borrows it. */
  :root {{
    --bg:#f6f7f9; --panel:#ffffff; --fg:#11141a; --muted:#5b6472; --line:#e0e4ea;
    --absent:#b23b32; --named:#b07a1c; --specified:#2f7d5d; --verified:#2b6b96;
    --accent:#3b5bdb; --seg-ink:#ffffff;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --bg:#101319; --panel:#171b22; --fg:#e6e9ef; --muted:#939cab; --line:#272d37;
      --absent:#d96b60; --named:#cf9a3f; --specified:#4fa87f; --verified:#4f9bc7;
      --accent:#7b95f0; --seg-ink:#0d1015;
    }}
  }}
  :root[data-theme="dark"] {{
    --bg:#101319; --panel:#171b22; --fg:#e6e9ef; --muted:#939cab; --line:#272d37;
    --absent:#d96b60; --named:#cf9a3f; --specified:#4fa87f; --verified:#4f9bc7;
    --accent:#7b95f0; --seg-ink:#0d1015;
  }}
  * {{ box-sizing:border-box; }}
  body {{ background:var(--bg); color:var(--fg); margin:0; padding:3rem 1.25rem 4rem;
         font:15px/1.6 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
         font-variant-numeric:tabular-nums; }}
  main {{ max-width:62rem; margin:0 auto; display:flex; flex-direction:column; gap:0; }}
  .eyebrow {{ font-size:.7rem; text-transform:uppercase; letter-spacing:.14em; font-weight:700;
              color:var(--muted); margin:0 0 .5rem; }}
  h1 {{ font-size:1.75rem; line-height:1.15; letter-spacing:-.02em; margin:0 0 .4rem;
        text-wrap:balance; }}
  h2 {{ font-size:.78rem; text-transform:uppercase; letter-spacing:.12em; font-weight:700;
        margin:2.75rem 0 .75rem; color:var(--muted); }}
  h2 .note {{ text-transform:none; letter-spacing:0; font-weight:400; }}
  .sub {{ color:var(--muted); margin:0 0 2rem; max-width:44rem; }}
  .verdict {{ background:var(--panel); border:1px solid var(--line); border-radius:4px;
              padding:1.5rem 1.6rem; }}
  .band {{ font-size:2.25rem; font-weight:700; letter-spacing:-.03em; line-height:1; }}
  .band small {{ font-size:.95rem; font-weight:500; color:var(--muted); margin-left:.6rem;
                 letter-spacing:0; }}
  .bar {{ display:flex; gap:2px; margin:1.35rem 0 .5rem; }}
  .seg {{ flex:1 1 0; min-width:0; height:2.1rem; display:flex; align-items:center;
          justify-content:center; border-radius:2px; overflow:hidden; }}
  .seg span {{ font-size:.6rem; text-transform:uppercase; letter-spacing:.04em; font-weight:700;
               color:var(--seg-ink); opacity:.95; white-space:nowrap;
               overflow:hidden; text-overflow:clip; padding:0 .2rem; }}
  .seg.r-absent{{background:var(--absent)}} .seg.r-named{{background:var(--named)}}
  .seg.r-specified{{background:var(--specified)}} .seg.r-verified{{background:var(--verified)}}
  .legend {{ color:var(--muted); font-size:.8rem; }}
  .honest {{ margin-top:1.35rem; padding:.9rem 1.1rem; border-left:3px solid var(--accent);
             background:var(--bg); border-radius:0 3px 3px 0; }}
  .honest p {{ margin:0; }}
  .honest p + p {{ margin-top:.6rem; }}
  table {{ width:100%; border-collapse:collapse; font-size:.88rem; }}
  .scroll {{ overflow-x:auto; }}
  th {{ text-align:left; font-size:.68rem; text-transform:uppercase; letter-spacing:.1em;
        font-weight:700; color:var(--muted); border-bottom:1px solid var(--line);
        padding:.5rem .7rem; white-space:nowrap; }}
  td {{ border-bottom:1px solid var(--line); padding:.85rem .7rem; vertical-align:top; }}
  tr.r-absent td:first-child {{ box-shadow:inset 3px 0 0 var(--absent); }}
  tr.r-named td:first-child {{ box-shadow:inset 3px 0 0 var(--named); }}
  tr.r-specified td:first-child {{ box-shadow:inset 3px 0 0 var(--specified); }}
  tr.r-verified td:first-child {{ box-shadow:inset 3px 0 0 var(--verified); }}
  .dim {{ min-width:12rem; padding-left:1rem !important; }}
  .dim strong {{ display:block; font-size:.95rem; }}
  .demands {{ display:block; color:var(--muted); font-size:.78rem; margin-top:.2rem; }}
  .pill {{ display:inline-block; padding:.15rem .55rem; border-radius:3px; font-size:.68rem;
           font-weight:700; text-transform:uppercase; letter-spacing:.06em;
           color:var(--seg-ink); white-space:nowrap; }}
  .p-absent{{background:var(--absent)}} .p-named{{background:var(--named)}}
  .p-specified{{background:var(--specified)}} .p-verified{{background:var(--verified)}}
  .items {{ margin:0; padding:0; list-style:none; display:flex; flex-direction:column; gap:.6rem; }}
  .items li {{ background:var(--panel); border:1px solid var(--line); border-radius:3px;
               padding:.85rem 1rem; }}
  .items li.conflict {{ border-left:3px solid var(--absent); }}
  .items li.landmine {{ border-left:3px solid var(--named); }}
  .items li span {{ display:block; color:var(--muted); font-size:.87rem; margin-top:.3rem; }}
  .corpus {{ margin:0; padding:0; list-style:none; display:flex; flex-wrap:wrap; gap:.4rem; }}
  .corpus li {{ background:var(--panel); border:1px solid var(--line); border-radius:3px;
                padding:.3rem .6rem; font-size:.82rem; }}
  .none {{ color:var(--muted); margin:0; }}
  .mode {{ font-weight:700; color:var(--accent); }}
  code {{ font-size:.85em; }}
  footer {{ margin-top:3rem; padding-top:1.1rem; border-top:1px solid var(--line);
            color:var(--muted); font-size:.8rem; max-width:46rem; }}
</style>
<main>
  <p class="eyebrow">Stage 0 · intake</p>
  <h1>What this source can and cannot support</h1>
  <p class="sub">Assessed {esc(doc.get('assessedAt'))}, before anything was generated from it —
     so the gaps arrive as a decision to make rather than as invented detail to discover later.</p>

  <div class="verdict">
    <div class="band">{esc(band)} <small>{pct}% build-ready</small></div>
    <div class="bar">{bar}</div>
    <div class="legend">{score:g} of {total} dimensions specified or better · {len(sources)} source file(s)
       · {len(conflicts)} contradiction(s) · {len(landmines)} shape-changing gap(s)</div>
    <div class="honest">
      <p style="margin:0 0 .5rem"><strong>How the output must be described.</strong> {esc(honest)}</p>
      <p style="margin:0">Recommended interview mode: <span class="mode">{esc(mode)}</span> — {esc(mode_why)}</p>
    </div>
  </div>

  <h2>Dimensions</h2>
  <div class="scroll"><table>
    <thead><tr><th>Dimension</th><th>Rating</th><th>Evidence</th><th>What the build must invent</th></tr></thead>
    <tbody>{dim_rows}</tbody>
  </table></div>

  <h2>Contradictions <span class="note">— a human must choose</span></h2>
  {listing(conflicts, 'None found. The source is silent in places, but it does not disagree with itself — which is why a faster mode is safe here.', 'conflict')}

  <h2>Shape-changing gaps <span class="note">— silences that redesign the model, not details that fill it in</span></h2>
  {listing(landmines, 'None recorded.', 'landmine')}

  <h2>Corpus</h2>
  <ul class="corpus">{src_list}</ul>

  <footer>
    Ratings: <strong>absent</strong> not addressed · <strong>named</strong> mentioned, nothing decided
    · <strong>specified</strong> buildable without inventing · <strong>verified</strong> specified and
    traceable to something authoritative. <code>named</code> scores zero: a vendor name with no
    contract behind it buys the build nothing.
    <br>A thin source is a legitimate input. The failure mode this report exists to prevent is not
    thin input — it is thin input whose output gets presented as a conversion.
  </footer>
</main>
"""
    with open(html_out, 'w') as f:
        f.write(page)
    if not quiet and not as_json:
        print(f"  report: {html_out}")
PY

exit $?
