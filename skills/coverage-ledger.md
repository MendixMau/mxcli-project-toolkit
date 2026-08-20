# Coverage-Ledger Method

**Status:** Skill / repeatable method. Produces a coverage ledger as part of the Stage 4 build plan.

**Applies to:** Every BRD-driven build whose plan carries `claims` (see `brd-to-build-plan.md` Step 5b). The ledger closes a gap in the build-plan format: **a requirement must either be claimed by a row or explicitly catalogued with a reason — requirements must never become invisible.**

**Fits into:** `conversion-runbook.md` Stage 4 (`✋`) — coverage check runs at gate time and blocks the gate until all three verdict-classes are clean.

**Consumes:** `architecture/build-plan.md` with the `claims` field (authored per `brd-to-build-plan.md` Step 5b) + the authoritative BRD JSON files.

**Feeds:** Stage 4 gate (chat output); Stage 5 build (rows referencing ledger entries for deferred/descoped work).

---

## Where the ledger lives

Three path shapes exist in real projects. All three are read by `project-bin/conformance-check.sh`
and `project-bin/coverage-preflight.sh`; the first is canonical.

| Path | When | Status |
|---|---|---|
| `architecture/modules/<Module>/coverage-ledger.md` | multi-module project | **canonical** |
| `architecture/modules/<Module>-coverage-ledger.md` | project whose `architecture/modules/` is flat | accepted |
| `architecture/coverage-ledger.md` | single-BRD project | accepted |

