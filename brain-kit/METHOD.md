# How to build a company brain

A company brain is a git repo of short markdown notes that coding agents (and people) search with grep. Each note holds one lesson
your teams learned, with its source. This page is the method we used to build an internal Mendix brain of about 600 notes, with the numbers
we measured along the way. The scripts in `bin/` run every step and `template/` is the empty brain to start from. A test run of the scripts on 39 pages
of the public Mendix docs (security, performance, REST) gave 69 notes, all three topics through the gate, for $5.26 end to end.

## Two kinds of brain: pick the one you are building

| | Knowledge brain (this page) | Company tier (`skills/company-brain.md` in this toolkit) |
|---|---|---|
| Holds | lessons learned: pitfalls, procedures, version facts, house rules, with sources | house conventions for builds: design system, approved components, own skills, lint rules |
| Built from | what your organisation already wrote down (wiki, repos, chat, field journals) | hand-made per company, filled as projects run |
| Read when | a risky task, an error, a step that is hard to undo | building any app for that company |

They combine well: the company tier's routing table can point at the knowledge brain. This page is about the knowledge brain.

## The pipeline at a glance

```
 1 SCOPE  ->  2 PROVE  ->  3 HARVEST  ->  4 CLASSIFY  ->  5 SHORTLIST  ->  6 COMPACT  ->  7 KEYWORDS  ->  8 GATE  ->  9 USAGE LAYER  ->  10 PROVE AGAIN  ->  11 KEEP ALIVE
 decide      measure       export         cheap model      a person          one lesson      grep terms      faithful +   AGENTS, ROUTING,   real task,          gaps drive the
 in / out    first         raw docs       per document     reviews           per note                        findable     INDEX              with / without      next harvest
```

| Step | Script | Model | Cost |
|---|---|---|---|
| 3 harvest | `ingest.py` (normalise exports) | none | 0 |
| 4 classify | `classify.py` | cheap (Haiku) | ours: about $11 for a few thousand pages |
| 5 shortlist | `shortlist.py`, then a person edits the tables | none | 0 |
| 6 compact | `compact.py` | writer (Opus) | demo run: $0.41 to $0.71 per topic of 20 to 24 notes |
| 7 keywords | `keywords.py` | cheap | cents |
| 8 gate + repair | `gate.py`, `fix.py` | judge (Sonnet), cheap, writer | the biggest share: one audit per note |
| 9 usage layer | `index.py` + hand-written AGENTS.md and ROUTING.md | none | 0 |
| | `build-topic.sh <topic>` chains 6 to 9 | | ours, whole brain incl. experiments: ~$180 |

---

## 1. Scope: decide what is in and what is out

Write the scope down before harvesting anything; every later prompt quotes it.

- **Out: public documentation.** Cite it, do not copy it. An agent already knows most of it, and a copy goes stale.
- **Out: one app's facts.** Decisions that are only true for one model belong in that app's own docs (for Mendix: `mxcli brain`).
- **Out: tools another source already covers.** We left mxcli out: the toolkit serves it in every session.
- **In: what nobody outside your teams knows.** Internal procedures, measured results, pitfalls with their fix, house rules,
  version-bound gotchas.
- **Topics.** 10 to 15 topic folders (security, upgrade, performance, integration, ...). One sentence per topic saying what is in it.
- **Layers.** Keep generated reference tables (`baseline/`) visibly separate from field lessons (`internal/`).

## 2. Prove it pays off, before building infrastructure

We wrote 15 real developer tasks with known right answers and ran them three ways:

| Arm | Score | Correct | Traps hit |
|---|---|---|---|
| No docs | 23% | 0 | 4 of 10 |
| Text search + read page | 70% | 6 | 0 |
| Hybrid index + link graph | 73% | 7 | 0 |

**Access to the material is the whole effect; how you retrieve it is noise.** That is why the brain is plain markdown and grep:
no vector database, no MCP server, no graph. Run your own small version of this test first; it takes a day and decides how much
infrastructure you need (probably none).

## 3. Harvest: export what the organisation already wrote

Export first, then normalise. `ingest.py` takes folders of `.md`, `.txt` or `.html` and writes one file per document with a uniform
header (id, title, url, author, date). **Get the url right**: the gate later resolves every note's cited url back to this file.

What we harvested: a few thousand wiki pages, a set of code repos, a chat troubleshooting digest, field journals, the public release
notes and Marketplace data, and one redacted upgrade procedure from the field.

The best single shape we found was the troubleshooting digest's **symptom / root cause / fix / status** entry: it became the pitfall
note shape.

## 4. Classify: a cheap model reads everything once

One call per document: keep yes / maybe / no, topic, likely note kind, a summary, key facts, names seen, secrets present, freshness,
quality 1 to 5. Our result: about 28% yes and 15% maybe, for about $11. **Use the cheapest model here**: it is a sieve, and a
person reviews what passes.

## 5. Shortlist: the human checkpoint

