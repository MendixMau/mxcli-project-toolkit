# Mendix Agent Setup — credentials, model binding, and the proof it answers

**Applies to:** any mxcli project that ships GenAI agents (MxGenAIConnector + AgentCommons + ConversationalUI)
**Purpose:** stand up a project's agents in a fresh environment — import the MxCloud GenAI
resource keys, bind a deployed model to each agent version, index the knowledge base, and
verify each agent by making it answer a question. Most of this has no MDL, mxcli or SQL path
and is done by driving the **running app's UI with Playwright**; key import is the one
exception, and the section below says exactly what the headless route omits.

Completes the agent skill family: `mendix-agents.md` builds the agent, `mendix-agent-ui.md`
embeds the chat panel, **this skill makes the runtime actually answer**. Worked, battle-tested
driver scripts live in the TFC-TCXGraphPOC project (`tests/e2e/configure-genai.js`,
`import-agents.js`, `test-agents.js`, plus `.ai-context/skills/genai-configuration.md` with
the full app-specific detail); copy and adapt them rather than rewriting from scratch.

## Prerequisites — what you must be handed before starting

- **The MxCloud GenAI resource keys themselves** — base64-encoded JSON blobs, one per
  resource (text generation, embeddings, knowledge base). Typically issued from the Mendix
  Portal per app environment. Without them nothing below works; there is no anonymous mode.
- Supply them to the driver script via **environment variables only** (the TFC project uses
  `GenAIText`, `GenAIEmbed`, `GenAIKB`). **Never on argv** (argv is world-readable in
  `/proc`), never committed, and never screenshot the filled key textarea.
- A running app, and an **Administrator** login for it. Scripts must log out in a `finally`
  block — trial runtimes cap concurrent sessions, and a leaked slot makes the *next* run's
  correct password read as "Sign in failed".

## Why the UI is the usual path — and the one headless exception

Key import is **two** operations: write the `Configuration` row, **and** call the Mendix
GenAI backend to enumerate the models behind that key, writing one `MxCloudDeployedModel`
per model. Insert the row by hand — SQL, or a microflow that stops there — and you get the
first half without the second: a key with no models. The Models grid renders it as
configured, so the app *looks* right, and the failure surfaces much later as an agent that
returns nothing at chat time. Only the backend knows what the key entitles you to.

`ACT_ConfigurationStringImport_Save` does both, which is why the UI is the usual path.

**But there IS a supported headless path, and it is the right one for a container that must
configure itself with no human.** `MxGenAIConnector.Configuration_RegisterByString` takes the
base64 key string and its own documentation says *"Can be used in microflows, for instance
After Startup."* It does reach the backend — the stack trace when it fails names
`Configuration_ModelDetails_GET` ← `Configuration_CreateFromConfigurationImport` ←
`Configuration_RegisterByString`.

**What it does not do is create the `MxCloudDeployedModel` rows.** Call it alone and you land
in exactly the signature failure above. You have to run the rest yourself, which is the body
of `ACT_Configuration_Sync` minus its final `show message` (a page activity cannot run in an
after-startup microflow):

```
Configuration_ModelDetails_GET(Configuration)          -> List of ModelDetails
  Configuration_CreateSetAndCommitMxCloudDeployedModel(Configuration, ModelDetailsList)
  Configuration_AddEmbeddingsModel(Configuration, MxCloudDeployedModel)
  Configuration_UpdateIsCreatedInStudioPro(Configuration, MxCloudDeployedModel)
```

Measured 2026-08-31 (DealIQ): three keys registered from environment variables at startup
produced 4 `Configuration` rows and **0** `DeployedModel` rows until that sequence was added;
with it, 9 deployed models — eight text plus one embeddings — read back by OQL.

So: **use the UI when a human is configuring an environment; use the headless path when a
fresh container must come up unattended.** Either way, step 2 below is the check that
matters, and neither path can skip it.

The same asymmetry holds on the agent side: the **only** place a deployed model is bound to
an agent version is dialog 2 of the agent-import flow ("Check Agent settings after import" →
"Model for the selected version"). Agent import is the second half of GenAI configuration,
not a bulk loader — re-importing an existing agent is a no-op on the object (matched by UUID)
and exists to *reach that dialog*.

## Order of operations — and the two steps people skip

