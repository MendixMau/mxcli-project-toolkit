# The judged review either happened or it didn't — put the verdict on the artifact, not in the session's memory

**From:** a Mendix workflow-and-agents POC project (requirements-driven, Stage 5+)
**Date:** 2026-09-02
**Kind:** skill-draft
**Field evidence:** this toolkit already carries five skills whose closing step is a judged pass
(`module-review.md` stage 4, `test-result-audit.md`, `finding-disposition.md`,
`e2e-evidence-report.md`, `journey-proof.md`). On a real project, **47 HTML reports** sat under
`docs/` and **exactly one** had ever had a judged review written over it — not because the rule
was unknown, but because the rule lived in prose and was wired into one runner. Measured by
`bin/review-verdict.sh --all` on 2026-09-02: 47 unstamped, 1 stamped. Two of the reports written
that same day, over the same app, disagreed with each other about whether the UI was acceptable.
**Proposed target:** `skills/judged-review-verdict.md` + `bin/review-verdict.sh`
**Companion half of the same proposal:** `contrib/inbox/2026-09-02-ui-measurement-run.md`
(proposed target `skills/ui-measurement-run.md`) — that one is the *measurement*; this one is the
*trigger and the verdict*. Neither is useful alone: a measurement nobody judges is a folder of
PNGs, and a judgement with nothing measured is an opinion.

---

## 0. The incident

A user asked, in three separate sessions over two weeks, for a UI review of a running Mendix app.
Each time a session ran something, reported it as done, and moved on. Two weeks later the user
opened the app and asked, in substance: *there are misalignments everywhere and no padding — did
that review ever actually happen?*

It had not. Three things were true at once, and each of them looked like success:

| What the session did | What it reported | What was actually true |
|---|---|---|
| Ran a measurement script over some pages | "UI measurement run complete" | it captured the top 900px of every page and 3 of ~10 pages (see the companion draft) |
| Wrote an HTML report of the captures | "report is under `docs/`" | nobody had looked at the captures; the report restated the script's own output |
| Called it reviewed | "reviewed" | no verdict existed anywhere — not in the report, not in a register, not in the chat |

**No assertion was broken and no step failed.** The failure is that the word "reviewed" had no
referent. Nothing in the project could be asked "was this reviewed?" and answer.

The toolkit had already diagnosed this exact disease and not generalised the cure.
`finding-disposition.md` says of its own founding incident that the session did the right thing
*"because that session happened to think of it, not because any skill's closing step required
it"*. That is this incident, one layer earlier: **`finding-disposition.md` governs what happens
to findings once a review exists. Nothing governs whether the review exists.**

---

## 1. The rule

> **A run is not done when the steps pass; it is done when the review has been written and its
> verdict stamped on the artifact. A report carrying no verdict reads `UNREVIEWED`, and
> `UNREVIEWED` is not green.**

The load-bearing word is **artifact**. Every prior version of this rule in this toolkit and in
the project that raised it lived in one of two places, and both are memory:

| Where the trigger lived | Why it fails |
|---|---|
| In a skill's closing prose | fires only if the acting session read that skill *and* remembered it at the end of a long run. Measured: 1 of 48 |
| Wired into one runner (`review-pass.js render`) | fires only for reports that runner produced. Every other producer of an HTML report under `docs/` — the UI measurement, the frame reviews, the verification passes, the path walks — ended at "N/N steps passed" and stopped |

So the real trigger was *"whether the session remembered, and which script it happened to run"*.
Move it onto the artifact and it becomes checkable by anyone, at any time, with no session in the
loop:

```html
<meta name="review-verdict" content="WEAK">
```

One line in the report's `<head>`. Six legal values, shared with the rest of the corpus and not
extended: `PASS` · `WEAK` · `FAIL` · `FAULT` · `BLOCKED` · `UNREVIEWED`. Absent = `UNREVIEWED`.

---

## 2. The audit — `bin/review-verdict.sh`

Sweeps every `*.html` under `docs/` and buckets it: stamped (with its verdict), stamp present but
not a recognised verdict, unstamped-and-recent, unstamped-and-predates-the-convention.

Four design decisions in it are the whole contribution, and each is a defect this toolkit has
already shipped at least once:

