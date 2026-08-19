#!/bin/bash
# brd-report.sh — the Stage 2 surface. ONE renderer, for BRDs from any source.
#
# WHY THIS EXISTS (2026-08-19). This replaces three copies of
# `pipelines/*/pipeline/generate-enrichment-report.js`, which were the same page written three
# times because nothing said a BRD reader does not belong under `pipelines/`. The three copies
# drifted onto three different BRD shapes:
#
#   java-angular / node-express-react   b.module   e.attributeCount  a.to      u.screen
#   outsystems                          b.modules  (no entity/page/microflow sections at all)
#   brd-generation.md, the DOCUMENTED   b.modules  e.attributes[]    a.target  u.screens[]
#
# and all three SCAFFOLDERS emit `module` singular — so the outsystems report was broken
# against its own pipeline's output, and a BRD written by hand per `brd-generation.md`
# rendered `Module: undefined`, blank attribute columns, "0 hidden rules" and "0/N reviewed".
# A page that looked complete and said nothing. Same disease as `bin/lib/discover-brds.sh`
# documents one layer down: *the fix does not travel*.
#
# Requirements-driven and greenfield projects got no Stage 2 surface AT ALL, because the only
# renderer lived inside a pipeline they never run — while `conversion-runbook.md` promises the
# surface unconditionally. Documents-only sources have the same problem: their BRDs come from
# `kb-generation.md`, not from an extractor.
#
# WHAT THIS IS NOT. It is not a gate and it is not a validator. It renders what the BRDs say
# and marks what they do not say. `gate-check.sh` owns the Stage 2 gate; `brd-validation.md`
# owns the judgement about whether a BRD is any good. Per `skills-over-scripts.md`, everything
# here is fact-fetching and arithmetic: which keys are present, counted against how many were
# looked for. The one thing it will not do is print a `0` it cannot back up.
#
# THE PART THAT MATTERS: PROVENANCE. A requirements-driven BRD legitimately has no
# code-extracted `domainEntities`. A migration BRD absolutely should. Under one renderer those
# two must NOT look the same, so every section carries a `report-schema.md` verdict:
#
#   pass      the section is present and was read
#   fault     expected for this BRD's provenance and absent — a visible finding, never a 0
#   skipped   not applicable to this provenance, WITH the reason printed
#   manual    provenance could not be determined, so nobody can say which of the two it is
#
# `fail` is not expressible here and that is deliberate (report-schema.md `expressibleVerdicts`):
# this instrument never judges whether the CONTENT is right, only whether it is there.
#
# Usage:
#   brd-report.sh <project-dir> [--html PATH] [--json] [--quiet]
#
# exit 0 rendered (faults included — a fault is information, and the gate is gate-check's job)
#      2 usage   3 no BRDs found (never a pass)   4 a BRD is not valid JSON
#
# Bash 3.2 + any Python 3 (resolved by lib/portable.sh, not assumed to be named `python3`).

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The one place that knows where BRDs live. Sourced, never re-derived: re-deriving it is the
# 2026-08-12 bug documented in that file's header, where one of three copies read only the
# FIRST knowledge-base directory and reported a clean result over 10% of the corpus.
# shellcheck disable=SC1091
. "$HERE/lib/discover-brds.sh"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"

usage() {
  cat >&2 <<'USAGE'
usage: brd-report.sh <project-dir> [--html PATH] [--json] [--quiet]

  Renders the Stage 2 BRD surface from every BRD in the project, whatever produced them —
  a pipeline extractor, kb-generation.md, an SME interview, or a text editor.

  --html PATH   where to write (default: <project-dir>/analysis/brd-report.html)
  --json        machine-readable summary on stdout instead of prose
  --quiet       render, say nothing

exit 0 rendered   2 usage   3 no BRDs found   4 a BRD is not valid JSON
USAGE
  exit 2
}

PROJECT_DIR="${1:-}"
shift 2>/dev/null || true

case "$PROJECT_DIR" in -h|--help|'') usage ;; esac

HTML_OUT=""
AS_JSON=0
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --html)  HTML_OUT="${2:-}"; shift 2 ;;
    --json)  AS_JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "brd-report: unknown option: $1" >&2; usage ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "brd-report: not a directory: $PROJECT_DIR" >&2; exit 2; }

# Was: `command -v python3` in the scripts this one is modelled on — which succeeds on the
# Windows Store alias stub. require_py probes by running the interpreter.
require_py

BRD_FILES=$(discover_brds "$PROJECT_DIR")
BRD_COUNT=$(count_lines "$BRD_FILES")

if [ "$BRD_COUNT" = "0" ]; then
  # An empty result set is never a pass (report-schema.md). Distinct exit code so no caller
  # can read "found nothing" as "nothing to find".
  echo "brd-report: no BRDs found under $PROJECT_DIR — nothing rendered." >&2
  echo "  looked in: analysis/*/knowledge-base/brd, analysis/knowledge-base/brd, knowledge-base/brd" >&2
  echo "  Stage 2 has no surface until BRDs exist. See skills/brd-generation.md." >&2
  exit 3
fi

[ -n "$HTML_OUT" ] || HTML_OUT="$PROJECT_DIR/analysis/brd-report.html"
mkdir -p "$(dirname "$HTML_OUT")" 2>/dev/null || true

BRD_FILES="$BRD_FILES" BRD_COUNT="$BRD_COUNT" HTML_OUT="$HTML_OUT" AS_JSON="$AS_JSON" \
QUIET="$QUIET" PROJECT_DIR="$PROJECT_DIR" "$PY" <<'PY'
import json, os, sys, html, datetime

files      = [f for f in os.environ['BRD_FILES'].splitlines() if f.strip()]
html_out   = os.environ['HTML_OUT']
as_json    = os.environ['AS_JSON'] == '1'
quiet      = os.environ['QUIET'] == '1'
project    = os.environ['PROJECT_DIR']

