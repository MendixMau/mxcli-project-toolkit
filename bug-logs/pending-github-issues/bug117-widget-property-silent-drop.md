**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-117: Widget-property writer silently drops any
unsupported property name, on any widget type, with no MDL-WIDGET07 warning` (discovered
2026-08-25, ToeicBuddy-conversion field run)
**Status:** NOT YET FILED — retest on v0.20.0 first (found on a pre-v0.20.0 build, 2026-08-25); when filing, cite mendixlabs/mxcli#928, whose 0.19.0 release note names the widget-type-agnostic `isBuiltinPropName` allow-list as the root cause and fixed only `editable`/`contentparams`
**Note:** discovered and confirmed live during an active field run of the mxcli conversion
pipeline (not a synthetic repro built after the fact). Both cases below were hit while trying to
fix the same real page, one after the other, which is what made the pattern (not an isolated
one-off) visible.

---

**Title:** Widget-property writer silently drops unsupported property names instead of emitting MDL-WIDGET07 (confirmed on LISTVIEW paging properties and the GALLERY shorthand's own documented properties)

**Body:**

## Summary

Writing a property name a widget's real schema does not support round-trips clean through every
mxcli-side check (`mxcli check --references`: "Check passed!", zero warnings — specifically no
MDL-WIDGET07) and `mxcli exec` reports success. The property is simply absent from the
persisted `.mpr`, confirmed via `DESCRIBE PAGE`. Even the real, flagless `mx check` (Studio
Pro's own build checker) reports 0 errors, since an absent property isn't a build error by
itself — it just silently doesn't do what the script asked for.

Two independent, confirmed cases against the same page:

1. **LISTVIEW** accepts `PageSize`/`Pagination`/`PagingPosition` (documented in mxcli's own
   `create-page/reference/widgets.md` "Paging Properties" table, but *only* under `###
   DATAGRID Widget` — LISTVIEW has no such properties in its real schema at all). After exec,
   only `PageSize` persists; `Pagination`/`PagingPosition` vanish with no warning.
2. **GALLERY shorthand** accepts `PageSize`/`Pagination`/`PagingPosition` (not documented for
   GALLERY at all) *and* `DesktopColumns`/`TabletColumns`/`PhoneColumns` (which mxcli's own
   `### GALLERY Widget` doc section does document) — none of the six persist. `mxcli widget
   describe gallery -p <project>.mpr` shows the real underlying pluggable-widget schema keys
   are `pageSize`/`pagination`/`pagingPosition`/`desktopItems`/`tabletItems`/`phoneItems` —
   different names than the shorthand grammar accepts/documents.

## Environment

- mxcli: `39c7d94` (`2026-08-25T06:09:00Z`)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux (container), x86_64

## Reproduction

```sql
create module "BUG96";
/
create persistent entity "BUG96"."Item" (
  "Name": string
);
/
create page "BUG96"."Page_List" (
  title: 'List',
  layout: Atlas_Core.Atlas_Default
) {
  listview lvItems (
    datasource: database "BUG96"."Item",
    PageSize: 1,
    Pagination: buttons,
    PagingPosition: bottom
  ) {
    dynamictext txtName (content: '{1}', ContentParams: [{1} = Name])
  }
}
/
```

```bash
./mxcli check bug96-repro.mdl                    # => Syntax OK, Check passed! (no MDL-WIDGET07)
./mxcli exec bug96-repro.mdl -p EmptyTest.mpr    # => reports success on every statement
./mxcli -p EmptyTest.mpr -c "DESCRIBE PAGE BUG96.Page_List"
#   -> only PageSize: 1 appears on lvItems; Pagination/PagingPosition are absent entirely
~/.mxcli/mxbuild/*/modeler/mx check EmptyTest.mpr
#   -> The app contains: 0 errors.   (no signal anything is wrong)
```

The GALLERY case is structurally identical — swap `listview`/`dynamictext` for a `gallery (...)
{ template t { dynamictext ... } }` block using `DesktopColumns`/`TabletColumns`/`PhoneColumns`/
`PageSize`/`Pagination`/`PagingPosition` — and compare against
`mxcli widget describe gallery -p EmptyTest.mpr`'s real schema key names.

## Expected behavior

Either the property is written correctly (if the widget genuinely supports it, mapped to
whatever the real internal schema key is), or `mxcli check` emits **MDL-WIDGET07** — the
warning `create-page/SKILL.md` already documents as existing for exactly this situation ("a
built-in widget carries an unrecognized property ... it would otherwise be silently dropped on
write").

## Actual behavior

The property is silently accepted by the grammar and silently dropped by the writer, with zero
warning at any check stage (`mxcli check --references`, `mxcli exec`, or the real `mx check`).

## Root cause (inferred)

MDL-WIDGET07's unsupported-property detection appears to be scoped to a subset of
widgets/properties rather than validating every written property against the target widget's
actual resolved schema (the same data `mxcli widget describe` reads). LISTVIEW and the GALLERY
shorthand both fall outside whatever set is currently checked.

## Severity

**Medium.** Does not corrupt the project or crash the build (unlike BUG-20), but silently
produces a page that does not do what its own source script says it does, with every available
mxcli-side and real-build check reporting success — this is exactly the kind of defect a
snapshot/gate/screenshot discipline is needed to catch, and a project without that discipline
would ship the broken behavior undetected.

## Workaround

For a pluggable widget, use `update widgets set '<realSchemaKey>' = <value> where name =
'<widgetName>' in <Module>` against the real schema key (from `mxcli widget describe`) instead
of the shorthand property name. No workaround exists for a genuinely native widget (e.g.
LISTVIEW) that lacks the capability in its real schema at all — pick a different widget type.

## Suggested fix

Validate every property name written to every widget type — shorthand or pluggable — against
that widget's actual resolved schema at write time, and emit MDL-WIDGET07 (or fail) for any
name that doesn't match, rather than scoping the check to a subset of widgets.
