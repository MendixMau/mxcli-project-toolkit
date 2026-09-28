# Fixture provenance — design-reaches-app

## Where the compiled stylesheets came from

`built-*.css` reproduce the STRUCTURE of a real `deployment/web/theme.compiled.css`
written by mxbuild 11.14.0 for a Mendix 11.14 app on Atlas 3 with
`$use-css-variables: true`. Captured 2026-09-09 from the field run that found the
defect this instrument exists for.

The structural facts the parser depends on are verbatim from that file, because every
one of them is a fact nobody would have imagined:

| Fact | Why the parser depends on it |
|---|---|
| `:root {` alone on its line, one declaration per indented line | the awk block reader keys on exactly this |
| a BARE `:root` and a SCOPED `:root.theme-neutral` both declaring `--brand-primary` | the scoped one appears LATER in the file. Reading "last occurrence" reports a correctly bound knob as unbound — measured, and it is the bug this fixture's `scoped-only` case pins |
| shades derived at runtime: `--brand-primary-600: color-mix(in srgb, var(--brand-primary), var(--color-contrast) 20%)` | why binding the ONE knob is sufficient, and why a check for a hardcoded default hex is the wrong check |
| the framework's own `:root` emitted BEFORE `theme/web/custom-variables.scss`'s | the cascade order that made a theme-module override lose |
| `/* Brand Colors */` comment lines inside the block | a comment line inside `:root` must not parse as a declaration |

**What was changed, and nothing else:** the colour LITERALS. The real file carries a
customer's sampled brand palette and this repository is public. Hex values are replaced
with `#AA1122` / `#00CC66` style placeholders. No line was reflowed, no block reordered,
no selector altered, no structure simplified.

## Counts asserted against the real file at capture time

| Measured on the real build | Value |
|---|---|
| lines in `deployment/web/theme.compiled.css` | 30,900 |
| design-system tokens defined in `design/ds.css` | 43 |
| design-system tokens present in the built sheet | 43 |
| design-system classes defined | 28 |
| design-system classes present in the built sheet, BEFORE the fix | 0 |
| framework knobs bound to a design token, BEFORE the fix | 0 of 35 |
| framework knobs bound to a design token, AFTER the fix | 29 of 35 |
| occurrences of `var(--brand)` in the built sheet, BEFORE the fix | 0 |

The 0-of-35 and 0-of-28 rows are the whole reason this instrument exists: both were true
while `mx check`, `mxcli lint`, the MDL suite and two e2e journeys were green.

## The two-tree layout (case 9), captured 2026-09-28

Case 9 builds its project in the shape of a real two-tree checkout, a Mendix 11.14.0 app
(mxbuild 11.14.0, Atlas 3, `$use-css-variables: true`) with the model under `app/`. The
paths, verbatim from that checkout:

| Path (relative to the repo root) | Holds |
|---|---|
| `design/ds.css` | the design system: tokens and classes |
| `mdlsource/` | the MDL scripts the WARN pass reads |
| `app/<Name>.mpr` + `app/mprcontents/` | the model |
| `app/theme/web/custom-variables.scss` | the framework knobs (664 lines, 35 uncommented declarations) |
| `app/themesource/<module>/web/` | theme modules |
| `app/deployment/web/theme.compiled.css` | the built sheet (1.2 MB) |

Measured there on 2026-09-28, with the built sheet passed by hand and nothing else:

| | Before the fix (knob file read from the root) | After the fix (no arguments at all) |
|---|---|---|
| knobs bound | **0 of 0** | **26 of 30** |
| tokens arrived | 157 of 157 | 157 of 157 |
| classes arrived | 239 of 269 | 239 of 269 |
| `$use-css-variables` | unknown (dead-bridge pass silently skipped) | true |
| verdict | `clean, 3 warning(s)`, exit 0 | `clean, 2 warning(s)`, exit 0 |

The 35 declarations include some that name no knob the built bare `:root` defines; those
drop out of the denominator. The "before" verdict is the defect: a pass that read nothing,
reported as clean.
