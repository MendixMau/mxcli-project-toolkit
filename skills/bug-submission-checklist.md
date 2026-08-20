# Bug Submission Checklist — From "Found It" to "Filed It" Without Lying by Omission

**Applies to:** any mxcli defect (or similar CLI-vs-modeler-tool defect) moving from a bug-log entry
toward `gh issue create`. Written after filing 17 issues (mendixlabs/mxcli #827–843) across two
projects surfaced concrete, repeatable ways this process was getting it wrong — bundling two defects
into one, crediting the wrong fix commit, and asserting severity from a tool's own read-back instead
of ground truth.

**Prerequisites — read these first, this file assumes them:**
- [[tool-output-is-not-ground-truth]] — why a tool's own report of its work (describe, exit code,
  a passing gate) is not evidence, in either direction.
- [[sandbox-ab-tool-defect-probe]] — how to prove a defect is binary/version-specific without
  risking the real model.

This file is the layer on top: once you have a defect, what has to be true before it goes upstream.

---

## The three failure modes this exists to stop

1. **Bundling.** Two defects with different root causes and different fixes get described as one
   finding because they share a repro script. A reader (or a maintainer) fixes one half and closes
   the issue with the other half still broken.
2. **Bad attribution.** "Already fixed upstream, see commit X" gets copied from a bug log's prose
   summary of a fix, without reading the diff. X turns out to be an adjacent, same-day commit that
   doesn't touch the relevant code at all.
3. **Unverified severity.** "Silent data loss" gets asserted from a CLI's own `describe`/read-back
   output, which is exactly the layer least entitled to be trusted about whether something was
   *written*, as opposed to merely *reported*.

Each has a real, dated instance below. This is not a generic PR checklist — every gate exists
because skipping it already produced a wrong filed artifact or a two-week misdiagnosis.

---

## Gate 0 — Pin the scope before you do anything else

Write down, before drafting anything:

- Exact mxcli binary commit (`./mxcli --version` and, if built from source,
  `git -C <repo> rev-parse --short HEAD`) for **every** binary the repro was run against.
- Exact Mendix Studio Pro / mxbuild (`mx`) version used as the gate.
- Whether this was tested on both forks (RnD/upstream and a downstream fork) or only one.

**Why:** a "resolved" verdict is resolved against a specific binary, not against mxcli in general.
BUG-WF04 (2026-08-03) verified `CALL MICROFLOW` clean against RnD `504aec67` and a downstream fork's
`26f2866` and closed the question — but those binaries post-date four fixes that landed 2026-07-29.
Projects still on the **tagged v0.16.0 release** (which `gh release list` shows as **Latest**, not
the nightly) hit the exact same defect a day later on a real project (BUG-WF05). The "resolved"
verdict never claimed to cover v0.16.0; it was read as if it did. State the binary explicitly every
time, including in the issue title's Environment section — never write "fixed" without naming what
it's fixed *relative to*.

---

## Gate 1 — Classify: read-back bug, or write-path data loss? (BSON is the only oracle)

**Never conclude "data was lost" from `mxcli describe`, `SHOW`, or any CLI read-back command
alone.** Those code paths can be wrong independently of what was actually written — that is a
distinct bug from the one you're trying to characterize, and conflating them mis-states severity.

### Protocol

1. Run `exec`, then run the CLI's own read-back (`describe`, `SHOW X`) and note what it claims is
   missing.
