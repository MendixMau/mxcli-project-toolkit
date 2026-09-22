**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-141` — found 2026-09-22 building a supplier-portal
comparison page on a requirements-driven RFQ project (Mendix 11.14.0)
**Status:** NOT YET FILED — fix ready on fork branch `MendixMau/mxcli:fix/alter-page-set-rendermode`
(fork PR MendixMau/mxcli#1); companion `bug141-fix-README.md` has the PR package
**Suggested labels:** bug, alter-page

---

**Title:** `ALTER PAGE … SET RenderMode` is refused on a dynamic text, though `CREATE PAGE` writes it

**Body:**

## Summary

`RenderMode` is how a dynamic text becomes a heading (`H1`–`H6`) or a paragraph. `CREATE PAGE`
writes it (`dynamictext x (Content: 'Title', RenderMode: H1)`), `DESCRIBE PAGE` round-trips it, and
the MCP backend's page mutator already sets it — but the MPR backend's `ALTER PAGE … SET` refuses
it, so fixing one heading level means replacing the whole widget.

## Environment

- mxcli main at `31eee45` (also seen on v0.21.0)
- Mendix **11.14.0**
- Linux container

## Repro

```sql
alter page MyModule.SomePage {
  set RenderMode = H2 on txtTitle      -- txtTitle is a DYNAMICTEXT
};
```

**Actual:**

```
failed to set RenderMode on txtTitle: property "RenderMode" not found (widget has no pluggable Object)
```

(on current main the refusal is worded as "not a property of this built-in widget … use alter
styling" — which is also wrong: RenderMode is not a design property).

**Expected:** `Altered page`, and `describe page` shows `RenderMode: H2`.

**Workaround:** `replace txtTitle with { dynamictext txtTitle (Content: '…', RenderMode: H2) }` —
which means restating the content, its parameters and its class just to change one enum.

## Root cause

`setRawWidgetPropertyMut` in `mdl/backend/pagemutator/mutator.go` handles a fixed list of built-in
properties and sends everything else to the pluggable-widget setter. `RenderMode` is not on the
list, so it falls through and fails. `mdl/backend/mcp/page_mutator.go` already handles it — the
two property lists have drifted.

## Proposed fix

Add a `rendermode` case that applies only to a dynamic text (`Forms$DynamicText`), accepts
`Text | Paragraph | H1..H6` case-insensitively, stores the canonical spelling, and names the
allowed set on any other value or widget. A fix with tests and docs is ready; happy to open the PR
once this is approved.

**Out of scope (separate issues if wanted):** `set Content` / `ContentParams` on a dynamic text
(parser-level), `RenderMode` on a container, `RenderType` on a button.
