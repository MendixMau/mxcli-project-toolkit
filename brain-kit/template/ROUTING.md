# {{COMPANY}} brain: routing

Loaded on demand from a project's pointer line (see README, "Wire it into a project"). Find the row that fires and read only that
file. **No row fires: close this file and carry on.** Search and citation rules: `AGENTS.md`.

Rows are trigger conditions, front-loaded on the triggering word, one per topic. Keep the table under ~20 rows.

| When (trigger) | Read this |
|---|---|
| **Error code, stack trace, build or deploy failure** | `grep -rliE "<code>\|<symptom noun>" internal/`, one or two keywords, never a sentence |
| **{{Upgrading}}** {{the product or its modules}} | `internal/{{upgrade}}/INDEX.md` |
| **{{Security}}**: {{roles, SSO, headers}} | `internal/{{security}}/INDEX.md` |
| **{{Performance problem}}**: {{slow page or query, timeouts, memory}} | `internal/{{performance}}/INDEX.md` |
