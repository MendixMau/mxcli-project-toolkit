# Workflow probe plan — closing the "unprobed" rows of `skills/workflow-structure-rules.md` §11

**Target:** Mendix 11.14, current mxcli (`mxcli --version` first — record it).
**Where:** a scratch project or a sandbox copy that keeps the original `.mpr` filename
(`learned-workflow-patterns.md` §8, "To re-verify on any binary").
**Method:** one construct per script, smallest possible body, three checks per construct:
`mxcli check --references` → native `mx check` → open in Studio Pro and look at the icons.
A pass on the first alone proves nothing for workflows (Warning 3). Start every construct with
`mxcli syntax workflow` and `HELP` — absence there is not evidence of non-support (§7).

| # | Construct | Candidate MDL to try first | Result (mxcli / mx check / SP) | Notes |
|---|---|---|---|---|
| 1 | multi-user task + decision method + completion timing | `MULTI USER TASK … OUTCOMES …` — check syntax topic for method/timing clauses | | |
| 2 | explicit `JUMP TO <activity>` in the main flow | | | must be the last statement of its path |
| 3 | `END OF PARALLEL SPLIT PATH` as an explicit terminator inside `PATH n { }` | | | today termination is by nesting only |
| 4 | boundary event timer, **non-interrupting**, ending in end-of-boundary-event-path | extend §19's `boundary event timer 'P3D' { … }` form | | interrupting form is proven |
| 5 | boundary event on **notification** | | | |
| 6 | event sub-process, timer, interrupting | | | recurrence must be refused here |
| 7 | event sub-process, timer, non-interrupting with recurrence `interval 1 Day maxExecutions 2` | | | also try `interval 0` and `maxExecutions 1` — expect refusal |
| 8 | event sub-process, notification (both kinds) | pair with `NOTIFY WORKFLOW` from a microflow | | |
| 9 | `WAIT FOR NOTIFICATION` / `WAIT FOR TIMER` in the body | | | |
| 10 | enum `DECISION` **without** an Empty outcome | mxcli ≥ v0.18.0 only | | expect a Studio Pro warning/error — record the code |
| 11 | XPath token form `System.UserRoles = '[%UserRole_Manager%]'` inside `TARGETING USERS XPATH '…'` | | | reconciles §6's divergence with the MCP team's form |
| 12 | `END WORKFLOW` nested inside a parallel `PATH` | | | expect CE1844 — confirms §4 is visible somewhere in the chain, and at which step |

**Closing the loop:** every row lands in `workflow-structure-rules.md` §11 (proven / hand-add) and,
for a new proven form, as a snippet in `learned-workflow-patterns.md` §6–§7 plus
`build/workflow-example.mdl`. A refused form with a corrupting write is a BUG-DRAFT in
`bug-logs/mxcli-bugs.md`. Same commit, one changelog line, credit the probe project.
