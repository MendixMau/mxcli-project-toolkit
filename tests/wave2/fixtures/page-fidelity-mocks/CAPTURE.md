# page-fidelity-mocks — what these two wireframes are, and what was changed

`page-fidelity.js` parses **wireframe HTML**, so per `CLAUDE.md` -> "Shipping an instrument"
rule 1 its fixture input must be a real capture, not something imagined. These two files
reproduce the STRUCTURE of two real wireframes from a **MOC/PSSR app replacement**
(requirements-driven, 2026-09-09) — the grouped project overview and the approver queue —
and **only their literal text and class prefixes were changed**, because the wireframes
themselves and the palette in them are a customer's.

**What is verbatim, because every one of these is a fact nobody would have imagined:**

- the `div.wf-wrap > div.wf-screen` boundary, with `div.anno` as a **sibling** of the
  screen and not a child;
- `.page-head` holding the page's only `<h1>` **and** a `.sub` paragraph **and** a
  `.page-actions` block, all in one once-used div;
- `.toolbar` once-used, holding a search input and a filter select;
- the group heading / table / pager triple **repeated twice**, which is what makes
  `.x-group-head`, `.x-tablewrap` and `.pager` used-twice and `.page-head` used-once in
  the same file — the pair the classifier has to separate;
- sample rows as `<td>` text with chips as `<span>`, three list items in the other file;
- the whole class vocabulary declared in the wireframe's **own** `<style>` block, which is
  what puts all of it in front of the classifier in the first place.

**What was changed:** the record names, department names, site codes, page titles and the
class prefix (`ds-` -> `x-` for the design-system-looking names, so the fixture cannot be
mistaken for a claim about any real design system). No line was reflowed, no block
reordered, no selector altered, no structure simplified.

**Two `class="bound"` elements were ADDED to `grouped-overview.html`**, and they are the one
thing here that is not a reduction of the real file: an `<h2 class="bound">` holding a record's
own title and a `<span class="bound">` holding a filename. They stand in for the real detail
page's `<h1>` and file chip, which is where the defect was found (54%, all three misses being
sample values a correctly binding page cannot contain). Reproduced on the overview fixture
rather than adding a third wireframe, because the marker's behaviour has nothing to do with
which screen carries it.

**Counts measured on the REAL overview wireframe** (the numbers the defect was found on):

| class | uses | subtree kept when dropped | old verdict | correct verdict |
|---|---|---|---|---|
| `page-head` | 1 | 0.513 | mock (deleted the h1) | structure |
| `toolbar` | 1 | 0.825 | mock | structure |
| `ds-card` | 1 | 0.962 | mock | structure |
| `ds-tablewrap` | 2 | 0.172 | mock | mock |
| `ds-state` | 10 | 0.795 | mock | mock |

The old rule was `uses === 1 && kept < 0.4` -> structure. Only `ds-card`-sized wrappers
cleared it; the page header did not, and it is the one holding the heading.
