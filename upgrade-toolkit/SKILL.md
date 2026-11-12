---
name: mendix-upgrade
description: Orchestrate a Mendix app upgrade (Studio Pro version plus Marketplace modules) from triage to an honest progress report (N of M checks closed; machine codes PASS / FAIL / INVALID). Says which step file and script to use, in which order, and when to stop. Use when asked to upgrade a Mendix app or to judge whether an upgrade is safe.
status: v3.1 (2026-10-05; release-impact.md is a required triage output and gate rung, screenshots wait for the page to settle, positive controls judge only ui-landing rows, convert-made module edits are recognised, every script has a catch and a pass control, `make test` in controls/)
---

# Mendix upgrade orchestrator

Run the steps in order. Each step file says what to run and what proves it. Every step writes its evidence to the run
folder's work dir `$W`; the report cites only files that exist.
A person reading the result starts at [READING-THE-VERDICT.md](READING-THE-VERDICT.md).

| step | file | done when |
|---|---|---|
| 1 triage | [steps/triage.md](steps/triage.md) | version path, module plan (targets of cross-module associations last), localedits, release-impact.md, scanner coverage, playbook picked |
| 2 baseline | [steps/baseline.md](steps/baseline.md) | old app: snapshot, frozen DB, smoke walk and always-on journeys on a copy, controls green |
| 2b propose | [steps/propose.md](steps/propose.md) | `$W/PROPOSAL.md` signed by a person (`Signed-off:`) or `Status: PAUSED`; nothing in the app model changes before |
| 3 upgrade | [steps/upgrade.md](steps/upgrade.md) | one commit per step, step idcheck clean after each |
| 4 repair | [steps/repair.md](steps/repair.md) | mx check 0 errors, mxbuild succeeds, quick start PASS |
| 5 gate | [steps/gate.md](steps/gate.md) | identity, constants, data, REST, start log, smoke walk, journeys, screens (shotdiff), release impact handled |
| 5b remedy | [steps/remedy.md](steps/remedy.md) | a decision card per blocker (`bin/remedy.py`), AUTO-TRY options tried and gated again |
| 6 report | [steps/report.md](steps/report.md), [steps/gate.md](steps/gate.md) (Step 6 section) | verdict per rung with evidence paths, the completion grade (`bin/grade.py`), one row in `runs/HISTORY.md` |
| (resume) | [steps/resume.md](steps/resume.md) | after an interrupted run: journal vs last commit, unexplained MPR change restored and redone, survivors listed |
| (journeys) | [steps/journeys.md](steps/journeys.md) | always-on set at baseline, impact-picked set at gate |
| (decide) | [steps/decide.md](steps/decide.md) | every stuck item asked, answered in DECISIONS.md; a D row is a choice (open step, assumed) or a log (evidence on its parent step, routine) |

