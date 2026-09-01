# Handing a container-built model to a human — Studio Pro, a sandbox, a colleague

**Applies to:** any mxcli project whose model was built headlessly and now has to be opened,
run and demonstrated by a person — in Studio Pro, on a free Mendix Cloud sandbox, or by a
colleague who was not in the session that built it.

**Purpose:** a model that passes `mx check` with 0 errors is not a runnable app. Three
separate things must arrive for someone to see it work, and only one of them is in the `.mpr`.
This skill is the list of what the other two are and how they get there.

## The rule that shapes everything else

> **The model travels. The data and the runtime configuration do not.**

| What | Lives in | Travels with the model? |
|---|---|---|
| Entities, microflows, pages, security | `.mpr` + `mprcontents/` | **yes** |
| Demo data — the deals, the accounts, the evidence | database rows | no |
| Runtime configuration — API keys, an agent's bound model | database rows | no |

Everything below follows from that table. The failures it prevents all have the same shape:
the recipient opens the app, it builds, it runs, it renders — and it is empty, or mute, or
they cannot get past the login screen. Nothing errors. There is nothing to search for.

## 1. Pin the Studio Pro version, in writing

The model's version is in the `.mpr` and Studio Pro must match it **exactly** — not "the
latest 11.x". Say the number in the project's own README or run-book; the recipient cannot
guess it and a mismatch presents as a corrupt-looking project rather than a version error.

Check it: `./mxcli -p <project>.mpr -c "SHOW MODULES"` prints the version in its banner, or
read `mxcli docker build`'s first lines.

If the app uses the Agent Editor document types, the floor is Mendix **11.9+**; there is no
graceful degradation below it, the documents simply do not load.

## 2. Warn about the `.mpr` format switch BEFORE they run a build

`mxcli docker build` **consolidates** a split model — thousands of `mprcontents/*.mxunit`
files — into a single large `.mpr`. `bin/exec.sh` does not. So the first thing a recipient
sees after their first build is `git status` reporting **~2000 deletions and one enormous
modified binary**, which looks exactly like catastrophic damage and is not.

Two things belong in the project's run-book, not in someone's memory:

- consolidation is a **build artifact**: discard it (`git checkout -- <mpr> <mprcontents>/`),
  never commit it;
- model changes are made with `exec.sh`, which keeps the split form and therefore keeps the
  diff reviewable.

Measured on DealIQ (2026-09-01): 2049 units → one 43 MB file, twice, because the first
restore was undone by the next build. Whoever picks the project up will hit it on day one.

## 3. Put the demo identities on the login screen

If a tester has to grep MDL for a password, the handoff has already failed.

A demo app's login page should carry the personas as **one-click sign-in cards** — role, what
that role can see, and the credentials filled in on click. Not a README table: the screen
they are already looking at when the question occurs to them.

This matters more than it sounds. The recipient's first minute decides whether they explore
the app or file a bug against it, and "I cannot log in" is the cheapest possible way to lose
that minute.

## 4. Seeding is an ACTION, not a lifecycle event

An `AfterStartupMicroflow` that seeds demo data cannot be cleared, cannot be meaningfully
re-run, and gives the operator no control at all: the only lever is restarting the app.

Split it:

- **after-startup** keeps genuine runtime wiring — the things without which the app is broken
  and which nobody should have to ask for;
- **a Seed button** on an admin page creates the demo content, get-or-create so pressing it
  twice is a no-op;
- **a Wipe button** beside it clears that content.

Report through **state, not a dialog**: put a live count on the same card. Press Seed, watch
it go 0 → 5. A modal claiming "5 deals created" over a page still reading 0 is how a demo
surface starts lying, and MDL has no `show message` statement anyway.

## 5. A wipe must never delete the accounts

Where `Account` extends `Administration.Account`, **the accounts are the login users**.
A wipe that clears them locks the operator out of the app they just wiped, with no way back
short of dropping the database.

Wipe transactional demo content. Keep: accounts, teams, organisations, reference data the
seed reads back, and any API/agent configuration that is expensive to re-establish. Say what
survives **on the button's own caption** — the question in the mind of the person hovering
over it is "will I lose my login", and they should not have to find the answer in a comment.

Delete children before parents explicitly rather than relying on delete-behaviour: cascade
means the script's meaning depends on a domain-model setting somewhere else, and a changed
setting then leaves orphans silently.

