# Upstream Feedback — where a finding goes, and in what form

**Applies to:** the moment an agent has learned something worth sending upstream — an mxcli
command that lied, a gate that let a defect through, a runbook stage that was missing a step —
and is about to open an issue, a PR or a discussion. Answers one question: **which repo, which
vehicle, and what may be posted.**

**Companions:** `bug-submission-checklist.md` (the full evidence bar for an mxcli defect — this
file routes, that one proves), `close-the-loop.md` (local filing; this is the upstream half),
`tool-output-is-not-ground-truth.md` (verify before you file), `CONTRIBUTING.md` (lanes and
the no-client-data rule that CI enforces).

---

## 1. Two destinations, and they do not overlap

| Destination | What belongs there | Vehicle |
|---|---|---|
| `mendixlabs/mxcli` | Defects and gaps in the **binary itself**: MDL syntax accepted by `check` then rejected by `exec`, a command whose output is wrong, a `DESCRIBE`/`CREATE` round-trip that does not close, a flag that should exist | **Issues only.** We do not hold that source. Never attempt a PR, never post a patch |
| `MendixMau/mxcli-project-toolkit` | Everything about the **process**: skills, gates, runbook stages, `bin/` scripts, agent roles, report generators, checklists | **PR** when the fix is small and obvious · **Idea** (GitHub Discussion) when it needs design · **Issue** when a toolkit script has a plain reproducible defect |