1. **Import keys** — must come back **with models**. Exit non-zero on a dialog matching
   `no models could be retrieved`; a green grid with an empty "Available models" column is
   the same finding.
2. **Verify models landed**: `genaicommons$deployedmodel` has rows. `deployedmodel=0` with a
   populated `mxgenaiconnector$configuration` table is *the* signature failure.
3. **Import/bind agents** — per agent, dialog 2's model combobox must be non-empty. An empty
   combobox always means step 1 really failed; click **Not now**, never Confirm an empty
   binding.
4. **Make every agent answer a question.** Steps 1 and 3 both run cleanly end to end against
   an app whose agents cannot answer anything. Nothing counts as configured until an answer
   has rendered.

## Verification judgement — the traps, each one paid for

- **Two signals decide "active", and you need both:** the Model combobox is non-empty AND
  the chat container is not disabled. The disabled class tracks *test-run* state, not model
  binding — on a fresh page it is routinely absent while Model is blank, so a check on the
  chat container alone reports a broken agent as ready.
- **An `Error` bubble is a reportable outcome, not "still thinking".** The round-trip
  happened and the agent could not serve it. Never let it time out silently into "no answer".
- **Do not read the answer the instant the message count grows** — the bubble exists before
  tokens stream in, and you will fail a healthy agent on an empty string. Poll until the text
  stops changing.
- **Answers can exceed 60s** for tool-using agents, and 120s is not enough either. An
  agentic turn is a model call, a tool execution, and a SECOND model call. Measured
  2026-08-31: the tool finished at +76s and the settled answer landed after a 120s window had
  already closed, so the run reported "the agent did not reach our data" about a turn that
  reached it perfectly. **Default the answer timeout to 300s**, and before trusting any
  SILENT verdict, check `conversationalui$message` for an assistant row that landed after the
  window — `Success` late means only your timeout was wrong.
- **Poll on message STATUS, not on the text settling.** ConversationalUI writes the assistant
  row immediately with `Status = Loading` and fills the content in when the model returns, so
  "an assistant row exists" is true long before there is anything to read. Waiting for
  `Status <> 'Loading'` is exact and cheaper than watching for the text to stop changing.
- **Tool names must match `^[a-zA-Z]\w*$`** (the converse API validates every
  `toolSpec.name`). Both `AgentCommons.Tool.Name` and **`KnowledgeBase.Name`** feed that
  field — an attached KB is sent as a retrieval tool under its machine `Name`, not its
  `DisplayTitle`. A KB named with spaces 400s *every* completion for that agent while the
  agent reads fully active. Fix it in the microflow that creates the KB (valid name on
  create + a self-heal rename branch), not in the UI (blocked for non-draft versions).
- **Duplicate tool names 400 the same way** (`The tool X is already defined at
  toolConfig.tools.N`). The classic source is a startup "repair" microflow that
  `Tool_Create`s unconditionally on every boot — repair routines must check-then-create,
  never create-always. The UI offers no tool delete, so existing duplicates need one scoped
  SQL cleanup, after which the idempotent repair keeps it clean.
- **Key import is NOT idempotent, on either path, whatever the documentation says.**
  `Configuration_RegisterByString` documents itself as *"Overwrites an existing configuration
  with the same ID"*. It does not. Measured across four boots of one app: 4 → 15
  `Configuration` rows carrying the same THREE `ConfigurationID`s. `DeployedModel` stayed at
  9 the whole time (those dedupe on Configuration+Model), so nothing visibly broke and the
  count grew unnoticed — the only way to see it is to boot twice and count rows. Guard the
  startup path on *"does a DeployedModel already exist"* rather than trusting the overwrite,
  and leave key rotation to a deliberate re-import by someone who knows the key changed.
- **Cleaning up stacked configurations: the two shapes differ.** Text and Embeddings
  duplicates are empty siblings of one row that owns the models — drop the siblings. But each
  Knowledge Base duplicate owns its **own** `MxCloudKnowledgeBaseResource`, and while the
  join table cascades on `Configuration` delete, the resource row does not: deleting configs
  alone leaves orphaned resources, invisible until something retrieves one and finds no key.
  Delete the resources first. Note also that the Mendix association column is
  `<module>$<entity>id`, not `<module>$<entity>` — get that wrong and the DELETE matches
  nothing and reports a successful cleanup.
