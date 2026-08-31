# Testing a module — the shape, and how each part lies
**Applies to:** any mxcli project with a runnable app.

Two jobs. **(1)** Say what testing a module means, so it is the same thing every time. **(2)** Carry
the **false-green register** — the confirmed ways a test reports green while the feature is broken,
and the guard for each. Job 2 is why this skill exists; if you shorten it, do not shorten §4.

**Read the owner, not a copy here:**

| Need | Read |
|---|---|
| Playwright harness setup, widget discovery, suite structure | `e2e-harness-base.md` (shared toolkit) |
| DB/OQL assertion mechanics | `learned-db-assertions.md` (shared toolkit) |
| The run → fix → re-run loop shape | `qa-loop-goal-pattern.md` (shared toolkit) |
| Unit-test syntax and the runner | `.ai-context/skills/test-microflows.md` — ⚠ mxcli-bundled, **regenerated on upgrade**. Read for mechanics; never edit it, never link doctrine at it. |
| Non-pipeline app, à-la-carte assurance | `existing-app-assurance.md` (shared toolkit) |
| Why a green UI report can still be lying | **§4a below** — merged in, no longer a separate file |
| The deep five-rung version of "prove it", with per-rung non-vacuity controls | `journey-proof.md` (shared toolkit) |
| Requirement traceability the suite asserts against | `coverage-ledger.md` (shared toolkit) |
| Why `$?` and tool output are not evidence | `tool-output-is-not-ground-truth.md` (shared toolkit) |
| Does the whole journey hang together, not just each piece — a different axis, not a fifth rung | `process-coherence-pass.md` (shared toolkit) |
| The full build→gate→prove→look→confirm→next loop this shape plugs into, incl. monkey testing | `module-review.md` (shared toolkit) |

> **Promotion note, closed 2026-08-18.** All three rows above now have a shared-toolkit copy,
> so §4 — the load-bearing section — no longer cites anything a fresh project cannot open.
> `e2e-ui-test-honesty.md` was merged into §4a and deliberately has **no** shared copy: if you
> find one anywhere, this file is canonical and that copy is stale.

---

## §1 — The shape

**Every module gets two things. Two more are optional.**

| | Part | Answers | Always? |
|---|---|---|---|
| **UI** | Playwright walks the screen | Can a person complete the flow? | **yes** |
| **Data** | OQL / DB assertion | Did the write actually land? | **yes** |
| **Unit** | `.test.mdl` via `mxcli test` | Is the logic right on its own? | optional |
| **Trace** | OpenTelemetry spans | Which microflow fired, and did any activity error? | optional |

That is the whole vocabulary. **No tiers, no numbers, no depth levels.** An earlier draft used a
numbered four-tier ladder; it was dropped on 2026-08-05 because the numbers collided with a
different numbered scheme already in use in build-plan rows, and because the numbering carried no
meaning anyone could keep straight. If you meet `T0`–`T4` in a build plan, that is the **other**
scheme, at per-script grain. It is unrelated to this skill and is not being renumbered.

**Why UI and Data are both mandatory.** They fail differently. A screen can look correct over a write
that never landed; a row can land while the screen is unreachable. Neither substitutes for the other.

> **"Data" means *check the source of truth*, not *always query a database.*** Plenty of modules have
> no database rows to assert on — read-only screens over REST, non-persistent DTOs, modules whose
> entities are all non-persistent. **Do not force an OQL query onto them; it will pass vacuously,
> which is the exact failure §4 exists to prevent.** Assert against whatever the real source is:
>
> | Module shape | The Data assertion is |
> |---|---|
> | Persistent entities, a write happens | OQL **count delta** or a fresh unique key |
> | Read-only screen over REST / non-persistent DTOs | compare the screen against the **upstream response** (e.g. `pagination.totalItems` vs rendered rows) |
> | Neither is reachable | **say so on the row, and name the query that proves it** — e.g. `SHOW ENTITIES IN <Module>` showing N/N non-persistent, with a date. An absent Data assertion must be *documented and evidenced*, never silently missing. |
>
> Confirmed 2026-08-06 on a live build: one module was entirely the second shape — every entity it
> owns is non-persistent, the screens are read-only over REST, and its spec already compared the
> rendered row count against the upstream `pagination.totalItems`. Forcing an OQL count onto it would
> have added a check that could only ever pass.

