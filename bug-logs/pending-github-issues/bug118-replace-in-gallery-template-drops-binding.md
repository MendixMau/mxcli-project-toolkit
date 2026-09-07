**Repo:** `mendixlabs/mxcli`
**Likely duplicate of:** BUG-114 (`ALTER PAGE REPLACE` re-scopes
`ContentParams` to the outer data context, CE1613). Same write path, different wrong outcome —
dropped/`<unbound>` here versus re-scoped there. Check whether one fix covers both before filing
separately.
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-118: ALTER PAGE ... REPLACE targeting a widget
nested inside a GALLERY template's child slot drops the new widget's ContentParams/attribute
binding` (discovered 2026-08-25, ToeicBuddy-conversion field run)
**Status:** _not yet filed — staged for review before submission_
**Note:** unlike most entries in this folder, this defect WAS caught by the real `mx check`
gate (CE0402), not left silent — filing it anyway because the two mxcli-side checks
(`mxcli check --references`, `mxcli exec`) both reported success, so a project relying on those
alone (rather than the real, flagless `mx check`) would still ship it undetected.

---

**Title:** `ALTER PAGE ... REPLACE` on a widget nested inside a GALLERY template's child slot drops the new widget's ContentParams/attribute binding (`<unbound>`, real `mx check` CE0402)

**Body:**

## Summary

`alter page Module.Page { replace <widgetInsideGalleryTemplate> with { container c {
dynamictext d (Content: '{1}', ContentParams: [{1} = SomeAttr]) } } }` builds and executes with
no error from mxcli itself, but the real Studio Pro/mxbuild `mx check` fails with `CE0402
"No value specified."` on the new dynamictext. `DESCRIBE PAGE` confirms the binding was
dropped, not mis-resolved: `ContentParams: [{1} = <unbound>]`.

The equivalent REPLACE at the *top level* of a page (target is a direct child of the page body,
not nested inside a pluggable widget's template) correctly carries bindings through — confirmed
working in the same session, replacing a top-level LISTVIEW with a GALLERY. The defect appears
specific to a REPLACE target nested one level inside a pluggable widget's template/child-slot.

## Environment

- mxcli: `39c7d94` (`2026-08-25T06:09:00Z`)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux (container), x86_64

## Reproduction

```sql
create module "BUG97";
/
create persistent entity "BUG97"."Item" (
  "Name": string
);
/
create page "BUG97"."Page_Gallery" (
  title: 'Gallery',
  layout: Atlas_Core.Atlas_Default
) {
  gallery galItems (datasource: database "BUG97"."Item") {
    template t1 {
      container ctnCard {
        dynamictext txtName (content: '{1}', ContentParams: [{1} = Name])
      }
    }
  }
}
/
```

```bash
./mxcli exec bug97-setup.mdl -p EmptyTest.mpr    # create the baseline page above
```

Then apply the REPLACE that reproduces the defect:

```sql
alter page "BUG97"."Page_Gallery" {
  replace txtName with {
    container ctnWrap {
      dynamictext txtName2 (content: '{1}', ContentParams: [{1} = Name])
    }
  }
};
```

```bash
./mxcli check bug97-replace.mdl -p EmptyTest.mpr --references   # => Check passed!
./mxcli exec bug97-replace.mdl -p EmptyTest.mpr                 # => "Altered page", no error
./mxcli -p EmptyTest.mpr -c "DESCRIBE PAGE BUG97.Page_Gallery"
#   -> dynamictext txtName2 (Content: '{1}', ContentParams: [{1} = <unbound>])
~/.mxcli/mxbuild/*/modeler/mx check EmptyTest.mpr
#   [error] [CE0402] "No value specified." at Text 'txtName2'
#   The app contains: 1 errors.
```

Also tried, same result: `ContentParams: [{1} = $currentObject/Name]` (explicitly qualified
form) instead of the bare `Name` shown above — rules out attribute-rooting as the cause.

## Expected behavior

The new widget's `ContentParams` binding resolves against the GALLERY template's per-item data
context (`$currentObject`), the same way it does for a widget in the *original* template
(unaffected — only the REPLACE-introduced widget loses it) and the same way a top-level page
REPLACE already resolves bindings correctly.

## Actual behavior

The binding is dropped entirely (`<unbound>`), not mis-scoped to the wrong context — the
generated widget has no reference to the attribute at all, confirmed by reading the persisted
`.mpr` back via `DESCRIBE PAGE`.

## Root cause (inferred)

The `alter page ... replace` writer's binding-resolution logic appears to use a different code
path (or no path at all) when the REPLACE target is nested inside a pluggable widget's
template/child-slot, versus when the target is a direct child of the page body. An INSERT into
the same template context correctly resolves bindings (the original template's own widgets are
proof), so the gap is specific to REPLACE's handling of an existing nested target.

## Severity

**Medium.** Caught by the real `mx check` (not silent, unlike BUG-117), but silent through both
`mxcli check --references` and `mxcli exec` — a project gating only on mxcli's own checks (a
documented, seemingly reasonable workflow) would ship a broken page. Recovery is at least clean
once caught: `git checkout`/an `.mpr` snapshot restore, since the write is otherwise
self-contained.

## Workaround

Avoid REPLACE for any widget nested inside a pluggable widget's template if the replacement
carries a data binding. Use `alter page ... { set <Property> = ... on <existingWidgetName>; }`
against the already-existing, already-bound widget instead of constructing a new one via
REPLACE.

## Suggested fix

Use the same binding-resolution code path for a REPLACE target regardless of nesting depth or
whether it sits inside a pluggable widget's template — most likely by correctly propagating the
target's ambient item-level data context ($currentObject) into the new widget being written, the
way INSERT already does for the same template.