- **Idempotency guards must scrape what is actually rendered.** DataGrid2 matches neither
  `td` nor `[role="gridcell"]`, and a key on an unopened tab is not in the DOM at all — a
  guard that misses re-imports keys the grid visibly lists, stacking duplicate
  `Configuration` rows that only SQL can remove (the config page has no delete affordance).
- **Do not assert on `mxcli oql` output.** It renders a fixed-width table and TRUNCATES long
  cells, so a correct answer arrives as `Your least ready deal is **ABB Partne...` and every
  substring check against the expected value fails. Measured 2026-08-31: three consecutive
  runs reported that the agent had not reached the app's data, about an answer that named the
  right record. Use OQL for counts and existence; read any content you intend to assert on
  with `psql -tAf` (a file, not `-c` through `su -c "..."` — Mendix table names contain a
  literal `$` and three layers of shell quoting will eat it silently).
- **Playwright mechanics:** `page.click()` is routinely intercepted (nav flyouts overlapped
  by grids; every modal's `.mx-underlay`) — fire the DOM click inside `page.evaluate()`.
  Message dialogs stack on top of the popup that raised them; drain them, and *keep the
  text* — it is the most important signal the run produces. A failed import popup does not
  self-close; cancel it explicitly.

## Environment-specific: sandboxed/proxied containers

Everything in this section is about restricted-egress environments (e.g. a cloud agent
container behind a mandatory proxy). Skip it on a normal workstation.

- **MxGenAIConnector's HTTP client does not honour Java's system proxy properties.** The JVM
  can have `-Dhttps.proxyHost` configured and logged, and the connector still opens its own
  direct socket — which a default-deny gateway 403s (`Host not in allowlist: …`) no matter
  what the allowlist says. Worse, there is no HTTP response to report, so the connector logs
  its own error with nothing after the colon:
  `Something went wrong while attempting to retrieve model information from the backend:`
  A failing call here says nothing about the credential — check it with `curl` before
  suspecting the key.

- **Try the runtime's own proxy settings FIRST.** Mendix has `http.proxyHost` /
  `http.proxyPort` as *runtime settings*, which is a different mechanism from JVM system
  properties and is the one its HTTP client actually reads. On a PAD they are overridable
  from the environment, and the package documents them itself in
  `etc/constants/variables.conf`:

  ```bash
  export RUNTIME_PARAMS_HTTP_PROXYHOST=127.0.0.1
  export RUNTIME_PARAMS_HTTP_PROXYPORT=39493      # parse from $HTTPS_PROXY, never hardcode
  ```

  Measured 2026-08-31 (DealIQ): two exported variables, worked on the first boot — the model
  list came back and nine `DeployedModel` rows landed. No shim, no `/etc/hosts`.

- **The loopback shim is the fallback, not the default.** Where the runtime settings are not
  reachable — an embedded runtime, a host you cannot pass environment variables to — the
  workaround class is a shim: one local listener per backend host, splicing each connection
  into a `CONNECT` tunnel on the real proxy, plus `/etc/hosts` entries. It is a lot of moving
  parts for something two variables usually solve, so reach for it only after the above
  fails. TLS still terminates at the proxy with its CA in the JVM truststore — never disable
  TLS verification.
- **The proxy port is not stable across container recycles.** Anything that captured it at
  startup (the shim, the app's runtime settings) silently tunnels into nothing after a
  recycle. Read the proxy from the live environment at every start, and verify the port in
  the startup log matches `$HTTPS_PROXY` before booting the app.
- After a recycle, restore in order: database up → hosts entries → shim (passing
  `HTTPS_PROXY` through `sudo` explicitly) → probe the backend host (expect 401, meaning
  *reached and challenged*) → then boot the app.
- Failure signatures in `runtime.log` while this is broken: the 403 allowlist message,
  `DeployedModel is required`, `EmbeddingsResponse was empty`. Do not "fix" any of them by
  inserting model rows by hand.

## Related skills

| Skill | Why |
|---|---|
| `mendix-agents.md` | building the agent itself — runtime data, not model documents |
| `mendix-agent-ui.md` | embedding the ConversationalUI chat panel |
| `testing-shape.md` | the false-green register these verification rules extend |
| `tool-output-is-not-ground-truth.md` | why an exit code from these scripts is not yet a finding |
