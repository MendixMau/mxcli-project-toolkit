# Playbook: Marketplace modules with local edits

Found by `localedits.py` in triage (RED = data-bearing edit). Default: KEEP the module at its installed version and
report "upgrade complete except kept modules". Update only when the edit can be replayed with its data intact.

1. Evidence: `localedits.py app/ --md ... [--cid M=<id>] [--proxy M=<version>] [--mxcli-diff]`. UNKNOWN (exit 2) is
   not "no edits". `--proxy` lines compare with another version: decide drift vs edit per line (a proxy of another
   major is called out as weak evidence). Layers: domain (RED when data-bearing; a validation rule on a System.User
   specialization is RED too, accounts are live data), pages and layouts (UI, the `--force-ui` route), and logic
   (microflows, nanoflows, Java actions, rules, enumerations ADDED or REMOVED locally; contents are not compared,
   `--mxcli-diff` for that). A LOGIC line means keep or replay, never force (E5b-28: four locally deleted SSO
   microflows would have come back silently).
2. Save the edit as MDL before updating (domain model, pages, microflows of that module).
3. Update the module (stepupdate.sh; its step idcheck will STOP on the removed element; approve only after the
   replay is planned).
4. Replay. An association that the package also installs must be replayed as drop plus create; `create or modify`
   creates a duplicate with the same name (E5 F17, upstream mxcli).
5. Identity back: `python3 bin/restore_guid.py app.mpr Module.Entity.Attribute --from original.mpr` for every
   replayed attribute, entity and association. A replay gets a new GUID and the runtime would drop and re-add the
   column (E1 19).
Cross-module associations INTO a module (`idcheck.py app/ --xmod`, usually MxModelReflection) are dropped by any
update of that module (E4-18): treat it as edited, replay each association as in steps 4 and 5, or keep it.

Never make the build green by switching vendor Java off: commenting out or emptying a Marketplace module's method
compiles, starts and passes the data diff while the feature is gone (NS-5: DatadogConnector count/time/gauge on 11,
notification-service 076dca76). Update the module or port the code; `bin/vendorjava.py app/ --base <original commit>`
lists every such edit (steps/gate.md item 13).

6. Proof: `idcheck.py original.mpr app/` must no longer list the element, then the full gate (data diff on the RED
   elements' key values set in the baseline).

Proved by controls: restore_guid (field E1 fixture), localedits UNKNOWN/proxy/logic/user validation (field E5b
logic fixture), step idcheck stop. Not proved: an
online localedits download (controls use the offline cache).
