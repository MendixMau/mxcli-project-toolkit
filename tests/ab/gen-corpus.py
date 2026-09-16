#!/usr/bin/env python3
"""gen-corpus.py — render answer-key.json into a synthetic "webpage, complete" requirements corpus.

    gen-corpus.py <out-dir> [--seed N] [--key answer-key.json] [--no-manifest]

Deterministic for a given seed. Python 3 standard library only (no Pillow): PNGs are written
with zlib+struct, JPEGs with a tiny baseline encoder, text is drawn with a built-in 5x7 bitmap
font at 2-3x scale so a vision model can read it.

Everything is fictional — "Harbour Berth Booking" is not a product and the port authority
does not exist. The corpus is the fixture side of an A/B experiment: agents under test get
<out-dir> (minus MANIFEST.json); the scorer gets answer-key.json + MANIFEST.json.
"""
import argparse
import base64
import hashlib
import json
import math
import os
import random
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------------------
# 5x7 bitmap font (uppercase; lowercase is drawn as uppercase)
# ----------------------------------------------------------------------------------------
FONT = {
 'A': ["01110","10001","10001","11111","10001","10001","10001"],
 'B': ["11110","10001","10001","11110","10001","10001","11110"],
 'C': ["01111","10000","10000","10000","10000","10000","01111"],
 'D': ["11110","10001","10001","10001","10001","10001","11110"],
 'E': ["11111","10000","10000","11110","10000","10000","11111"],
 'F': ["11111","10000","10000","11110","10000","10000","10000"],
 'G': ["01111","10000","10000","10111","10001","10001","01111"],
 'H': ["10001","10001","10001","11111","10001","10001","10001"],
 'I': ["01110","00100","00100","00100","00100","00100","01110"],
 'J': ["00111","00010","00010","00010","00010","10010","01100"],
 'K': ["10001","10010","10100","11000","10100","10010","10001"],
 'L': ["10000","10000","10000","10000","10000","10000","11111"],
 'M': ["10001","11011","10101","10101","10001","10001","10001"],
 'N': ["10001","11001","10101","10011","10001","10001","10001"],
 'O': ["01110","10001","10001","10001","10001","10001","01110"],
 'P': ["11110","10001","10001","11110","10000","10000","10000"],
 'Q': ["01110","10001","10001","10001","10101","10010","01101"],
 'R': ["11110","10001","10001","11110","10100","10010","10001"],
 'S': ["01111","10000","10000","01110","00001","00001","11110"],
 'T': ["11111","00100","00100","00100","00100","00100","00100"],
 'U': ["10001","10001","10001","10001","10001","10001","01110"],
 'V': ["10001","10001","10001","10001","01010","01010","00100"],
 'W': ["10001","10001","10001","10101","10101","11011","10001"],
 'X': ["10001","10001","01010","00100","01010","10001","10001"],
 'Y': ["10001","10001","01010","00100","00100","00100","00100"],
 'Z': ["11111","00001","00010","00100","01000","10000","11111"],
 '0': ["01110","10001","10011","10101","11001","10001","01110"],
 '1': ["00100","01100","00100","00100","00100","00100","01110"],
 '2': ["01110","10001","00001","00010","00100","01000","11111"],
 '3': ["11111","00010","00100","00010","00001","10001","01110"],
 '4': ["00010","00110","01010","10010","11111","00010","00010"],
 '5': ["11111","10000","11110","00001","00001","10001","01110"],
 '6': ["00110","01000","10000","11110","10001","10001","01110"],
 '7': ["11111","00001","00010","00100","01000","01000","01000"],
 '8': ["01110","10001","10001","01110","10001","10001","01110"],
 '9': ["01110","10001","10001","01111","00001","00010","01100"],
 ' ': ["00000","00000","00000","00000","00000","00000","00000"],
 '.': ["00000","00000","00000","00000","00000","01100","01100"],
 ',': ["00000","00000","00000","00000","01100","00100","01000"],
 ':': ["00000","01100","01100","00000","01100","01100","00000"],
 ';': ["00000","01100","01100","00000","01100","00100","01000"],
 '-': ["00000","00000","00000","11111","00000","00000","00000"],
 '(': ["00100","01000","10000","10000","10000","01000","00100"],
 ')': ["00100","00010","00001","00001","00001","00010","00100"],
 '/': ["00001","00001","00010","00100","01000","10000","10000"],
 "'": ["00100","00100","01000","00000","00000","00000","00000"],
 '*': ["00000","10101","01110","11111","01110","10101","00000"],
 '!': ["00100","00100","00100","00100","00100","00000","00100"],
 '?': ["01110","10001","00001","00010","00100","00000","00100"],
 '%': ["11001","11001","00010","00100","01000","10011","10011"],
 '=': ["00000","00000","11111","00000","11111","00000","00000"],
 '+': ["00000","00100","00100","11111","00100","00100","00000"],
 '_': ["00000","00000","00000","00000","00000","00000","11111"],
 '<': ["00010","00100","01000","10000","01000","00100","00010"],
 '>': ["01000","00100","00010","00001","00010","00100","01000"],
 '[': ["01110","01000","01000","01000","01000","01000","01110"],
 ']': ["01110","00010","00010","00010","00010","00010","01110"],
 '|': ["00100","00100","00100","00100","00100","00100","00100"],
 '#': ["01010","01010","11111","01010","11111","01010","01010"],
 '&': ["01100","10010","10100","01000","10101","10010","01101"],
 '@': ["01110","10001","10111","10101","10111","10000","01110"],
 'v': ["00000","00000","10001","10001","01010","01010","00100"],
}


