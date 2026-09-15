# Skill: app-analysis — a standing dossier of an existing app before you change it

**Use when:** you are handed an app you did not build (inheritance, takeover, review,
"continue development on this"), before the first change slice and again at every milestone.
The output is `architecture/app-dossier.md`, a document the team keeps, plus an HTML render
of it for people who will not open a repository.

**Do not use for:** a build plan of something new (`skills/coverage-ledger.md`), a lint run
(`project-bin/lint-gate.sh`), or a single change (`skills/existing-app-change.md`, which
this dossier feeds).

**Instrument:** `project-bin/app-facts.sh` (installed as `bin/app-facts.sh` in a project).
It collects facts into `analysis/app-facts/`. It has no opinion. Every verdict in the dossier
is yours, written by the rules below.
**Renderer:** `bin/app-report.sh` in the toolkit turns the dossier plus facts into
`analysis/app-report.html`.

---

## The one rule

> The dossier states what is TRUE about the app, with the query or file that proves it,
> and a disposition for each finding that says what will be done about it. A section the
> instrument did not collect is written as **fault**, never omitted.

An omitted section reads as "nothing wrong here", the most expensive lie a review can tell.
The manifest has a status for every section, including the ones this version cannot fill;
carry them all across.

## Procedure

1. **Collect.** `bin/app-facts.sh` in the project root. First run on a big app takes minutes:
   a full catalog rebuild plus 1-2 s per loop-containing microflow (300 of them at 4 workers
   is 2-3 minutes). Exit 2 means the facts are not trustworthy; read the message, fix the
   cause, rerun. Do not write a dossier from a run that exited 2.
2. **Read `manifest.json` first.** Check `sections.*.status`. Note `parse_mismatch`, `failed`
   and `rules_not_describable` under loops: each one is a document the loop section says
   nothing about. `catalog_undercount` is not in that list; it is the catalog's blind spot.
3. **Write or refresh the dossier** section by section, using the rules below and the two
   companion skills for the judgement calls: `skills/module-dependency-review.md` and
   `skills/microflow-loop-antipatterns.md`.
4. **Keep dispositions.** On a refresh, regenerate the fact sections and leave the
   Dispositions section as it is, then reconcile: a disposition whose finding is gone is
   marked resolved with the date; a new finding gets a new disposition line, even if that
   line says "accepted, no action" with a reason.
5. **Render.** `bin/app-report.sh` from the project root. It writes `analysis/app-report.html`
   and `analysis/app-report.json` beside it. Open the HTML once and look at it
   (`skills/measured-claims.md`: a render you did not look at is not verified). Read the
   executive summary the way a stakeholder will: if the fix-first list does not name the five
   things you would start on Monday, the scoring inputs are wrong, not the list.
   **An agent arriving later reads `analysis/app-report.json`, not the page.** It carries the
   health state, the severity counts, every scored finding with its evidence path and
   recommended fix, the review progress, and the section verdicts. Do not parse the tables.
6. **Hand-check two facts** against Studio Pro or `mxcli describe` before you publish, one
   from the dependency section and one from the loop section. The instrument has been
   wrong before (a join bug once zeroed the bidirectional-pair count on 302 edges). If your
   checks disagree with the facts, stop and fix the instrument, not the dossier.

## Dossier layout

`architecture/app-dossier.md`, in this order. Headings are fixed so the renderer and the
next reader find them.

The rendered page does NOT open with this layout. It opens with an executive summary the
renderer derives: what the app is, the health state, the fix-first five, review progress, and
what was not measured. Section 1 below is the second thing on the page, not the first, because
a table of statuses is not what a person opening a report needs to read first.

```
# App dossier: <app name>
Generated <date> from <mpr> (<sha16>) with <mxcli version> · facts: analysis/app-facts/

## 1. Verdict summary        one table: section · status · one-line reason
                            first cell is the bare title: `Inventory`, not `2. Inventory`
## 2. Inventory              what is there
## 3. Dependency shape       how modules lean on each other
## 4. Flow risk patterns     what loops do
## 5. Security posture       FAULT in this version
## 6. Lint baseline          FAULT in this version (run lint-gate.sh, paste its summary)
## 7. Dead elements          from graph_dead_assets, own modules; manual confirm before delete
## 8. Dispositions           hand-written, survives refresh
## 9. Method                 which queries, which thresholds, what was NOT checked
```

### Section statuses

Use the toolkit verdict vocabulary (`skills/report-schema.md`):

| status | meaning here |
|---|---|
| `pass` | collected, judged, nothing above threshold, or every finding has a disposition that is a decision |
| `fail` | collected, judged, at least one finding above threshold without a decision (`later` with no slice or date, `undecided`, or a missing line all count as no decision) |
| `fault` | not collected, or collected but not trustworthy (partial describe, parse mismatch above `MAX_PARSE_MISMATCH_PCT`) |
| `manual` | collected, but the verdict needs a person (dead elements, every "accepted" disposition) |
| `skipped` | deliberately not run this time, with the reason in the summary row |

