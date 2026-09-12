# Linking an mxcli project to the Mendix platform — Team Server and deploy

**Applies to:** any mxcli project built outside Studio Pro that now needs a Mendix platform
identity — a Team Server repository, a cloud environment, a URL other people can open.

**Purpose:** create the app, put an existing model into it without rewriting history, and deploy —
from a headless container, with a PAT. Everything here is field-measured; the traps are the point,
because four of them read as "wrong credentials" or "the app is down" and are neither.

**Field runs:** two. (1) A dashboard-publishing migration project, 2026-09-07 — 144 commits of
model work that had never touched the platform, adopted into a new Team Server app and deployed to
a Free App sandbox. (2) A TOEIC training app, 2026-09-08 — a two-tree repo flattened so Team Server
carries the engineering artefacts beside the model, and the three project-file-name checks in trap
6 tracked down from a Studio Pro that would not open the project. Every status code, exception name
and count quoted below was observed on one of those runs.

**Once the app exists, this file is done.** The recurring per-session operation — which remote is
authoritative, settle-then-push order, and the four checks to run before calling a push blocked —
is `skills/teamserver-alignment.md`, which is routed baseline for exactly that reason.

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

## STOP — six traps, each of which reads as something it is not

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

### 5. `Bad file descriptor` on the first push is the transport, not the pack

A first import is a big push — the whole model, `theme/`, and every widget `.mpk` in one pack. At
around 40 MB it can die like this:

```
remote: fatal: write error: Bad file descriptor
remote: fatal: index-pack abnormal exit
! [remote rejected] ts-export -> main (unpacker error)
```

Every word of that accuses the payload. It is not the payload. On the measured run the largest
blob was a 4.9 MB widget `.mpk` — nothing pathological — and the agent proxy reported
`recentRelayFailures: []`, so nothing upstream saw a cut either. The **same pack, same branch,
same credential** landed on the first retry once the HTTP layer was tuned:

```bash
git -c http.postBuffer=524288000 \
    -c http.version=HTTP/1.1 \
    -c http.lowSpeedLimit=0 \
    -c http.lowSpeedTime=999999 \
    push --no-progress teamserver ts-export:main
```

Buffer the pack instead of streaming it, drop to HTTP/1.1, and disable git's low-speed abort. Set
them on the first push of a new app rather than waiting for the failure.

**Do not respond to this symptom by shrinking the payload, repacking, or force-pushing.** Each of
those looks reasonable given the wording, each costs a rebuild, and none addresses the cause — and
the force-push variant is the one that can leave Team Server in a state nobody wanted.

**Confirm the push against the remote, not against the exit status.** In this failure git has been
seen to report success on the client side while the ref never moved. One `ls-remote` settles it:

```bash
WANT=$(git rev-parse ts-export)
git ls-remote teamserver main | grep -q "$WANT" || echo "not landed - investigate, do NOT force"
```

### 6. The project file's NAME is checked in three places, and fixing one creates the next

Team Server's blank-app template names the model `App.mpr`. If yours is called something else,
Studio Pro will tell you three different things at three different moments, and only the second is
fatal. They are one problem, so fix all three in one commit.

**(a) Git revision metadata — noisy, not fatal.** With the model pushed under its own name, Studio
Pro still asks git about the template's name:

```
pathspec 'App.mpr' did not match any file(s) known to git
```

The project opens, the Changes tab populates, everything works. It is easy to read this as the
cause of a later failure and chase it. It is not.

**(b) `mprcontents/mprname` — fatal.** In the MPR **v2** storage format the model records its own
filename in a plain-text file beside the database:

```
mprcontents/mprname     ->  "App.mpr"   (no trailing newline)
```

`MprStorageManager.EnsureThatTheExistingMprContentsReferToThisMprFile(String mprFilePath)` compares
that string to the name on disk and **refuses to load** on a mismatch:

```
Mendix.Modeler.Storage.StorageMprNameDiscrepancyException
```

