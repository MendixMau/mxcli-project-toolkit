# REST integration in Mendix via mxcli — getting it right the first time

**Applies to:** any mxcli project modelling a REST-backed entity.

**Read before modelling any REST-backed entity.** Not after the grid comes up empty.

Derived from one 6-hour debugging session on a production REST integration (2026-07-29) in which
**four independent defects all presented as the same symptom: an empty grid.** Nothing in the
tooling distinguished them. This file exists so the next integration costs 40 minutes.

---

## RULE 0 — NAMING IS KING

**Every entity name must exactly match the JSON structure's element name, at every object
level, including the root.**

```
schema element      entity must be called
─────────────────   ─────────────────────
Root                Root
Pagination          Pagination
ItemsItem           ItemsItem
NodesItem           NodesItem
EdgesItem           EdgesItem
```

Nothing else in this file matters if this is wrong. A mismatch does not warn, does not error,
and does not fail the build. The mapping simply instantiates nothing and every downstream panel
reads empty.

**Proven directly (2026-07-29).** `IMM_PagedThings` returned `(empty)` in the debugger while
its root targeted `ThingsResponse`. Renaming that entity to `Root` — changing nothing
else — made it work. Same for the child: `ItemsItem`, not `ThingVersion`.

**Do not argue with this from a counterexample.** `IMM_SearchThings` works with semantic names
(`SearchThingsResponse` / `Things`) because it was authored in Studio Pro. Every mapping
mxcli generated with mismatched names came back empty. I used that one counterexample to
dismiss the rule three separate times while the user kept fixing it by hand. If a mapping
returns nothing, check the names first, not last.

### The consequence you must design around

Every paged endpoint yields the same element names — `Root`, `Pagination`, `ItemsItem` — and
entity names are unique per module. So two paged endpoints in one module cannot each own a
`Root`.

**Share the entities.** One `Root`, one `Pagination`, one `ItemsItem` carrying the union of
fields, reused by every mapping in the module:

```
Root ──Root_ItemsItem──▶ ItemsItem   (versions AND effectivities)
     ──Root_NodesItem──▶ NodesItem
     ──Root_EdgesItem──▶ EdgesItem
```

These are non-persistent read-model DTOs, not domain entities. A shared, slightly baggy shape is
the correct trade — fields the calling endpoint doesn't supply are simply empty.

The alternatives are worse: per-structure Custom Name edits (manual, per structure, in Studio
Pro) or one module per endpoint (sprawl).

### And the association must match too

Naming alone isn't enough — the shape has to be right as well:

```
Root_ItemsItem     Root → ItemsItem     ReferenceSet   ✅ parent owns, loader walks forward
ChildNode_Root      ChildNode → Root    Reference      ❌ backwards, and singular
```

A reverse walk on a non-persistent entity resolves as a database query against objects that were
never in a database. Silently zero.

---

## Why this is hard — the thing to internalise

Every layer in this stack swallows its own failure:

| layer | how it fails | what you see |
|---|---|---|
| JSON structure with root occurrence 0 | produces no root object | empty list |
| Import mapping with unbound elements | matches nothing | empty list |
| Reverse association retrieve (non-persistent) | resolves as a DB query | empty list |
| `rest call` throwing | caught by `on error` | empty list |
| Stale deployment | runs yesterday's model | empty list |

`mxcli check`, `--references` and `mxbuild` pass on **all** of them. So does the page render.
You get one symptom for five causes and no signal to separate them. That is the whole problem —
it is not that REST is hard.

There is also a hidden layer people don't model: it is **not** API ↔ entity. It is
**API → JSON structure → import mapping → entity**. The structure is invisible in most views,
has no error state, and mxcli generates it broken.

---

## The protocol

### 1. Capture the real payload before modelling anything

```bash
curl -s "$BASE/endpoint" -H "$AUTH" | python3 -m json.tool > analysis/json-samples/JSON_Thing.json
```

