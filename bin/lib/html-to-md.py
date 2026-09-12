#!/usr/bin/env python3
"""html-to-md.py — convert a saved-webpage corpus to Markdown ONCE, so nobody reads raw HTML.

WHY THIS EXISTS (2026-09-09, a requirements-driven project whose corpus was Markdown files plus
HTML pages — saved-webpage exports with their `_files` sidecar folders). Stages 1–4 were slow
and token-hungry, and the measured cause was that agents opened the .html files themselves: a
saved page is 3–10× the tokens of its own text (inline styles, nested wrapper divs, the nav
sidebar, the footer, a base64 screenshot or two), and every session paid that cost again. The
fix is a one-time transform whose output is what everyone reads instead.

WHAT IT WRITES. For each .html/.htm/.xhtml under the source root:
  <out>/<same relative path>.md            the text, as Markdown, with a small header
  <out>/<same relative path>_images/NN.ext every inline base64 image, decoded to a file, so a
                                           vision read is possible without the HTML
and one index over EVERY file under the source root — pages, markdown, sidecar images, css,
js, fonts — at <out>/../documents-index.md. The index names every file's basename exactly,
because it is the artifact a single ledger glob mark points at (bin/source-ledger.sh greps the
artifact for each inventoried basename; a row it does not name reports FAULT).

WHAT IT KEEPS: h1–h6, paragraphs, ordered/unordered lists, tables (as Markdown tables),
bold/italic, links as [text](href), <pre>/<code>, every <img> as ![alt](src).
WHAT IT DROPS: <script>, <style>, <noscript>, <svg>, <template>, comments, and chrome regions —
<nav>, <footer>, <header> when it contains a nav, role=navigation|banner|contentinfo, and any
element whose class/id contains nav|sidebar|footer|menu|cookie|breadcrumb. Conservative on
purpose: <main>, <article> and anything containing an h1–h3 are never dropped, whatever their
class says — a wrongly dropped region is content silently gone, which is worse than a nav
that survives.

THE HEADER is the read's denominator. Each .md opens with source path, raw size, word count,
image count and the section list (every heading with the md line number it sits on), so a
reader can state "all N sections covered" and a reviewer can check the claim by line number.

Idempotent: a page whose .md is newer than its source is skipped (its header is read back for
the index) unless --force. The file walk is bin/lib/source-inventory.py's — the same prune
rules as the Stage 0 inventory, so the index and the inventory can never disagree about what
"every file" means.

Usage (called by bin/html-to-md.sh; runnable directly):
    html-to-md.py <project-root> <source-root> <out-root> [--force]

Python 3, standard library only (html.parser, base64). Writes only under <out-root> and the
index beside it.
"""
import base64
import importlib.util
import os
import re
import sys
import time
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))

# The corpus walk is the inventory's, not a second copy of its prune rules.
_spec = importlib.util.spec_from_file_location('source_inventory', os.path.join(HERE, 'source-inventory.py'))
_inv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_inv)

