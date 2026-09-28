# mxcli upstream issue drafts (mendixlabs/mxcli), ranked by impact

**Source:** a field project's guest-groups work, probes on scratch copies 2026-09-27.
mxcli v0.23.0, Mendix 11.12.2, v1 .mpr. **Status:** drafts, not filed. Duplicate search done
(nearest existing issues noted per item).

---

## 1. Association `owner Both` across modules leaves the other entity's access rules without MemberAccess (CE0066)
**Repro:** `drop association UserGroups.GuestGroup_App;` then
`create association UserGroups.GuestGroup_App from UserGroups.GuestGroup to AppStore.App ... owner Both;`
**Expected:** every access rule on both ends gets a MemberAccess for the association (as Studio Pro does).
**Actual:** "Reconciled 3 access rule(s)" (GuestGroup side only); AppStore.App's 13 rules untouched →
`mx check`: `[CE0066] ... at Domain model of module 'AppStore'`. `update security` does not fix it.
**Workaround:** raw BSON patch of the unit (add MemberAccess None on the far side's rules, recompute ContentsHash).
**Related:** #1067 (closed), #758, #867, #610 — none cover this.

## 2. `create or modify association` silently ignores an owner change
**Repro:** existing association with owner Default; `create or modify association ... owner Both;`
**Expected:** owner becomes Both, or an error stating owner cannot be modified.
**Actual:** "Modified association"; `describe association` still shows `owner Default`.
**Workaround:** drop+create — but that mints a new ID (DB links lost, member rights reset to None) and hits #1 cross-module.

## 3. Partial `revoke ... (write (<association>))` is a silent no-op
**Repro:** `revoke Mod.Role on Mod.Entity (write (Mod.Assoc));` on a rule with ReadWrite on the association.
**Expected:** member right drops to ReadOnly.
**Actual:** success message, rule unchanged.
**Workaround:** re-grant the whole rule with the desired member list.
**Related:** #947 (closed; grant replaces instead of merging).

## 4. XPath system member in the wrong case passes `check`, fails at build (CE0161)
**Repro:** `retrieve $G from UserGroups.Guest where [CreatedDate >= $Since];`
**Expected:** `mxcli check` flags `CreatedDate` (system members are `createdDate`, `changedDate`, `owner`, `changedBy`), ideally with a fix hint like MDL047.
**Actual:** "Check passed!"; after exec `mx check` → `[CE0161] Error(s) in XPath constraint`.
**Workaround:** lowercase. **Related:** #641 (closed).

## 5. Feature: lint rule for REST call / retrieve / microflow call / delete inside a loop
Commit-in-loop is covered (CONV011); REST calls with commits inside a loop were the #1 finding of a
best-practices review and nothing flagged them. Blocker noted in the toolkit: the Starlark API exposes
no loop containment. Ask: expose the enclosing loop (or a `in_loop` flag) on activities, or ship a Go rule.

## 6. MPR012 assumes the React client
On a Dojo-client project MPR012 reports a React-only issue (false alarm). Ask: read the project's
client setting and skip/downgrade when not React. No existing issue found.

## 7. (comment on open #1061) `check --references` misses a queue created in the same script
A task queue created earlier in the same script is reported unresolved by `check --references`,
though exec creates and resolves it. Add as a repro comment on #1061 rather than a new issue.

---
**Not filed:** grants injecting System.owner/changedBy MemberAccess (CE0066) — fixed upstream in
2455ee9f, not reproducible on v0.23.0.
