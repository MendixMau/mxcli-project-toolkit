#!/bin/bash
# extraction-report.sh — the Stage 1 surface. ONE renderer, for knowledge bases of any provenance.
#
# WHY THIS EXISTS (2026-08-20). `gate-check.sh` check_stage_1 requires
# `<kb>/extraction-report.html`, and the only thing that wrote that file was
# `pipelines/*/pipeline/generate-report.js` — inside a pipeline that requirements-driven and
# greenfield projects never run. So a documents-only project could not pass its own Stage 1
# gate, no matter how complete its knowledge base was, while `conversion-runbook.md` promises
# the surface unconditionally for every entry mode. Same disease as `brd-report.sh` one stage
# later, same fix: the reader moves to `bin/` and stops caring what produced the input.
#
# The pipeline renderer also had the specific bug this file is built not to have. Its loader was
#
#     function readJson(name) { try { ... } catch (_) { return []; } }
#
# so a missing file, a half-written file and a genuinely empty extraction all rendered as `0`,
# and its coverage figure was `totalGaps === 0 ? 100 : ...` — which prints 100% for a knowledge
# base with nothing in it. A page that looked complete and said nothing.
#
# WHAT THIS IS NOT. It is not a gate and it is not the quality loop. `gate-check.sh` owns the
# Stage 1 gate; `extractor-quality-loop.md` owns the six scored dimensions and the ≥95%
# judgement, and nothing here scores anything. Per `skills-over-scripts.md` everything below is
# fact-fetching and arithmetic: counts found, against counts expected, from more than one place.
#
# THE TWO RULES IT KEEPS.
#
#   1. PROVENANCE DECIDES WHAT IS OWED. A documents knowledge base has no `entities.json` and
#      that is not a gap; a code-extracted one without `entities.json` means the merge did not
#      run. Under one renderer those must not look the same, so every section carries a
#      `report-schema.md` verdict:
#
#        pass      present and read (or a zero that two methods agree on)
#        fault     expected for this provenance and absent, unreadable, or contradicted
#        skipped   not applicable / optional for this provenance, WITH the reason printed
#        manual    cannot be told apart without a human, and nothing on disk answers it
#
#   2. NO UNCORROBORATED ZERO. An empty `entities.json` is only a measured zero if a second,
#      independent record agrees — the pre-merge `extracted/*.json` items of that type, or the
#      Construct Counts table in `reports/summary.md`. One method returning zero is `manual`,
#      never `pass`: "the extractor found none" and "the reader read the wrong file" produce the
#      identical `0`, and telling them apart is the whole job.
#
# `fail` is not expressible here, deliberately (report-schema.md `expressibleVerdicts`): this
# instrument reports what the knowledge base contains, never whether the content is correct.
#
# Malformed JSON is a FAULT ON THE PAGE, not an abort — unlike `brd-report.sh`, which exits 4.
# The difference is on purpose. A BRD that will not parse makes the Stage 2 surface meaningless,
# but an `extracted/screens.json` that will not parse is exactly the finding a Stage 1 reader
# needs to see rendered, next to the fourteen files that did parse.
#
# Usage:
#   extraction-report.sh <project-dir> [--html PATH] [--json] [--quiet]
#
#   One page per knowledge base, written to <kb>/extraction-report.html — the path the gate
#   looks for. --html overrides it, and is refused when the project has more than one knowledge
#   base, because one path cannot receive two pages and silently keeping the last one is how
#   `facts-lock.sh` came to report a clean result over 10% of a corpus (see lib/discover-brds.sh).
#
# exit 0 rendered (faults included — a fault is information, and the gate is gate-check's job)
#      2 usage   3 no knowledge base, or nothing in it to render (never a pass)
#
# Bash 3.2 + any Python 3 (resolved by lib/portable.sh, not assumed to be named `python3`).

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The one place that knows where a project's knowledge bases live. Sourced, never re-derived.
# shellcheck disable=SC1091
. "$HERE/lib/discover-brds.sh"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"

usage() {
  cat >&2 <<'USAGE'
usage: extraction-report.sh <project-dir> [--html PATH] [--json] [--quiet]

  Renders the Stage 1 surface from every knowledge base in the project, whatever produced it —
  a code-extraction pipeline (Path A), a document corpus per kb-generation.md (Path B), or both.

  --html PATH   where to write (default: <kb>/extraction-report.html, one per knowledge base;
                refused when the project has more than one knowledge base)
  --json        machine-readable summary on stdout instead of prose
  --quiet       render, say nothing

exit 0 rendered   2 usage   3 no knowledge base, or nothing in it
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
    *) echo "extraction-report: unknown option: $1" >&2; usage ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "extraction-report: not a directory: $PROJECT_DIR" >&2; exit 2; }

# Was: `command -v python3` in the scripts this one is modelled on — which succeeds on the
# Windows Store alias stub. require_py probes by running the interpreter.
require_py

