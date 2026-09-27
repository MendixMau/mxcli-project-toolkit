# `mx check` on a scratch copy of only the .mpr: 1337 errors that mask the real ones

**Source:** marketplace-rnd probes 2026-09-27. **Status:** unreviewed inbox drop.

## Failure
Copying just `Marketplace.mpr` to a scratch dir and running `mx check` gave 1337 errors
(1165 CE0462, 101 CE0535, 70 CE6083) and hit CE6478 "Too many errors" — so a real CE0066 from
the probe would have been invisible behind the cap.

## Recipe
Copy (real copies, not symlinks) `widgets/ theme/ themesource/ javasource/ userlib/ resources/
vendorlib/ javascriptsource/` alongside the .mpr. Baseline became 0 errors; then probe.
State the baseline count before reading any probe result (denominator rule).
Home: a "probe on a scratch copy" recipe in `skills/learned-detection-gaps.md` or
`retesting-learned-rules.md`.
