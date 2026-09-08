**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-122` — observed 2026-09-07 building script `87b`
of a topbar-titled portal project (Mendix 11.13.0)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1069 (2026-09-08)
**Suggested labels:** bug, mdl, alter-page, pluggable-widgets, datagrid2

---

**Title:** `ALTER PAGE … SET PageSize` fails with "pluggable property not found" on a DataGrid 2
that `CREATE` accepted the same property on

**Body:**

## Summary

The create path and the alter path resolve pluggable-widget property names from different
tables.

`create or modify page` accepts `PageSize: 20` on a `datagrid` widget and writes it — the grid
demonstrably paginates at 20 in the running app. `ALTER PAGE` rejects the same property name on
the same widget:

```
alter page Common.RunRegister { set PageSize = 10 on dgApprovalRuns };
→ Error: failed to set: failed to set PageSize on dgApprovalRuns:
  pluggable property "PageSize" not found
```

`mxcli check --references` passes the script clean. The failure appears only at exec.

## Environment

- mxcli **v0.20.0**
- Mendix **11.13.0**
- Linux container

## Aggravating factors

1. **mxcli is not transactional across statements.** The failing `set` aborted the script, so a
   second, unrelated statement behind it (a `dynamictext` `Content` change on a different page)
   never applied. A one-line property tweak leaves a two-page script half-done.
2. **`DESCRIBE PAGE` does not round-trip `PageSize` at all** — the property is absent from the
   dump — so the current value cannot be read back out of the model to confirm what was set.

## Impact

The workaround is to re-emit the entire page with `create or modify page`, changing only the one
value. On this project that turned a two-value edit into a 190-line script, and re-emitting a
page wholesale carries its own risk of drift against whatever else has touched it since.

## Expected

`ALTER PAGE … SET <prop>` accepts every property `create … (<prop>: …)` accepts on the same
widget type. Failing that, `check --references` should reject the unknown property so the failure
is caught before the model is touched.

## Related

MDL-WIDGET16 (DataGrid 2 stores no column names, so `ALTER PAGE` must address columns by derived
name). Same underlying cause: the DG2 pluggable-property surface exposed on create is not the
surface exposed on alter.
