---
description: Wire this project to the mxcli-project-toolkit (one-command install) and start the pipeline
---

Wire the current project to the mxcli-project-toolkit and enter its pipeline. Steps, in order:

1. Locate the toolkit clone: `~/Mendix/mxcli-project-toolkit` (if missing, ask the user where it is or offer to `git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit`).
2. Run the one-command install against the **project root** (the current working directory unless the user says otherwise):
   ```bash
   ~/Mendix/mxcli-project-toolkit/bin/init-project.sh "$PWD"
   ```
   This scaffolds `intake.md`, `PROJECT.md`, `CLAUDE.local.md` (runbook-first wiring + baseline routing), all five agent stubs in `.claude/agents/`, and the `index.html` dashboard, and opens the visual guide in the browser. It is idempotent — existing files are never overwritten.
3. Read `~/Mendix/mxcli-project-toolkit/skills/conversion-runbook.md` **in full** — it is the executable spec; READMEs are orientation only.
4. Read the generated `CLAUDE.local.md` and `intake.md`.
5. Start Stage P: propose the **entry mode** with evidence per the runbook's Entry Modes classification rules (source code exists → analyze it; specs exist → requirements-driven; greenfield only from a conversation; existing-app-assurance if nothing is being built), then run the intake interview — ask the questions in chat via AskUserQuestion, **end your turn, and wait for answers**. Record every answer in `PROJECT.md` as `CONFIRMED` (or `ASSUMED` only if the user explicitly delegates).

If the project was already wired (everything skipped), instead run `~/Mendix/mxcli-project-toolkit/bin/sync-project.sh "$PWD"` and report what it found.
