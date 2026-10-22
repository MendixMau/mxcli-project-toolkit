"""Minimal read-only BSON decoder (subset used by Mendix .mxunit files)."""
import struct, uuid, base64
def _cstr(b, i):
    j = b.index(b'\x00', i); return b[i:j].decode('utf-8', 'replace'), j + 1
def _doc(b, i, arr=False):
    n = struct.unpack_from('<i', b, i)[0]; end = i + n; i += 4; out = [] if arr else {}
    while i < end - 1:
        t = b[i]; i += 1; k, i = _cstr(b, i)
        if t == 0x01: v = struct.unpack_from('<d', b, i)[0]; i += 8
        elif t == 0x02:
            l = struct.unpack_from('<i', b, i)[0]; v = b[i+4:i+4+l-1].decode('utf-8','replace'); i += 4 + l
        elif t in (0x03, 0x04): v, i = _doc(b, i, t == 0x04)
        elif t == 0x05:
            l = struct.unpack_from('<i', b, i)[0]; st = b[i+4]; raw = b[i+5:i+5+l]; i += 5 + l
            v = str(uuid.UUID(bytes_le=raw)) if st in (3, 4) and l == 16 else base64.b64encode(raw).decode()
        elif t == 0x08: v = b[i] == 1; i += 1
        elif t == 0x09: v = struct.unpack_from('<q', b, i)[0]; i += 8
        elif t == 0x0A: v = None
        elif t == 0x10: v = struct.unpack_from('<i', b, i)[0]; i += 4
        elif t == 0x12: v = struct.unpack_from('<q', b, i)[0]; i += 8
        else: raise ValueError('bson type %x' % t)
        out.append(v) if arr else out.__setitem__(k, v)
    return out, end
def loads(b): return _doc(b, 0)[0]
