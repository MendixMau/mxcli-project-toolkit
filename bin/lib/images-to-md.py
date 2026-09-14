#!/usr/bin/env python3
"""images-to-md.py — one worklist of every unique picture in the source corpus, one description
file each, coverage checked. The SCRIPT prepares and verifies; the MODEL reads and writes
(skills-over-scripts.md).

WHY THIS EXISTS (2026-09-14). `bin/html-to-md.sh` converts a corpus's HTML to Markdown once and
lists every image in `documents-index.md` with an "Images to read (vision)" denominator — but
nothing then reads the pictures except whichever session happens to look, and the description
is never stored anywhere another session can find it. Field precedent: a 25-slide functional-
description deck (22 distinct PNGs, 1,173 words of slide text) was read as prose at Stage P and
its images were extracted 20 days later by hand; the pictures overturned an analysis conclusion
and closed four open questions. The hand capture produced `slides.json` (per slide: text runs +
image list), `media/slideNN-N.png`, and a README table "what the image actually shows"; it
noted two byte-identical duplicates by eye; it left no per-image file, so nothing downstream
cites a picture. This instrument makes that repeatable.

WHAT IT COLLECTS, from every corner a picture can hide in:
  (a) loose image files under the source root (png/jpg/jpeg/gif/bmp/webp/tif/tiff; svg is
      listed but marked vector — read as text, never described here)
  (b) HTML sidecar images (a saved page's `<page>_files/*`, found by the ordinary source-root
      walk) and the inline base64 images `bin/html-to-md.sh` already decoded to
      `analysis/knowledge-base/text/**/*_images/*`
  (c) containers: every .pptx/.docx under the source root, opened with zipfile — media from
      ppt/media/ or word/media/, with the pptx slide->image mapping kept via each slide's
      .rels file (plus the slide's own <a:t> text as context), and the docx image mapped to
      the nearest preceding heading (best effort)
  (d) PDF, best effort, stdlib only: /Subtype /Image objects; /DCTDecode streams are raw JPEG;
      /FlateDecode with 8-bit DeviceRGB/DeviceGray is zlib-decompressed and wrapped as a PNG we
      write ourselves (struct + zlib, no Pillow); anything else is `needs-render` and counted,
      never silently dropped.

WHAT IT WRITES, under <out> (default analysis/knowledge-base/images/):
  manifest.json   one row per UNIQUE image (deduped by sha256): id, dimensions (read from file
                  headers only), role, every location it appears at with context, and the copy
                  at images/<id>.<ext>.
  worklist.md     one section per content image: id, dimensions, every location, and the exact
                  path of the description file it owes.
Plus, under analysis/knowledge-base/text/: one slideNN.md and one slides.json per pptx deck
(same shape as the hand capture above), and — everywhere an image already has a description —
a quoted excerpt inlined right after its `![alt](path)` line, so one read of the page covers
text and pictures (`--inline`, run automatically once `--check` reports everything described).

Judgement never lives here (skills-over-scripts.md): this script never writes a description; a
human or a fanned-out subagent does, per `skills/image-transcription.md`, into
`analysis/knowledge-base/images/<id>.md`. `--check` only verifies the file exists, is non-empty,
and carries the template's headings — never whether the description is any good.

Usage (called by bin/images-to-md.sh; runnable directly):
    images-to-md.py <project-root> <source-root> <images-out-root> <text-root>
                     [--check] [--inline] [--force]

Exit: 0 for a plain run or a completed --check/--inline; 1 when --check finds content images
still undescribed (their ids are listed); 2 on a usage error.

Python 3, standard library only (zipfile, zlib, struct, xml.etree). Idempotent: an image's id
is stable across runs (carried over from the previous manifest.json by sha256), so a
description file written against img-014 never orphans; unchanged image bytes are never
rewritten; --force forgets the old id assignment and rebuilds from zero.
"""
import hashlib
import json
import os
import posixpath
import re
import struct
import sys
import time
import zipfile
import zlib
from xml.etree import ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location('source_inventory', os.path.join(HERE, 'source-inventory.py'))
_inv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_inv)

RASTER_EXTS = ('png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tif', 'tiff')
VECTOR_EXTS = ('svg',)
IMG_EXTS = RASTER_EXTS + VECTOR_EXTS
TINY_LONG_EDGE = 64
CONTEXT_MAX = 300

REQUIRED_HEADINGS = ('## Kind', '## Verbatim text', '## Structure',
                     '## Implied requirements and rules', '## Uncertain', '## Summary')

# The saved-webpage sidecar spellings html-to-md.py owns; an image under one of these belongs
# to the page of the same stem. Kept in sync by eye — see that file's `owner_of` construction.
SIDECAR_SUFFIXES = ('_files/', '_bestanden/', '_fichiers/', '_Dateien/', '.files/')

