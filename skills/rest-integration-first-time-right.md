# REST-fed filterable DataGrid in Mendix via mxcli — first time right

**Applies to:** any mxcli project that shows data from a REST API in a page: search/filter bar →
microflow calls the API → import mapping → non-persistent rows → DataGrid. The "Route List /
Route Detail" shape.

**Status:** v2, rewritten 2026-08-22. Every claim below was re-measured on **mxcli v0.18.0 +
Mendix 11.13.0** with a runtime test (`mxcli test`, Docker), not inferred from `DESCRIBE`,
`check --references` or mxbuild. v1 of this skill (2026-07-29) carried two rules that are now
**proven false** — see §0. If you hold a copy of v1, discard it.

---

## 0. What changed since v1 — read this even if you know the old skill

| v1 said | Measured 2026-08-22 on v0.18.0 | Consequence |
|---|---|---|
| **RULE 0 — entity name must equal the JSON element name at every level (`Root`, `Pagination`, `ItemsItem`)** | **False.** `SearchResponse`/`PageInfo`/`Route` mapped to `(Object)`/`pagination`/`items` — not one name matches — and the runtime import returned root + pagination + 2 items. | **Name entities after the domain.** No shared `Root` NPE, no union `ItemsItem`, no `custom name map` gymnastics. The mapping binds by explicit element path; name equality was never a Mendix rule. |
| **mxcli writes JSON structures DEAD (root occurrence `0..0`); run `fix-json-occurrences.sh --fix` before every mapping** | **Fixed since v0.17.0.** v0.17/v0.18 write root `0..1`, array items `0..*`. A fresh, unpatched structure imported correctly. Patching the root to `1..1` changed nothing. | **Retire the patch step.** The fixer script still prints `DEAD` for anything ≠ `1..1` — that verdict is now a false alarm. |
| *(not known)* | **NEW trap — the `import from mapping` activity's range.** Omit the range keyword and mxcli (v0.17 **and** v0.18) writes `ForceSingleOccurrence=1`. On an object-rooted mapping that activity **returns EMPTY, throws nothing, logs nothing** — at `check`, `--references`, mxbuild and runtime. `DESCRIBE` shows it as a trailing `first`. Write **`all`**. | This is the defect the folk-fix "re-select the mapping in Studio Pro" was silently repairing: SP resets the flag to 0. It is also the likeliest cause behind BUG-84 ("array child never populated") and a project's 0-row read-model pages. |

The whole v1 diagnosis chain (naming → occurrences → re-select in SP) was three symptoms of
**one flag on the calling activity**, never on the structure or the mapping.

---

## 1. The pattern, end to end

Five documents, one page. Build in this order; each step has a read-back.

### 1.1 Filter object — one non-persistent entity per search page

```
create non-persistent entity "Mod"."RouteFilter" (
  "RoutingCode": string(50),
  "RoutingType": enumeration("Mod"."ENUM_RoutingType"),
  "LifecycleState": enumeration("Mod"."ENUM_LifecycleState"),
  "PageNo": integer default 1,
  "PageSize": integer default 20,
  "TotalItems": integer default 0,
  "TotalPages": integer default 1
);
```

- Do **not** name it `Filter` — reserved word, the page's datasource call silently breaks.
- Paging counters live here so the page footer can show them without a second call.

### 1.2 Response entities — domain names, parent owns the children

```
create non-persistent entity "Mod"."SearchResponse" ();          -- wrapper, may have 0 attributes
create non-persistent entity "Mod"."PageInfo" ( "Page": integer, "PageSize": integer,
                                                "TotalItems": integer, "TotalPages": integer );
create non-persistent entity "Mod"."Route" ( "RouteId": string(100), "RouteCode": string(50), … );

create association "Mod"."SearchResponse_PageInfo"
  from "Mod"."SearchResponse" to "Mod"."PageInfo" type Reference    owner Both;
create association "Mod"."SearchResponse_Route"
  from "Mod"."SearchResponse" to "Mod"."Route"    type ReferenceSet owner Default;
```

