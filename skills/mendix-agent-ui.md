# Mendix Agent UI — the copilot sidebar

**Applies to:** any Mendix app embedding a `ConversationalUI` chat surface.
**Purpose:** the four-layer route from wireframe to a working copilot panel, and the
handful of details that make it work. For the agent, tools and knowledge base behind it,
see `skills/mendix-agents.md`.

## The split that makes this easy

**You build the frame. ConversationalUI builds the conversation.**

```
.copilot
  .c-head    ← yours: badge, title, subtitle, spacer, minimise
  .c-body    ← yours: greeting, autofill CTA, starter chips
    dataview → ConversationalUI.Snippet_ChatContext_ConversationalUI_Bubbles
               ← theirs: message list AND input bar
```

Get that boundary wrong and you ship two input bars. Get it right and the chat comes for
free while the panel still looks like your app.

## Five layers, in order

### 1. Wireframe first

An HTML wireframe in `design/wireframes/`, built on the same `ds.css` tokens as the rest of
the app. The MDL is written *against* the wireframe — a snippet header should be able to say
"rebuilt to match `design/wireframes/<page>.html` exactly" and mean it.

Do not skip to MDL. The copilot panel has more layout decisions in it than any other
component in a typical app (header density, chip wrapping, bubble max-width, where scroll
lives), and they are an order of magnitude cheaper to settle in HTML.

### 2. CSS in the style gallery

`.copilot` and friends live in the shared stylesheet, entirely in design tokens. No literal
colours, no literal radii. That is what lets the same markup sit in a page column, a modal,
or a docked sidebar and still look native.

Three structural rules do the real work:

| Rule | Why |
|---|---|
| `.copilot` → `display:flex; flex-direction:column; overflow:hidden` | rounds the corners of whatever ConversationalUI renders inside |
| `.c-body` → `flex:1; min-height:0` | **scroll lives here, not on the page.** `min-height:0` is the half everyone forgets, and without it the whole page scrolls |
| `.c-foot` | static mockups only — a live app gets its input bar from ConvUI |

Watch for **drift between the wireframe CSS and the app CSS.** These two get edited by
different people at different times and quietly diverge — one ends up with `.c-msgs` and a
`border-left`, the other with `.c-body` and a full border. Diff them when a screen stops
matching its wireframe.

→ `skills/agents-examples/copilot.example.scss`

### 3. The snippet

Hand-build `.c-head` and the static parts of `.c-body`, then hand off to ConvUI inside a
DataView:

```
dataview dvChat (
  DataSource: microflow AIAssistant.DS_ChatContext_Create,
  Class: 'chat-dataview--display-contents'
) {
  snippetcall scBubbles (Snippet: ConversationalUI.Snippet_ChatContext_ConversationalUI_Bubbles)
}
```

Four details, each of which costs an hour to rediscover:

1. **No static `.c-foot`.** ConvUI renders the input bar. Building one from the wireframe
   ships the page with two.
2. **`chat-dataview--display-contents` on the DataView.** A Mendix DataView emits its own
   wrapper div, which breaks the flex chain between `.c-body` and the bubbles so the list
   never fills. `display: contents` on the wrapper and its content div fixes it.
3. **`flex:1;min-height:0` inline on the body container too**, not only in the stylesheet —
   the snippet may be dropped into a grid column that does not inherit them.
4. **Starter chips are placeholders in the snippet.** Real conversation starters are
   injected at runtime by the `DS_ChatContext_Create_*` datasource via
   `SuggestedUserPrompt_Create`, so they can differ per page. Hardcoding them in the snippet
   means they never change.

**Known mxcli limit:** `CE0115` blocks `snippetcall` parameter wiring. If the snippet needs a
parameter, exec with a placeholder container and patch the `snippetcall` in over MCP after.

→ `skills/agents-examples/agent-snippet.example.mdl`

### 4. Placement — MCP, not MDL

Putting the panel on a page is a page *patch*, not a page *create*, and `pg_patch_page` over
MCP is the tool for it. The recurring shape:

```
mainGrid row 0 column 0   weight 12 → 8
mainGrid row 0 column 1   NEW, weight 4
  └── .copilot
        ├── .c-head
        └── .c-body
              └── DataView → AIAssistant.DS_ChatContext_Create
                    └── SnippetCall → ConversationalUI...Bubbles
```

Then `ped_check_errors` → expect 0, then save. **Record every patch as a comment-only `.mdl`
file** next to the runnable scripts: what changed, which pages, verification result, commit.
The patch itself is not replayable, but the record is the only description of the page's
intended state — and it is where you log what you could not do.

Example of the last part, worth copying as a habit:

