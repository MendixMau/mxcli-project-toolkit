# REST between Mendix apps: contract, consumer honesty, and a test ladder that stays cheap

**Applies to:** two or more Mendix apps that you build yourself and that read each other's data over
REST ("microservices between Mendix apps"). One app publishes what it owns; another polls it.

**Purpose:** the decisions to make before the first script, the consumer habits that keep a page
honest about stale data, and how to test across apps without paying for a full multi-app run on
every change.

**Evidence:** three demo apps built with mxcli v0.24 to v0.26 on Mendix 11.15, October 2026: an
**order app** (publishes `rest/orders/v1` and `rest/announcements/v1`), a **stock app** (polls the
order app, publishes `rest/order-readiness/v1` and two stock feeds) and a **customer app** (publishes
four customer feeds and polls both others). Nine published APIs, five consumer directions. Domain
names are generic placeholders. Every numbered rule in §2 and every result in §3 that is not marked
**(recommendation)** comes from a failure or proof recorded in the apps' FINDINGS files or proof
documents; the 26-row register is `process/rest-between-mendix-apps-register-2026-10.md`. In §1,
a "Why" marked **(design choice)** is reasoning the apps adopted, not a recorded failure.

**Not this file:**

| For | Read |
|---|---|
| JSON structure, import mapping, the `all` range flag, a REST-fed DataGrid | `rest-integration-first-time-right.md` |
| Which channel a password or base URL comes from | `learned-constants-and-secrets.md` |
| What "tested" means for one module, and the false-green register | `testing-shape.md` |
| MDL syntax | `./mxcli syntax rest` → `rest.published`, `rest.consumed`, `rest.call`; `./mxcli syntax integration` |
| A stand-in for a third-party API (Prism, proxy) | the mxcli skill `mock-rest-apis` |

---

## 1. Before the first script: write the contract down

Write the contract **in the publisher's repo** as an OpenAPI file per API, plus one short markdown
file with the decisions. The consumer's team reviews it; nothing is built until both agree.
In the evidence, every API had an OpenAPI file, and the decisions table (pull only, key, version
rule, auth, versioning) was settled before either side wrote MDL.

Decide these, and write each down:

| Decision | What the evidence did | Why |
|---|---|---|
| **Pull or push** | Pull only, in every direction. Each app publishes what it owns; the other polls. | No outbox, no retry queue, no inbound write endpoint. An app that is down is simply not polled, and nothing is lost. Push is a valid choice, but it needs all three: an outbox, a retry queue and an inbound write endpoint. **(design choice)** |
| **Versioned path** | `rest/<api>/v1`. Additive changes only inside a version; a breaking change is `/v2` beside `/v1`. Every body carries `contractVersion`. | The consumer can test against a `version` mode of its fixture (§3) and refuse a body it does not understand. |
| **Record key and version** | One key per record (for example `ORD-0001/ITEM-B/WH-A`) and an integer version, +1 on every content change. Receivers upsert on the key and ignore a version not higher than the one stored. | Replays, overlapping polls and a restore from backup all land on the same state. |
| **Paging** | Opaque cursor: `nextCursor` from the previous page, `null` on the last page. Cursor = base64 of `updatedAt|key`; order by `updatedAt`, then key. | Stable under inserts **(design choice)**. Recorded: a row with an empty `updatedAt` never matches a cursor, so the seed must set it on every row. |
| **Incremental read** | `since=<ISO instant>`; the consumer sends its last fully processed `updatedAt` minus an overlap (2 minutes in the evidence). | The overlap is safe only because of the version rule above. |
| **Correlation** | The caller sends `X-Correlation-Id`; the publisher echoes it in the response header and in every error body, and both sides log it. | One id to grep in two runtime logs. **(design choice)** |
| **Error shape** | `{ "code": "bad_limit", "message": "...", "correlationId": "..." }`. 401 bad or missing credentials (with `WWW-Authenticate`), 403 known account not allowed on this API, 404 unknown key, 422 bad parameter. | One shape for every consumer to parse **(design choice)**. Recorded: the runtime's 560 arrives before your microflow runs (§2, step 3). |
| **Auth** | One service account per direction, named `<consumer>-reader`, HTTP Basic; HTTPS outside dev. | As of mxcli v0.24 (BUG-152), MDL cannot set the service's own authentication, so the check lives in the operation microflow (§2, step 1). |
| **Ports** | A fixed port per app, written in the plan (in the evidence 8085, 8086, 8087). Never 8081/8091: `mxcli test --local` binds those. | A wrong app answering on a shared port returns 200 with the wrong body. Smoke tests check the body, not only the status. |
| **Who owns each fact** | A table: fact → owning app. The consumer stores a *copy* with an "as of" time and never computes its own version of an owned fact. | §2 has the two cross-app contradictions this rule would have prevented. |
| **Transport dates** | Keep dates as String in the JSON structure and validate them in the microflow; give the snippet a non-date sample. | A date-shaped sample infers DateTime, and a String mapping onto it fails mxbuild with CE5015 (`check` does not see it). |

