**From:** factory-app
**Date:** 2026-09-14
**Kind:** bug
**Field evidence:** bug-log entries in factory-app not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic
**Proposed target:** see per-item notes below

---

## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-01.md] Reproduction script

```mdl
-- BUG-LOCAL-01 — assigning a ReferenceSet (System.User_UserRoles) from a
-- microflow corrupts the BSON stream. Variant A (bare object via CHANGE).
-- Detector: mx check must still LOAD the project afterwards.
create module ZZB;
/

create microflow ZZB.ACT_R01 ()
returns Boolean as $Result
begin
  declare $Result boolean = false;

  retrieve $Role from System.UserRole
    where "Name" = 'User'
    limit 1;

  $Acc = create Administration.Account (
    "Name" = 'zzb_r01_user',
    "Password" = 'ZzB#R01Pass!',
    "Active" = true);

  change $Acc (System.User_UserRoles = $Role);

  commit $Acc with events;

  set $Result = true;
  return $Result;
end;
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-04.md] Reproduction script

```mdl
-- BUG-LOCAL-04 symptom 2 — short-form cross-module nav-through expression.
-- `$W/ZZB.Widget_Category/Label` (no target-entity qualifier) compiles in
-- mxcli but is rejected by the real parser with CE0117.
-- Detector: mx check error list must not contain CE0117.
create module ZZB;
/
create module ZZB2;
/

create persistent entity ZZB2."Category" (
  "Label": String(100)
);
/

create persistent entity ZZB."Widget" (
  "Code": String(100)
);
/

create association ZZB."Widget_Category"
  from ZZB."Widget"
  to ZZB2."Category";
/

create microflow ZZB.ACT_R04 ()
returns String as $Result
begin
  declare $Result string = '';

  retrieve $W from ZZB."Widget" limit 1;

  set $Result = $W/ZZB.Widget_Category/Label;

  return $Result;
end;
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-05.md] Reproduction script

```mdl
-- BUG-LOCAL-05 — `alter settings configuration` corrupts the Settings unit.
-- Deterministic on v0.16.0: reports success, project then fails to load with
-- AggregateException / "Expected '$ID' as the first property".
-- Detector: mx check must still LOAD the project afterwards.
alter settings configuration 'Default'
  DatabaseType = 'PostgreSql',
  DatabaseUrl = 'localhost:5432',
  DatabaseName = 'zzbtest',
  DatabaseUserName = 'zzbuser',
  DatabasePassword = 'zzbpass';
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-07.md] Reproduction script

```mdl
-- BUG-LOCAL-07 — a cross-module association used as a widget datasource makes
-- mxcli write a null DestinationEntityId on the EntityRefStep. mxbuild reports
-- 0 errors; Studio Pro crashes on open with
-- `ArgumentNullException: value at EntityRefStep.set_DestinationEntityId`.
-- Detector: mx check must LOAD, and the page unit must carry a non-null
-- destination entity for the ref step.
create module ZZB;
/
create module ZZB2;
/

create persistent entity ZZB2."Category" (
  "CatLabel": String(100)
);
/

create persistent entity ZZB."Widget" (
  "Code": String(100)
);
/

create association ZZB."Widget_Category"
  from ZZB."Widget"
  to ZZB2."Category";
/

create page ZZB."P_R07" (
  Title: 'R07',
  Layout: Atlas_Core.Atlas_TopBar,
  Params: { $W: ZZB."Widget" }
)
{
  dataview dvWidget (DataSource: $W) {
    datagrid dgCats (DataSource: $currentObject/ZZB.Widget_Category) {
      column CatLabel (Attribute: CatLabel, Caption: 'Label')
    }
  }
}
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-08.md] Reproduction script

```mdl
-- BUG-LOCAL-08 — the OpenAPI importer does not resolve `$ref`. Import reports
-- "109 operations", 0 errors, clean build — but every operation is a shell
-- with no Query clause and `Response: none`.
-- Detector: count "Response: none" in DESCRIBE REST CLIENT read-back.
create module ZZB;
/

create rest client ZZB."MESC01Api" (
  OpenAPI: '<project-root>/source/client scope/API-contract/MES_2.0_C01_Artifact10_OpenAPI_Contract-v1.15.yaml',
  BaseUrl: 'http://localhost:3001/api/mes/core/v1'
);
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-09.md] Reproduction script

```mdl
-- BUG-LOCAL-09 — quoted identifiers are NOT stripped inside an import-mapping
-- body. They are stored literally as `ZZB."Routing"`, which resolves to
-- nothing; mxbuild then reports CE1613 for the entity and every attribute.
-- Detector: mx check error list must not contain CE1613.
create module ZZB;
/

create non-persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create json structure ZZB."JSON_R09"
  snippet $${"routing_code":"RT-PCBA-001","routing_name":"Routing for PCBA line 1"}$$;
/

-- Quoted identifiers inside the body — this is the defect under test.
create import mapping ZZB."IMM_R09"
  with json structure ZZB."JSON_R09"
{
  create ZZB."Routing" {
    "RoutingCode" = routing_code,
    "RoutingName" = routing_name
  }
};
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-10a.md] Reproduction script

```mdl
-- BUG-LOCAL-10a — a `create rest client` operation written with Query: and
-- Response: persists only Method/Path/Timeout. Read-back shows
-- `Response: none` and no Query clause.
-- Detector: DESCRIBE REST CLIENT read-back must show the mapping response,
-- not "Response: none".
create module ZZB;
/

create non-persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create json structure ZZB."JSON_R10"
  snippet $${"routing_code":"RT-PCBA-001","routing_name":"Routing for PCBA line 1"}$$;
/

create import mapping ZZB."IMM_R10"
  with json structure ZZB."JSON_R10"
{
  create ZZB.Routing {
    RoutingCode = routing_code,
    RoutingName = routing_name
  }
};
/

create rest client ZZB."MESSlice" (
  BaseUrl: 'http://localhost:3001/api/mes/core/v1',
  Authentication: none
)
{
  operation "SearchRoutes" {
    Method: get,
    Path: '/routes',
    Query: (
      $page: integer,
      $pageSize: integer
    ),
    Headers: ('X-Tenant-Id' = 'demo-tenant-01'),
    Timeout: 300,
    Response: mapping ZZB."IMM_R10"
  }
};
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-10c.md] Reproduction script

```mdl
-- BUG-LOCAL-10c — `datagrid (DataSource: microflow ...)` parses, exec reports
-- success, and NO datasource is stored. Silent no-op, no error anywhere.
-- Detector: DESCRIBE PAGE read-back must mention the datasource microflow.
create module ZZB;
/

create persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create microflow ZZB."DS_Routes" ()
returns List of ZZB."Routing" as $Routes
begin
  retrieve $Routes from ZZB."Routing";
  return $Routes;
end;
/

create page ZZB."P_R10c" (
  Title: 'R10c',
  Layout: Atlas_Core.Atlas_TopBar
)
{
  datagrid dgRoutes (DataSource: microflow ZZB."DS_Routes") {
    column RoutingCode (Attribute: RoutingCode, Caption: 'Routing Code')
  }
}
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-11.md] Reproduction script

