#!/usr/bin/env python3
"""make_mpk.py APP_GIT COMMIT OUT.mpk: export one commit of a Mendix app repo as an app package (.mpk).

Layout follows a Studio Pro export: the .mpr at the root, the project folders, and a package.xml that names the
project file and lists every other file. No data snapshot (the database differs per version)."""
import io, os, subprocess, sys, tarfile, zipfile
from xml.sax.saxutils import quoteattr

KEEP = ("javasource/", "javascriptsource/", "resources/", "theme/", "themesource/", "userlib/", "vendorlib/", "widgets/")

app, commit, out = sys.argv[1:4]
tar = subprocess.run(["git", "-C", app, "archive", "--format=tar", commit], check=True, capture_output=True).stdout
tf = tarfile.open(fileobj=io.BytesIO(tar))
members = [m for m in tf.getmembers() if m.isfile()]
mpr = [m.name for m in members if "/" not in m.name and m.name.endswith(".mpr")]
assert len(mpr) == 1, f"expected one .mpr at the root of {commit}, found {mpr}"
files = sorted(m.name for m in members if m.name.startswith(KEEP))

xml = ['<?xml version="1.0" encoding="utf-8"?>',
       '<package xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://www.mendix.com/package/1.0/">',
       '  <modelerProject xmlns="http://www.mendix.com/modelerProject/1.0/">', '    <project />',
       f'    <projectFile path={quoteattr(mpr[0])} />', '    <files>']
xml += [f'      <file path={quoteattr(f)} />' for f in files]
xml += ['    </files>', '  </modelerProject>', '</package>', '']

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("package.xml", "\n".join(xml))
    for name in [mpr[0]] + files:
        z.writestr(name, tf.extractfile(name).read())
print(f"{out}: {mpr[0]} + {len(files)} files, commit {commit}")