PAGE_EXTS = ('html', 'htm', 'xhtml')
MD_EXTS = ('md', 'markdown')
IMG_EXTS = ('png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'tif', 'tiff', 'ico')
CHROME_EXTS = ('css', 'js', 'map', 'woff', 'woff2', 'ttf', 'otf', 'eot')

VOID = {'img', 'br', 'hr', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'param',
        'source', 'track', 'wbr'}
DROP_TAGS = {'script', 'style', 'noscript', 'svg', 'template', 'head', 'iframe', 'object',
             'canvas', 'video', 'audio', 'map', 'title', 'select', 'datalist'}
BLOCK_TAGS = {'p', 'div', 'section', 'article', 'main', 'body', 'html', 'ul', 'ol', 'li',
              'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'blockquote', 'pre', 'hr',
              'dl', 'dt', 'dd', 'figure', 'figcaption', 'header', 'footer', 'aside', 'nav',
              'form', 'fieldset', 'legend', 'details', 'summary', 'address', 'center',
              'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'caption', 'colgroup'}
# Opening one of these implicitly closes an open one of the same kind (browsers do this; a
# saved page written by hand or by an old CMS relies on it).
IMPLICIT_CLOSE = {  # tag: (ancestors it closes, ancestors that end the search)
    'p': ({'p'}, None),                       # None: any other block tag stops it
    'li': ({'li'}, {'ul', 'ol'}),
    'tr': ({'tr'}, {'table', 'thead', 'tbody', 'tfoot'}),
    'td': ({'td', 'th'}, {'tr', 'table'}),
    'th': ({'td', 'th'}, {'tr', 'table'}),
    'dt': ({'dt', 'dd'}, {'dl'}),
    'dd': ({'dt', 'dd'}, {'dl'}),
    'option': ({'option'}, {'select', 'datalist'}),
}
CHROME_WORDS = ('nav', 'sidebar', 'footer', 'menu', 'cookie', 'breadcrumb')
CHROME_ROLES = ('navigation', 'banner', 'contentinfo')
NEVER_DROP = {'main', 'article', 'body', 'html'}


class Node:
    __slots__ = ('tag', 'attrs', 'children', 'parent')

    def __init__(self, tag, attrs=None, parent=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.children = []
        self.parent = parent


class TreeBuilder(HTMLParser):
    """html.parser events → a small element tree. Text nodes are plain str children."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node('#root')
        self.cur = self.root
        self.title = ''
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag == 'title':
            self._in_title = True
        # implicit closes
        rule = IMPLICIT_CLOSE.get(tag)
        if rule:
            closers, stops = rule
            n = self.cur
            while n is not None and n.tag != '#root':
                if n.tag in closers:
                    self.cur = n.parent
                    break
                if (stops is None and n.tag in BLOCK_TAGS) or (stops is not None and n.tag in stops):
                    break
                n = n.parent
        node = Node(tag, attrs, self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        node = Node(tag.lower(), attrs, self.cur)
        self.cur.children.append(node)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == 'title':
            self._in_title = False
        if tag in VOID:
            return
        n = self.cur
        while n is not None and n.tag != '#root':
            if n.tag == tag:
                self.cur = n.parent
                return
            n = n.parent
        # stray end tag: ignore

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        self.cur.children.append(data)

    def handle_comment(self, data):
        pass


# --- chrome detection ------------------------------------------------------------------------

def _class_id(node):
    return ((node.attrs.get('class') or '') + ' ' + (node.attrs.get('id') or '')).lower()


def contains_heading(node, upto=3):
    for c in node.children:
        if isinstance(c, Node):
            if len(c.tag) == 2 and c.tag[0] == 'h' and c.tag[1].isdigit() and int(c.tag[1]) <= upto:
                return True
            if contains_heading(c, upto):
                return True
    return False


def contains_tag(node, tag):
    for c in node.children:
        if isinstance(c, Node):
            if c.tag == tag or contains_tag(c, tag):
                return True
    return False


def is_chrome(node):
    """Drop this element as chrome? Conservative: main/article/anything with an h1–h3 stays."""
    if node.tag in NEVER_DROP:
        return False
    hit = False
    if node.tag == 'nav' or node.tag == 'footer':
        hit = True
    elif node.tag == 'header' and contains_tag(node, 'nav'):
        hit = True
    elif (node.attrs.get('role') or '').lower() in CHROME_ROLES:
        hit = True
    else:
        ci = _class_id(node)
        if ci.strip() and any(w in ci for w in CHROME_WORDS):
            hit = True
    if not hit:
        return False
    if contains_heading(node, 3):
        return False
    return True


# --- rendering ---------------------------------------------------------------------------------

class Renderer:
    def __init__(self, page_dir, images_dir_rel, images_dir_abs, project=None):
        self.page_dir = page_dir          # where the html lives: relative src values resolve here
        self.project = project            # sidecar refs are rewritten project-relative when they exist
        self.images_dir_rel = images_dir_rel
        self.images_dir_abs = images_dir_abs
        self.image_count = 0
        self.inline_written = 0
        self.sidecar_refs = []   # src values of non-data images, as written in the html
        self.dropped = 0
        self.blocks = []         # list of markdown block strings (no trailing newline)

    # -- inline -------------------------------------------------------------------------------
    def inline(self, node, pre=False):
        """Render the children of node as one inline string."""
        out = []
        for c in node.children:
            if isinstance(c, str):
                out.append(c if pre else re.sub(r'\s+', ' ', c))
                continue
            t = c.tag
            if t in DROP_TAGS:
                continue
            if is_chrome(c):
                self.dropped += 1
                continue
            if t == 'br':
                out.append('\n' if pre else '  \n')
            elif t == 'img':
                out.append(self.image(c))
            elif t in ('strong', 'b'):
                s = self.inline(c, pre).strip()
                out.append(f'**{s}**' if s else '')
            elif t in ('em', 'i'):
                s = self.inline(c, pre).strip()
                out.append(f'*{s}*' if s else '')
            elif t == 'code' and not pre:
                s = self.inline(c, True).strip().replace('`', '')
                out.append(f'`{s}`' if s else '')
            elif t == 'a':
                s = self.inline(c, pre).strip()
                href = (c.attrs.get('href') or '').strip()
                if s and href and not href.lower().startswith(('javascript:', '#')):
                    out.append(f'[{s}]({href})')
                else:
                    out.append(s)
            elif t in BLOCK_TAGS:
                # a block inside an inline context (e.g. <div> in <a>): flatten to text
                out.append(' ' + self.inline(c, pre) + ' ')
            elif t == 'input':
                v = c.attrs.get('value') or ''
                ty = (c.attrs.get('type') or 'text').lower()
                if ty in ('checkbox', 'radio'):
                    out.append('[x] ' if 'checked' in c.attrs else '[ ] ')
                elif ty not in ('hidden', 'submit', 'button'):
                    out.append(f'[{v}]' if v else '')
            else:
                out.append(self.inline(c, pre))
        s = ''.join(out)
        return s if pre else re.sub(r'[ \t]+', ' ', s)

    def image(self, node):
        src = (node.attrs.get('src') or '').strip()
        alt = re.sub(r'\s+', ' ', (node.attrs.get('alt') or '').strip())
        if not src:
            return ''
        self.image_count += 1
        if src.lower().startswith('data:'):
            path = self.write_inline(src)
            if path:
                return f'![{alt}]({path})'
            return f'![{alt}](data:… inline image {self.image_count}, undecodable)'
        self.sidecar_refs.append(src)
        # A sidecar path is relative to the HTML's own folder, which is not where the .md lives.
        # Rewrite it project-relative when the file exists, so the reference resolves from
        # anywhere in the project (and names the sidecar exactly as the inventory does).
        if self.page_dir and self.project and '://' not in src:
            cand = os.path.normpath(os.path.join(self.page_dir, re.sub(r'[?#].*$', '', src)))
            if os.path.exists(cand):
                src = os.path.relpath(cand, self.project).replace(os.sep, '/')
        return f'![{alt}]({src})'

    def write_inline(self, data_uri):
        m = re.match(r'data:image/([a-zA-Z0-9.+-]+);base64,(.*)$', data_uri, re.S)
        if not m:
            return None
        ext = m.group(1).lower()
        ext = {'jpeg': 'jpg', 'svg+xml': 'svg'}.get(ext, ext)
        try:
            raw = base64.b64decode(re.sub(r'\s+', '', m.group(2)), validate=False)
        except Exception:  # noqa: BLE001
            return None
        os.makedirs(self.images_dir_abs, exist_ok=True)
        self.inline_written += 1
        name = f'{self.inline_written:02d}.{ext}'
        with open(os.path.join(self.images_dir_abs, name), 'wb') as f:
            f.write(raw)
        return f'{self.images_dir_rel}/{name}'

    # -- blocks -------------------------------------------------------------------------------
    def emit(self, text):
        text = text.strip('\n')
        if text.strip():
            self.blocks.append(text)

    def flush_inline(self, buf):
        s = ''.join(buf).strip()
        if s:
            self.emit(s)
        del buf[:]

    def block(self, node, depth=0):
        """Render node's children as blocks; inline runs become paragraphs."""
        buf = []
        for c in node.children:
            if isinstance(c, str):
                buf.append(re.sub(r'\s+', ' ', c))
                continue
            t = c.tag
            if t in DROP_TAGS:
                continue
            if is_chrome(c):
                self.dropped += 1
                continue
            if len(t) == 2 and t[0] == 'h' and t[1].isdigit():
                self.flush_inline(buf)
                s = self.inline(c).strip()
                if s:
                    self.emit('#' * int(t[1]) + ' ' + s)
            elif t in ('ul', 'ol'):
                self.flush_inline(buf)
                self.emit(self.list(c, depth))
            elif t == 'table':
                self.flush_inline(buf)
                self.emit(self.table(c))
            elif t == 'pre':
                self.flush_inline(buf)
                s = self.inline(c, pre=True).strip('\n')
                self.emit('```\n' + s + '\n```')
            elif t == 'hr':
                self.flush_inline(buf)
                self.emit('---')
            elif t == 'blockquote':
                self.flush_inline(buf)
                sub = Renderer(self.page_dir, self.images_dir_rel, self.images_dir_abs, self.project)
                sub.inline_written = self.inline_written
                sub.block(c, depth)
                self.adopt(sub)
                self.emit('\n'.join('> ' + l for b in sub.blocks for l in b.split('\n')))
            elif t in ('dt',):
                self.flush_inline(buf)
                self.emit('**' + self.inline(c).strip() + '**')
            elif t in ('dd',):
                self.flush_inline(buf)
                self.emit(': ' + self.inline(c).strip())
            elif t in BLOCK_TAGS or t in ('li',):
                # a block container: if it holds only inline content, it is a paragraph;
                # otherwise recurse
                if any(isinstance(g, Node) and (g.tag in BLOCK_TAGS or g.tag in ('ul', 'ol', 'table')) for g in c.children):
                    self.flush_inline(buf)
                    self.block(c, depth)
                else:
                    self.flush_inline(buf)
                    s = self.inline(c).strip()
                    if s:
                        self.emit(s)
            else:
                buf.append(self.inline_one(c))
        self.flush_inline(buf)

    def inline_one(self, node):
        wrapper = Node('#w')
        wrapper.children = [node]
        return self.inline(wrapper)

    def adopt(self, sub):
        self.image_count += sub.image_count
        self.inline_written = sub.inline_written
        self.sidecar_refs += sub.sidecar_refs
        self.dropped += sub.dropped

    def list(self, node, depth):
        lines = []
        ordered = node.tag == 'ol'
        n = 0
        for c in node.children:
            if not isinstance(c, Node) or c.tag != 'li':
                continue
            n += 1
            marker = f'{n}. ' if ordered else '- '
            head_parts = []
            nested = []
            for g in c.children:
                if isinstance(g, Node) and g.tag in ('ul', 'ol'):
                    nested.append(g)
                elif isinstance(g, Node) and g.tag in ('p', 'div'):
                    head_parts.append(self.inline(g))
                elif isinstance(g, Node) and g.tag == 'table':
                    nested.append(g)
                else:
                    w = Node('#w'); w.children = [g]
                    head_parts.append(self.inline(w))
            head = re.sub(r'\s+', ' ', ''.join(head_parts)).strip()
            lines.append('  ' * depth + marker + head)
            for g in nested:
                if g.tag == 'table':
                    lines.append('\n'.join('  ' * (depth + 1) + l for l in self.table(g).split('\n')))
                else:
                    lines.append(self.list(g, depth + 1))
        return '\n'.join(l for l in lines if l.strip())

    def table(self, node):
        rows = []
        has_th = []

        def cell_text(cell):
            return re.sub(r'\s+', ' ', self.inline(cell)).strip().replace('|', '\\|')

        def walk(n):
            for c in n.children:
                if not isinstance(c, Node):
                    continue
                if c.tag == 'tr':
                    cells = [g for g in c.children if isinstance(g, Node) and g.tag in ('td', 'th')]
                    if cells:
                        rows.append([cell_text(g) for g in cells])
                        has_th.append(all(g.tag == 'th' for g in cells))
                elif c.tag in ('thead', 'tbody', 'tfoot'):
                    walk(c)
                elif c.tag == 'caption':
                    cap = self.inline(c).strip()
                    if cap:
                        rows.append(['__caption__', cap])
                        has_th.append(False)
        walk(node)
        caption = None
        if rows and rows[0][0] == '__caption__':
            caption = rows.pop(0)[1]; has_th.pop(0)
        if not rows:
            return ''
        width = max(len(r) for r in rows)
        rows = [r + [''] * (width - len(r)) for r in rows]
        out = []
        if caption:
            out.append(f'**{caption}**\n')
        out.append('| ' + ' | '.join(rows[0]) + ' |')
        out.append('|' + '---|' * width)
        for r in rows[1:]:
            out.append('| ' + ' | '.join(r) + ' |')
        return '\n'.join(out)


# --- one page ----------------------------------------------------------------------------------

def convert_page(src_abs, src_rel_project, out_abs, images_dir_abs, project):
    with open(src_abs, 'rb') as f:
        raw = f.read()
    text = raw.decode('utf-8', 'replace')
    m = re.search(rb'charset\s*=\s*["\']?([A-Za-z0-9_-]+)', raw[:4096])
    if m and m.group(1).decode('ascii', 'replace').lower().replace('-', '') not in ('utf8',):
        try:
            text = raw.decode(m.group(1).decode('ascii'), 'replace')
        except LookupError:
            pass
    tb = TreeBuilder()
    try:
        tb.feed(text)
        tb.close()
    except Exception as e:  # noqa: BLE001 — a page that will not parse is still a page to list
        return {'error': f'parse failed: {e}'}
    stem = os.path.splitext(os.path.basename(out_abs))[0]
    images_dir_rel = f'{stem}_images'
    r = Renderer(os.path.dirname(src_abs), images_dir_rel, images_dir_abs, project)
    r.block(tb.root)
    body = '\n\n'.join(r.blocks)
    body_lines = body.split('\n')
    words = len(re.findall(r'\S+', body))
    headings = heading_lines(body_lines)
    title = re.sub(r'\s+', ' ', tb.title).strip()
    # header: fixed lines + one per section; line numbers are 1-based positions in the final file
    fixed = [
        f'<!-- html-to-md: raw={len(raw)} words={words} images={r.image_count} inline={r.inline_written} sections={len(headings)} -->',
        f'**Source:** `{src_rel_project}`' + (f' — *{title}*' if title else ''),
        f'**Raw size:** {len(raw) / 1024:.1f} KB · **Words:** {words} · **Images:** {r.image_count}'
        + (f' ({r.inline_written} inline, written to `{images_dir_rel}/`)' if r.inline_written else '')
        + (f' · **Chrome regions dropped:** {r.dropped}' if r.dropped else ''),
        '',
        f'**Sections ({len(headings)})** — the denominator: a read covers all of them, by line number:',
    ]
    n_header = len(fixed) + max(len(headings), 1) + 2   # + section lines + blank + separator
    section_lines = []
    for i, l in headings:
        m = re.match(r'^(#{1,6}) (.*)$', l)
        section_lines.append(f'- L{n_header + 1 + i}: {"  " * (len(m.group(1)) - 1)}{m.group(2)}')
    if not headings:
        section_lines.append('- (no headings — the page is one section)')
    header = fixed + section_lines + ['', '---']
    assert len(header) == n_header
    content = '\n'.join(header) + '\n' + body + '\n'
    os.makedirs(os.path.dirname(out_abs), exist_ok=True)
    with open(out_abs, 'w', encoding='utf-8') as f:
        f.write(content)
    return {'raw': len(raw), 'words': words, 'images': r.image_count, 'inline': r.inline_written,
            'sections': len(headings), 'md_bytes': len(content.encode('utf-8')), 'title': title}


def read_back(md_abs):
    """Stats of an already-converted page, from its own machine-readable first line."""
    try:
        with open(md_abs, encoding='utf-8') as f:
            first = f.readline()
        m = re.search(r'<!-- html-to-md: raw=(\d+) words=(\d+) images=(\d+) inline=(\d+) sections=(\d+) -->', first)
        if not m:
            return None
        return {'raw': int(m.group(1)), 'words': int(m.group(2)), 'images': int(m.group(3)),
                'inline': int(m.group(4)), 'sections': int(m.group(5)),
                'md_bytes': os.path.getsize(md_abs), 'title': ''}
    except OSError:
        return None


def heading_lines(lines):
    """(index, line) of every Markdown heading, ignoring lines inside ``` fences."""
    out, fence = [], False
    for i, l in enumerate(lines):
        if l.startswith('```'):
            fence = not fence
            continue
        if not fence and re.match(r'^#{1,6} ', l):
            out.append((i, l))
    return out


def md_stats(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            t = f.read()
    except OSError:
        return 0, 0, 0
    words = len(re.findall(r'\S+', t))
    sections = len(heading_lines(t.split('\n')))
    images = len(re.findall(r'!\[[^\]]*\]\(', t))
    return words, sections, images


IMG_SRC_RE = re.compile(r'<img\b[^>]*?\bsrc\s*=\s*["\']([^"\']+)["\']', re.I | re.S)


def img_refs(html_path):
    """Non-data <img src> values of a page, for sidecar ownership — regex on purpose: it runs
    on skipped (already converted) pages too, so the index reads the same on every run."""
    try:
        with open(html_path, 'rb') as f:
            t = f.read().decode('utf-8', 'replace')
    except OSError:
        return []
    return [m for m in IMG_SRC_RE.findall(t) if not m.strip().lower().startswith('data:')]


# --- the run -----------------------------------------------------------------------------------

def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    project = os.path.abspath(argv[1])
    src_root = os.path.abspath(argv[2])
    out_root = os.path.abspath(argv[3])
    force = '--force' in argv[4:]
    if not os.path.isdir(src_root):
        print(f'html-to-md: source root is not a directory: {src_root}', file=sys.stderr)
        return 2
    files = _inv.enumerate_root(src_root)
    if not files:
        print(f'html-to-md: no files under {src_root} — nothing to convert', file=sys.stderr)
        return 3

    def rel_project(p):
        return os.path.relpath(p, project).replace(os.sep, '/')

    # sidecar ownership: X_files/ belongs to X.html in the same directory (saved-webpage
    # convention); an image a page references by src belongs to that page too.
    pages = {}   # rel (under src root) -> stats
    owner_of = {}  # rel -> page rel
    page_rels = [e['rel'] for e in files if (e['ext'] or '') in PAGE_EXTS]
    for prel in page_rels:
        stem = os.path.splitext(prel)[0]
        for cand in (stem + '_files/', stem + '_bestanden/', stem + '_fichiers/', stem + '_Dateien/', stem + '.files/'):
            for e in files:
                if e['rel'].startswith(cand):
                    owner_of.setdefault(e['rel'], prel)

    print(f'html-to-md: {len(files)} file(s) under {rel_project(src_root)}/, {len(page_rels)} page(s) → {rel_project(out_root)}/')
    print('')
    print(f'  {"page":<48} {"raw KB":>8} {"md words":>9} {"ratio":>7}  note')
    tot_raw = tot_md = tot_words = tot_img = tot_inline = 0
    converted = skipped = 0
    for e in files:
        if (e['ext'] or '') not in PAGE_EXTS:
            continue
        rel = e['rel']
        out_abs = os.path.join(out_root, os.path.splitext(rel)[0] + '.md')
        images_dir_abs = os.path.join(out_root, os.path.splitext(rel)[0] + '_images')
        note = 'converted'
        st = None
        if not force and os.path.exists(out_abs) and os.path.getmtime(out_abs) >= os.path.getmtime(e['path']):
            st = read_back(out_abs)
            if st is not None:
                note = 'up to date, skipped'
                skipped += 1
        if st is None:
            st = convert_page(e['path'], rel_project(e['path']), out_abs, images_dir_abs, project)
            if 'error' in st:
                print(f'  {rel[:48]:<48} {(e.get("bytes") or 0) / 1024:>8.1f} {"-":>9} {"-":>7}  {st["error"]}')
                pages[rel] = {'error': st['error']}
                continue
            converted += 1
        # images the page references by relative src belong to it — on every run, so a skipped
        # page owns the same sidecars as a converted one
        base = os.path.dirname(rel)
        for s in img_refs(e['path']):
            s = re.sub(r'[?#].*$', '', s.strip())
            if '://' in s or not s:
                continue
            target = os.path.normpath(os.path.join(base, s)).replace(os.sep, '/')
            owner_of.setdefault(target, rel)
        st['md'] = os.path.relpath(out_abs, project).replace(os.sep, '/')
        pages[rel] = st
        ratio = (st['raw'] / st['md_bytes']) if st['md_bytes'] else 0
        print(f'  {rel[:48]:<48} {st["raw"] / 1024:>8.1f} {st["words"]:>9} {ratio:>6.1f}×  {note}'
              + (f', {st["inline"]} inline image(s) written' if st.get('inline') else ''))
        tot_raw += st['raw']; tot_md += st['md_bytes']; tot_words += st['words']
        tot_img += st['images']; tot_inline += st.get('inline', 0)

    # --- the index: EVERY file -------------------------------------------------------------
    rows = []
    n_md = n_img = n_chrome = n_other = 0
    md_words_total = 0
    img_to_read = 0
    for e in files:
        rel = e['rel']; ext = (e['ext'] or '').lower()
        owner = owner_of.get(rel)
        if ext in PAGE_EXTS:
            st = pages.get(rel) or {}
            if 'error' in st:
                rows.append((rel, 'page (NOT converted: ' + st['error'] + ')', '—', '—', '—', '—'))
            else:
                rows.append((rel, 'page', f'`{st["md"]}`', str(st['sections']), str(st['images']), str(st['words'])))
                img_to_read += st['images']
        elif ext in MD_EXTS:
            w, s, i = md_stats(e['path'])
            n_md += 1; md_words_total += w; img_to_read += i
            rows.append((rel, 'markdown', '— (read as is)', str(s), str(i), str(w)))
        elif ext in IMG_EXTS:
            n_img += 1
            role = f'image of {owner}' if owner else 'image (standalone)'
            if not owner:
                img_to_read += 1
            rows.append((rel, role, '—', '—', '—', '—'))
        elif ext in CHROME_EXTS:
            n_chrome += 1
            role = f'chrome of {owner}' if owner else 'chrome (no owning page)'
            rows.append((rel, role, '—', '—', '—', '—'))
        else:
            n_other += 1
            rows.append((rel, f'other ({e.get("format") or "unknown"})' + (f' in {owner}_files' if owner else ''), '—', '—', '—', '—'))
    index_abs = os.path.join(os.path.dirname(out_root), 'documents-index.md')
    os.makedirs(os.path.dirname(index_abs), exist_ok=True)
    n_pages = len(page_rels)
    with open(index_abs, 'w', encoding='utf-8') as f:
        f.write('# Documents index — every file under the source root\n\n')
        f.write(f'Written by `bin/html-to-md.sh` on {time.strftime("%Y-%m-%d")} over `{rel_project(src_root)}/` '
                f'({len(files)} files). One row per file, sidecars included: this is the artifact a single '
                f'ledger mark points at (`bin/source-ledger.sh mark <project> \'*\' --artifact '
                f'{rel_project(index_abs)} ...`), so it names every file.\n\n')
        f.write(f'**Totals:** {n_pages} page(s) → {tot_words} words of Markdown (raw {tot_raw / 1024:.1f} KB → '
                f'{tot_md / 1024:.1f} KB, {(tot_raw / tot_md) if tot_md else 0:.1f}×) · {n_md} markdown file(s), '
                f'{md_words_total} words · {n_img} image file(s) · {n_chrome} chrome file(s) (css/js/fonts) · '
                f'{n_other} other.\n\n')
        f.write(f'**Images to read (vision) before Stage 2 closes: {img_to_read}** — every image a page or '
                f'markdown file references ({tot_img} from pages, of which {tot_inline} inline and now written to '
                f'`*_images/`) plus every standalone image file. The count is the denominator.\n\n')
        f.write('| path | role | converted-to | sections | images | words |\n|---|---|---|---|---|---|\n')
        for r in rows:
            f.write('| ' + ' | '.join(x.replace('|', '\\|') for x in r) + ' |\n')
    print('')
    print(f'  {"TOTAL":<48} {tot_raw / 1024:>8.1f} {tot_words:>9} {(tot_raw / tot_md) if tot_md else 0:>6.1f}×  '
          f'{converted} converted, {skipped} skipped (up to date), {tot_img} image(s) ({tot_inline} inline written)')
    print(f'  index: {rel_project(index_abs)} — {len(rows)} row(s): {n_pages} page, {n_md} markdown, {n_img} image, '
          f'{n_chrome} chrome, {n_other} other · images to read (vision): {img_to_read}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