```mdl
-- BUG-LOCAL-11 — mxcli silently attaches `on error rollback` to activities
-- that were written with no error handler at all, converting every runtime
-- failure into a silent one.
-- Detector: DESCRIBE MICROFLOW read-back must NOT contain "on error rollback".
create module ZZB;
/

create microflow ZZB.SUB_Handle (
  "ErrorMessage": String
)
returns Boolean as $Ok
begin
  declare $Ok boolean = true;
  return $Ok;
end;
/

create microflow ZZB.ACT_R11 ()
returns Boolean as $Result
begin
  declare $Result boolean = false;

  -- Written with NO error clause. If read-back shows `on error rollback`,
  -- the tool invented it.
  $Sub = call microflow ZZB.SUB_Handle("ErrorMessage" = 'probe');

  set $Result = true;
  return $Result;
end;
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-13.md] Reproduction scripts

**R13 — fresh `create import mapping`:**

```mdl
create module ZZB;
/

create non-persistent entity ZZB."RouteListItem" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create json structure ZZB."JSON_R13List"
  snippet $${
  "items": [{"routing_code": "R-1", "routing_name": "Widget Route"}]
}$$;
/

create import mapping ZZB."IMM_R13"
  with json structure ZZB."JSON_R13List"
{
  create ZZB.RouteListItem {
    RoutingCode = routing_code,
    RoutingName = routing_name
  }
};
/
```

**R13b — same, but rewritten with `create or modify import mapping`** immediately after the
fresh create (the exact trigger the original bug write-up singled out as the broken case):

```mdl
create import mapping ZZB."IMM_R13"
  with json structure ZZB."JSON_R13List"
{ create ZZB.RouteListItem { RoutingCode = routing_code, RoutingName = routing_name } };
/

create or modify import mapping ZZB."IMM_R13"
  with json structure ZZB."JSON_R13List"
{ create ZZB.RouteListItem { RoutingCode = routing_code, RoutingName = routing_name } };
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-14.md] Reproduction script

```mdl
-- BUG-LOCAL-14 — `create json structure` emits occurrence 0 on every element.
-- Detector: read root minOccurs/maxOccurs out of the .mxunit bytes.
-- Expect root 1..1. mxcli v0.16.0 writes 0..0 (structure maps nothing).
create module ZZB;
/

create json structure ZZB."JSON_SearchRoutes"
  snippet $${"pagination":{"page":1,"pageSize":1,"totalItems":10,"totalPages":10},"items":[{"routing_id":"8ac9a044-65ae-43f6-b838-a05fb4dd8e9e","routing_code":"RT-PCBA-001","routing_name":"Routing for PCBA line 1","row_version":1}]}$$;
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-17.md] Reproduction script

```mdl
-- BUG-LOCAL-17 — an ACTIONBUTTON inside a datagrid customContent column makes
-- the model UNLOADABLE. Not a validation error: mxbuild cannot parse the
-- project at all ("Unable to cast ... DivContainer to ... WidgetObject" at
-- ProjectLoader.LoadProject).
-- Detector: mx check must LOAD the project (grep for "Unable to cast" /
-- "ProjectLoader", which a CE#### grep would miss entirely).
create module ZZB;
/

create persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create microflow ZZB."ACT_Open" (
  "Routing": ZZB."Routing"
)
begin
  log info node 'ZZB' 'open';
end;
/

create page ZZB."P_R17" (
  Title: 'R17',
  Layout: Atlas_Core.Atlas_TopBar
)
{
  datagrid dgRoutes (DataSource: database ZZB."Routing") {
    column RoutingCode (Attribute: RoutingCode, Caption: 'Routing Code')
  }
}
/

alter page ZZB."P_R17" {
  insert after RoutingCode {
    column "Open" (ShowContentAs: customContent) {
      actionbutton btnOpen (
        Caption: 'Open',
        Action: microflow ZZB."ACT_Open"("Routing": $currentObject)
      )
    }
  }
};
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-18.md] Reproduction script

```mdl
-- BUG-LOCAL-18 — `ALTER PAGE ... SET Attribute = X ON textbox` does not
-- retarget the binding, it REMOVES it. Read-back shows the textbox with no
-- Attribute at all.
-- Detector: DESCRIBE PAGE read-back must show txtCode bound to RoutingName.
create module ZZB;
/

create persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create page ZZB."P_R18" (
  Title: 'R18',
  Layout: Atlas_Core.Atlas_TopBar,
  Params: { $R: ZZB."Routing" }
)
{
  dataview dvRouting (DataSource: $R) {
    textbox txtCode (Label: 'Code', Attribute: RoutingCode)
  }
}
/

alter page ZZB."P_R18" {
  set Attribute = RoutingName on txtCode
};
/
```


## [candidate — from bug-logs/bakeoff-2026-07-31/BUG-LOCAL-19.md] Reproduction script

```mdl
-- BUG-LOCAL-19 — a listview microflow datasource lands, but its ARGUMENT is
-- silently discarded. DESCRIBE PAGE shows the datasource present, so read-back
-- cannot detect it; the page unit contains a MicroflowParameterMapping shell
-- with no expression, and the argument attribute name appears nowhere.
-- Detector: grep the page unit bytes for the argument attribute name.
create module ZZB;
/

create persistent entity ZZB."Routing" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/

create microflow ZZB."DS_ByCode" (
  "RouteId": String
)
returns List of ZZB."Routing" as $Routes
begin
  retrieve $Routes from ZZB."Routing";
  return $Routes;
end;
/

create page ZZB."P_R19" (
  Title: 'R19',
  Layout: Atlas_Core.Atlas_TopBar,
  Params: { $R: ZZB."Routing" }
)
{
  dataview dvRouting (DataSource: $R) {
    listview lvItems {
      dynamictext txtLabel (Content: 'row')
    }
  }
}
/

alter page ZZB."P_R19" {
  set DataSource = microflow ZZB."DS_ByCode"("RouteId": $currentObject/RoutingCode) on lvItems
};
/
```

*Note: this script required `MXCLI_ENGINE=legacy` to run on RnD — a listview created with
no `DataSource` at all fails outright on the default modelsdk engine (`ListView source <nil>
not yet supported by the modelsdk engine`). See the engine-selection gotcha below.*


## [candidate — from bug-logs/mxcli-bugs.md] BUG-LOCAL-01: Assigning a ReferenceSet association to System.User/Administration.Account from a microflow corrupts the BSON stream

