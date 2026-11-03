# Build log — auto-appended by bin/exec.sh

One line per exec against the model. Written by the script, not by hand, so it is
true even when someone forgets. Read this before assuming the model builds.

`gate` is the mxbuild verdict, and it is never blank:
`pass` verified clean · `fail` verified broken · `skipped` mxbuild/java missing ·
`unverified` errors file unparseable, or mxbuild exited non-zero without checking the
model (wrong version, JDK) · `not-run` the gate was never reached.
Only `pass` means anything looked at the model. A zero exit does not.

| when (ISO-8601 local) | script | gate | result | detail |
|---|---|---|---|---|
| 2026-10-21T05:41:52+0000 | `test.mdl` | pass | ✅ applied | mxbuild clean (no errors file written); lint unchanged vs baseline · change: logic · retry after infra exit · mxbuild log: .mpr-snapshots/.mxbuild-logs/20261021-054151-30003.log · steps: guards 0s check 0s snapshot 0s baseline 1s exec 0s gate 2s lint 1s |
