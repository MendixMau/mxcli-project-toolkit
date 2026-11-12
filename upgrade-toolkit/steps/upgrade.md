# Step 3: upgrade (one commit per step, project under git)

Goal: reach the target version with every step proven not to change a runtime identity.

1. Module updates through the batch runner, never a hand-rolled loop:
   `bash $B/stepupdate.sh app/ $W/plan.txt --approved $W/approved.txt --baseline $W/original/<app>.mpr [--force-ui <list>] [--unattended]`
   (make the original once: `mkdir -p $W/original && git -C app archive <first commit> | tar -x -C $W/original`, then `--baseline $W/original/<app>.mpr`: on an MPR v2 app a bare `git show <commit>:<app>.mpr` has no units, NR2-7). Per line it saves the previous commit's MPR and mprcontents/, runs the
   update under the heavy lock (default `mxcli-container.sh marketplace update {cid} --to {version} --module {module}`),
   runs a STEP idcheck (previous commit vs working copy, not original vs working copy, which goes blind after the first
   accepted finding), auto-approves findings that are net zero against the original (an attribute a pre-step added and
   the next step removed), and commits "step: <module> <version>". A new finding: STOP, nothing committed. It runs from
   a copy of bin/, so editing the toolkit during a batch cannot break it. It puts `.stepupdate/`, `.claude/` and
   `.mxcli/` (mxcli writes both into the app) in .gitignore before the first step (E5b-17, E6-4, E7-21).
   Two step lines are warnings, not stops: `WIDGETS:` (the update changed shared widgets/*.mpk, NS-6: playbooks/widgets.md
   section 3) and `warn MODULE_RECREATED <Module>` (idcheck: every unit id of the module is new, so it was deleted and
   re-imported instead of updated in place; NS-7, notification-service cc318c0b: DataWidgets 2.27.6 rewrote 12 own pages
   and was reverted the next day). After a MODULE_RECREATED line, diff the own pages the step touched
   (`git show --stat HEAD`) before going on, or revert the step and update the module with Studio Pro.
   - approved.txt: one fnmatch pattern per line on the element or "FINDING kind name", then `# reason`. Only for
     findings accepted in writing.
   - Local edits refusal ("Save them first: --save-edits"). stepupdate names the edited element kinds. UI only
     (pages, layouts, snippets, images): rerun with `--force-ui <Module>`; the edits are saved under
     `.stepupdate/saved-edits/<Module>` and the update is forced. Replay them from there after the step, then commit
     (E4-13). A page that mxcli cannot round-trip (it refuses its own describe output, for example a duplicate widget
     name in a vendor page, CE0495) stays as the update left it: list it in the report as not replayed (E7-19). The `force-ui:` line of localedits.py is the list to pass. Logic or domain edits: keep the module (the
     edited-modules playbook), never force.
   - Associations of OTHER modules that point into the module (mxcli v0.28.0, #1502): the refusal says "N association(s) in other
     modules reach into <Module> and are removed with it" and lists them as `ASSOCIATION <Owner>.<Name>` rows. They are the app's own
     domain model, not edits of the module. `--force-ui <Module>` saves each as `.stepupdate/saved-edits/<Module>/association-<Owner>_<Name>.mdl`;
     stepupdate prints them after the step (ASSOCIATIONS-SAVED, `.stepupdate/assoc-saved.txt`, the summary). Replay each after the updates with
     `mxcli exec <file> -p app/<app>.mpr`; it comes back with a NEW GUID, so name it in `replay/<Module>.guids` and `restore_guid.py` puts the
     original back (otherwise the rows in its table are orphaned). The pipeline notes `NOT replayed` for a saved association no
     `replay/<Module>.mdl` creates. The convert-made and package-owned routes never force over these.
   - TOOL ERROR "open package target.mpk: open /tmp/mxuNNN/target.mpk: no such file or directory" (mxcli v0.28.0): the update passed the gate,
     dropped the module and could not find the package it had fetched. stepupdate stops (exit 3), reverts the tree (the module comes back from git) and
     records nothing. It is the build, not the module: use another mxcli build (SETUP.md, `MXCLI_REF`), do not retry with `--force`.
   - Installed version not usable as the local-edit baseline (unpublished, HTTP 500, or a package made before 9.18):
     stepupdate retries once with `--no-baseline` and logs it in `.stepupdate/no-baseline.txt` with a WARNING: local
     edits in that module are unproven, so localedits must have said its domain and logic layers are unchanged
     (E5b-27, E5b-26). `--no-fallback` turns the retry off. The no-baseline route saves NOTHING: for a `--force-ui`
     module it prints "UNSAVED: <Module> updated through --no-baseline and saved 0 files" and stops (unattended: keeps
     the module), because its UI edits would be lost silently (E7-1: three layouts replayed by hand). After you have
     the edits listed for a hand replay (localedits report of the previous commit), rerun with
     `--accept-unsaved <Module>`: the step commits and the summary lists it under "UNSAVED (replay by hand)". When the TARGET package itself was made before 9.18 it
     cannot be imported on 10.x: stepupdate prints "SKIP", reverts, and records the module in `.stepupdate/kept.txt`
     (E4-16). Take the post-convert version instead.
   - Files outside the model (T5-17: brand colours in Atlas_Core `_variables.scss` were lost with no signal): before every
     update of a module that has `themesource/`, `javascriptsource/` or `javasource/` files, stepupdate runs
     `localedits.py --files-only` and copies the folders to `.stepupdate/saved/<Module>/`. Edited theme/JavaScript files
     refuse the module like other UI edits (`--force-ui <Module>` goes on); edited Java user code: keep the module. After the
     update every replaced file prints `FILES-OVERWRITTEN <path> (saved: ...)`, the changed `$var: value;` lines are appended
     to `theme/web/custom-variables.scss` when that file exists (`REPLAYED-VARS`; otherwise replay from the saved copy), and the
     summary lists the module. If the installed package cannot be compared (`FILES-UNKNOWN`) and the update replaced
     files, the step STOPS until you have compared the saved copies (`--accept-unsaved <Module>`). Never take the
     `--no-baseline` route without reading these lines; re-run the screens rung after a theme module update.
     The plan line's content id goes to localedits as `--cid <Module>=<id>` (B4N1-4: an 11.x .mpr records none, so every
     module with files was `FILES-UNKNOWN`). JavaScript action files compare only what Studio Pro keeps when it
     regenerates them: the import set and the USER CODE / EXTRA CODE blocks; header, JSDoc and import order are not an
     edit (B4T2-3, B4N1-5), a changed line inside a block still is.
   - Resume without a new plan file: `--from <line number | Module>` starts there, `--skip Mod,Mod` leaves modules
     out; both are logged (E4-7, E4-32).
   - Unattended: `--unattended` applies the stop rule mechanically. A STOP (step idcheck finding, refusal, failed
     update) reverts the tree (tracked files restored, files the update created removed, untracked files from before
     kept), records the module in `.stepupdate/kept.txt` and continues. The summary line says
     "N steps: N run, N committed, N kept, N network"; exit 1 when anything was kept. Report every kept module (SKILL stop rules).
   - Tool and network errors are never a verdict on a module (batch 1: every worker lost a whole pass to "14 steps
     done, 14 kept" that was really a broken command). A TOOL ERROR (mxcli "accepts 1 arg(s)", x509 / certificate,
     "no credential for profile", proxy unreachable, docker exit 125 to 127) STOPS at once, also unattended: exit 3,
     tree reverted, nothing in kept.txt. Fix the toolchain and rerun with `--from <Module>`. A NETWORK error (TLS
     handshake timeout, i/o timeout, connection reset, HTTP 5xx other than the baseline refusal, 429) is retried
     after 5, 15 and 45 s; still failing, it is a `NETWORK` line in kept.txt (rerun it, it is not a refusal), and the
     same network error on two modules in a row stops the batch (exit 3). Placeholders are shell-quoted, so an MPR
     named "Purchase Request.mpr" needs no workaround. Behind an egress proxy, mxrun.sh passes HTTPS_PROXY, the CA
     (`UPG_CA`, else `SSL_CERT_FILE` or /root/.ccr/ca-bundle.crt) and `--network host` for a proxy on 127.0.0.1;
     values with spaces go in `UPG_ENV_FILE`, never UPG_EXTRA.
     kept.txt holds one line per module (the latest reason); a module a later pass commits leaves the file (E6-12).
     A step idcheck REVIEW (persistence loss or removal) is named REVIEW in the KEPT line, as in the idcheck legend
     (E6-7): accept it in approved.txt with a reason, or keep it. With rows in that table, keep it unattended.
   - Kept-module guard (T5-15, T5F-4; a procedure, not scripted in stepupdate.sh): while the kept list
     (`.stepupdate/kept.txt` plus `stranded.md`) is non-empty, `crosscalls.py app/ --kept-file .stepupdate/kept.txt
     --plan-file $W/plan.txt` must have exited 0 (or every CAP line is already held back in the plan) before the batch
     starts. After each module step, run `mx check` (the toolset of the step) and compare its error list with the previous
     step's: a NEW error whose document sits in a kept module (CE0117 in Administration after MendixSSO moved) STOPS
     the batch, the same as an idcheck finding. Revert that step, hold the planned module at its previous major, rerun
     from the next line. The first sign of this class must never be javac or the runtime.
   - Kept-module dependencies (T6R-7, the other direction; scripted): a module that stays while others move must not be
     needed by a module that moved. T6R committed AmazonTranslateConnector while AWSAuthentication stayed at 2.1.2 (an
     idcheck REVIEW kept it); the first sign was 12 CE1613 in mx check and javac. Every pass that ends with kept.txt
     non-empty runs `keptdeps.py` itself (report in `.stepupdate/keptdeps.txt`, exit 1): each module with a `step:`
     commit is checked against each kept module, both ways, by name, by parameter of a flow, attribute of an entity,
     enumeration value and Java import. Before you KEEP a module by hand (a revert, an attended STOP you accept as a
     keep), run it first: `python3 $B/keptdeps.py app/ --kept <Module> --updated-from-git` (or `--updated C,D`).
     `FAIL <U> <ver> needs kept <K> <ver>: n of m references missing` (or `FAIL kept <K> calls updated <U>`): the keep
     breaks U. Update K too and rerun, revert U to a version built against the kept K, or port the missing elements;
     write the pair and the choice in the journal. `REVIEW <U> needs kept <K>`: every name resolves but signatures and
     types are unproven, so mx check and the build after the commit must show no error in either module naming the
     other. `keptdeps: INVALID` (a kept.txt module not in the model, no git) means nothing was checked: fix the input,
     never read it as PASS.
   - Targets of cross-module associations (`idcheck.py app/ --xmod`, usually MxModelReflection): the update itself
     drops the associations other modules own into it (E4-18). The expected outcome is "kept" (the step idcheck stops it)
     unless the owner is on the plan too: then put the TARGET before the OWNER (`python3 $B/planorder.py app/ plan.txt`
     checks the order, `--write` fixes it; stepupdate prints PLAN-ORDER lines at its start). The owner's import after the
     target restores the association with its old GUID in one step (PV-2: OIDC after UserCommons; the other order gave 17
     CE1613). Already in the wrong order: reimport the owner at its current version after the target, then rerun the
     step idcheck. Only a kept owner needs the edited-modules replay route (drop plus create plus restore_guid per
     association), and only when it is worth the work.
2. Before the convert: `python3 $B/convertpre.py app/` (MC-2, MC-3). It REFUSES (exit 1) while the tree holds uncommitted
   build output (proxies, JS action stubs, classpath files mix into the convert commit and convertnoise cannot
   separate them: commit them as `build: <what>` first), and WARNS about a model-changing commit (a `repair:` role
   mapping, say) between the last `step:` or `original` commit and the convert: convertmade.sh then proves no module
   CONVERT-MADE, because an MPR v1 project keeps every module in one .mpr. Rule: no model change between the last
   step commit and the convert; role mappings (rolecheck NEW-ROLES) go after the post-convert pass.
   Convert, in place, with the TARGET toolset: `UPG_ROOT=<run> $B/heavy-lock.sh convert $B/mx10.sh <target ver> mx convert --in-place <abs path to app dir>`
   A 9.x source converts with the 10.x target toolset too (mx10.sh); a 9.24 mx cannot convert to 10.24 (E7-11). 11.x
   target (also from an 11.x source, N1-14): the local mxbuild. `mx convert app/` alone answers "No input or output
   specified" (exit 2) on 10.24 (E4-17, E5b-15). Save the output (`... 2>&1 | tee $W/convert-<ver>.log`), then
   `python3 $B/convertcheck.py $W/convert-<ver>.log app/ --target <full ver> --json $W/convert-<ver>.json` (the json
   keeps the error, warning and deprecation counts for COMPARE, N1-11; repair.md "Counts per rung"). Never read mx convert's exit code or
   "mx convert finished": both say success with 31 errors (E6) and on a refused source (Academy 10.18 to 11.15, AC-1,
   AC-7). CONVERTED = the project file now carries the target version; its error count is the repair backlog for
   step 4, write it in the journal. NOT CONVERTED = stop; a 10.x below 10.24 going to 11 must take the 10.24 rung
   first. Commit the convert ALONE (subject "convert to <ver>"): nothing else staged, no tool files, no fix. Then
   `python3 $B/convertnoise.py app/ --rev HEAD`: exit 0 = the commit holds only model units, widget packages without
   their appstore.id entry, widgets-appstore-metadata.json and regenerated javasource/javascriptsource/jars. Exit 1 =
   FOREIGN paths (tool files, docs, .gitignore) or a WIDGET whose contents changed: split them out into their own
   commits before step 3 (notification-service 3fbf1566 squashed the 11.12.4 convert with 456 toolkit paths, NS-13).
   The model part is the convert's own noise (IsRequired on every microflow, `$value != empty` rewritten to
   `length(toString($value)) > 0`, AppStorePackageId to AppStorePackageIdString; NS-10): never review it unit by unit.
   Convert ONCE per rung, on the integration branch, with the patch version production will run, then freeze that
   commit: every later step builds on it. notification-service converted four times on parallel branches (6f92a11f
   10.24.9, then three times 10.24.8) and threw the 10.24.9 line away, 49 days to production (NS-8).
   Then the page mappings the convert rewrote (9 to 10, T2-1): `python3 $B/convertcheck.py --mappings <pre-convert app dir
   (the "original" commit checked out apart)> app/ --json $W/convert-mappings.json`. Exit 1 = REVIEW lines: a button
   inside a data view on a microflow, nanoflow or association now maps the PAGE PARAMETER, not the data view's object.
   Fix each in Studio Pro or MDL (map the data view object) before step 4 closes; the gate re-runs it.
3. Post-convert module updates (plan: read the playbook rows of every module you target, not only `mxcli marketplace versions`; the newest WorkflowCommons needs Atlas 4, playbooks/10-to-11.md, QI-7): same runner with the target-version plan, plus `--localedits $W/localedits.json`. A module with no version between the
   pre- and post-convert ones needs only the post-convert update. The converter itself changes vendor modules
   (ExcelImporter, GoogleAuthenticator in E4), and the update then refuses them as local edits (E4-30). Those
   convert-made edits are expected. stepupdate checks it itself (bin/convertmade.sh): when the module's last
   "step: <Module>" commit (installed pristine, idcheck PASS) is followed only by step and convert commits, the
   refusal (local edits, or "N element(s) could not be read") is CONVERT-MADE and the update runs with `--force`
   (saved for reference in `saved-edits/<Module>.convert-made`, nothing to replay; the commit subject says
   "convert-made edits forced", E6-13). "build:" commits that leave the model (*.mpr, mprcontents/) alone and commits
   that change only userlib/, vendorlib/ or .gitignore (jar cleanup) do not break the chain (T5-9, T6-10); any other
   commit in between (repair, replay, gate) means LOCAL and the normal refusal rules apply.
   No "step: <Module>" commit at all (a 9.x source; a 10.x run that skipped the pre-convert pass, which is REQUIRED
   below 10.24, T7-3; on an 11.x source the pass is optional but still worth doing, so convertmade can prove a module
   pristine, N1-14): pass the pre-convert localedits report, `--localedits $W/localedits.json`, made WITH `--mxcli-diff` (the
   offline layers only see documents added or removed, never a microflow body or page edit). A module it shows
   with the domain unchanged, 0 UI and 0 logic lines and 0 mxcli-diff modified elements, with only step/convert/build/jar commits since the "original"
   commit (at least one convert), is CONVERT-MADE (source printed as "pre-convert localedits"; T1-15, T3-10, T4-3, T7-12).
   Refusal kinds that are no person's edit: JAR_DEPENDENCY rows only = PACKAGE-OWNED (the managed dependency list
   belongs to the package, which brings its own), forced with `--save-edits <Module>.package-owned` (T7-15: kept,
   CommunityCommons 10 would be stranded on Mendix 11). JAVA_ACTION rows only: `bin/usercode.py` compares the USER CODE
   blocks of javasource/<module> with the installed package (.mpk cache); identical = convert-made metadata, forced;
   different or not comparable = LOGIC, keep (T5-9: MendixSSO 4.1.0 was kept with byte-identical code). Any other
   mix keeps the rule above. `--no-convert-made` turns all of these off.
   After the post-convert updates: resync the Java dependencies (`mx update-widgets`/build resync; Academy went from 67
   to 48 files in vendorlib), then `python3 $B/repair/jarclash.py app/ --md $W/jarclash.md`.
   In a cloud container `mx sync-java-dependencies` usually cannot finish (B4T2-9, B4N1-6): it needs
   repository.mendix.com and, for the CycloneDX Gradle plugin, plugins.gradle.org through the egress proxy. Try it with
   `UPG_ENV_FILE` holding `JAVA_TOOL_OPTIONS=-Dhttps.proxyHost=... -Dhttps.proxyPort=... -Djavax.net.ssl.trustStore=<cacerts
   with the proxy CA>`; mxrun.sh passes the env file, the truststore must be a path inside the container (a JDK
   cacerts with the proxy CA imported, mounted with `UPG_EXTRA="-v <host file>:<path>:ro"`). When it still fails ("Could not resolve ... plugin",
   "Failed to find some hosts"), stepupdate prints `jar cleanup REFUSED, vendorlib is stale` and that is correct: do
   not guess. Run `python3 $B/repair/jardedupe.py app/ --updated-from-git`, check for every REMOVE line marked
   `(rests on vendorlib)` that the newer copy it names is in `app/vendorlib/`, write that check in the journal, then
   `--apply --vendorlib-synced` (stepupdate: `UPG_VENDORLIB_SYNCED=1`). A newer copy that is missing: get it from host
   Maven first. Module packages carry no vendorlib jars, so the .mpk cannot prove this for you.
   Old-major jars of an updated module (pdfbox/fontbox 2.0.24 behind unversioned `*.CommunityCommons.RequiredLib`
   markers, javac at Misc.java:643, B4T2-10, B4N1-7): stepupdate's jardedupe call counts every module with a `step:`
   commit as updated (`--updated-from-git`, also for an earlier pass) and passes the plan's content ids (`--cid`), so a
   cached installed package (`UPG_CACHE/<id>-<version>.mpk`) shows whether that version still ships the jar. A hand rerun
   takes the same flags; without them such a jar stays `CONFLICT`. A CLASH is two jars
   carrying the same classes: an old library copy left in userlib, inside an unused jar (Academy: pdfbox inside a
   2021 Markdown library), or in a module that has no newer version (PDFReader 1.0.0). Remove the stale jar, or port
   the stranded module's Java to the new library (the team did both, AC-6). Clashes listed at triage were there
   before the upgrade; only new ones are the upgrade's.
4. Edited modules (RED or logic lines in localedits) are not on the plan unless the edited-modules playbook route is
   taken.

Check after every step: step idcheck exit 0. After the last step: `python3 $B/idcheck.py $W/original/<app>.mpr app/ --md $W/idcheck-total.md`
for the written acceptance (the default output lists every finding; `--red-only` shows only the data-bearing ones).
A module update can make an entity non-persistent (Atlas_Web_Content 3.7.0 LoginContext in E4, E4-19): the step
idcheck lists it as REVIEW (removed or made non-persistent); accept it in writing or keep the module.
"N element(s) could not be read" (mxcli cannot read some documents, E6) is its own refusal: when it is not
CONVERT-MADE, stepupdate stops with "elements could not be read"; check the module with localedits and take
`--force-ui` only when it has UI edits only.

Output: one commit per step, `$W/approved.txt`, `.stepupdate/` logs (`kept.txt`, `no-baseline.txt`, `unsaved.txt`,
`saved-edits/`, `keptdeps.txt` and `keptdeps.json` while modules are kept).

## Every commit names its step
A commit in the app repo carries the trailer `Upgrade-Step: S-n`, the step in `$W/steps.jsonl` that the change belongs to (STEP-RECORDS-PLAN.md).
- Hand commits: `bash $B/appcommit.sh --app app --by agent --kind repair --rule repair-row-<N> --why "..." --step S-n --work $W -- <paths>`. An id that
  is not in the run's steps is refused (exit 2); a P-n alias is accepted and written as its S-n. `UPG_STEP` and `UPG_STEPS_WORK` are the defaults
  for `--step` and `--work`. No step for the change yet: open one first (steps/decide.md, Mid-run decisions).
- The toolkit's own commits pass it themselves when `$W/steps.jsonl` exists (`steps.py trailer --kind K`): stepupdate's `step: <module> <version>` commits
  and the replays go to the step of the topic `modules`, the jar cleanup to `repairs`, the convert to `convert`. A kind with no such step (for
  example `config`: the run start, regenerated stubs) is committed without the trailer.
- `bin/changelog.py` reads the trailer and calls `steps.py done` once per commit, so the commit shows under its step. CHANGES.md has a `step` column;
  a commit without the trailer reads "no step", and a trailer naming a step the run does not have reads "unknown step S-n".
