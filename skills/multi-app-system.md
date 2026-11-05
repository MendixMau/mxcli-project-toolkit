# Multi-App System — one register, one writer per app, security across apps

**Applies to:** any mxcli project that is one of **two or more Mendix apps** built as one system —
apps that call each other, share a module or a login, or are built by parallel agent sessions.
**Purpose:** the four things a single app's `PROJECT.md` cannot hold: who owns which app, which
contracts exist and how far each got, which assets are shared, and which decisions bind more than
one app. Plus the session and security rules that keep N apps from breaking each other.

**Not this skill:**

| For | Read |
|---|---|
| Whether to split at all (single vs multi-app) | `architecture-blueprint.md` → "A. Single-app vs multi-app" |
| Cutting one monolith into apps | `decompose-app.md` |
| Designing one REST contract and its test ladder | `rest-between-mendix-apps.md` |
| One OData/REST seam: keys, machine role, external entities | `mendix-service-seam.md` |
| Releasing a change that crosses apps or a shared module | `multi-app-release.md` |
| Where the system register lives, if the company has a private tier | `company-brain.md` |

---

## When this fires

- A second Mendix app joins the system — before its first script.
- A decision (an IdP, a contract, a shared module version, a persona list) binds more than one app.
- More than one agent session is building apps of the same system at the same time.

---

## 1. One system register

Write **one** `SYSTEM.md` in the company brain (`company-brain.md`) or in a small system repo —
**never inside one app's repo**, where that app's session would own it. It has four tables:

| Table | Columns | Status values |
|---|---|---|
| **Apps** | app, repo, owner (person or session), Mendix version, port, `PROJECT.md` path | — |
| **Contracts** | id, publisher, consumer(s), path + version, status, evidence | `spec` · `mock` · `built` · `verified` |
| **Shared assets** | module / design system / seed / persona list, owner app, version per app | — |
| **Cross-app decisions** | id (`SYS-D<n>`), decision, apps affected, status | `CONFIRMED` · `ASSUMED` |

Rules:

1. **Contract status is earned, one step at a time.** `spec` = an OpenAPI/`$metadata` file is in the
   publisher's repo. `mock` = a consumer builds against a fixture of it. `built` = the publisher
   serves it (grep the publisher's model for the path, do not take the table's word). `verified` =
   rung 4 of the ladder in `rest-between-mendix-apps.md` §3 ran against the live publisher.
   *Failure it prevents:* a consumer ran its journey green against a mock for days while a search
   of the publisher's model found no reference to that API at all; the next app added three more
   contracts to a pair that had never closed its first loop. Rule: no new contract between two
   apps while one of theirs sits at `mock` with no publisher date.
2. **Every cross-app decision is mirrored.** Each affected app's `PROJECT.md` gets a pointer row in
   its Decisions table — `| 3 | SYS-D4: IdP = central OIDC, groups → roles (see SYSTEM.md) |
   CONFIRMED | mirrored |`. The gate reads `PROJECT.md`; the register is where the decision is
   *made*. A decision in `SYSTEM.md` with no mirror row is invisible to the app's gate.
3. **Every app is in the register before its first script**, and in the company brain's
   `projects.tsv` if one exists. *Failure:* a three-app system's `projects.tsv` listed one app; the
   other two existed only in chat and a hand-written map.
4. **A shared asset has one owner app.** "Read by both, owned by neither" is how two apps ended up
   holding private copies of the same seed rows. No owner = no change until one is named.
5. **List, don't remember.** Fill the Contracts table from each app's own model (published and
   consumed services — `./mxcli show odataservices`, `show odataclients`, the published/consumed
   REST lists; probe `./mxcli --help` for the names on your binary), not from the plan. As of
   mxcli v0.28 no command joins one app's consumer to another app's publisher, so the join is this
   table.

---

## 2. Session ownership — one writer per `.mpr`

`agent-roles.md`'s rule (only the main session mutates the `.mpr`) lifted to the system:

| Session | Writes | Never writes |
|---|---|---|
| **App session** (one per app) | its own `.mpr`, its repo, its `PROJECT.md` | another app's repo or model |
| **Coordinator** (optional, the steering session) | `SYSTEM.md`, briefs, `handoffs/` | **any `.mpr`**, any app's `PROJECT.md` except through that app's session |

- **Name the owner in the Apps table**, not in chat. *Failure:* a register's open question read
  "confirm nobody is building it in another session" — ownership lived in session memory, and a
  peer session was found working on the same `.mpr`.
