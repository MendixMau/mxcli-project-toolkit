# `mxcli run --local --test-endpoint` stopped by a signal leaves AfterStartupMicroflow on the injected flow (second field case for #244, and the toolkit-side half)

**From:** a field project (anonymised)
**Date:** 2026-10-13
**Kind:** bug
**Field evidence:** an agent stopped a running `mxcli run --local --test-endpoint` (a background-task
stop, so a signal, not a clean exit) to restart the app. Later a clean-up removed the injected
`MxTest` module but not the setting; exec.sh's pre-flight then reported the model "ALREADY has 1 error"
(CE1613), and the next app start recursed with a StackOverflowError in `MxTest.RegisterEndpoint`.
mxcli v0.25.0, Mendix 11.14.0 Beta, toolkit c1efcb3.
**Proposed target:** upstream mxcli for the root cause (already logged here as #244, closed 2026-10-14 by #322 (toolkit refusal); the upstream root cause remains); in the
toolkit, `skills/testing-shape.md` (the `--test-endpoint` paragraph) and an exec.sh pre-flight hint

**Currency check:** 2026-10-16 against master d1cbd41: partly stale. exec.sh's pre-flight now refuses on a leftover injected setting and prints the `ALTER SETTINGS` repair (`_common.sh`), so the exec.sh hint half is done. Still open: the upstream root cause behind #244 closed 2026-10-14 by #322 (toolkit refusal); the upstream root cause remains, and `skills/testing-shape.md` does not say that a stop by signal skips the restore.
---

## What is already covered

- #244 (closed 2026-10-14 by #322 (toolkit refusal); the upstream root cause remains) describes the same family on mxcli v0.25.0 / Mendix 11.15.0: the wrapper chains the
  "current" after-startup flow, which is already `MxTest.RegisterEndpoint`, so it calls itself. It
  asks upstream to restore on interrupt and to refuse a self-wrap.
- `skills/testing-shape.md` says `--test-endpoint` writes into the working model while the app runs and
  that "a clean stop prints 'test endpoint removed; project restored'". It does not say that a stop by
  signal skips that restore.

## What this case adds

1. **Trigger is a signal stop of `run --test-endpoint` itself**, not an interrupted `mxcli test` run.
   Agents routinely stop background tasks this way to restart an app.
2. **A partial clean-up makes it worse.** Removing the `MxTest` module afterwards (by hand or by a later
   cleanup) leaves `AfterStartupMicroflow` pointing at a flow that no longer exists: CE1613 at build,
   which exec.sh's delta gate then carries as a "pre-existing" error on every later script. Re-creating
   it by starting with `--test-endpoint` again gives the self-recursion from #244.
3. **The repair that worked**, run through `bin/exec.sh` (an `ALTER SETTINGS`, said in chat):

   ```sql
   mdl 1;
   alter settings runtime (AfterStartupMicroflow: 'MyModule.ASU_Startup');
   ```

   mxbuild went back to 0 errors; the app then started normally.

## Proposed toolkit changes (hypothesis, not built)

- `testing-shape.md`: add "Stop `run --test-endpoint` with Ctrl+C in its own terminal or let it exit;
  a kill or task stop skips the restore. Afterwards `git status` on the model must be empty; if the
  Settings unit is still modified, restore it from git (or with the `alter settings runtime` line
  above) before any exec." Run build-time apps without `--test-endpoint` (the skill already says so).
- `exec.sh` pre-flight: when the baseline holds CE1613 on the project Settings, or `describe settings`
  shows `AfterStartupMicroflow` starting with `MxTest.`, print one line naming the cause and the repair,
  instead of only "Model ALREADY has 1 error(s)".
- Upstream (#244): restore the original after-startup on SIGTERM/SIGINT too, and refuse to wrap an
  after-startup that is already `MxTest.RegisterEndpoint`.

Probe: start `mxcli run --local --test-endpoint` on a scratch copy, stop it with `kill -TERM <pid>`,
then `describe settings`. Today (v0.25.0): after-startup is still `MxTest.RegisterEndpoint`.
