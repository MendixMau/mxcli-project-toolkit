# Skill: Measured claims — the register, and the rule that gives it force

**When to use:** before you cite any behavioural claim about the harness, the Mendix runtime, or a
test tool as *evidence*. Also whenever you are about to write a new claim down.

---

## The rule

**A claim not measured in this file may not be cited as evidence.**

Not "should be measured eventually". May not be cited. A plausible mechanism, a claim inherited
from an older skill, a thing everybody knows — none of those are measurements, and each has been
wrong here at least once (§2 below is one).

This rule exists because of a specific failure: a root cause was published, and then retracted,
because the control used to establish it **could not discriminate** — it would have produced the
same output whether the hypothesis was true or false. The retraction cost more than the original
investigation.

**Three arms agreeing is evidence of nothing until the control has been shown to move.** If every
arm of your experiment returns the same result, the first hypothesis to test is that your
instrument is broken, not that your hypothesis is confirmed.

**Format for every entry:** claim · verdict · how it was measured · what it costs us.

**Calibration, not configuration.** Every number below came from a real measurement on a real
project. The project identities are removed deliberately — a toolkit reader is in a different
project, and a number is useful to them as an *order of magnitude to expect*, never as a value to
assume. Where a measurement is inseparable from one project's specifics, the entry says so.

---

## 1. `playwright-cli eval` never signals failure through its exit code

**Verdict: CONFIRMED, and broader than suspected.** Measured on `@playwright/cli@0.1.15`, macOS
host, headless chromium, page `about:blank`.

| Arm | Expression | stdout | rc |
|---|---|---|---|
| control | `() => true` | `### Result` / `true` | **0** |
| failing assertion | `() => false` | `### Result` / `false` | **0** |
| documented throw pattern | `() => { throw new Error('MUTANT-SHOULD-FAIL') }` | `### Error` + stack | **0** |
| missing selector (real-world) | `() => document.querySelector('.mx-name-doesNotExist') !== null` | `### Result` / `false` | **0** |

**All four exit 0.** The prior, weaker claim was "a thrown `Error` exits 0". The measurement is
stronger: *nothing* exits non-zero. A returned `false` — the ordinary shape of a failing DOM
assertion — is indistinguishable by exit code from a passing one.

**Cost:** under `set -e`, every `playwright-cli eval` assertion passes unconditionally. The
mxcli-bundled `test-app.md` skill documents **35** such invocations and presents them as
assertions. A suite built from that skill reports green having verified nothing.

**The only failure signal is stdout text** — `### Error`, or `### Result` followed by `false`. Any
wrapper must parse stdout; exit codes carry no information here.

**Blast radius:** `test-app.md` is mxcli-bundled and regenerated on upgrade, so editing your copy
is a no-op. Eight copies were found on one machine. The fix is an upstream mxcli issue plus a
shared-toolkit override, not a local edit. **A journey harness built on the Playwright Node API
directly is unaffected** — this defect belongs to the CLI wrapper, not to Playwright.

### Two incidental findings from the same session

- **`playwright-cli` may not be able to launch at all on a host**, if its config pins
  `executablePath` to a devcontainer path. The daemon then dies with *"Failed to launch chromium
  because executable doesn't exist"*. Workaround: copy the config and repoint it at the locally
  installed headless shell. Note `open` accepts `--config`; **`eval` does not** — it inherits the
  already-open daemon. This is the same platform-fatal shape as a Windows-only `psql.exe` path in
  a harness that runs on macOS.
- **`file:` URLs are blocked** by the CLI's `network.allowedOrigins`, which defaults to a narrow
  localhost port range.

### Method note — the first measurement was invalid

The first attempt ran all three arms with no browser open. All three returned rc=1, which *looks
like* a clean discriminating result and is not: they failed identically for a reason unrelated to
the hypothesis (*"The browser 'default' is not open"*). An earlier attempt was more wrong still —
it tested a different binary that has no `eval` subcommand at all.

---

## 2. `networkidle` never fires under Mendix

**Verdict: FALSE as stated. The rule survives; the rationale does not.** Measured:
`networkidle` fired in **1 ms**.

Several skills — including the mxcli-bundled one — justify avoiding `networkidle` on the grounds
that Mendix's polling keeps the connection busy so it never fires. **That reason is wrong and must
not be repeated.**

**Keep the rule.** Playwright marks `networkidle` DISCOURAGED, and a wait that resolves in 1 ms is
not a readiness signal. But state the real grounds: it is a network-quiet heuristic, not a proof
that the page rendered. Landing must be proven by a rung-1 landing guard on a named `ready` widget
instead.

This entry is the register's own best argument: a correct rule was being taught with a false
mechanism, and nobody had checked, for as long as the rule kept working.

---

## 3. App ownership travels with the port

**Verdict: CONFIRMED working.** Measured against a live, *stale* `stack.env` that named a port
belonging to a different project's Mendix — which answered 200 with a real login page.

| Arm | rc | Behaviour |
|---|---|---|
| stale `stack.env`, no ownership marker | **2** | refuses; names the port, the source of the port, and three fixes |
| `ALLOW_UNVERIFIED_APP=1` | 0 | proceeds; ownership recorded as `unknown` |
| `APP_PORT` set explicitly (operator assertion) | 0 | proceeds; ownership `asserted`, basis recorded as `APP_PORT env` |

rc **2 = instrument fault**, never 1 = finding. A harness pointed at the wrong app has not found
anything; it has failed to measure.

**Method note:** the first run of this measurement reported `rc=0` for the refusing arm — because
the command was piped to `tail`, so `$?` was `tail`'s status. Re-measured unpiped. **A pipeline
masking an exit code is the same defect class this file exists to document**, and it appeared
inside the measurement of that class.

---

