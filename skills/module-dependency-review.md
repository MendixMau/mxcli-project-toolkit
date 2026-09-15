# Skill: module-dependency-review — judging how an app's modules lean on each other

**Use when:** writing section 3 of an app dossier (`skills/app-analysis.md`), or when a change
slice touches a module boundary and you need to know what that boundary looks like today.

**Inputs:** `analysis/app-facts/dependencies.json` and `inventory.json` from
`bin/app-facts.sh`. The catalog itself (`.mxcli/catalog.db`) for the drill-downs below.

---

## Why the stock views are not enough

`mxcli graph-report` and the `graph_module_*` views derive a module name by cutting the text
before the first dot. Verified 2026-09-15 on four projects, that invents a `Navigation` module
(from the profile `Navigation.Responsive`), breaks on widget refs whose target has no dot, and
its claim that framework modules are excluded is untrue of the coupling view.
The instrument therefore joins `refs.ModuleName` to `objects.ModuleName`
and classifies each module as own, marketplace or framework from `modules_data.Source`.
When a number in this section disagrees with the graph-report, the join wins; note the
discrepancy under Method.

## What to write

One paragraph of shape, then five tables. Numbers come straight from `dependencies.json`.

1. **Shape sentence.** How many own modules, how many have any edge between them, how many sit
   in a tangle. Example form: "31 own modules; 24 are connected; 9 of them form one tangle
   around the order and customer modules."
2. **Tangles** (`tangles.list`). A tangle is a strongly connected component: every module in it
   can reach every other. Each tangle is ONE finding, `DEP-TANGLE-nn`, listing its modules.
   Do not also list every cycle inside it; the 3-cycle list is evidence for the drill-down,
   not a finding each.
3. **Bidirectional pairs** (`bidirectional_pairs`). A pair whose two modules both sit in one
   tangle gets no id of its own: the tangle finding covers it. `DEP-PAIR-nn` is only for pairs
   outside every tangle. Show both directions with their ref kinds: a pair that is `call` one way
   and `associate` the other is a domain-model split across modules; a pair that is `call`
   both ways is two services that should be one, or need an interface module between them.
4. **Cohesion** (`cohesion`): modules under `MIN_COHESION_PCT` (default 60), each `DEP-COH-nn`.
   Show intra, outbound, inbound. Under 30 with high outbound is usually a facade or an API
   module and is fine once named as such in the disposition. Modules whose `cohesion` is null
   (no internal references at all) go in a separate list with a one-line note, not a finding
   each: they are empty shells or pure data modules.
5. **Hubs.** Own modules with distinct outbound targets above `MAX_FANOUT_MODULES` (count them
   from `edges`), and the top ten `god_nodes`. A god node in a utility module (`Util.SUB_Log`)
   is normal; a god entity with 200 inbound refs is the thing every change will touch, and
   goes in the dossier so the change skill sees it.
6. **Marketplace surface** (`edges_to_marketplace`): which own modules depend on which
   marketplace modules. Context only, no finding id. It becomes a finding in the upgrade
   skill, not here.

## How to judge

| observation | default reading | before you write it, check |
|---|---|---|
| tangle of 2 modules, `associate` both ways | one domain split in two; the association direction crossed | the entities: if both sides own entities that reference each other, a merge or an owner decision is needed |
| tangle of 2, `call` both ways | mutual services | whether one direction is only `SUB_`/utility calls; if so, move those into a shared module and the tangle dissolves |
| tangle of 5+ modules | no layering; changes ripple unpredictably | do NOT propose an untangling plan in the dossier; record it, size it as one slice per pair, and put the order in dispositions |
| cohesion < 30, outbound high, inbound low | orchestration or API module | its name; if it is `Integration_*` or `API_*` that is by design, disposition `accept` |
| cohesion < 30, inbound high | shared kernel or a dumping ground | whether its entities are referenced from many modules (kernel: fine) or its microflows are (dumping ground: finding) |
| god entity in own module | the change hot spot | AccessRuleCount and HasEventHandlers in `entities_data`; an event handler on a god entity is where hidden regressions live |
| dead assets | candidates only | Java code, published REST operations, workflows and page URLs are invisible to the catalog; every dead asset is `manual` |

## Drill-down queries

Run against `.mxcli/catalog.db` when a table row needs a face. All read-only.

```sql
-- what exactly crosses from A to B, by kind and source document
SELECT r.RefKind, r.SourceType, r.SourceName, r.TargetName, count(*) n
FROM refs r JOIN objects o ON o.QualifiedName = r.TargetName
WHERE r.ModuleName = 'A' AND o.ModuleName = 'B'
GROUP BY 1,2,3,4 ORDER BY n DESC LIMIT 40;

-- who calls a god node, by module
SELECT r.ModuleName, r.SourceType, count(*) FROM refs r
WHERE r.TargetName = 'Module.Name' GROUP BY 1,2 ORDER BY 3 DESC;

-- entities of a module and what references them from outside it
SELECT e.QualifiedName, e.EntityType, e.AttributeCount, e.AccessRuleCount, e.HasEventHandlers,
       (SELECT count(*) FROM refs r WHERE r.TargetName = e.QualifiedName AND r.ModuleName <> e.ModuleName) inbound_external
FROM entities_data e WHERE e.ModuleName = 'A' ORDER BY inbound_external DESC;
```

## Verdict for the section

- `fail`: any tangle, bidirectional pair, or module under `MIN_COHESION_PCT` without a
  disposition line in section 8.
- `pass`: none of those, or every one has a decision (`fix`, `accept` with a reason, or
  `later` with a slice or date; `later, undecided` is not a decision).
- `fault`: `counts.own_edges` is 0 on an app with more than three own modules, or
  `scope.own_modules` disagrees with the inventory (an own module named `Atlas_*` is dropped;
  a marketplace module imported without metadata shows as own, so name it in
  `.claude/lint-vendor-modules.txt` and rerun instead of editing the table by hand).

## Not findings

A dependency on `System`, on any marketplace module, or from a page to an entity elsewhere.
A single direction edge, however heavy: that is layering working. A tangle whose modules
are all marketplace: not ours.

## Related

`skills/app-analysis.md` (owner), `skills/existing-app-change.md` (uses the hubs and tangles
to size the regression net), `skills/microflow-loop-antipatterns.md` (the other half of
section 4 in the dossier).
