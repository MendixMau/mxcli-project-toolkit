#!/bin/bash
# source-ledger.sh — was every source file actually consumed, and by what?
#
# WHY THIS EXISTS (2026-09-02, a VBA-to-Mendix migration). The Stage P intake asked exactly
# the right question — "documents outside the source folders not yet accounted for?" — and
# noticed, correctly, that a .pptx was a new artifact type. It closed the question with:
#
#     "the .pptx is already inside source/ and was already used as triage input by the
#      Group A–D triage pass — nothing additional exists"
#
# That claim was false. grep across every analysis, architecture and docs file found zero
# references to the deck outside one inventory line. The triage never opened it. Once the
# question was marked answered, the deck was "accounted for" and nothing downstream had a
# reason to look again; two months of BRDs, blueprint, build plan and module briefs were built
# on the VBA alone, while a 25-slide functional description with 22 diagrams — the only place
# the workflow engine's semantics were written down — sat in the folder.
#
# The intake caught the risk and discharged it with the one kind of answer that cannot be
# trusted: a claim about another document's contents, made without reading that document.
# This script makes that claim mechanical. For every row of the Stage 0 inventory
# (analysis/source-sufficiency.json, EVERY file under the source root — see
# bin/lib/source-inventory.py) it wants a DISPOSITION:
#
#   extracted   → an artifact path that exists, is non-empty, and NAMES the source file, plus
#                 EVIDENCE: one specific finding that came out of the file and where it landed.
#                 A mention is not a reading (post-mortem 2026-09-02, Failure 3: two mechanical
#                 coverage counts, 45/47 and 47/47, both junk). The grep is the floor that
#                 catches "never opened"; the evidence line is the hand-assigned verdict.
#                 "The triage already used it" is checked by grepping the triage for the
#                 file's name. Zero hits is a FAULT, not a pass. For a container with
#                 embedded media (a deck's 22 diagrams) the disposition must also say how
#                 many of those images were read; text-only is not the file.
#   waived      → a register line, written by a person with a reason:
#                     bin/gate-check.sh <project> --waive source/<rel> --reason "..."
#                 (one waiver vocabulary — the same flag that waives stages and obligations)
#   sensitive   → logged by path, never read (document-discovery.md's rule)
#   superseded  → by a newer version that IS in the inventory
#
# and it checks DRIFT: a file on disk under the source root that has no inventory row — the
# exact state of a project someone just dropped new sources into — is reported by name.
#
# WHAT IT IS NOT. It does not judge whether an extraction was any good. It fetches one fact
# per file — is there a disposition, does the artifact it names carry the file — and prints
# it. Quality is the extractor-quality-loop's business (skills-over-scripts.md). It is an
# instrument: PENDING (nobody said), FAULT (somebody said and it does not hold up), never an
# opinion about content.
#
# WHERE IT BITES. Sourced into bin/gate-check.sh: BLOCKS the Stage 1 and Stage 2 gates while
# any row is PENDING/FAULT or any file is un-inventoried. Stage 0 only advises — the
# inventory is Stage 0's output, and a gate must never block the action that resolves it.
# A project with no rubric at all but files under sources/ or source/ is "N files on disk,
# none inventoried" — that is exactly the un-inventoried case, and it blocks. A project with
# neither is nothing-to-check and does not.
#
# Usage:
#   source-ledger.sh check  <project-dir> [--register PATH] [--json] [--quiet]
#   source-ledger.sh report <project-dir> [--register PATH] [--html PATH]
#   source-ledger.sh mark   <project-dir> <rel-path-or-glob> --artifact <project-relative path>
#                           --evidence "<one finding that came out of the file, and where it landed>"
#                           [--media N | --media-waived "why"] [--pages N | --pages-waived "why"]
#                           [--by WHO] [--state extracted|sensitive|superseded]
#                           [--superseded-by <rel>]
#
# Exit (check/report): 0 every row accounted for and nothing un-inventoried · 1 something owed
#   (PENDING / FAULT / drift / missing) · 2 usage · 3 nothing to check (no rubric, no sources)
#
# Bash 3.2 + any Python 3 (bin/lib/portable.sh). Read-only except `mark`, which writes one
# disposition into analysis/source-sufficiency.json.
#
# FIELD RUN (2026-09-02, the VBA migration that motivated it — 96 files: 95 VBA .cls exports + one functional-description deck):
#   - init found the deck (allowlist never did): 5.2 MB, 25 slides, 22 embedded images.
#   - the intake's own claim, replayed as a disposition (deck → the triage file): FAULT,
#     "never names the deck".
#   - the first extraction pass as it was actually made (--pages 25 --media 3): FAULT,
#     "22 embedded image(s) inside, 3 accounted for" — the second pass (all 22) passes.
#   - the 95 .cls under a pattern disposition against knowledge-base/: first measured as 33
#     modules "named in NO analysis file". 18 of those were THIS instrument's bug — bytes.lower()
#     is ASCII-only, so every Ä/Ü/ü filename never matched (found by the unattended rerun, which
#     reported the same 18 against its own KB). After casefolding text: 81 name-verified, 15
#     modules genuinely named nowhere, and those 15 report FAULT — the Stage 1 gate on the real
#     project is BLOCKED on them, which is the honest verdict (post-mortem Failure 3).
# Fixture: tests/wave2/test-source-ledger.sh (the same shape, 36 assertions).

