# mxcli v0.21.0 (2026-09-06): catalog and describe gaps found while building app-analysis, 2026-09-15

Investigation only. No GitHub issues filed yet. Found while building `project-bin/app-facts.sh`
against four local projects (62 to 2,700 microflows) and one 107-module internal app. Structural
facts only; no project content quoted.

Binary: `~/.local/bin/mxcli`, `mxcli version v0.21.0 (2026-09-06T15:33:18Z)`.

## 1. The catalog holds top-level activities only

`activities_data` (and the `activities` view) lists, per microflow, the activities of the outer
flow. Everything inside a `LoopedActivity` body is absent: the nested loops, the commits, the
retrieves, the calls. Verified on one microflow: `mxcli describe` renders two loops (one nested)
and three commits; the catalog has 26 rows for it with exactly one `LoopedActivity` and no row
for anything between `loop ... begin` and `end loop;`.

Consequences:
- Any Starlark rule built on `activities_for()` cannot see loop bodies. A "commit in loop" rule
  is not writable today; a "commit anywhere" rule undercounts.
- `microflows_data.ActivityCount` undercounts for every loop-containing microflow.
- The catalog loop count per microflow is the number of top-level loops, not all loops.

Workaround in the toolkit: describe every loop-containing document and parse the MDL
(`app-facts.sh` step 3). Ask upstream for a `ParentActivityId` or `Depth` column, or a
`loop_body_activities` view.

## 2. `describe` has no type for rules

`mxcli describe microflow M.R` and bare `mxcli describe M.R` both report not found for a
document whose `microflows_data.MicroflowType` is `RULE`. The `describe --help` type list has
microflow, nanoflow, workflow, page, snippet and others, but no `rule`. Rules can contain loops
and do on the large app (2 of 425 loop documents).

Workaround: report them as not describable, not as failures. Ask upstream for `describe rule`.

## 3. `describe microflow` is strict about type; auto-detect is the safe call

Candidates taken from `activities_data` include nanoflows and rules (all three live in
`microflows_data`). `describe microflow <nanoflow>` fails with "microflow not found". Bare
`describe <QualifiedName>` auto-detects microflow vs nanoflow correctly. Not a bug, a trap:
documented here because the first real run lost 11 of 425 documents to it.

## 4. graph-report header claims framework exclusion the coupling view does not apply

`mxcli graph-report` prints a header saying framework modules are excluded, but
`graph_module_coupling` (and `graph_module_dependencies`, `graph_module_cohesion`) derive the
module with `substr(Name, 1, instr(Name, '.') - 1)` and have no filter. Effects seen:
- a phantom module named `Navigation` from `Navigation.Responsive` and similar profile names;
- widget refs whose target has no dot (`WIDGET|IMAGE` style names) produce an empty module;
- `System` and marketplace modules appear in coupling counts.

Workaround: `refs.ModuleName` joined to `objects.ModuleName`, own/marketplace/framework from
`modules_data.Source` and the name `System`. Ask upstream to either drop the header claim or
filter the views, and to use the module column instead of a string split.

## 5. `graph_cycles` is empty where module-level cycles exist

On a project with four mutually dependent module pairs (verified by the join in item 4),
`graph_cycles` had zero rows. The view is asset-level and materialized at build time; whatever it
detects, it is not module cycles. The toolkit computes strongly connected components itself.

## 6. Silent incompleteness after upgrade (reminder, not new)

A catalog built by an older mxcli can lack whole tables (`scheduled_events_data` was missing on
one project) with no error from any command. `build_mode=fast` leaves `refs` and `activities`
empty, also silently. `app-facts.sh` forces `graph-report` (full build) and checks for nine
tables by name before reading anything.