# "the owning HTML file is on the chrome route" — best-effort reading: a path segment that IS
# (or contains) one of html-to-md's chrome words marks every image under it as chrome, never
# content. A judgement call: html-to-md drops chrome REGIONS inside a page, not whole pages, so
# there is no existing "chrome route" for a page to inherit — this instrument treats a folder
# name on the route (…/nav/…, …/sidebar-icons/…) as the nearest honest reading of the rule.
CHROME_WORDS = ('nav', 'sidebar', 'footer', 'menu', 'cookie', 'breadcrumb')

WNS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
RNS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
ANS = 'http://schemas.openxmlformats.org/drawingml/2006/main'


def wtag(tag):
    return '{%s}%s' % (WNS, tag)


def atag(tag):
    return '{%s}%s' % (ANS, tag)


def rattr(tag):
    return '{%s}%s' % (RNS, tag)


# --- small utilities -----------------------------------------------------------------------

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def truncate(s, n=CONTEXT_MAX):
    s = re.sub(r'\s+', ' ', s).strip()
    return s if len(s) <= n else s[:n - 1].rstrip() + '…'


def norm_ext(ext):
    ext = ext.lower().lstrip('.')
    return {'jpeg': 'jpg'}.get(ext, ext)


# --- image dimensions from headers only, no Pillow ------------------------------------------

def image_dims(data, ext):
    """(width, height) or (None, None). Best effort; a format this can't read is not fatal —
    the size floor just does not apply to it."""
    try:
        if ext == 'png' and data[:8] == b'\x89PNG\r\n\x1a\n':
            return struct.unpack('>II', data[16:24])
        if ext in ('jpg', 'jpeg'):
            return _jpeg_dims(data)
        if ext == 'gif' and data[:6] in (b'GIF87a', b'GIF89a'):
            return struct.unpack('<HH', data[6:10])
        if ext == 'bmp' and data[:2] == b'BM':
            wd, ht = struct.unpack('<ii', data[18:26])
            return wd, abs(ht)
        if ext == 'webp' and data[:4] == b'RIFF' and data[8:12] == b'WEBP':
            return _webp_dims(data)
    except Exception:  # noqa: BLE001 — a header this can't parse is not a crash
        pass
    return None, None


def _jpeg_dims(data):
    if data[:2] != b'\xff\xd8':
        return None, None
    i = 2
    n = len(data)
    while i + 4 <= n:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:  # SOI/EOI/RST: no length field
            i += 2
            continue
        if i + 4 > n:
            break
        seg_len = struct.unpack('>H', data[i + 2:i + 4])[0]
        is_sof = 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC)
        if is_sof and i + 9 <= n:
            ht, wd = struct.unpack('>HH', data[i + 5:i + 9])
            return wd, ht
        i += 2 + seg_len
    return None, None


def _webp_dims(data):
    fourcc = data[12:16]
    if fourcc == b'VP8 ' and len(data) >= 30:
        wd = data[26] | ((data[27] & 0x3F) << 8)
        ht = data[28] | ((data[29] & 0x3F) << 8)
        return wd, ht
    if fourcc == b'VP8L' and len(data) >= 25:
        bits = data[21] | (data[22] << 8) | (data[23] << 16) | (data[24] << 24)
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if fourcc == b'VP8X' and len(data) >= 30:
        wd = (data[24] | (data[25] << 8) | (data[26] << 16)) + 1
        ht = (data[27] | (data[28] << 8) | (data[29] << 16)) + 1
        return wd, ht
    return None, None


# --- PNG encoder, for PDF-extracted raw pixels (struct + zlib, no Pillow) -------------------

def encode_png(width, height, channels, raw_pixels):
    """raw_pixels: width*height*channels bytes, top-down, no filter applied yet."""
    color_type = {1: 0, 3: 2}.get(channels)
    if color_type is None:
        return None
    stride = width * channels
    out = bytearray()
    for y in range(height):
        out.append(0)  # filter type 0 (none) per scanline
        out += raw_pixels[y * stride:(y + 1) * stride]

    def chunk(tag, payload):
        c = struct.pack('>I', len(payload)) + tag + payload
        return c + struct.pack('>I', zlib.crc32(tag + payload) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color_type, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(out), 6))
            + chunk(b'IEND', b''))


# --- manifest entries -------------------------------------------------------------------------

