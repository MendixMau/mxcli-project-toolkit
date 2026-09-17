# Toolkit roadmap: the existing app capability

One backlog for everything the app analysis work has surfaced. Written 2026-09-16 from two design
notes, one field dry run, a harvest of thirty external repositories, and six parallel research
runs against a large live application.

Structure only. No application, customer or module names appear here by design.

## How to read this

Each item has an owner file, a cost, and a reason it exists. An item with no named consumer is not
on this list, per the artifact manifest's own rule. Ordering inside a wave is deliberate where it
says so.

Status vocabulary: `designed` means written down and not applied, `measured` means a number behind
it, `proposed` means an idea with a reason and no design yet.

---

## Wave 0. Cheap, certain, no dependencies

Nothing here waits on anything else. Roughly two days total.

| # | Item | Where | Cost | Status |
|---|---|---|---|---|
| 0.1 | Emit index facts from the facts instrument, join them in the loop skill | `project-bin/app-facts.sh`, `skills/microflow-loop-antipatterns.md` | 0.5 d | measured |
| 0.2 | Fix published service operations contributing zero reference rows | catalog build, upstream | 2 to 4 h | measured |
| 0.3 | Fix the model snapshot script on the single file model format | `bin/snapshot-mpr.sh` | 1 to 2 h | measured |
| 0.4 | File the three command line defects upstream | `bug-logs/` | 1 h | measured |
| 0.5 | Correct the MCP save claim, with its two caveats | `skills/learned-mcp-patterns.md` | 30 m | measured |
| 0.6 | ~~Correct the docs that say impact and local diff do not exist~~ | | | **withdrawn** |
| 0.7 | Remove a command from the docs that does not exist | `README.md`, `ROUTING.md`, `agents/test-agent.md` | 30 m | measured |
| 0.8 | Revisit the handoff tables against the bug log | `skills/iterative-build-loop.md`, `skills/migrate-general.md` | 2 h | measured |
| 0.9 | Document that catalog invalidation is keyed on path, not content | `skills/existing-app-assurance.md` and the read only wording everywhere | 1 h | measured |

**0.6 was withdrawn because the claim behind it was mine, not the toolkit's.** No sentence in the
toolkit denies that impact analysis exists. The roadmap described an error nobody had written. The
local diff claim is real but sits in exactly one sentence, in a design note written this week, and
it was never true. Both corrections cost minutes, and the lesson is worth more than the fix: an item
went onto a roadmap on the strength of a remembered reading rather than a grep.

**0.8 is the largest single pocket of rot found.** Five handoff rows tell a reader to open Studio
Pro, and four of them cite defects the toolkit's own bug log records as closed, or capabilities that
existed all along. Six of the nine confirmed drifts are the toolkit disagreeing with its own bug
log. On a project pinned below the installed Studio Pro version, an unnecessary open is not a
nuisance, it is an irreversible model upgrade.

**0.9 is a safety item wearing a documentation costume.** See 2.7.

**0.1 is the highest value item on this whole page.** A field dry run died because a performance
recommendation depended on whether a database index existed, and nothing collected that. It turns
out the describe command has been printing indexes all along, with sort direction and multi column
form preserved. On the probe application, 94.4 percent of persistent entities carry no index, and
of the in loop retrieves that filter on an attribute, 28 of 31 filter on an unindexed one. The
instrument existed. Nobody had looked.

**0.3 matters more than its size suggests.** The snapshot script fails on the older single file
model format with exit 1 and zero bytes on both streams, and the exec wrapper calls it
unconditionally, so the model guard chain is off on both legs on every project using that format.
Every failed attempt also leaves a full size orphan copy behind.

The root cause is **not** the directory test, which is what this roadmap said in its first draft and
what two other documents still say. An and-list is exempt from `set -e`. The actual killer is a
`find` over the missing directory inside a pipeline a couple of lines further down, where `pipefail`
propagates the failure and kills the script before its own format-aware refusal can run. Proved by
micro test. The fix needs a mirror arm in the restore script too, which today refuses the very
snapshot the fix produces. One hour plus a fixture.

