#!/usr/bin/env python3
"""mkv2.py: an MPR v2 copy of a v1 model (NR2-3, NR2-10): every unit moves to mprcontents/<uuid>.mxunit and its
Contents column is dropped, as in a real 10.x+ Git app (the Unit table keeps ContentsHash only).

  mkv2.py <v1 dir holding App.mpr> <out dir>
"""
import os, shutil, sqlite3, sys, uuid

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(dst, "mprcontents"))
for sub in ("widgets", "javasource", "userlib", "theme", "themesource", "javascriptsource"):
    if os.path.isdir(os.path.join(src, sub)):
        shutil.copytree(os.path.join(src, sub), os.path.join(dst, sub))
mpr = os.path.join(dst, "App.mpr")
shutil.copy(os.path.join(src, "App.mpr"), mpr)
con = sqlite3.connect(mpr)
for uid, blob in con.execute("select UnitID, Contents from Unit").fetchall():
    if blob is None:
        continue
    with open(os.path.join(dst, "mprcontents", str(uuid.UUID(bytes_le=bytes(uid))) + ".mxunit"), "wb") as f:
        f.write(blob)
con.execute("alter table Unit drop column Contents")
con.commit(); con.close()
