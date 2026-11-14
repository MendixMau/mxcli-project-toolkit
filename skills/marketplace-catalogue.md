# Marketplace catalogue — capability to standard component

**Applies to:** any mxcli project (Stage 3 fit-gap; Stage 5 before hand-building an integration)
**Purpose:** when a capability has a standard Mendix Marketplace component, the fit-gap names it
and either buys it or says why not. Read this while writing `architecture/fit-gap.md`
(`architecture-blueprint.md` Step 4), and again before scripting any capability in the table below
by hand.

## The failure this prevents

An unattended build skipped Stage 3: no `architecture/`, no fit-gap, and the intake's Marketplace
question stayed "Not yet asked". A sub-agent then built an LLM agent as a hand-written Java action
posting to a GenAI REST endpoint, while the project's own instructions named GenAI Commons, the
Mendix Cloud GenAI connector and Agent Commons. Nothing had compared the capability with the
Marketplace, so nothing stopped it. The hand-built version has no model configuration page, no
token accounting, no tool-calling contract and no upgrade path; replacing it costs the module.

## The rule

1. **One fit-gap row per capability the requirements name**, with a Verdict of exactly one of
   Native, Config, Buy, Build, Workaround or Gap (`architecture-blueprint.md` Step 4).
2. **For each row, look the capability up in the table below.** Listed there → the default verdict
   is **Buy**, with the package in backticks in the Mendix approach cell (the name `SHOW MODULES`
   will list; confirm it with `mxcli marketplace search "<name>"`).
3. **A Build (or Workaround) for a listed capability names the component and the reason**, in the
   row: `Marketplace: <component> not used because <reason>`. "Quicker to write" is not a reason;
   the "Build is acceptable when" column is.
4. **Not in the table is not "nothing exists".** Search the Marketplace for the capability anyway
   (`mxcli marketplace search "<capability>"`) and record what you found in the row.

`gate-check.sh <project> build-ready` reports (advisory for now, not counted as a FAIL) when
`architecture/fit-gap.md` is missing (not owed under `Build type: poc`), has no Verdict column, has a row with no recognised verdict, or has a Build for a capability
matched by `bin/lib/marketplace-catalogue.tsv` (this table's keywords) that names neither the
component nor the word "Marketplace". It checks only that the review was written; whether the
verdict is right is this skill's judgement and the Stage 3 sign-off's.
A Build row that hit a keyword by accident ("custom chart widget" matches `charts`) is not wrong: it passes once it carries a one-sentence `Marketplace: <component> not used because <reason>`.

Bad row (refused):

    | Triage summary by LLM | Java action posting to the chat completions endpoint | **Build** | quick |

Good rows:

    | Triage summary by LLM | `GenAICommons` + `MxGenAIConnector` | **Buy** | catalogue genai-llm |
    | Triage summary by LLM | Java action | **Build** | Marketplace: GenAI Commons not used because the app is pinned below the version it needs (PROJECT.md D-7) |

## The catalogue

Names are the Marketplace titles; the module name in backticks is what `SHOW MODULES` lists.
**"verify in Marketplace"** means the toolkit has not confirmed the exact module name, its current
version or its Mendix version floor: search for it before writing the Buy row, and never copy a
version number from here.

Names not verified against the live Marketplace; confirm each with `mxcli marketplace search` before relying on it.

| id | Capability | Component(s) | Use when | Build is acceptable when |
|---|---|---|---|---|
| genai-llm | LLM chat / completions, summarise, classify, extract from text | **GenAI Commons** (`GenAICommons`) + **Mendix Cloud GenAI connector** (`MxGenAIConnector`); for another provider its connector on GenAI Commons (OpenAI, Amazon Bedrock: verify in Marketplace) | any call to a language model | the app's Mendix version is below the modules' floor and cannot move; or the provider has no connector and wrapping it in GenAI Commons' interfaces is recorded as the Build |
| genai-agent | AI agents: tool / function calling, multi-step, MCP tools | **Agent Commons** (`AgentCommons`) on GenAI Commons; MCP Client for MCP tools (verify in Marketplace); `mendix-agents.md`, `mendix-agent-setup.md` | an LLM that calls microflows as tools, versioned prompts | as genai-llm |
| genai-knowledge | Embeddings, knowledge base, retrieval-augmented generation, semantic search | **Mendix Cloud GenAI connector** knowledge bases; **PgVector Knowledge Base** for a self-hosted PostgreSQL store (module name: verify in Marketplace) | grounding answers in the app's documents or data | never for the store itself; a custom chunking step is a Build row of its own |
| sso-oidc | SSO / OIDC / OAuth login, IdP groups to user roles | **OIDC SSO** (`OIDC`, needs **User Commons**); `multi-app-system.md` for role mapping | any external identity provider | SAML-only IdP: the SAML module (verify in Marketplace) |
| events-kafka | Events between apps, publish/subscribe, Kafka | **Business Events** (business event services in Studio Pro plus the Mendix Business Events module; verify in Marketplace); the Kafka connector for a non-Mendix Kafka topic (verify in Marketplace) | asynchronous app-to-app integration | a synchronous request/response is published REST, not events: that is a Native row |
| document-generation | PDF / document generation from a page | **Document Generation** (`DocumentGeneration`; check its rendering-service and Mendix version requirements: verify in Marketplace) | letters, statements, printable reports | the deployment cannot reach or host the rendering service, recorded as the reason |
| excel | Excel import / export | **Excel Importer** (`ExcelImporter`, with Mx Model Reflection); export: Excel Exporter / XLS Report (verify in Marketplace); newer import: Data Importer (verify in Marketplace) | users upload or download spreadsheets | CSV only: the platform's CSV handling or a small import mapping |
| encryption | Encrypting stored values, secrets at rest | **Encryption** (`Encryption`) | any attribute or constant that must be stored encrypted | never hand-roll cryptography |
| community-commons | General utilities (string, date, file, batch, run in separate transaction) | **Community Commons** (`CommunityCommons`) | before writing a Java action for a generic utility | the function is not in it: search its Java actions first |
| charts | Charts and dashboards | **Charts** (widgets; a widget-only package lands as `widgets/Charts.mpk`) | any bar, line, pie or time-series visual | one KPI tile: a Native text/badge row |
| email | Sending and receiving e-mail | **Email Connector** (verify in Marketplace) | any outgoing notification or mailbox read | the platform's notification channel already carries it |

Utilities with no keyword in the gate (community-commons) are still a fit-gap row when the build
needs them.

## Done when

- every capability the requirements name has a row (count the requirements' capabilities; the
  row count is not smaller), and
- every row whose capability is in the table above is Buy, or names the component and the reason,
  and
- `gate-check.sh <project> build-ready` prints `✓ Fit-gap` (not the advisory `⚠ Fit-gap`).

## Related

- `architecture-blueprint.md` Step 4 (the table format) and Step 7b D (the review of each Buy)
- `brd-to-build-plan.md` Step 0 (installing every confirmed Buy before the first domain-model script)
- `interview-protocol.md` (the Marketplace question's ASSUMED default in auto mode)
- `lint-rules/mxtk_ai001_genai_without_commons.star` (MXTK-AI001: an LLM endpoint in the model
  with no GenAI Commons)
