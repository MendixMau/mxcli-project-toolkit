# CAC-1 — Scope Checkpoint

**Fires after:** Phase 1 Source Triage
**Feeds into:** Phase 2 Extraction + Phase 3 BRD Scaffolding
**Template:** See `checkpoint-template.md` for format rules.

---

## What to Surface

Pull from `source-triage.md` output:
- Total modules/files classified
- Business vs framework breakdown (count)
- Capabilities identified and coverage status (extractable / manual / skip)
- Any stack signals that weren't covered by existing extractors

## What's Next

Phase 2 runs the extraction pipeline against the confirmed scope. If a new extractor is needed
(nothing in toolkit covers this stack), that has to be built before extraction can run.

---

## Predefined Questions

### Q1 — POC boundary

**When to ask:** Always (first migration decision).

**How to generate options:** Look at the capability map from triage. Surface the 3 most cohesive
capability clusters as options A/B/C. Mark the smallest shippable slice as recommended.

Example:
> "Which capabilities should be in the POC scope?"
> - A) [Core feature 1 + Core feature 2] — smallest shippable slice *(recommended)*
> - B) [Full feature set] — migrate everything now
> - C) [Core feature 1 only] — one capability, lowest risk

**Record as:** `pipeline-state.md` → `## Decisions Made` → `Goal:`

---

### Q2 — Extractor strategy

**When to ask:** When triage finds a gap (stack not covered by existing extractors).
**Skip if:** Triage confirms existing extractors cover ≥80% of the scope.

**How to generate options:** Check `mxcli-project-toolkit/pipelines/` for matching pipeline.
If found: option A = reuse it. If not found: offer build-new vs manual-only.

> "The source uses [stack X]. The toolkit [has / doesn't have] an extractor for this stack. How should we proceed?"
> - A) Reuse existing [pipeline name] extractor *(recommended — already tested)*
> - B) Build a new extractor (30–60 min investment; reusable for future projects)
> - C) Manual-only — skip extraction, write BRDs by hand from source reading

**Record as:** `pipeline-state.md` → `## Decisions Made` → `Pipeline:`

---

## Open Question

> "Is there a project brief, stakeholder document, Confluence page, or Jira epic that defines
> the target? Drop a link or paste the key constraints — or say 'none' if this is code-only."

**What to do with the answer:**
- If a link is provided: add it to `project-profile.md` under `## External References`
- If constraints are pasted: record them in `pipeline-state.md` under `## Decisions Made`
- If 'none': note it and proceed

---

## Decision Recording

```
pipeline-state.md → ## Decisions Made:
  Goal: [POC first / Full / Strangler fig] — [capability list]
  Pipeline: [pipeline name or manual-only]
  External refs: [links or 'none']
```
