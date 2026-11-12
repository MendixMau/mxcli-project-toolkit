# How to use this brain (for coding agents)

This repo holds a DEMO of the brain format, built from a pinned slice of the public Mendix docs (security, performance, REST). A real company brain holds internal lessons instead: short notes, one lesson each, with their sources.
It is not the public documentation, and it holds nothing that is only true for one app (that lives in the app's own docs).

## When to consult it

Do not search the brain for every task. A lookup costs tokens and time, and on a routine change it adds nothing.
Consult it on these triggers only:

1. **Risky task types**: security and access rules, a performance problem, consuming or publishing a REST service.
   Skim the topic `INDEX.md` once at the start.
2. **On failure**: an error code, a stack trace, a build or deploy failure. Grep the code or the symptom noun.
3. **Before a step that is hard to undo**: changing access rules or entity access on a running app. Check for a pitfall note first.

Skip it for routine work: a new page, a small microflow change, a bug with a clear cause.

## Layout

- `internal/<topic>/<slug>.md`: notes. Each topic has an `INDEX.md` (one line per note) and a `## Gaps` list of what is not covered yet.
- `INDEX.md`: the topics. `ROUTING.md`: which trigger opens which topic. `QUALITY.md`: how the automatic gate scored each topic.

## How to search

1. When you know the topic, read `internal/<topic>/INDEX.md` first. The index lines are short hooks; skim them all.
2. Otherwise grep with ONE or TWO distinctive keywords per pattern, never a sentence. Use alternations for synonyms and spellings:
   `grep -rliE "timeout|time.?out" internal/`. Good keywords: error codes, product, module, API and setting names, the symptom noun.
   Bad pattern: "app won't start after the upgrade" (matches nothing).
3. Every note has a `keywords:` line with the words a reader would type; hits there are strong.
4. Narrow by frontmatter: `grep -rl "kind: pitfall" internal/<topic>/`, `grep -rl "versions:.*11" internal/`.

## Note frontmatter

| field | values |
|---|---|
| kind | pitfall (symptom / root cause / fix / status), procedure (when / steps / checks / watch out), practice or decision (rule / why / how to apply), reference (table) |
| applies_to | general (true for any Mendix app) |
| versions | the product or module versions the note is valid for |
| sources | where the lesson comes from: title, url, author, date |
| status | draft-unreviewed (generated and machine-checked), draft-thin, reviewed (a person confirmed it) |

## Rules when you use a note

- Say which note you used and pass on its source url.
- Check `versions` against the app you are working on. A note outside its version range is a hint, not a fact.
- `status: draft-unreviewed` means the note passed automatic checks against its sources, but no person has confirmed it yet.
- When a note states a conflict between sources, tell the user; do not pick a side silently.
- When the brain has nothing, say so and fall back to the public documentation.