**Severity:** Critical — corrupts the MPR so both Studio Pro and `mx check`/`docker check` fail to
load the project (`AggregateException` / `StorageLoadException`, "Expected '$ID' as the first
property..." or "Expected '$Type' as the second property..."). Same *error-shape* family as the
toolkit's BUG-18 (invalid `AttributeIdentifier` write), but a different trigger.

**Symptom:** After executing a microflow that assigns `System.User_UserRoles` (a `ReferenceSet`,
many-to-many) to a newly created `Administration.Account`, `mx check`/`docker check` and Studio
Pro itself fail to open the project. The specific corrupted-looking field is **not stable** —
across 3 reproduction attempts it manifested as a broken `Settings` unit, then
`EnableMicroflowReachabilityAnalysis`, then `UrlPrefix` — all in unrelated project-settings units,
not the microflow's own unit. This points to a BSON **stream desync**: once the writer emits a
malformed object for the `ReferenceSet` change, whatever object happens to be serialized next in
the same write batch inherits the corruption, which is why the visible symptom looks unrelated
and shifts between attempts.

**Reproduced with all three of these syntax variants (all fail the same way):**
```mdl
-- Variant A: bare object via CHANGE
change $NewAccount (System.User_UserRoles = $Role);

-- Variant B: list literal via CHANGE — actually a PARSE error, not a load-time corruption
change $NewAccount (System.User_UserRoles = [$Role]);   -- rejected at syntax-check time

-- Variant C: inline at CREATE time
$NewAccount = create Administration.Account (..., System.User_UserRoles = $Role);
```
Variant B is at least caught early (syntax error, no execution) — A and C both execute
"successfully" (no error printed by `mxcli exec`) and corrupt the project silently. **`mxcli
check --references` and `mxcli exec`'s own success message do NOT catch this** — only the real
`mx`/`docker check` binary (or Studio Pro itself) surfaces it, and only on a subsequent load.

**Workaround (used in this project):** Don't assign `ReferenceSet` role membership from a
microflow at all. Use the declarative `create demo user '<name>' password '<pw>' entity
Administration.Account (<Role>);` MDL statement instead — it creates the account and assigns the
role via a different, working code path. This is a full behavioral substitute when the goal is
just "a working test/demo login with a role," not a generic fix for `ReferenceSet` writes from
microflows.

**Not yet tested:** whether `ReferenceSet` associations *other* than `System.User_UserRoles`
(e.g., a custom two custom-entity many-to-many) hit the same bug, or whether it's specific to
`System.User`'s built-in role association.

**Recovery procedure that actually worked:** Reverting just the 1-2 suspected corrupted tracked
`mprcontents/*.mxunit` files via `git checkout` was **not sufficient** — each retry corrupted a
*different* file, and partial reverts left the project in an inconsistent state relative to new
untracked units. What worked: full `git checkout -- App.mpr mprcontents/` + `git clean -fd
mprcontents/` back to the last clean commit, then replay every subsequent statement **one at a
time**, running `./mxcli docker check -p App.mpr --no-update-widgets` (the real `mx` binary,
not `mxcli check`) after each single statement before proceeding to the next.

**Discovered:** 2026-07-06, factory-app project, Mendix 11.12.0 Beta, during Equipment build.

**Retested 2026-07-13 on mxcli v0.16.0 — still reproduces, no change.** Ran the exact Variant A
statement (`change $NewAccount (System.User_UserRoles = $Role);`) inside a disposable scratch
module (`ZZ_Retest16`), through `bin/exec.sh`'s real `mxbuild --target=deploy` gate. Reproduced on
two independent checkouts (`main` and `1146version` branches) with the identical error: `"Change in
has an invalid value '' for property Attribute. The text 'System.User_UserRoles' is not a valid
AttributeIdentifier."` v0.14.0's changelog-claimed "$ID-first BSON ordering fix" does **not** fix
this bug. The workaround (declarative `create demo user` MDL, not microflow role assignment) stays
in effect — no CLAUDE.md rule change.

---


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-27.md] Reproduction script

```mdl
-- BUG-27 — cross-module GRANT EXECUTE ON MICROFLOW triggers CE0148
-- Detector: GRANT EXECUTE where the module role and the microflow live in different modules
create module ZKT27A;
/
create module ZKT27B;
/
create module role ZKT27A."Role1";
/
create microflow ZKT27B."MF_Test" () returns Boolean
begin
	return true;
end
/
grant execute on microflow ZKT27B."MF_Test" to ZKT27A."Role1";
```

(Engalar requires the `{}` body form instead of `begin/end` — same statements otherwise.)


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-28.md] Grammar note (checked before writing the repro, per instructions)

Grepping the RnD source tree (`~/Mendix/mxcli`) for `reset`, `layout`,
`RESET`, or `RESETLAYOUT` in any `.go`/`.g4`/`.md` file returns **zero matches** — the token
`RESET` does not exist in RnD's lexer at all. `RESET LAYOUT` is not a syntax-checker/executor
disagreement in RnD; it is a feature that was never added upstream.

In Engalar's grammar (`mdl/grammar/domains/MDLMicroflow.g4:112`), `RESET LAYOUT` is a real
`microflowOption`, only reachable from `createMicroflowStatement`'s option list (there is no
`ALTER MICROFLOW ... RESET LAYOUT` form — it can only be requested at microflow creation time):

```
microflowOption
    : FOLDER STRING_LITERAL
    | COMMENT STRING_LITERAL
    | RESET LAYOUT
    ;
```

Engalar's own test suite (`mdl/executor/flowbuilder_graph_v2_test.go:315`,
`TestResetLayoutProducesValidCoordinates`) documents a bug that existed and was fixed: a helper
called `resetLayoutGen` used to clear `RelativeMiddlePoint` to `""`, which made Studio Pro
overlap every activity at the origin. The test comment says "`resetLayoutGen` was the bug — it
has been deleted."


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-29.md] Reproduction script

RnD form (`begin`/`end`):
```mdl
-- BUG-29 — double-quoted attribute segment in a nav expression ($Var/"Attr")
-- Detector: mxcli check/exec accepts $Var/"Attr" (quoted attribute segment); mxbuild (mx check)
-- is expected to reject it with CE0117 since attribute segments must stay unquoted.
create module ZKT29;
/
create entity ZKT29."TestEntity" (
	"Attr1": String
);
/
create microflow ZKT29."MF_Test" () returns Boolean
begin
	$Obj = create ZKT29."TestEntity";
	if $Obj/"Attr1" = 'x' then
		return true;
	else
		return false;
	end if;
end
```

Engalar form (`{}` body) is statement-for-statement identical apart from body delimiters.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-30.md] Reproduction script

RnD form (`begin`/`end`), two microflows for direct comparison:
```mdl
-- BUG-30 — currentDeviceType() function-call form accepted by grammar, rejected by mxbuild
-- Detector: mxcli's generic functionCall rule (IDENTIFIER LPAREN args RPAREN) accepts
-- currentDeviceType('Phone') as a made-up function name; the working form is the
-- bracket-percent token [%CurrentDeviceType%]. mxbuild should reject the function-call form
-- with CE0117 ("unknown function") while accepting the token form.
create module ZKT30;
/
create microflow ZKT30."MF_FunctionForm" () returns Boolean
begin
	if currentDeviceType() = 'Phone' then
		return true;
	else
		return false;
	end if;
end
/
create microflow ZKT30."MF_TokenForm" () returns Boolean
begin
	if [%CurrentDeviceType%] = 'Phone' then
		return true;
	else
		return false;
	end if;
end
```
Engalar form: identical, with `{}` bodies instead of `begin`/`end`.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-31.md] Reproduction script

RnD dialect (`begin...end`, `AS $$ ... $$`):

```mdl
-- BUG-31 — Void/boolean-returning JS action called from nanoflow — reported malformed BSON
-- Detector: exec succeeds but check --references / mx check fails with CE0008/CE0109, or project unreadable afterward
create module ZKT31;
/
create javascript action ZKT31.JSA_VoidAction()
as $$
function JSA_VoidAction() {
	// no return
}
$$;
/
create javascript action ZKT31.JSA_BoolAction() returns boolean
as $$
function JSA_BoolAction() {
	return true;
}
$$;
/
create nanoflow ZKT31.NF_CallJSActions()
begin
	call javascript action ZKT31.JSA_VoidAction();
	$Result = call javascript action ZKT31.JSA_BoolAction();
end;
/
```

Engalar dialect (`{ }` bodies, `{ code $$ ... $$ }` for JS action source — Engalar's grammar for
`createJavaScriptActionStatement` differs from RnD's: no `AS $$...$$`, instead a brace block
containing an `IDENTIFIER DOLLAR_STRING` pair, e.g. `code $$ ... $$`):