**Why Trace exists at all.** A correctly configured import-mapping activity that silently does not
run is invisible to `DESCRIBE`, to BSON inspection, to `check --references`, and to `mxbuild`. The UI
is green, the page renders, the list is simply empty. Trace is the only instrument here that sees it.

---

## §2 — Who chooses the optional parts: the customer, at intake

**Ask once, at project intake — not once per module.** Record the answer in `PROJECT.md` as a
CONFIRMED decision like any other.

> **The intake question.** Every module gets UI tests and database assertions as standard. There are
> two optional additions, both with a real cost:
>
> - **Unit tests** — check a microflow's logic on its own. Worth it where a module has fiddly
>   calculation or mapping logic. **Cost:** the runner temporarily writes to your project file, so
>   Studio Pro must be closed and the file snapshotted first. It also has two confirmed parsing
>   defects (§4) that have to be worked around.
> - **Trace (OpenTelemetry)** — see inside the running app: which microflow fired, and whether a step
>   errored even though the screen looked fine. Worth it where a module **calls out** to something —
>   a REST call, an import mapping, external data — because that is where failures get swallowed.
>   **Cost:** someone must switch it on by hand in Studio Pro's settings (there is no command for it)
>   and start the trace collector by hand. Neither is scriptable today.

**Then one rule on top, and only one:** a module that **calls out** to something external may add
Trace even when the project default is off. That is where swallowed failures live, and it is the only
place Trace reliably earns its setup cost.

**A module may declare its shape; it may never leave it blank.** Same discipline as "a step may say
*not built*; it may never be *absent*".

**Declared in the build plan**, per module, alongside the base set (§3).

> **Revisit trigger for the Trace default.** Trace is optional because of a *setup* constraint, not
> because it is low value — the evidence runs the other way. In the 2026-08-05 per-module fan-out,
> 3 real model bugs were found and **2 of the 3 were found by Trace alone**. The blocker is
> that the Mendix-side OTel switch lives inside the `.mpr` binary with no command to set it, and the
> collector's launch line exists only in a handoff doc. **When that setup becomes scriptable, make
> Trace standard.** Do not re-open this on preference; re-open it when the constraint lifts.

---

## §3 — When it fires: the base set is done

**"When the module is finished" is not a usable trigger.** Modules are never finished — they are
improved, fixed and extended continuously. Any trigger phrased as *absence of remaining work* never
fires on a module anyone is still touching, which is every module that matters.

**So the trigger is declared in advance.** The module's build plan names a **base set**: the scripts
that constitute its base logic. When every script *in that named set* is done, testing opens. Scripts
added later do not move the goalpost, because the goalpost was placed before they existed.

**Guard — the base set must cover the module's coverage checklist.** That checklist is the agreed
definition of done (`iterative-build-loop.md`). Without this anchor someone declares two scripts
"base", earns a green suite, and the module isn't built.

**After the base set: re-run, don't re-propose.**

| Event | What happens |
|---|---|
| A fix to an existing script | **Re-run** the suite as regression. No questions, no re-authoring. |
| A new script within agreed scope | Re-run. Extend the suite only for a *behaviour* the coverage checklist doesn't already cover. |
| A new behaviour / scope change | The coverage checklist changes — the existing drift-sync path. The suite extends with it. |

So the authoring conversation happens **once per module**; everything after is cheap re-running. That
is what makes this affordable on a module under active development.

**The loop, once per module:**

| # | Step |
|---|---|
| 0 | Bring the stack up and **prove** it (§5) |
| 1 | Read the base set's scripts, the module's coverage checklist, and the declared shape |
| 2 | Author the suite against the coverage checklist |
| 3 | Run it. Fix what it finds. Re-run. Include the §6 positive control. |
| 4 | Report per part, per scenario (§7) |

Scenarios come from the coverage checklist, which already owns them. Do not keep a second copy here
or in an agent file — hardcoded scenario lists rot as modules change.

---

## §4 — The false-green register

**The load-bearing section. Every entry is a confirmed incident, not a hypothesis.** The dates exist
so the next person argues with the incident rather than with the rule.