## 4. "Sign in failed." means the password is wrong

**Verdict: FALSE — and it cost most of a session.** Measured against a Docker-hosted Mendix stack.

Mendix's login page renders **two** different messages, and only one of them is about credentials:

| Runtime log | Login page shows |
|---|---|
| `Login FAILED: invalid password for user 'x'` | The username or password you entered is incorrect. |
| `Login FAILED: unknown user 'x'` | The username or password you entered is incorrect. |
| `ERROR - Connector: Maximum number of sessions exceeded! (You are currently using a trial license)` | **Sign in failed.** |

The credentials were correct throughout. The first two journeys of the run passed; every journey
after them failed, and the UI attributed it to the credential. The real cause was the unlicensed
runtime's **concurrent-session cap**.

Three arms, to show the control moves:

| Arm | Page message | Runtime log |
|---|---|---|
| correct user / correct password | Sign in failed. | Maximum number of sessions exceeded |
| correct user / stale password | username or password incorrect | invalid password |
| a username that does not exist in this database | username or password incorrect | **unknown user** |

Note the third arm: a default admin identity carried over from another project produces *unknown
user*, not an auth failure — the account simply does not exist in this database.

**Cost:** the harness reported `FAIL [ui] login`, which reads as a finding against the app. It is
an **instrument fault** — nothing downstream ran.

**Fix, and adopt this shape:** any login rejection whose message does **not** match
`/username or password/i` returns `fault: true`, and the runner records `INVALID`, not `FAIL`. The
fallback identity is **not** tried on a fault — it would burn a second account against the same
cap, and a silent admin fallback makes every role-scoped assertion vacuously green.

### Corollary, measured the same session — a Mendix session is not released when the browser closes

It persists in `System.Session` until it times out and the cluster manager sweeps it, and it
**survives a container restart** — the rows are in the database, not memory. Six stale sessions
from six separate runs blocked all further logins. Two fixes, both needed:

- **The runner must log out before closing the browser.** A GET to `/logout` **does not work** — it
  renders a page and leaves the session alive (measured: the app root still resolved to the
  dashboard afterwards). The `xas` `logout` action does; after it, `/` redirects to the login page.
- **Shorten the session timeout and the cluster-manager interval** in the runtime's environment, so
  leaked sessions expire in a minute or two rather than the ten-minute default. Both are runtime
  parameters set in the container/compose configuration.

**Operator note:** the runner logs in **once** and then loops every journey file passed to it.
Invoking it once per journey burns one session per journey and reproduces the cap. Pass all
journeys in a single invocation.

---

## 5. The Docker stack tests the app; an empty database tests the fixture

**Verdict: CONFIRMED — the default stack had no data at all.**

A compose file pointed the runtime at a fresh PostgreSQL volume. Nothing migrated the Run-Locally
data into it, and no after-startup microflow seeded the business domain. Every data rung reported
INVALID — *"the DB has no row to drive this journey"* — which is the **honest** verdict and still
worthless: it measures the empty fixture, not the app.

The project's `deployment/data/database/` directory already held the data the app was built
against, and `mxcli docker build` copies it into the build tree that is bind-mounted into the
container. Switching the runtime's database type to match that on-disk database made it live at
zero cost. The runtime then confirmed *"No database sync needed"* — the schema matched the model.

Row counts from the recovered fixture, **from a single project, not replicated** — cited only as
the order of magnitude a demo-scale fixture has:

| Kind of table | Rows |
|---|---|
| master data (items) | 30 |
| master data (locations) | 20 |
| transactional (placements) | 64 |
| transactional (movement log) | 44 |
| session/aggregate | 15 |
| reference codes | 28 |

The effect on the journey was categorical, not marginal: the module's journey went from *1 PASS / 1
INVALID* (never left the first data rung) to walking all five steps, with a row-count delta of
exactly +1, both associations set on every row, and the `mustPointAt` claim resolving against the
seeded target.

**Two things to preserve when you do this:** only the *build copy* of the database is mounted, so
runs mutate the copy and the pristine `deployment/` tree is untouched; and `mxcli docker build`
resets it, which is your reset button between runs.

---

## 6. A host-side mock API silently detaches when the app container is recreated

**Verdict: CONFIRMED, and it looks exactly like a feature defect.**

A mock service running on the host was reached from inside the app container via a socat sidecar
started with `--network container:<name>`. Docker resolves that to a **container ID**, not a name.
Recreating the app container — *any* compose edit, not just a restart — leaves the sidecar
`running` against a dead namespace:

```
app container now : c079723250107d…     proxy bound: 6b1485b12a6d…     >>> ORPHANED
docker exec <app> curl http://localhost:<mock-port>/…   ->  000  (exit 7)
```

The application's configured base URLs still point at the mock, so the affected pages render empty
and **the journey reports a UI failure against the app**. Rebinding the sidecar restored it, and
the module's journey went from a single failure at *"button not visible"* to **27 PASS**, including
the whole downstream detail page.

**Every restart of the app container must be followed by a rebind of the sidecar.** This belongs in
a preflight assertion, not in an operator's memory. Until it is one, treat "pages that consume a
mocked integration render empty" as a suspected instrument fault, not a finding.

---

## Adding an entry

An entry earns its place only if it carries all four parts: the claim, the verdict, the
measurement, and the cost. In particular:

- **Show the control moving.** At least two arms, and say what would have falsified the claim.
- **Record the invalid attempts too.** §1 and §3 both contain a first measurement that was wrong in
  a way that looked right. Those method notes are the most transferable content in this file.
- **Anonymize the project, keep the number.** A reader in another project needs the magnitude and
  the mechanism, not your module names.
- **If a number came from one project and has not been replicated, say so in the entry.** An
  un-replicated number is still calibration; an un-labelled un-replicated number is a false fact.