# --- read ------------------------------------------------------------------------------

docs = []
for f in files:
    try:
        with open(f) as fh:
            docs.append((f, json.load(fh)))
    except Exception as e:
        print(f"brd-report: {f} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(4)

kb_dirs = sorted({os.path.dirname(os.path.dirname(f)) for f in files})

# --- tolerant readers --------------------------------------------------------------------
#
# Both shapes are accepted for the duration of the `module` → `modules[]` transition, and the
# legacy one is RECORDED rather than silently normalised — a reader of the page should be able
# to see which BRDs still carry the old key, or the transition never finishes.

def first_present(d, *keys):
    """(value, key-that-supplied-it) or (None, None). A present-but-empty value still counts
    as present: `"attributes": []` is a real answer, and coercing it to missing would report a
    genuinely empty entity as a drifted key."""
    for k in keys:
        if isinstance(d, dict) and k in d and d[k] is not None:
            return d[k], k
    return None, None

def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]

def alist(d, *keys):
    v, k = first_present(d, *keys)
    return as_list(v), k

# --- provenance -------------------------------------------------------------------------
#
# CAN `sourceKB` CARRY THIS? Only halfway, and the halfway is the dangerous part. `sourceKB`
# is a list of doc-KB FILENAMES (`brd-generation.md`:127). A non-empty one proves documents
# contributed; an empty or absent one proves nothing at all — the scaffolders never emit the
# key, an SME-interview BRD has no KB files to name, and a hand-written BRD may just have
# omitted it. So `sourceKB` is read as one POSITIVE signal, never as the provenance itself.
#
# The declared form is a top-level `"provenance"` string. That key is not invented here:
# `coverage-ledger.md` already ledgers `/provenance/*` alongside `/sourceKB/*` as BRD metadata,
# so the slot exists and nothing else claims it.
#
# Inference is a fallback and is LABELLED as inference on the page. When neither a declaration
# nor a fingerprint is available the answer is `unknown`, printed as such — never defaulted to
# a guess, because the guess decides whether a missing `domainEntities` is a fault or a
# non-event, and getting that wrong in either direction is the whole bug this file replaces.

PROVENANCES = ('code-extracted', 'documents', 'interview', 'greenfield')

def provenance_of(b):
    declared, _ = first_present(b, 'provenance')
    if isinstance(declared, str) and declared.strip():
        p = declared.strip()
        if p in PROVENANCES:
            return p, 'declared', f'the BRD declares "provenance": "{p}"'
        return 'unknown', 'declared-unrecognised', (
            f'the BRD declares "provenance": "{p}", which is not one of '
            f'{"/".join(PROVENANCES)} — treated as undetermined rather than guessed at')

    # Scaffolder fingerprint: brd-mappers/index.js writes generatedAt + appType + openGaps +
    # summary.openGapCount together, and nothing else in this toolkit writes any of them.
    summary = b.get('summary') if isinstance(b.get('summary'), dict) else {}
    code_marks = [k for k in ('generatedAt', 'appType', 'openGaps') if k in b]
    if 'openGapCount' in summary:
        code_marks.append('summary.openGapCount')
    if 'generatedAt' in b and len(code_marks) >= 2:
        return 'code-extracted', 'inferred', (
            'no declared provenance; inferred from the extractor scaffolder fingerprint ('
            + ', '.join(code_marks) + ')')

    if as_list(b.get('sourceKB')):
        return 'documents', 'inferred', (
            'no declared provenance; inferred because sourceKB names '
            f'{len(as_list(b.get("sourceKB")))} document-KB file(s)')

    return 'unknown', 'undetermined', (
        'no "provenance" key, no extractor fingerprint, and no sourceKB — nothing on this BRD '
        'says where it came from')

# --- what each provenance owes ------------------------------------------------------------
#
# EXPECTED  absence is a finding. FAULT.
# OPTIONAL  legitimately present or absent for this provenance. SKIPPED, reason printed.
# N/A       this provenance cannot produce it at all. SKIPPED, reason printed.
#
# The single reason this table exists: a requirements-driven BRD with no `domainEntities` is
# normal, and a migration BRD with no `domainEntities` means the extractor produced nothing
# and nobody noticed. One renderer, so the two must be told apart HERE or not at all.

E, O, N = 'expected', 'optional', 'n/a'

SECTIONS = [
    # key                label                          how the count is derived
    ('domainEntities',   'Domain entities'),
    ('microflows',       'Microflows / logic'),
    ('pages',            'Pages'),
    ('useCases',         'Use cases'),
    ('businessRules',    'Business rules'),
    ('dataRequirements', 'Data requirements'),
    ('integrations',     'Integrations'),
    ('hiddenRules',      'Hidden business rules'),
    ('openQuestions',    'Open questions'),
]

# `code-extracted` is the only provenance that OWES a domain model. The scaffolders
# (brd-mappers/index.js) emit domainEntities, microflows, pages and useCases on every module,
# unconditionally — so an empty one of those means the extractor produced nothing and nobody
# looked, which is exactly the false green this file exists to stop.
#
# Every other provenance owes `useCases` and nothing else. A requirements-driven BRD that
# describes no use case describes nothing; its entities, microflows and pages are DESIGNED at
# Stages 3-4 rather than extracted at Stage 1, so their absence at Stage 2 is normal and
# marking it a fault would train readers to ignore the colour.
EXPECT = {
    'code-extracted': {
        'domainEntities': E, 'microflows': E, 'pages': E, 'useCases': E,
        'businessRules': O, 'dataRequirements': O, 'integrations': O,
        'hiddenRules': O, 'openQuestions': O,
    },
    'documents': {
        'domainEntities': O, 'microflows': O, 'pages': O, 'useCases': E,
        'businessRules': O, 'dataRequirements': O, 'integrations': O,
        'hiddenRules': N, 'openQuestions': O,
    },
}
# interview and greenfield owe exactly what documents owes: neither has code to extract from.
EXPECT['interview']  = dict(EXPECT['documents'])
EXPECT['greenfield'] = dict(EXPECT['documents'])

