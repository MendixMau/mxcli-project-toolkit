# Standard prompts

Copy one, fill the `<...>`. Each says when to use it. Rules that apply to all: commit explicit paths (never `git add -A`), no customer or app names in the repo (code names only), no merge, never push to main.

## 1. Backfill the run log
When: a machine has old run folders (for example `~/upgrade-lab`) whose runs are not yet in `upgrade-toolkit/FIELD-RUNS.md`.

```
Backfill the field run log from the run folders on this machine.
1. python3 -I upgrade-toolkit/bin/runlog.py --explain ~/upgrade-lab     (per folder: LOGGED / WOULD-ADD / SKIPPED <reason>)
2. Add each SKIPPED folder the reason allows, with code names: ... --backfill ~/upgrade-lab --match <part of the folder path>
   --app <CODE> --type "<app type>" [--run-id <ID>] [--verdict-from SCORECARD]   (dry run first; the last flag is for a folder
   that has a SCORECARD verdict but no gate-summary.md). Add --verbose to see where each version came from.
3. python3 -I upgrade-toolkit/bin/runlog.py --backfill ~/upgrade-lab --write   (then the same per-folder commands with --write)
   then python3 -I upgrade-toolkit/bin/runlog.py --summary   (rewrites "Per app (latest run)" at the top of FIELD-RUNS.md)
4. bash upgrade-toolkit/bin/customer_names_check.sh upgrade-toolkit   (must print "customer-names: clean")
5. Commit FIELD-RUNS.md with explicit paths on a branch `field-runs-log`, push it, open a PR. Do not merge.
6. Reply with the PR link and the app and run counts (rows added, duplicates skipped, refused).
```

## 2. Start an upgrade
When: a new app to upgrade to the latest LTS.

```
Upgrade <app, code name> from <source version> to the latest LTS. Read upgrade-toolkit/SKILL.md and follow it. Run
the pipeline up to the proposal step, put the upgrade proposal (PROPOSAL.md) in front of me and wait for my sign-off
before anything changes in the app model. Set UPG_APP_NAME=<code name> and UPG_APP_TYPE="<app type>" for the run log.
Report with the progress line (N of M checks closed), never as "failed".
```

## 3. Resume after a container restart
When: the session or container restarted mid-run; run folders in cloud containers are lost, pushed branches survive.

```
Resume the upgrade of <code name>. Read DECISIONS.md in the run folder and the commits on branch <branch> to see what
is done. Check state/*.done, then resume the pipeline from the first step that is not done:
bash upgrade-toolkit/bin/cloud/upgrade-pipeline.sh <same arguments> --from <step>. Do not repeat decisions already
in DECISIONS.md. Commit and push the branch after each milestone.
```

## 4. Handover to another agent
When: work moves to a new session or person.

```
Read upgrade-toolkit/HANDOVER.md, then upgrade-toolkit/SKILL.md. Then take the open work in the order HANDOVER.md
lists it, starting with item 1. Run scoped controls only (--only REGEX), commit explicit paths, merge main before
opening a PR. Reply with what you took, what is done and what is still open.
```
