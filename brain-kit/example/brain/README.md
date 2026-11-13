# Demo brain (public Mendix docs)

Mendix's practitioner knowledge for developers and coding agents: what our teams learned, in short notes with sources.
Agents: read `AGENTS.md`.

## How to use it

**With a coding agent (Claude Code, Cursor, Copilot).** Clone this repo next to your project and add one line to the project's
`CLAUDE.md` or `AGENTS.md` (every instruction file the project has: a session that never opens the file never sees the brain):

```
Mendix field knowledge: ~/demo-brain. Before security, performance or REST work, or on an error you cannot explain, read
~/demo-brain/ROUTING.md and search the brain as its AGENTS.md says.
```

**By hand.**

| You want | Do this |
|---|---|
| The notes on one topic | open `internal/<topic>/INDEX.md` (topics: `INDEX.md`) |
| A fix for an error | `grep -rliE "ERR123\|timeout" internal/` (one or two keywords, never a sentence) |
| Only pitfalls on a topic | `grep -rl "kind: pitfall" internal/<topic>/` |

**Trust.** Every note lists its sources and starts as `draft-unreviewed`. `QUALITY.md` shows per topic how the automatic gate scored
them. Check the source before acting on a note that matters. Found a wrong note, or a lesson that is missing? Open a merge request;
a person reviews it before it lands.

## Adding a lesson

Copy the template for its kind from `note-templates/`, fill it, run the gate (`python3 <brain-kit>/bin/gate.py --brain . --checks lint,find`),
and open a merge request. One lesson per note. Cite where it came from.
