# A/B experiment corpus (arm branch only — never merged)

`corpus/` is a synthetic requirements corpus for a fictional "Harbour Berth Booking" application:
36 saved-webpage HTML exports with `_files/` sidecars, 4 Markdown files. No real organisation,
product, person or client data. It is generated deterministically by `gen-corpus.py` (seed
20260909) from an answer key that lives OUTSIDE this branch on purpose: the agent under test
must not see it. The key, generator, scorer and results are committed to master with the
experiment report under `process/`.

A session running on this branch: copy `corpus/` into the project's `sources/` and work the
pipeline. Do not read anything else under `tests/ab/`.

## Small variant (2026-09-09)

The corpus was regenerated at a reduced size: sidecar images trimmed to 1–2 per page and
inline base64 screenshots to 2, so an unattended run finishes inside a session's limits. The
first attempt (187 sidecar images, 9 inline) exhausted the rate limit in every run before any
of them reached Stage 2. Every requirement, business rule, contradiction and screenshot-only
item is unchanged — only image volume was cut, so scores stay comparable.
