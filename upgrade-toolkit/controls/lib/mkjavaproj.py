#!/usr/bin/env python3
"""mkjavaproj.py: a project folder for the T6R-5 grep rules of release_impact.py --auto (javasource + userlib).

  mkjavaproj.py <out dir> [--own-uses] [--jar-hit] [--git]
Default: MendixSSO's own Java imports com.nimbusds and calls IContext.rollbackTransAction() (as the real MendixSSO 4.0.2
does); CommunityCommons imports org.apache.commons.lang3; a generated proxy names AdminException (proxies are excluded);
userlib/fixture-helper.jar holds one class that names nothing of the rows. The real Checklist 9.24 app shape (T6R).
--own-uses: an own module (MyFirstModule) imports com.nimbusds and names AdminException: those rows stay open.
--jar-hit:  userlib/fixture-helper.jar also names bundleComponentLoaded and IMxRuntime in a class file.
--git:      an empty .git folder (the vcs fact).
"""
import io, os, sys, zipfile

out, own, jarhit, git = sys.argv[1], "--own-uses" in sys.argv, "--jar-hit" in sys.argv, "--git" in sys.argv


def put(rel, data):
    p = os.path.join(out, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "wb").write(data if isinstance(data, bytes) else data.encode())


put("javasource/mendixsso/implementation/UserManager.java",
    "package mendixsso.implementation;\nimport com.nimbusds.oauth2.sdk.token.AccessToken;\n"
    "class UserManager { void f(com.mendix.systemwideinterfaces.core.IContext c) { c.rollbackTransAction(); } }\n")
put("javasource/communitycommons/StringUtils.java",
    "package communitycommons;\nimport org.apache.commons.lang3.StringUtils;\nclass S {}\n")
put("javasource/myfirstmodule/proxies/Gen.java", "package myfirstmodule.proxies;\n// AdminException IMxRuntime\nclass Gen {}\n")
put("javasource/myfirstmodule/actions/Keep.java",
    "package myfirstmodule.actions;\n" + ("import com.nimbusds.jwt.JWT;\nclass Keep { Object e = AdminException.class; }\n"
                                          if own else "class Keep {}\n"))
b = io.BytesIO()
with zipfile.ZipFile(b, "w") as z:
    z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
    z.writestr("com/example/fixture/Helper.class",
               b"\xca\xfe\xba\xbe\x00\x01" + (b"bundleComponentLoaded\x00IMxRuntime" if jarhit else b"helper"))
put("userlib/fixture-helper.jar", b.getvalue())
if git:
    os.makedirs(os.path.join(out, ".git"), exist_ok=True)
