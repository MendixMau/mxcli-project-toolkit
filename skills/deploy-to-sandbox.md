# Promoting an app to a deployed sandbox

**Applies to:** any mxcli project with a cloud target (Mendix Free App Sandbox, licensed node, container)
**Purpose:** get a locally-working app *demonstrably* working on the deployment, and produce the
evidence before a customer is asked to test it.

## The failure this exists to prevent

> "Everything runs great locally."

That sentence is never evidence about a deployment, and the moment it is offered as a reason not to
test one, it is actively misleading. It was offered on a real project on 2026-09-16. When the e2e
suite was finally pointed at the sandbox for the first time, the very first journey said:

```
FAIL  demo.initiator  Initiator      0/6 []
FAIL  demo.approver   Approver       0/6 []
FAIL  demo.admin      Administrator  0/6 []
      MISSING (should see): Projects, Workflows, My approvals, Reports, Administration, Config
```

All six items were present. A second browser script that **polled** for the client to boot, instead
of sleeping a fixed 2500ms, read back all six from the same URL with the same credentials seconds
later. Three localhost assumptions were producing that, and **not one of them was about the app**:

| # | Assumption | What it reported |
|---|---|---|
| 1 | `waitForTimeout(2500)` after login, tuned to a warm local runtime | a correct app as 0/6 |
| 2 | an ownership guard reading a stale *local* port from `stack.env` | refused to run at all, exit 2 |
| 3 | journeys whose oracle is the *local database* | `DB read failed ... for PlantA` on a healthy app |

Had the app been handed over on the strength of "it runs great locally", every one of these would
have surfaced as the customer's first impression instead.

**The rule.** A deployment is untested until a test has run *against that URL*. Local green is a
prerequisite, never a substitute, and never a reason to skip.

## Step 1 — enumerate what the deployment does NOT have

Before touching the harness, list what the target lacks relative to localhost. Do not guess it;
read the platform's own docs and probe. For a Mendix **Free App Sandbox** the answer is large:

- **no M2EE admin API** (no DB oracle, no `oql`, no runtime introspection)
- **no environment constants / runtime settings UI** — constants are baked from Studio Pro
- **no deploy API, no pipeline** — deploys are Studio Pro only
- **no custom domain, no IP allowlist** — it is on the public internet
- **cold start**: first request after idle can take tens of seconds
- **one environment** — no separate test/acceptance

Each line is a harness assumption waiting to fire. Write the list down; it is the input to Steps 2–4.

Done when you can name, for every external thing your tests touch, whether the deployment has it.

## Step 2 — wait for readiness, never sleep for it

The single highest-yield fix. A remote runtime serves `index.html` long before it serves a rendered
UI, so any fixed sleep tuned locally is a coin flip remotely — and a longer sleep is not the answer,
because it is also wasted on every local run.

Poll for the thing you are actually waiting for. For Mendix that is **rendered widgets**, not text
length and not a URL:

```js
const ready = await page.evaluate(() => {
  const text = (document.body?.innerText || '').trim().length;
  const widgets = document.querySelectorAll('[class*="mx-name-"]').length;
  return text > 200 && widgets > 5;          // text alone is not enough: an error page has text
});
```

For the *remaining* fixed sleeps — the mid-journey ones that encode real knowledge about what the
app is doing at that moment — scale them in **one** place rather than editing each:

```js
const scale = /localhost|127\.0\.0\.1/.test(process.env.APP_URL || '') ? 1 : 3;
const orig = page.waitForTimeout.bind(page);
page.waitForTimeout = ms => orig(Math.round(ms * scale));
```

Only the unit was wrong, not the knowledge. On the 2026-09-16 project this was 148 sleeps across 14
files; the wrapper fixed all of them and left local behaviour byte-identical (scale 1).

Done when the readiness poll reports the *seconds it actually took* — that number is the evidence
for whether your scale factor is right, and a poll that never logs its duration cannot be tuned.

## Step 3 — audit every guard for a localhost premise

Guards written for a local stack encode local threat models. Re-read each one and ask what it is
actually protecting against remotely.

The worked example: a guard refused to run because `stack.env` said `:8080` was `unverified`. It
existed for an excellent measured reason — `:8080` had once belonged to *another project's* Mendix,
and every rung would have run against it happily. But that premise is **port ambiguity**, and a
named remote host has none: `<app>.mxapps.io` resolves to one deployment and cannot silently be
someone else's app on the same machine. The stale local port was blocking a remote run over a risk
that did not exist.

```js
const REMOTE_APP = /^https?:\/\//.test(process.env.APP_URL || '')
  && !/localhost|127\.0\.0\.1/.test(process.env.APP_URL);
if (REMOTE_APP) STACK.ownership = 'asserted-remote';
```

