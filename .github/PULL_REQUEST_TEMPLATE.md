<!-- Thanks for feeding the toolkit. Pick your lane, delete the other section. -->

## Inbox lane (`contrib/inbox/` files only)

Nothing to fill in — the field-evidence line inside the file is the whole bar.

- [ ] No client data: no client/vendor/person names, codenames, internal hosts, real local paths

## Direct lane (changes to `skills/`, `bug-logs/`, `bin/`, `project-bin/`, `project-tests/`, pipelines)

**What changed and why (one paragraph):**

**Field evidence** — which real project this ran against / was observed in, and what it measured
or fixed there (CLAUDE.md → "Shipping an instrument", rule 4; required for any instrument change):

- [ ] No client data anywhere in the diff
- [ ] For a new/changed instrument: golden input captured (not hand-written), both layouts
      (single-tree and `.mpr`-under-`app/`), both platforms (macOS + Git Bash/Windows) considered
- [ ] For a new skill: routing row added (`bin/lib/skill-routing.tsv` + `bin/render-routing.sh`)
- [ ] `CHANGELOG.md` line appended in this PR, crediting the source project or person
