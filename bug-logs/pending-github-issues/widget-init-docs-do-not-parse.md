**Repo:** `mendixlabs/mxcli`
**Source:** field build on mxcli **v0.20.0** (2026-08-28 build), Mendix 11.12.1, Linux container
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1036 (2026-09-04)
**Severity:** Medium — no corruption, no data loss; it costs a feature and a lot of time, and it
sends the reader to a labelled gap by way of a document that told them the opposite.

---

# `mxcli widget init` generates MDL examples that the parser rejects

## Summary

`mxcli widget init` writes one markdown doc per widget into
`app/.ai-context/skills/widgets/`, explicitly for LLM consumption. For a pluggable widget those
docs contain three sections — **MDL Example**, **Child Slots (curly-brace blocks)** and
**Object Lists (repeating child entries)** — all of which describe a `PLUGGABLEWIDGET ... { ... }`
form with keywords inside the braces.

**No keyword documented for that body parses on v0.20.0.** The grammar accepts a pluggable
widget only as `pluggablewidget '<id>' <name> ( <scalar properties> )`, with no body at all.

The practical consequence: any pluggable-widget property that is a **list of objects** is
unreachable from MDL, and the generated documentation is what tells you it is reachable.

## Reproduce

Any project with the HTML Element widget available. `mxcli widget init -p app.mpr` first, then
put each of these inside a `create or replace page ... { container c { … } }` and run
`mxcli diff -p app.mpr probe.mdl` (read-only — no exec needed, this is a parse failure):

```sql
-- 1. Baseline: properties in parens, no body — PARSES
pluggablewidget 'com.mendix.widget.web.htmlelement.HTMLElement' pw (tagName: 'div')

-- 2. Documented child slot — PARSE ERROR
pluggablewidget 'com.mendix.widget.web.htmlelement.HTMLElement' pw (tagName: 'div') {
  tagcontentcontainer { dynamictext t (Content: 'x') }
}
--   line N:6 mismatched input 'tagcontentcontainer' expecting '}'

-- 3. Documented object list — PARSE ERROR
pluggablewidget 'com.mendix.widget.web.htmlelement.HTMLElement' pw (tagName: 'div') {
  attribute a (attributeName: 'title', attributeValueType: 'template', attributeValueTemplate: 'x')
}
--   line N:6 mismatched input 'attribute' expecting '}'

-- 4. Documented object list, events — PARSE ERROR
pluggablewidget 'com.mendix.widget.web.htmlelement.HTMLElement' pw (tagName: 'div') {
  event e (eventName: 'onClick')
}
--   line N:6 mismatched input 'event' expecting '}'
```

Every body form fails identically: the parser wants `}` where the generated doc puts a keyword.

## What the generated doc says

`app/.ai-context/skills/widgets/htmlelement.md`, written by `widget init` itself:

```
## MDL Example

PLUGGABLEWIDGET 'com.mendix.widget.web.htmlelement.HTMLElement' widget1 {
  tagcontentcontainer {
    -- widgets for `tagContentContainer`
  }
  attribute item1   -- one entry of `attributes`
  event item1   -- one entry of `events`
}

## Child Slots (curly-brace blocks)
| MDL keyword | Widget property |
| `tagcontentcontainer` | `tagContentContainer` |

## Object Lists (repeating child entries)
### `attribute` → property `attributes`
```

Note also that `widget init --help` mentions `objectLists` as a field newer versions emit — so
the doc generator knows about object lists; the grammar appears not to.

## Why it cost a feature

The build needed the platform HTML Element as a **sandboxed iframe**: `tagName: '__customTag__'`
+ `tagNameCustom: 'iframe'`, with `sandbox='allow-scripts'` (deliberately WITHOUT
`allow-same-origin`) and `srcdoc` bound to an attribute. `sandbox` and `srcdoc` are entries in
the `attributes` object list, so on v0.20.0 there is no way to set them.

The only same-file alternative, `tagContentMode: 'innerHTML'` with `tagContentHTML`, is a
**scalar** property and does parse — but it executes the uploaded document same-origin inside the
Mendix page, where its JS can reach client APIs as the signed-in user. That is precisely the
regression the sandbox exists to prevent, so it was refused and the screen ships a labelled gap.

The time cost came from the docs. Two separate sessions concluded "MDL cannot express this",
then re-opened it after reading `htmlelement.md` and believing the feature was available,
then closed it again after probing. A generated document that does not parse is worse than no
document: it is authoritative-looking, it is written specifically for an agent to follow, and it
is on disk from the first `widget init`.

## Suggested fix, in preference order

1. **Implement the body grammar** the docs already describe (`tagcontentcontainer`, `attribute`,
   `event`). This is the fix that unblocks pluggable widgets generally — object-list properties
   are common (Data Grid 2 columns, Charts series, HTML Element attributes).
2. If that is not near-term, make `widget init` **emit only what the current grammar accepts**,
   and state plainly in the doc that object-list and child-slot properties cannot be set from
   MDL on this version, naming the workaround (Studio Pro, or MCP).

(1) and (2) are not exclusive — shipping (2) now would stop the docs from misdirecting readers
while (1) is built.

## Environment

- mxcli `v0.20.0` (2026-08-28T13:22:53Z)
- Mendix 11.12.1, mxbuild `~/.mxcli/mxbuild/11.12.1`
- Linux container, no Studio Pro
- `mxcli widget init -p app.mpr` reports: `0 new, 0 refreshed, 33 up to date, 9 skipped (built-in or unparseable)`, `Generated 42 widget docs`

## Related, same session, possibly the same root

`mxcli widget init` **skips built-in widgets** (the "9 skipped" above). The platform
**FileUploader** (`com.mendix.widget.web.fileuploader.FileUploader`) is among them: it has no
generated doc and no definition, so `exec` fails with `no definition for widget ...
(run 'mxcli widget init -p app.mpr')` — advice that cannot help, because the widget ships inside
Studio Pro rather than in the project's `widgets/*.mpk`. That blocked a file picker on the same
build. Worth filing separately if the maintainers prefer; it is recorded here because a reader
hitting one will hit the other.
