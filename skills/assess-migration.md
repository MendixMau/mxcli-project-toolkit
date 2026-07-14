# Migration Assessment: Investigating Non-Mendix Projects
**Applies to:** migration.

**This skill is bundled with mxcli — don't read a copy here.** The canonical, always-current version ships in every mxcli-initialized project at **`.ai-context/skills/assess-migration.md`** (refreshed with each mxcli release). This file used to be a verbatim copy; that guaranteed silent drift, so it's now a pointer per the README's division-of-labor rule ("this toolkit does not duplicate bundled skills").

Read the bundled version for the full investigation process (stack identification, entity/logic/integration/security inventory, risk assessment, report template).

## What this toolkit adds on top of the bundled assessment

- **The assessment is an input, not a conclusion.** Its findings feed `source-triage.md`'s coverage matrix — triage checks the assessment against this toolkit's actual extractor/mapper coverage, decides whether pipeline automation is warranted (reuse vs build-new, per the two-way call), and recommends a slice ordering before any BRD is generated. Never jump from assessment straight to BRDs.
- **Cross-validation with the extraction pipeline.** For medium/large sources, run both the manual assessment and the stack's extraction pipeline (`pipelines/<stack>/`); discrepancies between the two are exactly the gaps `source-triage.md` exists to surface. See README → "How `assess-migration` and the extraction pipeline complement each other".
- **Stage placement:** in `conversion-runbook.md` terms, the assessment is Stage 0 (Triage) input, owned by `ba-agent`, and its acceptance is part of the Stage 0 `✋` gate.