One file per structure, named after it. **Never model from the contract or an OpenAPI spec.**
Real example: the contract implied a field held a code; the payload showed it holds an id
(`"node-003-1"` vs `"N01"`). Only the bytes tell you.

Check every endpoint — sibling endpoints often share an identical `{pagination, items}` wrapper and
differ only inside `items`. That similarity is how the wrong payload ends up in the right
structure, and it is invisible until you read the item fields.

### 2. Name entity attributes from the payload — this is the biggest lever

Mendix derives each schema element's **Custom Name** from the JSON key by capitalising the first
character and keeping underscores:

| JSON key | Custom Name | your attribute should be |
|---|---|---|
| `routing_id` | `Routing_id` | `Routing_id` |
| `product_family_code` | `Product_family_code` | `Product_family_code` |
| `is_current` | `Is_current` | `Is_current` |

**Why it matters more than it looks.** Studio Pro's *Map automatically* pairs elements to
attributes by **exact name**. With PascalCase entities it matches nothing, silently skips every
field, and — if no entity is assigned — invents a parallel entity that *does* match, leaving you
with two competing domain models.

With matching names you never hand-bind anything. That is the real prize: **hand-made bindings
reference schema elements by internal ID, so regenerating a structure destroys every one of them**
and leaves red dots plus CE0272. Name-matched mappings survive regeneration and re-bind in one
click.

Do **not** rename UI-only entities (filter holders, view models). They are not mapping targets;
keep them in your normal convention.

It is not a mechanical PascalCase→snake_case transform. Derive from the payload:
`ThingVersionId` → `Thing_version_id`, not `Version_id`.

### 2b. Map automatically matches OBJECT names too — align Custom Names, not entities

**Attribute names alone are not enough.** *Map automatically* matches at two levels:

| schema element | must equal |
|---|---|
| the **ROOT** object (always named `Root`) | the **entity** name — so the entity must literally be called `Root` |
| every nested object (`Pagination`, `ItemsItem`, `NodesItem`, `EdgesItem`) | the **entity** name |
| the **leaf** elements (`routing_version_id`…) | the **attribute** names |

**The root counts.** This is the part that is easy to miss and cost hours: a mapping whose root
object targets a semantically-named entity (`ThingsResponse`) instantiates NOTHING under
auto-map, and the failure is invisible — `check --references` is green, the build stops reporting
it, and the only symptom is the response variable reading `(empty)` in the debugger.

**Consequence — one auto-mappable structure of a given shape per module.** Every paged endpoint
of that shape produces `Root` / `Pagination` / `ItemsItem`. Entity names are unique within a
module, so the second structure of that shape cannot have its entities named the same way. Either
give each structure distinct Custom Names by hand, or accept that only one mapping per module is
auto-mappable and hand-bind the rest.

If the object name does not match any entity, Studio Pro **creates a new one** — plus a new
association — rather than reusing yours. Observed 2026-07-29: one module accumulated
`Item`, `ItemItems`, `Items`, `ItemsItem` and `Pagination`, all duplicating hand-built
`Thing` / `ThingVersion` / `SearchThingsPagination`, from repeated auto-map runs. Each new
mapping silently retargeted to the duplicate, so the microflow's retrieve over the ORIGINAL
association returned nothing while the mapping "worked".

**Fix direction: change the schema's Custom Name, not the entity.** Mendix derives `ItemsItem`
from the array's item object, but the **Custom Name column is editable**. Set it to your entity's
name (`ThingVersion`) and auto-map binds to the real entity.

Custom Name is a display/binding label with no other meaning. An entity name carries domain
meaning and is referenced across pages, microflows and access rules. Bend the one that costs
nothing.

Do this for the object element BEFORE running Map automatically the first time — retargeting an
already-generated mapping means deleting the duplicate entity and its association too.

### 3. JSON structures: mxcli writes them DEAD (BUG-LOCAL-14)

Every structure mxcli creates gets **root occurrence `0..0`**. A root at 0 never instantiates, so
the mapping yields nothing — with no error at any gate. Measured, not recalled:

```
create json structure Mod."JSON_Test" snippet $${...}$$;
  →  ROOT occ = 0..0
```

