# Linking an mxcli project to the Mendix platform — Team Server and deploy

**Applies to:** any mxcli project built outside Studio Pro that now needs a Mendix platform
identity — a Team Server repository, a cloud environment, a URL other people can open.

**Purpose:** create the app, put an existing model into it without rewriting history, and deploy —
from a headless container, with a PAT. Everything here is field-measured; the traps are the point,
because four of them read as "wrong credentials" or "the app is down" and are neither.

**Field run:** a dashboard-publishing migration project, 2026-09-07. 144 commits of model work
that had never touched the platform, adopted into a new Team Server app and deployed to a Free App
sandbox. Every status code quoted below was observed on that run.

---

## Before anything: what a PAT can and cannot do

Create the token at `https://user-settings.mendix.com`. Scopes you will actually need:

| scope | for |
|---|---|
| `mx:app:create` | creating the app |
| `mx:modelrepository:repo:read` / `:write` | Team Server git |
| `mx:pipelines:read` / `:write` | **deploying** — see the routing trap below |
| `mx:deployment:read` / `:write` | Deploy API reads |

Store it outside any git repo (`~/Mendix/.env`, `MX_PAT=…`). Never echo it, never put it in a
remote URL, never let it reach `.git/config`.

---

## STOP — four traps, each of which reads as something it is not

Read these before debugging anything. Each cost real time on the field run, and each produces a
symptom that points at the wrong cause.

### 1. `403` from the Platform SDK is not a scope problem — Node ignores `HTTPS_PROXY`

The SDK returns `403 Forbidden` on **every** call from a proxied container. `curl` with the same
token against the same endpoint returns `200`. Node does not read `HTTPS_PROXY`, so the SDK dials
out directly and is refused at the network edge before the request is ever made.

```bash
NODE_USE_ENV_PROXY=1 node create-app.js     # Node >= 22.21
```

Believing the 403 costs you a re-minted PAT and an afternoon. The tell: try the same endpoint with
`curl`; if `curl` succeeds, it was never authentication.

### 2. The Deploy API cannot deploy from a PAT. The Pipelines API can.

This is the single most expensive thing in this document.

| API | host | PAT? | deploys? |
|---|---|---|---|
| Deploy API v4 | `deploy.mendix.com/api/v4` | ✅ | **no** — read-only; lists apps and environments, `404` on every sub-resource (deployments, packages, backups, snapshots, deploy, transport, status, metrics — all eight tried) |
| Deploy API v1 | `deploy.mendix.com/api/1` | ❌ `400 INVALID_CREDENTIALS` | yes, but only with a legacy `Mendix-ApiKey` |
| **Pipelines API** | `pipeline-portal.home.mendix.com/api/v1` | ✅ | **yes** |

The API with "deploy" in its name, which every search result points at, is the one that cannot do
it. Spec: `https://docs.mendix.com/openapi-spec/pipelines.yaml`.

```
POST /apps/{appId}/runs      {"pipelineId": "<uuid>"}   scope mx:pipelines:write
GET  /apps/{appId}/runs/{runId}/status                  scope mx:pipelines:read
```

**`startRun` runs a pipeline that already exists.** There is no endpoint to create one, and none
to *list* them (`/apps/{id}/pipelines` → `404`), so the `pipelineId` must be read out of the portal
UI once and stored beside the app ID. The residual human step is one pipeline setup, not one click
per deploy.

**The measurement that settles "wrong credential" vs "wrong URL"** — worth more than the table:

> `405 Method not allowed 'GET'` means routing resolved **before** auth: the path exists and your
> credential passed. `401`/`403` means the credential failed. `400 INVALID_CREDENTIALS` means the
> auth *scheme* is not recognised at all.
>
> On the field run, `POST .../runs` with a deliberately-zeros UUID returned **`404`, not `401`** —
> which is how we learned the PAT authenticated fine and only the pipeline was missing.

### 3. A first cloud environment cannot be created from any API

An app created through the Projects API has a repository and **no deployment target**.
`GET /api/v4/apps/<id>/environments` returns `404 Application not found` until someone deploys once
from the Developer Portal. `POST /api/v4/apps` → `405`. Plan for one human action here.

### 4. Chromium cannot reach external hosts through an agent proxy

If you test the deployed app with Playwright and get `net::ERR_CONNECTION_RESET` while `curl`
returns `200` on the same URL in the same second, it is not the app. Check the proxy's own status
endpoint: `ws_closed_mid_exchange`, "tunnel closed (code 1006) after 6s". Browser-style persistent
connections do not survive the relay — the same failure appears for unrelated hosts, which is how
you know it is not your app. Passing an explicit `proxy:` to `chromium.launch()` does not fix it.

