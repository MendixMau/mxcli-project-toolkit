# exec.sh keeps an MDL write when mxbuild crashes after it, and the next exec runs on an unloadable model

**From:** a field project (anonymised) — an existing Mendix app being changed with mxcli + this toolkit
**Date:** 2026-10-13
**Kind:** bug
**Field evidence:** the project's BUILD-LOG shows two "gate could not run" rows 46 s apart: the
script that made the model unloadable, then the next script, which exec.sh accepted and ran on top
of it. Mendix 11.14.0 Beta (Classic client), mxcli v0.25.0, toolkit commit c1efcb3 (`project-bin/exec.sh`
is byte-identical on master 0c62f6f, blob a03adec).
**Proposed target:** `project-bin/exec.sh` (gate branch "mxbuild failed to run" and the pre-flight
"Baseline NOT measured" branch); one line in `skills/iterative-build-loop.md`

---

## What happened (finding, reproduced once in the field)

A page script set a data view's data source to a two-hop association path in its full form
(`$Parent/MyModule.A_B/MyModule.B/MyModule.B_C/MyModule.C`). `mxcli check` passed. After the
exec, the mxbuild loader itself crashed instead of reporting CE errors:

```
An error occurred when trying to set the 'DestinationEntity' property of a Entity ref step in a Page.
```

exec.sh printed:

```
  ✗ mxbuild failed to run (exit 1) — gate could not verify the model.
  → Snapshot preserved. Open in SP to verify manually before proceeding.
```

and kept the write. It did exit 1 and cleared the verification stamp (good), but the agent driving
the build ran the next script. exec.sh's pre-flight printed `⚠  Baseline NOT measured: mxbuild exited 1
without checking the model.`, carried on, applied the next script, and hit the same crash.

BUILD-LOG rows, verbatim except the script names:

```
| 2026-10-13T12:26:18 | `25g-PageA-rebuild.mdl` | fail | ❌ gate failed | 5 error(s): CE1613 — script rolled back · approval: auto (PROJECT.md) |
| 2026-10-13T12:28:46 | `25g-PageA-rebuild.mdl` | fail | ❌ gate could not run | mxbuild exit 1 · approval: auto (PROJECT.md) |
| 2026-10-13T12:29:32 | `25h-SnippetB-rebuild.mdl` | fail | ❌ gate could not run | mxbuild exit 1 · approval: auto (PROJECT.md) |
```

Recovery: `./bin/restore-mpr.sh <full path to the snapshot taken before 25g>` then
`./bin/verify-model.sh` (0 errors). The 25h row had to be re-run afterwards.

## Why it matters

- The header comment of exec.sh says an unverified gate is rolled back **for `--patch` only**. That is
  true and deliberate, but for MDL the "kept" case was designed for "mxbuild could not start"
  (wrong version, no JDK). Here mxbuild started, ran on the baseline cleanly a minute earlier, and
  crashed only on the written model. That is a property of the write, not of the machine.
- The next exec has no way to tell the two apart: "Baseline NOT measured" is a warning, not a refusal.
  So in an unattended chain the damage compounds: every following script is written onto a model
  nothing can load, and each one gets its own snapshot of the broken state.

## Proposed fix (hypothesis, not built)

1. **Restore when mxbuild ran clean on the baseline but cannot run after the write.** exec.sh already
   has both facts: the pre-flight measured a baseline (`BASE_KNOWN=1`) and the post-exec run exits
   non-zero with no errors file. In that case, call `restore_snapshot` exactly as the `--patch` path
   does, and log `↩ rolled back: mxbuild crashed on the written model`. Keep today's behaviour when the
   baseline itself was not measured (that is the real "machine cannot build" case).
2. **Refuse a write when the baseline cannot be measured** and the last BUILD-LOG row for this model
   is `gate could not run`, with one STOP line naming `bin/restore-mpr.sh` and the snapshot to restore.
   `ALLOW_UNVERIFIED=1` stays the explicit override.
3. Reword the kept-write message: "Open in SP to verify" is not something an agent can do. Something
   like `STOP: the model may not load. Restore with ./bin/restore-mpr.sh <snapshot path>` is actionable.

Probe that would falsify the claim (for the retest fixture): a fake mxbuild that exits 0 on the
baseline and exits 1 with no errors file after the exec; today exec.sh exits 1 and leaves the
written model in place; after the fix the model on disk equals the snapshot.

Related: `--patch` already restores on an unverified gate (header lines 25–29); PR #304 touches the
same file (per-project lock) but not this branch.
