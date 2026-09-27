# exec.sh inline gate-fail auto-restore never restores a v1 (single-file) model

**Source:** marketplace-rnd (152 MB v1 .mpr, no `mprcontents/`). **Status:** unreviewed inbox drop.

## Failure
The gate-fail auto-restore in `project-bin/exec.sh` only restores when `SNAP_UNITS -gt 0`
(counted under `mprcontents/`). On a v1 model the snapshot has none, so it prints
"⚠ Snapshot has no mprcontents/ — refusing to restore from it." and leaves the broken model in
place. `project-bin/restore-mpr.sh` already has a v1 arm (restore the single .mpr file,
~lines 51–60); exec.sh carries an older inline copy of that logic without it.

## Fix
Have exec.sh call `restore-mpr.sh` instead of its inline copy (one restore implementation), or
port the v1 arm. Fixture: a v1 snapshot + failed gate must end with the .mpr byte-identical to
the snapshot.
