**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-dg2-association-path-bindings` — found 2026-09-25 (field report on v0.23.0; `check` half re-verified on v0.24.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, pages, datagrid, check
**Duplicate check:** searched 2026-09-25 (`datagrid column quoted association path CE1613`, `sort by association attribute datagrid`). Related, closed: #830 (unquoted association column), #1152 (sort over association round-trip); fe5a7408e (unreleased) lets a sort column name its association. No issue found for the **quoted** column path. Before filing, check whether fe5a7408e also covers the DataGrid 2 `sort by` form; if so, file the column half only.

---

**Title:** DataGrid 2: a quoted association path in a column `Attribute:` is stored as one attribute named `Assoc/Attr`; `check` passes, the build fails with CE1613

**Body:**

## Summary

`Attribute: "Assoc_A_B/Name"` (quoted) on a DataGrid 2 column is stored as a single attribute whose name contains a slash. The unquoted form is stored as a path. `check --references` passes both, and the quoted one fails at build with CE1613. The generated project `CLAUDE.md` tells agents to "always quote identifiers … always safe", so agents that follow it hit this on every association column. The same applies to `sort by Assoc/Attr` on the grid's database source: it passes `check` and is written as a plain attribute of the grid entity (CE1613).

**Version:** field run on mxcli v0.23.0 / Mendix 11.12.4 (build results); `check` behaviour re-verified on v0.24.0.

## Repro

```
create page ModuleA.EntityA_Grid (Title: 'Grid', Layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (DataSource: database ModuleA.EntityA sort by "Assoc_A_B/Name" asc) {
    column colQ (Attribute: "Assoc_A_B/Name", Caption: 'Quoted')
    column colU (Attribute: Assoc_A_B/Name, Caption: 'Unquoted')
  }
};
```

## Measured

- v0.24.0 `check --references`: `Check passed!`, with an MDL-WIDGET16 info line deriving the column names as `colQ → "Assoc_A_B/Name", colU → Assoc_A_B/Name`. The quotes survive into the stored name.
- v0.23.0 build (field): the quoted column gives CE1613, and the unquoted column builds. `sort by Assoc/Attr`, unquoted or quoted, gives CE1613. The fully qualified `Module.Assoc/Module.Entity/Attr` sort form does not parse.

## Expected

A quoted identifier that contains `/` is either split into a path or rejected by `check`. A sort over an association is either authored as a path or rejected by `check`.

## Workaround

Write association paths unquoted. Sort by a local attribute, or use a microflow datasource.
