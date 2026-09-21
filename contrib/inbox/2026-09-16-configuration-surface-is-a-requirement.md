# "Read it from the environment" is only a design if the environment can be written to — a deployment tier was chosen at stage 0 and silently deleted a configuration mechanism the whole app depended on

**From:** Maurits Visser, from a MOC/PSSR app replacement
**Date:** 2026-09-16
**Kind:** learning / process
**Field evidence:** confirmed on a real deployment, not a hypothesis. Four configuration
routes probed to exhaustion over roughly a day; verbatim results below.
**Proposed target:** `skills/architecture-blueprint.md` (the NFR / deployment section — the
question belongs at architecture time, not at deploy time), with a pointer from whatever
stage first names a target environment. Possibly also a short `skills/` file on
deployment-target capability, since this is judgement, not a script.

---

## What happened

The app's graph-integration credentials were designed to come from environment variables,
with model constants left deliberately empty. That is the textbook answer, it survived
design review, and it is written up as a numbered decision in the project's own docs.

Then the app was deployed to a **Mendix free sandbox**, and a free sandbox has no
configuration surface at all. Not a restricted one — none. Four routes, all probed:

| Route | Result |
|---|---|
| Developer Portal, free app | there is no constants / environment-variables tab |
| Deploy API v4 | 24 environment sub-resources probed — **every one 404**. v4 has no constants endpoint and no lifecycle endpoints |
| Deploy API v1 `/environments/{Mode}/settings` | the endpoint exists, but it is a **licensed-node** API. It rejects Personal Access Tokens by design; four auth-header combinations tried. A full-rights API key authenticates and the call still does not apply |
| the app's own `/xas/` protocol | reaches app *data*, never platform *configuration* |

A fifth route — driving the portal with Playwright — is blocked by corporate SSO with MFA
and is not drivable headlessly.

So the mechanism the architecture depended on did not exist on the target, and the app
shipped a runtime guard saying so instead of working.

## The finding

> **A configuration mechanism is a requirement on the deployment target, not a free choice
> of the designer.**

The cost is not that the design was wrong — it was right for a licensed environment, and it
still is. The cost is that nobody checked, and the check was trivially available: the very
first `GET /apps/{id}` response we ever made, days earlier, contained
`"licenseType": "free"` and `"planName": "free"`. The fact was in hand the whole time and
nothing in the process asked for it.

## The fix that shipped, for the record

Give the constants **model defaults** — the only value a free sandbox reads — and leave the
fallback chain alone. The project's `JA_Env` java action reads `System.getenv(Name)` first
and returns the constant `Fallback` only when the variable is absent or blank, so the same
binary runs correctly on the free sandbox *and* on a licensed environment with no model
change. That property is what made the late reversal cheap: the design was not undone, only
given a floor.

The trade-off is real and must be stated in the artifact rather than left for a reader to
discover: a constant default lives in the `.mpr`, so the value is in git, on Team Server,
and inside every deployment package. That is acceptable for a demo service account on a
demo endpoint, on a private repo, and it is not acceptable for anything else.

## A factual error this corrected, worth carrying into the toolkit

Two places in the project's own docs told the reader to *"mark this constant as a password
in Studio Pro"*. **Mendix has no such property.** A constant has Name, Type, Default Value,
Documentation, Export Level and Exposed to Client, and nothing marks one as secret. Hiding a
credential from users is **attribute-level entity access** — the way `MxGenAIConnector`'s
`Configuration` entity omits `AccessToken` from its read grant — not a constant property.
The instruction had been in the repo for weeks and had been followed by nobody because it
could not be followed.

## Proposed toolkit change

1. **An environment-capability question at architecture time**, in the same batch as the
   other NFR questions: *what environment does this deploy to, what tier is it, and what can
   be configured on it after deploy — constants, environment variables, scheduled events,
   certificates?* The answer changes the design of every secret, every endpoint URL and
   every feature flag in the app. It is judgement, so per `skills-over-scripts.md` it is a
   skill question, not a script.
2. **A mechanical probe to answer it**, since the platform will tell you: one call to
   `/apps/{id}` returns `licenseType` and `planName`, and that is enough to route to "this
   target can be configured" or "this target cannot". Cheap enough to run at stage 0 and at
   every deploy.
3. **A default-plus-override pattern as the recommended shape for any externalised value**,
   rather than environment-only. Environment-only is strictly worse: it is the same design
   plus a failure mode on every target that cannot be configured, and the floor costs one
   fallback parameter.

## Also available for promotion: a headless `/xas/` driver

Reverse-engineering the Mendix client protocol to drive a deployed app without a browser
took most of a day and produced a reusable asset (`tools/xas/` in that project — session
sequence, the `params.version: 2` requirement on the second `get_session_data`, the fact
that HTTP 560 is the opaque catch-all and that verdicts live in `instructions[]` rather than
`.message`). It is genuinely generic — it reads no source, knows nothing about this app —
and every project that needs to poke a deployed Mendix app headlessly will otherwise pay the
same day. Say the word and I will prepare it as a proper contribution rather than an inbox
note; it needs the field-proof bar (two layouts, two platforms, a cited field run).