This is the trap inside the trap: renaming the `.mpr` in git to silence (a) *creates* (b). Nothing
else in `mprcontents/` mentions the name, and the fourth column of the SQLite `_MetaData` table is
**not** a hash of the filename — ten candidate encodings were tested and none matched, so do not
go looking for one.

Write it with plumbing so a running app is never disturbed:

```bash
BLOB=$(printf 'App.mpr' | git hash-object -w --stdin)   # no trailing newline
export GIT_INDEX_FILE=$(mktemp -u)
git read-tree <parent>
git update-index --add --cacheinfo 100644,$BLOB,mprcontents/mprname
NEW=$(git commit-tree "$(git write-tree)" -p <parent> -m "Point mprname at App.mpr")
unset GIT_INDEX_FILE
```

**(c) `refs/notes/mx_metadata` — silently wrong.** Studio Pro reads the model version from a git
note, not from the `.mpr`. A commit with **no** note makes it fall back to the newest note in the
ref — which on a fresh app is the template's. On the field run an 11.13.0 model was pushed with no
note and 11.13 refused it, insisting the project was "on 11.14", because 11.14.0 was what the
template's note said.

```bash
git notes --ref=mx_metadata add -f -m \
  '{"BranchName":"main","ModelerVersion":"11.13.0","ModelChanges":[],"RelatedStories":[],"isWebModelerCommit":false}' HEAD
git push teamserver refs/notes/mx_metadata:refs/notes/mx_metadata   # notes are NOT pushed by default
```

Read the version out of the model rather than trusting the dialog that just lied to you:

```bash
python3 -c "import sqlite3;print(list(sqlite3.connect('App.mpr').execute('select * from _MetaData')))"
# (2, '11.13.0', '11.13.0', '{SHA256}...')   -> storage format 2, ModelerVersion 11.13.0
```

**The check:** before any push, assert (a) and (b) from the tree and write (c) from the `.mpr`.

```bash
[ -f App.mpr ] || exit 1
[ "$(cat mprcontents/mprname)" = "App.mpr" ] || exit 1
```

---

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

**The username is the literal string `pat`, and it is case-sensitive.** The password is the PAT.

`PAT` in uppercase returns exactly the same `401` as a wrong credential, so a sweep of candidate
usernames that happens to try the uppercase form concludes the token is bad and stops one keystroke
from the answer. That is how a field run lost a day. Measured against
`https://git.api.mendix.com/<AppID>.git/info/refs?service=git-receive-pack`:

| username | result |
|---|---|
| `pat` | **200** |
| the owning account's email | **200** |
| `PAT`, `token`, `oauth2`, `mx`, `apikey`, empty | `401` |
| a non-owning address on the same account | `401` |

Standardise on `pat`: it does not depend on which of an account's addresses owns the app. Use
`service=git-receive-pack`, not `git-upload-pack` — a `200` on upload-pack only proves fetch.

The endpoint challenges with `www-authenticate: Basic realm="Git Service"`, so it is **Basic auth
only**; `Authorization: MxToken …` and `Bearer …` both `401`. It is not app-specific — two
unrelated apps on the same account behave identically.

```bash
git -c credential.helper='!f(){ echo "username=pat"; echo "password=$MX_PAT"; }; f' \
    push teamserver ...
```

### 3. Put an existing model in — without rewriting history

**Rule for a NEW project — one repository, model at the root, from the first commit.** Team
Server expects the Mendix project at the repository root, and Studio Pro ignores any extra
directory beside it. So put `docs/`, `mdlsource/`, `project-tests/`, `architecture/` and the rest
*next to* the `.mpr`, make Team Server the origin the day the app is created, and mirror to
GitHub if you want a second remote. There is then nothing to sync, no subtree, no
"which repo is authoritative" question, and the person who clones the Team Server repo finds
the tests and the decisions where they expect them. The field run that produced everything
below started two-tree (`app/` under an engineering root) because the app had no platform
identity for its first 144 commits; the owner's verdict on discovering that the Team Server
clone held none of the artefacts was "*let's do that from the start next time*". Do.
`bin/init-project.sh` scaffolds beside whatever `.mpr` it finds — point it at the root.