Assert over HTTP instead. You can still prove a great deal (see "Smoke-test what you deployed").

---

## The sequence

### 1. Create the app

`mendixplatformsdk` `createNewApp` → `POST /rest/projectservice/v1/projects`. Repository type
defaults to `git`. Then `GET /v1/repositories/<appId>/info` returns the clone URL.

Reachable hosts on this path: `projectservice.mendix.com`, `repository.api.mendix.com`,
`git.api.mendix.com`, `deploy.mendix.com`. **`api.mendix.com` is NOT one of them** — an egress
allowlist built around that name will not help. `model.api.mendix.com` is needed only for
SDK-driven model edits, which this path does not use.

### 2. Authenticate git

**The username is the literal string `pat`.** An email address is rejected with
`remote: Invalid username or password` — which reads like a bad token and is not.

```bash
git -c credential.helper='!f(){ echo "username=pat"; echo "password=$MX_PAT"; }; f' \
    push teamserver ...
```

### 3. Put an existing model in — without rewriting history

**Team Server expects the Mendix project at the repository ROOT.** Verify by looking at the
template repo the platform just created: it holds `App.mpr`, `mprcontents/`, `theme/`,
`javasource/` all top-level.

If your repo is two-tree (model under `app/`, engineering artefacts at root), do **not** flatten
it. On the field run that collided: root and `app/` both carried `CLAUDE.md`, `AGENTS.md`,
`.claude/` and `.ai-context/` with *different content*, on top of 112 `app/` references across 50
tracked files. Use a subtree, and accept that the two repositories hold different trees by design.

```bash
git subtree split --prefix=app -b ts-export
```

Then make the template commit an **ancestor** so the push is a fast-forward and nothing is
force-pushed. Use plumbing rather than `git merge -s ours`: checking out the export branch swaps
every file in the working tree and will disturb a running app.

```bash
TSMAIN=$(git rev-parse teamserver/main)
TREE=$(git rev-parse ts-export^{tree})
NEW=$(git commit-tree "$TREE" -p "$(git rev-parse ts-export)" -p "$TSMAIN" -m "Adopt model")
git branch -f ts-export "$NEW"

git merge-base --is-ancestor "$TSMAIN" ts-export      # MUST pass: fast-forward
[ "$(git rev-parse ts-export^{tree})" = "$TREE" ]     # MUST pass: our tree, unchanged
```

Both assertions must hold **before** pushing, and `git push --dry-run` must show `a..b` with **no
`+`** (a `+` is a forced update). Never force-push Team Server.

**Every later sync repeats the merge.** `subtree split` is deterministic — the previous split tip
is an ancestor of the next — but its output never contains the merge commits made on your side, so
a bare `git subtree push` is rejected as non-fast-forward. Re-merge each time.

### 4. Deploy

First time: a human, in the portal. After that: create a pipeline once, then `POST /apps/{appId}/runs`.

---

## Smoke-test what you deployed

A deploy that returns success is not a deploy that works, and on the field run the deployed build
was **one commit behind** what had been pushed — invisible without checking.

Assert over HTTP (trap 4 rules out a browser). What this proves, in order of value:

1. **The stylesheet is your design system, not the blank template's.** This is the load-bearing
   check: a template deploy passes "is it up" and "is it Mendix" identically. Count *project-specific*
   class names and state the denominator — `5/5 present in 620KB of CSS`.
2. **Specific fixes are present**, each paired with a discrimination control where one exists: assert
   the corrected rule is there **and** the superseded one is gone. Without the second half a
   substring match reports success against the very rule you replaced.
3. **Which build is live.** Any string that differs between builds is a free version fingerprint —
   on the field run, a host-allowlist constant in the login page identified the deployed commit
   with no deploy-API access at all.

Record what you *cannot* assert (sign-in, runtime behaviour, the database) as BLOCKED with its
cause, in the same output. A smoke test that quietly omits them reads as full coverage.

---

## Which repository is authoritative

Decide once and write it down. With a subtree the two repos hold different trees, so they are not
mirrors and cannot be: Team Server is authoritative for the **model**, the engineering repo is
authoritative for everything that is not the Mendix project, and `app/` is a synced working copy.
Two remotes on one branch is fine; two remotes that diverge is how a split-model `.mpr` gets
corrupted.
