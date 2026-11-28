# Review checklists — what peer reviewers flag on Mendix changes, ranked by how often

**Applies to:** any mxcli project; reviewing a Mendix change (a branch, an MR, a worktree, the
last stage's output), whether you made it or someone else did. `change-review.md` is the process
that sends you here; this file is the standard it applies.
**Purpose:** the review standard, from evidence instead of taste. Every section below is ranked
by how often real reviewers raised it. Walk the sections the change touches, cite the section
in each finding.
**Source:** distilled from roughly 8,500 peer-review remarks across one Mendix organisation's
app teams (about a dozen product teams, several years of merge requests), contributed by Emre
Özhan Yigitbasi's cc-agent-harness, where these checklists are the standard of every agent
review run. The numbers in brackets are historical remark counts: they rank the checks, they are
not quotas. Company-specific rules (their design system, their tracker, their CI) stay in that
company's brain; what is here held across all of their teams.

## Which sections to walk

| The change touches | Walk |
|---|---|
| anything | **C** Correctness (always) · **S** Security (always, any hit is blocking) |
| names, new elements, refactors | **Q** Quality |
| pages, snippets, widgets, styling, user-facing text | **U** UI |
| retrieves, XPath, grids, loops, page-load or scheduled logic | **P** Performance |
| non-obvious behaviour, new branches or scenarios | **D** Docs and tests |
| constants, environment, dependencies, error paths | **L** Config and logging |
| a branch with merge commits from its base | **M** Merge hygiene |

Severity: **blocker** (wrong data, security hole, broken flow), **major** (a requirement not met,
a missing error path, an obvious performance trap), **minor** (quality, naming, docs), **nit**.

## C — Correctness and completeness (~3,000 remarks, the largest group)

1. **Functional bugs (937).** Trace every decision path, including `else`/default branches,
   against the requirement. Loop edge cases: empty list, off by one, an item processed twice, an
   object created but never advanced. A delete-and-recreate that loses associations or history an
   in-place change would have kept.
2. **Incomplete implementation (797).** Compare against every acceptance criterion, not the happy
   path. Scope creep counts too: entities or attributes changed beyond what was asked. An
   ambiguous requirement is flagged, not silently interpreted.
3. **Unclear logic (397).** A condition whose intent is not obvious from names gets simplified or
   annotated with *why*. Order of side effects: commit before anything that depends on the
   committed state (notify-before-commit is the classic).
4. **Unnecessary operations (242).** Commits inside loops, the same object retrieved twice, an
   association passed as a parameter when it is reachable, a check placed where it can never fire.
5. **Missing input validation (328).** Every externally triggered flow (published REST, form
   submit, scheduled import) validates before acting; values from headers, payloads and optional
   associations are null-checked before use.
6. **Missing error handling (275).** Call REST, web service, Java and JavaScript actions that can
   fail get an explicit error path. Inside a loop, extract the call into a sub-microflow so it can
   have one. *Prevents:* a failure that rolls back silently instead of reaching the user.

## S — Security and access (~460 remarks, lowest volume, highest severity)

1. **Missing access control (239).** Any entity, page or microflow reachable by more than one role
   has an explicit rule; a "check" sub-microflow is not a gate. **IDOR:** does the flow trust an
   object passed from the client, or verify the current user may touch that object? Terminal
   states (done, closed) usually become read-only. Anonymous users never reach private data:
   check entity access and page access together. A distinct anonymous role, not a reused
   authenticated one.
2. **Over-permissive access (219).** Read or write on attributes that should be hidden or read-only
   for that role. A role that can change an owner association can escalate itself. A
   `[%CurrentUser%]` compared against the wrong attribute silently grants everyone.

Report every plausible IDOR or exposure as a **blocker**, with the object and role it exposes.

## Q — Quality and maintainability (~3,000 remarks)

1. **Unused code (671).** Attributes, variables, parameters, modules the change left behind. A
   replaced integration is removed, not left dormant.
2. **Naming (468) and inconsistent naming (224).** After the last change, re-read every name the
   change touches against what it now does: flows, variables, return values, decision captions,
   referenced widgets. A flow's name covers its whole job; a returned flag names the outcome the
   caller acts on (`IsSuccessful`, not `IsStored`); a referenced widget gets a real name, not
   `textBox3`. A rename reaches captions, annotations and docs in the same change. One prefix
   convention per element category per module. *Field case:* in one agent-built story, names were
   the largest comment class (17 of 78) in every round.
3. **Simplification (463).** A sub-microflow that holds a single check rarely earns its
   indirection. An existing Java action or rule that already does the job beats new logic.
4. **Organisation (451).** Constants, mappings and enumerations in their own folders. UI sections
   in the order the user works.
5. **Duplication (228) and missed reuse (194).** Before accepting a new retrieve, validation or
   sub-microflow, search the model for one that exists (`SHOW REFERENCES`, the catalog).
   Near-identical pages or flows per entity type call for one parameterised version.
   *Prevents:* a fix applied to one copy and missing in its twin.
6. **Hardcoded values (142).** URLs, magic numbers, `IsProduction = true` inline instead of a
   constant; a closed set of strings instead of an enumeration.
7. **Domain model (101).** A boolean that really holds three states is an enumeration. A shared
   concept lives on the shared entity, not copied per account type.

## U — UI, design system, accessibility (~1,080 remarks)

1. **Inconsistent styling (373) and UI consistency (167).** The project's design-system classes
   (Atlas, or the company's own), not ad-hoc spacing; spacing and alignment match sibling elements
   on the same page; no second copy of a section that already exists; links and buttons behave the
   same everywhere (new tab or same tab, not mixed).
2. **Design-system compliance (162).** Replace a bespoke class where the design system has one;
   match the design spec, not "close enough"; the current component (Data grid 2) over the legacy
   one on new pages.
3. **Responsive (193).** Overflow, truncation and wrapping at small widths; cross-browser for CSS
   effects (Safari is the recurring one).
4. **Accessibility (105).** Meaningful alt text; heading order; tab and focus order that lands
   somewhere sensible; interactive elements not distinguished by colour alone.
5. **Missing translations (81).** Every new user-facing string (toasts, labels, captions, filter
   text) through the translation system, in every supported language.

What you cannot verify from the model (real rendering, a design-spec match) is listed under
*Not checked* for a human visual pass, never guessed. `module-review.md` stage 4 (LOOK) is the
in-build counterpart.

## P — Performance (~330 remarks)

1. **Redundant work (251).** The same object or list retrieved twice in one flow; a list retrieved
   only to count it; a heavy flow running once per row or widget instead of once per page; an
   index removed that another query still needs.
2. **Queries (81).** Grids paginate and filter in the query, not in memory. Retrieve over the
   association you need instead of fetching the parent first. Do not pass a value a retrieve
   could supply. State the data volume you assumed when you rate severity.

## D — Documentation and tests (~870 remarks)

1. **Missing documentation (574).** Non-obvious behaviour (side effects, workarounds, why this
   exists) is annotated on the element. A behaviour change support will be asked about is written
   down where they look. Stale docs are fixed or removed: they mislead more than none.
2. **Missing tests (263).** Every new branch, status or scenario has a test, not the happy path
   alone (both "created" and "already exists"). New UI actions carry a stable test hook (a
   `t-`-style class or name) so journeys can target them. A test that cannot be written yet is
   named as such, not skipped silently. `testing-shape.md` and `affected-tests.sh` say which
   tests this change owes.
3. **Missing metadata (33).** Hand-made changes carry date and author in the annotation; the
   tracked story carries its fix version.

## L — Configuration and logging (~450 remarks)

1. **Missing configuration (263).** Environment-dependent values (flags, timeouts, app
   registrations) verified against the target environment, not assumed from dev. A new JAR or
   library declared everywhere the project declares dependencies. Deployment-specific values as
   constants, not entity attributes. A value sent to another system checked against what that
   system expects. `learned-constants-and-secrets.md` for secrets.
2. **Missing logging (189).** Error paths log at `error`, not the default level. Debug-level
   `info` logs from development are lowered or removed before merge. A state transition other
   systems depend on emits its own event or log line. A possibly empty value sent downstream gets
   a defined fallback.

## M — Merge hygiene (after a non-trivial merge or rebase)

1. Both sides' changes are actually kept: a conflict resolved wholesale to one side can drop the
   other side's fix (one widget replacement ending as two, or none).
2. No orphans: documents one side deleted that the merge re-added.
3. No no-op "modified" documents: a unit that changed with no intended change pollutes the next
   diff; find out why. `mxcli diff-local` names the properties when MDL shows nothing.
4. Security conflicts get a manual pass with section **S** after resolution, never auto-resolved.
   `teamserver-alignment.md` covers the Team Server side.

## Completion criteria

- Sections walked, per the table: listed under *Standard applied* in the review.
- Every finding names its section and number (`C1`, `S1`, `Q2`…) and is specific enough to act on
  without asking the reviewer.
- 0 open security findings, or each one reported as a blocker with the exposed object and role.
