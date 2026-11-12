# Closure re-audit, batches 4 and 5 (QJ-2, 2026-10-08)

The b4/b5 release-impact tables were re-checked against the closure rule (`steps/triage.md` step 10). Every
"not relevant" on a removed setting or flipped default that rests only on "the setting is not set" was flagged.
`release_impact.py --check` now flags these rows itself, so the gate treats them as open.

## Scope

- **Tables:** the last release-impact table of each run branch, 14 tables (b5-news has none).
- **Rows:** 4,100 in all.
- **Results:** 17 flagged at first. 5 were scan-backed (a scan the first pattern missed), which leaves **12 unsound, 6 distinct rows**. Each was settled with the old-default history from the brain (`sp-changes.jsonl`).

| Row (11.0 unless noted) | Runs | Old default (brain) | Verdict |
|---|---|---|---|
| 10.0.0 runtime uniqueness validation setting removed | b4-checklist, b4/b5-kanban-opcenter, b4/b5-opcenter-ef, b5-tasks | database validation only since 9.0.5 | **Sound with a cite**: every source is 9.24+, which already had the new default. The entry must say so. |
| 10.0.0 UseMimeDecoderForBase64 removed, "now always strict" | b4-checklist | opt-in setting since 9.6.10/9.12.0; strict was the default | **Sound with a cite.** |
| -Djava.security.manager / .policy no longer supported | b4-purchase-request-11 | the default launcher had no security manager | **Sound with a cite.** |
| Objects.SetSystemAttributesOnChange removed | b5-forms, b5-tasks | **flipped in 10.20.0** (changedDate on commit only) | **Unsound.** Forms: the real regression (Forms.SubmitForm), now R30. Tasks: the entry claimed "already used the commit-only default", which is false on 9.24.3. R30 finds only MendixSSO.RS_NotifyUserRolesChanged, which reads a User fetched from the database with no change before the read, so it is the same on old and new. No regression. |
| Microflows.RemoveVariableOnDeleteObjectsActivity removed | b5-forms | changed in 10.17.0 and again in 11.0.0 | **Open.** Forms has 2 list deletes (Forms.NewResponse `$ListOptions`, AppSwitcherModule `$DecryptedTokenList`). Whether the list is used after the Delete needs flow order. Tasks: closed by a DESCRIBE scan, which is sound. |
| ObjectManagement.StrictChangeBehavior removed | b5-tasks | **strict became the default in 10.0.0** | **Sound with a cite (since R31).** A real change for every 9.24 source. The Tasks entry checked one entity (TaskTracker), not the whole app; R31 (S2) scans the whole app's own Java and ObjectHandling calls and is clear on tasks915. |

## What follows

1. Behaviour rule **S2, StrictChangeBehavior**: done as R31 (QJ-3). Microflow change actions cannot hit it (Studio Pro
   type-checks them), so R31 looks at by-name setters in own Java and ObjectHandling.setMemberValueByMemberName.
2. Behaviour rule **S3, list used after Delete** (jump crosses 10.17 or 11.0): needs a flow-ordered clause in
   replacement_check. That clause is build item 12 in `quality-judgement-plan.md`.
3. Entries that need a cite: on a rerun of those apps, write the cite from the table above. No old run is edited.

**Lesson.** Run with the new check, the rule catches the Forms miss. It also catches one more false claim (Tasks #230) and two rows that are really open (#226, #229).
Most other flags are closures that were right but didn't show why. A one-line cite fixes those.
