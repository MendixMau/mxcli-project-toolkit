# Project-Scoped Process Notes — Apex sample (OS→Mendix PoC)

**Scope:** These are **project-specific** build-discipline notes from the Apex sample OutSystems→Mendix PoC. They reference that project's paths, demo users, and design docs — they are **not** generic toolkit rules. They live here (not in `skills/learned-*.md`, not in Baseline routing) so a new project doesn't inherit Apex-specific paths by accident.

**The generic versions of the durable rules that used to sit here now live in shared skills:**
- **Widget-location-context format** → `skills/learned-page-patterns.md` (generalized)
- **Page build discipline / field fidelity** (spec-first, DTO cross-check, test-as-non-admin, stub naming, correct-widget-first) → `skills/learned-page-patterns.md` (generalized, with Apex examples kept)
- **CE-error triage discipline** → `skills/iterative-build-loop.md` (CE Error Triage) + `skills/learned-microflow-patterns.md` (annotation-on-fix rule)
- **MDL script freezing / new-numbered-script-per-fix** → `skills/iterative-build-loop.md` (Script Conventions → Numbering and versioning)
- **Rotating keep-5 MPR snapshots + auto-restore gate** → `skills/iterative-build-loop.md` (`bin/exec.sh` template)

**What remains below is genuinely Apex-specific** (exact doc paths, demo users, folder layout) — kept as a reference example, not a shared rule.

---

## Design Sources — Where to Look Before Implementing (Apex sample)

**Rule:** Consult design sources before any domain model change, CE error fix, or logic implementation. Never improvise from memory.

| Priority | Path | Use when |
|----------|------|----------|
| 1 | `docs/domain-design-enriched/F001–F012.md` | Any entity, attribute, association, or microflow question |
| 2 | `docs/poc-plan.md` | Scope boundary, stub vs. real, integration decisions |
| 3 | `extraction/knowledge-base/brd/F001–F012.brd.json` | OS original behavior, field names, flow logic |
| 4 | `extraction/knowledge-base/share/KB_*.md` | Requirements detail, field labels, CorpSearch/SAP API specs |
| 5 | `docs/interface-registry.md` | Cross-module calls, parameter contracts |
| 6 | `bug-logs/mxcli-bugs.md` | Unexpected mxcli behavior — check here before assuming a script bug |

**F-doc index:** F001=Order Reg UI, F002=Approval Workflow, F003=Master Data, F004=Corporate Search, F005=SAP Integration, F006=Common Components, F010=WF Backend, F011=Customer Common, F012=Order Backend. F007–F009 are out of PoC scope.

**Do NOT use:** `docs/domain-design/` (superseded), `docs/domain-design-patched/` (superseded), `docs/superpowers/` (pipeline planning), `extraction/extractors/`, `extraction/generators/`.

---

## CE Error Triage — Mandatory 5-Step Approach (Apex sample specifics)

The generic discipline is in `iterative-build-loop.md`. Project-specific hooks:

1. **Collect:** run `./bin/exec.sh` — its mxbuild gate reports the CE error list and auto-restores on failure. (For an out-of-band check without an exec, open the project in Studio Pro.)
2. **Trace to script:** review latest scripts in `mdlsource/layer2/` (highest number = most recent). For each error: which script created/modified the flagged element? Is it a **script bug** (wrong wiring) or a **design gap** (element never built)?
3. **Consult design docs** (only for design gaps, in the priority order above).
4. **Propose with justification:** state root cause, proposed fix, and the F-doc section or poc-plan decision that justifies it. Wait for user approval.
5. **Execute:** only after explicit approval.

**Never:** add attributes/entities to silence errors without requirement justification. Never fix the model to match a broken page binding — the page may be wrong.

---

## MPR Backup / Recovery (Apex sample)

Use the rotating keep-5 snapshot discipline — **never** ad-hoc `.mpr.backup` copies (they accumulate and rot). `bin/exec.sh` snapshots automatically before every exec and auto-restores on an mxbuild failure.

```bash
# exec.sh snapshots automatically. To snapshot manually (only if calling mxcli exec directly):
./bin/snapshot-mpr.sh

# If Studio Pro crashes or the MPR is corrupt: restore the newest snapshot
./bin/restore-mpr.sh
```

**Snapshot especially matters when:**
- Any contentparams write (BUG-04 null GUID risk)
- Any script touching cross-module associations or entity-qualified paths
- Any sequence of 3+ mxcli exec calls in one session
- Before scripting new pages with complex widget trees

**Corruption detection:**
- `mxcli check --references` → syntax/reference errors (before exec)
- `bin/exec.sh` mxbuild gate → CE errors (after exec)
- Neither catches BSON-level null GUIDs (BUG-04) — only Studio Pro opening reveals these

**Do NOT** use `git checkout HEAD -- <project>.mpr` as recovery — it discards all good MPR changes since the last commit. Restore from `.mpr-snapshots/` via `bin/restore-mpr.sh`.

---

> The **Page Build Discipline / Field Fidelity** rules that used to live here (spec-first, DTO
> cross-check, test-as-non-admin, stub naming, correct-widget-first) are now generic rules in
> `skills/learned-page-patterns.md`, with this project's paths (`KB_MXXXX_*`, `07_Form.md`) and demo
> user (`demo.user` / HQDomestic) preserved there as the worked example.
