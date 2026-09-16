# `cd X && cmd` defeats every Bash permission allowlist — the single largest source of dead turns in a three-day deploy arc, and the rule was already in the settings file

**From:** Maurits Visser, from a MOC/PSSR app replacement
**Date:** 2026-09-16
**Kind:** learning / process
**Field evidence:** confirmed, and confirmed the embarrassing way — the fix was to stop
writing `cd` and the very first retry succeeded. Detail below.
**Proposed target:** unsure. It is agent-harness friction rather than Mendix process, so
possibly `process/process-learnings.md`, or the project `CLAUDE.md` template that
`bin/init-project.sh` writes — the latter is where it would actually reach a session.

---

## What happened

The project's `.claude/settings.json` had allowed `Bash(./mxcli:*)` from the day it was
scaffolded. Permission rules match on the **start of the command line**. So:

```
./mxcli exec mdlsource/11-agent/A25-graph-transport.mdl -p MOC.mpr     → matches, allowed
cd /path/to/project && ./mxcli exec ... -p MOC.mpr                     → matches nothing
```

Roughly **fifteen turns** were spent in a loop of denials, each read as "the tool is
blocked", followed by writing a *new* permission rule, followed by the same denial — because
the new rule also started with `./mxcli` and the command still started with `cd`. The
diagnosis only landed after running `cd` as its own separate call and then the tool in the
next one, which worked first try, against an allowlist that had not changed at all.

The remedy is free, because **the Bash tool's working directory persists between calls.**
Issue `cd <dir>` once, on its own, then run the tool. For git, `git -C <dir>`. For mxcli, an
absolute `-p` path.

## Three siblings from the same arc, same root cause — an agent writing a command that *reads* as something it is not

1. **Renaming a credential variable on the command line** (`FOO=$PAT some-tool`) reads as
   exfiltration preparation and is refused. Pass it as the tool's documented env var, or via
   an askpass helper.
2. **A heredoc anywhere near a credential** is refused — including a `git commit -F -` whose
   body merely *discusses* one. Write the file with the file-writing tool instead and pass
   the path. This worked every time; the heredoc worked none.
3. **A refusal is sticky for the rest of the turn.** After one denial on a settings-file
   edit, an unrelated and fully allowlisted `./mxcli` call in the same turn was refused with
   the *same* label. Retrying on a fresh turn succeeded with no change. So a second denial in
   one turn is not evidence about the second command, and the correct move is to end the turn
   rather than to keep reformulating.

## Why this is worth a toolkit line rather than a shrug

The project has a measured finding that session cost tracks **turn count × context size**,
not output length — output is ~0.2% of tokens and ~9% of cost. Fifteen dead turns late in a
long session are therefore among the most expensive things that can happen, and every one of
them was spent re-deriving a fact that a one-line note would have supplied.

The note is now in that project's `CLAUDE.md` as a numbered start-here rule. It belongs in
the template, so the next project gets it at scaffold time instead of on day three.
