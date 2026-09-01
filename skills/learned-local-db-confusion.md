# A Mendix project can have two or three genuinely different local databases

**Applies to:** any mxcli project on a machine that runs more than one Mendix project, or
that mixes agent-driven headless work with manual Studio Pro sessions.
**Purpose:** never conclude "the app has no data" from looking at *a* Postgres — identify
which of the possible databases you are actually looking at first. Companion:
`bug-logs/mxcli-bugs.md` BUG-100 (the Compose project-name collision that makes case 2
systematic), `empty-widget-triage.md` (the UI-side symptom this often presents as).

There are at least three distinct database instances a person can be looking at without
realizing it:

1. **This project's Docker Compose Postgres** (container and host port set by the project's
   own `.docker/docker-compose.yml`) — what mxcli/agent seeding and headless exec normally
   write to.
2. **A different project's Docker Postgres** squatting on the port you assumed — classically
   `5432`; the "standard" port is not reserved, and whichever project's compose stack came
   up first on the machine claims it. (With BUG-100 unfixed the collision is worse than a
   port race: the projects share one volume outright.)
3. **Studio Pro's own embedded local-run database** — separate from both, managed by Studio
   Pro per the project's Run configuration, with no connection string in the `.mpr` when it
   is the default. Seeding the Docker DB does nothing to this one.

Found live 2026-08-21 on a WMS conversion project: seeded data existed correctly in that
project's own DB container (a non-default host port), but a plain local check hit a
*different project's* container squatting on 5432 — and separately, Studio Pro's local run
was pointed at its own embedded DB, so the app viewed through Studio Pro showed no seed data
for a second, independent reason.

## Don't try to force everyone onto "the standard port"

Standardizing on 5432 does not fix this — with several project containers running
concurrently, something is always on 5432 first, and the collision just moves to whichever
project loses the race. Unique per-project ports are correct; the fix belongs in *checking*,
not in flattening ports back to one number.

## Check before trusting "empty" or "stale"

Resolve the project's **actual** DB container and host port from its own compose file —
never assume 5432:

```bash
# which container and host port THIS project's stack really uses
docker compose -f <project>/.docker/docker-compose.yml ps
docker compose -f <project>/.docker/docker-compose.yml port db 5432   # or the service's name
# then count rows THERE, not on localhost:5432
psql -h 127.0.0.1 -p <that-port> -U <user> <db> -c '\dt'
# and check what is actually squatting on 5432
docker ps --format '{{.Names}} {{.Ports}}' | grep 5432
```

If the container name on 5432 belongs to a different project, you were reading the wrong
database — everything you concluded from it is void.

## Preferred fix: point Studio Pro at the same Docker Postgres

When a project moves between agent-driven headless work and manual Studio Pro sessions on
the *same* data, point Studio Pro's local run Configuration at the project's own Docker
Postgres host port (App Settings → Configurations → connection settings) instead of leaving
it on the embedded DB. One database, one source of truth. Trade-off: Studio Pro's
convenience-run now depends on the DB container being up.

If you do this, also stop the project's Docker **app** container (not the DB) before running
from Studio Pro — two live Mendix runtimes against one schema at once races on
schema/constant checks and can trip the trial-license concurrent-session cap.
