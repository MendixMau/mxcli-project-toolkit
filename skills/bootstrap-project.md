# Bootstrap Project — Generate a New Project's CLAUDE.md
**Applies to:** any mxcli project.
**Purpose:** Assemble a new mxcli-powered project's `CLAUDE.md` from this toolkit's standardized Baseline routing plus that project's own, genuinely project-specific facts — so a new project starts with the same discipline `IVM-MxCLI-main` had to retrofit, instead of discovering the gap after microflows already exist with no annotations.
**Companion skills:** `agent-roles.md` (the natural next step once `CLAUDE.md` exists — generates the project's `.claude/agents/{mdl,gate,test}-agent.md`).
**Source:** Written after finding `IVM-MxCLI-main`'s `CLAUDE.md` never routed to `learned-microflow-patterns.md` despite the toolkit having the rule — a gap that existed because nothing generated that project's routing table against a standard.

---

## When to Use This Skill

- Starting a brand-new mxcli-powered project (migration or greenfield) and setting up its `CLAUDE.md` for the first time
- Auditing an existing project's `CLAUDE.md` against the toolkit's current Baseline routing (run this whenever the toolkit's `git pull` brings in a newly-baseline-worthy skill)
- Someone says "review the toolkit and build the CLAUDE.md" — that instruction alone is not enough; this skill is what makes it repeatable instead of improvised

---

## Core Principle

**Two different sources, don't conflate them.** The Baseline routing table is standardized — copy it verbatim, don't rephrase it, don't selectively trim it. Everything else in a project's `CLAUDE.md` (source stack, mxcli invocation style, communication preferences, project paths) is **not** derivable from the toolkit at all — it has to come from asking the user or inspecting the actual project, every time, even if a similar project already has one. Never copy another project's `CLAUDE.md` as a shortcut starting point (see Anti-Patterns).

---

## Step 1: Gather Project-Specific Facts — Ask, Don't Assume

None of these live in the toolkit. Ask the user or check the project directly; don't infer from the project name or copy from memory of a different project:

| Fact | Why it matters | How to check |
|---|---|---|
| **mxcli invocation style** | Global binary (`mxcli`) vs. project-local (`./mxcli`) — get this wrong and every command in `CLAUDE.md` is wrong | `which mxcli`; check for a binary committed in the project root |
| **Source platform / stack** | Decides which situational skills apply (`source-os11.md` vs `source-java-spring-angular.md` vs none, if greenfield) | Ask the user, or run `source-triage.md` Step 1 if a migration is already underway |
| **mxbuild / Studio Pro setup** | Whether `mx check` needs `mxcli setup mxbuild` first, and which Studio Pro version | `mxcli setup mxbuild --help`, check `~/.mxcli/mxbuild/` |
| **Communication style preferences** | E.g. "never show raw MDL in chat, describe changes in plain language then execute silently" — genuinely project/client-specific, never assume the default | Ask the user directly |
| **Migration-input location** (migrations only) | Where BRDs/architecture docs from an upstream analysis project live | Ask the user; this is almost never the toolkit's own `pipelines/` output location |
| **Project/`.mpr` filename** | Every example command in the routing tables needs the real filename, not a placeholder | Check the project directory |

**If this is an audit of an existing project rather than a fresh bootstrap**, also diff its current `CLAUDE.md` against what Step 1 would produce today — stale facts (like a wrong mxcli invocation style) are exactly the kind of drift this step exists to catch.

---

## Step 2: Copy the Baseline Routing Table Verbatim

From this toolkit's `README.md` "Baseline routing" section, copy the table as-is into the new project's `CLAUDE.md`. Do not trim rows because "this project probably won't need X" — Baseline means it applies regardless of task, and the point of this step is removing that judgment call, not re-making it per project.

---

## Step 3: Select Situational Rows for This Project's Actual Stack

From the toolkit's `README.md` "When to use which skill" table, include only the rows relevant to the source stack confirmed in Step 1:

- **OutSystems source** → `source-os11.md`, `os-xml-schema.md`, `migrate-outsystems.md`, `pipelines/outsystems/`
- **Java/Spring + Angular source** → `source-java-spring-angular.md` (if it exists yet — see `migration-pipeline.md`'s companion list), `pipelines/java-angular/`
- **Any migration, regardless of source** → `migration-pipeline.md`, `source-triage.md` (also Baseline, but worth restating in context), `brd-generation.md`, `brd-validation.md`, `modularize-domain.md`, `architecture-blueprint.md`, `design-artifacts.md`, `brd-to-build-plan.md`, `iterative-build-loop.md`
- **Greenfield (no source migration at all)** → likely none of the migration-pipeline rows; the project probably only needs Baseline plus mxcli's own bundled `.ai-context/skills/` (which this toolkit doesn't own or duplicate)

Don't include a row "just in case" — an unused situational row is noise the same way an over-annotated microflow is noise (see `learned-microflow-patterns.md`).

---

## Step 4: Assemble and Get Sign-off Before Writing

Combine Steps 1–3 into the draft `CLAUDE.md`, then **show it to the user before writing the file** — this mirrors `modularize-domain.md`'s mandatory checkpoint, because getting the mxcli invocation style or communication style wrong here means every subsequent session inherits the mistake silently. Call out explicitly:

- Which facts came from Step 1 (so the user can correct any wrong assumption)
- Which situational rows you included and why, so an obviously-wrong stack guess gets caught immediately

Only write the file after confirmation.

---

## Step 5: Hand Off to `agent-roles.md`

Once `CLAUDE.md` exists and correctly routes to `learned-microflow-patterns.md`, the project is ready for `agent-roles.md` to generate `.claude/agents/{mdl,gate,test}-agent.md` — that skill's Step 1 ("read the target project first") now has a reliable `CLAUDE.md` to read.

---

## Anti-Patterns This Skill Prevents

- **Copying an existing project's `CLAUDE.md` as a starting template.** Carries over that project's stale, project-specific facts (the concrete case: `IVM-MxCLI-main`'s `CLAUDE.md` still says "mxcli is in the project root, use `./mxcli`" — wrong, it's a global binary — and that exact wrong instruction would silently propagate into any project bootstrapped from a copy of it).
- **Improvising the Baseline table from memory instead of copying it from the toolkit's README.** Reintroduces the inconsistency-across-projects problem "Baseline routing" was written to eliminate.
- **Including every situational skill "just in case."** Produces a `CLAUDE.md` nobody reads closely, the same failure mode as over-annotating a microflow.
- **Writing the file without a sign-off checkpoint.** A wrong mxcli invocation style or communication-style assumption baked into `CLAUDE.md` on day one is expensive precisely because every later session trusts it.
- **Treating this as a one-time-per-project skill.** Re-run Step 1–2 whenever the toolkit's Baseline table changes (a `git pull` brought in a new baseline-worthy skill) — an existing project's `CLAUDE.md` goes stale the same way `IVM-MxCLI-main`'s did.