Secrets: the reader passwords are **constants with no value in the model**, set per machine
(`.mxcli/constants.json`, never committed) or per environment. An empty value, or a placeholder
such as `__SET_ME__`, closes the account. `learned-constants-and-secrets.md` has the channel rules.

---

## 2. Building it

### Publisher side

1. **Authenticate inside the operation microflow.** As of mxcli v0.24, `create published rest
   service` has no auth clause, and an `Authentication:` property is silently ignored (BUG-152);
   re-probe on a newer binary. Studio Pro can set the published service's own authentication. Done
   only in the microflow, the endpoint itself is anonymous at runtime: every request reaches the
   microflow with no user, so every operation microflow must run the check, and nothing else stands
   in front of it. Read the `Authorization` header, compare against the constant, return 401 with
   `WWW-Authenticate` for none or wrong, 403 for a known account on an API it may not read. Then
   prove it at runtime (rung 4). Bonus: an inbound call-log row can then name the caller on every
   outcome, including 401.
2. **`''` is not `empty` for a String query parameter.** An unset `?limit=` arrives as `''`. Test
   `$p != empty and trim($p) != ''`, or every unset parameter is rejected (7 of 29 tests passed
   before this fix, 29 of 29 after).
3. **Know which errors you never see.** A malformed parameter such as `cursor=%%%` (invalid
   percent-encoding) is rejected by the Mendix runtime with **560** before your microflow runs. A
   well-formed bad cursor reaches your code and gets your **422** `bad_cursor`. Put both in the
   contract, so the consumer and the mock know the 560 exists.
4. **Every change that alters the payload must bump both `version` and `updatedAt`.** The evidence
   shipped a producer with the order version hardcoded to 1 and state hardcoded to `Open`, and a
   `since` filter on the order's date only. A cancellation changed neither, so the consumer's
   incremental read skipped it and advanced its cursor past it. Rule: list every attribute the
   payload projects, and make the `since` XPath cover every timestamp that can change any of them.
5. **One script owns the service and names every resource** — `create or modify published rest
   service` replaces the resource list (BUG-152).
6. **Write `contractVersion` and `generatedAt` into every body**, and make the field signs and units
   match the contract example (the evidence had a variance value whose sign the database stored the
   other way round; the API now writes `0 - VariancePct`).

### Consumer side

7. **Keep one endpoint row per upstream API**: `LastSuccessAt`, `LastError`, `LastErrorAt`,
   `CredentialsRejected`, cursor, and the source's `generatedAt` of the last good read.
8. **A non-2xx answer raises an error in the runtime.** Handle it **without rollback** and read the
   latest HTTP response, or the status is lost: the first handler in the evidence logged a 401 as
   0 "Not reachable" and rolled the endpoint row back. **(recommendation)** A 401 sets
   `CredentialsRejected` and stops polling until someone changes the password; a 5xx or timeout
   keeps polling.
9. **`LastError = ''` is not `LastError = empty`.** After a good read the code cleared the error to
   `''`; the banner's XPath `LastError != empty` matched the empty string, so every healthy feed said
   "unreachable". Guard on non-empty string, and test both values (§3, rung 1).
10. **Show "as of" from the source's time, and a stale marker.** The line reads
    "Stock readiness as of 2026-10-08 17:17, not reachable" and keeps the last good rows. A first
    read that fails says "never read", not "0". A feed polled every 5 minutes whose last success is
    days old is stale: say so on the page. **(recommendation)** Stale threshold = 3 × the poll
    interval, computed on the page, not stored.
