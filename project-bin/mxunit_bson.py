# mxunit_bson.py -- minimal order-preserving BSON codec for Mendix MPR v2 model units.
#
# Mendix stores each model unit (mprcontents/**/*.mxunit) as BSON. Round-tripping one
# byte-identically requires preserving key ORDER and the exact element types, which a
# dict-based reader does not: hence [(type, key, value)] triples rather than dicts.
#
# Used by wf-add-path-terminators.py. Only for model surgery mxcli genuinely cannot express
# -- it bypasses every validation mxcli and mxbuild perform.
#
# COVERAGE, measured rather than assumed: 1068 of the 1069 units in a real 16-module project
# re-encode byte-identically (VB-USI, 2026-09-14). The one miss carries BSON type 0x09
# (UTC datetime), which no workflow unit uses; the codec raises on it rather than guessing.
# Extend enc_val/dec_val together, and re-measure against a real project, before relying on
# it for a unit type outside workflows.

import struct
class Bin:
    __slots__=("sub","data")
    def __init__(s,sub,data): s.sub,s.data=sub,data
def _cstr(b,i):
    j=b.index(b'\x00',i); return b[i:j].decode('utf-8'), j+1
def dec_doc(b,i):
    ln=struct.unpack_from('<i',b,i)[0]; end=i+ln; i+=4
    out=[]
    while b[i]!=0:
        t=b[i]; i+=1
        k,i=_cstr(b,i)
        v,i=dec_val(b,i,t)
        out.append((t,k,v))
    assert i+1==end, (i,end)
    return out, end
def dec_val(b,i,t):
    if t==0x01: return struct.unpack_from('<d',b,i)[0], i+8
    if t==0x02:
        n=struct.unpack_from('<i',b,i)[0]; i+=4
        return b[i:i+n-1].decode('utf-8'), i+n
    if t in (0x03,0x04): return dec_doc(b,i)
    if t==0x05:
        n=struct.unpack_from('<i',b,i)[0]; sub=b[i+4]
        return Bin(sub,b[i+5:i+5+n]), i+5+n
    if t==0x08: return (b[i]!=0), i+1
    if t==0x0A: return None, i
    if t==0x10: return struct.unpack_from('<i',b,i)[0], i+4
    if t==0x12: return struct.unpack_from('<q',b,i)[0], i+8
    raise ValueError("bson type 0x%02x at %d"%(t,i))
def enc_val(t,v):
    if t==0x01: return struct.pack('<d',v)
    if t==0x02:
        e=v.encode('utf-8'); return struct.pack('<i',len(e)+1)+e+b'\x00'
    if t in (0x03,0x04): return enc_doc(v)
    if t==0x05: return struct.pack('<i',len(v.data))+bytes([v.sub])+v.data
    if t==0x08: return b'\x01' if v else b'\x00'
    if t==0x0A: return b''
    if t==0x10: return struct.pack('<i',v)
    if t==0x12: return struct.pack('<q',v)
    raise ValueError(t)
def enc_doc(items):
    body=b''.join(bytes([t])+k.encode('utf-8')+b'\x00'+enc_val(t,v) for t,k,v in items)
    return struct.pack('<i',len(body)+5)+body+b'\x00'
def load(p):
    b=open(p,'rb').read(); d,e=dec_doc(b,0); assert e==len(b); return d
def dump(d,p): open(p,'wb').write(enc_doc(d))