NA_REASON = {
    'hiddenRules': 'hidden rules are rules found INSIDE extracted code that the domain model '
                   'does not show. A {p} BRD has no code to hide them in — this is not a gap.',
}

def expectation(prov, key):
    if prov not in EXPECT:
        return None
    return EXPECT[prov].get(key, O)

# --- item-level key expectations ----------------------------------------------------------
#
# A section that is present but whose ITEMS have drifted keys is the worse failure of the two:
# the section renders, the count is right, and every cell in it is blank. So each item is
# checked for the keys the renderer needs, under every name any producer has used, and a key
# found under none of them is reported as UNREADABLE — by name, per BRD. A future rename
# announces itself on the page instead of arriving as a column of dashes.

ITEM_KEYS = {
    'domainEntities':   [('name', ('name',)),
                         ('attributes', ('attributes', 'attributeCount'))],
    'microflows':       [('name', ('name',)),
                         ('purpose', ('purpose', 'description'))],
    'pages':            [('name', ('name',))],
    'useCases':         [('id', ('id',)), ('title', ('title',))],
    'businessRules':    [('id', ('id',)), ('title', ('title', 'rule', 'description'))],
    'dataRequirements': [('id', ('id',)), ('entity', ('entity',))],
    'integrations':     [('name', ('name', 'system'))],
    'openQuestions':    [('question', ('question',))],
}

# Keys still accepted under a legacy name. Reported so the transition is visible and finite.
LEGACY = {
    'module':         'modules[] — brd-generation.md carries an array of 1..n',
    'attributeCount': 'attributes[] — the count is derivable, the list is not',
    'to':             'target — on an association',
    'screen':         'screens[] — a use case may touch more than one',
}

# --- per-BRD analysis ----------------------------------------------------------------------

def rules_of(mfs):
    """hiddenRules is not a top-level key on any shape — it hangs off microflows[]. Derived
    here rather than read, so a BRD with microflows but no hidden rules is a real zero and a
    BRD with no microflows cannot report one."""
    out = []
    for m in mfs:
        if not isinstance(m, dict):
            continue
        for hr in as_list(m.get('hiddenRules')):
            if isinstance(hr, dict):
                out.append({'microflow': m.get('name'), 'rule': hr.get('rule'),
                            'risk': hr.get('risk') or 'unrated'})
            else:
                out.append({'microflow': m.get('name'), 'rule': hr, 'risk': 'unrated'})
    return out

analysed = []
for path, b in docs:
    if not isinstance(b, dict):
        print(f"brd-report: {path} is valid JSON but not an object", file=sys.stderr)
        sys.exit(4)

    legacy_used = []
    unreadable = []

    mods, mods_key = alist(b, 'modules', 'module')
    if mods_key == 'module':
        legacy_used.append('module')
    if not mods:
        unreadable.append('modules — neither `modules` nor `module` is set; this BRD names no '
                          'Mendix module, so nothing downstream can place what it describes')

    ident = b.get('id') or os.path.basename(path).replace('.brd.json', '')
    title = b.get('title') or (mods[0] if mods else ident)

    prov, prov_kind, prov_why = provenance_of(b)

    raw = {}
    keys_found = {}
    for key, _label in SECTIONS:
        if key == 'hiddenRules':
            continue
        v, k = alist(b, key)
        raw[key] = [x for x in v]
        keys_found[key] = k
    raw['hiddenRules'] = rules_of(raw['microflows'])
    keys_found['hiddenRules'] = 'microflows[].hiddenRules' if raw['microflows'] else None

    # item-level drift
    for key, checks in ITEM_KEYS.items():
        items = [x for x in raw.get(key, []) if isinstance(x, dict)]
        if not items:
            continue
        for want, aliases in checks:
            missing = 0
            for it in items:
                _v, got = first_present(it, *aliases)
                if got is None:
                    missing += 1
                elif got != want:
                    if got in LEGACY and got not in legacy_used:
                        legacy_used.append(got)
            if missing:
                unreadable.append(
                    f"{key}[].{want} — {missing} of {len(items)} item(s) carry it under none of "
                    f"{'/'.join(aliases)}. Rendered as unknown, NOT as zero.")

    # association target drift, one level down
    assoc_missing = 0
    assoc_total = 0
    for e in raw['domainEntities']:
        if not isinstance(e, dict):
            continue
        for a in as_list(e.get('associations')):
            if not isinstance(a, dict):
                continue
            assoc_total += 1
            _v, got = first_present(a, 'target', 'to')
            if got is None:
                assoc_missing += 1
            elif got == 'to' and 'to' not in legacy_used:
                legacy_used.append('to')
    if assoc_missing:
        unreadable.append(
            f"domainEntities[].associations[].target — {assoc_missing} of {assoc_total} "
            f"association(s) name no other end under target/to.")

    # use-case screens drift
    for u in raw['useCases']:
        if isinstance(u, dict) and 'screen' in u and 'screens' not in u and 'screen' not in legacy_used:
            legacy_used.append('screen')

    # verdicts
    verdicts = {}
    for key, label in SECTIONS:
        n = len(raw[key])
        exp = expectation(prov, key)
        if n:
            verdicts[key] = ('pass', f'{n} present')
        elif exp is None:
            verdicts[key] = ('manual', 'provenance undetermined — whether this absence is a '
                                       'gap or a non-event needs a human, and no field on this '
                                       'BRD answers it')
        elif exp == E:
            verdicts[key] = ('fault', f'absent, and a {prov} BRD is expected to carry it. '
                                      f'This is a finding, not a zero.')
        elif exp == N:
            verdicts[key] = ('skipped', NA_REASON.get(
                key, 'not applicable to a {p} BRD.').format(p=prov))
        else:
            verdicts[key] = ('skipped', f'optional for a {prov} BRD — absence here is not a '
                                        f'finding.')

    # brd-validation.md check 5 — the two signals, side by side.
    conf = b.get('confidence')
    conf = conf.strip() if isinstance(conf, str) else None

    doc_confirmed = sum(1 for u in raw['useCases']
                        if isinstance(u, dict) and u.get('status') == 'doc-confirmed')
    kb_files = as_list(b.get('sourceKB'))
    if doc_confirmed:
        doc_signal = 'confirmed'
        doc_why = (f'{doc_confirmed} use case(s) reconciled against the doc-KB '
                   f'(status: doc-confirmed)')
    elif kb_files:
        doc_signal = 'cited'
        doc_why = (f'{len(kb_files)} doc-KB file(s) named in sourceKB, but no use case carries '
                   f'a doc-confirmed status yet')
    else:
        doc_signal = 'none'
        doc_why = 'no sourceKB, no doc-confirmed use case — nothing corroborates this BRD'

    # The ONLY comparison brd-validation.md check 5 actually makes. Everything else on this
    # grid is left unranked on purpose: inventing a score here would be exactly the
    # skills-over-scripts.md failure of encoding a judgement the skill has not made.
    if conf in ('low', 'medium') and doc_signal in ('confirmed', 'cited'):
        review = ('review-ready',
                  'Low code confidence, but there is doc-KB material to review it against — '
                  'brd-validation.md check 5 names this the better manual-review candidate.')
    elif conf in ('low', 'medium') and doc_signal == 'none':
        review = ('uncorroborated',
                  'Neither code confidence nor doc coverage. Manual review has nothing to '
                  'check this against; it needs SME input, not a reviewer.')
    else:
        review = ('unranked',
                  'brd-validation.md check 5 ranks only the low-confidence pair. Both signals '
                  'are shown; the ordering is a judgement the skill has not made.')

    analysed.append({
        'path': path, 'id': ident, 'title': title, 'modules': mods,
        'provenance': prov, 'provenanceKind': prov_kind, 'provenanceWhy': prov_why,
        'raw': raw, 'verdicts': verdicts, 'unreadable': unreadable,
        'legacy': legacy_used,
        'confidence': conf, 'docSignal': doc_signal, 'docWhy': doc_why, 'review': review,
        'keysFound': keys_found,
    })