**Everything from here to the end of this step is the retrofit path** for a project that
already grew up two-tree. **Team Server expects the Mendix project at the repository ROOT.** Verify by looking at the
template repo the platform just created: it holds `App.mpr`, `mprcontents/`, `theme/`,
`javasource/` all top-level.

If your repo is two-tree (model under `app/`, engineering artefacts at root) you have two options,
and the earlier advice here — "do not flatten" — was too strong. Measure before choosing.

**Flatten** when Team Server should carry the whole engineering repo, so that `docs/`,
`architecture/`, `design/`, `analysis/`, `mdlsource/` and the tests sit beside the model. Studio
Pro ignores folders it does not recognise, so they cost it nothing, and there is then one tree with
two remotes and nothing that can drift.

**Subtree** when Team Server should carry the model alone — a client who gets the model but not
your analysis, or a repo whose non-model half is too large to hand to every Studio Pro user.

The number that decides it is the collision count, not an opinion:

```bash
comm -12 <(git ls-files app/ | sed 's|^app/||' | sort) <(git ls-files | grep -v '^app/' | sort)
```

On the second field run (2026-09-08, a TOEIC training app) that printed **218** paths — and **211
of them were byte-identical**, leaving 7 real merges: the two `CLAUDE.md`/`AGENTS.md` pairs, a
`.gitignore`, and two Starlark lint rules where the root copies were simply the newer toolkit
versions. A day's worth of "the trees have diverged" turned out to be one afternoon's work.
Compare content, not names:

```bash
for f in $(comm -12 ...); do
  git diff --quiet HEAD:app/$f HEAD:$f 2>/dev/null || echo "REAL MERGE: $f"
done
```

Three things that bite during a flatten, none of them obvious:

- **A symlink and a directory with the same name are a type clash, not a merge.** `app/design`
  was a symlink to the root `design/`; `git mv` cannot resolve that. Drop the symlink.
- **Anchored `.gitignore` rules stop matching and nothing warns you.** `/app/.claude/loop/stack.env`
  matches nothing once `app/` is gone, so a file that had been safely ignored for months becomes
  stageable — and it held the credentials. Re-anchor every `/app/...` rule and prove it:
  `git check-ignore -v .claude/loop/stack.env` must name a line.
- **The `.mpr` basename changes** if you also rename to `App.mpr` — see trap 6, and check whatever
  your tooling derives from it.

Prove the flatten before committing it: `mxcli -p App.mpr -c "SHOW MODULES"` and `mxcli lint`. On
the measured run the project's own scripts needed no path changes at all, because they discover the
`.mpr` by walking up rather than assuming a location — worth checking in yours.

Then adopt with the single-tree form below.

**Taking the subtree route instead:**

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

**Single-tree repo — the same adoption without the subtree.** When the `.mpr` already sits at
the repo root there is nothing to split; a side branch and an `ours` merge give the same
fast-forward property, and the GitHub history is never touched:

```bash
git checkout -b ts-align main
git merge --allow-unrelated-histories -X ours --no-edit teamserver/main
git diff --stat main ts-align                          # MUST print nothing: the tree is still ours
git merge-base --is-ancestor teamserver/main ts-align  # MUST pass: fast-forward
git push teamserver ts-align:main                      # no --force; then confirm with ls-remote (trap 5)
```

`-X ours` resolves every overlapping path to your history; the template commit survives as a
second parent. The `git diff --stat` line is the gate — output means the merge changed the model
and must not be pushed. (Checking out `ts-align` swaps the working tree like any checkout; on a
machine running the app, use the plumbing form above instead.)

**Before choosing between this and a force-push at all, count what the remote holds that you do
not.** Divergence alone (`git log` in both directions) says the histories differ; the decisive
number is how many *paths* exist on Team Server and nowhere locally:

```bash
comm -23 <(git ls-tree -r --name-only teamserver/main | sort) \
         <(git ls-tree -r --name-only main | sort) | wc -l
```