KB_DIRS=$(discover_kbs "$PROJECT_DIR")
KB_COUNT=$(count_lines "$KB_DIRS")

if [ "$KB_COUNT" = "0" ]; then
  # An empty result set is never a pass (report-schema.md). Distinct exit code so no caller can
  # read "found nothing" as "nothing to find".
  echo "extraction-report: no knowledge base found under $PROJECT_DIR — nothing rendered." >&2
  echo "  looked in: analysis/*/knowledge-base, analysis/knowledge-base, knowledge-base" >&2
  echo "  Stage 1 has no surface until one exists. Migration: run the extraction pipeline." >&2
  echo "  Requirements-driven: build it from the document corpus per skills/kb-generation.md." >&2
  exit 3
fi

if [ -n "$HTML_OUT" ] && [ "$KB_COUNT" != "1" ]; then
  echo "extraction-report: --html takes one path, but this project has $KB_COUNT knowledge bases:" >&2
  printf '%s\n' "$KB_DIRS" | sed 's/^/    /' >&2
  echo "  Drop --html to write <kb>/extraction-report.html in each — that is where the gate looks." >&2
  exit 2
fi

KB_DIRS="$KB_DIRS" HTML_OUT="$HTML_OUT" AS_JSON="$AS_JSON" QUIET="$QUIET" \
PROJECT_DIR="$PROJECT_DIR" "$PY" <<'PY'
import json, os, re, sys, html, datetime

kb_dirs   = [d for d in os.environ['KB_DIRS'].splitlines() if d.strip()]
html_out  = os.environ['HTML_OUT'] or None
as_json   = os.environ['AS_JSON'] == '1'
quiet     = os.environ['QUIET'] == '1'
project   = os.environ['PROJECT_DIR']

# --- readers that distinguish "absent" from "empty" from "broken" --------------------------
#
# THE bug in the renderer this replaces was one line: `catch (_) { return []; }`. Three
# different facts collapsed into one empty array, and every consumer downstream printed `0`.
# So every read here returns a state, and the state is what the verdict is computed from.

ABSENT, EMPTY, OK, BROKEN = 'absent', 'empty', 'ok', 'broken'

def read_json_list(path):
    """-> (state, items, detail). `items` is only meaningful when state is ok/empty."""
    if not os.path.exists(path):
        return ABSENT, [], 'file does not exist'
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception as e:
        return BROKEN, [], f'{type(e).__name__}: {e}'
    if isinstance(data, dict) and isinstance(data.get('items'), list):
        data = data['items']          # extracted/*.json wrap their payload
    if not isinstance(data, list):
        return BROKEN, [], f'valid JSON but a {type(data).__name__}, not a list'
    return (OK if data else EMPTY), data, f'{len(data)} item(s)'

def read_text(path):
    if not os.path.exists(path):
        return ABSENT, '', 'file does not exist'
    try:
        with open(path, errors='replace') as fh:
            t = fh.read()
    except Exception as e:
        return BROKEN, '', f'{type(e).__name__}: {e}'
    return (OK if t.strip() else EMPTY), t, f'{len(t)} byte(s)'

def ls(d, pattern):
    if not os.path.isdir(d):
        return []
    rx = re.compile(pattern)
    return sorted(f for f in os.listdir(d) if rx.match(f))

# --- what a knowledge base is made of --------------------------------------------------------
#
# All three pipelines' mergers emit the same fifteen filenames into the knowledge-base root, so
# this list is NOT per-platform — it is the merger contract, and a fourth pipeline that keeps it
# renders here for free. `xtype` is the `item.type` the same construct carries in the pre-merge
# `extracted/*.json`, which is how the second opinion on a zero is obtained.

E, O, N = 'expected', 'optional', 'n/a'

# key,             file,                     xtype(s),                       label
CODE_SECTIONS = [
    ('entities',       'entities.json',          ('entity',),        'Domain entities',      E),
    ('logics',         'logics.json',            ('logic',),         'Logic (microflow candidates)', E),
    ('screens',        'screens.json',           ('screen',),        'Screens',              E),
    ('staticEntities', 'staticEntities.json',    ('staticEntity',),  'Static entities',      O),
    ('structures',     'structures.json',        ('structure',),     'Structures',           O),
    ('webBlocks',      'webBlocks.json',         ('webBlock',),      'Reusable blocks',      O),
    ('webFlows',       'webFlows.json',          ('webFlow',),       'Flows',                O),
    ('workflows',      'workflows.json',         ('workflow',),      'Workflows',            O),
    ('dataScreenActions', 'dataScreenActions.json', ('dataScreenAction',), 'Screen data actions', O),
    ('serviceApis',    'serviceApis.json',       ('serviceApi',),    'Service APIs',         O),
    ('extEntities',    'extEntities.json',       ('ext-entity',),    'External entities',    O),
    ('exceptions',     'exceptions.json',        ('exception',),     'Exception handlers',   O),
    ('timers',         'timers.json',            ('timer',),         'Timers',               O),
    ('roles',          'roles.json',             ('role',),          'Roles',                O),
    ('requirements',   'requirements.json',
        ('excel-sheet', 'docx', 'pdf', 'pptx'),                      'Documents read by the extractor', O),
]