| Part | How it goes green while broken | Guard — required, not advisory |
|---|---|---|
| **Design system** | **`mx check: 0 errors` proves the *model* is valid. CSS is not in the model.** It says nothing about what the browser renders, nothing about whether a class named in a `DynamicClasses` expression exists, and nothing about whether a rule's selector can match the HTML Mendix emits. `mxcli check --references` treats a class name as an opaque string; `mxcli lint`'s Starlark API has **no filesystem access at all**, so a rule that reads a stylesheet has nothing to read it with. On a 2026-08-26 field run, five real design-system defects were green in every one of these at the moment each was found — every one was found with a screenshot. | Run `bin/check-design-portability.sh` at the Stage-3 gate, and make the StyleGallery a **gate** (reachable, opened, looked at) rather than a step — `design-artifacts.md` Step 5b |
| **Design system** | **A design-system defect is dormant until some widget carries the class**, so the defects are all present from the first build and surface one at a time, months later, as UI work attaches classes to pages. "The build is green and the pages look fine" is therefore not evidence that the design system is correct — it is evidence that it is *not being exercised yet*, and it reads identically either way. | Exercise the whole system at once on one screen: the StyleGallery, instantiated with the same widgets the real pages use |
| **Model** | An **uncalled microflow is legal**, so `mx check` reports 0 errors after a `DROP` + `CREATE` silently drops another script's call site. `mxcli lint`'s orphan rule (QUAL004) does not close it either: `orphaned_elements.star` lists `ACT_` in `ENTRY_POINT_PREFIXES`, so an `ACT_` microflow with no callers at all is assumed to be a UI entry point and passes. A correct heuristic, a false negative here — and a silent exemption is indistinguishable from a clean result. | `describe` before any whole-document restatement and diff against the dump — `learned-mdl-preflight.md` STOP row 21. Verify the *effect* in the database, not in the model. |
| **UI** | A nav click with no landing guard asserts against the **previous** page and screenshots it under the intended page's title — manufacturing *plausible* failures that send you debugging the wrong subsystem (2026-07-30: twelve "Route List" failures, one nav click that never happened) | Every navigation is followed by a **landing assertion** before any other assertion |
| **UI** | `page.goto` recovery silently repairs state carry-over between specs | Recovery must **fail** the spec, not repair it |
| **UI** | Two windows on one account strip the nav menu mid-run | One session per account. Mechanics in `e2e-harness-base.md`. |
| **UI** | A login helper **silently falls back to an admin account** (a guard against lockout) — a role-scoped test then proves nothing, and neither the run nor the report looks any different (2026-08-05) | Any spec whose result depends on *who* is logged in must **assert the actual identity**, not merely that login succeeded |
| **UI** | A helper **no-ops without erroring** when its expected page is absent, so the spec runs to completion against the wrong page (2026-08-05, a mobile scanning spec) | Helpers must **throw** when a precondition is missing, never return quietly. Dump live page state rather than trusting the assertion's own label. |
| **UI** | A full `page.goto(baseUrl)` **silently logs the session out** once security is above `Off`. Suites that log in once and then "reset navigation" with a goto bounce to `/login.html` and every downstream assertion breaks for the wrong reason (2026-08-15, after raising `Off` → `Prototype`) | Fix at the helper, not the call site: the shared navigate-home helper detects the login form (`#usernameInput`) and **re-authenticates every time**. Never trust a cookie across `page.goto`. |
| **UI** | `:has-text(...)` is a **Playwright-only** pseudo-class. Inside `page.evaluate` it reaches `document.querySelector`, which throws `SyntaxError`; generic `.catch()` swallows it, so a `has_widget`-style helper evaluates **permanently false** and a visible row reads as absent (2026-08-15) | In `evaluate` context use a plain `.textContent.includes(...)` scan. Reserve `:has-text` / `:visible` for real Playwright locator strings. |
| **UI** | `display: contents` elements always report `offsetParent === null` — so an `offsetParent !== null` visibility filter returns **empty** for a Data Grid 2 the user is actively looking at (browser layout quirk, not a Mendix bug) | Check the ancestor tabpanel's own `getComputedStyle(...).display`, never the row's `offsetParent`. |
| **Data** | Asserting a row *exists* when seed data already satisfied the assertion | Assert on the **new** row — count delta or a fresh unique key. Never bare existence. |
| **Data** | "No items found" has **five** distinct causes and looks identical for all five | Measure with an instrument; never infer the cause from the empty state |
| **Unit** | **The runner silently drops the first test** when the file opens with a `/** */` header comment. The count looks plausible and nothing warns. (BUG-LOCAL-29, 2026-08-05) | **Count the `/` separators in the file and compare against `mxcli test --list`** before trusting a run. Avoid file-level `/** */` headers. |
| **Unit** | **`@expect` forms other than `=` equality are not captured** — `length(...)`, `!= empty`, `> 0` all parse to no visible assertion. In the only test file in existence this hit 8 of 14 tests. (BUG-LOCAL-30, 2026-08-05) | Write every `@expect` as plain `=` or `$Var/Attr =` equality. Run `--list` and confirm **every** test shows its `@expect`. |
| **Unit** | A microflow passes in isolation but no button calls it, or the caller passes different args | Assert the **caller path** exists, not just the microflow |
| **Trace** | `[].every()` is `true` — assertions pass on **zero spans** | Assert the span set is **non-empty first**, then assert over it. Also check the action wasn't a no-op: navigating to the page you are already on fires nothing. |
| **Trace** | A caught error leaves the microflow span `OK` while its activities are `ERROR` | Assert at **activity** granularity, not microflow granularity |
| **all** | `$?` after a pipeline measures the pipe, not the script — biased toward false *success* | Never read `$?` through a pipe. See `tool-output-is-not-ground-truth.md`. |

