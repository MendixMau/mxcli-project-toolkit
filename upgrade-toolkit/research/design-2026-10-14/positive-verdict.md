# Positive verdict wording for the upgrade toolkit: design (read-only research, nothing edited)

Machine codes and exit codes stay as they are; only a human layer is added. `Overall: **X** (exit N)` stays the first line of gate-summary.md (controls grep it, line 3177-3212).

## 1. Vocabulary: machine code -> report word (exact phrasing)
| code (rung) | report word | sentence the report prints |
|---|---|---|
| PASS | verified | `<rung>: verified (<one line>)` |
| PASS* | verified, with accepted differences | `<rung>: verified, N differences accepted in writing (see <accept file>)` |
| FAIL, rung output has any REGRESSION / FAIL / START_FAILED / NEW_ERROR / GUID_CHANGED line (or cannot tell) | regression to fix | `<rung>: REGRESSION to fix: <count + what>; worked on the old app, not on the new one` |
| FAIL, every open line is REVIEW (SCREEN/EFFECT/const/idcheck REVIEW), no FAIL line | needs a decision | `<rung>: needs a decision: N differences to look at (<accept file> closes them)` |
| INVALID, NOT RUN (required) | not measured yet | `<rung>: not measured yet: <reason>; closes when <input/fix>` |
| INVALID from an open human item (release rows open, widgets UNRENDERED, process `=> ?`, defect w/o evidence) | needs a decision | as above, naming the decision file |
| EXCEPT / PASS (on stand-in ...) | verified on stand-in, real system pending | `<rung>: verified except N items that need <system>; closes on the vendor test system` |
| NOT RUN (optional) | not in scope | listed, not counted |
The word "REGRESSION" is never softened: it stays upper case and is listed first. "FAILED" as a run label disappears from prose;
"FAIL" stays in the table's verdict column and in exit lines. Default split is conservative: a FAIL rung is "needs a decision" only when
its .out positively shows REVIEW > 0 and FAIL/REGRESSION = 0; anything unparsable is "regression to fix".

## 2. "X% complete": one primary number
Primary = **checks closed / checks owed**, where a check is one gate rung in scope (required rungs + optional rungs that were configured)
**plus one fixed item "owner sign-off"**. Closed = PASS or PASS*. Everything else is pending, in the denominator, never the numerator.
Why rungs: the denominator is fixed by `RUNGS` in gate.sh (line 94) and `optional()` (line 180), so it cannot be inflated by adding easy
journeys or shrunk by dropping a hard one; gate.sh already counts it (`npass`); it maps 1:1 to the existing table. Item counts
(journeys 99/101, pairs, release rows) are printed per pending rung as the second level, and action coverage (`coverage 101/280`) stays
a separate number that is never mixed in. Sign-off makes the honest maximum before approval (N-1) of N, never 100% by machine alone.
Arithmetic: integer floor (`100*closed/owed`), fraction always printed beside it: `6 of 11 checks closed (54%)`. No rounding up.
Worked example (10.24 -> 11.12.6, widgets configured, rest/apis not configured): owed = 9 required + widgets + sign-off = 11.
build PASS, idcheck PASS, const PASS* (1 allow line), data PASS, logdiff PASS, smoke PASS -> 6 closed.
journeys FAIL (`2 regression`) -> regression; screens FAIL (`screens: 140 PASS, 2 PASS*, 3 REVIEW, 0 INVALID`) -> needs a decision;
release INVALID (`auto: 31, human: 4, open: 2`) -> needs a decision; widgets INVALID (3D viewer UNRENDERED) -> stuck item; sign-off pending.
```
Progress: 6 of 11 checks closed (54%). 1 with REGRESSIONS to fix, 3 need a decision, 0 not measured yet, owner sign-off pending.
REGRESSION to fix (1): journeys: 2 journeys pass on the old app and fail on the new one (proc-p03-02, create-save-Order); repair, then --only journeys
Needs a decision (3): screens: 3 pairs to look at -> shot-accept-journeys.txt | release: 2 rows open -> release-impact.md |
  widgets: Viewer3D.mpk renders on no page -> stuck item S-1 (options asked in chat)
Pending sign-off: owner approves in DECISIONS.md after the above close.
```