- **Direction matters, names don't.** The wrapper → child direction lets the microflow walk
  *forward* (`$Response/Mod.SearchResponse_Route`). A child → parent association is walked in
  reverse, which on non-persistent objects resolves as a *database query* and returns nothing,
  silently. (Re-confirmed 2026-08-22: with child-owned associations the test could not even
  compile `$Page/TotalItems` — the reverse walk types as a list.)
- A flat `GET /things/{id}` response can map straight onto the real domain entity; the wrapper
  is only for paged/nested responses.
- Reuse the wrapper/PageInfo pair across every paged endpoint in the module — that is the
  "reuse standard mapping entities" you want, and it needs no generic names to work.

### 1.3 JSON structure — from a captured payload, never from the contract

```
create json structure "Mod"."JSON_SearchRoutes"
  snippet $${ "pagination": { "page": 1, "pageSize": 20, "totalItems": 2, "totalPages": 1 },
              "items": [ { "routing_id": "r-1", "route_code": "RT-001", "is_current": true,
                           "effective_from": "2026-01-01T00:00:00", "row_version": 1 } ] }$$;
```

- `curl` the real endpoint and paste the bytes. Contracts lie about types and field names.
- Give every field a **typed, non-null sample** — `null` in the snippet infers Unknown.
- Occurrences are written correctly on v0.17+. No patch step.

### 1.4 Import mapping — explicit paths, raw keys on the right

```
create import mapping "Mod"."IMM_SearchRoutes"
  with json structure "Mod"."JSON_SearchRoutes"
{
  create Mod.SearchResponse {
    create Mod.SearchResponse_PageInfo/Mod.PageInfo = pagination {
      Page = page, PageSize = pageSize, TotalItems = totalItems, TotalPages = totalPages
    },
    create Mod.SearchResponse_Route/Mod.Route = items {
      RouteId = routing_id, RouteCode = route_code, IsCurrent = is_current,
      EffectiveFrom = effective_from, RowVersion = row_version
    }
  }
};
```

- **Left** of `=` is the attribute; **right** is the raw JSON key as the API sends it. Since
  #882 (v0.18.0) either the raw key or Mendix's exposed name (`Routing_id`) resolves — but
  `DESCRIBE` prints the exposed form, so its output is still not a safe paste-back.
- **Unquoted identifiers inside the mapping body.** This inverts the always-quote rule; quotes
  here are stored literally and produce 58× CE1613.
- **Never `create or modify` a mapping that contains an array** — drop, then create.

### 1.5 The search microflow — URL as one string, `all`, explicit error path, log ladder

```
create microflow "Mod"."ACT_Route_Search" ("Filter": "Mod"."RouteFilter")
returns List of "Mod"."Route" as $Routes
begin
  $NoRoutes = create list of Mod."Route";                      -- error-path return, declared FIRST
  declare $CodeParam String = if $Filter/RoutingCode = empty then '' else $Filter/RoutingCode;
  declare $TypeParam String = if $Filter/RoutingType = empty then '' else toString($Filter/RoutingType);
  declare $Url String = @Mod.ApiBaseUrl + '/routes'
      + '?routingCode=' + $CodeParam + '&amp;routingType=' + $TypeParam
      + '&amp;page=' + toString($Filter/PageNo) + '&amp;pageSize=' + toString($Filter/PageSize);
  log info node 'RouteSearch' '[1] url={1}' with ({1} = $Url);

  $Json = rest call get '{1}' with ({1} = $Url)
      header 'Accept' = 'application/json'
      timeout 30 returns String on error continue;
  log info node 'RouteSearch' '[2] json len={1}' with ({1} = toString(length($Json)));

  $Response = import from mapping Mod."IMM_SearchRoutes"($Json) all on error {
    log error node 'RouteSearch' '[3E] mapping THREW type={1} msg={2}'
        with ({1} = $latestError/ErrorType, {2} = $latestError/Message);
    return $NoRoutes;
  };
  if $Response = empty then
    log warning node 'RouteSearch' '[3] mapping returned EMPTY — range flag or dead structure';
    return $NoRoutes;
  end if;

  retrieve $Routes from $Response/Mod."SearchResponse_Route";
  retrieve $Page   from $Response/Mod."SearchResponse_PageInfo";
  $Count = count($Routes);
  log info node 'RouteSearch' '[4] items={1}' with ({1} = toString($Count));
  if $Page != empty then
    change $Filter (TotalItems = $Page/TotalItems, TotalPages = $Page/TotalPages);
  end if;
  return $Routes;
end;
```