Playbooks per path: [9 to 10](playbooks/9-to-10.md), [10 to 11](playbooks/10-to-11.md),
[11.x to a newer 11.y](playbooks/11-to-11.md),
[edited Marketplace modules](playbooks/edited-modules.md), [widgets that break at runtime](playbooks/widgets.md),
[lessons from the publishers' own upgrades](playbooks/publisher-lessons.md),
[minimum-impact order and multi-deployment modules, TRIAL](playbooks/minimum-impact.md).

New machine or container: [SETUP.md](SETUP.md) (`bin/setup-container.sh` does it in one command).

Paths: `TK=~/Mendix/mxcli-project-toolkit/upgrade-toolkit`, `B=$TK/bin` (every script). A run folder holds `app/` (the
project under its own git), `work/` (`$W`) and `tools/` (mxbuild-<ver>, runtime-<ver>, mxcli-linux; may be symlinks
to a shared folder). Container tools take any run folder: `UPG_ROOT=<run folder>`. Heavy Docker steps (mxbuild,
mx check, marketplace update, app start) go through `$B/heavy-lock.sh` (one at a time per laptop, /tmp/heavy-docker.lock).
On a shared machine the wait for the lock can be long (E5b-34): run a heavy step as a background Bash job with an
explicit long timeout (up to 7200000 ms), or in the foreground with timeout 600000, never with the default.

Scripts new in v3: `shotdiff.py` (old vs new screenshots, pair by pair; also run by `run_journeys.py --compare`),
`toolcheck.sh` (refuses an incomplete toolset folder before mxbuild or mx runs; mx9.sh and mx10.sh call it),
`snapshot.py --ledger` (refuses a database that an earlier snapshot already started an app on: one fresh
`createdb -T` copy per snapshot, E4-21).

Scripts new in v3.1: `release_impact.py` (the Studio Pro and module release-note rows of every jump, from the brain's
version tables; `--check` refuses open rows), `settle.js` (screenshots wait until no loading indicator shows and
the DOM is stable; an unsettled shot is named `-LOADING`), `journey-verbs.js` (journey verbs toggle, select and
confirm, and the topmost popup wins a shared widget name), `convertmade.sh` (a module whose only changes since its
pristine install came from mx convert is CONVERT-MADE, not a local edit; with no pristine step commit, the pre-convert
localedits report is the proof: `--localedits`, T7-12), `usercode.py` (a module's javasource user code against its
installed package: a JAVA_ACTION-only refusal with identical code is convert-made, T5-9), `repair/pds_oldnames.sh` (the design
property rename without the property-level oldNames that shadow Atlas's value-level ones). `convertcheck.py` (what mx convert
really did: its exit code is 0 with errors and on a refused source), `repair/jarclash.py` (classes two jars both carry,
also a library hidden inside another jar), `replacement_check.py` (deprecated modules and patterns the app still
holds, from `playbooks/replacements.tsv`, whatever their version window, and platform behaviour changes such as changedDate read in a microflow expression or an enumeration set by member name in own Java; triage step 10, B6, QJ-1, QJ-3), `dojo_report.py` (Dojo to React client per widget package: ready, delete, can move, can't move; from
`playbooks/dojo-successors.tsv`; advisory on 11, blocking on 12; triage step 10, B6-4), `brain_mine.py` (toolkit upkeep, not a run step: candidate
rows for that table mined from the brain's release notes, no LLM, B6-2). Scripts new from the notification-service history study (NS):
`vendorjava.py` (Marketplace Java commented out or emptied by hand since the base, gate item 13), `widgetdiff.py` (the
widget packages a module step swapped, printed by stepupdate as WIDGETS), `convertnoise.py` (a convert commit holds
only what mx convert makes).

E2E per user process (E2E-16): define e2e tests per user process, not per action. Draft them with
`draft_processes.py` from the model, the user manual and a 15-minute key-user interview (`templates/process-interview.md`).
Only a human sets `status: confirmed`; an agent never confirms its own draft. Compile with `process_journeys.py`, run on
the old app first (before-picked), then on the new one (`--compare`).

Test readiness (RD-1): `readiness.py` ends triage (item 13) and runs again after the baseline (item 9). It says per gate
rung whether the app can be judged, what the customer must supply, and the best reachable verdict, before any upgrade work.

## Rules that hold in every step

- Target version (LTS-1): the default target is the latest released LTS at its newest patch that has release notes,
  recorded as a full version (`mxversion.py`). As of 2026-10-13 that is Mendix 11.12 LTS (newest patch 11.12.6,
  2026-10-08; 11.12.5 says "do not upgrade to this version", so a patch is never taken from this text: read the notes); the next LTS, 11.18, is planned for December 2026. Check the source of truth at triage, never memory, and grep the chosen patch's notes for "do not upgrade to this version" (NR2-1):
  https://docs.mendix.com/releasenotes/studio-pro/lts-mts/ and the release notes of that minor. Paths: 9.x to 10.24 to
  11.12; 10.x to 10.24 to 11.12; 11.x below 11.12 one rung to 11.12. An app already on a newer non-LTS 11.x (11.15) is
  parked until the next LTS, never downgraded. Another target (MTS, non-LTS) only when the user asks for it by name. A
  run that picked a non-LTS target on its own is INVALID for the scorecard.
- Version path: an 11.x source needs no 10.24 rung: one rung straight to the target, see the 11-to-11 playbook (pre-convert
  pass optional, convert, `mx update-widgets`, post-convert pass). 10.x goes to 10.24 first, then to 11. Each rung (10.12 to 10.24, 10.24 to 11.y) is a full pass through
  steps 3 to 6 with its own verdict. Within a rung on 10.x: modules to the newest version that fits the CURRENT
  version, convert, modules again for the target. The pre-convert module pass is REQUIRED on a 10.x source below
  10.24, also when the target is 11 (the 10.24 rung comes first; the 10-to-11 playbook's "updates between the two
  converts" is the pass of the SECOND rung, not a replacement for the first, T7-3): it makes the "step:" commits that
  let convertmade.sh tell the convert's rewrites from a person's edits (T7 skipped it and 6 of 8 modules were kept).
  On 9.x see the 9-to-10 playbook (no module-import on 9.24): there the pre-convert localedits report, run WITH
  `--mxcli-diff` (the offline layers compare no microflow or page contents), is the proof, so pass it to stepupdate as
  `--localedits $W/localedits.json` (T1-15, T3-10, T4-3); a report without the element layer proves nothing and the
  module stays LOCAL. Exception, 9.24 and below (NR1-4): `mxcli marketplace diff` calls `mx module-import`, which mx
  9.x lacks, so every module comes back UNKNOWN. There the proof is the same `--mxcli-diff` run AFTER the convert, on
  10.24 (save it as `$W/localedits-post.md`); read its rows with `convertnoise.py` (NS-10) beside it: a row that the
  convert's known rewrites explain is the convert's, any other element is a person's edit and the module stays LOCAL.
- Record FULL versions (10.24.16.96987): `python3 $B/mxversion.py <toolset | runtime | app.mpr | app.mda>`.
- Never touch the frozen baseline DB; every run AND every snapshot gets its own `createdb -T X_frozen ...` copy (a
  start writes to the database, so a second snapshot on the same copy compares the app with itself after a start).
- Never judge data safety by `$ID`; the runtime maps tables and columns by `GUID`. Use idcheck.py.
- A tool that says "ok" may have checked nothing: scanner (`scancover.py`), localedits (exit 2 = UNKNOWN modules),
  journeys (a role with no test user, a todo) all report INVALID, never PASS.
- mx convert's exit code and "mx convert finished" mean nothing (E6: 31 errors, rc=0; Academy: a refused 10.18
  source, rc=0). `convertcheck.py` after every convert: the project version must be the target.
- Convert once per rung on the integration branch, with the patch production runs, then freeze it (NS-8). Commit the
  convert alone, then each fix in its own commit; `convertnoise.py app/ --rev HEAD` refuses a convert commit that
  holds tool files, docs or a changed widget (NS-10, NS-13).

## Known defects to plan around

- `marketplace update` of MxModelReflection (and any module other modules point at) DROPS the cross-module
  associations that other modules own; all of them hold data. List the targets with `idcheck.py app.mpr --xmod` and
  update those modules LAST (or not headless). Step idcheck catches it (E1: 27 associations).
- Updating an edited module replaces it with the package: the local edit is gone, and re-creating it gives new GUIDs
  (data dropped, while mx check, mxbuild and the start all succeed). See the edited-modules playbook.
- A module update resets the module's constants to package defaults (E1: `MFAmodule.EnabledMFA` True to False, MFA
  silently off) and can ADD a switch whose default hides data (E4 and E5b: a new boolean emptied the dashboard
  charts, every journey PASSed). constcheck.py lists an added boolean as REVIEW; shotdiff shows the empty page.

## Run log and timing

The pipeline writes `$WORK/state/timing.tsv` (one row per attempt of a step: start, end, exit code) and, at the end of the gate
step, calls `bin/runlog.py --work $WORK` itself: one row in `FIELD-RUNS.md` with "run time (machine)" and "person wait" next to
the verdict, and a `Time:` line in `gate-summary.md`. Set `UPG_APP_CODE` and `UPG_APP_TYPE` (code names) before the run. A refusal
(duplicate run id, customer name, no app code name) never fails the run: read the `Run log:` line in `gate-summary.md` or the
information section in `NEEDS-JUDGMENT.md` and fix the cause. **FIELD-RUNS.md still needs committing through a toolkit PR**
(explicit paths, `git commit -- <paths>`); the pipeline prints the reminder. Details: [SETUP.md](SETUP.md), [steps/report.md](steps/report.md).

## Run done

A run is DONE when there are 0 open items and the owner has signed off. Every item ends in exactly one closed state:

| state | means | who closes it | proof |
|---|---|---|---|
| FIXED | re-measured PASS or PASS* | the toolkit | the gate rung, after the fix |
| EVIDENCED | cannot be measured in this app (no route, no data the UI can make), shown from the model or a log | a person confirms | evidence line + `confirmed: <name>` |
| DECIDED | an option was chosen ([steps/decide.md](steps/decide.md)) | a person | DECISIONS.md line, CONFIRMED |
| HANDED-OFF | someone else does it (Studio Pro step, custom widget, key user) | a person | name + date in DECISIONS.md |
| PAUSED | the owner stopped the run on purpose | a person | `Status: PAUSED <reason>` |

- "Open" is anything else. The progress line counts FIXED only; the other states are listed by name.
- The agent closes FIXED alone. It may propose EVIDENCED, DECIDED or HANDED-OFF with a recommendation, never close them.
- Re-architecture (replace a widget family, rebuild a layout, drop a module, rewrite Java) is always a proposal to the owner,
  never done silently. Pause is a valid answer at every stop.
- Before anything changes, the owner signs the upgrade proposal ([steps/propose.md](steps/propose.md)); an unsigned proposal
  is a stop (rule below) and, on an unattended run, "proposal not signed" in every report.
- AGENT-DECISIONS: every D row names its step id (`S-n`, written in the row). A choice the agent makes on its own and that has no step
  yet gets one in the SAME command that records it: `bin/steps.py propose --work $W --new --topic T --title TEXT --found TEXT --say TEXT
  [--why TEXT] [--option TEXT ...] [--decision D71]`. It writes the approval `assumed` by the agent, which is an open topic for the owner,
  and prints the new `S-n` for the D row ([steps/decide.md](steps/decide.md), Mid-run decisions). A D row with no step is invisible to the owner.
- The machine definition below stays: it defines FIXED for the gate rungs.

## Definition of done (the machine definition of FIXED for the gate rungs)

DONE only when: mx check 0 errors AND mxbuild succeeds AND quick start PASS AND idcheck exit 0 (or every REVIEW line
accepted in writing) AND constcheck no open CHANGED and no open REVIEW AND data diff 0 FAIL 0 INVALID AND REST
contract and start log PASS or PASS* (REVIEW lines accepted in writing) AND smoke walk no regression AND every journey
PASS (or each non-PASS explained as a baseline defect) AND shotdiff PASS or PASS* on every screenshot pair (no open
SCREEN REVIEW, no SCREEN INVALID) AND `release_impact.py --check $W/release-impact.md` exit 0 (every release-note row of
the jump handled or not relevant; otherwise INVALID). A run without screenshots of both sides is INVALID on the screens rung. Anything else is FAIL (something broke) or INVALID (could not be judged). Never round
INVALID up to PASS; never call a run that did not happen "no issues".
External APIs (E2E-13, E2E-14, E2E-15, steps/gate.md item 12): no gate run calls a production system. In order of
preference, each consumed API is answered by (a) the vendor's test or sandbox system for that API, (b) responses
recorded from a real system (`apimock.py --recorded`), (c) the stand-in `apimock.py`, only when no test system is
reachable. The stand-in is a stopgap, not the standard: plain PASS needs real (test) systems. A run on the stand-in
(b or c) ends at best in `PASS (on stand-in APIs: <systems>)` (gate exit 4): a conditional PASS for the report, to be
run again against the real test systems before go-live. On the stand-in, rung `apis` needs every endpoint MOCKED, no
UNKNOWN endpoint and no unanswered request. When a system cannot be stood in (Teamcenter), the best verdict is
`PASS (except Teamcenter: N items)` (gate exit 4): only the N journeys, smoke steps and endpoints that need that system
are NOT CHECKED, each listed by name. Both read `PASS (on stand-in APIs: Opcenter; except Teamcenter: 3 items)`. Never
plain PASS; a failure that is not a call into an excluded system stays FAIL, an UNKNOWN endpoint stays INVALID.

## Stop rules

- Proposal not signed: `$W/PROPOSAL.md` section 6 has no `Signed-off: <name> <date>` (pipeline exit 14), or it says `Status: PAUSED` (exit 15), or a plan input changed after the sign-off (the sign-off is cleared). Do not convert, update or repair. An agent never writes the sign-off line. Unattended runs sign nothing: ASSUMED (unattended) in DECISIONS.md, "proposal not signed" in every report.

- RED line in localedits for a module on the plan: ask (steps/decide.md). UNATTENDED default: keep that module at its version, carry
  on with the rest, and report "upgrade complete except kept modules: <list>" (never PASS for the kept ones).
- `bin/steps.py check --work $W` names a D row of AGENT-DECISIONS.md that has no step ("MISSING D71: ..."): open the step
  (`steps.py propose --new`), write its `S-n` in the row, then go on. Do not start the next change of that kind first.

- Step idcheck reports a new data-bearing finding (GUID_CHANGED, REMOVED): stop that module (stepupdate.sh does). Do
  not continue to the build "to see": the build, mx check and the start all succeed while the column is dropped.
- Quick start FAIL: fix it before the gate (after-startup contract, constants, jars).
- An always-on journey (login per role, MFA password-only refused) PASSed on the old app and FAILs on the new one.
- A control fails (positive control not clean, mutant not caught, `make test` red): the instrument is broken.
- toolcheck refuses the toolset: complete it (copy the whole mxbuild folder), never run mxbuild from a partial one.
  `toolcheck.sh --host` before a run: python modules (pymongo, bcrypt) with the pip command for that python; no rsync
  only warns.
- stepupdate exits 3 (TOOL ERROR: quoting, proxy CA, credential, docker; or the same network error on two modules in
  a row): fix the toolchain and rerun with `--from`. A tool failure is never recorded as a kept module.
- design_props_guard says APPLY FAILED: the app may be half copied; restore it with git before anything else.
- A version path that skips 10.24 between 10.x and 11 (an 11.x source is already past it).
- convertcheck says NOT CONVERTED.

## Proof that the tools work

`cd $TK/controls && make test` (about 4 minutes with the Docker controls; `make fast` skips them). Every fixed item in
[FEEDBACK.md](FEEDBACK.md) names its control. Field controls read `~/upgrade-lab` (UPG_LAB) and are skipped without it.
