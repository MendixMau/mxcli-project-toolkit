# MERGED — see `skills/module-review.md`

This skill no longer exists on its own. `ui-review-loop.md` (the per-page looking) and
`module-completion-loop.md` (the build→gate→prove sequence) were two skills for **one job:
reviewing a module before calling it done**.

Two files meant one of them got skipped, and the one that got skipped was always the looking.
Measured consequence, 2026-08-19: a module reported 31/31 checks green and shipped to a demo
with a broken data grid and a completely unstyled page, neither of which any journey had ever
opened.

**Everything from both files is in `skills/module-review.md`**, as stages 1–5 of a single pass,
plus the stage that was missing from both: the intelligence check — *is this logical, does it
look right, does it match our design* — run over **every page in the module**, not the pages a
journey happened to visit.

Do not restore this file. If you are here from an old cross-reference, follow the link; if you
are here to run a review, run the one pass.

---

**If you came here looking for a UI loop, there is one — `skills/ui-loop.md`** (added 2026-08-25).
It is not a restoration of this file and it does not compete with `module-review.md`: it is the
cheap per-page look *during* the build (one page, one screenshot, three questions, no report),
where this file was a second *module-close verdict*. Cadence is the difference, and it is the whole
difference — `Gate: UI` fires per module, so on a single-module app the looking happens once, at
the very end, after every page already exists. `ui-loop.md` feeds that gate and never discharges it.

The lesson recorded above still stands and is quoted in that skill: if you ever find yourself
running `ui-loop.md` *instead of* `module-review.md` stage 4, you have re-created exactly the bug
this tombstone exists to record.