A section with zero findings AND zero measured items (zero own modules, zero loops on an app
with 1,000 microflows) is `fault`, not `pass`. Measure the denominator before you believe
the numerator.

### Two verdicts, because there are two questions

Those five words judge the REVIEW: how much of this document has been decided. A first dossier
has no decisions, so every section reads `fail`. That is honest about the document and says
nothing at all about the app, and a colour that is red on a healthy app and on a sick one
teaches people to ignore it. So the renderer scores the app separately, from the facts alone.

| axis | question it answers | values | moves when |
|---|---|---|---|
| health | how risky is this app today | `ok` · `watch` · `at risk` · `unknown` | the app changes |
| review progress | how much has been decided | `not started` · `in progress` · `complete` | the dossier changes |
| section verdict | collected, and dispositioned | the five words above | either changes |

Health is `at risk` with any critical or high finding, `watch` with any medium, `ok` otherwise,
and `unknown` when inventory, dependencies or loops did not collect. It needs no dossier, so
it reads the same on a first run and a tenth, and the same way on another app. Never quote one
axis as the other: "the report says fail" is a statement about the document.

### Severity

A property of a finding, not of a section. Four words, the ones the expert-services reviews
already use: `critical`, `high`, `medium`, `low`. Score = pattern class + scheduled reach +
blast radius, and 6 is critical, 4 to 5 high, 2 to 3 medium, 1 and under low.

| input | weight |
|---|---|
| `REST_IN_LOOP`, `END_TRANSACTION`, `DEP_TANGLE` | 3 |
| `LOOP_TQ`, `LOOP_COMMIT_DEFERRED`, `DEP_PAIR` | 2 |
| `LOOP_NESTED`, `DEP_COHESION`, `DEAD_CANDIDATES` | 1 |
| reachable from an **enabled** scheduled event | +2 |
| reachable only from a disabled one | +1 |
| the module is depended on by `WIDE_BLAST_INBOUND` (6) or more own modules | +1 |
| a tangle, always +1, and +1 again at `WIDE_BLAST_INBOUND` members or more | +1 or +2 |

Three inputs, all already collected, none of them an opinion: what the statement costs per
iteration, whether anything runs it unattended, how many modules feel it. `bin/app-report.sh`
does the arithmetic and prints the derivation under the fix-first table; the weights live in
this table. Change them in both places or the page stops matching the skill.

A severity is never a decision. A `critical` finding with `accept · owner · reason` is a closed
line and still critical; that is the point of keeping the two axes apart.

The renderer takes the worse of instrument status and your verdict: a dossier `skipped` always
stands; an instrument `fault` or `partial` beats a dossier `pass`; a section missing from the
dossier renders `fault`; no dossier at all renders every section `manual`. You cannot pass a
section the instrument did not collect. When the render disagrees with you, fix the collection.
Write the verdict table's first cell as the bare title (`Inventory`): the renderer tolerates a
leading `2. ` and bold markers, but bare is the convention.

## Thresholds

Named so a project can override them at the top of its dossier under a `Thresholds` line.
Defaults come from four probe projects (62 to 2,700 microflows); starting points, not law.

| constant | default | used in |
|---|---|---|
| `MAX_ENTITIES_PER_MODULE` | 15 | inventory: a module carrying more is a candidate to split |
| `MAX_ATTRIBUTES_PER_ENTITY` | 20 | inventory: count of wide entities per module |
| `MAX_ACTIVITIES_PER_MICROFLOW` | 25 | inventory: count of long microflows per module |
| `MIN_COHESION_PCT` | 60 | dependency: a module below it mostly talks outward |
| `MAX_FANOUT_MODULES` | 6 | dependency: a module depending on more own modules than this is a hub |
| `LOOP_DB_CALLS_MAX` | 0 | loops: any database retrieve, commit, delete or REST call inside a loop body is a finding |
| `MAX_PARSE_MISMATCH_PCT` | 5 | loops: above this share of microflows where the parser found fewer loops than the catalog (`parse_mismatch`), section is `fault` |
| `WIDE_BLAST_INBOUND` | 6 | severity: a module depended on by this many own modules or more adds +1 to every finding inside it |

## Section rules

**2. Inventory.** One table of own modules: entities (persistent / non-persistent / view),
microflows, nanoflows, pages, loop activities, count over `MAX_ENTITIES_PER_MODULE`,
`MAX_ATTRIBUTES_PER_ENTITY`, `MAX_ACTIVITIES_PER_MICROFLOW`. Marketplace modules as one
line each with version. Scheduled events as a table: name, microflow, enabled, interval,
with the enabled and disabled totals stated: only an enabled event puts a loop on the
nightly path. Inventory is `pass` when written; it carries no verdict of its own. Point at
the outliers in one sentence each, do not editorialise.
A marketplace module imported without metadata reads as own. The instrument honours
`.claude/lint-vendor-modules.txt` (the file `lint-gate.sh` uses) and classes those as
marketplace; if obvious vendor modules still show as own, add them there and rerun rather
than hand-correcting the dossier.

