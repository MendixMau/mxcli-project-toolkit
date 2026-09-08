# Improvement Register — findings accumulate; a check-run does not

**Applies to:** any project running `module-review.md`, `process-coherence-pass.md`,
`monkey-test.md`, or `wiring-sweep.md` more than once.
**Companion:** `close-the-loop.md` (the same append-and-drain shape, applied to findings instead
of session state); `coverage-ledger.md` (the same shape again, applied to requirement scope).

---

## The failure mode this exists to close

Every review pass in this toolkit already produces a report — `module-review.md`'s one
self-contained HTML file per pass, `process-coherence-pass.md`'s structured findings list,
`monkey-test.md`'s three-line summary. Each is honest about *that run*. None of them, on their
own, can answer a question that only exists across runs: **is this the same class of defect
showing up for the fourth time, or four unrelated bugs?**

`module-review.md`'s own "Defining acceptable" table already names the failure by its wrong
answer: *"a rising trend read as N unrelated one-offs"* is listed as **not acceptable** for the
monkey gate, and the Acceptable column says to *"track findings-per-module as a trend"* — but
names no mechanism. A report that resets to zero every pass cannot distinguish a fluke from a
pattern, and a pattern (the same defect class recurring across modules) is itself a finding — one
about the *process* that keeps producing it, not about any single module. That finding is
currently invisible, because nothing outlives the pass that found it.

## What this is not

Not a duplicate of any pass's own report. Each pass's HTML/structured output stays the record of
*that run*, screenshots and all. This register holds the **one-line distillation** of every P1/P2
that crossed a pass's threshold, plus its disposition — so that "how many times has this class of
thing happened" is a grep, not an archaeology project across a directory of dated HTML files.

Not a second place to file the same finding. Per `close-the-loop.md`'s third rule — **nothing
goes in two places** — a finding lives in its originating pass's own report; this register holds a
pointer-row back to it, not a copy of the finding's full detail.

## The register

One file, project-level, append-only: `docs/improvement-register.md`. One row per finding.

```markdown
| Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition |
|---|---|---|---|---|---|---|
| 2026-08-19 | OrderMgmt | module-review §4c | dead-wiring | P1 | "Submit Decision" button has no action | fixed same session |
| 2026-08-19 | Workflow | process-coherence-pass 1 | dead-wiring | P1 | SubmitToDownstream mf, zero refs anywhere | deferred — see PROJECT.md #14 |
| 2026-08-20 | Approvals | module-review §4c | dead-wiring | P1 | "Record Decision" button has no action | fixed same session |
```

**Defect class is a closed, reused vocabulary — do not invent a new one per row.** Use
`module-review.md`'s own seeded-defect-pass categories, which already cover the classes this
toolkit's passes are built to catch:

`dead-wiring` · `unreachable-terminal-state` · `vocabulary-mismatch` · `swallowed-error` ·
`access-rule-gap` · `unstyled-page` · `blank-render` · `missing-empty-state` · `reuse-gap` ·
`crash` (monkey-test.md's crash class) · `other` (rare; if `other` recurs, that is itself a signal
the vocabulary needs a new class, not that nothing recurs)

A fixed, shared vocabulary is what makes the trend read possible — free-text descriptions of "what
went wrong" do not group into a count.

## Ingesting `mxcli report` / `mxcli lint`

