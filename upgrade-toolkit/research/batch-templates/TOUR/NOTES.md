# TOUR (Product Tour / Guided Maker Experience Template, public Marketplace template)

- Version path: 9.4.0.24572 -> 10.24.0.73019 -> 11.12.5. Rung 1 not started (proposal unsigned).
- Progress line: none (no gate ran). Changes line: none; nothing in the app model changed.
- Steps done: fetch, triage, baseline, basewalk (5 PASS, 0 FAIL, 0 INVALID: 3 role logins, sign-out, create-save), propose (written, section 6 NOT signed). No login override file was needed this time (BT-3 fix).
- BT-5 fixed and field-proven here. Before: create-save FAILed on the old app (duplicate key on the first created Approvals.Request). Cause: `mendixsystem$entityidentifier.object_sequence` is the NEXT id the runtime hands out, inclusive; seed_pg set it to the last seeded id (6), the runtime allocated 6..105 and its first id 6 collided with seeded row 6. Control run on the same frozen database: object_sequence 6 -> create-save FAIL; changed to 7 -> create-save PASS. Toolkit commit 78dbdcca (seed_pg.py and seed_snapshot.py set last id + 1; controls seed-sequence-next-pass/catch, mutation-tested, run with `--only`). The frozen database of this run was patched to 7 by hand to prove it; a fresh baseline would seed 7 itself.
- Proposal: 4 module updates by the toolkit (Atlas_Core 3.0.2 -> 3.21.1, Atlas_Web_Content 3.0.2 -> 3.9.0, MendixSSO 2.3.1 -> 10.6.2, WorkflowCommons 1.2.0 -> 3.12.1), 2 decision items (P-1 renamed module DataGrid to DataWidgets, recommendation: install the new module; P-2 Atlas_Core themesource edits, RA-6 option 2), 5 person-anyway items.
- RA ids: RA-6 (P-2, tried once, recipe not run), RA-16 and RA-14/15 look-ahead, not exercised.
- Why it stopped: the signing line. The classifier refused this worker's write of the sign-off to a PROPOSAL.md (for CMPL; not retried for TOUR, per the lead).

## For the owner
- Sign `PROPOSAL.md` section 6 (answers to P-1, P-2 default to the recommendations), then `bash upgrade-toolkit/bin/cloud/resume.sh <run folder>`. The run folder `night/druns/TOUR` is kept (disk permitting) for that.
- Rung 2 (11.12.5) is not run.