**Verdict discipline — the canonical statement, referenced from `journey-proof.md` rather than
restated there.** PASS / FAIL / INVALID are never collapsed: `PASS` is measured and correct, `FAIL`
is measured and wrong (the feature is broken), `INVALID` means **the instrument did not run** —
absent, not green. "The test could not run" and "the feature is broken" send you to different
people; blending them is how a week gets spent debugging a page that was never reached. In the
report/exit-code dialect these become `pass` / `fail` / `fault`, and **`fault` is never amber** —
amber means "ran, degraded". Corollary, applied everywhere in this toolkit: an empty result set is
never a pass — guard non-emptiness first, then assert (`[].every()` is `true`).

**Two verdicts, never collapsed.** When a §4 shape is present the correct report is ***the test is
invalid***, not *the feature failed*. Collapsing them is what sends people diagnosing the wrong
subsystem. Refuse to report green on a zero-span trace assertion, an unguarded navigation, or a
bare-existence DB assertion — regardless of what the runner printed.

**An assertion is also too weak if it lacks a fixture, an observable, and an exact expected value.**
Not "correct", not "as specified". The register says how a part lies; this says when the assertion
was never strong enough to catch it either way.

---

## §4a — UI honesty: make a failing test prove *where it was*

*(Merged from the former `e2e-ui-test-honesty.md`. This is the misfiling half of the UI story: the
register above says a green can lie; this says a **red** can lie too, and more expensively.)*

**The failure mode:** a UI test that navigates without verifying it arrived asserts against whatever
page is still on screen, fails every assertion for the wrong reason, and saves that screenshot under
the *intended* page's name. The report then looks like a genuine app defect. That is worse than a
silent bug — it **manufactures plausible failures** that send you diagnosing the wrong subsystem.

Found 2026-07-30 in a warehouse-management project: twelve "Route List" failures, an entire theory
about a missing module and a dead mock service — all one nav click that never happened. Caught by a
human looking at the screenshot, not by the suite.

### The seven rules

1. **Every navigation needs a landing guard.** Prove the page changed before asserting anything on
   it. Downstream sections that depend on it check the same flag and **skip**, they do not cascade.

   ```js
   const onPage = await page.locator(READY_WIDGET).first()
     .isVisible({ timeout: 8000 }).catch(() => false);
   step(meta, onPage, 'page loaded',
        onPage ? 'rendered'
               : 'nav item not reachable — did NOT navigate; skipping assertions '
                 + 'rather than testing the previous page');
   if (!onPage) { await shot(page, meta, `${name}-NOT-REACHED`); }
   else { /* assertions live here, and only here */ }
   ```

2. **Never `.catch(() => {})` a navigation click without checking the outcome.** Swallowing the
   error is fine. Not checking whether it worked is not.

3. **Screenshot failures, not just successes** — `<name>-NOT-REACHED.png`, `<name>-DID-NOT-OPEN.png`.
   Assertion text tells you what was *missing*; only the screenshot tells you what was *there*. That
   is the difference between diagnosing and guessing: three hypotheses were burned on one bug for
   want of a single image. **File the shot under the page you actually reached, never under the one
   you meant to reach** — a misfiled screenshot is the artifact that makes the wrong theory credible.

