# Constants and secrets — decide the channel before you write the value

**Applies to:** any mxcli project
**Purpose:** for any value that differs between environments — an encryption key, an API base
URL, an integration username and password, a batch size, a feature toggle — decide **which
channel supplies it** before it is written anywhere, and make a value that is missing in a
deployed environment fail loudly instead of surfacing as a bug in an unrelated subsystem.

Companion instrument: `project-bin/constants-audit.sh` (installed as `bin/constants-audit.sh`).
It fetches the facts; this file is the judgement.

---

## The failure this exists to prevent

A Mendix build project on a free-node sandbox, 2026-09-16. The coaching agent on the deployed sandbox sat loading forever. The model
looked right, the three Mendix Cloud GenAI keys were valid, the app started clean. Pasting a
key by hand into the connector's own **Import key** dialog was refused with:

> For the key import to work, the Encryption module must be configured correctly. Contact your
> system administrator to make sure the Encryption key constant is set and has the right number
> of characters (32).

The cause was one constant: `Encryption.EncryptionKey`, shipped by its marketplace module as
`default ''`. MxGenAIConnector encrypts a key's access token while storing it, so the empty
constant blocked **every** route at once — Import key, Create key, and the startup microflow
that registers the keys. The error names *Encryption*; the symptom is in *GenAI*; half a day
went into "the Cloud GenAI resource pack must be missing".

Locally it had always worked, because the value came from `app/.mxcli/constants.json` —
gitignored, machine-local, invisible to a deployed environment and to every other clone.

**The whole defect is one sentence: nobody decided where that value comes from in a deployed
environment, so the answer was "nowhere", and the app said so in the wrong language.**

---

## Step 1 — The rule

> **No value that varies by environment is ever a literal in a microflow, a page, a Java action
> or a theme file. It is a constant, and the constant's channel is decided at the same moment
> the constant is created.**

What varies by environment, in practice (this is the list to sweep for, not a taxonomy):

| Kind | Examples | Almost always |
|---|---|---|
| Crypto material | `Encryption.EncryptionKey`, signing keys | **secret**, 32 chars exactly for Encryption |
| Integration credentials | API username, password, bearer token, client secret, API key | **secret** |
| Endpoints | REST base URL, OData service root, SMTP host, database of record | not secret, but always differs |
| Identity | mail-from address, environment name shown in the header, support URL | not secret |
| Behaviour | batch size, page size, timeouts, retry counts, feature toggles | not secret |

---

## Step 2 — The five channels, and which one wins

| # | Channel | Where it lives | Reaches a deployed cloud environment? |
|---|---|---|---|
| 1 | **Model default** | the constant itself, in the `.mpr`, in git and Team Server | **yes — and it is the only channel a free node has** |
| 2 | Per-configuration override | the `.mpr`'s configurations (`ALTER SETTINGS CONSTANT … IN CONFIGURATION …`) | no — Studio Pro / local runs only |
| 3 | Local constant store | `app/.mxcli/constants.json`, gitignored | no — the machine it is on, only |
| 4 | Runtime environment variable | `CONSTANTS_<MODULE>_<NAME>` | yes, wherever you control the container |
| 5 | Developer Portal constant | Environments → *env* → Constants | yes — **licensed nodes only** |

Later numbers win at runtime where they exist. Read that table as a hierarchy of *reach*, not
of preference: 1 reaches everywhere and is the least private; 5 is the most private and reaches
the fewest environments you will actually be standing in.

### The free-node rule — measured, not assumed

A Mendix **free / sandbox** environment has **no Constants tab at all**, and the Deploy API
does not offer a way in either: with a Personal Access Token, v4 returns **404** for both
`/api/v4/apps/{app}/environments/{env}/settings/constants` and `…/constants`, and v1 rejects a
PAT outright (`INVALID_CREDENTIALS`, HTTP 400). Verified 2026-09-16 against a live free node.

