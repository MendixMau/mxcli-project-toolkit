# Context cost — read the finding before you install anything

**Applies to:** any project run by an AI coding agent over weeks. Moved here from `README.md` on 2026-09-02; the README keeps a one-paragraph pointer. Nothing below is Mendix-specific — it is about running Claude Code, and it applies to every repo the hooks touch.


A month's token allowance, 20% of it gone in three days: about **2x the sustainable rate**. The
cause was not carelessness. Measured across 10,855 main-loop calls on one project:

| model | calls | median ctx | p90 | max | over 200k |
|---|---:|---:|---:|---:|---:|
| Sonnet 4.6 — 200k window | 2,416 | 104k | 147k | 166k | **0%** |
| Opus 5 — 1M window | 8,439 | 296k | 689k | 907k | **70%** |

**89% of cache-read spend ($1,276 of $1,437) came from context above 200k** — territory that was
*structurally impossible* on the older model.

The 200k window was a **cost governor disguised as a limitation**. It was experienced as friction
— "I have to compact constantly" — while doing the budgeting for free, on every call. The 1M
window did not make sessions cheaper; it removed the thing that was making them cheap and handed
the job to you, with no meter and no alarm. A habit that had been enforced became optional, and
optional habits decay.

Two things people reach for that do not fix it:

- **A cheaper model.** Sonnet 5 is also a 1M window. It cuts the *rate* ~40% and leaves the 89%
  untouched. Per call: Opus@341k $0.17, Sonnet@341k $0.10, **Opus@100k $0.05**. Context discipline
  is a 3.4x lever; model tier is 1.67x.
- **Just remembering to `/clear`.** The cost is on the other side. After a `/clear`, rediscovering
  state from `PROJECT.md` + checkpoints + progress + handoffs cost **100k tokens** — and whatever
  a session reads at startup rides in its prefix and is re-read on *every subsequent call*. ~$10,
  paid ~300 times. That is what `RESUME.md` and `checkpoint.sh` exist to prevent; see
  `skills/close-the-loop.md`.

### The hooks, and why they are tiered

```bash
bin/install-claude-hooks.sh              # prints the tier table, installs nothing
bin/install-claude-hooks.sh --basic      # tier 1
bin/install-claude-hooks.sh --full       # tier 1 + 2
bin/install-claude-hooks.sh --full --ceiling   # + tier 3, which BLOCKS tool calls
bin/install-claude-hooks.sh --uninstall
```

These hooks are **user-global**: `~/.claude/hooks/` fires in every repo and every concurrent
session on the machine, Mendix or not. That asymmetry is the whole reason for the tiers — a bad
skill wastes tokens, **a bad global hook blocks work everywhere**.

| Tier | Flag | What you get | Who it is for |
|---|---|---|---|
| 1 | `--basic` | `shrink-image-read` (downscales screenshots before they enter context), plus `checkpoint.sh` / `close-task.sh` in `~/.claude/bin` | Anyone, day one. Non-blocking, no failure mode |
| 2 | `--full` | `context-watch` (advisory cost meter), `work-boundary`, `precompact-guard` | People who have felt the pain. Noise before that |
| 3 | `--ceiling` | `context-ceiling` — **refuses tool calls** above a limit; the session goes write-only | A deliberate, informed choice. Never a default |

Tier 3 refuses Read/Grep/WebFetch/Agent and most Bash, and keeps Write/Edit/checkpoint/git open,
so the escape route is open by construction. Every hook also has an env-var escape that needs no
reinstall: `CLAUDE_CTX_WATCH=0`, `CLAUDE_CTX_CEILING=0`, `CLAUDE_PRECOMPACT_GUARD=0`,
`CLAUDE_WORK_BOUNDARY=0`. The uninstall line is printed on every run.

**Do not install tier 3 on someone else's machine.** Evidence: an earlier guard blocked a session
that had done everything right — handoff doc, scope status, 18 BRDs written — but had not used
`checkpoint.sh`, the one artifact the guard recognised. An expert user's reaction was *"I can't
even compact?"*. Two rules fell out of that, and they generalise to any guard:

1. A blocking guard must accept **evidence it did not itself create** — a recent commit, a
   recently modified doc — not only its own stamp file.
2. A guard must **never block the action that resolves it.** Blocking `/compact` when compaction
   is the remedy is perverse. Warn once, then let it through.

`init-project.sh` mentions this section and never installs global hooks silently.

**Hand someone the hooks without the numbers above and you get cargo cult** — they disable the
ceiling the first time it fires, because nobody told them what it was protecting them from. Lead
with the finding, not the install command.

---

