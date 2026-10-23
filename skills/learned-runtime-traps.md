# Runtime traps — valid models that fail only at runtime, for some roles or some navigation

**Applies to:** any mxcli project.

**Purpose:** rules for constructs that pass every model-side gate (`mxcli check`, `mx check`,
mxbuild) and forward-only journeys, and fail only at runtime under a condition admin-run tests
do not create. Each section is **trigger-only**: `bin/rule-lookup.sh` inlines it into a context
pack when its trigger (`bin/lib/rule-triggers.tsv`) appears in the step, so nobody reads this
file whole.

## Saving in a separate transaction leaves the object "new" in your request

**Trigger:** a page-triggered microflow creates (or receives) an object and saves it only with
`CommunityCommons.commitInSeparateDatabaseTransaction` (or any own-transaction commit).

**Rule:** before the microflow ends, roll the request's copy back with `refresh`, or create the
object inside the separate transaction and never hold it in the request. Never fix it by granting
the role Create on the entity (that lets the browser create those rows), and never with a second
`commit` in the request (untested; the row is already inserted).

```sql
$Run = call microflow Ops.ACT_Job_Start(...);
if $Run != empty then
  rollback $Run refresh;
end if;
```

**Failure it prevents:** the separate transaction commits the row in a new context; the request's
own copy is still new, goes back to the browser and stays in the page's client state. After the
browser **Back** button, a later request carries it, the runtime checks **Create** on the entity for
the sender's role, and a role with read-only access is refused — the whole request fails:
`Attempt to illegally add an object to the state` (HTTP 560 on `/xas/`). Every server-backed widget
on the page fails while the frame still renders. Invisible to `mx check`, unit tests, forward
journeys and admin test users (who have Create).

**Catches it:** a journey with a browser-Back step and a 5xx check, run as the least-privileged role
(#564); the monkey's `backAfterSubmit`. Field report: #565 (mxcli v0.27.0, Mendix 11.14.0).