- **A consumer whose publisher is owned elsewhere builds against a mock** generated from the
  publisher's contract file, and waits for `built` before switching. It does not edit the publisher.
- **Isolation per tool.** Claude Code: one session per app repo; worktrees only within one app.
  Agent teams share one working tree, so they are not for `.mpr` writers. Codex / Copilot: a
  nested `AGENTS.md` per app repo pointing at `SYSTEM.md`.
- **Machine hygiene.** Stop only your own process — by PID or by your app's port, never
  `pkill -f "mxcli run"`, which stops every app on the machine (it did). One port per app, written
  in the Apps table. `mxcli test --local` binds shared ports: one run at a time across all apps
  (`rest-between-mendix-apps.md` → "Keeping it cheap").

### Handoffs

When one session did something another must know ("pushed your branch", "swept two of your files
into my commit", "contract X is now `built`"), write `handoffs/<YYYY-MM-DD>-<topic>.md` in the
system repo or company brain:

- addressed to the receiving session (app name), with **"verify rather than trust"** at the top;
- what changed, the commit or file to check, what the receiver must do;
- **deleted by the receiver once acted on.** A handoff folder with files older than a week is a
  backlog nobody owns — count them at the weekly review.

---

## 3. Security across apps

**One identity provider for the system, decided once** (`SYS-D` row, mirrored), before any app
builds its own login. *Failure:* the plan promised "OIDC SSO with role mapping" on day one; after
several apps were built a search of every app's decisions and model found no OIDC in any of them —
each had its own local user store, and SSO became a retrofit across all apps.

| Concern | Official route | Record |
|---|---|---|
| **Human login across apps** | OIDC SSO module with name-based role mapping from IdP **group claims** (OIDC SSO 5.x; needs User Commons ≥ 3). Optionally one Mendix app as IdP via the OIDC Provider. | One mapping table per app: IdP group → module/user role. Every user role in every app appears in it or is marked local-only. |
| **App-to-app calls** | A **service account per direction** (`<consumer>-reader`) on a machine-only role, authenticated with **tokens** (client credentials from the IdP, verified by the publisher) rather than HTTP Basic. Basic over TLS is the dev minimum `mendix-service-seam.md` P2 proved, not the target. | A Service accounts table in `SYSTEM.md`: account, direction, roles, where the secret lives (channel, not value), last rotated, target auth. |
| **Versions** | Check the OIDC SSO and User Commons versions against **each** app's Mendix version before the first app installs them. | "unverified" in the Shared assets row until one app runs it, then a second. |

Sources: OIDC SSO module https://docs.mendix.com/appstore/modules/oidc/ and
https://marketplace.mendix.com/link/component/120371 ; OIDC Provider
https://docs.mendix.com/appstore/services/oidc-provider ; consumed-service authentication
https://docs.mendix.com/refguide/consumed-odata-services/ ; constants
https://docs.mendix.com/refguide/constants/ ; portfolio access https://docs.mendix.com/governance-control

**Secrets are never printed.** Never `cat` a constants file, echo a password, or pass one on a
command line (shell history and process list). Read it into an env var and use it; when proving
auth, print the HTTP status, not the request. Channels per value: `learned-constants-and-secrets.md`.
*Failure:* a session printed a service-account password into its transcript; it had to be rotated
in both the publishing and the consuming app, and every machine-local constants file updated.

**Dev login tiles stay dev-only.** Demo sign-in tiles are the offline fallback while SSO is wired;
they never ship in a deployed build.

---

## Completion criteria

Read from `SYSTEM.md` and each app's `PROJECT.md`; each line states its count.

- **N of N apps** in the register with an owner, a repo, a Mendix version and a port (an app in the
  system but not in the register counts in N and fails).
- **M of M contracts** with publisher, consumer and a status; every `built`/`verified` one with the
  grep or rung-4 evidence named. A contract at `mock` with no publisher date is listed, not hidden.
- **K of K cross-app decisions** with a pointer row in every affected app's `PROJECT.md`.
- **S of S service accounts** with direction, role, secret channel and target auth; 0 secrets in any
  committed file (`bin/check-no-client-data.sh` or the company brain's leak check).
- **Every user role in every app** in its group-mapping table or marked local-only (R of R).
- `handoffs/`: H open, none older than a week — or each one's reason stated.
