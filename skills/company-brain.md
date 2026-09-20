# Company Brain — the private tier between the toolkit and a project

**Applies to:** any mxcli project; any company running more than one.
**Purpose:** Give company-specific material a home that is neither the public toolkit (which the
leak guard forbids for anything client-named) nor a hand copy inside each project (which rots).
Say what goes to which of the three tiers, how to wire a project to the company tier, and the
two rules that keep the tiers honest.

## When this fires

- Someone asks where *our* conventions, lint rules, MDL snippets, design system or approved MPKs
  should live so every project sees them.
- A session finds something reusable that names a client, a house rule or an internal component
  — it cannot go to the toolkit as-is, and `docs/brain/` is per app.
- A project is being scaffolded for a company that already has a company brain.
- A public toolkit file is about to cite a path outside the toolkit.

## The three tiers — say which one before writing anything

| Tier | Owner | Holds | Test that it belongs there |
|---|---|---|---|
| **Toolkit** (this repo) | shared, public | process, stages, gates, `learned-*` patterns, stock lint rules | still true with a different client, module and `.mpr` |
| **Company brain** | the company, private | own skills, naming conventions, lint rules, MDL snippets, design system, approved components, learnings that name clients, patches and proposals held against the toolkit | true for this company's apps; may name a client; never names a person's data |
| **Project** (`PROJECT.md`, `docs/brain/`) | one app | gate answers; decisions anchored to `@Module.Element` | only true for this model |

`close-the-loop.md`'s destinations table decides between the toolkit and the project. This skill
adds the middle row. The wrong shape to watch for: a project's `CLAUDE.local.md` growing a
"house rules" section by hand — that is company-brain content copied into one project, and the
next project will not have it.

## Wiring — one pointer, no baseline words

```bash
bin/init-company-brain.sh ~/Mendix/<company>-brain --name "<Company>"   # once per company
bin/wire-company-brain.sh <project-root> ~/Mendix/<company>-brain       # once per project
#   or: bin/init-project.sh <project-root> --company ~/Mendix/<company>-brain
```

`wire-company-brain.sh` writes one marked block (~50 words) into the project's `CLAUDE.local.md`
naming the company brain's root and its `ROUTING.md`, and registers the project in the brain's
`projects.tsv`. The company's routing table is **never copied** into the project: it loads on
demand when the pointer fires. That is why this costs the project's session-start budget
nothing — the toolkit's own baseline ratchet (`render-routing.sh`) is not the company's to spend.

**Completion criterion:** `grep -c 'COMPANY-BRAIN:BEGIN' CLAUDE.local.md` is exactly 1 and the
block's path resolves. Two blocks or a dead path is a wiring failure.

## What goes up, and how

At project wrap-up (`close-the-loop.md`):

1. `bin/harvest-learnings.sh <project> --to <company-brain>/inbox` — drafts inbox files from
   the project's bug logs, register promotion tables and locally patched scripts.
2. The company triages weekly: promote into `skills/`, `components/`, `examples/mdl/`,
   `proposals/`, or delete. Promotion is a decision, recorded in the file's header; never drift.
3. Onward to the toolkit only for what is still true with a different client: genericize, PR or
   `contrib/inbox/` drop, then replace the company file with a **pointer stub** listed in
   `skills/PROMOTED.md` so project routing rows keep resolving.

## Two rules, both checked

1. **The public toolkit never cites the company tier.** `bin/check-no-private-citations.sh` runs
   in CI. A private pointer in a public skill is a dead link for everyone else — the failure it
   prevents is five skills cited by this repo that existed only in one person's private repo.
   The company brain may cite the toolkit freely.
2. **Client names yes, data never.** The company brain runs the toolkit's leak guard in
   probes-only mode (`bin/leak-check.sh` in the template): personal data, credentials, record
   contents, local paths and internal hosts are caught; a name denylist is optional.

## Components (MPKs) — catalog here, decisions in the project

A component is approved when its `.mpk` sits beside a filled manifest (`components/TEMPLATE.md`:
version, Mendix range, namespace once imported, the CLI command that actually worked, proven-in
table).

**Import from the CLI.** The write modes are CLI and MCP, picked by the shape of the work
(`learned-mdl-preflight.md` Step 0); Studio Pro is a handoff surface for a human
(`handoff-to-studio-pro.md`), not a mode an agent chooses — and MCP needs it running, so on a
headless machine the CLI is the only option. **Probe the binary you have** for the import
subcommand rather than assuming: the "marketplace is manual" prior misfired twice in this
toolkit's history. A CLI that cannot import on your version is a defect to record and log, not a
cue to open the GUI.

Once imported, the component is a module in the model, so a decision about using it anchors in
the project's `docs/brain/` as `@<Module>.<Element>` with no new mechanism; the manifest stays
the catalog entry.

## Not this skill

- Which decisions go to `PROJECT.md` vs `docs/brain/` — `close-the-loop.md`.
- Cross-project questions ("which projects use component X", "which are stuck at Stage 3") —
  not built; `projects.tsv` is the registry a future derived index would read.