```mdl
-- BUG-31 (Engalar dialect) — Void/boolean-returning JS action called from nanoflow — reported malformed BSON
create module ZKT31;
/
create javascript action ZKT31.JSA_VoidAction()
{
  code $$
function JSA_VoidAction() {
	// no return
}
$$
}
/
create javascript action ZKT31.JSA_BoolAction() returns boolean
{
  code $$
function JSA_BoolAction() {
	return true;
}
$$
}
/
create nanoflow ZKT31.NF_CallJSActions()
{
  call javascript action ZKT31.JSA_VoidAction();
  $Result = call javascript action ZKT31.JSA_BoolAction();
}
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-32.md] What was actually tested

The MCP-touch precondition could not be exercised. Instead, this retest establishes the baseline:
does a plain `CREATE` of a document via `exec` alone (no MCP involved at all) ever leave an
orphaned `.mxunit` file? On both forks: no. Every `.mxunit` file written to disk during `exec` is
also registered as a row in the project's SQLite `Unit` table (`EmptyTest.mpr` → `Unit` table,
`UnitID` BLOB keyed, GUID stored in .NET mixed-endian byte order / `bytes_le`), and every created
microflow shows up correctly in `SHOW MICROFLOWS IN <module>`.

This rules out "plain CREATE always orphans files" as an explanation, but says nothing about
whether prior MCP activity against the module changes that behavior — that part of BUG-32 remains
unverified and requires a live Studio Pro + MCP session to test properly.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-33.md] Reproduction script

RnD dialect (`begin...end`):

```mdl
-- BUG-33 — Cross-module association traversal, short form vs fully-qualified target-entity path
-- Detector: microflow using $Var/ZKT33A.Assoc_AToB/EntityB/SomeAttr (no module qualifier on target
-- entity) fails to parse/validate, while $Var/ZKT33A.Assoc_AToB/ZKT33B.EntityB/SomeAttr succeeds.
create module ZKT33A;
/
create module ZKT33B;
/
create persistent entity ZKT33A.EntityA (
	Name: string
);
/
create persistent entity ZKT33B.EntityB (
	SomeAttr: string
);
/
create association ZKT33A.Assoc_AToB
from ZKT33A.EntityA to ZKT33B.EntityB
type reference;
/
-- SHORT FORM (no target module qualifier) — this is the one under test
create microflow ZKT33A.ACT_ShortForm($Var: ZKT33A.EntityA)
returns string
begin
	declare $result string = $Var/ZKT33A.Assoc_AToB/EntityB/SomeAttr;
	return $result;
end;
/
-- FULLY-QUALIFIED FORM — control
create microflow ZKT33A.ACT_QualifiedForm($Var: ZKT33A.EntityA)
returns string
begin
	declare $result string = $Var/ZKT33A.Assoc_AToB/ZKT33B.EntityB/SomeAttr;
	return $result;
end;
/
```

Engalar dialect (`{ }` bodies, `declare $x: type = ...`) — same statements, only the microflow
body delimiters and `declare` syntax differ; each microflow was also tested in isolation (own
fresh scratch copy per form) to cleanly attribute which one causes the mxbuild error:

```mdl
create microflow ZKT33A.ACT_ShortForm($Var: ZKT33A.EntityA)
returns string
{
	declare $result: string = $Var/ZKT33A.Assoc_AToB/EntityB/SomeAttr;
	return $result;
}
/
```
```mdl
create microflow ZKT33A.ACT_QualifiedForm($Var: ZKT33A.EntityA)
returns string
{
	declare $result: string = $Var/ZKT33A.Assoc_AToB/ZKT33B.EntityB/SomeAttr;
	return $result;
}
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-34.md] Reproduction script

Not applicable — no MDL script triggers this path. A live repro would require:
1. Studio Pro open with `EmptyTest.mpr` (or equivalent) loaded.
2. `mxcli --mcp` (or direct Studio Pro MCP) bridge connected.
3. A page containing a DataGrid2 widget with an external filter bar.
4. An MCP call to `pg_patch_page` setting the filter bar's attribute-list property to a typed
   `AttributeRef[]` array value.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-35.md] Reproduction script

```mdl
-- BUG-35 -- AutoChangedBy/AutoCreatedDate/AutoChangedDate attribute binding on an entity
-- Detector: CE1613 (or other CE) from mx check / exec / check --references when creating an
-- entity with attributes typed autochangedby / autocreateddate / autochangeddate, using the
-- exact attribute names required by the fixed system members (ChangedBy / CreatedDate / ChangedDate)
create module ZKT35;
/
create persistent entity ZKT35.Widget (
  "Name": String(100),
  "ChangedBy": autochangedby,
  "CreatedDate": autocreateddate,
  "ChangedDate": autochangeddate
);
```

A second variant was also tried, using a mismatched attribute name that does not match the
fixed system member name (e.g. `"ChangedByUser": autochangedby`), to see how each tool
handles the mismatch:

```mdl
create module ZKT35B;
/
create persistent entity ZKT35B.Widget (
  "Name": String(100),
  "ChangedByUser": autochangedby,
  "CreatedOn": autocreateddate,
  "LastTouchedOn": autochangeddate
);
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-36.md] Reproduction script

RnD dialect (BEGIN/END microflow body):

```mdl
-- BUG-36 -- scalar (non-entity) parameter from a page action-button microflow call
-- Detector: after exec, DESCRIBE MICROFLOW / DESCRIBE PAGE and check --references show
-- whether the GreetingText parameter is actually bound to the literal passed by the
-- actionbutton, or left empty/unmapped (only visible at runtime otherwise).
create module ZKT36;
/
create persistent entity ZKT36.Item (
  "Name": String(100)
);
/
create microflow ZKT36.ACT_Greet ($GreetingText: String)
returns Boolean as $Result
begin
  declare $Result Boolean = true;
  return $Result;
end;
/
create page ZKT36.Item_Overview
(
  Title: 'Item Overview',
  Layout: Atlas_Core.Atlas_Default,
  Params: { $Item: ZKT36.Item }
)
{
  DATAVIEW dv1 (DataSource: $Item) {
    TEXTBOX tb1 (Attribute: Name)
    ACTIONBUTTON btnGreet (Caption: 'Greet', Action: MICROFLOW ZKT36.ACT_Greet(GreetingText: 'Hello World'))
  }
};
```

Engalar dialect (identical semantics, `{ }` microflow body — Engalar's grammar has diverged
from BEGIN/END for microflow bodies; its own `mxcli syntax microflow.create` help text is
stale and still documents BEGIN/END, which does not actually parse):

```mdl
create module ZKT36;
/
create persistent entity ZKT36.Item (
  "Name": String(100)
);
/
create microflow ZKT36.ACT_Greet ($GreetingText: String)
returns Boolean as $Result
{
  declare $Result Boolean = true;
  return $Result;
}
/
create page ZKT36.Item_Overview
(
  Title: 'Item Overview',
  Layout: Atlas_Core.Atlas_Default,
  Params: { $Item: ZKT36.Item }
)
{
  DATAVIEW dv1 (DataSource: $Item) {
    TEXTBOX tb1 (Attribute: Name)
    ACTIONBUTTON btnGreet (Caption: 'Greet', Action: MICROFLOW ZKT36.ACT_Greet(GreetingText: 'Hello World'))
  }
};
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-37.md] Reproduction script

