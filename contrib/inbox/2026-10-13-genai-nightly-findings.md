# mxcli nightly defects found regenerating the GenAI Showcase App (Rehost, nightly re-run)

**From:** MendixMau — Rehost increment 2 nightly re-run on mendix/genai-showcase-app (MIT) (split from #293)
**Date:** 2026-10-13
**Kind:** bug
**Field evidence:** captures not committed (lab run, #293). mxcli `nightly-80-gbd45c47e`, Mendix 11.12.0, 36 modules regenerated into `mxcli new --version 11.12.0` with 5 marketplace modules installed.
**Proposed target:** `bug-logs/mxcli-bugs.md` (one BUG-n each), upstream issues. None is among U1–U53 of `bug-logs/pending-github-issues/2026-10-12-mxcli-0.26-round-trip-report.md` unless a U-id is named.

---

Format: defect — verbatim message — repro — workaround.

- **N-1. `project-tree --json` omits rules and message definition collections.** Both describe on the nightly (U5 fixed), but a tree-driven extractor never emits them. Repro: `-c "show rules"` lists 9 `Rule_` documents; `project-tree --json | grep -c Rule_` prints 0. Effect: 5 × CE1613 for export mappings on message definitions (`message definition "GenAICommons.MD_Reference.Reference" not found`) and flows calling rules fail validation (`… which is not a rule in this project`). Workaround: none yet; an extractor could add `show rules <M>` to its fill-in.
- **N-2. exec stores a ContentParams association path as a raw string in `AttributeRef.Attribute`; the model then cannot load.** check passes, exec says `Created snippet AgentCommons.Snippet_Output_List`, then `mx check` and mxbuild stop with `System.ArgumentNullException: Value cannot be null. (Parameter 'value')` ("…set the 'Attribute' property of a Attribute in a Snippet…"). Describe line: `ContentParams: ({1} = $currentObject/AgentCommons.Value_Variable/AgentCommons.Variable/Key)`; without `$currentObject/` it is just as unloadable. The source stores `AttributeRef` null. Related to U10, but this association-path form gets through check. Workaround: fix by hand.
- **N-3. check and exec accept an import or export mapping whose entity does not exist.** `Created import mapping ExampleMicroflows.IM_Ticket` while `ExampleMicroflows.Ticket` was absent; `mx check`: 16 × `[CE1613] "The selected attribute 'ExampleMicroflows.Ticket.Identifier' no longer exists."`. Expected: refuse, as for a microflow parameter of a missing entity.
- **N-4. (likely) A pluggable widget attribute bound to an outer data context loses that context.** `markdown markdownViewer3 (stringAttribute: SystemPrompt, …)` inside `dataview dataView7 (DataSource: microflow ConversationalUI.DS_CopyHelper_Create)` is bound to the innermost entity: `[CE1613] "… 'ConversationalUI.CopyHelper.SystemPrompt' no longer exists."` (3). The source BSON binding is not read yet; confirm first.
- **N-5. describe emits a snippet call without the `Params:` its snippet requires.** exec: `snippet AgentCommons.Snippet_Agent_SelectVersion requires parameter $Agent — add Params: (Agent = $<variable>)…`; `AgentCommons.Version_Overview` never lands (4 × CE1613 at callers). Maybe U6's family.
- **N-6. exec errors that do not name the failing statement.** `failed to build snippet: … AgentCommons.MCP is not a specialization of AgentCommons.Tool…` names no snippet and no statement number, so a resume loop cannot place it; the toolkit falls back to one statement per process (320 statements of ConversationalUI). Expected: `statement N:` as `--continue-on-error` already prints.
- **N-7. Building blocks describe as comments only.** `describe buildingblock ConversationalUI.ConversationStarter` prints `-- Building Block: …` and no `create`. 4 `not-emitted` ledger rows.

Still open, re-seen: U7 (type parameter → `.Entity`, now 14 build errors), U18 (#923 decisions, 3 rows), U23 (`attribute reference not qualified`), U31 (`with all` stdout still ends at 10 001 lines).
