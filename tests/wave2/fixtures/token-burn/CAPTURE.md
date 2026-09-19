# token-burn fixture — capture notes

**Captured, not hand-written.** `transcripts/s-1.jsonl` and
`transcripts/s-1/subagents/agent-1.jsonl` are records taken verbatim in *shape* from a real
Claude Code transcript (captured 2026-09-18: a toolkit-maintenance session of ~17,000 lines,
plus one of its Agent-tool subagent transcripts), then scrubbed. Every structural fact
`bin/token-burn.sh` depends on is present because the real harness wrote it that way — none of
it was imagined:

- one `assistant` record **per streamed content block**, all carrying the same `message.id`
  and the same `usage` (the ~2× overcount if summed per record);
- `message.model` = `<synthetic>` on a harness-generated record (exactly one kept);
- `cwd` is **per record**: a session launched in `~` spends records in `~`, `~/proj` and
  `~/proj/app`;
- subagent files carry `isSidechain: true` and `agentId`, and sit under
  `<session>/subagents/`;
- `usage` has the four integer counters plus `cache_creation{…}` and
  `output_tokens_details` — and `output_tokens_details` is **`null` on some real records**
  (the scrubber crashed on it first; the instrument reads only the four integers, so it is
  unaffected, but any reader that walks `usage` deeper must guard for it).

## Selection

From the session: 5 days (2026-08-31, 09-01, 09-08, 09-15, 09-18), the first 6 distinct
assistant `message.id`s per day **with all their duplicate records kept**, at most 2
`user`/`queue-operation`/`system` records per day, and one `<synthetic>` record. From the
subagent transcript: the first 25 assistant records and their user turns (one day, 2026-09-17).
All records of the first in-project message id (`msg_14`) were rewritten to
`cwd: /srv/example/proj/app` to stand in for the two-tree (`.mpr` under `app/`) layout.

## Scrubbing

| Field | Replacement |
|---|---|
| `uuid` / `parentUuid` | `u-<n>` (one consistent map) |
| `message.id` | `msg_<n>` (one consistent map — duplicates stay duplicates) |
| `sessionId` | `s-1`; `agentId` → `agent-1` |
| `cwd` | home → `/srv/example`; the toolkit clone → `/srv/example/proj`; anything else → `/srv/example/other` |
| `message.content` | the string `"[scrubbed]"` |
| dropped | `gitBranch`, `slug`, `requestId`, and every other key not listed under "kept" |

Kept: `type`, `sessionId`, `uuid`, `parentUuid`, `isSidechain`, `timestamp`, `version`, `cwd`,
(`agentId`), and `message{model, id, type, role, content, stop_reason, usage{input_tokens,
cache_creation_input_tokens, cache_read_input_tokens, output_tokens, cache_creation,
output_tokens_details}}`. No real path, id, name or content survives; the fixture is safe to
publish.

## Expected numbers (computed independently of the instrument)

One Python one-liner over both files: unique `message.id`, `type == assistant`, model not
`<synthetic>`, `cwd` at or under `/srv/example/proj`. Columns are
input · cache-write · cache-read · output · messages; headline = input + cache-write + output.

| | input | cache-write | cache-read | output | msgs | headline |
|---|---|---|---|---|---|---|
| claude-fable-5-1 | 288 | 31365 | 2607781 | 15524 | 9 | 47177 |
| claude-sonnet-5 (subagent) | 26 | 59772 | 998476 | 60 | 13 | 59858 |
| **total** | 314 | 91137 | 3606257 | 15584 | 22 | 107035 |

Records: 52 in-project assistant records collapse to 22 messages; 76 records at
`/srv/example` are excluded; 6 records of `msg_14` are at `/srv/example/proj/app` and count.

Per day (headline): 2026-09-08 → 38527 (5 msgs) · 2026-09-17 → 59858 (13) · 2026-09-18 → 8650 (4).
With `PROJECT.md` beside: stage 1 = 2026-09-08 = 38527 (`39k`); stage 2 = 09-17 + 09-18 =
68508 (`69k`, sonnet-5 87% · fable-5-1 13%, cache-read 1438109 → `1438k`); current stage 2.
