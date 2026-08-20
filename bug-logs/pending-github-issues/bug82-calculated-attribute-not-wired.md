# Pending GitHub issue — mendixlabs/mxcli

**Status:** drafted, NOT yet filed. File to https://github.com/mendixlabs/mxcli/issues after a
final wording pass.

---

**Title:** `calculated by` attribute wiring is dropped at write time — BSON-verified data loss, not just a runtime no-op

**Body:**

## Summary

`alter entity ... add|modify attribute X: type calculated by Module.Microflow [default V];` is
accepted by `mxcli check --references` (0 errors), executes cleanly against the live `.mpr`
("Added attribute"/"Modified attribute"), and passes native `mx check` (0 errors) — but the
resulting attribute is **never actually wired as calculated in the deployed runtime model**.
Every retrieve of the attribute returns empty/null, never the microflow's return value,
indistinguishable from a plain stored attribute that was never given a value.

This was initially logged as "runtime never computes" (an unclassified behavioral finding) with
one open confound — Mendix requires a calculation microflow to take a parameter of the entity
type, and the original isolated repro's parameter list wasn't recorded, so a modelling error
couldn't be ruled out. That confound has since been **tested and eliminated**: a fresh isolated
repro used a correctly-signed calculation microflow (entity-typed parameter, returns the
attribute's own type), and the clause is still dropped. This reclassifies the finding to a
narrower and stronger claim: **write-path data loss, confirmed at the BSON level**, not merely an
untraced runtime behavior.

## Environment

- mxcli: v0.17.0
- Mendix Studio Pro / mxbuild: 11.12.0

## Steps to reproduce

1. Create a brand-new persistent entity with a brand-new Integer attribute.
2. Mark it `calculated by` a microflow that takes a parameter of the entity's own type and
   unconditionally `return`s a literal (e.g. `42`).
3. Create a row via a microflow call, then read it back via `mx.data.get()` in the browser
   immediately after creation (no caching, no stale DB state possible).
4. **Actual:** the attribute returns `""` (empty), never `42`. A genuinely-wired calculated
   attribute recomputes on every retrieve regardless of stored DB state, so there is no legitimate
   reason for this result other than the calculation link not existing in the compiled model.
5. BSON-level confirmation: decode the domain-model unit for the entity. The attribute is stored
   as `DomainModels$StoredValue` with **no** calculated value type and **no** reference to the
   microflow. `SHOW CALLERS OF <the microflow>` reports zero callers. Both the `ALTER` form and the
   CREATE-time form fail identically — there is no working form.

Independently reproduced on real, already-correct project attributes (multiple, on different
entities, each `calculated by` its own already-correct `GET_` microflow, confirmed correct both by
inspection and by directly invoking the microflow elsewhere) — all returned empty on every
retrieve, `SHOW CALLERS` reporting zero callers post-wiring in every case.

## Expected vs. actual

**Expected:** `calculated by` wiring is recorded in the compiled domain model, and the attribute
recomputes via the microflow on every retrieve.

**Actual:** the calculation link is silently never written. `mxcli check --references`,
`mxcli exec`'s success message, and native `mx check` all report success/0-errors regardless.

## Diagnostic method

Neither `mxcli check --references` nor native `mx check` catch this — both treat the attribute as
valid. `CATALOG.ATTRIBUTES.IsCalculated` is not reliable evidence either way — it reads `0` for
every attribute project-wide, including ones independently proven broken by this report, so the
catalog builder may never populate that column at all. The only reliable check found: create a
row, then read the attribute back via `mx.data.get({xpath, callback})` in a live browser session
and inspect the raw value, or decode the domain-model unit's BSON directly and check for the
calculated-value-type/microflow reference.

## Severity

**High.** Silent data-loss at the model-write layer for a documented, non-deprecated Studio Pro
feature (attribute `Value` = Calculated vs Stored, still current in Studio Pro 11 docs, no
deprecation notice). No error, no warning, at any layer mxcli itself exposes.

## Workaround

Drop `calculated by` entirely; use a plain stored attribute with a literal default, and actively
compute + `change` + `commit` the value at the point(s) where the underlying data changes —
reusing the already-correct computation microflow unchanged, just calling it explicitly instead of
via the (non-functional) calculated-attribute mechanism.

**General rule going forward:** do not trust `mxcli check`, `mxcli exec` success messages, or
native `mx check` as evidence that a `calculated by` attribute wiring took effect. Verify with a
live retrieve (`mx.data.get` in-browser, or an OQL/API round-trip through the actual runtime, or a
direct BSON decode) before relying on a newly-added calculated attribute for anything — UI
conditions, downstream logic, or test assertions. Prefer the active-compute-and-store pattern
above by default until this is confirmed fixed upstream.

## Related

See also the toolkit's own bug log entry `BUG-90` (loop-variable association-path inlining into a
call-microflow parameter) — another case in the same defect family where mxcli's own static checks
pass but native `mx check`/runtime behavior diverges; verify with the native toolchain or live
runtime behavior, not mxcli's own check output, whenever a construct is unusual.
