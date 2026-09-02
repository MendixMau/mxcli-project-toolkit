#!/usr/bin/env python3
"""source-inventory.py — THE enumerator of a project's source corpus. One copy, two callers.

bin/source-sufficiency.sh (init / init --refresh) and bin/source-ledger.sh (check) both need
the same answer to "which files are on disk under the source root" — the first to write the
inventory, the second to notice what the inventory no longer matches. Two enumerators would be
two prune lists, and the day they differ the ledger reports drift over files the inventory
was told to ignore, or misses the ones it was not. Same lesson as bin/lib/intake-template.sh.

DENYLIST, NOT ALLOWLIST. Until 2026-09-02 the inventory listed files by extension allowlist,
and the allowlist grew one incident at a time: .yaml added 08-19 after an OpenAPI contract
went unlisted, code extensions added 08-31 after a Node app's 40 .ts files went unlisted, and
then a .pptx — the only functional description of a workflow engine — went unlisted for two
months on a VBA migration. An allowlist can only ever be as complete as the last incident.
So: every file under the root is a row, minus a short prune list of things that are never a
source (VCS internals, dependency trees, build output, the project's own generated analysis).
An unfamiliar extension is inventoried as kind `unknown` — it still gets opened, still gets a
disposition. Leave no file behind.

Usage (JSON on stdout, one object per line):
    source-inventory.py enumerate <root>
    source-inventory.py describe  <file>...     # format/route/media/pages for given files

Python 3, standard library only. Read-only.
"""
import json
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORMATS_TSV = os.environ.get('SOURCE_FORMATS_TSV', os.path.join(HERE, 'source-formats.tsv'))

# Directories that are never a source. Kept short on purpose: every name here is a place a
# real corpus has been found NOT to live, and nothing else. `sources/` is deliberately absent —
# on a project whose root is analysis/ (the legacy default) the client's code sits there.
PRUNE_DIRS = {
    'node_modules', '.git', '.svn', '.hg', 'dist', 'build', 'vendor', '.venv', 'venv',
    '__pycache__', '.idea', '.vscode', '.mpr-snapshots', 'mprcontents', 'theme-cache',
    'deployment', '.pytest_cache', '.mypy_cache', 'bower_components',
    # the project's OWN outputs, when the root is analysis/ or the project dir itself:
    'knowledge-base', 'brd', 'reports',
}
PRUNE_FILES = {'.DS_Store', 'Thumbs.db', 'desktop.ini', '.gitkeep', '.gitignore'}
# bin/init-project.sh scaffolds sources/README.md ("Drop the legacy application source here").
# It is the toolkit's, not the client's, and a fresh scaffold must not read as a one-file corpus
# nobody inventoried. Recognised by content, never by name — a client's own README.md is a source.
SCAFFOLD_README_MARK = b'Drop the legacy application source here'
PRUNE_PATTERNS = [
    re.compile(r'^source-sufficiency\.'), re.compile(r'^source-ledger\.'),
    re.compile(r'\.brd\.json$'), re.compile(r'^(triage|brd-report|extraction-report)\.html$'),
    re.compile(r'\.pyc$'), re.compile(r'\.class$'),
]


def load_formats():
    table = {}
    if not os.path.exists(FORMATS_TSV):
        return table
    with open(FORMATS_TSV, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip() or line.startswith('#'):
                continue
            cols = line.split('\t')
            if cols[0] == 'ext' or len(cols) < 4:
                continue
            exts, kind, route, media = cols[0], cols[1], cols[2], cols[3]
            notes = cols[4] if len(cols) > 4 else ''
            for e in exts.split('|'):
                table[e.strip().lower()] = {
                    'kind': kind, 'route': route, 'media': media.strip().lower() == 'yes',
                    'notes': notes}
    return table


FORMATS = load_formats()

# Where embedded media lives inside the zip-based containers. A deck's diagrams are usually
# the process specification; a text-only extraction that never mentions them has not read the
# deck. Counted here so the ledger can demand they be accounted for.
ZIP_MEDIA_PREFIXES = ('ppt/media/', 'word/media/', 'xl/media/', 'visio/media/', 'Pictures/',
                      'media/')
ZIP_PAGE_PATTERNS = [
    re.compile(r'^ppt/slides/slide\d+\.xml$'),
    re.compile(r'^xl/worksheets/sheet\d+\.xml$'),
    re.compile(r'^visio/pages/page\d+\.xml$'),
]


def describe(path):
    """format/route/media/pages for one file. Never raises; unreadable → counts null."""
    ext = os.path.splitext(path)[1].lower().lstrip('.')
    fmt = FORMATS.get(ext)
    row = {
        'ext': ext or None,
        'format': (fmt['kind'] if fmt else 'unknown'),
        'route': (fmt['route'] if fmt else
                  'no known route for this extension — custom extractor per '
                  'skills/extractor-quality-loop.md, or a waiver with a reason'),
        'media': None,
        'pages': None,
    }
    try:
        size = os.path.getsize(path)
    except OSError:
        size = None
    row['bytes'] = size
    if fmt and fmt['media']:
        row['media'], row['pages'] = count_media(path, ext)
    elif ext == 'xlsx' or ext == 'xlsm':
        _m, row['pages'] = count_media(path, ext)
    return row


def count_media(path, ext):
    media = pages = None
    try:
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as z:
                names = z.namelist()
            media = sum(1 for n in names
                        if any(n.startswith(p) for p in ZIP_MEDIA_PREFIXES)
                        and not n.endswith('/'))
            pg = sum(1 for n in names if any(p.match(n) for p in ZIP_PAGE_PATTERNS))
            pages = pg if pg else None
        elif ext == 'pdf':
            with open(path, 'rb') as f:
                data = f.read()
            media = len(re.findall(rb'/Subtype\s*/Image', data))
            pg = len(re.findall(rb'/Type\s*/Page[^s]', data))
            pages = pg if pg else None
        else:
            media = 0
    except Exception:  # noqa: BLE001 — a corrupt container is still a file to disposition
        media = None
    return media, pages


def _is_scaffold_readme(path):
    try:
        with open(path, 'rb') as f:
            return SCAFFOLD_README_MARK in f.read(4096)
    except OSError:
        return False


def enumerate_root(root):
    root = os.path.normpath(root)
    out = []
    if not os.path.isdir(root):
        return out
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in PRUNE_DIRS)
        for fn in sorted(filenames):
            if fn in PRUNE_FILES or any(p.search(fn) for p in PRUNE_PATTERNS):
                continue
            full = os.path.join(dirpath, fn)
            if fn == 'README.md' and dirpath == root and _is_scaffold_readme(full):
                continue
            rel = os.path.relpath(full, root)
            entry = {'path': full, 'rel': rel.replace(os.sep, '/')}
            entry.update(describe(full))
            out.append(entry)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == 'enumerate':
        for e in enumerate_root(argv[2]):
            print(json.dumps(e))
        return 0
    if cmd == 'describe':
        for p in argv[2:]:
            d = {'path': p}
            d.update(describe(p))
            print(json.dumps(d))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
