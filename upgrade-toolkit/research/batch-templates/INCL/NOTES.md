# INCL (Incentro Layouts, public Marketplace template)

- Version path planned: 9.3.0.22930 -> 10.24.0.73019 -> 11.12.5 (two hops). Real version read from the package's .mpr, catalogue said 9.3.
- Step reached: fetch done, triage done, baseline STOPPED (pipeline exit 10, "OLD app does not build"). PROPOSAL.md and gate-summary.md do not exist: the pipeline never got to `propose` or `gate`.
- Progress line: none (no gate ran). Changes line: none, the app model was not touched.
- App shape: two modules, `IncentroLayouts` (own, 0 entities, only layouts) and `System`. No Marketplace modules, so `plan.txt` and `module-jumps.txt` were written as comment-only (empty plan, allowed by the pipeline's message).
- Why it stopped: the old app does not build on 9.3.0.22930 (after getting mxbuild to run at all, see BT-1). 15 errors: layouts `Phone_Sidebar` and `Phone_BottomBar` use design properties the project theme does not support, and the navigation profile has no default home page. It is a module to import into a host app, not a runnable app (BT-2).
- Owner decision (not taken by the worker): wrap the module in a host app / give it a home page and theme so a baseline exists, or record the template as not upgradeable as a standalone app. Changing the app to make it build would change the baseline, so it is not done here.
- Re-architecture topics hit: none reached (triage found no widgets, Dojo or Atlas_Core issues to match). RA ids: none.
- Toolkit bugs found: BT-1 (Mono-era mxbuild for Mendix 9 before 9.20 cannot run), BT-2 (a module-only template stops with a misleading "does not build"). Both open in FEEDBACK.md.
- Cost: ~1.2 GB for source mxbuild/runtime 9.3 plus the Mono image layer.

## For the owner
- INCL is a module-only template (no home page, theme or host app): it needs a host app to be upgraded and walked. Either wrap it in a host app and upgrade that, or record it as not upgradeable on its own.
