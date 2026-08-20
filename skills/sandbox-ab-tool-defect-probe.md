# Sandbox A/B: proving a tool defect is version-specific, without risking the model

**Applies to:** any mxcli project.

**When to read:** you suspect an mxcli/mxbuild defect, or you're about to decide whether to swap a
binary. Also whenever a probe would write something the model's loader might reject.

Established 2026-08-04 when investigating whether a defect is real or environment-specific (a
workflow `CALL MICROFLOW` on Mendix 11.13 — tagged mxcli v0.16.0 crashed the MPR loader; a clean
reference commit was unaffected. Same model, same script, same gate).

## The method

1. **rsync the whole project dir to `/tmp`** — one sandbox per arm.
2. **Baseline-gate each sandbox before probing.** If baseline isn't clean, the sandbox is wrong,
   not the tool.
3. Run the identical probe in each arm, varying **exactly one** thing (usually the binary).
4. Gate each arm. Then **roundtrip-read** the written element — persisting is not the same as
   persisting correctly.
5. `rm -rf` the sandboxes. Record the result; never leave 400 MB copies lying around.

## The traps that cost real time

- **`mx check` needs the whole project directory, not just `.mpr` + `mprcontents/`.** Copying only
  the model produced **1337 spurious `CE6083` "design property not supported by your theme"**
  errors — `theme/` and `themesource/` were missing. Nearly read as a corrupt baseline.
  Exclude only the heavy, non-semantic dirs: `.git`, `.mpr-snapshots`, `widget-src`,
  `.mendix-cache`, `deployment`, `.playwright-cli`, `node_modules`. ~2.7 GB → ~420 MB.
- **The Bash tool's cwd persists between calls.** A `cd $SANDBOX` in one call silently made the
  next call's `rsync ./ $SANDBOX2` copy the *already-probed* sandbox — the control arm came up
  "workflow already exists" and would have read as a bogus result. **Use absolute paths for every
  path in a multi-arm experiment.** Cheap tell: assert the pre-state (`SHOW WORKFLOWS` → expect 1).
- **Always run the negative control.** "New binary works" alone can't distinguish a real fix from a
  sandbox artifact. Reproducing the crash in arm B, same recipe, is what makes it evidence.
- **Pick the gate that matches the project's Mendix version.** Installed SP bundles carry their own
  `mx` at `/Applications/Mendix Studio Pro <ver> Beta.app/Contents/modeler/mx` — often newer than
  anything under `~/.mxcli/mxbuild/`. Gating 11.13 with an 11.12 `mx` proves nothing.

## Why bother instead of snapshot-and-restore

The failure mode here makes the MPR **unloadable by Studio Pro**, and `exec.sh`'s gate does not
roll back a BSON crash (it parses error JSON; a stack trace isn't JSON, so it prints
`✓ Script applied` and keeps the change). A sandbox arm costs one `rsync`; a bad real-model write
costs a recovery. See `mpr-corruption-and-sp-load-errors.md` for the surgical recovery
(`DROP WORKFLOW` via mxcli, which reads models SP's loader rejects).

## Corollary — version-probe before believing any "resolved" verdict

A bug marked resolved is resolved **against a specific binary**. `./mxcli --version` plus
`git -C <repo> rev-parse --short HEAD` and `git merge-base --is-ancestor <fix> HEAD` for each
claimed fix commit takes one call and prevents inheriting someone else's green result. Related:
`tool-output-is-not-ground-truth.md`. Once a defect is confirmed this way, [[bug-submission-checklist]]
covers what else has to be verified before filing it upstream.
