# security-check fixtures — CAPTURE notes

Source: a fictional English-practice demo app (module `ToeicBuddy`, roles Learner/Trainer),
mxcli v0.28, Mendix 11.13.0, captured 2026-11-13. Nothing was edited.

- `base/lint.txt`, `<m>/lint.txt` — `mxcli lint -p <app>.mpr > lint.txt 2>&1` (banner lines included).
- `base/dump.txt`, `<m>/dump.txt` — the output of a small script that ran, in this order,
  `show project security`, `describe user role <X>` (4 roles), `show module roles in ToeicBuddy`,
  `show demo users`, `show security matrix` (the Administration / FeedbackModule / NanoflowCommons /
  MyFirstModule lines filtered out), and `show access on <E>` for each ToeicBuddy entity,
  each under a `## ...` heading. `mxcli-stub.sh` splits it back into per-command answers.
- `base/show-entities.txt`, `base/show-user-roles.txt` — verbatim `show entities` / `show user roles`
  of the unmodified app. Used for every scenario; `m1b` (an added entity with no access rules) gets
  ONE synthetic table row from the stub, because the capture of that scenario has the entity only in
  its access dump. `m4c` added a user role "Anonymous" that the baseline table does not list, so its
  module roles are not in that scenario's snapshot; the guest-access lines and lint findings carry it.

Scenarios (one planted mistake each, restored between runs):
`m3` own-rows restriction removed from Attempt · `m7` Learner may write Question.CorrectIndex/Explanation ·
`m4c` guest access on, Anonymous mapped to the Learner module role · `m2c` Learner granted the Team and
Bank pages and their data-source microflows · `m1b` new persistent entity with no access rules ·
`m6a` new module role Auditor (reads Attempt, sees Team) mapped to no user role ·
`m8bare` Learner's read on Attempt removed (the model no longer builds; read-only commands still work).

Checked before commit: grep for home paths, e-mail addresses, URLs, hostnames, IPs and the word USI found
nothing. The only proper nouns are the fictional app's own (ToeicBuddy, LoanDesk.mpr as the file name,
MxAdmin = Mendix's default admin user name, demo user names learner1/trainer1).