analysed.sort(key=lambda a: (str(a['id']), a['path']))

# --- totals ------------------------------------------------------------------------------
#
# Every count carries its denominator. A bare "0 hidden rules" is indistinguishable from a
# renderer that read the wrong key, and that is the precise bug this file replaces.

tally = {'pass': 0, 'fault': 0, 'skipped': 0, 'manual': 0}
for a in analysed:
    for v, _ in a['verdicts'].values():
        tally[v] += 1
cells = len(analysed) * len(SECTIONS)

prov_counts = {}
for a in analysed:
    prov_counts[a['provenance']] = prov_counts.get(a['provenance'], 0) + 1

totals = {}
for key, _ in SECTIONS:
    totals[key] = sum(len(a['raw'][key]) for a in analysed)
all_modules = sorted({m for a in analysed for m in a['modules'] if isinstance(m, str)})
all_actors = sorted({(x if isinstance(x, str) else (x.get('name') if isinstance(x, dict) else str(x)))
                     for _p, b in docs for x in as_list(b.get('actors'))})
all_actors = [x for x in all_actors if x]
unreadable_total = sum(len(a['unreadable']) for a in analysed)

result = {
    'brdCount': len(analysed),
    'knowledgeBaseDirs': kb_dirs,
    'sectionCells': cells,
    'verdicts': tally,
    'unreadableKeys': unreadable_total,
    'provenance': prov_counts,
    'totals': totals,
    'moduleCount': len(all_modules),
    'actorCount': len(all_actors),
    'brds': [{'id': a['id'], 'path': a['path'], 'provenance': a['provenance'],
              'provenanceKind': a['provenanceKind'],
              'confidence': a['confidence'], 'docCorroboration': a['docSignal'],
              'reviewSignal': a['review'][0],
              'unreadable': a['unreadable'], 'legacyKeys': a['legacy'],
              'verdicts': {k: v[0] for k, v in a['verdicts'].items()}} for a in analysed],
}

# --- stdout -------------------------------------------------------------------------------

if as_json:
    print(json.dumps(result, indent=2))
elif not quiet:
    print(f"BRD report: {len(analysed)} BRD(s) across {len(kb_dirs)} knowledge-base dir(s)")
    for d in kb_dirs:
        print(f"    {d}")
    print(f"  provenance: " + ', '.join(f"{n} {p}" for p, n in sorted(prov_counts.items())))
    print(f"  sections  : {tally['pass']} pass, {tally['fault']} fault, "
          f"{tally['skipped']} skipped, {tally['manual']} manual "
          f"(of {cells} = {len(analysed)} BRD(s) x {len(SECTIONS)} sections)")
    # Printed on its own line and NOT folded into the section tally: an unreadable key is a
    # fault about the SHAPE of a section that otherwise rendered, so summing it into
    # `fault` above would make a populated section look absent. "0 fault" next to
    # "unreadable keys: 2" is honest; one number covering both would not be.
    print(f"  unreadable keys: {unreadable_total}"
          + ("  (each is a fault, listed per BRD below; not folded into the section tally)"
             if unreadable_total else ""))
    print("")
    for a in analysed:
        faults = [(k, why) for k, (v, why) in a['verdicts'].items() if v == 'fault']
        manuals = [k for k, (v, _w) in a['verdicts'].items() if v == 'manual']
        head = f"  {a['id']} [{a['provenance']}, {a['provenanceKind']}]"
        print(head)
        if a['provenance'] == 'unknown':
            print(f"      PROVENANCE UNDETERMINED — {a['provenanceWhy']}")
            print(f"      {len(manuals)} section(s) cannot be verdicted: {', '.join(manuals)}")
        for k, why in faults:
            print(f"      FAULT  {k}: {why}")
        for u in a['unreadable']:
            print(f"      FAULT  unreadable key: {u}")
        if a['legacy']:
            print(f"      legacy key(s) still in use: "
                  + '; '.join(f"{k} (use {LEGACY.get(k, k)})" for k in a['legacy']))
    if tally['fault'] == 0 and unreadable_total == 0 and tally['manual'] == 0:
        print("  No faults. Every section either carried content or was skipped with a reason.")
    print("")

