# Upgrade toolkit: plan and experiments

Status: experiments drafted 2026-10-02; completion and handoff strategy directed by the owner 2026-10-15.
Personal toolkit only; nothing goes to mxcli-project-toolkit without "promote this".
Customer app (F1) stays LOCAL in ~/upgrade-lab. No customer names in anything that leaves this machine.

## Goal

One end-to-end upgrade tool that an agent imports into a fresh session and runs on any Mendix app:
triage, baseline, upgrade, gate, report. Report the upgrade work completed, bugs found and fixed, verification evidence,
and remaining human checks together. A clean build alone does not establish completion or verification.

The bar it must clear on F1, 10.12.9 to 10.24.16: the customer's real upgrade built clean and lost data
(Account.MFA_Type and Email_Connector template data, new GUIDs, DROP COLUMN). Our tool must reach the
same target version with build 0 errors AND data diff 0 FAIL, or stop and say exactly why.

## Upgrade completion and handoff strategy

Owner direction, 2026-10-15: drive every app toward completion and attempt full test coverage. Be realistic about
customer systems, credentials, licences, environments and owner decisions. When the remaining work genuinely needs
a human or an unavailable environment, finish the engineering work that can be done and provide a specific handoff.
The report must explain the resulting app, repairs and limitations. It must not describe an app as failed merely
because a test could not run.

Report these separately for each requested version target:

- **Upgrade delivery:** `COMPLETED`, `COMPLETED WITH HANDOFF`, `IN PROGRESS` or `BLOCKED`, with the exact version,
  branch or commit and package evidence. Completion requires the agreed target, successful build and start,
  documented changes, assessed data preservation, and no unresolved confirmed upgrade blocker. An explicitly
  accepted exclusion stays visible with its acceptance. A completed intermediate version does not complete a later target.
- **Verification:** measured PASS, accepted differences, confirmed regressions, instrument gaps and checks not run.
  Preserve gate verdicts, exit codes and evidence. An unavailable check is neither a proven regression nor a pass.
- **Owner closure:** sign-off and each handed-off action remain explicit. Engineering completion with a handoff does
  not manufacture owner approval or erase pending checks from the existing progress ledger.

`COMPLETED WITH HANDOFF` means the engineering completion evidence exists and the remaining items are named human
checks, customer prerequisites or explicitly accepted scope exclusions. It does not close a confirmed regression,
unproven data loss or an engineering repair that the toolkit can still perform. If build or start could not be run,
report the preparation performed and the blocked phase instead of claiming a completed upgrade.

Before handing off a check, attempt the applicable automated tests, fixture or instrument repairs, focused probes
and available stand-ins. Record what was tried and why further testing needs a person or external access. Report
stand-in results with their scope. Keep driving work the toolkit can do; do not use a handoff to avoid a feasible test.
Do not lower thresholds, relabel a failing test, or silently accept a screenshot or data difference to obtain completion.

Every run report must include the handoff in [steps/report.md](steps/report.md), using
[templates/upgrade-handoff.md](templates/upgrade-handoff.md). Each action names the process or feature, steps to test,
expected result, attempted evidence, remaining prerequisite, owner and closure evidence. Separate a request for a
decision from a request to execute a test. A generic instruction to "test everything" is insufficient.

Keep an evidence-backed history across sessions: stable app identity, run and version-hop identifiers, attempts per
app, targets reached, bugs found and fixed, accepted exclusions, handoff actions and lessons fed back into the toolkit.
Retain earlier attempts; deduplicate the same app and the same bug across reruns. Count upgrade completions separately
from verified or owner-signed-off completions. State the audited history scope and unknowns before publishing totals.

Implementation order: require the report and handoff template first; then add structured delivery, verification and
handoff fields to history and rendered reports; finally add controls proving that an unavailable test never becomes a
false app regression or false pass, and that confirmed bugs and data risks remain visible. Keep the current gate
contract unchanged while the reporting changes are developed.

## The pipeline and which asset does what

| Step | What happens | Assets used | Status |
|---|---|---|---|
| 0 Setup | app copied into a git worktree, version path decided (10.x must pass 10.24 before 11) | mxcli v0.24, mx/mxbuild 10.12.9, 10.24.16 (amd64 container `tools/mx10.sh`), 11.12.2 to 11.15 local | exists |
| 1 Triage | what will break and where the traps are | the optional upgrade scanner `scan.py` + catalog; `mxcli marketplace diff` per module (local edits = trap); brain notes filtered by `applies_to` version; toolkit `query-the-model`, `assess-migration` | scanner exists, local-edit flag new |
| 2 Baseline | prove the old version works and record it | regression skill `seed_pg.py` + `snapshot.py`; `runapp_m2ee.py`; REST recordings; toolkit `journey-runner.js`, `journey-map`, `learned-db-assertions`; Tier 1 smoke walk generator | data/REST exist, smoke walk new |
| 3 Upgrade | convert, update modules one at a time, one commit each | `mx convert`; `mxcli marketplace update`; GUID-safe handling of edited modules; ID check after each commit; toolkit `conversion-runbook`, `wiring-sweep` | ID check + GUID-safe replay new |
| 4 Gate | same database, two binaries | regression `diff.py` ladder (controls, data, REST, log, journeys); toolkit `testing-shape`, `tool-output-is-not-ground-truth`, `test-result-audit` | exists (34/34 controls) |
| 5 Report | PASS / FAIL / INVALID with evidence, lessons as brain note candidates | `REPORT.md` shape; toolkit `e2e-evidence-report`, `measured-claims`; brain gate (`compact/`) | partly |

