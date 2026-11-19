**From:** MendixUseCaseDiscovery
**Date:** 2026-11-19
**Kind:** metrics
**Field evidence:** metrics-ledger.tsv from MendixUseCaseDiscovery: 136 exec rows; summary only, no script names
**Proposed target:** see per-item notes below

---

```
== metrics-trend: 136 execs, 2026-11-18 → 2026-11-19

outcomes
  applied, clean gate+lint   16 (12%)
  applied, lint rose         89 (65%)
  applied, other             0 (0%)
  gate failed / rolled back  15 (11%)
  blocked / refused          13 (10%)
  snapshot restores          15

speed (elapsed seconds per exec)
  median 15   worst 143   runs 136
  first half median 15 → second half median 15 (+0)

lint (total findings, rows where lint ran: 104)
  first 23 (2026-11-18) → last 157 (2026-11-19)   delta +134

score: no scored rows (taken at each bin/module-close.sh, or on demand: bash bin/metrics-ledger.sh record; per exec only under `Score: every exec`; needs ./mxcli)
```
