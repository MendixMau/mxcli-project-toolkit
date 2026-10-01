# Context pack — controlled A/B bench, 2026-10-01

**Question:** when a build helper gets one generated file for its step (`project-bin/context-pack.sh`)
instead of a reading list, does it build as well or better, and does it cost less?

**Method.** All runs used a scratch copy of one real Mendix app (mxcli v0.24.0). The real model was
never touched. The app's module brief got a `### Build steps` table (five rows) and a folder plan.
Each run was a fresh drafting agent with the same model and one build step to do. It got either:

- **pack**: the step's `context-pack.sh` output (brief row, `mxcli brain brief` for the WHY, live
  DESCRIBE of every name the step reads or copies, folder plan), or
- **nopack**: the same brief row plus the usual reading list (brief, skills, "DESCRIBE what you need").

Each run was scored mechanically:

1. `mxcli check --references` on the script.
2. `check-page-shell` for page steps.
3. Exec into a **fresh** copy of the model, exit code.
4. `mx check` on that copy, counting only errors that were **not** there before (baseline error list).
5. A folder and access-rights check against the folder plan.

Token, tool-call and wall-time figures come from each agent's own usage report.

Two rounds:

- **r2**: microflow step, 3 pack and 3 nopack runs.
- **r3**: five step kinds on the pack. These were a new microflow (big), a change to an existing
  microflow (move it and keep its rights), a brief row with a typo'd name, a run with no brain
  available, and a page. The page step also got 2 nopack runs. After the first page runs, the
  fixes below were made and the page step was run twice more ("pack v2").

## Results

**Correctness.** All 16 runs passed `mxcli check` and exec with rc 0. Every run put its element in the
planned folder. The change run kept the original access rights. The typo run reported the bad name
instead of guessing (the pack exits 1 and names the missing element).

The one quality failure was on pages:

| Page runs | New `mx check` errors |
|---|---|
| pack (first version), run 1 | 1 × CE2421 |
| pack (first version), run 2 | 3 × CE2421 |
| nopack, runs 1–2 | 0 |
| pack v2 (with widget watch-out), runs 1–2 | 0 |

CE2421 means a `TEXTBOX` is bound to a DateTime or enumeration attribute. `mxcli check` passes it;
only `mx check` fails it. The pack showed the attribute types, but the helpers still reached for
`TEXTBOX`. The nopack runs happened to read a page skill that steers to `DYNAMICTEXT`.

**Cost.** Averages per run:

| Step | Arm | Runs | Tokens | Tool calls | Seconds |
|---|---|---|---|---|---|
| Microflow (r2) | nopack | 3 | 144k | — | — |
| Microflow (r2) | pack | 3 | 130k (−9%) | −38% | −41% |
| Page (r3) | nopack | 2 | 101.7k | 40 | 306 |
| Page (r3) | pack, all versions | 4 | 99.7k (−2%) | 29.5 (−25%) | 214 (−30%) |

**Tokens are noisy.** Pack page runs ranged from 69k to 173k. Without the 173k run, the pack average
is −18%. With two to four runs per arm, the token saving is **not proven**. Fewer tool calls and less
time held in every pair.

The other r3 pack runs (one each) used 113k–144k tokens, 12–19 tool calls, and 60–87 s.

## Conclusions acted on

- **Page widget watch-out** (`dfbb16a`). For a page step, the pack now lists each read entity's
  DateTime, Boolean and enumeration attributes under "not TEXTBOX-bindable", with the replacement
  widget. Result: 4 CE2421 errors over 2 runs before, 0 over 2 runs after. Microflow packs are
  byte-identical to before.
- **Impact list for changed elements.** For a step that changes an existing element, the pack now
  includes `mxcli impact` ("depends on — keep their contract"). The change helpers no longer search
  for callers by hand.
- **Brain headings nested under "## Why"**, so the pack reads as one document.

## Open items

- **Tokens not proven.** It needs more runs per arm, or a larger task where context reading is a
  bigger share.
- **Module-scale run** (next). It covers five dependent steps building one unbuilt slice: action
  microflow, detail page, open-detail microflow, data source, overview page. Each step runs on the
  model the previous step left. That is two arms, two lanes each, so 20 helper runs. It tests what
  this bench cannot: does the pack stay right when it is regenerated from a model that earlier
  helpers changed?
- **`page-fidelity.js` returned null (0/0) on this wireframe in every run.** This is an instrument
  gap and needs a separate fix.
- **Windows not run.** `context-pack.sh` is Bash 3.2 and uses no mac-only tools, but it has no Git Bash
  run yet.

## Where it belongs: CLI or toolkit

The pack does two different jobs. They belong in different places.

**1. Reading the model: belongs in mxcli.** Most of the pack is mechanical:

- DESCRIBE each name;
- `impact` for changed elements;
- `brain brief` for the slice;
- type-based warnings such as "these attributes can't take a TEXTBOX".

Today the script makes about 6–12 separate mxcli calls for this. A helper without the pack makes the
same calls itself, one tool call each. That is where its extra 10+ tool calls go.

mxcli R&D is already folding `mx check` and `mxcli check` into one call. The read side is the natural
twin:

| Today | One call |
|---|---|
| `mxcli check` + `mx check` (+ `check-page-shell`) | `mxcli check` that also runs the mx rules, e.g. CE2421, which `mxcli check` misses today |
| DESCRIBE × n + `impact` + `brain brief` + `context` | something like `mxcli context --for-step <names> --example <name> --slice <slice>`: definitions, dependents and WHY in one document |

In mxcli the type rules would live next to the checker that enforces them. The watch-out list would
then be generated from the same rule table as the CE2421 check, and could not drift from it.
`mxcli context` today gives relationships but no definitions, so it is the obvious command to extend.

**2. Deciding what a step needs: stays in the toolkit.** These parts carry project and process
knowledge that mxcli should not own:

- the brief's `### Build steps` row (what to build, what it reads, which element to copy);
- the folder plan;
- the dispatch wiring (`iterative-build-loop.md`, the `mdl-agent` stub);
- this bench.

**Split.** The toolkit decides *which* names go in. mxcli turns names into one context document. Then
`context-pack.sh` shrinks to about 30 lines: read the brief row, call mxcli once, add the folder plan.
Until mxcli has the command, the script stays as it is. The bench above is the acceptance test for
the CLI version: same scores, same or fewer tool calls.

**Upstream asks (drafted, for the maintainer to file):**

- `mxcli check` should flag CE2421 (TEXTBOX on a non-string attribute) and CE1571.
- `mxcli check` should validate enumeration values.
- A "context for a set of names" command, or `mxcli context` extended with definitions.