4. **One navigation helper, reused everywhere.** Sections that hand-roll navigation skip the
   accumulated knowledge in the shared one. Here the shared `navClick()` already knew nav **groups
   toggle** — force-clicking an expanded group collapses it and hides the child. The hand-rolled
   block did not. **This is the canonical statement of the nav-group-toggle trap** — `journey-proof.md`
   and `journey-examples.md` both point back here rather than restating it.

5. **Never reload to "get unstuck".** `page.goto(baseUrl)` as recovery wipes client state, hides real
   carry-over between flows, and lets the suite continue as though navigation worked. Navigate by the
   UI's own affordances (back arrow, cancel, nav item). If none exist, report and skip. If you must
   reload, log it loudly as non-user-like. (Under security above `Off` it is also a silent logout —
   see the register.) A `goto` **reset between independent journeys** is legitimate; the forbidden
   one is `goto` as *mid-journey recovery*.

6. **Assert on the database, not just the DOM.** A committed action should move a row count.
   `before=N, after=N` is the assertion that revealed a session record was never created — the
   UI-level "list is empty" was a downstream symptom pointing at the wrong place entirely.

7. **Take the success screenshot after the actions and landing guard, before the text/trace/data
   rungs** — so the image is the page state those rungs measured. A shot taken later shows the app
   after any navigation the rungs provoked and quietly stops being evidence for the checks printed
   beside it. **This is the canonical statement of the screenshot-timing rule** — `journey-proof.md`
   and `journey-examples.md` both point back here.

### Platform notes (Mendix / Playwright)

- **Two windows on one account degrade each other.** Concurrent sessions strip nav items from the
  slower window mid-run, and it reports as "role restriction". One account per window; an empty
  fallback user or a rejected login silently recombines them. *A menu that loses entries mid-run is
  never a role restriction.*
- **A probe that logs in and never logs out holds a Mendix session until it times out, and a trial
  license caps concurrent sessions.** Once the pool is exhausted the *next* run's login fails as a
  bland **"Sign in failed."** on the login page — indistinguishable from a wrong password, and
  `system$user.failedlogins` stays at **0** because authentication was never reached. Every
  downstream step then reports as a feature failure. Measured 2026-08-31 on a Mendix 11.13 app: a
  16-step narrated tour scored 0, with each step labelled `(as (not signed in))`, and the only honest
  evidence was one line in the runtime log —
  `ERROR - Connector: ... Maximum number of sessions exceeded! (You are currently using a trial
  license)`. Sixteen "defects" that were one leaked session pool.
  **Guard, two halves, both required:** every probe logs out in a `finally` block
  (`page.goto('<base>/logout')` before closing the context — closing the browser alone does *not*
  release the server-side session); and **before any login failure is reported as a defect, grep the
  runtime log for `Maximum number of sessions exceeded`**. When it is there the verdict is
  `INVALID`/`fault` — the instrument did not run — never `FAIL`. `failedlogins = 0` alongside a
  "Sign in failed." on screen is itself the tell: the credentials were never checked.
- **Phone viewports:** a target can be attached and rendered but **below the fold**, where
  `isVisible()` is false and the click is skipped. `scrollIntoViewIfNeeded()` before the visibility
  check.
- **Do not scale up a speed multiplier** that divides hand-tuned waits. A pluggable combobox needing
  ~1200 ms to open its dropdown fails at 150 ms, and the resulting failures look completely real.

---

## §5 — Precondition: the stack is up, and *you* bring it up

**The crash-net scripts cannot provide one.** `restart-sp.sh` kills Studio Pro and the runtime and
reopens SP, then stops — every exit path says *"click Run Locally in Studio Pro"*. Correct for crash
recovery, useless as a test precondition: it blocks every run on a human. Bring the stack up yourself
and only report a blocker if you cannot.

| Command | Use |
|---|---|
| `mxcli docker run` | setup, build and start in one |
| `mxcli docker status` | verify it is actually up — **do not infer "up" from the absence of an error** |
| `mxcli docker reload` | rebuild + hot reload after an exec |
| `mxcli docker down` | tear down |