> **On a free node, channel 1 is the only channel. A constant with no model default is empty
> there, permanently, and no browser session, API call or agent can change that.**

So a demo or sandbox that must simply work is a deliberate decision to put working values in
the model — and to treat them as burned. Say so on the constant and in the register; do not
discover it later.

---

## The Mendix PAT — resolve it before you report it missing

The Personal Access Token is the one secret the *agent* needs rather than the app: marketplace
installs (`mxcli auth login`), the Deploy API, and Team Server push all take it. It is not a
constant and it has no channel table — it has a resolution ladder, and the ladder starts one rung
lower than most sessions start it.

> **Rung 0 — look in the environment:
> `env | grep -iE '^(MX_PAT|PAT|MENDIX_PAT)='`. Never tell the user a token is unavailable
> without having run that.**

`MX_PAT` is first because it is the name this toolkit's own convention stores the token under —
`platform-link.md` §"Create the token" says to keep it in `~/Mendix/.env` as `MX_PAT=…`. A ladder
that only knew `PAT`/`MENDIX_PAT` would miss a token stored exactly the way the toolkit told the
user to store it, and then report it missing — which is the failure this whole rung exists to
prevent, one level up.

Only if rung 0 comes back empty, ask — one batch, per `interview-protocol.md`, then stop:

| Rung | Ask the user to | Then |
|---|---|---|
| 1 | export it into the session environment (`MX_PAT=…`, the name `platform-link.md` prescribes) | nothing further — scripts that read `$MX_PAT` now work |
| 2 | configure it in Studio Pro / `mxcli auth login --token <PAT>` | it lands in `~/.mxcli/auth.json` (mode 0600); marketplace commands find it, platform scripts still need rung 1 or 3 |
| 3 | point at the file that already holds it | **wire it in** — see below |

**Rung 3 is only half done when they point.** A path named in chat is gone by the next session, so
the pointing is followed immediately by wiring: record the path in the project's gitignored env
file (`~/Mendix/.env` as `MX_PAT=`, or `.ts-sync.env` / `.docker/.env` — whatever that project
already sources), have the project's
platform wrapper source it, and say in the constants register which file holds it — the *path*,
never the value. A session that has to ask again has not finished this step.

**The failure this rung 0 exists to prevent (same project, 2026-09-17).** Mid-task, a session needed to
push a fix to Team Server, grepped `.docker/.env`, `.docker/.env.example` and `stack.env`, found
nothing, and told the user the token was gone and would have to be re-provided. It never ran
`env`, and it never tried `MX_PAT`. The token was in
the session environment the whole time; one `env | grep` would have returned it. The user's
correction was four words long. **Absence from the files you happened to grep is not absence.**

### Feeding it to git — `pat` is the username, the token is the password

Team Server (`https://git.api.mendix.com/<appId>.git`) authenticates with the **literal string
`pat` as the username** and the token as the password. An askpass helper that echoes `$PAT` for
every prompt sends the token as the *username* and fails with `Invalid username or password` —
which reads exactly like an expired token, and sends the next hour into re-issuing a perfectly
good one. The working helper answers the two prompts differently:

```bash
#!/usr/bin/env bash
case "$1" in
  *[Uu]sername*) echo "pat" ;;
  *[Pp]assword*) echo "$PAT" ;;
esac
```