`shortlist.py` turns the classification into one table per topic (yes with quality >= 3, plus good maybes, each document on its first
topic only, secrets always out). **A person reads the table and deletes rows.** Nothing becomes a note that a person did not leave
on a shortlist. For a very large corpus we added a strong-model pass per space that opens the candidates and writes the shortlist with
reasons; for a few hundred documents the table is enough.

## 6. Compact: one lesson per note, in a fixed shape

The writer model gets one topic's shortlisted documents and writes notes:

| Kind | Body |
|---|---|
| pitfall | **Symptom** / **Root cause** / **Fix** / **Status** |
| procedure | **When** / **Steps** / **Checks** / **Watch out** |
| practice, decision | **Rule** / **Why** / **How to apply** |
| reference | a compact table |

Frontmatter: title, topic, kind, applies_to, versions, keywords, sources (title, url, author, date), status. The rules that matter:
only facts in the sources, no advice of its own, merge duplicates into one note, state conflicts, redact names, and a **Status** line
that says exactly what the source supports ("seen once", "fixed in 10.24.3", never "confirmed" unless a source says so).
Large topics run in batches: batch 1 writes, later batches **merge** into the notes so far, so a topic converges instead of growing
duplicates. Each topic ends with an INDEX (one hook line per note) and a **Gaps** list.

## 7. Keywords: where the reader's words meet the note's words

Agents grep for the symptom they see, not for the note's title. A cheap model adds 6 to 12 terms per note: the symptom in plain words,
exact error text and codes, module, API and setting names, synonyms. The gate's findability check tells you whether they work.

## 8. Gate: prove every note is faithful and findable

Three checks per topic; `gate.py` runs them, `fix.py` repairs failures, the gate runs again (unchanged notes reuse their verdict).

| Check | How | Bar |
|---|---|---|
| **lint** | frontmatter complete, kinds valid, sources present, 40 to 650 words, links resolve, no denied names | 0 errors |
| **faithful** | a second model lists every claim in the note and checks it against the note's own sources | >= 90% of notes with 0 unsupported claims |
| **findable** | a model writes the question a reader in that situation would ask, in their words; a search agent with only grep and read, following the brain's AGENTS.md, must return the note in its top 3 | >= 80% hit@3 |

Our result after repair: every topic 87% to 100% findable; 466 of 467 checkable notes faithful, 3 notes not checkable. Two lessons:
- **Test the test.** Every early low findability score we saw was a bug in our harness (the agent answered in prose, or ran out of calls),
  not a bad brain. The gate reports harness errors separately and never scores them as misses.
- **Facts that are tables belong in a script.** "Which module version works with Mendix 10.24" is a lookup, not prose: we keep
  a small lookup script beside the notes.

## 9. Usage layer: when to consult, and how

Three hand-written files decide whether agents use the brain well:

- **AGENTS.md**: *when* to consult (risky task types, an error code, a step that is hard to undo; **never for routine work**) and *how*
  (topic INDEX first, then grep one or two keywords, never a sentence; cite the note and its source; check `versions`).
- **ROUTING.md**: one trigger row per topic ("Upgrading Studio Pro or modules -> internal/upgrade/INDEX.md").
- **One pointer line in every instruction file of the project** (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, ...). In a test with a real
  theme module, a pointer in one file reached the brain in 2 of 3 sessions; the same pointer in every instruction file, 3 of 3.
  The session that missed simply never opened the one file that had it.

## 10. Prove it again, on a real task

We planned a real Mendix upgrade with and without the brain (brain held out for the lessons under test): **40 to 48% without, 68 to 76%
with**, at a lower cost per run because the agent needed fewer turns. Score this kind of test in code where you can (extract version
targets, compare in code); an LLM judge counting wrong claims was unreliable, so we checked those by hand.

## 11. Keep it alive

- Every topic INDEX keeps a **Gaps** list; the gaps decide what to harvest next.
- New lessons go in on a branch with a merge request; a person reviews before it lands; `status` moves from `draft-unreviewed` to `reviewed`.
- `QUALITY.md` shows the gate scores per topic, so readers know how much to trust each part.
- Re-run `build-topic.sh <topic> --merge` when the shortlist gains documents; the gate's cache keeps it cheap.

---

## Lessons from our other brains

Besides the internal knowledge brain we built company-tier brains: two for fictional demo companies (Tramius, a manufacturer, and
Kestrel, a bank) and two for customers. None of them has an eval yet, so these lessons come from reading the repos and their history,
not from scores.

| Brain | What worked | What went wrong |
|---|---|---|
| **Tramius** (manufacturer, 75 commits) | a design system as the master copy for 5 apps; a weekly checklist; a landscape table with a mode per system | it drifted into a project dump: 89% of its 524 files are project work (graph builds, an app design, mocks, a file parser) that no routing row reaches; a template row was never replaced; 1 of 5 apps is wired |
| **Kestrel** (bank, 3 commits) | a landscape table marked built / mock / gap; a "shared contract, binding for new apps" section; the first version was redone once a real solution existed | three routing rows point at a skills stub that points on to another repo, so an agent stops at the stub |
| **Customer A** (17 commits, filled in 2 days) | trigger-first routing with 12 rows; 4 skills in a fixed shape (Applies to, Steps, Done when, What each rule prevents); a mock built and tested | 8 of 11 knowledge notes have no routing row; deliverables live next to brain content |
| **Customer B** (1 commit) | real company and engagement history written down | the routing file is the untouched template and never points at that content |
| **Internal brain** (about 600 notes, 14 topics) | every topic INDEX keeps a Gaps list; one lookup script replaces paging through version tables | the first commit had no ROUTING.md, so it could not be wired for weeks; build intermediates with unredacted text were committed and had to be removed |

