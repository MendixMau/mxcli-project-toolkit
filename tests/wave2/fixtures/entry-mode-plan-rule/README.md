# entry-mode-plan-rule fixtures

`PROJECT.md` and `intake.md` are captured verbatim from `bin/init-project.sh` (toolkit commit
`ff4103b`, 2026-11-17) run into an empty git repository with `MXTK_NO_GUIDE=1`; only the project
name in the H1 was changed to `Fixture`. They are the register and intake a project really starts
with, so the position reader is tested against the scaffold's own HTML comments (which name
`--adopt 5` and `Build type`) and the bold `**Stage P — Kickoff**` readout, not against input
written to match the parser. `tests/wave2/test-entry-mode-plan-rule.sh` appends the one line
each case declares.
