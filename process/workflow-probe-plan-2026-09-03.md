# Workflow probe plan — closing the "unprobed" rows of `skills/workflow-structure-rules.md` §11

**RUN 2026-09-03 — COMPLETE. 12 of 12 rows resolved.**

| | |
|---|---|
| `mxcli --version` | **v0.20.0** (2026-08-28T13:22:53Z) |
| Mendix version | **11.14.0** (scratch app created by `mxcli new --version 11.14.0`) |
| Native validator | `/Applications/Mendix Studio Pro 11.14.0 Beta.app/Contents/modeler/mx check` |
| Where | blank scratch app `WfProbe` at `/tmp/wfp/WfProbe`, never the real project |
| Baseline | scaffold + context entity + task page + 2 microflows: **0 errors** before any probe |

**Substitution for step 3 of the method, declared.** "Open in Studio Pro and look at the icons"
was **NOT RUN** — this was an unattended session with no operator at the GUI. In its place each
construct got a **`DESCRIBE WORKFLOW` round-trip** (did the construct survive the write, or was
it silently dropped?) on top of the native `mx check`, which is the same validation engine
Studio Pro runs. That covers the *error* half of step 3 and the *silent-drop* half; what remains
uncovered is purely visual — whether the editor draws the right icon for a construct that is
otherwise valid. Two rows below (4, 9) are marked accordingly.

**Headline: `mxcli check` is not evidence for workflows — it was wrong on 5 of 12 rows.**
Three constructs passed `mxcli check --references` *and* `exec` *and* the `DESCRIBE`
round-trip, and were still broken or corrupting under `mx check`. One of them (row 10) leaves
the `.mpr` unopenable. Six defects filed: BUG-107 … BUG-112. One early conclusion was **wrong and corrected in-run**: the parameterised `CALL MICROFLOW` was first recorded as unwritable; re-probing four spellings showed the value simply has to be quoted (BUG-107), so the construct is proven and the bug is a crash-on-bad-input, not a missing feature.

**Target:** Mendix 11.14, current mxcli (`mxcli --version` first — record it).
**Where:** a scratch project or a sandbox copy that keeps the original `.mpr` filename
(`learned-workflow-patterns.md` §8, "To re-verify on any binary").
**Method:** one construct per script, smallest possible body, three checks per construct:
`mxcli check --references` → native `mx check` → open in Studio Pro and look at the icons.
A pass on the first alone proves nothing for workflows (Warning 3). Start every construct with
`mxcli syntax workflow` and `HELP` — absence there is not evidence of non-support (§7).

