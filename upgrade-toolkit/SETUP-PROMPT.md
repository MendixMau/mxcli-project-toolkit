# Mendix upgrade — setup prompt

Paste everything below the line into a Claude Code session (cloud session or local terminal).
Fill in the four `<...>` values first. Keep `MENDIX_PAT` in the environment, never in this text.

---

Upgrade my Mendix app with the upgrade toolkit, unattended, until the gate says PASS.

**Inputs**
- App: `<git URL of the app, or path to the folder holding the .mpr>`
- Target Mendix version: `<full version; default = latest LTS at its newest patch, as of 2026-10 Mendix 11.12 (11.12.5). Another version only if asked by name>`
- Test or sandbox systems for the external APIs the app calls: `<e.g. Opcenter test URL, or none>`
- Systems that cannot be stood in locally (excluded, listed in the verdict): `<e.g. Teamcenter, or none>`

**Setup**
1. Clone the toolkit: `git clone https://github.com/MendixMau/mxcli-project-toolkit ~/Mendix/mxcli-project-toolkit`
   (it holds the toolkit in `upgrade-toolkit/`, the release-note brain in `company-brain-test/brain/`, and the
   unattended pipeline in `pipeline/`).
2. Read `upgrade-toolkit/SETUP.md`, then run its one command:
   `bash upgrade-toolkit/bin/setup-container.sh ~/run1 <old version> <target version>` and `source ~/run1/upg-env.sh`.
   Find the old version with `upgrade-toolkit/bin/mxversion.py` on the app's .mpr.
   `MENDIX_PAT` must already be set in the environment; if it is not, stop and tell me.
3. Put the app under `~/run1/app` as its own git repo.
4. Check the instruments: `cd upgrade-toolkit/controls && make fast`. A red control means the toolkit is broken: stop
   and report it, do not upgrade with it.

**Run**
5. Follow `upgrade-toolkit/SKILL.md` from step 1. It is the source of truth for every step, stop rule and verdict word.
6. Use the brain for release-note impact (`release_impact.py`; `UPG_BRAIN` only if the brain lives elsewhere).
7. External APIs, in this order: (a) the test systems I listed above, (b) responses recorded from a real system,
   (c) the API stand-in (`bin/apimock.py`, same stand-in for the old and the new app) only where no test system is
   reachable. A gate on the stand-in ends at best in `PASS (on stand-in APIs: ...)`: a conditional PASS, to be run
   again on real test systems before go-live. Only the systems I listed above may be excluded; any other API the
   stand-in cannot classify stays INVALID.

**Loop until PASS**
8. After each gate run (`bin/gate.sh`):
   - FAIL on a real difference in the app → fix the app as a human upgrader would, commit, rerun the gate.
   - INVALID because the toolkit cannot judge something → write it in `TOOLKIT-FEEDBACK.md` with evidence, work
     around it only where SKILL.md allows, rerun.
   - Stop at PASS, or `PASS (except <system>: N items)` / `PASS (on stand-in APIs: ...)` (never reported as plain
     PASS), or after 5 rounds with the remaining blockers listed.
9. Never weaken a gate: never round INVALID up to PASS, never skip a check to get green.

**Deliver**
10. Write `SCORECARD.md` (verdict per gate rung, with evidence paths), `HANDWORK.md` (what you changed by hand and
    why) and `TOOLKIT-FEEDBACK.md` (toolkit gaps), and push the app branch. Never push customer data into the
    toolkit repo.
