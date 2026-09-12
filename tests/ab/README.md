# ab-fixture — Harbour Berth Booking

The fixture side of a controlled A/B experiment on the mxcli-project-toolkit's Stage 0–2
pipeline (intake → triage → source ledger → BRDs). One fictional application, one answer key,
a deterministic corpus generator, and a scorer. **Everything is synthetic** — no real company,
product, person or client data appears anywhere; the port authority does not exist.

| File | What it is | Who sees it |
|---|---|---|
| `answer-key.json` | Ground truth: entities, associations, requirements, business rules, contradictions, screenshot-only rules, roles, screens, and the corpus plan (which page carries what, chrome pages, sidecar image counts) | **experimenter + scorer only** |
| `gen-corpus.py` | Renders the key into a "webpage, complete" documentation export | experimenter |
| `corpus/` | One generated corpus (default seed 20260909) — the thing the agents under test get, **minus `MANIFEST.json`** | agents under test (without the manifest) |
| `corpus/MANIFEST.json` | What actually landed where: files, sizes, per-id placements, chrome list | **experimenter + scorer only** |
| `score.py` | Scores a toolkit project after an agent ran Stages 0–2 on the corpus | experimenter |

## The rules

1. **Agents under test never see `answer-key.json` or `MANIFEST.json`.** Give them the corpus
   directory generated with `--no-manifest`, or delete `MANIFEST.json` before handing it over.
   Do not put the fixture directory itself anywhere a session under test can list.
2. Both arms of the experiment run on the **same seed** — the generator is deterministic
   (byte-identical output for the same key + seed; verified with md5 over every file).
3. The scorer is mechanical. It fetches facts and prints them; it does not judge BRD quality
   beyond what the key states. Read the matching table before believing a number.

## Generate

```bash
python3 gen-corpus.py <out-dir> [--seed N] [--no-manifest] [--key answer-key.json]
```

Python 3 stdlib only. ~25 s. Produces ~13 MB:

- 36 HTML pages `NN-title.html`, each with a `NN-title_files/` folder holding 3–12 PNG/JPG
  images, `site.css` (+ sometimes `print.css`), `app.js`, and a `.woff` stub — the way a browser's
  "Webpage, complete" export looks. Every page repeats the same header, cookie banner, sidebar
  nav (all 36 pages) and footer. Markup is verbose: nested `div` wrappers, inline styles, class
  soup.
- 6 of the 36 are pure chrome (home, about, release notes, news, privacy, contact): no
  requirements. The release notes contain changelog lines that *look* like requirements.
- 8 pages carry a one-line minified block of 22–40 KB (a berth-occupancy "heatmap" of spans).
  Two key statements (R044, B015) live **inside** such a line — line-based readers that truncate
  long lines miss them.
- 9 pages embed inline `data:image/png;base64` screenshots (58–67 KB each) of prototype screens.
- Requirements are spread across prose, bullet lists, 2-column tables ("Requirement | …"), and
  four are negatively phrased ("There is no automatic approval …").
- 4 Markdown files: `glossary.md` (entity definitions), `roles.md`, `decisions-log.md` (ADR
  style; carries R048 and B009), `workshop-notes.md` (carries R046, R047).
- 3 contradictions on different pages (C001 auto-approval vs none; C002 cancellation 24 h vs
  72 h; C003 who may waive a surcharge).