# Path B, per document-discovery.md's "Output structure". These are files, not item arrays, so
# they are counted by existence and by line/entry, never parsed for constructs.
DOC_SECTIONS = [
    ('docKb',        'Document KB files',   E),   # share/KB_*.md
    ('docCanonical', 'Canonical KB.md',     E),   # share/KB.md
    ('discovery',    'Discovery manifest',  O),   # share/discovery-manifest.json
    ('reviewLater',  'Deferred files',      O),   # share/Review_Later.md
    ('extractionLog','Extraction log',      O),   # share/EXTRACTION_LOG.md
]

# `n/a` reasons, printed instead of a colour nobody can interpret.
NA = {
    'code': 'this knowledge base holds no extracted code — there is no merger output to read, '
            'and Stage 1 for a {p} source is a document corpus, not a construct inventory.',
    'doc':  'this knowledge base was produced by a code-extraction pipeline. Document KB files '
            'come from kb-generation.md (Path B), which a {p} source does not run.',
}

def expect_for(prov, base, family):
    """base is the section's own E/O; family is 'code' or 'doc'. Provenance can only downgrade
    a section to n/a — it never promotes an optional one to expected, because nothing on disk
    would justify calling an absence a finding."""
    if prov == 'unknown':
        return None            # -> manual. Nobody can say which of the two this is.
    if family == 'code' and prov == 'documents':
        return N
    if family == 'doc' and prov == 'code-extracted':
        return N
    return base

# --- per knowledge base -----------------------------------------------------------------------

