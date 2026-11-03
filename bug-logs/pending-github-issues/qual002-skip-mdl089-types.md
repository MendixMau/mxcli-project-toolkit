Repo: mendixlabs/mxcli
Source: toolkit issue #246; `bug-logs/mxcli-bugs.md` (published REST services section, item 4)
Status: **NOT FILED.**

--- everything above this line is stripped before filing ---

**Title:** QUAL002 asks for documentation on document types MDL cannot document (MDL089)

## Environment

- mxcli **v0.25.0** (measured), v0.26.0 rule text unchanged on this point

On one project 45 QUAL002 findings: ImportMapping 29, JavaAction 11, PublishedRestService 2,
Page/ImageCollection/JsonStructure 3. For published REST services and import mappings a `/** */`
comment cannot store documentation:

```
⚠ the doc comment before `create or modify published rest service … "ServiceBulletins"` is lost: that statement cannot store documentation, so the comment is ignored; the next statement that can take it is `create or modify microflow …` [MDL089]
```

Without the warning the comment lands on the next microflow and overwrites its documentation. In an
mxcli-only workflow those findings can only be closed in Studio Pro.

Asks:
1. For the MDL089 set, change the suggestion to "document it in Studio Pro (MDL cannot store documentation here, MDL089)", or report at a lower severity.
2. Better: let MDL store documentation on these types.

Today's workaround: the per-kind options `check_import_mappings` / `check_published_rest_services` set to `false` in `lint-config.yaml`.
