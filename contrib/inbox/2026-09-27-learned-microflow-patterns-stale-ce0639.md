# learned-microflow-patterns.md: stale CE0639 claim + contradicts CONV010

**Source:** marketplace-rnd guest-groups build. **Status:** unreviewed inbox drop.

1. `skills/learned-microflow-patterns.md` (~l.397, 409–424) says validation feedback →
   "CE0639 unavoidable via mxcli". BUG-47 is resolved; the guest-groups SUB with validation
   feedback built with 0 errors on v0.23.0. Stamp the rule as retested/obsolete.
2. Same section recommends validation feedback directly in `ACT_OrderDetail_Save`. CONV010
   (ACT microflow content allowlist) does not allow ValidationFeedback in ACT_ — the pattern
   lints red. Recipe: `VAL_`/`SUB_` does the feedback, `ACT_` calls it and branches.
3. Side note: upstream fixed CONV010's merge false positive; the project re-synced to
   upstream's rule. Check whether the toolkit's own `lint-rules/conv010_act_microflow_content.star`
   replacement is now obsolete.
