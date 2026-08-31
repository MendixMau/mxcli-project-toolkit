# Render, don't copy: agent-file distribution redesign + one copy list (design-note residue)

**From:** a personal-toolkit design note (2026-08-17), written after `sync-project.sh` was
found able to destroy ~33KB of completed agent config; queued genericized during the
2026-08-31 orphan-skill triage
**Date:** 2026-08-31
**Kind:** process
**Field evidence:** measured on a real project — five completed agent files (~33KB) would
have been replaced by 4.6KB templates because the stub detector reads the files' own literal
`{{DOUBLE_BRACE}}` safety sentence as proof of incompleteness (`gate-check.sh` fixed this
identical false positive by stripping it first; sync never got the fix). Diffing those
completed agents against their templates: three of five differ **only at placeholder
slots** — the files really are generic body + named slots.
**Proposed target:** `bin/sync-project.sh`, `bin/init-project.sh`, agent templates
**Already done, do not re-propose:** the same note's "Change 1" (exec.sh must not prompt to
reopen Studio Pro; opt-in `SP_RESTART=1` only) is already implemented —
`project-bin/exec.sh` now defaults `RESTART_SP="${SP_RESTART:-0}"` with the rule in a
comment.

---

## Change A — render agent files instead of guessing whether a human edited them

Split each agent file into: the toolkit-owned template, a project-owned
`.claude/agent-wiring.yaml` (never written by sync), and the generated
`.claude/agents/<name>.md` re-rendered from the two. Then:

- The clobber-bug class disappears — human work is not in the generated file.
- Template improvements finally arrive: today sync's only options are overwrite-everything
  or touch-nothing, so it picks touch-nothing and template edits reach 0 completed projects.

Two required escape hatches: `HAND_OWNED: true` (never render; each use signals the template
needs work — needed for the genuinely divergent files), and never render over an unrendered
edit without showing the diff. **Migration: don't** — mark all existing agent files
`HAND_OWNED`, let new projects start rendered.

## Change B — one copy list, not two

`sync-project.sh` and `init-project.sh` each carry their own list of installed crash-net
scripts, and at measurement time they disagreed (9 vs 7) — a brand-new project got *less*
than an old one. Same list, defined once, used by both (the `install-manifest.sh` precedent
already exists).

## Change C — a stale toolkit warns, never blocks

The note's Principle 1: someone must be able to keep working on an old toolkit commit
indefinitely; the `Toolkit commit:` mismatch should warn loudly and continue, with only an
artifact that genuinely requires a newer toolkit refusing, by name. (Triage note: the
hard-block appears already partially softened in current `gate-check.sh` — verify what
remains before promoting this part.)

Credit: a personal-toolkit design note, measured on a product-provisioning PoC project.