- 2 requirements that exist **only inside an image** — S001 as a sidecar PNG on page 09
  (`fig-booking-form-validation.png`: "IMO number must be exactly 7 digits"), S002 as an inline
  base64 PNG on page 21 (`id="fig-review-decision"`: "Rejection reason is required when outcome
  is Rejected"). The generator's self-test greps every text file to prove neither string leaks.
  Text is drawn with a 5x7 bitmap font at 3x scale; verified legible by a vision model.

Images are pure-Python: PNG via zlib, baseline JPEG via a ~60-line encoder with fixed-length
Huffman tables (valid for every decoder, deliberately inefficient — the bulk is the point).

## Run the experiment

For each arm: scaffold a toolkit project (`bin/init-project.sh <project>`), copy the corpus into
`<project>/sources/<anything>/` **without** `MANIFEST.json`, and let the agent run Stages 0–2
per `skills/conversion-runbook.md`. Then score.

## Score

```bash
python3 score.py <project-dir> --key answer-key.json [--json] \
    [--toolkit ~/Mendix/mxcli-project-toolkit] [--manifest corpus/MANIFEST.json] \
    [--brd-dir DIR] [--include-analysis] [--no-run]
python3 score.py --self-test          # generates a corpus, scores fabricated perfect/half/paraphrased/empty projects
```

What it reads (toolkit conventions, not invented ones): BRDs via the three-path convention of
`bin/lib/discover-brds.sh` (`analysis/*/knowledge-base/brd`, `analysis/knowledge-base/brd`,
`knowledge-base/brd`); `PROJECT.md` (Decisions and Open questions tables, `## Current stage`,
`Adopted at stage` / `Waived …` lines); `analysis/triage.md`; `analysis/sme-questions.md`;
`docs/BUILD-LOG.md`; `.claude/` receipts; and, when the toolkit is reachable (`--toolkit`,
`$MXTK_TOOLKIT`, the `Toolkit root` row in `CLAUDE.local.md`, or `~/Mendix/mxcli-project-toolkit`),
it runs `bin/source-ledger.sh check --json` and `bin/gate-check.sh <project> 1` / `2`.

| Metric | How it is computed |
|---|---|
| Requirement recall | key requirement counts as found when some BRD statement has stemmed-keyword overlap ≥ 0.6 of the key statement's tokens, or cites its id (`R012`), or cites its page file with overlap ≥ 0.5. Negation-aware: a key statement with no/not/never/cannot/only/without only matches a candidate that also carries a negation (or "manual"). |
| Requirement precision | 1 − phantoms / claims. **Claims** are use-case titles, items of any `requirements` / `businessRules` / `rules` / `validations` / `hiddenRules` array, and microflow validations. Main-flow steps, purposes and descriptions are used for recall but are not claims. A claim is grounded when it overlaps ≥ 0.5 with any key requirement, rule or screenshot-only rule. |
| Business-rule recall | as requirements, **and** every `must_contain` group of the rule (its threshold/state: "72", "overdue", "harbour master|harbourmaster") must appear in the same statement. The table's Note column says "statement found but threshold missing" when the rule was paraphrased without its number. |
| Entity / attribute / association recall | BRD `domainEntities[].name` vs key entities (normalised; a BRD "Agent" matches "ShippingAgent"); attributes by normalised name with prefix/suffix tolerance ("IMO" matches "IMONumber"); associations as unordered entity pairs from `domainEntities[].associations[].target` or a top-level `associations[]`. |
| Contradictions surfaced (0–3) | a row of PROJECT.md's tables, a BRD `openQuestions` entry, an `sme-questions.md` line, or an `analysis/**/*.md` line mentioning contradict/conflict/inconsistent, that either cites both requirement ids or contains a term from every `detect_terms` group of the contradiction. |
| Screenshot-only found (0–2) | any BRD statement, register row or question carrying all `must_contain` groups with overlap ≥ 0.6. The ledger verdict on the sidecar screenshot image is reported next to it. |
| Ledger | `counts` from `source-ledger.sh check --json` (EXTRACTED/WAIVED/PENDING/FAULT/drift) and the same verdicts bucketed by file kind (chrome pages, content pages, sidecar images, sidecar support files, markdown) — the key's `corpus.pages[].chrome` and `sidecar_images` tell the scorer which rows are which. With `--manifest`, row count vs manifest file count. |
| Gates | the `Stage N (…): VERDICT` line of gate-check for stages 1 and 2, the register's current-stage line, waiver/adoption lines, BUILD-LOG stage lines, `.claude/` receipts. |

`--json` prints every table as machine-readable numbers; the Markdown output includes the full
per-id matching table (nearest BRD statement and where it lives), the phantom list, and the
ledger-by-kind table.

### Known biases of the scorer (read before comparing arms)

- Fuzzy matching over-credits near-twins: in the self-test's half set the section-cite and
  negation rules were tuned until the planted 24/48 scored exactly 0.5, but a BRD that
  restates a rule verbatim next to a requirement on the same page can still earn a match for
  both. Look at the `How` column (`overlap` / `id-cite` / `section-cite`).
- Precision counts changelog lines and marketing copy an agent turns into "requirements" as
  phantoms. That is intended (the chrome pages are noise), but an agent that lists *technical*
  ADRs from `decisions-log.md` as requirements is penalised too.
- Roles/screens are a cheap substring presence check over BRD actors and statements, not a
  quality measure.
- Gate verdicts depend on the toolkit version found; the scorer reports which root it used.

## What the self-test proves

`score.py --self-test` generates a corpus into a temp dir and asserts: size 8–20 MB, 36 pages
with 6 chrome, no screenshot-only text in any text file, every key statement on its page, ≥ 6
pages with a > 20 KB line; then fabricates a perfect BRD set from the key (recall 1.0 /
precision 1.0 / rules 15/15 / entities + attributes + associations 1.0 / 3 contradictions / 2
screenshot-only), a half set with three planted phantoms (recall ≈ 0.5, exactly 3 phantoms,
0/3 and 0/2), a paraphrase set (reworded rules match; a rule without its threshold does not),
and an empty project (recall 0, precision n/a). When the toolkit is reachable it also copies
the corpus under `sources/`, runs `source-sufficiency.sh init` and checks the ledger inventoried
every file as PENDING.

## Regenerating the key's corpus plan

The corpus plan (`corpus.pages[]`, `corpus.markdown[]`) lives in the key so the generator and
the scorer cannot drift: every requirement/rule/screenshot id is placed exactly once, and each
item's `section.file` must equal the page that carries it (the generator raises otherwise).
Change the key, regenerate, re-run the self-test.

## Validation branch `ab/final` (throwaway — never merged)

Merged master (PR #37) plus `corpus/`, the small variant of the synthetic corpus, so one
Sonnet run can exercise the shipped docs-ready path through Stage 4. The answer key sits in
this same directory on master; the session under test is told not to open anything under
`tests/ab/` beyond copying `corpus/`, and the report notes that caveat.