class Entry:
    __slots__ = ('id', 'sha256', 'ext', 'width', 'height', 'bytes', 'role', 'reason', 'data', 'locations')

    def __init__(self, id_, sha, ext, width, height, size, role, reason, data):
        self.id = id_
        self.sha256 = sha
        self.ext = ext
        self.width = width
        self.height = height
        self.bytes = size
        self.role = role
        self.reason = reason
        self.data = data  # raw bytes to copy to images/<id>.<ext>; None for needs-render
        self.locations = []

    def to_json(self, project, images_out_abs):
        path = None
        if self.role != 'needs-render':
            dest = os.path.join(images_out_abs, '%s.%s' % (self.id, self.ext))
            path = os.path.relpath(dest, project).replace(os.sep, '/')
        # 'file' on a location is bookkeeping for the documents-index `described` column —
        # the spec's manifest shape is {source, kind, ref, context}, so it stays out of here.
        locs = [{k: v for k, v in loc.items() if k != 'file'} for loc in self.locations]
        return {
            'id': self.id, 'sha256': self.sha256, 'ext': self.ext,
            'width': self.width, 'height': self.height, 'bytes': self.bytes,
            'role': self.role, 'reason': self.reason, 'path': path,
            'locations': locs,
        }


def load_old_manifest(manifest_path):
    """sha256 -> id, from a previous run, so ids never shift under a description someone wrote."""
    sha_to_id = {}
    try:
        with open(manifest_path, encoding='utf-8') as f:
            data = json.load(f)
        for row in data.get('images', []):
            if row.get('sha256') and row.get('id'):
                sha_to_id[row['sha256']] = row['id']
    except (OSError, ValueError):
        pass
    return sha_to_id


def make_next_id(used_numbers):
    def _next():
        n = 1
        while n in used_numbers:
            n += 1
        used_numbers.add(n)
        return 'img-%03d' % n
    return _next


# --- collection: loose files + html sidecars + inline-decoded ------------------------------

def path_is_chrome_route(rel):
    parts = re.split(r'[\\/]', rel.lower())
    return any(any(word in part for word in CHROME_WORDS) for part in parts)


def sidecar_owner(rel, page_rels):
    for prel in page_rels:
        stem = posixpath.splitext(prel)[0]
        for suf in SIDECAR_SUFFIXES:
            if rel.startswith(stem + suf):
                return prel
    return None


def collect_loose(src_root, rel_project):
    """Every image file under the source root, sidecars included — (a) and half of (b)."""
    files = _inv.enumerate_root(src_root)
    page_rels = [e['rel'] for e in files if (e['ext'] or '') in ('html', 'htm', 'xhtml')]
    out = []
    for e in files:
        ext = norm_ext(e['ext'] or '')
        if ext not in IMG_EXTS:
            continue
        rel = e['rel']
        try:
            with open(e['path'], 'rb') as f:
                data = f.read()
        except OSError:
            continue
        owner = sidecar_owner(rel, page_rels)
        file_rel = rel_project(e['path'])  # the image's OWN path — for documents-index matching,
        # never the same thing as `source` below, which is the CONTAINER/PAGE a ledger mark is
        # owed against; conflating the two once made a sidecar image's `described` value land on
        # its owning page's documents-index row instead of the image's own row.
        if owner:
            out.append({'data': data, 'ext': ext, 'source': rel_project(os.path.join(src_root, owner)),
                        'kind': 'page', 'ref': owner, 'context': 'sidecar image of ' + owner,
                        'path_hint': rel, 'file': file_rel})
        else:
            out.append({'data': data, 'ext': ext, 'source': file_rel,
                        'kind': 'loose', 'ref': None, 'context': 'loose file in source corpus',
                        'path_hint': rel, 'file': file_rel})
    return out


def collect_inline_decoded(project, text_root, rel_project):
    """Images bin/html-to-md.sh already decoded to <out>/<page>_images/NN.ext — the other half
    of (b): these live under the OUTPUT tree, not the source root, so they are never seen twice."""
    out = []
    if not os.path.isdir(text_root):
        return out
    for dirpath, dirnames, filenames in os.walk(text_root):
        dirnames.sort()
        if not dirpath.endswith('_images'):
            continue
        page_md = dirpath[: -len('_images')] + '.md'
        page_rel = rel_project(page_md) if os.path.exists(page_md) else rel_project(dirpath)
        for fn in sorted(filenames):
            ext = norm_ext(os.path.splitext(fn)[1])
            if ext not in RASTER_EXTS:
                continue
            full = os.path.join(dirpath, fn)
            try:
                with open(full, 'rb') as f:
                    data = f.read()
            except OSError:
                continue
            out.append({'data': data, 'ext': ext, 'source': page_rel, 'kind': 'page',
                        'ref': page_rel, 'context': 'inline image decoded from ' + page_rel,
                        'path_hint': fn})
    return out


# --- collection: pptx ---------------------------------------------------------------------------

def pptx_slide_texts(zf, slide_name):
    try:
        root = ET.fromstring(zf.read(slide_name))
    except (KeyError, ET.ParseError):
        return []
    return [t.text for t in root.iter(atag('t')) if t.text]