# --- html ----------------------------------------------------------------------------------

def esc(s):
    return html.escape(str(s if s is not None else ''))

V_ORDER = {'fault': 0, 'manual': 1, 'pass': 2, 'skipped': 3}

def unknown_cell(a, key, value):
    """Render a value that could not be read as `?`, never as 0 or a blank. The blank cell is
    what made the old report look complete while saying nothing."""
    if value is None:
        return '<span class="unknown" title="key not readable on this BRD">?</span>'
    return esc(value)

def entity_rows(a):
    out = []
    for e in a['raw']['domainEntities']:
        if not isinstance(e, dict):
            out.append(f'<tr><td colspan="5">{esc(e)}</td></tr>')
            continue
        attrs, akey = first_present(e, 'attributes', 'attributeCount')
        if akey == 'attributes':
            n_attr = len(as_list(attrs))
        elif akey == 'attributeCount':
            n_attr = attrs
        else:
            n_attr = None
        kind, _ = first_present(e, 'mendixType')
        if kind is None:
            persistent, pk = first_present(e, 'persistent')
            kind = ('PersistentEntity' if persistent else 'NonPersistentEntity') if pk else None
        assocs = []
        for x in as_list(e.get('associations')):
            if isinstance(x, dict):
                t, _ = first_present(x, 'target', 'to')
                assocs.append(t if t is not None else '?')
            else:
                assocs.append(str(x))
        out.append(
            '<tr>'
            f'<td class="mono">{esc(e.get("name"))}</td>'
            f'<td>{unknown_cell(a, "mendixType", kind)}</td>'
            f'<td class="num">{unknown_cell(a, "attributes", n_attr)}</td>'
            f'<td class="mono">{esc(", ".join(assocs)) or "&mdash;"}</td>'
            f'<td class="num">{len(as_list(e.get("businessRules")))}</td>'
            '</tr>')
    return ''.join(out)

def mf_rows(a):
    out = []
    for m in a['raw']['microflows']:
        if not isinstance(m, dict):
            continue
        purpose, _ = first_present(m, 'purpose', 'description')
        out.append('<tr>'
                   f'<td class="mono">{esc(m.get("name"))}</td>'
                   f'<td>{unknown_cell(a, "purpose", purpose)}</td>'
                   f'<td class="num">{len(as_list(m.get("validations")))}</td>'
                   '</tr>')
    return ''.join(out)

def page_rows(a):
    out = []
    for p in a['raw']['pages']:
        if not isinstance(p, dict):
            continue
        out.append('<tr>'
                   f'<td class="mono">{esc(p.get("name"))}</td>'
                   f'<td>{esc(p.get("purpose") or p.get("uiPattern") or "&mdash;")}</td>'
                   f'<td class="mono">{esc(p.get("dataContext") or "&mdash;")}</td>'
                   '</tr>')
    return ''.join(out)

def uc_cards(a):
    out = []
    for u in a['raw']['useCases']:
        if not isinstance(u, dict):
            out.append(f'<div class="uc">{esc(u)}</div>')
            continue
        screens, _ = alist(u, 'screens', 'screen')
        bits = []
        for lab, key in (('Actors', 'actors'), ('Preconditions', 'preconditions'),
                         ('Postconditions', 'postconditions')):
            vals = as_list(u.get(key))
            if vals:
                bits.append(f'<div class="ucf"><strong>{lab}:</strong> '
                            + esc('; '.join(str(x) for x in vals)) + '</div>')
        flow = as_list(u.get('mainFlow'))
        if flow:
            bits.append('<div class="ucf"><strong>Main flow:</strong><ol>'
                        + ''.join(f'<li>{esc(s)}</li>' for s in flow) + '</ol></div>')
        if screens:
            bits.append('<div class="ucf"><strong>Screens:</strong> <span class="mono">'
                        + esc(', '.join(str(s) for s in screens)) + '</span></div>')
        status = u.get('status') or u.get('reviewStatus')
        tag = f'<span class="tag">{esc(status)}</span>' if status else ''
        out.append(f'<div class="uc"><div class="uch"><span class="mono">{esc(u.get("id"))}</span> '
                   f'{esc(u.get("title"))} {tag}</div>{"".join(bits)}</div>')
    return ''.join(out)

def simple_rows(items, cols):
    out = []
    for it in items:
        if not isinstance(it, dict):
            out.append(f'<tr><td colspan="{len(cols)}">{esc(it)}</td></tr>')
            continue
        tds = []
        for aliases in cols:
            v, _ = first_present(it, *aliases)
            if isinstance(v, list):
                v = ', '.join(str(x) for x in v)
            tds.append(f'<td>{unknown_cell(None, aliases[0], v) if v is None else esc(v)}</td>')
        out.append('<tr>' + ''.join(tds) + '</tr>')
    return ''.join(out)

def verdict_chip(key, a):
    v, why = a['verdicts'][key]
    return f'<span class="v v-{v}" title="{esc(why)}">{v}</span>'

