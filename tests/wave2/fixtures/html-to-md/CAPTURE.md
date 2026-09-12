# Fixture provenance — html-to-md

**This page is synthetic.** `Fleet Portal Requirements.html` and its `_files/` sidecar were written
by hand on 2026-09-09 in the SHAPE of a browser "Save page as… (complete)" export of a wiki page —
the shape the requirements-driven project that motivated `bin/html-to-md.sh` had hundreds of.
The real exports are a client's requirements and cannot be committed; nothing here was copied
from them.

Why a synthetic page is acceptable here, when CLAUDE.md says golden input is captured, never
hand-written: the rule guards parsers of TOOL output, whose real columns nobody imagines. A saved
webpage has no tool contract — every wiki writes different markup — so there is no single
"real output" to capture, and the instrument's job is exactly to survive whatever markup shows
up. What this fixture pins is the STRUCTURAL facts observed on the real exports, each one put
here because the converter has to get it right:

| Fact reproduced | Why the converter depends on it |
|---|---|
| `<!-- saved from url=… -->` comment, `<title>`, `<link>` to `./<Page>_files/site.css`, `<script src>` | the sidecar folder is named `<page stem>_files/` and its css/js are chrome of that page, not content |
| a `<header role=banner>` holding a `<nav>`, a `div.sidebar`, a `div.breadcrumbs`, a `div.cookie-banner`, a `<footer role=contentinfo>` | each is a chrome region that must be dropped; every one carries a `*SENTINEL-n` token the fixture asserts is absent |
| inline `<style>` and two `<script>` blocks, a `<noscript>`, an `<svg>` | dropped whole; each carries a sentinel |
| `<main role=main>` wrapping `div.content-wrapper` → `div.wiki-content` with inline styles | the content lives three wrapper divs deep; nothing about a wrapper's class may drop it (`toc-macro` wraps a real `<h2>`) |
| h1 → h2 → h3 outline, a nested `<ul>`, an `<ol>`, a `<table>` with `<thead>/<tbody>/<colgroup>`, a `<pre>`, `<code>`, `<strong>`/`<b>`/`<em>` | the constructs the Markdown must keep, and the section list must number |
| one `<img>` to the sidecar png and one inline `data:image/png;base64` img | sidecar referenced by its existing path; inline decoded to `<page>_images/01.png` |
| `glossary.md` beside the page | a Markdown source is listed (role `markdown`), never converted |

The PNG is the well-known 1×1 transparent PNG (70 bytes), used both inline and as the sidecar
file so the base64-decode path writes a byte-identical, valid image.