Why each line is there:

| Line | Reason |
|---|---|
| `$NoRoutes` first | a custom `on error {}` opens a branch that never reaches the retrieve; it must return something or CE0108 |
| unset enum → `''` | any non-blank value is an exact-match filter server-side; `toString(empty)` poisons the URL |
| one `{1}` for the whole URL | multi-placeholder templates do not substitute — they go out literally |
| `@Mod.ApiBaseUrl` constant | a hard-coded `localhost` is the container under Docker; constant syntax proven |
| `on error continue` on `rest call` | the only handler it accepts; a block is CE6035. An empty body is how failure presents |
| **`all`** on `import from mapping` | **see §0** — omitted = `ForceSingleOccurrence=1` = silent EMPTY |
| `[3]` empty check | distinguishes "threw" from "mapped nothing" — the two must never look alike |
| `$Count = count($Routes)` | bare `$x = count(...)` is the aggregate form; `length()` is for strings |
| counters from `$Page` | `count($Routes)` only sees one page, never the true total |

### 1.6 The page — filter bar above the grid, both inside the filter dataview

```
create page "Mod"."Route_List" (
  Title: 'Routes',
  Layout: Atlas_Core.Atlas_TopBar,
  Params: { $FilterObj: Mod.RouteFilter }
) {
  dataview dvFilter (DataSource: $FilterObj, Class: 'card') {
    layoutgrid filterBar {
      row row1 {
        column col1 (DesktopWidth: AutoFill) { textbox txtCode (Label: 'Routing code', Attribute: RoutingCode) }
        column col2 (DesktopWidth: AutoFill) { combobox cbType (Label: 'Type', Attribute: RoutingType) }
      }
      row row2 {
        column col1 (DesktopWidth: AutoFill) {
          container actions (Class: 'page-actions') {
            actionbutton btnReset  (Caption: 'Reset',
              Action: microflow Mod.ACT_Filter_Reset(FilterObj: $FilterObj))
            actionbutton btnSearch (Caption: 'Search', ButtonStyle: Primary,
              Action: microflow Mod.ACT_Filter_Apply(FilterObj: $FilterObj))
          }
        }
      }
    }
    datagrid dgRoutes (DataSource: MICROFLOW Mod.ACT_Route_Search(Filter: $currentObject)) {
      column RouteCode (Attribute: RouteCode, Caption: 'Code', Sortable: false)
      column Lifecycle (Caption: 'Lifecycle', ShowContentAs: customContent) {
        dynamictext txtBadge (Attribute: LifecycleState, Class: 'badge badge-info')
      }
    }
  }
};
```

- The grid must sit **inside** the dataview that supplies the filter object — a sibling gets
  CE1571 (scope, not a missing argument).
- Put the filter widgets in a `layoutgrid` **outside** the grid, not in the grid's `controlbar`:
  control-bar widgets resolve against the *row* entity and CE1613 on every combobox.
- A DataGrid-2 `textfilter`/`dropdownfilter` filters the rows the datasource already returned.
  For server-side filtering the inputs bind to the filter object, and the API does the work.
- Search/Reset are a **no-op write with `refresh`** — there is no "re-run datasource" action:

```
create microflow "Mod"."ACT_Filter_Apply" ("FilterObj": "Mod"."RouteFilter")
begin
  change $FilterObj (PageNo = 1) refresh;
end;
```

- An opener microflow creates the filter object and shows the page:
  `$F = create Mod.RouteFilter; show page Mod.Route_List(FilterObj: $F);`
