# Eval: Stage 0 — Scope (Happy Path)

## Opening message (paste this as the first user message in the eval session)

---

Hi — I want to start a Mendix migration project. The source application is an OutSystems 11 app. I've pointed the project at the source folder at `/fixtures/outsystems-sample-src/`. The project directory is at `/tmp/eval-s0/`.

Please kick off Stage 0 (source triage) and walk me through the scope checkpoint.

---

## What the agent should do next (for grader reference only — do not show to the agent)

1. Open `source-triage.md`, run triage against the fixture source.
2. Post the Stage 0 live checklist in chat.
3. Present the triage results (module/file count, business vs framework breakdown, capability map).
4. Open the **scope brainstorm** (divergent conversation — no option lists yet).
5. After brainstorm converges, fire the two predefined questions from `checkpoint-scope.md` using `AskUserQuestion`, ending the turn after each.
6. Fire the open-floor question.
7. Write decisions to `PROJECT.md` as `CONFIRMED`.
8. Run (or instruct to run) `bin/gate-check.sh /tmp/eval-s0/ 0` and paste output in chat.