---

## Wave 1. The fourth entry mode

Designed in `docs/existing-app-mode-design.md`. Needs a revision pass first, see 1.0.

**The order below is load bearing, and the reason is not what the first draft of this page said.**
Today the readers fail CLOSED. An absent or unrecognised mode resolves to empty, nothing is waived,
and all 36 manifest rows stay owed. That is the safe direction and it is not a defect.

The hazard is one we would CREATE. Add a parser arm for the new token before the manifest carries a
column 6 value for it, and every unedited row reports that the project does not owe it, which turns
a project owing its intake, its register, its triage, its requirements and its verification into a
clean run. So the manifest goes first. No test covers that column, which is the other half of why.

| # | Item | Where | Cost | Status |
|---|---|---|---|---|
| 1.0 | Revise the design note: four factual corrections, two disagreements | `docs/existing-app-mode-design.md` | 4 h | needed |
| 1.1 | Artifact manifest mode column, all rows, plus unknown token hardening | `bin/lib/artifact-manifest.tsv`, `bin/lib/artifact-check.sh` | 0.5 d | designed |
| 1.2 | Both mode parsers and the stage waiver arm | `bin/gate-check.sh`, `bin/lib/artifact-check.sh` | 0.5 d | designed |
| 1.3 | Classification rule ahead of the current first rule | `skills/conversion-runbook.md` | 2 h | designed |
| 1.4 | Slice table and blast radius rows in the triage template | `bin/lib/triage-template.sh` | 0.5 d | designed |
| 1.5a | Architecture stage reports not started when an upstream artifact is missing | `bin/gate-check.sh` | 30 m | confirmed |
| 1.5b | Architecture stage passes zero byte artifacts | `bin/gate-check.sh` | 2 h | confirmed |
| 1.5c | Resolve the architecture stage when a slice has no screens | `bin/gate-check.sh` | 0.5 d | designed |
| **1.9** | **Mode parsers substring match, so a mode line can waive the wrong stages** | `bin/gate-check.sh`, `bin/lib/artifact-check.sh`, `bin/status.sh` | 2 h | **confirmed** |
| 1.6 | Slice shape field, values change and addition, and its three rules | `skills/existing-app-change.md` | 4 h | proposed |
| 1.7 | Live model provenance in both report renderers | `bin/extraction-report.sh`, `bin/brd-report.sh` | 4 h | designed |
| 1.8 | An evaluation scenario for the existing app path | `evals/scenarios/` | 1 d | needed |

### Why 1.0 comes first

Research after the note was written found four claims in it that do not hold and two decisions
worth reversing.

Corrections: the artifact manifest has 36 rows, not 41. There are three readers of the mode, not
four. One report renderer shows a visible manual verdict rather than skipping silently. And four
of the five blast radius questions are answerable from catalog tables already present, so only
index collection is genuinely new work.

Disagreements, both worth taking:

- The note waives the design system for this mode. That orphans the wireframe, because the design
  artifacts spec requires every wireframe to link the shared stylesheet and a shell check compares
  built pages against it. Better answer: capture the application's existing theme once at
  onboarding as a standing artifact, and let every slice link it.
- The note waives the walking skeleton on the reasoning that on a live application the skeleton is
  the application. True for changing behaviour, false for adding it. Evidence: on the probe
  application nobody had ever executed a model write, and a model format blocker that took two
  research runs to surface would have appeared in twenty minutes under a skeleton.

### Why 1.5 is two items, not one

Both halves are confirmed and they need different fixes in different places, so they are split.

**1.5a is a reporting defect.** The check returns early when an upstream artifact is missing, before
it ever reaches the wireframe test, so a stage holding a genuine wireframe still reports not
started. The verdict is unchanged either way, so the cost is a misled reader rather than a wrong
gate. Fix inside the stage function: collect all four results and report everything missing and
everything present in one line.