2. Independently open the raw stored bytes — `mprcontents/*.mxunit` BSON, via `strings -n 4` or a
   proper BSON decode — and look for the property at its **actual** field path, not the field the
   reader function happens to check. Read-back bugs are frequently "looked in the wrong field":
   `extractDataGrid2DataSource` read `ds["Microflow"]` when the real path was
   `ds["MicroflowSettings"]["Microflow"]` (issue #839).
3. If the raw BSON has the correct value: **read-back bug.** Severity is bounded — the built app
   runs correctly, only tooling built on `describe` is misled. Say so explicitly in the draft (see
   #839's title: "read-back bug, not data loss").
4. If a full-project BSON grep shows **nothing** references the value anywhere (not just "the
   describe function didn't print it," but genuinely absent from the model): **write-path data
   loss.** This is the high-severity case — flag it as silent runtime impact.
5. If a single repro produces **both** kinds of gap in different fields (this happens — see below),
   classify each field independently. Don't let the presence of one confirmed write-path loss
   contaminate the severity claim for an adjacent field that turns out to be read-back-only, or vice
   versa.

### Evidence this gate exists

- **Datagrid microflow datasource:** a bakeoff entry asserted "silently dropped on write, not just
  hidden from read-back" but flagged its own uncertainty ("this pass didn't independently BSON-probe
  the target's output to distinguish the two"). A retest did the BSON probe and found the opposite:
  `DataSource.MicroflowSettings.Microflow` was present and correct in the stored BSON the whole
  time. Filed as #839 with the corrected, narrower claim.
- **REST client operation `Query:` + `Response: mapping`:** the original bakeoff note recorded one
  undifferentiated symptom ("everything except Method/Path/Timeout was dropped on write"). A retest
  BSON-inspected the same operation and found it was **two different bugs**: `QueryParameters` was
  correctly stored (read-back-only, same class as #839), but `ResponseHandling` was genuinely stored
  as `Rest$NoResponseHandling` — confirmed by a full-project BSON scan showing nothing references the
  import mapping unit except its own definition. One half is cosmetic, one half is real. Filed as
  #843 with both halves disambiguated in the same body (see Gate 3 on whether that should have been
  two issues instead of one).

---

## Gate 2 — Before trusting any pass/fail verdict, prove the gate can fail for this defect

Before an A/B result ("binary A fails, binary B passes") is allowed to settle anything, confirm the
grading gate is actually sensitive to the defect class you're testing. Run one deliberately-broken
artifact through it as a negative control. If the gate reports it clean, the gate is blind and your
A/B result is unscored, not confirmed.

**Evidence:** a six-variant probe of `CALL MICROFLOW WITH`-clause forms graded every arm with
`mx check` alone. `mx check` does not validate the workflow activity's on-disk `$Type` — it returned
`0 errors` on **all six arms**, including all six that were actually broken (pre-11.9
`Workflows$CallMicroflowTask` instead of `Workflows$CallMicroflowActivity`, red pin in Studio Pro,
app would not boot). The conclusion "syntax X is safe" was confirmed by a gate that had never once
gone red on the defect in question (BUG-WF06, which cost roughly a day and superseded the wrong
attribution recorded in BUG-24). The cheapest gate that actually caught it was opening the workflow
in Studio Pro and looking at the activity icons — not a CLI check at all.

Keep a gate-sensitivity table for the constructs you work with (mxcli's is in
[[tool-output-is-not-ground-truth]] Part 3) and consult it before picking an oracle.

---

## Gate 3 — Split or merge? Default to splitting when the fixes don't share an owner

Ask: **do the sub-findings need different code changes in different places?** If yes, lean toward
filing separately, even if they share one repro script and were discovered in the same sitting.

- **Good precedent (split):** BUG-24's original repro ("red pin + runtime crash on `CALL
  MICROFLOW`") turned out to be two independent defects hit by the same trigger: a null
  `ParameterId` from a fully-qualified `WITH` key (fixed by commit `2099bbe1`) and a pre-11.9
  `$Type` storage name (fixed by an unrelated commit, `253d60d8`). These were drafted as **two
  separate reports** precisely because fixing one leaves the other fully in place — a maintainer who
  fixes the `WITH`-key bug and closes "the" issue would still ship red pins.
- **Cautionary counter-example (not split, arguably should have been):** the `Query:` (read-back
  layer, `describe` fix only) and `Response: mapping` (writer fix, a different function entirely)
  findings were disclosed clearly within one body but filed as a **single** issue (#843). The draft
  says outright: "the fix has two independent parts... (1) the describe/read-back layer... (2) the
  operation-writer statement handler..." — that sentence is itself the signal it should have been
  two issues. Treat this as the pattern to catch next time: if you find yourself writing "the fix has
  two independent parts," stop and reconsider before filing as one.

**Rule of thumb:** same trigger + same fix location = one issue. Same trigger + different fix
location = two issues, cross-referenced in both bodies ("independent of the WITH-key defect
described in issue N, which affects the parameter mapping, not the activity type").

---

## Gate 4 — "Already fixed upstream" claims require reading the diff, not the commit message

A bug log's prose description of what a commit fixes is a claim, not evidence. Before writing
"already fixed by commit X" in a draft:

1. `git show <X>` — read the actual diff. Does it touch the file/function relevant to *this*
   symptom, or does it just land in the same area on the same day?
2. `git merge-base --is-ancestor <X> <tested-binary-commit>` — confirm the fix commit is actually an
   ancestor of the binary you're crediting with the fix. A binary from *before* X should still
   reproduce the bug; if it doesn't, your attribution or your repro is wrong.
3. Where feasible, apply the diff to a scratch clone, rebuild, and re-run the repro yourself rather
   than trusting the commit message's own description of what it fixes.

**Evidence this gate exists — the bad attribution, corrected:**
A draft originally credited `253d60d8` for fixing the fully-qualified `WITH`-key null-`ParameterId`
defect. Reading `253d60d8`'s diff directly showed it **only version-gates the workflow `$Type`
storage name** (a completely different bug, see Gate 3) and touches no `WITH`-key or
parameter-mapping code at all. The two commits landed the same day, nine minutes apart (`253d60d8`
then `2099bbe1`) — close enough in the log to be mistaken for one change. The actual fix is
`2099bbe1`. The correction is recorded as a dated banner in the draft itself (see Gate 7), not a
silent edit of the original claim.

**Evidence this gate pays off when done right:** one fix wasn't just cited — it was independently
re-verified: "applied cleanly to a scratch clone, rebuilt, and confirmed the root occurrence flips
from `0..0` to `1..1` with no regression." That's the standard to hold "fix exists" claims to before
writing "submission-ready: yes."

---

## Gate 5 — Severity comes from what Gates 1–2 established, not from the tool's framing or a prior document's assertion

Severity must trace to verified evidence, and must be pinned to the specific version/binary from
Gate 0 — the same defect can be a different severity on different Mendix versions.

**Evidence:** on Mendix 11.12.1, an invalid `CALL MICROFLOW` parameter binding was **silent** — both
checkers passed, the app loaded, and only the runtime binding was wrong (BUG-WF02). The identical
MDL construct on Mendix 11.13 makes the **entire MPR unloadable** at `mx check` time (BUG-WF05) —
11.13's stricter BSON loader turned a latent defect into a hard blocker. A severity note written
against one Mendix version and copied forward to describe "the bug" in general would be wrong in
one direction or the other. State the Mendix version the severity claim applies to, explicitly.

Do not let a prior "submission-ready: no" become permanent caution creep, and do not let a prior
"submission-ready: yes" survive unexamined either — both must be re-earned against Gates 1–4 at
draft time. A bakeoff pass correctly marked 10 of 14 entries "No — root cause undiagnosed"; only
re-diagnosis (not time passing) is what moved two of them to submission-ready days later.

---

## Gate 6 — What a submission-ready draft must contain

A draft is not ready to file until every one of these is present. This is the format that has
actually been filed and accepted (verified by reading back the live issue body via
`gh issue view 839/843 --repo mendixlabs/mxcli`):

- [ ] **Local tracking header** (kept in the `.md` file, **stripped before filing** — confirmed the
  filed issue body starts at "Environment:", not at "Repo:"/"Status:"): `Repo`, `Source` (which
  bug-log entry / bakeoff file this came from, with a relative link), `Status` (unfiled / `FILED —
  <url>` / feature request / docs-only), and a one-line `Note` carrying anything a filer must not
  forget (e.g. "doubles as a please-ship-a-release nudge," "bundles two defects, see Gate 3").
- [ ] **Title** — states the symptom and, if known, the mechanism (`"read-back bug, not data
  loss"`, `"— confirmed on both RnD and a downstream fork"`) rather than a bare error code.
- [ ] **Environment** — every binary/commit tested (Gate 0), Mendix Studio Pro version, OS.
- [ ] **Steps to reproduce** — a complete, minimal, runnable MDL script plus the exact commands
  (`mxcli check`, `mxcli exec`, `mx check`/`docker check`) and their literal output.
- [ ] **Expected vs. Actual**, stated separately, not folded into one paragraph.
- [ ] **Root cause**, when diagnosed — name the actual function/field
  (`extractDataGrid2DataSource`, `ds["MicroflowSettings"]["Microflow"]`,
  `resolveMemberChangeGenStandalone`), not just "a parsing issue."
- [ ] **Fix evidence**, when claiming already-fixed — exact commit hash, what the diff actually
  does (Gate 4), and whether it was independently rebuilt/re-verified or only read.
- [ ] **Severity**, explicitly scoped to the Mendix version/binary it was verified against (Gate 5),
  and explicitly separated if the finding has more than one part (Gate 3).
- [ ] **A trigger-boundary table**, where the investigation produced one (e.g. a four-variant
  `WITH`-key table) — a table of "which exact forms did/didn't fail" is stronger evidence than prose
  and lets a maintainer verify your claim in one read.

---

## Gate 7 — Corrections annotate history; they never silently overwrite it

When re-testing turns up that a previous bug-log entry, draft, or filed issue was wrong — wrong
attribution, wrong root cause, wrong severity, or an outright misdiagnosis — the fix is a **dated
banner added at the top of the original entry**, not an edit that erases the original text.

The banner must state, in this order: (1) that it's a correction and what specifically was wrong,
(2) a pointer to the corrected/superseding entry, (3) *how* the wrong conclusion was reached — the
methodology gap, not just the fact — so the next investigator doesn't repeat the same mistake for a
different construct. Leave the original text below the banner intact.

**Precedent — the pattern this rule is copied from, verbatim:**

```
> ### ⚠️ MISDIAGNOSED — see BUG-WF06 (2026-08-05)
>
> **The red pin and the runtime `Class 'Workflows$CallMicroflowTask' could not be found` have
> nothing to do with the `WITH` clause.** ... Reproduced 2026-08-05 with correct short `WITH` keys,
> with fully-qualified keys, and with no `WITH` at all: red pin in every case.
```
— BUG-24, in `bug-logs/mxcli-bugs.md`. BUG-WF05 itself later needed a second, narrower banner
("this entry is right, but incomplete, and its workaround is not sufficient") when its own corrected
conclusion ("use a short `WITH` key") turned out to leave BUG-WF06 fully in place. Two banners
stacked on the same defect chain, each dated, each explaining what the previous correction still got
wrong — that chain is itself the audit trail, and is more valuable than a "fixed" state that hides
how many times it was wrong first.

The same convention applies to a filed GitHub issue discovered to be wrong after filing: add a
comment with the same three-part structure, don't edit the original issue body.

---

## Gate 8 — Filing mechanics

1. `gh issue create --repo mendixlabs/mxcli --title "<title>" --body-file <path>` — the body file is
   **only** the Title/Body content from Gate 6, with the local tracking header stripped (confirmed
   against live filed issues — `gh issue view <n>` shows the body starts at Environment/Summary, not
   at Repo/Status/Note).
2. Immediately after filing, update the local draft's `Status:` line to
   `FILED — <issue url> (<date>)`, and update any bug-log entry that cross-references it.
3. If the draft doubles as something other than a plain bug report (a "please cut a release" nudge,
   a feature request, a docs-only fix), say so in the `Note:` line before filing, and keep that
   framing in the issue title/body — see BUG-28 (filed explicitly as a feature request, not a
   check/exec disagreement) and BUG-45 (filed as "please ship MDL048," not a fresh defect).
4. Do not file a bug for a defect whose "submission-ready" status is still "no" per Gate 5 — file a
   bug-log entry, not a GitHub issue, until Gates 1–4 are satisfied. BUG-WF05 (fully-qualified
   `WITH`-key doubling) and BUG-WF06 (pre-11.9 `$Type` storage name) followed exactly this path:
   diagnosed and split (Gate 3), then filed once ready as
   [mxcli#844](https://github.com/mendixlabs/mxcli/issues/844) and
   [mxcli#846](https://github.com/mendixlabs/mxcli/issues/846) respectively (2026-08-05), alongside
   the DECISION-casing defect from the same investigation as
   [mxcli#845](https://github.com/mendixlabs/mxcli/issues/845). The gap between "diagnosed" and
   "filed" is a queued task, not a process failure — keep it visible on the project's resume
   document until closed.

---

## Quick-reference: the eight gates

| Gate | One-line check | Fails silently as |
|---|---|---|
| 0. Scope | Named every binary commit + Mendix version tested | A fix "confirmed" on one binary silently assumed to cover all |
| 1. Read-back vs write-path | BSON-verified, not `describe`-verified | Cosmetic bug reported as data loss, or vice versa |
| 2. Gate sensitivity | Ran a known-broken negative control through the same gate | A blind gate laundering a real defect as "passing" |
| 3. Split vs merge | Different fix location ⇒ different issue | One fix lands, the other half stays open under a closed issue |
| 4. Commit attribution | Read the diff, checked ancestry, ideally rebuilt it | Crediting an adjacent same-day commit that does something else |
| 5. Severity | Traced to Gates 1–2, pinned to a Mendix version | A version-specific "silent" bug asserted as universally silent |
| 6. Draft completeness | Every checklist item present before filing | A maintainer can't reproduce or verify the claim |
| 7. Corrections | Dated banner, original text preserved | History gets silently rewritten; the same mistake recurs unlogged |