**a. It never infers a verdict.** Per `skills-over-scripts.md`, the judgement is written by a
session that looked; this script only reports *whether that happened*. The moment it starts
deriving a verdict from step counts it becomes the false-green it exists to retire. Its header
says so in the file, not in a commit message.

**b. Dates come from the filename, not `mtime`.** Reports are named `<thing>-YYYY-MM-DD.html`. A
git checkout rewrites every mtime to clone time, so an mtime-based cutoff flags the entire
archive on a fresh clone and the finding is discarded as noise on first sight. This is the
`_ob_find`/`_art_find` family of bug — a checker whose file selection is subtly wrong reports a
verdict about the wrong file and is *worse than absent*, because it looks like coverage.

**c. It warns; it never blocks.** CLAUDE.md → "Shipping an instrument", rule 7: *a guard must
never block the action that resolves it.* The way to clear an `UNREVIEWED` report is to open it,
read the screenshots and write the review — so a gate that refuses until the review exists is
refusing the remedy. Exit is 0 even with findings; `--strict` is opt-in for a caller that wants
the gate.

**d. The backlog is separated from the finding.** 47 reports predate the convention. They are
listed only under `--all` and are explicitly *not* a finding — a check that opens with 47 red
lines on day one trains the reader to skip it, and the one real row is then invisible. Same
failure shape the `gate-check.sh` summary fix retired: a guard that fires correctly, into the
middle of a long report, every single time.

Output shape (real, from the field run):

```
Stamped (3):
  FAIL      docs/e2e/journey-03-cross-persona-2026-09-02.html
  WEAK      docs/ui-review/ui-improvement-2026-09-02.html
  FAIL      docs/ui-review/ui-review-full-2026-09-02.html
3 stamped · 0 unreviewed since 2026-09-02 · 47 predate the convention · 0 malformed
```

---

## 3. What "written the review" means — the bar the stamp certifies

The stamp is worthless if it can be applied without looking, so the skill has to say what looking
is. This part is not new material; it is the promotion of an existing project skill
(`journey-review.md`, already a toolkit candidate) and it should be cross-referenced, not
restated, if that skill promotes alongside this one.

The minimum a verdict certifies:

1. **Every screenshot in the bundle was opened at rendered size**, not thumbnailed, not inferred
   from the JSON. On the field run **six of the nine review questions could not be answered from
   the JSON at all** — layout, copy, duplication, role-appropriateness, legibility, and whether a
   pass could have failed. A review written from step notes is the old run with a new heading.
2. **Each question is answered explicitly.** "Nothing found" is a legal answer *after looking*;
   silence is not an answer. (Authoring rule 4 — completion criteria carry denominators.)
3. **Findings are written down with severities**, and an open P1 makes the verdict `FAIL`. The
   verdict must be derivable from the findings, so a reader can disagree with the severity rather
   than with a hidden judgement.
4. **The headline of the report is the review verdict, never the step count.** 23/23 steps green
   with four open P1s is a `FAIL` that says 23/23 at the top, and that is the single most
   effective way to mislead a stakeholder who will not scroll.
5. **The verdict on an earlier, partial report is not retroactively upgraded.** On the field run
   the partial UI report stayed stamped `WEAK` after a complete re-run produced a separate `FAIL`
   report the same day: *a later pass does not make an earlier pass's evidence complete.* Editing
   the old stamp to `FAIL` would have destroyed the record of what the partial run actually saw.

---

## 4. Corrections are made in place, not by deletion

Field evidence from the same day, and it belongs in the skill because it is the behaviour a
verdict system makes tempting to skip.

The first report published a diagnosis that was **wrong**: it said the measuring instrument was
"reporting a scrollHeight it is not really reading" — i.e. fabricating it. It was not. The
instrument read `document.documentElement.scrollHeight` correctly; the app simply does not scroll
the document (companion draft, §on scroll roots). The wrong diagnosis pointed at "the tool is
broken" and would have produced a rewrite of a tool that needed one selector changed.

The correction was added to the published report as a visible **"Correction, added after the
re-run"** paragraph, quoting the original wrong sentence, rather than by silently editing the
sentence away. Rule:

