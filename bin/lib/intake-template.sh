#!/usr/bin/env bash
# intake-template.sh — THE intake.md template. One copy, sourced by both writers.
#
# WHY THIS FILE EXISTS. bin/init-project.sh WRITES intake.md and bin/sync-project.sh REPAIRS
# it, so both need to know what the current template says. That was two copies, kept in step
# by a comment reading "MUST stay byte-identical to Q9 in bin/init-project.sh's intake heredoc"
# — the same arrangement that let bin/lib/skill-routing.tsv and bin/lib/install-manifest.sh
# exist, and for the same reason: hand-kept copies drift, and the drift is silent because both
# halves still look right on their own. sync's copy of Q9 carrying a false-green marker after
# init's was fixed is exactly that failure, one commit wide.
#
# Q9 STAYS AT NUMBER 9, with its exact heading. "## 9." is hardcoded as the locator for the
# interview-mode question in gate-check.sh, sync-project.sh and four places across tests/wave2/.
# Renumber it and sync stops finding it, concludes it is missing, and appends a SECOND copy.
# Add new questions at 1-8, or after 9; never renumber 9.
#
# NO ANSWER MARKERS in the bodies. "_Not yet asked._" normalises (check_stage_P strips leading
# [ \t>*_-]) to something matching no marker branch, so a fresh scaffold FAILS Stage P naming
# every section. "Unverified — how to verify: ..." is a legitimate ANSWER — the question was
# asked, the answer is pending — and putting it in the template made the generator manufacture
# the gate's own pass condition. See init-project.sh's comment above the intake block.

# The full template body, exactly as init-project.sh writes it.
mxtk_intake_template() {
  cat <<'MXTK_INTAKE_EOF'
# intake.md — Stage P Kickoff Interview

Replace each "_Not yet asked._" line below with a real answer, in one of two forms:

  Answered (CONFIRMED): ...          the question was asked and answered
  Unverified — how to verify: ...    the question WAS asked, the answer is not known yet,
                                     and this line says how it will be established

Both forms pass gate-check's Stage P. "_Not yet asked._" passes nothing, deliberately: this
file is generated before the interview happens, and a scaffold must never be able to certify
an interview that never took place. Per conversion-runbook.md's interview protocol, every
question is asked in chat and the turn ends to wait for the answer; unknowns the user hands
back ("you decide") are recorded as ASSUMED in PROJECT.md rather than blocking Stage P.

**These are the questions only the human can answer.** Anything derivable — where the source
sits, what documents exist, which Mendix version the .mpr targets, whether prior analysis is
present — is the agent's homework, brought back as "I found X, confirm?" rather than asked
here. Do that homework FIRST: it is what turns each question below into a recommendation
with evidence instead of a blank prompt.

## 1. Entry mode: migration, requirements-driven, or greenfield?

_Not yet asked._ The agent proposes with evidence and the user confirms — never a silent
inference (conversion-runbook.md "Entry Modes"; classification rules apply in order, first
match wins: any legacy source → migration; else any specs/BRDs/wireframes →
requirements-driven; else greenfield). Auditing or regression-testing an app nobody is
rebuilding is not a mode at all — that routes to existing-app-assurance.md and skips the
pipeline. Getting this wrong skips whole stages: real misrouting, 2026-07-14.

## 2. What is this project, and what is driving it?

_Not yet asked._ Sets stakes, urgency and the default for Q3 in one answer. (a) POC/demo —
prove feasibility, throwaway output, speed over completeness. (b) Production replacement with
a hard date — licence expiry, platform EOL, contract; fidelity and speed win, improvements
deferred. (c) Production replacement, open-ended — modernisation is part of the goal. Only
the user knows; record the date itself if there is one.

## 3. Fidelity: port as-is, or improve as we go?

_Not yet asked._ Default inherited from Q2 — (b) implies as-is, (c) licenses redesign — so
put the inherited default to the user and ask what to override. This decides whether every
Stage 3 fit-gap finding is a gap to close or an opportunity to take.

## 4. Scope boundary: the whole application, or a slice?

_Not yet asked._ Name what is explicitly OUT, not just what is in — "out" is the half that
gets forgotten and rebuilt anyway. A module-sized source is the common case and is easy to
mistake for a whole app; if it is a slice, say what the slice must keep working with.

## 5. What must NOT change?

_Not yet asked._ Integrations, data contracts, external URLs, scheduled jobs, reports other
systems consume. These are the constraints that invalidate an architecture late and cheaply
if found now; they are rarely visible in the source, because they live in its consumers.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

_Not yet asked._ How to verify: ask the human; not inferable from the code.

## 7. Is an SME available — who, and at what cadence?

_Not yet asked._ Availability is not the useful half: an SME who exists but answers in two
weeks reshapes the plan as much as no SME at all. Ask who, for which class of decision, and
what the realistic turnaround is.

## 8. Anything else — scope, priorities, or worries?

_Not yet asked._ The standing open-floor question the runbook requires at every checkpoint
(§1). Closed questions capture decisions; they never surface what the user wanted to say
unprompted. "Nothing further" is a valid answer — but it has to be the user's, not assumed.

## 9. Interview mode: attended (default) or unattended?

_Not yet asked._ How to verify: ask the user; default is attended. Attended = every gate
question is asked in chat and the agent waits for the answer. Unattended (opt-in only, explicit
request required) = recommended options are applied as ASSUMED and logged for reconciliation.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

_Not yet asked._ Only relevant when the project did not start here: a build already underway,
analysis that lives in Confluence, a design system someone else owns. Name the stage the toolkit
picks up at and record it — `bin/gate-check.sh <project> --adopt <stage> --reason "..."` — so the
earlier stages report WAIVED instead of a red row nobody can ever clear. Answer "starting from
scratch here" and nothing is waived, which is the right answer for most projects. Do NOT infer
this from what happens to be on disk: a missing artifact and an artifact produced elsewhere look
identical, and guessing wrong either nags forever or waives a stage that genuinely still matters.
MXTK_INTAKE_EOF
}

# Just the question texts, "## N. " stripped. This is the unit sync-project.sh compares against
# a project's intake: the NUMBER is not part of a question's identity. Old Q2 ("licence/security
# constraints") is current Q6 with identical wording, and a number-sensitive comparison would
# report it missing and append a duplicate of a question the user already answered.
mxtk_intake_question_texts() {
  mxtk_intake_template | sed -n 's/^## [0-9][0-9]*\. //p'
}

# One question's full section, by its text (not its number), trailing blanks stripped.
mxtk_intake_question_section() {
  mxtk_intake_template | awk -v want="$1" '
    /^## [0-9]+\. /{ t=$0; sub(/^## [0-9]+\. /, "", t); insec = (t == want) }
    insec { print }' \
  | awk '{a[NR]=$0} END{last=NR; while(last>0 && a[last]~/^[ \t]*$/) last--;
          for(i=1;i<=last;i++) print a[i]}'
}
