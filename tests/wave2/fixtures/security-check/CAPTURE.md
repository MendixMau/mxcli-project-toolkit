# security-check fixtures — CAPTURE notes

Source: a fictional English-practice demo app (module `ToeicBuddy`, roles Learner/Trainer),
mxcli v0.28, Mendix 11.13.0, captured 2026-11-13. Raw captures are verbatim unless a line below says
otherwise; one filter was applied and is described next.

- `base/lint.txt`, `<m>/lint.txt` — `mxcli lint -p <app>.mpr > lint.txt 2>&1` (banner lines included).
- `base/dump.txt`, `<m>/dump.txt` — the output of a small script that ran, in this order,
  `show project security`, `describe user role <X>` (4 roles), `show module roles in ToeicBuddy`,
  `show demo users`, `show security matrix` (FILTERED: the lines naming the Administration, FeedbackModule,
  NanoflowCommons and MyFirstModule roles, microflows and pages were removed by hand to keep the fixture on
  the app's own module; the unfiltered capture is `base/security-matrix-unfiltered.txt`), and `show access on <E>` for each ToeicBuddy entity,
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

Checked before commit: grep for home paths, e-mail addresses, URLs, hostnames, IPs and company names found
nothing. The only proper nouns are the fictional app's own (ToeicBuddy, LoanDesk.mpr as the file name,
MxAdmin = Mendix's default admin user name, demo user names learner1/trainer1).

Added in the review round (all taken read-only with the same mxcli v0.28 from the same demo app):
- `list-rules.txt` — verbatim `mxcli lint --list-rules -p <app>.mpr` with the project'"'"'s `.claude/lint-rules/` in place.
  `list-rules-no-starlark.txt` — the same command on a copy of the project that has no `.claude/lint-rules/`
  (SEC004-SEC009, SEC014, CONV006, CONV007 are absent there). `mxcli init` in that copy restores them (checked).
- `base/security-matrix-unfiltered.txt` — verbatim `show security matrix`, nothing filtered.
- `base/access-other-modules.txt` — verbatim `show access on <E>` for the seven non-System entities outside
  `ToeicBuddy` (the secdump had only covered `ToeicBuddy`). The stub falls back to it, because the real tool
  answers for every entity and the script now refuses an empty answer.
- Scenarios made at test time (`two1`, `two2`, `unk`, `shape1`-`shape4`) are the captured base dump with one
  line edited by the test (a restriction continued on a second line, an extra line in a rule, a heading
  renamed); the test file says which. They are edited captures, not new captures.
