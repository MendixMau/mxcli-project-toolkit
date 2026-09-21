# Release process — intake, triage, and the release train

**Scope.** This doc governs how a contribution moves from arrival to a tagged release, and how
that release is cut. `CONTRIBUTING.md` already covers the three ways to *send* a contribution
(inbox drop, harvest script, direct PR) and the two rules that apply in every lane — read that
first if you're contributing, not maintaining. This doc adds the fourth intake channel (GitHub
issues), the triage rubric that turns an arrived item into a verdict, the test tiers a change
must reach before it can merge, and the release train that turns merged commits into a tagged
version. Reconciling the two documents into one (folding this rubric into `CONTRIBUTING.md`) is
a follow-up, not done here — see "Not yet built" at the end.

## 1. Intake lanes

Four ways something arrives. The first three are PR-shaped (see `CONTRIBUTING.md` for how to
send them); the fourth is issue-shaped.

| Lane | Accepts | Must carry | Triage SLA | Labels on arrival |
|---|---|---|---|---|
| **Inbox drop** (`contrib/inbox/`, PR touching only that dir) | anything with the 4 front-matter lines from `contrib/inbox/TEMPLATE.md`; one item per file, ≤ 600 words | no client data; hypothesis vs. finding labelled | labelled ≤ 2 days; promoted into `skills/`/`bug-logs/`/`bin/` or closed-to-issue within one release cycle (≤ 7 days). A file older than 14 days is triage debt — `bin/triage.sh` reports it | `lane/inbox`, `kind/*`, `needs/triage` |
| **Harvest** (`bin/harvest-learnings.sh <project-root>`) | bugs / promotions / patches drafted from a wired project | same as inbox, plus: the human reviewed every drafted file for client data before opening the PR | same as inbox | `lane/harvest` + inbox labels |
| **Issue** | bug report (verbatim command + output, plus the `Toolkit release: v…` line from `bin/sync-project.sh`) or an idea (one paragraph naming the failure it prevents) | bug: reproducible on a named release; idea: names the toolkit file it would change | bug: labelled ≤ 2 days, `needs/info` auto-closes after 14 days of silence; idea: parked under `kind/idea`, reviewed at each release cut, converted to a PR only once it has a field trigger | `kind/bug` or `kind/idea`, `needs/triage` |
| **Direct PR** (`skills/`, `bin/`, `project-bin/`, `project-tests/`, `bug-logs/`, `pipelines/`) | a finished change | PR template rows filled; `CHANGELOG.md` line under `## Unreleased`; new bug entries headed `## BUG-DRAFT-<slug>:`; a field run cited for any instrument (CLAUDE.md → "Shipping an instrument") | first grade ≤ 2 days; merge or verdict ≤ 48h after the author marks it `ready`; no activity for 14 days → `verdict/promote-to-issue` and close | `lane/direct`, `kind/*`, `size/*`, `provenance/agent-authored` when applicable |

Who triages: a mid-tier toolkit session grades and labels (a cheap-tier session only splits or
summarizes — see §5); a **human confirms every `verdict/*` label and every merge.**
`bin/triage.sh` today covers the inbox lane mechanically (age, size, lane guess); it reads
`contrib/inbox/*.md` only — PR/issue triage is done by a session following the rubric below,
not (yet) by a script. Extending `bin/triage.sh` to PRs/issues is a follow-up.

## 2. Triage rubric

Five grades, 1–5 each. Grade the PR or issue body first, the diff second — an item that cannot
be graded from its body gets `needs/info`, not a guess.

| Grade | 1 | 3 | 5 |
|---|---|---|---|
| **Completeness** | idea or partial diff; nothing runnable | change lands but a promised piece is missing (routing row, fixture, producer for a consumed artifact — CLAUDE.md rule 5) | every producer/consumer/routing/changelog piece present in the same PR |
| **Relevance** | project-specific, reads a BRD from `pipelines/`, or duplicates a bundled mxcli skill | generic but overlaps an existing skill/instrument (needs a merge, not a new file) | generic, downstream of the BRD boundary, cites the incident it prevents |
| **Regression-test need** (how badly it needs one) | pure prose/pointer, nothing to assert | touches a guard, gate or parser: a scoped fixture exists and is named | new instrument or exit-code change: needs a captured golden fixture *and* the existing fixtures it would invalidate, updated |
| **Field-proof** (CLAUDE.md "Shipping an instrument", rules 1-7) | selftests only, imagined input | one field run cited, one layout/platform | cited run + both layouts + both platforms + producer named; a blocking guard accepts outside evidence and never blocks its own remedy |
| **Hygiene** | client data, home path, `git add -A` residue, no CHANGELOG line, a numbered `BUG-` heading that collides on master | clean diff, changelog present, at or under the size cap (or a split plan given) | also: worktree-clean, session/provenance trailer present, one purpose per PR, fixture sits beside its capture |

