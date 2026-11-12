#!/usr/bin/env python3
"""mprunits.py: the one reader of the Unit table for every tool that looks at a model (NR2-3, NR2-10).

An MPR v1 keeps each unit's BSON in Unit.Contents. An MPR v2 (every Git app since 10.x) keeps it in
mprcontents/**/<uuid>.mxunit and its Unit table has NO Contents column, only ContentsHash, so `select Contents from
Unit` dies with "no such column: Contents". Read the columns first, then fall back to the files.

  from mprunits import unit_rows
  for uid, cid, blob in unit_rows(mpr_path): ...     # blob is bytes or None (a unit with no content anywhere)
"""
import glob, os, sqlite3, uuid


def unit_rows(mpr, proj_dir=None):
    """[(UnitID bytes, ContainerID bytes|None, BSON bytes|None)] for an MPR v1 or v2. proj_dir: the folder holding
    mprcontents/ when it is not the folder of the .mpr (a package extracted next to its own mprcontents/)."""
    proj = proj_dir or os.path.dirname(os.path.abspath(mpr))
    con = sqlite3.connect(f"file:{mpr}?mode=ro", uri=True)
    try:
        cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
        rows = con.execute("select UnitID, ContainerID, " + ("Contents" if "Contents" in cols else "NULL") + " from Unit").fetchall()
    finally:
        con.close()
    files = {}
    if os.path.isdir(os.path.join(proj, "mprcontents")):
        for f in glob.glob(os.path.join(proj, "mprcontents", "**", "*.mxunit"), recursive=True):
            files[os.path.basename(f)[:-7].lower()] = f
    out = []
    for uid, cid, blob in rows:
        if blob is None and files:
            f = files.get(str(uuid.UUID(bytes_le=bytes(uid))).lower()) or files.get(str(uuid.UUID(bytes=bytes(uid))).lower())
            if f:
                with open(f, "rb") as fh:
                    blob = fh.read()
        out.append((bytes(uid), bytes(cid) if cid else None, bytes(blob) if blob else None))
    return out
