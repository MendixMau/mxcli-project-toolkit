# Fixture provenance — images-to-md

**Every input file this fixture uses is built on the fly, by `gen-fixture.py` in this folder,
at test-run time.** Nothing binary is committed here. Why that is the right call for this
instrument specifically (CLAUDE.md's "golden input is captured, never hand-written" guards
parsers of TOOL output, whose real columns nobody imagines — the same reasoning
`tests/wave2/fixtures/html-to-md/CAPTURE.md` already sets out for a saved webpage export):

- A `.pptx`/`.docx` is itself a well-specified container format (OOXML: a zip of XML parts).
  There is no "real tool's undocumented output shape" to fail to imagine here — the shape the
  extractor depends on (`ppt/media/`, `ppt/slides/_rels/slideN.xml.rels`, `<a:t>` runs;
  `word/media/`, `word/_rels/document.xml.rels`, `w:pStyle`) is the format's own published
  contract, and `gen-fixture.py` builds exactly that contract from scratch with `zipfile`,
  the same way a real Office app would. A hand-built PDF is the same story: `/Subtype /Image`,
  `/Filter /DCTDecode`, `/Length` are PDF spec vocabulary, not a guess at what some PDF writer
  happens to emit.
- The one place a real tool's undocumented shape WOULD matter — a saved-webpage HTML export —
  is exactly what `tests/wave2/fixtures/html-to-md/` already pins with a hand-authored capture;
  this fixture's own `page.html` is a trivial, uncontroversial sidecar case (one `<img>`, one
  `_files/` folder) reused only to prove images-to-md does not double-count what html-to-md
  already produced — the interesting HTML shape is that fixture's job, not this one's.
- Committing generated binaries (PNG/JPEG/PPTX/DOCX/PDF bytes) would make every diff of this
  fixture opaque. Committing the *generator* keeps the fixture readable and lets the dedup case
  (two on-disk files with byte-identical content) be stated in code instead of eyeballed.

What `gen-fixture.py` builds, and why each piece is in the corpus:

| Piece | Why |
|---|---|
| loose `tiny.png`, 16×16 | the size-floor rule: long edge < 64px → role `chrome`, never owed a description |
| loose `photo.jpg`, a real baseline JPEG (encoder below) | a loose content image outside any container |
| `page.html` + `page_files/shot.png` + `page_files/site.css` | the html-to-md sidecar case — run `bin/html-to-md.sh` first, then prove the sidecar image is found once, not double-counted with html-to-md's own index row |
| `Deck.pptx`, 3 slides | `ppt/media/image1.png` (slide 1) and `ppt/media/image3.png` (slide 3) are **byte-identical but different zip entries** — the dedup has to work on sha256 of decoded bytes, not "same media filename"; `ppt/media/image2.png` (slide 2) is distinct. Each slide carries an `<a:t>` text run, which the worklist must show as that image's context. |
| `Spec.docx`, one image | `word/media/image1.png` sits in a paragraph after a `Heading1` paragraph — the nearest-preceding-heading mapping, best effort |
| `Doc.pdf`, one hand-built `/DCTDecode` image object | the raw-JPEG extraction path; the PDF is built with an explicit `xref` table, one image XObject, `/Length` stated exactly |

The JPEG encoder in `gen-fixture.py` is the same pure-Python baseline encoder already proven in
`tests/ab/gen-corpus.py` (trivial fixed-length Huffman tables — valid for any decoder, no
memorised spec tables needed), reproduced here in compact form so this fixture has no import
dependency on another test's generator.