set -u

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

CMD="${1:-}"
PROJECT_DIR="${2:-}"
shift 2 2>/dev/null || true

usage() {
  cat >&2 <<'USAGE'
usage: source-ledger.sh <check|report|mark> <project-dir> [options]

  check   [--register PATH] [--json] [--quiet]   one verdict per inventory row + drift
  report  [--register PATH] [--html PATH]        same, rendered to analysis/source-ledger.html
  mark    <rel-path-or-glob> --artifact <path> --evidence "<finding → where>" [--media N | --media-waived "why"]
          [--pages N | --pages-waived "why"] [--by WHO] [--state extracted|sensitive|superseded] [--superseded-by <rel>]

  To waive a file (deliberately not extracted), write the decision where every other waiver
  lives:   bin/gate-check.sh <project-dir> --waive source/<rel> --reason "..."

exit 0 all accounted for · 1 something owed · 2 usage · 3 nothing to check
USAGE
  exit 2
}

case "$CMD" in check|report|mark) ;; *) usage ;; esac
[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "source-ledger: not a directory: $PROJECT_DIR" >&2; exit 2; }

REGISTER=""; HTML_OUT=""; AS_JSON=0; QUIET=0
MARK_TARGET=""; MARK_ARTIFACT=""; MARK_MEDIA=""; MARK_MEDIA_WAIVED=""; MARK_PAGES=""; MARK_PAGES_WAIVED=""; MARK_BY=""; MARK_STATE="extracted"; MARK_SUPER=""; MARK_EVIDENCE=""
if [ "$CMD" = "mark" ]; then
  MARK_TARGET="${1:-}"; shift || true
  [ -n "$MARK_TARGET" ] || usage
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --register)      REGISTER="${2:-}"; shift 2 ;;
    --html)          HTML_OUT="${2:-}"; shift 2 ;;
    --json)          AS_JSON=1; shift ;;
    --quiet)         QUIET=1; shift ;;
    --artifact)      MARK_ARTIFACT="${2:-}"; shift 2 ;;
    --media)         MARK_MEDIA="${2:-}"; shift 2 ;;
    --media-waived)  MARK_MEDIA_WAIVED="${2:-}"; shift 2 ;;
    --pages)         MARK_PAGES="${2:-}"; shift 2 ;;
    --pages-waived)  MARK_PAGES_WAIVED="${2:-}"; shift 2 ;;
    --evidence)      MARK_EVIDENCE="${2:-}"; shift 2 ;;
    --by)            MARK_BY="${2:-}"; shift 2 ;;
    --state)         MARK_STATE="${2:-}"; shift 2 ;;
    --superseded-by) MARK_SUPER="${2:-}"; shift 2 ;;
    -h|--help)       usage ;;
    *) echo "source-ledger: unknown option: $1" >&2; usage ;;
  esac
done

RUBRIC="$PROJECT_DIR/analysis/source-sufficiency.json"
[ "$CMD" = "report" ] && [ -z "$HTML_OUT" ] && HTML_OUT="$PROJECT_DIR/analysis/source-ledger.html"
INVENTORY_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/source-inventory.py"
[ -f "$INVENTORY_PY" ] || { echo "source-ledger: $INVENTORY_PY missing — cannot enumerate the corpus" >&2; exit 2; }

require_py