## 3. Stuck-item step (new `steps/decide.md`, ~40 lines)
Triggers (an item that cannot be upgraded as-is, not a measurement gap): localedits RED module on the plan (SKILL stop rule 1); stepupdate
kept module / data-bearing idcheck finding; convertcheck or repair leaving a Java action that no longer compiles; vendorjava COMMENTED-OUT /
EMPTIED; dojo_report "can't move"; replacement_check row still hitting a deprecated module; widgets UNRENDERED or a widget crash on the
new client; a REGRESSION still open after two repair attempts on the same page. Not triggers: INVALID from missing inputs (fix the
measurement), a first-seen regression (repair first), REVIEW pairs (accept-file judgement, section 4 of READING-THE-VERDICT).
Options per kind (max 4 + "something else"):
| kind | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Marketplace module | keep old version (kept list) | replace with Marketplace equivalent (`replacements.tsv` row) | rebuild locally, drop the module | hand to a person (name) |
| page / snippet | keep as converted, accept the look (PASS* path) | rebuild with the new widgets | remove if dead (`impact_map`) | hand to a person |
| widget (.mpk) | keep old package, accept risk | swap to successor (`dojo-successors.tsv`) | rebuild as pluggable / native | hand to a person |
| Java action / vendor Java | keep old jar, pin | port to the new API | replace with Marketplace / microflow | hand to a person |
Asking: Claude Code uses AskUserQuestion (one question per item, options above, evidence path in the question). Other harnesses print the
same as a numbered markdown list with "5. something else". Either way the agent ends its turn and waits ("ask, then stop"); recommending
an option from evidence is fine, choosing silently is not. UNATTENDED runs keep the existing default (keep at old version) and record it ASSUMED.
Record: `$W/DECISIONS.md`, one line per item, append-only:
`S-1 | widgets: Viewer3D.mpk | widget | swap to successor | <reason> | <who> | CONFIRMED (or ASSUMED) | closes by: widgets rung PASS`.
How it counts: a decision never closes a check. It moves the item from "needs a decision" to "decided, pending <closes by>"; the rung's
numerator changes only when the gate re-measures it PASS/PASS*. "Keep old version" items stay listed as "kept (S-n)" in every later report
(SKILL: a kept module is never reported as upgraded). Sign-off cannot close while DECISIONS.md holds an ASSUMED line or an unnamed hand-off.

## 4. File edits (minimal)
- `bin/gate.sh` 469 keep. After it add: `echo "Progress: $nclosed of $nowed checks closed ($((100*nclosed/nowed))%). $nreg with REGRESSIONS to fix, $ndec need a decision, $nmeas not measured yet, owner sign-off pending."`
  with `nowed=$(( required_in_scope + optional_configured + 1 ))`, `nclosed=$npass`, and a `human_of RUNG` helper next to `verdict_of`
  (line 290) that returns regression/decision/unmeasured by the section-1 rule. 483-487 (legend): prepend one line
  `Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix, or needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet.`
  489 keep; after it echo the Progress line. 491 loop: print `human_of` word before `$s`.
- `READING-THE-VERDICT.md` line 17 `| verdict | exit | means | you do |` -> `| verdict | exit | report says | means | you do |`, rows 19-22
  gain `verified` / `verified on stand-in, real system pending` / `REGRESSION to fix or needs a decision` / `not measured yet`. New
  section 2b "The progress line" (denominator, sign-off, floor) and a row in section 4: `| stuck item | options asked in chat | DECISIONS.md |`.
- `steps/gate.md` 220 `Verdict words: PASS only under the SKILL definition of done, otherwise FAIL or INVALID.` ->
  `Verdict codes: PASS only under the SKILL definition of done, otherwise FAIL or INVALID. Report words and the progress line: READING-THE-VERDICT.md section 2; a FAIL with any REGRESSION line is said "REGRESSION to fix", never "pending".`
  Step 6 list item 1 `FAIL list:` -> `REGRESSION list (FAIL):`; new item 0 `Progress line, then DECISIONS.md items (steps/decide.md).`
- `SKILL.md` description `to an honest PASS / FAIL / INVALID report` -> `to an honest progress report (N of M checks closed; machine codes PASS / FAIL / INVALID)`;
  table row `| (decide) | steps/decide.md | every stuck item asked, answered in DECISIONS.md |`; stop rule 133 `ask.` -> `ask (steps/decide.md).`
- `bin/cloud/upgrade-pipeline.sh` 172 `Rule: a FAIL or INVALID below is not a pass.` -> `Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing.`

## 5. Risks and guards
- Risk: "needs a decision" absorbs a real regression (screens REVIEW of an empty chart, E4/E5b). Guard: the split uses the instrument's own
  counts, unparsable -> regression; a REVIEW is closed only by a pinned accept line someone wrote after looking (existing rule, gate.md 117).
- Risk: percentage reads high while a regression is open (10/11 = 90%). Guard: the Progress line names REGRESSION count before anything
  else, and the overall code/exit stay FAIL/1; no "complete" word is ever printed while nfail > 0.
- Risk: decisions inflate the numerator. Guard: numerator is `npass` only; DECISIONS.md is never read by the count.
- Risk: sign-off forged by an agent. Guard: same as `status: confirmed`: only a human writes APPROVED; ASSUMED blocks it.
- Controls (stub gate, `gcase`):
  `ctl gate-regression-never-complete-catch 1 'Overall: \*\*FAIL\*\*' 'Progress: [0-9]+ of [0-9]+ checks closed' 'REGRESSIONS to fix' '!0 with REGRESSIONS' '!complete' -- gcase regr GATE_STUB_RC_run_journeys=1 GATE_STUB_OUT_run_journeys='journeys: 99 PASS, 2 REGRESSION'`
  `ctl gate-review-only-decision-pass 1 'needs a decision' '!REGRESSION to fix: .*screens' -- gcase rev GATE_STUB_RC_shotdiff=1 GATE_STUB_OUT_shotdiff='screens: 140 PASS, 0 PASS*, 3 REVIEW, 0 INVALID'`
  `ctl gate-unparsable-fail-is-regression-catch 1 'REGRESSION to fix: .*logdiff' -- gcase unp GATE_STUB_RC_logdiff=1`
  `ctl gate-all-green-never-100-pass 0 'Progress: 12 of 13 checks closed \(92%\)' 'owner sign-off pending' '!100%' -- gcase pass ...` (as gate-all-pass)
  The first one is the one asked for: it fails if a run with a regression ever prints "complete" or a zero regression count.
