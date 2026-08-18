# Coverage-Ledger Method

**Status:** Skill / repeatable method. Produces a coverage ledger as part of the Stage 4 build plan —
`architecture/coverage-ledger.md` for a single-BRD project, or one per module at
`architecture/modules/<Module>/coverage-ledger.md`, which is where `bin/verify-module.sh` looks.

**Applies to:** Every BRD-driven build after `build-plan-method.md` is adopted. The ledger closes a gap in the build-plan format: **a requirement must either be claimed by a row or explicitly catalogued with a reason — requirements must never become invisible.**

**Fits into:** `conversion-runbook.md` Stage 4 (`✋`) — coverage check runs at gate time and blocks the gate until all three verdict-classes are clean.

**Consumes:** `architecture/build-plan.md` with `claims` field (per `build-plan-method.md`) + the authoritative BRD JSON files.

**Feeds:** Stage 4 gate (chat output); Stage 5 build (rows referencing ledger entries for deferred/descoped work).

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
| **Format forced compression** | A table cell or Mermaid node punishes detail — acceptance criterion doesn't fit, so it's dropped. | **Block form, never table form.** See `build-plan-method.md` §3 — rows are prose blocks; tables are only indexes. Prose has room for what matters. |

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

## Known Limits

- **Coverage proves accounting, not correctness.** A row can claim `/rightPanel` and build the wrong panel. The `acceptance` field (per `build-plan-method.md` §6) defends against that.
- **The BRD is assumed complete.** A requirement absent from the BRD is invisible here. Stage 1–2 addresses BRD completeness.
- **Leaf granularity is `jq`'s.** A single long prose leaf bundling seven concepts is one claimable unit. Mitigation: when a row's description is materially longer than the leaf it claims, consider splitting the row or asking `ba-agent` to split the leaf.
- **The script exists — use it.** `bin/coverage-check.sh` (shared toolkit) implements the procedure
  above and parses **this** ledger format; the hand-run commands are kept here so you can see what it
  measures and reproduce a verdict without it. `bin/verify-module.sh` calls it as
  `bin/coverage-check.sh --summary <brd.json> <coverage-ledger.md>` and treats a **missing ledger or
  missing BRD as a FAULT, not a pass** — "no requirements to check against" is precisely how projects
  shipped with no ledger at all and read that absence as silence.
