# StyleGallery — client-free reference set

A complete, ready-to-copy StyleGallery (see `skills/learned-stylegallery.md`) built against
one invented domain — a purchase-request app with a supplier catalogue — so it carries no
client name, brand, or project-specific content. Everything here is copy-in reference: MDL
you can execute against your own project, and a matching static showcase you can open in a
browser with nothing running.

## What's here

```
stylegallery/
├── ds.css                       — brand-neutral stylesheet (three-tier tokens)
├── design-system.html           — static showcase, loads ds.css, no external assets
└── mdlsource/gallery/           — the in-app StyleGallery module, numbered exec order
    ├── 00-module.mdl
    ├── 05-demo-data.mdl
    ├── 11-buttons.mdl
    ├── 12-form-controls.mdl
    ├── 13-badges-chips.mdl
    ├── 14-kpi-tiles.mdl
    ├── 15-data-grid.mdl
    ├── 15b-cards-lists.mdl
    ├── 16-process-stepper.mdl
    ├── 17-dialog-toast.mdl
    ├── 18-breadcrumbs.mdl
    ├── 19-ai-copilot.mdl
    └── 90-gallery-home.mdl
```

`ds.css` and the MDL snippets share one class contract — every class a snippet references is
defined in `ds.css`, and nothing in `ds.css` goes unused. See the header comment in `ds.css`
for the full list, grouped by component family.

## Exec order — 90 MUST run last

Numbering is the dependency order, not a suggestion:

1. `00-module.mdl` — creates the `StyleGallery` module and its `Viewer` module role.
2. `05-demo-data.mdl` — non-persistent demo entities + datasource microflows every later
   snippet's real widgets bind to. Nothing renders without this.
3. `11` through `19` (plus `15b`) — one component-family snippet each, in any order relative
   to one another, but all after `05`.
4. `90-gallery-home.mdl` — **last, always**. It `snippetcall`s every snippet from step 3; run
   it before they exist and the references fail to resolve.

Run each against your project with the toolkit's safe exec wrapper, one file at a time and in
that order:

```bash
./bin/exec.sh mdlsource/gallery/00-module.mdl
./bin/exec.sh mdlsource/gallery/05-demo-data.mdl
./bin/exec.sh mdlsource/gallery/11-buttons.mdl
./bin/exec.sh mdlsource/gallery/12-form-controls.mdl
./bin/exec.sh mdlsource/gallery/13-badges-chips.mdl
./bin/exec.sh mdlsource/gallery/14-kpi-tiles.mdl
./bin/exec.sh mdlsource/gallery/15-data-grid.mdl
./bin/exec.sh mdlsource/gallery/15b-cards-lists.mdl
./bin/exec.sh mdlsource/gallery/16-process-stepper.mdl
./bin/exec.sh mdlsource/gallery/17-dialog-toast.mdl
./bin/exec.sh mdlsource/gallery/18-breadcrumbs.mdl
./bin/exec.sh mdlsource/gallery/19-ai-copilot.mdl
./bin/exec.sh mdlsource/gallery/90-gallery-home.mdl
```

(`exec.sh` snapshots the `.mpr` first and validates with mxbuild after — see the consuming
project's own `CLAUDE.local.md` for the safe-exec convention if it isn't wired up yet.)

After `90`, `Gallery_Home` exists but is **not wired into navigation** on purpose — a
`create or replace navigation` here would overwrite whatever navigation profile the
consuming project already has. Add it to a navigation profile yourself and grant
`StyleGallery.Viewer` to a role a real demo user holds — see `learned-stylegallery.md`'s
Step 5b gate, items 3 and 4, for what "wired" means before calling this done.

## Adapting the tokens for a real brand

Open `ds.css` and edit only the **Tier 1: PRIMITIVE** block at the top — the grey ramp, the
one accent hue, the status hues, the spacing/radius scale. Every component rule below it
reads from **Tier 2 (semantic)** and **Tier 3 (component)** variables, which themselves point
back at Tier 1 — so changing the primitives re-colours everything without touching a
component rule. Do not hand-edit Tier 2/3 values directly; that's how a real project's
`ds.css` drifts from its own class contract over time (a drift this set specifically avoided
by being authored fresh against its own final MDL, not copied from a prior project's files).

Bring the same palette into the Mendix side by mirroring the Tier 1 values into
Atlas_Core's own design properties / `styles/web/` variables, per `design-artifacts.md`.

## Field run

Executed end to end on 2026-09-15 against a blank `mxcli new` scaffold (Mendix 11.13.0,
mxcli v0.21.0): all 13 files, in the order above, each passing `mxcli check --references`
against the `.mpr` as it stood after the previous file, then `exec`. Native validation
(`mx check -w -d -b` from `mxcli setup mxbuild`) reported **0 errors in `StyleGallery`**
after one fix — the KPI tile's `DynamicClasses` expression used a bare attribute name
(`if TrendDir = ...`), which `mxcli check` accepts and `mx check` rejects with CE0117; the
`$currentObject/` prefix rule is `learned-mdl-preflight.md` STOP item 12, and that run is
exactly why the rule exists. Result: 1 page (`Gallery_Home`) whose 12 snippet calls all
resolve, 12 snippets, 4 entities, 7 microflows. The remaining warnings in that run were all
scaffold noise (Atlas templates, NanoflowCommons version), none in `StyleGallery`.

Not yet done: nobody has opened `Gallery_Home` in a running app and compared it to
`design-system.html`. That side-by-side is Step 5b's fourth gate item ("someone visually
verified") and is still owed by whoever copies this set into a real build.

## Where the material came from

Harvested from two field projects and rewritten from scratch onto one invented purchase
-request domain — no project name, brand colour, font, hostname, or file path survives from
either source; the class *shapes* (three-tier tokens, `.btn`/`.badge`/`.kpi`/`.dg-*`/`.step`/
`.crumb-*`/`.toast` families) are the reusable pattern, not any specific line of CSS or MDL.