The per-module directory is canonical because it is the shape both instruments already name, it
scales (the directory holds the module's brief, ledger and notes together), and changing canon
would invalidate every ledger already written to it.

The flat shape is read because it is what projects actually have: VB-USI's `architecture/modules/`
contains `Approval-brief.md`, `ProductNumbers.md`, `Common-brief.md` and no subdirectories at all.
An instrument that globs only the canonical shape tells such a project it has no ledger even when
it has one. **When no ledger is found, the instruments print all three paths they tried** — a
"not found" that does not name what it looked for is not actionable.

---

## The four fallback levels — what an instrument does when there is no ledger

A missing `coverage-ledger.md` used to be one hard FAULT covering two opposite situations: a
Track B existing-app audit that was never going to have one (permanent, meaningless noise), and a
migration project that should have one and doesn't (a real gap with a real remedy). The verdict is
now graded on **what is present**, never on a declared entry mode — a project onboarded as
Migration can be running a Track B assurance pass the same day, and VB-USI is doing exactly that.

| Level | Condition | What happens | rc |
|---|---|---|---|
| **1 · MEASURED** | ledger found | run the engine; verdicts exactly as before | engine's own (0/1) |
| **2 · DERIVED** | no ledger, but BRDs + build-plan `claims` | join those two into a ledger written to `docs/coverage/derived-ledger[-<Module>].md`, **labelled DERIVED**, then measure against it | engine's own (0/1) |
| **3 · NOT MEASURED** | BRDs present, no `claims` anywhere in the plan | report the honest denominator — "N requirement leaves across M BRDs; 0 traceable to a build-plan row" — and name the remedy | 3 |
| **4 · NOT APPLICABLE** | no BRD at all | say so, with the reason: no pipeline produced a spec for this module | 4 |

**Nothing blocks.** No level adds a gate and no exit code got more severe than it was: levels 2–4
are all strictly less severe than the FAULT (rc 2) they replaced. Every level states what it
knows, what it does not, and what would upgrade it. Louder and clearer, never stricter.

**rc 3 is "NOTHING EXAMINED", not "clean".** Same contract as `bin/open-questions.sh` rc 3 and
`bin/questions-report.sh`, which refuses to render a clean-looking zero over an empty directory.
An instrument that examined nothing must not exit 0, because 0 reads as green everywhere it is
consumed.

### Level 2 is a join, not an invention

Deriving is legitimate because this skill already defines the ledger as *generated from the BRD
and the build plan's `claims` field*, and lists exactly those two under **Consumes**. Level 2 does
that join mechanically instead of by hand. It is still not a decided artifact: the derived file
lands in `docs/coverage/`, **never** in `architecture/`, so the next run cannot read its own output
back as level 1, and it carries a header saying nobody signed it off. A derived ledger has no
NON-BUILDABLE table, so a leaf that was deliberately deferred or descoped shows as UNCLAIMED —
reviewing the derived file and committing it to the canonical path with reasons filled in is what
upgrades the project to level 1.

Note for `conformance-check.sh` specifically: a derived ledger carries no `acceptance` cells, and
conformance measures precisely those. So at level 2 conformance still reports NOT MEASURED (rc 3)
rather than inventing acceptance commands.

### The boundary that is never crossed

**Derive from the BRD and the build plan only. Never reverse-derive a requirement from the live
model or from shipped code.** A ledger records what was *decided*; a ledger reconstructed from what
happens to exist inverts that meaning and turns every bug into a requirement. This is
`process/improvement-plan-e2e-reporting.md` Finding 3 option 2, considered and rejected, and
`skills/report-schema.md` says the same thing from the other end: a requirement pointer must never
be synthesized.

### Reading this on an existing-app audit

If you arrived here from `existing-app-assurance.md` — a Mendix app you already have, no pipeline,
no BRD, no stages — level 4 is your normal, permanent state, and it is not a defect. There is no
spec to trace the app back to because the app was never produced from one; it is audited against
itself. The instruments that carry real signal for that entry mode are the journeys, the wiring
sweep, and the LOOK stage, not coverage or conformance.

---

## The Failure This Method Prevents

**Date:** 2026-07-29 · **Project:** Order_List page, F001 domain

The BRD specified in `pages[0].buildComposition`:
- 7 gridColumns · 3 filterBar entries · actionBar with "New Order", "Refresh"
- rowClick "navigate to Order_Detail with orderId"
- footer "pagination controls"
- rightPanel "AI Assistant (read-only, always visible — BR-07)"

And in `pages[0].actions`:
- `ACT_Order_Search`, `ACT_Order_OpenDetail`

The build plan at node S4 said:
```
4 · f001-04-page-orderlist.mdl | page skeleton | filter bar · grid · footer | CLI, SP closed
```

**Six requirements silently disappeared:**
1. Action bar (New Order, Refresh buttons)
2. Row click → open Order_Detail with orderId
3. Pagination controls in footer
4. Mandatory AI panel (BR-07, right sidebar)
5. `ACT_Order_OpenDetail` microflow
6. Alternate flows (error banner, empty state)

**Nothing failed.** The `mxbuild` was clean. The page was built. It went unnoticed for days.

Three distinct defects caused this:

| Defect | How it happens | How the ledger fixes it |
|--------|-----------------|--------------------------|
| **Layout inventory, not behaviour** | "filter bar · grid · footer" is a *region inventory*, not a functional spec. A row click is not a region, so it has nowhere to live. | **`claims` field is mandatory and exhaustive.** Every BRD leaf must either be claimed by a row ID or appear in the ledger. |
| **No traceability back to source** | No row said which BRD fields it discharged. Loss was undetectable because there was nothing to check against. | **Mechanical coverage check** (§2): which BRD leaves are claimed by no row? Answer must be empty or fully ledgered. |
| **Format forced compression** | A table cell or Mermaid node punishes detail — acceptance criterion doesn't fit, so it's dropped. | **Block form, never table form** (stated in full below) — build-plan rows are prose blocks; tables are only indexes. Prose has room for what matters. |

---

## Method Overview

### Two-Table Format

The ledger is two tables, generated from the BRD and the build plan's `claims` field.

**Table 1: Claimed leaves**
- Leaf pointer (e.g., `/pages/0/buildComposition/rowClick`)
- Claiming row ID (e.g., `F001-UC001-L5.4`)
- Status (CLAIMED)

**Table 2: Unclaimable / deferred / descoped leaves**
- Leaf pointer
- Category (LEDGERED)
- Category type: `provenance` | `interpretation` | `metric` | `deferred(slice)` | `open-question` | `descoped(reason)`
- Explanation / reason

### Five Verdicts

After running the coverage check (`jq paths` on the BRD + grep on the build plan's `claims` field), every leaf gets one of:

| Verdict | Meaning | Gate |
|---------|---------|------|
| **CLAIMED** | Exactly one row claims it by a precise JSON pointer or a counted wildcard | ✓ OK |
| **LEDGERED** | Catalogued in Table 2 with a category and a reason | ✓ OK (if reason is valid) |
| **UNCLAIMED** | No row, no ledger entry | ✗ **GATE FAILS** — this is the original bug |
| **PHANTOM** | A row claims a path the BRD does not actually contain | ✗ **GATE FAILS** — stale claim after BRD edit |
| **DOUBLE-CLAIMED** | Two rows claim the same leaf | ✗ **GATE FAILS** — two owners is no owner |

### Ledger Categories (Non-Buildable)

Not every BRD leaf is a buildable requirement. The ledger categories are closed and each entry must justify itself:

| Category | Example | Why not a row |
|----------|---------|---------------|
| `provenance` | `/provenance/*`, `/sourceKB/*` | Metadata about where the BRD came from, not a app requirement. |
| `interpretation` | `/criticalFinding/*` (e.g., MBR-05 = "union of three coverage paths") | A reading of the corpus. It *shapes* rows; it is not one itself. Entry must name which rows it shaped. |
| `metric` | `/pages[0]/specFieldUniverse/total` (count: 85) | Measures the source universe. Not a target to build. |
| `deferred(slice-N)` | `/pages/2/*` (entire Order_Transaction page) | Real scope, scheduled for a later slice. Must name the slice. |
| `open-question` | `/openQuestions/*`, `/crossCuttingRequirements/5` (BR-08 WCAG, unresolved) | Blocked or undecided. Must appear in plan's pending-decisions count and some row's `blockedBy` field. |
| `descoped(reason)` | — | Explicitly removed. Must have `PROJECT.md` decision row with a named decider. |

A ledger entry with no reason is an unclaimed leaf with extra steps and fails the gate.

---

## Coverage Check Procedure

### Step 1: Enumerate BRD Leaves

```bash
BRD=analysis/<source>/knowledge-base/brd/F001-order-management.brd.json
jq -r '[paths(scalars)] | .[] | "/" + (map(tostring) | join("/"))' "$BRD" | sort -u > /tmp/leaves.txt
wc -l /tmp/leaves.txt  # e.g., "535 /tmp/leaves.txt"
```

`jq paths(scalars)` gives one pointer per scalar, including array elements. So each of the 7 `gridColumns`, each of the 3 `filterBar` entries, each `mainFlow` step is independently countable. This granularity is deliberate: the Order_List failure lost **elements of arrays**, and a coarser unit would not have caught it.

### Step 2: Extract Claims from Build Plan

```bash
grep -A20 '^claims:' architecture/build-plan.md | grep -oE '^\s+/[^ ]+' | tr -d ' ' | sort > /tmp/claims.txt
```

**Expansion rules:**
- A bare pointer claims exactly that leaf: `/pages/0/buildComposition/rowClick`
- `/a/b/* (N)` claims every leaf under that path AND **asserts the count is N**. If the BRD later gains an 8th grid column, the count mismatch fails the check. A wildcard without a count is rejected — an uncounted wildcard is a silent absorber of new requirements.
- Claiming a container (e.g., `/pages/0/buildComposition`) is rejected. Only leaves and counted wildcards.

### Step 3: Generate Verdicts

```bash
# UNCLAIMED — appears in BRD but no row claims it
comm -23 /tmp/leaves.txt /tmp/claims.txt > /tmp/unclaimed.txt

# PHANTOM — row claims a path the BRD does not have
comm -13 /tmp/leaves.txt /tmp/claims.txt > /tmp/phantom.txt

# DOUBLE-CLAIMED — two rows claim the same leaf
sort /tmp/claims.txt | uniq -d > /tmp/double.txt
```

### Step 4: Run the Gate

1. `UNCLAIMED` must be empty or fully ledgered (every entry in `unclaimed.txt` appears in Table 2 with a valid category).
2. `PHANTOM` must be empty (stale claims after BRD edits).
3. `DOUBLE-CLAIMED` must be empty (ambiguous ownership).

If all three are empty, coverage is clean. If unclaimed leaves exist but are all ledgered, coverage is clean (ledgered items are accounted for). Otherwise, **gate FAILS**.

---

## When the Ledger Is Regenerated

The ledger exists for the **life of the build plan**, not just at Stage 4:

- **At Stage 4 gate** (first time, before signing off): Full check. All verdicts must be clean.
- **After any BRD flush** (from a Stage-3 architecture decision that landed in the BRD): Re-run the check. A stale claim becomes PHANTOM and fails the gate — this is the primary defence against drift.
- **Before each slice build starts** (Stage 5): Re-run the check. New deferred entries may have been added to the ledger as a slice boundary moved.

No `mxcli` involvement at any point. The check reads two plain files (BRD JSON, build plan Markdown) and does text/JSON processing.

---

## Example: Order_List with All Six Lost Requirements Recovered

**BRD leaves that fell through the old format:**

| # | Requirement | BRD Leaf | Now Claimed By |
|---|-------------|----------|---|
| L1 | Action bar buttons | `/pages/0/buildComposition/actionBar/*` (2) | `F001-UC001-L5.3` |
| L2 | Row click navigation | `/pages/0/buildComposition/rowClick` | `F001-UC001-L5.4` |
| L3 | Footer pagination | `/pages/0/buildComposition/footer` | `F001-UC001-L5.5` |
| L4 | AI panel (BR-07) | `/pages/0/buildComposition/rightPanel` + `/crossCuttingRequirements/4/*` | `F001-XC-L5.1` (snippet) + `F001-UC001-L5.6` (wiring) |
| L5 | `ACT_Order_OpenDetail` | `/pages/0/actions/1`, `/microflows/1/*` | `F001-UC002-L3.1` |
| L6 | Alternate flows | `/useCases/0/alternateFlows/0`, `/1` | `F001-UC001-L5.7` |

**In the ledger format:**

- 7 gridColumns `/pages/0/buildComposition/gridColumns/* (7)` → claimed by `F001-UC001-L5.1` ✓
- 3 filterBar `/pages/0/buildComposition/filterBar/* (3)` → claimed by `F001-UC001-L5.2` ✓
- 2 actionBar `/pages/0/buildComposition/actionBar/* (2)` → claimed by `F001-UC001-L5.3` ✓
- rowClick `/pages/0/buildComposition/rowClick` → claimed by `F001-UC001-L5.4` ✓
- footer `/pages/0/buildComposition/footer` → claimed by `F001-UC001-L5.5` ✓
- rightPanel `/pages/0/buildComposition/rightPanel` → claimed by `F001-UC001-L5.6` ✓

None are unclaimed, none are double-claimed. Coverage is clean.

---

## Integration with Stage 4 Gate

Add to the Stage 4 (`✋`) checklist in `conversion-runbook.md`:

- [ ] Coverage check run (procedure above). UNCLAIMED, PHANTOM, DOUBLE-CLAIMED all empty. Leaf counts pasted in chat.
- [ ] Every ledger entry has a category and a reason; every `open-question` entry appears in pending-decisions and some row's `blockedBy`.
- [ ] Every CONFIRMED decision from Stages 0–3 maps to a build-plan row id or a ledger `descoped` entry.

The gate output is pasted in chat, like `gate-check.sh` — user signs off on the coverage verdict alongside the plan approval.

---

## Two build-plan conventions this method depends on

These were cited for months as `build-plan-method.md` §3 and §6. **That file does not exist and
never did** — `git log --all --diff-filter=A -- '*build-plan-method*'` returns nothing on any ref.
The `claims` field found a real home in `brd-to-build-plan.md` Step 5b; these two did not, so they
are stated here, in the skill that consumes them, rather than left pointing at a phantom.

**1. Block form, never table form.** A build-plan row is a prose block, not a table cell or a
Mermaid node. Tables are indexes only. The reason is mechanical: a cell punishes detail, so the
acceptance criterion is the first thing dropped when it does not fit, and a dropped acceptance
criterion is how the Order_List failure above stayed invisible. `claims:` blocks (Step 5b) assume
this form — they are lines under a row, which a table cell cannot hold.

**2. The `acceptance` field.** Every buildable row carries one, and it is what makes the row
checkable rather than merely claimed:

> **`acceptance`** — one line stating the observable fact that makes the row done. Where the fact
> is machine-checkable, write it as a backticked, runnable `SHOW …` / `DESCRIBE …` command against
> the model, e.g. `` `DESCRIBE PAGE Orders.Order_List` ``. Where it is not, write the prose test a
> human applies. Never a restatement of the row's title.

`project-bin/conformance-check.sh` reads exactly this: it re-runs the backticked command from the
ledger's `acceptance` column against the live `.mpr` and compares the result with the stored
`status` (OK / STALE / UNDERSTATED). Rows whose acceptance cell is prose are counted, not run —
that is the `prose-only` number in its output. An ellipsis or an operand-less fragment
(`` `DESCRIBE PAGE …Route_List` ``) is classified UNRUNNABLE rather than executed. So: a runnable
acceptance cell is the difference between a ledger that is measured and one that is merely stored.

---

## Known Limits

- **Coverage proves accounting, not correctness.** A row can claim `/rightPanel` and build the wrong panel. The `acceptance` field (specified above) defends against that.
- **The BRD is assumed complete.** A requirement absent from the BRD is invisible here. Stage 1–2 addresses BRD completeness.
- **Leaf granularity is `jq`'s.** A single long prose leaf bundling seven concepts is one claimable unit. Mitigation: when a row's description is materially longer than the leaf it claims, consider splitting the row or asking `ba-agent` to split the leaf.
- **The script exists — use it.** `bin/coverage-check.sh` (shared toolkit) is the measurement
  **engine**: it implements the procedure above and parses **this** ledger format, given a BRD and a
  ledger. The hand-run commands are kept here so you can see what it measures and reproduce a
  verdict without it. `project-bin/coverage-preflight.sh` is the **front-end** that decides what can be
  measured at all — it resolves the three ledger path shapes, grades a missing ledger into the four
  levels above, and calls the engine at levels 1 and 2. Run the front-end; it delegates.
  A missing ledger or BRD is still never read as a pass — but it is no longer a single
  undifferentiated FAULT either, because "this project skipped a step" and "this entry mode never
  had the step" are opposite facts that were printing the same sentence.
