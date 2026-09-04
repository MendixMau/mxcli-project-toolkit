**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-100` (2026-08-14, two projects on one machine; mechanism matches observed symptoms, fix confirmed to resolve them)
**Status:** NOT YET FILED
**Suggested labels:** bug, docker, data-loss
**Duplicate check:** searched `COMPOSE_PROJECT_NAME` 2026-09-03 — nothing.

---

**Title:** `mxcli docker init` writes compose files into `.docker/` without `COMPOSE_PROJECT_NAME`, so every mxcli project on a machine resolves to Compose project `docker` and shares containers and one Postgres volume

**Body:**

## Summary

Compose derives its project name from the containing directory when `COMPOSE_PROJECT_NAME` is unset. Every mxcli project names that directory `.docker`, so every project on the machine is Compose project `docker`: identical container names (`docker-mendix-1`, `docker-db-1`), one shared named volume (`docker_postgres-data`), one default network. Starting project B's stack tears down project A's containers as stale, and B's schema sync runs against A's data.

## Symptoms (none look like a naming collision)

- App container "replaced" mid-session with a different app's domain model
- A previously green e2e suite failing basic persistence assertions
- Containers gone from `docker ps` without being stopped
- Sidecars started with `--network container:<id>` silently orphaned

## Diagnosis

```bash
docker ps -a --format '{{.Names}}: {{.Label "com.docker.compose.project.working_dir"}}'
# a docker-mendix-1 whose working_dir points at a DIFFERENT project's .docker = this bug
docker volume ls   # one docker_postgres-data doing double duty confirms it
```

## Workaround

`COMPOSE_PROJECT_NAME=<slug>` in `<project>/.docker/.env`, then tear down and redeploy. Note `compose down` after the change resolves to the new name and will not see the old containers; and the rename creates a new empty volume, so dump first if the data matters.

## Suggested fix

`mxcli docker init` sets `COMPOSE_PROJECT_NAME` at scaffold time, derived from the `.mpr` filename (or prompted). This is a template gap, not a per-project judgment call.
