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

## Four layers, in order

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
- [ ] `ped_check_errors` → 0 on every patched page, then saved
- [ ] Each MCP patch recorded as a comment-only `.mdl`, deferrals included
