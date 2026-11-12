# Demo brain: routing

Loaded on demand from a project's pointer line. Find the row that fires and read only that file. **No row fires: close this file
and carry on.** Search and citation rules: `AGENTS.md`.

| When (trigger) | Read this |
|---|---|
| **Error code, best-practice recommender rule (MXP0xx), slow log line** | `grep -rliE "<code>\|<symptom noun>" internal/`, one or two keywords, never a sentence |
| **Security**: user roles, module roles, entity access, access rules, anonymous users, password policy | `internal/security/INDEX.md` |
| **Performance problem**: slow page, slow microflow or retrieve, commits in loops, indexes | `internal/performance/INDEX.md` |
| **REST**: consuming or publishing a REST service, JSON structures, mappings, authentication | `internal/rest-integration/INDEX.md` |
