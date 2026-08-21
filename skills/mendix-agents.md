# Mendix Agents — building one that works

**Applies to:** any Mendix 11.9+ app with the agent-editor marketplace stack installed.
**Purpose:** everything around `mxcli`'s bundled `agents.md` — the creation routes, the
export-verified JSON schema, tool-writing craft, knowledge base loading, and the runtime
wiring. For the chat UI itself see `skills/mendix-agent-ui.md`.

## Read the bundled skill first — and check it is current

MDL syntax for `create model`, `create knowledge base`, `create consumed mcp service` and
`create agent` ships **with mxcli**, at `<mxcli>/cmd/mxcli/skills/agents.md`, and lands in
each project as `.ai-context/skills/agents.md` at `mxcli init` time. This skill never
duplicates it.

**Those project copies go stale and nothing tells you.** `init` copies once; a later
`mxcli` upgrade does not refresh them. Diff before trusting one:

```bash
diff <mxcli-repo>/cmd/mxcli/skills/agents.md .ai-context/skills/agents.md
```

A recent addition that older copies lack, and that matters:

> **`Provider` is free-form and validated by nothing.** `Provider: TotallyMadeUp` parses,
> writes, and round-trips through `describe model`. Agent Editor documents are stored as
> custom blobs and mxbuild contains no agent-editor strings at all, so `mx check` and the
> build both stay green — the fault surfaces only when Studio Pro opens the document.
> Take provider values from a document Studio Pro created, never from memory.

That is the shape of most failures in this stack: **green build, empty result.** Assume it.

## Prerequisites

Mendix 11.9+ and seven marketplace modules. `AgentEditorCommons` depends transitively on
the rest, so all seven must be installed:

| Module | Role |
|---|---|
| `GenAICommons` | Core types — Request/Response, DeployedModel, Tool, KnowledgeBase |
| `MxGenAIConnector` | Mendix Cloud AI backend, model config, embeddings |
| `AgentCommons` | Agent management — versioned agents, tools, KBs, MCP |
| `AgentEditorCommons` | Bridge to the Studio Pro Agent Editor extension |
| `MCPClient` | MCP server connections, tool discovery and execution |
| `ConversationalUI` | Chat widgets, tool-approval UI, trace monitoring |
| `Encryption` | Provides the 32-char key models and KBs reference |

Also register `ASU_AgentEditor` as an after-startup microflow.

## Three ways to create an agent — pick the second

`AgentCommons.Agent` is an **entity**, not a model document. An agent cannot be declared in
MDL; something has to create it at runtime.

| Route | When |
|---|---|
| **Import a JSON export** | **Default.** No seed microflow, no After Startup wiring, diffable in git, reviewable by a non-developer. |
| Seed microflow (`ASU_*`) | Only when agents must exist before any human logs in. Costs you an After Startup registration, and `alter settings model` is a STOP — it corrupts BSON. |
| By hand in the agent editor | Exploration. Export it the moment it works. |

The seed route is real work: `Agent_Create` → `change` Title/Description/UUID/UsageType →
`commit` → `Version_Create` → `change` SystemPrompt/ToolChoice/Temperature → one
`Tool_Create` + `change` per tool. Get-or-create by Title to stay idempotent. Roughly 12
statements per agent versus one JSON file.

## The JSON schema — verified against a real export

Confirmed by diffing against an actual export. Key sets match exactly at all three levels.

```
top-level : Title, Description, UsageType, UUID, Versions,
            Variables, Version_InUse, TestCases
version   : Title, SystemPrompt, VersionNumber, UUID, VersionChangedDate,
            ToolChoice, Tools, MCPs, SingleMCPTools, Temperature, KnowledgeBases
tool      : Name, Description, Microflow, UserAccessApproval, IsEnabled, UUID
```

**Five corrections a real export forced.** The published schema misleads on all of them:

| Field | Schema says | Reality |
|---|---|---|
| `UserAccessApproval` | example shows `"Hidden"` | **`HiddenForUser`** — the enum key |
| tool `DisplayTitle` / `DisplayDescription` | present | **absent** from real exports |
| `PromptOwner`, version `Description`, `VersionOwner` | present | **absent** from real exports |
| `Version_InUse` | not mentioned | **required** — `{"UUID": "<a version UUID>"}` |
| `Temperature` | not mentioned | present on the version |

`Version_InUse.UUID` must match one of `Versions[].UUID`, or **nothing is active after
import** — silently.

Enum values, verified against the model:

- `UsageType`: `Single_Call` | `Conversational`
- `ToolChoice`: `auto` | `none` | `any` | `tool`
- `UserAccessApproval`: `UserConfirmationRequired` | `HiddenForUser` | `VisibleForUser`

**The general lesson:** `DESCRIBE JSON STRUCTURE` shows the *sample snippet the structure
was generated from*, which is not the format the importer accepts. Get a real export before
generating one.

→ `skills/agents-examples/agent-template.json`, `skills/agents-examples/catalog-copilot.agent.json`

## Writing tools

**Scalar parameters only.** A tool call cannot populate an object or an Enumeration. If the
microflow you want to expose takes a filter *object* with enum fields, do not try to cast
free text into those enums — write a thin tool that takes plain Strings and does the query
itself. Chasing the enum round-trip means a one-branch-per-value CASE chain per enum, and
it buys nothing.