The brain is read at steps 1 and 3 (grep, version filter) and written only through its gate at step 5.

## New pieces to build (in this order)

1. **ID check** `idcheck.py`: diff entity and attribute GUIDs between two `.mda` (or MPR) versions.
   An attribute whose name survives but whose GUID changes = column will be dropped. Runs in seconds, no app start.
   Proof: it must flag MFA_Type and the Email_Connector pairs on the customer's 10.24.16 and stay silent on our pure conversion.
2. **Local-edit triage** `localedits.py`: per Marketplace module, baseline mpk vs app, list edited elements, and mark
   the ones that hold data (attributes, associations) as red.
3. **GUID-safe module update**: the open research question. Options to test, cheapest first:
   a. keep the edited module, update only unedited ones (safe, less modern);
   b. update with `--force`, then a data migration (copy old column before, restore after);
   c. replay edits while reusing the old GUIDs (if mxcli/MPR allows it).
   Pick by gate result, not by preference.
4. **Smoke walk generator**: per user role, open every navigation item and every page reachable in one click,
   pass = page renders without client error; run on old version first (it is the oracle).
5. **Orchestrator skill** `SKILL.md`: the five steps, stop rules, and what counts as done. Short; points to the scripts.

## Experiments

Each run: a fresh agent (subagent or `claude -p` in a clean worktree) gets only the app, the target version and the
upgrade toolkit. No hand help. Then I score it. After each run the toolkit improves and the next run starts fresh.

| Run | Path | What it tests |
|---|---|---|
| E1 | F1 10.12.9 to 10.24.16 | the known data trap; compare with the customer's real result |
| E2 | F1 10.24.16 (our gated result) to 11.12.x | the 18 scanner blockers (CommunityCommons, own mail modules), Dojo vs React, SCSS `@import` |
| E3 | F1 10.12.9 to 11.12.x asked directly | the tool must chain via 10.24 and gate in between, not jump |
| E4 | E1 again with toolkit v2 | did the lessons from E1 to E3 stick |
| E5 | hold-out app (not F1) | stops us tuning the tool to one app |
| A/B | E1 with and without brain access | what the brain is worth for upgrades (same method as Test A) |

Scorecard per run: build errors, data diff FAIL / PASS*, REST and log verdict, smoke walk pass rate,
scanner blockers left, wrong claims of "done", human interventions, wall time, tokens.

## How I will work

- Build the ID check first and prove it on the known F1 evidence before any agent run.
- Every new script gets a control: a case it must catch and a case it must pass.
- Runs in a run folder (`<run>/app`, `<run>/work`, `<run>/tools`), for example ~/upgrade-lab/f1/runs/<run>/; never OneDrive.
  The container wrappers mount any folder through `UPG_ROOT` (E1 7). Toolkit in ~/Mendix/mxcli-project-toolkit/upgrade-toolkit/.
- Every fix is proved by `cd controls && make test`; the register of all items is FEEDBACK.md.
- One journal per run; findings go into the toolkit before the next run.
- Ports: base app 8380/8390, new app 8290/8300 (8080/8090 are taken).

## Risks and first housekeeping

- `mig-pg`: runapp.py now creates it with the named volume mig-pg-data and without `--rm` (E1 8). The create path is not
  proved by a control; keep a `pg_dump` of any frozen baseline anyway.
- mxbuild's theme compile has a fixed 30 s limit and fails under amd64 emulation plus load (E1 9): retry when quiet.
- Brain grep: filter out `_snapshot-*` and `_prefix` duplicates (E1 10, steps/triage.md).
- 10.x tools run in an amd64 container (slow: a 10.x build is about 5 minutes).
- `mxcli marketplace update` defects found earlier (MxModelReflection dropped cross-module associations) may block E1; log them, maybe an upstream issue after asking.
- Cost: agent runs use this Claude Code session, not the $18 API budget. Only the A/B brain test calls the API: estimate before running, flag above $10.

## Decisions needed

1. Hold-out app for E5: one of the mx-expert-services clones, or another app you have.
2. Okay to run autonomously for a few hours, reporting per run?
