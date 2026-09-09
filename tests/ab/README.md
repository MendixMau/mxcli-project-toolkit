# A/B experiment corpus (arm branch only — never merged)

`corpus/` is a synthetic requirements corpus for a fictional "Harbour Berth Booking" application:
36 saved-webpage HTML exports with `_files/` sidecars, 4 Markdown files. No real organisation,
product, person or client data. It is generated deterministically by `gen-corpus.py` (seed
20260909) from an answer key that lives OUTSIDE this branch on purpose: the agent under test
must not see it. The key, generator, scorer and results are committed to master with the
experiment report under `process/`.

A session running on this branch: copy `corpus/` into the project's `sources/` and work the
pipeline. Do not read anything else under `tests/ab/`.