## 6. Anything read from an environment variable needs a UI fallback

Config that a container supplies through env vars — API keys, endpoints — will not be there
in Studio Pro or on a free sandbox. If the only path is the env var, the feature is simply
dead for the recipient and the app cannot say why.

Every such value needs a second path: an admin page that accepts it by hand, and a startup
routine that reports what it found rather than assuming.

## 7. Runtime configuration that is not in the model at all

The hardest class, because nothing in the repository is missing and nothing errors.

The worked example: an **agent's bound deployed model**. The agent, its prompt, its tools and
its versions are all model documents that travel fine. The *binding to a deployed model* is a
database row, per environment, and the only supported place to set it is inside the agent
import dialog. A fresh deploy therefore comes up with a fully-configured agent that answers
nothing, and the sole visible symptom is a red banner on a page nobody opens.

Measured on DealIQ: 1 agent, 2 versions, 9 available models, **zero bindings**.

So the run-book must name, for each such value: what it is, that it does **not** travel, and
the exact UI path to re-establish it. Then put it on the admin surface as a live check —
"model bound: yes/no" — so the next person sees it before their demo rather than during.

## 7b. Or ship the database — but it and the encryption key travel as a PAIR

The obvious shortcut to everything in §4, §6 and §7 is to hand over the **database** rather
than the instructions for rebuilding its contents. The environment that built the app already
has the seeded data, the API keys and the agent's model binding, all of it in Postgres. A
`pg_dump` carries the lot, and the recipient points Studio Pro at that database instead of its
built-in one.

That genuinely works, and it is the fastest route to a demo-ready app. Two conditions, and the
first one is silent when you get it wrong.

**The dump alone is not enough — secrets are encrypted at rest.** Measured on DealIQ
(2026-09-01): `mxgenaiconnector$configuration.accesstoken` reads

    {AES3}<base64 ciphertext>    (111 chars)

That is the Encryption module's ciphertext, keyed on the `Encryption.EncryptionKey` constant.
On this project that constant lives in `app/.mxcli/constants.json`, which is **gitignored** —
correctly, it is a secret. So a database restored without the same encryption key gives you a
configuration page that looks fully populated and a connector that cannot decrypt a single
credential. The failure surfaces later, at call time, as an authentication error against a key
the UI is happily displaying as present.

So: **the dump and the encryption key move together, or neither moves.** Both are secrets;
neither goes in the repository. If the key cannot travel, do not ship the dump — re-enter the
credentials through the UI (§6) and re-bind the model (§7), which is slower and cannot fail
this way.

**And a dump is a secret in its own right.** It contains live bearer tokens and every demo
account's password hash. It is a file to hand over deliberately, not an artifact to leave in a
build directory or attach to an issue.

**When each route is right:**

| Route | Use when |
|---|---|
| Ship the dump + encryption key | the recipient must demo *today*, you can transfer two secrets safely, and their Studio Pro can point at Postgres |
| Ship the model + Seed button | anything else — a colleague on a different machine, a sandbox, a repo that has to stand on its own |

The second is the one worth engineering for, because it is the only one that works when you
are not there. The buttons in §4 exist precisely so that the answer to "how do I get data?" is
not "ask the person who built it for a database".

Note also that Studio Pro defaults to its own built-in database, so this route is a
configuration change on the recipient's side, not just a file transfer — the app's database
settings have to name the Postgres host, port and credentials before any of it applies.

## 8. A verification checklist short enough that people run it

Five lines, in the project's run-book, in order:

1. sign in as each persona from the login cards;
2. press Seed — the count moves;
3. open the main list — rows render;
4. exercise the one integration that depends on runtime config (ask the agent a question);
5. press Wipe, press Seed again — the app returns to a demo-ready state.

Anything longer gets skipped, and a skipped checklist is worth nothing.

## Related

| Skill | Why |
|---|---|
| `fixture-seeding.md` | deciding WHAT data a run needs; this skill is about the operator controls that create and clear it |
| `mendix-agent-setup.md` | the agent-specific half of §7 — credentials, model binding, and verifying an agent answers |
| `testing-shape.md` | the false-green register; "the model says so" is not "the screen shows so" |
| `tool-output-is-not-ground-truth.md` | why a clean `mx check` is not a working app |
