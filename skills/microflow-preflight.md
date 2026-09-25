# Microflow Pre-flight — Loops, Size and Layout Before the First MDL Line
**Applies to:** any mxcli project.

**Purpose:** Decide a microflow's shape — what runs inside each loop, how many activities it
really has, whether it carries layout annotations — before drafting it. Lint only sees the
result after `exec`, and it cannot see inside a loop. Measured on **mxcli v0.24.0**
(released 2026-09-24) on a scratch copy of a real model. Older binaries lay out differently;
the advice is the same.

---

## Trigger — run this if ANY of these hold for the microflow you are about to write

1. It has **any loop** (`loop … in`, or `while`).
2. A **retrieve, commit, delete, REST call, Java action or sub-microflow call** is planned inside a loop.
3. It has **more than one loop**, or a **nested loop**.
4. Planned total is **more than 20 activities, counting loop bodies**. Why 20: CONV009 (15)
   and QUAL003 (25) read the catalog's top-level `ActivityCount` only. A microflow with 20
   activities inside one loop plus 2 outside counts as **3** and fires neither. This
   preflight counts what lint cannot, and stops at 20 because drafts grow before they shrink.
5. It **builds a list from a list** (create list + `add` in a loop).
6. It **retrieves and commits the same entity** in one flow.

None applies → post `microflow-preflight: no trigger` in chat and proceed.

## The checklist — post it in chat before the first MDL line

```
microflow-preflight: <Module.Microflow>
- Loops: N. Per loop: retrieve y/n · commit/delete y/n · call y/n · batch strategy · expected list size
- Retrieves inside loops: 0 (else: moved before the loop, find/filter inside)
- Commits/deletes inside loops: 0 — collected into <Entity>_CommitList, one commit after the loop
- REST/Java/web-service calls inside loops: 0, or the batch endpoint / task queue named
- Nested loops: N — each replaced by find/filter, or justified in one line
- Lists built from lists: N — each a list operation, not loop + add
- Activities: top-level T + all loop bodies B = T+B (≤ 20, else the SUB_ split named)
- Top-level activities: T (≤ 15, else SUB_ flows named)
- Decisions + loops: D (≤ 9, else guard chain moved to a VAL_)
- Layout: no @position   (or: every canvas statement annotated, and why)
```

## Best practice → what catches it → how to write it first time

| Practice (Mendix docs) | Caught after the fact by | Write it so |
|---|---|---|
| No commit inside a loop | **CONV011** NoCommitInLoop. Delete in a loop: **no lint rule — preflight is the only check** | `$Order_CommitList = create list of Sales.Order;` · in the loop `add $Order to $Order_CommitList;` · after it `commit $Order_CommitList;`. If every item changed, `commit $Orders;` after the loop |
| Commit late, events on purpose | `mxcli check` **MDL067** (info): a bare `commit` is WITH EVENTS, so a commit in a loop fires every handler once per item | One commit at the end; write `without events` only when you mean it |
| No database retrieve inside a loop | **no lint rule — preflight is the only check** | Retrieve once before the loop; inside, `$Match = find($List, Name = $Item/Name);` |
| No REST / Java / web-service call per iteration | **no lint rule — preflight is the only check** (CONV013 checks error handling on the call, not where it sits) | Batch endpoint, or a task queue where the loop only enqueues. No `on error` inside a loop body — CE0644, see `learned-microflow-patterns.md` |
| Bounded lists | **no lint rule — preflight is the only check** (`mxcli check` MDL068 catches only an unbounded `range`) | `retrieve … sort by … limit 1000 offset $Offset;`, one batch per iteration or per `SUB_…_Batch` call |
| Nested loop used as a lookup | `mxcli check` **MDL001** nested-loop warning (before exec). After exec: none. Each loop adds 1 to QUAL001 | Replace the inner loop with `find`/`filter`; a genuine N×M aggregation stays, with an annotation |
| List built from a list | **no lint rule — preflight is the only check** | `filter`, `sort`, `range`, `union`, `subtract` list operations |
| At most 25 elements per microflow | **CONV009** at 15 (info), **QUAL003** at 25 (warning), both top-level only | Split by responsibility: `ACT_` = UI + calls, `VAL_` returns Boolean, `SUB_` persists |
| Keep decision logic simple | **QUAL001** McCabe > 10 (1 + decisions + loops) | Move a guard chain into a `VAL_` |

