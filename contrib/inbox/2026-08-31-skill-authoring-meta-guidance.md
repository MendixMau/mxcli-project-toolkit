# Skill-authoring meta-guidance worth folding in (obra/superpowers `writing-skills`, mattpocock `writing-for-agents`)

**From:** public repo review — obra/superpowers and mattpocock/skills, both MIT-licensed
**Date:** 2026-08-31
**Kind:** process
**Field evidence:** partially corroborated by this toolkit's own 2026-08-31 A/B baseline (`process/preflight-skill-baseline-2026-08-31.md`) — the five authoring rules adopted that day in `CLAUDE.md` already absorb the overlapping parts; this entry queues only the residue.
**Proposed target:** `CLAUDE.md` → "Adding new skills" (as additional rules), possibly a `skills/writing-skills.md` if the material outgrows the section

---

Both public repos maintain a skill *about writing skills*. Rules they state that the
toolkit's five adopted authoring rules do **not** yet cover:

1. **Write for the trigger, then stop.** A skill is retrieved by an agent mid-task with a
   specific trigger; everything not needed at that moment is dilution. Superpowers frames
   it as ruthless scope: one skill = one situation. Our arm-C verification saw a possible
   dilution effect from ~800 words of growth in one revision — same mechanism, observed
   locally.
2. **Show the failure, not just the rule.** Both repos pair each rule with the concrete
   bad output it prevents (a before/after or a verbatim wrong answer). The toolkit does
   this in CLAUDE.md incident notes but inconsistently inside `skills/*.md`.
3. **Test retrieval, not just content** (mattpocock): periodically check that the routing
   line actually fires for the phrasings users/agents really produce — a skill can be
   perfect and unreachable. The toolkit has routing rows as trigger conditions (rule 1 of
   the adopted five) but no practice of testing them against real phrasings.
4. **Degrade to a pointer.** When a skill must reference volatile facts, reference where
   to look, never the fact itself — the toolkit adopted this as rule 5 (no environment
   caches); superpowers extends it to *any* fact with an authoritative home, including
   other skills' content. Overlaps our "single source of the rule; every other mention
   defers here" convention — worth stating as one unified principle.

Triage suggestion: fold 1–3 into the "Adding new skills" ruleset (making eight rules), or
split the section into `skills/writing-skills.md` with CLAUDE.md keeping a pointer, per
the degrade-to-a-pointer rule itself.

Credit: obra/superpowers `writing-skills`, Matt Pocock `writing-for-agents` — patterns
summarised in our own words; no text copied.
