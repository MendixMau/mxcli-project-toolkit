**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-layout-merge-in-if-branch` — found 2026-09-25
**Status:** NOT YET FILED
**Suggested labels:** bug, layout, lint
**Duplicate check:** not yet searched (GitHub API unreachable from the session that drafted this) — search `MPR008 merge` and `#1154` before filing.

---

**Title:** v0.24.0 auto-layout places the merge on top of the activity that follows a loop inside an `if` branch (MPR008 on a script with no `@position`)

**Body:**

## Summary

With the rewritten layout engine (#1154), a microflow whose `if` branch contains a loop *followed by another activity* gets its merge node laid out on top of that activity. The script has no `@position` at all. `describe microflow` shows the merge 20 px from the trailing activity, and `mxcli lint` reports **MPR008** (overlapping elements) on a correct script.

**Version:** mxcli v0.24.0 (built from the `v0.24.0` tag), Mendix 11.12.1, Linux.

## Repro

```
-- no @position anywhere; default layout
create or modify microflow Probe.SUB_LoopInIf ()
begin
  retrieve $Items from Probe.Item;
  if $Items != empty then
    loop $Row in $Items
    begin
      change $Row (Name = 'x');
      change $Row (Name = 'y');
    end loop;
    commit $Items on error rollback;
  else
    log info node 'Probe' 'empty';
  end if;
end;
```

```
mxcli exec repro.mdl -p App.mpr
mxcli -p App.mpr -c "describe microflow Probe.SUB_LoopInIf"
mxcli lint -p App.mpr
```

## Measured

| element | x, y |
|---|---|
| if | 520, 200 |
| loop (true branch) | 870, 200 |
| commit (true branch, after the loop) | 1210, 200 |
| **merge** | **1230, 200** |
| log (else branch) | 690, 350 |
| end | 1430, 200 |

Lint: `MPR008` on `Probe.SUB_LoopInIf`.

## Controls (same binary, same model) — both lay out clean

- Plain if/else without a loop: merge at 970, 200; true-branch activities at 690 and 850; lint clean.
- An `if` branch that contains **only** the loop and nothing after it: lint clean.

So the loop's width is accounted for when the merge is placed, but an activity after the loop inside the same branch is not.

## Expected

The merge sits after the last activity of the longest branch, as it does for branches without a loop.

## Workaround

Move the loop into a sub-microflow, or place the trailing activity after `end if`. Hand-placing only the merge with `@merge` is worse: partial hand placement trips MPR008/MPR011 itself, and the `syntax microflow.layout` help rightly says to prefer no `@position` at all.