`0` means a force-push would destroy commit objects only, never file content — measured on a
fresh `Initial app upload.` (1042 paths, all also present locally). It is still not a licence to
force: the merge above costs one commit and destroys nothing.

**Every later sync repeats the merge.** `subtree split` is deterministic — the previous split tip
is an ancestor of the next — but its output never contains the merge commits made on your side, so
a bare `git subtree push` is rejected as non-fast-forward. Re-merge each time.

### 4. Deploy

**It depends entirely on whether the app is a Free App**, and that is not a detail — it decides
whether any of this is automatable at all.

### On a licensed app

First time: a human, in the portal (see trap 3). After that: create a pipeline once in the portal,
then `POST /apps/{appId}/runs` with its `pipelineId` on every change.

### On a Free App — none of it is automatable, and the limits go further than deploy

Mendix's Free App limitations table is explicit, and it invalidates the obvious plan:

| | Free App | Licensed |
|---|---|---|
| **Deployment** | **Studio Pro only** | Studio Pro, portal, **or API** |
| Runtime settings | **Not available** | Configurable in the portal |
| Constants | Studio Pro only | Environment variables in the portal |
| Metrics, alerts, **log levels** | **Not available** | Available |
| **Historic app logs** | **Not available — live logs only** | Available |
| Scheduled events | **Not run** | Run |
| Start/stop manually | Not available | Available in the portal |

The Deploy API agrees: *"Only Retrieve apps, Create Free App environment, and Retrieve app API
calls are supported for Free Apps."* So on a Free App there is **no pipeline to trigger**, and a
`pipelineId` you cannot obtain is not a blocker you can engineer around.

**Three consequences worth knowing before you promise any of them:**

1. **Deploy stays manual.** Do not plan CI around a Free App sandbox.
2. **OpenTelemetry is impossible there.** OTel is a *runtime* feature — it is driven by `OTEL_*`
   environment variables and runtime settings, and works anywhere the runtime runs (local, Docker,
   licensed cloud, self-hosted). It is **not** Studio-Pro-dependent. But a Free App forbids exactly
   the thing it needs: runtime settings and env-var constants. The blocker is the plan, not the
   tooling.
3. **Logging demos are thin.** Live logs only, no history, no log-level control, no API. A local
   run is a far stronger logging demo: full log stream, `mxcli log list` / `mxcli log set` to change
   levels on a running app, Prometheus at `:8090/prometheus`, and real OTel traces via
   `mxcli run --local --trace-otlp <collector>`.

**A caution about tracing that costs a demo if you learn it live:** unfiltered per-activity tracing
is roughly **10× slower** and produces ~110k spans for one busy transaction, which is why default
span filters ship enabled — it is a flow-*shape* mode, not a timing mode. And the console exporter
drops start/end timestamps and parent span IDs, so flame charts require exporting to a real
collector, not the console.

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

Decide once and write it down. The answer differs by route. (A project laid out per step 3's
day-one rule — one repository, model at the root — never faces the question; it exists only
because of the subtree or the flatten.)

**Subtree:** the two repos hold different trees, so they are not mirrors and cannot be. Team Server
is authoritative for the **model**, the engineering repo for everything that is not the Mendix
project, and `app/` is a synced working copy.

**Flattened:** one tree, two remotes, and the two must never diverge. Push **Team Server first**,
the code host second — Team Server is the copy Studio Pro and the deployed environment read, so if
only one of the two can be updated it must be that one. Confirm each push with `ls-remote` before
starting the next.

Either way: two remotes on one branch is fine; two remotes that diverge is how a split-model `.mpr`
gets corrupted.

The route also decides what every Studio Pro user clones. On the 2026-09-08 run the flattened tree
was ~196 MB, of which 74 MB was a directory of `.mpr` backups and 47 MB was end-to-end test video —
neither needed to open or build the model. Push it if you want it beside the model; just know the
number, because a first push of a fifth that size is what trap 5 is about.
