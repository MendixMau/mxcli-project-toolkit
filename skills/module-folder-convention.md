# Module Folder Convention — where a document goes, decided before it is created
**Applies to:** any mxcli project.
**Purpose:** One layout for documents inside a module, decided in the module brief and applied by
the mdl-agent at `create` time — not discovered as a cleanup job months later.

## Why This Exists

Folder placement had a convention and no owner. `organize-project.md` (mxcli-shipped) described
functional grouping; `assess-quality.md` §B described a *different*, type-first `[objects]`/`[UI]`
layout and marked itself "Not automatically enforced". Neither was routed from `ROUTING.md`,
neither was asked for by `module-brief.md`, and `agents/mdl-agent.md` never mentioned folders. So
every `create` statement omitted the `folder` property, which is legal MDL and puts the document
at module root.

Measured on a live WMS conversion (2026-08-19, 12 project-owned modules): one module with **26
documents loose at module root**, another with 14, two with no folders at all, and three mutually
incompatible schemes among the modules that did have folders — while every *marketplace* module in
the same app was rigorously foldered. The tooling was never the obstacle: `folder '<path>'` is one
property on the statement that creates the document.

The failure mode is not untidiness. `modularize-domain.md` Step 3 answers "should this be a
separate module?" with **"no — one module, sub-areas as folders"**, and that answer is only sound
if the folders actually get made. A flat 26-document module is the outcome that skill exists to
prevent, reached by following its advice.

---

## The layout

**Feature group first, document type second.**

```
<Module>/
├── <FeatureGroup>/          a feature or aggregate root — RouteDefinition, Sequencing, Assignment
│   ├── Pages/               pages, and snippets used only by this feature
│   ├── Microflows/          ALL flow logic for this feature — microflows AND nanoflows together
│   ├── Services/            integration + reusable sub-logic: SUB_, published/consumed services,
│   │                        mappings, JSON structures, scheduled events
│   └── Resources/           this feature's own enums, constants, regexes, templates, images
├── <FeatureGroup>/
│   └── …
└── Common/                  module-wide, belongs to no single feature
    ├── Snippets/
    └── Resources/
```

**`Microflows/` holds nanoflows too.** One folder for the feature's flow logic, deliberately —
splitting microflows from nanoflows separates two documents that are usually edited in the same
breath (a nanoflow that opens a page, the microflow behind it), and the `NAV_`/`ACT_` prefixes
already say which is which. The folder name is a mild misnomer accepted in exchange for that.

**The type vocabulary is closed:** `Pages`, `Microflows`, `Services`, `Resources`, plus
module-level `Common/{Snippets,Resources}`. Closed on purpose — an open set becomes one dialect
per module, which is the state this skill was written to end. A type subfolder holding nothing is
simply not created; `Common/` is created only when something genuinely module-wide exists.

**`Common/` means module-wide, not unclassified.** A document goes there because every feature
uses it. A document nobody has classified goes to whoever can classify it — see "Deciding the
path" below.

**Feature groups are named after the feature or aggregate root** — `RouteDefinition`, not
`RoutePages`, not `Route_Overview_Screen`. If you cannot name the group without naming a document
type or a single screen, the grouping is wrong, not the name.

**Entities are not foldered.** They all live in the module's single domain model — that
co-location is the point, per `modularize-domain.md`: the relationships are visible in one diagram.

### This supersedes both earlier conventions

| Source | What it says | Status |
|---|---|---|
| `organize-project.md` | Feature-first, **flat inside** the feature (no type layer) | Superseded — use it for **MDL syntax only** |
| `assess-quality.md` §B | Type-first `[objects]` / `[UI]`, entity subfolders below | Superseded — do not build to it |
| **this skill** | Feature group → `Pages`/`Microflows`/`Services`/`Resources`, `Common/` at module level | **Authoritative** |

Both superseded files ship with mxcli and are regenerated on upgrade, so neither can be edited to
say so. That is exactly why the resolution is recorded here instead: a reader who lands on either
of them and follows it will produce a layout this skill rejects, and the only defence is that
`ROUTING.md` points here first. Do not resolve a conflict by picking whichever file you read most
recently.

---

## Every document type: where it goes, and whether mxcli can put it there

The convention covers every document type. **The tooling does not.** These are two different
questions and conflating them is how a "fully foldered" module still ends up with documents at
root — the script placed what it could and said nothing about the rest.

