#!/usr/bin/env python3
"""gen-fixture.py <sources-dir> — builds the images-to-md test corpus. See CAPTURE.md.

Every piece is a real, well-formed file of its kind (a genuine baseline JPEG, a genuine OOXML
zip, a genuine PDF object with a stated /Length) built from the format's own published
contract with the standard library only — never a byte-for-byte copy of anything hand-crafted
by a real tool, and never a fake extension on the wrong bytes.
"""
import math
import os
import struct
import sys
import zipfile
import zlib


def png_bytes(w, h, rgb):
    stride = w * 3
    row = bytes(rgb) * w
    raw = bytearray()
    for _ in range(h):
        raw.append(0)
        raw += row

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))


# --- minimal baseline grayscale JPEG encoder (fixed-length canonical Huffman tables — valid
# for any decoder; the same approach as tests/ab/gen-corpus.py, reproduced compactly here so
# this fixture has no cross-test import dependency). ------------------------------------------
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
_DC_CODES = {v: (i, 4) for i, v in enumerate(_DC_VALUES)}
_AC_CODES = {v: (i, 8) for i, v in enumerate(_AC_VALUES)}


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
            self.write((1 << pad) - 1, pad)


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
                bw.write(diff if diff > 0 else diff + (1 << s) - 1, s)
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
                bw.write(v if v > 0 else v + (1 << s) - 1, s)
                run = 0
            if run:
                c, l = _AC_CODES[0x00]; bw.write(c, l)
    bw.flush()
    out += bw.out + b'\xFF\xD9'
    return bytes(out)


def build(src):
    os.makedirs(src, exist_ok=True)

    # --- loose files: a tiny (chrome) png, a content-sized jpg photo ---------------------
    with open(os.path.join(src, 'tiny.png'), 'wb') as f:
        f.write(png_bytes(16, 16, (200, 200, 200)))
    with open(os.path.join(src, 'photo.jpg'), 'wb') as f:
        f.write(jpeg_bytes(96, 96, [128] * (96 * 96)))

    # --- saved webpage + sidecar image + sidecar css --------------------------------------
    files_dir = os.path.join(src, 'page_files')
    os.makedirs(files_dir, exist_ok=True)
    with open(os.path.join(files_dir, 'shot.png'), 'wb') as f:
        f.write(png_bytes(150, 100, (5, 6, 7)))
    with open(os.path.join(files_dir, 'site.css'), 'w') as f:
        f.write('body { margin: 0; }\n')
    with open(os.path.join(src, 'page.html'), 'w') as f:
        f.write('<html><head><link rel="stylesheet" href="page_files/site.css"></head>'
                '<body><h1>Vehicle List</h1><p>Some requirements text.</p>'
                '<img src="page_files/shot.png" alt="Vehicle list screenshot"></body></html>')

    # --- pptx: 3 slides. Slide 1 and slide 3 embed DIFFERENT zip entries that happen to be
    # byte-identical PNGs — dedup must fold them by content, not by filename. -------------
    img1 = png_bytes(200, 150, (10, 20, 30))
    img2 = png_bytes(200, 150, (40, 50, 60))
    img3 = img1  # same bytes, different media filename in the zip
    pptx_path = os.path.join(src, 'Deck.pptx')
    with zipfile.ZipFile(pptx_path, 'w') as z:
        z.writestr('[Content_Types].xml',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Default Extension="png" ContentType="image/png"/>'
            '<Override PartName="/ppt/presentation.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
            '</Types>')
        z.writestr('_rels/.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>')
        z.writestr('ppt/presentation.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><presentation/>')
        z.writestr('ppt/media/image1.png', img1)
        z.writestr('ppt/media/image2.png', img2)
        z.writestr('ppt/media/image3.png', img3)
        slide_text = {1: 'Welcome to Harbour Ops', 2: 'Booking a berth', 3: 'Welcome to Harbour Ops'}
        slide_media = {1: 'image1.png', 2: 'image2.png', 3: 'image3.png'}
        for n in (1, 2, 3):
            z.writestr('ppt/slides/slide%d.xml' % n,
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
                'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
                '<p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>%s</a:t></a:r></a:p></p:txBody></p:sp>'
                '<p:pic><p:blipFill><a:blip r:embed="rId1" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>'
                '</p:blipFill></p:pic></p:spTree></p:cSld></p:sld>' % slide_text[n])
            z.writestr('ppt/slides/_rels/slide%d.xml.rels' % n,
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships/image" Target="../media/%s"/></Relationships>' % slide_media[n])

    # --- docx: one image in a paragraph right after a Heading1 paragraph ------------------
    docx_img = png_bytes(300, 200, (70, 80, 90))
    docx_path = os.path.join(src, 'Spec.docx')
    with zipfile.ZipFile(docx_path, 'w') as z:
        z.writestr('[Content_Types].xml',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Default Extension="png" ContentType="image/png"/>'
            '<Override PartName="/word/document.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '</Types>')
        z.writestr('_rels/.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr('word/media/image1.png', docx_img)
        z.writestr('word/_rels/document.xml.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/image" Target="media/image1.png"/></Relationships>')
        z.writestr('word/document.xml',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body>'
            '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Vehicle Screens</w:t></w:r></w:p>'
            '<w:p><w:r><w:drawing><a:blip r:embed="rId1"/></w:drawing></w:r></w:p>'
            '</w:body></w:document>')

    # --- a hand-built PDF: catalog, one page, one /DCTDecode image XObject, exact xref -----
    pdf_jpg = jpeg_bytes(80, 80, [90] * (80 * 80))
    objs = [
        b'1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
        b'2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
        b'3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /XObject << /Im1 4 0 R >> >> '
        b'/MediaBox [0 0 200 200] >>\nendobj\n',
        (b'4 0 obj\n<< /Type /XObject /Subtype /Image /Width 80 /Height 80 /ColorSpace /DeviceGray '
         b'/BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n' % len(pdf_jpg)
         + pdf_jpg + b'\nendstream\nendobj\n'),
    ]
    pdf = bytearray(b'%PDF-1.4\n')
    offsets = [0]
    for o in objs:
        offsets.append(len(pdf))
        pdf += o
    xref_off = len(pdf)
    pdf += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1)
    for off in offsets[1:]:
        pdf += ('%010d 00000 n \n' % off).encode('ascii')
    pdf += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF' % (len(objs) + 1, xref_off)
    with open(os.path.join(src, 'Doc.pdf'), 'wb') as f:
        f.write(bytes(pdf))


if __name__ == '__main__':
    build(sys.argv[1])
    print('images-to-md fixture written under', sys.argv[1])