**1.5b is a content defect and the serious one.** The shared artifact resolver tests existence only,
and the wireframe test adds no size test, so five zero byte files plus one signed row produce a
PASS. The same run prints a FAULT saying an artifact exists but is empty, three lines earlier. The
toolkit contradicts itself inside one output and the gate believes the wrong half. The same line
also misses a real wireframe one directory down, so it manufactures false red as well as false
green. A field run passed this stage with a stub that lied, which is the only place in that run
where the toolkit told a reader something false.

### Why 1.9 exists, and why the defect I went looking for does not

I sent an investigation after a believed defect: that an unparsed entry mode produces a false pass.
**It does not, and the belief was mine, not the toolkit's.** An absent or unrecognised mode resolves
to empty in both executable readers and fails closed. Nothing is waived. Stage P on a real unanswered
intake correctly reports FAIL. That claim is withdrawn.

The same lines do hold a real defect, and it is worse than the one I imagined. All three readers
match the mode with **unanchored substrings, tried in a fixed order, first arm wins**. So a mode line reading
`migration, definitely not greenfield` is read as greenfield and waives four stages, marking 17
artifacts as not owed. A line reading `migration (requirements documents also provided)` waives the
cutover stage on a migration project, which is the one project type that most needs it. The status
display shows the correct token for both, so the display and the gate disagree and nothing says so.

Fix is one shared tokeniser used by all three readers: first token, exact match, unknown resolves to
empty and writes a line to stderr. Not split, because all copies must change together or the readers
diverge again.

### Why 1.6 exists

Adding a feature inverts the blast radius question. All five inbound questions answer zero, and the
honest question is outbound: what do I read, and what breaks me when it moves. Three rules follow
from one declared field.

1. The coverage prohibition needs a mirror. It protects a change slice from reverse deriving a
   requirement from the live model. On an addition it is inert, and the slice feels free when it is
   not, because a leaf asserting anything about existing data is an assertion about the model. Rule:
   on an addition, any leaf asserting something about existing data must cite the describe output.
   Only leaves about new behaviour are free.
2. Split the slice table into modules read and modules written, and point the regression net at
   what is written. Without this, the rule that a module inside a dependency cycle makes the blast
   radius the whole cycle gives a read only screen a fifty module regression net.
3. The walking skeleton is owed on an addition and waived on a change, per the reasoning in 1.0.

---

## Wave 2. Closing the dossier's real gaps

The dossier earned its place as the first stage's artifact. It is not a knowledge base, and the
gap is now measured rather than guessed.

| # | Item | Where | Cost | Status |
|---|---|---|---|---|
| 2.1 | Name the dossier as the stage artifact and rewrite blast radius to read the facts | `skills/existing-app-change.md` | 0.5 d | designed |
| 2.2 | Names alongside counts in the inventory facts | `project-bin/app-facts.sh` | 0.5 d | measured |
| 2.3 | Decide fast versus full facts per stage, and fix the manifest when loops are skipped | `project-bin/app-facts.sh` | 4 h | designed |
| 2.4 | Ordering rule for the unranked middle severity band | `bin/app-report.sh` | 0.5 d | measured |
| 2.5 | Commit the layer map script and its skill | `bin/app-layer-map.sh`, `skills/layering-review.md` | ready | untracked |
| 2.6 | A delta between refreshes, beyond a plain file diff | `bin/app-report.sh` | 1 d | proposed |
| 2.7 | A standing check against documentation drift, four parts | `bin/check-cli-surface.sh`, `bin/check-negative-claims.sh` | 1 d | designed |

**2.7 is worth more than every individual correction in wave 0 put together**, because it stops the
class rather than the instance. Four parts. A help surface snapshot with a per release diff. A tag
on every negative claim naming the version and bug it was true against, so the check can fail on an
untagged negative and fail again when a tag names a bug the log now records as resolved. MCP rows
re derived from the binary rather than transcribed. And a fixture test that hashes a cloned model
directory before and after every command the toolkit labels read only, then prints what each one
actually wrote.