def analyse(kb):
    a = {'path': kb, 'name': os.path.basename(os.path.dirname(kb)) or os.path.basename(kb),
         'sections': {}, 'faults': [], 'notes': []}

    share     = os.path.join(kb, 'share')
    extracted = os.path.join(kb, 'extracted')
    reports   = os.path.join(kb, 'reports')

    # -- second and third opinions, gathered before any verdict ---------------------------
    #
    # The pre-merge record. Counts here are PRE-deduplication, so extracted >= merged is normal
    # and the reverse is not: a merge cannot invent an item it never loaded.
    xcounts, xstate, xfiles = {}, ABSENT, []
    if os.path.isdir(extracted):
        xfiles = ls(extracted, r'.*\.json$')
        broke = []
        for f in xfiles:
            st, items, det = read_json_list(os.path.join(extracted, f))
            if st == BROKEN:
                broke.append(f'{f} ({det})')
                continue
            for it in items:
                if isinstance(it, dict) and isinstance(it.get('type'), str):
                    xcounts[it['type']] = xcounts.get(it['type'], 0) + 1
        if broke:
            xstate = BROKEN
            a['faults'].append('extracted/ is present but ' + str(len(broke)) +
                               ' file(s) would not parse: ' + '; '.join(broke) +
                               ' — the second opinion on every zero below is that much weaker.')
        else:
            xstate = OK if xfiles else EMPTY

    # `reports/summary.md` carries the merger's own Construct Counts table, written from the
    # SAME deduped list `_emit` writes the JSON from — so a disagreement is not a rounding
    # difference, it means one of the two is stale.
    scounts, sstate = {}, ABSENT
    sstate, stext, _d = read_text(os.path.join(reports, 'summary.md'))
    if sstate == OK:
        for line in stext.splitlines():
            m = re.match(r'^\|\s*([A-Za-z-]+)\s*\|\s*(\d+)\s*\|\s*$', line)
            if m:
                scounts[m.group(1)] = int(m.group(2))

    a['xcounts'], a['xstate'], a['xfileCount'] = xcounts, xstate, len(xfiles)
    a['scounts'], a['sstate'] = scounts, sstate

    # -- provenance ------------------------------------------------------------------------
    #
    # Read off the artifacts, not declared anywhere: a knowledge base has no header to declare
    # in. `unknown` is printed as unknown and blocks every verdict it touches — the guess is
    # what decides whether a missing entities.json is a fault or a non-event, and getting that
    # wrong in either direction is the bug this file exists to stop.
    code_marks = [f for _k, f, _x, _l, _e in CODE_SECTIONS if os.path.exists(os.path.join(kb, f))]
    if os.path.isdir(extracted):
        code_marks.append('extracted/')
    doc_marks = ls(share, r'KB.*\.md$')
    if os.path.exists(os.path.join(share, 'discovery-manifest.json')):
        doc_marks.append('discovery-manifest.json')

    if code_marks and doc_marks:
        prov, prov_why = 'mixed', (f'{len(code_marks)} merger artifact(s) and {len(doc_marks)} '
                                   f'document artifact(s) — both paths contributed')
    elif code_marks:
        prov, prov_why = 'code-extracted', (f'{len(code_marks)} merger artifact(s) present '
                                            f'({", ".join(sorted(code_marks)[:4])}…), no share/KB files')
    elif doc_marks:
        prov, prov_why = 'documents', (f'{len(doc_marks)} document artifact(s) under share/, '
                                       f'no merger output')
    else:
        prov, prov_why = 'unknown', ('no merger output and no share/KB files — nothing in this '
                                     'directory says what built it')
    a['provenance'], a['provenanceWhy'] = prov, prov_why

    # -- code sections -----------------------------------------------------------------------
    for key, fname, xtypes, label, base in CODE_SECTIONS:
        exp = expect_for(prov, base, 'code')
        state, items, detail = read_json_list(os.path.join(kb, fname))
        n = len(items)
        # Only a CLEAN extracted/ read is allowed to corroborate. A partially-parsed one would
        # contribute a 0 for the very type whose file was the one that would not parse, and that
        # 0 would then read as agreement — a false green built out of the failure itself.
        second = sum(xcounts.get(t, 0) for t in xtypes) if xstate == OK else None
        third  = sum(scounts[t] for t in xtypes if t in scounts) if scounts else None
        if third is not None and not any(t in scounts for t in xtypes):
            third = None

        sec = {'key': key, 'label': label, 'family': 'code', 'file': fname, 'state': state,
               'count': n if state in (OK, EMPTY) else None, 'items': items,
               'second': second, 'third': third, 'expect': exp}

        if state == BROKEN:
            sec['verdict'] = ('fault', f'{fname} is present but unreadable — {detail}. '
                                       f'Counted as nothing read, NOT as zero.')
        elif exp is None:
            sec['verdict'] = ('manual', 'provenance undetermined — whether this file should '
                                        'exist here needs a human, and nothing on disk says.')
        elif state == ABSENT:
            if exp == E:
                sec['verdict'] = ('fault', f'{fname} is absent. The merger writes it '
                                           f'unconditionally, so its absence means the merge did '
                                           f'not run or did not finish. This is a finding, not a zero.')
            elif exp == N:
                sec['verdict'] = ('skipped', NA['code'].format(p=prov))
            else:
                sec['verdict'] = ('skipped', f'optional — absent, and a {prov} knowledge base '
                                             f'does not owe it.')
        elif n:
            corr = []
            if second is not None and second < n:
                a['faults'].append(
                    f'{fname} holds {n} item(s) but the pre-merge extracted/ record carries only '
                    f'{second} of type {"/".join(xtypes)}. A merge cannot produce more than it '
                    f'loaded — one of the two is stale.')
            if third is not None and third != n:
                a['faults'].append(
                    f'{fname} holds {n} item(s); reports/summary.md says {third}. Both are '
                    f'written from the same deduped list in one merger run, so they disagree '
                    f'only if one of them is left over from an earlier run.')
            if second is not None:
                corr.append(f'extracted/ carries {second} pre-dedup')
            if third is not None:
                corr.append(f'summary.md says {third}')
            sec['verdict'] = ('pass', f'{n} present' +
                              (' (' + '; '.join(corr) + ')' if corr else ''))
        else:
            # The zero rule. One method is not a measurement.
            positive = [(lbl, v) for lbl, v in (('extracted/', second), ('summary.md', third))
                        if v is not None and v > 0]
            agree = [lbl for lbl, v in (('extracted/', second), ('summary.md', third)) if v == 0]
            if positive:
                sec['verdict'] = ('fault', f'{fname} is empty, but ' + ' and '.join(
                    f'{lbl} carries {v}' for lbl, v in positive) +
                    f' of type {"/".join(xtypes)}. The merge dropped them.')
            elif agree:
                sec['verdict'] = ('pass', 'zero, and ' + ' and '.join(agree) +
                                          ' agree(s) — a measured zero, not an unread file.')
            elif exp == E:
                sec['verdict'] = ('manual', f'{fname} is empty and nothing corroborates it — no '
                                            f'extracted/ record, no summary.md table. "The '
                                            f'extractor found none" and "the reader read the '
                                            f'wrong file" both look like this.')
            else:
                sec['verdict'] = ('skipped', 'empty and uncorroborated, but optional for a '
                                             f'{prov} knowledge base — recorded as unverified '
                                             f'rather than as a measured zero.')
        a['sections'][key] = sec

    # -- document sections ---------------------------------------------------------------------
    kb_files = [f for f in ls(share, r'KB_.*\.md$')]
    canon_state, _t, canon_detail = read_text(os.path.join(share, 'KB.md'))
    man_state, manifest, man_detail = read_json_list(os.path.join(share, 'discovery-manifest.json'))
    rl_state, _t, rl_detail = read_text(os.path.join(share, 'Review_Later.md'))
    log_state, _t, log_detail = read_text(os.path.join(share, 'EXTRACTION_LOG.md'))

    doc_state = {
        'docKb':         (OK if kb_files else (EMPTY if os.path.isdir(share) else ABSENT),
                          len(kb_files), f'{len(kb_files)} KB_*.md under share/'),
        'docCanonical':  (canon_state, 1 if canon_state == OK else 0, canon_detail),
        'discovery':     (man_state, len(manifest), man_detail),
        'reviewLater':   (rl_state, 1 if rl_state == OK else 0, rl_detail),
        'extractionLog': (log_state, 1 if log_state == OK else 0, log_detail),
    }
    HOWTO = {
        'docKb':         'One per approved source document (kb-generation.md).',
        'docCanonical':  'The canonical merge across all KB_*.md. brd-validation.md consumes '
                         'THIS file, not the individual ones.',
        'discovery':     'The mechanical scan record from document-discovery.md.',
        'reviewLater':   'Files the scan could not classify or could not read.',
        'extractionLog': 'Session diary from kb-generation.md.',
    }
    for key, label, base in DOC_SECTIONS:
        exp = expect_for(prov, base, 'doc')
        state, n, detail = doc_state[key]
        sec = {'key': key, 'label': label, 'family': 'doc', 'file': 'share/', 'state': state,
               'count': n, 'items': [], 'second': None, 'third': None, 'expect': exp,
               'detail': detail, 'howto': HOWTO[key]}
        if state == BROKEN:
            sec['verdict'] = ('fault', f'present but unreadable — {detail}. Counted as nothing '
                                       f'read, NOT as zero.')
        elif exp is None:
            sec['verdict'] = ('manual', 'provenance undetermined — nothing on disk says whether '
                                        'this knowledge base owes document artifacts.')
        elif exp == N:
            sec['verdict'] = ('skipped', NA['doc'].format(p=prov))
        elif state in (ABSENT, EMPTY) and exp == E:
            sec['verdict'] = ('fault', f'absent or empty, and a {prov} knowledge base is '
                                       f'expected to carry it. {HOWTO[key]} This is a finding.')
        elif state in (ABSENT, EMPTY):
            sec['verdict'] = ('skipped', f'optional for a {prov} knowledge base — absence here '
                                         f'is not a finding.')
        else:
            sec['verdict'] = ('pass', detail)
        a['sections'][key] = sec
    a['kbFiles'] = kb_files
    a['manifest'] = manifest if man_state in (OK, EMPTY) else []
    a['manifestState'] = man_state

    # -- BRDs: Stage 2's artifact, shown here only as a forward link -----------------------------
    a['brdCount'] = len(ls(os.path.join(kb, 'brd'), r'.*\.brd\.json$'))

    # -- measured dimensions ----------------------------------------------------------------
    #
    # NOT a score. `extractor-quality-loop.md` owns the six scored dimensions and the ≥95% gate,
    # and encoding that judgement in a shell script is exactly the skills-over-scripts.md failure
    # this toolkit keeps re-learning. Every figure below is a ratio whose denominator is on the
    # page, and every one of them is None — printed "not measured" — when the denominator is
    # missing. There is no 100% for an empty knowledge base here.
    items = [it for k, _f, _x, _l, _e in CODE_SECTIONS
             for it in a['sections'][k]['items'] if isinstance(it, dict)]
    links = sum(len(it.get('_links') or []) for it in items)
    gaps  = sum(len(it.get('_gaps') or []) for it in items)
    named = sum(1 for it in items if (it.get('module') or it.get('inferredModule')))

    def ratio(num, den):
        return None if not den else round(100.0 * num / den, 1)

    docs_expected = None
    if a['manifestState'] in (OK, EMPTY):
        docs_expected = sum(1 for m in a['manifest']
                            if isinstance(m, dict) and m.get('classification') == 'document')

    readable = [k for k, _f, _x, _l, _e in CODE_SECTIONS
                if a['sections'][k]['state'] in (OK, EMPTY)]
    zeros = [s for s in a['sections'].values()
             if s['family'] == 'code' and s['state'] == EMPTY]
    a['dims'] = {
        'mergerFilesReadable':  (len(readable), len(CODE_SECTIONS)),
        'itemsTotal':           len(items),
        'crossRefCoverage':     ratio(links, links + gaps),
        'crossRefLinks':        links,
        'crossRefGaps':         gaps,
        'moduleAttribution':    ratio(named, len(items)),
        'moduleAttributed':     named,
        'zerosTotal':           len(zeros),
        'zerosCorroborated':    sum(1 for s in zeros if s['verdict'][0] == 'pass'),
        'documentsExpected':    docs_expected,
        'documentsExtracted':   len(kb_files),
        'documentCoverage':     ratio(len(kb_files), docs_expected) if docs_expected else None,
    }

    modules = {}
    for it in items:
        m = it.get('module') or it.get('inferredModule') or '(unattributed)'
        modules[m] = modules.get(m, 0) + 1
    a['modules'] = sorted(modules.items(), key=lambda kv: (-kv[1], kv[0]))

    tally = {'pass': 0, 'fault': 0, 'skipped': 0, 'manual': 0}
    for s in a['sections'].values():
        tally[s['verdict'][0]] += 1
    a['tally'] = tally
    return a

