# Build a Company Knowledge Brain — lessons learned, sourced, gated, findable

**Applies to:** any mxcli project; any company that wants its teams' lessons in front of every coding agent.
**Purpose:** Turn what an organisation already wrote down (wiki, chat, field journals, repos) into a git
repo of short markdown notes, one lesson each with its source, that agents search with grep before risky
work. Method, template and scripts: `brain-kit/`.
**Source:** an internal Mendix knowledge brain (about 600 notes, 14 topics, 2026-10) and a demo run of the
same scripts on 39 public Mendix docs pages (69 notes, every topic through the gate, $5.26), 2026-11.

## When this fires

- Someone asks how to set up, build or fill a company brain with best practices or lessons learned.
- A team has a wiki or troubleshooting channel full of answers that agents never see.
- A brain exists and someone asks how to test it, why agents do not use it, or how to keep it alive.

For house conventions (design system, own skills, MDL snippets, approved components) use
`company-brain.md`: that is the company tier. The two combine — the company tier's `ROUTING.md` can
point at the knowledge brain for risky tasks.

## The method in one screen

Read `brain-kit/METHOD.md` before starting; it carries the numbers behind every step.

| # | Step | Tool | Rule that matters |
|---|---|---|---|
| 1 | Scope | by hand | out: public docs (cite, do not copy), one app's facts, tools another source covers |
| 2 | Prove | 15 real tasks | measure before building: no docs 23%, docs by text search 70%, graph index 73% — retrieval method is noise |
| 3 | Harvest | `bin/ingest.py` | export first, normalise once; get each document's url right, the gate resolves sources by it |
| 4 | Classify | `bin/classify.py` | cheapest model, it is a sieve |
| 5 | Shortlist | `bin/shortlist.py` | **a person deletes rows**; nothing becomes a note without a human-kept source |
| 6 | Compact | `bin/compact.py` | one lesson per note, fixed shape per kind (pitfall, procedure, practice, reference), Status says only what the source supports |
| 7 | Keywords | `bin/keywords.py` | the reader's words: symptom, error text, setting names |
| 8 | Gate + repair | `bin/gate.py`, `bin/fix.py` | lint 0 errors; faithful ≥ 90% of notes; findable hit@3 ≥ 80% for a grep-only agent; a harness error is never scored as a miss |
| 9 | Usage layer | `bin/index.py` + hand-written `AGENTS.md`, `ROUTING.md` | say when NOT to consult; pointer line in **every** instruction file (one file: 2 of 3 sessions reached it, all files: 3 of 3) |
| 10 | Prove again | real task, with and without | upgrade plan: 40 to 48% without, 68 to 76% with; two runs per arm is a hint, not proof |
| 11 | Keep alive | Gaps list per topic | gaps drive the next harvest; review moves `draft-unreviewed` → `reviewed` |

`brain-kit/bin/build-topic.sh <topic>` chains steps 6 to 9. Models run through headless Claude Code by
default (no API key); `backend: api` in `brain.yaml` uses the Anthropic SDK. Every step logs spend and
stops at `budget_usd`.

## Start small

1. `cp -R brain-kit/template <company>-knowledge-brain`, fill the `{{...}}` placeholders.
2. Write five to ten notes by hand on the one topic your teams get wrong most, from `note-templates/`.
3. `python3 brain-kit/bin/gate.py --brain <dir> --checks lint` (free), then `--checks lint,find`.
4. Write `ROUTING.md` (one trigger row per topic) and wire the pointer into every instruction file.
5. Only then run the harvest pipeline on exports.

**Done when:** every topic has an INDEX with a Gaps list, `QUALITY.md` shows lint 0, faithful and
findable above the bar, and a real task run with the brain beats the same task without it.

## Not this skill

- House conventions, design system, approved components for every app — `company-brain.md`.
- One app's decisions — that app's `docs/brain/` (`close-the-loop.md`).
