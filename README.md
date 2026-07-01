# mxcli-project-toolkit

Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.

Used across all mxcli-powered projects — OS migration, ClientB, future Java/Angular migrations, and others.

---

## What's in here

```
mxcli-project-toolkit/
  skills/
    migration-pipeline.md       ← Full pipeline phase guide (XML → KB → BRD → MDL)
    brd-generation.md           ← BRD JSON prompt templates + validation checklist
    kb-generation.md            ← Document extraction (Excel/Word/PDF → KB markdown)
    source-os11.md              ← OutSystems 11 XML schema reference
    os-xml-schema.md            ← OS eSpace XML structure details
    mdl-cookbook-microflows.md  ← MDL scripting patterns for microflows
    e2e-harness-base.md         ← End-to-end test harness base
    learned-*.md                ← Validated learnings from live projects
  bug-logs/
    mxcli-bugs.md               ← Known mxcli CLI bugs and workarounds
    bug-log-contoso-m0022.md    ← Project-specific bug log (Contoso M-0022)
  process/
    process-learnings.md        ← Cross-project process improvements
    test-plan-contoso-m0022.md  ← Reference test plan
  SESSION-NOTES.md              ← Running session diary
```

---

## When to use which skill

| Task | Skill to load |
|------|--------------|
| Running the extraction pipeline | `migration-pipeline.md` |
| Writing or enriching a BRD JSON | `brd-generation.md` |
| Extracting Excel/Word/PDF specs | `kb-generation.md` |
| Understanding OS XML source | `source-os11.md` + `os-xml-schema.md` |
| Writing MDL microflow scripts | `mdl-cookbook-microflows.md` |
| Diagnosing a mxcli error | `bug-logs/mxcli-bugs.md` |

---

## How to add a new skill

1. Create a new `.md` file in `skills/` with this header:
   ```markdown
   # Skill Name — Purpose
   **Purpose:** one-line description
   **Source:** which project or session this came from
   ```
2. Structure it as a step-by-step guide with prompt templates where applicable
3. Add it to the table above in this README
4. Commit and push — available to all projects on next `git pull`

---

## How to add a project-specific learning

For validated patterns from a live project, add a file `skills/learned-{topic}.md`. These get loaded by Claude when relevant and accumulate into cross-project knowledge.

For bugs, append to `bug-logs/mxcli-bugs.md` or create a project-specific log.

---

## Used by

- `OS-migration-skills/` — OutSystems 11 → Mendix pipeline
- ClientB integration project
- Future: Java/Angular → Mendix migration pipeline