**Do not reach for the escape hatch instead.** That guard had an `ALLOW_UNVERIFIED_APP=1` override,
and using it would have "worked" — while teaching operators to keep the flag permanently on, which
disarms the guard exactly where it is real. Fix the premise; never normalise the bypass.

Done when every guard either fires for a reason true of the deployment, or explicitly recognises the
remote case. A guard you had to override to get a green run is a defect, not a green run.

## Step 4 — a skipped assertion is SKIPPED, never PASS

Some assertions genuinely cannot be made remotely — a DB oracle against a platform with no database
is not a timeout problem, it is impossible at any timeout. Two answers are tempting and both lie:

- **let it fail** → the journey reports the *app* as broken. (`DB read failed ... for PlantA`, on a
  healthy sandbox. This is the expensive kind of false finding: it sends someone to debug an app
  that works.)
- **skip it quietly** → the journey reports PASS having checked strictly less than it claims.
  Green-by-absence, the same defect the obligation check exists to prevent.

Use a distinct exit code and say it out loud:

```
0 PASS · 1 FINDING · 2 INSTRUMENT FAULT · 3 SKIPPED (not assertable here, and nobody pretended otherwise)
```

Carry the denominator into the summary, and state the interpretation rather than leaving it to be
inferred:

```
4 passed, 0 failed, 0 faulted, 8 skipped, of 12

SKIPPED is not PASS. 8 of 12 journeys assert against the deployed app not at
all; run those locally before calling a handover tested.
```

Done when the summary names how many of N were skipped, and a reader cannot mistake the run for full
coverage. `8 skipped of 12` is a handover conversation; `4 passed` alone is a claim that isn't true.

## Step 5 — verify the configuration the deployment holds, item by item

Constants, agent wiring, GenAI/LLM resources, secrets and connection strings are the most common
silent drift between local and deployed, because locally they come from a `.env` or a dev default
that simply does not exist on the target.

Build a config ledger — one row per setting, each with **how it is verified on the deployment**, and
verify through the running app, never by reading the model:

| Setting | Local source | Deployed source | Verified by |
|---|---|---|---|
| LLM text/embedding resource | env vars | constant baked from Studio Pro | ask the agent a question, read the reply text |
| knowledge-base connection | env vars | constant | ask a question only the KB can answer |
| external DB / graph credentials | `*.env`, gitignored | constant | a query returning a known count |
| SMTP relay + sender | local catch-all | constant | send one mail, confirm receipt |
| recipient override | non-empty in dev | **empty in production** | inspect a sent mail's To: |
| seeded demo users | seed script | same seed, shipped in the model | sign in as each role |

Two rules make this ledger real rather than decorative:

1. **Verify through behaviour, never through presence.** A constant holding a value proves nothing;
   the model being called proves it. Read the answer text back. An error card is also a chat bubble,
   and a green deploy log is not a working integration.
2. **A row with no verification column is not a row.** If you cannot say how a setting is checked on
   the deployment, it is unverified — record it as such rather than leaving it blank.

Done when every row has a verification that was actually run against the deployment, and rows that
could not be verified say so.

## Step 6 — one command, run before every handover

Package Steps 2–5 as a single script that takes the URL and prints the ledger. It must be one
command because a handover checklist that is six commands gets run once and then trusted forever.

```
APP_URL=https://<app>.mxapps.io/ DEMO_PASSWORD=… bin/sandbox-smoke.sh
```

Requirements: takes the target URL as input (never hardcodes it); reads credentials from the
environment (never from the script body); runs the *whole* set including the journeys that will
skip, so the denominator stays honest; exits non-zero on any FAIL or FAULT, and zero on skips alone
— because a skip is a known gap, while a failure is a surprise.

Done when the command has been run against the real deployment and its output is quoted in the
handover note. An instrument nobody has run is a claim, not a check.

## Step 7 — decide the handover shape from the evidence, not from the demo

The smoke result answers "does the deployment work". It does not answer "is this shareable". Before
handing a URL to a customer, check separately:

- **Credentials in the repo.** If handover includes source, any tracked secret must be rotated
  first — a secret in git history survives deleting the file. This is a rotation decision, not a
  deletion one.
- **Demo passwords on a public URL.** A seeded admin password committed in the model is fine on
  localhost and is a public administrative login on an internet-facing sandbox.
- **Tokens you cannot reissue.** If the only way to mint an API/MCP token is a script in somebody's
  scratch directory, the capability does not survive the session. Promote the issuer into the repo
  before it is part of a handover.
- **Known open defects.** Name them in the handover note with what the customer will see. A tester
  who hits a known bug nobody warned them about reports it as "the product is broken".

Done when the handover note states, in the customer's terms: what works, what is known-broken, and
what was not tested against this deployment at all.