> ### 🔴 Docker is NOT a safe default if the app calls host services by `localhost`
>
> **Confirmed the hard way, 2026-08-06, on the first real run of this skill.** Inside a container,
> `localhost` is **the container**, not your machine. Measured from `docker-mendix-1`:
>
> | From inside the container | Result |
> |---|---|
> | `http://localhost:3001/...` (the mock API) | **000 — unreachable** |
> | `http://host.docker.internal:3001/...` | **200** |
>
> The microflow hardcodes `'http://localhost:3001/api/mes/core/v1/routes'`, so under Docker the REST
> call never happens. The same applies to the OTel endpoint (`localhost:4318`).
>
> **How it presents — and why it is dangerous:** an empty grid *and* an empty span set. Every trace
> assertion would pass **vacuously** on zero spans, leaving only a row-count failure, which sends
> you debugging the page. The correct verdict is ***the run is invalid***, not *the feature failed*.
>
> **Before choosing Docker, check whether the app calls anything on the host** — a mock, a collector,
> a database, any integration. If it does and the URLs are hardcoded to `localhost`, either run
> against Studio Pro's local run instead, or parameterise those URLs to `host.docker.internal`
> (**a model write** — ask first). Do not "fix" the resulting emptiness in the test.

**Three more gotchas that will otherwise be diagnosed as feature bugs:**

- **Docker has its own database.** Data assertions and demo data must target the *Docker* DB, not the
  SP-local one. Assert against the wrong database and the result is meaningless in whichever
  direction it lands.
- **Do not trust a remembered port.** Measured 2026-08-06: Docker binds **8080** — the *same* port as
  SP's Run Locally, not 8081. (8081 appears in an old log line as `ApplicationRootUrl`; it is not a
  bound port.) A suite that hardcodes `APP_PORT ||= '8081'` then hits a dead port and it looks exactly
  like "the app is broken". **Do not hardcode and do not remember: measure.** `bin/test-stack-up.sh`
  resolves the port, proves the thing answering is *this project's* Mendix, and publishes the answer
  to `.claude/loop/stack.env` for every consumer to read.
- **The admin/OQL route works — no `psql` needed for the Data rung.** Measured 2026-08-06 on Mendix
  11.13 **under Docker**: `mxcli oql --direct` on admin port `runtime+10` (8090) with the project's
  own token returned a correct row count. `learned-db-assertions.md` now leads with this; if you meet
  an older copy claiming the token route "always returns 401" on 11.10+ and mandating `psql.exe`,
  that copy is stale — the randomisation is a property of one deployment's config, not of Mendix.

**Unit tests need more than this — they write to your model.** `mxcli test` generates a TestRunner
microflow, **injects it into the project**, **sets security OFF**, builds, restarts the runtime, then
restores. So: **ask before running it**, close Studio Pro, snapshot the `.mpr` first, and **verify
the restore afterwards** — a failed restore leaves the app with security off, which is the failure
nobody notices. Run `mxcli test --list` first: it parses without executing or writing, and catches
both §4 Unit defects for free.

---

## §6 — Prove the assertion can fail

**An assertion never observed failing is not evidence; it is an untested claim about your test code.**

| Part | Cheap positive control |
|---|---|
| UI | Point the landing guard at a page you did not navigate to — it must fail |
| Data | Run the assertion **before** the action — it must fail on the pre-state |
| Unit | Change an `@expect` to a wrong value — it must fail. Costs a second model write; run `--list` first. |
| Trace | Assert on a microflow that did not run — it must fail, *not* pass vacuously on an empty span set |

Run the control once when the suite is authored, and again whenever an assertion is rewritten.

---

## §7 — Reporting

Record **which parts ran**, so a later reader can tell "we checked the data landed" from "we checked
the integration actually fired".

```
Shape declared: UI + Data [+ Unit] [+ Trace]     actually run: <...>   (say so if they differ, and why)
UI:     <ran | n/a>  — landing guard on every nav: <y/n>   identity asserted: <y/n>   positive control: <passed>
Data:   <ran | n/a>  — delta-not-existence: <y/n>                                     positive control: <passed>
Unit:   <ran | n/a>  — --list count matches file: <y/n>    every @expect visible: <y/n>
Trace:  <ran | n/a>  — non-empty span check: <y/n>         activity granularity: <y/n>
Stack:  docker | sp-local, APP_URL=<url>, docker status verified: <y/n>
Invalid tests: <any §4 shape found — reported separately from feature failures, or "none">
```

**CE-error-free ≠ done. UI-green ≠ done.**