| # | Construct | Candidate MDL to try first | Result (mxcli / mx check / SP) | Notes |
|---|---|---|---|---|
| 1 | multi-user task + decision method + completion timing  | `MULTI USER TASK Rev 'Review' PAGE M.P OUTCOMES 'Done' { };` — mxcli ✓ · mx check ✓ 0 errors · round-trip ✓ | **PROVEN (bare form) / hand-add (method + timing)** | Undocumented in `mxcli syntax workflow` yet fully supported. **No grammar for decision method or completion timing** — `DECISION METHOD MAJORITY`, `METHOD …`, `COMPLETION …` and a bare `MAJORITY` are all parse errors. So the activity is scriptable, its decision rule is a Studio Pro hand-add. |
| 2 | explicit `JUMP TO <activity>` in the main flow  | In an outcome: mxcli ✓ · mx check ✓ 0 errors · round-trip ✓. In a boundary-event body: mxcli ✓ · **mx check CE0495 + CE6680** · round-trip ✓ | **PROVEN in an outcome / BROKEN in a boundary body** | `JUMP TO <activity>`. Must be the last statement of its path. In a boundary body it writes a Jump with no Target, named after its target — **BUG-109**. |
| 3 | `END OF PARALLEL SPLIT PATH` as an explicit terminator inside `PATH n { }`  | `END OF PARALLEL SPLIT PATH;`, `END PATH;` → parse errors | **NOT EXPRESSIBLE — and not needed** | MDL has no explicit path terminator at all. Branch termination is by nesting only, and that is **correct**: the nested form passes `mx check` with 0 errors. Not a gap — record as "by nesting". |
| 4 | boundary event timer, **non-interrupting**, ending in end-of-boundary-event-path  | Non-interrupting: mxcli ✓ · mx check ✓ 0 errors · round-trip ✓ · *icons NOT RUN*. Interrupting: no legal terminator exists — empty body → **CE0105**, `JUMP TO` → BUG-109, `END WORKFLOW` → parse error | **PROVEN (non-interrupting) / NOT EXPRESSIBLE (interrupting)** | **The duration must be a Mendix expression, not an ISO period.** `'P3D'` passes `mxcli check` and fails `mx check` with **CE0117 "Error(s) in expression"**. `'addDays([%CurrentDateTime%], 3)'` is correct. This *corrects* `learned-workflow-patterns.md` §19, which documented `'P3D'` as proven. |
| 5 | boundary event on **notification**  | `BOUNDARY EVENT NOTIFICATION 'Ping'` → `mismatched input 'NOTIFICATION' expecting {TIMER, INTERRUPTING, NON}` | **NOT SUPPORTED** | The grammar admits only timer boundary events. Hand-add in Studio Pro. |
| 6 | event sub-process, timer, interrupting  | `EVENT SUBPROCESS …` / `EVENT SUB PROCESS …` → `mismatched input 'EVENT' expecting END` | **NOT SUPPORTED** | No event-sub-process construct in the grammar, in any position. Hand-add in Studio Pro. |
| 7 | event sub-process, timer, non-interrupting with recurrence `interval 1 Day maxExecutions 2`  | as row 6 — the container does not exist, so recurrence has nothing to attach to | **NOT SUPPORTED** | Bounds (`interval ≥ 1`, `maxExecutions ≥ 2`, unit ∈ Minute/Hour/Day/Week/Month) remain model rules for the Studio Pro hand-add; untestable from MDL. |
| 8 | event sub-process, notification (both kinds)  | as row 6 | **NOT SUPPORTED** | `NOTIFY WORKFLOW` from a microflow remains proven (unchanged); the *receiving* sub-process is a hand-add. |
| 9 | `WAIT FOR NOTIFICATION` / `WAIT FOR TIMER` in the body  | `WAIT FOR TIMER 'addDays([%CurrentDateTime%], 1)';` and `WAIT FOR NOTIFICATION;` — mxcli ✓ · mx check ✓ 0 errors · round-trip ✓ · *icons NOT RUN* | **PROVEN — both** | Both undocumented in `mxcli syntax workflow`, both work. `WAIT FOR TIMER` takes an **expression**, same as row 4 — `'P1D'` gives CE0117. `WAIT FOR NOTIFICATION` takes **no name** (`WAIT FOR NOTIFICATION 'Ping'` and `… Ping` are both parse errors); the name is a Studio Pro property. |
| 10 | enum `DECISION` **without** an Empty outcome  | `'Probe.StatusEnum.Draft'` → mxcli **rejects**. `'StatusEnum.Draft'` → mxcli **rejects**. `'Draft'` → mxcli ✓, exec ✓, round-trip ✓, **`mx check` cannot load the project: `StorageLoadException`** | **CORRUPTING — an enum decision cannot be written at all** | **BUG-108, since folded into the older BUG-76** — which had already established that *every* `DECISION` corrupts, not only enum-valued ones. What is new here: the validator is inverted: the only accepted form corrupts, both correct forms are refused. The Empty-outcome question could not even be reached. Recovery is `DROP WORKFLOW` (mxcli can still read the corrupt model) — verified back to 0 errors. |
| 11 | XPath token form `System.UserRoles = '[%UserRole_Manager%]'` inside `TARGETING USERS XPATH '…'`  | `TARGETING XPATH '[System.UserRoles = ''[%UserRole_User%]'']'` — mxcli ✓ · mx check ✓ 0 errors · round-trip ✓ | **PROVEN — resolves §6's divergence toward the MCP team's form** | The token form survives mxcli's single-quoted string with `''` escaping. Both forms are now proven; §6's "use the proven one" caveat is retired. Separately, `DESCRIBE` re-emits it **unescaped and unparseable** — **BUG-110**. |
| 12 | `END WORKFLOW` nested inside a parallel `PATH`  | `END WORKFLOW` is not a statement anywhere: inside a path, inside an outcome, or in the main flow. All parse errors. | **UNREACHABLE FROM MDL — structurally prevented** | CE1844 cannot be triggered from MDL because MDL cannot express an end-workflow activity at all. §4's rule still governs anything hand-added in Studio Pro, and still governs the diagram. |

**Closing the loop:** every row lands in `workflow-structure-rules.md` §11 (proven / hand-add) and,
for a new proven form, as a snippet in `learned-workflow-patterns.md` §6–§7 plus
`build/workflow-example.mdl`. A refused form with a corrupting write is a BUG-DRAFT in
`bug-logs/mxcli-bugs.md`. Same commit, one changelog line, credit the probe project.
