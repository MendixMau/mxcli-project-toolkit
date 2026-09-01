# Security Is Not a Later Script

**Applies to:** any Mendix module built through mxcli/MDL where security is scripted
separately from the domain model.
**Purpose:** stop the "structurally perfect page nobody can read" failure — entity access,
role mapping and the ready-check discipline that prevents it.

Written after a module build (a WMS demo project, 2026-07-29) shipped a structurally perfect
page that no user could read, and the gap was found by the client-facing user scrolling a
Studio Pro error list — not by the pipeline.

**Companion:** `tool-output-is-not-ground-truth.md`.

---

## What happened

Three separate security omissions, discovered in the wrong order and all at the end:

| # | Omission | Surfaced as |
|---|---|---|
| 1 | No entity access rules on any module entity | 12 × `CE2729 No read access to attribute 'X'` |
| 2 | Module role never mapped into a *user* role | silent — page invisible to non-admins |
| 3 | The source system's own roles never modelled | not surfaced at all; still open at handoff |

Each was fixed reactively, one error list at a time.

## The reasoning error worth remembering

The build script asserted:

> "Non-persistent entities carry no row-level security, so there are no entity access rules
> to grant."

**This is wrong, and it is wrong in an instructive way.** It conflates two distinct things:

| | Non-persistent entities |
|---|---|
| **Row-level** security (XPath constraints) | genuinely absent — there are no rows to constrain |
| **Member-level** access (read/write per attribute) | **required** — without it no widget can bind |

A page bound to a non-persistent entity with no access rules renders perfectly and displays
nothing. Every column is an error.

**A wrong justification is more dangerous than no justification.** An unexplained gap invites
review; a confidently-argued one closes the question. This one sat in a script header, read
plausibly, and stopped anyone — including its author — re-examining it.

## The invisible one

Omission 2 produced no error at all. `grant view on page X to Module.User` succeeds, and the
security matrix looks populated. But if no *user role* contains `Module.User`, nobody holds it.

It was masked because **mxcli auto-adds the new module role to `Administrator`** when it
creates a module. Testing as admin worked. A demo user would have seen an empty menu.

```bash
# the check that catches it
./mxcli -p app.mpr -c "DESCRIBE USER ROLE 'User'" | grep -o "YourModule\.[A-Za-z]*"
```

Compare against sibling modules. If every other custom module appears in that role and yours
doesn't, that is the bug.

---

## THE RULE: entities and their access rules are one unit

Write `grant ... on Entity` in the **same script** as `create entity`. Not a later "security
script", not a "grants pass". mxcli's own reference puts them adjacent for this reason.

Splitting them creates a window where the model is complete and unusable, and nothing in the
pipeline compares the two.

## THE SECOND RULE: a ready-check must mean *built*, not *decided*

The module brief had a full security section — roles, entitlements, a read-only auditor —
and a ready-check reading **"Security model confirmed ✅"**.

It was confirmed as *designed*. None of it was *built*. The brief and the model diverged
silently and no gate compared them, because the gate checked that the design existed.

Any ready-check item about the model must be verified against the model:

```bash
./mxcli -p app.mpr -c "SHOW SECURITY MATRIX IN <Module>"
```

An empty `## Entity Access` section on a module that has pages means security is **not
done**, whatever the brief says.

---

## Pre-flight checklist — before calling any module complete

1. `SHOW SECURITY MATRIX IN <Module>` — is `Entity Access` populated?
2. `DESCRIBE USER ROLE '<role>'` — does a real user role contain the module role?
3. Do the entity grants cover **create** where a microflow or import mapping constructs
   objects? Non-persistent DTOs need `create` on everything a mapping populates.
4. Do editable widgets have **write** on their bound attributes, not just read?
5. Does the built model match the module brief's security table — and if not deliberately,
   is the deviation written down?

## On `create`/`delete` and lint rule CONV006

CONV006 discourages granting create/delete in access rules. It targets **persistent**
entities holding real data. Non-persistent DTOs populated by an import mapping require
`create` on every entity the mapping instantiates — restricting it breaks the mapping and
protects nothing, because there is no stored data and the upstream system revalidates every
call.

Note the deviation explicitly rather than tripping the rule silently.