```mdl
-- BUG-37 — COMBOBOX in association mode rejected by mxcli despite Studio Pro requiring it
-- Detector: check --references and mx check pass with 0 errors for a COMBOBOX bound to an
-- association (Association: + datasource: + CaptionAttribute:) instead of an enum attribute.
create module ZKT37;
/
create entity ZKT37.Customer ( Name: String );
create entity ZKT37.Order ( Number: String );
create association ZKT37.Order_Customer
  from ZKT37.Order to ZKT37.Customer;
/
create or replace page ZKT37.OrderEdit
( Title: 'Order', Layout: Atlas_Core.Atlas_Default, Params: { $Order: ZKT37.Order } )
{
  dataview dv (datasource: $Order) {
    combobox cmbCustomer (
      label: 'Customer',
      Association: ZKT37.Order_Customer,
      datasource: database ZKT37.Customer,
      CaptionAttribute: Name
    )
  }
}
/
describe page ZKT37.OrderEdit;
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-38.md] Reproduction script

```mdl
-- BUG-38 — DatagridDropdownFilter in association/reference mode uncreatable via MDL
-- Detector: check --references and mx check on a DATAGRID column bound to an association
-- attribute, containing a dropdownfilter, to see whether the filter binds to the associated
-- entity (reference/association mode) or is rejected/misbound.
create module ZKT38;
/
create entity ZKT38.Customer ( Name: String );
create entity ZKT38.Order ( Number: String );
create association ZKT38.Order_Customer
  from ZKT38.Order to ZKT38.Customer;
/
create or replace page ZKT38.OrderList
( Title: 'Orders', Layout: Atlas_Core.Atlas_Default )
{
  datagrid dgOrders (datasource: database ZKT38.Order) {
    column colCustomer (attribute: Order_Customer, caption: 'Customer') {
      dropdownfilter ddfCustomer
    }
  }
}
/
describe page ZKT38.OrderList;
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-39.md] Reproduction script

Two entities (`Category`, `Product`) with a many-to-one association `Product_Category`, and
two microflows: the broken form and the documented workaround.

```mdl
create module ZKT39;
/
create persistent entity ZKT39.Category (
  "Name": String(100)
);
/
create persistent entity ZKT39.Product (
  "Name": String(100)
);
/
create association ZKT39.Product_Category
  from ZKT39.Product to ZKT39.Category
  type Reference
  owner Default;
/
-- BROKEN FORM: association traversal from $RefProduct used directly as the RHS
-- comparand inside the WHERE clause of a RETRIEVE against a different entity.
create microflow ZKT39.ACT_FindSameCategory_Broken ($RefProduct: ZKT39.Product)
returns list of ZKT39.Category as $Categories
begin
  retrieve $Categories from ZKT39.Category
    where Name = $RefProduct/ZKT39.Product_Category/Name;
  return $Categories;
end;
/
-- WORKAROUND: retrieve the target object into a variable first, then filter
-- using that variable's attribute (no traversal expression inside WHERE).
create microflow ZKT39.ACT_FindSameCategory_Workaround ($RefProduct: ZKT39.Product)
returns list of ZKT39.Category as $Categories
begin
  retrieve $TargetCategory from $RefProduct/ZKT39.Product_Category limit 1;
  retrieve $Categories from ZKT39.Category
    where Name = $TargetCategory/Name;
  return $Categories;
end;
```

For isolation, the broken and workaround forms were also tested in separate modules
(`ZKT39B`, `ZKT39W`) on separate scratch copies, to rule out one microflow's error being
misattributed to the other by mxbuild's error report (both activities have the same default
name, "Retrieve list of Category from database").


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-40.md] Reproduction script (RnD dialect, begin...end)

```mdl
create module ZTFC40;
/

create persistent entity ZTFC40.OrderContext (
  Status: string(200)
);
/

create microflow ZTFC40.ACT_Validate ($OrderContext: ZTFC40.OrderContext)
begin
  @position(200,200) return;
end;
/

create page ZTFC40.TaskPage (
  title: 'Task Page',
  layout: Atlas_Core.Atlas_Default,
  params: { $WorkflowUserTask: System.WorkflowUserTask }
) {
  layoutgrid g1 {
    row r1 {
      column c1 (desktopwidth: 12) {
        dynamictext txt1 (content: 'Task Page', rendermode: H2)
      }
    }
  }
}
/

create workflow ZTFC40.OrderApproval
  parameter $WorkflowContext: ZTFC40.OrderContext
  display 'Order Approval'
begin
  call microflow ZTFC40.ACT_Validate;
end workflow;
/

-- The statement under test.
alter workflow ZTFC40.OrderApproval
  insert after ACT_Validate user task ReviewOrder 'Review the order'
    page ZTFC40.TaskPage
    outcomes
      'Approve' { }
      'Reject' { }
  ;
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-41.md] Reproduction script (RnD dialect)

```mdl
create module ZTFC41;
/

create persistent entity ZTFC41.GalleryPart (
  TFCId: string(50),
  PartName: string(100),
  Status: string(50)
);
/

create page ZTFC41.DG2FilterTest (
  title: 'DG2 Filter Test',
  layout: Atlas_Core.Atlas_Default
) {
  layoutgrid g1 {
    row r1 {
      column c1 (desktopwidth: 12) {
        pluggablewidget 'com.mendix.widget.web.datagrid.Datagrid' "dgParts" (
          datasource: database from ZTFC41.GalleryPart sort by TFCId asc,
          pageSize: 25,
          pagination: buttons,
          pagingPosition: both,
          columnsFilterable: true
        ) {
          column "colTFCId" (attribute: "TFCId", caption: 'TFC ID') {
            filter "filterTFCId" {
              textfilter "fTFCId" (attributes: [ZTFC41.GalleryPart.TFCId])
            }
          }
          column "colPartName" (attribute: "PartName", caption: 'Part Name')
          column "colStatus" (attribute: "Status", caption: 'Status') {
            filter "filterStatus" {
              dropdownfilter "fStatus" (attributes: [ZTFC41.GalleryPart.Status])
            }
          }
        }
      }
    }
  }
}
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-42.md] Reproduction script (RnD dialect)

```mdl
create module ZTFC42;
/

create enumeration ZTFC42.Status (
  Open 'Open',
  Closed 'Closed'
);
/

create persistent entity ZTFC42.Item (
  Code: string(50),
  Status: enumeration(ZTFC42.Status)
);
/

create page ZTFC42.ItemDetail (
  params: { $Item: ZTFC42.Item },
  title: 'Item Detail',
  layout: Atlas_Core.PopupLayout
) {
  dataview dv1 (datasource: $Item) {
    textbox tCode (attribute: Code)
  }
};
/

-- Native DATAGRID keyword.
create page ZTFC42.NativeGridTest (
  title: 'Native Grid Test',
  layout: Atlas_Core.Atlas_Default
) {
  datagrid dgNative (
    datasource: database from ZTFC42.Item sort by Code asc,
    Action: show_page ZTFC42.ItemDetail (Item: $currentObject)
  ) {
    column colCode (attribute: Code, caption: 'Code',
      DynamicCellClass: 'if ($currentObject/Status = ZTFC42.Status.Closed) then ''text-danger'' else '''' '
    ) {
      textfilter fCode
    }
    column colStatus (attribute: Status, caption: 'Status') {
      dropdownfilter fStatus
    }
  }
};
/

-- Pluggable DG2 (generic pluggablewidget path) — the actual bug scenario.
create page ZTFC42.PluggableGridTest (
  title: 'Pluggable Grid Test',
  layout: Atlas_Core.Atlas_Default
) {
  layoutgrid g1 {
    row r1 {
      column c1 (desktopwidth: 12) {
        pluggablewidget 'com.mendix.widget.web.datagrid.Datagrid' "dgPlug" (
          datasource: database from ZTFC42.Item sort by Code asc,
          Action: show_page ZTFC42.ItemDetail (Item: $currentObject)
        ) {
          column "colCode" (attribute: "Code", caption: 'Code',
            DynamicCellClass: 'if ($currentObject/Status = ZTFC42.Status.Closed) then ''text-danger'' else '''' '
          ) {
            filter "filterCode" {
              textfilter "fCode" (attributes: [ZTFC42.Item.Code])
            }
          }
          column "colStatus" (attribute: "Status", caption: 'Status') {
            filter "filterStatus" {
              dropdownfilter "fStatus" (attributes: [ZTFC42.Item.Status])
            }
          }
        }
      }
    }
  }
};
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-43.md] Reproduction script

```mdl
-- BUG-43 — ALTER SETTINGS CONSTANT corrupts the Settings unit BSON
-- Detector: after exec, run `mx check` against the .mpr; a corrupted Settings unit
-- fails to load with AggregateException / "Expected '$ID' as the first property..."
create module ZWLS43;
/
create constant ZWLS43.MyConst type string default 'original-value';
/
alter settings constant 'ZWLS43.MyConst' value 'changed-value';
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-44.md] Reproduction script