> **A published verdict or diagnosis that turns out wrong is corrected in place, with the
> original claim quoted.** A report whose history can be edited is not evidence, and the
> next reader has no way to know which of its claims have survived a challenge.

---

## 5. Wiring — or this proposal repeats the incident it describes

This is the part that matters most, because the whole finding is *"the rule existed and nothing
fired it"*. A promoted skill that is only routed in a table has the same failure mode.

| Wiring point | What it does | Status on the field project |
|---|---|---|
| `bin/review-verdict.sh` in the repo | anyone can ask the question at any time | **done**, run, output above |
| A row in `README.md` → "When to use which skill" | discoverable | proposed below |
| A rung inside `project-bin/verify-module.sh` | the module-close pass reports unreviewed reports alongside its other instruments | **not done** — proposed; `journey-review.md` §10 already asks for it |
| The producing skills' closing steps point here instead of re-deriving | `module-review.md`, `test-result-audit.md`, `e2e-evidence-report.md`, `finding-disposition.md` | not done — triage's call |

Note the honest gap: **rung 3 is the one that would have caught the original incident**, and it is
the one not yet built. Everything above it still relies on a session choosing to run the audit.
Filed as a hypothesis, not a finding: *a stamp-audit rung inside the module-close command is what
turns this from a tool into a trigger.* It has not been proven on a field run, because it does not
exist yet.

---

## 6. Field run, cited (field-proof rule 4)

Run on 2026-09-02 against a Mendix workflow-and-agents POC project, ~50 pages, 3 personas:

- `bin/review-verdict.sh` swept 50 HTML reports under `docs/`, reported 3 stamped / 0 unreviewed
  since the convention date / 47 backlog / 0 malformed. Verified by hand against the three
  stamped files.
- The stamp emitter was hardened during the run: its original form assumed every report carried
  `<meta charset="utf-8">` and silently emitted nothing for reports that did not. Three branches
  now — replace an existing stamp, insert after the charset meta, or prepend. **This is the
  measurement-instrument defect class again**: a writer that no-ops on unanticipated input reports
  success and produces nothing.
- The judged review the stamp certifies was then actually performed over 12 full-height captures
  across 10 distinct pages and 3 personas, producing 4 open P1s and ~20 P2s over an app whose
  every prior automated check was green. Verdict: `FAIL`.

What it found that the unstamped regime could not: **two reports about the same app, written the
same day, disagreeing** — and no mechanism for a reader to know which had been judged and which
had merely been generated.

---

## 7. What this does NOT do

- It does not judge. It records whether a judgement happened and what it concluded.
- It does not replace `finding-disposition.md` (what happens to findings), `test-result-audit.md`
  (was the testing itself complete), or `module-review.md` stage 4 (the LOOK). It sits one layer
  earlier than all three and is the thing they each assume.
- It does not gate. See §2c.
- It does not define the review questions — that is `journey-review.md`'s job if that skill
  promotes, and a project's own review skill otherwise. This skill only requires that the
  questions exist, are answered, and produce a verdict a stamp can carry.

---

## 8. Proposed routing row (paste into `README.md` → "When to use which skill")

Written as a trigger condition, front-loaded on the triggering word (authoring rule 1):

| Task | Read this file |
|---|---|
| Finishing any run that produces a report — before calling it reviewed, and any time you cannot say which reports have been judged: the verdict goes on the artifact as a stamp, `UNREVIEWED` is not green, and the audit warns without ever blocking the review that clears it | `skills/judged-review-verdict.md` |

## 9. Proposed CHANGELOG line

```
new(skills/bin): `judged-review-verdict.md` + `bin/review-verdict.sh` — the judged review's trigger
moves off the runner and onto the artifact: a `<meta name="review-verdict">` stamp on every report,
audited by a sweep that dates from filenames (mtime is rewritten by any checkout), separates the
pre-convention backlog from the finding, and warns without ever blocking the review that clears it.
Field evidence: 48 reports under `docs/` on a real project, 1 ever judged — not because the rule was
unknown but because it lived in prose and was wired into a single runner; two reports about the same
app, same day, disagreed with each other and nothing said which had been looked at
— a Mendix workflow-and-agents POC project
```