analysed = [analyse(d) for d in kb_dirs]

# A knowledge base directory that exists but holds nothing recognisable is not a Stage 1 pass,
# and writing a page for it would make the gate green over an empty shelf. Refuse instead.
substantive = [a for a in analysed if a['provenance'] != 'unknown']
if not substantive:
    print(f"extraction-report: {len(analysed)} knowledge-base director(ies) found, none with "
          f"anything in them — nothing rendered.", file=sys.stderr)
    for a in analysed:
        print(f"    {a['path']} — {a['provenanceWhy']}", file=sys.stderr)
    print("  Stage 1 has no surface until the extraction (Path A) or the document KB (Path B) "
          "has produced something.", file=sys.stderr)
    sys.exit(3)

# --- stdout ------------------------------------------------------------------------------------

result = {
    'knowledgeBases': len(analysed),
    'rendered': [],
    'bases': [{
        'path': a['path'], 'provenance': a['provenance'], 'brdCount': a['brdCount'],
        'verdicts': a['tally'], 'discrepancies': a['faults'], 'dimensions': a['dims'],
        'sections': {k: s['verdict'][0] for k, s in a['sections'].items()},
    } for a in analysed],
}

# --- html -----------------------------------------------------------------------------------

def esc(s):
    return html.escape(str(s if s is not None else ''))