- Binding an Action onto an **existing** button needs `alter page … replace btn with {…}`
  in full; `set` cannot bind actions. A datasource can be set after the fact with
  `alter page … { set DataSource = microflow … on dgRoutes }`, but list-view datasource
  **arguments** are dropped by ALTER — write list-view datasources inline at CREATE time.
- Detail page: same shape without the filter object — `dataview (DataSource: $Route)` and
  child `listview`s whose datasource microflows take `$currentObject/RouteId`.

---

## 2. Prove it before the page exists — the 60-second runtime test

Deploy-and-click is the slow oracle. `mxcli test` is the fast one, and it is the only one
that catches the §0 trap. Put this beside the mapping on day one:

```
-- tests/import.test.mdl
/**
 * @test import mapping instantiates root, pagination and the items array
 * @expect $result = 202
 */
$result = call microflow Mod.TEST_ImportCount();
/
```

```
create microflow "Mod"."TEST_ImportCount" () returns Integer as $Out
begin
  declare $Json String = '<the captured payload, 2 items, totalItems 2>';
  $Response = import from mapping Mod."IMM_SearchRoutes"($Json) all;
  if $Response = empty then return -1; end if;
  retrieve $Routes from $Response/Mod."SearchResponse_Route";
  retrieve $Page   from $Response/Mod."SearchResponse_PageInfo";
  $Count = count($Routes);
  declare $Out Integer = $Count * 100;
  if $Page != empty then set $Out = $Out + $Page/TotalItems; end if;
  return $Out;
end;
```

`./mxcli test tests/ -p app.mpr` (Docker; `--local` cannot run on macOS — the cached mxbuild
is the Linux build). The encoding `items×100 + totalItems` makes every failure mode a different
number: `-1` root never instantiated (range flag), `200` pagination branch unbound, `2` items
branch unbound, `202` correct. **`mxcli test` writes a `MxTest` module into the `.mpr` and
restores it afterwards — it is a model write; ask first on a real project.**

---

## 3. Verification checklist — before calling the integration done

```bash
./mxcli -p app.mpr -c "DESCRIBE MICROFLOW Mod.ACT_Route_Search" | grep "import from"
#   must end in "all" — a trailing "first" is the silent-EMPTY flag
./mxcli -p app.mpr -c "DESCRIBE IMPORT MAPPING Mod.IMM_SearchRoutes"   # both branches present?
curl -s "$URL" | python3 -m json.tool | head          # payload still the shape you modelled?
./mxcli test tests/ -p app.mpr                         # 202
```

Then in the running app read `[1]`–`[4]`. Decision tree: `[2]` zero → call failed;
`[2]` large, `[3]` EMPTY → **range flag** (was: dead structure); `[3]` fine, `[4]` zero →
association direction; all fine, page empty → stale deployment or a different variable.

**A clean build is not a working page.** mxbuild is blind to every row in that tree.

---

## 4. Things that still hold from v1

- Capture the real payload before modelling anything; only the bytes tell you a "code" field
  holds an id.
- Deploy before concluding anything — `deployment/model`'s directory mtime is not a deploy
  timestamp.
- One session owns writes to a given `.mpr`.
- mxcli silently attaches `on error rollback` to `import from mapping` and `call microflow`
  when you write no handler (BUG-LOCAL-11); a rollback swallows the exception. Write the
  handler, read it back.
- Fixture facts cost hours: an endpoint that genuinely returns 0 children looks exactly like
  a broken mapping. Know which fixture id has data before you debug.

## Related

- `learned-mdl-preflight.md` — write-mode choice and the STOP table
- `learned-page-patterns.md` — DataGrid-2 filter placement for database-backed grids
- `tool-output-is-not-ground-truth.md` — why the runtime test, not `DESCRIBE`, is the oracle
- `bugs/bug-84-import-mapping-array-child-never-populated.md` — re-run its discriminating test
  with `all` before filing anything
- project `bug-logs/mxcli-bugs.md` — BUG-LOCAL-14 (resolved), BUG-LOCAL-33 (the range flag)
