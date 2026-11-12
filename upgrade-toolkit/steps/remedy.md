# Step 5b: remedy (options instead of a dead end)

Run after the gate (steps/gate.md) and before the report (Step 6). The gate says PASS, FAIL or INVALID. A FAIL rung, a
kept module or an open release-impact row used to end the run there. This step turns each blocker into a decision card
with the ways out, tries the cheapest safe mechanical one itself, gates again, and hands the rest to a person.

Why: the same blockers come back across apps, and so do the ways out. Notification service 9.24 to 10.24: Data Widgets
3.11.7 lost the drop-down filter captions and doubled the paging text; the team reverted Data Widgets by hand. 10.24 to
11.12: a private DropdownContainer widget calls findDOMNode and has no newer version. Asset Console 10.12 to 11.12:
3D Viewer 4.0.0 crashes with React error #525; the fix is a licensed download. Kept modules (local edits, an
Administration update that drops Account rows) were listed and nothing said what to do next.

## Run

```sh
python3 $B/remedy.py --work $W --app app/          # newest $W/gate-*/gate-summary.md, kept.txt, release-impact.md
python3 $B/remedy.py --work $W --app app/ --next   # only the next action per open card
```

Optional inputs: `--gate F`, `--kept-file F`, `--release F`, `--replacements F.json` (replacement_check.py --json),
`--dojo F.json` (dojo_report.py --json), `--finding TEXT` or `--findings F` (a blocker found outside the gate, such as a
hand-opened page or an ASSUMPTIONS line), `--from VER --to VER`. Output: `$W/remedy-cards.md` and `$W/remediation.json` (QI-5: never `remediation.md`; on a case-insensitive disk it is the same file as the merged `REMEDIATION.md` a brief asks for). `--gate` takes the gate summary or the gate folder that holds it.
remedy.py only reads; it never changes the app. `--keptdeps F` adds a saved keptdeps.py output (RT-8);
`--kept-snapshot F` and `--reset-kept-snapshot` steer the kept-list snapshot (RT-9, below).

Exit: 0 = no open card, 3 = an AUTO-TRY option is waiting, 1 = only HUMAN decisions are open, 2 = input error (also a
remedies.tsv row that breaks the rules below).

## The card

One card per blocker, matched against `playbooks/remedies.tsv` (one row per option; the specific rows come before the
generic ones). Each option has: action, effort (S, M, L), risk, evidence source, the test still needed, and the mode.

| option | meaning | mode |
|---|---|---|
| A | keep or pin the old version of the module or widget for this rung (a stepupdate plan line, never a git revert of the binary MPR) | AUTO-TRY when the row has an apply and a regate |
| B | swap: another widget, module or version, or a mechanical repair that keeps the new one | AUTO-TRY when the row has an apply and a regate |
| C | rebuild: own code, a new widget, a migration; or a proven mechanical fix (verified yes, such as the global .sr-only theme rule) | HUMAN, AUTO-TRY only when verified says yes |
| D | stay on the source version (9.x or 10.x: the .24 LTS of the source major) until B or C is done | always HUMAN |

A blocker with no specific row gets a generic card (kept with edits, kept unproven, regression with no named cause,
React 19 widget, Dojo). An open release-impact row with no specific row, an INVALID or required NOT RUN rung, and a FAIL
whose report says "instrument not measuring" are instrument gaps: listed under the cards, no card, because they need a
measurement, not a remedy.

## Ranking and evidence (RT-1, RT-3)

The `verified` column of remedies.tsv carries the evidence: `yes (run)`, `partial (run)`, `no`, `-`, or
`disproven (run: what broke)`. Options are listed and tried in evidence order: verified yes first, then partial, then
no or none, disproven and tried-FAIL last; effort breaks a tie, the letter only after that. In the notification service
remedy trial (notif RT r1) the letter order put the pin first; it forced Administration to 4.2.0 and broke every
Data grid 2 header filter ("Unable to get filter store"). That row is now `disproven`: remedy.py prints it with
`[DISPROVEN: ...]`, the table refuses AUTO-TRY on it, and the HUMAN choice lists it apart.

## AUTO-TRY rules

The pipeline may apply an AUTO-TRY option itself only when all of these hold:

1. It is mechanical: one recipe on its own branch (`remedy_apply.sh` makes `remedy-<card>-<option>`). No data
   migration, no new code. A FAIL abandons the branch; the gate branch is never rewritten.
2. verified is yes or partial. `no` or `-` makes it HUMAN (remedy.py says why in `[HUMAN: ...]`).
3. A kept module with a data line (idcheck persistence loss, rows dropped) is never AUTO-TRY: remedy.py demotes it.
4. A row whose test names keptdeps (prove a kept module unedited, then update it) needs keptdeps clean for the other
   kept modules: none of them may call the subject (RT-8: GenAICommons proved clean, the kept MxGenAIConnector that
   calls it gave 19 errors). remedy.py runs `keptdeps.py APP --kept <the others> --updated <subject>` with `--app`, or
   reads `--keptdeps F` and `APP/.stepupdate/keptdeps.txt`. A dependent found adds option B<n>: update both in one step
   (HUMAN). Without `--app` and without a keptdeps file the option stays HUMAN ("keptdeps not shown clean").
5. Evidence order first (above), one option at a time.
6. Gate again on the rungs the row names, re-seeded from the original gate so the untouched rungs keep their rows:
   `gate.sh --only <rungs> --seed-from <original gate folder>` (remedy_apply.sh does it).
