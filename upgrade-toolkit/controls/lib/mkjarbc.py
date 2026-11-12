#!/usr/bin/env python3
"""mkjarbc.py: the T6R-10 BouncyCastle rename (jdk15on / jdk15to18 -> jdk18on) as real zips.

  mkjarbc.py <out dir> [--manifest]
userlib:   bcprov-jdk15on-1.68.jar, bcpkix-jdk15to18-1.68.jar (Encryption markers; javasource/encryption exists, so
           Encryption is present and nothing is STALE), own-helper-1.0.jar (no marker).
vendorlib: bcprov-jdk18on-1.81.jar, bcpkix-jdk18on-1.81.jar.
Default: no manifest names at all (the file name is the only identity, the shape that slipped through before T6R-10).
--manifest: the real BC 1.81 shape for vendorlib (Bundle-SymbolicName only, no Automatic-Module-Name; checked on
bcprov-jdk18on-1.81.jar from Maven Central) and no manifest name on the userlib jars.
"""
import io, os, sys, zipfile


def jar(classes, manifest=""):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n" + manifest)
        for c in classes:
            z.writestr(c, b"\xca\xfe\xba\xbe")
    return b.getvalue()


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


out, real = sys.argv[1], "--manifest" in sys.argv
cls = lambda p: [f"org/bouncycastle/{p}/C{i}.class" for i in range(6)]
put(f"{out}/userlib/bcprov-jdk15on-1.68.jar", jar(cls("jce")))
put(f"{out}/userlib/bcpkix-jdk15to18-1.68.jar", jar(cls("cert")))
put(f"{out}/vendorlib/bcprov-jdk18on-1.81.jar", jar(cls("jce"), "Bundle-SymbolicName: bcprov\nBundle-Version: 1.81\n" if real else ""))
put(f"{out}/vendorlib/bcpkix-jdk18on-1.81.jar", jar(cls("cert"), "Bundle-SymbolicName: bcpkix\nBundle-Version: 1.81\n" if real else ""))
put(f"{out}/userlib/own-helper-1.0.jar", jar(["com/example/own/Helper.class"]))
for j in ("bcprov-jdk15on-1.68.jar", "bcpkix-jdk15to18-1.68.jar"):
    put(f"{out}/userlib/{j}.Encryption.RequiredLib")
put(f"{out}/javasource/encryption/actions/Keep.java", b"package encryption.actions;\n")
put(f"{out}/App.mpr", b"Encryption")