def section_block(a, key, label, body_html, note=''):
    v, why = a['verdicts'][key]
    n = len(a['raw'][key])
    head = (f'<h4>{esc(label)} <span class="v v-{v}">{v}</span>'
            f'<span class="cnt">{n}</span></h4>')
    if v == 'pass':
        return head + (note or '') + body_html
    # Never a bare 0: the reason IS the content of the section when it is empty.
    cls = 'why why-' + v
    return head + f'<p class="{cls}">{esc(why)}</p>'

body_sections = []
for a in analysed:
    prov_note = (f'<div class="prov prov-{a["provenance"]}">'
                 f'<strong>Provenance: {esc(a["provenance"])}</strong> '
                 f'<span class="pk">({esc(a["provenanceKind"])})</span>'
                 f'<span>{esc(a["provenanceWhy"])}</span></div>')

    unread = ''
    if a['unreadable']:
        unread = ('<div class="unread"><strong>Unreadable keys — '
                  f'{len(a["unreadable"])}</strong><ul>'
                  + ''.join(f'<li>{esc(u)}</li>' for u in a['unreadable'])
                  + '</ul><p>These are rendered as <span class="unknown">?</span> above, never '
                    'as 0. A key that no longer reads is schema drift, not an empty BRD.</p></div>')

    legacy = ''
    if a['legacy']:
        legacy = ('<div class="legacy"><strong>Legacy keys still in use</strong><ul>'
                  + ''.join(f'<li><code>{esc(k)}</code> → {esc(LEGACY.get(k, k))}</li>'
                            for k in a['legacy'])
                  + '</ul></div>')

    rlabel, rwhy = a['review']
    quality = (
        '<div class="quality">'
        '<div class="qs"><span class="ql">Code confidence</span>'
        f'<span class="qv c-{esc(a["confidence"] or "unstated")}">'
        f'{esc(a["confidence"] or "not stated")}</span>'
        '<span class="qn">gap-count heuristic (brd-generation.md: high=0, medium=1&ndash;3, '
        'low=4+). It measures the extractor, not the requirement.</span></div>'
        '<div class="qs"><span class="ql">Doc-KB corroboration</span>'
        f'<span class="qv d-{esc(a["docSignal"])}">{esc(a["docSignal"])}</span>'
        f'<span class="qn">{esc(a["docWhy"])}</span></div>'
        f'<div class="qs qr"><span class="ql">Review signal</span>'
        f'<span class="qv r-{esc(rlabel)}">{esc(rlabel)}</span>'
        f'<span class="qn">{esc(rwhy)}</span></div>'
        '</div>')

    blocks = [
        section_block(a, 'domainEntities', 'Domain entities',
            '<div class="scroll"><table><thead><tr><th>Name</th><th>Type</th>'
            '<th>Attributes</th><th>Associations</th><th>Rules</th></tr></thead><tbody>'
            + entity_rows(a) + '</tbody></table></div>'),
        section_block(a, 'microflows', 'Microflows / logic',
            '<div class="scroll"><table><thead><tr><th>Name</th><th>Purpose</th>'
            '<th>Validations</th></tr></thead><tbody>' + mf_rows(a) + '</tbody></table></div>'),
        section_block(a, 'pages', 'Pages',
            '<div class="scroll"><table><thead><tr><th>Name</th><th>Purpose</th>'
            '<th>Data context</th></tr></thead><tbody>' + page_rows(a) + '</tbody></table></div>'),
        section_block(a, 'useCases', 'Use cases', uc_cards(a)),
        section_block(a, 'businessRules', 'Business rules',
            '<div class="scroll"><table><thead><tr><th>ID</th><th>Rule</th>'
            '<th>Enforced by</th></tr></thead><tbody>'
            + simple_rows(a['raw']['businessRules'],
                          [('id',), ('title', 'rule', 'description'), ('enforcedBy',)])
            + '</tbody></table></div>'),
        section_block(a, 'dataRequirements', 'Data requirements',
            '<div class="scroll"><table><thead><tr><th>ID</th><th>Title</th><th>Entity</th>'
            '<th>Key fields</th></tr></thead><tbody>'
            + simple_rows(a['raw']['dataRequirements'],
                          [('id',), ('title',), ('entity',), ('keyFields',)])
            + '</tbody></table></div>'),
        section_block(a, 'integrations', 'Integrations',
            '<div class="scroll"><table><thead><tr><th>Name</th><th>Type</th>'
            '<th>Direction</th><th>Detail</th></tr></thead><tbody>'
            + simple_rows(a['raw']['integrations'],
                          [('name', 'system'), ('type',), ('direction',),
                           ('description', 'stubBehaviour', 'realTarget')])
            + '</tbody></table></div>'),
        section_block(a, 'hiddenRules', 'Hidden business rules',
            '<div class="scroll"><table><thead><tr><th>Microflow</th><th>Rule</th>'
            '<th>Risk</th></tr></thead><tbody>'
            + ''.join(f'<tr><td class="mono">{esc(h["microflow"])}</td><td>{esc(h["rule"])}</td>'
                      f'<td class="risk-{esc(h["risk"])}">{esc(h["risk"])}</td></tr>'
                      for h in a['raw']['hiddenRules'])
            + '</tbody></table></div>',
            note='<p class="note">Rules found inside extracted logic that the domain model does '
                 'not show. Derived from <code>microflows[].hiddenRules</code>.</p>'),
        section_block(a, 'openQuestions', 'Open questions',
            '<ul class="oq">'
            + ''.join('<li>' + esc(q.get('question') if isinstance(q, dict) else q)
                      + (f' <span class="tag">{esc(q.get("status"))}</span>'
                         if isinstance(q, dict) and q.get('status') else '')
                      + '</li>' for q in a['raw']['openQuestions'])
            + '</ul>'),
    ]

    chips = ''.join(f'<span class="chip">{esc(m)}</span>' for m in a['modules']) \
            or '<span class="chip chip-bad">no module named</span>'

    body_sections.append(
        f'<section class="brd" id="{esc(a["id"])}">'
        f'<h3><span class="mono">{esc(a["id"])}</span> {esc(a["title"])}</h3>'
        f'<div class="chips">{chips}</div>'
        + prov_note + quality + unread + legacy + ''.join(blocks) +
        f'<p class="src">{esc(a["path"])}</p>'
        '</section>')