```mdl
-- BUG-44 — CE0070: validation rule rejected on a non-persistent entity's attribute
-- Detector: mxcli check --references and mx check for CE0070 (or any error) on the
-- validation rule for a NON-PERSISTENT entity, contrasted with the same construct
-- working fine on a PERSISTENT entity.
create module ZWLS44;
/
create non-persistent entity ZWLS44.NpEntity (
    "Name": string(100) not null error 'Name is required'
);
/
create persistent entity ZWLS44.PEntity (
    "Name": string(100) not null error 'Name is required'
);
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-45.md] Reproduction script

RnD dialect (`begin ... end` microflow body):
```mdl
create module ZWLS45;
/
create entity ZWLS45.Item ( "Name": string(100) );
/
create microflow ZWLS45.ACT_LookupById ($GuidText: String)
returns ZWLS45.Item
begin
  retrieve $Found from ZWLS45.Item where [id = $GuidText] limit 1;
  return $Found;
end;
/
```

Engalar dialect (`{ ... }` microflow body, `returns ... as $var`) — Engalar's grammar rejects the RnD `begin/end` form outright with parse errors, so a second script was needed for the same semantic construct:
```mdl
create module ZWLS45;
/
create entity ZWLS45.Item ( "Name": string(100) );
/
create microflow ZWLS45.ACT_LookupById ($GuidText: String)
returns ZWLS45.Item as $Found
{
  retrieve $Found from ZWLS45.Item where [id = $GuidText] limit 1;
  return $Found;
}
```
This microflow-body syntax divergence between the two forks is itself worth flagging (see draft issue #2 below) — it's a portability trap, not the CE0161 bug itself.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-46.md] Reproduction script

```mdl
-- BUG-46 — CE0066 security-hash reconciliation failure after GRANT
-- Detector: create module+entity+role, GRANT full CRUD for the only role that exists
-- (i.e. complete coverage), then mx check. If CE0066 still fires despite complete
-- coverage, that indicates a genuine mxcli-side security-hash bug rather than the
-- normal "incomplete access rules" CE0066.
create module ZIVM46;
/
create persistent entity ZIVM46.Widget (
  Name: string(200) not null
);
/
create module role ZIVM46.User;
/
grant ZIVM46.User on ZIVM46.Widget (create, delete, read *, write *);
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-47.md] Reproduction script (RnD dialect — begin...end microflow body)

```mdl
create module ZIVM47;
/
create persistent entity ZIVM47.Product (
  Code: string(50),
  Name: string(200),
  Price: decimal
);
/
create microflow ZIVM47.M001_ValidateProduct (
  $Product: ZIVM47.Product
)
returns boolean as $IsValid
begin
  declare $IsValid boolean = true;

  if $Product/Code = empty then
    validation feedback $Product/Code message 'Product code is required';
    set $IsValid = false;
  end if;

  if $Product/Name = empty then
    validation feedback $Product/Name message 'Product name is required';
    set $IsValid = false;
  end if;

  return $IsValid;
end;
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-48.md] Reproduction script (RnD dialect, begin...end)

This is RnD's own shipped regression fixture for exactly this symptom —
`mdl-examples/bug-tests/795-datagrid-microflow-datasource-describe.mdl`:

```mdl
create module Issue795;
create module role Issue795.User;

create persistent entity Issue795.Bucket (
  BucketKey: string(200),
  Size: integer
);

create microflow Issue795.GetBuckets ()
returns list of Issue795.Bucket as $items
begin
  retrieve $items from Issue795.Bucket;
  return $items;
end;

create or replace page Issue795.Probe (
  Title: 'Probe',
  Layout: Atlas_Core.Atlas_Default
) {
  datagrid gMicroflow (datasource: microflow Issue795.GetBuckets) {
    column colKey (attribute: BucketKey, caption: 'Key')
  }
  datagrid gDatabase (datasource: database from Issue795.Bucket) {
    column colKey2 (attribute: BucketKey, caption: 'Key')
  }
}