def pct(v):
    """A ratio that could not be computed prints as `not measured`. It never prints 100 —
    `totalGaps === 0 ? 100 : ...` in the renderer this replaces is why."""
    return '<span class="unknown" title="denominator missing">not measured</span>' \
        if v is None else f'{v}%'

def section_block(s):
    v, why = s['verdict']
    n = s['count']
    cnt = '?' if n is None else n
    head = (f'<h4>{esc(s["label"])} <span class="v v-{v}">{v}</span>'
            f'<span class="cnt">{cnt}</span></h4>')
    if v != 'pass':
        # Never a bare 0: the reason IS the content of the section when it is empty.
        return head + f'<p class="why why-{v}">{esc(why)}</p>'
    return head + f'<p class="why">{esc(why)}</p>' + (s.get('body') or '')

def item_rows(items, limit=200):
    out = []
    for it in items[:limit]:
        if not isinstance(it, dict):
            out.append(f'<tr><td colspan="4">{esc(it)}</td></tr>')
            continue
        mod = it.get('module') or it.get('inferredModule')
        out.append('<tr>'
                   f'<td class="mono">{esc(it.get("name") or it.get("linkId") or it.get("uniqueId"))}</td>'
                   + (f'<td class="mono">{esc(mod)}</td>' if mod else
                      '<td><span class="unknown">unattributed</span></td>')
                   + f'<td class="num">{len(it.get("_links") or [])}</td>'
                   f'<td class="num">{len(it.get("_gaps") or [])}</td>'
                   '</tr>')
    if len(items) > limit:
        out.append(f'<tr><td colspan="4" class="note">…and {len(items) - limit} more. '
                   f'The full list is the JSON this page was rendered from.</td></tr>')
    return ''.join(out)