stat = lambda val, lbl: (f'<div class="stat-card"><div class="val">{esc(val)}</div>'
                         f'<div class="lbl">{esc(lbl)}</div></div>')

prov_summary = ', '.join(f'{n} {p}' for p, n in sorted(prov_counts.items()))

page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Stage 2 — BRD report — {esc(os.path.basename(os.path.abspath(project)))}</title>
<style>
  /* Shared shell tokens, copied from toolkit-guide.html — every stage surface uses these so
     project artifacts read as one system. Once Stage 3 produces design/design-system.html,
     THAT file's tokens supersede these for anything generated afterwards. */
  :root {{
    --bg: #f8fafc;
    --surface: #ffffff;
    --ink: #1e293b;
    --ink-soft: #64748b;
    --ink-faint: #94a3b8;
    --line: #e2e8f0;
    --accent: #0f4c81;
    --pass-bg: #dcfce7;  --pass-ink: #166534;
    --fail-bg: #fee2e2;  --fail-ink: #991b1b;
    --warn-bg: #fef3c7;  --warn-ink: #92400e;
    --radius: 10px;
    --font: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    --mono: ui-monospace, 'SF Mono', Menlo, monospace;
  }}
  *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: var(--font); background: var(--bg); color: var(--ink); line-height: 1.55;
         padding: 40px 20px 80px; }}
  .wrap {{ max-width: 980px; margin: 0 auto; }}
  h1 {{ font-size: 28px; letter-spacing: -0.02em; }}
  h2 {{ font-size: 19px; margin: 48px 0 14px; letter-spacing: -0.01em; }}
  h3 {{ font-size: 17px; margin: 0 0 8px; }}
  h4 {{ font-size: 12px; text-transform: uppercase; letter-spacing: .07em; color: var(--ink-soft);
        margin: 24px 0 8px; display: flex; align-items: center; gap: 8px; }}
  p {{ margin: 8px 0; }}
  .lede {{ color: var(--ink-soft); font-size: 15px; max-width: 680px; margin-top: 10px; }}
  code {{ font-family: var(--mono); font-size: 0.88em; background: #eef2f7;
          border: 1px solid var(--line); border-radius: 4px; padding: 1px 5px; }}
  .mono {{ font-family: var(--mono); font-size: 12.5px; }}
  .num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  table {{ border-collapse: collapse; width: 100%; background: var(--surface);
           border: 1px solid var(--line); border-radius: var(--radius); overflow: hidden;
           font-size: 13.5px; }}
  th, td {{ text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--line);
            vertical-align: top; }}
  th {{ background: var(--ink); color: #e2e8f0; font-weight: 600; font-size: 12px; }}
  tr:last-child td {{ border-bottom: none; }}
  .scroll {{ overflow-x: auto; }}
  .stat-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
                gap: 12px; margin: 22px 0 8px; }}
  .stat-card {{ background: var(--surface); border: 1px solid var(--line);
                border-radius: var(--radius); padding: 14px; text-align: center; }}
  .stat-card .val {{ font-size: 24px; font-weight: 700; color: var(--accent); }}
  .stat-card .lbl {{ font-size: 12px; color: var(--ink-soft); }}
  .brd {{ background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius);
          padding: 22px 24px; margin-bottom: 22px; }}
  .chips {{ margin: 4px 0 12px; }}
  .chip {{ display: inline-block; font-family: var(--mono); font-size: 11px; background: #eef2f7;
           border: 1px solid var(--line); border-radius: 999px; padding: 2px 9px; margin-right: 6px; }}
  .chip-bad {{ background: var(--fail-bg); color: var(--fail-ink); border-color: var(--fail-ink); }}
  .v {{ display: inline-block; font-size: 10.5px; font-weight: 700; text-transform: uppercase;
        letter-spacing: .06em; padding: 1px 8px; border-radius: 999px; }}
  .v-pass {{ background: var(--pass-bg); color: var(--pass-ink); }}
  .v-fault {{ background: var(--fail-bg); color: var(--fail-ink); }}
  .v-skipped {{ background: #eef2f7; color: var(--ink-soft); }}
  .v-manual {{ background: var(--warn-bg); color: var(--warn-ink); }}
  .cnt {{ margin-left: auto; font-family: var(--mono); color: var(--ink-faint); }}
  .why {{ font-size: 13.5px; border-left: 3px solid var(--line); padding: 6px 12px;
          color: var(--ink-soft); background: #fbfcfe; }}
  .why-fault {{ border-left-color: var(--fail-ink); color: var(--fail-ink); background: var(--fail-bg); }}
  .why-manual {{ border-left-color: var(--warn-ink); color: var(--warn-ink); background: var(--warn-bg); }}
  .prov {{ font-size: 13px; border: 1px solid var(--line); border-left: 4px solid var(--accent);
           border-radius: 0 var(--radius) var(--radius) 0; padding: 8px 12px; margin-bottom: 12px; }}
  .prov span {{ display: block; color: var(--ink-soft); }}
  .prov .pk {{ display: inline; color: var(--ink-faint); }}
  .prov-unknown {{ border-left-color: var(--warn-ink); background: var(--warn-bg); }}
  .quality {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
              gap: 10px; margin-bottom: 6px; }}
  .qs {{ border: 1px solid var(--line); border-radius: var(--radius); padding: 10px 12px; }}
  .ql {{ display: block; font-size: 10.5px; text-transform: uppercase; letter-spacing: .07em;
         color: var(--ink-faint); }}
  .qv {{ display: inline-block; font-weight: 700; font-size: 14px; margin: 2px 0 4px; }}
  .c-low, .d-none, .r-uncorroborated {{ color: var(--fail-ink); }}
  .c-medium, .r-review-ready {{ color: var(--warn-ink); }}
  .c-high, .d-confirmed {{ color: var(--pass-ink); }}
  .qn {{ display: block; font-size: 12px; color: var(--ink-soft); }}
  .unread {{ background: var(--fail-bg); border: 1px solid var(--fail-ink);
             border-radius: var(--radius); padding: 10px 14px; margin: 12px 0; font-size: 13px;
             color: var(--fail-ink); }}
  .unread ul, .legacy ul {{ margin: 6px 0 0 18px; }}
  .unread p {{ margin-top: 8px; }}
  .legacy {{ background: var(--warn-bg); border: 1px solid var(--warn-ink);
             border-radius: var(--radius); padding: 10px 14px; margin: 12px 0; font-size: 13px;
             color: var(--warn-ink); }}
  .unknown {{ font-weight: 700; color: var(--fail-ink); }}
  .uc {{ border: 1px solid var(--line); border-radius: var(--radius); padding: 12px 14px;
         margin-bottom: 8px; }}
  .uch {{ font-weight: 600; margin-bottom: 6px; }}
  .ucf {{ font-size: 13px; color: var(--ink-soft); margin: 3px 0; }}
  .ucf ol {{ margin: 4px 0 0 20px; }}
  .tag {{ font-size: 11px; background: #eef2f7; border: 1px solid var(--line); border-radius: 999px;
          padding: 1px 8px; margin-left: 6px; color: var(--ink-soft); }}
  .oq {{ margin-left: 20px; font-size: 13.5px; }}
  .note {{ font-size: 12.5px; color: var(--ink-faint); }}
  .src {{ font-family: var(--mono); font-size: 11px; color: var(--ink-faint); margin-top: 16px; }}
  .risk-high {{ color: var(--fail-ink); font-weight: 700; }}
  .risk-medium {{ color: var(--warn-ink); font-weight: 700; }}
  .footer {{ margin-top: 56px; font-size: 12px; color: var(--ink-faint);
             border-top: 1px solid var(--line); padding-top: 14px; }}
</style>
</head>
<body>
<div class="wrap">
  <h1>Stage 2 — what the BRDs actually say</h1>
  <p class="lede">Rendered {esc(datetime.datetime.now().strftime('%Y-%m-%d'))} from
     {len(analysed)} BRD(s) in {len(kb_dirs)} knowledge-base director(ies) — whatever produced
     them. Every section carries a verdict, so a section that is empty because this kind of BRD
     has nothing to put there reads differently from one that is empty because something broke.</p>

  <div class="stat-grid">
    {stat(len(analysed), 'BRDs')}
    {stat(len(all_modules), 'Modules named')}
    {stat(len(all_actors), 'Actors')}
    {stat(totals['useCases'], 'Use cases')}
    {stat(totals['domainEntities'], 'Domain entities')}
    {stat(totals['microflows'], 'Microflows')}
    {stat(totals['pages'], 'Pages')}
    {stat(totals['businessRules'] + totals['dataRequirements'], 'Rules + data reqs')}
    {stat(totals['integrations'], 'Integrations')}
    {stat(totals['hiddenRules'], 'Hidden rules')}
    {stat(totals['openQuestions'], 'Open questions')}
  </div>

  <h2>Verdicts</h2>
  <p class="lede">{tally['pass']} pass &middot; {tally['fault']} fault &middot;
     {tally['skipped']} skipped &middot; {tally['manual']} manual — over {cells} section(s)
     ({len(analysed)} BRD &times; {len(SECTIONS)} sections). Provenance: {esc(prov_summary)}.
     Unreadable keys: {unreadable_total}.</p>
  <div class="scroll"><table>
    <thead><tr><th>BRD</th><th>Provenance</th>
    {''.join(f'<th>{esc(l.split(" / ")[0])}</th>' for _k, l in SECTIONS)}</tr></thead>
    <tbody>
    {''.join('<tr><td class="mono"><a href="#' + esc(a['id']) + '">' + esc(a['id']) + '</a></td>'
             + '<td>' + esc(a['provenance']) + '</td>'
             + ''.join('<td>' + verdict_chip(k, a) + '</td>' for k, _l in SECTIONS)
             + '</tr>' for a in analysed)}
    </tbody>
  </table></div>

  <h2>Per BRD</h2>
  {''.join(body_sections)}

  <div class="footer">
    Verdicts follow <code>skills/report-schema.md</code>:
    <strong>pass</strong> present and read &middot;
    <strong>fault</strong> expected for this provenance and absent &middot;
    <strong>skipped</strong> not applicable, reason given &middot;
    <strong>manual</strong> provenance undetermined, so no verdict is available.
    <code>fail</code> is not expressible here on purpose — this surface reports what the BRDs
    contain, never whether the content is correct. That judgement is
    <code>skills/brd-validation.md</code>'s, and the Stage 2 gate is
    <code>bin/gate-check.sh</code>'s.
    <br>Generated by <code>bin/brd-report.sh</code> — one renderer for every entry mode.
    BRDs are located by <code>bin/lib/discover-brds.sh</code>, which reads every knowledge-base
    directory, not the first one.
  </div>
</div>
</body>
</html>
"""

with open(html_out, 'w') as f:
    f.write(page)

if not quiet and not as_json:
    print(f"  report: {html_out}")
PY

exit $?
