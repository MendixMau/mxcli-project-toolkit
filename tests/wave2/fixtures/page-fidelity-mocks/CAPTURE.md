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

## bind-contract — the five-column bind table and DESCRIBE's blind ImageUrl (2026-09-23)

`bind-contract.html` carries five rows of the real bind table in a field project's
`CatalogView-redesign-v2.html`, **verbatim in markup and prose** — including the struck
`<s>Demo chip</s>` row with its `CUT —` verdict, the CSS cell "(already a ds.css candidate)",
and the Dark-mode cell naming `#mxapp.theme-dark`. Changed: the class prefix (`mps-` -> `x-`)
and the attribute names (`LastPublishedVersionLogo` -> `LogoUrl`,
`PublisherOrganizationLogo` -> `PublisherLogoUrl`, `LastPublishedVersionDemoUrl` -> `DemoUrl`).

`bind-contract-describe.mdl` is a reduction of `mxcli describe page` (v0.23.0) output for the
built page: the two `image` widgets are verbatim apart from names, and they show the fact
nobody would have imagined — `ImageUrl: '{1}'` with **no parameters**, although the `.mpr`
holds a `Forms$ClientTemplate` whose `Parameters` carry the attribute (read from the unit's
BSON). The surrounding widgets were cut to what the rows need.

`bind-contract-alter.mdl` is the binding script's shape (`set ImageUrl = [Attr] on <widget>`),
which is what makes those bindings visible to the scorer.

Measured on the real page: bindings 13/18 -> 14/16 (DemoUrl row no longer owed; the two
image rows seen through the ALTER script), contract 16/30 -> 16/29 (`.css` gone).

## commented-template — a template comment that names `<main>` (2026-10-02)

`commented-template.html` reduces a wireframe from a requirements-driven build whose team
wrote its own wireframe template. **Verbatim in shape:** the `<!DOCTYPE>` followed by a
header comment whose rules say "inside `<main>`" and "AFTER `</main>`" (rules 3 and 7 kept
word for word apart from the product name); `div.app-shell > aside.app-rail` with a
`.userchip`; `div.app-main > main.page-column` holding `.page-header` (crumb, `h1.page-title`,
`p.page-sub`), `.seg-tabs`, a `.dg-toolbar`, a bound `.inbox` list, an `h2.section-title`
and a `table.dg`; then `div.wf-anno` with `table.bind` **after** `</main>`. **Changed:** every
name and sample value (the domain became orders and customers), and the rail, filters, rows
and bind table were cut to two or three entries each.

On the real wireframe, master's `contentOf()` matched `<main` inside the comment and scored
the comment text: `headings 0/0 actions 0/0 content 0/0 classes 0/0 bindings 3/6`, printed
as `fidelity 50%`; a sibling page printed `fidelity 100%` on `bindings 1/1`. On this fixture
master prints `fidelity 100% … bindings 2/2`; with comments stripped it is
`text-match 85% … headings 2/2 … classes 6/22 … bindings 2/2`.

`commented-template.mdl` is the page built to that wireframe; `-stub.mdl` is the same page as a
forward-reference stub carrying a `Stub:` caption; `-snippets.mdl` moves the page header into a
snippet declared in the same file and calls a second snippet that is not in the input.