def collect_pptx(path, rel):
    """Returns (occurrences, per_slide) — per_slide: {slide_no: {'texts': [...], 'images': []}}
    (images filled in by the caller, once ids are assigned)."""
    occ = []
    per_slide = {}
    try:
        zf = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        return occ, per_slide
    slide_re = re.compile(r'^ppt/slides/slide(\d+)\.xml$')
    with zf:
        names = set(zf.namelist())
        slide_nums = sorted(int(m.group(1)) for m in
                            (slide_re.match(n) for n in names) if m)
        for n in slide_nums:
            slide_name = 'ppt/slides/slide%d.xml' % n
            rels_name = 'ppt/slides/_rels/slide%d.xml.rels' % n
            texts = pptx_slide_texts(zf, slide_name)
            context = truncate(' '.join(texts)) if texts else '(no text on this slide)'
            per_slide[n] = {'texts': texts, 'images': []}
            if rels_name not in names:
                continue
            try:
                rroot = ET.fromstring(zf.read(rels_name))
            except ET.ParseError:
                continue
            for rel_el in rroot:
                rtype = rel_el.get('Type', '')
                target = rel_el.get('Target', '')
                if not rtype.endswith('/image') or not target:
                    continue
                media_path = posixpath.normpath(posixpath.join('ppt/slides', target))
                if media_path not in names:
                    continue
                data = zf.read(media_path)
                ext = norm_ext(posixpath.splitext(media_path)[1])
                occ.append({'data': data, 'ext': ext, 'source': rel, 'kind': 'slide', 'ref': n,
                            'context': context, 'path_hint': media_path, 'slide_no': n})
    return occ, per_slide


# --- collection: docx, best effort ---------------------------------------------------------------

def collect_docx(path, rel):
    occ = []
    try:
        zf = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        return occ
    with zf:
        names = set(zf.namelist())
        rels_map = {}
        if 'word/_rels/document.xml.rels' in names:
            try:
                rroot = ET.fromstring(zf.read('word/_rels/document.xml.rels'))
                for rel_el in rroot:
                    if rel_el.get('Type', '').endswith('/image'):
                        target = rel_el.get('Target', '')
                        rels_map[rel_el.get('Id')] = posixpath.normpath(posixpath.join('word', target))
            except ET.ParseError:
                pass
        if 'word/document.xml' not in names:
            return occ
        try:
            root = ET.fromstring(zf.read('word/document.xml'))
        except ET.ParseError:
            return occ
        body = root.find(wtag('body'))
        if body is None:
            return occ
        current_heading = '(no preceding heading)'
        for p in body.iter(wtag('p')):
            style = p.find('.//' + wtag('pStyle'))
            text = ''.join(t.text or '' for t in p.iter(wtag('t')))
            if style is not None and (style.get(wtag('val')) or '').lower().startswith('heading') and text.strip():
                current_heading = text.strip()
                continue
            for blip in p.iter(atag('blip')):
                rid = blip.get(rattr('embed'))
                media_path = rels_map.get(rid)
                if not media_path or media_path not in names:
                    continue
                data = zf.read(media_path)
                ext = norm_ext(posixpath.splitext(media_path)[1])
                occ.append({'data': data, 'ext': ext, 'source': rel, 'kind': 'docx', 'ref': None,
                            'context': 'under heading: ' + current_heading, 'path_hint': media_path})
    return occ


# --- collection: pdf, best effort, stdlib only ---------------------------------------------------

def _pdf_read_dict(data, start):
    """start points at the '<<' opener. Returns (dict_text, index just past the matching '>>')."""
    depth = 0
    i = start
    n = len(data)
    dict_start = i
    while i < n - 1:
        if data[i:i + 2] == b'<<':
            depth += 1
            i += 2
            continue
        if data[i:i + 2] == b'>>':
            depth -= 1
            i += 2
            if depth == 0:
                return data[dict_start:i], i
            continue
        i += 1
    return data[dict_start:], n


PDF_OBJ_RE = re.compile(rb'(\d+)\s+0\s+obj')


