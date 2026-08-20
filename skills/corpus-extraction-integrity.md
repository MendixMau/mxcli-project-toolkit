# Corpus extraction integrity

**Applies to:** any project that extracts structured requirements from a delivered document set —
spreadsheets, specs, contracts — into per-scope knowledge-base files that agents then read.

Learned on a large document-driven conversion project, where a document corpus of several hundred
files fed a requirements pipeline. Every rule below cost something to discover.

---

## 1. A scope-filtered extractor silently drops everything global

The natural implementation keeps a table row when the row mentions the scope:

```python
if match.search(line):
    rows.append(line)
```

Correct for per-item sheets. **Catastrophic for global ones** — a cross-reference map, an index, a
rulebook. Their rows carry no scope token, so they match nothing, the section ends up empty, and it
disappears with no error.

Cost on one project: hundreds of sections and tens of thousands of rows, including the only
state-transition matrix in the corpus, the cross-application handoff contract, and well over a
thousand validation rules. Four separate agents then reported those findings as *"absent from the
corpus"* — and their reports read as verified fact.

**Fix.** Build a union matcher of all scopes. A section with data rows but zero union matches is
global: write it verbatim to one shared `extracted-global/`, not duplicated into every scope
directory (these sheets run to thousands of rows). Detect this dynamically — a hardcoded sheet list
rots the moment the corpus changes.

Anything generating from the KB must then read **both** its scope directory and the global one. Say
so in a `README.md` inside `extracted-global/`; the requirement is not discoverable otherwise.

## 2. Every extraction needs a coverage assertion counted from the source

A partial extraction and a complete one look identical: same filenames, plausible row counts, exit
zero. Nothing in the output reveals the difference.

Pick one or two totals countable from the source itself — for example, a total page count from a
page catalogue and a total action count from an action catalogue — and fail the run on mismatch.
Count from the *canonical* sheet only; summing a whole file inflates wildly and the assertion
becomes noise you learn to ignore.

Add a hard failure when the global bucket is empty. That is the precise signature of rule 1
regressing, and it is otherwise invisible.

This assertion is what eventually caught a defect that had corrupted most of the scope extractions.

## 3. Validate converters against the customer's own renditions, not by eye

If the customer shipped both the source file and their own converted version of some documents, that
is a free test set. Diff against it.

On one project: the large majority of conversions were byte-identical, a handful were lossy — and
all the lossy ones were provably the source application's fault (one `#N/A` cell, sheet names
hitting a 31-character limit). Without that comparison there is no way to distinguish *our
converter is wrong* from *their export is lossy*, and you will guess wrong.

Two traps found this way:
- `openpyxl.max_row` counts trailing blank rows. It reported thousands of rows missing that were
  never there.
- `python-docx` raises `AttributeError` on files with duplicate `<w:style>` definitions —
  `paragraph.style` is `None`. Falling back to `zipfile` + `ElementTree` reproduced a large
  document — a quarter-million characters — exactly.

## 4. Measure the cell before concluding two sources disagree

Two status fields appeared to carry contradictory value sets. Both were cells truncated at exactly
60 characters by an export limit — fragments, not competing claims. A batch of cells across the
corpus were cut the same way.

Check string length against a round number before writing up a contradiction. A truncated cell and a
short-but-complete one are indistinguishable by reading. And an unresolvable field is a cheap,
concrete customer ask: one re-export unblocked dozens of enumerations.

## 5. Agents invent over data they are already holding

The failure that motivated the enum audit: a subagent fabricated three enumerations whose correct
values were in a file it had read that same turn.

Consequences:
- **Fixing the pipeline does not fix this.** A regenerated artifact can carry the same invention.
  Diff generated values against an authoritative extract as a separate mechanical pass.
- **Generic-sounding values are the tell.** A set that would fit any system —
  `Historical/Projected`, `Pending/Mapped/Failed` — is what gets written when nobody looked. Real
  domain vocabulary is specific and idiosyncratic to the source system.
- **Disclosed uncertainty is not verification.** One artifact flagged two fields as "disputed" and
  offered two candidates. Both were wrong; the answer was in an unchecked file. "Disputed, A or B"
  reads as diligence and can still be wrong twice.
- **An honest blank beats a plausible fill.** Where a source explicitly defers values to master
  data, the correct output is no values plus a citation of the deferral. Replacing an over-claim
  with a better-sourced over-claim is still wrong.

## 6. Mark the provenance boundary before anything crosses it

Our own mock server and build guides sat inside the customer's source folder. Downstream they were
cited as customer requirement, and a demo script ended up with a spoken line attributing our own
artifacts to the customer.

Keep generated and received material in separate trees. Keep a manifest of what was actually
delivered, MD5-matched, and run a guard that reports three things: delivered-but-missing,
in-corpus-but-not-delivered, and format-only renditions of the same document.

## 7. Anonymised filenames stop describing their contents

Where files are renamed for anonymisation, the new names drift from the subject and never drift
back — e.g. a file coded `F011-equipment-management` turned out to actually be a 2D map
definition, entirely unrelated to its name.

Do not rename them once other documents cite the paths. Write an `INDEX.md` mapping identifier to
true subject, put the real name in the artifact's own `title`, and state at the top of the index
that filenames are not subjects. Then route every lookup through it.

---

## Applying this

When reviewing or writing any scope-filtered extraction:

1. Where do rows without a scope token go?
2. What total is asserted, and counted from what?
3. What does the run do when the global bucket is empty?
4. What was the converter validated against?
5. Is there a mechanical diff between generated values and source values?
6. Can you tell, from the tree alone, what the customer sent and what we made?

When an agent reports something "not found in the corpus" — **check the source before believing it.**
Four did, on the same day, and all four were wrong.