That last part exists because of a real incident during this work. "Read only" had been defined as
"does not change the model file" and then generalised to the whole disk. A command that only lists
rules silently rebuilt a full catalog into a degraded one, because invalidation is keyed on the
model's path rather than its content. The assurance skill's sentence is true about the model and
silent about the catalog beside it.

**2.4 has a measured answer already.** The middle band does not need a better sort, it needs one
fact. On the probe application, 53 of 109 middle findings are reachable from exactly one entry
point, and it is the same one for all 53. A further 22 are reachable from nothing. The genuinely
actionable band is about 30. A four part ordering rule of entry point class, loop body cost, blast
radius and flow size was tested against the real data and took a seventy way tie down to thirty
distinct ranks.

**2.2 is the structural cause of most of the remaining gap.** The inventory carries counts and no
names, which is why a slice has to go back to the model for anything specific.

---

## Wave 3. From the external harvest

Ranked by value over cost when the harvest was written. Two entries have been downgraded since by
direct measurement, and they are marked.

| # | Item | Cost | Status |
|---|---|---|---|
| 3.1 | Lint report converter, closing the lint placeholder section | 0.5 d | ready to port |
| 3.2 | Two security catalog queries, closing part of the security placeholder | 0.5 d | ready to port |
| 3.3 | Four loop and transaction anti patterns not in our list | 0.5 d | ready to port |
| 3.4 | Nine written performance guidelines, absorbed into the skills | reading | ready |
| 3.5 | Three graph rules: module fan out, orphan entities, unmapped roles | 1 d | ready to port |
| 3.6 | Severity and priority roadmap model | 1 d | partly done |
| 3.7 | Live runtime profiling | **downgraded** | see note |
| 3.8 | Chapter decomposition for a standard architecture document | days | deferred |
| 3.9 | A self contained document theme set for a PDF render | 1 d | ready to copy |

**3.7 is downgraded.** Direct inspection found fifteen markdown files with no code, and the command
line tool has since gained metrics, tracing and query level logging that cover most of it. Take the
written guidance, skip the rest.

**3.2 has a known boundary.** Four settings are not in the catalog at any level and can only come
from the lint builtin or the raw model. Those stay an honest placeholder with a named reason, which
is a far smaller admission than the whole section being one.

**The security section should split** into a collected part and a four item placeholder, rather
than remaining a single fault row.

---

## Wave 4. Not yet designed

Ideas with a reason and no design. Listed so they are not rediscovered.

- **Randomised input fuzzing at the model level** rather than through a browser. Novel, and it
  needs a seeding strategy because roughly a third of parameter slots are object typed. Two to
  three days. Worth more as a capability than as a demonstration.
- **A history for health**, so improvement between refreshes is visible. Today a second run cannot
  show that anything got better.
- **Namespaced slice artifacts**, so two change slices can be in flight at once. Deliberately
  rejected for now as premature. It is the open question most likely to be reversed first, and it
  means threading a slice argument through every file resolution in the gate.
- **Entity event handlers and loop collection size** in the facts. The first turned out to be in
  the catalog already, so this is smaller than it looked.

---

## What is not on this list, and why

- Wireframe generation for existing screens. Reverse deriving a requirement from a live model is
  forbidden by the coverage skill, and generating a picture of a screen that already exists is
  exactly that. Wireframe what has no implementation yet, never draw one backwards from running
  code.
- A load testing capability. Measured as theatre without production data volumes, and the static
  index audit answers the same question more honestly and in about a minute.
- A randomised browser walker. The client has documented traps that make an untuned walker thrash
  rather than explore. The model level equivalent above is the version worth building.
- Anything requiring a graph database or a vector store. The activity level schema is a good idea
  and far too heavy to carry for query convenience alone.

---

## Housekeeping owed before any of this ships

- Fourteen files trip the leak guard, eleven of them because of filenames in a contribution inbox.
  All predate this branch. Clean them so the guard passes honestly instead of being bypassed.
- Two design notes, a script and a skill are untracked in the worktree. Commit them.
- Two disposition stores now exist, the dossier's own section and an improvement register, which
  violates the toolkit's nothing in two places rule. Pick one.
