# Security Is Not a Later Script

**Applies to:** any Mendix module built through mxcli/MDL where security is scripted
separately from the domain model.
**Purpose:** stop the "perfect page nobody can read" failure: entity access, role mapping, ready-checks.

Written after a module build shipped a structurally perfect page that no user could read; a user
found it in a Studio Pro error list, not the pipeline.

**Companion:** `tool-output-is-not-ground-truth.md`.

---

## What happened

Three security omissions, all found at the end:

| # | Omission | Surfaced as |
|---|---|---|
| 1 | No entity access rules on any module entity | 12 × `CE2729 No read access to attribute 'X'` |
| 2 | Module role never mapped into a *user* role | silent — page invisible to non-admins |
| 3 | The source system's own roles never modelled | not surfaced at all; still open at handoff |

## The reasoning error worth remembering

The build script asserted: "Non-persistent entities carry no row-level security, so there are no
entity access rules to grant."

**This is wrong.** It conflates two things:

| | Non-persistent entities |
|---|---|
| **Row-level** security (XPath constraints) | genuinely absent — there are no rows to constrain |
| **Member-level** access (read/write per attribute) | **required** — without it no widget can bind |

A page bound to a non-persistent entity with no access rules renders and displays nothing.

**A wrong justification is more dangerous than no justification:** an unexplained gap invites
review; a confident one closes the question.

## The invisible one

Omission 2 produced no error at all. `grant view on page X to Module.User` succeeds, and the
security matrix looks populated. But if no *user role* contains `Module.User`, nobody holds it.

It was masked because **mxcli auto-adds the new module role to `Administrator`**: testing as
admin worked, a demo user saw an empty menu.

```bash
# the check that catches it
./mxcli -p app.mpr -c "DESCRIBE USER ROLE 'User'" | grep -o "YourModule\.[A-Za-z]*"
```

If every sibling module appears in that role and yours doesn't, that is the bug.

---

## THE RULE: entities and their access rules are one unit

Write `grant ... on Entity` in the **same script** as `create entity`. Not a later "security
script", not a "grants pass".

Splitting them leaves a model that is complete and unusable, and nothing compares the two.

## THE SECOND RULE: a ready-check must mean *built*, not *decided*

A module brief had a full security section and a ready-check reading **"Security model confirmed"**.
It was confirmed as *designed*, not *built*; no gate compared brief and model.

Any ready-check item about the model must be verified against the model:

```bash
./mxcli -p app.mpr -c "SHOW SECURITY MATRIX IN <Module>"
```

An empty `## Entity Access` section on a module that has pages means security is **not
done**, whatever the brief says.

---

## CE2729 also fires from navigation and page microflows

Field run (mxcli v0.26.0): eight failed gates, grants written for the page's own role only.

| Cause | Write it so |
|---|---|
| `home page Module.Page` on the **default** profile, for a role with no access to that page | Keep the default home page one **every role can view**; add `home page Module.Page for <UserRole>;` per role that needs its own |
| A page data-source microflow granted `execute` only to the designing role | `grant execute on microflow M.DS_X to` **every module role that can reach the page**, in the microflow's script |
| Re-running a partial `create or modify navigation` resets the menu | Give the **final** profile its own last script; never re-run an earlier one |

## Pre-flight checklist — before calling any module complete

1. `SHOW SECURITY MATRIX IN <Module>` — is `Entity Access` populated?
2. `DESCRIBE USER ROLE '<role>'` — does a real user role contain the module role?
3. Do the entity grants cover **create** where a microflow or import mapping constructs
   objects (non-persistent DTOs: everything a mapping populates)?
4. Do editable widgets have **write** on their bound attributes, not just read?
5. Does every role that can reach a page have page access **and** execute on each microflow it calls? (CE2729 above)
6. Does the built model match the module brief's security table — and if not deliberately,
   is the deviation written down?

## On `create`/`delete` and lint rule CONV006

CONV006 discourages granting create/delete in access rules. It targets **persistent**
entities holding real data. Non-persistent DTOs populated by an import mapping require
`create` on every entity the mapping instantiates; restricting it breaks the mapping and
protects nothing, as the upstream system revalidates every call.

Note the deviation explicitly rather than tripping the rule silently.