class Canvas:
    """RGB byte canvas with rectangle, text and noise primitives. No dependencies."""

    def __init__(self, w, h, color=(255, 255, 255)):
        self.w, self.h = w, h
        self.px = bytearray(bytes(color) * (w * h))

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 3
            self.px[i:i + 3] = bytes(c)

    def rect(self, x, y, w, h, c, fill=True):
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.w, x + w), min(self.h, y + h)
        if x1 <= x0 or y1 <= y0:
            return
        if fill:
            row = bytes(c) * (x1 - x0)
            for yy in range(y0, y1):
                i = (yy * self.w + x0) * 3
                self.px[i:i + (x1 - x0) * 3] = row
        else:
            self.rect(x, y, w, 1, c); self.rect(x, y + h - 1, w, 1, c)
            self.rect(x, y, 1, h, c); self.rect(x + w - 1, y, 1, h, c)

    def text(self, x, y, s, scale=2, color=(20, 20, 20)):
        cx = x
        for ch in s:
            up = ch.upper()
            g = FONT.get(up) or FONT.get(ch) or FONT['?']
            for ry, row in enumerate(g):
                for rx, bit in enumerate(row):
                    if bit == '1':
                        self.rect(cx + rx * scale, y + ry * scale, scale, scale, color)
            cx += 6 * scale
        return cx

    def text_width(self, s, scale=2):
        return len(s) * 6 * scale

    def noise(self, rng, amplitude, x=0, y=0, w=None, h=None, every=1):
        """Add +-amplitude noise to a region; `every` thins it out (size control)."""
        w = self.w if w is None else w
        h = self.h if h is None else h
        px = self.px
        W = self.w
        for yy in range(y, min(self.h, y + h)):
            base = yy * W
            for xx in range(x, min(self.w, x + w), every):
                i = (base + xx) * 3
                d = rng.randint(-amplitude, amplitude)
                for k in range(3):
                    v = px[i + k] + d
                    px[i + k] = 0 if v < 0 else 255 if v > 255 else v

    def gray(self):
        out = bytearray(self.w * self.h)
        px = self.px
        for i in range(self.w * self.h):
            j = i * 3
            out[i] = (px[j] * 299 + px[j + 1] * 587 + px[j + 2] * 114) // 1000
        return out


# ----------------------------------------------------------------------------------------
# PNG (zlib + struct)
# ----------------------------------------------------------------------------------------
def png_bytes(canvas):
    w, h, px = canvas.w, canvas.h, canvas.px
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += px[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))


# ----------------------------------------------------------------------------------------
# Baseline JPEG, grayscale, one scan. The Huffman tables are deliberately trivial (fixed-length
# canonical codes written into DHT) — valid for any decoder, no memorised spec tables needed.
# ----------------------------------------------------------------------------------------
_STD_LUM_Q = [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
              14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
              18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
              49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]


def _zigzag():
    order = []
    for s in range(15):
        diag = [(r, s - r) for r in range(8) if 0 <= s - r < 8]
        if s % 2 == 0:
            diag.reverse()
        order += [r * 8 + c for r, c in diag]
    return order


_ZZ = _zigzag()
_COS = [[math.cos((2 * x + 1) * u * math.pi / 16) for x in range(8)] for u in range(8)]
_CU = [1 / math.sqrt(2)] + [1.0] * 7
_DC_VALUES = list(range(12))
_AC_VALUES = [0x00, 0xF0] + [(r << 4) | s for r in range(16) for s in range(1, 11)]
_DC_CODES = {v: (i, 4) for i, v in enumerate(_DC_VALUES)}           # 12 codes, 4 bits each
_AC_CODES = {v: (i, 8) for i, v in enumerate(_AC_VALUES)}           # 162 codes, 8 bits each


class _Bits:
    def __init__(self):
        self.out = bytearray(); self.acc = 0; self.n = 0

    def write(self, code, length):
        self.acc = (self.acc << length) | code
        self.n += length
        while self.n >= 8:
            b = (self.acc >> (self.n - 8)) & 0xFF
            self.out.append(b)
            if b == 0xFF:
                self.out.append(0)
            self.n -= 8
            self.acc &= (1 << self.n) - 1

    def flush(self):
        if self.n:
            pad = 8 - self.n
            self.write(((1 << pad) - 1), pad)


def _dht(tc_th, bits_index, values):
    bits = [0] * 16
    bits[bits_index - 1] = len(values)
    body = bytes([tc_th]) + bytes(bits) + bytes(values)
    return b'\xFF\xC4' + struct.pack('>H', len(body) + 2) + body


def jpeg_bytes(w, h, gray, quality=70):
    q = 5000 / quality if quality < 50 else 200 - quality * 2
    Q = [max(1, min(255, int((v * q + 50) / 100))) for v in _STD_LUM_Q]
    out = bytearray(b'\xFF\xD8')
    out += b'\xFF\xE0' + struct.pack('>H', 16) + b'JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'
    out += b'\xFF\xDB' + struct.pack('>H', 67) + b'\x00' + bytes(Q[i] for i in _ZZ)
    out += b'\xFF\xC0' + struct.pack('>HBHHB', 11, 8, h, w, 1) + b'\x01\x11\x00'
    out += _dht(0x00, 4, _DC_VALUES) + _dht(0x10, 8, _AC_VALUES)
    out += b'\xFF\xDA' + struct.pack('>HB', 8, 1) + b'\x01\x00\x00\x3F\x00'
    bw = _Bits()
    prev_dc = 0
    blk = [0.0] * 64
    tmp = [0.0] * 64
    for by in range(0, h, 8):
        for bx in range(0, w, 8):
            for y in range(8):
                yy = min(h - 1, by + y)
                for x in range(8):
                    xx = min(w - 1, bx + x)
                    blk[y * 8 + x] = gray[yy * w + xx] - 128.0
            # separable DCT: rows then columns
            for y in range(8):
                row = blk[y * 8:y * 8 + 8]
                for v in range(8):
                    cv = _COS[v]
                    tmp[y * 8 + v] = sum(row[x] * cv[x] for x in range(8))
            coeffs = [0] * 64
            for u in range(8):
                cu = _COS[u]
                for v in range(8):
                    s = sum(tmp[y * 8 + v] * cu[y] for y in range(8))
                    val = 0.25 * _CU[u] * _CU[v] * s
                    coeffs[u * 8 + v] = int(round(val / Q[u * 8 + v]))
            zz = [coeffs[i] for i in _ZZ]
            diff = zz[0] - prev_dc
            prev_dc = zz[0]
            s = abs(diff).bit_length()
            code, ln = _DC_CODES[s]
            bw.write(code, ln)
            if s:
                bw.write(diff if diff > 0 else (diff + (1 << s) - 1), s)
            run = 0
            for k in range(1, 64):
                v = zz[k]
                if v == 0:
                    run += 1
                    continue
                while run > 15:
                    c, l = _AC_CODES[0xF0]; bw.write(c, l); run -= 16
                s = abs(v).bit_length()
                c, l = _AC_CODES[(run << 4) | s]
                bw.write(c, l)
                bw.write(v if v > 0 else (v + (1 << s) - 1), s)
                run = 0
            if run:
                c, l = _AC_CODES[0x00]; bw.write(c, l)
    bw.flush()
    out += bw.out + b'\xFF\xD9'
    return bytes(out)