describe page Issue795.Probe;
```

The RnD repo's own comment on this fixture: "Symptom: a DataGrid2 bound to a microflow
described as `datagrid g1 {` with no DataSource at all... Root cause: extractDataGrid2DataSource
looked up a top-level 'Microflow' key, got '', and returned no data source... Fix: every
datasource reader now goes through microflowSourceRef / nanoflowSourceRef."


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-49.md] Reproduction script

```mdl
create module ZIVM49;
/
create module role ZIVM49.User;
/
create persistent entity ZIVM49.Widget (
  Name: string(200)
);
/
create page ZIVM49.Overview (
  title: 'Overview',
  layout: Atlas_Core.Atlas_Default
) {
  datagrid dg1 (datasource: database ZIVM49.Widget) {
    column col1 (attribute: Name, caption: 'Name')
  }
};
/
grant view on page ZIVM49.Overview to ZIVM49.User;
/
show access on page ZIVM49.Overview;
/
-- Now REPLACE the same page and see if the grant survives.
create or replace page ZIVM49.Overview (
  title: 'Overview v2',
  layout: Atlas_Core.Atlas_Default
) {
  datagrid dg1 (datasource: database ZIVM49.Widget) {
    column col1 (attribute: Name, caption: 'Name')
  }
};
/
show access on page ZIVM49.Overview;
/
```


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-50.md] Reproduction script

```mdl
create module ZIVM50B;
/
create persistent entity ZIVM50B.Product (
  Name: string(200),
  IsActive: boolean default true
);
/
create page ZIVM50B.Product_Overview (
  title: 'Products',
  layout: Atlas_Core.Atlas_Default
) {
  datagrid dgProducts (datasource: database ZIVM50B.Product) {
    column Name (attribute: Name, caption: 'Name')
    column colActions (
      attribute: IsActive,
      caption: 'Manage',
      ShowContentAs: customContent,
      Sortable: false
    ) {
      actionbutton btnEdit (
        caption: 'Edit',
        action: none,
        buttonstyle: primary
      )
    }
  }
};
/
describe page ZIVM50B.Product_Overview;
/
-- Attempt 1: 3-level dotted path (grid.column.widget)
alter page ZIVM50B.Product_Overview {
  SET Caption = 'Edit Now' ON dgProducts.colActions.btnEdit
};
/
-- Attempt 2: 2-level path (grid.widget, skipping the column name)
alter page ZIVM50B.Product_Overview {
  SET Caption = 'Edit Now' ON dgProducts.btnEdit
};
/
-- Attempt 3: bare widget name (no grid qualification)
alter page ZIVM50B.Product_Overview {
  SET Caption = 'Edit Now' ON btnEdit
};
/
```

Note: `describe page` shows the column's actual widget name is derived from the attribute
(`colActions` as authored, but confirmed via `DESCRIBE` in an earlier pass that an unqualified
column identifier can get normalized to the attribute short name) — this doesn't change the
outcome below; none of the three addressing schemes reach the nested `actionbutton`.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-51.md] Reproduction scripts

Three contexts were tested for both quoted (`"Module"."Target"(Param: value)`) and unquoted
(`Module.Target(Param: value)`) forms, since the original report's comment
(`mdlsource/05-inventory-pages.mdl:8-9` in inventory-app-main) generalizes to "action/datasource/
snippet bindings":

**1. `show_page` action target (page-to-page navigation with a parameter):**
```mdl
actionbutton btnQuoted (
  caption: 'Quoted',
  action: show_page "ZIVM51Q"."Item_Edit"(Item: $currentObject),
  buttonstyle: primary
)
```

**2. `microflow` action target (button microflow call with a parameter):**
```mdl
actionbutton btnQuoted (
  caption: 'Quoted',
  action: microflow "ZIVM51A"."ACT_TouchItem"(Item: $currentObject),
  buttonstyle: primary
)
```

**3. `microflow` datasource target (DataGrid2 microflow datasource with a parameter):**
```mdl
datagrid dg1 (datasource: microflow "ZIVM51M"."GET_ItemByName"(Name: $Filter))
```

Each was paired with an identical unquoted control on a fresh project copy.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-52.md] Environment note

Could not build a fresh RnD binary from `~/Mendix/mxcli` source
(HEAD `504aec67`, `v0.16.1-dirty`) — `go build` and a downloaded nightly-release
binary were both silently deleted by the macOS environment mid-link/mid-download
(`operation not permitted` / binary vanishes seconds after being written), on every
retry, with `CGO_ENABLED=0`, custom `GOTMPDIR`, and post-build ad-hoc `codesign` all
tried. This looks like an environment-level protection reacting to something in the
dependency tree (mxcli vendors `jpillora/chisel`, a SOCKS/tunnel tool, which is a
common false-positive trigger), not a build error in the mxcli source itself. Used
the already-installed `/usr/local/bin/mxcli` (v0.16.0, 2026-07-12, official release
build, ad-hoc linker-signed and already trusted by the OS) as the RnD binary
instead. Flagging so a maintainer with a clean machine can retest against true
HEAD if the version gap matters.

- RnD used: `/usr/local/bin/mxcli` v0.16.0 (2026-07-12)
- Engalar used: `~/Mendix/engalar-mxcli/bin/mxcli` `26f2866` (2026-07-31)
- mxbuild used: the macOS `mx` bundled inside `/Applications/Mendix Studio Pro 11.12.0 Beta.app` (the Linux ELF binaries mxcli auto-downloads under `~/.mxcli/mxbuild/*/modeler/mx` cannot run natively on macOS — `exec format error` — `mxcli docker check` transparently found and used the Studio Pro copy instead)


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-53.md] Environment note

Same RnD-binary substitution as BUG-52: used `/usr/local/bin/mxcli` v0.16.0
(official release) because building/downloading a fresher RnD binary was blocked
by the macOS environment (see BUG-52.md for detail). Engalar:
`26f2866` (2026-07-31). mxbuild: Studio Pro's bundled `mx` (macOS arm64), reached
via `mxcli docker check`, since the auto-downloaded mxbuild is Linux-only.


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-55a.md] Environment note

Same RnD-binary substitution as BUG-52/53: `/usr/local/bin/mxcli` v0.16.0
(official release) used as RnD because building/downloading a fresher RnD
binary from the `mxcli` source repo was blocked by the macOS environment
(see BUG-52.md). Engalar: `26f2866` (2026-07-31).


## [candidate — from bug-logs/mxcli-retest-2026-08-03/BUG-55b.md] Environment note

Same RnD-binary substitution as the other three bugs in this batch:
`/usr/local/bin/mxcli` v0.16.0 (official release) used as RnD because
building/downloading a fresher RnD binary from the `mxcli` source repo (HEAD
`504aec67`) was blocked by the macOS environment — every `go build` and a
downloaded nightly-release binary were silently removed seconds after being
written (see BUG-52.md for detail). Engalar: `26f2866` (2026-07-31).


## [candidate — from bug-logs/rnd-vs-wengao-bakeoff-2026-07-31.md] Caveat on "Wengao" scope — corrected

Earlier in this audit the local `engalar-mxcli` clone appeared to be a shallow clone with
only 4 commits, which looked inconsistent with the task's framing of "~2000 commits
ahead." That was wrong: it was shallow, not absent-history. Running `git fetch
--unshallow` against `origin/dev` reveals the real history: **3,679 commits**, most
recent `26f2866` (2026-07-27) — same commit tested throughout this audit, confirmed
still current (`git fetch --all` returns nothing new). The repo also has ~60 other
remote branches (`fix/*`, `feat/*`) not explored in this pass. Results below reflect
`dev` @ `26f2866` unless noted otherwise.

Wengao's fork also has a **documentation/parser mismatch**: its own
`mxcli syntax microflow.create` reference shows `BEGIN ... END` as the microflow-body
syntax, but the actual binary rejects `BEGIN` and requires `{ }` blocks (confirmed by
testing the doc's own example verbatim). Its `ALTER PAGE` targeting is also stricter/
different from what `page.alter`'s docs suggest: datagrid columns must be addressed as
`GridWidget.AttributeName` (not the column's own declared widget name), and
`ACTIONBUTTON`/`Action: MICROFLOW` parameter names must be unquoted identifiers. All
Wengao repro scripts below were rewritten and hand-verified against these actual
(not documented) rules before being counted — five bugs (R01, R10c, R11, R17, R19) were
initially miscounted as "fixed" on Wengao purely because the repro failed to parse; they
were corrected and re-run.


## [candidate — from bug-logs/uncentralized-findings-2026-07-31.md] poc-app (1146version + main, deduplicated) — 12

1. Cross-module `grant execute` → CE0148, distinct trigger from existing central BUG-04.
2. `reset layout` — invalid MDL that passes `mxcli check` but fails at exec.
3. Double-quoted attribute paths in nav expressions (`$Obj/"Attr"`) pass `mxcli check` but
   fail CE0117 at mxbuild.
4. `currentDeviceType()` function-call form is accepted by the grammar but rejected by
   mxbuild (CE0117) — must use bracket-percent form `[%CurrentDeviceType%]`.
5. Void/boolean-returning JS actions used in nanoflows write malformed BSON (CE0008/CE0109).
6. `CREATE` of a document in an MCP-touched module leaves a dangling, unregistered
   `.mxunit` file — Studio Pro hangs on open.
7. Cross-module association nav-through expressions require the fully-qualified
   target-entity path (`$Item/Module.Assoc/TargetModule.TargetEntity/Attr`); the short form
   fails.
8. MCP `pg_patch_page` rejects typed `AttributeRef[]` arrays for DataGrid2 external-filter-bar
   widgets (`PROP_NOT_PRIMITIVE`).
9. `AutoChangedBy`/`AutoChangedDate` binding → CE1613.
10. A scalar (non-entity) parameter passed from a page button to a microflow silently fails
    to bind — no error at `exec` or `check` time.
11. COMBOBOX in association mode is rejected by mxcli (internal tag `MDL-WIDGET01`) even
    though Studio Pro requires association mode for this control.
12. `DatagridDropdownFilter` in association/ref mode is uncreatable via MDL; needs MCP
    `pg_patch_page` with a specific `refOptions`/`refEntity`/`Pages$MicroflowSource` shape.
13. XPath filters cannot use an association-traversal expression as the comparand — must
    retrieve the target first, then filter.

(13 listed — #8 above is the one confirmed duplicate between the two poc-app agent reports;
counted once in the total of 12.)

Sources: `MIGRATION-PROGRESS.md`, project-local `bug-logs/mxcli-bugs.md` (BUG-LOCAL-04,
BUG-LOCAL-06), `CLAUDE.md:153-161`.


## [candidate — from bug-logs/upstream-drafts/elk-format-drops-datagrid-child-slots.md] INTERNAL ONLY — local tracking header

> **Filing boundary:** the public issue body is EXACTLY the text between the two markers
> `<<<PUBLIC BODY START>>>` and `<<<PUBLIC BODY END>>>`. Everything outside them is internal and
> must be stripped before `gh issue create`.

- **Repo:** `mendixlabs/mxcli`
- **Status:** unfiled (drafted 2026-08-18)
- **Source:** local defect log ("broader ELK tree-loss" / tracker task 30); guard implemented in
  `tests/e2e/design-audit.js:228-278` (`readCompleteness`), consumed at
  `tests/e2e/design-audit.js:526-545`; rendered rows in `docs/report.json`
  (search `mxcli #891 content-slot guard`); schema handling at
  `docs/verification/report-schema.md:283-284, 379`.
- **Relationship to #891 — this is NOT #891, and the split is deliberate (Gate 3).**
  #891 point 1 is the **MDL renderer** dropping a pluggable-widget content slot: `describe page`
  emits an accordion group with no children, so a round-trip loses the grid. What is drafted here is
  the **ELK renderer** (`--format elk`) dropping datagrid child slots **while the `mdlSource` field
  of the very same response carries them in full**. Different renderer, different fix location,
  different severity (no round-trip data loss here — the MDL is complete). Verified firsthand:
  `./mxcli -p <app>.mpr describe page Administration.Account_Overview` prints the controlbar, the
  column filters and the customContent bodies; `--format elk` on the same page does not.
- **Note for the filer:** cross-reference #891 and #834 in the body but do not merge. Our project has
  no pluggable widget with a content slot, so we have **no** independent reproduction of #891 itself
  and nothing to add to it.

<<<PUBLIC BODY START>>>

**Title:** `describe --format elk` silently drops every datagrid child slot (controlbar, column filters, customContent bodies) while the same response's `mdlSource` carries them — any tool that walks the ELK tree audits a partial page and reports it clean


## [candidate — from bug-logs/upstream-drafts/test-app-skill-assertion-pattern-cannot-fail.md] INTERNAL ONLY — local tracking header

> **Filing boundary:** the public issue body is EXACTLY the text between the two markers
> `<<<PUBLIC BODY START>>>` and `<<<PUBLIC BODY END>>>`. Everything outside them is internal and
> must be stripped before `gh issue create`.

- **Repo:** `mendixlabs/mxcli`
- **Status:** unfiled (drafted 2026-08-18)
- **Source:** `docs/verification/measured-claims.md:11-60` (claim 1, measured 2026-08-18).
  **Re-measured independently for this draft, same day, fresh browser session** — five arms plus
  two negative controls; results below are mine, not a citation of that document.
- **Note for the filer:** this is a **docs-correctness** issue against a bundled skill file, not a
  behaviour bug in mxcli's own code. `playwright-cli` is a third-party binary
  (`@playwright/cli`); mxcli does not control its exit codes. What mxcli controls is that
  `.ai-context/skills/test-app.md` documents a pattern as an assertion when it cannot fail.
  Local edits to the file are a no-op — it is regenerated on every mxcli upgrade, which is exactly
  why this has to go upstream.
- Filed separately from the `networkidle` rationale defect in the same file (see
  `test-app-skill-networkidle-rationale-is-wrong.md`) — see the Gate 3 note there.

<<<PUBLIC BODY START>>>

**Title:** Bundled skill `test-app.md` documents an "Assertion Pattern" that cannot fail: every `playwright-cli eval` exits 0, including on a thrown `Error`


## [candidate — from bug-logs/upstream-drafts/test-app-skill-networkidle-rationale-is-wrong.md] INTERNAL ONLY — local tracking header

> **Filing boundary:** the public issue body is EXACTLY the text between the two markers
> `<<<PUBLIC BODY START>>>` and `<<<PUBLIC BODY END>>>`. Everything outside them is internal and
> must be stripped before `gh issue create`.

- **Repo:** `mendixlabs/mxcli`
- **Status:** unfiled (drafted 2026-08-18)
- **Source:** `docs/verification/measured-claims.md:63-75` (claim 2). The in-house measurement there
  ("`networkidle` fired in 1 ms") was **not** re-measured for this draft, and the page state it was
  taken under (pre- or post-login) is not recorded in that entry. The draft below is therefore built
  on Playwright's own published guidance, which is public and verifiable, and cites the in-house
  observation only as a secondary datapoint with its limits stated. **Do not strengthen that
  sentence when filing.**
- **Note for the filer:** docs-only, low severity, and deliberately kept out of the
  higher-severity `test-app.md` assertion-pattern issue
  (`test-app-skill-assertion-pattern-cannot-fail.md`). Same file, different remedy; bundling a
  one-sentence rewrite with a false-green defect risks either half being lost.
- The advice itself is correct and must survive the fix. Only the reason given for it is wrong.

<<<PUBLIC BODY START>>>

**Title:** Bundled skill `test-app.md`: the stated reason for avoiding `networkidle` ("it never fires") is not correct — keep the rule, fix the rationale


## [candidate — from bug-logs/upstream-drafts/test-mdl-javadoc-file-header-swallows-first-test.md] INTERNAL ONLY — local tracking header

> **Filing boundary:** the public issue body is EXACTLY the text between the two markers
> `<<<PUBLIC BODY START>>>` and `<<<PUBLIC BODY END>>>`. Everything outside them is internal and
> must be stripped before `gh issue create`.

- **Repo:** `mendixlabs/mxcli`
- **Status:** unfiled (drafted 2026-08-18)
- **Source:** local defect log entry "BUG-LOCAL-29" (`bug-logs/mxcli-bugs.md:1672-1730`), originally
  confirmed 2026-08-05. **Independently re-measured 2026-08-18 on v0.17.0** for this draft, with a
  six-arm trigger-boundary probe the original entry did not have.
- **Note for the filer:** likely the same parser as #903 (`extractDocAndBody`, CRLF panic) but a
  different failure — reference #903, do not merge into it. Deliberately does **not** bundle the
  sibling finding "non-equality `@expect` forms are not captured" (local BUG-LOCAL-30): that one's
  severity turns on whether an uncaptured expectation passes vacuously or errors at run time, which
  has never been measured. Unfiled by Gate 5, on purpose.

<<<PUBLIC BODY START>>>

**Title:** `mxcli test`: a javadoc-style (`/** */`) file-header comment silently swallows the first test block — the count is plausible and nothing warns