mxcli's own lint rules (QUAL/SEC/ARCH/MDL/design/CONV series, `mxcli report --format markdown` or
`mxcli lint --format json`) already carry a category and severity. Do not re-derive a class for
these by hand — map mxcli's category onto the register's `Source pass` column (e.g. `mxcli lint
QUAL004`) and keep mxcli's own severity, rather than forcing every mxcli finding through the
defect-class list above, which is scoped to what the toolkit's own passes catch. A row from `mxcli
report` is still one row; the register does not care whether the fact came from a toolkit skill or
a native mxcli instrument, only that it is dated, classed, and dispositioned.

## Trigger — when a row gets appended

- `module-review.md` stage 5 (CONFIRM): every P1/P2 in that pass's report gets one row here before
  the pass is considered closed. This is the primary feed — it fires every module, not every
  cluster.
- `process-coherence-pass.md`'s output: every finding from passes 1–4, `Measured` or `Judged`.
- `monkey-test.md`: every `crash`-class finding (not `info` — those are triage noise by the
  skill's own reading and would flood the register with non-signal).
- `wiring-sweep.md`: every FAIL/FAULT row.
- Ad hoc, whenever `mxcli report`/`mxcli lint` surfaces something the user wants tracked across
  time rather than fixed once and forgotten.

## The trend read — the actual point of keeping this

Read at `process-coherence-pass.md`'s cluster cadence (every N=2–3 modules) and always at Stage 6:

```
grep by Defect class, count occurrences, group by whether Disposition is "fixed" or not.
```

**Three or more rows in the same `Defect class` across different modules is itself a P1/P2
finding — file it as one**, with `Source pass` = `improvement-register.md trend read` and a
description of the *process* gap (a checklist item nobody is running, a pattern nobody
documented as mandatory) rather than the individual defect, which is already filed on its own
row. This is the mechanism `module-review.md`'s Acceptable table names and does not build: a
recurring class read as one process finding, not silently re-counted as N independent one-offs
each time it recurs.

## The rendered surface

`bin/render-improvement-register.sh` (installed by the toolkit; toolkit copy:
`project-bin/render-improvement-register.sh`) renders the register as one self-contained HTML
page, `docs/improvement-register.html` — the findings table, counts by disposition-read and
severity, and the opened-vs-closed-over-time view the markdown itself cannot show. Run it after
each pass that appends findings, so the page a stakeholder opens is never a pass behind the
file. It renders only: what counts as a finding, when one may close, and what a recurring class
means stay here in this skill — the trend read above is still performed by a person against the
register, and the page's "closed" tag is nothing more than this skill's own fixed/resolved grep
made visible, with the raw disposition text alongside it.

## The three rules

1. **A row is appended, never edited to hide what happened.** If a disposition changes (a deferred
   finding gets fixed later), append a new row referencing the old one; do not rewrite history —
   same discipline as `close-the-loop.md`'s `BUILD-LOG.md`.
2. **Nothing is filed twice.** The full finding detail stays in its originating pass's own report;
   this register holds the distillation and a pointer, not a duplicate.
3. **A trend finding is filed the same way a defect finding is** — as its own row, with its own
   disposition, not just observed and left as a comment. An observed-but-unfiled trend is exactly
   the failure this register exists to prevent.

## Corrections — a superseded claim gets a row, or it comes back

The register also carries **corrections**: a claim an earlier artifact made that a later
measurement overturned. Without a row, the old claim resurfaces — it is still in the BRD, the
blueprint cites the BRD, the brief cites the blueprint, and the next session reads whichever it
opens first. On the 2026-09-02 post-mortem project several superseded claims did exactly that,
in documents that cited each other.

One row per correction, appended, never edited:

| # | Date | Claim (verbatim, with where it lives) | Measurement that overturned it (query or file, with the number) | Where the old claim still stands, and who flushes it |
|---|---|---|---|---|
| C-01 | 2026-09-02 | "Approval is a 15-step sequential chain" — blueprint §21.1, F007 | `Workflowtabelle` rows for the current WFVersion: 7 legs, predecessor column; 21 populated rows | blueprint §21.1–21.2, scripts 80/82/84 → architect, before Stage 4 re-gate |

The fifth column is the point: a correction is not done when it is true, it is done when every
document that carried the old claim has been re-synced (`conversion-runbook.md` §3b drift-sync
uses the same `[sync: … UNSYNCED]` marker; a correction row is what puts the marker there).
Numbers in the fourth column carry their query — a correction stated without its measurement is
the same defect it is correcting.

## Related

- `skills/close-the-loop.md` — the append-and-drain shape and the routing-by-lifespan rule this
  register follows; add a row to that skill's Destinations table pointing here for P1/P2 findings.
- `skills/coverage-ledger.md` — the same shape, applied to requirement traceability instead of
  defects.
- `skills/module-review.md` — CONFIRM stage is the primary feed; the "Defining acceptable" table's
  unbuilt "track findings-per-module as a trend" line is what this skill implements.
- `skills/process-coherence-pass.md`, `skills/monkey-test.md`, `skills/wiring-sweep.md` — the
  other three feeds.