| Document type | Folder | Create-time `folder`? | `MOVE` support |
|---|---|---|---|
| Page | `<Feature>/Pages` | ✅ `folder: 'path'` property | ✅ `move page` |
| Snippet | `<Feature>/Pages`, or `Common/Snippets` | ✅ `folder: 'path'` property | ✅ `move snippet` |
| Microflow | `<Feature>/Microflows` | ✅ `folder 'path'` keyword | ✅ `move microflow` |
| Nanoflow | `<Feature>/Microflows` | ✅ `folder 'path'` keyword | ✅ `move nanoflow` |
| Enumeration | `<Feature>/Resources`, or `Common/Resources` | ❌ **none** | ✅ `move enumeration` |
| Constant | `<Feature>/Resources`, or `Common/Resources` | ❌ **none** | ✅ `move constant` |
| Java action | `<Feature>/Services` | ❌ undocumented | ❌ undocumented — Studio Pro |
| Scheduled event | `<Feature>/Services` | ❌ undocumented | ❌ undocumented — Studio Pro |
| Mapping · JSON structure · published/consumed service · message definition | `<Feature>/Services` | ❌ not supported | ❌ not supported — Studio Pro |
| Workflow · document template · image collection · regex · dataset | `<Feature>/Resources` (workflow: `Microflows`) | ❌ not supported | ❌ not supported — Studio Pro |

**Two consequences you have to act on, not just know:**

- **Enumerations and constants cannot be placed at creation.** mxcli's placement table lists them
  as `N/A` — they land at module root and stay there until a `MOVE` moves them. A script that
  creates either one is not finished without the matching `move enumeration` / `move constant`
  statement in the same script. This is the single easiest way to comply with this skill and still
  leave documents at root.
- **Everything below the line is a Studio Pro action.** Not a reason to leave it unfiled — the
  convention still says where it belongs; it means the placement is a manual step, and the
  mdl-agent reports it as one rather than silently skipping it.

Verified against mxcli's own `organize-project.md` placement table, 2026-08-19. That table is the
syntax reference — nested paths use `/` (`folder 'Order/Processing'`). This skill governs *which
path goes in the quotes*. If a future mxcli version adds create-time placement for more types,
this table is what needs updating.

### A type no rule covers

New Mendix versions add document types, and this table will fall behind. When you hit one:

**Use the named default, then flag it.** Logic- or integration-shaped → `<Feature>/Services`.
A resource the feature owns → `<Feature>/Resources`. Genuinely module-wide → `Common/`.
Then say so in your report, naming the type. Never invent a fifth folder locally.

If that type shows up a second time, it stops being a fallback and earns an explicit row in the
table above. The fallback exists so nobody is ever blocked on a document-type question; the
amendment rule exists so the fallback doesn't quietly become the convention.

---

## Deciding the path

**Normal case: read it from the brief.** `module-brief.md`'s Technical layer carries a
`### Document folder plan` — the module's feature groups, then one row per document. The
architect names the groups because that is an architecture decision; the mdl-agent looks the
document up and copies the path. There is nothing to derive.

**When the brief has no row for a document** (a stub, a late addition, a helper discovered while
writing), derive it:

1. **Type half — mechanical.** Read it off the table above: page or feature-local snippet →
   `Pages/`, microflow or nanoflow → `Microflows/`, `SUB_`/integration/scheduled → `Services/`,
   enum or constant → `Resources/` (plus the `MOVE`, since neither can be placed at creation).
2. **Feature half — from the name.** Strip the known prefix
   (`ACT_ DS_ VAL_ SUB_ OCH_ NAV_ IVK_ ASU_ SCH_ TOOL_ BCO_`), take the leading token, and match it
   against the module's entity names and the brief's declared feature groups.
   `ACT_Route_Save` → `RouteDefinition/Microflows`. `Route_Overview` → `RouteDefinition/Pages`.

**No feature match → ask. Do not bucket.** `Common/` is for documents that genuinely serve every
feature in the module, never for documents nobody classified. Sweeping the unmatched into it is a
fail-open default: it produces a folder that looks organised, hides the open question, and grows
without bound. Surface the document by name and let the brief answer.

**Never fall through to module root.** Omitting the `folder` property is legal MDL and silently
produces the exact defect this skill exists to prevent.

---

## What this skill does NOT do

There is **no runtime check**. Nothing inspects `SHOW FOLDERS`, no gate fails on placement, and
no instrument emits corrective `MOVE` statements. Placement is enforced by being decided in the
brief and required by the agent that writes the MDL — a documentation control, deliberately
chosen (2026-08-19) over building an instrument.

Two consequences, stated so nobody mistakes silence for a pass:

- **A regression will not be detected.** A document created outside the brief-and-agent path, or
  by Studio Pro directly, lands wherever it lands and nothing says so.
- **Existing projects are not repaired.** Modules that are already flat stay flat until somebody
  writes the `MOVE` script by hand. `./mxcli -p <mpr> -c "SHOW FOLDERS"` lists every document under
  `(module root)` per module and is the starting point for that.

---

## Companion skills

`module-brief.md` (where the folder plan is decided) · `learned-mdl-preflight.md` Step 0 (chosen
alongside the write mode) · `modularize-domain.md` Step 3 (folders as the alternative to splitting
a module) · `organize-project.md` (MDL syntax) · `agents/mdl-agent.md` (applies it at `create` time)
