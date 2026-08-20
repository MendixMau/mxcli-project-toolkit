# Skill: Binding Text Inside a DataGrid customContent Column

**Applies to:** any mxcli project. Use when writing MDL for a `datagrid` column with
`ShowContentAs: customContent` and want to display a value — a status badge, a formatted
field, anything bound to the row object. Read this **before** writing the widget.

**Status:** confirmed on Mendix 11.12.0 / mxcli v0.16.0, 2026-07-30, by observing the
Studio Pro error pane before and after. Not confirmed by `mxcli check` — see the trap below.

---

## The rule

Inside a customContent column, bind with **`Attribute:`**. Never put an **expression**
inside `ContentParams:`.

```sql
-- ❌ BROKEN — CE1613 "attribute … no longer exists" at build
dynamictext txtLifecycleBadge (
  Content: '{1}',
  ContentParams: [{1} = toString($currentObject/Lifecycle_state)],
  Class: 'badge badge-info'
)

-- ✅ WORKS
dynamictext txtLifecycleBadge (
  Attribute: Lifecycle_state,
  Class: 'badge badge-info'
)
```

`Attribute: X` is the documented shorthand for `Content: '{1}', ContentParams: [{1} = X]`
(`.ai-context/skills/create-page.md`). The difference that matters is that it is a **plain
attribute reference, not an expression** — mxcli serialises an expression as if it were an
attribute path, and mxbuild then cannot resolve it.

**The `toString()` wrapper is the trigger**, not the `$currentObject/` prefix. Dropping only
the prefix does not help. And `toString()` was never needed: a `dynamictext` bound to an
**enumeration** renders its caption automatically.

## Why it bites specifically in customContent

A customContent column is the only place on a typical list page where a widget must reference
the *row* object. Everywhere else the value is either a static literal or a plain column
`Attribute:`. So `$currentObject/…` expressions — and therefore this defect — cluster there.
If a page throws CE1613 on a list screen, look in the customContent columns first.

## The trap: `mxcli check` passes, and so does read-back

Two instruments lie about this, in different ways:

1. **`mxcli check` and `--references` both pass** on the broken form. A green check is not
   evidence. The failure appears only at build time.
2. **`DESCRIBE PAGE` renders a NORMALISED form.** After writing the *correct* `Attribute:`
   version, `DESCRIBE PAGE` prints it back as
   `Content: '{1}', ContentParams: [{1} = toString($currentObject/Lifecycle_state)]` —
   byte-identical to the broken version. **Read-back therefore cannot tell you which form is
   stored.** I concluded from this that the fix was a no-op; it was not. The only instrument
   that distinguishes them is the Studio Pro error pane (or mxbuild).

This is a concrete instance of `skills/tool-output-is-not-ground-truth.md`: two mxcli surfaces
agreed with each other and both were uninformative.

## Do not repair it with ALTER PAGE

Never `REPLACE` a datagrid column to reach a widget inside it — the column loses its
datasource. Fix the source script and regenerate the module. If the module already exists,
`drop module` then re-exec; that is cheaper and safer than surgery on the page.

## Limitation

`Attribute:` cannot express a **multi-placeholder** template (`'{1} — {2}'`). When you need
one, split it into two single-binding widgets rather than reaching back for `ContentParams`.
A two-widget header is a smaller price than a build error you cannot see coming.

Related: `mendix-write-modes.md` (which lists ContentParams expressions as MCP-only — that
entry predates this finding and should be revisited, since `Attribute:` makes the common case
CLI-authorable), `mxcli-alter-page-observations.md`, `skills/tool-output-is-not-ground-truth.md`,
`skills/oneshot-page-structure-patterns.md` (same silent-failure class, one layer up — container
orientation instead of column binding).