**The pattern:** the content was usually fine. What failed was the **route** from an agent to the content: rows missing, rows pointing at
stubs, template rows left in place, apps not wired.

### Rules we took from them

1. **Decide which kind you are building before the first file, and never mix.** A knowledge brain holds lessons; a company tier holds house
   conventions, landscape, contracts and design system. Project work (an app, a graph build, a mock) lives in its own repo.
2. **No route, no use.** Every folder an agent should read needs a trigger row in ROUTING.md. Check it weekly: every row's file exists,
   and every content folder has a row.
3. **Delete the template rows when you scaffold.** A dangling "example row" costs every session a wasted hop.
4. **Point routing at content, never at a stub or at another repo.**
5. **Put ROUTING.md in the first commit**, and never commit build intermediates (`work/` stays ignored).
6. **Ground a company tier in something built.** The bank brain's first pass on invented placeholders was thrown away; the customer brain
   filled in two days because real answers and a working mock existed.
7. **Company-tier content that earns its keep is what only that company knows**: binding contracts, which systems are real and which are mocks,
   design tokens. Lessons that hold for everyone belong in the knowledge brain or in the shared toolkit.

## Using, testing and improving a brain

### How agents reach it

```
 project instruction files            brain                          note
 (CLAUDE.md, AGENTS.md, .cursorrules)
 pointer line in EVERY file  ->  ROUTING.md: does a row fire?  ->  topic INDEX  ->  grep 1-2 keywords  ->  read, cite, check versions
                                  no row fires: close it, carry on
```

- **Pointer block.** In this toolkit, `bin/init-company-brain.sh` scaffolds a company tier and `bin/wire-company-brain.sh` writes a short
  pointer block (about 50 words) into every instruction file of a project. It refuses a brain without README.md and ROUTING.md and is safe to
  rerun. Done when each file has exactly one block and its path resolves.
- **Skills.** A skill reads the brain through the same route: it names the trigger ("before an upgrade, open ROUTING.md") and never copies
  brain content into itself. The toolkit itself never cites the brain, so a skill stays valid for teams without one.
- **When not to open it.** Opening ROUTING.md for a label rename cost 3 turns and $0.09 in a pilot. That is why AGENTS.md says "skip for routine
  work". A prototype that copies the trigger rows straight into the project's instruction file saves the hop for about 260 extra words that
  are always loaded; we have not yet measured whether it pays off.

### How to test it

| Test | What it answers | Cost |
|---|---|---|
| `gate.py --checks lint` | is every note well formed, sourced, linked, free of denied names | free |
| `gate.py` (faithful + findable) | does every claim match its source; can a grep-only agent find each note | cents per note |
| **real task, with and without the brain** | does it change the result | a few dollars per run |

For the real-task test: pick tasks with answers you can check in code, hold out the brain notes the task depends on, and run each arm at least
twice. Our upgrade test (2 runs per arm) went from 40 to 48% without the brain to 68 to 76% with it. **Treat two runs as a hint, not proof**:
one variant scored 76% and 55% on its two runs. Read what moved too: the whole gain came from the 16 module-version targets, the other 15
items stayed flat, and the extra detail made the agent drop "back up first" in 3 of 4 runs.

### How to improve it

- **Change the shape, then test again.** After the upgrade test we split one big table into one file per module and added a lookup script:
  module targets went to 15.5 of 16 and cost per run fell from $3.14 to $2.07.
- **A lookup returns candidates, not a guess**, when a name is ambiguous.
- **Gaps drive the harvest.** Every topic INDEX lists what no source covers; that list is the next export to ask for.
- **Re-gate after every change.** `build-topic.sh <topic> --merge` reuses the verdicts of unchanged notes, so a re-run is cheap.
- **Review moves status.** A person reviews a note on a merge request and moves it from `draft-unreviewed` to `reviewed`. QUALITY.md shows how
  far that has come per topic.

## What we would tell you on day one

1. Start with 15 real tasks and measure before you build anything.
2. Markdown and grep are enough. The gate is what makes grep work.
3. A cheap model sieves, a person decides, a strong model writes, a second model checks.
4. One lesson per note, a fixed shape per kind, the reader's words in `keywords`.
5. Say when NOT to use the brain. A brain consulted on every task costs more than it returns.
6. A brain nobody fills dies: wire the pointer everywhere, and let the Gaps list drive the next harvest.
7. Most brains fail on the route, not the content: no row in ROUTING.md means no agent will ever read it.
8. Keep project work out. A brain that becomes a project folder stops being a brain.