7. Record the result in `$W/remedy-tried.txt`, one line: `<card key> <option> PASS|FAIL <evidence> [eye=<shot>] [# note]`.
   Something you tried that is not an option of the card goes in as `<card key> X:<label> PASS|FAIL <evidence>` (V3D-6): it is
   listed as an extra row and never resolves the card; a card option letter is never borrowed for it.
8. Run remedy.py again. A PASS closes the card (RESOLVED); a FAIL moves the card to the next option.

Everything else is HUMAN: the person picks an option on the card. D, a rebuild, licensed downloads, a private design
system owner, and anything that touches data are always HUMAN.

## Widget remedies (V3D-7 to V3D-10, QI-4)

- Triage a widget swap fast: replace `web/widgets/<path>` in a STARTED app's run folder with the candidate package's files
  (delete the `.gz` twins), reload, probe. It served exactly the package's files and predicted the built result (3D Viewer
  5.3.0: #525 both ways). It needs the same XML properties; the commit still needs `mx update-widgets`, `mx check` and a build.
  Only the winner goes through the build.
- Test the page with no external system first (the mock path: UseIntegration off, demo data reset, a search that opens the
  panel; a stronger check than the connector path, where a guard may deny the call). A widget probe checks: no "Could not
  render widget", no React error #525 or other console error or pageerror, a canvas or the widget's own nodes, and the
  content visible by eye in the screenshot. Then one guarded external run that must show the same fallback as the baseline.
- Card option D (stay) is proven by the blocked page rendering on the stay version, not by "the rung converted and started"
  (V3D-9: the 10.24 rung never opened the 3D panel). For a React symptom read the stay runtime's React major in
  `mxclientsystem/mxui/mxui.js` (below 19: 10.12.2 and 10.24.27 are 18.2.0). Keep the stay rung's mda, or its commit and build
  command, until the card is closed; rebuilding it later costs a full build.
- Patching a vendor package (C2 on `react-bundled-viewer3d`) is HUMAN only: a lab proof and stopgap, never a delivered fix
  without the owner. The patched file still matches row R36: accept it by checksum (`replacement_check.py --accept`).
- A blank canvas after a restart on the SAME database is the harness, not a new failure: `runapp.py start` unpacks the mda
  again and a FileDocument's contents live in `run/<name>/data/files`, so the rows stay in Postgres and the files are gone.
  Use a fresh database copy (BACKLOG #104 makes runapp say so).
- Widget blockers with no newer clean version (List view controls and mx.logger) have the card `widget-mxlogger`: B newer
  clean version (check it with replacement_check R38 first), B2 rebuild on Data Widgets, B3 local shim, C fork, D stay.

## By eye (RT-6)

A row whose regate names the pseudo-rung `eye` fixes a visual symptom that the instruments can pass: shotdiff passed a
doubled paging text at 4.8 percent, smoke passed in-widget error alerts. `eye` is never sent to gate.sh. A PASS of such
an option counts only with `eye=<shot path>` in its tried line (the shot a person looked at); without it the card stays
HUMAN.

## Apply runner: remedy_apply.sh (RT-10)

```sh
bash $B/remedy_apply.sh --config $W/remedy.conf <card key> <option>          # AUTO-TRY option
bash $B/remedy_apply.sh --config $W/remedy.conf <card key> <option> --human  # an option a person chose
bash $B/remedy_apply.sh --config $W/remedy.conf --finish <card key> <option> PASS --eye shots/after.png
```

remedy.conf (KEY=VALUE): APP, WORK, GATE_CONF, CHECK_CMD, BUILD_CMD (placeholders {MPR} {MDA} {APP}), optional
GATE_SEED, WIDGETS_CMD, CLEANUP_CMD, APPLY_DIR (recipes `<card key, : as _>.<option>.sh`, default $W/remedy-apply),
MIN_FREE_GB, RETRIES, REMEDY_ARGS (see the script header). It reads the option from `$W/remediation.json`, refuses a
HUMAN option without `--human`, an option already tried, and a dirty app. Then: branch, recipe, a report of every
widget mpk the recipe moved (RT-2), widget refresh, mx check, build to a labelled mda with a disk check, gate
`--only --seed-from`, then the tried line, the cleanup and a remedy.py rerun.

Exit: 0 = PASS recorded, 1 = FAIL recorded (app back on the base branch, the option's branch kept as evidence),
2 = input or tool error (nothing recorded; a missing or failing recipe is not a verdict), 4 = a regate rung INVALID or
NOT RUN (fix it, rerun with `--from gate`; RT-11: a smoke walk that hits GATE_TIMEOUT is INVALID and its line says
"raise GATE_TIMEOUT"), 5 = paused for a person: the regate names eye, or the release rung is not PASS.
`$W/remedy-todo-<card>-<option>.md` lists the shots and rows and the `--finish` commands.

## Kept list snapshot and stale tried lines (RT-9)

A later stepupdate pass rewrites `APP/.stepupdate/kept.txt`; in the trial that dropped a known FAIL silently. When the
kept file is that default (or `--kept-snapshot F` is given), remedy.py keeps a snapshot (`$W/remedy-kept-snapshot.txt`
by default). A module in the snapshot but not in the current list keeps its card with `WARN kept list shrank`, unless a
tried PASS resolved it; `--reset-kept-snapshot` starts again from the current list. A tried line for a card the run no
longer generates prints a WARN too. A kept line "skipped by --skip" is a choice, printed as `CHOICE`, not a gap (RT-13).

## Done when

`remedy-cards.md` exists for the last gate run, every AUTO-TRY option is tried or recorded, and the report (Step 6)
shows the cards. The verdict stays what the last gate said: a card never turns a FAIL into a PASS; only a new gate run
does.