def collect_pdf(path, rel):
    occ = []
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return occ
    for m in PDF_OBJ_RE.finditer(data):
        objnum = m.group(1).decode('ascii')
        j = m.end()
        while j < len(data) and data[j:j + 1].isspace():
            j += 1
        if data[j:j + 2] != b'<<':
            continue
        dict_text, dict_end = _pdf_read_dict(data, j)
        if not re.search(rb'/Subtype\s*/Image', dict_text):
            continue
        k = dict_end
        while k < len(data) and data[k:k + 1].isspace():
            k += 1
        if data[k:k + 6] != b'stream':
            continue
        k += 6
        if data[k:k + 2] == b'\r\n':
            k += 2
        elif data[k:k + 1] in (b'\n', b'\r'):
            k += 1
        length_m = re.search(rb'/Length\s+(\d+)\b', dict_text)
        if length_m:
            stream_end = k + int(length_m.group(1))
        else:
            es = data.find(b'endstream', k)
            stream_end = es if es != -1 else len(data)
        stream = data[k:stream_end]

        filt_m = re.search(rb'/Filter\s*/(\w+)', dict_text)
        filt = filt_m.group(1).decode('ascii') if filt_m else ''
        width_m = re.search(rb'/Width\s+(\d+)', dict_text)
        height_m = re.search(rb'/Height\s+(\d+)', dict_text)
        pw = int(width_m.group(1)) if width_m else None
        ph = int(height_m.group(1)) if height_m else None

        if filt == 'DCTDecode':
            occ.append({'data': stream, 'ext': 'jpg', 'source': rel, 'kind': 'pdf', 'ref': 'obj %s' % objnum,
                        'context': 'PDF image object %s (DCTDecode → raw JPEG)' % objnum,
                        'path_hint': 'obj%s.jpg' % objnum})
            continue

        if filt == 'FlateDecode' and b'/DecodeParms' not in dict_text:
            cs_m = re.search(rb'/ColorSpace\s*/(\w+)', dict_text)
            bpc_m = re.search(rb'/BitsPerComponent\s+(\d+)', dict_text)
            cs = cs_m.group(1).decode('ascii') if cs_m else ''
            bpc = int(bpc_m.group(1)) if bpc_m else None
            channels = {'DeviceRGB': 3, 'DeviceGray': 1}.get(cs)
            if channels and bpc == 8 and pw and ph:
                try:
                    raw = zlib.decompress(stream)
                except zlib.error:
                    raw = None
                if raw is not None and len(raw) == pw * ph * channels:
                    png = encode_png(pw, ph, channels, raw)
                    if png:
                        occ.append({'data': png, 'ext': 'png', 'source': rel, 'kind': 'pdf',
                                    'ref': 'obj %s' % objnum,
                                    'context': 'PDF image object %s (FlateDecode → PNG re-encoded)' % objnum,
                                    'path_hint': 'obj%s.png' % objnum})
                        continue
        # anything else: counted, not silently dropped
        occ.append({'data': stream, 'ext': 'bin', 'source': rel, 'kind': 'pdf', 'ref': 'obj %s' % objnum,
                    'context': 'PDF image object %s: filter %s not supported here — needs-render '
                               '(pdftoppm/mutool)' % (objnum, filt or '(none)'),
                    'path_hint': 'obj%s.bin' % objnum, 'needs_render': True})
    return occ


# --- the run -----------------------------------------------------------------------------------