**The `Description` is the tool's entire interface.** The model never sees the microflow,
its parameter names, or its body. Say what each parameter accepts and what blank means.

**Never return empty.** "No results for X" is a sentence. A blank string is a void the
model fills with plausible invented data.

**Bound every list.** `limit 10`. An unbounded retrieve blows the context window.

**Name which lookup failed.** Three distinct "not found" strings beat one generic failure —
otherwise the model guesses at the cause and tells the user something wrong.

**State read-only status in the system prompt, explicitly.** A model holding only read tools
will still cheerfully claim it updated something.

**Mask internal identifiers.** UUIDs, row IDs and tenant IDs should never reach the model.
Decide the masking list once, per module, and apply it in every tool's return string.

For **write** tools, additionally:
- `UserAccessApproval: "UserConfirmationRequired"`. `HiddenForUser` on a write tool means
  the model mutates data with no human in the loop.
- Write an audit record on every branch. Without one, a real write and a hallucinated write
  look identical a week later.
- Display-only parameters (a name to render on a confirmation card) must be documented as
  such in the tool Description, with "pass '' if you don't need it" — or the model invents
  values for them.
- Inline association-sets in the microflow body mean the **MCP exec path with Studio Pro
  open**. The disk-write path corrupts them.

→ `skills/agents-examples/tool-read.example.mdl`, `skills/agents-examples/tool-write.example.mdl`

## Knowledge bases

Three silent failures, all of which look like success:

1. **`ChunkCollection_AddChunk` creates a plain `Chunk`.** Retrieval only accepts
   `KnowledgeBaseChunk`. `ChunkCollection_GetKnowledgeBaseChunkList` filters plain Chunks
   out, and both `Embed_Insert` and `Embed_Replace` depend on it — so nothing ever reaches
   the KB while the admin button reports success. Use
   **`ChunkCollection_AddKnowledgeBaseChunk`**.
2. **`Embed_Replace` needs `MxObjectID` on every chunk** to dedupe by object. Plain Chunks
   have none and validation fails silently. Once on `KnowledgeBaseChunk` you have it, and
   Replace makes a re-run idempotent instead of duplicating the catalogue.
3. **Empty metadata values are rejected** (`400: must not be empty`). Optional String
   attributes are legitimately empty on some records, and one empty value fails that whole
   chunk — typically discovered as "chunks 16 and 17 failed" partway through a load. Guard
   every metadata add the same way you guard the chunk text.

Guarding the chunk *text* is a quality question, not an error one: `' | Notes: '` with
nothing after it is noise in the vector.

Other things worth knowing: `Collection_GetCreate` is get-or-create, and the collection name
takes no whitespace. The KB resource must be configured on the MxGenAIConnector admin page
(Portal key import) before any of this runs.

→ `skills/agents-examples/kb-load.example.mdl`

## Runtime wiring

`AgentCommons` ships `ChatContext_ChatWithHistory_ActionMicroflow_AgentBuilder` and it looks
like the microflow to wire up. **It is not** — it requires a `PageHelper`, an Agent Editor
concept that does not exist at runtime outside the editor.

Write your own action microflow instead:

```
retrieve Agent by Title
  → PromptToUse_GetAndReplace        (resolves the InUse version)
  → Request_CreateFromChatContext
  → Request_AddAgentCapabilities     (wires every tool the version declares)
  → ChatCompletions_WithHistory      (with an active Text DeployedModel)
  → ChatContext_UpdateAssistantResponse
```

Log a warning naming the fix on every failure path. A chat that silently does nothing is the
hardest thing here to debug.

**If you only need RAG and no tools, skip the Agent document entirely:**
`ChatContext_Preprocessing` → `Request_AddKnowledgeBaseRetrieval` per KB →
`ChatCompletions_WithHistory`. Retrieve **`DeployedKnowledgeBase`**, not
`ConsumedKnowledgeBase` — Deployed is the retrieval-side entity, and the names are close
enough to cost an afternoon.

→ `skills/agents-examples/agent-action.example.mdl`

## Never commit a client export

Real exports carry client-identifying content — system prompts naming the client, tool
descriptions in their language, domain vocabulary that only means something to them. Scrub
before committing, or keep the export outside the repo. See `anonymize-client-app-for-demo.md`.

## Checklist

- [ ] Seven modules installed, `ASU_AgentEditor` wired as after-startup
- [ ] Project's `.ai-context/skills/agents.md` diffed against the mxcli source
- [ ] Provider values taken from a Studio-Pro-created document
- [ ] Agent defined as JSON in the repo, not a seed microflow
- [ ] `Version_InUse.UUID` matches a `Versions[].UUID`
- [ ] Every tool: scalar params, guarded, bounded, non-empty failure strings
- [ ] Write tools: `UserConfirmationRequired` + audit record on every branch
- [ ] Internal identifiers masked out of every tool return
- [ ] KB loaders use `AddKnowledgeBaseChunk` + `Embed_Replace` + guarded metadata
- [ ] Read-only status stated explicitly in the system prompt, if it applies
- [ ] Verified by **reading data back**, not by a green exec log
