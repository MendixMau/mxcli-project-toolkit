# test-assessments/ — throwaway proof runs, never product output

This folder holds two kinds of thing, both disposable and both gitignored (this README is the
only tracked file here — see `.gitignore`):

1. **Tool-defect A/B probes** — sandbox runs that follow `skills/sandbox-ab-tool-defect-probe.md`:
   rsync a project to a scratch subfolder here, run the identical script against two binaries,
   gate each arm, roundtrip-read, then `rm -rf` the subfolder. The *finding* goes into
   `bug-logs/`, not here — this is scratch space for producing the finding, not a record of it.
2. **Skill-wiring proof runs** — a fresh, context-free agent given a realistic task and pointed
   only at this repo, to test whether `bin/lib/skill-routing.tsv`'s rendered surfaces actually
   lead it to the right skill. The transcript/verdict is scratch; if it reveals a routing gap,
   the fix goes into `skill-routing.tsv` and this repo's tests, not here.

## Why this is not `analysis/`, `sources/`, or `knowledge-base/`

Those three hold a *consuming project's* output — a real migration's extracted model. This folder
never holds project output. It holds evidence about whether *this toolkit* — its tools and its
routing — works, which is why it's a sibling of `tests/`, not of a project's `analysis/`.

## Conventions

- One subfolder per run, named for what it's proving: `dg2-bug42-probe/`, `skill-wiring-2026-08-20/`.
- Always `rm -rf` a probe's rsynced project copies when done — never leave a 400 MB clone sitting
  here between sessions (see the sandbox skill's own warning about this).
- Never write a client/project name into a file that leaves this folder (a bug-log entry, a
  skill edit) — scrub it the same way any other promotion into this repo does.
- If a run produces something worth keeping (a repro script, a proof transcript worth citing),
  promote the specific artifact into `bug-logs/` or `skills/` and delete the rest of the run
  folder — don't let this directory become a second, uncurated bug-logs.
