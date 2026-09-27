# exec.sh gate logs "mxbuild clean" when mxbuild refused the model (version mismatch)

**Source:** marketplace-rnd (Mendix 11.12.2, v1 single-file .mpr), review
`docs/reviews/2026-09-26-exec-gate-missed-ce0066.md` in that project (full fix diff there).
**Status:** unreviewed inbox drop. **Impact: high** — 29 of 29 Mac exec rows 09-24..09-26 were
false greens; a real CE0066 shipped through the gate.

## Failure
`find_mxbuild` picked the newest cached mxbuild (11.14.0 Beta), not the model's version. That
mxbuild refuses an 11.12.2 model with **exit 3**, writes the reason to the errors file's
`errors[]`, and leaves `problems[]` empty. The gate counts Error-severity `problems[]`, gets 0,
sets `GATE_STATE="pass"` and never looks at `MXBUILD_EXIT`. BUILD-LOG: "mxbuild clean".

Bad output (verbatim shape): exec row `gate: pass (0 errors)` while mxbuild exit=3.

## Fix (from the review's diff)
1. `_common.sh` `mxtk_mxbuild_error_count`: if count is 0 **and** exit != 0 → print `?`, return 1.
2. `exec.sh` (and `verify-model.sh`): non-zero exit with 0 problems → `unverified`, never `pass`.
3. `find_mxbuild`: prefer the cached mxbuild matching the model's `_MetaData._ProductVersion`
   (new helper `mxtk_model_version`); only fall back to newest with a loud warning.
4. `find_java`: on mac use `/usr/libexec/java_home -v 21` (platform-guarded).
Stopgap the project used: `.claude/toolkit.env` with `MXBUILD_PATH` and `JAVA_HOME`.

## Rule to state in a skill
An exit code and a problem count are two facts; "0 problems" from a tool that exited non-zero
means *not measured*, not *clean* (fits `skills/tool-output-is-not-ground-truth.md`).
