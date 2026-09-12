# Token-path A/B — 2026-09-09 to 09-12

**Question.** A Markdown+HTML requirements project was slow and token-hungry through stages 1–4.
Does converting HTML once, retiring the always-on bug-ledger row, stage-scoped runbook reads and a
docs-ready fast path change cost and quality — and is the pipeline "overdoing" its artifacts?

**Method.** Synthetic "Harbour Berth Booking" corpus generated from an answer key
(`tests/ab/gen-corpus.py`, seed 20260909): 36 saved-webpage HTML exports with `_files/` sidecars,
4 Markdown files; 48 requirements, 15 rules with thresholds, 3 planted contradictions, 2
requirements present only inside screenshots. Scored by `tests/ab/score.py` (self-test: recall 1.0
on a perfect BRD set, 0.5 on a half set). Arms ran as unattended cloud sessions from the same
prompt; cost from the session record, timing from the run's own gate log. Corpus lives only on the
throwaway `ab/arm-*` branches, never on master.

## Wave 1 — Sonnet, stages P–2, one rep per arm

| | A master | B branch, standard path | C branch, docs-ready |
|---|---|---|---|
| cost | $7.94 | $5.45 | $5.42 |
| wall to Stage 2 | 19m04 | 12m46 | 12m04 |
| requirement recall (48) | 54% | 81% | 94% |
| rules with threshold (15) | 47% | 87% | 100% |
| contradictions surfaced (3) | 0 | 1 | 3 |
| screenshot-only found (2) | 1 | 2 | 2 |
| source ledger (run's own report) | PASS, 41 extracted + 159 waived | PASS, 200 extracted | PASS, 200 extracted |
| ASSUMED rulings | 17 | 14 | 8 |

Arm B found and ran `bin/html-to-md.sh` unprompted (it is routed), so B vs C isolates only the
waived Stage 1 + single glob mark + thin BRD. Recall matches in B/C are `section-cite` (a real
reference back to the converted section); A's are loose overlap.

## Wave 2 — Haiku, stages P–4, three corpora × two arms (+1 replication)

| run | corpus | arm | cost | P→4 wall | gates | BRDs | artifact words |
|---|---|---|---|---|---|---|---|
| harbour-a | synthetic docs | master | $0.73 | 4.3m | 0–4 pass | 5 | 43,551 |
| harbour-b | synthetic docs | branch | $0.96 | 5.6m | 1–4 pass (1 waived) | 8 | 58,290 |
| toeic-a | single-file HTML app + guide | master | $0.67 | 5.4m | 0–4 pass | 3 | 30,148 |
| toeic-b | same | branch | $0.90 | 7.8m | P–4 pass | 1 | 39,431 |
| puffin-a | React/Express/SQL code | master | $0.64 | — | **none: hollow run** | 0 | — |
| puffin-a2 | same (replication) | master | ~$0.7 | 8.2m | 0–4 pass | 4 | 12,327 |
| puffin-b | same | branch | $1.03 | 5.2m | P–4 pass | ? | — |

`puffin-a` wrote CONFIRMED decision rows for stages 2–4 with no artifacts behind them and
`PROJECT.md`'s stage header still at "Stage P". The replication did not reproduce it: one-off agent
failure, not a pipeline defect. Both runs left the stage header at "Stage P" (it is never
advanced) — that is what made the hollow run look plausible; small fix, filed as follow-up.

## Fixed reading load the runbook mandates (from `bin/lib/skill-routing.tsv`, master)

Baseline tier: 23 docs, 75,147 words, every session. On-demand routed on top: P 11.7k · 0 23.0k ·
1 17.3k · 2 8.4k · 3 23.1k · 4 18.4k · **5 134.2k** · 6 113.0k · 7 10.0k words. Stage 5's figure
is half `mxcli-bugs.md` (48.6k) which `bin/bug-lookup.sh` already replaces.

## Conclusions

1. The analysis stages are not inherently expensive: a full P–4 pass is 4–8 minutes and under
   $1.10 on Haiku for three different corpora. The slow day came from raw HTML in context, the
   stale 47.5k-word ledger row still wired into older projects, and interview stops.
2. `html-to-md.sh` is the single biggest win and is safe: 9× fewer agent-readable bytes, recall
   54% → 81–94%, both screenshot-only requirements found, and the routing delivers it unprompted.
3. The docs-ready fast path is strong on the one documents corpus (n=1, verbatim fixture): keep
   it as the explicit opt-in mode the runbook now describes, not the default, until a real corpus
   confirms it. Note its thin BRD carries no `microflows[]`; Stage 4 on `harbour-b` still produced
   a build plan, so the work moves rather than disappears.
4. No correctness change to the pipeline is warranted.
5. The real "overdoing" is proportionality, not volume: a 3-file corpus produced 30k words of
   stage artifacts, a 200-file corpus 44–58k. The artifact set is a fixed cost per project. A
   small-project tier naming which artifacts may be waived is the follow-up worth writing.

**Caveats.** n=1 per cell; the fixture restates every requirement verbatim, so recall partly
measures copying; precision is not meaningful (a BRD legitimately says more than the key);
unattended runs skip the interview cost; Stages 5–6 unmeasured. Spend: $118 on a first fan-out
that hit the rate limit before any run finished (nine Fable sessions — pilot one rep first), $19
wave 1, $5.60 wave 2 + replication.
