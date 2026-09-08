**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-67: CREATE SNIPPET ... (Params: { $X: String }) — a
primitive-typed snippet parameter, documented in mxcli syntax snippet.create's own example, fails
at exec time with "entity not found"` (originally sighted 2026-08-12 on a main build-track
project, Stage 5 Phase 11; retested and confirmed still open 2026-08-31 on v0.20.0 — see
`bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1028 (2026-09-04)
**Suggested labels:** bug, snippet, documentation

---

**Title:** `CREATE SNIPPET ... (Params: { $X: String })` — a primitive-typed snippet parameter,
shown in `mxcli syntax snippet.create`'s own example — fails at `exec` with `entity not found:
String`

**Body:**

## Summary

`mxcli syntax snippet.create` documents a mixed entity/primitive parameter list as valid:

```
CREATE SNIPPET Module.Name
  ( Params: { $P: Module.Entity, $Label: String } )
  { ... }
```

A snippet declared with a primitive-typed param (`String` or lowercase `string`, either case)
passes `mxcli check` (both plain syntax check and `--references`) cleanly, then fails at `mxcli
exec` with:

```
Error: failed to build snippet: failed to resolve entity string: entity not found: string
```

The exec-time snippet-builder unconditionally tries to resolve every param's type name as an
entity reference, regardless of whether it is a primitive keyword — so the tool's own documented
example cannot actually execute.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Originally sighted: 2026-08-12, mxcli (pinned build contemporaneous with the BUG-63–BUG-72
  cluster), Mendix 11.13.0. Reproduced independently since on v0.20.0 (2026-08-31): `Params: { $X:
  String }` still fails at exec with `entity not found: String`.

## Steps to reproduce

```sql
create snippet Test.SNIPPET_Label (
  Params: { $Label: String }
) {
  dynamictext dt (content: $Label)
};
```

```
$ ./mxcli check snippet.mdl -p Test.mpr
All references valid.

$ ./mxcli exec snippet.mdl -p Test.mpr
Error: failed to build snippet: failed to resolve entity string: entity not found: string
```

Identical failure with `String` (capitalized) as with lowercase `string`.

**Scope of the bug — confirmed narrow to `CREATE SNIPPET`:** the equivalent PAGE param with a
primitive type (`params: { $RefID: string }`) works fine on `CREATE PAGE` — pages with exactly
that param shape execute successfully. The defect is specific to the `CREATE SNIPPET` code path,
not primitive param-typing in general.

## Root cause (as far as diagnosed from the outside)

`CREATE SNIPPET ... Params: { $X: Type }` does not special-case primitive type keywords before
attempting to resolve `Type` as an entity reference — unlike `CREATE PAGE` param resolution, which
does distinguish primitives from entity references correctly. There also appears to be a related,
narrower quote-stripping gap in the same code path: `CREATE SNIPPET`'s `Params: { ... }` clause
does not strip quotes from a *qualified entity* type name before resolving it either (e.g.
`{ $Context: "Module"."Entity" }` fails with `entity not found: "Module"."Entity"`, quote
characters included literally in the failed lookup string, while the unquoted form
`{ $Context: Module.Entity }` succeeds immediately) — this quoting gap is likely a distinct,
narrower parser fix from the primitive-type gap, but both live in the same param-resolution code
path.

## Expected vs. actual

**Expected:** `CREATE SNIPPET`'s param resolver recognizes primitive type keywords (`String`,
`Integer`, `Boolean`, `DateTime`, etc.) the same way `CREATE PAGE`'s does, and does not attempt an
entity lookup for them.

**Actual:** every param's type name is unconditionally resolved as an entity reference, so any
primitive-typed snippet param — including the one shown in the tool's own `mxcli syntax
snippet.create` example — fails at exec time with a confusing `entity not found` error that gives
no hint the type was meant to be primitive.

## Severity

**Medium.** Blocks a documented, seemingly-ordinary feature (passing a plain string into a
reusable snippet) with no workaround at the syntax level; the tool's own syntax reference actively
misleads here since it shows an example that cannot execute.

## Workaround

Introduce a small non-persistent "parameter holder" entity (single attribute of the primitive
type needed, e.g. `Common.RefIDHolder` with one `RefID: String` attribute) purely to carry the
value into the snippet as an entity-typed param — the embedding page must create/populate the
holder object before calling the snippet and pass that object in as the snippet param instead of
the raw primitive value. Adds one throwaway non-persistent entity and one extra object-creation
step per call site; no data-loss/security implications since the holder is never persisted.

## Suggested fix

1. Special-case primitive type keywords in `CREATE SNIPPET`'s param-type resolver, matching what
   `CREATE PAGE`'s resolver already does correctly.
2. Separately, strip quotes from a quoted qualified entity type name in the same `Params: { ... }`
   clause, matching page param resolution's existing quote-stripping behavior.
3. Until fixed, correct `mxcli syntax snippet.create`'s own example so it does not show a
   primitive-typed param as valid, since it currently cannot execute.

---

**Status: FILED — https://github.com/mendixlabs/mxcli/issues/1028 (2026-09-04).**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "CREATE SNIPPET
primitive parameter entity not found String" and "snippet primitive parameter String" — no
existing issue found as of 2026-08-31. Several closed snippet-related issues were inspected
(#868 SNIPPETCALL Params-map/CE0115, #680 CREATE JAVA ACTION Enumeration param serialized as
entity ref, #402 ALTER SNIPPET namespace lookup, #291/#295 SNIPPETCALL/PageParameterMapping
corruption) — all are different snippet defects, none address a primitive-typed `CREATE SNIPPET`
param failing entity resolution.
