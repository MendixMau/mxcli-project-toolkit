**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-123` — noted 2026-09-03, measured 2026-09-07
clearing script `87`'s drop set on a topbar-titled portal project (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, cross-references, show-callers, safety

---

**Title:** `SHOW CALLERS OF` indexes neither page button actions nor `show page` targets, so it
reports "no callers" for microflows that pages call

**Body:**

## Summary

`SHOW CALLERS OF Module.Microflow` reports **no callers** for a microflow wired to a page button.
`Approval.ACT_ApprovalRun_ShowFlow` has been the action on the *View flow* button of the running
overview since it was built; the index says nothing references it.

The same blind spot covers pages in the other direction: nothing reports which microflows
`show page Module.SomePage`, so a page cannot be cleared for deletion from the index either.

## Repro

```
mxcli -p <project>.mpr -c "SHOW CALLERS OF Approval.ACT_ApprovalRun_ShowFlow"
→ (no callers)

mxcli -p <project>.mpr -c "DESCRIBE PAGE Approval.Approval_RunningOverview" | grep ShowFlow
→ actionbutton btnViewFlow (Action: MICROFLOW Approval.ACT_ApprovalRun_ShowFlow(...))
```

## Impact

`SHOW CALLERS` / `SHOW REFERENCES` / `SHOW IMPACT OF` are the documented way to answer *"is it
safe to drop this?"*, and they share this index. **A drop cleared that way is not cleared.**

Clearing script `87`'s drop set honestly required a **22,836-line `DESCRIBE` dump** of every
microflow and page in the project plus a word-boundary grep. That turned up **four microflows and
three home-page tiles** the index had not mentioned.

mxbuild does catch the resulting dangling reference afterwards, so this costs an hour rather than
a corrupted model — but the tool answers a safety question confidently and wrongly, which is the
part worth fixing.

## Expected

Index widget `Action:` targets and microflow `show page` targets into the same cross-reference
table. If that is a larger job, have `SHOW CALLERS` state which reference kinds it covers, so its
silence reads as *"not indexed"* rather than *"not referenced"*.