pages = []
for a in analysed:
    if a['provenance'] == 'unknown':
        continue

    for k, _f, _x, _l, _e in CODE_SECTIONS:
        s = a['sections'][k]
        if s['verdict'][0] == 'pass' and s['items']:
            s['body'] = ('<div class="scroll"><table><thead><tr><th>Name</th><th>Module</th>'
                         '<th>Links</th><th>Gaps</th></tr></thead><tbody>'
                         + item_rows(s['items']) + '</tbody></table></div>')

    a['sections']['docKb']['body'] = (
        '<ul class="oq">' + ''.join(f'<li class="mono">{esc(f)}</li>' for f in a['kbFiles'])
        + '</ul>') if a['kbFiles'] else ''

    d = a['dims']
    disc = ''
    if a['faults']:
        disc = ('<div class="unread"><strong>Count discrepancies — '
                f'{len(a["faults"])}</strong><ul>'
                + ''.join(f'<li>{esc(x)}</li>' for x in a['faults'])
                + '</ul><p>Two records of the same extraction disagree. Neither number is used '
                  'as the answer above; both are printed so the stale one can be found.</p></div>')

    prov_note = (f'<div class="prov prov-{a["provenance"]}">'
                 f'<strong>Provenance: {esc(a["provenance"])}</strong> '
                 f'<span class="pk">(read from the artifacts on disk)</span>'
                 f'<span>{esc(a["provenanceWhy"])}</span></div>')

    # A dimension that this provenance cannot have is printed `n/a` with its reason, never as
    # `0 / 15`. A documents knowledge base scoring zero on "merger files readable" is not a poor
    # extraction, it is an extraction that was never supposed to happen — and a reader skimming
    # the cards would read the two identically.
    NA_DIM = '<span class="qv r-unranked">n/a</span>'
    code_na = ('this knowledge base was built from documents; no merger ran, so there is '
               'nothing here to measure.') if a['provenance'] == 'documents' else None
    doc_na  = ('this knowledge base was built by a code-extraction pipeline; document KB files '
               'come from Path B, which it does not run.') \
              if a['provenance'] == 'code-extracted' else None

    def card(label, value_html, note, na_reason=None):
        return ('<div class="qs">'
                f'<span class="ql">{label}</span>'
                + (NA_DIM if na_reason else value_html)
                + f'<span class="qn">{na_reason or note}</span></div>')

    dims = (
        '<div class="quality">'
        + card('Merger files readable',
               f'<span class="qv">{d["mergerFilesReadable"][0]} / {d["mergerFilesReadable"][1]}</span>',
               'The merger writes all of them on every run, so this is out of 15 whether or not '
               'the source had any of a given construct. Missing or unparseable ones are faults '
               'above, never 0s.', code_na)
        + card('Cross-reference coverage', f'<span class="qv">{pct(d["crossRefCoverage"])}</span>',
               f'{d["crossRefLinks"]} link(s) against {d["crossRefGaps"]} gap(s) over '
               f'{d["itemsTotal"]} item(s). No items means no denominator, so no figure.', code_na)
        + card('Module attribution', f'<span class="qv">{pct(d["moduleAttribution"])}</span>',
               f'{d["moduleAttributed"]} of {d["itemsTotal"]} item(s) name a module. The rest land '
               f'in <code>(unattributed)</code> and cannot be placed at Stage 3.', code_na)
        + card('Corroborated zeros',
               f'<span class="qv">{d["zerosCorroborated"]} / {d["zerosTotal"]}</span>',
               'Empty sections a second record agrees with. The remainder are <strong>manual</strong> '
               'above — one method returning zero is not a measurement.', code_na)
        + card('Documents extracted',
               f'<span class="qv">{d["documentsExtracted"]}'
               + (f' / {d["documentsExpected"]}' if d['documentsExpected'] is not None else '')
               + '</span>',
               'KB_*.md files against documents classified `document` in discovery-manifest.json.'
               if d['documentsExpected'] is not None else
               'No discovery-manifest.json, so there is no expected count to divide by — the '
               'number on the left is a count, not a coverage.', doc_na)
        + card('Overall score', '<span class="qv r-unranked">not computed</span>',
               'Deliberately. The six scored dimensions and the &ge;95% threshold are '
               '<code>skills/extractor-quality-loop.md</code>&rsquo;s judgement; a composite '
               'invented here would be a number with no skill behind it.')
        + '</div>')

    mod_table = ('<div class="scroll"><table><thead><tr><th>Module</th><th>Items</th></tr></thead>'
                 '<tbody>' + ''.join(
                     f'<tr><td class="mono {"unknown" if m == "(unattributed)" else ""}">{esc(m)}</td>'
                     f'<td class="num">{n}</td></tr>' for m, n in a['modules'])
                 + '</tbody></table></div>') if a['modules'] else \
                '<p class="why why-skipped">No extracted items carry a module, because this ' \
                'knowledge base has no extracted items. Not a zero — a different shape of input.</p>'

    # Same rule as the dimension cards, one level louder: a headline number is the part a reader
    # takes away, so `Extracted items 0` on a documents knowledge base would be the single most
    # misleading thing on the page. A count this provenance cannot produce reads `n/a`.
    def stat(val, lbl, na=None):
        v = ('<div class="val" style="color:var(--ink-faint)" title="' + esc(na) + '">n/a</div>'
             if na else f'<div class="val">{esc(val)}</div>')
        return f'<div class="stat-card">{v}<div class="lbl">{esc(lbl)}</div></div>'
    t = a['tally']

    code_blocks = ''.join(section_block(a['sections'][k]) for k, _f, _x, _l, _e in CODE_SECTIONS)
    doc_blocks  = ''.join(section_block(a['sections'][k]) for k, _l, _e in DOC_SECTIONS)

    body = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Stage 1 — extraction report — {esc(a['name'])}</title>
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
  .r-unranked {{ color: var(--ink-faint); }}
  .qn {{ display: block; font-size: 12px; color: var(--ink-soft); }}
  .unread {{ background: var(--fail-bg); border: 1px solid var(--fail-ink);
             border-radius: var(--radius); padding: 10px 14px; margin: 12px 0; font-size: 13px;
             color: var(--fail-ink); }}
  .unread ul {{ margin: 6px 0 0 18px; }}
  .unread p {{ margin-top: 8px; }}
  .unknown {{ font-weight: 700; color: var(--fail-ink); }}
  .oq {{ margin-left: 20px; font-size: 13.5px; }}
  .note {{ font-size: 12.5px; color: var(--ink-faint); }}
  .src {{ font-family: var(--mono); font-size: 11px; color: var(--ink-faint); margin-top: 16px; }}
  .footer {{ margin-top: 56px; font-size: 12px; color: var(--ink-faint);
             border-top: 1px solid var(--line); padding-top: 14px; }}