The test that separates them: *would this still be wrong with no toolkit installed at all?* Yes →
mxcli. No → toolkit. A finding that is really both ("`check` passed a construct `exec` rejects, and
`learned-detection-gaps.md` did not list it") is **two** submissions, one per repo, each citing the
other's number once it exists.

## 2. Before anything else: is it already written down?

> **A gap that reads as "the toolkit already said this and it was not followed" is not a toolkit
> submission.** It is a compliance failure against an existing skill. Filing it adds a rule on top
> of a rule that already exists, and the second rule will be skipped for the same reason the first
> was.

Before drafting, search for the advice you are about to propose:

```bash
grep -rniE '<two or three key words>' <toolkit>/skills/ <toolkit>/bin/ <toolkit>/CONTRIBUTING.md
```

| What the grep shows | What you actually have |
|---|---|
| The advice exists, in a skill that is routed for this situation | Nothing to file upstream. Record the miss locally (`docs/BUILD-LOG.md` or the project's improvement register) and ask why the routing did not reach you |
| The advice exists, but nothing routes to it in this situation | A routing gap — small PR to the routing table row, or an Idea if the stage itself is unclear |
| The advice exists, was routed, was read, and there was still no point at which work *stopped* | A gate gap — see the rule below |
| Nothing | A genuine gap — choose a vehicle in §3 |

**Prefer one blocking gate over several new documents.** Advice without a gate has already failed
once by the time you are reading this; more advice is not the fix. If the proposal is "add a
paragraph to skill X", ask what the check is that would have refused to proceed, and propose that.

## 3. Choosing the vehicle

| Vehicle | Choose it when | It must carry |
|---|---|---|
| **Bug** (issue) | Reproducible defect against known-correct behaviour, with a clear retest. You can say what *should* have happened without arguing about it | Repro steps, expected vs actual, versions, the retest command |
| **PR** | You hold the source, the fix is small, and there is **one obviously right implementation**. If you would have to *choose* a design, it is not a PR | The diff, the before/after evidence, the check that proves it |
| **Idea** (Discussion, category `Ideas`) | The evidence says something structural is wrong but the shape of the fix is a judgement call | The evidence with denominators, two or three candidate shapes, your recommendation |

Why Ideas exist as a separate lane: an issue carries an implicit *someone must close this*, and
the fastest way to close a process gap is to add another document — which is the failure §2
describes. Ideas carry no closure pressure, so they are the correct container for "the toolkit did
not stop me" findings, where the right fix is a gate, a re-ordering of a stage, or a script that
refuses, and nobody yet knows which.

The commands, once the draft has passed §5:

| Vehicle | Command |
|---|---|
| mxcli issue | `gh issue create -R mendixlabs/mxcli --title "..." --body-file <part1.md>` |
| toolkit issue | `gh issue create -R MendixMau/mxcli-project-toolkit --title "..." --body-file <part1.md>` |
| toolkit PR | branch off `origin/master`, one concern per PR, `gh pr create -R MendixMau/mxcli-project-toolkit --base master --body-file <part1.md>` |
| toolkit Idea | `gh api graphql` `createDiscussion` with the repo id and the `Ideas` category id (read both with a `repository { id discussionCategories(first:10) { nodes { id name } } }` query first — do not hard-code them) |

## 4. The two-part local draft

Every submission is drafted **locally first**, as one file under the project's `submissions/`
(one file per finding, slug-named). Two parts, one file:

| Part | Contents | Posted? |
|---|---|---|
| **1 — publishable** | Summary · reproduction · cause (or "unknown, observed at …") · suggested fixes, ranked · how to retest. Placeholders throughout: `<Module>.<Page>`, `<model>.mpr`, `<toolkit>` — never a real name | **Yes** — and only this |
| **2 — local evidence** | Project-specific detail, scratch-copy observations, the workaround actually used, related local notes and file paths | **Never** |

The first line of the file is a status line, and it is the only index that stays true:

```
Status: DRAFT | FILED mendixlabs/mxcli#NNN 2026-09-18 | MERGED MendixMau/mxcli-project-toolkit#NN | CLOSED-COMPLETED | CLOSED-WONTFIX
```

Update it the moment the item lands, with the number. A `submissions/` directory whose status lines
are current is a resume doc that cannot drift; one whose lines were "going to be updated later" is
the failure §7 records.

## 5. Scrub gate — run against the exact text being posted

If it is not needed to reproduce the problem, it does not go in the post. Run these on Part 1
**after** it is extracted into its own file, not on the combined draft:

```bash
P=<part1.md>
grep -nIE 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|\$2[aby]\$[0-9]{2}\$|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$P"   # credentials
grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$P"                                              # email addresses
grep -nIE 'https?://[^ )>]+' "$P" | grep -vE 'github\.com|docs\.mendix\.com|localhost'                        # internal URLs
grep -nIE '(xas|xasid|session|JSESSIONID|Bearer|token)[=: ]+[A-Za-z0-9._-]{16,}' "$P"                        # session tokens
grep -nIE 'jdbc:|postgres(ql)?://|CREATE TABLE|public\.[a-z_]+\$' "$P"                                         # schemas / DSNs
grep -niE '<employer>|<customer>|<engagement codename>|<real person surname>' "$P"                            # fill in per project
grep -nIE '/Users/[a-z.]+|/home/[a-z]+' "$P"                                                                  # home paths
```

The last three lines are the ones no regex can finish for you: customer and employer names, real
people's names, and real module or entity names that only make sense inside one engagement. Read
Part 1 once, top to bottom, as the maintainer who has never heard of the project. Every hit is
either replaced with a placeholder or the sentence is cut. The toolkit's own
`bin/check-no-client-data.sh` runs in CI on PRs to that repo; nothing runs on an issue or a
discussion, so for those the checklist above **is** the gate.

## 6. Evidence standard

| Rule | Why |
|---|---|
| Numbers carry their denominator: "5 of 7 pages", never "most" | "Most" is a feeling; 5/7 is retestable |
| Figures are quoted from the file that holds them, not from memory | The one time this was skipped, the recorded number was wrong and was cited twice more before anyone re-read the file |
| A negative result is filed, and labelled `Negative result:` in the title or first line | "We tried X on N cases and it did not reproduce" saves the next project the same afternoon — but only if it cannot be mistaken for a defect report |
| Every submission says how to retest it, as a command or a numbered list | A maintainer who cannot retest cannot close, and an item nobody can close is noise |
| Two defects with two root causes are two submissions | Bundled items get half-fixed and closed (`bug-submission-checklist.md`, failure mode 1) |

## 7. Close the loop — check the API, not the note

Filed items get checked back. A local note that says "filed" or "open" is a claim about the
remote; the remote is the truth, and it moves without telling you.

Why this section is here: seven issues were filed to `mendixlabs/mxcli` from one project. The local
index said "6 filed, 2 toolkit PRs open". Checking the API showed **5 of the first 6 already closed
COMPLETED within hours** of filing, and the toolkit had **9 open PRs, not 2** — with the PR that the
project's resume doc pointed at already merged. Every one of those local lines had been true when
written. None was true when read.

```bash
gh issue list -R mendixlabs/mxcli --author @me --state all --json number,title,state,stateReason,closedAt
gh pr list    -R MendixMau/mxcli-project-toolkit --author @me --state all --json number,title,state,mergedAt
gh api graphql -f query='{ repository(owner:"MendixMau", name:"mxcli-project-toolkit") { discussions(first:20, orderBy:{field:CREATED_AT, direction:DESC}) { nodes { number title closed category { name } } } } }'
```

Then, for each item whose state differs from its status line in `submissions/`: correct the status
line, and if the item was closed COMPLETED, retest the original repro against the current binary or
toolkit commit before removing any local workaround. A closed issue is a maintainer's claim; the
retest is the evidence. Do this at every session start that touches a filed item, and at project
wrap-up.

## 8. One-screen decision

```
Would it be wrong with no toolkit installed?  ── yes ──▶  mendixlabs/mxcli · ISSUE (never a PR)
        │ no
Does the toolkit already say this?            ── yes ──▶  not a submission; local compliance note
        │ no                                               (routing gap? → small PR to the routing row)
Reproducible defect in a toolkit script?      ── yes ──▶  toolkit ISSUE
        │ no
One obviously right fix, and it is small?     ── yes ──▶  toolkit PR (one concern, off origin/master)
        │ no
                                                     ──▶  toolkit IDEA (Discussions › Ideas): evidence,
                                                          candidate shapes, prefer a gate over a document
Every branch: two-part local draft → scrub Part 1 → post Part 1 only → status line → check back via API
```