Counting in an expression uses `length($List)`, never `count()` (`learned-mdl-preflight.md` STOP row 10).

## Layout — omit `@position` entirely

Upstream now states the toolkit's rule. `mxcli syntax microflow.layout` on v0.24.0 says:
*"Prefer no @position at all to a few: hand-placed statements are not measured against what
the builder puts around them."* A statement with `@position` is never moved. Every statement
without one is placed by the builder, which does not look at your hand-placed coordinates.

**The failure. Every one of these partial-annotation probes raised a lint finding on v0.24.0:**

| Probe | What was hand-written | Result |
|---|---|---|
| Only the loop annotated | `@position(970, 200)` on the loop, nothing else | **MPR008**: an auto-placed neighbour lands on the loop |
| Hand spacing | activities 100 px apart | **MPR008** overlap (the engine's own pitch is 160) |
| Negative body coordinates | `@position(-100, 80)` inside the loop | **MPR011** ×2: the child escapes its loop box |

**The clean version** is the same loop with no annotations. `describe` on it shows the layout
the builder produced (abbreviated):

```
@position(360, 200)   retrieve $Items from ProbeMF.Item;
@position(520, 200)   $Item_CommitList = create list of ProbeMF.Item;
@position(940, 200) @anchor(from: right, to: left)
loop $Item in $Items begin
  @position(210, 80)  …   @position(370, 80)  …   @position(530, 80)  …
end loop;
@position(1360, 200)  commit $Item_CommitList;
```

The builder re-lays-out every unannotated `create or modify`. v0.24.0 geometry, for reading `describe` output (centres; body
coordinates are relative to the loop box's top-left corner; n = activities in the body):

| Element | Position |
|---|---|
| Body child *i* (0-based) | (210 + 160·i, 80) |
| Loop centre | previous centre + 80·n + 180 |
| Next activity after the loop | loop centre + 80·n + 180 |
| Sequential pitch | 160 |

**`RESET LAYOUT` does not parse** on v0.24.0: `mismatched input 'RESET'` (BUG-28, never
implemented upstream). Never write it. If you have to repair a flow by hand, annotate **every**
canvas statement or none.

## Known v0.24.0 defect — loop followed by an activity inside an `if` branch

The script below is correct, and the engine still lays it out wrong:

```
if … then
  loop $Item in $Items begin … end loop;
  commit $Item_CommitList;
else … end if;
```

The builder places the merge at (1230, 200) and the commit at (1210, 200). `mxcli lint` reports
**MPR008** `Activities '(merge)' (1230,200) and '(unnamed)' (1210,200) overlap`. The lint
ratchet then rises on a script with nothing wrong in it. Plain if/else and a loop-only branch are clean.

**Remedy (not `@position`):** move the loop into its own `SUB_` microflow, which the size
table asks for anyway. Or move the following activity to after `end if`. Name the chosen
remedy on the checklist's Layout line.

## Verify — read the BUILD-LOG row

After `./bin/exec.sh`, the lint ratchet writes its verdict into the same BUILD-LOG row:
`lint unchanged vs baseline`, or `⚠️ applied, LINT ROSE` with `lint ROSE: <rules>`.

If the rules listed include CONV011, CONV009, QUAL003, QUAL001, MPR008 or MPR011 after a posted
checklist, **the preflight failed. Say so in chat**, fix the script and re-run. Do not accept
the rise with `--update-baseline`. Lint cannot see a retrieve or REST call inside a loop, so a
clean row proves only the rows lint covers. The checklist is the record for the rest.

## Not verified

- That `mx check` passes a flow whose loop child escaped its box (MPR011). This comes from the
  rule's source comment only.
- CONV013 / CONV014 firing on a REST or Java call.
- The `while` + `limit … offset` batch recipe run end to end. `while` itself executes on v0.24.0.
- Whether a `/** … */` doc comment round-trips into the microflow's Documentation.
- Nanoflow-vs-microflow guidance. No current Mendix docs page was found.
- Whether upstream fixes the if-branch merge overlap in a later release.
