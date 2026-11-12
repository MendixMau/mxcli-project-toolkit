# Step R: resume after an interrupted run

Use this when a run was cut off (a reboot, a killed session, a context that ended mid-step) and a fresh agent takes over.
The only trustworthy state is the git history of the app, the journal and what is still running. A half-written MPR is
not state: it is a question.

Why (FM-1): after a reboot the MPR had an uncommitted change and `JOURNAL.md` stopped two steps before the last commit.
The only record of what the change was (a finished `mx update-widgets`, then a stash and pop) was the previous agent's
transcript. Restoring to the last commit and redoing the step was safe; committing the change as found was not.

## Before any heavy step: journal first

Write the journal line BEFORE a step that takes minutes or touches the MPR (`mx update-widgets`, convert, a module
update, a build), not after: `<time> START <step>: <command>, expected result`. After it: `<time> DONE <step>: commit
<sha>`. A START without a DONE is exactly what a resumer has to explain. Commit the journal with the step.

## Order

1. State. `git -C app status --short` and `git -C app log --oneline -5`, then the journal tail. Compare the last commit
   with the last DONE line. Name every difference in the journal (RESUME line) before touching anything.
2. An uncommitted change in the MPR (or any unit) that no START line explains: never commit it. Keep a copy of the
   crashed state (`cp -R app $W/crash-<time>`), `git -C app checkout -- .` and `git -C app clean -fd`, then redo the step
   named by the journal.
3. Compare the redo with the crash copy when one exists: read the units of each with `mprunits.unit_rows` (a few lines of Python) and compare the document names and
   types; the same units with only GUIDs differing means the crash copy held the same work. A unit that exists only in the crash copy is a step
   nobody wrote down: find it before going on.
4. Survivors. `docker ps -a` for containers (`${UPG_NAME:-mig}-*`, the Postgres container and its databases), proxies and
   tunnels, a stale heavy lock (the lock file written by `$B/heavy-lock.sh` holds the label, the time and the pid; a lock whose pid is
   gone is removed by hand and said in the journal). Stop what is yours with the run's own prefix: source the run's `env.sh` first, never call
   `runapp.py stop` bare (FM-9: it stops the DEFAULT prefix, which may be another run's app).
5. Re-run the last check that the journal says passed (`mx check`, then `idcheck.py` for a module step) before the next
   step, and say so in the journal: a crash can leave a model that loads once and fails later (FM-4).
6. An `mx` call that dies with rc 139 and then a loader exception ("Object reference not set", "Collection was of a
   fixed size") is the emulation flake of amd64 mxbuild, not corruption: `mxrun.sh` retries it, a hand-run is repeated
   once (FM-2). Corruption is the same message on a second and third clean repeat.

## Done when

The journal has a RESUME block (state found, what was discarded, what survived, the next step) and the next START line
follows it. Report the discarded change and why in the final report.