11. **A status card shows the last real call, not a probe.** The evidence had a card saying
    "Reachable · ok" from a probe three days old while every live call that day returned 400. Write
    `LastSuccessAt` / `LastError` from the production call path, and show both.
12. **Ordering guard.** Ignore a record whose version is not higher than the stored one. A test
    pins it with three reads of the same two rows: a higher version stores both, a lower one stores
    none, a mixed read stores only the row that is newer. An old message can never
    overwrite newer state, and a repeat read changes nothing.
13. **Prune only after a complete good read.** The consumer upserted what the publisher served but
    never removed what it stopped serving, so a warehouse stayed on the card after the publisher
    dropped it. Delete rows not re-stamped by the latest read, and only when the read had no error
    and no next page. A failed or partial read keeps the last known rows.
14. **A cursor can skip; give a full read a button.** After the producer bug in step 4, the
    recovery was: scheduled reads stay incremental with overlap, an admin "Read now" does a full,
    idempotent read. Keep one.
15. **A check done once at publish time needs a retry.** An eligibility check ran only when the
    announcement was published; the other app was down then, and the card said "not reachable" for three
    days until a "Re-check" action was added.
16. **One owner per fact; never invent the owner's fact on failure.** Two contradictions reached the
    UI:
    - a consumer's fallback seeded a record as "Approved, approved now" when its read failed, so the
      same order was Approved in one app and Open in the owner;
    - two apps counted "support cases for this order" each in their own way (5 in one, 6 in the
      other: one counted app-wide cases).
    A consumer that has no answer shows "not visible here" or "never read", not a guess. A count of
    an owned fact is read from the owner's API, never recomputed.
17. **Size the cache columns from the real feed, not the example.** Item codes up to 40
    characters arrived from the live publisher; the consumer's columns were 30. The mock never sent
    one that long.

---

## 3. Testing across apps: the ladder

Climb from cheap to dear. A rung earns its cost only once the rung below is clean.

| Rung | What it proves | How (evidence) | Cost measured |
|---|---|---|---|
| **1. Publisher contract tests** | Filters, limits, paging, 404/422, auth rule, version rule — against the publisher's own microflows | `mxcli test tests/api-<name>.test.mdl`: orders 29 cases, announcements 17 | Two measured runs: ~76 s wall for one module's suite, and 9 min 21 s wall for one file whose tests took 848 ms. Wall time is the injection into the `.mpr` and the build, not the tests |
| **1b. Consumer logic tests** | Version rule, prune, "never read" vs "as of", `''` vs empty, feed-status line | Seed endpoint rows and stored copies in the test; call the SUB directly. Feed status: 4 cases (healthy, one failing, none ever read, failure before first success) | Same as rung 1 |
| **2. Consumer vs fixture server** | The consumer's HTTP path: auth, paging, every failure mode, idempotent repeat | One fixture per upstream under `tools/mocks/` (Python or Node, loopback only, fixture password). Modes switched by `GET /mock-admin/mode?mode=normal\|down\|partial\|invalid\|version\|cursor-cycle`; `/mock-admin/stats` counts requests. 6 modes × 3 feeds = 18 cases. Point the consumer's base-URL constant at the fixture for the run only, and restore the constants file on exit | Seconds per case; no publisher running |
| **3. Contract diff, mock vs live publisher** | That the mock still tells the truth | Same requests against the mock and the live publisher; diff keys, shapes and status codes. First run: **9 of 10** — the runtime's 560 on `cursor=%%%` (mock: 200) and an empty `limit=` (mock: 422, publisher: not given) | Minutes; needs the publisher running |
| **4. Live smoke per app** | Auth and routing on the real port | `curl -u` per API: no credentials, wrong password, each reader account. Matrix of 16 of 16 as designed (401/401/200/403 per API), plus `limit=1` then `nextCursor` on every paged API (4 of 4) | Seconds; check the body as well as the status |
| **5. Cross-app consistency** **(recommendation)** | The same key gives the same status and counts in every app | For a handful of keys, read the owner's API and each consumer's stored copy (OQL or its page), compare status, version and counts, print a table with the denominator. Nothing in the evidence did this; a UX scan found the two contradictions in §2 step 16 by eye | Seconds once all apps run |
| **6. Cross-app journeys** | The few flows that truly span apps: publish → poll → act → poll back; upstream down then back | Browser journeys per app, in order: "upstream unreachable after a good read" 26/26; the full cancellation story across three apps | Minutes to hours; run rarely |

