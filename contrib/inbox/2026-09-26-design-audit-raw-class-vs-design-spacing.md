# design-audit rung 7 `raw-class-vs-designproperty` fails the page header `design-spacing.md` prescribes

**From:** card-disbursement requirements-driven build (build-plan row 3.9)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** design-audit.js (toolkit 9fe925e) on a Mendix 11.13.0 app, 7 pages: 4 of 4 `raw-class-vs-designproperty` fails are the same finding, each `ctnHead.spacing-outer-bottom-large → "Spacing"`.
**Proposed target:** `project-tests/e2e/design-audit.js` (rung 7, ~l.547/666) or `skills/design-spacing.md` (l.60, l.66, l.94) — one of them has to give

---

Two toolkit instruments disagree about one class.

- `skills/design-spacing.md` l.60: "`spacing-outer-bottom-large` on every section container", and
  its page-header scaffold (l.94) is `container ctnPageHead (Class: 'page-head spacing-outer-bottom-large')`.
- design-audit rung 7 `raw-class-vs-designproperty` fails any hand-written class that duplicates
  a design property, and Atlas's "Spacing" design property emits that class — so every page
  built by the skill fails the rung.

Verbatim audit lines (page names genericised to their shape):

```
fail | <Module>.<X>_Overview      | rung7/raw-class-vs-designproperty | 1 hand-written class(es) duplicating a design property: ctnHead.spacing-outer-bottom-large → "Spacing"
fail | <Module>.<X>_NewEdit       | (same)
fail | StyleGallery.Gallery_Overview | (same)
```

The project ruled that the skill wins (rendered result identical, the skill's scaffold is what
every wireframe follows) and carries the 4 fails as known. Options for triage:
(a) the skill prescribes the design property instead (`DesignProperties: ['Spacing bottom': 'Large']`
or whatever mxcli v0.24 accepts — not probed here); (b) the rung exempts classes a toolkit skill
prescribes. Hypothesis, not tested: (a) is the better fix, since the property survives an Atlas
class rename and the raw class does not.
