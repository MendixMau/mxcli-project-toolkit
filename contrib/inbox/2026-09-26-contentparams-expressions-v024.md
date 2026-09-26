# ContentParams on mxcli v0.24: only a bare attribute or a quoted literal builds — preflight row 12 is outdated

**From:** card-disbursement requirements-driven build (gallery row 2.14a)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** two execs of a list-view snippet failed CE1613 at mxbuild with `mxcli check --references` green; then a five-form probe on a scratch copy of the model, `mx check` 11.13.0, mxcli v0.24.0 (f18c307) — output below.
**Proposed target:** `skills/learned-mdl-preflight.md` row 12; `skills/learned-detection-gaps.md` line 47 (the "customContent column" scope is too narrow — it is any dynamictext in an object context); `bug-logs/mxcli-bugs.md` as a BUG-23 variant (BUG-23's v0.21 retest covered the `$currentObject/` prefix only)

---

Finding (reproduced, not a hypothesis):

| ContentParams value | `mxcli check --references` | mxbuild (`mx check`) |
|---|---|---|
| `CaseRef` (bare attribute) | clean | clean |
| `'literal'` | clean | clean |
| `toString(CreditLimit)` | **error**: "looks like an expression, and MDL cannot author an expression-typed template parameter yet — an unquoted value is stored as an attribute" | CE1613 |
| `toString($currentObject/CreditLimit)` | **error** (same) | CE1613 |
| `if IsUrgent then 'x' else 'y'` | **clean — check is blind** | CE1613 |

Verbatim mxbuild:

```
[error] [CE1613] "The selected attribute 'StyleGallery.SampleCase.toString(CreditLimit)' no longer exists." at Text 'txtA'
[error] [CE1613] "The selected attribute 'StyleGallery.SampleCase.toString($currentObject/CreditLimit)' no longer exists." at Text 'txtB'
[error] [CE1613] "The selected attribute 'StyleGallery.SampleCase.ifIsUrgentthen'x'else'y'' no longer exists." at Text 'txtE'
```

`describe snippet` prints the if-form with its whitespace stripped (`{1} = ifIsUrgentthen'x'else'y'`) —
the one visible tell before mxbuild.

Source reading (v0.24.0): `mdl/visitor/visitor_page_v3.go:1232` takes `expr.GetText()` (ANTLR joins the
tokens without whitespace); `mdl/executor/cmd_pages_builder_v3_widgets.go:836-846` sends every
unquoted value to `resolveTemplateAttributePathFull`. So there is no expression-typed parameter at all;
check's refusal is a heuristic that keys on the parenthesis.

What is now wrong in the toolkit:
- `learned-mdl-preflight.md` row 12 — "Function calls themselves are fine; the prefix is the trigger" and
  the fix `ContentParams: [{1} = toString(Attr)]`. On v0.24 check refuses that fix and mxbuild fails it.
- `learned-detection-gaps.md` line 47 — scoped to "inside a customContent column"; the gap is any
  dynamictext in an object context, and check now catches the parenthesised forms but not `if`.

Workaround used: make the per-row label data (a seeded/derived String attribute bound as a bare
attribute); tone variants go in `DynamicClasses`, which does take an expression.
