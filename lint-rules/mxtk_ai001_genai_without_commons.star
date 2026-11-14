# mxtk-lint-rule: mxtk_ai001_genai_without_commons
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# MXTK-AI001: An LLM / GenAI endpoint called from the app's own code, with no GenAI Commons
#
# A language-model call belongs on the Marketplace GenAI stack: GenAI Commons + the Mendix Cloud
# GenAI connector (or another provider's connector on GenAI Commons), plus Agent Commons for an
# agent (skills/marketplace-catalogue.md, entries genai-llm / genai-agent / genai-knowledge).
# A hand-built call has no model configuration, no token accounting, no tool-calling contract and
# no upgrade path. Real failure: an unattended build skipped the Stage 3 fit-gap and wrote the
# agent as a Java action posting to a GenAI REST endpoint, though the project's instructions
# named the Marketplace modules.
#
# What it reads, in the app's own modules (every accessor below skips Marketplace modules, so a
# Marketplace connector's own endpoints are never flagged):
#   constants()        name, default value, description
#   constant_values()  per-configuration overrides of a constant's value
#   rest_clients()     consumed REST services: name, base URL, documentation
#   rest_operations()  consumed REST operations: name and path (/converse, /chat/completions)
#   java_actions()     name and documentation
#   jar_dependencies() Maven coordinates (an OpenAI / Anthropic / Bedrock runtime SDK)
# NOT read: the Java source behind a Java action (the catalog does not index it), and URLs typed
# into a microflow's REST call activity (not in the activity projection). A literal URL there,
# with no constant, is invisible to this rule; module-review.md covers it by reading.
#
# GenAI Commons present = a module named in GENAI_MODULES appears in modules() (imported from a
# file, Source empty) or in module_dependencies() (any Marketplace module that references or is
# referenced; read 2026-11-13 on mxcli 0.31.0: the graph lists Marketplace modules, modules()
# does not). Present -> nothing is reported: the stack is there and the review is a person's.
#
# Self-check: LLM evidence found, and module_dependencies() is empty while the app has modules,
# means the module graph was not built and presence cannot be told; the rule says so (`_rule`)
# instead of guessing either way.

RULE_ID = "MXTK-AI001"
RULE_NAME = "GenAIWithoutCommons"
DESCRIPTION = "LLM / GenAI endpoint called from the app's own code while GenAI Commons is absent"
CATEGORY = "architecture"
SEVERITY = "warning"

REQUIRES = ["full"]

GENAI_MODULES = ("GenAICommons", "MxGenAIConnector", "AgentCommons")

# Go RE2 via matches(). Endpoint paths and hostnames first; the bare words last and bounded, so
# "MxGenAIConnector" or "Algorithm" never match on a substring.
LLM_PATTERN = "(?i)(/converse(-stream)?([^a-z]|$)|chat/completions|/v1/completions|/v1/messages|/v1/responses|/v1/embeddings|bedrock-runtime|generativelanguage\\.googleapis|api\\.openai\\.com|api\\.anthropic\\.com|openai\\.azure\\.com|(^|[^a-z])(genai|gen-ai|openai|anthropic|llm|langchain4j)([^a-z]|$))"

# Case-sensitive, for camel-case names the bounded words above cannot see: OpenAIApiKey,
# AnthropicKey, JA_CallLlm, GenAIEndpoint. GENAI_MODULES names are removed from the text first.
CAMEL_PATTERN = "(^|[^A-Za-z]|[a-z])(GenAI|GenAi|OpenAI|OpenAi|Anthropic|Llm|LLM)([^a-z]|$)"


def _hit(*texts):
    for t in texts:
        if not t:
            continue
        for m in GENAI_MODULES:
            t = t.replace(m, " ")
        if matches(t, LLM_PATTERN) or matches(t, CAMEL_PATTERN):
            return True
    return False


def check():
    present = False
    app_modules = 0
    for m in modules():
        app_modules += 1
        if m.name in GENAI_MODULES:
            present = True
    deps = 0
    for d in module_dependencies():
        deps += 1
        if d.source_module in GENAI_MODULES or d.target_module in GENAI_MODULES:
            present = True
    if present:
        return []

    hits = []  # (module, document_type, name, what)
    for c in constants():
        if _hit(c.name, c.default_value, c.description):
            hits.append((c.module_name, "Constant", c.qualified_name, "constant"))
    for v in constant_values():
        if _hit(v.value):
            mod = v.constant.split(".")[0] if "." in v.constant else ""
            hits.append((mod, "Constant", v.constant, "constant value in configuration '{}'".format(v.configuration)))
    for r in rest_clients():
        if _hit(r.name, r.base_url, r.documentation):
            hits.append((r.module_name, "ConsumedRestService", r.qualified_name, "consumed REST service"))
    for o in rest_operations():
        if _hit(o.name, o.path):
            hits.append((o.module_name, "ConsumedRestService", o.service_qualified_name, "REST operation '{}' {}".format(o.name, o.path)))
    for j in java_actions():
        if _hit(j.name, j.documentation):
            hits.append((j.module_name, "JavaAction", j.qualified_name, "Java action"))
    for j in jar_dependencies():
        if _hit(j.group_id, j.artifact_id, j.coordinate):
            hits.append((j.module_name, "Module", j.module_name, "Java dependency {}".format(j.coordinate or (j.group_id + ":" + j.artifact_id))))

    if not hits:
        return []

    if deps == 0 and app_modules > 0:
        return [violation(
            message="MXTK-AI001 found {} LLM/GenAI reference(s) (first: {} {}) but the module graph is empty, so it cannot tell whether GenAI Commons is installed. This rule decided NOTHING.".format(len(hits), hits[0][3], hits[0][2]),
            location=location(module="_rule", document_type="Module", document_name="MXTK-AI001"),
            suggestion="Run `REFRESH CATALOG FULL` so the module graph is built, then lint again.",
        )]

    out = []
    seen = {}
    for mod, dtype, name, what in hits:
        key = dtype + "|" + name
        if key in seen:
            continue
        seen[key] = True
        out.append(violation(
            message="{} {} calls an LLM/GenAI endpoint from the app's own code, and GenAI Commons is not in the project.".format(what[0].upper() + what[1:], name),
            location=location(module=mod or "_unknown", document_type=dtype, document_name=name),
            suggestion="Use the Marketplace GenAI stack (GenAI Commons + Mendix Cloud GenAI connector, Agent Commons for agents) per skills/marketplace-catalogue.md; or record in architecture/fit-gap.md why not (\"Marketplace: GenAI Commons not used because ...\") and switch this rule off for the project as a user decision (lint-rules/README.md, \"Opting out of a rule\").",
        ))
    return out
