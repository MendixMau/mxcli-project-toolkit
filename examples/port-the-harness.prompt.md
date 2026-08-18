# Prompt — port the journey-proof harness to another project and report what breaks

Paste the fenced block below into a **fresh** agent session started in the *target* project's root.

**Read this first, before you decide the run failed.** This exercise is not expected to produce a
green run, and a green run on the first attempt would be the suspicious outcome, not the good one.
**The deliverable is the portability report, not a PASS.**

## Fill these in before pasting

The prompt contains three placeholders. Replace every one; a session that meets an unreplaced
placeholder will invent a path.

| Placeholder | What to put there |
|---|---|
| `<TOOLKIT_ROOT>` | the path to this toolkit clone on the operator's machine |
| `<REFERENCE_IMPL>` | a project that already runs the harness, to copy the engine from — **or the literal string `NONE`** if there is no such project available. See the note below |
| `<TARGET_ROOT>` | the project being ported into (usually the session's own root) |

**If `<REFERENCE_IMPL>` is `NONE`** the engine cannot be copied and Steps 4-5 will fault. That is a
legitimate outcome and the report must say so — it is the single strongest piece of evidence for
shipping the engine with the toolkit. Do not simulate the steps.

## The known-gap list, and how to maintain it

The block below opens with the gaps that are **already known and measured**, so a fresh session can
tell a pre-existing failure from one it just caused, and nobody pays for the same discovery twice.

- Keep the list current. A stale gap list is worse than none: it teaches the reader to ignore it.
- When a gap gets fixed, **delete the entry** rather than marking it fixed.
- **CONDITIONAL — not yet true.** If the JavaScript engine is promoted into the toolkit's install
  manifest, most of Step 1 collapses into `sync-project.sh` and Gap 1 should be deleted along with
  the `<REFERENCE_IMPL>` placeholder. **At the time of writing the engine has NOT been promoted**;
  do not edit the prompt as though it has. Verify against the manifest before changing this.

---

```
Port the journey-proof verification harness into this project, run as much of it as will run, and
give me a portability report. This harness has run in very few projects. I expect it to break.
Finding out exactly WHERE and WHY is the whole point — a clean pass on the first attempt would mean
the instruments are not measuring, not that the port worked.

## The one rule, and it governs your report as much as it governs the harness

pass / fail / fault are never collapsed.
  pass  = measured, correct
  fail  = measured, wrong — the thing is broken
  fault = THE INSTRUMENT DID NOT RUN. Absent. Not green, not amber, not "skipped".
Exit codes: rc 2 = instrument fault, rc 1 = finding, rc 0 = pass.
An empty result set is NEVER a pass — `[].every()` is `true`, and that exact bug has shipped.

Apply this to yourself. "I could not get X to run" is a fault and must appear in the report as one.
Do not quietly drop a step you could not do, and do not describe a step you skipped as passing.

## Source of truth

Toolkit:        <TOOLKIT_ROOT>
Reference impl: <REFERENCE_IMPL>     (READ-ONLY to you — do NOT write into it)
This project:   <TARGET_ROOT>

Session-start ritual, do it first and tell me the commit:
  git -C <TOOLKIT_ROOT> pull --ff-only
  git -C <TOOLKIT_ROOT> rev-parse --short HEAD

Read, in this order, and do not skip ahead to running things:
  <TOOLKIT_ROOT>/skills/journey-proof.md          the spec — five rungs, seven mutants
  <TOOLKIT_ROOT>/skills/harness-architecture.md   the parts, the seams, the exit contract
  <TOOLKIT_ROOT>/skills/measured-claims.md        what is already measured — do not re-derive it
  <TOOLKIT_ROOT>/skills/journey-examples.md       worked examples + spec-vs-runner gaps
  <TOOLKIT_ROOT>/skills/fixture-seeding.md        preconditions — derive, don't interview

## KNOWN GAPS — confirm these, do not spend time rediscovering them

Gap 1 — THE ENGINE DOES NOT TRAVEL. The toolkit ships project-bin/verify-module.sh but NOT the
  JavaScript it drives: journey-runner.js, report-normalize.js, report-render.js, design-audit.js,
  monkey.js, config.js, helpers.js, otel.js. Confirm this is STILL true by checking the toolkit's
  install manifest, then copy what you need by hand from <REFERENCE_IMPL> into this project's
  tests/e2e/ and say exactly which files you copied. Every file you had to copy is evidence: a file
  copied by hand is a file the installer should have shipped.
  If <REFERENCE_IMPL> is NONE, this is a hard fault. Report it and continue with the shell layer.

Gap 2 — review-module.sh and page-scope.sh are not in the toolkit at all, so verify-module.sh's
  model-side composite rung faults permanently. Confirm and move on.

Gap 3 — the Stage 6 gate accepts only one artifact shape. See Step 6.

## Step 0 — record the starting state, so "it broke" can be attributed

Before installing anything: `git status --porcelain` and the current HEAD. If this repo is dirty,
say so and list what. You must be able to tell your breakage from pre-existing breakage, and
another session may be working here.

## Step 1 — install, then measure what the installer actually delivered

  <TOOLKIT_ROOT>/bin/sync-project.sh <TARGET_ROOT>

Then AUDIT the result rather than trusting the script's own output:
  - which scripts landed in bin/ — diff against <TOOLKIT_ROOT>/project-bin/
  - which agents landed in .claude/agents/
  - whether CLAUDE.local.md has a Wiring block, and whether every path in it RESOLVES. Test each.
    A path that does not resolve is a wiring failure, not a cosmetic one.

## Step 2 — does the harness fit this project's shape at all?

Do not write a journey yet. Answer these from the model, READ-ONLY, deriving each value rather than
assuming one:
  - Which .mpr? There must be exactly one in the project root. Zero or several is a hard stop, not
    a guess.
  - Which modules are first-party? `SHOW MODULES`; Source column empty = first-party. Subtract the
    Mendix-shipped set.
  - Is there a navigation profile, and what are its roots? Which roles can reach which pages? Those
    are your personas — do not carry a role name in from anywhere else.
  - Are there BRDs / a coverage ledger / module briefs? If not, requirement carry-through is
    IMPOSSIBLE here and the report must say so. That is a fault, not something to invent around.
  - Are there wireframes? If not, the wireframe-conformance check cannot run. The a11y and
    class-promotion checks still can, and that distinction is exactly what they exist for — DO NOT
    let a missing wireframe silently cancel design checking altogether.
  - Is the app runnable at all? Which port, which database, is it up right now?

If this project has no BRDs and no ledger, SAY SO AND CONTINUE. A harness that only works on a
fully-documented project is a finding about the harness.

## Step 3 — fixture and identity, before any journey

Run the derive-and-measure step rather than interviewing me:
  bin/fixture-manifest.sh        # 0 = sufficient · 1 = short · 2 = could not measure

Then read fixture-seeding.md §4 and ask me ONLY the questions genuinely undecidable from the repo.
Do not seed anything without my approval.

Resolve the app port and its OWNERSHIP before anything touches it:
  bin/test-stack-up.sh --check   # publishes APP_PORT and APP_OWNERSHIP to .claude/loop/stack.env
An unverified port means "a Mendix answered", not "our app answered". Refuse it unless I say
otherwise, and record which ownership you acted on.

The trap that has cost real time, so check for it EXPLICITLY and BEFORE you run anything: a login
helper that SILENTLY FALLS BACK to an admin account. If the harness can quietly run as admin, every
role-scoped assertion goes vacuously green and the run looks identical to a real one. Assert the
actual identity, not merely that login succeeded. If you find a fallback, report it before running.

Also read measured-claims.md §4 before you diagnose any login failure. "Sign in failed." is NOT a
credential error — it is the concurrent-session cap, and it is an instrument fault, not a finding.

## Step 4 — one journey, the smallest real one

Author ONE journey against the simplest genuine golden path in this project. Use
journey-examples.md's minimal example as the shape. Every selector must be `.mx-name-<widgetName>`
read from THIS project's `DESCRIBE PAGE` output — never invented, never carried over from the
reference implementation. Validate it:

  node <TOOLKIT_ROOT>/examples/validate-journeys.js <your-journey>

Then run it — passing ALL journey files to a SINGLE invocation; one invocation per file burns one
login session per journey and will hit the session cap. Then, and this is not optional, run the
positive control:

  node tests/e2e/journey-runner.js <journeys...> --positive-control

A green journey means nothing until you have watched the same checks go red on a mutant. If the
control cannot run here, the journey's result is `fault`, not `pass`. Say that plainly.

Two things the control run will do that you must plan for BEFORE you run it: it writes REAL ROWS to
the database (one transactional table went 50 -> 57 in a single control run), and its output must
go to the control artifact slot, NEVER into the real journey findings file — a control run has
overwritten a real walk's raw evidence in that shared slot before.

## Step 5 — the design instrument, and be careful how you cite it

  node tests/e2e/design-audit.js --static-only     # works with the app DOWN

This is a SEPARATE INSTRUMENT, not rungs of the journey. The journey ships FIVE rungs and SEVEN
mutants. journey-proof.md forbids citing the design instrument's "rung 6"/"rung 7" output in a
gate, a module brief or a report as though it were part of the spec: those checks pass their own
positive control but have never gone red on real work a human then agreed was a real defect. Run
them, read them, report what they say — but do NOT treat their output as a verdict.

Mandatory guard, mxcli #891: an object-list item's content-slot children are never read, so a data
grid nested inside an accordion describes as an EMPTY GROUP and a class sweep reports clean WITHOUT
HAVING LOOKED. Any page whose structural output has an empty content slot must be recorded as
`partially-read` -> fault, NEVER pass. If the audit reports a suspiciously clean sweep, suspect
this first.

## Step 6 — the gate, which is known to be wrong

  <TOOLKIT_ROOT>/bin/gate-check.sh <TARGET_ROOT> 6

Stage 6 currently accepts only `ui-reviews/ui-review-*.html`, so a project running this whole
harness FAILS the gate it was built to satisfy. Confirm that is still true here and report it. Do
NOT work around it by renaming a file to match the glob — that is manufacturing a pass.

## Constraints — these are not negotiable

- NO WRITES TO THE MODEL WITHOUT ASKING ME FIRST, every single time. That covers `mxcli exec`,
  `bin/exec.sh`, any `--mcp` write, and ALSO `mxcli test` and `mxcli docker check` — those two
  sound read-only and both mutate the .mpr.
- `describe`, `oql`, and `-c "SHOW ..."` / `-c "DESCRIBE ..."` are read-only and fine.
- Use the local `./mxcli` binary in the project root. Bare `mxcli` is not on PATH.
- Never fan out parallel agents that write against one .mpr.
- Do not write anything into <REFERENCE_IMPL> — it is your read-only reference.
- Do not "fix" the harness from inside a run. It is diagnostic. Findings come to me.

## What I want back

A PORTABILITY REPORT, not a test log. Four sections:

1. WHAT TRAVELLED — worked on a foreign project with no edits.
2. WHAT DID NOT — per item: what broke, the actual error, whether the cause is the toolkit, this
   project, or the reference implementation, and the smallest change that would fix it. Every file
   you had to copy by hand belongs here.
3. WHAT IS HARDCODED TO THE OTHER PROJECT — names, ports, module names, entity names, selectors,
   role names, credentials, absolute paths. This is the highest-value section: it is the difference
   between a harness and one project's test suite.
4. WHAT YOU COULD NOT MEASURE, and what it would take to measure it.

Rank every finding by how much it blocks. Distinguish clearly between a defect in the harness, a
defect in this project, and a genuine difference between the two projects that the harness should
accommodate. Do not blend those three — they go to different people.

An honest "6 of 11 steps faulted, here is exactly why" is a far better outcome than a green run I
cannot trust.
```