# The register, when not given: the same candidates gate-check.sh resolves, in the same order
# of preference (nested analysis/<name>/PROJECT*.md is the live one on multi-source projects).
if [ -z "$REGISTER" ]; then
  for cand in "$PROJECT_DIR"/analysis/*/PROJECT*.md "$PROJECT_DIR"/PROJECT*.md; do
    [ -f "$cand" ] && { REGISTER="$cand"; break; }
  done
fi

# --- mark ---------------------------------------------------------------------------------

if [ "$CMD" = "mark" ]; then
  [ -f "$RUBRIC" ] || { echo "source-ledger: no inventory at $RUBRIC — run bin/source-sufficiency.sh init first" >&2; exit 3; }
  case "$MARK_STATE" in extracted|sensitive|superseded) ;; *) echo "source-ledger: --state must be extracted|sensitive|superseded (a waiver is a register line, see --help)" >&2; exit 2 ;; esac
  if [ "$MARK_STATE" = "extracted" ] && [ -z "$MARK_ARTIFACT" ]; then
    echo "source-ledger: mark ... --artifact <path> is required: which artifact carries what was extracted?" >&2; exit 2
  fi
  if [ "$MARK_STATE" = "extracted" ] && [ -z "$MARK_EVIDENCE" ]; then
    echo "source-ledger: mark ... --evidence \"<a specific finding this file yielded, with where it landed>\" is required." >&2
    echo "  A mention is not a reading (post-mortem 2026-09-02, Failure 3). Name one thing that came OUT of the file:" >&2
    echo "    --evidence \"slides 18-20: WFAM X/M/E semantics → KB.md §Forwarding\"" >&2
    echo "    --evidence \"WorkflowWeiterLeiten + PflichtfelderPrüfen → procedures.json rows 41-58\"" >&2
    echo "  For a glob covering an extractor's whole input: --evidence \"modules.json lists each file by name\"" >&2
    exit 2
  fi
  if [ "$MARK_STATE" = "superseded" ] && [ -z "$MARK_SUPER" ]; then
    echo "source-ledger: --state superseded needs --superseded-by <rel> (the newer file, which must be in the inventory)" >&2; exit 2
  fi
  RUBRIC="$RUBRIC" T="$MARK_TARGET" A="$MARK_ARTIFACT" M="$MARK_MEDIA" MW="$MARK_MEDIA_WAIVED" PG="$MARK_PAGES" PW="$MARK_PAGES_WAIVED" EV="$MARK_EVIDENCE" \
  BY="$MARK_BY" ST="$MARK_STATE" SUP="$MARK_SUPER" "$PY" <<'PY'
import json, os, sys, datetime, fnmatch
rubric = os.environ['RUBRIC']
doc = json.load(open(rubric))
inv = doc.get('inventory')
if inv is None:
    print("source-ledger: this rubric predates the inventory pass; delete it and re-init", file=sys.stderr); sys.exit(4)
t = os.environ['T'].replace(os.sep, '/')
is_glob = any(c in t for c in '*?[')
rels = [r.get('rel') or os.path.basename(r.get('path') or '') for r in inv]
hits = [r for r in rels if (fnmatch.fnmatch(r, t) if is_glob else (r == t or os.path.basename(r) == t))]
if not hits:
    print(f"source-ledger: '{t}' matches no inventory row. Rows: {', '.join(rels[:15])}{' ...' if len(rels) > 15 else ''}", file=sys.stderr)
    print("  (a file not in the inventory is drift — run bin/source-sufficiency.sh init <project> --refresh)", file=sys.stderr)
    sys.exit(2)
d = {('pattern' if is_glob else 'path'): t, 'state': os.environ['ST'],
     'by': os.environ['BY'] or None, 'date': datetime.date.today().isoformat()}
if os.environ['A']: d['artifact'] = os.environ['A']
if os.environ['EV']: d['evidence'] = os.environ['EV']
if os.environ['M']:
    try: d['media'] = int(os.environ['M'])
    except ValueError: print("source-ledger: --media takes a count", file=sys.stderr); sys.exit(2)
if os.environ['MW']: d['mediaWaived'] = os.environ['MW']
if os.environ['PG']:
    try: d['pages'] = int(os.environ['PG'])
    except ValueError: print("source-ledger: --pages takes a count", file=sys.stderr); sys.exit(2)
if os.environ['PW']: d['pagesWaived'] = os.environ['PW']
if os.environ['SUP']: d['supersededBy'] = os.environ['SUP']
disp = doc.setdefault('dispositions', [])
# One disposition per target: re-marking replaces, so a corrected artifact path does not
# leave the wrong one behind to be matched first.
disp[:] = [x for x in disp if (x.get('pattern') or x.get('path')) != t]
disp.append(d)
json.dump(doc, open(rubric, 'w'), indent=2); open(rubric, 'a').write("\n")
print(f"source-ledger: marked {len(hits)} row(s) {d['state']} ← {t}" + (f" → {d.get('artifact')}" if d.get('artifact') else ''))
print("  verify it holds: bin/source-ledger.sh check <project-dir>")
PY
  exit $?
fi

# --- check / report -----------------------------------------------------------------------

RUBRIC="$RUBRIC" PROJECT_DIR="$PROJECT_DIR" REGISTER="$REGISTER" HTML_OUT="$HTML_OUT" \
AS_JSON="$AS_JSON" QUIET="$QUIET" INVENTORY_PY="$INVENTORY_PY" "$PY" <<'PY'
import json, os, sys, re, fnmatch, subprocess, html, datetime, unicodedata

rubric   = os.environ['RUBRIC']
project  = os.path.abspath(os.environ['PROJECT_DIR'])
register = os.environ['REGISTER']
html_out = os.environ['HTML_OUT']
as_json  = os.environ['AS_JSON'] == '1'
quiet    = os.environ['QUIET'] == '1'
inv_py   = os.environ['INVENTORY_PY']

def enumerate_root(root):
    r = subprocess.run([sys.executable, inv_py, 'enumerate', root], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()]

def emit(result, rc):
    if as_json:
        print(json.dumps(result, indent=2))
    sys.exit(rc)

# --- no rubric: is there a corpus nobody listed? ------------------------------------------
if not os.path.exists(rubric):
    probe = None
    for cand in ('sources', 'source'):
        p = os.path.join(project, cand)
        if os.path.isdir(p):
            files = enumerate_root(p) or []
            if files:
                probe = (p, files); break
    if probe:
        p, files = probe
        msg = (f"{len(files)} file(s) under {os.path.relpath(p, project)}/ and no inventory — "
               f"nobody has listed the corpus. Run: bin/source-sufficiency.sh init <project-dir>")
        if not as_json and not quiet:
            print(f"Source ledger: FAIL — {msg}")
            for e in files[:20]: print(f"    not inventoried: {e['rel']}")
            if len(files) > 20: print(f"    ... and {len(files) - 20} more")
        emit({'status': 'FAIL', 'note': msg, 'counts': {'total': 0, 'drift': len(files)},
              'drift': [e['rel'] for e in files]}, 1)
    msg = "no inventory and no sources/ or source/ folder with files — nothing to check"
    if not as_json and not quiet: print(f"Source ledger: NOT CHECKED — {msg}")
    emit({'status': 'MANUAL', 'note': msg}, 3)

try:
    doc = json.load(open(rubric))
except Exception as e:  # noqa: BLE001
    msg = f"{rubric} is not valid JSON: {e}"
    if not as_json: print(f"Source ledger: FAULT — {msg}", file=sys.stderr)
    emit({'status': 'FAIL', 'note': msg}, 1)

inv = doc.get('inventory')
if inv is None:
    msg = ("rubric predates the inventory pass — no per-file rows to account for. Delete it and "
           "re-init (bin/source-sufficiency.sh init) to get the two-pass form")
    if not as_json and not quiet: print(f"Source ledger: NOT CHECKED — {msg}")
    emit({'status': 'MANUAL', 'note': msg}, 3)

root = doc.get('sourceRoot') or ''
if root and not os.path.isabs(root):
    root = os.path.join(project, root)

# --- register waivers: "Waived source <rel-or-basename>: reason" ---------------------------
waivers = {}
if register and os.path.exists(register):
    incomment = False
    for line in open(register, encoding='utf-8', errors='replace'):
        if '<!--' in line: incomment = True
        if incomment:
            if '-->' in line: incomment = False
            continue
        l = re.sub(r'^[ \t>*_-]+', '', line.rstrip('\n')).replace('*', '')
        m = re.match(r'(?i)^waived source\s+(.+?)\s*:\s*(.*)$', l)
        if m:
            waivers[m.group(1).strip().replace(os.sep, '/').lower()] = m.group(2).strip()

def waiver_for(rel):
    rel_l = rel.lower()
    base_l = os.path.basename(rel).lower()
    for key, reason in waivers.items():
        if key in (rel_l, base_l) or fnmatch.fnmatch(rel_l, key):
            return reason
    return None

# --- dispositions ------------------------------------------------------------------------
disps = doc.get('dispositions') or []
rels_in_inventory = {(r.get('rel') or os.path.basename(r.get('path') or '')) for r in inv}

def disposition_for(rel):
    base = os.path.basename(rel)
    # exact path first, then basename, then globs — a specific claim beats a sweeping one
    for d in disps:
        if d.get('path') and d['path'].replace(os.sep, '/') in (rel, base):
            return d, False
    for d in disps:
        if d.get('pattern') and fnmatch.fnmatch(rel, d['pattern']):
            return d, True
    return None, False

NAME_CACHE = {}
def artifact_names(artifact_rel, needle):
    """Does the artifact (file or directory) mention the source file's name? Case-insensitive,
    basename with and without extension — a triage that writes 'Funktionsbeschreibung' without
    '.pptx' still counts. Returns (exists, nonempty, hits) where hits is the number of lines
    naming the file across the artifact. ONE hit is what an inventory line produces ("the corpus
    holds 95 .cls and 1 .pptx"); that is a mention, not a reading, and the row's note prints the
    count so a reviewer can tell the two apart — the script cannot, and does not pretend to.
    Field measurement, 2026-09-02: the triage that "materially shaped" a project named the
    deck on exactly 1 line; the extraction README that read all 25 slides named it on 1 line
    too, but carried 25 slide rows. Hits are evidence for a human, not a verdict."""
    art = artifact_rel if os.path.isabs(artifact_rel) else os.path.join(project, artifact_rel)
    if not os.path.exists(art):
        return False, False, False
    # casefold on TEXT, never lower() on bytes: bytes.lower() is ASCII-only, so a needle with
    # Ä/Ü/ü never matched an artifact that plainly named the file. Found by the unattended rerun
    # on the motivating corpus (18 of 96 rows "unverified", every one an umlaut filename) — a
    # false FAULT the instrument raised against its own field project. Both sides are decoded
    # as UTF-8 (errors replaced) and casefolded, and NFC-normalised so a macOS-composed name
    # matches a Windows-decomposed one.
    needle = unicodedata.normalize('NFC', needle).casefold()
    stem = os.path.splitext(needle)[0]
    pats = [needle, stem] if len(stem) >= 4 else [needle]
    # Export tooling prefixes the file with what it is — Form_X.cls, Report_X.cls, Module_X.bas —
    # and the humans writing the analysis call it X. Field measurement 2026-09-02: the triage
    # named "<Module>" four times and "Form_<Module>" never. Strip ONE leading <Word>_ when what remains is still distinctive (>= 8 chars).
    m = re.match(r'^[a-z]+_(.{8,})$', stem)
    if m:
        pats.append(m.group(1))
    files = []
    if os.path.isdir(art):
        for dp, dn, fn in os.walk(art):
            dn[:] = [d for d in dn if d not in ('node_modules', '.git')]
            files += [os.path.join(dp, f) for f in fn]
    else:
        files = [art]
    nonempty = any(os.path.getsize(f) > 0 for f in files if os.path.isfile(f))
    if not nonempty:
        return True, False, 0
    hits = 0
    for f in files:
        if not os.path.isfile(f) or os.path.getsize(f) > 50_000_000:
            continue
        if f not in NAME_CACHE:
            try:
                with open(f, 'rb') as fh:
                    NAME_CACHE[f] = unicodedata.normalize('NFC', fh.read().decode('utf-8', 'replace')).casefold()
            except OSError:
                NAME_CACHE[f] = ''
        blob = NAME_CACHE[f]
        for line in blob.split('\n'):
            if any(p in line for p in pats):
                hits += 1
    return True, True, hits

rows = []
for r in inv:
    rel = r.get('rel') or os.path.basename(r.get('path') or '')
    path = r.get('path') or ''
    # A relative row path (rubrics written before init stamped absolute ones, or hand-written
    # fixtures) resolves against the source root, then the project — never against the cwd.
    if path and not os.path.isabs(path):
        for base in (root, project):
            if base and os.path.exists(os.path.join(base, path)):
                path = os.path.join(base, path); break
    on_disk = os.path.exists(path) if path else False
    media = r.get('media') or 0
    row = {'rel': rel, 'format': r.get('format') or r.get('kind') or 'unknown', 'media': media,
           'opened': r.get('kind') is not None and r.get('answers') is not None}
    reason = waiver_for(rel)
    if reason is not None:
        row.update(verdict='WAIVED', note=reason); rows.append(row); continue
    if r.get('missing') or (path and not on_disk):
        row.update(verdict='MISSING', note='inventoried, no longer on disk — re-run init --refresh, or restore it')
        rows.append(row); continue
    d, by_pattern = disposition_for(rel)
    if d is None:
        row.update(verdict='PENDING', note='no disposition — which artifact carries this file? '
                   '(bin/source-ledger.sh mark, or --waive source/<rel> in gate-check)')
        rows.append(row); continue
    st = d.get('state') or 'extracted'
    who = d.get('by') or '(unattributed)'
    if st == 'sensitive':
        row.update(verdict='SENSITIVE', note=f'logged by path, never read — {who}'); rows.append(row); continue
    if st == 'superseded':
        sup = (d.get('supersededBy') or '').replace(os.sep, '/')
        if sup and (sup in rels_in_inventory or os.path.basename(sup) in {os.path.basename(x) for x in rels_in_inventory}):
            row.update(verdict='SUPERSEDED', note=f'by {sup} — {who}')
        else:
            row.update(verdict='FAULT', note=f'superseded by "{sup}", which is not in the inventory — a superseding file nobody listed supersedes nothing')
        rows.append(row); continue
    if st != 'extracted':
        row.update(verdict='FAULT', note=f'unknown disposition state "{st}"'); rows.append(row); continue
    art = d.get('artifact') or ''
    if not art:
        row.update(verdict='FAULT', note='extracted, but no artifact named — extracted INTO what?'); rows.append(row); continue
    # EVIDENCE (2026-09-02 post-mortem, Failure 3): being mentioned is not being mined. A
    # disposition says what came OUT of the file — one specific finding and where it landed —
    # or it is a claim of the "already handled" kind this instrument exists to refuse.
    if not (d.get('evidence') or '').strip():
        row.update(verdict='FAULT', note='no evidence — what finding came out of this file, and where did it land? '
                   '(mark ... --evidence "..."; a mention in a summary is not a reading)')
        rows.append(row); continue
    exists, nonempty, hits = artifact_names(art, os.path.basename(rel))
    mentions = hits > 0
    if not exists:
        row.update(verdict='FAULT', note=f'artifact {art} does not exist'); rows.append(row); continue
    if not nonempty:
        row.update(verdict='FAULT', note=f'artifact {art} is empty'); rows.append(row); continue
    if not mentions:
        # Pattern or not: an artifact that never names the file did not consume it. Under a
        # pattern this used to report EXTRACTED-unverified; field measurement on the motivating
        # project put 33 of 95 modules in that bucket, and the post-mortem counted the same 39
        # by hand — "named in no analysis document at all" after Stage 1 was marked complete.
        # An extractor output lists its inputs by name; a summary that does not is a summary.
        row.update(verdict='FAULT', note=f'artifact {art} never names {os.path.basename(rel)}'
                   + (' (pattern-covered)' if by_pattern else '')
                   + ' — the claim that it consumed this file does not hold up; extract it, or point at the artifact that did')
        rows.append(row); continue
    # pages accounting: a paged container (slides, sheets, PDF pages) is consumed page by page,
    # and the disposition states how many — the denominator a reviewer holds the reader to.
    pages = r.get('pages') or 0
    if pages and pages > 0:
        ph = d.get('pages'); pw = d.get('pagesWaived')
        if pw:
            pass
        elif ph is None:
            row.update(verdict='FAULT', note=f'{pages} page(s)/slide(s)/sheet(s) inside and the disposition does not say how many were read — '
                       'mark --pages N (must equal the count), or --pages-waived "why"')
            rows.append(row); continue
        elif int(ph) < pages:
            row.update(verdict='FAULT', note=f'{pages} page(s) inside, {ph} read')
            rows.append(row); continue
    # media accounting: a container's diagrams are not consumed by its text
    if media and media > 0:
        handled = d.get('media')
        mw = d.get('mediaWaived')
        if mw:
            pass
        elif handled is None:
            row.update(verdict='FAULT', note=f'{media} embedded image(s) inside and the disposition says nothing about them — '
                       'read/describe them and mark --media N, or --media-waived "why"')
            rows.append(row); continue
        elif int(handled) < media:
            row.update(verdict='FAULT', note=f'{media} embedded image(s) inside, {handled} accounted for')
            rows.append(row); continue
    note = f'→ {art}' + f' (named on {hits} line{"s" if hits != 1 else ""}' + ('' if hits != 1 else ' — one mention is an inventory line, not a reading; check') + ')' + f' — {who}'
    note += f' · evidence: {d.get("evidence")}'
    if pages: note += f' · {pages} page(s) ' + ('waived: ' + d['pagesWaived'] if d.get('pagesWaived') else 'read')
    if media: note += f' · {media} image(s) ' + ('waived: ' + d['mediaWaived'] if d.get('mediaWaived') else 'accounted for')
    row.update(verdict='EXTRACTED', note=note, nameVerified=mentions, nameHits=hits)
    rows.append(row)

# --- drift: on disk, not in the inventory --------------------------------------------------
drift = []
disk = enumerate_root(root) if root and os.path.isdir(root) else []
if disk is None: disk = []
inv_paths = {os.path.normpath(r.get('path') or '') for r in inv}
inv_rels  = rels_in_inventory
for e in disk:
    if os.path.normpath(e['path']) in inv_paths or e['rel'] in inv_rels:
        continue
    if waiver_for(e['rel']) is not None:
        continue
    drift.append(e['rel'])

counts = {'total': len(rows)}
for v in ('EXTRACTED', 'WAIVED', 'SENSITIVE', 'SUPERSEDED', 'PENDING', 'FAULT', 'MISSING'):
    counts[v.lower()] = sum(1 for x in rows if x['verdict'] == v)
counts['nameVerified'] = sum(1 for x in rows if x['verdict'] == 'EXTRACTED' and x.get('nameVerified'))
counts['drift'] = len(drift)
counts['unopened'] = sum(1 for x in rows if not x['opened'])
owed = counts['pending'] + counts['fault'] + counts['missing'] + counts['drift']
status = 'PASS' if owed == 0 else 'FAIL'
if counts['total'] == 0 and not drift:
    status = 'MANUAL'
summary = (f"{counts['total']} inventoried — {counts['extracted']} extracted "
           f"({counts['nameVerified']} name-verified) · {counts['waived']} waived · "
           f"{counts['sensitive']} sensitive · {counts['superseded']} superseded · "
           f"{counts['pending']} pending · {counts['fault']} fault · {counts['missing']} missing · "
           f"{counts['drift']} on disk and NOT inventoried")
if counts['total'] == 0 and not drift:
    summary = "inventory holds zero rows and the source root holds zero files — nothing to account for; is sourceRoot right?"

result = {'status': status, 'note': summary, 'counts': counts, 'rows': rows, 'drift': drift,
          'sourceRoot': root, 'register': register}

if not as_json and not quiet:
    print(f"Source ledger: {status} — {summary}")
    for x in rows:
        if x['verdict'] in ('PENDING', 'FAULT', 'MISSING'):
            print(f"    {x['verdict']:<9} {x['rel']}  — {x['note']}")
    for dr in drift:
        print(f"    DRIFT     {dr}  — on disk, not in the inventory: bin/source-sufficiency.sh init <project> --refresh")
    if status == 'PASS':
        print("    every inventoried file has a disposition that holds up, and nothing new is on disk")

if html_out:
    def esc(s): return html.escape(str(s or ''))
    order = {'FAULT': 0, 'PENDING': 1, 'MISSING': 2, 'EXTRACTED': 3, 'SUPERSEDED': 4, 'SENSITIVE': 5, 'WAIVED': 6}
    trs = ''.join(
        f'<tr class="v-{x["verdict"].lower()}"><td class="mono">{esc(x["rel"])}</td>'
        f'<td>{esc(x["format"])}</td><td class="num">{x["media"] or ""}</td>'
        f'<td><span class="pill p-{x["verdict"].lower()}">{esc(x["verdict"])}</span></td>'
        f'<td>{esc(x["note"])}</td></tr>'
        for x in sorted(rows, key=lambda x: (order.get(x['verdict'], 9), x['rel'])))
    drift_rows = ''.join(f'<li class="mono">{esc(d)}</li>' for d in drift) or '<li class="none">none — the inventory matches the disk</li>'
    page = f"""<title>Source ledger — {esc(os.path.basename(project))}</title>
<style>
  :root {{ --bg:#faf9f6; --panel:#fff; --line:#e6e2da; --ink:#1d1c1a; --muted:#6e6a62; --accent:#2f5d8a;
           --fault:#b3261e; --pending:#b26a00; --ok:#2e7d4f; --waived:#6e6a62; }}
  @media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#15161a; --panel:#1d1f25; --line:#2c2f37; --ink:#ebe9e4; --muted:#9a978f; }} }}
  :root[data-theme="dark"] {{ --bg:#15161a; --panel:#1d1f25; --line:#2c2f37; --ink:#ebe9e4; --muted:#9a978f; }}
  body {{ background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; margin:0; }}
  main {{ max-width:70rem; margin:0 auto; padding:2.5rem 1.5rem 4rem; }}
  .eyebrow {{ color:var(--muted); font-size:.75rem; text-transform:uppercase; letter-spacing:.14em; margin:0 0 .4rem; }}
  h1 {{ font-size:1.7rem; margin:0 0 .5rem; letter-spacing:-.02em; }}
  .sub {{ color:var(--muted); max-width:46rem; margin:0 0 1.5rem; }}
  .verdict {{ background:var(--panel); border:1px solid var(--line); border-radius:4px; padding:1.2rem 1.4rem; margin-bottom:2rem; }}
  .status {{ font-size:1.6rem; font-weight:700; }} .status.PASS{{color:var(--ok)}} .status.FAIL{{color:var(--fault)}} .status.MANUAL{{color:var(--pending)}}
  h2 {{ font-size:.78rem; text-transform:uppercase; letter-spacing:.12em; color:var(--muted); margin:2rem 0 .6rem; }}
  table {{ width:100%; border-collapse:collapse; font-size:.88rem; }} .scroll {{ overflow-x:auto; }}
  th {{ text-align:left; font-size:.68rem; text-transform:uppercase; letter-spacing:.1em; color:var(--muted); border-bottom:1px solid var(--line); padding:.5rem .6rem; }}
  td {{ border-bottom:1px solid var(--line); padding:.6rem; vertical-align:top; }} .num {{ text-align:right; }}
  .mono {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.84em; }}
  .pill {{ display:inline-block; padding:.12rem .5rem; border-radius:3px; font-size:.66rem; font-weight:700; text-transform:uppercase; letter-spacing:.06em; color:#fff; white-space:nowrap; }}
  .p-fault{{background:var(--fault)}} .p-pending{{background:var(--pending)}} .p-missing{{background:var(--fault)}}
  .p-extracted{{background:var(--ok)}} .p-superseded{{background:var(--accent)}} .p-sensitive{{background:var(--accent)}} .p-waived{{background:var(--waived)}}
  ul {{ margin:0; padding-left:1.2rem; }} .none {{ color:var(--muted); list-style:none; margin-left:-1.2rem; }}
  footer {{ margin-top:3rem; padding-top:1rem; border-top:1px solid var(--line); color:var(--muted); font-size:.8rem; max-width:46rem; }}
</style>
<main>
  <p class="eyebrow">Stage 1 · extraction</p>
  <h1>Which source files were actually consumed, and by what</h1>
  <p class="sub">One row per file in the Stage 0 inventory. A row is consumed when an artifact exists,
     is non-empty and <em>names</em> the file — a claim that another document "already used it" is
     checked, not believed. Files with embedded diagrams are not consumed by their text alone.</p>
  <div class="verdict"><div class="status {esc(status)}">{esc(status)}</div><div>{esc(summary)}</div>
    <div style="color:var(--muted);font-size:.85rem;margin-top:.4rem">source root: <span class="mono">{esc(root)}</span> · register: <span class="mono">{esc(register or '(none found)')}</span> · checked {datetime.date.today().isoformat()}</div></div>
  <h2>Inventory rows</h2>
  <div class="scroll"><table><thead><tr><th>File</th><th>Format</th><th>Images inside</th><th>Verdict</th><th>Disposition</th></tr></thead><tbody>{trs}</tbody></table></div>
  <h2>On disk, not in the inventory</h2>
  <ul>{drift_rows}</ul>
  <footer>Verdicts: <strong>EXTRACTED</strong> an artifact carries it · <strong>WAIVED</strong> a person said no, with a reason, in the register
    · <strong>SENSITIVE</strong> logged, never read · <strong>SUPERSEDED</strong> a newer version is inventoried · <strong>PENDING</strong> nobody has said
    · <strong>FAULT</strong> somebody said, and it does not hold up · <strong>MISSING</strong> inventoried, gone from disk.
    This page decides nothing about extraction quality — that is the extractor-quality-loop's job. It only notices absence.</footer>
</main>
"""
    with open(html_out, 'w', encoding='utf-8') as f:
        f.write(page)
    if not quiet and not as_json:
        print(f"  report: {html_out}")

emit(result, 0 if status == 'PASS' else (3 if status == 'MANUAL' else 1))
PY
exit $?