# ----------------------------------------------------------------------------------------
# Picture content: "photos" of a fictional port, and mock screens
# ----------------------------------------------------------------------------------------
def scene(rng, w, h, noise_amp=6, noise_every=1):
    c = Canvas(w, h)
    horizon = int(h * rng.uniform(0.35, 0.55))
    sky_top = (rng.randint(120, 180), rng.randint(160, 210), rng.randint(210, 245))
    for y in range(horizon):
        t = y / max(1, horizon)
        col = tuple(int(sky_top[k] * (1 - t) + 235 * t) for k in range(3))
        c.rect(0, y, w, 1, col)
    sea = (rng.randint(20, 60), rng.randint(70, 120), rng.randint(110, 160))
    for y in range(horizon, h):
        t = (y - horizon) / max(1, h - horizon)
        wave = int(6 * math.sin(y * 0.35 + rng.random() * 0.2))
        col = tuple(max(0, min(255, int(sea[k] * (1 - 0.4 * t) + wave))) for k in range(3))
        c.rect(0, y, w, 1, col)
    # quay, containers, cranes
    quay_y = horizon + rng.randint(5, 25)
    c.rect(0, quay_y, w, rng.randint(8, 18), (90, 90, 95))
    for _ in range(rng.randint(4, 14)):
        cw, chh = rng.randint(12, 40), rng.randint(8, 16)
        c.rect(rng.randint(0, w - cw), quay_y - chh, cw, chh,
               (rng.randint(120, 220), rng.randint(40, 120), rng.randint(30, 80)))
    for _ in range(rng.randint(1, 4)):
        x = rng.randint(10, w - 30)
        top = rng.randint(10, horizon - 10)
        c.rect(x, top, 4, quay_y - top, (200, 60, 40))
        c.rect(x - rng.randint(10, 40), top, rng.randint(30, 80), 4, (200, 60, 40))
    # hull silhouette
    if rng.random() < 0.7:
        hw = rng.randint(w // 4, w // 2)
        hx = rng.randint(0, w - hw)
        c.rect(hx, horizon - 6, hw, 14, (30, 30, 40))
        c.rect(hx + hw // 3, horizon - 26, hw // 4, 20, (230, 230, 230))
    c.noise(rng, noise_amp, every=noise_every)
    return c


def mock_screen(rng, title, fields, message=None, message_after=None, marker_field=None,
                w=760, h=440, noise_amp=3, noise_every=2, text_scale=2, message_scale=3):
    """A fake application window: title bar, side nav, a form with labelled input boxes.
    `message` is drawn in red under `message_after`; `marker_field` gets a red asterisk."""
    c = Canvas(w, h, (236, 239, 243))
    c.rect(0, 0, w, 34, (28, 60, 100))
    c.text(12, 10, 'HARBOUR BERTH BOOKING', 2, (255, 255, 255))
    c.rect(0, 34, 150, h - 34, (215, 221, 228))
    for i, item in enumerate(['BOOKING BOARD', 'MY BOOKINGS', 'INSPECTIONS', 'TARIFFS', 'REPORTS']):
        c.text(10, 50 + i * 26, item, 2, (60, 70, 80))
    c.rect(170, 50, w - 190, h - 70, (255, 255, 255))
    c.rect(170, 50, w - 190, h - 70, (190, 196, 204), fill=False)
    c.text(186, 62, title, 2, (28, 60, 100))
    y = 94
    for label, value in fields:
        lab = label + (' *' if marker_field == label else '')
        c.text(186, y + 4, lab, text_scale, (70, 70, 70))
        col = (200, 40, 40) if marker_field == label else (150, 150, 150)
        c.rect(186 + 170, y - 2, w - 190 - 200, 22, (250, 250, 250))
        c.rect(186 + 170, y - 2, w - 190 - 200, 22, col, fill=False)
        c.text(186 + 176, y + 3, value, text_scale, (30, 30, 30))
        y += 30
        if message and message_after == label:
            # word-wrap the message inside the panel so nothing is clipped
            avail = (w - 190 - 32) // (6 * message_scale)
            lines, cur = [], ''
            for word in message.split():
                if cur and len(cur) + 1 + len(word) > avail:
                    lines.append(cur); cur = word
                else:
                    cur = (cur + ' ' + word).strip()
            lines.append(cur)
            for ln in lines:
                c.text(186, y, ln, message_scale, (200, 30, 30))
                y += 8 * message_scale
            y += 8
    c.rect(w - 130, h - 52, 90, 26, (28, 110, 60))
    c.text(w - 118, h - 45, 'SUBMIT', 2, (255, 255, 255))
    c.noise(rng, noise_amp, 170, 50, w - 190, h - 70, every=noise_every)
    return c


# ----------------------------------------------------------------------------------------
# Prose filler (fluff, never a rule) and HTML chrome
# ----------------------------------------------------------------------------------------
FILLER = [
    "This section was reviewed with the operations team during the second documentation workshop.",
    "The wording below reflects the agreed position at the time of writing and may be refined in a later revision.",
    "Readers new to port operations should first consult the glossary for the terms used here.",
    "Nothing in this chapter changes the responsibilities described in the stakeholder overview.",
    "Where the text says 'the system', it means the Harbour Berth Booking application as a whole.",
    "The examples given are illustrative and use fictional vessel names throughout.",
    "Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout.",
    "Questions about this chapter can be raised through the usual documentation feedback channel.",
    "The numbering of headings follows the master table of contents and is stable across revisions.",
    "This chapter does not describe the technical implementation; see the architecture notes for that.",
    "Paragraphs marked as guidance are explanatory and do not add obligations.",
    "The behaviour described here was demonstrated in the prototype walkthrough.",
    "Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.",
    "Diagrams are provided for orientation only.",
    "The review comments from the previous round have been incorporated into this revision.",
    "The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated.",
    "For the history of this chapter see the release notes page.",
    "Figures on this page are numbered per page, not per document.",
]

FILLER_BULLETS = [
    "Reviewed by the documentation owner.",
    "Cross-referenced from the glossary.",
    "Illustrated in the prototype.",
    "Discussed in workshop session 2.",
    "No open comments on this item.",
    "Wording aligned with the stakeholder overview.",
    "Applies to all terminals unless stated otherwise.",
    "See also the appendix data dictionary.",
]

FILLER_TABLE_ROWS = [
    ("Owner", "Documentation team, port operations"),
    ("Last reviewed", "Revision 7"),
    ("Related chapter", "See the navigation sidebar"),
    ("Illustration", "Figure on this page"),
    ("Guidance", "Explanatory text, no obligations added"),
    ("Status", "Agreed"),
]

MARKETING = [
    "Welcome to the documentation portal for Harbour Berth Booking, the fictional port authority's berth request application.",
    "The portal collects the functional description, the workshop notes and the decision log in one place.",
    "Use the sidebar to move between chapters; every page shares the same navigation.",
    "This portal is a documentation export. Interactive features of the original site are not available offline.",
    "The port handles a fictional mix of container, bulk and cruise traffic across three terminals.",
    "Our documentation team publishes a new revision roughly every fortnight.",
    "The application described here replaces a spreadsheet-based booking process.",
    "Thank you for reading. Feedback is welcome through the support page.",
]

CHANGELOG = [
    ("Revision 7", ["Corrected the caption of the review screen figure.", "Sidebar now lists the appendix.", "Fixed a broken link in the tariff chapter."]),
    ("Revision 6", ["Added the AIS integration chapter.", "Renumbered headings after the inspection chapters were split.", "Typo fixes throughout."]),
    ("Revision 5", ["Added the data dictionary appendix.", "Workshop notes moved to a separate file."]),
    ("Revision 4", ["Added screenshots from the prototype.", "Glossary extended with inspection terms."]),
    ("Revision 3", ["First complete draft for review."]),
    ("Revision 2", ["Restructured into chapters."]),
    ("Revision 1", ["Initial outline."]),
]

CLASS_SOUP = ["c-a1", "c-b2", "mod-x", "u-pad-3", "grid__cell", "t-body", "is-visible", "js-hook",
              "l-block", "l-block--wide", "theme-harbour", "v2", "legacy-wrap", "clearfix", "wp-block"]


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def soup(rng, n=3):
    return ' '.join(rng.sample(CLASS_SOUP, n))


def wrap_div(rng, inner, depth):
    for _ in range(depth):
        style = rng.choice(["margin:0;padding:0", "display:block", "position:relative",
                            "box-sizing:border-box;padding:0 4px", "font-size:inherit", ""])
        inner = f'<div class="{soup(rng)}"{(" style=%s" % json.dumps(style)) if style else ""}>{inner}</div>'
    return inner


def para(rng, sentences):
    return wrap_div(rng, '<p class="%s">%s</p>' % (soup(rng, 2), esc(' '.join(sentences))), rng.randint(1, 3))


def filler_para(rng, n=None):
    n = n or rng.randint(2, 4)
    return para(rng, rng.sample(FILLER, n))


def type_label(t):
    if t.startswith('String('):
        return 'Text, up to %s characters' % t[7:-1]
    if t.startswith('Enum('):
        return 'One of: ' + ', '.join(t[5:-1].split(','))
    return {'Decimal': 'Decimal number', 'Integer': 'Whole number', 'Boolean': 'Yes/No',
            'DateTime': 'Date and time', 'Date': 'Date'}.get(t, t)


def entity_table(rng, ent):
    rows = ''.join('<tr><td><code>%s</code></td><td>%s</td><td>%s</td></tr>'
                   % (a['name'], type_label(a['type']), 'Required' if a['required'] else 'Optional')
                   for a in ent['attributes'])
    return wrap_div(rng, ('<h3 id="ent-%s">%s</h3><table class="%s"><thead><tr><th>Attribute</th><th>Type</th>'
                          '<th>Required</th></tr></thead><tbody>%s</tbody></table>')
                    % (ent['name'], ent['name'], soup(rng, 2), rows), rng.randint(1, 2))


def assoc_sentence(a):
    kind = {'ManyToOne': 'many-to-one', 'OneToOne': 'one-to-one', 'ManyToMany': 'many-to-many'}[a['type']]
    return "%s refers to %s (%s, %s)." % (a['from'], a['to'], a['name'], kind)


def render_statement(rng, item, key):
    """Render one requirement/rule in the form the key asks for. Returns HTML, and a flag that says
    whether it is a minified one-line block that the page must emit verbatim."""
    form = item.get('form', 'prose')
    text = item['text']
    if form == 'prose':
        before = rng.sample(FILLER, rng.randint(0, 2))
        after = rng.sample(FILLER, rng.randint(0, 1))
        return para(rng, before + [text] + after)
    if form == 'bullet':
        items = rng.sample(FILLER_BULLETS, rng.randint(2, 4))
        items.insert(rng.randint(0, len(items)), text)
        lis = ''.join('<li class="%s">%s</li>' % (soup(rng, 1), esc(i)) for i in items)
        return wrap_div(rng, '<ul class="%s">%s</ul>' % (soup(rng, 2), lis), rng.randint(1, 2))
    if form == 'table':
        rows = rng.sample(FILLER_TABLE_ROWS, rng.randint(2, 4))
        rows.insert(rng.randint(0, len(rows)), ("Requirement", text))
        trs = ''.join('<tr><td class="%s">%s</td><td>%s</td></tr>' % (soup(rng, 1), esc(k), esc(v)) for k, v in rows)
        return wrap_div(rng, '<table class="%s"><thead><tr><th>Aspect</th><th>Statement</th></tr></thead><tbody>%s</tbody></table>'
                        % (soup(rng, 2), trs), 1)
    if form == 'minified':
        return None  # emitted inside the page's one-line block
    raise ValueError(form)


def minified_line(rng, embedded_html='', target_bytes=26000):
    """One line of >20 KB: a berth-occupancy 'heatmap' of inline-styled spans. Requirement text, if
    any, is buried in the middle of it."""
    cells = []
    while sum(len(c) for c in cells) < target_bytes:
        col = '#%02x%02x%02x' % (rng.randint(180, 240), rng.randint(60, 200), rng.randint(40, 120))
        cells.append('<span class="hm-cell %s" style="background:%s;width:9px;height:9px;display:inline-block" data-b="B%02d" data-d="%d" title="berth B%02d day %d"></span>'
                     % (rng.choice(CLASS_SOUP), col, rng.randint(1, 24), rng.randint(1, 31), rng.randint(1, 24), rng.randint(1, 31)))
    mid = len(cells) // 2
    head = ''.join(cells[:mid]); tail = ''.join(cells[mid:])
    return ('<div class="hm-wrap %s" style="line-height:0;font-size:0"><div class="hm-legend" style="font-size:11px">Berth occupancy heatmap (prototype data)</div>%s%s%s</div>'
            % (soup(rng, 2), head, embedded_html, tail))


def sidebar(pages, current):
    lis = []
    for p in pages:
        cls = ' class="active"' if p['file'] == current else ''
        lis.append('<li%s><a href="%s">%s</a></li>' % (cls, p['file'], esc(p['title'])))
    md = ''.join('<li><a href="%s">%s</a></li>' % (m, m) for m in ('glossary.md', 'roles.md', 'decisions-log.md', 'workshop-notes.md'))
    return ('<aside class="c-sidebar l-block theme-harbour"><div class="c-sidebar__inner"><div class="c-brand"><span class="c-brand__mark"></span>'
            '<span class="c-brand__name">Harbour Berth Booking</span><span class="c-brand__sub">Documentation portal</span></div>'
            '<nav aria-label="Chapters"><ul class="c-nav">%s</ul></nav><div class="c-sidebar__files"><h4>Files</h4><ul>%s</ul></div>'
            '<div class="c-sidebar__foot">Revision 7 &middot; exported for offline reading</div></div></aside>' % (''.join(lis), md))


def header_html():
    return ('<header class="c-header clearfix"><div class="c-header__bar"><a class="c-header__home" href="01-home.html">Home</a>'
            '<span class="c-header__crumb">Documentation</span><form class="c-search js-hook" action="#"><input type="search" placeholder="Search the documentation" name="q"><button type="submit">Search</button></form>'
            '<div class="c-header__user">Signed in as <b>documentation reader</b></div></div>'
            '<div class="c-cookie is-visible" role="dialog"><p>This documentation portal stores a single preference cookie so that the sidebar remembers whether it is collapsed. No analytics cookies are set. <a href="27-privacy-and-cookies.html">Read the privacy notice</a>.</p><button class="c-cookie__ok js-hook">OK</button></div></header>')


def footer_html(rng):
    return ('<footer class="c-footer"><div class="c-footer__cols"><div><h4>Documentation</h4><ul><li><a href="01-home.html">Home</a></li><li><a href="03-release-notes.html">Release notes</a></li><li><a href="34-contact-and-support.html">Contact and support</a></li></ul></div>'
            '<div><h4>Legal</h4><ul><li><a href="27-privacy-and-cookies.html">Privacy and cookies</a></li><li>Fictional Port Authority &mdash; a made-up organisation used for documentation examples</li></ul></div>'
            '<div><h4>Export</h4><p>Saved as "Webpage, complete". Linked stylesheets, scripts, fonts and images are in the <code>_files</code> folder next to this page.</p></div></div>'
            '<div class="c-footer__legal">%s All vessel names, agents, terminals and people mentioned anywhere on this site are invented.</div></footer>' % esc(rng.choice(MARKETING)))


def site_css(rng):
    rules = []
    for cls in CLASS_SOUP + ['c-header', 'c-sidebar', 'c-nav', 'c-footer', 'c-main', 'c-cookie', 'hm-cell', 'c-brand', 'c-search']:
        rules.append('.%s{margin:%dpx;padding:%dpx;color:#%06x}' % (cls, rng.randint(0, 12), rng.randint(0, 12), rng.randint(0, 0xffffff)))
        rules.append('.%s:hover{opacity:.%d}' % (cls, rng.randint(5, 9)))
        rules.append('.%s > .%s{display:block}' % (cls, rng.choice(CLASS_SOUP)))
    body = ('@font-face{font-family:"HarbourSans";src:url(font-harbour-sans.woff) format("woff")}'
            'body{font-family:"HarbourSans",system-ui,sans-serif;margin:0;background:#f4f6f8;color:#1f2933}'
            '.l-shell{display:grid;grid-template-columns:260px 1fr}.c-main{padding:24px 40px;max-width:980px}'
            'table{border-collapse:collapse;margin:12px 0}td,th{border:1px solid #cfd6dd;padding:6px 10px;vertical-align:top}'
            'figure{margin:16px 0}figcaption{font-size:.9em;color:#52606d}.active>a{font-weight:bold}\n')
    return body + '\n'.join(rules) + '\n' + ''.join('.gen-%d{width:%dpx}' % (i, i) for i in range(400))


def print_css():
    return '@media print{.c-sidebar,.c-header,.c-footer,.c-cookie{display:none}.c-main{max-width:none}}\n' + \
        ''.join('.p-%d{page-break-inside:avoid}' % i for i in range(120))


def app_js(rng):
    names = ['collapse', 'expand', 'toggle', 'search', 'cookie', 'track', 'lazy', 'nav', 'scroll', 'resize']
    fns = []
    for n in names:
        fns.append('function %s_%d(e){var t=this,n=e&&e.target,r=%d;if(!n)return r;for(var i=0;i<r;i++){t=t&&t.parentNode}return t}'
                   % (n, rng.randint(1, 99), rng.randint(1, 9)))
    cfg = json.dumps({'portal': 'hbb-docs', 'revision': 7, 'features': {n: rng.random() < .5 for n in names},
                      'lookup': {'k%03d' % i: rng.randint(0, 99999) for i in range(600)}}, separators=(',', ':'))
    return ('/*! hbb-docs portal bundle — fictional, no network calls */\n!function(w,d){"use strict";var CFG=' + cfg + ';'
            + ''.join(fns) + 'w.HBB={cfg:CFG,ready:function(f){d.readyState!=="loading"?f():d.addEventListener("DOMContentLoaded",f)}};'
            'w.HBB.ready(function(){var c=d.querySelector(".c-cookie__ok");c&&c.addEventListener("click",function(){c.parentNode.className="c-cookie"})})}(window,document);\n')


def woff_stub(rng):
    body = bytes(rng.getrandbits(8) for _ in range(6000))
    return b'wOFF' + b'\x00\x01\x00\x00' + struct.pack('>I', 44 + len(body)) + b'\x00\x00' * 2 + b'\x00' * 30 + body


# ----------------------------------------------------------------------------------------
# Pages
# ----------------------------------------------------------------------------------------
def page_sections(rng, page, key, byid, entities, figures):
    """Return list of (heading, html) sections for a content page. `figures` is a callback that
    returns the <figure> html for the n-th figure of the page."""
    secs = {}
    order = []
    chapter = int(page['file'][:2]) - 3  # heading numbers follow the key's sections
    carried = [byid[i] for i in page.get('carries', []) if i in byid]
    for it in carried:
        h = it['section']['heading']
        if h not in secs:
            secs[h] = []; order.append(h)
        secs[h].append(it)
    # a couple of filler sections so requirement headings are not the only ones
    for extra in ('%d.0 Introduction' % chapter, '%d.9 Notes' % chapter):
        if extra not in secs:
            secs[extra] = []; order.append(extra)
    order.sort(key=lambda h: [float(x) if x.replace('.', '').isdigit() else 99 for x in h.split(' ')[0].split('.')])
    out = []
    fig_n = 0
    minified_payload = ''
    for h in order:
        body = [filler_para(rng)]
        for it in secs[h]:
            html_ = render_statement(rng, it, key)
            if html_ is None:
                minified_payload += '<p class="hm-note" style="font-size:12px;line-height:1.3;display:block">%s</p>' % esc(it['text'])
            else:
                body.append(html_)
        if rng.random() < 0.5:
            body.append(filler_para(rng, 2))
        if rng.random() < 0.5 and fig_n < page['sidecar_images'] - 1:
            body.append(figures(fig_n)); fig_n += 1
        out.append((h, ''.join(body)))
    # entity tables
    for name in page.get('entities', []):
        ent = entities[name]
        out.append(('Data: %s' % name, filler_para(rng, 1) + entity_table(rng, ent)))
    if page.get('entities'):
        assocs = [a for a in key['associations'] if a['from'] in page['entities'] or a['to'] in page['entities']]
        if assocs:
            out.append(('Relationships', para(rng, [assoc_sentence(a) for a in assocs])))
    return out, fig_n, minified_payload


def chrome_sections(rng, page, figures):
    out = []
    title = page['title']
    if 'release' in page['file']:
        for rev, items in CHANGELOG:
            lis = ''.join('<li>%s</li>' % esc(i) for i in items)
            out.append((rev, '<ul>%s</ul>' % lis))
    elif 'privacy' in page['file']:
        out.append(('Cookies', para(rng, ["The portal stores one preference cookie for the sidebar state.", "No analytics or advertising cookies are used.", "Cookies can be cleared through the browser at any time."])))
        out.append(('Personal data', para(rng, ["The documentation export contains no personal data.", "Names of people appearing in examples are invented."])))
    elif 'contact' in page['file']:
        out.append(('Support', para(rng, ["Documentation feedback is collected through the feedback form of the original portal, which is not available in this offline export.", "For the purposes of this fixture there is nobody to contact."])))
        out.append(('Office hours', '<table><tr><th>Day</th><th>Hours</th></tr>' + ''.join('<tr><td>%s</td><td>09:00 - 17:00</td></tr>' % d for d in ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) + '</table>'))
    elif 'news' in page['file']:
        for i in range(6):
            out.append(('News item %d' % (i + 1), para(rng, rng.sample(MARKETING, 2) + rng.sample(FILLER, 1)) + (figures(i) if i < page['sidecar_images'] else '')))
    elif 'about' in page['file']:
        out.append(('Who we are', para(rng, MARKETING[:3])))
        out.append(('The port', para(rng, MARKETING[4:6])))
    else:
        out.append(('Welcome', para(rng, MARKETING[:2]) + figures(0)))
        out.append(('How to read this documentation', para(rng, MARKETING[2:4])))
        out.append(('Latest revision', para(rng, MARKETING[5:7])))
    return out


def make_figure(rng, page_dir, fig_index, rel, is_jpeg, caption, image_bytes_fn):
    fname = 'img-%02d.%s' % (fig_index + 1, 'jpg' if is_jpeg else 'png')
    return fname, ('<figure class="%s"><img src="%s/%s" alt="Figure %d (photo)" width="%d"><figcaption>Figure %d: %s</figcaption></figure>'
                   % (soup(rng, 2), rel, fname, fig_index + 1, 480, fig_index + 1, esc(caption)))


def generate(out_dir, seed, key, write_manifest=True):
    rng = random.Random(seed)
    os.makedirs(out_dir, exist_ok=True)
    pages = key['corpus']['pages']
    byid = {x['id']: x for x in key['requirements'] + key['business_rules']}
    entities = {e['name']: e for e in key['entities']}
    shots = {s['page']: s for s in key['screenshot_only']}
    manifest = {'seed': seed, 'app': key['app'], 'generated_by': 'gen-corpus.py', 'files': [], 'pages': [],
                'placements': {}, 'chrome_pages': [p['file'] for p in pages if p['chrome']], 'screenshot_only': [], 'markdown': []}

    def add_file(path, data, kind):
        full = os.path.join(out_dir, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'wb') as f:
            f.write(data)
        manifest['files'].append({'path': path, 'bytes': len(data), 'kind': kind})

    captions = ["Container terminal at dawn (stock illustration)", "Quay wall and mooring bollards", "Bulk carrier alongside",
                "Crane row at the north terminal", "Harbour entrance and breakwater", "Cruise berth, off season",
                "Inspection launch at the pontoon", "Signal mast", "Tug basin", "Shore power cabinet",
                "RoRo ramp", "Customs office at the south terminal"]

    for page in pages:
        prng = random.Random('%s:%s' % (seed, page['file']))
        rel = page['file'][:-5] + '_files'
        n_side = page['sidecar_images']
        figure_html = {}
        page_imgs = []
        shot = shots.get(page['file'])
        shot_side_index = None
        if shot and shot['mode'] == 'sidecar':
            shot_side_index = n_side - 1  # the last sidecar image is the screenshot
        for i in range(n_side):
            irng = random.Random('%s:%s:img%d' % (seed, page['file'], i))
            if shot_side_index == i:
                fname = os.path.basename(shot['image'])
                c = mock_screen(irng, shot['screen'].upper(),
                                [('VESSEL', 'MV NORTHERN GANNET'), ('IMO NUMBER', '123456'), ('BERTH', 'B07 NORTH TERMINAL'),
                                 ('ETA', '14-03 08:00'), ('ETD', '16-03 18:00'), ('CARGO CLASS', 'GENERAL')],
                                message=shot['text'], message_after='IMO NUMBER', marker_field='IMO NUMBER')
                data = png_bytes(c)
                add_file('%s/%s' % (rel, fname), data, 'image-screenshot')
                figure_html[i] = ('<figure class="%s" id="fig-validation"><img src="%s/%s" alt="Figure %d (screenshot)" width="640">'
                                  '<figcaption>Figure %d: the booking request form in the prototype.</figcaption></figure>'
                                  % (soup(prng, 2), rel, fname, i + 1, i + 1))
                manifest['screenshot_only'].append({'id': shot['id'], 'file': '%s/%s' % (rel, fname), 'page': page['file'], 'mode': 'sidecar'})
                page_imgs.append(fname)
                continue
            is_jpeg = (i == 0) or (i == 3 and n_side >= 6)
            if is_jpeg:
                w, h = 256, 176
                c = scene(irng, w, h, noise_amp=10)
                data = jpeg_bytes(w, h, c.gray(), quality=irng.choice([60, 75, 85]))
            else:
                w, h = irng.choice([(320, 220), (360, 240), (400, 260)])
                c = scene(irng, w, h, noise_amp=irng.choice([4, 6, 8]), noise_every=1)
                data = png_bytes(c)
            fname, fhtml = make_figure(prng, rel, i, rel, is_jpeg, captions[i % len(captions)], None)
            add_file('%s/%s' % (rel, fname), data, 'image')
            figure_html[i] = fhtml
            page_imgs.append(fname)

        def figures(n, figure_html=figure_html):
            return figure_html.get(n, '')

        # inline screenshots
        inline_figs = []
        for j in range(page.get('inline_screenshots', 0)):
            irng = random.Random('%s:%s:inline%d' % (seed, page['file'], j))
            if shot and shot['mode'] == 'inline' and j == 0:
                c = mock_screen(irng, shot['screen'].upper(),
                                [('REQUEST', 'HB-2031-00417'), ('VESSEL', 'MV GREY PETREL'), ('OUTCOME', 'REJECTED'), ('REASON', '')],
                                message=shot["text"], message_after="REASON", marker_field="REASON", noise_amp=4, noise_every=2)
                fid = 'fig-review-decision'
                cap = 'the decision panel of the officer review screen (prototype).'
                manifest['screenshot_only'].append({'id': shot['id'], 'file': page['file'], 'page': page['file'], 'mode': 'inline', 'element_id': fid})
            else:
                titles = {'08': 'BOOKING LIFECYCLE', '11': 'AGENT REGISTRATION', '14': 'VESSEL RECORD', '20': 'INVOICE',
                          '23': 'INSPECTION CHECKLIST', '28': 'NAVIGATION', '29': 'BOOKING BOARD', '30': 'MY BOOKINGS'}
                t = titles.get(page['file'][:2], page['title'].upper())
                fields = [('REFERENCE', 'HB-2031-00%03d' % irng.randint(100, 999)), ('VESSEL', 'MV ' + irng.choice(['SILVER TERN', 'BLUE SKUA', 'RED KNOT', 'GREY PETREL'])),
                          ('STATUS', irng.choice(['DRAFT', 'SUBMITTED', 'UNDER REVIEW', 'APPROVED'])), ('TERMINAL', irng.choice(['NORTH', 'SOUTH', 'EAST']))]
                c = mock_screen(irng, t, fields, noise_amp=irng.choice([3, 4]), noise_every=2)
                fid = 'fig-inline-%d' % (j + 1)
                cap = 'prototype mock-up of the %s screen.' % page['title'].lower()
            data = png_bytes(c)
            b64 = base64.b64encode(data).decode('ascii')
            inline_figs.append('<figure class="%s" id="%s"><img src="data:image/png;base64,%s" alt="Figure (screenshot)" width="640"><figcaption>Figure: %s</figcaption></figure>'
                               % (soup(prng, 2), fid, b64, esc(cap)))
            manifest['files'].append({'path': '%s#%s' % (page['file'], fid), 'bytes': len(data), 'kind': 'image-inline-base64'})

        # sections
        if page['chrome']:
            secs = chrome_sections(prng, page, figures)
            used_figs = min(len(secs), n_side)
            minified_payload = ''
        else:
            secs, used_figs, minified_payload = page_sections(prng, page, key, byid, entities, figures)
        # unused sidecar figures go into a gallery at the end so every image is referenced
        gallery = ''.join(figure_html[i] for i in range(n_side) if i >= used_figs and (shot_side_index != i))
        if shot_side_index is not None and shot_side_index >= used_figs:
            # the screenshot figure sits under its own section, not in the gallery
            secs.append(('Figure: booking form validation', filler_para(prng, 1) + figure_html[shot_side_index]))
        if gallery:
            secs.append(('Gallery', '<div class="c-gallery %s">%s</div>' % (soup(prng, 2), gallery)))
        if inline_figs:
            insert_at = min(1, len(secs))
            secs.insert(insert_at, ('Prototype screens', filler_para(prng, 1) + ''.join(inline_figs)))

        body_secs = []
        for h, html_ in secs:
            sid = 's-' + ''.join(ch if ch.isalnum() else '-' for ch in h.lower())
            body_secs.append(wrap_div(prng, '<section id="%s" class="%s"><h2>%s</h2>%s</section>' % (sid, soup(prng, 2), esc(h), html_), prng.randint(1, 2)))
        minified = ''
        if page.get('minified'):
            minified = '\n' + minified_line(prng, minified_payload, target_bytes=prng.randint(22000, 40000)) + '\n'
        elif minified_payload:
            raise RuntimeError('minified requirement on a page without a minified block: ' + page['file'])

        head = ('<!DOCTYPE html>\n<!-- saved from url=(0061)https://docs.harbour-berth-booking.invalid/portal/%s -->\n'
                '<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>%s &middot; Harbour Berth Booking documentation</title>\n'
                '<link rel="stylesheet" href="%s/site.css"><link rel="stylesheet" href="%s/print.css" media="print">\n'
                '<style>%s</style>\n<script src="%s/app.js" defer></script>\n</head>\n'
                % (page['file'], esc(page['title']), rel, rel, ''.join('.inl-%d{padding:%dpx}' % (i, i % 7) for i in range(150)), rel))
        meta = '<div class="c-meta">Revision 7 &middot; chapter %s &middot; %s</div>' % (page['file'][:2], 'reference only' if page['chrome'] else 'functional description')
        body = ('<body class="docs-body theme-harbour %s">\n<div id="app"><div class="l-shell">\n%s\n%s\n<main class="c-main %s"><article class="c-article">\n<h1>%s</h1>\n%s\n%s%s\n</article></main>\n%s\n</div></div>\n</body></html>\n'
                % (soup(prng, 2), header_html(), sidebar(pages, page['file']), soup(prng, 2), esc(page['title']), meta,
                   '\n'.join(body_secs), minified, footer_html(prng)))
        html_doc = (head + body).encode('utf-8')
        add_file(page['file'], html_doc, 'html')
        # sidecar support files
        add_file('%s/site.css' % rel, site_css(prng).encode(), 'css')
        if prng.random() < 0.6:
            add_file('%s/print.css' % rel, print_css().encode(), 'css')
        add_file('%s/app.js' % rel, app_js(prng).encode(), 'js')
        add_file('%s/font-harbour-sans.woff' % rel, woff_stub(prng), 'font')
        manifest['pages'].append({'file': page['file'], 'title': page['title'], 'chrome': page['chrome'], 'sidecar_images': n_side,
                                  'inline_screenshots': page.get('inline_screenshots', 0), 'minified': bool(page.get('minified')),
                                  'carries': page.get('carries', []), 'entities': page.get('entities', []), 'bytes': len(html_doc)})
        for i in page.get('carries', []):
            it = byid.get(i)
            if it:
                manifest['placements'][i] = {'file': page['file'], 'heading': it['section']['heading'], 'form': it.get('form', 'prose'),
                                             'negative': bool(it.get('negative'))}
            else:
                manifest['placements'][i] = {'file': page['file'], 'form': 'screenshot', 'mode': shots[page['file']]['mode']}

    # ---- markdown files ----
    mrng = random.Random('%s:md' % seed)
    gl = ['# Glossary\n', '\nTerms used across the Harbour Berth Booking documentation. Fictional throughout.\n\n', '| Term | Definition |\n|---|---|\n']
    defs = {
        'Vessel': 'A ship known to the registry; identified by IMO number, with name, length overall, beam, draught, flag state, vessel type and gross tonnage.',
        'ShippingAgent': 'A licensed agency acting for vessels; company name, licence number, contact e-mail, phone, suspension flag and credit limit.',
        'Terminal': 'A part of the port with its own berths; code, name, operating hours and whether it has a customs office.',
        'Berth': 'A mooring place at a terminal; code, name, maximum length, maximum draught, shore power flag, status.',
        'BookingRequest': 'A request by an agent to use a berth for a vessel between ETA and ETD; has a reference, status, cargo class, shore power request, submission time and remarks.',
        'ApprovalDecision': 'The recorded outcome of an officer review: decided on, outcome, reason, officer name, override flag.',
        'Tariff': 'A rate card per terminal: code, description, rate per metre per day, currency, valid from/to, surcharge percent.',
        'Invoice': 'The bill for a completed booking: invoice number, issued on, due on, total amount, VAT percent, status.',
        'Inspection': 'A scheduled visit by an inspector: scheduled for, completed on, outcome, inspector name, findings, follow-up flag.',
        'InspectionItem': 'One line of an inspection checklist: category, description, compliant flag, severity, note.',
        'AuditEntry': 'One line of the audit trail: occurred on, actor, action, entity name, detail.',
        'ETA / ETD': 'Estimated time of arrival / departure.', 'LOA': 'Length overall of a vessel, in metres.',
        'Shore power': 'Electrical supply from the quay so a moored vessel can switch off its generators.',
    }
    for t, d in defs.items():
        gl.append('| %s | %s |\n' % (t, d))
    add_file('glossary.md', ''.join(gl).encode(), 'markdown')

    roles_md = ['# Roles and permissions\n\n', 'The application distinguishes the following user roles.\n\n', '| Role | Who | What they do |\n|---|---|---|\n']
    for r in key['roles']:
        roles_md.append('| %s | %s | %s |\n' % (r['label'], r['name'], r['description']))
    roles_md.append('\nEvery user has exactly one role. Role names are shown in the header of every screen.\n')
    add_file('roles.md', ''.join(roles_md).encode(), 'markdown')

    adrs = [
        ('ADR-001', 'Documentation lives in the portal', 'All functional documentation is published through the documentation portal and exported for offline review.'),
        ('ADR-002', 'Chapters are numbered once', 'Heading numbers are allocated by the master table of contents and never re-used.'),
        ('ADR-003', 'Fictional example data', 'All examples use invented vessel names, agents and people.'),
        ('ADR-004', 'Booking references are permanent', byid['R048']['text'] + ' A cancelled request keeps its reference for the audit trail.'),
        ('ADR-005', 'Screenshots come from the prototype', 'Figures are exported from the clickable prototype, not drawn by hand.'),
        ('ADR-006', 'Invoice due dates', byid['B009']['text'] + ' This was agreed with the finance team in the third workshop.'),
        ('ADR-007', 'Workshop notes are kept verbatim', 'Workshop notes are stored as written during the session; clean-up happens in the chapters.'),
        ('ADR-008', 'Release notes per revision', 'Every published revision gets a release notes entry.'),
    ]
    md = ['# Decisions log\n\n', 'Architecture-decision-record style. One entry per decision, newest last.\n\n']
    for aid, title, text in adrs:
        md.append('## %s — %s\n\n**Status:** accepted\n\n**Decision:** %s\n\n**Consequences:** %s\n\n' % (aid, title, text, mrng.choice(FILLER)))
    add_file('decisions-log.md', ''.join(md).encode(), 'markdown')

    ws = ['# Workshop notes\n\n', 'Raw notes, three sessions. Not cleaned up (see ADR-007).\n\n',
          '## Session 1 — scope\n\n- Attendees: operations, documentation, two agents (fictional)\n- Walked through the chapter list\n- Coffee at 10:30\n- Parking lot: none\n\n',
          '## Session 2 — agents\n\n- Agents like the draft feature\n- %s\n- Question about attachments size limit: not decided\n- Agents want the e-mail notifications to include the reference\n\n' % byid['R046']['text'],
          '## Session 3 — officers\n\n- Officers want the queue sorted by ETA (already in the chapter)\n- %s\n- Discussed colours of the exceedance highlight; red is fine\n- Follow-up: none\n' % byid['R047']['text']]
    add_file('workshop-notes.md', ''.join(ws).encode(), 'markdown')
    for m in key['corpus']['markdown']:
        for i in m.get('carries', []):
            if i in byid:
                manifest['placements'][i] = {'file': m['file'], 'heading': byid[i]['section']['heading'], 'form': byid[i].get('form', 'prose')}
        manifest['markdown'].append(m)

    total = sum(f['bytes'] for f in manifest['files'] if f['kind'] != 'image-inline-base64')
    manifest['totals'] = {'files': sum(1 for f in manifest['files'] if f['kind'] != 'image-inline-base64'), 'bytes': total,
                          'html_pages': len(pages), 'chrome_pages': len(manifest['chrome_pages']),
                          'sidecar_images': sum(1 for f in manifest['files'] if f['kind'].startswith('image') and f['kind'] != 'image-inline-base64'),
                          'inline_screenshots': sum(1 for f in manifest['files'] if f['kind'] == 'image-inline-base64'),
                          'requirements': len(key['requirements']), 'business_rules': len(key['business_rules']),
                          'screenshot_only': len(key['screenshot_only']), 'contradictions': len(key['contradictions'])}
    if write_manifest:
        with open(os.path.join(out_dir, 'MANIFEST.json'), 'w') as f:
            json.dump(manifest, f, indent=2)
    return manifest


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('out_dir')
    ap.add_argument('--seed', type=int, default=20260909)
    ap.add_argument('--key', default=os.path.join(HERE, 'answer-key.json'))
    ap.add_argument('--no-manifest', action='store_true', help='do not write MANIFEST.json (what the agents under test get)')
    a = ap.parse_args(argv)
    with open(a.key, encoding='utf-8') as f:
        key = json.load(f)
    m = generate(a.out_dir, a.seed, key, write_manifest=not a.no_manifest)
    t = m['totals']
    print('corpus: %s — %d files, %.1f MB, %d HTML pages (%d chrome), %d sidecar images, %d inline screenshots; %d requirements, %d rules, %d screenshot-only, %d contradictions%s'
          % (a.out_dir, t['files'], t['bytes'] / 1e6, t['html_pages'], t['chrome_pages'], t['sidecar_images'], t['inline_screenshots'],
             t['requirements'], t['business_rules'], t['screenshot_only'], t['contradictions'],
             '' if a.no_manifest else ' — MANIFEST.json written (do NOT give it to the agents under test)'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
