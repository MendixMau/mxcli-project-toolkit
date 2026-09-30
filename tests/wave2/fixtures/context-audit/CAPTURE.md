# context-audit fixture — capture notes

**Captured, not hand-written.** Both transcripts were written by the Claude Code harness in a
real cloud session on 2026-09-30, then scrubbed by a script that keeps every field
`bin/context-audit.sh` reads and replaces all text with filler **of the same length** (sizes
are what the instrument measures):

- `projects/-srv-example/s-1/subagents/agent-1.jsonl` — every record of one Agent-tool
  subagent told to do a pipeline session start: read `CLAUDE.local.md`, the runbook, two
  baseline skills, and one of them again. The model chose to page the runbook
  (`offset`/`limit`) and to re-read parts of it; that is kept exactly as it happened.
- `projects/-srv-example/s-1.jsonl` — from the parent session: its `instructions` attachments,
  its first assistant call (the start-context number), its one automatic `compact_boundary`,
  and eight Bash tool_use/tool_result pairs whose command reads a file (`cat`, `sed -n`,
  `git show REV:path`, with `cd` and `VAR=` prefixes as typed).

Scrubbed: paths rewritten under `/srv/example/`, model ids replaced by `model-main` /
`model-sub`, every text, tool result and instruction-file body replaced by `x` filler of equal
length, all other attachment types and record fields dropped.

## Facts the fixture pins (each from the real capture)

- Tool results arrive as `tool_result` blocks inside `user` records, content either a string
  or a list of `{type: text}` blocks.
- The Read tool's own defaults apply when `offset`/`limit` are absent (offset 1, limit 2000):
  `{file_path}` and `{file_path, limit: 2000}` are the same read — a re-read.
- Paging a file is not re-reading it; asking for the same part again is.
- Auto-loaded CLAUDE.md files are `attachment` records of type `instructions`, one per file.
- A subagent's first call already carries ~52k tokens: that is the floor a dispatched agent
  starts from before reading anything.