</style>
</head>
<body>
<div class="wrap">
  <h1>Stage 1 — what the extraction actually produced</h1>
  <p class="lede">Rendered {esc(datetime.datetime.now().strftime('%Y-%m-%d'))} from
     <span class="mono">{esc(a['path'])}</span> — whatever built it. Every section carries a
     verdict, so a section that is empty because this kind of source has nothing to put there
     reads differently from one that is empty because something broke. No zero on this page is
     printed unless a second record agrees with it.</p>

  {prov_note}

  <div class="stat-grid">
    {stat(d['itemsTotal'], 'Extracted items', code_na)}
    {stat(len(a['modules']), 'Modules seen', code_na)}
    {stat(len(a['kbFiles']), 'Document KB files', doc_na)}
    {stat(a['brdCount'], 'BRDs (Stage 2)')}
    {stat(t['pass'], 'pass')}
    {stat(t['fault'], 'fault')}
    {stat(t['manual'], 'manual')}
    {stat(t['skipped'], 'skipped')}
  </div>

  {disc}

  <h2>Measured dimensions</h2>
  <p class="lede">Ratios, each with its denominator printed. Where the denominator is missing the
     figure reads <em>not measured</em> — it is never rounded up to a full bar.</p>
  {dims}

  <h2>Extracted constructs</h2>
  {code_blocks}

  <h2>Document knowledge base</h2>
  {doc_blocks}

  <h2>Items by module</h2>
  <p class="lede">Where Stage 3 will have to place things. <code>(unattributed)</code> is the
     bucket that has to be resolved by hand before <code>modularize-domain.md</code> can run.</p>
  {mod_table}

  <div class="footer">
    Verdicts follow <code>skills/report-schema.md</code>:
    <strong>pass</strong> present and read, or a zero two records agree on &middot;
    <strong>fault</strong> expected here and absent, unreadable, or contradicted &middot;
    <strong>skipped</strong> not applicable to this provenance, reason given &middot;
    <strong>manual</strong> nothing on disk can settle it.
    <code>fail</code> is not expressible here on purpose — this surface reports what the
    knowledge base contains, never whether the content is correct. That judgement is
    <code>skills/extractor-quality-loop.md</code>'s, and the Stage 1 gate is
    <code>bin/gate-check.sh</code>'s.
    <br>Generated by <code>bin/extraction-report.sh</code> — one renderer for every entry mode.
    Knowledge bases are located by <code>bin/lib/discover-brds.sh</code>, which reads every one
    of them, not the first.
  </div>
</div>
</body>
</html>
"""

    out = html_out or os.path.join(a['path'], 'extraction-report.html')
    try:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        with open(out, 'w') as f:
            f.write(body)
        pages.append(out)
    except Exception as e:
        print(f"extraction-report: could not write {out}: {e}", file=sys.stderr)

result['rendered'] = pages

if as_json:
    print(json.dumps(result, indent=2))
elif not quiet:
    print(f"Extraction report: {len(analysed)} knowledge base(s)")
    for a in analysed:
        t = a['tally']
        print(f"  {a['path']} [{a['provenance']}]")
        if a['provenance'] == 'unknown':
            print(f"      SKIPPED — {a['provenanceWhy']}")
            continue
        print(f"      sections: {t['pass']} pass, {t['fault']} fault, {t['skipped']} skipped, "
              f"{t['manual']} manual")
        for s in a['sections'].values():
            if s['verdict'][0] == 'fault':
                print(f"      FAULT  {s['key']}: {s['verdict'][1]}")
        for s in a['sections'].values():
            if s['verdict'][0] == 'manual':
                print(f"      MANUAL {s['key']}: {s['verdict'][1]}")
        for x in a['faults']:
            print(f"      FAULT  {x}")
        d = a['dims']
        print(f"      zeros corroborated: {d['zerosCorroborated']}/{d['zerosTotal']}; "
              f"module attribution: "
              f"{'not measured' if d['moduleAttribution'] is None else str(d['moduleAttribution']) + '%'}")
    for p in pages:
        print(f"  report: {p}")
PY

exit $?