**3. Dependency shape.** Follow `skills/module-dependency-review.md`. Report edges between
own modules, bidirectional pairs, cycles, cohesion per module, hubs, and the top god nodes.
`fail` when any cycle or bidirectional pair exists without a disposition, or a module is
below `MIN_COHESION_PCT`. Marketplace and System are context, never findings.

**4. Flow risk patterns.** Follow `skills/microflow-loop-antipatterns.md`. Report each
loop-containing microflow that has a database call, commit, delete, REST call, Java call or
nested loop in a loop body; mark the ones reachable from a scheduled event. `fail` when any
row has no disposition. `fault` when `manifest.sections.loops.status` is not `pass` or the
parse-mismatch share exceeds `MAX_PARSE_MISMATCH_PCT`. `rules_not_describable` does not fault
the section: name those documents under Method and open them in Studio Pro before the next
milestone. Unread `LOOP_CALL` rows cap the section at `manual`; `fail` still wins.

**5. Security posture** and **6. Lint baseline.** Write the `fault` row with the manifest's
reason verbatim, and give each one an id-bearing line (`SEC-FAULT-01`, `LINT-FAULT-01`) so a
later run can close it rather than rediscover it. For lint, running `bin/lint-gate.sh` and
pasting its summary block under the heading turns the section to `manual` (the gate's own
verdict stands; the dossier only quotes it). Automating both is tracked in the CHANGELOG.

**7. Dead elements.** From `dead_assets_own` in `dependencies.json`: the total, a breakdown by
asset type, and the top 20 modules by count. Do not list every asset. Always `manual` until a
dead-element instrument exists: the catalog cannot see Java code, published REST operations
called by name, or workflow references, so "no inbound reference" is a candidate, not a
verdict. Confirm each in Studio Pro ("Find usages") before it reaches a change slice.

Every finding table in sections 3 and 4 carries a **severity** column, first, with the score in
brackets, and is sorted worst first. Write the id in backticks and the target name in brackets
on the disposition line (`` `LOOP-TQ-07` (Module.SUB_Name, LOOP_TQ) ``): that is how the
renderer matches a decision to the finding it scored, and an unmatched decision shows as an
undecided finding on the page.

**8. Dispositions.** One line per finding: `<finding id> · <decision: fix | accept | later> ·
<owner> · <reason or slice>`. Finding ids come from the companion skills (`DEP-CYCLE-01`,
`LOOP-DB-014`, and so on). It is where the team's decisions live, and a refresh never
rewrites it; that is what makes the dossier a standing document and not a report.
A `later` is a decision only with a slice or a date; `later, undecided` is a placeholder and
leaves the section `fail`. Ids are never reused or deleted: a finding that stops existing
(module reclassified, loop removed) keeps its line, marked `closed <date>: <reason>`.

**9. Method.** Copy the mxcli version, timings and counts from `manifest.json`. State the
thresholds in force. Record every hand check you made (which MDL files you opened, which
counts you recomputed), the loop `catalog_undercount`, and any module you reclassified. List
what was not checked, in words, so the next reader does not assume it was. The four known
blind spots of this version: security, lint, workflow documents, and anything inside Java
actions or JavaScript actions.

## What is NOT a finding

- A marketplace module depending on another marketplace module. Not ours.
- `System` as a target. Every app depends on it.
- A page referencing an entity in another module. Pages are UI, they cross modules by design;
  the finding is when microflows and associations do it both ways.
- A loop that only builds a list, changes objects in memory, or calls a microflow that does the
  same. Read the called microflow first (`LOOP_CALL`).
- A retrieve over an association from an object already in memory (`RETRIEVE_ASSOC`). Usually
  costs nothing; read the microflow before listing one.
- A loop inside a marketplace module. Not ours: accept it, and give the count one line
  under Method rather than a disposition each.

## Refresh discipline

Refresh at every milestone and before every review, not on every commit. The instrument
rewrites the catalog, which every other mxcli command shares, so run it when nobody is
mid-edit. Commit `architecture/app-dossier.md` and `analysis/app-facts/manifest.json`,
`inventory.json`, `dependencies.json`, `loops.json`. Do not commit `analysis/app-facts/mdl/`
(hundreds of files that regenerate in minutes) or the HTML render, unless the project has
decided otherwise.

## Related

- `skills/module-dependency-review.md`, `skills/microflow-loop-antipatterns.md` (the judgement)
- `skills/existing-app-assurance.md` (the à-la-carte audit this dossier is the map for)
- `skills/existing-app-change.md` (the change slice that reads the dossier first)
- `skills/lint-that-actually-runs.md`, `skills/report-schema.md`, `skills/measured-claims.md`
- `skills/skills-over-scripts.md`: the instrument fetches, this file judges; keep it that way