Three rules hold wherever the token is used, and they are why a project keeps **one** wrapper
script (that project's `bin/platform/mx-platform.sh`) rather than an ad-hoc helper per session:

1. **Never in argv** — `ps` shows it to every process on the machine.
2. **Never in the remote URL** — git writes that verbatim into `.git/config` and every reflog entry.
3. **Never in a credential helper or any committed file** — that is the token on disk, permanently.

Do not print, echo or truncate the token to "check it" either: a permission classifier will refuse
it, and it should. Verify by *using* it; debug by reading the wrapper.

---

## Step 3 — Give every constant a default that tells the truth

Three defaults, three meanings. Pick on purpose:

| Default | Means | Use when |
|---|---|---|
| a real working value | "this is the value everywhere unless overridden" | non-secret config; **and** secrets on a demo whose only channel is the model (say it is burned) |
| `__SET_ME__` (or any obviously-wrong sentinel) | "every environment must override this" | a secret that must never ship — the app fails fast, naming *your* constant |
| `''` empty | "empty is a valid value here" | genuinely optional values, and nothing else |

**Never leave a required secret at `''`.** That is precisely how the free-node incident read as a
GenAI problem: an empty string is a legal value that downstream code accepts and then fails on,
several layers away, in someone else's error message. A sentinel fails at the first use, with
your constant's name in the message.

For `Encryption.EncryptionKey` specifically: **exactly 32 characters**. 31 or 33 fails at
runtime inside the same misleading error family.

---

## Step 4 — Write the decision down where the next session will read it

One file per project: `docs/constants-register.md`. It carries two things.

1. **A channel table** — which of the five channels this project actually uses, for what, with
   the local paths and env var names spelled out. Write what this project does; do not copy
   another project's table, which goes stale the day it scaffolds differently.
2. **One waiver line per accepted finding**, in exactly this form, anywhere in the file:

   ```
   Waived constant <Module.Name>: <reason>
   ```

   The audit reads those lines and reports `WAIVED` with the reason attached. A waiver is a
   decision on the record, not a mute button — if you cannot write the reason, you have not
   made the decision.

Record it on the constant too: `mxcli` keeps a constant's documentation, and that is the copy a
developer sees in Studio Pro without leaving the model.

---

## Step 5 — Run the audit, and read all four verdicts

```bash
bin/constants-audit.sh            # table + summary
bin/constants-audit.sh --json     # same data, machine-readable
```

It never prints a value — only `EMPTY` vs `SET`, the type, and the flags.

| Verdict | What it means | What to do |
|---|---|---|
| `CLIENT-SECRET` | a secret-named constant marked *exposed to client* — the value is served to every browser session | **fix; never waive.** No environment setting can hide it |
| `EMPTY` | no model default | fine on a licensed node whose Portal sets it; on a free node, in a Docker run, or in a fresh clone it is blank at runtime. Give it a value or a sentinel |
| `MODEL-SECRET` | a secret-named constant that does carry a model default | deliberate on a demo (the value is in git, Team Server and every clone — say "burned"); never right for anything holding real data |
| `WAIVED` | a finding with a register line | nothing — but re-read the reason at each stage gate |

**Completion criterion, with the denominator:** the run states the total (`N constants`) and
ends at **0 unwaived findings**. `WAIVED` is legal; silence is not — an audit nobody ran is not
a clean audit, and `EMPTY` is never green-by-absence.

**The secret test is a name heuristic, and it is a floor.** It matches `…Key`, `Secret`,
`Password`, `Pwd`, `Token`, `Credential`, `ApiKey`, `Passphrase`, `PrivateKey`. It therefore
over-reports (that project's `FeedbackModule.LocalStorageKey` is a browser bucket name, waived with
that reason) and it will miss a secret named `Foo`. The register, not the regex, is what makes
a classification real.

---

## When to run it

| Moment | Why |
|---|---|
| When adding any constant | the channel decision belongs at creation time, not at deploy time |
| After installing or updating any marketplace module | modules ship their own constants, usually as `default ''` — that is where the free-node defect came from |
| **Before any first deploy to a new environment**, and always before a free-node deploy | the one moment the free-node rule bites |
| At the build gate / module review | cheap, mechanical, and the register line is the artifact |

## Editing a marketplace module's constant

Setting a default on a constant owned by a marketplace module (as that project did to
`Encryption.EncryptionKey`, content 1011) is a **local modification**. `mxcli marketplace
update <id>` will report it and discard it. That is the desired behaviour, not a problem: it is
the prompt to re-decide the trade rather than carry it forward silently. Run `mxcli marketplace
diff <id> -p <app>.mpr` before any such update, and note the modification in the register.
