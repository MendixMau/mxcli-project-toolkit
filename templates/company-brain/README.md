# {{COMPANY}} company brain

The private tier between the shared **mxcli-project-toolkit** (the process, public, holds no
client data) and each **project** (one app, its own registers). What lives here is true for
this company's apps and nowhere else: own skills and conventions, lint rules, MDL snippets, the
design system, approved components (MPKs), learned patterns that may name clients, and the
patches and proposals this company is holding against the toolkit.

> **Governance rule — the whole model in one line.**
> Reviewed weekly. Promoted to the shared toolkit only by explicit decision, never by drift.

Toolkit root on this machine: `{{TOOLKIT_ROOT}}` (the toolkit's own README says how to consume it).

## Three directions, one repo

| Direction | What moves | Mechanism |
|---|---|---|
| **Down** — into every project | `skills/`, `lint-rules/`, `examples/mdl/`, `components/`, `prompts/` | Each project is wired with `{{TOOLKIT_ROOT}}/bin/wire-company-brain.sh <project> <this repo>` (or `init-project.sh --company <this repo>`). That writes ONE short pointer block into the project's `CLAUDE.local.md`; the routing table below loads on demand, so it costs the project no session-start words. |
| **Up** — out of projects | anything a session found reusable | `{{TOOLKIT_ROOT}}/bin/harvest-learnings.sh <project> --to <this repo>/inbox` at wrap-up, or copy `inbox/TEMPLATE.md` by hand. Triage weekly: promote into `skills/`, `components/`, `proposals/`, or delete. |
| **Onward** — into the shared toolkit | what is still true with a different client, module and .mpr | Explicit decision only. Genericize (no client names), open a toolkit PR or `contrib/inbox/` drop, then replace the file here with a **pointer stub** and list it in `skills/PROMOTED.md` so project routing rows keep resolving. |

## Routing — hand-maintained, on demand

`ROUTING.md` is this brain's routing table: one row per skill, **trigger condition first**
("Building any page for a {{COMPANY}} app — …"), not a summary. Keep it under ~40 rows; split by
domain when it grows. A project session reads `ROUTING.md` when the pointer block in its
`CLAUDE.local.md` fires, never earlier.

## Two rules that keep the tiers honest

1. **The public toolkit never cites this repo.** A pointer from a public skill into a private
   file is a dead link for everyone outside this company (real incident: five skills cited by
   the public toolkit existed only in a private repo; an engineer following the pointer got
   nothing). This repo may cite the toolkit freely. The toolkit's CI enforces the other
   direction with `bin/check-no-private-citations.sh`.
2. **Client names are allowed here; data never is.** Personal data, credentials, record
   contents, local filesystem paths and internal hostnames stay out. `bin/leak-check.sh` runs
   the toolkit's leak guard in probes-only mode (no name denylist required). Add a
   `.leakguard-deny` (gitignored) if this company also wants a name list.

## Layout

```
README.md            this file — governance + wiring
ROUTING.md           the on-demand routing table (trigger → file)
projects.tsv         registry of projects wired to this brain (path, name, status)
skills/              own skills; PROMOTED.md lists the ones now living in the toolkit
lint-rules/          own .star rules (third hash set beside the toolkit's stock rules)
examples/mdl/        MDL snippets proven in one of our apps
components/          approved MPKs, one manifest .md beside each .mpk
proposals/           patches/design notes against the toolkit, awaiting a go
patches/             the same as diffs, applied locally until upstream merges them
inbox/               zero-friction drop; TEMPLATE.md; triaged weekly
field-runs/          one record per full-pipeline run; the cross-run trend surface
handoffs/            cross-session briefings ("another session pushed your commits")
prompts/             starter prompts for recurring big tasks
bin/                 leak-check.sh and whatever else this company scripts
```

## Weekly review — the checklist

- [ ] `inbox/` empty or every file has a disposition (promote / keep as proposal / delete)
- [ ] `skills/PROMOTED.md` matches reality: every promoted skill here is a stub
- [ ] `bin/leak-check.sh` clean
- [ ] `projects.tsv`: every listed path still exists; retired projects marked `retired`
- [ ] `ROUTING.md`: every row's file exists; every new skill has a row
