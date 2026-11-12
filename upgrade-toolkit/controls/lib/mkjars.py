#!/usr/bin/env python3
"""mkjars.py: build the synthetic jar folders for the jarclash controls (Academy AC-6 shape, Apache names only).

  mkjars.py <out dir> clash|clean
clash: userlib/markdown-all-0.50.jar carries lib/pdfbox-2.0.24.jar inside it (the hidden copy), and
       userlib/pdfreader-1.0.0.jar carries pdfbox classes directly (a module with no newer version);
       vendorlib/pdfbox-3.0.3.jar is what CommunityCommons needs. Markers name the owning modules.
clean: vendorlib/pdfbox-3.0.3.jar and an unrelated jar; a shaded (relocated) pdfbox copy does not clash.
"""
import io, os, sys, zipfile

PDF = [f"org/apache/pdfbox/{p}.class" for p in ("pdmodel/PDDocument", "pdmodel/PDPage", "pdmodel/PDResources",
                                               "cos/COSDocument", "cos/COSName", "io/RandomAccessRead")]


def jar(classes, maven=None, nested=None):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
        for c in classes:
            z.writestr(c, b"\xca\xfe\xba\xbe")
        if maven:
            g, a, v = maven
            z.writestr(f"META-INF/maven/{g}/{a}/pom.properties", f"groupId={g}\nartifactId={a}\nversion={v}\n")
        for name, data in (nested or {}).items():
            z.writestr(name, data)
    return b.getvalue()


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


out, kind = sys.argv[1], sys.argv[2]
put(f"{out}/vendorlib/pdfbox-3.0.3.jar", jar(PDF, ("org.apache.pdfbox", "pdfbox", "3.0.3")))
put(f"{out}/vendorlib/commons-io-2.21.0.jar", jar(["org/apache/commons/io/IOUtils.class"], ("commons-io", "commons-io", "2.21.0")))
if kind == "clash":
    inner = jar(PDF, ("org.apache.pdfbox", "pdfbox", "2.0.24"))
    put(f"{out}/userlib/markdown-all-0.50.jar",
        jar(["com/example/md/Parser.class", "com/example/md/Node.class"], ("com.example", "markdown-all", "0.50"),
            {"lib/pdfbox-2.0.24.jar": inner}))
    put(f"{out}/userlib/pdfreader-1.0.0.jar", jar(PDF + ["pdfreader/actions/ReadPdf.class"]))
    open(f"{out}/userlib/pdfreader-1.0.0.jar.PDFReader.RequiredLib", "w").close()
    open(f"{out}/userlib/markdown-all-0.50.jar.Markdown.RequiredLib", "w").close()
else:
    put(f"{out}/userlib/report-tool-1.2.jar",
        jar([c.replace("org/apache/pdfbox", "com/example/shaded/pdfbox") for c in PDF], ("com.example", "report-tool", "1.2")))
