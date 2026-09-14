**From:** moc-app-replacement
**Date:** 2026-09-14
**Kind:** bug
**Field evidence:** bug-log entries in moc-app-replacement not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic
**Proposed target:** see per-item notes below

---

## [candidate — from bug-logs/project-bugs.md] BUG-DRAFT-test-local-destroys-run-local-database: mxcli test --local restarts PostgreSQL on a fresh data directory and destroys the run --local database

**Version:** mxcli v0.21.0 (2026-09-06), Mendix 11.14.0, Linux container, PostgreSQL 16.
**Severity:** high — silent data loss on a database the user is actively using.

### What the tool promises

`mxcli test --help`, verbatim:

> With `--local` the app runs on mxcli's own runtime instead of a container — the same boot
> as `mxcli run --local`, so no Docker daemon is needed. **It uses its own ports (8081/8091)
> and its own `<project>_test` database, so a warm `run --local` loop can keep serving the
> same project while tests run.**

That last clause is the promise, and it is what makes the tool safe to run mid-build.

### What happened

`mxcli run --local` was serving the project on `moc` for hours, with seeded notification
templates and demo users. Over roughly forty minutes, `mxcli test --local` was run about eight
times (a registration suite, growing from 3 to 18 tests, plus three small probes). Each run
prints:

```
  Starting local PostgreSQL...
  Database ready: moc_test (user "mendix") at 127.0.0.1:5432
```

The next `run --local` then failed:

```
Error: starting runtime: start failed: The database to be used does not exist.
```

`psql -l` showed **`moc_test` present and `moc` gone**. Only `postgres`, `template0`,
`template1` and `moc_test` remained.

### The evidence that it is the test runs and not something else

The PostgreSQL **server process** had restarted:

```
$ ps -o lstart= -p 2681
Wed Sep  9 03:47:45 2026
```

03:47 is inside the window of the test runs, and well after the app had last been serving on
`moc`. So `test --local` did not merely create its own database beside the existing one — it
brought up a PostgreSQL instance on the same port (`127.0.0.1:5432`, which it prints itself)
on a data directory that did not contain `moc`.

Both databases cannot have coexisted on the surviving cluster: `moc_test` is there and `moc`
is not, and nothing else in the session drops databases.

### Why this is worse than it looks

Nothing warns. The failure does not surface during the test run — every test passed, 18 of 18 —
and it does not surface at the end of it either. It surfaces on the **next unrelated action**,
as an error about a database, at which point the connection to the test run is not obvious.
The recovery (`createdb moc`, restart, re-seed) is cheap; noticing what happened is not.

The promise in `--help` actively encourages the pattern that loses the data: the whole point of
that sentence is to tell the user they may keep the app warm while testing.

### Reproduction

1. `mxcli run --local --db-host 127.0.0.1:5432 --db-name X ...`, let it serve, put data in it.
2. `mxcli test --local` on any `.test.mdl` in the same project.
3. `psql -l`. Expect `X` and `X_test`; observe `X_test` only.
4. Restart `run --local`: "The database to be used does not exist."

### Suggested fix

Either honour the `--help` text — create `<project>_test` **inside the running cluster**, never
starting a second one on the same port — or, if a separate instance is deliberate, use a
different port and say so, and drop the sentence that says a warm loop is safe.

### Local workaround

Recreate the database and restart; the app's own after-startup microflow re-seeds. Do not run
`test --local` while the served database holds anything not reproducible from a seed.


## [candidate — from bug-logs/toolkit-findings.md] FINDING-1: gate-check.sh's Stage-7 detector selects rows by bare column-2 value, so an open question numbered 7 fails a hard gate

**Severity: real.** Stage 7 is a ✋ hard gate, and this produces a `FAIL` on a project that has
made no cutover decision at all — the exact "there and wrong" verdict the gate reserves for
genuine problems.

**What happens.** The detector (`bin/gate-check.sh` ~line 1063–1089) qualifies a row as the
cutover decision when *"stage field (col 2) equal to 7, or the decision field (col 3) naming the
cutover"*. It applies that test to every pipe-delimited row in `PROJECT.md` rather than to the
Decisions table alone. `PROJECT.md` ships with a second table — **Open questions**, whose first
column is a number — so open question **#7** presents `7` in column 2 and is read as an
unconfirmed Stage-7 decision.

**Reproduce.** In any project's `PROJECT.md`, add a seventh row to the Open questions table:

```
| 7 | Anything at all | Stage P | OPEN |
```

then run `bin/gate-check.sh <project> 7`. Before:

```
Stage 7 (Cutover): FAIL · 1 cutover decision row(s) in PROJECT.md, none with a field
                   exactly CONFIRMED (✋ gate — UNCONFIRMED/ASSUMED does not pass)
```

Remove that row (or renumber it `OQ-07`) and the same command reports what it should:

```
Stage 7 (Cutover): WAIVED · requirements-driven entry mode — no legacy system to cut over from
```

**Why it matters more than it looks.** Any register that accumulates seven open questions trips
it, which is most projects by Stage 2 — this one reached nine before Stage 1 ended. The failure
is silent about its cause: nothing in the message points at the Open questions table, so the
reader looks for a missing cutover decision that was never owed. And the detector's own code
comment shows the column-awareness was a deliberate fix for a previous false *pass*
(`tolower($0) ~ /cutover/` matching prose) — the row-selection half of that fix is what is
still missing.

**Suggested fix.** Bound the row scan to the Decisions table: start at the `## Decisions`
heading and stop at the next `## `. That is the same fix the comment's own reasoning implies,
one level up from the column it fixed. A narrower version — ignore rows whose column-2 value is
not a stage label — would also work but leaves the next table with a numeric first column to
find the same bug again.

**Workaround used here.** Open questions are numbered `OQ-01 … OQ-09` instead of `1 … 9`. It
works, and it is a workaround, not a fix: a project that numbers them plainly (as the shipped
template invites) hits this.

---