def main(argv):
    if len(argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    project = os.path.abspath(argv[1])
    src_root = os.path.abspath(argv[2])
    images_out = os.path.abspath(argv[3])
    text_root = os.path.abspath(argv[4])
    flags = argv[5:]
    do_check = '--check' in flags
    do_inline = '--inline' in flags
    force = '--force' in flags

    def rel_project(p):
        return os.path.relpath(p, project).replace(os.sep, '/')

    manifest_path = os.path.join(images_out, 'manifest.json')
    sha_to_id = {} if force else load_old_manifest(manifest_path)
    used_numbers = set(int(v.split('-')[1]) for v in sha_to_id.values())
    next_id = make_next_id(used_numbers)

    entries = {}      # sha256 -> Entry
    id_index = {}     # img-NNN -> Entry
    order = []        # sha256, first-seen (deterministic) order
    total_occurrences = 0

    def ingest(occ):
        sha = sha256_bytes(occ['data'])
        if sha not in entries:
            id_ = sha_to_id.get(sha) or next_id()
            sha_to_id[sha] = id_
            ext = occ['ext']
            wd = ht = None
            if occ.get('needs_render'):
                role, reason = 'needs-render', occ['context']
            elif ext in VECTOR_EXTS:
                role, reason = 'vector', 'svg — read as text, not described here'
            else:
                wd, ht = image_dims(occ['data'], ext)
                long_edge = max(wd or 0, ht or 0)
                if wd and long_edge < TINY_LONG_EDGE:
                    role, reason = 'chrome', 'tiny (%dx%d, long edge < %dpx)' % (wd, ht, TINY_LONG_EDGE)
                elif path_is_chrome_route(occ.get('path_hint') or occ['source']):
                    role, reason = 'chrome', 'owning file is on the chrome route (%s)' % occ.get('path_hint', '')
                else:
                    role, reason = 'content', None
            data = occ['data'] if role != 'needs-render' else None
            entry = Entry(id_, sha, ext, wd, ht, len(occ['data']), role, reason, data)
            entries[sha] = entry
            id_index[id_] = entry
            order.append(sha)
        entry = entries[sha]
        entry.locations.append({'source': occ['source'], 'kind': occ['kind'], 'ref': occ['ref'],
                                 'context': truncate(occ['context']), 'file': occ.get('file')})
        return entry

    # (a) + (b, sidecar half)
    for occ in collect_loose(src_root, rel_project):
        ingest(occ)
        total_occurrences += 1
    # (b, inline-decoded half)
    for occ in collect_inline_decoded(project, text_root, rel_project):
        ingest(occ)
        total_occurrences += 1

    # (c) containers
    files = _inv.enumerate_root(src_root)
    slide_data_by_deck = {}  # deck rel -> per_slide
    for e in files:
        ext = (e['ext'] or '').lower()
        rel_src = rel_project(e['path'])
        if ext == 'pptx':
            occ_list, per_slide = collect_pptx(e['path'], rel_src)
            for occ in occ_list:
                entry = ingest(occ)
                total_occurrences += 1
                per_slide[occ['slide_no']]['images'].append(entry.id)
            slide_data_by_deck[rel_src] = per_slide
        elif ext == 'docx':
            for occ in collect_docx(e['path'], rel_src):
                ingest(occ)
                total_occurrences += 1

    # (d) pdf
    for e in files:
        if (e['ext'] or '').lower() != 'pdf':
            continue
        rel_src = rel_project(e['path'])
        for occ in collect_pdf(e['path'], rel_src):
            ingest(occ)
            total_occurrences += 1

    # --- write per-slide markdown + slides.json -------------------------------------------
    for deck_rel, per_slide in slide_data_by_deck.items():
        deck_stem = os.path.splitext(os.path.basename(deck_rel))[0]
        deck_dir = os.path.join(text_root, deck_stem)
        os.makedirs(deck_dir, exist_ok=True)
        slides_json = []
        for n in sorted(per_slide):
            info = per_slide[n]
            slide_md = os.path.join(deck_dir, 'slide%02d.md' % n)
            lines = ['<!-- images-to-md: slide=%d images=%d -->' % (n, len(info['images'])),
                     '**Source:** `%s` — slide %d' % (deck_rel, n), '', '---', '']
            for t in info['texts']:
                lines.append(t)
                lines.append('')
            for img_id in info['images']:
                ent = id_index.get(img_id)
                if ent is None or ent.role == 'needs-render':
                    continue
                dest = os.path.join(images_out, '%s.%s' % (ent.id, ent.ext))
                rel_img = os.path.relpath(dest, deck_dir).replace(os.sep, '/')
                lines.append('![](%s)' % rel_img)
                lines.append('')
            content = '\n'.join(lines).rstrip('\n') + '\n'
            existing = None
            if os.path.exists(slide_md):
                with open(slide_md, encoding='utf-8') as f:
                    existing = f.read()
            if existing != content:
                with open(slide_md, 'w', encoding='utf-8') as f:
                    f.write(content)
            slides_json.append({'slide': n, 'text': info['texts'], 'images': info['images']})
        sj_path = os.path.join(deck_dir, 'slides.json')
        new_sj = json.dumps(slides_json, indent=2, ensure_ascii=False) + '\n'
        old_sj = None
        if os.path.exists(sj_path):
            with open(sj_path, encoding='utf-8') as f:
                old_sj = f.read()
        if old_sj != new_sj:
            with open(sj_path, 'w', encoding='utf-8') as f:
                f.write(new_sj)

    # --- copy unique images, write manifest.json --------------------------------------------
    os.makedirs(images_out, exist_ok=True)
    n_content = n_chrome = n_vector = n_needs_render = 0
    for sha in order:
        ent = entries[sha]
        if ent.role == 'content':
            n_content += 1
        elif ent.role == 'chrome':
            n_chrome += 1
        elif ent.role == 'vector':
            n_vector += 1
        elif ent.role == 'needs-render':
            n_needs_render += 1
        if ent.data is not None:
            dest = os.path.join(images_out, '%s.%s' % (ent.id, ent.ext))
            write_needed = True
            if os.path.exists(dest):
                try:
                    with open(dest, 'rb') as f:
                        write_needed = sha256_bytes(f.read()) != ent.sha256
                except OSError:
                    write_needed = True
            if write_needed:
                with open(dest, 'wb') as f:
                    f.write(ent.data)

    manifest = {
        'generated': time.strftime('%Y-%m-%d'),
        'source_root': rel_project(src_root),
        'counts': {'content': n_content, 'chrome': n_chrome, 'vector': n_vector,
                   'needs_render': n_needs_render, 'unique': len(order),
                   'duplicates_folded': total_occurrences - len(order)},
        'images': [entries[s].to_json(project, images_out) for s in order],
    }
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')

    # --- worklist.md --------------------------------------------------------------------------
    worklist_path = os.path.join(images_out, 'worklist.md')
    lines = ['# Image worklist — one description per unique content image', '',
             'Generated by `bin/images-to-md.sh` on %s over `%s`. Every image below is unique '
             '(deduped by sha256) and lists every location it appears at. Write the description '
             'file at the exact path shown, per the template in `skills/image-transcription.md`, '
             'then run `bin/images-to-md.sh <project> --check`.' % (time.strftime('%Y-%m-%d'), rel_project(src_root)),
             '']
    content_shas = [s for s in order if entries[s].role == 'content']
    for sha in content_shas:
        ent = entries[sha]
        dims = '%sx%s' % (ent.width, ent.height) if ent.width else 'dimensions unknown'
        lines.append('## %s — %s, .%s' % (ent.id, dims, ent.ext))
        lines.append('')
        for loc in ent.locations:
            ref = (' — %s %s' % (loc['kind'], loc['ref'])) if loc['ref'] is not None else ''
            lines.append('- `%s`%s: %s' % (loc['source'], ref, loc['context']))
        lines.append('')
        lines.append('Describe: `%s`' % rel_project(os.path.join(images_out, '%s.md' % ent.id)))
        lines.append('')
    other_shas = [s for s in order if entries[s].role != 'content']
    if other_shas:
        lines.append('## Other images (not owed a description)')
        lines.append('')
        for sha in other_shas:
            ent = entries[sha]
            lines.append('- %s — %s (%s)' % (ent.id, ent.role, ent.reason or ''))
    with open(worklist_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines).rstrip('\n') + '\n')

    dup_folded = total_occurrences - len(order)
    print('images-to-md: %d unique image(s) — content %d, chrome %d, vector %d, needs-render %d '
          '(duplicates folded: %d)' % (len(order), n_content, n_chrome, n_vector, n_needs_render, dup_folded))
    print('  manifest: %s' % rel_project(manifest_path))
    print('  worklist: %s' % rel_project(worklist_path))
    print('Images to describe: %d%s' % (
        n_content,
        (' — write analysis/knowledge-base/images/<id>.md per the template in '
         'skills/image-transcription.md, then: bin/images-to-md.sh <p> --check') if n_content else ''))

    if do_check or do_inline:
        return run_check(project, images_out, entries, order, do_inline=(do_inline or do_check))
    return 0


