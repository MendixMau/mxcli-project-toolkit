#!/usr/bin/env python3
"""mkjarid.py: jar folders with the T3-3 / T3-17 name shapes (Apache libraries, real zips, pom.properties / manifest only).

  mkjarid.py <out dir>
userlib: commons-codec-1.15.jar and commons-codec.commons-codec-1.15.jar (one library under two names),
         org.apache.commons.io-2.3.0.jar (TcConnector marker) and commons-io-2.11.0.jar (CommunityCommons marker),
         org.apache.commons.lang3.jar (NO version in the name, manifest only: Automatic-Module-Name + Bundle-Version 3.1),
         own-helper-1.0.jar (no marker, the app's own).
vendorlib: commons-io-2.21.0.jar, commons-lang3-3.20.0.jar (manifest only, same module name).
Class names are shared inside a pair so jarclash sees the clash.
"""
import io, os, sys, zipfile


def jar(classes, maven=None, manifest=""):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n" + manifest)
        for c in classes:
            z.writestr(c, b"\xca\xfe\xba\xbe")
        if maven:
            g, a, v = maven
            z.writestr(f"META-INF/maven/{g}/{a}/pom.properties", f"groupId={g}\nartifactId={a}\nversion={v}\n")
    return b.getvalue()


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


out = sys.argv[1]
cls = lambda p, n=6: [f"org/apache/commons/{p}/C{i}.class" for i in range(n)]
codec = jar(cls("codec"), ("commons-codec", "commons-codec", "1.15"))
put(f"{out}/userlib/commons-codec-1.15.jar", codec)
put(f"{out}/userlib/commons-codec.commons-codec-1.15.jar", codec)
put(f"{out}/userlib/org.apache.commons.io-2.3.0.jar", jar(cls("io"), ("commons-io", "commons-io", "2.3")))
put(f"{out}/userlib/commons-io-2.11.0.jar", jar(cls("io"), ("commons-io", "commons-io", "2.11.0")))
put(f"{out}/vendorlib/commons-io-2.21.0.jar", jar(cls("io"), ("commons-io", "commons-io", "2.21.0")))
put(f"{out}/userlib/org.apache.commons.lang3.jar",
    jar(cls("lang3"), manifest="Automatic-Module-Name: org.apache.commons.lang3\nBundle-Version: 3.1\n"))
put(f"{out}/vendorlib/commons-lang3-3.20.0.jar", jar(cls("lang3"), manifest="Automatic-Module-Name: org.apache.commons.lang3\n"))
put(f"{out}/userlib/own-helper-1.0.jar", jar(["com/example/own/Helper.class"], ("com.example", "own-helper", "1.0")))
for j, m in (("org.apache.commons.io-2.3.0.jar", "TcConnector"), ("commons-io-2.11.0.jar", "CommunityCommons"),
             ("org.apache.commons.lang3.jar", "TcConnector"), ("commons-codec-1.15.jar", "XLSReport")):
    put(f"{out}/userlib/{j}.{m}.RequiredLib")
