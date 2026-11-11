# brain-kit: build a company brain

A company brain is a git repo of short markdown notes, one lesson each with its source, that coding agents search with grep.
This kit is the method and the scripts we used to build our internal Mendix knowledge brain, made portable.
It is the **knowledge** brain (lessons learned); house conventions for app builds are the company tier, `skills/company-brain.md`.
The skill that routes here is `skills/build-company-brain.md`.

| You want | Go to |
|---|---|
| **Understand the method** (11 steps, lessons from other brains, how to use, test and improve one) | [`METHOD.md`](METHOD.md) |
| **Start a brain by hand** (empty repo with AGENTS.md, ROUTING.md, note templates) | [`template/`](template/) + `bin/gate.py` |
| **Build a brain from your exports** (harvest, classify, shortlist, compact, keywords, gate, repair) | `bin/` + [`brain.yaml.example`](brain.yaml.example) |

## Start by hand (path B)

```bash
cp -R <toolkit>/brain-kit/template ~/acme-brain && cd ~/acme-brain && git init
# replace the {{...}} placeholders in AGENTS.md, ROUTING.md and README.md
mkdir internal/upgrade && cp note-templates/pitfall.md internal/upgrade/<slug>.md   # one lesson per note
python3 <toolkit>/brain-kit/bin/gate.py --brain . --checks lint          # free: shape, sources, links, denied names
python3 <toolkit>/brain-kit/bin/gate.py --brain . --checks lint,find     # + can a grep-only agent find each note? (cents per note)
python3 <toolkit>/brain-kit/bin/index.py --brain .                       # INDEX.md + QUALITY.md
```

## Build from exports (path C)

```bash
cp <toolkit>/brain-kit/brain.yaml.example ~/acme-brain-build/brain.yaml     # topics, sources, denied names, models
cp -R <toolkit>/brain-kit/template ~/acme-brain-build/brain
export BRAINKIT_CONFIG=~/acme-brain-build/brain.yaml
python3 <toolkit>/brain-kit/bin/ingest.py        # step 3: normalise exported .md/.txt/.html into work/ingest/
python3 <toolkit>/brain-kit/bin/classify.py      # step 4: cheap model, keep/maybe/no + topic per document
python3 <toolkit>/brain-kit/bin/shortlist.py     # step 5: one table per topic in work/shortlists/; a PERSON deletes rows here
<toolkit>/brain-kit/bin/build-topic.sh security  # steps 6 to 9: compact -> keywords -> gate -> repair -> re-gate -> index
```

Then write `AGENTS.md` and `ROUTING.md` for real (when to consult, and which trigger opens which topic): that is the judgment part
and no script does it for you. Wire the brain into projects with one pointer line in **every** instruction file (`CLAUDE.md`,
`AGENTS.md`, `.cursorrules`, ...).

## Requirements

- Python 3.10+ with `pyyaml` (`pip install pyyaml`; `anthropic` only for `backend: api`).
- Models: by default the scripts run **headless Claude Code** (`claude -p`) with whatever login it has, so no API key is needed.
  Set `backend: api` in brain.yaml to use the Anthropic SDK with `ANTHROPIC_API_KEY` (and `ANTHROPIC_BASE_URL` for a company gateway).
- Every step logs its spend to `work/costs.jsonl` and stops at `budget_usd` (or `BRAINKIT_BUDGET`).

## Rules the scripts enforce

- Nothing becomes a note unless a person left its source on a shortlist.
- Every note cites its sources; the faithfulness gate checks every claim against them.
- Names in `deny_names` fail the lint gate; credentials keep a document off every shortlist.
- A find run that broke (no answer, call cap, API error) is reported as a harness error, never as a low score.
