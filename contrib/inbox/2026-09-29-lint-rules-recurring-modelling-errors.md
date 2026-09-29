# Four modelling errors hit BOTH arms — they are lint rules, not tool bugs

**From:** ProcureFlow cook-off (mxcli + toolkit arm vs Studio Pro MCP arm, same frozen spec)
**Date:** 2026-09-29
**Kind:** learning
**Field evidence:** defect tables of both arms (~37 vs ~38 defects; modelling errors 16 vs 15); four defects recurred in both arms independently, so they come from the spec/platform, not the authoring tool.
**Proposed target:** `skills/learned-detection-gaps.md` / `skills/learned-microflow-patterns.md`, and upstream mxcli lint

---

| Rule | Defects it would have caught |
|---|---|
| Picker/selectable XPath reads rows the current role cannot read under entity access (e.g. via System.UserRoles / Account) | reassign picker listed only self / was empty — both arms |
| Microflow called from a page button changes/creates objects shown on that page without refreshInClient | "draft with agent" page not refreshed; goods-receipt lines never load — both arms |
| `change` without commit at the end of a timer/workflow-called microflow | escalation change lost (found only by a timer run) |
| addDays / trim on a possibly-empty attribute | null runtime error |
| Navigation without logout item; home page needs role read (CE2729) | caught late in both arms |

Also shared, spec-level: vendor legal-suffix matching; workflow admin centre access for the
AP manager role. Proposed: add the rules to the detection-gaps skill now, and file them as
mxcli lint requests. Hypothesis: prevents ~6–8 of ~75 combined defects.