# --- --check -------------------------------------------------------------------------------

def read_description(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError:
        return None


def check_description(text):
    if text is None or not text.strip():
        return False
    return all(h in text for h in REQUIRED_HEADINGS)


def run_check(project, images_out, entries, order, do_inline):
    content = [(s, entries[s]) for s in order if entries[s].role == 'content']
    missing = []
    for sha, ent in content:
        desc_path = os.path.join(images_out, '%s.md' % ent.id)
        if not check_description(read_description(desc_path)):
            missing.append(ent.id)
    described = len(content) - len(missing)
    print('')
    print('images-to-md --check: described %d of %d' % (described, len(content)))
    if missing:
        print('  missing or incomplete: %s' % ', '.join(sorted(missing)))
        return 1

    if do_inline and content:
        n_inlined = inline_descriptions(project, images_out, entries, order)
        print('  inlined description excerpts into %d file(s)' % n_inlined)

    update_documents_index(project, images_out, entries, order)

    owners = {}  # owning file rel path -> set of image ids it owes
    for sha, ent in content:
        for loc in ent.locations:
            owners.setdefault(loc['source'], set()).add(ent.id)
    if owners:
        print('')
        print('  Coverage complete. Ledger marks owed, per source file:')
        for owner in sorted(owners):
            print('    bin/source-ledger.sh mark <p> \'%s\' --artifact analysis/knowledge-base/images/manifest.json '
                  '--evidence "<fill in>" --media %d --by <who>' % (owner, len(owners[owner])))
    return 0


# --- --inline: quote the description right under the image line --------------------------------

MARKER_RE = re.compile(r'^<!-- image: (img-\d+) — description: (\S+) -->\s*$')
BEGIN_RE = re.compile(r'^<!-- image:begin (img-\d+) -->\s*$')
END_RE = re.compile(r'^<!-- image:end (img-\d+) -->\s*$')
IMG_LINE_RE = re.compile(r'!\[[^\]]*\]\(([^)]+)\)')


def extract_section(text, heading):
    m = re.search(r'^%s\s*$' % re.escape(heading), text, re.M)
    if not m:
        return ''
    start = m.end()
    m2 = re.search(r'^## ', text[start:], re.M)
    end = start + m2.start() if m2 else len(text)
    return text[start:end].strip('\n')


def resolve_image_ref(md_path, ref, project):
    if '://' in ref or ref.startswith('data:'):
        return None
    ref_clean = re.sub(r'[?#].*$', '', ref)
    cand = os.path.normpath(os.path.join(os.path.dirname(md_path), ref_clean))
    if os.path.exists(cand):
        return cand
    cand2 = os.path.normpath(os.path.join(project, ref_clean))
    if os.path.exists(cand2):
        return cand2
    return None


def sha_of_file(path):
    try:
        with open(path, 'rb') as f:
            return sha256_bytes(f.read())
    except OSError:
        return None


def inline_descriptions(project, images_out, entries, order):
    id_by_sha = {s: entries[s].id for s in order}
    n_files = 0
    text_root = os.path.join(project, 'analysis', 'knowledge-base', 'text')
    if not os.path.isdir(text_root):
        return 0
    for dirpath, dirnames, filenames in os.walk(text_root):
        dirnames.sort()
        for fn in sorted(filenames):
            if not fn.endswith('.md'):
                continue
            md_path = os.path.join(dirpath, fn)
            with open(md_path, encoding='utf-8') as f:
                lines = f.read().split('\n')
            changed = _inline_one_file(md_path, lines, id_by_sha, images_out, project)
            if changed is not None:
                with open(md_path, 'w', encoding='utf-8') as f:
                    f.write('\n'.join(changed))
                n_files += 1
    return n_files


def _inline_one_file(md_path, lines, id_by_sha, images_out, project):
    out = []
    changed = False
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        i += 1
        m = IMG_LINE_RE.search(line)
        if not m:
            continue
        target = resolve_image_ref(md_path, m.group(1), project)
        if not target:
            continue
        img_id = id_by_sha.get(sha_of_file(target))
        if not img_id:
            continue

        j = i
        if j < n and MARKER_RE.match(lines[j] or ''):
            out.append(lines[j])
            i = j + 1
        else:
            rel_desc = os.path.relpath(os.path.join(images_out, '%s.md' % img_id), project).replace(os.sep, '/')
            out.append('<!-- image: %s — description: %s -->' % (img_id, rel_desc))
            changed = True
        j = i

        block_start = block_end = None
        if j < n and BEGIN_RE.match(lines[j] or ''):
            block_start = j
            k = j + 1
            while k < n and not END_RE.match(lines[k] or ''):
                k += 1
            block_end = k

        desc_text = read_description(os.path.join(images_out, '%s.md' % img_id))
        if check_description(desc_text):
            verbatim = extract_section(desc_text, '## Verbatim text')
            summary = extract_section(desc_text, '## Summary')
            body = []
            if verbatim:
                body += ['**Verbatim text**'] + verbatim.split('\n') + ['']
            if summary:
                body += ['**Summary**'] + summary.split('\n')
            quoted = ['> ' + l if l else '>' for l in body]
            new_block = ['<!-- image:begin %s -->' % img_id] + quoted + ['<!-- image:end %s -->' % img_id]
            if block_start is not None:
                if lines[block_start:block_end + 1] != new_block:
                    changed = True
                i = block_end + 1
            else:
                changed = True
                i = j
            out += new_block
        elif block_start is not None:
            i = block_end + 1  # a regressed/missing description: drop the stale quoted block
            changed = True
        else:
            i = j
    return out if changed else None


# --- documents-index.md: append (or refresh) a `described` column ------------------------------

def _cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def update_documents_index(project, images_out, entries, order):
    idx_path = os.path.join(project, 'analysis', 'knowledge-base', 'documents-index.md')
    if not os.path.exists(idx_path):
        return
    with open(idx_path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    header_i = next((i for i, l in enumerate(lines) if l.startswith('| path |')), None)
    if header_i is None or header_i + 1 >= len(lines):
        return

    by_path = {}  # the image FILE's own project-relative path -> Entry (never the owning
    # container/page — that collision once made a sidecar image's row read its page's status)
    for sha in order:
        ent = entries[sha]
        for loc in ent.locations:
            if loc.get('file'):
                by_path[loc['file']] = ent

    def described_value(row_path):
        for src_rel, ent in by_path.items():
            if src_rel == row_path or src_rel.endswith('/' + row_path):
                if ent.role != 'content':
                    return ent.role
                desc_path = os.path.join(images_out, '%s.md' % ent.id)
                return 'yes' if check_description(read_description(desc_path)) else 'owed'
        return None

    header_cells = _cells(lines[header_i])
    has_described = bool(header_cells) and header_cells[-1] == 'described'
    base_cells = header_cells[:-1] if has_described else header_cells
    if 'path' not in base_cells:
        return
    path_idx = base_cells.index('path')

    lines[header_i] = '| ' + ' | '.join(base_cells + ['described']) + ' |'
    lines[header_i + 1] = '|' + '---|' * (len(base_cells) + 1)

    i = header_i + 2
    while i < len(lines) and lines[i].strip().startswith('|'):
        row_cells = _cells(lines[i])
        if has_described and len(row_cells) == len(base_cells) + 1:
            row_cells = row_cells[:-1]
        if len(row_cells) < len(base_cells):
            i += 1
            continue
        row_cells = row_cells[:len(base_cells)]
        val = described_value(row_cells[path_idx]) if path_idx < len(row_cells) else None
        lines[i] = '| ' + ' | '.join(row_cells + [val or '—']) + ' |'
        i += 1

    with open(idx_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


if __name__ == '__main__':
    sys.exit(main(sys.argv))
