# contrib/ — the contribution inbox

`inbox/` is the zero-friction lane for getting field learnings into the toolkit: copy
`inbox/TEMPLATE.md`, paste what you have, PR it. Full picture: `../CONTRIBUTING.md`.

Files here are **unreviewed, unrouted, unreleased** — nothing in the toolkit loads them, no
skill routes to them. Do not cite an inbox file from a skill or script. Triage promotes each
item into its real home (`skills/`, `bug-logs/`, `bin/`) and deletes it here in the same
commit; a long-lived inbox file means triage is behind, not that the file is authoritative.

`bin/harvest-learnings.sh <project-root>` drafts inbox files automatically from a project's
stored learnings.