Verdict mapping (thresholds, not sums):

- **merge-as-is** — every grade ≥ 4, hygiene = 5, and the test tier required in §3 was reached.
- **needs-changes** — hygiene ≥ 3 and every other grade ≥ 3; the missing rows are listed as
  `needs/*` labels; the same PR is fixed in place (by the author, agent or human).
- **rework** — relevance ≥ 3 but completeness or field-proof ≤ 2: the idea is right, the
  artifact is not; the PR closes, an issue keeps the idea and the field evidence, and a fresh
  small PR reopens it.
- **close** — relevance ≤ 2 (wrong layer, duplicate, project-only), or hygiene = 1 that cannot
  be squashed away (client data in a public PR is closed and the branch deleted, never "fixed
  up" in place).
- **promote-to-issue** — inbox items and stale PRs with good evidence but nobody to finish
  them: the content moves to an issue titled with its proposed target, and the inbox file is
  deleted in the same commit — the inbox is a queue, never an archive.

The grade lives as one comment on the PR or issue: `triage: C4 R5 T3 F2 H5 → needs-changes
(needs/field-run)`.

## 3. Test tiers

| Tier | What | Who runs it | Where required |
|---|---|---|---|
| **T0 inspection** | read the fixture whose greps cover the changed file and replicate them by hand; report the greps | author session | every PR, always |
| **T1 scoped fixture** | the one named `tests/wave2/test-*.sh <subject>` case (or `tests/run-tests.sh` case) that covers the change; `bin/render-routing.sh --check` for any routing change | author session — at most one fixture, named in the PR body | any PR touching `bin/`, `project-bin/`, `project-tests/`, or `bin/lib/*.tsv` |
| **T2 field run** | the instrument executed against a real project; what it measured, on which toolkit release, described generically (no client/project name) | author, cited in the PR's "Field evidence" row | every new/changed instrument, every blocking guard, every STOP row (its falsifying probe) |
| **T3 full suite** | both fixture suites (`tests/run-tests.sh` + `tests/wave2/run-all.sh`) | **CI**, on every PR, in an isolated checkout — **and** the release gate (§4), the only local full run | never a reflex run in the shared local tree (see CLAUDE.md "Testing this toolkit") |

Which tier each kind of change must reach: inbox/harvest drop → none, unreviewed and unloaded;
a prose skill edit or a routing-table row → T0 + `render-routing --check`; a guard or gate
change → T1 + T2; a new instrument, parser, or exit-code change → T1 + T2 + updated fixtures;
a process/template/CI change → T0 + one dry run pasted into the PR body.

## 4. PR lifecycle

**States:** `draft` (agent working, no review requested) → `ready` (author flips it after
reaching the tier required by §3 and pastes the rubric self-grade) → `triaged` (a `verdict/*`
label set by the maintainer per §2) → `merged` (squash-merge is the default per
`CONTRIBUTING.md`; the maintainer assigns any `BUG-` numbers and confirms the CHANGELOG line
sits under `## Unreleased`) → `released` (the commit ships inside a tagged section — see §6).

**WIP cap:** at most 8 non-draft PRs open at once. A ninth stays in draft until one of the
eight moves. A `ready` PR with no activity for 14 days gets `verdict/promote-to-issue`.

**Size cap:** ≤ 10 files and ≤ 400 changed lines, excluding fixtures, captures and
`CHANGELOG.md`. Over the cap: split the PR or stack it (each layer green on its own, split plan
stated in the PR body before work starts). `size/*` labels this from the diff.

## 5. Model tiers, by purpose

Described by what each tier is for, not by vendor or model name — a session on any harness
picks the equivalent tier it has:

- **Cheap** — mechanical work that ends in a check, never a verdict: splitting harvest output,
  summarizing one inbox file, computing a size label.
- **Mid** — work whose output is checked by a human verdict or by CI: rubric grading, `needs/*`
  labelling, writing a scoped fixture, wording a CHANGELOG line, a leak-guard review of a diff
  (paired with `bin/check-no-client-data.sh` as the mechanical floor).
- **Strong** — a wrong call here ships to every project on the next `git pull`: reviewing a
  guard/gate/parser PR, designing a new instrument, rewriting a routing skill.
- **Human** — never delegated: the release gate, setting a `verdict/*` label, the merge itself.

## 6. Release train

Cadence: a release train on fixed days — **Monday and Thursday** — cut from `master`.

Today's tool: `bin/cut-release.sh` renames CHANGELOG.md's `## Unreleased` heading to
`## vYYYY.MM.DD`, commits `CHANGELOG.md` alone (explicit path), tags the commit
`vYYYY.MM.DD`, and opens a fresh empty `## Unreleased` above it. It does not push — review the
commit and tag, then `git push origin master vYYYY.MM.DD` yourself. Current flags, confirmed
against the script:

```
bin/cut-release.sh                 # today's date: vYYYY.MM.DD
bin/cut-release.sh v2026.09.22     # an explicit name (must match vYYYY.MM.DD[-suffix])
bin/cut-release.sh --dry-run       # print what would happen, touch nothing
```

It refuses (exit 2) rather than guesses when: not on `master`, `CHANGELOG.md` has uncommitted
edits, `## Unreleased` is missing or empty, or the tag already exists.

**`--notes` does not exist yet** (see "Not yet built" below) — until it does, write the
GitHub Release body by hand from the freshly dated CHANGELOG section (`sed -n` between the new
`## vYYYY.MM.DD` heading and the next `## ` heading), then `gh release create vYYYY.MM.DD
--notes-file <that file>`.

**Release gate** — the only local full-suite run, on the `master` tip after the last merge of
the cycle: `tests/run-tests.sh` + `tests/wave2/run-all.sh`; `bin/check-no-client-data.sh` with
the maintainer's real denylist; `bin/render-routing.sh --check`; `bin/sync-project.sh
--dry-run` against one wired real project; then `bin/cut-release.sh`, push `master` plus the
tag, and open the GitHub Release.

**Rollback:** projects pin by tag. A bad release is reverted with `git revert -m 1` of the
offending squash commit(s), a `fix(...)` line lands under the next `## Unreleased`, and a
same-day hotfix tag ships (`vYYYY.MM.DD-hotfix1` — already accepted by `cut-release.sh`'s name
regex). Never force-push, never delete a tag.

**Merge queue:** not adopted. Required checks plus "require branch up to date" cover one
maintainer at under 5 merges/day. Revisit if merge conflicts, rather than review time, become
the bottleneck.

## 7. Multi-agent hygiene: worktree per task, explicit-path staging

- **Worktree per task.** `git worktree add ../wt-<slug> -b <branch>` — one session, one git
  index. This is the fix for the 2026-08-21 incident documented in CLAUDE.md → "Committing in
  this clone": a shared tree makes any whole-index operation (a pathless `git commit`, `git add
  -A`) untrustworthy the moment two sessions are in it at once. With a worktree per task the
  shared clone stays read-only `master`.
- **Explicit-path staging stays law.** `git add -- <paths>` and `git commit -- <paths>`; never
  `git add -A`, `git add .`, or a pathless `git commit -a`. `bin/check-no-client-data.sh` runs
  in CI and as a pre-commit hook, but a denylist can't know your client — read your own diff
  before it leaves the worktree.
- **One purpose per PR.** A PR that mixes skill prose, an instrument change, and an inbox drop
  is split before grading — the rubric in §2 grades one artifact at a time.

## Not yet built (follow-ups, not implemented in this change)

Kept here rather than silently dropped, per the source proposal's own `next`/`later` staging:

- `bin/cut-release.sh --notes` — print the dated CHANGELOG section for the GitHub Release body
  (today's workaround: `sed -n` the section by hand, described above).
- `bin/harvest-learnings.sh --split` — one inbox file per candidate (≤ 600 words each), so a
  multi-topic harvest drop is triaged item by item instead of as one oversized file. The
  current script is 227 lines; adding this is a real feature, not a small patch, so it stays a
  follow-up rather than landing alongside the process docs.
- `bin/install-hooks.sh` — a `prepare-commit-msg` hook that adds an `Assisted-by: <agent>
  (<tier>)` trailer automatically when an agent-session environment marker is present, so
  provenance doesn't depend on the agent remembering to add it.
- Folding this rubric and the lane table into `CONTRIBUTING.md` itself (today the two files
  overlap: `CONTRIBUTING.md`'s "three lanes" covers how to send a PR-shaped contribution, this
  doc's four lanes add the issue channel and the triage/release mechanics after arrival).
- `tests/wave2/fixtures/*/CAPTURE.md` required by a `check-fixture-provenance.sh` guard.
- A merge queue (`merge_group` trigger in `checks.yml`) — only if merge conflicts, not review
  time, become the bottleneck.
- Extending `bin/triage.sh` to grade/list open PRs and issues (today it covers the inbox lane
  only — see §1).
