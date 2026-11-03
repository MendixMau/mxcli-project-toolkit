# harvest-learnings — what these two bug logs are, and what was changed

`harvest-learnings.sh` section 1 splits each `bug-logs/*.md` file on its `## ` headings, so per
`CLAUDE.md` -> "Shipping an instrument" rule 1 its fixture input reproduces a real bug log. These
two files reproduce the **structure** of the bug logs that exposed the first-section-only defect
(a Mendix 10.24 project, 2026-10-13: 12 sections in one file and 1 in a second; the harvester
drafted the first section of each). **Only the text was changed**, because the logs are a client
project's, and the section counts were cut to 5 and 2.

**What is verbatim, because the splitter sees exactly these:**

- a `# ` title, an intro paragraph and a bullet list (with indented continuation lines) before
  the first `## `, which belong to no section;
- one blank line between sections, and a section that is not a bug at all
  (`## Improvement ideas, …`), which the heuristic still drafts;
- `> ` status blocks with `> - ` bullets, `**Label:**` lines, and a fenced block inside a section;
- `BUG-DRAFT-`, `NOTE-` and `TOOLKIT-DRAFT-` heading prefixes with a trailing `(date)`;
- the last section running to the end of the file, which ends in one newline.

`test-harvest-learnings.sh` T5 appends one section whose heading the toolkit log already carries,
taken from the clone's own `bug-logs/mxcli-bugs.md` at run time, so the known-heading filter is
checked on a later section, the path the defect broke.
