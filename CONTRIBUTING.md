# Contributing to mxcli-project-toolkit

Every rule in this toolkit was paid for by a real project hitting a real wall. If your project
hit one — a bug, a workaround, a pattern that saved a day, a toolkit script you had to patch
locally — **we want it, in whatever shape you have it.** The bar for getting something in the
door is deliberately on the floor: *it happened and you wrote it down.* Review and polish are
the maintainers' job, not the contributor's.

Why so eager: the same `graph-sweep.sh` bug was found and patched locally in **two different
projects, weeks apart**, because upstreaming felt like a chore. A contribution that sits in
your project helps one project; the moment it lands here it travels to all of them on the next
`git pull`.

## Three lanes, by friction

### Lane 1 — the inbox (default; near-zero friction)

Drop a file in `contrib/inbox/` and open a PR. Copy `contrib/inbox/TEMPLATE.md`, fill in the
four front-matter lines and paste what you have — a bug-log entry, a diff, three sentences,
verbatim terminal output. **No quality bar applies**: inbox files are explicitly unreviewed and
unreleased — nothing loads them, no skill routes to them, so a wrong entry cannot hurt any
consuming project. Triage promotes an item into `skills/`, `bug-logs/` or `bin/` (that is where
review and field-proofing happen) and deletes the inbox file in the same commit. The inbox is a
queue, never an archive.

### Lane 2 — the harvest script (contribution as one command)

From a project wired to this toolkit:

```
<toolkit>/bin/harvest-learnings.sh <project-root>
```

It scans the project for what evaporates otherwise — bug-log entries the toolkit's log doesn't
have, promotion tables in `PROJECT.md` / `CLAUDE.local.md`, local patches to installed toolkit
scripts — and writes ready-to-PR inbox files into your toolkit clone. Review them (see the
client-data rule below), commit, PR. Run it at project wrap-up at minimum; the wrap-up
checkpoint asks for it.

### Lane 3 — direct PRs

If you know the target file, PR straight into `skills/`, `bug-logs/` or `bin/`. Held to the
full bar: for anything under `bin/`, `project-bin/` or `project-tests/`, the five field-proof
rules in `CLAUDE.md` → "Shipping an instrument" apply (captured golden input, both layouts,
both platforms, one cited field run, a producer for every consumed artifact). For skills,
follow `README.md` → "How to add a new skill" including the routing-table row.

## The two rules that apply in every lane

1. **No client data.** No client or vendor names, engagement codenames, person names, internal
   hostnames, real local paths, NDA'd strings. Genericize before you commit
   (`ClientX`, `/path/to/project`). `bin/check-no-client-data.sh` runs in CI and as a
   pre-commit hook, but the denylist can't know your client — read your own diff.
2. **Say where it happened.** Every contribution names its field context: which project, what
   you observed, verbatim output for bugs. "I think" is fine to send — but label it as a
   hypothesis, not a finding (`skills/tool-output-is-not-ground-truth.md`).

## What happens to your PR

- CI runs the mechanical gates: every script parses (`bin/check-scripts.sh`), routing renders
  clean (`bin/render-routing.sh --check`), no macOS-only regressions
  (`bin/check-portability.sh`), leak guard (`bin/check-no-client-data.sh`), and — on PRs —
  the merge-queue discipline (`bin/check-pr-discipline.sh`: your CHANGELOG line rides in the
  same PR, and any new bug number is still free on `master`).
- A maintainer (human or a toolkit Claude session) reviews; inbox items get triaged into their
  real home, tested, and released by merge to `master` — consuming projects pick the change up
  on their next `git pull` + `bin/sync-project.sh`.
- The merge commit appends a `CHANGELOG.md` line **crediting you or your project by name**.
  That line is the record of which projects feed the toolkit.

## The merge queue (adopted 2026-09-01, after the first five-PR day)

One day of five parallel sessions produced: two different bug clusters both numbered
BUG-96..100, three PRs with no changelog line, two PRs whose CI never ran because their
conflicted state blocked it, and one half-redacted secret that a plain merge would have
carried into public history. None of the content was bad — the coordination was. Hence:

1. **Small and fast.** A PR should merge within ~48h; every day it waits, master moves and
   the conflict/collision surface grows. A conflicted PR gets its base merged in *before*
   review — a PR whose CI cannot run has no signal at all, and "green" silence is not green.
2. **Bug numbers are assigned at merge, not at write.** In a PR, head the entry
   `## BUG-DRAFT-<slug>:`; whoever merges gives it the next free number. If you do claim a
   number, CI now rejects one that is already taken on `master`.
3. **Changelog rides in the same PR.** Was always the rule; now CI checks it instead of
   trusting it.
4. **Squash-merge is the default.** This repo is public: intermediate commits (with their
   pre-redaction blobs, wrong paths, half-genericized names) must not reach `master`'s
   history. A merge commit is fine for a branch whose every commit is already clean.
5. **A claim ships with its probe.** A new skill rule or STOP row names the command that
   would falsify it (see the BUG-22 retirement for the worked example); a new or changed
   instrument ships its retest fixture. "It happened to me" gets it in the door — what keeps
   it true later is that the next person can re-check it in a minute.

## Good worked examples already in the wild

- An honest negative result filed against the filer's own theory
  (poctibor `bug-004-write-count-threshold-corruption`).
- A deliberate *don't-file* after searching upstream and finding the bug already logged
  (pattern-b overlap note → BUG-75/77, now 8 confirmations across 3 projects).
- A per-project promotion queue naming exact toolkit target files
  (tfc-tcxgraphpoc `PROJECT.md` → "Toolkit promotion changelog", TD-01…TD-06).

Model your contribution on any of these and it will sail through.