Two ways out:

**(a) Regenerate in Studio Pro** — paste the snippet, Refresh, confirm the top `(Object)` row reads
Occurrence `1`. Reliable, manual, does not scale.

**(b) Patch the bytes** — `bin/fix-json-occurrences.sh --fix`. The value is two integers; rewriting
them does not change file length. mxcli stores them as **int32 (BSON 0x10)**, Studio Pro as
**int64 (0x12)** — handle both. Verified: model loads, `DESCRIBE` round-trips, independent reader
confirms `1..1`. *Not yet verified: Studio Pro acceptance and runtime mapping output — confirm both
before trusting it on a real build.*

Either way, **verify occurrence the moment the structure exists**, before building anything on it.

Multi-array structures (e.g. `nodes` + `edges`) must be checked on **every** array. A half-fixed
structure gives you a populated first list and a permanently empty second one, which looks exactly
like a mapping bug and is not.

### 4. Instrument the microflow while writing it, not when it breaks

Five log lines. They are what make the failure modes distinguishable:

```
[1] URL        <the fully assembled url>
[2] json len   <bytes returned>
[3] mapped     <count after import mapping>
[3E] THREW     <error type + message — INSIDE the on-error handler>
[4] retrieved  <count after the association retrieve>
```

Read them as a decision tree:

- `[2]` zero → the call failed. Check `[3E]`.
- `[2]` large, `[3]` zero → **dead structure or unbound mapping.**
- `[3]` fine, `[4]` zero → **wrong association direction.**
- All fine, page empty → **stale deployment**, or the page reads a different variable.

The single log line `[2] json length=4774` is what finally cracked the reference session. Add it
first, not last.

### 5. Never let `on error` return empty silently

```
$Response = import from mapping Mod.IMM_Thing($Json) on error {
  log error node 'X' '[3E] mapping THREW — type=' + $latestError/ErrorType
      + ' message=' + $latestError/Message;
  return $NoResults;
};
```

An empty list meaning "it threw" and an empty list meaning "no matches" must never look the same.

Also: mxcli **silently attaches `on error rollback`** to `import from mapping` and `call microflow`
when you don't specify one (BUG-LOCAL-11). Always write the handler explicitly, and read it back.

### 6. Response wrapper owns the children; always retrieve forward

Create a wrapper entity per response and give it a **reference set** to the child entity, owned by
the parent:

```
create association Mod."ThingResponse_Thing"
  from Mod."ThingResponse" to Mod."Thing" [reference_set] owner both;
```

Then `retrieve $Items from $Response/Mod.ThingResponse_Thing` walks **forward**.

A reverse walk (child → parent) on **non-persistent** entities is resolved by a database query and
silently returns nothing, because non-persistent objects are not in the database. This defect cost
a full day twice in the same module.

### 7. Deploy before concluding anything

A saved model is not a running model. After any structure or mapping edit, **redeploy** before
judging the result. And note: `deployment/model`'s *directory* mtime does not move when files
inside are overwritten — it is not a deploy timestamp. Check a file inside it.

### 8. One session owns writes

Two agents (or two terminals) writing one `.mpr` means measurements go stale between reading and
reasoning. Symptoms appear and vanish for no visible cause.

---

## Verification checklist — before calling an integration done

```bash
./bin/fix-json-occurrences.sh                  # every structure root 1..1?
./mxcli -p app.mpr -c "DESCRIBE IMPORT MAPPING Mod.IMM_X"   # bindings present?
curl -s "$URL" | python3 -m json.tool | head   # payload still the shape you modelled?
```

Then in the running app, read the `[1]`–`[4]` log lines. **A clean build is not a working page** —
mxbuild is blind to every failure in the table at the top of this file.

---

## Related

- `learned-mdl-preflight.md` — write-mode choice and the STOP table
- `tool-output-is-not-ground-truth.md` — why read-back is mandatory
- project `bug-logs/mxcli-bugs.md` — BUG-LOCAL-09 … -17