> *Deferred — hide toggle. Requires a page local variable (`showCopilot: Boolean`, default
> true) + `ConditionalVisibilitySettings.expression` on the sidebar column + an action button
> in `.c-head` calling `NF_ToggleCopilot`. Cannot be set via `pg_patch_page` (no
> `visibilityCondition` in the schema). Needs `ped_update_document` with widget `$ID`s — logged
> as a separate task.*

### 5. Getting the page's context into the model

The panel can render perfectly, the agent can answer fluently, and the conversation can
still know nothing about the record on screen. That failure looks like a *quality* problem
("the agent gave a shitty answer", "it asked me which part I meant") rather than a wiring
problem, so it survives every check in the list above. Four things decide whether the
context arrives.

**Messages you create are not messages the model sees.** `ConversationalUI.Message_Create`
creates without committing, and `ConversationalUI.Request_CreateFromChatContext` builds the
request from a *database retrieve* over `ConversationalUI.Message`. An uncommitted context
message is therefore invisible to the very request it was written for — no error, no log
line, just an agent answering with no idea what page it is on. Any message that must reach
the model is followed by `ConversationalUI.Message_Commit`.

**Do not put context in a `system`-role message.** Committing one makes it worse, not
better: the provider rejects the whole request —

```
400 … messages: Unexpected role "system". The Messages API accepts a top-level
`system` parameter, not "system" as an input message role.
```

— and the panel renders a bare `Error` bubble for every question. Page context belongs in
the **system prompt**, not the message list.

**Append to the chat's own ProviderConfig, not to the agent.**
`AgentCommons.ChatContext_Create_ForAgent` creates a `ProviderConfig` *per chat context*
(one project: 92 configs against 90 contexts), so

```
retrieve $ProviderConfig from $ChatContext/ConversationalUI.ChatContext_ProviderConfig_Active;
change $ProviderConfig (SystemPrompt = $ProviderConfig/SystemPrompt + ' Context for this conversation: ' + $ContextMessage);
commit $ProviderConfig without events;
```

scopes the context to this one conversation and leaves the agent's stored configuration
untouched. Log a warning on the empty branch — a chat with no active ProviderConfig will
answer context-blind and nothing else will say so.

**The ActionMicroflow decides whether that append is read at all.** The two stock handlers
take the system prompt from different places:

| ActionMicroflow | System prompt comes from | Per-chat context |
|---|---|---|
| a handler built on `ConversationalUI.ChatContext_Preprocessing` | the chat's **ProviderConfig** | reaches the model |
| `AgentCommons.ChatContext_ChatWithHistory_ActionMicroflow_AgentBuilder` | `$PromptToUse/SystemPrompt` on the agent **Version** | silently ignored |

Both call `Request_AddAgentCapabilities`, so tools and knowledge bases stay attached either
way — the handler choice costs you the page context and nothing visible. Two panels wired to
two different handlers will disagree about what they know while looking identically healthy.
After switching a handler, re-run the KB-grounding probe: the tools survive the switch in
principle, but "in principle" is what this whole section is about.

**Probe by reading the reply, never by counting bubbles.** A bubble count passes over an
empty bubble, an `Error` bubble, and a fluent answer about the wrong record alike. The probe
that finds these defects types a question whose answer *requires* the page context, waits for
the text to stabilise, and prints the reply in full for a human to judge. Discover the panels
by class stem (`[class*="mx-name-dvGraphChat"]`) rather than a hardcoded widget-name list —
panel names carry per-page suffixes, and a stale suffix reads as "the panel is missing",
which hides the defect you are hunting.

## Where the panel goes

Overview pages take an 8 / 4 split. Dashboards take a fixed-height panel (~420px) in a top
row so it does not stretch with the content below. Detail pages reuse the same snippet with
a different subtitle — per-page subtitle text, per-page starters from the datasource, one
snippet.

## Checklist

- [ ] Wireframe exists and the snippet was built against it
- [ ] `.copilot` CSS is all tokens, in the shared stylesheet
- [ ] Wireframe CSS and app CSS diffed for drift
- [ ] `.c-body` has `flex:1; min-height:0` — inline *and* in CSS
- [ ] No static `.c-foot` in the live snippet
- [ ] `chat-dataview--display-contents` on the DataView
- [ ] Starters come from `SuggestedUserPrompt_Create`, not hardcoded
- [ ] Page context reaches the model: in the chat's ProviderConfig system prompt, not an uncommitted or `system`-role message
- [ ] The panel's ActionMicroflow is one that reads the ProviderConfig prompt
- [ ] Proven by a probe that prints the reply text, not a bubble count
- [ ] `ped_check_errors` → 0 on every patched page, then saved
- [ ] Each MCP patch recorded as a comment-only `.mdl`, deferrals included