### Cadence

| When | Run |
|---|---|
| Per change to an API or a consumer | Rung 1 for the touched app (only the touched test file), rung 1b if consumer logic changed, rung 2 for the touched consumer |
| Per slice | Rungs 1–2 in full for the touched apps, rung 3 for every API whose publisher or mock changed, rung 4 for every touched API |
| Per release, or after a contract change | All rungs; rung 5 on a fixed list of keys; rung 6 only for the cross-app journeys |

### Keeping it cheap

- **One `mxcli test --local` at a time on the machine, across all apps.** It binds the fixed ports
  8081 and 8091, whichever project runs it. Runners check those ports and refuse when they are
  taken; let them, and queue the next app's run behind the current one.
- **`exec.sh` locks per project, not per machine** (#304). Another app's `exec.sh` no longer blocks
  yours, so two apps' model writes may run side by side. A raw `mxcli exec` outside `exec.sh` takes
  no lock, so keep every model write on `exec.sh`. `mxcli test --attach` counts as a model write
  (`testing-shape.md`), so it still needs that app's lock and is not a way to run two tests of one
  app in parallel.
- **Never stop a test run with a signal** (BUG-157). `mxcli test` and `run --test-endpoint` point the
  after-startup microflow at an injected `MxTest` flow and restore it only on a clean exit. A run
  stopped by a kill or a background-task stop leaves the setting there, the next injection chains the
  flow to itself, and the app dies at startup with a StackOverflowError. Check the setting before
  the next run; BUG-157 has the repair. Never commit while an app started with `--test-endpoint`
  runs: it writes an `MxTest` module and an after-startup setting into the model.
- **`@cleanup rollback` is the default.** A seed that later tests use must say `@cleanup none`, and a
  cleanup test must remove it; delete by exact key, not by prefix (a prefix cleanup reached demo
  data that shared the prefix).
- **Reset every fixture before the suite and name its port in the suite header.** A stale mock
  process on the old port served two old records and failed a count; a test that reads a live mock
  goes red after any run that changed the mock.
- **An absent upstream is SKIPPED, not passed.** The runner that targets the real publisher reports
  SKIPPED when nothing listens on its port, and the wrapper must read **every** verdict, a clean
  exit and zero skips — one wrapper read only the first verdict.
- **Two apps on one host share the session cookie.** Give each app its own hostname
  (`app-b.localhost`) in browser journeys, or one login signs the other out.
- **Journey order can be load-bearing** when journeys reset a shared mock or need a state another
  journey leaves. Write the order in the suite, or make each journey set up its own state.

---

## 4. Definition of done for one API

| Check | Evidence to show |
|---|---|
| Contract file in the publisher's repo, reviewed by the consumer | the file path |
| Rung 1 and 1b | `N/N` from the test output |
| Rung 2: every fixture mode | `N/N`, modes listed |
| Rung 3: contract diff | the diff file, `x of y` equal, each difference explained |
| Rung 4: status matrix | the curl table |
| Page shows "as of", stale and "never read" states | a screenshot of each, as a real user role |
| Fact ownership row added | the ownership table |

---

## 5. What the evidence says about the ladder

Of 26 recorded failures, rungs 1–4 caught 12, a journey 4, a human looking 7, the exec gate or a
runner audit 3. Of the 11 found by a journey or a human, 9 had a cheaper rung that would have
caught them; the two cross-app contradictions needed rung 5, which nobody ran. The full register,
with the catching and the cheapest rung per failure, is
`process/rest-between-mendix-apps-register-2026-10.md`.

## Related

- `rest-integration-first-time-right.md` — the mapping and page mechanics for one consumer
- `learned-constants-and-secrets.md` — where reader passwords and base URLs live
- `testing-shape.md` — false-green register; test-runtime ports 8081/8091; `--attach` is a model write
- `tool-output-is-not-ground-truth.md` — a smoke test checks the body, not the status code
- `bug-logs/mxcli-bugs.md` BUG-152 — published REST auth, resource list, mapping drops; BUG-157 — a signal-stopped test run breaks startup
