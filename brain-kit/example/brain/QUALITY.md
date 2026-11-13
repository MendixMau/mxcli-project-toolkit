# Quality gate results

Updated 2026-11-04. Automatic checks, not human review: notes stay `draft-unreviewed` until a person reviews them.

- **lint errors**: frontmatter, kinds, sources, size, links, denied names.
- **faithful**: notes with zero unsupported claims when a second model checks each claim against the note's own sources.
- **not checkable**: notes whose sources could not be matched to a stored document. Treat with extra care.
- **findable**: share of notes a grep-only search agent returns in its top 3 for a question written in the reader's words. Bar 80%.

| topic | notes | lint errors | faithful | not checkable | findable (hit@3) | gated |
|---|---|---|---|---|---|---|
| security | 21 | 0 | 21/21 | 0 | 100% | 2026-11-04 16:06 |
| performance | 24 | 0 | 24/24 | 0 | 100% | 2026-11-04 16:02 |
| rest-integration | 24 | 0 | 24/24 | 0 | 96% | 2026-11-04 16:11 |
