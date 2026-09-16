**From:** toeic-buddy
**Date:** 2026-09-14
**Kind:** bug
**Field evidence:** bug-log entries in toeic-buddy not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic
**Proposed target:** see per-item notes below

---

## [candidate — from bug-logs/mxcli-bugs.md] 2026-08-25 — NEW BUG (not in the STOP table): a CREATE <Entity> (...) COMMIT; whose result is DISCARDED (no variable assignment) drops the Entity property under mxcli exec — CORRECTED finding, see below

**Severity: high. Not previously documented anywhere in `learned-mdl-preflight.md`.**

**This entry supersedes an earlier, WRONG diagnosis** (initially recorded here as "more than 7
CREATE-object activities per exec corrupts all of them" — a count-based theory). The count theory
was falsified by a follow-up test and is kept below, struck through, as a record of how the
investigation actually went — the wrong turn is as much a finding as the right answer, per this
run's own instructions to log friction rather than silently correct it.

**Symptom:** `mx check` (real mxbuild) reports `[CE6005] "The 'Entity' property is required."` on
a `Create object` activity. `mxcli check --references` (syntax-only) and `mxcli exec` itself both
report clean/success — only the real `mx check` reveals it.

**Real trigger, confirmed:** a `CREATE "Module"."Entity" (...) COMMIT;` statement whose result is
**not assigned to a variable** (bare `CREATE ... COMMIT;`, output discarded) compiles to a Create
activity missing its `Entity` property. Assigning the result (`$Row = CREATE ... COMMIT;`) —
even when `$Row` is never subsequently used — avoids the bug entirely, at any count tested.

**Bisection, corrected (each row an isolated test from a clean git-committed baseline, checked with
the real `mx check`):**

| Test | Pattern | Creates | Result |
|---|---|---|---|
| 1 | `$Pack{i} = CREATE DeptPack (...) COMMIT;` — assigned | 7 | clean |
| 2 | `CREATE ListeningItem (...) COMMIT;` — discarded | 20, 10, 8 | **corrupt, every one** |
| 3 | `CREATE VocabTerm (...) COMMIT;` — discarded, across 4 separate microflows in one exec | 28 | **corrupt, every one** |
| 4 (the correction) | `$Row{n} = CREATE ListeningItem (...) COMMIT;` — assigned | 20 | **clean** |

Test 4 is the one that overturned the count theory: same entity, same exec, same count (20) as a
failing test in row 2 — the only variable changed was adding `$RowN =` in front of each `CREATE`.
Clean. The apparent "≤7 is safe" pattern in the early tests was confounded: the one passing test
(DeptPack, 7 creates) happened to use assigned variables (`$Pack0`..`$Pack6`, needed later for
associations); every failing test happened to discard the result because the seed script had no
further use for the row. Count was never the variable — assignment was.

**Impact on this build:** any bulk data-seeding script must assign every `CREATE`'s result to a
variable, even when nothing downstream reads it (`$Row{n} = CREATE ...` is sufficient; the variable
need not be referenced again). Re-batching seed data at ≤7 creates/exec (the original mitigation)
is unnecessary once every create is assigned — reverting to larger batches with assignment.

**Recommendation for the toolkit:** add to `learned-mdl-preflight.md`'s STOP table or gotchas list:
"A `CREATE Entity (...) COMMIT;` whose result is discarded (no `$Var =`) drops the Entity property
— always assign, even to an unused variable." Retest on a later mxcli build before assuming this
persists.

<details><summary>Original (WRONG) count-based theory, kept for the record</summary>


