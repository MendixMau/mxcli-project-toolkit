# Skill: monkey-test — the crash net, and what a clean run is not allowed to mean

**Applies to:** any built module with a page a user can type into.
**Instrument:** `tests/e2e/monkey.js` (fetches facts only — this file holds every judgement).
**Runs after** the module's journeys pass. Never before: a monkey run against a broken
module reports the breakage as a crash and buries the real finding.

---

## What this is for, honestly

Fuzzing is **not** where the yield is in a Mendix stack. Measured on a comparable project:
the monkey pass scored **0 fail / 27 pass / 5 info** while the scripted journeys found **all
nine** real defects. Keep it anyway, for exactly one class the journeys cannot reach: an
**unhandled exception on input nobody thought to type**.

State that ratio in the report. A clean monkey run reads as "the app works" to anyone who
does not know the base rate, and that misreading is worse than not running it.

> **A clean run means:** no unhandled crash on *these inputs, at this seed*.
> **It does not mean:** the module is correct, the validation is right, or the data is safe.

## When to run it

| Situation | Run? |
|---|---|
| Module's journeys are green | **Yes** — this is the slot |
| Module's journeys are red or faulted | No. Fix those first. |
| Before a demo or a cutover | Yes — crash class is exactly the demo-killer |
| As evidence a module is done | **No.** It is not that evidence and must not be cited as it. |
| On a page with no free-text input | Skip, and record it as `n/a — no input surface`, not as a pass |

## The three rules

**1. Every run is seeded, and the seed goes in the finding.**
An unreproducible fuzz finding is worse than none — it burns a debugging session on noise.
The instrument prints `MONKEY_SEED=…` and every finding carries it. A finding reported
without its seed is not triageable; send it back.

**2. Payloads are never shell-interpolated.**
The nasty strings are XSS- and SQL-shaped by design. Concatenating one into a Bash command
fires the injection *in the harness*, where it proves nothing and can do real damage. They
travel base64 and decode inside the page. If you are ever tempted to echo a payload into a
shell, stop — that is the bug the payload was testing for, and you just wrote it.

**3. Diagnostic only. It fixes nothing and files nothing.**
Same rule as `e2e-harness-base.md` and `module-review.md`: no unapproved fix from a test run.

## Reading the result — the verdict table

| Instrument says | Verdict | What it means |
|---|---|---|
| `crash` | **FAIL** | Unhandled exception, error page, or an ERROR span. Real, file it. |
| `info` | **finding, not a failure** | Odd but handled. Triage; most are noise. |
| `ok` | **PASS, narrowly** | No crash on this input at this seed. Nothing more. |
| **no spans captured in any round** | **FAULT, not a pass** | The OTel arm of the oracle never ran, so swallowed-error crashes *could not* have been detected. Half the instrument was blind. Do not report the run as clean. |
| instrument absent / did not start | **FAULT** | Absence is never a pass. |

That fourth row is the one that gets mis-called. A Mendix microflow can catch its own error,
leave the UI cheerful, and produce an ERROR span and nothing else. With no spans, the run only
tested "did the browser blow up" — the weaker half.

## The crash oracle must stay concrete

"Did it crash?" is otherwise a judgement call that drifts run to run. It is defined as, and
only as: an uncaught page exception, a Mendix error page or error dialog, a 5xx on an
in-flight request, or an ERROR-status span. Widening it to "looked wrong" turns the net into
an opinion generator. Narrowing it to "page exception only" makes it blind to caught errors.

## Reporting

Three lines, next to the journey result, never instead of it:

```
monkey · <module> · seed <N> · <R> rounds
  <C> crash-class, <I> info, <O> ok      [or: FAULT — <why the oracle could not run>]
  Read as: no unhandled crash on these inputs. Not evidence the module works.
```

## Related

- `skills/skills-over-scripts.md` — why this file holds the rules and `monkey.js` holds none
- `skills/journey-proof.md` — the instrument that actually finds the defects
- `skills/e2e-harness-base.md` — the no-unapproved-fix rule
