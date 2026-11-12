#!/bin/bash
# run-controls.sh: every control of the upgrade toolkit. Each fixed FEEDBACK.md item has a CATCH case (input with the
# defect: the tool must flag it) and a PASS case (input without it: the tool must stay quiet).
#
#   run-controls.sh [--fast] [--only REGEX]      (or: make test / make fast in this folder)
#
# Three kinds, in this order:
#   synthetic  fixtures/ (committed, Marketplace and System names only), models built by lib/mkmodel.py
#   field      the real E1, E5, E4 and E5b evidence in ~/upgrade-lab (UPG_LAB), read-only, exported to a temp folder;
#              SKIP when the folder is absent. Never copied into this repo. field-catalog-* also needs mxcli's local
#              Marketplace catalog (~/.mxcli) and is SKIPped without it.
# Since v3 (E4 and E5b): shotdiff-* and journeys-screen-* (screens rung), toolset-*, snapshot-ledger-*, gen-*, the
#              localedits ui, logic and validation layers, stepupdate force-ui / unattended / no-baseline / from-skip.
# Since v3.1 (E6 and E7): release-impact-* (fixtures/brain) and brain-release-impact-* (the real brain, read only, SKIP
#              without it), control-*, mxversion-cdn-*, runapp-log-*, diff-db-only-* / diff-random-body-*, toolcheck-bash-*,
#              gen-module-pages-*, journeys-no-entry-* / journeys-closes-*, settle, journey verbs, convertmade, pds_oldnames.
# Since batch 1 (B1-J): gen-journeys-* (guards, proven-only textAbsent, microflow homes, layout sign-out),
#              journeys-engine-login-* (login patches; -catch runs login_page_home_control.js in a real browser, SKIP
#              without Playwright), journeys-microflow-home-closed-*, smoke-users-ledger-* / smoke-users-frozen-catch.
# Batch 1 (T1..T8, tool and network errors are never a verdict): stepupdate-spaced-* / -split-args / -tool-error-* /
#              -no-credential / -transient-retry / -network-*, localedits-transient-retry / -network / -no-mxcli-*,
#              mxrun-*, mxcli-container-home-*, design-props-*, toolcheck-host-*.
# Since batch 1 (T1..T8): convertmade-9to10-* / convertmade-build-commit-* (pre-convert localedits as the pristine proof,
#              build and jar commits neutral), stepupdate-jar-dependency-* / stepupdate-java-action-* / usercode-*, and
#              field-t5-* / field-t7-* (the workers' localedits reports from their run branches, SKIP without the refs).
# T5-17: localedits-theme-* / -java-usercode-* / -files-only-*, stepupdate-files-* (themesource, javascriptsource, Java user code).
# Since batch 2 (N1-13): gate-* (bin/gate.sh over stub instruments: dry-run, missing input, rc 2 is INVALID, NOT RUN listed).
# Since batch 3 (N1R2-8/9, T2R3-10/11): journeys exit 3 (INVALID only) and gate-journeys-rc3-*, gate-pre-*, gate-run-*,
#              gate-only-merge-* (PRE keys for later rungs, exported keys, {RUN}, --only merges the summary).
# Batch 2 journeys (B2-2, B2-3, G-3, T2R3-4, N1R2-3): gen-journeys-guard-title-* / -tabpage-* / -hide-on-*, -api-only-role-*,
#              -layout-signout-icon-*, -home-texts-* (fixtures/models/guard2.json, fixtures/journeys/impact-guard2.json).
# Batch 4 journeys (B4T2-11/B4N1-8, B4T2-16, B4T2-4): gen-actions-tab-* (a tab step for a widget on a tab page not shown
#              first, on the golden with one card moved onto a tab), journeys-verbs-row-* / -tab-* and journeys-verbs-browser-*
#              (Data grid 2 rows in a real browser, SKIP without playwright), gen-journeys-signout-flow-* / -caption-* /
#              -deep-* / -action-wins-* / -why-* / -probe-* (fixtures/models/guard5.json, fixtures/journeys/impact-guard5.json).
# Since batch 3 (T5-10, T3-11): seed-snapshot-* (bin/seed_snapshot.py: counts, zip input, unknown statement / value count / missing column /
#              missing entity GUID catch; the database ones run on a throwaway Postgres from lib/pgtmp.sh, SKIP without postgres binaries).
# Since E2E-8: action-inventory-* (bin/action_inventory.py on a golden captured from a real Marketplace model by
#              lib/capture_units.py: the HW14 cards, the grid New button, removed / unknown action types) and field-action-inventory-customer-*.
# D2 (quality-judgement-plan item 5): effect-values-* (bin/effect_values.py: compare on fixtures/effect-values/, snap on the sqlite stand-in)
# Since E2E-9 (E5b-11): pgmap-* (bin/pgmap.py on lib/sqlitepsql.py; pgmap-pg-* on a throwaway Postgres, SKIP without it),
#              pgdata-* (the patched engine's data rung and effect record, node), journeys-data-backend-*, journeys-effect-*.
# Since E2E-10: gen-actions-* (gen_journeys.py --actions on the same golden: one journey per action, todo -> skipped,
#              the T2R3 create-spec as override, field values by type, verbs known to the patched engine) and
#              field-gen-actions-customer-* (the customer model, own-row checks with --data-rung).
# Since E2E-11/12: journeys-coverage-* (the coverage line, the journey-set hash, baseline-defect evidence, the 30% rule),
#              fixture-check-* (bin/fixture_check.py: the four causes of an empty seed), gate-journey-actions-* / -coverage-*.
# Since E2E-13/14: apimock-* (bin/apimock.py on fixtures/apimock/, captured with lib/capture_units.py from the Marketplace
#              PFEP and Kanban apps; a stand-in on 127.0.0.1 only), journeys-apimock-* and gate-except-* / gate-apis-* / gate-smoke-*.
# Since E2E-16: process-* (bin/draft_processes.py drafts from the model, fixtures/processes/ manual and interview, always
#              status: draft; bin/process_journeys.py compiles confirmed ones, unresolvable -> INVALID, drafts never; the
#              process line and role order in run_journeys.py) and field-process-customer-* (customer + the customer spec as manual).
# E2E-15: apimock-standin-* and gate-standin-* (a pass on the stand-in is "PASS (on stand-in APIs: ...)", exit 4, never
#              plain PASS), gate-no-apimock-plain-pass.
# Batch 4 (B4N1-11, B4N1-9, B4T2-5, B4T2-6): apimock-check-zero-traffic-* / -unexercised-* (requests seen: N; MOCKED and
#              uncalled is INVALID), apimock-addon-* (fixtures/apimock/addon-exfn-auth.json: an add-on is UNKNOWN),
#              apimock-classify-location-* / -mocked-no-route-*, apimock-serve-public-host-bind-pass, gate-apis-zero-traffic-catch.
# FN (field finish pass): gen-fn-* / action-inventory-branch-entry-* / impact-map-dropdown-container-* / impact-map-js-snippet-*
#              (controls/generator_fn_control.py on fake models), journeys-verbs-fn-*, journeys-engine-fill-optional-pass,
#              journeys-coverage-closed-row-*.
# B6: replace-* (bin/replacement_check.py over playbooks/replacements.tsv, fixtures/models/replace-*.json) and
#              field-replace-customer-pass.
# B6-2: brain-mine-* (bin/brain_mine.py over fixtures/brain-mine).
# B6-4: dojo-react-* (bin/dojo_report.py over fixtures/models/dojo-react.json and fixtures/dojo-successors.tsv).
# Batch T6R: mxcli-container-relative-* (T6R-11), jarbc-* (T6R-10, lib/mkjarbc.py), seed-enum-* / seed-filedocs-* /
#              seed-mpr-missing-* (T6R-13), release-impact-from-mpr-cid-lost-* / release-impact-slug-* / -from-mpr-needs-versions-* (T6R-4), release-impact-tools-*
#              (T6R-5, lib/mkjavaproj.py), gen-journeys-guard-dataview-* (T6R-3, fixtures/models/guard3.json),
#              gen-journeys-home-subflow-* (T6R-3b, fixtures/models/guard4.json),
#              smoke-judge-* / smoke-rejudge-* (T6R-9, fixtures/smoke/, node), keptdeps-* / stepupdate-keptdeps-* (T6R-7,
#              fixtures/models/keptdeps*.json: an updated module that needs what a kept one lacks, both directions).
# Batch 4 setup (B4T2-1/2/7/12/13, B4N1-1/2/3/16): fixtures-log-* (versioned fixture logs), setup-* (setup-container.sh
#              steps over fake curl/apt-get/python/mxcli), guard-no-app-* / -names-* / -noop-*, mxrun-hostile-env-*,
#              runapp-const-* / -harness-* / -log-db-*, gate-const-* / gate-help-full-header-pass.
# LAY (layout rung): layoutdiff-* / geometry-* / layoutwalk-* (fixtures/layout, trimmed .geo.json of a real React upgrade), gate-layout-*,
#              theme-clash-dojo-table-* (Dojo mxui table rules on React scroll containers in own and vendor SCSS).
# Plan 9b: theme-clash-* (bin/theme_clash.py over fixtures/theme/: an old and new atlas_core tree plus one app-own
#              styling case per clash kind, the pass cases, the vendor skip, the no-atlas exit 3, the JSON round trip).
# Plan 6a (quality-judgement-plan.md section 3): impact-actions-* (bin/impact_actions.py over action_inventory.py's reach:
#              a two-level sub-flow chain, every source, unknown reach and the add-on, malformed input, usage).
# RM: remedy-* (bin/remedy.py over fixtures/remedy/: the 4 real blocker shapes as synthetic fixtures (DataWidgets 3
#              captions, a findDOMNode widget, a kept 3D Viewer with its own React, kept modules of every kind), the
#              remedy-tried.txt PASS/FAIL ladder, the table rules (AUTO-TRY only on A/B with apply and regate), clean).
#      remedy-apply-* (RT-10, bin/remedy_apply.sh over fixtures/remedy/apply: branch per option, FAIL abandons, pauses 5
#              for by-eye and release rows, --finish, not judged 4, --from gate) and the RT ranking, keptdeps, eye and snapshot rules.
#   start      runapp.py quick on the E1 MDA (Docker, mig-pg, heavy lock); only without --fast, SKIP when Docker,
#              mig-pg or the runtime is absent. Uses ports 8880/8890 and database fx_ctl_quick only.
#   journey    journey-control.sh: app start + Playwright, the always-on MFA journey PASSes on the E1 MDA and FAILs with
#              the planted fault EnabledMFA=false (ports 8880/8890, database fx_ctl_journey); only without --fast.
# Each control: name, expected exit code, regexes that must (or, with !, must not) occur in the output, and lines in
# expected/<name>.txt when that file exists. Exit 0 = all ran controls passed (SKIPs are listed, not failed).
set -u
# B4T1-4, B4N1-1: a worker's upg-env.sh exports UPG_EXTRA (--network host -e HTTPS_PROXY ...) and UPG_UPDATE_CMD; the
# controls inherited them and 2 mxrun controls FAILed in every sourced shell. Controls set what they need themselves.
unset UPG_EXTRA UPG_UPDATE_CMD
here=$(cd "$(dirname "$0")" && pwd)
TK=$(cd "$here/.." && pwd); B=$TK/bin; FX=$here/fixtures; EXP=$here/expected
LAB=${UPG_LAB:-$HOME/upgrade-lab}
fast=0; only=""
while [ $# -gt 0 ]; do
  case "$1" in --fast) fast=1; shift;; --only) only=$2; shift 2;; *) echo "usage: run-controls.sh [--fast] [--only REGEX]"; exit 2;; esac
done
T=$(mktemp -d "${TMPDIR:-/tmp}/upg-controls.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/m" "$T/field"
export UPG_LOCK=$T/test.lock UPG_LOCK_POLL=1   # controls never wait on the real heavy lock (except the start control)
# B4N1-2: a sourced upg-env.sh (setup-container.sh) exports UPG_EXTRA="--network host -e HTTPS_PROXY=..." and the cloud
# container exports JAVA_TOOL_OPTIONS: the container-wrapper controls then saw the run's own docker arguments. Controls set
# their own environment; these never come from the caller.
unset UPG_EXTRA UPG_ENV_FILE UPG_CA UPG_DRYRUN UPG_NAME
npass=0; nfail=0; nskip=0; failed=""; skipped=""

# ctl NAME EXIT [PATTERN ...] -- CMD ...      PATTERN: egrep regex that must occur; !REGEX must not occur
ctl() {
  local name=$1 want=$2; shift 2
  local pats=()
  while [ "$1" != "--" ]; do pats+=("$1"); shift; done; shift
  if [ -n "$only" ] && ! echo "$name" | grep -Eq "$only"; then return; fi
  local out="$T/out/$name.txt" rc ok=1 why=""
  "$@" > "$out" 2>&1; rc=$?
  [ "$rc" = "$want" ] || { ok=0; why="exit $rc, want $want"; }
  local p
  for p in ${pats[@]+"${pats[@]}"}; do
    case "$p" in
      '!'*) if grep -Eq -- "${p#!}" "$out"; then ok=0; why="$why; unexpected /${p#!}/"; fi;;
      *) if ! grep -Eq -- "$p" "$out"; then ok=0; why="$why; missing /$p/"; fi;;
    esac
  done
  if [ -f "$EXP/$name.txt" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fq -- "$line" "$out" || { ok=0; why="$why; missing expected line: $line"; }
    done < "$EXP/$name.txt"
  fi
  if [ $ok = 1 ]; then npass=$((npass + 1)); printf 'ok    %s\n' "$name"
  else nfail=$((nfail + 1)); failed="$failed $name"; printf 'FAIL  %s (%s)\n' "$name" "${why#; }"; sed 's/^/      | /' "$out" | head -15
  fi
}
# sedi SCRIPT FILE: in-place sed that works on GNU and BSD (macOS) sed, which differ on the -i suffix
sedi() { sed -i.sedi "$1" "$2" && rm -f "$2.sedi"; }
skip() { if [ -n "$only" ] && ! echo "$1" | grep -Eq "$only"; then return; fi; nskip=$((nskip + 1)); skipped="$skipped $1"; printf 'SKIP  %s (%s)\n' "$1" "$2"; }
model() { [ -f "$T/m/$1/App.mpr" ] || python3 "$here/lib/mkmodel.py" "$FX/models/$1.json" "$T/m/$1" > /dev/null || { echo "mkmodel $1 failed"; exit 2; }; echo "$T/m/$1"; }

echo "== synthetic controls ($T)"
for v in base guid-changed const-reset const-default-only missing-deps widget-descriptor widget-crc local-edit step1-adds \
         cid-zero pkg-administration xmod v9 ui-edit nav sched-old sched-new sched-gone \
         const-secret const-secret-reset logic-edit user-validation plain-validation missing-widgets xcall xcall-none xcall-java \
         keptdeps keptdeps-ok keptdeps-none keptdeps-back keptdeps-proxy roles-new-removed roles-new-dangling widgetcover; do model $v > /dev/null; done
M=$T/m

# --- gate: data identity (idcheck) ------------------------------------------------------------------------------
ctl idcheck-guid-catch 1 '^RED +GUID_CHANGED +attribute +MFAmodule\.MFA\.QR_Url' 'verdict: FAIL' -- python3 $B/idcheck.py $M/base/App.mpr $M/guid-changed/App.mpr
ctl idcheck-guid-pass 0 'verdict: PASS' '!^RED ' -- python3 $B/idcheck.py $M/base/App.mpr $M/base/App.mpr
# E5 F21: findings are listed by default (no --all needed), info lines included
echo '{"from": "'$FX'/models/base.json", "ops": [["delete", "modules/0/cross"], ["delete", "modules/0/entities/1"]]}' > $T/np-removed.json
python3 $here/lib/mkmodel.py $T/np-removed.json $M/np-removed > /dev/null
ctl idcheck-list-default-catch 0 '^info +REMOVED +entity +Administration\.AccountPasswordData' -- python3 $B/idcheck.py $M/base/App.mpr $M/np-removed/App.mpr
ctl idcheck-list-redonly-pass 0 '!AccountPasswordData' -- python3 $B/idcheck.py $M/base/App.mpr $M/np-removed/App.mpr --red-only
# E1 0: MxModelReflection drops cross-module associations: --xmod lists them per target module, so targets go last
ctl idcheck-xmod-catch 0 'Account_Device' 'MFAmodule' -- python3 $B/idcheck.py $M/xmod/App.mpr --xmod
ctl idcheck-xmod-pass 0 '!Account_Device' -- python3 $B/idcheck.py $M/base/App.mpr --xmod
# PV-2: the plan updates the TARGET of a cross-module association before the module that owns it (the owner's import
# restores the association), says so when it does not, rewrites the plan with --write, notes a kept owner, flags a cycle
model xmod-cycle > /dev/null
printf '# plan\n23513 4.2.0 Administration\n120743 1.6.0 MFAmodule\n' > $T/po-bad.txt
printf '120743 1.6.0 MFAmodule\n23513 4.2.0 Administration\n' > $T/po-good.txt
printf '120743 1.6.0 MFAmodule\n' > $T/po-kept.txt
cp $T/po-bad.txt $T/po-fix.txt
ctl planorder-owner-first-catch 1 '^ORDER Administration owns 1 association\(s\) into MFAmodule \(e\.g\. Administration\.Account_Device\): the plan updates Administration \(line 2\) before MFAmodule \(line 3\); put MFAmodule first' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-bad.txt
ctl planorder-target-first-pass 0 'order fine' '!^ORDER' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-good.txt
ctl planorder-kept-owner-note-pass 0 '^NOTE MFAmodule is planned, its owner Administration is not \(kept\)' '!^ORDER' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-kept.txt
ctl planorder-write-catch 1 'plan rewritten \(MFAmodule, Administration\)' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-fix.txt --write
ctl planorder-write-result-pass 0 'order fine' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-fix.txt
ctl planorder-write-keeps-comments-pass 0 '^# plan$' '^120743 1\.6\.0 MFAmodule$' -- cat $T/po-fix.txt
ctl planorder-cycle-catch 1 '^CYCLE ' -- python3 $B/planorder.py $M/xmod-cycle/App.mpr $T/po-good.txt
ctl planorder-no-plan-invalid 2 'no plan file' -- python3 $B/planorder.py $M/xmod/App.mpr $T/po-none.txt
# E1 19 / E5 F17: restore_guid puts the old GUID back; idcheck is then clean
cp -R $M/guid-changed $M/restored
ctl restore-guid-catch 1 'GUID_CHANGED' -- python3 $B/idcheck.py $M/base/App.mpr $M/restored/App.mpr
ctl restore-guid-apply 0 'written' -- python3 $B/restore_guid.py $M/restored/App.mpr MFAmodule.MFA.QR_Url --from $M/base/App.mpr
ctl restore-guid-pass 0 'verdict: PASS' -- python3 $B/idcheck.py $M/base/App.mpr $M/restored/App.mpr

# T5-15 / T5F-4: a KEPT module that calls the old API of a PLANNED module (microflow, Java action, generalization, Java
# import) caps that module at its current major; the plan must never move it silently
# MC-11: keptstyle lists platform widget selectors in a kept module's theme
mkdir -p $T/ks/themesource/KeptA/web $T/ks/themesource/KeptB/web
printf '/* .widget-old in a comment */\n.kepta-card { color: red; }\n.widget-datagrid .td {\n  color: blue;\n}\n.mx-listview-item,\n.kepta-x { margin: 0; }\n' > $T/ks/themesource/KeptA/web/main.scss
printf '.keptb-box .btn { color: red; }\n' > $T/ks/themesource/KeptB/web/main.scss
ctl keptstyle-catch 1 '^RISK KeptA themesource/KeptA/web/main\.scss:3 \.widget-datagrid \.td' '^RISK KeptA .*:6 \.mx-listview-item' '2 platform widget selector\(s\) in 1 module' '!widget-old' '!KeptB' -- python3 $B/keptstyle.py $T/ks --kept KeptA,KeptB
ctl keptstyle-own-classes-pass 0 '0 platform widget selector' '!RISK' -- python3 $B/keptstyle.py $T/ks --kept KeptB
ctl keptstyle-none-kept-pass 0 '0 kept module' -- python3 $B/keptstyle.py $T/ks --kept ''
ctl keptstyle-no-arg-invalid 2 'give --kept' -- python3 $B/keptstyle.py $T/ks
ctl crosscalls-flow-catch 1 '^CAP AuthMod at newest 3\.x \(installed 3\.2\.0\): called by kept KeptConn \(3 refs' 'microflow KeptConn\.ACT_Ask -> AuthMod\.ACT_Sign' 'java action KeptConn\.ACT_Java -> AuthMod\.JA_Token' 'entity KeptConn domain model -> AuthMod\.Credential' '!CAP OtherMod' -- python3 $B/crosscalls.py $M/xcall --kept KeptConn --planned AuthMod,OtherMod
ctl crosscalls-newest-catch 1 '^CAP AuthMod at 3\.9\.0 ' -- python3 $B/crosscalls.py $M/xcall --kept KeptConn --planned AuthMod --newest AuthMod=3.9.0
ctl crosscalls-none-pass 0 '0 planned module\(s\) capped' 'scanned [1-9][0-9]* documents' '!CAP ' -- python3 $B/crosscalls.py $M/xcall-none --kept KeptConn --planned AuthMod
# the caller is planned, not kept: its calls are the repair backlog, not a cap
ctl crosscalls-notkept-pass 0 '!CAP ' -- python3 $B/crosscalls.py $M/xcall --kept OtherMod --planned AuthMod
ctl crosscalls-java-catch 1 '^CAP AuthMod .*called by kept KeptConn \(1 refs, e\.g\. java import keptconn/actions/Sign\.java -> authmod\.proxies\.Credential' '1 Java files|and 1 Java files' -- python3 $B/crosscalls.py $M/xcall-java --kept KeptConn --planned AuthMod
# files the stepupdate runner writes: kept.txt (module first) and plan.txt (cid version module); same major = NOTE only
printf 'KeptConn target package made before 9.18\n' > $T/xc-kept.txt
printf '# plan\n2222 3.9.0 AuthMod\n1111 3.5.0 KeptConn\n' > $T/xc-plan-minor.txt
printf '2222 4.1.0 AuthMod\n' > $T/xc-plan-major.txt
ctl crosscalls-files-catch 1 '^CAP AuthMod .*plan 4\.1\.0\)' -- python3 $B/crosscalls.py $M/xcall --kept-file $T/xc-kept.txt --plan-file $T/xc-plan-major.txt
ctl crosscalls-same-major-pass 0 '^NOTE AuthMod 3\.2\.0 -> 3\.9\.0 keeps its major' '!CAP ' -- python3 $B/crosscalls.py $M/xcall --kept-file $T/xc-kept.txt --plan-file $T/xc-plan-minor.txt
# an input that cannot be judged is exit 2, never a silent pass: no kept option, a module that is not in the model
# PV-3: a same-major plan version is judged against its cached package: a page the kept module shows and the package no
# longer has is GONE and caps; the same page still in the package is a NOTE; no package in the cache says it was not checked
model xcall-page > /dev/null; model xcall-page-new > /dev/null; model xcall-page-keep > /dev/null
for k in gone here; do mkdir -p $T/cache-xc-$k; done
(cd $M/xcall-page-new && python3 -c "import zipfile; z=zipfile.ZipFile('$T/cache-xc-gone/2222-3.9.0.mpk','w'); z.write('App.mpr'); z.close()")
(cd $M/xcall-page-keep && python3 -c "import zipfile; z=zipfile.ZipFile('$T/cache-xc-here/2222-3.9.0.mpk','w'); z.write('App.mpr'); z.close()")
mkdir -p $T/cache-xc-none
ctl crosscalls-page-gone-catch 1 '^CAP AuthMod at 3\.2\.0 .*plan 3\.9\.0\): same major, but the 3\.9\.0 package no longer has 1 target' '^  GONE page AuthMod\.Login_Page \(used by KeptConn\.ACT_Show\)' '!GONE .*ACT_Sign' -- python3 $B/crosscalls.py $M/xcall-page --kept-file $T/xc-kept.txt --plan-file $T/xc-plan-minor.txt --cache $T/cache-xc-gone
ctl crosscalls-page-present-pass 0 '^NOTE AuthMod 3\.2\.0 -> 3\.9\.0 keeps its major.*every target exists in the plan version package' '!CAP |GONE' -- python3 $B/crosscalls.py $M/xcall-page --kept-file $T/xc-kept.txt --plan-file $T/xc-plan-minor.txt --cache $T/cache-xc-here
ctl crosscalls-page-unchecked-pass 0 '^NOTE AuthMod .*targets NOT checked against the plan version' '!CAP |GONE' -- python3 $B/crosscalls.py $M/xcall-page --kept-file $T/xc-kept.txt --plan-file $T/xc-plan-minor.txt --cache $T/cache-xc-none
ctl crosscalls-page-listed-first-catch 1 'e\.g\. page KeptConn\.ACT_Show -> AuthMod\.Login_Page; ' -- python3 $B/crosscalls.py $M/xcall-page --kept KeptConn --planned AuthMod
ctl crosscalls-no-kept-invalid 2 'give --kept' -- python3 $B/crosscalls.py $M/xcall --planned AuthMod
ctl crosscalls-unknown-module-invalid 2 'not a module of the model: Typo' -- python3 $B/crosscalls.py $M/xcall --kept KeptConn --planned Typo
ctl crosscalls-empty-kept-pass 0 'kept 0' '!CAP ' -- python3 $B/crosscalls.py $M/xcall --kept '' --planned AuthMod

# T6R-7: the other direction. An UPDATED module that needs what a KEPT module lacks (a name, a parameter of a flow, a Java
# class) is FAIL with the pair named; all names present is REVIEW (signatures unproven), never PASS; a kept module calling
# a name the update removed is FAIL too. fixtures/models/keptdeps*.json: UpdConn 4.0.0 updated, AuthMod 2.1.2 kept
ctl keptdeps-missing-catch 1 '^FAIL UpdConn 4\.0\.0 needs kept AuthMod 2\.1\.2: 3 of 12 references missing in AuthMod' 'name UpdConn\.ACT_Session -> AuthMod\.ACT_Session' 'verdict FAIL' '!OtherMod 4\.0\.0 needs' -- python3 $B/keptdeps.py $M/keptdeps --kept AuthMod --updated UpdConn,OtherMod
ctl keptdeps-param-catch 1 'parameter of microflow UpdConn\.ACT_Session -> AuthMod\.ACT_Sign\.SessionToken' '!-> AuthMod\.ACT_Sign\.Endpoint\b.*missing' -- python3 $B/keptdeps.py $M/keptdeps --kept AuthMod --updated UpdConn
ctl keptdeps-java-catch 1 'java import updconn/actions/Translate\.java -> authmod\.impl\.RegionBuilder' '!-> authmod\.proxies\.Credential' -- python3 $B/keptdeps.py $M/keptdeps --kept AuthMod --updated UpdConn
ctl keptdeps-review 1 '^REVIEW UpdConn 4\.0\.0 needs kept AuthMod 2\.1\.2: 8 references, all present by name' 'verdict REVIEW' '!^FAIL ' -- python3 $B/keptdeps.py $M/keptdeps-ok --kept AuthMod --updated UpdConn
# NR2-12: generated proxy classes are not tracked files; judge them against the model (microflow by call, entity by name)
ctl keptdeps-proxy-catch 1 'java import updconn/actions/Translate\.java -> authmod\.proxies\.microflows\.Microflows\.gone' '!-> authmod\.proxies\.Credential.*missing' '!Microflows\.aCT_Sign.*missing' -- python3 $B/keptdeps.py $M/keptdeps-proxy --kept AuthMod --updated UpdConn
ctl keptdeps-none-pass 0 'verdict PASS \(0 FAIL, 0 REVIEW pair\(s\); 2 of 2 updated' 'scanned [1-9][0-9]* documents' '!^(FAIL|REVIEW) ' -- python3 $B/keptdeps.py $M/keptdeps-none --kept AuthMod --updated UpdConn,OtherMod
ctl keptdeps-calls-missing-catch 1 '^FAIL kept AuthMod 2\.1\.2 calls updated UpdConn 4\.0\.0: 1 of 1 references missing in UpdConn \(e\.g\. name AuthMod\.ACT_Back -> UpdConn\.ACT_Gone' -- python3 $B/keptdeps.py $M/keptdeps-back --kept AuthMod --updated UpdConn
ctl keptdeps-both-lists-kept 1 'treated as kept' 'updated 1 \(UpdConn\)' -- python3 $B/keptdeps.py $M/keptdeps-ok --kept AuthMod --updated AuthMod,UpdConn
# input that cannot be judged is exit 2, never a silent pass
ctl keptdeps-no-kept-invalid 2 'give --kept' -- python3 $B/keptdeps.py $M/keptdeps --updated UpdConn
ctl keptdeps-no-updated-invalid 2 'give --updated' -- python3 $B/keptdeps.py $M/keptdeps --kept AuthMod
ctl keptdeps-unknown-module-invalid 2 'not a module of the model: Typo' -- python3 $B/keptdeps.py $M/keptdeps --kept Typo --updated UpdConn
ctl keptdeps-no-git-invalid 2 'updated-from-git: .*nothing judged' -- python3 $B/keptdeps.py $M/keptdeps --kept AuthMod --updated-from-git
# stepupdate's files: kept.txt (module first) and the "step: <Module> <version>" commits
mkdir -p $T/kdg; cp -R $M/keptdeps/. $T/kdg/; printf 'AuthMod target package made before 9.18\n' > $T/kdg-kept.txt
(cd $T/kdg && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm base && git -c user.email=c@c -c user.name=ctl commit -q --allow-empty -m 'step: UpdConn 4.0.0 (idcheck PASS)')
ctl keptdeps-from-git-catch 1 'updated 1 \(UpdConn\)' '^FAIL UpdConn 4\.0\.0 needs kept AuthMod' -- python3 $B/keptdeps.py $T/kdg --kept-file $T/kdg-kept.txt --updated-from-git

# --- gate: constants (E1 16) -------------------------------------------------------------------------------------
ctl constcheck-reset-catch 1 'CHANGED +MFAmodule\.EnabledMFA' -- python3 $B/constcheck.py $M/base $M/const-reset
ctl constcheck-same-pass 0 'FAIL 0' -- python3 $B/constcheck.py $M/base $M/base
ctl constcheck-default-catch 1 'CHANGED +MFAmodule\.Issuer' -- python3 $B/constcheck.py $M/base $M/const-default-only
echo '{"MFAmodule.Issuer": "set-by-environment"}' > $T/overrides.json
ctl constcheck-override-pass 0 'INFO +CHANGED +MFAmodule\.Issuer.*environment overrides' -- python3 $B/constcheck.py $M/base $M/const-default-only --overrides $T/overrides.json
ctl constcheck-secret-pass 0 '!MinLengthValue' -- python3 $B/constcheck.py $M/base $M/base
# --restore-to: the old values of reset constants go into a 0600 MDL file, never to the output (E4-25)
ctl constcheck-restore-secret-catch 1 'CHANGED +Administration\.KeystorePassword +set \(19 chars\) -> empty' 'restore: 1 statement.*mode 0600' '!old-k3y' -- python3 $B/constcheck.py $M/const-secret $M/const-secret-reset --restore-to $T/restore.mdl
ctl constcheck-restore-file-pass 0 "^CREATE OR MODIFY CONSTANT Administration\.KeystorePassword TYPE String DEFAULT 'old-k3y''store-value';$" '^-rw-------' -- sh -c "cat $T/restore.mdl; ls -l $T/restore.mdl"
ctl constcheck-restore-config-pass 1 "restore: 1 statement" -- python3 $B/constcheck.py $M/base $M/const-reset --restore-to $T/restore2.mdl
ctl constcheck-restore-config-file-pass 0 "^ALTER SETTINGS CONSTANT 'MFAmodule\.EnabledMFA' VALUE 'True' IN CONFIGURATION 'Default';$" -- cat $T/restore2.mdl

# --- gate: start log beyond ERROR lines (E1 18, E1 24) -------------------------------------------------------------
ctl logdiff-mfa-off-catch 1 'REVIEW +CHANGED.*MFA module login NOT active' 'was: .*MFA module login active' -- python3 $B/logdiff.py $FX/logs/old.log $FX/logs/new-mfa-off.log
ctl logdiff-same-pass 0 'FAIL 0 \| REVIEW 0' -- python3 $B/logdiff.py $FX/logs/old.log $FX/logs/new-same.log
ctl logdiff-start-failed-catch 1 'FAIL +START_FAILED' 'deprecated' -- python3 $B/logdiff.py $FX/logs/old.log $FX/logs/new-start-failed.log
# an ERROR logged after the start window before and inside it now is MOVED (REVIEW), not NEW_ERROR (E4 24)
ctl logdiff-moved-pass 1 'REVIEW +MOVED +ERROR SAML_SSO' '!NEW_ERROR' -- python3 $B/logdiff.py $FX/logs/old-lazy-error.log $FX/logs/new-early-error.log
ctl logdiff-new-error-catch 1 'FAIL +NEW_ERROR +ERROR SAML_SSO' -- python3 $B/logdiff.py $FX/logs/old.log $FX/logs/new-early-error.log
ctl logdiff-moved-other-error-catch 1 'FAIL +NEW_ERROR +ERROR Connector' -- python3 $B/logdiff.py $FX/logs/old-lazy-error.log $FX/logs/new-other-error.log

# --- gate: data diff (diff.py): System.owner sets (E1 22), NEW_ENDPOINT (E5 F20), narrow allow (E5 F20), contract (E5 F4), log.start (E1 24)
python3 $here/lib/mksnap.py $FX/snaps/before.json --log $FX/logs/old.log > $T/sb.json
python3 $here/lib/mksnap.py $FX/snaps/after-ok.json --log $FX/logs/new-same.log > $T/sa.json
python3 $here/lib/mksnap.py $FX/snaps/after-bad.json --log $FX/logs/new-same.log > $T/sbad.json
python3 $here/lib/mksnap.py $FX/snaps/after-ok.json --log $FX/logs/new-start-failed.log > $T/sfail.json
python3 - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
s = json.load(open(f"{t}/sa.json")); s["db"]["idsets"]["assoc:System.owner"].remove("0001-owner-account"); json.dump(s, open(f"{t}/s-owner-lost.json", "w"))
s = json.load(open(f"{t}/sa.json")); s["db"]["idsets"]["assoc:System.owner"].reverse(); json.dump(s, open(f"{t}/s-owner-order.json", "w"))
EOF
# PLM-26: module roles a module update added that no user role holds (Atlas_Core 3.21: User, Administrator)
printf 'Atlas_Core.User # mapped by hand after the gate\n' > $T/roles-waive.txt; printf 'Atlas_Core.User\n' > $T/roles-waive-bad.txt
ctl rolecheck-unmapped-catch 1 'UNMAPPED +Atlas_Core\.User .*Atlas_Core 3\.12\.6 -> 3\.12\.6.*held by no user role; proposal: user roles holding another Atlas_Core role: Clerk' 'UNMAPPED +Atlas_Core\.Administrator .*roles holding a role named Administrator in another module: Boss' '2 unmapped' 'verdict: REVIEW' '!Viewer' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-unmapped)
ctl rolecheck-mapped-pass 0 '2 module role\(s\) added by the update, 0 unmapped' 'mapped +Atlas_Core\.User +held by Clerk' '!UNMAPPED' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-mapped)
ctl rolecheck-waived-pass 1 'WAIVED +Atlas_Core\.User +\(mapped by hand' 'UNMAPPED +Atlas_Core\.Administrator' '1 unmapped' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-unmapped) --waive $T/roles-waive.txt
ctl rolecheck-waive-no-reason-invalid 2 'has no reason after' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-unmapped) --waive $T/roles-waive-bad.txt
ctl rolecheck-no-change-pass 0 '0 module role\(s\) added' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-old)
# MC-8, MC-9: a mapped module role that the update removed, and a reference to a role that never existed (mxcli wrote one)
ctl rolecheck-removed-mapped-catch 1 'REMOVED-MAPPED +Atlas_Core\.Viewer +removed by the update, still held by user role Clerk; Atlas_Core now has: User' '1 mapped role\(s\) that no longer exist' 'verdict: REVIEW' '!UNMAPPED' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-removed)
ctl rolecheck-dangling-catch 1 'DANGLING +Atlas_Core\.Ghost +held by user role Clerk but Atlas_Core has no such module role \(it has: Viewer\)' 'verdict: REVIEW' '!REMOVED-MAPPED' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-dangling)
ctl rolecheck-dangling-alone-catch 1 'DANGLING +Atlas_Core\.Ghost' -- python3 $B/rolecheck.py $(model roles-new-dangling) $(model roles-new-dangling)
printf 'Atlas_Core.Viewer # replaced by User, mapping dropped in the next commit\n' > $T/roles-waive-gone.txt
ctl rolecheck-removed-waived-pass 0 'WAIVED +Atlas_Core\.Viewer +\(replaced by User' '0 mapped role\(s\) that no longer exist' '!REMOVED-MAPPED' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-removed) --waive $T/roles-waive-gone.txt
ctl rolecheck-removed-unheld-pass 0 '0 mapped role\(s\) that no longer exist' '!REMOVED-MAPPED' -- python3 $B/rolecheck.py $(model roles-old) $(model roles-new-mapped)
# PLM-27: the Mx10 runtime deletes Anonymous_* users at start: one known-behaviour row, named users judged apart.
python3 - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
def anon(side, users, total, name_nn):
    return {"users": users, "total": total, "attrs": {"System.User.Name": {"nonnull": name_nn, "md5": "n3"}, "System.User.IsAnonymous": {"nonnull": name_nn, "md5": "f3"}},
            "assoc": {"System.UserRoles": {"pairs": name_nn, "md5": "r3"}}}
for nm, a_total, a_users, a_named in (("anon-ok", 3, 0, 3), ("anon-named-lost", 2, 0, 2)):
    b = json.load(open(f"{t}/sb.json")); a = json.load(open(f"{t}/sa.json"))
    b["db"]["entities"]["System.User"] = 21; a["db"]["entities"]["System.User"] = a_total
    for d, tot, nn in ((b, 21, 3), (a, a_total, a_named)):
        d["db"]["attributes"]["System.User.Name"] = {"nonnull": tot, "md5": "all%d" % tot}
        d["db"]["attributes"]["System.User.IsAnonymous"] = {"nonnull": tot, "md5": "x%d" % tot}
        d["db"]["associations"]["System.UserRoles"] = {"pairs": tot, "md5": "u%d" % tot}
    b["db"]["anonymous"] = anon("b", 18, 21, 3); a["db"]["anonymous"] = anon("a", a_users, a_total, a_named)
    if nm == "anon-named-lost":
        a["db"]["anonymous"]["attrs"]["System.User.Name"]["nonnull"] = 2
    json.dump(b, open(f"{t}/{nm}-b.json", "w")); json.dump(a, open(f"{t}/{nm}-a.json", "w"))
    for d in (b, a): del d["db"]["anonymous"]
    json.dump(b, open(f"{t}/{nm}-old-b.json", "w")); json.dump(a, open(f"{t}/{nm}-old-a.json", "w"))
EOF
ctl diff-anonymous-users-grouped-pass 0 'PASS\* \| db\.known\.anonymous_users \| 18 anonymous System\.User rows gone \(18 -> 0\)' '!FAIL \| db\.(attr|assoc|entity)\.System\.User' 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/anon-ok-b.json $T/anon-ok-a.json --allow $FX/allow/narrow.txt
ctl diff-anonymous-named-lost-catch 1 'FAIL \| db\.attr\.System\.User\.Name \| non-null 3 -> 2 \(named users\)' 'FAIL \| db\.entity\.System\.User \| named user rows 3 -> 2' -- python3 $B/diff.py $T/anon-named-lost-b.json $T/anon-named-lost-a.json --allow $FX/allow/narrow.txt
ctl diff-anonymous-old-snapshot-catch 1 'FAIL \| db\.entity\.System\.User \| rows 21 -> 3 \(if these are Anonymous_\* users' '!known\.anonymous' -- python3 $B/diff.py $T/anon-ok-old-b.json $T/anon-ok-old-a.json --allow $FX/allow/narrow.txt
ctl diff-owner-catch 1 'FAIL \| db\.identity\.assoc:System\.owner' -- python3 $B/diff.py $T/sb.json $T/s-owner-lost.json --allow $FX/allow/narrow.txt
ctl diff-owner-pass 0 '!System\.owner' 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sb.json $T/s-owner-order.json --allow $FX/allow/narrow.txt
ctl diff-new-endpoint-catch 2 'NEW_ENDPOINT \| http\./rest-doc/notify/openapi\.json' -- python3 $B/diff.py $T/sb.json $T/sa.json --allow $FX/allow/email-only.txt
ctl diff-allowlist-pass 0 'PASS\* \| http\./rest-doc/notify/openapi\.json' 'PASS\* \| db\.attr\.Administration\.Account\.Email' -- python3 $B/diff.py $T/sb.json $T/sa.json --allow $FX/allow/narrow.txt
ctl diff-allow-detail-catch 1 'FAIL \| db\.attr\.Administration\.Account\.Email \| values changed' -- python3 $B/diff.py $T/sb.json $T/sa.json --allow $FX/allow/wrong-detail.txt
# PV-7: the restart control. diff --emit-allow turns the FAIL rows between two starts of the SAME old app into allow lines
# (start noise); fed back as --allow they leave 0 FAIL, and a clean pair writes an empty file.
ctl diff-emit-allow-catch 1 '^--emit-allow: [1-9][0-9]* check\(s\) written' -- python3 $B/diff.py $T/sb.json $T/sa.json --emit-allow $T/noise.txt
ctl diff-emit-allow-lines-pass 0 'db\.attr\.Administration\.Account\.Email values changed[^#]* # start noise: differs between two starts of the same old app \(' -- cat $T/noise.txt
ctl diff-emit-allow-roundtrip-pass 2 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sb.json $T/sa.json --allow $T/noise.txt
ctl diff-emit-allow-clean-pass 0 '^--emit-allow: 0 check\(s\)' -- python3 $B/diff.py $T/sb.json $T/sb.json --db-only --emit-allow $T/noise-clean.txt
# NMR-1: the emitted line carries the noise row's own detail, so one noise error accepts that error only, never every new error
{ cat $FX/logs/old.log; echo "2026-09-14 10:16:02.296 ERROR - Cache: NoiseError: cache warmup"; } > $T/old-noise.log
{ cat $FX/logs/new-same.log; echo "2026-09-14 10:16:02.296 ERROR - Cache: NoiseError: cache warmup"; echo "2026-09-14 10:16:02.396 ERROR - ACT_Save: NullPointerException in ACT_Save"; } > $T/new-npe.log
python3 $here/lib/mksnap.py $FX/snaps/before.json --log $T/old-noise.log > $T/sr-noise.json
python3 $here/lib/mksnap.py $FX/snaps/after-ok.json --log $T/new-npe.log > $T/sa-npe.json
ctl diff-emit-allow-detail-pass 1 '^--emit-allow: 1 check' -- python3 $B/diff.py $T/sb.json $T/sr-noise.json --emit-allow $T/noise-npe.txt
ctl diff-emit-allow-detail-line-pass 0 '^log\.new_error 1x ERROR Cache: NoiseError: cache warmup # start noise' -- cat $T/noise-npe.txt
ctl diff-emit-allow-npe-catch 1 'FAIL \| log\.new_error \| 1x ERROR ACT_Save: NullPointerException' '!PASS\* \| log\.new_error \| 1x ERROR ACT_Save' -- python3 $B/diff.py $T/sb.json $T/sa-npe.json --allow $T/noise-npe.txt
ctl diff-emit-allow-noise-accepted-pass 1 'PASS\* \| log\.new_error \| 1x ERROR Cache: NoiseError: cache warmup \(accepted: start noise' -- python3 $B/diff.py $T/sb.json $T/sa-npe.json --allow $T/noise-npe.txt
ctl diff-contract-catch 1 'contract lost: POST /rest/notify/v1/message' 'model id gone' -- python3 $B/diff.py $T/sb.json $T/sbad.json --allow $FX/allow/narrow.txt
# E6-11, E7-18: the mutant control compares a db-only snapshot; --db-only drops the http and log noise, keeps the planted FAIL
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [d.pop(k, None) for k in ('http','log','admin')]; json.dump(d, open(sys.argv[2],'w'))" $T/s-owner-lost.json $T/s-mutant-dbonly.json
ctl diff-mutant-noise-catch 1 'FAIL \| http\..*endpoint not probed' -- python3 $B/diff.py $T/sb.json $T/s-mutant-dbonly.json --allow $FX/allow/narrow.txt
ctl diff-db-only-pass 1 'FAIL \| db\.identity\.assoc:System\.owner' '!\| http\.' '!\| log' '--db-only: http, log' -- python3 $B/diff.py $T/sb.json $T/s-mutant-dbonly.json --allow $FX/allow/narrow.txt --db-only
ctl diff-db-only-clean-pass 0 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sb.json $T/sb.json --allow $FX/allow/narrow.txt --db-only
# E7-17: a body with a random uuid changes the md5 per call; diff.py compares status and JSON shape, never the body md5
python3 -c "
import json,sys; d=json.load(open(sys.argv[1])); e=json.loads(json.dumps(d))
d.setdefault('http',{})['/rest/v1/random']={'status':400,'md5':'aaa','bytes':80}; e.setdefault('http',{})['/rest/v1/random']={'status':400,'md5':'bbb','bytes':80}
d['http']['/rest/v1/okrandom']={'status':200,'md5':'aaa','shape':{'id':'str'}}; e['http']['/rest/v1/okrandom']={'status':200,'md5':'ccc','shape':{'id':'str'}}
json.dump(d,open(sys.argv[2],'w')); json.dump(e,open(sys.argv[3],'w'))" $T/sb.json $T/sr-b.json $T/sr-a.json
ctl diff-random-body-pass 0 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sr-b.json $T/sr-a.json --allow $FX/allow/narrow.txt
python3 -c "import json,sys; e=json.load(open(sys.argv[1])); e['http']['/rest/v1/okrandom']['shape']={'uuid':'str'}; json.dump(e,open(sys.argv[2],'w'))" $T/sr-a.json $T/sr-a2.json
ctl diff-random-body-shape-catch 1 'FAIL \| http\./rest/v1/okrandom \| JSON shape changed' -- python3 $B/diff.py $T/sr-b.json $T/sr-a2.json --allow $FX/allow/narrow.txt
ctl diff-logstart-catch 1 'FAIL \| log\.start\.START_FAILED' 'REVIEW \| log\.start\.GONE' -- python3 $B/diff.py $T/sb.json $T/sfail.json --allow $FX/allow/narrow.txt
# diff.py reads the logdiff allow file for its log.start rows; MOVED reaches diff.py through the snapshots (E4 23, E4 24)
python3 $here/lib/mksnap.py $FX/snaps/before.json --log $FX/logs/old-lazy-error.log > $T/sb-lazy.json
python3 $here/lib/mksnap.py $FX/snaps/after-ok.json --log $FX/logs/new-early-error.log > $T/sa-early.json
ctl diff-log-moved-review-catch 1 'REVIEW \| log\.start\.MOVED' '!log\.start\.NEW_ERROR' -- python3 $B/diff.py $T/sb-lazy.json $T/sa-early.json --allow $FX/allow/narrow.txt
ctl diff-log-allow-pass 0 'PASS\* \| log\.start\.MOVED .*accepted: moved' 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sb-lazy.json $T/sa-early.json --allow $FX/allow/narrow.txt --log-allow $FX/allow/log-moved.txt
# E4-23: a REVIEW row is accepted in allow.txt like a FAIL row, prints PASS* with its reason, and diff exits 0
ctl diff-review-accepted-pass 0 'PASS\* \| log\.start\.MOVED .*accepted: the module initialises' 'FAIL 0 \| REVIEW 0' -- python3 $B/diff.py $T/sb-lazy.json $T/sa-early.json --allow $FX/allow/review-accepted.txt

# --- REST contracts across Swagger 2 (9.x) and OpenAPI 3 (10.x) (E5 F4) -------------------------------------------
ctl restcontract-kept-pass 0 '^PASS' -- python3 $B/restcontract.py $FX/rest/swagger-9.json $FX/rest/openapi-10-kept.json
ctl restcontract-lost-catch 1 'DELETE /rest/notify/v1/message/\{id\}' 'tenant' -- python3 $B/restcontract.py $FX/rest/swagger-9.json $FX/rest/openapi-10-lost.json
ctl restcontract-input-catch 2 'not a Swagger/OpenAPI' -- python3 $B/restcontract.py $FX/rest/swagger-9.json $FX/scan/covered.json

# --- triage: scanner coverage (E5 F1, E1 6) --------------------------------------------------------------------------
ctl scancover-catch 1 'NO COVERAGE' 'javafinal' -- python3 $B/scancover.py $FX/scan/no-coverage.json
ctl scancover-pass 0 '^COVERED' -- python3 $B/scancover.py $FX/scan/covered.json
ctl scancover-input-catch 2 'not a scan.py findings.json' -- python3 $B/scancover.py $FX/scan/not-a-scan.json

# --- triage: local edits offline (E5 F2, E1 5, E5 F13) ----------------------------------------------------------------
mkdir -p $T/cache
(cd $M/pkg-administration && python3 -c "import zipfile; z=zipfile.ZipFile('$T/cache/23513-4.1.0.mpk','w'); z.write('App.mpr'); z.close()")
cp $T/cache/23513-4.1.0.mpk $T/cache/23513-4.0.0.mpk
cp $T/cache/23513-4.1.0.mpk $T/cache/23513-3.0.0.mpk
export UPG_CACHE=$T/cache UPG_MXCLI=/usr/bin/false
ctl localedits-unknown-catch 2 'UNKNOWN' -- python3 $B/localedits.py $M/base/App.mpr
ctl localedits-cid0-catch 2 'give --cid' -- python3 $B/localedits.py $M/cid-zero/App.mpr --module Administration
ctl localedits-cid-pass 0 'unchanged' -- python3 $B/localedits.py $M/cid-zero/App.mpr --module Administration --cid Administration=23513
ctl localedits-edit-catch 1 'RED.*Administration\.Account\.Department' -- python3 $B/localedits.py $M/local-edit/App.mpr --module Administration
ctl localedits-clean-pass 0 'unchanged' '!^ +RED ' -- python3 $B/localedits.py $M/base/App.mpr --module Administration
# NR2-3 / NR2-10: an MPR v2 project (Contents column gone, units in mprcontents/) is read like an MPR v1 by localedits and smokewalk_gen
python3 $here/lib/mkv2.py $M/base $M/base-v2; model guard > /dev/null; python3 $here/lib/mkv2.py $M/guard $M/guard-v2
ctl localedits-mpr-v2-pass 0 'unchanged' '!^ +RED ' '!no such column' -- python3 $B/localedits.py $M/base-v2/App.mpr --module Administration
ctl smokewalk-gen-mpr-v2-pass 0 '^Worker: 3 page steps' '^Planner: 1 page steps, 1 microflow steps' '!no such column' -- python3 $B/smokewalk_gen.py $M/guard-v2/App.mpr -o $T/guard-v2-plan.json
# PV-6: a role whose home is a microflow gets a WARN (the runner skips microflow steps without --microflows)
ctl smokewalk-gen-microflow-home-warn-catch 0 '^WARN Planner: its home is a microflow: smokewalk\.js SKIPS microflow steps unless run with --microflows' '!^WARN Worker' -- python3 $B/smokewalk_gen.py $M/guard-v2/App.mpr -o $T/guard-v2-plan-w.json
# FM-6: the demo-data reset page never goes into a smoke plan (it opens a confirmation that rewrites data); it is listed under skipped
# a smoke shots folder kept from an earlier walk: the new shot of a step removes the same step under another suffix
mkdir -p "$T/stale-shots" && : > "$T/stale-shots/smoke-home-X.png" && : > "$T/stale-shots/smoke-home-X.txt" && : > "$T/stale-shots/smoke-other-Y.png"
ctl smokewalk-stale-shot-removed-pass 0 '^smoke-home-X-NOT-REACHED\.png$' '^smoke-other-Y\.png$' '!^smoke-home-X\.png$' '!^smoke-home-X\.txt$' -- node -e "
const fs=require('fs'),path=require('path');const src=fs.readFileSync('$B/smokewalk.js','utf8');
const fn=src.slice(src.indexOf('// BEGIN clearStaleShots'),src.indexOf('// END clearStaleShots'));
eval(fn+';clearStaleShots(\\'$T/stale-shots\\',\\'smoke-home-X-NOT-REACHED.png\\');fs.writeFileSync(\\'$T/stale-shots/smoke-home-X-NOT-REACHED.png\\',\\'\\');');
fs.readdirSync('$T/stale-shots').forEach(f=>console.log(f));"
ctl smokewalk-gen-demodata-excluded-catch 0 '^Admin: 2 page steps' '1 steps skipped' -- python3 $B/smokewalk_gen.py $(model smoke-exclude)/App.mpr -o $T/smoke-excl-plan.json
ctl smokewalk-gen-demodata-skipped-reason-pass 0 'excluded by pattern DemoData\*' '^Overview$' '!^DemoData_CreateByAdmin$' -- python3 -c "import json; p=json.load(open('$T/smoke-excl-plan.json'))['roles'][0]; print(p['skipped'][0]['why']); [print(s['caption']) for s in p['steps'] if s['via']=='menu']"
ctl smokewalk-gen-no-default-excludes-pass 0 '^Admin: 3 page steps' '0 steps skipped' -- python3 $B/smokewalk_gen.py $(model smoke-exclude)/App.mpr -o $T/smoke-excl-plan2.json --no-default-excludes
ctl smokewalk-gen-exclude-option-catch 0 '^Admin: 1 page steps' '2 steps skipped' -- python3 $B/smokewalk_gen.py $(model smoke-exclude)/App.mpr -o $T/smoke-excl-plan3.json --exclude 'Overview'
ctl smokewalk-gen-excluded-widget-pass 0 '^DemoData\*$' '^$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import smokewalk_gen as g; print(g.excluded('Shop.DemoData_X','w')); print(g.excluded('Shop.Orders','actionButton1'))"
ctl localedits-proxy-catch 1 'PROXY: compared with 4\.0\.0' -- python3 $B/localedits.py $M/local-edit/App.mpr --module Administration --proxy Administration=4.0.0
# E5b-5: a proxy a major version away says so; a proxy in the same major does not
ctl localedits-proxy-major-catch 1 'PROXY: compared with 3\.0\.0.*3\.0\.0 is a major version away from 4\.1\.0' -- python3 $B/localedits.py $M/local-edit/App.mpr --module Administration --proxy Administration=3.0.0
ctl localedits-proxy-minor-pass 1 'PROXY: compared with 4\.0\.0' '!major version away' -- python3 $B/localedits.py $M/local-edit/App.mpr --module Administration --proxy Administration=4.0.0
# E5b-19: pages and layouts of vendor modules, app vs package; E4-3: a module mxcli diff could not judge is UNKNOWN (exit 2)
ctl localedits-ui-layout-catch 0 'ui +CHANGED +page +Administration\.Account_Overview +layout .*MyFirstModule\.Layout_App' 'ui +ADDED +page +Administration\.Account_Extra' 'force-ui: Administration' -- python3 $B/localedits.py $M/ui-edit/App.mpr --module Administration
ctl localedits-ui-pass 0 'UI edits \(pages, layouts\): 0' 'force-ui: none' -- python3 $B/localedits.py $M/base/App.mpr --module Administration
# PLM-29: a local edit INSIDE a vendor layout (a region replaced, a snippet call removed) with the page layout reference
# unchanged and mxcli diff UNKNOWN (UPG_MXCLI=false stands for a package made before 9.18). The content signature sees it.
model layout-edit-app > /dev/null; model layout-edit-pkg > /dev/null; model layout-same-app > /dev/null
mkdir -p $T/cache-lay
(cd $M/layout-edit-pkg && python3 -c "import zipfile; z=zipfile.ZipFile('$T/cache-lay/23513-4.1.0.mpk','w'); z.write('App.mpr'); z.close()")
ctl localedits-layout-content-catch 0 'ui +CHANGED +layout +Administration\.Layout_Main +content differs from the package; local: .*RegionTopbar; package only: .*FeedbackCall' 'force-ui: Administration' -- env UPG_CACHE=$T/cache-lay python3 $B/localedits.py $M/layout-edit-app/App.mpr --module Administration
ctl localedits-layout-content-pass 0 'UI edits \(pages, layouts\): 0' 'force-ui: none' -- env UPG_CACHE=$T/cache-lay python3 $B/localedits.py $M/layout-same-app/App.mpr --module Administration
# PV-1: a constant that shares its qualified name with a page (MFAmodule.Shared) is found by type, not shadowed
model const-shadowed > /dev/null
ctl mprmodel-constant-shadowed-catch 0 "^\{'default': 'True', 'type': 'Boolean', 'exposed': False\}$" '^Forms\$Page$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import mprmodel; m=mprmodel.Model.load('$M/const-shadowed'); print(m.constant('MFAmodule.Shared')); print(m.docs['MFAmodule.Shared'].type)"
ctl mprmodel-constant-plain-pass 0 "^\{'default': 'False', 'type': 'Boolean', 'exposed': False\}$" '^None$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import mprmodel; m=mprmodel.Model.load('$M/const-shadowed'); print(m.constant('MFAmodule.EnabledMFA')); print(m.constant('MFAmodule.NoSuch'))"
# PLM-1: --mxcli-diff on a 9.x model is refused with one line; on 10.x it is not
ctl localedits-mxcli-diff-9x-catch 2 'needs a model of Mendix 10\.0 or newer, this one is 9\.24\.32\.58223' -- python3 $B/localedits.py $M/v9/App.mpr --mxcli-diff
ctl localedits-mxcli-diff-10x-pass 2 'UNKNOWN \(rc=0\)' '!needs a model of Mendix 10' -- env UPG_MXCLI=false python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd true
# PLM-30: restoreunit puts a document back from a baseline MPR (v1 and v2); dry run first, refusals write nothing
RU=$T/ru; mkdir -p $RU; cp -R $M/layout-edit-pkg $RU/tgt1; cp -R $M/layout-edit-pkg $RU/tgt-dry
python3 $here/lib/mkv2.py $M/layout-edit-app $RU/old2; python3 $here/lib/mkv2.py $M/layout-edit-pkg $RU/tgt2
ctl restoreunit-dry-run-catch 0 'RESTORE Administration\.Layout_Main' 'dry run, 1 document' -- python3 $B/restoreunit.py $M/layout-edit-app/App.mpr $RU/tgt-dry/App.mpr Administration.Layout_Main
ctl restoreunit-apply-pass 0 'restored 1 document\(s\), re-read and verified' -- python3 $B/restoreunit.py $M/layout-edit-app/App.mpr $RU/tgt1/App.mpr Administration.Layout_Main --apply
ctl restoreunit-edit-back-catch 0 "ui +CHANGED +layout +Administration\\.Layout_Main +content differs" -- env UPG_CACHE=$T/cache-lay python3 $B/localedits.py $RU/tgt1/App.mpr --module Administration
ctl restoreunit-again-same-pass 1 'SAME +Administration\.Layout_Main' 'nothing to do' -- python3 $B/restoreunit.py $M/layout-edit-app/App.mpr $RU/tgt1/App.mpr Administration.Layout_Main
ctl restoreunit-missing-doc-catch 2 'REFUSED Administration\.Nope' 'nothing written' -- python3 $B/restoreunit.py $M/layout-edit-app/App.mpr $RU/tgt-dry/App.mpr Administration.Nope --apply
ctl restoreunit-v2-apply-pass 0 'restored 1 document\(s\)' -- python3 $B/restoreunit.py $RU/old2/App.mpr $RU/tgt2/App.mpr Administration.Layout_Main --apply
ctl restoreunit-v2-again-same-pass 1 'SAME +Administration\.Layout_Main' -- python3 $B/restoreunit.py $RU/old2/App.mpr $RU/tgt2/App.mpr Administration.Layout_Main
# E5b-28: documents deleted or added locally (logic layer) and validation rules on a System.User specialization
ctl localedits-logic-catch 0 'logic +ADDED +microflow +Administration\.ACT_LocalAudit' 'LOGIC edits \(documents added or deleted, contents not compared\): 1' 'force-ui: none' -- python3 $B/localedits.py $M/logic-edit/App.mpr --module Administration
ctl localedits-logic-pass 0 'LOGIC edits \(documents added or deleted, contents not compared\): 0' -- python3 $B/localedits.py $M/base/App.mpr --module Administration
ctl localedits-user-validation-catch 1 '^ +RED +CHANGED +entity +Administration\.Account +validation rules \(\+Unique Email\) on a System\.User specialization' -- python3 $B/localedits.py $M/user-validation/App.mpr --module Administration
ctl localedits-plain-validation-pass 0 '^ +info CHANGED +entity +Administration\.AccountPasswordData +validation rules \(\+Required NewPassword\) \(behaviour' '!^ +RED ' -- python3 $B/localedits.py $M/plain-validation/App.mpr --module Administration
FD="python3 $here/lib/fakemxdiff.py"
echo '[{"name": "Administration", "elements_error": "The package could not be imported, because it was created with version 9.3.0 of Mendix Studio Pro."}]' > $T/fd-err.json
echo '[{"name": "Administration", "elements": {"verified": false, "modified": [], "unknown": [{"element": "BUILDING_BLOCK A"}], "onlyInstalled": ["JAR_DEPENDENCY a:b"]}}]' > $T/fd-jar.json
ctl localedits-mxdiff-unknown-catch 2 'mxcli diff: UNKNOWN \(package made before 9\.18' 'UNKNOWN \(not judged\): 1' -- env FAKE_DIFF=$T/fd-err.json python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
ctl localedits-mxdiff-pass 0 'mxcli diff: 0 modified' 'UNKNOWN \(not judged\): 0' -- python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
ctl localedits-mxdiff-unverified-catch 0 'verified=false \(1 elements not describable\), jar-only edits' 'force-ui: Administration' -- env FAKE_DIFF=$T/fd-jar.json python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
# a modified microflow / nanoflow / action / workflow / rule is logic: the module stays OFF the force-ui line (string and dict entries)
echo '[{"name": "Administration", "elements": {"verified": true, "modified": ["MICROFLOW Administration.ACT_Edited"], "unknown": [], "onlyInstalled": []}}]' > $T/fd-mf.json
echo '[{"name": "Administration", "elements": {"verified": true, "modified": [{"type": "JAVASCRIPT_ACTION", "name": "Administration.JS_Edited"}], "unknown": [], "onlyInstalled": []}}]' > $T/fd-js.json
echo '[{"name": "Administration", "elements": {"verified": true, "modified": [{"type": "PAGE", "name": "Administration.Page_Edited"}], "unknown": [], "onlyInstalled": []}}]' > $T/fd-pg.json
ctl localedits-mxdiff-logic-string-catch 0 'mxcli diff: 1 modified.*1 of them logic' 'force-ui: none' -- env FAKE_DIFF=$T/fd-mf.json python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
ctl localedits-mxdiff-logic-dict-catch 0 '1 of them logic' 'force-ui: none' -- env FAKE_DIFF=$T/fd-js.json python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
ctl localedits-mxdiff-page-modified-pass 0 'mxcli diff: 1 modified' 'force-ui: Administration' '!of them logic' -- env FAKE_DIFF=$T/fd-pg.json python3 $B/localedits.py $M/base/App.mpr --module Administration --mxcli-diff --mxcli-cmd "$FD"
# batch 1 (T3-2, T5-2, T7-2, T8-5): a TLS handshake timeout is retried, and when it stays it is NETWORK with a rerun
# line, never UNKNOWN; a missing mxcli is one line, not a traceback (T4-15, T7-1)
DL="env UPG_RETRY_SLEEP=0,0,0 FAKE_DL_SRC=$T/cache/23513-4.1.0.mpk UPG_MXCLI=$FX/bin/fake-mxcli-download.sh"
rm -rf $T/dl1; ctl localedits-transient-retry-pass 0 'retry 1 of 3' 'domain model unchanged' 'NETWORK \(not judged, transient\): 0' '!UNKNOWN \[' -- $DL FAKE_DL_MODE=flaky FAKE_DL_STATE=$T/dl1.n python3 $B/localedits.py $M/base/App.mpr --module Administration --cache $T/dl1
rm -rf $T/dl2; ctl localedits-network-catch 2 'retry 3 of 3' 'Administration .*: NETWORK \(TLS handshake timeout after 3 retries' 'UNKNOWN \(not judged\): 0, NETWORK \(not judged, transient\): 1' '^rerun: localedits\.py .*App\.mpr --module Administration' '!package not readable' -- $DL FAKE_DL_MODE=down FAKE_DL_STATE=$T/dl2.n python3 $B/localedits.py $M/base/App.mpr --module Administration --cache $T/dl2
rm -rf $T/dl3; ctl localedits-no-mxcli-catch 2 '^localedits: mxcli not found at /nonexistent/mxcli' '!Traceback' -- env UPG_MXCLI=/nonexistent/mxcli python3 $B/localedits.py $M/base/App.mpr --module Administration --cache $T/dl3
ctl localedits-no-mxcli-cached-pass 0 'domain model unchanged' -- env UPG_MXCLI=/nonexistent/mxcli python3 $B/localedits.py $M/base/App.mpr --module Administration
# an mxcli that is there but cannot be executed (no shebang: Exec format error) is exit 2 (incomplete), never 1 (= RED)
printf 'echo hi\n' > $T/mx-noexec; chmod 755 $T/mx-noexec
rm -rf $T/dl4; ctl localedits-mxcli-oserror-catch 2 '^localedits: cannot run .*mx-noexec' '!Traceback' -- env UPG_MXCLI=$T/mx-noexec python3 $B/localedits.py $M/base/App.mpr --module Administration --cache $T/dl4
unset UPG_CACHE UPG_MXCLI

# --- repair: missing modules and widgets, broken widget packages (E5 F15, E1 17, E5 F22) ----------------------------
ctl missing-deps-catch 1 'UserCommons' 'PopupMenu' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/catalog.json $M/missing-deps
# E4-27: content ids from mxcli's local catalog; a widget matches a Widget entry only, and no match is said, not guessed
ctl missing-deps-catalog-catch 1 '^  Marketplace: content 223053 .UserCommons. latest 2\.4\.0' '^  Marketplace: content 115826 .Pop-up Menu. latest 4\.3\.1 \(min Mendix 9\.24\.0, Mendix\)$' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/catalog.json $M/missing-deps
ctl missing-deps-catalog-nomatch-pass 1 '^  no catalog match: search the Marketplace by name' '!content 115826' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/no-match.json $M/missing-deps
ctl missing-deps-pass 0 '!MISSING' '!BROKEN' -- python3 $B/repair/missing_deps.py $M/base
# E7-6: platform widgets ship in packages with another name; a com.mendix widget never matches a third-party package
ctl missing-deps-platform-catch 1 'ColumnChart: used 1x' '^  Marketplace: content 105695 .Charts. latest 6\.3\.2' '^  Marketplace: content 230248 .Markdown viewer.' '!305407' '!no catalog match' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/platform-widgets.json $M/missing-widgets
ctl missing-deps-target-catch 1 'content 105695 .Charts. latest 6\.3\.2 \(min Mendix 10\.6\.0, Mendix\) \[min Mendix above target 9\.24\.32' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/platform-widgets.json --target 9.24.32 $M/missing-widgets
ctl missing-deps-target-pass 1 '!above target' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/platform-widgets.json --target 10.24.9 $M/missing-widgets
# pipeline run 3 (T7-29): Charts 3.x widgets build on 11 but fail at runtime: DEPRECATED-11 before the 11 rung, quiet below 11
ctl missing-deps-charts3-11-catch 1 'DEPRECATED-11 widget com.mendix.widget.custom.PieChart.PieChart: used 1x in Account_Overview' '!MISSING' -- python3 $B/repair/missing_deps.py --target 11.15.0 $(model charts3)
ctl missing-deps-charts3-10-pass 0 '!DEPRECATED-11' 'nothing missing' -- python3 $B/repair/missing_deps.py --target 10.24.26 $(model charts3)
ctl widget-descriptor-catch 1 'BROKEN.*data descriptor missing' -- python3 $B/repair/missing_deps.py $M/widget-descriptor
ctl widget-crc-catch 1 'BROKEN' -- python3 $B/repair/missing_deps.py $M/widget-crc

# --- repair: superseded userlib jars (E5 F18, E1 17) -----------------------------------------------------------------
J=$T/jars; mkdir -p $J/userlib $J/vendorlib
for f in bcprov-jdk18on-1.78.jar bcprov-jdk18on-1.78.jar.SAML20.RequiredLib commons-io-2.11.0.jar commons-io-2.11.0.jar.CommunityCommons.RequiredLib xercesImpl-2.12.2-sp1.jar own-helper-1.0.jar; do : > $J/userlib/$f; done
for f in bcprov-jdk18on-1.85.jar commons-io-2.21.0.jar xercesImpl-2.12.2.jar; do : > $J/vendorlib/$f; done
ctl jardedupe-catch 1 'bcprov-jdk18on-1\.78' 'commons-io-2\.11\.0' 'KEEP.*xercesImpl' -- python3 $B/repair/jardedupe.py $J
ctl jardedupe-apply-stale-refused 2 'REFUSED: vendorlib is stale' -- python3 $B/repair/jardedupe.py $J --apply
ctl jardedupe-apply 0 'vendorlib current: stated with --vendorlib-synced' -- python3 $B/repair/jardedupe.py $J --apply --vendorlib-synced
ctl jardedupe-pass 0 '!bcprov-jdk18on-1\.78' -- python3 $B/repair/jardedupe.py $J
ctl jardedupe-keeps-own-and-newer 0 -- bash -c "[ -f $J/userlib/own-helper-1.0.jar ] && [ -f $J/userlib/xercesImpl-2.12.2-sp1.jar ] && [ ! -f $J/userlib/bcprov-jdk18on-1.78.jar.SAML20.RequiredLib ]"
# U4: -sources and -javadoc jars are their own artifact: never compared with the class jar, never kept over it
JS=$T/jarside; mkdir -p $JS/userlib $JS/vendorlib
for f in hamcrest-library-1.3.jar hamcrest-library-1.3-sources.jar hamcrest-library-1.3-javadoc.jar hamcrest-library-1.2-sources.jar; do : > $JS/userlib/$f; done
ctl jardedupe-sources-catch 1 'REMOVE +userlib/hamcrest-library-1\.2-sources\.jar +DUPLICATE hamcrest-library:sources' '!REMOVE +userlib/hamcrest-library-1\.3\.jar' '!REMOVE +userlib/hamcrest-library-1\.3-javadoc\.jar' '!REMOVE +userlib/hamcrest-library-1\.3-sources\.jar' -- python3 $B/repair/jardedupe.py $JS
JS2=$T/jarside2; mkdir -p $JS2/userlib $JS2/vendorlib
for f in hamcrest-library-1.3.jar hamcrest-library-1.3-sources.jar hamcrest-library-1.3-javadoc.jar; do : > $JS2/userlib/$f; done
ctl jardedupe-sources-alone-pass 0 '!REMOVE' '0 jars to remove' -- python3 $B/repair/jardedupe.py $JS2
JS3=$T/jarside3; mkdir -p $JS3/userlib $JS3/vendorlib
for f in hamcrest-library-1.2.jar hamcrest-library-1.3.jar hamcrest-library-1.3-sources.jar; do : > $JS3/userlib/$f; done
ctl jardedupe-sources-class-dup-pass 1 'REMOVE +userlib/hamcrest-library-1\.2\.jar +DUPLICATE' '!REMOVE +userlib/hamcrest-library-1\.3' -- python3 $B/repair/jardedupe.py $JS3
# B2-JAR (N1-6, T2-14): deterministic jar cleanup. Fake jars: empty files, or tiny zips where the class list matters.
mkjar() { python3 -c "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); [z.writestr(n,'') for n in sys.argv[2:]]; z.close()" "$@"; }
JC=$T/jarclean; mkdir -p $JC/userlib $JC/vendorlib $JC/javasource/own/actions
printf 'Module PresentMod CommunityCommons' > $JC/App.mpr
for f in pdfbox-2.0.30.jar commons-logging-1.2.jar guava-32.0.jar guava-32.0.jar.PresentMod.RequiredLib jackson-core-2.14.1.jar jackson-core-2.14.1.jar.OIDC.RequiredLib \
         java-jwt-3.11.0.jar java-jwt-3.11.0.jar.OIDC.RequiredLib unknown-thing.jar unknown-thing-2.0.jar own-helper-1.0.jar; do : > $JC/userlib/$f; done
mkjar $JC/userlib/oldutil-1.0.jar com/oldutil/Util.class; : > $JC/userlib/oldutil-1.0.jar.OIDC.RequiredLib
echo 'import com.oldutil.Util; class A {}' > $JC/javasource/own/actions/A.java
for f in pdfbox-3.0.7.jar commons-logging-1.3.5.jar commons-logging-1.2.jar guava-33.0.jar; do : > $JC/vendorlib/$f; done
# CONFLICT: a present module that was NOT just updated declares the older MAJOR (pdfbox 2 vs 3): kept; --updated frees it
JK=$T/jarconflict; mkdir -p $JK/userlib $JK/vendorlib; printf 'Module KeptMod' > $JK/App.mpr
: > $JK/userlib/pdfbox-2.0.30.jar; : > $JK/userlib/pdfbox-2.0.30.jar.KeptMod.RequiredLib; : > $JK/vendorlib/pdfbox-3.0.7.jar
: > $JK/userlib/lang3-3.12.jar; : > $JK/userlib/lang3-3.12.jar.KeptMod.RequiredLib; : > $JK/vendorlib/lang3-3.14.jar
ctl jarclean-major-conflict-kept 1 'KEEP +userlib/pdfbox-2\.0\.30\.jar +CONFLICT .*KeptMod' '!REMOVE +userlib/pdfbox' 'REMOVE +userlib/lang3-3\.12\.jar' -- python3 $B/repair/jardedupe.py $JK
ctl jarclean-major-updated-removed 1 'REMOVE +userlib/pdfbox-2\.0\.30\.jar' '!CONFLICT' -- python3 $B/repair/jardedupe.py $JK --updated KeptMod
# B4T2-10: an updated module committed by an EARLIER pass (or before a hand rerun) is counted from its "step:" commit
# (--updated-from-git); a "step:" commit of another module frees nothing; no git = only --updated counts, said out loud.
# The pdfbox removal rests on vendorlib: the REMOVE line says so (B4T2-9: what --vendorlib-synced must have checked).
for k in jkg jko jkn; do rm -rf $T/$k; cp -r $JK $T/$k; done
(cd $T/jkg && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm "step: KeptMod 2.0.0 (stepupdate, idcheck PASS)")
(cd $T/jko && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm "step: OtherMod 1.0.0 (stepupdate, idcheck PASS)")
ctl jarclean-major-git-updated-removed 1 'REMOVE +userlib/pdfbox-2\.0\.30\.jar +DUPLICATE .*leftover marker: KeptMod was updated \(a .step:. commit\).*\(rests on vendorlib\)$' '!CONFLICT' -- python3 $B/repair/jardedupe.py $T/jkg --updated-from-git
ctl jarclean-major-git-other-kept 1 'KEEP +userlib/pdfbox-2\.0\.30\.jar +CONFLICT .*KeptMod' '!REMOVE +userlib/pdfbox' -- python3 $B/repair/jardedupe.py $T/jko --updated-from-git
ctl jarclean-major-git-absent-kept 1 'KEEP +userlib/pdfbox-2\.0\.30\.jar +CONFLICT' 'updated-from-git: .*only --updated counts' '!REMOVE +userlib/pdfbox' -- env GIT_CEILING_DIRECTORIES=$T python3 $B/repair/jardedupe.py $T/jkn --updated-from-git
ctl jarclean-cid-bad-invalid 2 'takes Module=ID' -- python3 $B/repair/jardedupe.py $JK --cid KeptMod=abc
# B4N1-7: unversioned '*.CommunityCommons.RequiredLib' markers after a --no-baseline install (11.x .mpr: content id 0).
# The installed package (UPG_CACHE/<cid>-<version>.mpk, cid from --cid) decides: it ships no pdfbox 2 = leftover marker,
# it ships it = CONFLICT even for an updated module; no --cid = no package = CONFLICT, as before.
if python3 -c 'import bson' 2>/dev/null; then
  JP=$T/jarpkg; echo '{"version": "10.24.16.96987", "modules": [{"name": "CommunityCommons", "appstore": [0, "11.5.1"]}]}' > $T/jarpkg.json
  python3 $here/lib/mkmodel.py $T/jarpkg.json $JP > /dev/null; mkdir -p $JP/userlib $JP/vendorlib $T/jarpkg-c1 $T/jarpkg-c2
  for f in pdfbox-2.0.24.jar fontbox-2.0.24.jar; do : > $JP/userlib/$f; : > $JP/userlib/$f.CommunityCommons.RequiredLib; done
  : > $JP/vendorlib/pdfbox-3.0.5.jar; : > $JP/vendorlib/fontbox-3.0.5.jar
  python3 -c "import zipfile; z=zipfile.ZipFile('$T/jarpkg-c1/170-11.5.1.mpk','w'); z.writestr('userlib/commons-io-2.15.1.jar',''); z.close()"
  python3 -c "import zipfile; z=zipfile.ZipFile('$T/jarpkg-c2/170-11.5.1.mpk','w'); z.writestr('userlib/pdfbox-2.0.24.jar',''); z.writestr('userlib/fontbox-2.0.24.jar',''); z.close()"
  ctl jarclean-package-leftover-removed 1 'REMOVE +userlib/pdfbox-2\.0\.24\.jar .*leftover marker: CommunityCommons.s installed package 170-11\.5\.1\.mpk ships no pdfbox-2\.0\.24\.jar' 'REMOVE +userlib/fontbox-2\.0\.24\.jar' '!CONFLICT' -- env UPG_CACHE=$T/jarpkg-c1 python3 $B/repair/jardedupe.py $JP --cid CommunityCommons=170
  ctl jarclean-package-no-cid-kept 0 'KEEP +userlib/pdfbox-2\.0\.24\.jar +CONFLICT .*CommunityCommons' '!REMOVE +userlib/pdfbox' -- env UPG_CACHE=$T/jarpkg-c1 python3 $B/repair/jardedupe.py $JP
  ctl jarclean-package-ships-jar-kept 0 'KEEP +userlib/pdfbox-2\.0\.24\.jar +CONFLICT .*CommunityCommons' '!REMOVE +userlib/pdfbox' -- env UPG_CACHE=$T/jarpkg-c2 python3 $B/repair/jardedupe.py $JP --cid CommunityCommons=170 --updated CommunityCommons
else for c in jarclean-package-leftover-removed jarclean-package-no-cid-kept jarclean-package-ships-jar-kept; do skip $c 'no bson'; done; fi
ctl jarclean-duplicate-older-removed 1 'REMOVE +userlib/pdfbox-2\.0\.30\.jar .*older than vendorlib/pdfbox-3\.0\.7' 'REMOVE +userlib/commons-logging-1\.2\.jar' \
    'REMOVE +vendorlib/commons-logging-1\.2\.jar' 'KEEP +userlib/guava-32\.0\.jar +CONFLICT .*PresentMod' '!REMOVE +userlib/guava-32' 'KEEP +vendorlib/guava-33\.0\.jar +newest' \
    '!REMOVE +vendorlib/commons-logging-1\.3\.5' -- python3 $B/repair/jardedupe.py $JC
ctl jarclean-unowned-stale-removed 1 'REMOVE +userlib/jackson-core-2\.14\.1\.jar +STALE: module\(s\) OIDC' 'REMOVE +userlib/java-jwt-3\.11\.0\.jar +STALE' -- python3 $B/repair/jardedupe.py $JC
ctl jarclean-imported-stale-kept 1 'KEEP +userlib/oldutil-1\.0\.jar +IMPORTED' '!REMOVE +userlib/oldutil' -- python3 $B/repair/jardedupe.py $JC
ctl jarclean-ambiguous-and-own-kept 1 'KEEP +userlib/unknown-thing\.jar +AMBIGUOUS' 'KEEP +userlib/unknown-thing-2\.0\.jar +AMBIGUOUS' '!own-helper' -- python3 $B/repair/jardedupe.py $JC
ctl jarclean-dryrun-deletes-nothing 1 'dry run' -- bash -c "python3 $B/repair/jardedupe.py $JC; rc=\$?; [ -f $JC/userlib/pdfbox-2.0.30.jar ] && [ -f $JC/userlib/jackson-core-2.14.1.jar.OIDC.RequiredLib ] && exit \$rc"
ctl jarclean-apply-stale-refused 2 'REFUSED: vendorlib is stale' -- python3 $B/repair/jardedupe.py $JC --apply
ctl jarclean-apply 0 'removed [0-9]+ jars' -- python3 $B/repair/jardedupe.py $JC --apply --vendorlib-synced --log $T/jarclean.log
ctl jarclean-apply-result 0 -- bash -c "cd $JC; [ ! -f userlib/pdfbox-2.0.30.jar ] && [ ! -f userlib/jackson-core-2.14.1.jar ] && [ ! -f userlib/jackson-core-2.14.1.jar.OIDC.RequiredLib ] && [ ! -f vendorlib/commons-logging-1.2.jar ] && [ -f vendorlib/pdfbox-3.0.7.jar ] && [ -f vendorlib/commons-logging-1.3.5.jar ] && [ -f vendorlib/guava-33.0.jar ] && [ -f userlib/guava-32.0.jar ] && [ -f userlib/oldutil-1.0.jar ] && [ -f userlib/own-helper-1.0.jar ] && [ -f userlib/unknown-thing.jar ] && grep -q 'REMOVE' $T/jarclean.log"
ctl jarclean-clean-after-apply 0 '!REMOVE' -- python3 $B/repair/jardedupe.py $JC
# PLM-23: the same version under two names, one is a metadata jar with no classes (okio 3.5.0 / okio-jvm 3.5.0): the jar
# with classes is the one that stays, and the only jar holding the classes of a package is never removed.
mkjarpom() { python3 -c "
import sys,zipfile
z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('META-INF/maven/com.squareup.okio/okio/pom.properties','groupId=com.squareup.okio\nartifactId=okio\nversion=3.5.0\n')
[z.writestr(n,'') for n in sys.argv[2:]]; z.close()" "$@"; }
JO=$T/jarokio; mkdir -p $JO/userlib; printf 'Module SapMod' > $JO/App.mpr
mkjarpom $JO/userlib/okio-3.5.0.jar META-INF/okio.kotlin_module; : > $JO/userlib/okio-3.5.0.jar.SapMod.RequiredLib
mkjarpom $JO/userlib/okio-jvm-3.5.0.jar okio/ByteString.class okio/Buffer.class; : > $JO/userlib/okio-jvm-3.5.0.jar.SapMod.RequiredLib
ctl jardedupe-classes-win-catch 1 'REMOVE +userlib/okio-3\.5\.0\.jar +DUPLICATE' 'KEEP +userlib/okio-jvm-3\.5\.0\.jar +newest' '!REMOVE +userlib/okio-jvm' -- python3 $B/repair/jardedupe.py $JO
JO2=$T/jarokio2; mkdir -p $JO2/userlib; printf 'Module SapMod' > $JO2/App.mpr
mkjarpom $JO2/userlib/okio-3.5.0.jar okio/Buffer.class; mkjarpom $JO2/userlib/okio-jvm-3.5.0.jar okio/internal/Util.class
ctl jardedupe-only-classes-kept-catch 0 'ONLY COPY WITH CLASSES for okio\.internal' '!REMOVE +userlib' -- python3 $B/repair/jardedupe.py $JO2
ctl jardedupe-classes-covered-pass 1 'REMOVE +userlib/okio-3\.5\.0\.jar' '!ONLY COPY' -- python3 $B/repair/jardedupe.py $JO --modules SapMod
# PLM-24: an older MAJOR kept in userlib next to the newer one in vendorlib is named SHADOWED, with the module that
# declares it, and the line says the module already moved other jars to vendorlib (a leftover of its old version).
JH=$T/jarshadow; mkdir -p $JH/userlib $JH/vendorlib; printf 'Module ModX' > $JH/App.mpr
for f in pdfbox-2.0.24.jar commons-io-2.11.0.jar; do : > $JH/userlib/$f; : > $JH/userlib/$f.ModX.RequiredLib; done
: > $JH/vendorlib/pdfbox-3.0.7.jar; : > $JH/vendorlib/commons-io-2.21.0.jar
ctl jardedupe-shadowed-catch 1 'SHADOWED +userlib/pdfbox-2\.0\.24\.jar +older major 2\.0\.24 next to vendorlib/pdfbox-3\.0\.7\.jar; ModX already moved other jars to vendorlib' 'shadowed: 1 older-major' 'rerun with --updated ModX' -- python3 $B/repair/jardedupe.py $JH
ctl jardedupe-shadowed-updated-pass 1 'REMOVE +userlib/pdfbox-2\.0\.24\.jar' '!SHADOWED' '!shadowed:' -- python3 $B/repair/jardedupe.py $JH --updated ModX
ctl jardedupe-shadowed-none-pass 0 '!SHADOWED' -- python3 $B/repair/jardedupe.py $JO2
# T3-3, T3-17: one jar identity (pom.properties groupId:artifactId, else manifest name, else file name) for inventory,
# jardedupe and jarclash. Real zips with the T3 name shapes; the T5-16 gate refuses removals against a stale vendorlib.
python3 $here/lib/mkjarid.py $T/jarid
ctl test-inventory-jar-identity-catch 0 'userlib/commons-codec-1\.15\.jar \| userlib/commons-codec\.commons-codec-1\.15\.jar' 'userlib/commons-io-2\.11\.0\.jar \| userlib/org\.apache\.commons\.io-2\.3\.0\.jar \| vendorlib/commons-io-2\.21\.0\.jar' 'userlib/org\.apache\.commons\.lang3\.jar \| vendorlib/commons-lang3-3\.20\.0\.jar' -- python3 -c "import sys; sys.path.insert(0,'$B'); import test_inventory as t; print('\n'.join(t.jar_files('$T/jarid')['duplicates']))"
ctl jarid-dedupe-catch 1 'REMOVE +userlib/commons-codec\.commons-codec-1\.15\.jar +DUPLICATE commons-codec:commons-codec' 'REMOVE +userlib/org\.apache\.commons\.io-2\.3\.0\.jar' 'REMOVE +userlib/commons-io-2\.11\.0\.jar' \
    'REMOVE +userlib/org\.apache\.commons\.lang3\.jar +DUPLICATE org\.apache\.commons\.lang3: older than vendorlib/commons-lang3-3\.20\.0\.jar' 'KEEP +vendorlib/commons-io-2\.21\.0\.jar' \
    '!REMOVE +vendorlib' '!own-helper' 'WARNING: vendorlib is stale' -- python3 $B/repair/jardedupe.py $T/jarid
cp -r $T/jarid $T/jarid-b; cp -r $T/jarid $T/jarid-c; cp -r $T/jarid $T/jarid-d
ctl jarid-apply-stale-refused 2 'REFUSED: vendorlib is stale' -- python3 $B/repair/jardedupe.py $T/jarid-b --apply
ctl jarid-apply-stale-removes-nothing 0 -- bash -c "cd $T/jarid-b/userlib; [ -f org.apache.commons.io-2.3.0.jar ] && [ -f commons-io-2.11.0.jar.CommunityCommons.RequiredLib ] && [ -f org.apache.commons.lang3.jar ]"
# an SBOM OLDER than the last module change is no proof (the sync ran for the previous module set)
echo '{}' > $T/jarid-c/vendorlib-sbom.json; touch -d '2001-01-01' $T/jarid-c/vendorlib-sbom.json
ctl jarid-apply-old-sbom-refused 2 'vendorlib-sbom\.json is older than the last module change' -- python3 $B/repair/jardedupe.py $T/jarid-c --apply
echo '{}' > $T/jarid-d/vendorlib-sbom.json; touch -d '+1 hour' $T/jarid-d/vendorlib-sbom.json
ctl jarid-apply-current-sbom-pass 0 'vendorlib current: vendorlib-sbom\.json is newer than the last module change' 'removed 4 jars and 3 markers' -- python3 $B/repair/jardedupe.py $T/jarid-d --apply
ctl jarid-apply-result 0 -- bash -c "cd $T/jarid-d/userlib; [ ! -f org.apache.commons.io-2.3.0.jar ] && [ ! -f commons-io-2.11.0.jar ] && [ ! -f org.apache.commons.lang3.jar ] && [ ! -f org.apache.commons.io-2.3.0.jar.TcConnector.RequiredLib ] && [ -f commons-codec-1.15.jar ] && [ -f own-helper-1.0.jar ] && [ ! -f commons-codec.commons-codec-1.15.jar ]"
ctl jarid-clean-after-apply 0 '!REMOVE' -- python3 $B/repair/jardedupe.py $T/jarid-d
ctl test-inventory-jar-identity-pass 0 '^\[\]$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import test_inventory as t; print(t.jar_files('$T/jarid-d')['duplicates'])"
ctl jarclash-same-artifact-catch 1 'same artifact commons-codec:commons-codec \(1\.15 vs 1\.15\) under two file names' 'same artifact org\.apache\.commons\.lang3 \(3\.1 vs 3\.20\.0\)' 'manifest org\.apache\.commons\.lang3 3\.1' -- python3 $B/repair/jarclash.py $T/jarid --min 1
ctl jarclash-same-artifact-pass 0 '^no clash' -- python3 $B/repair/jarclash.py $T/jarid-d --min 1
# T6R-10: BouncyCastle's jdk15on / jdk15to18 -> jdk18on rename is one library. Without a manifest module name (and with
# the real BC 1.81 manifest: Bundle-SymbolicName only) the old jar was a different artifact and kept shadowing the new one.
python3 $here/lib/mkjarbc.py $T/jarbc; python3 $here/lib/mkjarbc.py $T/jarbc-m --manifest
ctl jarbc-rename-catch 1 'REMOVE +userlib/bcprov-jdk15on-1\.68\.jar +DUPLICATE org\.bouncycastle:bcprov: older than vendorlib/bcprov-jdk18on-1\.81\.jar' 'REMOVE +userlib/bcpkix-jdk15to18-1\.68\.jar +DUPLICATE' '!REMOVE +vendorlib' '!own-helper' -- python3 $B/repair/jardedupe.py $T/jarbc
ctl jarbc-rename-manifest-catch 1 'REMOVE +userlib/bcprov-jdk15on-1\.68\.jar +DUPLICATE' 'REMOVE +userlib/bcpkix-jdk15to18-1\.68\.jar +DUPLICATE' '!REMOVE +vendorlib' -- python3 $B/repair/jardedupe.py $T/jarbc-m
ctl jarbc-rename-apply-refused 2 'REFUSED: vendorlib is stale' -- python3 $B/repair/jardedupe.py $T/jarbc-m --apply
ctl jarbc-rename-apply 0 'removed 2 jars and 2 markers' -- python3 $B/repair/jardedupe.py $T/jarbc --apply --vendorlib-synced
ctl jarbc-rename-pass 0 '!REMOVE' -- bash -c "python3 $B/repair/jardedupe.py $T/jarbc && [ -f $T/jarbc/userlib/own-helper-1.0.jar ] && [ -f $T/jarbc/vendorlib/bcprov-jdk18on-1.81.jar ]"
# T2R3-6: a jar the Java of an add-on module (.mxmodule; unpacked in .mendix-cache/modules/*/javasource) imports is
# never STALE, and its absent module's whole jar set stays as its dependency; unreadable add-on Java = UNPROVEN.
# N3-17 / T1R-13: '<jar>.<Module>.<ver>.RequiredLib' markers of an old module version, orphan markers, relative path.
JS=$T/jarstale; for k in addon-cache addon-zip addon-unreadable no-addon sso t1r n3 netty netty-nocodec; do python3 $here/lib/mkjarstale.py $JS/$k $k; done
# NS-3: netty 4.2 split netty-codec; the old userlib copy has no match and got no line at all (a06afe60)
ctl jarstale-netty-unmatched-catch 1 'UNMATCHED +userlib/netty-codec-4\.1\.119\.Final\.jar +no copy in vendorlib although MendixSSO moved its other jars there; vendorlib has netty-codec-base-4\.2\.5\.Final\.jar, netty-codec-compression-4\.2\.5\.Final\.jar' '1 UNMATCHED \(review by hand\)' '!REMOVE +userlib/netty-codec-4' -- python3 $B/repair/jardedupe.py $JS/netty
ctl jarstale-netty-matched-pass 1 'REMOVE +userlib/netty-codec-http-4\.1\.119\.Final\.jar +DUPLICATE' '!UNMATCHED' -- python3 $B/repair/jardedupe.py $JS/netty-nocodec
ctl jarstale-addon-cache-kept 1 'KEEP +userlib/java-jwt-3\.11\.0\.jar +NEEDED BY ADD-ON exfn_authentication' 'KEEP +userlib/jackson-core-2\.14\.1\.jar +NEEDED BY ADD-ON: OIDC jar set' 'KEEP +userlib/commons-codec-1\.15\.jar +NEEDED BY ADD-ON' \
    '!REMOVE +userlib/(java-jwt|jackson|json-|commons-codec)' 'REMOVE +userlib/pushy-0\.15\.2\.jar +STALE' -- python3 $B/repair/jardedupe.py $JS/addon-cache
ctl jarstale-addon-zip-kept 1 'KEEP +userlib/jackson-databind-2\.14\.1\.jar +NEEDED BY ADD-ON EXFN_Authentication' '!REMOVE +userlib/(java-jwt|jackson|json-|commons-codec)' 'REMOVE +userlib/pushy' -- python3 $B/repair/jardedupe.py $JS/addon-zip
ctl jarstale-addon-unreadable-unproven 0 'KEEP +userlib/java-jwt-3\.11\.0\.jar +UNPROVEN: .*EXFN_Authentication' 'KEEP +userlib/pushy.*UNPROVEN' '!REMOVE' -- python3 $B/repair/jardedupe.py $JS/addon-unreadable
ctl jarstale-no-addon-stale-catch 1 'REMOVE +userlib/java-jwt-3\.11\.0\.jar +STALE: module\(s\) OIDC' 'summary: 7 jars to remove \(0 duplicate versions, 7 stale' '!NEEDED BY ADD-ON' -- python3 $B/repair/jardedupe.py $JS/no-addon
ctl jarstale-addon-apply-keeps 0 'removed 1 jars and 1 markers' -- bash -c "python3 $B/repair/jardedupe.py $JS/addon-cache --apply --vendorlib-synced && cd $JS/addon-cache/userlib && [ -f java-jwt-3.11.0.jar ] && [ -f jackson-core-2.14.1.jar ] && [ -f json-20220924.jar ] && [ -f commons-codec-1.15.jar.OIDC.RequiredLib ] && [ ! -f pushy-0.15.2.jar ]"
ctl jarstale-sso-old-version-catch 1 'REMOVE +userlib/accessors-smart-2\.4\.7\.jar +OLD-VERSION: MendixSSO 4\.1\.0 is an old version \(now 4\.2\.0' 'REMOVE +userlib/jcip-annotations-1\.0-1\.jar +OLD-VERSION' \
    'REMOVE +userlib/commons-lang3-3\.12\.0\.jar\.MendixSSO\.4\.1\.0\.RequiredLib +OLD-MARKER' 'REMOVE +userlib/oauth2-oidc-sdk-9\.15\.jar\.MendixSSO\.4\.1\.0\.RequiredLib +ORPHAN marker' 'KEEP +userlib/lang-tag-1\.5\.jar +IMPORTED' \
    '!REMOVE +userlib/accessors-smart-2\.4\.9' '!REMOVE +userlib/commons-lang3-3\.12\.0\.jar ' 'summary: 2 jars to remove .*4 RequiredLib markers, 2 of them alone' -- python3 $B/repair/jardedupe.py $JS/sso
ctl jarstale-sso-apply 0 'removed 2 jars and 4 markers' -- python3 $B/repair/jardedupe.py $JS/sso --apply --vendorlib-synced
ctl jarstale-sso-apply-result 0 -- bash -c "cd $JS/sso/userlib; [ ! -f accessors-smart-2.4.7.jar ] && [ ! -f accessors-smart-2.4.7.jar.MendixSSO.4.1.0.RequiredLib ] && [ ! -f commons-lang3-3.12.0.jar.MendixSSO.4.1.0.RequiredLib ] && [ ! -f oauth2-oidc-sdk-9.15.jar.MendixSSO.4.1.0.RequiredLib ] && [ -f commons-lang3-3.12.0.jar ] && [ -f commons-lang3-3.12.0.jar.MendixSSO.4.2.0.RequiredLib ] && [ -f accessors-smart-2.4.9.jar ] && [ -f lang-tag-1.5.jar ]"
ctl jarstale-sso-clean-after-apply 0 '!REMOVE' -- python3 $B/repair/jardedupe.py $JS/sso
if python3 -c 'import bson' 2>/dev/null; then
  echo '{"version": "10.24.16.96987", "modules": [{"name": "MendixSSO", "appstore": [111349, "10.6.2"]}]}' > $T/jarstale-mpr.json
  python3 $here/lib/mkmodel.py $T/jarstale-mpr.json $JS/mpr > /dev/null; python3 $here/lib/mkjarstale.py $JS/mpr-jars sso; cp -r $JS/mpr-jars/userlib $JS/mpr-jars/javasource $JS/mpr/
  ctl jarstale-mpr-installed-catch 1 'REMOVE +userlib/accessors-smart-2\.4\.9\.jar +OLD-VERSION: MendixSSO 4\.2\.0 is an old version \(now 10\.6\.2, installed in the \.mpr\)' 'WARNING: vendorlib is stale' -- python3 $B/repair/jardedupe.py $JS/mpr
  ctl jarstale-mpr-installed-apply-refused 2 'REFUSED: vendorlib is stale' -- bash -c "python3 $B/repair/jardedupe.py $JS/mpr --apply; rc=\$?; [ -f $JS/mpr/userlib/accessors-smart-2.4.9.jar ] && exit \$rc"
else skip jarstale-mpr-installed-catch 'no bson'; skip jarstale-mpr-installed-apply-refused 'no bson'; fi
ctl jarstale-t1r-userlib-pairs 1 'summary: 6 jars to remove \(6 duplicate versions' 'REMOVE +userlib/accessors-smart-2\.4\.7\.jar +DUPLICATE net\.minidev:accessors-smart: older than userlib/accessors-smart-2\.4\.9\.jar' -- python3 $B/repair/jardedupe.py $JS/t1r
ctl jarstale-n3-vendorlib-pairs 1 'summary: 7 jars to remove \(7 duplicate versions' 'REMOVE +vendorlib/accessors-smart-2\.4\.9\.jar +DUPLICATE net\.minidev:accessors-smart: older than vendorlib/accessors-smart-2\.5\.2\.jar' \
    'REMOVE +userlib/nimbus-jose-jwt-9\.12\.1\.jar\.MendixSSO\.4\.1\.0\.RequiredLib +ORPHAN marker' -- python3 $B/repair/jardedupe.py $JS/n3
ctl jarstale-relpath-pass 1 'summary: 6 jars to remove' '!no userlib' -- bash -c "cd $JS/t1r && python3 $B/repair/jardedupe.py ."
ctl jarstale-relpath-bad-catch 2 'not a folder \(resolved from' -- bash -c "cd $JS && python3 $B/repair/jardedupe.py no-such-app"
mkdir -p $JS/empty; ctl jarstale-no-libs-catch 2 'no userlib/ and no vendorlib/' -- python3 $B/repair/jardedupe.py $JS/empty
# E5 F5: jars are counted from the files
J=$T/jarapp; mkdir -p $J/userlib $J/vendorlib; touch $J/userlib/commons-lang3-3.12.0.jar $J/userlib/commons-lang3-3.14.0.jar $J/userlib/pdfbox-2.0.27.jar $J/vendorlib/guava-32.1.jar $J/userlib/guava-31.0.jar
J2=$T/jarapp2; mkdir -p $J2/userlib; touch $J2/userlib/commons-lang3-3.14.0.jar $J2/userlib/pdfbox-2.0.27.jar
# duplicates inside userlib are reported at triage, not only between userlib and vendorlib (E5b-4)
ctl test-inventory-dup-jars-catch 0 'userlib/commons-lang3-3.12.0.jar \| userlib/commons-lang3-3.14.0.jar' 'userlib/guava-31.0.jar \| vendorlib/guava-32.1.jar' -- python3 -c "import sys; sys.path.insert(0,'$B'); import test_inventory as t; print(*t.jar_files('$J')['duplicates'], sep='\n')"
ctl test-inventory-dup-jars-pass 0 '^\[\]$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import test_inventory as t; print(t.jar_files('$J2')['duplicates'])"
ctl test-inventory-jars-catch 0 -- python3 -c "import sys; sys.path.insert(0,'$B'); import test_inventory as t; k=t.jar_key('bcprov-jdk18on-1.78.jar'); print(k); sys.exit(0 if k and k[0].startswith('bcprov') else 1)"
# T2-2: add-on modules (modules/*.mxmodule = zip holding project.mpr) carry their own Studio Pro version; Mendix 11 refuses
# one built before 10.21 (CE1893). The fixture is a zip holding an mpr made like mkmodel.py makes one (_MetaData row).
AD=$T/addon-app; mkdir -p $AD/modules
mkaddon() { python3 - "$1" "$2" <<'PYEOF'
import sqlite3, sys, tempfile, os, zipfile
out, ver = sys.argv[1:3]
d = tempfile.mkdtemp(); f = os.path.join(d, "project.mpr")
c = sqlite3.connect(f)
c.execute("create table Unit (UnitID blob primary key, ContainerID blob, ContainmentName text, TreeConflict int, ContentsHash text, ContentsConflicts text, Contents blob)")
c.execute("create table _MetaData (_ProductVersion text, _BuildVersion text, _SchemaHash text)")
c.execute("insert into _MetaData values (?, ?, '')", (ver, ver)); c.commit(); c.close()
z = zipfile.ZipFile(out, "w"); z.write(f, "project.mpr"); z.close()
PYEOF
}
mkaddon $AD/modules/EXFN_Authentication.mxmodule 9.24.4.58223
mkaddon $AD/modules/NewVendor.mxmodule 10.24.26.123458
ctl mxversion-mxmodule-pass 0 '^9\.24\.4\.58223$' -- python3 $B/mxversion.py $AD/modules/EXFN_Authentication.mxmodule
ctl mxversion-mxmodule-short-pass 0 '^10\.24\.26$' -- python3 $B/mxversion.py $AD/modules/NewVendor.mxmodule --short
echo notazip > $AD/modules/Broken.mxmodule
ctl mxversion-mxmodule-unreadable-catch 2 'no Mendix version found' -- python3 $B/mxversion.py $AD/modules/Broken.mxmodule
ctl test-inventory-addons-catch 0 'EXFN_Authentication.mxmodule built with 9\.24\.4\.58223' 'NewVendor.mxmodule built with 10\.24\.26\.123458' 'Broken.mxmodule built with UNKNOWN' "^\['EXFN_Authentication.mxmodule', '9.24.4.58223', True\]" '!NewVendor.mxmodule.*True' -- python3 -c "
import sys; sys.path.insert(0,'$B'); import mxversion as m, test_inventory as t
for f, v in m.addons('$AD'): print([f, v, m.below(v, 10, 21)])
print(*['%s built with %s' % (f, v or 'UNKNOWN') for f, v in m.addons('$AD')], sep='\n')"
ctl test-inventory-addons-pass 0 '^\[\]$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import mxversion as m; print(m.addons('$J2'))"
# the real report: an empty catalog.db (tables exist, no rows) plus the add-on folder; the row says what blocks Mendix 11
TI=$T/ti-app; mkdir -p $TI/.mxcli $TI/modules; cp $AD/modules/EXFN_Authentication.mxmodule $AD/modules/NewVendor.mxmodule $TI/modules/
python3 - $TI/.mxcli/catalog.db <<'PYEOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for t, cols in {"modules_data": "Name, Source, AppStoreVersion", "entities_data": "QualifiedName, ModuleName, EntityType, Generalization, AttributeCount, AssociationCount, HasEventHandlers",
                "published_rest_operations_data": "ServiceQualifiedName, HttpMethod, Path, Microflow", "rest_clients_data": "QualifiedName, BaseUrl, OperationCount",
                "activities_data": "ActionType", "odata_services_data": "QualifiedName, Path, EntitySetCount", "odata_clients_data": "QualifiedName, MetadataUrl",
                "scheduled_events_data": "QualifiedName, Microflow, Enabled, RepeatDescription", "java_actions_data": "ModuleName",
                "navigation_role_homes": "ProfileName, UserRole, Page, Microflow", "navigation_menu_items": "TargetPage", "widgets_data": "WidgetType",
                "jar_dependencies_data": "ModuleName, Coordinate, Version", "workflows_data": "QualifiedName", "business_event_services_data": "QualifiedName"}.items():
    c.execute(f"create table {t} ({cols})")
c.commit()
PYEOF
ctl test-inventory-addons-report-catch 0 '^\| Add-on modules \(\.mxmodule\) \| 2: EXFN_Authentication\.mxmodule built with 9\.24\.4\.58223; NewVendor\.mxmodule built with 10\.24\.26\.123458; BLOCKS MENDIX 11 \(built before 10\.21\): EXFN_Authentication\.mxmodule \|' -- python3 $B/test_inventory.py $TI
rm $TI/modules/EXFN_Authentication.mxmodule
ctl test-inventory-addons-report-pass 0 '^\| Add-on modules \(\.mxmodule\) \| 1: NewVendor\.mxmodule built with 10\.24\.26' '!BLOCKS MENDIX 11' -- python3 $B/test_inventory.py $TI
# missing_deps: a module only an add-on provides is ADD-ON, not MISSING; the other missing module stays MISSING
MD=$T/addon-missing; cp -R $M/missing-deps $MD; mkdir -p $MD/modules; mkaddon $MD/modules/UserCommons.mxmodule 9.24.4.58223
AO=$T/addon-other; cp -R $M/missing-deps $AO; mkdir -p $AO/modules; mkaddon $AO/modules/Unrelated.mxmodule 10.24.26.123458
ctl missing-deps-addon-catch 1 'ADD-ON \(\.mxmodule, built with 9\.24\.4\.58223\) UserCommons\.mxmodule: module UserCommons' '!MISSING module UserCommons' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/catalog.json $MD
AB=$T/addon-blocked; cp -R $M/base $AB; mkdir -p $AB/modules; mkaddon $AB/modules/EXFN_Authentication.mxmodule 9.24.4.58223; mkaddon $AB/modules/NewVendor.mxmodule 10.24.26.123458
ctl missing-deps-addon-below-1021-catch 1 'ADD-ON EXFN_Authentication.mxmodule built with 9\.24\.4\.58223: BLOCKS Mendix 11\.15\.0' '!NewVendor.mxmodule built with 10.*BLOCKS' -- python3 $B/repair/missing_deps.py --target 11.15.0 $AB
ctl missing-deps-addon-below-1021-target10-pass 0 '!BLOCKS' 'nothing missing' -- python3 $B/repair/missing_deps.py --target 10.24.26 $AB
ctl missing-deps-addon-other-catch 1 '^MISSING module UserCommons' '!ADD-ON' -- python3 $B/repair/missing_deps.py --catalog $FX/catalog/catalog.json $AO
# AC-6 (Academy 10.18 to 11.15): an old library copy hidden INSIDE another jar breaks the build; file names show nothing
python3 $here/lib/mkjars.py $T/jarclash clash; python3 $here/lib/mkjars.py $T/jarclean clean
ctl jarclash-hidden-catch 1 'hidden copy: userlib/markdown-all-0\.50\.jar!lib/pdfbox-2\.0\.24\.jar' 'pdfbox 2\.0\.24' 'pdfbox 3\.0\.3' -- python3 $B/repair/jarclash.py $T/jarclash
ctl jarclash-owner-catch 1 'userlib/pdfreader-1\.0\.0\.jar \[no maven metadata; modules: PDFReader\]' -- python3 $B/repair/jarclash.py $T/jarclash
ctl jarclash-shaded-pass 0 '^no clash' -- python3 $B/repair/jarclash.py $T/jarclean
ctl jarclash-input-catch 2 -- python3 $B/repair/jarclash.py $T/empty-nothing

# --- repair: backslash paths (E5 F14, E1 17) --------------------------------------------------------------------------
P=$T/bs; mkdir -p $P/javasource/oql/actions
printf 'class A {}\n' > "$P/javasource\\oql\\actions\\AddBooleanParameter.java"
ctl backslash-catch 1 'AddBooleanParameter' -- python3 $B/repair/backslash_paths.py $P
ctl backslash-apply 0 -- python3 $B/repair/backslash_paths.py $P --apply
ctl backslash-pass 0 -- python3 $B/repair/backslash_paths.py $P
ctl backslash-moved-home 0 -- test -f $P/javasource/oql/actions/AddBooleanParameter.java

# --- repair: SCSS import case (T2-5, N1-7) -----------------------------------------------------------------------------
S=$T/scss; mkdir -p $S/themesource/pub/web/buildingblocks/commandbar $S/theme/web
printf '$a: 1;\n' > $S/themesource/pub/web/buildingblocks/commandbar/_commandbar.scss
printf '@import "buildingblocks/commandBar/commandBar";\n@import "buildingblocks/nothere/nothere";\n@import "buildingblocks/commandbar/commandbar";\n' > $S/themesource/pub/web/_main.scss
printf '@import "../../themesource/pub/web/Main";\n' > $S/theme/web/main.scss
ctl scsscase-check-catch 1 'WOULD FIX .*_main\.scss:1: buildingblocks/commandBar/commandBar  ->  buildingblocks/commandbar/commandbar' 'WOULD FIX theme/web/main\.scss:1: .*/Main  ->  .*/main$' '!nothere.*->' 'summary: 2 import' -- python3 $B/repair/scsscase.py $S --check
ctl scsscase-check-wrote-nothing 0 -- grep -q 'commandBar/commandBar' $S/themesource/pub/web/_main.scss
ctl scsscase-fix 0 'FIXED +.*_main\.scss:1' 'summary: 2 import' -- python3 $B/repair/scsscase.py $S
ctl scsscase-rewritten 0 -- grep -q '"buildingblocks/commandbar/commandbar"' $S/themesource/pub/web/_main.scss
ctl scsscase-idempotent 0 'summary: 0 import' '!FIXED' -- python3 $B/repair/scsscase.py $S
ctl scsscase-idempotent-check 0 'summary: 0 import' -- python3 $B/repair/scsscase.py $S --check
ctl scsscase-unresolvable-left-alone 0 -- grep -q '"buildingblocks/nothere/nothere"' $S/themesource/pub/web/_main.scss
ctl scsscase-input-catch 2 -- python3 $B/repair/scsscase.py $T/empty-nothing

# --- repair: mx check got worse (E5 F16 guard) --------------------------------------------------------------------------
# B4T1-3, B4T2-2, B4T4-1, B4T5-2, B4T7-2, B4T8-1: a fixture that .gitignore swallows (*.log) is never committed, so its
# controls FAIL in every fresh clone. No file under controls/ may be ignored (needs git; SKIP outside a work tree).
if git -C "$here" rev-parse --git-dir >/dev/null 2>&1; then
  IGN='n=$(git -C "$1" ls-files -o -i --exclude-standard . | tee /dev/stderr | wc -l); echo "ignored under controls: $n"'
  ctl controls-fixtures-not-ignored-pass 0 '^ignored under controls: 0$' -- bash -c "$IGN" _ "$here"
  # catch: a file git still ignores (.DS_Store) placed under fixtures is found (the probe is removed again)
  mkdir -p "$here/fixtures/zz-ignore-probe" && : > "$here/fixtures/zz-ignore-probe/.DS_Store"
  ctl controls-fixtures-ignored-catch 0 '^ignored under controls: 1$' 'DS_Store' -- bash -c "$IGN" _ "$here"
  rm -rf "$here/fixtures/zz-ignore-probe"
else skip controls-fixtures-not-ignored-pass "not a git work tree"; skip controls-fixtures-ignored-catch "not a git work tree"; fi
# B4T2-2, B4N1-1: the fixture logs are versioned. Root .gitignore's *.log swallowed fixtures/check/*.log, so a fresh clone
# failed every checkdiff-* and guard-* control ("No such file"). No folder under fixtures/ may be ignored for *.log.
if git -C "$here" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  ctl fixtures-log-not-ignored-pass 1 '!.' -- git -C "$here" check-ignore --no-index fixtures/check/new-probe.log fixtures/new-folder/x/probe.log
  ctl fixtures-log-ignored-elsewhere-catch 0 -- git -C "$here" check-ignore -q --no-index scratch-probe.log
  ctl fixtures-log-none-untracked-pass 1 -- sh -c "git -C '$here' ls-files --others --ignored --exclude-standard fixtures | grep '\.log\$'"
  ctl fixtures-check-logs-tracked-pass 0 '^3$' -- sh -c "git -C '$here' ls-files fixtures/check | grep -c '\.log\$'"
else skip fixtures-log-not-ignored-pass 'not a git checkout'; fi
ctl checkdiff-worse-catch 1 'WORSE' 'CE6085' -- python3 $B/checkdiff.py $FX/check/before.log $FX/check/after-worse.log
ctl checkdiff-better-pass 0 '^OK' -- python3 $B/checkdiff.py $FX/check/before.log $FX/check/after-better.log
# --fixed: the fixed class gone and a hidden class revealed is CASCADE; a swapped class stays WORSE (E4-26)
ctl checkdiff-cascade-pass 0 '^CASCADE: .*CE0463 \(1 -> 0\) is gone' -- python3 $B/checkdiff.py $FX/check/before.log $FX/check/after-worse.log --fixed CE0463
ctl checkdiff-cascade-wrong-class-catch 1 'CE0066 is not gone' '^WORSE' -- python3 $B/checkdiff.py $FX/check/before.log $FX/check/after-worse.log --fixed CE0066
ctl checkdiff-no-fixed-still-worse-catch 1 '^WORSE.*gone CE0463' 'rerun with --fixed CE0463' -- python3 $B/checkdiff.py $FX/check/before.log $FX/check/after-worse.log
# design_props_guard.sh refuses a worse result and keeps the original (fake mx: UPG_GUARD_MX)
G=$T/guard; mkdir -p $G/app; cp $M/base/App.mpr $G/app/App.mpr; echo original > $G/app/marker.txt
cat > $T/fakemx.sh <<EOF
#!/bin/bash
# fake toolset: "mx check X" prints the before log for the original and the worse log for a copy that holds fixed.txt
ver=\$1; shift; [ "\$1" = mx ] && shift
if [ "\$1" = check ]; then d=\$(dirname "\$2"); if [ -f "\$d/fixed.txt" ]; then cat "\$(cat \$d/fixed.txt)"; else cat $FX/check/before.log; fi; fi
EOF
chmod +x $T/fakemx.sh
ctl guard-worse-catch 1 'refused|REFUSED|WORSE' -- env UPG_GUARD_MX=$T/fakemx.sh zsh $B/repair/design_props_guard.sh $G/app 10.24.16 -- bash -c "echo $FX/check/after-worse.log > fixed.txt; echo fixed > marker.txt" APP
ctl guard-worse-original-kept 0 '^original$' -- cat $G/app/marker.txt
ctl guard-better-pass 0 -- env UPG_GUARD_MX=$T/fakemx.sh zsh $B/repair/design_props_guard.sh $G/app 10.24.16 -- bash -c "echo $FX/check/after-better.log > fixed.txt; echo fixed > marker.txt" APP
ctl guard-better-applied 0 '^fixed$' -- cat $G/app/marker.txt

# v3.1 E7-4: --fixed is passed to checkdiff: the fixed class gone and a hidden class revealed is CASCADE and applied
echo original > $G/app/marker.txt; rm -f $G/app/fixed.txt
ctl guard-fixed-cascade-pass 0 '^CASCADE' 'applied' -- env UPG_GUARD_MX=$T/fakemx.sh zsh $B/repair/design_props_guard.sh $G/app 10.24.16 --fixed CE0463 -- bash -c "echo $FX/check/after-worse.log > fixed.txt; echo fixed > marker.txt" APP
ctl guard-fixed-cascade-applied 0 '^fixed$' -- cat $G/app/marker.txt
echo original > $G/app/marker.txt; rm -f $G/app/fixed.txt
ctl guard-fixed-wrong-class-catch 1 'CE0066 is not gone' 'REFUSED' -- env UPG_GUARD_MX=$T/fakemx.sh zsh $B/repair/design_props_guard.sh $G/app 10.24.16 --fixed CE0066 -- bash -c "echo $FX/check/after-worse.log > fixed.txt; echo fixed > marker.txt" APP
ctl guard-fixed-usage-catch 2 'usage: design_props_guard.sh' -- zsh $B/repair/design_props_guard.sh $G/app 10.24.16 --fixed -- true
# T1-19, T2-8, T4-4, T5-11: no rsync, or a failed copy back, is exit 2 and never "applied"
echo original > $G/app/marker.txt; rm -f $G/app/fixed.txt
# E7-20: the fixer runs under the heavy lock; a fixer that takes the lock itself does not deadlock (re-entrant)
rm -f $G/app/fixed.txt
ctl guard-fixer-locked-pass 0 'applied' -- env UPG_GUARD_MX=$T/fakemx.sh zsh $B/repair/design_props_guard.sh $G/app 10.24.16 -- zsh $B/heavy-lock.sh inner bash -c "test -e $UPG_LOCK && echo $FX/check/after-better.log > fixed.txt" APP
# batch 1 (T1-19, T2-8, T3-16, T4-4, T5-11, T6-7, T8-15): "applied" only when the app holds the fixed copy. Without
# rsync the cp fallback applies it (proved by a file diff); a failing rsync is APPLY FAILED, exit 1, never "applied".
GL=$T/guardlogs; mkdir -p $GL
printf '[error] [CE6087] Design property "Spacing" is not supported\nThe app contains: 1 errors.\n' > $GL/before.log
printf 'The app contains: 0 errors.\n' > $GL/after.log
printf '#!/bin/bash\nshift; [ "$1" = mx ] && shift\n[ "$1" = check ] && { if [ -f "$(dirname "$2")/fixed.txt" ]; then cat %s/after.log; else cat %s/before.log; fi; }\nexit 0\n' $GL $GL > $T/fakemx-own.sh; chmod +x $T/fakemx-own.sh
NR=$T/norsync; mkdir -p $NR   # PATH without rsync: every other command on PATH, linked
for d in $(echo "$PATH" | tr ':' ' '); do for f in "$d"/*; do n=${f##*/}; [ "$n" = rsync ] || [ -e "$NR/$n" ] || ln -s "$f" "$NR/$n" 2>/dev/null; done; done
mkdir -p $T/badrsync; printf '#!/bin/sh\necho "rsync: [receiver] mkstemp failed: No space left on device (28)" >&2\nexit 23\n' > $T/badrsync/rsync; chmod +x $T/badrsync/rsync
guardapp() { rm -rf $T/guard2; mkdir -p $T/guard2/app/sub; cp $M/base/App.mpr $T/guard2/app/; echo original > $T/guard2/app/marker.txt; echo old > $T/guard2/app/sub/gone.txt; }
FIXER="echo x > fixed.txt; echo fixed > marker.txt; rm sub/gone.txt"
guardapp
ctl design-props-no-rsync-catch 0 'applied \(fixer rc 0; cp fallback, rsync not found\)' '!APPLY FAILED' -- env PATH=$NR UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER" APP
ctl design-props-no-rsync-applied-pass 0 '^same$' -- sh -c "diff -rq $T/guard2/repair-guard/copy $T/guard2/app && test ! -e $T/guard2/app/sub/gone.txt && grep -qx fixed $T/guard2/app/marker.txt && echo same"
guardapp
ctl design-props-rsync-fail-catch 1 'APPLY FAILED: copying the fixed copy back \(rsync\) failed' '!^applied' -- env PATH=$T/badrsync:$PATH UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER" APP
ctl design-props-rsync-fail-unchanged-pass 0 '^original$' -- cat $T/guard2/app/marker.txt
# M2: mx check crashing with rc 139 (segfault, no output) is named a CRASH to retry, not "not an mx check output"
printf '#!/bin/bash\nexit 139\n' > $T/fakemx-139.sh; chmod +x $T/fakemx-139.sh
guardapp
ctl design-props-crash-139-catch 1 '^CRASHED: .*rc 139.*mx check before; .*mx check after; original untouched.*retry.*LD_PRELOAD=' '!not an mx check' '!^REFUSED' -- env UPG_GUARD_MX=$T/fakemx-139.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER" APP
ctl design-props-crash-139-unchanged-pass 0 '^original$' -- cat $T/guard2/app/marker.txt
guardapp
ctl design-props-no-crash-pass 0 '^applied' '!CRASHED' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER" APP
# FM-2: a check-before that dies in the model loader once (emulation flake) is rerun, not taken as the result
printf '#!/bin/bash\nshift; [ "$1" = mx ] && shift\nif [ "$1" = check ]; then\n  if [ -f "$(dirname "$2")/fixed.txt" ]; then cat %s/after.log; exit 0; fi\n  n=$(cat %s/flaky.n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > %s/flaky.n\n  if [ $n -le 2 ]; then echo "Unhandled exception. System.NullReferenceException: Object reference not set to an instance of an object."; exit 1; fi\n  cat %s/before.log\nfi\nexit 0\n' $GL $GL $GL $GL > $T/fakemx-flaky.sh; chmod +x $T/fakemx-flaky.sh
guardapp; rm -f $GL/flaky.n
ctl design-props-loader-flake-retry-pass 0 'check-before hit a model loader exception|guard-before hit a model loader exception' '^applied' '!REFUSED' -- env UPG_GUARD_MX=$T/fakemx-flaky.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER" APP
# B4T2-7: a fixer without the literal APP (the .mpr passed instead) edited the original, the unchanged copy was copied
# back over it and the guard said "applied": refused before anything runs, exit 2; a fixer naming the app itself too;
# a fixer that changes nothing is NO-OP, exit 1, never "applied"
guardapp
ctl guard-no-app-catch 2 'REFUSED, the fixer command has no literal APP' '!applied' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- bash -c "$FIXER"
ctl guard-no-app-untouched-pass 0 '^original$' -- sh -c "cat $T/guard2/app/marker.txt; test ! -e $T/guard2/repair-guard/copy || echo copy-made"
ctl guard-names-mpr-catch 2 'REFUSED, the fixer names the app itself' '!applied' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- sh -c 'echo fixed > "$1"/../marker.txt; : APP' sh $T/guard2/app/App.mpr
ctl guard-names-app-dir-catch 2 'REFUSED, the fixer names the app itself' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- sh -c ': APP' sh $T/guard2/app
ctl guard-names-untouched-pass 0 '^original$' -- cat $T/guard2/app/marker.txt
ctl guard-noop-catch 1 '^NO-OP: the fixer exited 0 but the copy is identical' '!^applied' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- true APP
ctl guard-app-in-fixer-pass 0 '^applied \(fixer rc 0' -- env UPG_GUARD_MX=$T/fakemx-own.sh zsh $B/repair/design_props_guard.sh $T/guard2/app 10.24.16 -- sh -c 'test -f "$1" && cd "${1%/*}" && echo x > fixed.txt && echo fixed > marker.txt' sh APP
ctl guard-app-in-fixer-applied-pass 0 '^fixed$' -- cat $T/guard2/app/marker.txt
# E7-5: pds_oldnames.sh hides property-level oldNames of an internal design system for the rename and restores the file
P=$T/pds; mkdir -p $P/themesource/platformdesignsystem/web $P/themesource/atlas_core/web $P/themesource/plain/web; : > $P/App.mpr
printf '{\n  "DivContainer": [{"name": "Margin top", "oldNames": ["Spacing top"], "type": "Dropdown", "options": [{"name": "S"}]}],\n  "Button": [{"name": "Size", "type": "Dropdown"}]\n}\n' > $P/themesource/platformdesignsystem/web/design-properties.json
printf '{"DivContainer": [{"name": "Spacing", "oldNames": ["Spacing top"], "type": "Spacing"}]}\n' > $P/themesource/atlas_core/web/design-properties.json
printf '{"Button": [{"name": "Size", "type": "Dropdown"}]}\n' > $P/themesource/plain/web/design-properties.json
cp $P/themesource/platformdesignsystem/web/design-properties.json $T/pds-orig.json
printf '#!/bin/bash\n# fake toolset: which design-properties files still carry oldNames when the rename runs\necho "rename $*"; grep -l oldNames %s/themesource/*/web/design-properties.json | sed "s|.*/themesource/|still: |"; exit ${PDS_RC:-0}\n' $P > $T/fakepdsmx.sh
chmod +x $T/fakepdsmx.sh
ctl pds-oldnames-hidden-catch 0 'hidden 1 property-level oldNames .*platformdesignsystem' 'Margin top <- Spacing top' 'still: atlas_core' '!still: platformdesignsystem' 'rename 10.24.16 mx rename-design-properties' 'restored 1' -- env UPG_PDS_MX=$T/fakepdsmx.sh zsh $B/repair/pds_oldnames.sh 10.24.16 $P/App.mpr
ctl pds-oldnames-restored-pass 0 -- cmp $T/pds-orig.json $P/themesource/platformdesignsystem/web/design-properties.json
ctl pds-oldnames-rename-fail-catch 7 'restored 1' -- env PDS_RC=7 UPG_PDS_MX=$T/fakepdsmx.sh zsh $B/repair/pds_oldnames.sh 10.24.16 $P/App.mpr
ctl pds-oldnames-restored-after-fail-pass 0 -- cmp $T/pds-orig.json $P/themesource/platformdesignsystem/web/design-properties.json
ctl pds-oldnames-usage-catch 2 'no file' -- zsh $B/repair/pds_oldnames.sh 10.24.16 $P/Nope.mpr
# E6-14: heavy-lock.sh refuses an executable path as the label instead of running the version as a command
ctl heavy-lock-label-missing-catch 2 'label missing' '!command not found' -- zsh $B/heavy-lock.sh $B/mx10.sh 10.24.16 mx check x.mpr
ctl heavy-lock-label-pass 0 'lbl rc=0' -- zsh $B/heavy-lock.sh lbl true

# --- 9 -> 10: final Java action parameters (E5 F19) -------------------------------------------------------------------
ctl javafinal-catch 1 'Create_201.*ContentType' 'Create_400.*StatusCode' -- python3 $B/javafinal.py $FX/java/catch
ctl javafinal-pass 0 -- python3 $B/javafinal.py $FX/java/pass
ctl javafinal-input-catch 2 -- python3 $B/javafinal.py $FX/rest

# --- seed: unique System.User names across specializations (E5 F3) ----------------------------------------------------
uniq_names() { "$@" | python3 $here/lib/uniqnames.py; }
FP="python3 $here/lib/fakepsql.py $FX/seed/two-user-specializations.json"
ctl seed-unique-pass 0 '6 names, duplicates: \[\]' -- uniq_names python3 $B/seed_pg.py --psql "$FP" --dry-run
cp $B/pgmap.py $T/   # seed_pg.py imports it from its own folder (E2E-9)
sed 's/s = f"s{short}x{seq}"/s = f"s{seq}"/' $B/seed_pg.py > $T/seed_pg_old.py   # the E5 formula, to prove the check bites
ctl seed-unique-catch 1 "duplicates: \\['s2'" -- uniq_names python3 $T/seed_pg_old.py --psql "$FP" --dry-run
# T6R-13: enum columns get the enumeration's first value from the model (--mpr), else stay NULL and are NAMED; FileDocument
# specializations (System.Image too) are not seeded by default (no file in the file store: FileNotFoundInStorageException)
FPE="python3 $here/lib/fakepsql.py $FX/seed/enum-filedoc.json"; SE=$(model seed-enums)
ctl seed-enum-fill-pass 0 "\"certificatetype\", \"reference\"\\) VALUES \\('[0-9]+', 'PublicKey'" "\"tokentype\"\\) VALUES \\('[0-9]+', 'REFRESH_TOKEN'" \
    'enum columns with a value from the model: 2; LEFT NULL: 1 \(MendixSSO\.Token\.Scope\)' '!: pass --mpr' -- python3 $B/seed_pg.py --psql "$FPE" --dry-run --mpr $SE/App.mpr
ctl seed-enum-null-named-catch 0 'LEFT NULL: 3 \(Encryption\.PGPCertificate\.CertificateType, MendixSSO\.Token\.Scope, MendixSSO\.Token\.TokenType\): pass --mpr' '!PublicKey' -- python3 $B/seed_pg.py --psql "$FPE" --dry-run
ctl seed-filedocs-skipped-pass 0 'FileDocument entities NOT seeded .*: 2 \(Encryption\.KeyFile, Encryption\.LogoImage\)' '!INSERT INTO "system\$filedocument"' '!pgpcertificate_keyfile' -- python3 $B/seed_pg.py --psql "$FPE" --dry-run --mpr $SE/App.mpr
ctl seed-filedocs-optin-catch 0 'INSERT INTO "system\$filedocument" .*Encryption\.LogoImage' 'INSERT INTO "encryption\$pgpcertificate_keyfile"' '!NOT seeded' -- python3 $B/seed_pg.py --psql "$FPE" --dry-run --mpr $SE/App.mpr --with-filedocuments
ctl seed-mpr-missing-catch 1 'no such file' -- python3 $B/seed_pg.py --psql "$FPE" --dry-run --mpr $T/nope.mpr
# N3-7, T7-9, T7R-3, T6-3: System objects are never seeded (also with --skip-module), nor singletons (1 row); override wins
FS="python3 $here/lib/fakepsql.py $FX/seed/system-and-singleton.json"
ctl seed-system-skip-catch 0 'INSERT INTO "shop\$order"' '!INSERT INTO "system\$language"' '!INSERT INTO "system\$user_language"' -- python3 $B/seed_pg.py --psql "$FS" --skip-module Foo --dry-run
ctl seed-system-optin-pass 0 'INSERT INTO "system\$language"' 'INSERT INTO "system\$user_language"' -- python3 $B/seed_pg.py --psql "$FS" --seed-system --dry-run
ctl seed-singleton-catch 0 'singleton: Config.Settings holds 1 row' '!INSERT INTO "config\$settings"' '!singleton: Administration' 'INSERT INTO "administration\$account"' -- python3 $B/seed_pg.py --psql "$FS" --dry-run
ctl seed-singleton-override-pass 0 'entities seeded: 3, objects: 8' '!singleton: Config' -- python3 $B/seed_pg.py --psql "$FS" --per-entity-override Config.Settings=2 --dry-run
ctl seed-override-unknown-catch 1 'no such persistent entity: Nope.X' -- python3 $B/seed_pg.py --psql "$FS" --per-entity-override Nope.X=1 --dry-run
# BT-5: object_sequence is the next id the runtime hands out, so it must sit one PAST the last seeded id
ctl seed-sequence-next-pass 0 "SET object_sequence = 5 WHERE id = 'e2'" "SET object_sequence = 4 WHERE id = 'e6'" -- python3 $B/seed_pg.py --psql "$FS" --dry-run
sed 's/{seq0 + cnt + 1} WHERE/{seq0 + cnt} WHERE/' $B/seed_pg.py > $T/seed_pg_bt5.py
ctl seed-sequence-next-catch 0 "!SET object_sequence = 5 WHERE id = 'e2'" -- python3 $T/seed_pg_bt5.py --psql "$FS" --dry-run

# --- seed: the publisher's demo data (data-snapshot.zip, HSQLDB) into Postgres (T5-10, T3-11) -------------------------------
# fixtures/snapshot is FORMAT-DERIVED (HSQLDB 2.x script lines as the three worker loaders parse them), not a capture: no
# real default.script is committed on any run branch. Replace it with a truncated real one when one is.
SNAP=$FX/snapshot; SS="python3 $B/seed_snapshot.py"
ctl seed-snapshot-dryrun-counts-pass 0 'demo\$product +6 +1 +5 +5 ' 'demo\$order +3 +1 +2 +2 ' 'demo\$order_product +4 +1 +3 +3 ' \
  'administration\$account +1 +0 +1 +1 ' 'system\$session .*skipped: login sessions' 'mendixsystem\$entity +5 .*skipped: runtime mapping' \
  '31 INSERT statements, 3 rows deleted, 28 net rows in 10 tables; skipped by rule 11, .* to load 17' 'NOT checked' '!UNMAPPED' -- $SS $SNAP --dry-run
python3 - "$SNAP" "$T/snap.zip" <<'PYZ'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[2], "w")
for f in ("default.script", "default.log"): z.write(f"{sys.argv[1]}/data/database/hsqldb/{f}", f"data/database/hsqldb/{f}")
z.writestr("data/files/documents/1", "x")
PYZ
ctl seed-snapshot-zip-pass 0 'to load 17' '1 files under files/' '!UNMAPPED' -- $SS $T/snap.zip --dry-run
ctl seed-snapshot-usage-catch 1 'psql CMD is required' -- $SS $SNAP
ctl seed-snapshot-missing-catch 1 'no default.script' -- $SS $T/out --dry-run
mkdir -p $T/snapbad/d; cp $SNAP/data/database/hsqldb/default.script $T/snapbad/d/
printf '%s\n' '/*C1*/UPDATE "demo$product" SET "stock"=1 WHERE "id"=1' > $T/snapbad/d/default.log
ctl seed-snapshot-unknown-statement-catch 1 'UNMAPPED \(1\)' 'statement not understood: UPDATE "demo\$product"' -- $SS $T/snapbad --dry-run
mkdir -p $T/snapbad2/d; sed '/^INSERT INTO "demo\$order_product" VALUES(1125899906842625,/s/)$/,7)/' $SNAP/data/database/hsqldb/default.script > $T/snapbad2/d/default.script
ctl seed-snapshot-value-count-catch 1 'UNMAPPED' 'order_product has 3 values for 2 columns' -- $SS $T/snapbad2 --dry-run
# PLM-4: HSQLDB internals in default.log (CREATE FUNCTION, INSERT INTO BLOCKS) are ignored, not UNMAPPED
mkdir -p $T/snapint/d; cp $SNAP/data/database/hsqldb/default.script $T/snapint/d/
printf '%s\n' '/*C1*/CREATE FUNCTION PUBLIC.MX_TOLOCALDATETIME(IN P1 TIMESTAMP) RETURNS TIMESTAMP LANGUAGE JAVA' '/*C1*/INSERT INTO BLOCKS VALUES(0,2147483647,0)' > $T/snapint/d/default.log
ctl seed-snapshot-hsqldb-internals-pass 0 '!UNMAPPED \(' -- $SS $T/snapint --dry-run
# SD-1: HSQLDB writes LOB block-map bookkeeping into default.log; it carries no row of the app and must not stop the replay.
mkdir -p $T/snapblocks/d; cp $SNAP/data/database/hsqldb/default.script $T/snapblocks/d/
printf '%s\n' '/*C1*/INSERT INTO BLOCKS VALUES(0,2147483647,0)' > $T/snapblocks/d/default.log
ctl seed-snapshot-blocks-bookkeeping-catch 0 '!UNMAPPED' '!statement not understood' 'to load 18' -- $SS $T/snapblocks --dry-run
printf '%s\n' '/*C1*/INSERT INTO BLOCKS VALUES(0,2147483647,0)' '/*C1*/INSERT INTO BLOCKSX VALUES(1)' > $T/snapblocks/d/default.log
ctl seed-snapshot-blocks-not-blanket-pass 1 'UNMAPPED \(1\)' 'statement not understood: INSERT INTO BLOCKSX' -- $SS $T/snapblocks --dry-run
if PGC=$(bash $here/lib/pgtmp.sh start 2>/dev/null); then
  PGD=$(echo "$PGC" | awk '{print $3}'); pgx() { psql -h "$PGD" -U mendix -qtA "$@"; }
  pgx -d fx -f $SNAP/pg-schema.sql > /dev/null && for n in ok colgone noguid skipt; do pgx -d fx -c "create database t_$n template fx" > /dev/null; done
  mypsql() { echo "psql -h $PGD -U mendix -d t_$1"; }
  pgx -d t_colgone -c 'alter table "demo$product" drop column price' ; pgx -d t_colgone -c 'drop table "demo$order_product"'
  pgx -d t_noguid -c "delete from \"mendixsystem\$entityidentifier\" where short_id=13"
  ctl seed-snapshot-mapping-dryrun-pass 0 'system\$user +2 +0 +2 +1 +matched by name: 1' 'system\$userroles +2 +0 +2 +1 +already present: 1' 'to load 14' 'dry run: nothing written' '!UNMAPPED' -- $SS $SNAP --psql "$(mypsql ok)" --dry-run
  ctl seed-snapshot-dryrun-writes-nothing-pass 0 '^0$' -- pgx -d t_ok -c 'select count(*) from "demo$product"'
  ctl seed-snapshot-apply-pass 0 'applied: 14 rows in 7 tables; every table gained exactly' '!UNMAPPED' -- $SS $SNAP --psql "$(mypsql ok)"
  ctl seed-snapshot-remap-pass 0 '^5\|13\|5$' -- pgx -d t_ok -F'|' -c 'select count(*), max(id>>48), max(id & 281474976710655) from "demo$product"'
  ctl seed-snapshot-userrole-pass 0 '^MxAdmin\|11$' '^demo_clerk\|11$' '!pg-admin-hash.*pg-admin-hash' -- pgx -d t_ok -F'|' -c 'select name, id>>48 from "system$user" order by id'
  ctl seed-snapshot-sequence-pass 0 'b2222222-0000-4000-8000-000000000001\|13\|6$' -- pgx -d t_ok -F'|' -c 'select * from "mendixsystem$entityidentifier" order by short_id'
  ctl seed-snapshot-column-missing-catch 1 'UNMAPPED \(2\)' 'column demo\$product.price has no counterpart' 'table demo\$order_product \(3 rows\) has no counterpart' 'nothing was loaded' -- $SS $SNAP --psql "$(mypsql colgone)"
  ctl seed-snapshot-column-missing-loaded-nothing-pass 0 '^0$' -- pgx -d t_colgone -c 'select count(*) from "demo$product"'
  ctl seed-snapshot-skip-waiver-pass 1 'waived \(--skip\)' 'column demo\$product.price' '!has no counterpart in the database \(' -- $SS $SNAP --psql "$(mypsql colgone)" --dry-run --skip demo\$order_product
  ctl seed-snapshot-entity-guid-catch 1 'GUID b2222222-0000-4000-8000-000000000001\) is not in the database' 'carry entity short id 3, which' -- $SS $SNAP --psql "$(mypsql noguid)" --dry-run
  ctl seed-snapshot-psql-error-catch 2 'psql failed' -- $SS $SNAP --psql "psql -h $PGD -U mendix -d nope" --dry-run
  bash $here/lib/pgtmp.sh stop "$PGD"
else skip seed-snapshot-postgres "no postgres binaries or the throwaway cluster did not start"; fi

# --- smokewalk wait predicates (E5 F9) ----------------------------------------------------------------------------------
if command -v node > /dev/null; then ctl smokewalk-predicates 0 '^ok +loggedIn while session throws' '!^FAIL' -- node $here/smokewalk_predicates.js
# R1: the React client has no mx.session.getUserName / mx.ui.getContentForm; an anonymous session is not logged in, a content page maps to its Dojo path
ctl smokewalk-react-catch 0 '^ok +react loggedIn when anonymous' '^ok +react contentPath without page' '^ok +react landedWhere on a popup state' -- node $here/smokewalk_predicates.js
ctl smokewalk-react-pass 0 '^ok +react loggedIn when ready' '^ok +react homeReady when ready' '^ok +react contentPath maps to the page path' '^ok +react landedWhere on the wanted page' '^ok +react landedWhere on another page' -- node $here/smokewalk_predicates.js
# T3-6: a step is judged by what the browser shows: the login form and the "An error occurred" dialog FAIL, a clean page passes
ctl smokewalk-landedok-pass 0 '^ok +landedOk login form page .*FAIL wanted' '^ok +landedOk error dialog .*FAIL wanted' '^ok +landedOk clean page .*PASS wanted' \
  '^ok +landedOk hidden login form .*PASS wanted' '^ok +landedOk when inspection throws is not a pass' '!^FAIL' -- node $here/smokewalk_predicates.js
# T6R-9: the compare pools repeated walks (fixtures/smoke/, --rejudge = no browser). A new error the old walks never showed
# is a REGRESSION, also when intermittent; the old app's own intermittent error on the new side is FLAKY on both (exit 2)
SW="node $B/smokewalk.js"; SF=$FX/smoke
ctl smoke-judge-single-regression-catch 1 '^  REGRESSION Clerk \| menu \| Orders \| Shop.Orders_Overview: PASS -> FAIL$' 'regressions: 1$' -- $SW --rejudge $SF/new-fail-same.json --compare $SF/old-pass.json
ctl smoke-judge-intermittent-catch 1 '^  REGRESSION \(intermittent: 1 of 2\) Clerk \| menu \| Orders .*old PASS 3 of 3, new not PASS 1 of 2' 'Orders -> Shop.Orders_Overview \[not PASS in 1 of 2 walks\]' '1 intermittent' \
  -- $SW --rejudge $SF/new-fail-same.json --rejudge $SF/new-pass.json --compare $SF/old-pass.json --compare $SF/old-pass.json --compare $SF/old-pass.json
ctl smoke-judge-flaky-both-pass 2 '^  FLAKY on both Clerk \| menu \| Orders .*old not PASS 1 of 3, new 1 of 1, same error: console: .*dataView#: attempt to uninitialize' 'regressions: 0$' '!  REGRESSION' \
  -- $SW --rejudge $SF/new-fail-same.json --compare $SF/old-flaky-a.json --compare $SF/old-flaky-b.json --compare $SF/old-pass.json
ctl smoke-judge-flaky-new-error-catch 1 '^  REGRESSION Clerk \| menu \| Orders .*old PASS 1 of 2, new not PASS 1 of 1; error not seen on the old app: pageerror: Cannot read' '!FLAKY on both' \
  -- $SW --rejudge $SF/new-fail-other.json --compare $SF/old-flaky-a.json --compare $SF/old-flaky-b.json
ctl smoke-judge-flaky-baseline-pass 0 '^  FLAKY-BASELINE Clerk \| menu \| Orders .*old not PASS 1 of 2, new PASS 2 of 2' 'regressions: 0$' \
  -- $SW --rejudge $SF/new-pass.json --rejudge $SF/new-pass.json --compare $SF/old-flaky-a.json --compare $SF/old-flaky-b.json
ctl smoke-judge-partial-walk-pass 0 '^  PASS +menu +Orders -> Shop.Orders_Overview$' '^steps: PASS 4, FAIL 0, INVALID 0' 'regressions: 0$' \
  -- $SW --rejudge $SF/new-pass.json --rejudge $SF/new-desk-only.json --compare $SF/old-pass.json
# T5: --login-path (default /login.html), also through the gate (SMOKE_LOGIN_PATH)
lp() { node -e "process.argv=['node','x','--plan','p','--url','http://h:1','--rejudge','r','--compare','c'$1]; const m=require('$B/smokewalk.js'); const o=m.args(); console.log('loginPath', o.loginPath, 'url', m.loginUrl(o.url, o.loginPath))"; }
ctl smokewalk-login-path-catch 0 '^loginPath /login-without-sso.html url http://h:1/login-without-sso.html$' -- lp ",'--login-path','/login-without-sso.html'"
ctl smokewalk-login-path-default-pass 0 '^loginPath /login.html url http://h:1/login.html$' -- lp ""
ctl smokewalk-login-path-bad-catch 2 'needs a path starting with /' -- lp ",'--login-path','login.html'"
ctl smoke-rejudge-needs-compare-catch 2 'rejudge needs --compare' -- $SW --rejudge $SF/new-pass.json
ctl smokewalk-api-only-pass 0 '^ok +apiOnlyHome login page home: got true' '^ok +apiOnlyHome ordinary home: got null' '^ok +apiOnlyHome menu step to the login page: got null' '!^FAIL' -- node $here/smokewalk_predicates.js
else skip smokewalk-predicates "no node"; for n in single-regression-catch intermittent-catch flaky-both-pass flaky-new-error-catch flaky-baseline-pass partial-walk-pass; do skip smoke-judge-$n "no node"; done; skip smoke-rejudge-needs-compare-catch "no node" ; skip smokewalk-api-only-pass "no node"; fi

# --- safety guards: frozen DB, DB prefix, heavy lock (E1 1, E1 3, E5 F10, E5 F11) ----------------------------------------
ctl smoke-users-refuse-catch 2 'REFUSED' -- python3 $B/smoke_users.py appdb
# T1-27, T2-15, T6-16: the gate's own journey copies (X_jold, X_after) are accepted when the run ledger lists them
printf 't1_x_jold journeys - 2026-10-06T10:00:00\nt1_x_frozen snapshot - 2026-10-06T09:00:00\n' > $T/smoke-ledger.txt
ctl smoke-users-ledger-catch 2 'REFUSED t1_x_other: not a copy' 'does not list it' -- python3 $B/smoke_users.py t1_x_other --ledger $T/smoke-ledger.txt
ctl smoke-users-frozen-catch 2 'REFUSED t1_x_frozen: a frozen baseline' -- python3 $B/smoke_users.py t1_x_frozen --ledger $T/smoke-ledger.txt --any-db
if python3 -c "import bcrypt" 2> /dev/null; then
  ctl smoke-users-ledger-pass 0 'one login per role on a DATABASE COPY' '!REFUSED' -- python3 $B/smoke_users.py t1_x_jold --ledger $T/smoke-ledger.txt
else skip smoke-users-ledger-pass "no python bcrypt"; fi
# T3-6 / T3F-2: the user is created as the entity the home microflow retrieves, never guessed; an empty password is no login
SU="python3 $here/lib/fakepsql.py $FX/seed"
ctl smoke-users-empty-password-catch 2 'REFUSED: the password is empty' -- python3 $B/smoke_users.py t1_x_jold --ledger $T/smoke-ledger.txt --password ''
ctl smoke-users-blank-password-catch 2 'REFUSED: the password is empty' -- python3 $B/smoke_users.py t1_x_jold --ledger $T/smoke-ledger.txt --password '   '
ctl smoke-users-bad-entity-catch 2 'bad --entity' -- python3 $B/smoke_users.py t1_x_jold --ledger $T/smoke-ledger.txt --entity 'a;drop' --password x
if python3 -c "import bcrypt" 2> /dev/null; then
  ctl smoke-users-ambiguous-catch 2 'AMBIGUOUS' 'CustomAdminModule.UserAccount, Other.PartnerAccount' '--entity Module.Entity' '!DO \$\$' \
    -- python3 $B/smoke_users.py fx_t --psql "$SU/user-two-below-account.json" 
  ctl smoke-users-auto-one-pass 0 'user entity CustomAdminModule.UserAccount \(the only specialization' "given text := 'CustomAdminModule.UserAccount'" \
    'short_id .*FROM "mendixsystem\$entity" e JOIN "mendixsystem\$entityidentifier"' 'sid << 48' "VALUES \\(uid, 'smoke_' .*, leaf\\)" 'INSERT INTO %I \(id\)' '!AMBIGUOUS' \
    -- python3 $B/smoke_users.py fx_t --psql "$SU/user-one-below-account.json"
  ctl smoke-users-entity-flag-pass 0 "given text := 'Other.PartnerAccount'" 'user entity Other.PartnerAccount \(--entity\)' '!AMBIGUOUS' '!REFUSED' \
    -- python3 $B/smoke_users.py fx_t --entity Other.PartnerAccount --psql "$SU/user-two-below-account.json"
  ctl smoke-users-entity-flag-other-pass 0 "given text := 'CustomAdminModule.UserAccount'" '!Other.PartnerAccount' \
    -- python3 $B/smoke_users.py fx_t --entity CustomAdminModule.UserAccount --psql "$SU/user-two-below-account.json"
  ctl smoke-users-generic-guard-pass 0 'given text := NULL' 'rerun with --entity Module.Entity' 'NOTE database not reachable' \
    -- python3 $B/smoke_users.py fx_t --psql false
else skip smoke-users-ambiguous-catch "no python bcrypt"; skip smoke-users-auto-one-pass "no python bcrypt"; skip smoke-users-entity-flag-pass "no python bcrypt"; fi
# PR-F28: each role's smoke user is the entity that role's own users share (Purchase Request's workflow assigns tasks to
# MendixSSO.MendixSSOUser by role); real Postgres, because the choice is made inside the DO block
# PR-F32: --sole-target leaves each role with its smoke user only (the workflow targets "all users with role X")
holders() { docker exec -i mig-pg psql -U mendix -d fx_ctl_f28 -tA <<'SQL'
select 'holders ' || string_agg(r.name || '=' || u.name, ',' order by r.name, u.name) from "system$userroles" ur
  join "system$user" u on u.id = ur."system$userid" join "system$userrole" r on r.id = ur."system$userroleid";
SQL
}
if [ $fast = 1 ]; then skip smoke-users-per-role-pass "--fast"
elif [ -n "$only" ] && ! printf '%s\n' smoke-users-per-role-pass smoke-users-shared-roles-catch smoke-users-sole-target-pass | grep -Eq "$only"; then :
elif ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mig-pg || ! python3 -c "import bcrypt" 2> /dev/null; then
  skip smoke-users-per-role-pass "no running mig-pg or no python bcrypt"
else
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_f28 && docker exec mig-pg createdb -U mendix fx_ctl_f28 \
    && docker exec -i mig-pg psql -q -U mendix -d fx_ctl_f28 -v ON_ERROR_STOP=1 < $FX/smoke-users/per-role.sql > /dev/null
  ctl smoke-users-per-role-pass 0 'smoke_approver -> role Approver \(MendixSSO\.MendixSSOUser\)' 'smoke_viewer -> role Viewer \(Administration\.Account\)' \
    'smoke_admin -> role Admin \(Administration\.Account\)' \
    'smoke_ops -> role Ops \(MendixSSO\.MendixSSOUser\)' \
    -- python3 $B/smoke_users.py fx_ctl_f28 --apply
  ctl smoke-users-shared-roles-catch 0 'Approver=demo_approver,' '!sole target' -- sh -c "cat $T/out/smoke-users-per-role-pass.txt; $(declare -f holders); holders"
  ctl smoke-users-sole-target-pass 0 'sole target: role Approver taken from 2 other' 'sole target: role Admin taken from 3 other' \
    'holders Admin=smoke_admin,Approver=smoke_approver,Ops=smoke_ops,Viewer=smoke_viewer$' \
    -- sh -c "python3 $B/smoke_users.py fx_ctl_f28 --sole-target --apply && $(declare -f holders); holders"
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_f28 > /dev/null
fi
# PR-F33: the park fixture assigns a waiting task whose only target is one user to that user, and nothing else (a
# task two users may take, one already assigned, one completed); real Postgres, the statement is one CTE
assignees() { docker exec -i mig-pg psql -U mendix -d fx_ctl_f33 -tA -c "select 'assignees ' || string_agg(t.name || '=' || u.name, ',' order by t.name) from \"system\$workflowusertask_assignees\" a join \"system\$workflowusertask\" t on t.id = a.\"system\$workflowusertaskid\" join \"system\$user\" u on u.id = a.\"system\$userid\""; }
if [ $fast = 1 ]; then skip journeys-park-assign-pass "--fast"
elif [ -n "$only" ] && ! printf '%s\n' journeys-park-assign-pass journeys-park-assign-again-pass | grep -Eq "$only"; then :
elif ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mig-pg; then skip journeys-park-assign-pass "no running mig-pg"
else
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_f33 && docker exec mig-pg createdb -U mendix fx_ctl_f33 \
    && docker exec -i mig-pg psql -q -U mendix -d fx_ctl_f33 -v ON_ERROR_STOP=1 < $FX/park/tasks.sql > /dev/null
  PKA="import sys; sys.path.insert(0, '$B'); import run_journeys as r; print('assigned', r.assign_sole_targets('docker exec -i mig-pg psql -U mendix -d fx_ctl_f33', 0))"
  ctl journeys-park-assign-pass 0 '^assigned \(1, None\)$' '^assignees t1=smoke_approver,t3=demo_receiver$' \
    -- sh -c "python3 -c \"\$0\" && $(declare -f assignees); assignees" "$PKA"
  ctl journeys-park-assign-again-pass 0 '^assigned \(0, None\)$' -- python3 -c "$PKA"
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_f33 > /dev/null
  # PR-P1 on the real statement: the newest waiting task of each user stays unassigned
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_p1 && docker exec mig-pg createdb -U mendix fx_ctl_p1 \
    && docker exec -i mig-pg psql -q -U mendix -d fx_ctl_p1 -v ON_ERROR_STOP=1 < $FX/park/tasks-many.sql > /dev/null
  PKP="import sys; sys.path.insert(0, '$B'); import run_journeys as r; print('assigned', r.assign_sole_targets('docker exec -i mig-pg psql -U mendix -d fx_ctl_p1'))"
  ctl journeys-park-keep-pg-pass 0 '^assigned \(3, None\)$' -- python3 -c "$PKP"
  ctl journeys-park-keep-pg-again-pass 0 '^assigned \(0, None\)$' -- python3 -c "$PKP"
  docker exec mig-pg dropdb -U mendix --if-exists fx_ctl_p1 > /dev/null
fi
# PR-P1: the park step leaves the newest M waiting tasks of each user unassigned (default 1), so "Assign to me" /
# "Assign to user" (rendered only for a task nobody holds) has a target. Purchase Request: "park: assigned 14" left every
# card on "Unassign" and 10 baseline defects. SQLite runs the selection (ASSIGN_PICK: the same CTEs and WHERE as the
# statement; the INSERT .. RETURNING wrapper is Postgres only, see journeys-park-assign-pass); pass 2 inserts the picks
cat > $T/parkkeep.py <<PYEOF
import sqlite3, sys
sys.path.insert(0, "$B")
import run_journeys as r
db, keep = sqlite3.connect(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else r.PARK_KEEP
for rnd in (1, 2):
    pick = db.execute(r.ASSIGN_PICK.replace("{keep}", str(keep))).fetchall()
    print("round", rnd, "assigns", ",".join(str(x[0]) for x in sorted(pick)))
    db.executemany('insert into "system\$workflowusertask_assignees" values (?, ?)', pick)
q = ('select t.id from "system\$workflowusertask" t where t.state = \'InProgress\' and not exists (select 1 from '
     '"system\$workflowusertask_assignees" a where a."system\$workflowusertaskid" = t.id) order by t.id')
print("unassigned", ",".join(str(x[0]) for x in db.execute(q)))
PYEOF
for k in def zero two; do rm -f $T/pk-$k.db; python3 $here/lib/sqlitepsql.py $T/pk-$k.db --init $FX/park/tasks-many.sql; done
ctl journeys-park-keep-pass 0 '^round 1 assigns 21,22,23$' '^unassigned 24,25$' -- python3 $T/parkkeep.py $T/pk-def.db
ctl journeys-park-keep-again-pass 0 '^round 2 assigns $' -- python3 $T/parkkeep.py $T/pk-def.db 1
ctl journeys-park-keep-zero-pass 0 '^round 1 assigns 21,22,23,24,25$' '^unassigned $' -- python3 $T/parkkeep.py $T/pk-zero.db 0
ctl journeys-park-keep-two-pass 0 '^round 1 assigns 21,22$' '^unassigned 23,24,25$' -- python3 $T/parkkeep.py $T/pk-two.db 2
ctl journeys-park-keep-statement-pass 0 'rn > 1 RETURNING 1\)' '!\{keep\}' -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r; print(r.ASSIGN_SQL.replace('{keep}', str(r.PARK_KEEP)))"
ctl journeys-park-keep-flag-pass 0 '--park-unassigned M' -- python3 $B/run_journeys.py --help
ctl runapp-prefix-catch 1 'refused' -- env UPG_DB_PREFIX=fx_ UPG_TOOLS=$T python3 $B/runapp.py start ctl $T/none.mda 10.24.16 appdb
# runtime lookup: short or full version, flat or the CDN tarball layout <full version>/runtime (E5b-31, E5b-2)
R=$T/rt; mkdir -p $R/runtime-10.24.16/runtime/launcher $R/runtime-9.24.32/9.24.32.58223/runtime/launcher
: > $R/runtime-10.24.16/runtime/launcher/runtimelauncher.jar; : > $R/runtime-9.24.32/9.24.32.58223/runtime/launcher/runtimelauncher.jar
# --- harness login override for SSO login pages (T2-7, N1-4): detection and replace, no Mendix started ---
LO=$T/lo; mkdir -p $LO
mklo() { rm -rf $LO/$1; mkdir -p $LO/$1/web; printf '%s' "$2" > $LO/$1/web/login.html; [ -z "${3:-}" ] || printf '%s' "$3" > $LO/$1/web/login.old; }
mklo sso '<html><head><meta http-equiv="refresh" content="0; url=./auth/v1/login"></head></html>' '<form><input id="usernameInput"></form>'
mklo sso-nostock '<script>window.location.href="./auth/v1/login"</script>'
mklo normal '<form id="f"><input id="usernameInput"><input id="passwordInput"></form><script src="mxclientsystem/mxui/mxui.js"></script>' '<form>old</form>'
lo() { python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; m=runapp.apply_login_override('$LO/$1','$2','$1'); print(m or 'UNTOUCHED')"; }
# FM-9: `runapp.py stop` without UPG_NAME must not remove another run's container: a fake docker lists fm-new and mig-new
mkdir -p $T/stopdocker $T/stopwork
cat > $T/stopdocker/docker <<'EOF2'
#!/bin/sh
case "$1" in
  ps) printf '%s\n' $STOP_NAMES;;
  rm) echo "$*" >> "$STOP_LOG";;
  logs) echo "log of $2";;
esac
exit 0
EOF2
chmod +x $T/stopdocker/docker
rm -f $T/stop.log
ctl runapp-stop-default-prefix-refused-catch 2 'REFUSED to stop mig-new: UPG_NAME is not set .*fm-new' -- env -u UPG_NAME "PATH=$T/stopdocker:$PATH" WORKDIR=$T/stopwork STOP_LOG=$T/stop.log STOP_NAMES='mig-new fm-new mig-pg' python3 $B/runapp.py stop new
ctl runapp-stop-refused-nothing-removed-pass 0 '^0$' -- sh -c "test -f $T/stop.log && wc -l < $T/stop.log | tr -d ' ' || echo 0"
ctl runapp-stop-with-name-pass 0 'stopping container fm-new' 'stopped fm-new' -- env UPG_NAME=fm "PATH=$T/stopdocker:$PATH" WORKDIR=$T/stopwork STOP_LOG=$T/stop.log STOP_NAMES='mig-new fm-new mig-pg' python3 $B/runapp.py stop new
ctl runapp-stop-only-default-pass 0 'stopping container mig-new' -- env -u UPG_NAME "PATH=$T/stopdocker:$PATH" WORKDIR=$T/stopwork STOP_LOG=$T/stop.log STOP_NAMES='mig-new mig-pg' python3 $B/runapp.py stop new
ctl runapp-stop-allow-default-pass 0 'stopping container mig-new' -- env -u UPG_NAME UPG_ALLOW_DEFAULT_PREFIX=1 "PATH=$T/stopdocker:$PATH" WORKDIR=$T/stopwork STOP_LOG=$T/stop.log STOP_NAMES='mig-new fm-new' python3 $B/runapp.py stop new
ctl runapp-login-sso-catch 0 '^HARNESS CONDITION: sso: .*replaced by login.old' -- lo sso auto
ctl runapp-login-sso-marker-pass 0 'HARNESS CONDITION' 'usernameInput' -- sh -c "cat $LO/sso/harness-login-override.txt $LO/sso/web/login.html; test -f $LO/sso/web/login.html.orig && test -f $LO/sso/web/login.html.gz"
ctl runapp-login-sso-nostock-catch 0 'no stock login page' 'INVALID' -- lo sso-nostock auto
ctl runapp-login-sso-nostock-bytes-pass 0 'auth/v1/login' '!usernameInput' -- cat $LO/sso-nostock/web/login.html
ctl runapp-login-normal-pass 0 '^UNTOUCHED' -- lo normal auto
ctl runapp-login-normal-bytes-pass 0 '!old' '!HARNESS' -- sh -c "cat $LO/normal/web/login.html; ls $LO/normal"
mklo sso-off '<meta http-equiv="refresh" content="0;url=./auth/v1/login">' '<form>old</form>'
ctl runapp-login-off-pass 0 '^UNTOUCHED' -- lo sso-off off
ctl runapp-login-off-bytes-pass 0 'refresh' '!old' -- cat $LO/sso-off/web/login.html
# T4: Academy-style SSO app: login-without-sso.html is found by auto; the client's next hop, index.html, is replaced by index3.html
mklo4() { rm -rf $LO/$1; mkdir -p $LO/$1/web; printf '%s' '<meta http-equiv="refresh" content="0; url=./auth/v1/login">' > $LO/$1/web/login.html
  printf '%s' '<form><input id="usernameInput"></form>' > $LO/$1/web/login-without-sso.html
  printf '%s' '<script>window.location.href="/openid/login"</script>' > $LO/$1/web/index.html; [ -z "${2:-}" ] || printf '%s' '<html>plain index3</html>' > $LO/$1/web/index3.html
  printf 'gz' > $LO/$1/web/index.html.gz; }
mklo4 acad index3; mklo4 acad-noalt
lo4() { python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.apply_login_override('$LO/$1','$2','$1')); print(runapp.apply_index_override('$LO/$1','$1') or 'INDEX-UNTOUCHED')"; }
ctl runapp-login-withoutsso-catch 0 '^HARNESS CONDITION: acad: .*replaced by login-without-sso.html' '^HARNESS CONDITION: acad: web/index.html replaced by index3.html .*SSO sign-in is NOT exercised' '!no stock login page' -- lo4 acad auto
ctl runapp-index-override-bytes-pass 0 'plain index3' 'HARNESS CONDITION' '!openid' -- sh -c "cat $LO/acad/web/index.html $LO/acad/harness-index-override.txt; test -f $LO/acad/web/index.html.orig && ! test -f $LO/acad/web/index.html.gz && grep -q openid $LO/acad/web/index.html.orig"
ctl runapp-index-noalt-catch 0 'web/index.html redirects off-app and the app ships no non-SSO index' 'may land on a 404' -- lo4 acad-noalt auto
ctl runapp-index-noalt-bytes-pass 0 'openid' '!plain' -- cat $LO/acad-noalt/web/index.html
# no login override (normal app, or off): index.html is never touched, even if it redirects
mklo4 acad-off index3
ctl runapp-index-no-override-pass 0 '^None$' '^INDEX-UNTOUCHED' -- lo4 acad-off off
ctl runapp-index-no-override-bytes-pass 0 'openid' '!plain' -- cat $LO/acad-off/web/index.html
# T9: MendixSSOClient push off, only when the constant exists and the caller did not name it
sp() { python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; e,m=runapp.sso_push_override($1,$2,'a'); print(e); print(m or 'NOTE-NONE')"; }
ctl runapp-sso-push-catch 0 "^\{'MendixSSOClient.PushAppDeploymentEnabled': 'false'\}" '^HARNESS CONDITION: a: MendixSSOClient.PushAppDeploymentEnabled=false' -- sp "{'MendixSSOClient.PushAppDeploymentEnabled','X.Y'}" '{}'
ctl runapp-sso-push-absent-pass 0 '^\{\}$' '^NOTE-NONE' -- sp "{'X.Y'}" '{}'
ctl runapp-sso-push-caller-wins-pass 0 '^\{\}$' '^NOTE-NONE' -- sp "{'MendixSSOClient.PushAppDeploymentEnabled'}" "{'MendixSSOClient.PushAppDeploymentEnabled':'true'}"
# field proof on a real Mendix theme (stock page, SSO-button page, SSO-automatic page shipped by Studio Pro)
# the customer 11.x example app and its functional spec live in InputCodeExamples/ (folder names are not repeated here):
# UPG_CUSTOMER_APP / UPG_CUSTOMER_SPEC override, else a glob finds them; no match means the field controls SKIP
ICE=$B/../../InputCodeExamples
CUSTDIR=${UPG_CUSTOMER_APP:-$(ls -d $ICE/customer-11x $ICE/*Routing_Workshop* 2>/dev/null | head -1)}
RW=$CUSTDIR/theme/web
if [ -f $RW/login-with-mendixsso-automatically.html ]; then
  ctl runapp-login-real-pages-pass 0 '^login.html False$' '^login-with-mendixsso-button.html False$' '^login-with-mendixsso-automatically.html True$' -- \
    python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; [print(f, runapp.login_redirects_off_app(open('$RW/'+f).read())) for f in ('login.html','login-with-mendixsso-button.html','login-with-mendixsso-automatically.html')]"
else skip runapp-login-real-pages-pass "no real theme pages in this checkout"; fi
# run_journeys preflight: an app whose login page redirects off-app gets HARNESS CONDITION (journeys INVALID), never a login FAIL
JP=$T/jpre; mkdir -p $JP/sso $JP/plain
printf '<meta http-equiv="refresh" content="0;url=./oauth/v2/login">' > $JP/sso/login.html; printf '<form id="loginForm"><input type="password"></form>' > $JP/plain/login.html
jpre() { python3 -c "
import sys, threading, functools, http.server; sys.path.insert(0, '$B'); import run_journeys as r
h = functools.partial(http.server.SimpleHTTPRequestHandler, directory='$JP/$1'); h.log_message = lambda *a: None
s = http.server.ThreadingHTTPServer(('localhost', 0), h); threading.Thread(target=s.serve_forever, daemon=True).start()
print(r.login_preflight(s.server_address[1], '/login.html'))"; }
ctl journeys-preflight-sso-catch 0 'HARNESS CONDITION: .*redirects off-app' -- jpre sso
ctl journeys-preflight-plain-pass 0 '^None$' -- jpre plain

ctl runapp-runtime-forms-pass 0 '^10.24.16 .*/runtime-10.24.16$' '^10.24.16.96987 .*/runtime-10.24.16$' '^9.24.32.58223 .*/runtime-9.24.32/9.24.32.58223$' -- \
  python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; [print(v, runapp.find_runtime(v, '$R')) for v in ('10.24.16','10.24.16.96987','9.24.32.58223')]"
ctl runapp-runtime-missing-catch 1 'no runtime 10.12.9.123 under' -- env UPG_DB_PREFIX=fx_ UPG_TOOLS=$R python3 $B/runapp.py start ctl $T/none.mda 10.12.9.123 fx_ctl
# E7-13: a second save of one name keeps the first log
mkdir -p $T/fakedock $T/rlog; printf '#!/bin/sh\necho "log $(date +%%s%%N)"\n' > $T/fakedock/docker; chmod +x $T/fakedock/docker
ctl runapp-log-kept-pass 0 'kept the earlier log as runtime-ctl-1.log' 'files 2' -- env "PATH=$T/fakedock:$PATH" WORKDIR=$T/rlog python3 -c "import sys; sys.path.insert(0,'$B'); import runapp, os; runapp.save_log('ctl'); runapp.save_log('ctl'); print('files', len(os.listdir('$T/rlog/logs')))"
rm -rf $T/rlog2; mkdir -p $T/rlog2
ctl runapp-log-single-pass 0 'files 1' '!kept the earlier' -- env "PATH=$T/fakedock:$PATH" WORKDIR=$T/rlog2 python3 -c "import sys; sys.path.insert(0,'$B'); import runapp, os; runapp.save_log('ctl'); print('files', len(os.listdir('$T/rlog2/logs')))"
# B4N1-16: a start records its database; every save also writes logs/runtime-<name>.<db>.log, one stable file that
# gate.sh OLD_LOG can name (the numbered copies moved with every save; workers copied the old start log by hand)
rm -rf $T/rlog3; mkdir -p $T/rlog3/run/old; echo fx_old > $T/rlog3/run/old/runapp-db.txt
ctl runapp-log-db-named-pass 0 '^runtime-old.fx_old.log$' '^runtime-old.log$' '^runtime-old-1.log$' -- env "PATH=$T/fakedock:$PATH" WORKDIR=$T/rlog3 python3 -c "import sys; sys.path.insert(0,'$B'); import runapp, os; runapp.save_log('old'); runapp.save_log('old'); print(*sorted(os.listdir('$T/rlog3/logs')), sep='\n')"
ctl runapp-log-db-latest-pass 0 '^same$' -- sh -c "cmp -s $T/rlog3/logs/runtime-old.fx_old.log $T/rlog3/logs/runtime-old.log && echo same"
# B4T2-12: gate.sh's CONST_OVERRIDES key is a PATH (exported to PRE commands); runapp read it as JSON ("Expecting
# value", every PRE rung rc 1). JSON text and a file path both work; anything else stops before a container is touched
CO=$T/co; mkdir -p $CO; printf '{"Mod.Url": "http://mock:8080"}\n' > $CO/ov.json; printf '{"Mod.Url": ' > $CO/bad.json; printf '["x"]' > $CO/list.json
co() { env CONST_OVERRIDES="$1" python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.const_overrides())"; }
ctl runapp-const-path-pass 0 "^\{'Mod.Url': 'http://mock:8080'\}$" -- co $CO/ov.json
ctl runapp-const-json-pass 0 "^\{'Mod.Url': 'x'\}$" -- co '{"Mod.Url": "x"}'
mkdir -p $T/co2; cp $CO/ov.json $T/co2/const-overrides.json
co2() { env CONST_OVERRIDES="$1" WORKDIR=$T/co2 python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.const_overrides())" 2>&1; }
ctl runapp-const-forgotten-warn 0 "WARN .*const-overrides\.json exists but CONST_OVERRIDES is not set" "container prefix is 'mig'" '^\{\}$' -- co2 ''
ctl runapp-const-set-nowarn-pass 0 "Mod.Url" '!WARN' -- co2 $CO/ov.json
ctl runapp-const-empty-pass 0 '^\{\}$' -- co ''
ctl runapp-const-bad-json-catch 1 'bad.json\) is not valid JSON' 'refused' -- co $CO/bad.json
ctl runapp-const-missing-file-catch 1 'neither a JSON object nor an existing file' -- co $CO/none.json
ctl runapp-const-not-object-catch 1 'must be a JSON object' -- co $CO/list.json
ctl runapp-const-bad-before-start-catch 1 'not valid JSON' '!no runtime' -- env CONST_OVERRIDES=$CO/bad.json UPG_DB_PREFIX=fx_ UPG_TOOLS=$R python3 $B/runapp.py start ctl $T/none.mda 10.12.9.123 fx_ctl
# T2R3-5, B4T2-13: EXFN_Authentication reads run/<name>\model\metadata.json (a Windows path built at runtime);
# auto creates it from the app's own file, removes the previous start's copy, off creates none, a listed file the app
# lacks stops the start
HF=$T/hf; hfapp() { rm -rf $HF; mkdir -p $HF/run/ctl/model $HF/run/ctl/web; echo '{"Constants": []}' > $HF/run/ctl/model/metadata.json; echo w > $HF/run/ctl/web/x.json; }
hf() { python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.harness_files('$HF/run/ctl', 'ctl', sys.argv[1]) or 'NONE')" "$1"; }
hfapp; echo stale > "$HF/run/ctl\\old.json"
ctl runapp-harness-auto-catch 0 '^HARNESS FILE: ctl: run/ctl\\model\\metadata.json' -- hf auto
ctl runapp-harness-auto-file-pass 0 '^same$' '!old.json' -- sh -c "cmp -s '$HF/run/ctl\\model\\metadata.json' $HF/run/ctl/model/metadata.json && echo same; ls $HF/run; cat $HF/run/ctl/harness-files.txt"
ctl runapp-harness-off-pass 0 '^NONE$' -- hf off
ctl runapp-harness-off-removed-pass 0 '^ctl$' -- ls $HF/run
ctl runapp-harness-list-pass 0 'model\\metadata.json, run/ctl\\web\\x.json' -- hf 'model/metadata.json,web\x.json'
ctl runapp-harness-list-missing-catch 1 'the app has no ctl/web/none.json to copy; refused' -- hf 'web/none.json'
ctl runapp-harness-dotdot-catch 1 "without '..'" -- hf '..\..\etc\passwd'
hfapp; rm $HF/run/ctl/model/metadata.json
ctl runapp-harness-auto-absent-pass 0 '^NONE$' -- hf auto
ctl heavy-lock-free-pass 0 'upgrade-toolkit ctl .* pid' 'ctl rc=0' -- zsh $B/heavy-lock.sh ctl cat $UPG_LOCK
ctl heavy-lock-released 1 -- test -e $UPG_LOCK
echo other > $T/busy.lock; (sleep 3; rm -f $T/busy.lock) &
ctl heavy-lock-waits-catch 0 'waiting: other' 'ctl rc=0' -- env UPG_LOCK=$T/busy.lock zsh $B/heavy-lock.sh ctl true

# --- versions and toolset guard (E1 4, E5 F7) -----------------------------------------------------------------------------
V=$T/tools/mxbuild-10.24; mkdir -p $V/runtime/bundles
python3 -c "import zipfile; z=zipfile.ZipFile('$V/runtime/bundles/com.mendix.public-api.jar','w'); z.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nImplementation-Version: 10.24.16.96987\n'); z.close()"
ctl mxversion-toolset 0 '^10\.24\.16\.96987$' -- python3 $B/mxversion.py $V
# S4: the 11.x CDN tarball extracts to <dir>/11.12.2/runtime (3-part folder name): the outer folder is accepted; no jar is still refused
V11=$T/tools/runtime-11.12.2; mkdir -p $V11/11.12.2/runtime/bundles
python3 -c "import zipfile; z=zipfile.ZipFile('$V11/11.12.2/runtime/bundles/com.mendix.public-api.jar','w'); z.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nImplementation-Version: 11.12.2.4711\n'); z.close()"
mkdir -p $T/tools/runtime-11.0.0/11.0.0/runtime
ctl mxversion-runtime11-outer-catch 0 '^11\.12\.2\.4711$' -- python3 $B/mxversion.py $V11
ctl mxversion-runtime11-nojar-pass 2 'no Mendix version found' -- python3 $B/mxversion.py $T/tools/runtime-11.0.0
ctl mxversion-mpr 0 '^9\.24\.32\.58223$' -- python3 $B/mxversion.py $M/v9/App.mpr
# AC-1, AC-7 (Academy; E6 convert.log): mx convert exits 0 with errors and on a refused source; read the log and the mpr
# python's sqlite3 module, not the sqlite3 CLI: the cloud image has no CLI, and the update failing silently left the
# version at 9.24 so these three controls failed on a fresh container (B4T2-2, B4N1-1)
for v in 10.24.16.96987 10.18.1.55792; do mkdir -p $T/conv/$v; cp $M/v9/App.mpr $T/conv/$v/App.mpr
  python3 -c "import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute('update _MetaData set _ProductVersion=?', (sys.argv[2],)); c.commit()" $T/conv/$v/App.mpr $v; done
ctl convertcheck-backlog-pass 0 'CONVERTED 9\.24\.32\.58223 -> 10\.24\.16\.96987' 'REPAIR BACKLOG 31' -- python3 $B/convertcheck.py $FX/logs/convert-errors-backlog.log $T/conv/10.24.16.96987 --target 10.24.16.96987
ctl convertcheck-clean-pass 0 '0 errors, 12 warnings' '!BACKLOG' -- python3 $B/convertcheck.py $FX/logs/convert-clean.log $T/conv/10.24.16.96987/App.mpr --target 10.24.16
ctl convertcheck-refused-catch 1 '^NOT CONVERTED' 'converts only from 10\.24' 'project version is 10\.18\.1\.55792' -- python3 $B/convertcheck.py $FX/logs/convert-refused-1018.log $T/conv/10.18.1.55792 --target 11.15.0
ctl convertcheck-unchanged-catch 1 'project version is 9\.24\.32\.58223, not the target' -- python3 $B/convertcheck.py $FX/logs/convert-errors-backlog.log $M/v9 --target 10.24.16.96987
ctl convertcheck-input-catch 2 -- python3 $B/convertcheck.py $FX/logs/convert-clean.log $M/v9 --target latest
# T2-1: mx convert 9 to 10 binds implicit button arguments to the PAGE PARAMETER inside a data view on a microflow
for v in maps-old maps-new maps-new-arg maps-new-current; do model $v > /dev/null; done
ctl convertcheck-mappings-review-catch 1 '^REVIEW +Shop\.Config_NewEdit: .*dataView1/saveButton:Shop\.ACT_Save' 'source MicroflowSource' 'ClientConfiguration = \$ClientConfiguration' '1 REVIEW, 2 INFO' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new
ctl convertcheck-mappings-same-object-pass 1 '^INFO +Shop\.Phone_Edit: .*actionButton2' 'maps the object of data view dataView6' '!^REVIEW +Shop\.Phone_Edit' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new
ctl convertcheck-mappings-unchanged-pass 1 '!Shop\.Stable' '!explicitButton' '!implicitButton' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new
ctl convertcheck-mappings-none-pass 0 '^0 call sites got an explicit mapping' '!REVIEW +Shop' -- python3 $B/convertcheck.py --mappings $M/maps-new $M/maps-new
ctl convertcheck-mappings-input-catch 2 -- python3 $B/convertcheck.py --mappings $M/maps-old $T/no-such-model
# the Argument-expression shape of real 10.x units (Forms$PageParameterMapping.Argument, empty PageVariable)
ctl convertcheck-mappings-arg-review-catch 1 '^REVIEW +Shop\.Config_NewEdit: .*dataView1/saveButton' 'ClientConfiguration = \$ClientConfiguration \(ref\)' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new-arg
ctl convertcheck-mappings-arg-own-dataview-pass 1 '^INFO +Shop\.Phone_Edit: .*actionButton2' '!^REVIEW +Shop\.Phone_Edit' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new-arg
# T2R3-8 / B4T2-8: the repair.md row 12 fix (Opcenter save-fix.mdl: Save maps $currentObject) stayed REVIEW. $currentObject
# inside the data view is that view's object (INFO); a REVIEW checked and kept is answered in writing, pinned to the mapping
CC="python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new-arg"
ctl convertcheck-mappings-currentobject-pass 0 '^INFO +Shop\.Config_NewEdit: .*saveButton.*currentObject.*maps the object of data view dataView1' ' 0 REVIEW, 3 INFO' '!^REVIEW' -- python3 $B/convertcheck.py --mappings $M/maps-old $M/maps-new-current
ctl convertcheck-mappings-review-prints-pin 1 '^REVIEW +Shop\.Config_NewEdit: .*@maps:[0-9a-f]{12}' 'answer it in writing' -- $CC
CCH=$($CC 2>/dev/null | sed -n 's/^REVIEW .*@maps:\([0-9a-f]\{12\}\).*/\1/p' | head -1)
echo "Shop.Config_NewEdit: Config_NewEdit/dataView1/saveButton:* @maps:$CCH # control: opened the page, the page parameter is the object to save" > $T/cc-answer.txt
ctl convertcheck-mappings-answer-pass 0 '^ANSWERED Shop\.Config_NewEdit: .*saveButton.*answered: control: opened the page' ' 0 REVIEW, 1 ANSWERED, 2 INFO' '!^REVIEW' -- $CC --answer $T/cc-answer.txt
echo "Shop.Config_NewEdit: Config_NewEdit/dataView1/saveButton:* @maps:000000000000 # control: written for another mapping" > $T/cc-answer-other.txt
ctl convertcheck-mappings-answer-other-mapping-catch 1 '^REVIEW +Shop\.Config_NewEdit: .*answer pinned to another mapping @maps:000000000000' '!^ANSWERED' -- $CC --answer $T/cc-answer-other.txt
echo "Shop.Config_NewEdit: Config_NewEdit/dataView1/saveButton:* @maps:$CCH" > $T/cc-answer-noreason.txt
ctl convertcheck-mappings-answer-noreason-catch 2 "write '<Page>: <site> @maps:<hash> # what you checked'" -- $CC --answer $T/cc-answer-noreason.txt
echo "Shop.Config_NewEdit: Config_NewEdit/dataView1/saveButton:* # control: no pin" > $T/cc-answer-nopin.txt
ctl convertcheck-mappings-answer-nopin-catch 2 "write '<Page>: <site> @maps" -- $CC --answer $T/cc-answer-nopin.txt
echo "Shop.Nope: Nope/dataView9/b:* @maps:$CCH # control: a page that is not in the model" > $T/cc-answer-stale.txt
ctl convertcheck-mappings-answer-stale-catch 1 '^STALE +answer matches no call site, not used: Shop\.Nope' '^REVIEW +Shop\.Config_NewEdit' -- $CC --answer $T/cc-answer-stale.txt
# --- repair: CE1571 call mappings under a protected add-on flow, mxcli's silent no-op (T2-4, T2R3-7) ---------------------
# ce1571-app: a 10.x page whose data view calls VendorAddon.SUB_GetDefault (a modules/*.mxmodule, not in App.mpr) with an
# empty mapping; ce1571-ref: the publisher's page with the mapping; ce1571-differs: mapped by hand to something else
for v in ce1571-app ce1571-ref ce1571-differs; do model $v > /dev/null; done
CM=$B/repair/copy_mappings.py; AG=$B/repair/alter_guard.py
for d in ce1571-app ce1571-differs; do cp -R $M/$d $T/$d; mkdir -p $T/$d/modules; mkaddon $T/$d/modules/VendorAddon.mxmodule 10.24.26.123458; done
CA=$T/ce1571-app; CD=$T/ce1571-differs; CW=$T/ce1571-apply; cp -R $CA $CW
ctl copy-mappings-scan-catch 1 '^CANDIDATE Shop\.Config_NewEdit: Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault \(empty mapping; flow outside the model: VendorAddon is an add-on \(modules/VendorAddon\.mxmodule\)\)' '^CANDIDATE Shop\.Log_Page' '!saveButton' 'summary: 2 call site' -- python3 $CM $CA --scan
ctl copy-mappings-scan-own-flows-pass 0 '^summary: 0 call site' '!CANDIDATE' -- python3 $CM $M/maps-new --scan
ctl copy-mappings-scan-no-addon-file-catch 1 'module VendorAddon is not in app\.mpr' -- python3 $CM $M/ce1571-app --scan
ctl copy-mappings-dryrun-catch 1 '^COPY +Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault: \(none\) -> ActualConfig = \$Config \(flow outside the model' '^SAME +Config_NewEdit/dataView1/saveButton' 'dry run, nothing written' -- python3 $CM $CA --page Shop.Config_NewEdit --ref $M/ce1571-ref
ctl copy-mappings-dryrun-wrote-nothing 1 '^CANDIDATE Shop\.Config_NewEdit' -- python3 $CM $CA --scan
ctl copy-mappings-apply 0 '^written: 1 site\(s\) in Shop\.Config_NewEdit' -- python3 $CM $CW --page Shop.Config_NewEdit --ref $M/ce1571-ref --apply
ctl copy-mappings-apply-idempotent-pass 0 '^SAME +Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault: ActualConfig = \$Config' '!^COPY' 'summary: 0 to copy' -- python3 $CM $CW --page Shop.Config_NewEdit --ref $M/ce1571-ref
ctl copy-mappings-apply-scan-pass 1 '!CANDIDATE Shop\.Config_NewEdit' '^CANDIDATE Shop\.Log_Page' -- python3 $CM $CW --scan
ctl copy-mappings-apply-hash-pass 0 '^hash ok 1$' -- python3 -c "
import sqlite3, hashlib, base64; c = sqlite3.connect('$CW/App.mpr'); d = sqlite3.connect('$CA/App.mpr')
old = dict(d.execute('select UnitID, Contents from Unit')); n = 0
for u, h, b in c.execute('select UnitID, ContentsHash, Contents from Unit'):
    if old[u] != b: n += 1; assert h == base64.b64encode(hashlib.sha256(b).digest()).decode(), 'stale ContentsHash'
print('hash ok', n)"
ctl copy-mappings-differs-catch 1 '^DIFFERS +Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault: app ActualConfig = \$Other \| reference ActualConfig = \$Config; left alone' '!^COPY' -- python3 $CM $CD --page Shop.Config_NewEdit --ref $M/ce1571-ref
ctl copy-mappings-replace-pass 1 '^COPY +Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault: ActualConfig = \$Other -> ActualConfig = \$Config' -- python3 $CM $CD --page Shop.Config_NewEdit --ref $M/ce1571-ref --replace
ctl copy-mappings-noref-catch 1 '^NOREF +Log_Page/logButton:VendorAddon\.ACT_Log: empty, and the reference has no mapping either' 'own wrapper' -- python3 $CM $CA --page Shop.Log_Page --ref $M/ce1571-ref
ctl copy-mappings-addon-page-refused-catch 2 'REFUSED VendorAddon\.Some_Page: module VendorAddon is a protected add-on \(modules/VendorAddon\.mxmodule\)' -- python3 $CM $CA --page VendorAddon.Some_Page --ref $M/ce1571-ref
ctl copy-mappings-input-catch 2 'no page, snippet or layout of that name' -- python3 $CM $CA --page Shop.Nope --ref $M/ce1571-ref
ctl copy-mappings-widget-catch 2 'no call site under a widget named nosuch' -- python3 $CM $CA --page Shop.Config_NewEdit --ref $M/ce1571-ref --widget nosuch
# a unit that does not re-encode byte for byte (a duplicated key) is never edited
CU=$T/ce1571-unsafe; cp -R $CA $CU
python3 - $CU/App.mpr <<'PYEOF'
import sqlite3, struct, sys, bson
c = sqlite3.connect(sys.argv[1])
for u, b in c.execute("select UnitID, Contents from Unit").fetchall():
    if bson.decode(b).get("Name") == "Config_NewEdit":
        el = b"\x10Zz\x00" + struct.pack("<i", 1)
        body = b[4:-1] + el + el
        c.execute("update Unit set Contents=? where UnitID=?", (struct.pack("<i", len(body) + 5) + body + b"\x00", u))
c.commit()
PYEOF
ctl copy-mappings-unsafe-bson-catch 2 'does not re-encode byte for byte; not edited' -- python3 $CM $CU --page Shop.Config_NewEdit --ref $M/ce1571-ref --apply
# MPR v2 (Contents NULL, one mprcontents/**/<uuid>.mxunit per unit): the file is written, the Unit table keeps no Contents
C2=$T/ce1571-v2; cp -R $CA $C2
python3 - $C2/App.mpr <<'PYEOF'
import sqlite3, sys, os, uuid
p = sys.argv[1]; c = sqlite3.connect(p)
for u, b in c.execute("select UnitID, Contents from Unit").fetchall():
    s = str(uuid.UUID(bytes_le=bytes(u))); d = os.path.join(os.path.dirname(p), "mprcontents", s[:2], s[2:4]); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, s + ".mxunit"), "wb").write(b)
c.execute("alter table Unit drop column Contents"); c.commit()
PYEOF
ctl copy-mappings-v2-apply 0 '^written: 1 site' -- python3 $CM $C2 --page Shop.Config_NewEdit --ref $M/ce1571-ref --apply
ctl copy-mappings-v2-idempotent-pass 0 '^SAME +Config_NewEdit/dataView1:VendorAddon' '!^COPY' -- python3 $CM $C2 --page Shop.Config_NewEdit --ref $M/ce1571-ref
# alter_guard: the stubs stand in for mxcli printing "Altered page" (T2R3-7) without, or with, a saved change
printf 'alter page Shop.Config_NewEdit {\n  set DataSource = microflow VendorAddon.SUB_GetDefault(ActualConfig = $Config) on dataView1\n};\n' > $T/ce1571-fix.mdl
CL=$T/ce1571-lost; CG=$T/ce1571-guarded; cp -R $CA $CL; cp -R $CA $CG
ctl alter-guard-addon-page-refused-catch 2 '^REFUSED +VendorAddon\.Some_Page: module VendorAddon is a protected add-on' 'not run' '!^Altered page' -- python3 $AG $CA -- sh -c 'echo Altered page' _ "alter page VendorAddon.Some_Page { set Title = 'x' }"
ctl alter-guard-check-warn-catch 1 '^WARN +VendorAddon\.SUB_GetDefault\(\.\.\.\): flow outside the model: VendorAddon is an add-on' 'saves NO mapping' 'copy_mappings\.py .* --page Shop\.Config_NewEdit' 'not run' -- python3 $AG $CA --check -- mxcli exec -p $CA/App.mpr $T/ce1571-fix.mdl
ctl alter-guard-check-clean-pass 0 'summary: 1 target\(s\), 0 warning' '!WARN' -- python3 $AG $CA --check -- mxcli -p $CA/App.mpr -c "alter page Shop.Log_Page { set Title = 'x' }"
ctl alter-guard-noop-catch 1 '^Altered page' '^NO-OP +Shop\.Config_NewEdit: the command exited 0 but the unit is byte for byte unchanged' -- python3 $AG $CA -- sh -c 'echo Altered page' _ $T/ce1571-fix.mdl
ctl alter-guard-mapping-lost-catch 1 '^MAPPING NOT SAVED Shop\.Config_NewEdit: Config_NewEdit/dataView1:VendorAddon\.SUB_GetDefault still has an empty mapping' '!^OK' -- python3 $AG $CL -- python3 -c "
import sys, bson; sys.path.insert(0, '$B/repair'); from copy_mappings import Mpr
m = Mpr('$CL'); u = m.docs['Shop.Config_NewEdit']; d = m.decode(u); d['Documentation'] = 'altered'; m.write(u, bson.encode(d)); print('Altered page')" $T/ce1571-fix.mdl
# B4T2-2: the pattern read '^  OK' (two spaces slipped in with 4181978) and never matched alter_guard's column-0 verdict
ctl alter-guard-saved-pass 0 '^OK +Shop\.Config_NewEdit: changed' '!NO-OP' '!MAPPING NOT SAVED' -- python3 $AG $CG -- sh -c "python3 $CM $CG --page Shop.Config_NewEdit --ref $M/ce1571-ref --apply" _ $T/ce1571-fix.mdl
# FM-4: a write that changed the unit but left ContentsHash stale (mxcli ALTER PAGE of a nanoflow mapping) is HASH STALE
CH=$T/ce1571-hash; cp -R $CA $CH
python3 -c "
import sqlite3, hashlib, base64; c = sqlite3.connect('$CH/App.mpr')
for u, b in c.execute('select UnitID, Contents from Unit').fetchall(): c.execute('update Unit set ContentsHash=? where UnitID=?', (base64.b64encode(hashlib.sha256(b).digest()).decode(), u))
c.commit()"
ctl alter-guard-hash-stale-catch 1 '^HASH STALE +Shop\.Config_NewEdit: the unit changed but ContentsHash is' 'patch the unit instead' '!^OK' -- python3 $AG $CH -- python3 -c "
import sys, bson; sys.path.insert(0, '$B/repair'); from copy_mappings import Mpr
m = Mpr('$CH'); u = m.docs['Shop.Config_NewEdit']; d = m.decode(u); d['Documentation'] = 'altered'
m.con.execute('update Unit set Contents=? where UnitID=?', (bson.encode(d), u)); m.con.commit(); print('Altered page')" $T/ce1571-fix.mdl
CH2=$T/ce1571-hash2; cp -R $CH $CH2; python3 -c "
import sqlite3, hashlib, base64; c = sqlite3.connect('$CH2/App.mpr')
for u, b in c.execute('select UnitID, Contents from Unit').fetchall(): c.execute('update Unit set ContentsHash=? where UnitID=?', (base64.b64encode(hashlib.sha256(b).digest()).decode(), u))
c.commit()"
ctl alter-guard-hash-valid-pass 0 '^OK +Shop\.Config_NewEdit: changed' '!HASH STALE' -- python3 $AG $CH2 -- sh -c "python3 $CM $CH2 --page Shop.Config_NewEdit --ref $M/ce1571-ref --apply" _ $T/ce1571-fix.mdl
ctl alter-guard-tool-error-catch 3 'TOOL ERROR the command exited 4' -- python3 $AG $CA -- sh -c 'exit 4' _ $T/ce1571-fix.mdl
ctl alter-guard-invalid-catch 2 '^INVALID +Shop\.Nope: no page or snippet' -- python3 $AG $CA -- sh -c true _ "alter page Shop.Nope { }"
ctl alter-guard-no-target-catch 2 '^INVALID +no `alter page' -- python3 $AG $CA -- mxcli -p $CA/App.mpr -c "show pages"

# --- repair: CE6911 cache-bust tags in theme/web/*.html, also the dojoConfig cacheBust CE6911 misses (T8R-5, T8R2 R-4, G-5)
# the fixture holds the dojoConfig block of the T8R2 gate patch verbatim and the 9.x query-string shape of REPAIR R-4
CB=$T/cachebust; mkdir -p $CB/theme/web; touch $CB/App.mpr; cp $FX/cachebust/index-9x.html $CB/theme/web/index.html
ctl cachebust-check-catch 1 'WOULD FIX theme/web/index\.html:17: cacheBust: "637643641483639052"' 'WOULD FIX theme/web/index\.html:21: .*mxui\.js\?637643641483639052' 'summary: 4 hard-coded' '!example\.com' -- python3 $B/repair/cachebust.py $CB
ctl cachebust-dryrun-wrote-nothing 0 -- grep -q 'cacheBust: "637643641483639052"' $CB/theme/web/index.html
ctl cachebust-apply 0 '^FIXED theme/web/index\.html:6' 'summary: 4 hard-coded' -- python3 $B/repair/cachebust.py $CB --apply
ctl cachebust-rewritten 0 -- sh -c "grep -q 'cacheBust: \"{{cachebust}}\"' $CB/theme/web/index.html && grep -q 'mxui.js?{{cachebust}}\"' $CB/theme/web/index.html && ! grep -q 637643641483639052 $CB/theme/web/index.html"
ctl cachebust-idempotent-pass 0 'summary: 0 hard-coded' '!WOULD FIX' -- python3 $B/repair/cachebust.py $CB
ctl cachebust-other-query-untouched 0 -- grep -q 'https://example.com/?id=1' $CB/theme/web/index.html
mkdir -p $T/cachebust-none; touch $T/cachebust-none/App.mpr
ctl cachebust-no-theme-pass 0 "built-in index\.html" -- python3 $B/repair/cachebust.py $T/cachebust-none
ctl cachebust-input-catch 2 'no \.mpr' -- python3 $B/repair/cachebust.py $T/empty-nothing
ctl mxversion-none-catch 2 -- python3 $B/mxversion.py $T/jars
# E7-10: the CDN runtime layout runtime-<ver>/<full ver>/runtime
R=$T/tools/runtime-9.24.32; mkdir -p $R/9.24.32.58223/runtime/launcher
python3 -c "import zipfile; z=zipfile.ZipFile('$R/9.24.32.58223/runtime/launcher/runtimelauncher.jar','w'); z.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nImplementation-Version: 9.24.32.58223\n'); z.close()"
ctl mxversion-cdn-runtime-pass 0 '^9\.24\.32\.58223$' -- python3 $B/mxversion.py $R
mkdir -p $T/tools/runtime-two; cp -R $R/9.24.32.58223 $T/tools/runtime-two/; cp -R $V $T/tools/runtime-two/10.24.16.96987
ctl mxversion-cdn-several-catch 2 'several runtimes' -- python3 $B/mxversion.py $T/tools/runtime-two
: > $T/tools/mxcli-linux
ctl mxcli-container-mismatch-catch 2 'is 9\.24\.32\.58223, mounted toolsets: 10\.24\.16\.96987' -- env UPG_ROOT=$T UPG_TOOLS=$T/tools zsh $B/mxcli-container.sh check -p $M/v9/App.mpr
# tools/ made of symlinks into a shared folder: the binary is mounted by its resolved path (E4-2)
mkdir -p $T/shared $T/linked; : > $T/shared/mxcli-real; ln -sf $T/shared/mxcli-real $T/linked/mxcli-linux; ln -sf $T/shared/gone $T/linked/mxcli-dangling
ctl mxcli-container-symlink-pass 0 '/shared/mxcli-real:/opt/upg/mxcli:ro' ' /opt/upg/mxcli version$' -- env UPG_DRYRUN=1 UPG_ROOT=$T UPG_TOOLS=$T/linked zsh $B/mxcli-container.sh version
# R38: a credential held only in MENDIX_PAT reaches the container by name (-e MENDIX_PAT), its value never on the command line
ctl mxcli-container-pat-env-pass 0 ' -e MENDIX_PAT ' '!ctl-dummy-pat' -- env UPG_DRYRUN=1 UPG_ROOT=$T UPG_TOOLS=$T/linked MENDIX_PAT=ctl-dummy-pat zsh $B/mxcli-container.sh version
ctl mxcli-container-no-pat-catch 0 '!MENDIX_PAT' ' /opt/upg/mxcli version$' -- env -u MENDIX_PAT UPG_DRYRUN=1 UPG_ROOT=$T UPG_TOOLS=$T/linked zsh $B/mxcli-container.sh version
ctl mxcli-container-dangling-catch 2 'is a dangling symlink' -- env UPG_ROOT=$T UPG_TOOLS=$T/linked UPG_MXCLI=$T/linked/mxcli-dangling zsh $B/mxcli-container.sh version
# batch 1 (T1-12, T3-7, T4-2, T6-6, T8-11): behind an egress proxy the container gets the proxy, its CA and, for a proxy on
# 127.0.0.1, the host network; without a proxy nothing is added. UPG_ENV_FILE carries values with spaces (T2-9, T5-13).
echo 'dummy CA' > $T/ca.crt; printf 'JAVA_TOOL_OPTIONS=-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=3128\n' > $T/env.list
NOPX="env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u NO_PROXY -u no_proxy -u SSL_CERT_FILE -u UPG_CA -u UPG_EXTRA -u UPG_ENV_FILE -u UPG_TOOLS -u UPG_NAME -u JAVA_TOOL_OPTIONS UPG_DRYRUN=1 UPG_ROOT=$T"
ctl mxrun-proxy-dryrun-pass 0 '-e HTTPS_PROXY=http://127\.0\.0\.1:3128 -e https_proxy=http://127\.0\.0\.1:3128' '-e NO_PROXY=localhost' '--network host' "-v $T/ca\.crt:/etc/upg/ca\.crt:ro -e SSL_CERT_FILE=/etc/upg/ca\.crt" -- $NOPX HTTPS_PROXY=http://127.0.0.1:3128 NO_PROXY=localhost UPG_CA=$T/ca.crt zsh $B/mxrun.sh img cmd
ctl mxrun-proxy-sslcertfile-pass 0 "-v $T/ca\.crt:/etc/upg/ca\.crt:ro" '--network host' -- $NOPX https_proxy=http://user:pw@localhost:8080 SSL_CERT_FILE=$T/ca.crt zsh $B/mxrun.sh img cmd
ctl mxrun-noproxy-pass 0 'docker run .* img cmd$' '!HTTPS_PROXY' '!--network' '!/etc/upg/ca\.crt' -- $NOPX zsh $B/mxrun.sh img cmd
ctl mxrun-remote-proxy-pass 0 '-e HTTPS_PROXY=http://proxy\.example:8080' '!--network host' -- $NOPX HTTPS_PROXY=http://proxy.example:8080 zsh $B/mxrun.sh img cmd
ctl controls-hermetic-env-pass 0 '^ok +mxrun-noproxy-pass$' ', 0 failed' -- env UPG_EXTRA='--network host -e HTTPS_PROXY=http://proxy.example:8080' UPG_UPDATE_CMD=false bash $here/run-controls.sh --fast --only '^mxrun-noproxy-pass$'
# B4N1-2: the environment of a cloud run (proxy, upg-env.sh's UPG_EXTRA, JAVA_TOOL_OPTIONS) does not reach the controls
HOSTILE="env HTTPS_PROXY=http://127.0.0.1:3128 https_proxy=http://127.0.0.1:3128 JAVA_TOOL_OPTIONS=-Dhttps.proxyHost=127.0.0.1 UPG_ENV_FILE=$T/env.list"
ctl mxrun-hostile-env-catch 0 '--network host' '-e HTTPS_PROXY=http://127\.0\.0\.1:3128' '--env-file' -- $HOSTILE UPG_DRYRUN=1 UPG_ROOT=$T zsh $B/mxrun.sh img cmd
ctl mxrun-hostile-env-noproxy-pass 0 'docker run .* img cmd$' '!HTTPS_PROXY' '!--network' '!--env-file' -- $HOSTILE UPG_EXTRA="--network host -e HTTPS_PROXY=http://127.0.0.1:3128" $NOPX zsh $B/mxrun.sh img cmd
ctl mxrun-network-given-pass 0 '--network bridge' '!--network host' -- $NOPX HTTPS_PROXY=http://127.0.0.1:3128 UPG_EXTRA="--network bridge" zsh $B/mxrun.sh img cmd
ctl mxrun-ca-missing-catch 2 'UPG_CA=/nonexistent/ca\.crt is not a file' -- $NOPX UPG_CA=/nonexistent/ca.crt zsh $B/mxrun.sh img cmd
ctl mxrun-env-file-pass 0 "--env-file $T/env\.list" -- $NOPX UPG_ENV_FILE=$T/env.list zsh $B/mxrun.sh img cmd
ctl mxrun-env-file-missing-catch 2 'UPG_ENV_FILE=/nonexistent/env is not a file' -- $NOPX UPG_ENV_FILE=/nonexistent/env zsh $B/mxrun.sh img cmd
# T7-13: a HOME set for the container moves mxcli's config; the credential and toolsets follow it
mkdir -p $T/home/.mxcli; echo '{}' > $T/home/.mxcli/auth.json
ctl mxcli-container-home-pass 0 ':/tmp/\.mxcli/auth\.json:ro' ':/tmp/\.mxcli/mxbuild/10\.24\.16\.96987:ro' '!:/root/\.mxcli/' -- $NOPX HOME=$T/home UPG_TOOLS=$T/tools UPG_EXTRA="-e HOME=/tmp" zsh $B/mxcli-container.sh version
ctl mxcli-container-home-envfile-pass 0 ':/work/h/\.mxcli/auth\.json:ro' -- sh -c "printf 'HOME=/work/h\n' > $T/home.env; $NOPX HOME=$T/home UPG_TOOLS=$T/tools UPG_ENV_FILE=$T/home.env zsh $B/mxcli-container.sh version"
ctl mxcli-container-home-default-pass 0 ':/root/\.mxcli/auth\.json:ro' ':/root/\.mxcli/mxbuild/10\.24\.16\.96987:ro' -- $NOPX HOME=$T/home UPG_TOOLS=$T/tools zsh $B/mxcli-container.sh version
# T6R-11: `-p App.mpr` from the app folder is resolved against the caller's folder (it was resolved against /w in the
# container: "mpr file not found"), and a project outside UPG_ROOT is refused with the rule
mkdir -p $T/relp; cp $M/base/App.mpr $T/relp/App.mpr
ctl mxcli-container-relative-p-pass 0 ' -p /.*/relp/App\.mpr$' '!-p App\.mpr' -- sh -c "cd $T/relp && $NOPX UPG_TOOLS=$T/tools zsh $B/mxcli-container.sh check -p App.mpr"
ctl mxcli-container-relative-p-version-catch 2 'relp/App\.mpr is 10\.24\.16\.96987, mounted toolsets: none' -- sh -c "cd $T/relp && $NOPX UPG_TOOLS=$T/relp UPG_MXCLI=$T/tools/mxcli-linux zsh $B/mxcli-container.sh check -p App.mpr"
ctl mxcli-container-outside-root-catch 2 'is not under UPG_ROOT=.*only UPG_ROOT is mounted' -- sh -c "cd $T/relp && $NOPX UPG_ROOT=$T/relp/sub UPG_TOOLS=$T/tools zsh $B/mxcli-container.sh check -p App.mpr"
ctl mxcli-container-relative-missing-catch 2 'Nope\.mpr not found on the host \(a relative -p is resolved against the current folder' -- sh -c "cd $T/relp && $NOPX UPG_TOOLS=$T/tools zsh $B/mxcli-container.sh check -p Nope.mpr"

# --- stepupdate: per-step idcheck, stop on the first finding (E1 0b, E1 15, E1 25) ------------------------------------------
S=$T/step; mkdir -p $S/app; cp $M/base/App.mpr $S/app/App.mpr
for v in step1-adds guid-changed; do mkdir -p $S/$v; cp $M/$v/App.mpr $S/$v/; done
(cd $S/app && git init -q && git add App.mpr && git -c user.email=c@c -c user.name=ctl commit -qm base)
printf '120743 1.6.0 step1-adds\n120743 1.7.0 guid-changed\n' > $S/plan.txt
export UPG_UPDATE_CMD="cp $S/{module}/App.mpr {mpr}"
ctl stepupdate-catch 1 'committed' 'STOP: new data-bearing finding after guid-changed' -- bash $B/stepupdate.sh $S/app $S/plan.txt
# NR2-22: a step whose package entries carry Windows separators (OQL 4.2.0 / 5.1.0) leaves `javasource\oql\A.java` in the app root.
# The batch moves it home before the commit (idcheck, mx check and the build were all green with the stubs); a different file
# already at the target is a STOP.
S3=$T/step-bs; mkdir -p $S3/app; cp $M/base/App.mpr $S3/app/App.mpr; cp $S/plan.txt $S3/plan.txt; sed -i.bak '2d' $S3/plan.txt
(cd $S3/app && git init -q && git add App.mpr && git -c user.email=c@c -c user.name=ctl commit -qm base)
printf '#!/bin/sh\ncp "$1/App.mpr" "$2" && printf x > "$(dirname "$2")/javasource\\oql\\A.java"\n' > $S3/upd.sh
ctl stepupdate-backslash-moved-catch 0 'BACKSLASH: 1 file\(s\) of step1-adds were written with Windows separators' 'committed' -- env UPG_UPDATE_CMD="sh $S3/upd.sh $S/{module} {mpr}" bash $B/stepupdate.sh $S3/app $S3/plan.txt
ctl stepupdate-backslash-tree-pass 0 '^javasource/oql/A\.java$' '^root files with a backslash: 0$' -- sh -c "cd $S3/app && git ls-files | grep -F oql; echo root files with a backslash: \$(ls | grep -cF '\\')"
# NR2-7: the same batch on an MPR v2 app (units in mprcontents/): the previous step is snapshotted WITH its mprcontents/
# (it was `git show HEAD:App.mpr`, a .mpr with no units: "idcheck: INVALID, no entities read from one side", STOP on step 1)
S2=$T/step-v2; mkdir -p $S2/app
for v in base step1-adds guid-changed; do python3 $here/lib/mkv2.py $M/$v $S2/$v; done
cp -R $S2/base/. $S2/app/; cp $S/plan.txt $S2/plan.txt
(cd $S2/app && git init -q && git add -A && git -c user.email=c@c -c user.name=ctl commit -qm base)
ctl stepupdate-mpr-v2-catch 1 'committed' 'STOP: new data-bearing finding after guid-changed' '!idcheck input error' '!no entities read' -- env UPG_UPDATE_CMD="cp $S2/{module}/App.mpr {mpr} && rm -rf $S2/app/mprcontents && cp -R $S2/{module}/mprcontents $S2/app/mprcontents" bash $B/stepupdate.sh $S2/app $S2/plan.txt
ctl stepupdate-catch-nothing-committed 0 'step: step1-adds' '!step: guid-changed' -- git -C $S/app log --format=%s
# T4-mpr, T8-10: an app path with a space is one word for the update command (was split: every module refused)
for d in "my app" "my app2"; do mkdir -p "$T/$d"; cp $M/base/App.mpr "$T/$d/App.mpr"
  (cd "$T/$d" && git init -q && git add App.mpr && git -c user.email=c@c -c user.name=ctl commit -qm base); done
SP="$T/my app"
printf '120743 1.6.0 step1-adds\n' > $S/plan-sp.txt
ctl stepupdate-space-split-catch 0 'committed' '!No such file' -- bash $B/stepupdate.sh "$SP" $S/plan-sp.txt
ctl stepupdate-space-quoted-pass 0 'committed' '!No such file' -- env UPG_UPDATE_CMD="cp $S/{module}/App.mpr '{mpr}'" bash $B/stepupdate.sh "$T/my app2" $S/plan-sp.txt
unset UPG_UPDATE_CMD

# --- stepupdate: recognised refusals, --no-baseline fallback, resume and keep (E4 13, E4 16, E4 7, E5b 26, E5b 27, E5b 17) -
# fake-update.sh prints the real mxcli messages from E4 / E5b; the module name picks the behaviour.
newapp() {  # newapp NAME 'plan lines': fresh git app under $S/NAME with an untracked file that must survive a revert
  rm -rf $S/$1; mkdir -p $S/$1; cp $M/base/App.mpr $S/$1/App.mpr; echo keep > $S/$1/notes-untracked.txt
  (cd $S/$1 && git init -q && git add App.mpr && git -c user.email=c@c -c user.name=ctl commit -qm base)
  printf "$2" > $S/$1.plan
}
export UPG_UPDATE_CMD="bash $FX/bin/fake-update.sh $S {module} {mpr}"
export GIT_AUTHOR_NAME=ctl GIT_AUTHOR_EMAIL=c@c GIT_COMMITTER_NAME=ctl GIT_COMMITTER_EMAIL=c@c
newapp ui '1 1.0 UiEdit\n'
ctl stepupdate-ui-edits-catch 2 'local UI edits only \(LAYOUT PAGE' 'rerun with --force-ui UiEdit' 'STOP: update of UiEdit refused for local edits' -- bash $B/stepupdate.sh $S/ui $S/ui.plan
ctl stepupdate-gitignore-claude-pass 0 '^\.claude/$' '^\.stepupdate/$' -- cat $S/ui/.gitignore
newapp ui2 '1 1.0 UiEdit\n'
ctl stepupdate-force-ui-pass 0 'saved edits for replay: .*/UiEdit \(1 files\)' 'committed' ' 0 kept, 0 network$' -- bash $B/stepupdate.sh $S/ui2 $S/ui2.plan --force-ui UiEdit
# B2-JAR: the step that finishes the module updates cleans the jars itself and commits them as a neutral "jar:" commit
newapp jc '1 1.0 Fine\n'
mkdir -p $S/jc/userlib $S/jc/vendorlib; : > $S/jc/userlib/pdfbox-2.0.30.jar; : > $S/jc/vendorlib/pdfbox-3.0.7.jar
(cd $S/jc && git add userlib vendorlib && git commit -qm "base jars")
ctl jarclean-stepupdate-wired 0 'jar cleanup \(jardedupe --apply\)' 'REMOVE +userlib/pdfbox-2\.0\.30\.jar' -- env UPG_VENDORLIB_SYNCED=1 bash $B/stepupdate.sh $S/jc $S/jc.plan
ctl jarclean-stepupdate-commit 0 'jar: jardedupe --apply' -- git -C $S/jc log --format=%s
ctl jarclean-stepupdate-log 0 'REMOVE +userlib/pdfbox-2\.0\.30\.jar' 'vendorlib current: stated with --vendorlib-synced' -- cat $S/jc/.stepupdate/jardedupe.log
# T5-16: no sync after the module update: stepupdate must not delete userlib jars against the old vendorlib
newapp jc2 '1 1.0 Fine\n'
mkdir -p $S/jc2/userlib $S/jc2/vendorlib; : > $S/jc2/userlib/pdfbox-2.0.30.jar; : > $S/jc2/vendorlib/pdfbox-3.0.7.jar
(cd $S/jc2 && git add userlib vendorlib && git commit -qm "base jars")
ctl jarclean-stepupdate-stale-refused 0 'jar cleanup REFUSED, vendorlib is stale \(nothing removed\)' '!jar cleanup \(jardedupe --apply\)' -- bash $B/stepupdate.sh $S/jc2 $S/jc2.plan
ctl jarclean-stepupdate-stale-keeps 0 -- bash -c "[ -f $S/jc2/userlib/pdfbox-2.0.30.jar ]"
# B4T2-10: CommunityCommons was committed by an EARLIER pass; this pass updates another module. stepupdate's jardedupe
# call reads the "step:" commits, so the old-major jar its leftover marker names goes; without that commit it stays CONFLICT.
for k in jc3 jc4; do
  newapp $k '1 1.0 Fine\n'
  mkdir -p $S/$k/userlib $S/$k/vendorlib $S/$k/javasource/keptmod; : > $S/$k/javasource/keptmod/.keep
  : > $S/$k/userlib/pdfbox-2.0.30.jar; : > $S/$k/userlib/pdfbox-2.0.30.jar.KeptMod.RequiredLib; : > $S/$k/vendorlib/pdfbox-3.0.7.jar
done
(cd $S/jc3 && git add userlib vendorlib javasource && git commit -qm "step: KeptMod 2.0.0 (stepupdate, idcheck PASS)")
(cd $S/jc4 && git add userlib vendorlib javasource && git commit -qm "base jars")
ctl jarclean-stepupdate-earlier-pass-removed 0 'jar cleanup \(jardedupe --apply\)' 'REMOVE +userlib/pdfbox-2\.0\.30\.jar .*KeptMod was updated' -- env UPG_VENDORLIB_SYNCED=1 bash $B/stepupdate.sh $S/jc3 $S/jc3.plan
ctl jarclean-stepupdate-earlier-pass-result 0 -- bash -c "[ ! -f $S/jc3/userlib/pdfbox-2.0.30.jar ] && [ -f $S/jc3/vendorlib/pdfbox-3.0.7.jar ]"
ctl jarclean-stepupdate-no-step-commit-kept 0 '!REMOVE +userlib/pdfbox' -- bash -c "env UPG_VENDORLIB_SYNCED=1 bash $B/stepupdate.sh $S/jc4 $S/jc4.plan; grep -E 'KEEP +userlib/pdfbox-2\.0\.30\.jar +CONFLICT' $S/jc4/.stepupdate/jardedupe.log && [ -f $S/jc4/userlib/pdfbox-2.0.30.jar ]"
ctl jarclean-stepupdate-stale-names-jars 0 "jars marked 'rests on vendorlib' in .*jardedupe\.log" -- bash $B/stepupdate.sh $S/jc2 $S/jc2.plan --from 1
# NS-6: the Email Connector import swapped shared widgets (notification-service cdd62cc5: Datagrid 2.28.3 -> 2.30.6)
python3 $here/lib/mkwidgetmpk.py $S/widgets-new/com.mendix.widget.web.Datagrid.mpk Datagrid 2.30.6
for k in wg wgok; do newapp $k "1 1.0 $([ $k = wg ] && echo Widg || echo Fine)\n"
  python3 $here/lib/mkwidgetmpk.py $S/$k/widgets/com.mendix.widget.web.Datagrid.mpk Datagrid 2.28.3
  python3 $here/lib/mkwidgetmpk.py $S/$k/widgets/Badge.mpk Badge 3.0.0; (cd $S/$k && git add widgets && git commit -qm "base widgets"); done
ctl stepupdate-widgets-changed-catch 0 'WIDGETS: the Widg update changed 1 widget package\(s\)' '^ +widgets/com\.mendix\.widget\.web\.Datagrid\.mpk Datagrid 2\.28\.3 -> 2\.30\.6$' '^ +WIDGETS: Widg 1\.0: com\.mendix\.widget\.web\.Datagrid\.mpk Datagrid 2\.28\.3 -> 2\.30\.6$' '!Badge' 'committed' -- bash $B/stepupdate.sh $S/wg $S/wg.plan
ctl stepupdate-widgets-ledger-pass 0 '^Widg 1\.0: com\.mendix\.widget\.web\.Datagrid\.mpk Datagrid 2\.28\.3 -> 2\.30\.6$' -- cat $S/wg/.stepupdate/widgets.txt
ctl stepupdate-widgets-unchanged-pass 0 'committed' '!WIDGETS' -- bash $B/stepupdate.sh $S/wgok $S/wgok.plan
ctl widgetdiff-bad-rev-catch 2 'not a commit' -- python3 $B/widgetdiff.py $S/wg --rev no-such-rev
# NS-7: an update that deletes and re-imports a module (cc318c0b, DataWidgets 2.27.6): every unit id of it is new
mkdir -p $S/recreate; cp $M/base/App.mpr $S/recreate/App.mpr; python3 $here/lib/reid_module.py $S/recreate/App.mpr Administration > /dev/null
ctl idcheck-module-recreated-catch 0 '^warn MODULE_RECREATED Administration: all 5 unit ids new \(5 units now\)' '^verdict: PASS' -- python3 $B/idcheck.py $M/base/App.mpr $S/recreate/App.mpr
ctl idcheck-module-updated-pass 0 '!MODULE_RECREATED' -- python3 $B/idcheck.py $M/base/App.mpr $M/step1-adds/App.mpr
ctl idcheck-module-recreated-json-pass 0 '"module": "Administration"' -- sh -c "python3 $B/idcheck.py $M/base/App.mpr $S/recreate/App.mpr --json $T/recreate.json > /dev/null && cat $T/recreate.json"
newapp rc '1 1.0 Recreate\n'
ctl stepupdate-module-recreated-catch 0 '^ +warn MODULE_RECREATED Administration' 'committed' -- bash $B/stepupdate.sh $S/rc $S/rc.plan
# NS-10/NS-13: notification-service 3fbf1566 is the 11.12.4 convert (model units, Badge.mpk and 22 more without their
# appstore.id entry, widgets-appstore-metadata.json, regenerated JSDoc) squashed together with toolkit files
for k in cn cnok cnw; do rm -rf $S/$k; mkdir -p $S/$k/mprcontents/0a $S/$k/javascriptsource/nanoflowcommons/actions
  (cd $S/$k && git init -q && echo v1 > App.mpr && echo u1 > mprcontents/0a/unit.mxunit && echo old > javascriptsource/nanoflowcommons/actions/Geocode.js)
  python3 $here/lib/mkwidgetmpk.py $S/$k/widgets/Badge.mpk Badge 3.2.0 5f1a2b3c-badge-appstore-id
  (cd $S/$k && git add -A && git -c user.email=c@c -c user.name=ctl commit -qm "original 10.24.8")
  (cd $S/$k && echo v2 > App.mpr && echo u2 > mprcontents/0a/unit.mxunit && echo new > javascriptsource/nanoflowcommons/actions/Geocode.js && echo '{"schemaVersion": "1.0"}' > widgets/widgets-appstore-metadata.json)
  python3 $here/lib/mkwidgetmpk.py $S/$k/widgets/Badge.mpk Badge $([ $k = cnw ] && echo 3.3.0 || echo 3.2.0)
  [ $k = cn ] && mkdir -p $S/cn/.ai-context/skills && echo x > $S/cn/.ai-context/skills/SKILL.md && echo x > $S/cn/CLAUDE.md
  (cd $S/$k && git add -A && git -c user.email=c@c -c user.name=ctl commit -qm "convert to 11.12.4"); done
ctl convertnoise-foreign-catch 1 '7 changed paths: 2 model, 2 noise, 1 regenerated, 0 WIDGET, 2 FOREIGN' 'FOREIGN \.ai-context/ \(1 path\)' 'FOREIGN CLAUDE\.md' 'verdict: REVIEW' '!WIDGET  ' -- python3 $B/convertnoise.py $S/cn
ctl convertnoise-noise-only-pass 0 '2 model, 2 noise, 1 regenerated, 0 WIDGET, 0 FOREIGN' 'verdict: PASS' -- python3 $B/convertnoise.py $S/cnok
ctl convertnoise-widget-step-catch 1 'WIDGET  widgets/Badge\.mpk: contents changed' 'verdict: REVIEW' -- python3 $B/convertnoise.py $S/cnw
# MC-2, MC-3: convertpre.py refuses uncommitted build output and warns about a model commit after the last step commit
G="git -c user.email=c@c -c user.name=ctl"
for k in cpdirty cpok cpmodel; do rm -rf $S/$k; mkdir -p $S/$k/mprcontents/0a $S/$k/javasource/m/proxies; (cd $S/$k && git init -q && echo v1 > App.mpr && echo u1 > mprcontents/0a/unit.mxunit
  git add -A && $G commit -qm "original 10.12" && echo v2 > App.mpr && $G commit -qam "step: Atlas_Core 3.12.6"); done
(cd $S/cpdirty && echo gen > javasource/m/proxies/P.java && echo x >> App.mpr)
(cd $S/cpmodel && echo v3 > App.mpr && $G commit -qam "repair: map roles" && echo doc > NOTES.md && git add -A && $G commit -qm "docs: notes")
ctl convertpre-dirty-catch 1 '^REFUSE: 2 uncommitted path\(s\)' 'javasource/ \(1 path\)' 'App\.mpr \(1 path\)' 'convertpre: REFUSED' -- python3 $B/convertpre.py $S/cpdirty
ctl convertpre-clean-pass 0 'convertpre: ready; 0 uncommitted, 0 model-changing' '!WARN' '!REFUSE' -- python3 $B/convertpre.py $S/cpok
ctl convertpre-model-commit-warn 0 'WARN: model-changing commit\(s\) after the last unedited state \([0-9a-f]+ step: Atlas_Core' '[0-9a-f]{7} repair: map roles' 'convertpre: ready; 0 uncommitted, 1 model-changing' '!docs: notes' -- python3 $B/convertpre.py $S/cpmodel
ctl convertpre-no-git-invalid 2 'not a git repository' -- python3 $B/convertpre.py $T
# MC-19: widgetcover.py lists a used widget package that no smoke step or journey page renders (Viewer on Shop.Viewer_Panel; the
# smoke fixture walks Home_Overview, Orders_Overview, Inbox_Overview only; Spare is used only on an excluded page: not a gap)
WC="python3 $B/widgetcover.py"
mkdir -p $T/wcj; echo '{"steps": [{"open": "Shop.Viewer_Panel"}]}' > $T/wcj/viewer.journey.json; printf 'Shop.Viewer_Panel\n' > $T/wc-rendered.txt
printf 'Viewer.mpk # licensed viewer, walked by hand in the TC journey\n' > $T/wc-waive.txt; printf 'Viewer.mpk\n' > $T/wc-waive-bad.txt
ctl widgetcover-unrendered-catch 3 'widgetcover: 3 widget package\(s\) in .*, 2 used on a page, 3 page/snippet/layout documents rendered' '^UNRENDERED widgets/Viewer\.mpk 4\.0\.0 \(Viewer\.widget\.Viewer\): used on 1 page\(s\) \(e\.g\. Shop\.Viewer_Panel\)' 'verdict: UNRENDERED \(1 of 2 used' '!Markdown' '!Spare' -- $WC $M/widgetcover --smoke $FX/smoke/new-pass.json
ctl widgetcover-journey-pass 0 'verdict: PASS' '!UNRENDERED' -- $WC $M/widgetcover --smoke $FX/smoke/new-pass.json --journeys $T/wcj
ctl widgetcover-rendered-file-pass 0 'verdict: PASS' -- $WC $M/widgetcover --smoke $FX/smoke/new-pass.json --rendered $T/wc-rendered.txt
ctl widgetcover-waived-pass 0 '^WAIVED widgets/Viewer\.mpk \(licensed viewer' 'verdict: PASS\* 1 waived of 2 used package\(s\) .*Viewer\.mpk: licensed viewer' '!UNRENDERED' '!verdict: PASS \(' -- $WC $M/widgetcover --smoke $FX/smoke/new-pass.json --waive $T/wc-waive.txt
ctl widgetcover-waive-no-reason-invalid 2 'has no reason after' -- $WC $M/widgetcover --smoke $FX/smoke/new-pass.json --waive $T/wc-waive-bad.txt
# a step that FAILed renders nothing, but Home_Overview PASSed for the other role (2 documents rendered, not 3)
ctl widgetcover-failed-step-catch 3 '2 page/snippet/layout documents rendered' 'UNRENDERED widgets/Viewer\.mpk' -- $WC $M/widgetcover --smoke $FX/smoke/new-fail-other.json
ctl widgetcover-no-walk-invalid 2 'give at least one of' -- $WC $M/widgetcover
# NMR-3: an unreadable .mpk (an LFS pointer) or no package at all for widgets the pages use could not be measured: exit 2 INVALID,
# never PASS. A model whose pages use no custom widget has nothing to measure and stays PASS.
rm -rf $T/wcbad $T/wcnone; cp -r $M/widgetcover $T/wcbad; cp -r $M/widgetcover $T/wcnone
echo 'version https://git-lfs.github.com/spec/v1' > $T/wcbad/widgets/Viewer.mpk; rm -rf $T/wcnone/widgets
ctl widgetcover-unreadable-mpk-invalid 2 '1 package\(s\) not readable as a zip' '^UNREADABLE widgets/Viewer\.mpk' 'verdict: INVALID \(could not measure' '!verdict: PASS' -- $WC $T/wcbad --smoke $FX/smoke/new-pass.json
ctl widgetcover-no-widgets-folder-invalid 2 '^NO PACKAGES: .*does not exist, but pages use' 'verdict: INVALID' '!verdict: PASS' -- $WC $T/wcnone --smoke $FX/smoke/new-pass.json
ctl widgetcover-no-widgets-used-pass 0 'widgetcover: 0 widget package\(s\)' 'verdict: PASS' -- $WC $M/nav --smoke $FX/smoke/new-pass.json
# MC-4: mx convert's own regenerated theme cache and exclusion-variable file are regenerated, not FOREIGN
rm -rf $S/cnt; mkdir -p $S/cnt/theme-cache/web $S/cnt/themesource/atlas_core/web; (cd $S/cnt && git init -q && echo v1 > App.mpr && echo a > theme-cache/web/a.css && echo a > themesource/atlas_core/web/_generated-exclusion-variables.scss && echo a > themesource/atlas_core/web/_custom.scss
  git add -A && git -c user.email=c@c -c user.name=ctl commit -qm "original 10.12" && echo v2 > App.mpr && echo b > theme-cache/web/a.css && echo b > theme-cache/web/new.css && echo b > themesource/atlas_core/web/_generated-exclusion-variables.scss
  git add -A && git -c user.email=c@c -c user.name=ctl commit -qm "convert to 10.24.27")
ctl convertnoise-theme-generated-pass 0 '4 changed paths: 1 model, 0 noise, 3 regenerated, 0 WIDGET, 0 FOREIGN' 'verdict: PASS' -- python3 $B/convertnoise.py $S/cnt
(cd $S/cnt && echo c > themesource/atlas_core/web/_custom.scss && git add -A && git -c user.email=c@c -c user.name=ctl commit -qm "convert 2")
ctl convertnoise-theme-own-scss-catch 1 'FOREIGN themesource/ \(1 path\)' 'verdict: REVIEW' -- python3 $B/convertnoise.py $S/cnt
ctl convertnoise-root-commit-catch 2 'no parent' -- python3 $B/convertnoise.py $S/cnok --rev HEAD~1
newapp logic '1 1.0 LogicEdit\n'
ctl stepupdate-logic-edits-catch 2 'local LOGIC edits \(MICROFLOW RULE' '!rerun with --force-ui' -- bash $B/stepupdate.sh $S/logic $S/logic.plan
newapp nb '1 1.0 OldBase\n2 1.0 Gone\n'
ctl stepupdate-no-baseline-pass 0 'OldBase cannot serve as the local-edit baseline \(range from 9.18.0' 'WARNING: local edits in OldBase are unproven' 'Gone cannot serve .*expected redirect' 'no-baseline \(local edits unproven\): Gone' -- bash $B/stepupdate.sh $S/nb $S/nb.plan
# N1-5: a second pass that never touches Gone must not report Gone in its closing summary
newapp nbs '1 1.0 Gone\n'; bash $B/stepupdate.sh $S/nbs $S/nbs.plan > /dev/null 2>&1; printf '1 1.0 Fine\n' > $S/nbs2.plan
ctl stepupdate-no-baseline-stale-catch 0 'step 1: Fine' 'committed' '!no-baseline \(local edits unproven\)' -- bash $B/stepupdate.sh $S/nbs $S/nbs2.plan
newapp nf '1 1.0 OldBase\n'
ctl stepupdate-no-fallback-catch 2 'STOP: update of OldBase failed' '!retry with --no-baseline' -- bash $B/stepupdate.sh $S/nf $S/nf.plan --no-fallback
newapp op '1 1.0 OldPkg\n2 1.1 Fine\n'
ctl stepupdate-old-package-skip-catch 1 'SKIP: the OldPkg 1.0 package itself was made before Studio Pro 9.18' 'step 2: Fine' 'committed' 'kept: OldPkg 1.0 target package' -- bash $B/stepupdate.sh $S/op $S/op.plan
ctl stepupdate-old-package-reverted-pass 0 'notes-untracked.txt' '!junk' -- ls $S/op
newapp un '1 1.0 Broken\n2 1.1 Guid\n3 1.2 Fine\n'
ctl stepupdate-unattended-catch 1 'KEPT: Broken' 'KEPT: Guid' 'step 3: Fine' '2 kept, 0 network$' -- bash $B/stepupdate.sh $S/un $S/un.plan --unattended
ctl stepupdate-unattended-commits-pass 0 'step: Fine' '!step: Guid' -- git -C $S/un log --format=%s
newapp fr '1 1.0 Broken\n2 1.1 Fine\n3 1.2 Guid\n'
ctl stepupdate-attended-stop-catch 2 'STOP: update of Broken failed' '!step 2' -- bash $B/stepupdate.sh $S/fr $S/fr.plan
# T6R-7: --skip keeps Guid, so the pass ends in the kept-module check; the fake names are not modules of the base
# model, so that check is INVALID and the pass exits 1 (never a silent 0)
ctl stepupdate-from-skip-pass 1 'step 1: Broken 1.0 skipped \(before --from Fine\)' 'step 3: Guid 1.2 skipped \(--skip\)' 'committed' 'keptdeps: INVALID \(exit 2\).*not a module of the model: Guid' -- bash $B/stepupdate.sh $S/fr $S/fr.plan --from Fine --skip Guid
# U1: the summary counts what kept.txt holds: a --skip module is kept (it said 0 kept next to a kept: line)
newapp ks '1 1.0 Fine\n2 1.1 Guid\n3 1.2 Down\n'
ctl stepupdate-kept-count-skip-catch 1 '1 run, 1 committed, 2 kept, 0 network$' 'kept: Guid skipped by --skip' -- bash $B/stepupdate.sh $S/ks $S/ks.plan --skip Guid,Down
newapp kn '1 1.0 Fine\n'
ctl stepupdate-kept-count-none-pass 0 '1 committed, 0 kept, 0 network$' -- bash $B/stepupdate.sh $S/kn $S/kn.plan
# pipeline run 3 (T2-9, T3-13, T6-2, T7-8, T8-14): managed deps through host Maven; a 429 mirror falls through to the next
V=$T/vlm; mkdir -p $V/app/userlib $V/app/vendorlib; touch $V/app/userlib/present-1.0.jar
printf 'Synchronizing the following Java dependencies: commons-io:commons-io:2.11.0, org.x:present:1.0\n12:31:53 done\n' > $V/deps
printf 'com.x:y:[2,3)\n' > $V/range; printf 'nothing here\n' > $V/none
cat > $V/fakemvn.sh <<'FAKE'
#!/bin/bash
s=""; o=""; for a in "$@"; do case "$a" in -DoutputDirectory=*) o=${a#*=};; esac; done
prev=""; for a in "$@"; do [ "$prev" = -s ] && s=$a; prev=$a; done
grep -q 'bad' "$s" && { echo "[ERROR] Could not transfer artifact: status code: 429"; exit 1; }
touch "$o/commons-io-2.11.0.jar" "$o/present-1.0.jar"; exit 0
FAKE
chmod +x $V/fakemvn.sh
ctl vendorlib-mvn-mirror-fallback-pass 0 'mirror failed: https://bad1.*429' 'resolved through https://good' 'added: commons-io-2.11.0.jar' '1 added, 1 already present' '!added: present' -- env UPG_MVN=$V/fakemvn.sh UPG_MAVEN_MIRRORS="https://bad1 https://good" bash $B/cloud/vendorlib_mvn.sh $V/app $V/deps --apply
ctl vendorlib-mvn-all-fail-catch 1 'FAILED: every mirror failed' '!resolved through' -- env UPG_MVN=$V/fakemvn.sh UPG_MAVEN_MIRRORS="https://bad1 https://bad2" bash $B/cloud/vendorlib_mvn.sh $V/app $V/deps --apply
ctl vendorlib-mvn-range-catch 3 'RANGE' 'com.x:y:\[2,3\)' -- env UPG_MVN=false bash $B/cloud/vendorlib_mvn.sh $V/app $V/range --apply
ctl vendorlib-mvn-nodeps-catch 2 'NO DEPENDENCY' '!12:31:53' -- env UPG_MVN=false bash $B/cloud/vendorlib_mvn.sh $V/app $V/none --apply
ctl vendorlib-mvn-dry-pass 0 'plan: 2 dependencies' 'dry run' -- env UPG_MVN=false bash $B/cloud/vendorlib_mvn.sh $V/app $V/deps
mkdir -p $V/papp; touch $V/papp/App.mpr
# F2: an --app-dir outside the run folder is refused up front (exit 3), not left for mxbuild to fail on at baseline
mkdir -p $V/outside/oapp; touch $V/outside/oapp/App.mpr
ctl pipeline-appdir-outside-catch 3 'is outside the run folder' '!step ' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/outside/oapp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw2/work
# F1: force-ui.txt reaches stepupdate as --force-ui (else --unattended keeps every edited module), replay/<Module>.mdl runs after the updates
mkdir -p $V/pw3/replay; printf '# update anyway, replay\nMendixSSO\nAtlas_Core\n' > $V/pw3/force-ui.txt; echo 'alter entity X.Y drop validation rule;' > $V/pw3/replay/MendixSSO.mdl; : > $V/pw3/replay/Atlas_Core.patch
ctl pipeline-dry-forceui-replay-pass 0 'stepupdate\.sh .* --unattended --force-ui MendixSSO.?,Atlas_Core --saved-edits .*/pw3/saved-edits' 'exec .*/pw3/replay/MendixSSO\.mdl -p ' 'git -C .*/papp apply --check .*/pw3/replay/Atlas_Core\.patch' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw3 --only update --dry-run
# the version ladder: --to picks the route from the start version (9.x through the newest 10.24 toolset; 10.24 straight on)
mkdir -p $V/ltools/mxbuild-10.24.9.1 $V/ltools/mxbuild-10.24.27.1
ctl pipeline-ladder-9-goes-through-10-24-pass 0 'version ladder 9\.24\.2\.1 -> 10\.24\.27\.1 -> 11\.12\.7$' -- env UPG_TOOLS=$V/ltools bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 9.24.2.1 --to 11.12.7 --work $V/lw --dry-run
ctl pipeline-ladder-10-24-goes-straight-pass 0 'version ladder 10\.24\.3\.1 -> 11\.12\.7$' -- env UPG_TOOLS=$V/ltools bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.3.1 --to 11.12.7 --work $V/lw --dry-run
ctl pipeline-ladder-no-10-24-toolset-catch 2 'goes to 11\.12\.7 through 10\.24: no mxbuild-10\.24\.\* toolset found, give --via' '!unexpected failure' -- env UPG_TOOLS=$V/none bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 9.24.2.1 --to 11.12.7 --work $V/lw --dry-run
ctl pipeline-ladder-refuses-to-with-target-catch 2 'give one or the other' -- env UPG_TOOLS=$V/ltools bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 9.24.2.1 --to 11.12.7 --target 10.24.1 --work $V/lw --dry-run
ctl pipeline-dry-noforceui-catch 0 '!--force-ui' '!replay/' 'stepupdate\.sh .* --unattended' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only update --dry-run
# F14: replay/<Module>.guids restores the original GUIDs after the MDL replay; approved-step.txt reaches the step idcheck only
mkdir -p $V/pw4/replay; printf 'MendixSSO\n' > $V/pw4/force-ui.txt; echo 'create or modify association A.R_X from A.R to B.U;' > $V/pw4/replay/MendixSSO.mdl
printf '# original GUIDs back\nA.R_X\nA.R_Y\n' > $V/pw4/replay/MendixSSO.guids; printf 'A.R_X # restored by replay/MendixSSO.guids\n' > $V/pw4/approved-step.txt; printf '# accepted\n' > $V/pw4/approved.txt
ctl pipeline-dry-replay-guids-pass 0 'exec .*/pw4/replay/MendixSSO\.mdl -p ' 'restore_guid\.py .* A\.R_X --from .*/pw4/original\.mpr' 'restore_guid\.py .* A\.R_Y --from' '!restore_guid\.py .* original GUIDs' 'stepupdate\.sh .* --approved .*/pw4/\.approved-with-step\.txt' 'idcheck\.py .*/pw4/original\.mpr .* --approved .*/pw4/approved\.txt' '!idcheck\.py .*original\.mpr .*approved-with-step' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw4 --only update --dry-run
ctl pipeline-dry-no-step-approvals-catch 0 'stepupdate\.sh .* --approved .*/pw3/approved\.txt' '!approved-with-step' '!restore_guid' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw3 --only update --dry-run
# F14: a module whose last update is pre-convert is replayed before the convert; one still in plan.txt waits for step update
mkdir -p $V/pw5/replay; printf '9 1.0 MendixSSO\n8 1.0 Atlas_Core\n' > $V/pw5/plan-pre.txt; printf '8 2.0 Atlas_Core\n' > $V/pw5/plan.txt
echo 'alter entity X.Y drop validation rule;' > $V/pw5/replay/MendixSSO.mdl; : > $V/pw5/replay/Atlas_Core.patch
ctl pipeline-dry-replay-pre-pass 0 'stepupdate\.sh .*/pw5/plan-pre\.txt' 'exec .*/pw5/replay/MendixSSO\.mdl -p .* > .*replay-MendixSSO\.out' '!Atlas_Core\.patch' 'mx convert --in-place' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw5 --only convert --dry-run
# F15 (Purchase Request 10.24, real run): a module update rewrote the line next to a local edit; a context-free replay
# is allowed only when each removed block occurs once in its file (patch_unique.py)
mkdir -p $V/punq/a $V/punq/b $V/punq/c
printf "    .x {\n        background: var(--bg);\n        min-height: auto;\n    }\n" > $V/punq/a/s.scss
cp $V/punq/a/s.scss $V/punq/b/s.scss; printf "        min-height: auto;\n" >> $V/punq/b/s.scss; printf "    .x {\n    }\n" > $V/punq/c/s.scss
printf -- "--- a/s.scss\n+++ b/s.scss\n@@ -1,4 +1,4 @@\n     .x {\n         background-color: \$bg;\n-        min-height: auto;\n+        min-height: 500%%;\n     }\n" > $V/punq/edit.patch
printf -- "--- a/s.scss\n+++ b/s.scss\n@@ -1,2 +1,3 @@\n     .x {\n+        top: 0;\n     }\n" > $V/punq/add.patch
ctl patch-unique-drift-pass 0 "^unique: every removed block occurs once" "!AMBIGUOUS" -- python3 -I $B/patch_unique.py $V/punq/edit.patch $V/punq/a
ctl patch-unique-twice-catch 1 "^AMBIGUOUS s\.scss .*found 2 times" -- python3 -I $B/patch_unique.py $V/punq/edit.patch $V/punq/b
ctl patch-unique-gone-catch 1 "^AMBIGUOUS s\.scss .*found 0 times" -- python3 -I $B/patch_unique.py $V/punq/edit.patch $V/punq/c
ctl patch-unique-no-anchor-catch 1 "^AMBIGUOUS s\.scss .*removes nothing, no anchor" -- python3 -I $B/patch_unique.py $V/punq/add.patch $V/punq/a
# F7: the journeys get --psql for the database the app runs on, so the data rungs are measured (not INVALID "no --psql")
ctl pipeline-dry-journeys-psql-pass 0 'gen_journeys\.py .* --data-rung' 'run_journeys\.py .* --label before-picked .*--psql docker.*psql.*-d.*_smoke_jold' 'run_journeys\.py .* --label after .*--psql docker.*psql.*-d.*_smoke_jnew' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only journeys --dry-run
# PRF-2: the journeys step hands users.json to gen_journeys.py, which names the actions of a one-user role that can never render (assign-to-me-dead)
ctl pipeline-dry-journeys-users-pass 0 'gen_journeys\.py .* --users .*/pw/users\.json --data-rung' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only journeys --dry-run
ctl pipeline-dry-build-rows-pass 0 'mx sync-java-dependencies .* > .*/sync-java.log' 'missing_deps.py .* --target 11\.15\.0\.1' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only build --dry-run
ctl pipeline-dry-diff-gate-pass 0 'gate\.sh .*--config .*gate\.conf --only build.?,idcheck.?,const.?,data.?,logdiff.?,screens --dry-run' 'OLD_MDA=.*/old-10\.24\.26\.1\.mda' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only diff --dry-run
# the NEEDS-JUDGMENT rerun hint carries exactly one --from (the stopped step), not the run's own plus a second
NJ=$V/njrun; mkdir -p $NJ/app $NJ/tools/mxbuild-10.24.26.1 $NJ/tools/mxbuild-11.15.0.1 $NJ/tools/runtime-10.24.26.1 $NJ/tools/runtime-11.15.0.1; touch $NJ/app/App.mpr; printf '#!/bin/sh\nexit 0\n' > $NJ/tools/mxcli-linux; chmod +x $NJ/tools/mxcli-linux
ctl pipeline-nj-one-from-pass 0 'needs judgment \(exit 13\)' 'upgrade-pipeline\.sh .*--only update --from update$' '!--from update .*--from' -- bash -c "MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $NJ/app --source 10.24.26.1 --target 11.15.0.1 --work $NJ/work --from update --only update; cat $NJ/work/NEEDS-JUDGMENT.md"
# F13: a 10.x to 11 run with a plan.txt and no plan-pre.txt stops before the convert (Mendix 11 refuses packages made before 10.21)
mkdir -p $NJ/w13; printf '1 1.0 Administration\n' > $NJ/w13/plan.txt
ctl pipeline-no-plan-pre-catch 0 'needs judgment \(exit 13\)' 'plan-pre.txt missing on a 10.x to 11 run' '!mx convert exit' -- bash -c "MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $NJ/app --source 10.24.26.1 --target 11.15.0.1 --work $NJ/w13 --from convert --only convert; cat $NJ/w13/NEEDS-JUDGMENT.md"
mkdir -p $NJ/w13b; printf '1 1.0 Administration\n' > $NJ/w13b/plan.txt; printf '# nothing before the convert\n' > $NJ/w13b/plan-pre.txt
ctl pipeline-plan-pre-stated-pass 0 '!plan-pre.txt missing' 'convert' -- bash -c "MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $NJ/app --source 10.24.26.1 --target 11.15.0.1 --work $NJ/w13b --from convert --only convert; cat $NJ/w13b/NEEDS-JUDGMENT.md 2>/dev/null; true"
newapp o11b '1 1.0 Old11Base\n'
ctl stepupdate-pre1021-baseline-pass 0 'installed Old11Base cannot serve as the local-edit baseline \(range from 10.21.0 to 10.24.99\)' 'committed' '!SKIP' -- bash $B/stepupdate.sh $S/o11b $S/o11b.plan --unattended
newapp o11 '1 1.0 Old11Pkg\n'
ctl stepupdate-pre1021-skip-catch 0 'SKIP: the Old11Pkg 1.0 package itself was made before Studio Pro 10.21' 'pre-convert plan \(plan-pre.txt' 'kept: Old11Pkg' ' 0 committed, 1 kept' -- bash -c "bash $B/stepupdate.sh $S/o11 $S/o11.plan --unattended; cat $S/o11/.stepupdate/kept.txt; test ! -e $S/o11/junk.txt && echo reverted"
# v3.1 E7-1: a --force-ui module that only updates through --no-baseline saves nothing: UNSAVED, never "saved edits"
newapp nbu '1 1.0 NoBaseUi\n'
ctl stepupdate-unsaved-catch 2 'UNSAVED: NoBaseUi updated through --no-baseline and saved 0 files' 'STOP: NoBaseUi would lose its UI edits' 'Nothing committed' '!saved edits for replay' -- bash $B/stepupdate.sh $S/nbu $S/nbu.plan --force-ui NoBaseUi
newapp nbu '1 1.0 NoBaseUi\n'
ctl stepupdate-unsaved-unattended-catch 1 'KEPT: NoBaseUi .*UNSAVED' 'kept: NoBaseUi UNSAVED' -- bash $B/stepupdate.sh $S/nbu $S/nbu.plan --force-ui NoBaseUi --unattended
newapp nbu '1 1.0 NoBaseUi\n'
ctl stepupdate-unsaved-accept-pass 0 'accepted \(--accept-unsaved NoBaseUi\)' 'committed' 'UNSAVED \(replay by hand\): NoBaseUi 1.0' -- bash $B/stepupdate.sh $S/nbu $S/nbu.plan --force-ui NoBaseUi --accept-unsaved NoBaseUi
# v3.1 E6-7: a removal (idcheck verdict REVIEW) is named REVIEW in the KEPT line, a GUID change stays a plain finding
mkdir -p $S/base; cp $M/base/App.mpr $S/base/
newapp rv '1 1.0 Removes\n'; cp $M/step1-adds/App.mpr $S/rv/App.mpr; git -C $S/rv commit -qam 'start at step1-adds'
ctl stepupdate-review-word-catch 1 'KEPT: Removes .*idcheck REVIEW \(persistence loss or removal' -- bash $B/stepupdate.sh $S/rv $S/rv.plan --unattended
newapp rg '1 1.0 Guid\n'
ctl stepupdate-review-word-guid-pass 1 'KEPT: Guid .*idcheck finding' '!idcheck REVIEW' -- bash $B/stepupdate.sh $S/rg $S/rg.plan --unattended
# v3.1 E6-12: kept.txt is one line per module, and a module a later pass commits leaves it
newapp kp '1 1.0 UiEdit\n'
bash $B/stepupdate.sh $S/kp $S/kp.plan --unattended > /dev/null 2>&1; bash $B/stepupdate.sh $S/kp $S/kp.plan --unattended > /dev/null 2>&1
ctl stepupdate-kept-dedupe-catch 0 '^1 UiEdit local edits' -- sh -c "grep -c . $S/kp/.stepupdate/kept.txt | tr '\n' ' '; cat $S/kp/.stepupdate/kept.txt"
ctl stepupdate-kept-later-pass 0 'committed' '!kept: UiEdit' ' 0 kept, 0 network$' -- bash $B/stepupdate.sh $S/kp $S/kp.plan --unattended --force-ui UiEdit
ctl stepupdate-gitignore-mxcli-pass 0 '^\.mxcli/$' -- cat $S/kp/.gitignore
# T6R-7: a pass that keeps AuthMod and commits UpdConn, whose new version needs what AuthMod 2.1.2 lacks, names the pair
# and exits 1 (it was "1 kept" only; the CE1613 errors came at mx check). Nothing kept = keptdeps does not run.
cat > $T/kd-update.sh <<'EOF2'
case "$2" in
  AuthMod) echo "something unexpected"; exit 3;;
  UpdConn) cp "$1/keptdeps/App.mpr" "$3"; cp -R "$1/keptdeps/javasource" "$(dirname "$3")/";;
  *) exit 9;;
esac
EOF2
kdapp() { rm -rf $S/$1; mkdir -p $S/$1; cp $M/$2/App.mpr $S/$1/App.mpr; (cd $S/$1 && git init -q && git add App.mpr && git commit -qm base); printf "$3" > $S/$1.plan; }
kdapp kdu keptdeps-none '1 2.1.2 AuthMod\n2 4.0.0 UpdConn\n'
ctl stepupdate-keptdeps-catch 1 'KEPT: AuthMod' 'stepupdate: kept-module dependencies' '^   FAIL UpdConn 4\.0\.0 needs kept AuthMod 2\.1\.2: 3 of 12 references missing' '^   keptdeps: verdict FAIL' -- env UPG_UPDATE_CMD="bash $T/kd-update.sh $M {module} {mpr}" bash $B/stepupdate.sh $S/kdu $S/kdu.plan --unattended
ctl stepupdate-keptdeps-files 0 '"verdict": "FAIL"' -- cat $S/kdu/.stepupdate/keptdeps.json
kdapp kdn keptdeps-none '1 4.0.0 UpdConn\n'
ctl stepupdate-keptdeps-nothing-kept-pass 0 'committed' '!kept-module dependencies' -- env UPG_UPDATE_CMD="bash $T/kd-update.sh $M {module} {mpr}" bash $B/stepupdate.sh $S/kdn $S/kdn.plan --unattended
ctl stepupdate-keptdeps-not-run-pass 1 -- test -e $S/kdn/.stepupdate/keptdeps.txt
# a kept.txt module the model does not know is INVALID, never a silent pass (the fake modules above are not in base)
ctl stepupdate-keptdeps-invalid-catch 0 'keptdeps: not a module of the model: Broken, Guid' -- cat $S/un/.stepupdate/keptdeps.txt
# a pass that empties kept.txt (UiEdit committed by stepupdate-kept-later-pass) drops the stale report
ctl stepupdate-keptdeps-stale-removed-pass 1 -- test -e $S/kp/.stepupdate/keptdeps.txt
# T5-17 (T3-21, T3F-9): files outside the model. Two tiny fake packages are built here (mxcli's published-package form: an
# .mpk zip with App.mpr and the module's themesource / javascriptsource / javasource); the project copies carry or lack an edit.
export TH=$T/th; mkdir -p $TH/cache
cat > $TH/vars-pkg.scss <<'EOF2'
// Generated by Atlas_Core 3.20.0: do not edit by hand
$brand-primary: #264ae5 !default;
$brand-success: #3cb33d !default;
$gray-dark: #0a1325 !default;
EOF2
sed -e 's/#264ae5/#f26522/' -e 's/^\/\/ Generated.*/\/\/ Generated by the build/' -e 's/$/\r/' $TH/vars-pkg.scss > $TH/vars-edit.scss          # CRLF, other header, ONE colour edited
sed -e 's/^\/\/ Generated.*/\/\/ generated by mxbuild/' -e 's/$/\r/' $TH/vars-pkg.scss > $TH/vars-same.scss                              # CRLF and header noise only
sed 's/#264ae5/#1a2b3c/' $TH/vars-pkg.scss > $TH/vars-newpkg.scss                                                                        # the NEW package changes the same variable
printf 'public class Act {\n  // BEGIN USER CODE\n  int a = 1;\n  // END USER CODE\n}\n' > $TH/Act-pkg.java
sed 's/int a = 1/int a = 2/' $TH/Act-pkg.java > $TH/Act-edit.java
python3 - $TH <<'EOF2'
import sys, zipfile
th = sys.argv[1]
with zipfile.ZipFile(f"{th}/cache/23513-4.1.0.mpk", "w") as z:
    z.write(f"{th}/../m/pkg-administration/App.mpr", "App.mpr")
    z.write(f"{th}/vars-pkg.scss", "themesource/administration/web/_variables.scss")
    z.writestr("javascriptsource/administration/actions/util.js", "export const a = 1;\n")
    z.write(f"{th}/Act-pkg.java", "javasource/administration/actions/Act.java")
EOF2
mkdir -p $TH/empty
thapp() {  # thapp NAME VARS-FILE [JS-TEXT] [JAVA-FILE]: a git app (App.mpr + the module's files) under $TH/NAME
  rm -rf $TH/$1; mkdir -p $TH/$1/themesource/administration/web $TH/$1/javascriptsource/administration/actions $TH/$1/javasource/administration/actions $TH/$1/theme/web
  cp ${THMPR:-$M/base/App.mpr} $TH/$1/App.mpr; cp $2 $TH/$1/themesource/administration/web/_variables.scss
  printf '%s\n' "${3:-export const a = 1;}" > $TH/$1/javascriptsource/administration/actions/util.js
  cp ${4:-$TH/Act-pkg.java} $TH/$1/javasource/administration/actions/Act.java
  printf '$brand-warning: #ffaa00;\n' > $TH/$1/theme/web/custom-variables.scss
  (cd $TH/$1 && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm base)
  printf '23513 4.2.0 Administration\n' > $TH/$1.plan
}
thapp edit $TH/vars-edit.scss 'export const a = 2;'
ctl localedits-theme-edit-catch 1 'FILES-EDITED themesource/administration/web/_variables\.scss +CHANGED +1 variable\(s\) changed: \$brand-primary' 'FILES-EDITED javascriptsource/administration/actions/util\.js' 'FILES edits \(themesource, javascriptsource, Java user code; exit 1\): 2' 'force-ui: Administration' '!^ +RED ' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/edit/App.mpr --module Administration
thapp same $TH/vars-same.scss
ctl localedits-theme-edit-pass 0 'domain model unchanged' 'FILES edits \(themesource, javascriptsource, Java user code; exit 1\): 0' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/same/App.mpr --module Administration
thapp java $TH/vars-same.scss 'export const a = 1;' $TH/Act-edit.java
ctl localedits-java-usercode-edit-catch 1 'FILES-EDITED javasource/administration/actions/Act\.java +CHANGED +user code differs' 'force-ui: none' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/java/App.mpr --module Administration
ctl localedits-files-only-catch 1 'FILES-EDITED themesource/administration/web/_variables\.scss' '!domain' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/edit/App.mpr --module Administration --files-only
ctl localedits-files-only-pass 0 'files unchanged' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/same/App.mpr --module Administration --files-only
# not comparable is never "unedited"
ctl localedits-files-only-unknown-catch 2 'FILES NOT COMPARED' '!files unchanged' -- env UPG_MXCLI=/usr/bin/false UPG_CACHE=$TH/empty python3 $B/localedits.py $TH/same/App.mpr --module Administration --files-only
# F16 (Purchase Request 10.24, real run): a package imported with a stale AppStoreVersion; --installed (stepupdate passes
# the version of its own step commit) compares against the package actually installed. 4.1.9 = the edit copy's files
python3 - $TH <<'EOF2'
import sys, zipfile
th = sys.argv[1]
with zipfile.ZipFile(f"{th}/cache/23513-4.1.9.mpk", "w") as z:
    z.write(f"{th}/../m/pkg-administration/App.mpr", "App.mpr")
    z.write(f"{th}/vars-edit.scss", "themesource/administration/web/_variables.scss")
    z.writestr("javascriptsource/administration/actions/util.js", "export const a = 2;\n")
    z.write(f"{th}/Act-pkg.java", "javasource/administration/actions/Act.java")
EOF2
ctl localedits-installed-override-pass 0 'the MPR records 4\.1\.0, installed is 4\.1\.9 \(--installed\)' 'files unchanged' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache python3 $B/localedits.py $TH/edit/App.mpr --module Administration --files-only --installed Administration=4.1.9
# B4T2-3, B4N1-5: a Studio Pro JavaScript action that Studio Pro regenerated (header, generated imports, import order,
# quotes, JSDoc) is not an edit; a changed line inside USER CODE, or an added import, still is. Shape of the real
# NanoflowCommons actions; the package copy has no header, as in the B4T2 .mpk.
mkdir -p $TH/cache-js; cp $TH/cache/23513-4.1.0.mpk $TH/cache-js/
cat > $TH/jsact-pkg.js <<'EOF2'
import { Base64 } from "js-base64";
import Big from "big.js";

// BEGIN EXTRA CODE
const PREFIX = "b64:";
// END EXTRA CODE

/**
 * @param {string} base64
 * @returns {Promise.<string>}
 */
export async function Decode(base64) {
	// BEGIN USER CODE
	return PREFIX + Base64.decode(base64);
	// END USER CODE
}
EOF2
python3 -c "import zipfile,sys; z=zipfile.ZipFile('$TH/cache-js/23513-4.1.0.mpk','a'); z.write('$TH/jsact-pkg.js','javascriptsource/administration/actions/Decode.js'); z.close()"
{ printf '// This file was generated by Mendix Studio Pro.\r\n//\r\n// WARNING: Only the following code will be retained when actions are regenerated:\r\n// - the import list\r\n// Other code you write will be lost the next time you deploy the project.\r\n'
  printf 'import "mx-global";\r\nimport Big from '"'"'big.js'"'"';\r\nimport {Base64} from "js-base64"\r\n\r\n'
  sed -e '1,3d' -e 's/@param {string} base64/@param {string} base64 - the text/' -e 's/$/\r/' $TH/jsact-pkg.js; } > $TH/jsact-regen.js
sed 's/return PREFIX + Base64.decode(base64);/return Base64.decode(base64);/' $TH/jsact-regen.js > $TH/jsact-user.js
sed 's/^import "mx-global";/import "mx-global";\nimport { trim } from "lodash";/' $TH/jsact-regen.js > $TH/jsact-import.js
for k in regen user import; do rm -rf $TH/js-$k; cp -R $TH/same $TH/js-$k; cp $TH/jsact-$k.js $TH/js-$k/javascriptsource/administration/actions/Decode.js; done
ctl localedits-js-action-regenerated-pass 0 'files unchanged' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache-js python3 $B/localedits.py $TH/js-regen/App.mpr --module Administration --files-only
ctl localedits-js-action-user-code-catch 1 'FILES-EDITED javascriptsource/administration/actions/Decode\.js' -- env UPG_CACHE=$TH/cache-js python3 $B/localedits.py $TH/js-user/App.mpr --module Administration --files-only
ctl localedits-js-action-import-catch 1 'FILES-EDITED javascriptsource/administration/actions/Decode\.js' -- env UPG_CACHE=$TH/cache-js python3 $B/localedits.py $TH/js-import/App.mpr --module Administration --files-only
# no EXTRA CODE block between the imports and the function: the text before the first marker ends in "export async function ...";
# the import set is the import statements only, so the Studio Pro generated Big import in the package copy is not an edit
mkdir -p $TH/cache-jsr
python3 - <<EOF2
import zipfile
src = zipfile.ZipFile('$TH/cache-js/23513-4.1.0.mpk'); dst = zipfile.ZipFile('$TH/cache-jsr/23513-4.1.0.mpk', 'w')
for n in src.namelist():
    if n != 'javascriptsource/administration/actions/Decode.js':
        dst.writestr(n, src.read(n))
dst.close()
EOF2
for k in pkg regen user; do python3 $here/lib/jsregen.py $k $TH/jsr-$k.js; done
python3 -c "import zipfile; z=zipfile.ZipFile('$TH/cache-jsr/23513-4.1.0.mpk','a'); z.write('$TH/jsr-pkg.js','javascriptsource/administration/actions/Decode.js'); z.close()"
for k in regen user; do rm -rf $TH/jsr-$k; cp -R $TH/same $TH/jsr-$k; cp $TH/jsr-$k.js $TH/jsr-$k/javascriptsource/administration/actions/Decode.js; done
ctl localedits-js-import-only-regen-pass 0 'files unchanged' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache-jsr python3 $B/localedits.py $TH/jsr-regen/App.mpr --module Administration --files-only
ctl localedits-js-import-only-user-catch 1 'FILES-EDITED javascriptsource/administration/actions/Decode\.js' -- env UPG_CACHE=$TH/cache-jsr python3 $B/localedits.py $TH/jsr-user/App.mpr --module Administration --files-only
# F6: a file whose first line says AUTO-GENERATED / DO NOT MODIFY is Studio Pro's output (Atlas_Core
# _generated-exclusion-variables.scss, $use-modern-client), not an edit; a body change under a plain "generated" line still is.
mkdir -p $TH/cache-gen; cp $TH/cache/23513-4.1.0.mpk $TH/cache-gen/
printf '// THIS FILE IS AUTO-GENERATED. PLEASE DO NOT MODIFY THIS FILE.\n$use-modern-client: false;\n' > $TH/gen-pkg.scss
printf '// generated from the brand sheet\n$brand-x: #111;\n' > $TH/genlike-pkg.scss
python3 -c "import zipfile; z=zipfile.ZipFile('$TH/cache-gen/23513-4.1.0.mpk','a'); z.write('$TH/gen-pkg.scss','themesource/administration/web/_generated-exclusion-variables.scss'); z.write('$TH/genlike-pkg.scss','themesource/administration/web/_brand.scss'); z.close()"
for k in gen genlike; do rm -rf $TH/fg-$k; cp -R $TH/same $TH/fg-$k; cp $TH/genlike-pkg.scss $TH/fg-$k/themesource/administration/web/_brand.scss; done
printf '// THIS FILE IS AUTO-GENERATED. PLEASE DO NOT MODIFY THIS FILE.\n$use-modern-client: true;' > $TH/fg-gen/themesource/administration/web/_generated-exclusion-variables.scss
cp $TH/gen-pkg.scss $TH/fg-genlike/themesource/administration/web/_generated-exclusion-variables.scss
printf '// generated from the brand sheet\n$brand-x: #222;\n' > $TH/fg-genlike/themesource/administration/web/_brand.scss
ctl localedits-autogenerated-file-pass 0 'files unchanged' '!FILES-EDITED' -- env UPG_CACHE=$TH/cache-gen python3 $B/localedits.py $TH/fg-gen/App.mpr --module Administration --files-only
ctl localedits-generated-comment-edit-catch 1 'FILES-EDITED themesource/administration/web/_brand\.scss' '!_generated-exclusion' -- env UPG_CACHE=$TH/cache-gen python3 $B/localedits.py $TH/fg-genlike/App.mpr --module Administration --files-only
# after the update (themefiles report): a regenerated action is not FILES-OVERWRITTEN, a replaced USER CODE line is
rm -rf $TH/js-pkgform; cp -R $TH/js-regen $TH/js-pkgform; cp $TH/jsact-pkg.js $TH/js-pkgform/javascriptsource/administration/actions/Decode.js
python3 -c "import sys; sys.path.insert(0,'$B'); import themefiles as t; t.snapshot('$TH/js-regen','Administration','$TH/snap-regen'); t.snapshot('$TH/js-user','Administration','$TH/snap-user')"
ctl themefiles-js-action-report-pass 0 '!FILES-OVERWRITTEN' -- python3 $B/themefiles.py report $TH/js-pkgform Administration $TH/snap-regen
ctl themefiles-js-action-report-catch 1 'FILES-OVERWRITTEN javascriptsource/administration/actions/Decode\.js' -- python3 $B/themefiles.py report $TH/js-pkgform Administration $TH/snap-user
# stepupdate: refuse, force + no-baseline (saved, listed, replayed), unproven stop, clean pass
export TH_NEWVARS=$TH/vars-newpkg.scss
newapp_th() { thapp $1 $2 "${3:-export const a = 1;}"; cp $TH/$1.plan $S/$1.plan; rm -rf $S/$1; cp -R $TH/$1 $S/$1; }
newapp_th e1 $TH/vars-edit.scss 'export const a = 2;'
thstep() { UPG_MXCLI=/usr/bin/false UPG_CACHE=${UPG_CACHE_TH:-$TH/cache} UPG_NEWVARS=$TH/vars-newpkg.scss "$@"; }
ctl stepupdate-files-edit-refuse-catch 2 'FILES-EDITED themesource/administration/web/_variables\.scss' 'rerun with --force-ui Administration' 'STOP: update of Administration refused for local file edits' '!committed [0-9a-f]{7}' -- thstep bash $B/stepupdate.sh $S/e1 $S/e1.plan
ctl stepupdate-files-edit-untouched-pass 0 '^colour kept$' -- sh -c "grep -q f26522 $S/e1/themesource/administration/web/_variables.scss && echo colour kept"
newapp_th e2 $TH/vars-edit.scss 'export const a = 2;'
ctl stepupdate-files-no-baseline-catch 0 'FILES: this route replaces Administration' 'FILES-OVERWRITTEN themesource/administration/web/_variables\.scss \(saved: .*/saved/Administration/themesource/administration/web/_variables\.scss' 'FILES-OVERWRITTEN javascriptsource/administration/actions/util\.js' 'REPLAYED-VARS 1 variable line\(s\) into theme/web/custom-variables\.scss: \$brand-primary: #f26522;' 'FILES-OVERWRITTEN: Administration 4\.2\.0 2 file' -- thstep bash $B/stepupdate.sh $S/e2 $S/e2.plan --force-ui Administration --accept-unsaved Administration
ctl stepupdate-files-saved-copy-pass 0 'f26522' -- cat $S/e2/.stepupdate/saved/Administration/themesource/administration/web/_variables.scss
ctl stepupdate-files-replayed-pass 0 '^\$brand-warning: #ffaa00;' '^\$brand-primary: #f26522;' -- cat $S/e2/theme/web/custom-variables.scss
newapp_th e3 $TH/vars-edit.scss 'export const a = 2;'
rm -rf $S/e3/theme/web/custom-variables.scss; (cd $S/e3 && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm nocustom)
ctl stepupdate-files-no-custom-variables-catch 0 'FILES-OVERWRITTEN themesource/administration/web/_variables\.scss' 'theme/web/custom-variables\.scss does not exist: variables NOT replayed' '!REPLAYED-VARS' -- thstep bash $B/stepupdate.sh $S/e3 $S/e3.plan --force-ui Administration --accept-unsaved Administration
newapp_th e4 $TH/vars-same.scss
ctl stepupdate-files-unproven-catch 2 'FILES-UNKNOWN: Administration has theme/JavaScript/Java files but they cannot be compared' 'FILES-OVERWRITTEN themesource/administration/web/_variables\.scss' 'FILES-UNKNOWN: the update replaced [0-9]+ file\(s\)' 'STOP: Administration lost [0-9]+ file\(s\) that cannot be shown unedited' '!committed [0-9a-f]{7}' -- env UPG_CACHE_TH=$TH/empty bash -c "$(declare -f thstep); thstep bash $B/stepupdate.sh $S/e4 $S/e4.plan"
newapp_th e5 $TH/vars-same.scss
ctl stepupdate-files-clean-pass 0 'files: [0-9]+ file\(s\) of Administration changed by the new package itself' 'committed' '!FILES-OVERWRITTEN' '!FILES-EDITED' '!FILES-UNKNOWN' -- thstep bash $B/stepupdate.sh $S/e5 $S/e5.plan
# B4N1-4: an 11.x .mpr records content id 0; the plan line has it. stepupdate passes it to localedits (--cid), so the
# files are compared (clean: committed) instead of FILES-UNKNOWN; a plan line with no id is still FILES-UNKNOWN.
THMPR=$M/cid-zero/App.mpr newapp_th e6 $TH/vars-same.scss
ctl stepupdate-files-plan-cid-pass 0 'files: [0-9]+ file\(s\) of Administration changed by the new package itself' 'committed' '!FILES-UNKNOWN' '!FILES-EDITED' -- thstep bash $B/stepupdate.sh $S/e6 $S/e6.plan
# QW-3 (backlog #31): a package that answers HTTP 500 cannot be compared with, but git can prove the theme/JS/Java files
# unedited: the install commit C (the newest commit touching the module's folders that also changes the module's recorded
# version) has the same files as now. Built here: a real git repo, App.mpr 4.0.0 then 4.1.0 (mkmodel from base)
HG=$T/hist; mkdir -p $HG
sed 's/"4\.1\.0"/"4.0.0"/g' $FX/models/base.json > $HG/m400.json; python3 $here/lib/mkmodel.py $HG/m400.json $HG/m400 > /dev/null
hgit() { git -C "$1" -c user.email=c@c -c user.name=ctl "${@:2}"; }
hgapp() {  # hgapp NAME: App.mpr 4.0.0 + files, then the install commit (4.1.0, the files changed) with the toolkit's subject
  rm -rf $HG/$1; mkdir -p $HG/$1/themesource/administration/web $HG/$1/javascriptsource/administration/actions $HG/$1/javasource/administration/actions
  cp $HG/m400/App.mpr $HG/$1/App.mpr; cp $TH/vars-edit.scss $HG/$1/themesource/administration/web/_variables.scss
  printf '%s\n' 'export const a = 1;' > $HG/$1/javascriptsource/administration/actions/util.js; cp $TH/Act-pkg.java $HG/$1/javasource/administration/actions/Act.java
  git -C $HG/$1 init -q; hgit $HG/$1 add -A .; hgit $HG/$1 commit -qm "base"
  cp $M/base/App.mpr $HG/$1/App.mpr; cp $TH/vars-same.scss $HG/$1/themesource/administration/web/_variables.scss
  hgit $HG/$1 add -A .; hgit $HG/$1 commit -qm "step: Administration 4.1.0 (stepupdate, content 23513)"
}
hgapp hclean; echo notes > $HG/hclean/README.md; hgit $HG/hclean add README.md; hgit $HG/hclean commit -qm "docs"
sed -i 's/\r$//' $HG/hclean/themesource/administration/web/_variables.scss; hgit $HG/hclean commit -qam "line ends only"
ctl themefiles-history-clean-pass 0 '^FILES-UNEDITED-BY-HISTORY Administration since [0-9a-f]{7} [0-9-]+ "step: Administration 4\.1\.0 \(stepupdate' '[0-9]+ files, provenance: toolkit step' '!FILES-EDITED' '!FILES-UNKNOWN' -- python3 $B/themefiles.py history $HG/hclean Administration --mpr App.mpr
hgapp hedit; sed -i 's/f26522/00ff00/; s/^\$brand-primary: *[^;]*/$brand-primary: #00ff00/' $HG/hedit/themesource/administration/web/_variables.scss; echo '$brand-extra: #123;' >> $HG/hedit/themesource/administration/web/_variables.scss; hgit $HG/hedit commit -qam "brand colour"
ctl themefiles-history-edited-catch 1 '^FILES-EDITED themesource/administration/web/_variables\.scss \(by history, since [0-9a-f]{7}\)' '!FILES-UNEDITED' -- python3 $B/themefiles.py history $HG/hedit Administration --mpr App.mpr --json $HG/hedit.json
ctl themefiles-history-edited-vars-pass 0 'brand-extra: #123;' -- cat $HG/hedit.json
git clone -q --depth 1 file://$HG/hclean $HG/hshallow
ctl themefiles-history-shallow-catch 2 '^FILES-UNKNOWN Administration: shallow clone' '!UNEDITED' -- python3 $B/themefiles.py history $HG/hshallow Administration --mpr App.mpr
cp -R $HG/hclean $HG/huntracked; echo x > $HG/huntracked/themesource/administration/web/_new.scss
ctl themefiles-history-untracked-catch 2 '^FILES-UNKNOWN Administration: untracked, ignored or uncommitted files' '!UNEDITED' -- python3 $B/themefiles.py history $HG/huntracked Administration --mpr App.mpr
cp -R $HG/hclean $HG/higno; echo '*.map' > $HG/higno/.gitignore; hgit $HG/higno add .gitignore; hgit $HG/higno commit -qm ignore; echo x > $HG/higno/themesource/administration/web/local.map
ctl themefiles-history-ignored-catch 2 '^FILES-UNKNOWN Administration: untracked, ignored or uncommitted files' '!UNEDITED' -- python3 $B/themefiles.py history $HG/higno Administration --mpr App.mpr
cp -R $HG/hclean $HG/hdirty; echo '$z: 1;' >> $HG/hdirty/themesource/administration/web/_variables.scss
ctl themefiles-history-uncommitted-catch 2 '^FILES-UNKNOWN Administration: untracked, ignored or uncommitted files' '!UNEDITED' -- python3 $B/themefiles.py history $HG/hdirty Administration --mpr App.mpr
rm -rf $HG/hnogit; mkdir -p $HG/hnogit/themesource/administration/web; cp $M/base/App.mpr $HG/hnogit/; echo a > $HG/hnogit/themesource/administration/web/a.scss
ctl themefiles-history-not-git-catch 2 '^FILES-UNKNOWN Administration: not a git work tree' -- python3 $B/themefiles.py history $HG/hnogit Administration --mpr App.mpr
# the files changed in a commit that did NOT change the version are not an install: with no version-changing commit
# touching the folders the answer is UNKNOWN, and a later edit commit is never read as the install
hgapp hnover; cp $HG/m400/App.mpr $HG/hnover/App.mpr; hgit $HG/hnover commit -qam "mpr back to 4.0.0 (a version the folders' commit never installed)"
ctl themefiles-history-version-mismatch-catch 2 '^FILES-UNKNOWN Administration: the newest commit that changes Administration.s version' '!UNEDITED' -- python3 $B/themefiles.py history $HG/hnover Administration --mpr App.mpr
# stepupdate: FILES-UNKNOWN (no package in the cache) + git proof = commits without --accept-unsaved; an edit found by history is FILES-EDITED
hgapp h1x; mkdir -p $HG/h1x/theme/web; printf '$brand-warning: #ffaa00;\n' > $HG/h1x/theme/web/custom-variables.scss; hgit $HG/h1x add -A .; hgit $HG/h1x commit -qm "custom variables"
rm -rf $S/h1; cp -R $HG/h1x $S/h1; printf '23513 4.2.0 Administration\n' > $S/h1.plan
ctl stepupdate-files-history-proved-pass 0 '^   FILES-UNEDITED-BY-HISTORY Administration since' 'unedited by git history' 'committed [0-9a-f]{7}' '!FILES-UNKNOWN' '!STOP' '!accept-unsaved' -- env UPG_CACHE_TH=$TH/empty bash -c "$(declare -f thstep); thstep bash $B/stepupdate.sh $S/h1 $S/h1.plan"
ctl stepupdate-files-history-recorded-pass 0 'unedited proven by git, not by the package' -- sh -c "cat $S/h1/.stepupdate/overwritten.txt"
# the same repo with a later commit that edits a theme file: history finds the edit, the step refuses like any FILES-EDITED
cp -R $HG/h1x $S/h2; echo '$brand-extra: #123;' >> $S/h2/themesource/administration/web/_variables.scss; hgit $S/h2 commit -qam "brand"; printf '23513 4.2.0 Administration\n' > $S/h2.plan
ctl stepupdate-files-history-edited-catch 2 'FILES-EDITED themesource/administration/web/_variables\.scss \(by history, since [0-9a-f]{7}\)' 'rerun with --force-ui Administration' 'STOP: update of Administration refused for local file edits' '!committed [0-9a-f]{7}' -- env UPG_CACHE_TH=$TH/empty bash -c "$(declare -f thstep); thstep bash $B/stepupdate.sh $S/h2 $S/h2.plan"
THMPR=$M/cid-zero/App.mpr newapp_th e7 $TH/vars-same.scss; printf '0 4.2.0 Administration\n' > $S/e7.plan
ctl stepupdate-files-no-cid-unknown-catch 2 'FILES-UNKNOWN: Administration has theme/JavaScript/Java files but they cannot be compared' '!committed [0-9a-f]{7}' -- thstep bash $B/stepupdate.sh $S/e7 $S/e7.plan
# v3.1 E6-13: refusals of edits mx convert made to a module the pre pass installed pristine are forced, not kept
convapp() {  # convapp NAME MODULE [extra commit subject]: history base, step: MODULE 1.0, convert, [extra]
  newapp $1 "1 2.0 $2\n"
  (cd $S/$1 && git commit -q --allow-empty -m "step: $2 1.0 (stepupdate, idcheck PASS)" && echo c > conv.txt && git add conv.txt && git commit -qm "convert: mx convert --in-place 10.12.9 -> 10.24.16" && \
   { [ -z "${3:-}" ] || { echo r > rep.txt; git add rep.txt; git commit -qm "$3"; }; })
}
convapp cm ConvUi
ctl stepupdate-convert-made-pass 0 'CONVERT-MADE: ConvUi was installed pristine' 'updating with --force' 'committed' '!saved edits for replay' -- bash $B/stepupdate.sh $S/cm $S/cm.plan
ctl stepupdate-convert-made-commit-pass 0 'step: ConvUi 2.0 \(stepupdate, idcheck PASS, convert-made edits forced\)' -- git -C $S/cm log -1 --format=%s
convapp cmr ConvUi "repair: hand edit of a page"
ctl stepupdate-convert-made-repair-catch 2 'LOCAL: after the pristine install of ConvUi' 'repair: hand edit' 'STOP: update of ConvUi refused for local edits' -- bash $B/stepupdate.sh $S/cmr $S/cmr.plan
convapp cmu Unread
ctl stepupdate-unread-convert-pass 0 'CONVERT-MADE: Unread' 'committed' -- bash $B/stepupdate.sh $S/cmu $S/cmu.plan
newapp ur '1 1.0 Unread\n'
ctl stepupdate-unread-catch 2 '22 element\(s\) could not be read' 'STOP: update of Unread refused, elements could not be read' '!update failed' -- bash $B/stepupdate.sh $S/ur $S/ur.plan
ctl stepupdate-convert-made-off-catch 2 'STOP: update of ConvUi refused for local edits' '!CONVERT-MADE' -- bash $B/stepupdate.sh $S/cmr $S/cmr.plan --no-convert-made
# batch 1: a tool or network failure is never a verdict on the module (T1-11..13, T4-1/2, T7-13, T8-10/11/21).
# An MPR name with spaces is one argument (placeholders are shell-quoted; the old '{mpr}' workaround still works)
spaced() { newapp $1 "$2"; (cd $S/$1 && git mv App.mpr "My App.mpr" && git commit -qm 'spaced name'); }
spaced sp '1 1.0 Fine\n'
UPG_UPDATE_CMD="bash $FX/bin/fake-argv.sh $S -p {mpr}" \
  ctl stepupdate-spaced-mpr-pass 0 'committed' '1 run, 1 committed, 0 kept, 0 network$' -- bash $B/stepupdate.sh $S/sp $S/sp.plan --unattended
ctl stepupdate-spaced-mpr-argc-pass 0 '^argc after -p: 1$' -- cat "$S/sp/.stepupdate/step1-Fine.log"
spaced spq '1 1.0 Fine\n'
UPG_UPDATE_CMD="bash $FX/bin/fake-argv.sh $S -p '{mpr}'" \
  ctl stepupdate-spaced-quoted-pass 0 'committed' '1 committed, 0 kept' -- bash $B/stepupdate.sh $S/spq $S/spq.plan --unattended
ctl stepupdate-spaced-quoted-argc-pass 0 '^argc after -p: 1$' -- cat "$S/spq/.stepupdate/step1-Fine.log"
# a command that still splits its arguments: mxcli's "accepts 1 arg(s)" is a TOOL ERROR, never KEPT, even unattended
spaced sps '1 1.0 Fine\n2 1.0 Fine2\n'
UPG_UPDATE_CMD="bash $FX/bin/fake-argv.sh $S -p {mpr} {module}" \
  ctl stepupdate-split-args-catch 3 'STOP: TOOL ERROR in the update of Fine \(accepts 1 arg\(s\), received 2' '!KEPT' '!step 2' -- bash $B/stepupdate.sh $S/sps $S/sps.plan --unattended
export UPG_RETRY_SLEEP="0 0 0"
NET="bash $FX/bin/fake-net.sh $S {module} {mpr}"
rm -rf $S/net-state; newapp tx '1 1.0 X509\n2 1.0 Fine\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-tool-error-stop-catch 3 'STOP: TOOL ERROR in the update of X509' 'x509: certificate signed by unknown authority' 'tree reverted' '!KEPT' '!step 2' -- bash $B/stepupdate.sh $S/tx $S/tx.plan --unattended
ctl stepupdate-tool-error-reverted-pass 0 '^clean$' -- sh -c "cd $S/tx && test -z \"\$(git status --porcelain --untracked-files=no)\" && ! test -e x509-junk.txt && ! grep -q X509 .stepupdate/kept.txt 2>/dev/null && echo clean"
rm -rf $S/net-state; newapp na '1 1.0 NoAuth\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-no-credential-catch 3 'TOOL ERROR .*no credential for profile' '!KEPT' -- bash $B/stepupdate.sh $S/na $S/na.plan --unattended
# NETWORK: retried (UPG_RETRY_SLEEP, 5 15 45 s by default); a success on retry commits as usual
rm -rf $S/net-state; newapp fl '1 1.0 Flaky\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-transient-retry-pass 0 'network error on Flaky \(TLS handshake timeout\): retry 1 of 3' 'committed' '1 committed, 0 kept, 0 network$' -- bash $B/stepupdate.sh $S/fl $S/fl.plan --unattended
# retries exhausted: NETWORK in kept.txt (not a refusal), next line runs; twice in a row is the infrastructure: STOP
rm -rf $S/net-state; newapp dn '1 1.0 Down\n2 1.1 Fine\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-network-unattended-catch 1 'retry 3 of 3' 'NETWORK: Down not updated' 'step 2: Fine' '1 committed, 0 kept, 1 network$' 'kept: Down NETWORK: TLS handshake timeout' -- bash $B/stepupdate.sh $S/dn $S/dn.plan --unattended
rm -rf $S/net-state; newapp d2 '1 1.0 Down\n2 1.0 Down2\n3 1.1 Fine\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-network-twice-catch 3 'same network error \(TLS handshake timeout\) on Down and Down2 in a row' '!step 3' -- bash $B/stepupdate.sh $S/d2 $S/d2.plan --unattended
rm -rf $S/net-state; newapp bz '1 1.0 Busy\n'
UPG_UPDATE_CMD=$NET ctl stepupdate-network-attended-catch 2 'retry 3 of 3' 'STOP: NETWORK error on Busy \(HTTP 503\)' '!KEPT' -- bash $B/stepupdate.sh $S/bz $S/bz.plan
# the baseline refusal "expected redirect, got HTTP 500" stays a refusal (no retry), as before
newapp g5 '1 1.0 Gone\n'
ctl stepupdate-http500-baseline-pass 0 'Gone cannot serve .*expected redirect' '!network error' -- bash $B/stepupdate.sh $S/g5 $S/g5.plan
unset UPG_RETRY_SLEEP
# batch 1 (T1-15, T3-10, T4-3, T7-12): no "step:" commit on a 9.x path; the pre-convert localedits is the pristine proof.
# T5-9, T6-10: build: commits that leave the model alone and userlib-only jar cleanups are neutral.
CM=$T/cm2; mkdir -p $CM
cmrepo() {  # cmrepo NAME 'subject|file' ...: fresh repo, commit "original" (App.mpr), then one commit per argument
  local r=$CM/$1; shift; rm -rf $r; mkdir -p $r; cp $M/base/App.mpr $r/App.mpr
  (cd $r && git init -q && git add App.mpr && git commit -qm "original" && \
   for c in "$@"; do f=${c#*|}; mkdir -p "$(dirname "$f")"; echo "$c" >> "$f"; git add "$f"; git commit -qm "${c%%|*}"; done)
}
lejson() {  # lejson FILE MODULE DOMAIN UI LOGIC [MODIFIED|none]: a localedits.py --json report with one module; the
  # element layer (--mxcli-diff) has MODIFIED modified elements (default 0), "none" = the report ran without --mxcli-diff
  python3 -c "import json,sys; r=lambda n:[{'change':'ADDED','kind':'x','name':'X.'+str(i),'detail':'','data':False} for i in range(int(n))]; m=(sys.argv[6:] or ['0'])[0]; e={'name':sys.argv[2],'cid':999,'version':'1.0','compared_with':'1.0','domain':r(sys.argv[3]),'ui':r(sys.argv[4]),'logic':r(sys.argv[5])}; e.update({} if m=='none' else {'elements':{'verified':True,'modified':['MICROFLOW X.'+str(i) for i in range(int(m))],'unknown':[],'onlyInstalled':['JAR_DEPENDENCY a:b']},'elements_error':None}); json.dump([e],open(sys.argv[1],'w'))" "$@"
}
lejson $CM/clean.json FeedbackModule 0 0 0; lejson $CM/logic.json FeedbackModule 0 0 1; lejson $CM/domain.json FeedbackModule 1 0 0
lejson $CM/nodiff.json FeedbackModule 0 0 0 none; lejson $CM/modified.json FeedbackModule 0 0 0 1
cmrepo v9 'convert 9.24.23 -> 10.24.26|App.mpr' 'build: regenerated stubs|javasource/feedbackmodule/actions/A.java' 'step: Atlas_Core 3.21.0 (stepupdate, idcheck PASS)|App.mpr'
ctl convertmade-9to10-localedits-clean-pass 0 '^CONVERT-MADE: FeedbackModule has no step commit; source: pre-convert localedits .*domain model unchanged, 0 UI lines, 0 logic lines' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $CM/clean.json
ctl convertmade-9to10-localedits-logic-catch 1 '^LOCAL: .*pre-convert localedits .*does not show FeedbackModule clean: 1 logic lines' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $CM/logic.json
ctl convertmade-9to10-localedits-domain-catch 1 '^LOCAL: .*1 domain rows' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $CM/domain.json
# the offline layers compare no contents (a microflow body edit is invisible): without --mxcli-diff it is LOCAL
ctl convertmade-9to10-localedits-nodiff-catch 1 '^LOCAL: .*element contents not compared' '!CONVERT-MADE' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $CM/nodiff.json
ctl convertmade-9to10-localedits-modified-catch 1 '^LOCAL: .*1 mxcli-diff modified elements' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $CM/modified.json
ctl convertmade-9to10-localedits-absent-catch 1 '^LOCAL: .*not in the localedits report' -- bash $B/convertmade.sh $CM/v9 MendixSSO --localedits $CM/clean.json
# MC-6: a "could not be read" refusal says when the pre-convert localedits report shows the module unedited, and names the route
lejson $CM/clean-unread.json Unread 0 0 0
cmrepo urc 'noop|notes.txt'; printf '1 1.0 Unread\n' > $CM/urc.plan
ctl stepupdate-unread-localedits-clean-catch 2 'localedits \(.*clean-unread\.json\) shows Unread UNEDITED' 'rerun with --force-ui Unread' 'STOP: update of Unread refused, elements could not be read' -- bash $B/stepupdate.sh $CM/urc $CM/urc.plan --localedits $CM/clean-unread.json
ctl stepupdate-unread-no-localedits-catch 2 'UI edits only: rerun with --force-ui Unread' '!UNEDITED' -- bash $B/stepupdate.sh $S/ur $S/ur.plan
ctl convertmade-9to10-no-localedits-catch 1 "^LOCAL: no 'step: FeedbackModule' commit" 'give --localedits' -- bash $B/convertmade.sh $CM/v9 FeedbackModule
cmrepo v9r 'convert 9.24.23 -> 10.24.26|App.mpr' 'repair 0: JavaVersion Java21|App.mpr'
ctl convertmade-9to10-localedits-repair-catch 1 '^LOCAL: no .step: FeedbackModule. commit, and after the original commit' 'repair 0: JavaVersion' -- bash $B/convertmade.sh $CM/v9r FeedbackModule --localedits $CM/clean.json
cmrepo v9n 'build: regenerated stubs|javasource/feedbackmodule/actions/A.java'
ctl convertmade-9to10-localedits-noconvert-catch 1 '^LOCAL: no convert commit after the original commit' -- bash $B/convertmade.sh $CM/v9n FeedbackModule --localedits $CM/clean.json
cmrepo b1 'step: FeedbackModule 1.0 (stepupdate, idcheck PASS)|App.mpr' 'convert: mx convert|App.mpr' 'build: regenerated stubs|javasource/feedbackmodule/actions/A.java' 'repair 3: jardedupe --apply|userlib/commons-io-2.11.0.jar' 'gitignore tool folders|.gitignore'
ctl convertmade-build-commit-neutral-pass 0 '^CONVERT-MADE: FeedbackModule was installed pristine' -- bash $B/convertmade.sh $CM/b1 FeedbackModule
cmrepo b2 'step: FeedbackModule 1.0 (stepupdate, idcheck PASS)|App.mpr' 'convert: mx convert|App.mpr' 'build: regenerated stubs|App.mpr'
ctl convertmade-build-commit-model-catch 1 '^LOCAL: after the pristine install' 'build commit changes the model' -- bash $B/convertmade.sh $CM/b2 FeedbackModule
ctl convertmade-localedits-input-catch 2 'not a localedits.py --json file' -- bash $B/convertmade.sh $CM/v9 FeedbackModule --localedits $FX/bin/fake-update.sh
# T7-15: JAR_DEPENDENCY-only refusals are package-owned and forced; T5-9/T8-12: JAVA_ACTION-only refusals are forced
# only when the javasource user code equals the installed package (bin/usercode.py against the .mpk cache).
newapp jd '1 2.0 JarDep\n'
ctl stepupdate-jar-dependency-only-forced-pass 0 'PACKAGE-OWNED: JarDep is refused for JAR_DEPENDENCY rows only' 'saved for reference under .*/JarDep\.package-owned' 'committed' '!LOGIC edits' -- bash $B/stepupdate.sh $S/jd $S/jd.plan
ctl stepupdate-jar-dependency-only-commit-pass 0 'step: JarDep 2.0 \(stepupdate, idcheck PASS, package-owned jar dependencies forced\)' -- git -C $S/jd log -1 --format=%s
newapp jdo '1 2.0 JarDep\n'
ctl stepupdate-jar-dependency-off-catch 2 'JAR_DEPENDENCY rows only: package-owned, not a logic edit' '!LOGIC edits' 'STOP: update of JarDep refused' -- bash $B/stepupdate.sh $S/jdo $S/jdo.plan --no-convert-made
UC=$T/uc; mkdir -p $UC/cache $UC/pkg/javasource/javaact/actions $UC/pkg/javasource/javaact/proxies
printf '// generated by 9.24\npackage javaact.actions;\npublic class StartLogin {\n\tpublic StartLogin(IContext c) { super(c); }\n\t// BEGIN USER CODE\n\t\treturn Login.start(this.ctx);\r\n\t// END USER CODE\n\t// BEGIN EXTRA CODE\n\t// END EXTRA CODE\n}\n' > $UC/pkg/javasource/javaact/actions/StartLogin.java
echo 'class Proxy9 {}' > $UC/pkg/javasource/javaact/proxies/P.java
(cd $UC/pkg && python3 -m zipfile -c $UC/cache/999-1.0.mpk javasource)
lejson $UC/le.json JavaAct 0 0 0
javaapp() {  # javaapp NAME USERCODE-LINE: app whose JavaAct stub was regenerated by 10.24 (header, constructor) around USERCODE
  newapp $1 '999 2.0 JavaAct\n'; mkdir -p $S/$1/javasource/javaact/actions $S/$1/javasource/javaact/proxies
  printf "// generated by 10.24, parameter metadata rewritten\npackage javaact.actions;\npublic class StartLogin extends UserAction<Boolean> {\n  public StartLogin(IContext context, String p) { super(context); }\n\t// BEGIN USER CODE\n$2\n\t// END USER CODE\n\t// BEGIN EXTRA CODE\n\t// END EXTRA CODE\n}\n" > $S/$1/javasource/javaact/actions/StartLogin.java
  echo 'class Proxy10 {}' > $S/$1/javasource/javaact/proxies/P.java
  (cd $S/$1 && git add javasource && git commit -qm "build: regenerated stubs")
}
javaapp ja '\t\treturn Login.start(this.ctx);   '
ctl stepupdate-java-action-identical-usercode-forced-pass 0 'IDENTICAL: user code of 1 Java files of JavaAct 1\.0' 'CONVERT-MADE: JavaAct is refused for JAVA_ACTION rows only' 'committed' -- env UPG_CACHE=$UC/cache bash $B/stepupdate.sh $S/ja $S/ja.plan --localedits $UC/le.json
ctl stepupdate-java-action-commit-pass 0 'step: JavaAct 2.0 \(stepupdate, idcheck PASS, convert-made Java action metadata forced, user code identical\)' -- git -C $S/ja log -1 --format=%s
javaapp jc '\t\tLog.info("local tweak"); return Login.start(this.ctx);'
ctl stepupdate-java-action-changed-usercode-keep-catch 1 'DIFFERENT: Java code of JavaAct 1\.0' 'changed user code: javasource/javaact/actions/StartLogin\.java' 'local LOGIC edits \(JAVA_ACTION' 'KEPT: JavaAct' '!committed [0-9a-f]{7}' '0 committed, 1 kept' -- env UPG_CACHE=$UC/cache bash $B/stepupdate.sh $S/jc $S/jc.plan --localedits $UC/le.json --unattended
ctl usercode-no-package-catch 2 'CANNOT COMPARE: installed package JavaAct 1\.1 not cached' -- env UPG_CACHE=$UC/cache UPG_MXCLI=/bin/false python3 $B/usercode.py $S/ja JavaAct --cid 999 --version 1.1
if [ -d "$LAB/f1/runs/e4/work" ] && [ -d "$LAB/e5/run2/work" ]; then
  # field: replay the real refusal output (E4 ExcelImporter local edits, E5b NanoflowCommons pre-9.18 baseline)
  newapp fe4 '1 1.0 ExcelImporter\n'
  UPG_UPDATE_CMD="grep -v heavy-lock $LAB/f1/runs/e4/work/stepupdate-post-1-ExcelImporter.log; exit 1" \
    ctl field-e4-stepupdate-logic-edits-catch 2 'local LOGIC edits \(MICROFLOW RULE' -- bash $B/stepupdate.sh $S/fe4 $S/fe4.plan
  newapp fe5 '1 1.0 NanoflowCommons\n'
  printf '#!/usr/bin/env bash\ncase " $* " in *" --no-baseline "*) cp %s/step1-adds/App.mpr "$1"; exit 0;; esac\nsed -n "/step 2: NanoflowCommons/,/heavy-lock/p" %s | grep -v -e heavy-lock -e "== step"; exit 1\n' "$S" "$LAB/e5/run2/work/stepupdate-1.out" > $S/fe5.sh
  UPG_UPDATE_CMD="bash $S/fe5.sh {mpr}" \
    ctl field-e5b-stepupdate-pre918-baseline-pass 0 'NanoflowCommons cannot serve as the local-edit baseline' 'committed' -- bash $B/stepupdate.sh $S/fe5 $S/fe5.plan
else
  skip field-e4-stepupdate-logic-edits-catch "no $LAB"; skip field-e5b-stepupdate-pre918-baseline-pass "no $LAB"
fi
if [ -f "$LAB/e5/run3/app/.stepupdate/step7-TaskQueueHelpers.log" ] && [ -f "$LAB/f1/runs/e6/work/stepupdate-post.log" ]; then
  # field E7-1: the real TaskQueueHelpers no-baseline route (E7 step 7) with --force-ui must not claim saved edits
  L7=$LAB/e5/run3/app/.stepupdate/step7-TaskQueueHelpers.log
  printf '#!/usr/bin/env bash\ncase " $* " in *" --no-baseline "*) sed -n "/^\[heavy-lock\]/,\$p" %s | sed 1d | grep -v heavy-lock; cp %s/step1-adds/App.mpr "$1"; exit 0;; esac\nsed "/^\[heavy-lock\]/,\$d" %s; exit 1\n' "$L7" "$S" "$L7" > $S/fe7.sh
  newapp fe7 '117272 3.1.0 TaskQueueHelpers\n'
  UPG_UPDATE_CMD="bash $S/fe7.sh {mpr}" \
    ctl field-e7-stepupdate-unsaved-catch 2 'UNSAVED: TaskQueueHelpers updated through --no-baseline and saved 0 files' '!saved edits for replay' -- bash $B/stepupdate.sh $S/fe7 $S/fe7.plan --force-ui TaskQueueHelpers
  newapp fe7b '117272 3.1.0 TaskQueueHelpers\n'
  UPG_UPDATE_CMD="bash $S/fe7.sh {mpr}" \
    ctl field-e7-stepupdate-nobaseline-pass 0 'TaskQueueHelpers cannot serve as the local-edit baseline' 'committed' '!UNSAVED' -- bash $B/stepupdate.sh $S/fe7b $S/fe7b.plan
  # field E6-13: the real post-convert refusal (Atlas_NativeMobile_Content, 22 elements could not be read) is a refusal,
  # and the E6 history shows it convert-made (git log only, the evidence repo is not touched)
  newapp fe6 '117175 3.2.1 Atlas_NativeMobile_Content\n'
  UPG_UPDATE_CMD="sed -n '/step 2: Atlas_NativeMobile/,/heavy-lock/p' $LAB/f1/runs/e6/work/stepupdate-post.log | grep -v -e heavy-lock -e '== step'; exit 1" \
    ctl field-e6-stepupdate-unread-catch 2 'could not be read' 'STOP: update of Atlas_NativeMobile_Content refused, elements could not be read' -- bash $B/stepupdate.sh $S/fe6 $S/fe6.plan
  E6A=$LAB/f1/runs/e6/app
  ctl field-e6-convertmade-pass 0 '^CONVERT-MADE: GoogleAuthenticator was installed pristine at 1cb33f2' -- bash $B/convertmade.sh $E6A GoogleAuthenticator 3866574
  ctl field-e6-convertmade-native-pass 0 '^CONVERT-MADE: Atlas_NativeMobile_Content' -- bash $B/convertmade.sh $E6A Atlas_NativeMobile_Content 99b160e
  ctl field-e6-convertmade-repair-catch 1 '^LOCAL: after the pristine install of Atlas_Core' 'repair: jardedupe' -- bash $B/convertmade.sh $E6A Atlas_Core 9cd4160
  ctl field-e6-convertmade-noconvert-catch 1 '^LOCAL: no convert commit' -- bash $B/convertmade.sh $E6A CSV 4826603
else
  skip field-e7-stepupdate-unsaved-catch "no E7/E6 evidence"; skip field-e6-convertmade-pass "no E7/E6 evidence"
fi
# field batch 1 (T5-9, T7-12): the workers' real localedits reports and app history subjects, from their run branches
# (read only with git show). The history is rebuilt from the subjects (T5: evidence/app-gitlog.txt; T7: JOURNAL
# "original", convert, the NanoflowCommons and Administration steps); files per commit are the subject's kind.
RG=$(cd "$TK/.." && pwd)
if git -C "$RG" rev-parse -q --verify origin/runs/t5-visual-inspection > /dev/null && git -C "$RG" rev-parse -q --verify origin/runs/t7-quality-inspection > /dev/null; then
  FB=$T/fb1; mkdir -p $FB
  git -C "$RG" show origin/runs/t5-visual-inspection:runs/t5-visual-inspection/evidence/localedits.json > $FB/t5.json
  git -C "$RG" show origin/runs/t7-quality-inspection:runs/t7-quality-inspection/evidence/localedits.json > $FB/t7.json
  fbrepo() {  # fbrepo NAME < "<hash> <subject>" lines newest first: one commit per line, oldest first
    local r=$FB/$1; rm -rf $r; mkdir -p $r; cp $M/base/App.mpr $r/App.mpr
    (cd $r && git init -q && tac | while read -r h s; do
       case "$s" in original*) git add App.mpr;;
         gitignore*) echo "$h" >> .gitignore; git add .gitignore;;
         build:*) mkdir -p javasource/m; echo "$h" >> javasource/m/A.java; git add javasource;;
         *) echo "$h" >> App.mpr.txt; git add App.mpr.txt;; esac
       git commit -qm "$s"; git tag "x$h"; done)
  }
  git -C "$RG" show origin/runs/t5-visual-inspection:runs/t5-visual-inspection/evidence/app-gitlog.txt | fbrepo t5
  # the workers ran localedits without --mxcli-diff: the history and the offline layers are clean, but no element
  # contents were compared, so MendixSSO stays LOCAL (its JAVA_ACTION refusal is usercode.py's case, T5-9)
  ctl field-t5-convertmade-mendixsso-nodiff-catch 1 '^LOCAL: no .step: MendixSSO. commit, and the pre-convert localedits .*element contents not compared' '!CONVERT-MADE' -- bash $B/convertmade.sh $FB/t5 MendixSSO xdcf2d29 --localedits $FB/t5.json
  python3 -c "import json,sys; r=json.load(open(sys.argv[1])); [x.update(elements={'verified':True,'modified':[],'unknown':[],'onlyInstalled':[]},elements_error=None) for x in r]; json.dump(r,open(sys.argv[2],'w'))" $FB/t5.json $FB/t5d.json
  ctl field-t5-convertmade-mendixsso-pass 0 '^CONVERT-MADE: MendixSSO has no step commit; source: pre-convert localedits .*MendixSSO 4\.1\.0: domain model unchanged' -- bash $B/convertmade.sh $FB/t5 MendixSSO xdcf2d29 --localedits $FB/t5d.json
  ctl field-t5-convertmade-head-catch 1 '^LOCAL: no .step: MendixSSO. commit, and after the original commit' 'fix brand-variables partial' '!build: gate build' -- bash $B/convertmade.sh $FB/t5 MendixSSO HEAD --localedits $FB/t5.json
  ctl field-t5-convertmade-bedrock-catch 1 '^LOCAL: .*compared with a proxy \(4\.0\.0\)' -- bash $B/convertmade.sh $FB/t5 AmazonBedrockConnector xdcf2d29 --localedits $FB/t5.json
  printf '%s\n' 'c4 step: Administration 4.1.0 (stepupdate, idcheck PASS)' 'c3 step: NanoflowCommons 5.2.1 (stepupdate, idcheck PASS)' 'c2 convert' 'c1 original' | fbrepo t7
  ctl field-t7-convertmade-communitycommons-nodiff-catch 1 '^LOCAL: .*element contents not compared' -- bash $B/convertmade.sh $FB/t7 CommunityCommons --localedits $FB/t7.json
  python3 -c "import json,sys; r=json.load(open(sys.argv[1])); [x.update(elements={'verified':True,'modified':[],'unknown':[],'onlyInstalled':[]},elements_error=None) for x in r]; json.dump(r,open(sys.argv[2],'w'))" $FB/t7.json $FB/t7d.json
  ctl field-t7-convertmade-communitycommons-pass 0 '^CONVERT-MADE: CommunityCommons has no step commit; source: pre-convert localedits .*CommunityCommons 10\.0\.5' -- bash $B/convertmade.sh $FB/t7 CommunityCommons --localedits $FB/t7d.json
  ctl field-t7-convertmade-tcconnector-catch 1 '^LOCAL: .*15 domain rows' -- bash $B/convertmade.sh $FB/t7 TcConnector --localedits $FB/t7.json
  ctl field-t7-convertmade-unknown-catch 1 '^LOCAL: .*UNKNOWN \(package not readable\)' -- bash $B/convertmade.sh $FB/t7 Viewer3D_TC --localedits $FB/t7.json
else
  skip field-t5-convertmade-mendixsso-pass "no origin/runs/t5-visual-inspection or t7 ref"
fi
unset UPG_UPDATE_CMD

# --- gate: screenshots old vs new (E4 / E5b: empty dashboard charts passed every other rung) ------------------------------
python3 $here/lib/mkshots.py $T/shots > /dev/null
SH=$T/shots
ctl shotdiff-empty-catch 1 '^REVIEW +shots-Administrator/dashboard.*empty now' -- python3 $B/shotdiff.py $SH/old $SH/empty
# NR1-25: a lost caption and a doubled paging text are a few pixels; the visible text beside the shot catches them
ctl shotdiff-text-lost-catch 1 '^REVIEW +shots-Administrator/overview.*visible text changed: lost status; new select' -- python3 $B/shotdiff.py $SH/textold $SH/textlost
ctl shotdiff-text-doubled-catch 1 '^REVIEW +shots-Administrator/overview.*visible text changed: new currently, of, showing, to' -- python3 $B/shotdiff.py $SH/textold $SH/textdup
ctl shotdiff-text-same-pass 0 '^PASS +shots-Administrator/overview.*text same' '!^REVIEW' -- python3 $B/shotdiff.py $SH/textold $SH/textsame
ctl shotdiff-text-one-side-pass 0 '^PASS +shots-Administrator/overview' '!text same' -- python3 $B/shotdiff.py $SH/textold $SH/textnone
ctl shotdiff-same-pass 0 'REVIEW 0' '!^REVIEW' -- python3 $B/shotdiff.py $SH/old $SH/same
ctl shotdiff-missing-invalid 2 '^INVALID +shots-Administrator/dashboard.*no NEW screenshot' -- python3 $B/shotdiff.py $SH/old $SH/missing
ctl shotdiff-notreached-invalid 2 '^INVALID .*NOT-REACHED' -- python3 $B/shotdiff.py $SH/old $SH/notreach
ctl shotdiff-size-catch 1 '^REVIEW .*page size 480x360 -> 480x560' -- python3 $B/shotdiff.py $SH/old $SH/taller
echo 'shots-*/dashboard-* # control: charts removed on purpose' > $T/shot-accept.txt
ctl shotdiff-accept-pass 0 '^PASS\* .*accepted: control' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept.txt
echo 'shots-*/dashboard-*' > $T/shot-accept-noreason.txt
ctl shotdiff-accept-needs-reason 1 'has no reason' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept-noreason.txt
ctl shotdiff-nopil-catch 1 '^REVIEW .*empty now' -- python3 -S $B/shotdiff.py $SH/old $SH/empty
ctl shotdiff-nopil-pass 0 'REVIEW 0' -- python3 -S $B/shotdiff.py $SH/old $SH/same
# E6-17: a screenshot of a page still loading is INVALID, never compared (by file name and by the progress bar itself)
ctl shotdiff-loading-pixel-catch 2 '^INVALID .*dashboard.*loading indicator in the NEW \(progress bar' -- python3 $B/shotdiff.py $SH/old $SH/loading
ctl shotdiff-loading-name-catch 2 '^INVALID .*dashboard.*NEW screenshot taken while the page was still loading' -- python3 $B/shotdiff.py $SH/old $SH/loadname
ctl shotdiff-loading-nopil-catch 2 '^INVALID .*progress bar' -- python3 -S $B/shotdiff.py $SH/old $SH/loading
ctl shotdiff-loading-divider-pass 0 '^PASS +shots-Administrator/divider' '!INVALID [1-9]' -- python3 $B/shotdiff.py $SH/divider-old $SH/divider-new
# T5-18 / T6-15: the detector fires on BOTH sides at the same row of two equal images (a file-upload field, a static
# card line): REVIEW, closable after a look, never INVALID-for-ever. Real pairs from the batch-1 runs T5 and T6.
SF=$FX/shots
shasum12() { python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:12])" "$1"; }
ctl shotdiff-both-sides-indicator-review 1 '^REVIEW +shots-Administrator/smoke-Settings_.*indicator on both sides, images equal: OLD \(progress bar at y=250\) and NEW \(progress bar at y=250\)' 'new @sha256:[0-9a-f]{12}' '^screens: 0 PASS, 0 PASS\*, 1 REVIEW, 0 INVALID' -- python3 $B/shotdiff.py $SF/t5-settings/old $SF/t5-settings/new
ctl shotdiff-both-sides-indicator-t6-review 1 '^REVIEW +shots-DepartmentManager/smoke-Home_.*indicator on both sides, images equal: .*y=302' -- python3 $B/shotdiff.py $SF/t6-dm-dashboard/old $SF/t6-dm-dashboard/new
echo "shots-Administrator/smoke-Settings_* @sha256:$(shasum12 $SF/t5-settings/new/shots-Administrator/smoke-Settings_MasterData.NAV_Settings.png) # T5-18: opened both, identical; the detector reads the file-upload field" > $T/shot-accept-t5.txt
ctl shotdiff-both-sides-indicator-accept-pass 0 '^PASS\* +shots-Administrator/smoke-Settings_.*accepted: T5-18' '!unpinned' '^screens: 0 PASS, 1 PASS\*' -- python3 $B/shotdiff.py $SF/t5-settings/old $SF/t5-settings/new --accept $T/shot-accept-t5.txt
echo "shots-DepartmentManager/smoke-Home_* @sha256:$(shasum12 $SF/t6-dm-dashboard/new/shots-DepartmentManager/smoke-Home_Masterdata.NAV_Dashboard_DepartmentManager.png) # T6-15: opened both, fully rendered; a static line in a dashboard card" > $T/shot-accept-t6.txt
ctl shotdiff-both-sides-indicator-t6-accept-pass 0 '^PASS\* +shots-DepartmentManager/smoke-Home_.*accepted: T6-15' -- python3 $B/shotdiff.py $SF/t6-dm-dashboard/old $SF/t6-dm-dashboard/new --accept $T/shot-accept-t6.txt
ctl shotdiff-both-sides-indicator-synthetic-review 1 '^REVIEW .*dashboard.*indicator on both sides, images equal' -- python3 $B/shotdiff.py $SH/barboth-old $SH/barboth-new
# the bar on both sides but the page changed, or on one side only: still INVALID, and no accept line closes it
echo 'shots-*/dashboard-* # control: an accept line must not close this' > $T/shot-accept-any.txt
ctl shotdiff-both-sides-indicator-changed-catch 2 '^INVALID .*dashboard.*loading indicator in the OLD .* and NEW .*accept line refused' -- python3 $B/shotdiff.py $SH/barboth-old $SH/barmoved-new --accept $T/shot-accept-any.txt
ctl shotdiff-loading-accept-refused-catch 2 '^INVALID .*dashboard.*still loading \(-LOADING\).*accept line refused' '!^PASS\* .*dashboard' -- python3 $B/shotdiff.py $SH/old $SH/loadname --accept $T/shot-accept-any.txt
ctl shotdiff-onesided-indicator-accept-refused-catch 2 '^INVALID .*dashboard.*loading indicator in the NEW .*accept line refused' -- python3 $B/shotdiff.py $SH/old $SH/loading --accept $T/shot-accept-any.txt
# T7-22: a -STUCK shot (indicator stayed, DOM still) is INVALID, and an accept line after a look closes it (PASS*)
ctl shotdiff-stuck-catch 2 '^INVALID .*dashboard.*STUCK: NEW loading indicator never went away' -- python3 $B/shotdiff.py $SH/old $SH/stuck
echo "shots-*/dashboard-* @sha256:$(shasum12 $SH/stuck/shots-Administrator/dashboard-Administrator-step1-STUCK.png) # control: opened both, the empty grid keeps its progress bar" > $T/shot-accept-stuck.txt
ctl shotdiff-stuck-accept-pass 0 '^PASS\* .*dashboard.*STUCK.*accepted: control: opened both' -- python3 $B/shotdiff.py $SH/old $SH/stuck --accept $T/shot-accept-stuck.txt
# N1-8: a one-sided -STUCK on a pair that is identical below the top 10 px is the same page, not judged per side
ctl shotdiff-stuck-onesided-equal-pass 0 '^PASS +shots-Administrator/dashboard.*equal below the top 10 px' '!INVALID [1-9]' -- python3 $B/shotdiff.py $SH/stuckeq-old $SH/stuckeq-new
ctl shotdiff-stuck-onesided-equal-new-pass 0 '^PASS +shots-Administrator/dashboard.*NEW named -STUCK' -- python3 $B/shotdiff.py $SH/old $SH/stuckeq-newside-new
ctl shotdiff-stuck-onesided-equal-nopil-pass 0 '^PASS +shots-Administrator/dashboard.*equal below' -- python3 -S $B/shotdiff.py $SH/stuckeq-old $SH/stuckeq-new
ctl shotdiff-stuck-onesided-different-catch 2 '^INVALID .*dashboard.*STUCK: OLD loading indicator never went away' -- python3 $B/shotdiff.py $SH/stuckdiff-old $SH/stuckdiff-new
# B4N1-14: the STUCK and one-sided STUCK lines say how much of the page is there (ink), so a blank page is visible
ctl shotdiff-stuck-ink-shown 2 '^INVALID .*dashboard.*STUCK: NEW .*ink OLD [0-9.]+% NEW [0-9.]+%' -- python3 $B/shotdiff.py $SH/old $SH/stuck
ctl shotdiff-stuck-onesided-ink-shown 0 '^PASS +shots-Administrator/dashboard.*indicator only, ink [0-9.]+%\)' -- python3 $B/shotdiff.py $SH/stuckeq-old $SH/stuckeq-new
if git -C "$RG" rev-parse -q --verify origin/runs/b4-opcenter-ef-11 > /dev/null; then
  # field (Opcenter EF 10.24 to 11, B4N1-14): rendered StarterKit pages named -STUCK under the UMC session-renew bar vs
  # the truly blank home pages; the ink share tells them apart (0.3% blank, 12-50% rendered)
  FB4=$T/field/b4n1; mkdir -p $FB4
  git -C "$RG" archive origin/runs/b4-opcenter-ef-11 runs/b4-opcenter-ef-11/evidence/baseline/smoke-before-shots \
    runs/b4-opcenter-ef-11/evidence/gate-r2/smoke-after-shots | tar -x -C $FB4
  FB4E=$FB4/runs/b4-opcenter-ef-11/evidence
  ctl field-b4n1-stuck-ink-catch 2 '^INVALID +shots-User/smoke-home_page_.*STUCK: OLD and NEW .*ink OLD 0\.3% NEW 0\.3%' \
    '^PASS +shots-User/smoke-Starter_Kit_Contents_.*ink 12\.5%\)' '^screens: 4 PASS, 0 PASS\*, 0 REVIEW, 2 INVALID' -- python3 $B/shotdiff.py $FB4E/baseline/smoke-before-shots $FB4E/gate-r2/smoke-after-shots
else
  skip field-b4n1-stuck-ink-catch "no origin/runs/b4-opcenter-ef-11 ref"
fi
ctl shotdiff-stuck-equal-loading-still-catch 2 '^INVALID .*dashboard.*still loading \(-LOADING\)' -- python3 $B/shotdiff.py $SH/old $SH/stuckeq-loading-new
# T7-28: an accept pinned to one image does not accept another image of the same name (the next rung)
echo 'shots-*/dashboard-* @sha256:000000000000 # control: written for the rung-1 image' > $T/shot-accept-pin.txt
ctl shotdiff-accept-hash-mismatch-catch 1 '^REVIEW +shots-Administrator/dashboard.*empty now.*accept line pinned to another image @sha256:000000000000' '!^PASS\* .*dashboard' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept-pin.txt
echo "shots-*/dashboard-* @sha256:$(shasum12 $SH/empty/shots-Administrator/dashboard-Administrator-step1.png) # control: charts removed on purpose" > $T/shot-accept-pinok.txt
ctl shotdiff-accept-hash-match-pass 0 '^PASS\* .*dashboard.*accepted: control' '!unpinned' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept-pinok.txt
ctl shotdiff-accept-unpinned-warns 0 '^PASS\* .*dashboard.*unpinned accept: add @sha256:[0-9a-f]{12}' '1 unpinned accepts' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept.txt
# a mistyped pin (short hash) used to fold into the pattern and match nothing, silently: it is refused
echo 'shots-*/dashboard-* @sha256:abc # control: a short hash' > $T/shot-accept-badpin.txt
ctl shotdiff-accept-badpin-catch 1 'the pin must be' -- python3 $B/shotdiff.py $SH/old $SH/empty --accept $T/shot-accept-badpin.txt
# B4T2-17: a page with per-run content (a created row's id) gets a new hash every run, so a plain pin never holds twice
# and workers fell back to unpinned accepts. A masked pin holds outside the mask, is bounded (25%) and is counted apart.
RA=$SH/runid-a/shots-Administrator/dashboard-Administrator-step1.png
echo "shots-*/dashboard-* @sha256:$(shasum12 $RA) # control: pinned plain on run a" > $T/shot-accept-runid-plain.txt
ctl shotdiff-runid-plain-pin-catch 1 '^REVIEW +shots-Administrator/dashboard.*accept line pinned to another image' '!^PASS\* .*dashboard' -- python3 $B/shotdiff.py $SH/old $SH/runid-b --accept $T/shot-accept-runid-plain.txt
MH=$(python3 $B/shotdiff.py --hash $RA --mask 300,60,60,16 2>/dev/null | sed -n 's/.*@sha256:\([0-9a-f]\{12\}\).*/\1/p')
ctl shotdiff-hash-mask-prints 0 '^@mask:300,60,60,16 @sha256:[0-9a-f]{12} +\(0\.6% of the image not pinned\)' -- python3 $B/shotdiff.py --hash $RA --mask 300,60,60,16
echo "shots-*/dashboard-* @mask:300,60,60,16 @sha256:$MH # control: the per-run id masked" > $T/shot-accept-mask.txt
ctl shotdiff-mask-pin-pass 0 '^PASS\* +shots-Administrator/dashboard.*accepted: control: the per-run id masked.*masked accept: 0\.6% not pinned' '\(1 masked accepts\)' '!unpinned' -- python3 $B/shotdiff.py $SH/old $SH/runid-b --accept $T/shot-accept-mask.txt
ctl shotdiff-mask-pin-nopil-pass 0 '^PASS\* +shots-Administrator/dashboard.*masked accept' -- python3 -S $B/shotdiff.py $SH/old $SH/runid-b --accept $T/shot-accept-mask.txt
ctl shotdiff-mask-outside-catch 1 "^REVIEW +shots-Administrator/dashboard.*masked line pinned to another image @sha256:$MH; this image masked @sha256:[0-9a-f]{12}" '!^PASS\* .*dashboard' -- python3 $B/shotdiff.py $SH/old $SH/runid-moved --accept $T/shot-accept-mask.txt
echo "shots-*/dashboard-* @mask:0,0,480,200 @sha256:$MH # control: a mask over half the page" > $T/shot-accept-mask-wide.txt
ctl shotdiff-mask-too-wide-catch 1 '^REVIEW +shots-Administrator/dashboard.*mask covers 56% of the image, more than 25%: refused' '!^PASS\* .*dashboard' -- python3 $B/shotdiff.py $SH/old $SH/runid-b --accept $T/shot-accept-mask-wide.txt
ctl shotdiff-hash-mask-too-wide-catch 1 'more than 25%' -- python3 $B/shotdiff.py --hash $RA --mask 0,0,480,200
echo "shots-*/dashboard-* @mask:300,60,60,16 # control: a mask without a pin" > $T/shot-accept-mask-nopin.txt
ctl shotdiff-mask-needs-pin-catch 1 'a mask needs the masked pin' -- python3 $B/shotdiff.py $SH/old $SH/runid-b --accept $T/shot-accept-mask-nopin.txt
# T1-24: NOT-REACHED on both sides used to pair and PASS; it is INVALID BASELINE DEFECT, closable only after a look
ctl shotdiff-notreached-both-catch 2 '^INVALID .*dashboard.*BASELINE DEFECT: OLD step NOT-REACHED and NEW too' '!^PASS +shots-Administrator/dashboard' -- python3 $B/shotdiff.py $SH/nrboth-old $SH/nrboth-new
ctl shotdiff-notreached-both-accept-pass 0 '^PASS\* .*dashboard.*BASELINE DEFECT.*accepted: control' -- python3 $B/shotdiff.py $SH/nrboth-old $SH/nrboth-new --accept $T/shot-accept-any.txt
ctl shotdiff-notreached-new-accept-refused-catch 2 '^INVALID .*NEW step NOT-REACHED, OLD reached it.*accept line refused' -- python3 $B/shotdiff.py $SH/old $SH/notreach --accept $T/shot-accept-any.txt
if command -v node > /dev/null; then
  ctl settle-wait-catch 0 '^ok +progress bar never goes away -> not settled' '^ok +DOM keeps changing' '^ok +indicator stays, DOM still -> stuck' '^ok +indicator stays, DOM changing -> loading, not stuck' '!^FAIL' -- node $here/settle_control.js
  # B4N1-14: a thin top bar on a page with text is ignored (said); a blank page, another indicator or a changing DOM is not
  ctl settle-topbar-pass 0 '^ok +top bar only, page has text, DOM still -> settled' '^ok +top bar only, blank page -> stuck' '^ok +top bar plus a grid loading state -> stuck' '^ok +top bar, DOM still changing -> loading' '!^FAIL' -- node $here/settle_control.js
  ctl smokewalk-settle-pass 0 '^ok +pageSettled when loaders hidden' '^ok +pageSettled while progress bar shown' '!^FAIL' -- node $here/smokewalk_predicates.js
else skip settle-wait-catch "no node"; skip smokewalk-settle-pass "no node"; fi
# filecheck.js --compare: equal sides SAME, a different checksum or a side that did not finish DIFFERENT
if command -v node > /dev/null; then ctl filecheck-compare 0 '^SAME: upload, download' '^rc=0' '^DIFFERENT' '^  dl_sha: old "aa" new "bb"' '^  new side did not complete: login' '^rc=1' -- bash $here/filecheck_compare_control.sh
else skip filecheck-compare "no node"; fi
# run_journeys --compare --rejudge: a PASSing journey whose screen lost content is SCREEN REVIEW (journeys rung, item 1c)
J=$T/rj; mkdir -p $J/old/before $J/new/after
cp -R $SH/old/shots-Administrator $J/old/before/; cp -R $SH/empty/shots-Administrator $J/new/after/
# both journeys carry a measured effect record (E2E-9): without one, a PASS on both runs is EFFECT INVALID (exit 3)
for d in old/before new/after; do echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "PASS", "effects": [{"n": 1, "changed": {}}]}, "login-Administrator": {"role": "Administrator", "verdict": "PASS", "effects": [{"n": 1, "changed": {}}]}}, "roles": {}}' > $J/$d/summary.json; done
ctl journeys-screen-catch 1 'PASS +dashboard-Administrator .*SCREEN REVIEW' '!login-Administrator .*SCREEN' '^screens: 1 PASS, 0 PASS\*, 1 REVIEW, 0 INVALID' -- python3 $B/run_journeys.py x --label after --work $J/new --compare $J/old --rejudge
# T1-26 / T4-17: the screens line is printed when every pair passes too, so the gate can cite it
J2=$T/rj2; mkdir -p $J2/old/before $J2/new/after
cp -R $SH/old/shots-Administrator $J2/old/before/; cp -R $SH/same/shots-Administrator $J2/new/after/
cp $J/old/before/summary.json $J2/old/before/; cp $J/new/after/summary.json $J2/new/after/
# E2E-11: a compare run needs the journey-set hash on both sides and a denominator (or its waiver, then PASS*)
pinset() { for f in "$@"; do python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['journey_set']={'sha256': 'c0ffee'*10+'c0ff'}; json.dump(d, open(sys.argv[1], 'w'))" "$f"; done; }
pinset $J/old/before/summary.json $J/new/after/summary.json $J2/old/before/summary.json $J2/new/after/summary.json
NOACT=(--no-actions 'control: synthetic set, no model behind it')
ctl journeys-compare-screens-line-pass 0 '^screens: 2 PASS, 0 PASS\*, 0 REVIEW, 0 INVALID$' '^coverage: 1 PASS\* \(no denominator: control' '!coverage INVALID' -- python3 $B/run_journeys.py x --label after --work $J2/new --compare $J2/old --rejudge "${NOACT[@]}"
# an open pair that no journey owns still keeps the run red (it used to vanish from the verdict)
J3=$T/rj3; mkdir -p $J3/old/before $J3/new/after
cp -R $SH/old/shots-Administrator $J3/old/before/; cp -R $SH/empty/shots-Administrator $J3/new/after/
for d in old/before new/after; do echo '{"journeys": {"login-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $J3/$d/summary.json; done
ctl journeys-compare-screens-orphan-catch 1 '^screens: 1 PASS, 0 PASS\*, 1 REVIEW, 0 INVALID' -- python3 $B/run_journeys.py x --label after --work $J3/new --compare $J3/old --rejudge
ctl journeys-screen-accept-pass 0 '!SCREEN REVIEW' -- python3 $B/run_journeys.py x --label after --work $J/new --compare $J/old/before/summary.json --rejudge --shot-accept $T/shot-accept.txt "${NOACT[@]}"
ctl journeys-compare-path-catch 2 'no summary.json there.*nothing was run' -- python3 $B/run_journeys.py x --label after --work $J/new --compare $J/nothere --rejudge
# N1R2-8 / T2R3-11: INVALID only (SCREEN INVALID, a BASELINE DEFECT) exits 3 with its own verdict line, never 1 (FAIL)
J4=$T/rj4; mkdir -p $J4/old/before $J4/new/after; cp -R $SH/old/shots-Administrator $J4/old/before/
for d in old/before new/after; do echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $J4/$d/summary.json; done
ctl journeys-screen-invalid-only-catch 3 'PASS +dashboard-Administrator .*SCREEN INVALID' '^verdict: INVALID only \(exit 3\): .*1 SCREEN INVALID, 0 failing on the baseline' '!\[REGRESSION\]' -- python3 $B/run_journeys.py x --label after --work $J4/new --compare $J4/old --rejudge
J5=$T/rj5; mkdir -p $J5/old/before $J5/new/after
cp -R $SH/old/shots-Administrator $J5/old/before/; cp -R $SH/same/shots-Administrator $J5/new/after/
for d in old/before new/after; do echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "FAIL"}, "login-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $J5/$d/summary.json; done
ctl journeys-baseline-defect-advice-catch 3 'FAIL +dashboard-Administrator .*BASELINE DEFECT' '1 failing on the baseline' '^  baseline: dashboard-Administrator fail on the OLD app too: drop or fix these journeys' -- python3 $B/run_journeys.py x --label after --work $J5/new --compare $J5/old --rejudge
# a REGRESSION next to INVALIDs is still FAIL (exit 1): INVALID only is only what it says
J6=$T/rj6; mkdir -p $J6/old/before $J6/new/after; cp -R $SH/old/shots-Administrator $J6/old/before/
echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "PASS"}, "login-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $J6/old/before/summary.json
echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "FAIL"}, "login-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $J6/new/after/summary.json
ctl journeys-regression-beats-invalid-catch 1 'FAIL +dashboard-Administrator .*REGRESSION' '!verdict: INVALID only' -- python3 $B/run_journeys.py x --label after --work $J6/new --compare $J6/old --rejudge
# E6-20: a module-pages check with a page no entry point reaches is INVALID in the run, not a silent plan row
mkdir -p $T/rjne/after $T/gpl-ne $T/gpl-ok
echo '{"journeys": {"login-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $T/rjne/after/summary.json
echo '{"not_browser": [{"id": "module-pages:OQL", "targets": ["OQL.ExampleOQL_Result"], "no_entry": ["OQL.ExampleOQL_Result"], "why": "no entry point: NOT PROVED. No menu item reaches OQL.ExampleOQL_Result"}]}' > $T/gpl-ne/plan.json
echo '{"not_browser": [{"id": "module-pages:OQL", "targets": ["OQL.ExampleOQL_Result"], "no_entry": []}]}' > $T/gpl-ok/plan.json
ctl journeys-no-entry-catch 3 'module-pages:OQL' 'NOT PROVED' -- python3 $B/run_journeys.py $T/gpl-ne --label after --work $T/rjne --rejudge
ctl journeys-no-entry-reached-pass 0 '!module-pages:OQL' -- python3 $B/run_journeys.py $T/gpl-ok --label after --work $T/rjne --rejudge
# E7-3: a hand-written journey with "closes" turns a todo into that journey's verdict; without it the todo stays INVALID
mkdir -p $T/rjcl/after $T/gpl-cl
echo '{"todo": [{"id": "menu:Wizard", "why": "behind a wizard"}]}' > $T/gpl-cl/plan.json
echo '{"journeys": {"wizard-Administrator": {"role": "Administrator", "verdict": "PASS", "closes": ["menu:Wizard"]}}, "roles": {}}' > $T/rjcl/after/summary.json
ctl journeys-closes-todo-pass 0 'closed by wizard-Administrator' -- python3 $B/run_journeys.py $T/gpl-cl --label after --work $T/rjcl --rejudge
mkdir -p $T/rjcl2/after; echo '{"journeys": {"wizard-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' > $T/rjcl2/after/summary.json
ctl journeys-todo-open-catch 3 'menu:Wizard' 'todo: behind a wizard' -- python3 $B/run_journeys.py $T/gpl-cl --label after --work $T/rjcl2 --rejudge
mkdir -p $T/rjcl3/after; echo '{"journeys": {"wizard-Administrator": {"role": "Administrator", "verdict": "FAIL", "closes": ["menu:Wizard"]}}, "roles": {}}' > $T/rjcl3/after/summary.json
ctl journeys-closes-fail-catch 1 'menu:Wizard' -- python3 $B/run_journeys.py $T/gpl-cl --label after --work $T/rjcl3 --rejudge
# E7-3 / E5b-21 / E6-8 / E6-17: the engine COPY gets the settle wait, the topmost-popup click and the new verbs
if [ -f ${TOOLKIT_E2E:-$B/../vendor/e2e}/journey-runner.js ]; then
  ctl journeys-engine-patch-pass 0 '^ready: wait for the landing guard' '^shoot: wait for the page to settle' '^act: toggle/switch, select/reference/dropdown, row, menu, confirm' '^click: the widget in the topmost popup' '^fill: every shown row of a list' '^act: upload a generated file' '^ui: a step that asserts noDialog FAILs when a dialog is open' '!NOT applied' -- python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-copy
  ctl journeys-engine-syntax-pass 0 -- node --check $T/engine-copy/journey-runner.js
  # FN-7: the patched fill skips an optional fill whose input is not shown (an input in a list with no items)
  ctl journeys-engine-fill-optional-pass 0 'if \(!el && a\.optional\) \{ console\.log' -- cat $T/engine-copy/journey-runner.js
  # PR-P2 in the patched engine: a step that asserts noDialog FAILs when a dialog is open after its click
  ctl journeys-engine-nodialog-pass 0 "if \\(step\\.ui && step\\.ui\\.noDialog\\) \\{" "const said = await V\\.openDialog\\(page\\);" "said === null \\? 'PASS' : 'FAIL'" -- cat $T/engine-copy/journey-runner.js
  # PR-P3: the patched engine's row verb double-clicks and says so
  ctl journeys-engine-row-verb-pass 0 "a\\.dblclick \\? 'double-clicked' : 'clicked'" "a\\.dblclick \\? 'Double-click' : 'Click'" -- cat $T/engine-copy/journey-runner.js
  # PR-F39: the patched engine checks every match of the landing guard, not the first (a hidden snippet widget)
  ctl journeys-engine-ready-any-match-pass 0 'V\.reached\(page, page\.locator\(step\.ui\.ready\), 12000\)' '!locator\(step\.ui\.ready\)\.first' -- cat $T/engine-copy/journey-runner.js
  # PR-P4: the row verb's nth reaches the engine's note and sentence
  ctl journeys-engine-row-nth-pass 0 "clicked'\\} \\$\\{a\\.nth \\? 'row ' \\+ \\(a\\.nth \\+ 1\\) : 'the first row'\\} of \\$\\{a\\.widget\\}" "target: .\\$\\{a\\.nth \\? 'row ' \\+ \\(a\\.nth \\+ 1\\) : 'the first row'\\} of" -- cat $T/engine-copy/journey-runner.js
  mkdir -p $T/engine-old; sed 's/case .dismissModal.: await H.dismissModal(page); break;/case "dismiss": break;/' ${TOOLKIT_E2E:-$B/../vendor/e2e}/journey-runner.js > $T/engine-old/journey-runner.js
  for f in helpers.js config.js otel.js; do cp ${TOOLKIT_E2E:-$B/../vendor/e2e}/$f $T/engine-old/; done
  ctl journeys-engine-patch-drift-catch 1 '^NOT applied: act: toggle' -- env TOOLKIT_E2E=$T/engine-old python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-copy2
  # T7-10, T8-9: the login patches (LOGIN_PATH, "signed in" = no visible password input + no login URL + READY)
  ctl journeys-engine-login-page-home-patch-pass 0 '^login: open LOGIN_PATH' '^login: signed in only without a visible password input' "^loginOnce: 'already in the app' needs READY" '^loginOnce: wait until no password input is visible' '^navTo: also menu bars' '!NOT applied' -- python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-login
  ctl journeys-engine-login-syntax-pass 0 -- node --check $T/engine-login/helpers.js
  mkdir -p $T/engine-old-login; for f in journey-runner.js config.js otel.js; do cp ${TOOLKIT_E2E:-$B/../vendor/e2e}/$f $T/engine-old-login/; done
  sed "s|cfg.baseUrl + '/', { waitUntil|cfg.baseUrl + '/index.html', { waitUntil|" ${TOOLKIT_E2E:-$B/../vendor/e2e}/helpers.js > $T/engine-old-login/helpers.js
  ctl journeys-engine-login-patch-drift-catch 1 '^NOT applied: login: open LOGIN_PATH .*helpers.js text changed' -- env TOOLKIT_E2E=$T/engine-old-login python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-copy3
  # behaviour, in a real browser: an anonymous home that is a login PAGE (local HTTP server, no Mendix needed)
  PWNP=${PLAYWRIGHT_NODE_PATH:-$HOME/mendix-playwright/node_modules}
  NODE_PATH=$PWNP node -e "require('playwright')" 2> /dev/null || PWNP=$(npm root -g 2> /dev/null)
  if NODE_PATH=$PWNP node -e "process.exit(require('fs').existsSync(require('playwright').chromium.executablePath()) ? 0 : 1)" 2> /dev/null; then
    mkdir -p $T/engine-plain; cp ${TOOLKIT_E2E:-$B/../vendor/e2e}/*.js $T/engine-plain/
    ctl journeys-engine-login-page-home-catch 0 '^ok +unpatched engine on / reports a false login PASS' '^ok +patched engine on / gives no false PASS' '^ok +patched engine on /login.html signs in' '^ok +patched engine already in, READY union with a hidden first match recognises the app' '!^FAIL' -- env NODE_PATH=$PWNP node $here/login_page_home_control.js $T/engine-login $T/engine-plain
    # T8R B2-2: the landing guard waits, and a 0-height data view with drawn content counts; hidden or empty does not
    ctl journeys-landing-guard-catch 0 '^ok +old check on a 0-height data view: false' '^ok +old check on a late guard: false' '^ok +old check on a hidden first match: false' '^ok +old check on a union, hidden Set URL first: false' '!^FAIL' -- env NODE_PATH=$PWNP node $here/landing_guard_control.js
    ctl journeys-landing-guard-pass 0 '^ok +reached: union, hidden Set URL first: true' '^ok +reached: union, Set URL only: false' '^ok +reached: 0-height data view, drawn: true' '^ok +reached: late guard' '^ok +reached: guard display:none: false' '^ok +reached: 0-height wrapper, empty: false' '^ok +reached: hidden first, shown popup: true' '^ok +reached: every match hidden: false' '!^FAIL' -- env NODE_PATH=$PWNP node $here/landing_guard_control.js
  else skip journeys-engine-login-page-home-catch "no playwright with a browser"; skip journeys-landing-guard-catch "no playwright with a browser"; skip journeys-landing-guard-pass "no playwright with a browser"; fi
else skip journeys-engine-patch-pass "no shared journey engine"; skip journeys-engine-syntax-pass "no shared journey engine"; skip journeys-engine-ready-any-match-pass "no shared journey engine"; skip journeys-engine-patch-drift-catch "no shared journey engine"
  skip journeys-engine-login-page-home-patch-pass "no shared journey engine"; skip journeys-engine-login-page-home-catch "no shared journey engine"; fi
# FN-3..FN-7, FN-11 (field finish pass): generator fixes on fake models (controls/generator_fn_control.py)
GFN="python3 $here/generator_fn_control.py"
ctl gen-fn-in-list-pass 0 '^ok +fields keep a list input, marked' '^ok +in_list fill is optional' '^ok +in_list fill has no own-row check' '^ok +fields leave a plain input unmarked' '!^FAIL' -- $GFN
ctl gen-fn-in-list-plain-catch 0 '^ok +plain fill is not optional' '^ok +plain fill keeps its own-row check' '!^FAIL' -- $GFN
ctl gen-fn-url-attribute-pass 0 '^ok +ImageURL is filled as a URL' '^ok +callback_uri is filled as a URL' '^ok +URL value too long for the column falls back' '!^FAIL' -- $GFN
ctl gen-fn-url-attribute-plain-catch 0 '^ok +Surname is not taken for a URL' '!^FAIL' -- $GFN
ctl action-inventory-branch-entry-pass 0 '^ok +branch entry lands on the parameter-free page' '^ok +branch page no click reaches keeps the entry, marked' '^ok +branch page a click reaches is reached by the click' '!^FAIL' -- $GFN
ctl action-inventory-branch-entry-plain-catch 0 '^ok +every branch page needs an object: all kept as before' '^ok +an entry that shows one page is untouched' '!^FAIL' -- $GFN
ctl impact-map-dropdown-container-pass 0 '^ok +Dropdown container is a popup menu' '^ok +Pop-up menu is a popup menu' '^ok +Gallery is no popup menu' '!^FAIL' -- $GFN
ctl impact-map-js-snippet-pass 0 '^ok +JavaScript HTML snippet draws nothing' '^ok +HTML content snippet draws something' '^ok +another widget draws something' '!^FAIL' -- $GFN
ctl gen-fn-save-menu-guard-pass 0 '^ok +save lands on the menu that holds the opener' '^ok +save lands on the opener when no menu holds it' '!^FAIL' -- $GFN
if command -v node > /dev/null; then
  ctl journeys-verbs-catch 0 '^ok +select missing option catch' '^ok +toggle stuck catch' '^ok +confirm without dialog catch' '^ok +topmost picks the popup button' '^ok +topmost picks the page widget over the layout one' '^ok +select first on empty list catch' '^ok +row on empty list catch' '^ok +row on missing list catch' '!^FAIL' -- node $here/journey_verbs_control.js
  ctl journeys-verbs-pass 0 '^ok +select exact option' '^ok +toggle to true' '^ok +confirm clicks primary' '^ok +select first option' '^ok +row clicks the first grid row' '^ok +topmost skips a hidden page widget' '!^FAIL' -- node $here/journey_verbs_control.js
  # FN-4, FN-12, FN-13: a Dropdown container is opened by its toggle; a read-only reference selector holding a value is
  # complete; a message box that answers a confirm in the same place is an answer, an error box is not
  ctl journeys-verbs-fn-pass 0 '^ok +confirm answered by a new dialog' '^ok +select read-only holding a value, first asked' '^ok +select read-only holding the wanted value' '^ok +menu opens a dropdown container' '^ok +menu dropdown container already open' '!^FAIL' -- node $here/journey_verbs_control.js
  ctl journeys-verbs-fn-catch 0 '^ok +confirm answered by an error dialog catch' '^ok +confirm same dialog stays open catch' '^ok +select read-only other value catch' '^ok +select read-only empty catch' '^ok +menu dropdown container that stays closed catch' '!^FAIL' -- node $here/journey_verbs_control.js
  # B4T2-16: a hidden first match does not lose its selector; rows that render but match nothing are an instrument gap
  ctl journeys-verbs-row-instrument-gap-catch 0 '^ok +row renders but no selector catch: .*an instrument gap .*not a fixture gap' '!^FAIL' -- node $here/journey_verbs_control.js
  ctl journeys-verbs-row-hidden-first-pass 0 '^ok +row skips a hidden first row' '!^FAIL' -- node $here/journey_verbs_control.js
  # B4T2-11: the tab verb opens a tab page and fails when the tab never becomes active (wired once run_journeys dispatches it)
  ctl journeys-verbs-tab-pass 0 '^ok +tab opens the tab page' '!^FAIL' -- node $here/journey_verbs_control.js
  ctl journeys-verbs-tab-catch 0 '^ok +tab stays inactive catch' '^ok +tab missing catch' '!^FAIL' -- node $here/journey_verbs_control.js
  # PR-F27: the 11.12.5 date picker placeholder is "dd mmm yyyy"; "1/15/2027" typed there is "Invalid date"
  ctl journeys-verbs-date-pass 0 '^ok +dateAs follows the placeholder: returned "15 Jan 2027"' '^ok +dateAs time after hours is minutes: returned "15-01-2027 12:00"' '!^FAIL' -- node $here/journey_verbs_control.js
  ctl journeys-verbs-date-catch 0 '^ok +dateAs leaves a text placeholder catch: returned "1/15/2027"' '^ok +dateAs leaves a non-date value catch: returned "U-1-2"' '!^FAIL' -- node $here/journey_verbs_control.js
  # B4T2-16 in a real browser: Data grid 2 markup (display: contents rows, role gridcell / cell, late rows, empty placeholder)
  VBNP=${PLAYWRIGHT_NODE_PATH:-$HOME/mendix-playwright/node_modules}
  NODE_PATH=$VBNP node -e "require('playwright')" 2> /dev/null || VBNP=$(npm root -g 2> /dev/null)
  if NODE_PATH=$VBNP node -e "process.exit(require('fs').existsSync(require('playwright').chromium.executablePath()) ? 0 : 1)" 2> /dev/null; then
    VB="env NODE_PATH=$VBNP node $here/verbs_browser_control.js"
    ctl journeys-verbs-browser-row-pass 0 '^ok +dg2 rows \(display: contents\): .*clicked row1' '^ok +dg2 rows load late' '^ok +dg2 cells with role="cell"' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-row-catch 0 '^ok +dg2 empty placeholder: threw .*the list is empty, a fixture gap' '^ok +rows render, unknown markup: threw .*an instrument gap' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-row-nth-pass 0 '^ok +dg2 row nth: row 3 clicked' '^ok +dg2 row nth with dblclick: row 2' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-row-nth-catch 0 '^ok +dg2 row nth: row 3 of 2 shown: threw: .*row 3 asked for, the list shows 2: .*a fixture gap' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-row-dblclick-pass 0 '^ok +dg2 double-click trigger: dblclick opens the row: clicked row1' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-row-dblclick-catch 0 '^ok +dg2 double-click trigger: a single click opens nothing: clicked nothing' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-tab-pass 0 '^ok +tab opens a tab page: active, actionButton1 visible true' '^ok +tab never activates: threw' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-item-pass 0 '^ok +item clicks the asked list item: .*clicked item3' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-item-catch 0 '^ok +item count differs from model: threw .*cannot be told apart' '!^FAIL' -- $VB
    # PR-F27: Combo box 2.10 (Atlas_Web_Content on 11.12.5) renders a 0 px input; the menu opens from the input container
    ctl journeys-verbs-browser-combo-pass 0 '^ok +combo 2\.10 hidden input: returned Marketing, shows Marketing' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-combo-catch 0 '^ok +combo menu never opens: threw .*never opened.*an instrument gap' '!^FAIL' -- $VB
    # PR-F40: PopupMenu as captured on the 10.24 Purchase Request: the name is on the open list, the trigger unnamed
    ctl journeys-verbs-browser-menu-pass 0 '^ok +menu named on the list: returned pop_upMenu5 opened' '^ok +menu behind a decoy menu: returned pop_upMenu5 opened \(trigger 2 of 2\).*decoy menu open 0' '^ok +menu already open: returned pop_upMenu5 already open.*clicks 0' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-fill-pass 0 '^ok +fill behind a hidden tab field: filled reason=Approval test 1013051833 \| Leave a comment...=U-run-1' '^ok +fill in the dialog first: .*In the dialog=U-run-1' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-fill-catch 0 '^ok +fill only a hidden field: no shown match' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-menu-catch 0 '^ok +menu never opens: threw pop_upMenu5: none of the 1 pop-up menu trigger' '!^FAIL' -- $VB
    # PR-F42: the captured Task Inbox (own record by ${RUN_ID}) and the captured message box over "Complete PO(s)"
    ctl journeys-verbs-browser-near-pass 0 '^ok +near picks the own record: picked Appr F42B' '^ok +near skips a longer id: picked Appr F42B' '^ok +near absent takes the first: picked Appr F42A' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-near-catch 0 '^ok +near is no part of another id: picked Appr F42A' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-ack-pass 0 '^ok +ack an information box: returned "The purchase orders have been created\.", covered before mx-underlay, after null' '^ok +ack a warning box: returned' '^ok +ack with no box: returned null' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-ack-catch 0 '^ok +ack leaves an error box: returned null, covered before mx-underlay, after mx-underlay' '!^FAIL' -- $VB
    # PR-P2: a dialog still open after a task-outcome click (Warning box, popup page, one that opens late) is returned; none or a hidden one is null
    ctl journeys-verbs-browser-dialog-catch 0 '^ok +dialog open: a warning box: returned "Warning: Please complete the tasks first than click on' '^ok +dialog open: a popup page: returned' '^ok +dialog open: one that opens late: returned' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-dialog-pass 0 '^ok +dialog open: none: returned null' '^ok +dialog open: hidden: returned null' '!^FAIL' -- $VB
    # PR-C2 (run 3, P10 Unpause after Pause): a menu step after an earlier one waits for the page to settle
    ctl journeys-verbs-browser-menu-settle-pass 0 '^ok +menu again after a re-render: waits for the page to settle: returned pop_upMenu5 opened .*trigger opened the menu 2 time' '^ok +menu again, nothing re-renders: opens' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-menu-settle-catch 0 '^ok +menu again, the page never settles: says so: threw .*had not settled after the earlier menu step: .*still loading: mx-progress' '!^FAIL' -- $VB
    # PR-C3 (run 4, P10): a notice popup (one Close button) left by the earlier menu step is closed before the next one
    ctl journeys-verbs-browser-menu-notice-pass 0 '^ok +menu with a notice open \(one Close button\): closes it first: returned pop_upMenu5 opened .*closed a notice first' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-menu-notice-catch 0 '^ok +menu with a form dialog open \(a field\): leaves it: threw' '^ok +menu with a question open \(two buttons\): leaves it: threw' '!^FAIL' -- $VB
    # PR-B6 (run 3, P04): the click right after a tab click takes the same-named widget inside that tab's pane
    ctl journeys-verbs-browser-tabpane-pass 0 '^ok +tab pane tiebreak: the button inside the clicked tab: picked Add attachment' '^ok +tab pane tiebreak: one shown match is unchanged' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-tabpane-catch 0 '^ok +tab pane tiebreak is one shot: a later click keeps the old pick: picked Back' '^ok +tab pane tiebreak: the duplicate is not in the clicked tab \(catch\): picked Back' '!^FAIL' -- $VB
    # PR-C1 (run 4): a journey that must open an unassigned task takes the list item that states no assignee
    ctl journeys-verbs-browser-unassigned-pass 0 '^ok +unassigned picks the item showing Assign to me, not the first: picked Appr F42B' '^ok +unassigned picks the item that states no assignee, also without the button' '^ok +unassigned absent takes the first \(the old pick\)' '^ok +unassigned with every item unassigned takes the first' '!^FAIL' -- $VB
    ctl journeys-verbs-browser-unassigned-catch 0 '^ok +unassigned is not the assigned first item \(catch\): not Appr F42A' '^ok +unassigned with every item assigned keeps the first \(the step guard says it\)' '!^FAIL' -- $VB
  else for c in row-pass row-catch tab-pass item-pass item-catch combo-pass combo-catch menu-pass menu-catch fill-pass fill-catch near-pass near-catch ack-pass ack-catch menu-settle-pass menu-settle-catch menu-notice-pass menu-notice-catch tabpane-pass tabpane-catch unassigned-pass unassigned-catch; do skip journeys-verbs-browser-$c "no playwright with a browser"; done; fi
else for c in catch pass row-instrument-gap-catch row-hidden-first-pass tab-pass tab-catch date-pass date-catch browser-row-pass browser-row-catch browser-tab-pass browser-item-pass browser-item-catch browser-combo-pass browser-combo-catch browser-menu-pass browser-menu-catch browser-fill-pass browser-fill-catch browser-near-pass browser-near-catch browser-ack-pass browser-ack-catch; do
  skip journeys-verbs-$c "no node"; done; fi
ctl journeys-fill-colon-pass 0 '^"https://idp.example.com:8443/sso\?run=0102"$' -- python3 -c "import sys,json; sys.path.insert(0,'$B'); import run_journeys as r; t=r.run_copy_text(json.dumps({'do':'fill','value':'https://idp.example.com:8443/sso?run=\${RUN_ID}'}), {}, '0102'); print(json.dumps(json.loads(t)['value']))"
ctl journeys-screen-loading-catch 0 "^menu_A-Administrator INVALID" -- python3 -c "import sys,re; sys.path.insert(0,'$B'); import run_journeys as r; m=r.SHOT.match('shots-Administrator/menu_A-Administrator-step1-LOADING.png'); print(m.group(1), 'INVALID')"

# --- E2E-9 / E5b-11: the data rung asks the app's Postgres (pgmap.py, pgdata.js), every step records its effect --------
# lib/sqlitepsql.py is a psql stand-in on SQLite; fixtures/pgmap/shop.sql is synthetic (inheritance, column and table
# storage, a column association on the generalization, a 63-byte table name, an inconsistent mapping row, a runtime table).
SQ="python3 $here/lib/sqlitepsql.py"; PM="python3 $B/pgmap.py"
$SQ $T/shop.db --init $FX/pgmap/shop.sql; SHOP="$SQ $T/shop.db"
DOWN="sh -c 'echo connection refused >&2; exit 2'"
ctl pgmap-map-pass 0 '^pgmap: 6 entities, 7 attributes, 4 associations \(1 table storage, 2 column storage\), 1 names cut at 63 bytes, 1 problems' \
  'cut at 63 bytes: .* -> shop\$averylongentitynamethatmakesthetablenamelongerthansixtythr$' -- $PM map --psql "$SHOP" --out $T/pgmap.json
ctl pgmap-bad-row-catch 0 'problem: association Shop.Bad_Category: mapping row is inconsistent' -- $PM map --psql "$SHOP"
pmq() { env UPG_PSQL="$SHOP" UPG_PGMAP=$T/pgmap.json $PM "$@"; }
ctl pgmap-inherited-attr-pass 0 'INNER JOIN "shop\$base" AS "q0__1" ON "q0__1".id = "q0".id WHERE "q0__1"."code" = .C1.' -- pmq sql "SELECT COUNT(*) AS n FROM Shop.Item WHERE Code = 'C1'"
ctl pgmap-inherited-attr-count-pass 0 '^\[1\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item WHERE Code = 'C1'"
ctl pgmap-column-assoc-pass 0 '^\[1\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item AS e INNER JOIN e/Shop.Item_Category/Shop.Category AS t WHERE t.Title = 'Fruit'"
ctl pgmap-column-assoc-reverse-pass 0 '^\[1\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Category AS c INNER JOIN c/Shop.Item_Category/Shop.Item AS i"
ctl pgmap-table-assoc-pass 0 '"shop\$item_tag"' '^\[1\]$' -- sh -c "UPG_PSQL='$SHOP' UPG_PGMAP=$T/pgmap.json; export UPG_PSQL UPG_PGMAP; q='SELECT COUNT(*) AS n FROM Shop.Tag AS t INNER JOIN t/Shop.Item_Tag/Shop.Item AS i'; $PM sql \"\$q\" && $PM query \"\$q\""
ctl pgmap-generalization-assoc-pass 0 '^\[1\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item AS e INNER JOIN e/Shop.Base_Tag/Shop.Tag AS t"
ctl pgmap-left-join-pass 0 '^\[2\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item AS e LEFT OUTER JOIN e/Shop.Item_Category/Shop.Category AS t"
ctl pgmap-truncated-table-pass 0 '^\[1\]$' -- pmq query "SELECT COUNT(*) AS n FROM Shop.AVeryLongEntityNameThatMakesTheTableNameLongerThanSixtyThreeBytes"
# never guessed from names: an attribute, association or entity the mapping does not hold is refused (exit 1)
ctl pgmap-unknown-attr-catch 1 'attribute Shop.Item.Colour is not in mendixsystem\$attribute' '!^\[' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item WHERE Colour = 'red'"
ctl pgmap-bad-assoc-catch 1 'association Shop.Bad_Category: storage unknown' '!^\[' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Item AS e INNER JOIN e/Shop.Bad_Category/Shop.Category AS t"
ctl pgmap-remote-entity-catch 1 'entity Shop.Remote is not in mendixsystem\$entity' -- pmq query "SELECT COUNT(*) AS n FROM Shop.Remote"
ctl pgmap-counts-pass 0 '"Shop.Item": 2' '"Shop.Item_Tag": 1' '"Shop.Base_Tag": 1' '!System.Session' -- pmq counts
ctl pgmap-db-down-catch 2 'database did not answer: connection refused' -- env UPG_PGMAP=$T/pgmap.json $PM counts --psql "$DOWN"
ctl pgmap-no-psql-catch 1 'psql \(or UPG_PSQL\) is required' -- env -u UPG_PSQL $PM map
# run_journeys: the data backend is stated on every run; no database is INVALID with its reason, never silently mxcli
mkdir -p $T/gen-data && echo '{"journeys": [], "skipped": [], "todo": [], "covered": [{"id": "home:X", "why": "walked by login-A"}], "unreachable": []}' > $T/gen-data/plan.json
RJD="python3 $B/run_journeys.py $T/gen-data --label data --port 1 --admin-port 2 --admin-pass x --users $FX/journeys/no-users.json"
ctl journeys-data-backend-unset-catch 0 '^  data INVALID: no --psql / UPG_PSQL' -- env -u UPG_PSQL $RJD --work $T/e2e-data1
ctl journeys-data-backend-down-catch 0 '^  data INVALID: the database did not answer the mapping query: .*connection refused' -- $RJD --work $T/e2e-data2 --psql "$DOWN"
ctl journeys-data-backend-psql-pass 0 '^  data psql: pgmap: 6 entities' '!data INVALID' -- $RJD --work $T/e2e-data3 --psql "$SHOP"
# --compare: a journey PASSing on both runs must have changed the same rows on both (the effect record)
EF=$T/rjef; mkdir -p $EF/old/before
cp -R $SH/old/shots-Administrator $EF/old/before/   # screen pairs that pass, so the effects line alone decides
ef() { mkdir -p $EF/$1/after; cp -R $SH/same/shots-Administrator $EF/$1/after/; python3 -c "import json,sys; json.dump({'journeys': {'create-Administrator': dict({'role': 'Administrator', 'verdict': 'PASS'}, **json.loads(sys.argv[1]))}, 'roles': {}}, open('$EF/$1/after/summary.json', 'w'))" "$2"; }
python3 -c "import json; json.dump({'journeys': {'create-Administrator': {'role': 'Administrator', 'verdict': 'PASS', 'effects': [{'n': 1, 'changed': {}}, {'n': 2, 'changed': {'Shop.Item': 1, 'Shop.Base': 1}}]}}, 'roles': {}}, open('$EF/old/before/summary.json', 'w'))"
ef same '{"effects": [{"n": 1, "changed": {}}, {"n": 2, "changed": {"Shop.Item": 1, "Shop.Base": 1}}]}'
ef none '{"effects": [{"n": 1, "changed": {}}, {"n": 2, "changed": {}}]}'
ef inv '{"effects": [{"n": 1, "changed": {}}, {"n": 2, "invalid": "row counts not read before the step: UPG_PSQL is unset"}]}'
ef missing '{}'
pinset $EF/old/before/summary.json $EF/same/after/summary.json $EF/none/after/summary.json
RJE="python3 $B/run_journeys.py x --label after --compare $EF/old --rejudge"
ctl journeys-effect-same-pass 0 '^effects: 1 PASS, 0 PASS\*, 0 REVIEW, 0 INVALID$' -- $RJE --work $EF/same "${NOACT[@]}"
ctl journeys-effect-review-catch 1 'PASS +create-Administrator .*EFFECT REVIEW' '^effects: 0 PASS, 0 PASS\*, 1 REVIEW, 0 INVALID' -- $RJE --work $EF/none
echo 'create-Administrator step2 Shop.* # control: the new app saves through a different flow on purpose' > $T/effect-accept.txt
ctl journeys-effect-accept-pass 0 '^effects: 0 PASS, 1 PASS\*, 0 REVIEW, 0 INVALID' '!EFFECT REVIEW' -- $RJE --work $EF/none --effect-accept $T/effect-accept.txt "${NOACT[@]}"
echo 'create-Administrator step2 Shop.*' > $T/effect-accept-bad.txt
ctl journeys-effect-accept-reason-catch 2 "no '# reason'" -- $RJE --work $EF/none --effect-accept $T/effect-accept-bad.txt
ctl journeys-effect-invalid-catch 3 'EFFECT INVALID' '^effects: 0 PASS, 0 PASS\*, 0 REVIEW, 1 INVALID' '1 EFFECT INVALID' '!^verdict: PASS' -- $RJE --work $EF/inv
ctl journeys-effect-missing-catch 3 'new run has no effect record' '^  effects: .*--psql' -- $RJE --work $EF/missing
# --- E2E-11: the coverage line and the rules that keep rung 8's INVALID honest (plan section 3) ------------------------
# a synthetic generated set of 5 journeys, 4 linked to an action of a 6-action inventory (one todo, one without journey);
# old (before) and new (after) summaries written per case, the baseline pinned to the set's hash as a live run pins it
CV=$T/rjcov; mkdir -p $CV/gen/journeys/Administrator
cvj() { python3 -c "import json,sys; d={'id': sys.argv[1], 'steps': [{'ui': {'goto': '/'}}]}
if sys.argv[2]: d['action'] = sys.argv[2]
if sys.argv[3]: d['seeds'] = json.loads(sys.argv[3])
json.dump(d, open('$CV/gen/journeys/Administrator/' + sys.argv[1] + '.journey.json', 'w'), indent=1)" "$@"; }
cvj dashboard-Administrator Shop.Dash.btnA ''
cvj login-Administrator '' ''
cvj j3-Administrator Shop.P3.btn '[{"name": "cat", "sql": "SELECT Title FROM Shop.Category WHERE Title = '"'Veg'"'"}]'
cvj j4-Administrator Shop.P4.btn '[{"name": "item", "sql": "SELECT Name FROM Shop.Item WHERE Name = '"'Apple'"'"}]'
cvj j5-Administrator Shop.P5.btn ''
echo '{"journeys": []}' > $CV/gen/plan.json
python3 -c "import json; a=[{'id': i, 'todo': []} for i in ('Shop.Dash.btnA', 'Shop.P3.btn', 'Shop.P4.btn', 'Shop.P5.btn')]
a += [{'id': 'Shop.P6.cmb', 'todo': ['combobox (no generated verb for a combo box)']}, {'id': 'Shop.P7.btn', 'todo': []}]
json.dump({'actions': a}, open('$CV/actions.json', 'w')); json.dump({'actions': [x for x in a if x['id'] != 'Shop.P5.btn']}, open('$CV/actions5.json', 'w'))"
cp -R $CV/gen $CV/gen2; python3 -c "import json; f='$CV/gen2/journeys/Administrator/j5-Administrator.journey.json'; d=json.load(open(f)); d['steps'].append({'ui': {'click': 'x'}}); json.dump(d, open(f, 'w'))"
# cvs DIR GEN 'j3=FAIL,...' [noset]: a summary (every other journey PASS, with an effect record), pinned to GEN's set
cvs() { mkdir -p $1; cp -R $SH/same/shots-Administrator $1/ 2>/dev/null
  python3 -c "import json,sys; sys.path.insert(0, '$B'); from run_journeys import journey_set
v=dict(x.split('=') for x in sys.argv[2].split(',') if x)
js={j + '-Administrator': {'role': 'Administrator', 'verdict': v.get(j, 'PASS'), 'effects': [{'n': 1, 'changed': {}}]} for j in ('dashboard', 'login', 'j3', 'j4', 'j5')}
d={'journeys': js, 'roles': {}}
if len(sys.argv) < 4: d['journey_set'] = journey_set(sys.argv[1])
json.dump(d, open('$1/summary.json', 'w'))" $2 "$3" ${4:+$4}; }
cvs $CV/base/before $CV/gen ''; rm -rf $CV/base/before/shots-Administrator; cp -R $SH/old/shots-Administrator $CV/base/before/
cvs $CV/base0/before $CV/gen '' noset
RJC="python3 $B/run_journeys.py $CV/gen --label after --rejudge"
CVA=(--compare $CV/base --actions $CV/actions.json)
cvs $CV/ok/after $CV/gen ''
ctl journeys-coverage-line-pass 0 '^actions 6 found · 4 generated \(2 todo: combobox 1, no journey 1\) · 4 pass on baseline \(0 defect\) · 4 pass on new · 0 regression · coverage 4/6 \(66%\)$' \
  '!coverage INVALID' '!^coverage: |[1-9] PASS\*' -- $RJC --work $CV/ok "${CVA[@]}"
ctl journeys-coverage-no-actions-catch 3 '^actions \? found · 5 journeys \(todo unknown\) .*coverage \? \(no actions.json: coverage unknown\)' \
  'coverage INVALID: coverage unknown: no --actions' '!^verdict: PASS' -- $RJC --work $CV/ok --compare $CV/base
ctl journeys-coverage-waived-pass 0 '^coverage: 1 PASS\* \(no denominator: control' 'coverage \? \(no denominator: control' '!coverage INVALID' -- $RJC --work $CV/ok --compare $CV/base "${NOACT[@]}"
ctl journeys-coverage-waiver-needs-reason-catch 2 'needs a reason' -- $RJC --work $CV/ok --compare $CV/base --no-actions ' '
ctl journeys-coverage-actions-unreadable-catch 2 'not readable as actions.json' -- $RJC --work $CV/ok --compare $CV/base --actions $CV/nope.json
cvs $CV/chg/after $CV/gen2 ''
ctl journeys-coverage-hash-changed-catch 3 'coverage INVALID: journey set changed since the baseline \(sha256 [0-9a-f]{12} then, [0-9a-f]{12} now\)' -- $RJC --work $CV/chg "${CVA[@]}"
ctl journeys-coverage-hash-missing-catch 3 'coverage INVALID: the baseline recorded no journey-set hash' -- $RJC --work $CV/ok --compare $CV/base0 --actions $CV/actions.json
ctl journeys-coverage-stale-action-catch 3 'coverage INVALID: 1 journey action ids not in actions.json \(stale inventory\?\): j5-Administrator -> Shop.P5.btn' \
  '^actions 5 found · 3 generated' -- $RJC --work $CV/ok --compare $CV/base --actions $CV/actions5.json
cvs $CV/reg/after $CV/gen 'j4=FAIL'
ctl journeys-coverage-regression-catch 1 'FAIL +j4-Administrator .*\[REGRESSION\]' ' · 3 pass on new · 1 regression · coverage 4/6' -- $RJC --work $CV/reg "${CVA[@]}"
# baseline defects: FAIL on the old app too. Only with evidence that a tool can check are they PASS*, else INVALID
cvs $CV/d3/before $CV/gen 'j3=FAIL'; cvs $CV/d3n/after $CV/gen 'j3=FAIL'; cvs $CV/d3p/after $CV/gen ''
CVD=(--compare $CV/d3 --actions $CV/actions.json)
ctl journeys-coverage-defect-no-evidence-catch 3 'FAIL +j3-Administrator .*\[BASELINE DEFECT \(before FAIL\): no evidence\]' '3 pass on baseline \(1 defect\)' \
  'coverage INVALID: 1 baseline defects without evidence' '0 with evidence, 1 without \(INVALID\)' -- $RJC --work $CV/d3n "${CVD[@]}"
python3 $B/fixture_check.py $CV/gen --psql "$SHOP" --out $CV/fc.json > /dev/null 2>&1
echo 'j3-Administrator FIXTURE fc.json # control: no Veg category in the fixture' > $CV/ev-fixture.txt
ctl journeys-coverage-defect-fixture-pass 0 '\[BASELINE DEFECT FIXTURE \(FIXTURE: seed cat returned nothing \(fc.json\)\)\]' \
  '^defects: 1 failing on the baseline: 1 with evidence \(FIXTURE 1\) = 1 PASS\*, 0 without' '!coverage INVALID' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-fixture.txt
cvs $CV/d4/before $CV/gen 'j4=FAIL'; cvs $CV/d4n/after $CV/gen 'j4=FAIL'
echo 'j4-* FIXTURE fc.json # control: the seed is there, so this is no fixture gap' > $CV/ev-fixture4.txt
ctl journeys-coverage-defect-fixture-ok-catch 3 'evidence line 1: FIXTURE fc.json: j4-Administrator is OK, not EMPTY' 'coverage INVALID: 1 baseline defects without evidence' \
  -- $RJC --work $CV/d4n --compare $CV/d4 --actions $CV/actions.json --baseline-evidence $CV/ev-fixture4.txt
printf 'start\nERROR Shop.P3 microflow failed: control\nend\n' > $CV/old-app.log
echo 'j3-Administrator OLD-APP old-app.log:2 # control: the old app errors there' > $CV/ev-old.txt
ctl journeys-coverage-defect-old-app-pass 0 '\[BASELINE DEFECT OLD-APP \(OLD-APP: old-app.log:2 ERROR Shop.P3 microflow failed' '!coverage INVALID' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-old.txt
echo 'j3-Administrator OLD-APP old-app.log:9 # control' > $CV/ev-old9.txt; echo 'j3-Administrator OLD-APP gone.log # control' > $CV/ev-oldgone.txt
# FN-36: a plan row closed by a journey that fails on the old app too (evidenced) takes the closer's defect class; without
# evidence the row keeps its plain FAIL and the closer's defect stays INVALID
mkdir -p $CV/d3c; cp -R $CV/d3n/after $CV/d3c/; python3 -c "import json; f='$CV/d3c/after/summary.json'; d=json.load(open(f))
d['journeys']['plan-row']={'role': '', 'verdict': 'FAIL', 'why': 'covered: closed by j3-Administrator', 'closed_by': 'j3-Administrator'}; json.dump(d, open(f, 'w'))"
ctl journeys-coverage-closed-row-defect-pass 0 'FAIL +plan-row .*\[BASELINE DEFECT OLD-APP \(closed by j3-Administrator; OLD-APP: old-app.log:2 ERROR Shop.P3 microflow failed' '!coverage INVALID' -- $RJC --work $CV/d3c "${CVD[@]}" --baseline-evidence $CV/ev-old.txt
ctl journeys-coverage-closed-row-no-evidence-catch 1 'FAIL +plan-row ' '!plan-row .*BASELINE DEFECT' 'coverage INVALID: 1 baseline defects without evidence' -- $RJC --work $CV/d3c "${CVD[@]}"
ctl journeys-coverage-defect-old-app-line-catch 3 'OLD-APP .*old-app.log:9: the file has 3 lines' 'coverage INVALID: 1 baseline defects' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-old9.txt
ctl journeys-coverage-defect-old-app-file-catch 3 'OLD-APP .*gone.log: no such file' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-oldgone.txt
# Field run: a rerun reorders the old-app output, so a cited line can drift onto another journey's row. One line naming
# this journey elsewhere in the file is accepted (with the new line); none, or a cited line naming another journey, is not
printf '  FAIL    j4-Administrator x\n  FAIL    j3-Administrator y\n' > $CV/jout.txt; printf '  FAIL    j4-Administrator x\n' > $CV/jout4.txt
echo 'j3-Administrator OLD-APP jout.txt:1 # control: the line moved' > $CV/ev-drift.txt; echo 'j3-Administrator OLD-APP jout4.txt:1 # control' > $CV/ev-drift4.txt
ctl journeys-coverage-defect-old-app-drift-pass 0 'OLD-APP: jout.txt:2 \(cited :1, which moved\)' '!coverage INVALID' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-drift.txt
ctl journeys-coverage-defect-old-app-drift-catch 3 'OLD-APP .*jout4.txt:1: line 1 names another journey and j3-Administrator is not in the file' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-drift4.txt
cvs $CV/r1/before $CV/gen ''; cvs $CV/r2/before $CV/gen 'j3=FAIL'
echo 'j3-Administrator FLAKY r1 r2 # control: one of two reruns passed' > $CV/ev-flaky.txt; echo 'j3-Administrator FLAKY r2 r2 # control' > $CV/ev-flaky2.txt
ctl journeys-coverage-defect-flaky-pass 0 '\[BASELINE DEFECT FLAKY \(FLAKY: reruns PASS / FAIL\)\]' '!coverage INVALID' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-flaky.txt
ctl journeys-coverage-defect-flaky-both-fail-catch 3 'FLAKY: reruns FAIL / FAIL \(needs one PASS and one not\)' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-flaky2.txt
echo 'j3-Administrator BROKEN old-app.log # control' > $CV/ev-bad.txt
ctl journeys-coverage-evidence-class-catch 2 "want '<journey> FIXTURE\|OLD-APP\|FLAKY <evidence> # note'" -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-bad.txt
# a baseline defect that passes on the new app is listed for review, not hidden; without evidence it is still INVALID
ctl journeys-coverage-defect-passes-new-pass 0 'PASS +j3-Administrator .*\[BASELINE DEFECT OLD-APP, passes on new: review' -- $RJC --work $CV/d3p "${CVD[@]}" --baseline-evidence $CV/ev-old.txt
ctl journeys-coverage-defect-passes-new-catch 3 'PASS +j3-Administrator .*\[BASELINE DEFECT \(before FAIL\), passes on new: no evidence\]' -- $RJC --work $CV/d3p "${CVD[@]}"
# more than 30% of the set failing on the OLD app: the instrument is not measuring, evidence or not
cvs $CV/d34/before $CV/gen 'j3=FAIL,j4=FAIL'; cvs $CV/d34n/after $CV/gen 'j3=FAIL,j4=FAIL'
printf 'j3-Administrator OLD-APP old-app.log:2 # control\nj4-Administrator OLD-APP old-app.log:2 # control\n' > $CV/ev-34.txt
ctl journeys-coverage-defect-ratio-catch 3 'coverage INVALID: instrument not measuring: 2 of 4 actions fail on the baseline \(50% > 30%\)' '2 with evidence \(OLD-APP 2\)' \
  -- $RJC --work $CV/d34n --compare $CV/d34 --actions $CV/actions.json --baseline-evidence $CV/ev-34.txt
# a live run pins its set: the hash in summary.json is the one a later rejudge compares (no browser: no test user)
ctl journeys-coverage-live-pins-set-pass 0 '^set 5 \[.Shop.P3.btn.\] same$' -- sh -c "env -u UPG_PSQL python3 $B/run_journeys.py $CV/gen --label live --port 1 --admin-port 2 --admin-pass x --users $FX/journeys/no-users.json --work $CV/live > /dev/null 2>&1; python3 -c \"import json; d=json.load(open('$CV/live/live/summary.json'))['journey_set']; b=json.load(open('$CV/base/before/summary.json'))['journey_set']; print('set', d['files'], d['links']['j3-Administrator'], 'same' if d['sha256'] == b['sha256'] else 'differs')\""
# B4N1-13: an evidenced baseline defect is counted PASS* (baseline defect) in the headline, not FAIL; an unevidenced one
# stays FAIL there (and INVALID in the coverage rules)
ctl journeys-headline-baseline-defect-pass 0 '^journeys: 4 PASS, 0 FAIL, 0 INVALID, 1 PASS\* \(baseline defect\)$' -- $RJC --work $CV/d3n "${CVD[@]}" --baseline-evidence $CV/ev-old.txt
ctl journeys-headline-no-evidence-catch 3 '^journeys: 4 PASS, 1 FAIL, 0 INVALID$' '!PASS\* \(baseline defect\)' -- $RJC --work $CV/d3n "${CVD[@]}"
# B4N1-12: the exit-3 advice "fail on the OLD app too: drop them" names only journeys that did not PASS on the old run;
# a journey that PASSed there but whose OLD screenshot is unusable gets "accept or repair the wait", never "drop"
OS=$T/rjoldshot; mkdir -p $OS/old/before/shots-Administrator $OS/old2/before/shots-Administrator $OS/new/after
cp -R $SH/same/shots-Administrator $OS/new/after/
echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "PASS"}}, "roles": {}}' | tee $OS/old/before/summary.json > $OS/new/after/summary.json
echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "INVALID"}}, "roles": {}}' > $OS/old2/before/summary.json
ctl journeys-advice-old-pass-shot-catch 3 'PASS +dashboard-Administrator .*SCREEN INVALID' '^  old screenshot: dashboard-Administrator PASSed on the OLD app .*--shot-accept.*do not drop' \
  '0 failing on the baseline' '!^  baseline: ' -- python3 $B/run_journeys.py x --label after --work $OS/new --compare $OS/old --rejudge
ctl journeys-advice-old-not-pass-shot-pass 3 '1 failing on the baseline' '^  baseline: dashboard-Administrator fail on the OLD app too' '!^  old screenshot: ' \
  -- python3 $B/run_journeys.py x --label after --work $OS/new --compare $OS/old2 --rejudge
# B4T2-15: a plan row closed by another journey is judged on the closer's effect record, on both runs (it was EFFECT
# INVALID "no effect record"); B4N1-10: System.XASInstance (re-registered per start) is runtime housekeeping
EC=$T/rjeffclose; mkdir -p $EC/old/before; cp -R $SH/old/shots-Administrator $EC/old/before/
ec() { mkdir -p $EC/$1/after; cp -R $SH/same/shots-Administrator $EC/$1/after/ 2>/dev/null; python3 -c "import json,sys
d=json.loads(sys.argv[2]); json.dump({'journeys': d, 'roles': {}, 'journey_set': {'sha256': 'c0ffee'*10+'c0ff'}}, open(sys.argv[1], 'w'))" $EC/$1/after/summary.json "$2"; }
ECR='"act-P.newButton1": {"role": "", "verdict": "PASS", "why": "covered: closed by create-save"}, "sign-out": {"role": "", "verdict": "PASS", "why": "todo closed by sign-out-hand (hand-written journey)", "closed_by": "sign-out-hand"}'
ec old "{\"create-save\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {\"Shop.Item\": 1, \"System.XASInstance\": -2}}]}, \"sign-out-hand\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {}}]}, $ECR}"
mv $EC/old/after/summary.json $EC/old/before/summary.json; rm -rf $EC/old/after
ec ok "{\"create-save\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {\"Shop.Item\": 1}}]}, \"sign-out-hand\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {}}]}, $ECR}"
ec gone "{\"create-save\": {\"verdict\": \"PASS\"}, \"sign-out-hand\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {}}]}, $ECR}"
ec sys "{\"create-save\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {\"Shop.Item\": 1, \"System.User\": 1}}]}, \"sign-out-hand\": {\"verdict\": \"PASS\", \"effects\": [{\"n\": 1, \"changed\": {}}]}, $ECR}"
RJEC="python3 $B/run_journeys.py x --label after --compare $EC/old --rejudge"
ctl journeys-effect-closed-inherit-pass 0 '^effects: 4 PASS, 0 PASS\*, 0 REVIEW, 0 INVALID$' '!EFFECT INVALID' '!XASInstance' -- sh -c "$RJEC --work $EC/ok --no-actions 'control: synthetic set' && python3 -c \"import json,sys; sys.path.insert(0, '$B'); import run_journeys as r; j=json.load(open('$EC/ok/after/summary.json'))['journeys']; b=json.load(open('$EC/old/before/summary.json'))['journeys']; [print(x['journey'], x['verdict'], x['detail']) for x in r.effect_compare(j, b)]\""
ctl journeys-effect-closed-record-line-pass 0 '^act-P.newButton1 PASS .*\(the record of create-save, which closed it\)$' '^sign-out PASS .*\(the record of sign-out-hand, which closed it\)$' \
  -- python3 -c "import json,sys; sys.path.insert(0, '$B'); import run_journeys as r; j=json.load(open('$EC/ok/after/summary.json'))['journeys']; b=json.load(open('$EC/old/before/summary.json'))['journeys']; [print(x['journey'], x['verdict'], x['detail']) for x in r.effect_compare(j, b)]"
ctl journeys-effect-closed-closer-missing-catch 3 'act-P.newButton1 .*EFFECT INVALID.*new run has no effect record \(the record of create-save' '^effects: 2 PASS, 0 PASS\*, 0 REVIEW, 2 INVALID$' \
  -- $RJEC --work $EC/gone --no-actions 'control: synthetic set'
ctl journeys-effect-system-entity-catch 1 'create-save .*EFFECT REVIEW.*System.User: old \+0, new \+1' '!XASInstance' -- $RJEC --work $EC/sys --no-actions 'control: synthetic set'
# B4T2-18: an empty (0 byte) or broken journey file names the file and nothing runs (exit 2), never a traceback
mkdir -p $T/gen-empty/journeys/Administrator $T/gen-badjson/journeys/Administrator
: > $T/gen-empty/journeys/Administrator/blank.journey.json; echo '{"id": "x", "steps": [' > $T/gen-badjson/journeys/Administrator/cut.journey.json
ctl journeys-empty-file-catch 2 'journey file .*/blank\.journey\.json: empty file \(0 bytes\): INVALID, nothing was run' '!Traceback' -- python3 $B/run_journeys.py $T/gen-empty --label after --work $CV/ok --rejudge
ctl journeys-badjson-file-catch 2 'journey file .*/cut\.journey\.json: not JSON' '!Traceback' -- python3 $B/run_journeys.py $T/gen-badjson --label after --work $CV/ok --rejudge
# TC-1: a connector step without a proof value, or with one the step does not assert, is INVALID before anything runs
mkdir -p $T/gen-tc1-bad/journeys/Administrator $T/gen-tc1-weak/journeys/Administrator $T/gen-tc1-ok/journeys/Administrator
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": "Teamcenter", "ui": {"textPresent": ["Items"]}}]}' > $T/gen-tc1-bad/journeys/Administrator/conn.journey.json
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": true, "proof": "ITM-0042", "ui": {"textPresent": ["Items"]}}]}' > $T/gen-tc1-weak/journeys/Administrator/conn.journey.json
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": true, "proof": "ITM-0042", "ui": {"textPresent": ["ITM-0042"]}}, {"do": "open", "ui": {"textPresent": ["Home"]}}]}' > $T/gen-tc1-ok/journeys/Administrator/conn.journey.json
ctl journeys-connector-noproof-catch 2 'conn\.journey\.json: CONNECTOR NO PROOF \(TC-1\): step 1 reads Teamcenter but has no "proof"' 'INVALID, nothing was run' '!Traceback' -- python3 $B/run_journeys.py $T/gen-tc1-bad --label after --work $CV/ok --rejudge
ctl journeys-connector-proof-not-asserted-catch 2 "step 1: proof 'ITM-0042' is not asserted" '!Traceback' -- python3 $B/run_journeys.py $T/gen-tc1-weak --label after --work $CV/ok --rejudge
ctl journeys-connector-proof-pass 0 '!CONNECTOR NO PROOF' '!journey file ' -- python3 $B/run_journeys.py $T/gen-tc1-ok --label after --work $CV/ok "${CVA[@]}" --rejudge
# PV-10: the proof is not one of the mock's own values; "connected" (text shown only while connected) is asserted when given;
# a connector step with no "connected" prints a NOTE (not a refusal)
mkdir -p $T/gen-tc10-mock/journeys/Administrator $T/gen-tc10-conn/journeys/Administrator $T/gen-tc10-ok/journeys/Administrator
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": "Teamcenter", "proof": "Rev A", "mockValues": ["Rev A", "Rev B"], "ui": {"textPresent": ["Rev A"]}}]}' > $T/gen-tc10-mock/journeys/Administrator/conn.journey.json
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": "Teamcenter", "proof": "ITM-0042", "connected": "Connected", "ui": {"textPresent": ["ITM-0042"]}}]}' > $T/gen-tc10-conn/journeys/Administrator/conn.journey.json
echo '{"id": "conn-page", "steps": [{"do": "open", "connector": "Teamcenter", "proof": "ITM-0042", "connected": "Connected", "mockValues": ["Rev A"], "ui": {"textPresent": ["ITM-0042", "Connected"]}}]}' > $T/gen-tc10-ok/journeys/Administrator/conn.journey.json
ctl journeys-connector-mock-proof-catch 2 "step 1: proof 'Rev A' is also what the mock shows" '!Traceback' -- python3 $B/run_journeys.py $T/gen-tc10-mock --label after --work $CV/ok --rejudge
ctl journeys-connected-not-asserted-catch 2 "step 1: connected 'Connected' is not asserted" '!Traceback' -- python3 $B/run_journeys.py $T/gen-tc10-conn --label after --work $CV/ok --rejudge
ctl journeys-connected-pass 0 '!CONNECTOR NO PROOF' '!NOTE \(PV-10\)' -- python3 $B/run_journeys.py $T/gen-tc10-ok --label after --work $CV/ok "${CVA[@]}" --rejudge
ctl journeys-connected-note-pass 0 '^NOTE \(PV-10\) conn\.journey\.json: step 1 reads an external system and asserts no connected state' '!CONNECTOR NO PROOF' -- python3 $B/run_journeys.py $T/gen-tc1-ok --label after --work $CV/ok "${CVA[@]}" --rejudge
ctl journeys-good-files-pass 0 '!journey file ' -- $RJC --work $CV/ok "${CVA[@]}"
# --- E2E-12: fixture_check.py runs every journey's seeds before the run and sorts what answers nothing by its cause -------
FC="python3 $B/fixture_check.py"
fcg() { local g=$CV/fx-$1; shift; mkdir -p $g/journeys/Administrator
  while [ $# -gt 0 ]; do python3 -c "import json,sys; json.dump({'id': sys.argv[1], 'steps': [], 'seeds': json.loads(sys.argv[2])}, open('$g/journeys/Administrator/' + sys.argv[1] + '.journey.json', 'w'))" "$1" "$2"; shift 2; done; }
fcg ok a-Administrator '[{"name": "item", "sql": "SELECT Name FROM Shop.Item WHERE Name = '"'Apple'"'"}, {"name": "same", "sql": "SELECT Name FROM Shop.Item WHERE Name = '"'{{item}}'"'"}]' \
  b-Administrator '[]'
ctl fixture-check-ok-pass 0 '^  OK +a-Administrator +item=Apple, same=Apple' '^fixture: 2 journeys · 1 with seeds · OK 1 · EMPTY 0 · QUERY-ERROR 0 · WARMING 0 · UNREACHABLE 0$' -- $FC $CV/fx-ok --psql "$SHOP"
fcg empty a-Administrator '[{"name": "cat", "sql": "SELECT Title FROM Shop.Category WHERE Title = '"'Veg'"'"}]' \
  n-Administrator '[{"name": "blank", "sql": "/*sql*/ SELECT NULL"}]' o-Administrator '[{"name": "item", "sql": "SELECT Name FROM Shop.Item WHERE Name = '"'Apple'"'"}]'
ctl fixture-check-empty-catch 1 '^  EMPTY +a-Administrator +cat returned nothing: 0 rows' '^  EMPTY +n-Administrator +blank returned nothing: first value is NULL or empty' \
  'EMPTY 2 · QUERY-ERROR 0' 'seed it before the run' '"status": "EMPTY"' -- sh -c "$FC $CV/fx-empty --psql '$SHOP' --out $CV/fc-empty.json; rc=\$?; cat $CV/fc-empty.json; exit \$rc"
fcg qerr a-Administrator '[{"name": "p", "sql": "SELECT Name FROM Shop.Product"}]' b-Administrator '[{"name": "bad", "sql": "/*sql*/ SELEC nothing"}]'
ctl fixture-check-query-error-catch 2 '^  QUERY-ERROR +a-Administrator +p: not translated: entity Shop.Product' '^  QUERY-ERROR +b-Administrator +bad: the SQL failed' \
  'a fault, not a finding' '!seed it before' -- $FC $CV/fx-qerr --psql "$SHOP"
$SQ $T/warm.db --init $FX/pgmap/shop.sql; echo "INSERT INTO \"mendixsystem\$entity\" VALUES ('e8', 'Shop.Order', 'shop\$order', NULL, false)" | $SQ $T/warm.db
fcg warm a-Administrator '[{"name": "o", "sql": "SELECT COUNT(*) AS n FROM Shop.Order"}]'
ctl fixture-check-warming-table-catch 2 '^  WARMING +a-Administrator +o: Shop.Order is mapped but its table is not in the database yet' -- $FC $CV/fx-warm --psql "$SQ $T/warm.db"
grep '^CREATE TABLE "mendixsystem' $FX/pgmap/shop.sql > $T/nomap.sql; $SQ $T/nomap.db --init $T/nomap.sql
ctl fixture-check-warming-mapping-catch 2 '^  WARMING +a-Administrator +mendixsystem\$entity is empty' -- $FC $CV/fx-warm --psql "$SQ $T/nomap.db"
ctl fixture-check-unreachable-catch 2 '^  UNREACHABLE +a-Administrator +the database did not answer: .*connection refused' 'UNREACHABLE 1$' -- $FC $CV/fx-warm --psql "$DOWN"
ctl fixture-check-no-psql-catch 2 '^  UNREACHABLE +a-Administrator +no --psql / UPG_PSQL' -- env -u UPG_PSQL $FC $CV/fx-warm
ctl fixture-check-no-gen-catch 2 'no journeys/ folder' -- $FC $CV/nothere
# the patched engine itself: the data rung and the effect record through UPG_PSQL, on a fake page and the SQLite psql
if command -v node > /dev/null && [ -f ${TOOLKIT_E2E:-$B/../vendor/e2e}/journey-runner.js ]; then
  ctl pgdata-engine-patch-pass 0 '^oql: SQL through UPG_PSQL' '^effect: require pgdata.js' '^effect: each step' '^effect: counts taken before the actions' '!NOT applied' -- python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-pg
  ctl pgdata-engine-syntax-pass 0 -- sh -c "node --check $T/engine-pg/journey-runner.js && node --check $T/engine-pg/helpers.js && node --check $T/engine-pg/pgdata.js"
  mkdir -p $T/pgef $T/pgef3; ctl pgdata-effect-pass 0 '^ok +save writes the own row -> data PASS, effect Base \+1 Item \+1' '!^FAIL' -- node $here/pgdata_effect_control.js $T/engine-pg $here/lib/sqlitepsql.py $FX/pgmap/shop.sql $T/pgef
  ctl pgdata-effect-catch 0 '^ok +save writes nothing \(T2-1\) -> data FAIL' '^ok +database unreachable -> data INVALID' '^ok +UPG_PSQL unset -> data INVALID' '!^FAIL' -- node $here/pgdata_effect_control.js $T/engine-pg $here/lib/sqlitepsql.py $FX/pgmap/shop.sql $T/pgef3
  # the unpatched engine has no effect record and asks mxcli: the control must notice (proves it bites)
  mkdir -p $T/engine-pg-plain $T/pgef2; cp ${TOOLKIT_E2E:-$B/../vendor/e2e}/*.js $T/engine-pg-plain/; cp $B/settle.js $B/journey-verbs.js $B/pgdata.js $B/pgmap.py $T/engine-pg-plain/
  ctl pgdata-effect-unpatched-catch 1 '^FAIL +save writes the own row' -- node $here/pgdata_effect_control.js $T/engine-pg-plain $here/lib/sqlitepsql.py $FX/pgmap/shop.sql $T/pgef2
else for c in pgdata-engine-patch-pass pgdata-engine-syntax-pass pgdata-effect-pass pgdata-effect-catch pgdata-effect-unpatched-catch; do skip $c "no node or no shared journey engine"; done; fi
# the same mapping on a real Postgres (the 63-byte cut is Postgres's own; pg-schema.sql has no "remote" column: fallback)
if PGC=$(bash $here/lib/pgtmp.sh start 2>/dev/null); then
  PGD=$(echo "$PGC" | awk '{print $3}')
  psql -h "$PGD" -U mendix -qtA -d fx -c 'create database shop' > /dev/null && psql -h "$PGD" -U mendix -qtA -d shop -f $FX/pgmap/shop.sql > /dev/null
  PGS="psql -h $PGD -U mendix -d shop"
  ctl pgmap-pg-map-pass 0 '^pgmap: 6 entities, 7 attributes, 4 associations \(1 table storage, 2 column storage\), 1 names cut at 63 bytes, 1 problems' -- $PM map --psql "$PGS" --out $T/pgmap-pg.json
  ctl pgmap-pg-query-pass 0 '^\[1\]$' -- env UPG_PSQL="$PGS" UPG_PGMAP=$T/pgmap-pg.json $PM query "SELECT COUNT(*) AS n FROM Shop.Item AS e INNER JOIN e/Shop.Base_Tag/Shop.Tag AS t WHERE e.Name = 'Apple'"
  ctl pgmap-pg-counts-pass 0 '"Shop.Item": 2' '"Shop.Item_Tag": 1' '!System.Session' -- env UPG_PSQL="$PGS" UPG_PGMAP=$T/pgmap-pg.json $PM counts
  ctl pgmap-pg-unknown-attr-catch 1 'not in mendixsystem\$attribute' -- env UPG_PSQL="$PGS" UPG_PGMAP=$T/pgmap-pg.json $PM query "SELECT COUNT(*) AS n FROM Shop.Item WHERE Colour = 'x'"
  psql -h "$PGD" -U mendix -qtA -d fx -f $FX/snapshot/pg-schema.sql > /dev/null
  ctl pgmap-pg-no-remote-column-pass 0 '^pgmap: [0-9]+ entities' '!database did not answer' -- $PM map --psql "psql -h $PGD -U mendix -d fx"
  bash $here/lib/pgtmp.sh stop "$PGD"
else for c in pgmap-pg-map-pass pgmap-pg-query-pass pgmap-pg-counts-pass pgmap-pg-unknown-attr-catch pgmap-pg-no-remote-column-pass; do skip $c "no postgres binaries or the throwaway cluster did not start"; done; fi

# --- gate: an ADDED behaviour switch is REVIEW, not INFO (E5b-20) -----------------------------------------------------------
model const-added-switch > /dev/null
ctl constcheck-added-switch-catch 1 'REVIEW +ADDED +MFAmodule\.ShowSystemData .*runs with' 'INFO +ADDED +MFAmodule\.Banner' -- python3 $B/constcheck.py $M/base $M/const-added-switch
echo 'MFAmodule.ShowSystemData # control: off is right for this app' > $T/cc-allow.txt
ctl constcheck-added-switch-allow-pass 0 'PASS\* +ADDED +MFAmodule\.ShowSystemData' -- python3 $B/constcheck.py $M/base $M/const-added-switch --allow $T/cc-allow.txt
echo '{"MFAmodule.ShowSystemData": "true"}' > $T/cc-env.json
ctl constcheck-added-switch-override-pass 0 "INFO +ADDED +MFAmodule\.ShowSystemData .*environment sets 'true'" -- python3 $B/constcheck.py $M/base $M/const-added-switch --overrides $T/cc-env.json

# FM-8: a publisher "*Version" label that went up with the module update is INFO, not a FAIL; a lower one, a non-version value or a
# mismatch with the installed module version stays a FAIL
for v in const-ver-old const-ver-new const-ver-down; do model $v > /dev/null; done
ctl constcheck-version-label-pass 0 'INFO +CHANGED +MFAmodule\.PublisherVersion .*version label: PublisherVersion went up to 5\.0\.0' 'FAIL 0' -- python3 $B/constcheck.py $M/const-ver-old $M/const-ver-new
ctl constcheck-version-label-down-catch 1 'FAIL +CHANGED +MFAmodule\.PublisherVersion' '!version label' -- python3 $B/constcheck.py $M/const-ver-new $M/const-ver-down
echo '{"MFAmodule": "5.0.0"}' > $T/cc-mv-ok.json; echo '{"MFAmodule": "4.0.0"}' > $T/cc-mv-bad.json
ctl constcheck-version-label-module-pass 0 'is the installed MFAmodule version' -- python3 $B/constcheck.py $M/const-ver-old $M/const-ver-new --module-versions $T/cc-mv-ok.json
ctl constcheck-version-label-module-mismatch-catch 1 'FAIL +CHANGED +MFAmodule\.PublisherVersion' -- python3 $B/constcheck.py $M/const-ver-old $M/const-ver-new --module-versions $T/cc-mv-bad.json

# --- toolset completeness before mxbuild (E4-20, E5b-1) and the mxbuild container flags (E4-4) ------------------------------
TS=$T/ts; mkdir -p $TS/inc/mxbuild-10.24.16/modeler $TS/ok/mxbuild-10.24.16/modeler/runtemplates/deployment $TS/ok/mxbuild-10.24.16/modeler/tools/node/node_modules $T/fakedocker
for d in inc ok; do for x in mx mxbuild; do printf '#!/bin/sh\n' > $TS/$d/mxbuild-10.24.16/modeler/$x; chmod +x $TS/$d/mxbuild-10.24.16/modeler/$x; done; done
printf '#!/bin/sh\necho "docker $*"\n' > $T/fakedocker/docker; chmod +x $T/fakedocker/docker
ctl toolset-incomplete-catch 2 'REFUSED, incomplete toolset .*runtemplates/deployment.*node_modules.*dojo-web' '!^docker' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/inc zsh $B/mx10.sh 10.24.16 mxbuild --target=package x.mpr
ctl toolset-incomplete-mx9-catch 2 'REFUSED' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/inc zsh $B/mx9.sh 10.24.16 mxbuild x.mpr
ctl toolset-incomplete-mx-warns 0 'WARNING, incomplete toolset' '^docker run .*modeler/mx check' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/inc zsh $B/mx10.sh 10.24.16 mx check x.mpr
# E6-1: the zsh scripts run under bash too (they re-exec zsh); E6-2: the refusal names the CDN tarball
ctl toolcheck-bash-pass 0 '!bad substitution' -- bash $B/toolcheck.sh $TS/ok/mxbuild-10.24.16 mxbuild
ctl toolcheck-bash-refuses-catch 2 'REFUSED, incomplete toolset' '!bad substitution' 'cdn\.mendix\.com/runtime/mxbuild-<full ver>\.tar\.gz' -- bash $B/toolcheck.sh $TS/inc/mxbuild-10.24.16 mxbuild
mkdir -p $TS/inc/mxbuild-10.24.16.96987/modeler; cp $TS/inc/mxbuild-10.24.16/modeler/mxbuild $TS/inc/mxbuild-10.24.16.96987/modeler/
# batch 1 (T1-6, T4-4, T6-7): the host check names the python modules with the pip command for THAT python; no rsync warns
printf '#!/bin/sh\ncase "$*" in *"import sys"*) echo /fake/python3;; *"import bson"*) echo "ModuleNotFoundError: No module named bson" >&2; exit 1;; *) exit 0;; esac\n' > $T/py-nobson; chmod +x $T/py-nobson
printf '#!/bin/sh\necho /fake/python3\nexit 0\n' > $T/py-ok; chmod +x $T/py-ok
ctl toolcheck-host-modules-catch 2 'REFUSED, python modules missing for /fake/python3: pymongo\. Install with: .*/py-nobson -m pip install pymongo$' -- env UPG_PYTHON=$T/py-nobson zsh $B/toolcheck.sh --host
ctl toolcheck-host-pass 0 'host OK' '!REFUSED' -- env PATH=$T/badrsync:$PATH UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
ctl toolcheck-host-no-rsync-catch 0 'WARNING, no rsync' -- env PATH=$NR UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
# C6: no GNU timeout/gtimeout is a WARNING (gate.sh has a watchdog), present is silent; non-GNU sed without gsed warns
NT=$T/notimeout; mkdir -p $NT
for d in $(echo "$PATH" | tr ':' ' '); do for f in "$d"/*; do n=${f##*/}; case $n in timeout|gtimeout) continue;; esac; [ -e "$NT/$n" ] || ln -s "$f" "$NT/$n" 2>/dev/null; done; done
ctl toolcheck-host-no-timeout-catch 0 'WARNING, no GNU timeout or gtimeout' 'host OK' -- env PATH=$NT UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
ctl toolcheck-host-timeout-pass 0 'host OK' '!no GNU timeout' -- env UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
NS=$T/nogsed; mkdir -p $NS $T/bsdsed; printf '#!/bin/sh\nexit 1\n' > $T/bsdsed/sed; chmod +x $T/bsdsed/sed
ctl toolcheck-host-bsd-sed-catch 0 'WARNING, sed is not GNU sed' -- env PATH=$T/bsdsed:$NT UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
# B4T2-1, B4N1-3: setup-container.sh pre-places the ANTLR jar (Maven Central 429 -> mirror; a proxy page is no jar), never
# takes a credential on a command line, and runs toolcheck AFTER the pip/apt step: REFUSED or no rsync = exit 1 (it ran
# before the pip step with `|| true`: "REFUSED" for modules installed a step later, exit 0 with modules or rsync missing)
SC=$T/sc; mkdir -p $SC/bin $SC/bin2 $SC/bin3
cat > $SC/bin/curl <<'EOF'
#!/bin/bash
out=; prev=; for a; do [ "$prev" = -o ] && out=$a; prev=$a; done; url=${!#}
echo "$*" >> "$(dirname "$0")/../curl.log"
case $url in *repo1.maven.org*) echo "curl: (22) The requested URL returned error: 429" >&2; exit 22;; esac
case ${FAKE_CURL:-} in
  allfail) echo "curl: (22) The requested URL returned error: 503" >&2; exit 22;;
  html) case $url in *googleapis*) echo '<html>blocked by policy</html>' > "$out"; exit 0;; esac;;
esac
printf 'PK\003\004fake-jar' > "$out"
EOF
printf '#!/bin/sh\necho "argv: $*" >> %s/mxcli.log; read -r t; echo "stdin: $t" >> %s/mxcli.log; mkdir -p "$HOME/.mxcli"; echo "{}" > "$HOME/.mxcli/auth.json"\n' $SC $SC > $SC/bin/mxcli
printf '#!/bin/sh\ncase "$*" in *install*rsync*) printf "#!/bin/sh\\nexit 0\\n" > %s/rsync; chmod +x %s/rsync;; esac\nexit 0\n' $SC/bin2 $SC/bin2 > $SC/bin2/apt-get
printf '#!/bin/sh\necho "E: Unable to locate package rsync" >&2; exit 100\n' > $SC/bin3/apt-get
printf '#!/bin/sh\ncase "$*" in *"import sys"*) echo /fake/python3;; *"-m pip install"*) for a; do p=$a; done; touch %s/pip-$p;; *"import bson"*) [ -f %s/pip-pymongo ];; *"import bcrypt"*) [ -f %s/pip-bcrypt ];; *) exit 0;; esac\n' $SC $SC $SC > $SC/py-state
chmod +x $SC/bin/* $SC/bin2/* $SC/bin3/* $SC/py-state
JAR=4.13.2/antlr4-4.13.2-complete.jar; JD=$SC/home/.m2/repository/org/antlr/antlr4
setup() { local h=$1; shift; env HOME=$SC/$h "$@" bash $B/setup-container.sh $SC/run-$h 11.6.3; }
ctl setup-antlr-mirror-catch 0 'antlr jar: https://repo1\.maven\.org/maven2 failed' 'antlr jar placed from https://maven-central\.storage-download\.googleapis\.com/maven2' -- setup home PATH=$SC/bin:$NR UPG_SETUP_STEPS=antlr
ctl setup-antlr-jar-pass 0 '^PK' '!\.part' -- sh -c "head -c 2 $JD/$JAR; echo; ls $JD/4.13.2"
ctl setup-antlr-present-pass 0 'antlr jar present' '!placed from|failed' -- setup home PATH=$SC/bin:$NR UPG_SETUP_STEPS=antlr
ctl setup-antlr-not-a-jar-catch 0 'googleapis\.com/maven2 failed \(429, unreachable or not a jar\)' 'placed from https://repo\.maven\.apache\.org/maven2' -- setup home-html PATH=$SC/bin:$NR FAKE_CURL=html UPG_SETUP_STEPS=antlr
ctl setup-antlr-allfail-catch 1 'REFUSED, antlr4-4\.13\.2-complete\.jar could not be fetched from https://repo1' '!placed from' -- setup home-fail PATH=$SC/bin:$NR FAKE_CURL=allfail UPG_SETUP_STEPS=antlr
ctl setup-antlr-allfail-nojar-pass 0 '^none$' -- sh -c "ls $SC/home-fail/.m2/repository/org/antlr/antlr4/4.13.2 | grep . || echo none"
ctl setup-antlr-own-mirror-pass 0 'placed from https://nexus\.example/maven2$' -- setup home-nx PATH=$SC/bin:$NR UPG_MAVEN_MIRROR=https://nexus.example/maven2/ UPG_SETUP_STEPS=antlr
ctl setup-antlr-netrc-pass 0 '--netrc-optional .*https://nexus\.example/maven2/org/antlr' -- tail -1 $SC/curl.log
ctl setup-mirror-credentials-catch 2 'REFUSED, UPG_MAVEN_MIRROR carries credentials' '!s3cr3t' -- setup home-cr PATH=$SC/bin:$NR UPG_MAVEN_MIRROR=https://ci:s3cr3t@nexus.example/maven2 UPG_SETUP_STEPS=antlr
ctl setup-mirror-credentials-nocurl-pass 1 -- grep -q s3cr3t $SC/curl.log
ctl setup-auth-run-pass 0 '!pat-XYZ' -- setup home-au PATH=$SC/bin:$NR MENDIX_PAT=pat-XYZ UPG_SETUP_STEPS=auth
ctl setup-auth-stdin-catch 0 '^argv: auth login$' '^stdin: pat-XYZ$' '!argv: .*pat-XYZ' -- cat $SC/mxcli.log
ctl setup-check-refused-catch 1 'REFUSED, python modules missing for /fake/python3: pymongo' 'NOT READY: toolcheck\.sh --host refused' '!done: source' -- setup home-rf PATH=$SC/bin2:$NR UPG_PYTHON=$T/py-nobson UPG_SETUP_STEPS=host,check
rm -f $SC/bin2/rsync $SC/pip-*
ctl setup-check-after-install-pass 0 'host OK \(.*/py-state has pymongo/bson and bcrypt, rsync present\)' '!REFUSED' 'NOTE: no 10\.24 toolset' 'done: source' -- setup home-ok PATH=$SC/bin2:$NR UPG_PYTHON=$SC/py-state UPG_SETUP_STEPS=host,check
ctl setup-check-installed-pass 0 'pip-bcrypt' 'pip-pymongo' 'rsync' -- ls $SC $SC/bin2
ctl setup-check-no-rsync-catch 1 'NOT READY: rsync missing' '!done: source' -- setup home-nr PATH=$SC/bin3:$NR UPG_PYTHON=$T/py-ok UPG_SETUP_STEPS=host,check
ctl setup-env-file-pass 0 '^export UPG_ROOT=.*/run-home-env UPG_TOOLS=' -- sh -c "env HOME=$SC/home-env UPG_SETUP_STEPS=env bash $B/setup-container.sh $SC/run-home-env 11.6.3 > /dev/null && cat $SC/run-home-env/upg-env.sh"
# S1-S3 (Apple Silicon / laptop): setup-container.sh through stubbed uname (Darwin/arm64), docker, make, npm and npx; no real
# Docker or Mac. S1 mxcli is cross-built GOOS=linux GOARCH=amd64 and a Mac's own mxcli is never replaced; S2 every docker
# pull/build in step 4 carries --platform linux/amd64; S3 no /opt/pw-browsers = install Chromium (or a NEXT-STEP line
# when PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is set), toolcheck --host warns with the same line, exit 0.
MAC=$T/mac; mkdir -p $MAC
printf '#!/bin/sh\ncase "$1" in -m) echo ${FAKE_ARCH:-arm64};; *) echo ${FAKE_UNAME:-Darwin};; esac\n' > $MAC/uname
printf '#!/bin/sh\necho "$*" >> "$HOME/docker.log"\ncase "$1 $2" in "image inspect") exit 1;; esac\nexit 0\n' > $MAC/docker
printf '#!/bin/sh\nd=; v=; for a; do case $a in BUILD_DIR=*) d=${a#BUILD_DIR=};; VERSION=*) v=${a#VERSION=};; esac; done\necho "GOOS=$GOOS GOARCH=$GOARCH $*" >> "$HOME/make.log"\nmkdir -p "$d"; printf "#!/bin/sh\\necho mxcli version $v\\n" > "$d/mxcli"; chmod +x "$d/mxcli"\n' > $MAC/make
# MXCLI_REF: the source is fetched at the ref (never HEAD) by git, which is stubbed here; the stub make prints the VERSION it was given
printf '#!/bin/sh\necho "git $*" >> "$HOME/git.log"\nexit 0\n' > $MAC/git
printf '#!/bin/sh\nmkdir -p node_modules/playwright\n' > $MAC/npm
printf '#!/bin/sh\necho "$*" >> "$HOME/npx.log"\n' > $MAC/npx
chmod +x $MAC/*
mkdir -p $SC/mxsrc/.git $SC/haspw   # $SC/nopw stays absent
NM=$T/nomx; cp -a $NR $NM; rm -f $NM/mxcli   # a dev machine's own mxcli must not leak into the Linux-no-host case
macsetup() { local h=$1; shift; mkdir -p $SC/$h/.local/bin; env HOME=$SC/$h PATH=$MAC:$NM MXCLI_SRC=$SC/mxsrc UPG_PYTHON=$T/py-ok UPG_PW_OPT=$SC/nopw PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD= PLAYWRIGHT_BROWSERS_PATH= "$@" bash $B/setup-container.sh $SC/run-$h 11.6.3; }
mkdir -p $SC/mac-own/.local/bin; printf 'users own mxcli\n' > $SC/mac-own/.local/bin/mxcli
ctl setup-mxcli-linux-amd64-catch 0 'host mxcli left alone' -- macsetup mac-own UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-make-env-pass 0 '^GOOS=linux GOARCH=amd64 build ' -- cat $SC/mac-own/make.log
ctl setup-mxcli-mac-keeps-own-pass 0 '^users own mxcli$' -- cat $SC/mac-own/.local/bin/mxcli
ctl setup-mxcli-mac-none-nolink-run-pass 0 'host mxcli left alone \(none on PATH; Darwin host\)' -- macsetup mac-none UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-mac-none-nolink-catch 1 -- test -e $SC/mac-none/.local/bin/mxcli
ctl setup-mxcli-linux-nohost-pass 0 '!host mxcli left alone' -- macsetup mac-lin FAKE_UNAME=Linux UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-linux-nohost-link-pass 0 'run-mac-lin/tools/mxcli-bin/mxcli' -- readlink -f $SC/mac-lin/.local/bin/mxcli
ctl setup-images-run-pass 0 -- macsetup mac-img UPG_SETUP_STEPS=images
ctl setup-images-platform-catch 0 '^build --platform linux/amd64 -q --network host -t mig-mx10' '^build --platform linux/amd64 -q --network host -t e5-mx9' '^pull --platform linux/amd64 -q eclipse-temurin:11-jdk' -- cat $SC/mac-img/docker.log
ctl setup-images-platform-all-pass 0 '^all-amd64$' -- sh -c "grep -E '^(pull|build) ' $SC/mac-img/docker.log | grep -v -e '--platform linux/amd64' || echo all-amd64"
ctl setup-playwright-chromium-catch 0 'no /opt/pw-browsers: installing Chromium' -- macsetup mac-pw UPG_SETUP_STEPS=playwright
ctl setup-playwright-chromium-npx-pass 0 '^--yes playwright@1\.56\.1 install chromium$' -- cat $SC/mac-pw/npx.log
ctl setup-playwright-skip-nextstep-catch 0 'NEXT-STEP: Chromium not installed .*npx --yes playwright@1\.56\.1 install chromium' -- macsetup mac-pws PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 UPG_SETUP_STEPS=playwright
ctl setup-playwright-skip-no-npx-pass 1 -- test -e $SC/mac-pws/npx.log
ctl setup-playwright-cloud-pass 0 '!installing Chromium' '!NEXT-STEP' -- macsetup mac-pwc UPG_PW_OPT=$SC/haspw UPG_SETUP_STEPS=playwright
ctl setup-playwright-cloud-no-npx-pass 1 -- test -e $SC/mac-pwc/npx.log
mkdir -p $SC/tc-home
ctl toolcheck-host-chromium-warn-catch 0 'WARNING, no Chromium for Playwright .*cd ~/mendix-playwright && npx --yes playwright@1\.56\.1 install chromium' 'host OK' '!REFUSED' -- env HOME=$SC/tc-home PLAYWRIGHT_BROWSERS_PATH= UPG_PW_OPT=$SC/nopw UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
ctl toolcheck-host-chromium-pass 0 'host OK' '!Chromium' -- env HOME=$SC/tc-home PLAYWRIGHT_BROWSERS_PATH= UPG_PW_OPT=$SC/haspw UPG_PYTHON=$T/py-ok zsh $B/toolcheck.sh --host
ctl toolcheck-cdn-url-catch 2 'curl -fLO https://cdn\.mendix\.com/runtime/mxbuild-10\.24\.16\.96987\.tar\.gz' -- zsh $B/toolcheck.sh $TS/inc/mxbuild-10.24.16.96987 mxbuild
ctl heavy-lock-bash-pass 0 'ctl rc=0' -- env UPG_LOCK=$T/test.lock bash $B/heavy-lock.sh ctl true
ctl toolset-complete-pass 0 '^docker run .*-e HOME=/tmp .*modeler/mxbuild --java-home=/opt/java/openjdk --java-exe-path=/opt/java/openjdk/bin/java --target=package' '!toolcheck' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok zsh $B/mx10.sh 10.24.16 mxbuild --target=package x.mpr
ctl toolset-caller-flags-kept 0 '--java-home=/x x.mpr' '!openjdk' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_EXTRA="-e HOME=/w/h" zsh $B/mx10.sh 10.24.16 mxbuild --java-home=/x x.mpr
# M1: mxbuild 11.x on an arm64 host (amd64 emulation) runs through the LD_PRELOAD wrapper; amd64 hosts and 10.x are unchanged
mkdir -p $TS/ok/mxbuild-11.12.2/modeler/runtemplates/deployment $TS/ok/mxbuild-11.12.2/modeler/tools/node/node_modules
for x in mx mxbuild; do printf '#!/bin/sh\n' > $TS/ok/mxbuild-11.12.2/modeler/$x; chmod +x $TS/ok/mxbuild-11.12.2/modeler/$x; done
# FM-11: a bare subcommand gets mx put in front; an unknown tool and a missing toolset stay errors
ctl mx10-bare-subcommand-pass 0 "running: mx check" '^docker run .*mxbuild-10\.24\.16/modeler/mx check x\.mpr' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok zsh $B/mx10.sh 10.24.16 check x.mpr
ctl mx10-explicit-mx-pass 0 '^docker run .*mxbuild-10\.24\.16/modeler/mx check x\.mpr' '!running: mx' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok zsh $B/mx10.sh 10.24.16 mx check x.mpr
ctl mx10-no-toolset-bare-catch 2 'no .*mxbuild-9\.9\.9/modeler/check' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok zsh $B/mx10.sh 9.9.9 check x.mpr
ctl mx10-preload-arm64-catch 0 '^docker run .* sh -c .*libuuid\.so\.1.*libfreetype\.so\.6.*libfontconfig\.so\.1.*LD_PRELOAD.*exec "\$@" sh .*mxbuild-11\.12\.2/modeler/mx check x\.mpr' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_HOST_ARCH=arm64 zsh $B/mx10.sh 11.12.2 mx check x.mpr
ctl mx10-preload-amd64-pass 0 '^docker run .*mxbuild-11\.12\.2/modeler/mx check x\.mpr' '!LD_PRELOAD' '!sh -c' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_HOST_ARCH=x86_64 zsh $B/mx10.sh 11.12.2 mx check x.mpr
ctl mx10-preload-10x-arm64-pass 0 '^docker run .*mxbuild-10\.24\.16/modeler/mx check x\.mpr' '!LD_PRELOAD' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_HOST_ARCH=arm64 zsh $B/mx10.sh 10.24.16 mx check x.mpr
ctl mx10-preload-caller-wins-pass 0 'LD_PRELOAD=/x\.so' '!sh -c' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_HOST_ARCH=arm64 UPG_EXTRA="-e LD_PRELOAD=/x.so" zsh $B/mx10.sh 11.12.2 mx check x.mpr
# NR2-15: mxbuild 11.12 segfaults (rc 139) about one call in three: mx10.sh retries a crash before it counts. A fake docker
# crashes the first N calls (counter file), then succeeds; the retry sleep is 0.
mkdir -p $T/crashdocker
cat > $T/crashdocker/docker <<'EOF2'
#!/bin/sh
n=$(cat "$CRASH_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$CRASH_COUNT"
echo "partial output of call $n"
if [ "$n" -le "$CRASH_FIRST" ]; then [ -n "$CRASH_MSG" ] && echo "$CRASH_MSG" >&2; exit ${CRASH_RC:-139}; fi
echo "mx check done"; exit 0
EOF2
chmod +x $T/crashdocker/docker
rm -f $T/crash1.n; ctl mx10-crash-139-retry-pass 0 'mx check done' 'tool crash \(rc 139\), retry 1 of 2' '!call 1$' -- env "PATH=$T/crashdocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/crash1.n CRASH_FIRST=1 zsh $B/mx10.sh 10.24.16 mx check x.mpr
rm -f $T/crash2.n; ctl mx10-crash-139-gives-up-catch 139 'retry 2 of 2' '!mx check done' -- env "PATH=$T/crashdocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/crash2.n CRASH_FIRST=9 zsh $B/mx10.sh 10.24.16 mx check x.mpr
rm -f $T/crash3.n; ctl mx10-crash-off-streams-catch 139 '!retry' -- env "PATH=$T/crashdocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH_SLEEP=0 UPG_RETRY_CRASH=0 CRASH_COUNT=$T/crash3.n CRASH_FIRST=1 zsh $B/mx10.sh 10.24.16 mx check x.mpr
rm -f $T/crash4.n; ctl mx10-plain-failure-no-retry-pass 1 '!retry' -- env "PATH=$T/crashdocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/crash4.n CRASH_FIRST=9 CRASH_RC=1 zsh $B/mx10.sh 10.24.16 mx check x.mpr
rm -f $T/crash5.n; ctl mxcli-fix-aborted-retry-pass 0 'mx check done' 'tool crash \(rc 1\), retry 1 of 2' -- $NOPX UPG_DRYRUN= "PATH=$T/crashdocker:$PATH" HOME=$T/home UPG_TOOLS=$T/tools UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/crash5.n CRASH_FIRST=1 CRASH_RC=1 CRASH_MSG='signal: aborted' zsh $B/mxcli-container.sh fix widgets -p $T/relp/App.mpr
# FM-2: after an rc 139 retry the next call can die in the model loader on a model that is fine; one more retry, said as a flake.
mkdir -p $T/flakedocker
cat > $T/flakedocker/docker <<'EOF2'
#!/bin/sh
n=$(cat "$CRASH_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$CRASH_COUNT"
[ "$n" = 1 ] && [ "${FLAKE_CRASH:-1}" = 1 ] && exit 139
[ "$n" -le "$FLAKE_UNTIL" ] && { echo "Unhandled exception. System.NullReferenceException: Object reference not set to an instance of an object." >&2; exit 1; }
echo "mx check done"; exit 0
EOF2
chmod +x $T/flakedocker/docker
rm -f $T/flake1.n; ctl mx10-loader-flake-retry-pass 0 'mx check done' 'amd64 emulation flake, rerun' -- env "PATH=$T/flakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH=1 UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/flake1.n FLAKE_UNTIL=2 zsh $B/mx10.sh 10.24.16 mx check x.mpr
rm -f $T/flake2.n; ctl mx10-loader-error-without-crash-no-retry-catch 1 'Object reference not set' '!flake' '!mx check done' -- env "PATH=$T/flakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$TS/ok UPG_RETRY_CRASH=1 UPG_RETRY_CRASH_SLEEP=0 CRASH_COUNT=$T/flake2.n FLAKE_UNTIL=9 FLAKE_CRASH=0 zsh $B/mx10.sh 10.24.16 mx check x.mpr
# the image report: fake docker answers with the lib lines a real `sh -c` would print
printf '#!/bin/sh\ncase "$FAKE_LIBS" in all) printf "have libuuid.so.1\\nhave libfreetype.so.6\\nhave libfontconfig.so.1\\n";; *) printf "have libuuid.so.1\\nmissing libfreetype.so.6\\nmissing libfontconfig.so.1\\n";; esac\n' > $T/fakedocker/docker-libs
mkdir -p $T/fakedocker-libs; cp $T/fakedocker/docker-libs $T/fakedocker-libs/docker; chmod +x $T/fakedocker-libs/docker
ctl toolcheck-image-libs-missing-catch 0 'present 1/3.*missing: libfreetype\.so\.6 libfontconfig\.so\.1' -- env "PATH=$T/fakedocker-libs:$PATH" zsh $B/toolcheck.sh --image mig-mx10
ctl toolcheck-image-libs-pass 0 'present 3/3' '!missing' -- env "PATH=$T/fakedocker-libs:$PATH" FAKE_LIBS=all zsh $B/toolcheck.sh --image mig-mx10

# --- impact map: documents keyed by type and name, excluded pages skipped (E5b-18, E4-31) ----------------------------------
ctl impact-shared-name-pass 0 '!scheduled' '!still references' -- python3 $B/impact_map.py $M/sched-old $M/sched-new --md /dev/stdout --out $T/imp-sched.json
ctl impact-shared-name-catch 0 'Shop\.DeleteExpired.*removed' 'Shop\.Live_Page.*still references removed Vendor\.ACT_Gone' '!Example_Page.*still references' -- python3 $B/impact_map.py $M/sched-old $M/sched-gone --md /dev/stdout --out $T/imp-gone.json
# domain model (impact-dm-*): one document record per difference, named by module $DomainModel, entity and attribute; a flow
# that uses a changed entity is a caller record. Keyed by name: ids, GUIDs and attribute order print nothing (ids, reorder, self).
for v in dm-old dm-default dm-attr-added dm-attr-removed dm-type dm-validation dm-access dm-access-gain dm-entity-removed dm-ids dm-reorder; do model $v > /dev/null; done
DMO=$M/dm-old
ctl impact-dm-default-catch 0 '^- \[medium\] `PurchaseApprovals\.Request\.Status`: default: .Pending_Approval. -> .Finished.$' \
  '^- \[medium\] `PurchaseApprovals\.ACT_Submit`: uses PurchaseApprovals\.Request \(Status default\)$' '!still references' \
  -- python3 $B/impact_map.py $DMO $M/dm-default --md /dev/stdout --out $T/imp-dm-default.json
ctl impact-dm-default-record-pass 0 '^document PurchaseApprovals\.Request\.Status PurchaseApprovals\.\$DomainModel default: .Pending_Approval. -> .Finished.$' \
  -- python3 -c "import json; d=json.load(open('$T/imp-dm-default.json')); [print(c['kind'], c['qn'], c['doc'], c['detail']) for c in d['changes'] if c['qn'].endswith('Status')]"
ctl impact-dm-attr-added-catch 0 '^- \[low\] `PurchaseApprovals\.Request\.Priority`: attribute added \(Integer\)$' '!PurchaseApprovals\.ACT_Submit' '!still references' \
  -- python3 $B/impact_map.py $DMO $M/dm-attr-added --md /dev/stdout --out $T/imp-dm-attr-added.json
ctl impact-dm-attr-removed-catch 0 '^- \[high\] `PurchaseApprovals\.Request\.Note`: attribute removed \(was String\)$' \
  '^- \[high\] `PurchaseApprovals\.ACT_Submit`: uses PurchaseApprovals\.Request \(Note attribute removed\)$' \
  -- python3 $B/impact_map.py $DMO $M/dm-attr-removed --md /dev/stdout --out $T/imp-dm-attr-removed.json
ctl impact-dm-type-catch 0 '^- \[high\] `PurchaseApprovals\.Request\.Amount`: type Integer -> String$' \
  '^- \[high\] `PurchaseApprovals\.ACT_Submit`: uses PurchaseApprovals\.Request \(Amount type Integer -> String\)$' \
  -- python3 $B/impact_map.py $DMO $M/dm-type --md /dev/stdout --out $T/imp-dm-type.json
ctl impact-dm-validation-catch 0 '^- \[medium\] `PurchaseApprovals\.Request\.Status`: validation: \[\] -> \[Unique\]$' '!`PurchaseApprovals\.Request\.Amount`' \
  -- python3 $B/impact_map.py $DMO $M/dm-validation --md /dev/stdout --out $T/imp-dm-validation.json
# access: compared rule by rule (keyed by role set) and member by member; high only when a user can lose something
ctl impact-dm-access-catch 0 '^- \[high\] `PurchaseApprovals\.Request`: access rule for PurchaseApprovals\.Clerk: create removed; default member rights ReadOnly -> None$' \
  '^- \[medium\] `PurchaseApprovals\.ACT_Submit`: uses PurchaseApprovals\.Request \(access rule for PurchaseApprovals\.Clerk\)$' \
  -- python3 $B/impact_map.py $DMO $M/dm-access --md /dev/stdout --out $T/imp-dm-access.json
ctl impact-dm-access-gain-pass 0 '^- \[medium\] `PurchaseApprovals\.Request`: access rule for PurchaseApprovals\.Clerk: default member rights ReadOnly -> ReadWrite$' \
  '!\[high\]' -- python3 $B/impact_map.py $DMO $M/dm-access-gain --md /dev/stdout --out $T/imp-dm-access-gain.json
ctl impact-dm-entity-removed-catch 0 '^- \[high\] `PurchaseApprovals\.Legacy`: entity removed$' \
  '^- \[high\] `PurchaseApprovals\.ACT_Legacy`: still references removed entity PurchaseApprovals\.Legacy$' '!`PurchaseApprovals\.Legacy\.Code`' \
  -- python3 $B/impact_map.py $DMO $M/dm-entity-removed --md /dev/stdout --out $T/imp-dm-entity-removed.json
ctl impact-dm-self-pass 0 '^0 changes \(0 high\)' '!^- \[' -- python3 $B/impact_map.py $DMO $DMO --md /dev/stdout --out $T/imp-dm-self.json
ctl impact-dm-ids-pass 0 '^0 changes \(0 high\)' '!^- \[' -- python3 $B/impact_map.py $DMO $M/dm-ids --md /dev/stdout --out $T/imp-dm-ids.json
ctl impact-dm-reorder-pass 0 '^0 changes \(0 high\)' '!^- \[' -- python3 $B/impact_map.py $DMO $M/dm-reorder --md /dev/stdout --out $T/imp-dm-reorder.json

# --- journeys generator: anonymous roles, layout-safe guards, homes without a menu, unreachable pages (E4-11, E4-12, E5b-6/9/10/11/12/22/24)
cp $FX/journeys/impact-nav.json $T/impact-nav.json   # relative MPR paths, resolved against the impact file (E5b-24)
GJ="python3 $B/gen_journeys.py $T/impact-nav.json"
G=$T/gen-nav; (cd / && $GJ --out-dir $G --roles-with-users Admin,Clerk > /dev/null 2>&1)
GA=$T/gen-nav-admin; (cd / && $GJ --out-dir $GA --roles-with-users Admin > /dev/null 2>&1)
ctl gen-anonymous-invalid-catch 0 '"id": "anonymous-Guest"' '"why": "anonymous role' -- python3 -c "import json; print(json.dumps(json.load(open('$G/plan.json'))['skipped'], indent=1))"
# S (quality-judgement L3): plan.json names the anonymous role when guest access is on, and null when it is off
ctl gen-anonymous-role-pass 0 '^Guest$' -- python3 -c "import json; print(json.load(open('$G/plan.json'))['anonymous_role'])"
ctl gen-relative-model-pass 0 'using grid1' '!new model not loaded' -- sh -c "cd / && $GJ --out-dir $T/gen-nav-rel --roles-with-users Admin,Clerk 2>&1"
ctl gen-landing-layout-catch 0 '"ready": ".mx-name-grid1"' '!container1' -- cat $G/journeys/Admin/login-Admin.journey.json
ctl gen-landing-conditional-pass 0 '!grid9' -- cat $G/journeys/Admin/login-Admin.journey.json
# T8R B2-3: a role whose home page is a login form (an API-only role) gets no login journey; it is listed as not_browser
model nav-api > /dev/null; cp $FX/journeys/impact-nav-api.json $T/impact-nav-api.json
GP=$T/gen-nav-api; (cd / && python3 $B/gen_journeys.py $T/impact-nav-api.json --out-dir $GP --roles-with-users Admin,Clerk,ApiUser > $T/gen-nav-api.out 2>&1)
ctl gen-api-role-catch 0 "^nb login-ApiUser API-only role: its home page Shop.Login_Web holds a login form" '!^journey login-ApiUser' -- python3 -c "import json; p=json.load(open('$GP/plan.json')); [print('journey', j if isinstance(j, str) else j['id']) for j in p['journeys']]; [print('nb', e['id'], e.get('why', '')) for e in p['not_browser']]"
ctl gen-api-role-pass 0 '^journey login-Admin$' '^journey login-Clerk$' -- python3 -c "import json; p=json.load(open('$GP/plan.json')); [print('journey', j if isinstance(j, str) else j['id']) for j in p['journeys']]"
# T1-guard: a guard inside a list row (renders only with data) or under a hidden parent is never picked
LR=$(model listrow); LW="import sys; sys.path.insert(0, '$B'); import mprmodel as P, impact_map as I; print(I.landing_widget(P.Model.load('$LR/App.mpr'), sys.argv[1]))"
ctl landing-listrow-catch 0 "'widget': 'PageTitle'" '!T_ButtonContainer6' '!HiddenNote' -- python3 -c "$LW" Shop.Inbox
ctl landing-listrow-pass 0 "'widget': 'T_ButtonContainer6'" -- python3 -c "$LW" Shop.Plain
ctl gen-home-nomenu-catch 0 '"Scan the code with your app"' '!"Home"' '!Shown only on error' -- cat $G/journeys/Clerk/login-Clerk.journey.json
ctl gen-home-menu-pass 0 "textPresent \['Home'\]" -- python3 -c "import json; print('textPresent', json.load(open('$G/journeys/Admin/login-Admin.journey.json'))['steps'][0]['ui']['textPresent'])"
# N1-3: the layout of the page reached after login has a menu widget without a known source (older models): the
# captions cannot be proven on screen, so no textPresent is emitted (the READY selector decides) and the omission is told
model nav-nosrc > /dev/null; cp $FX/journeys/impact-nav-nosrc.json $T/impact-nav-nosrc.json
GN=$T/gen-nav-nosrc; (cd / && python3 $B/gen_journeys.py $T/impact-nav-nosrc.json --out-dir $GN --roles-with-users Admin > /dev/null 2>&1)
ctl gen-home-menu-unproven-catch 0 '"ready": ".mx-name-grid1"' '!textPresent"' '_textPresent_omitted' -- cat $GN/journeys/Admin/login-Admin.journey.json
ctl gen-unreachable-catch 0 "unreachable.*'page:Shop.Orphan'.*'page:Shop.Orphan_Child'" -- python3 -c "import json; p=json.load(open('$G/plan.json')); print('unreachable', [e['id'] for e in p['unreachable']])"
ctl gen-reachable-pass 0 'todo.*page:Shop.Detail' -- python3 -c "import json; p=json.load(open('$G/plan.json')); print('todo', [e['id'] for e in p['todo']])"
ctl gen-covered-catch 0 "covered.*home:Shop.Home.*home:Shop.Popup_Home" -- python3 -c "import json; p=json.load(open('$G/plan.json')); print('covered', [e['id'] for e in p['covered']])"
ctl gen-covered-pass 0 "todo.*home:Shop.Popup_Home" -- python3 -c "import json; p=json.load(open('$GA/plan.json')); print('todo', [e['id'] for e in p['todo']])"
ctl gen-signout-catch 0 '"id": "sign-out"' 'SignOut|Sign out' -- cat $G/journeys/Admin/sign-out.journey.json
ctl gen-signout-pass 0 "todo.*'sign-out'" -- sh -c "cd / && $GJ --out-dir $T/gen-nav-clerk --roles-with-users Clerk > /dev/null 2>&1; python3 -c \"import json; p=json.load(open('$T/gen-nav-clerk/plan.json')); print('todo', [e['id'] for e in p['todo']])\""
ctl gen-create-no-data-rung-catch 0 '"textPresent"' 'Item \$\{RUN_ID\}' '!"creates"' -- sh -c "$GJ --out-dir $T/gen-create --create $FX/journeys/create-spec.json > /dev/null 2>&1; cat $T/gen-create/journeys/Admin/create-save.journey.json"
ctl gen-create-data-rung-pass 0 '"creates": "Shop.Item"' -- sh -c "$GJ --out-dir $T/gen-create2 --create $FX/journeys/create-spec.json --data-rung > /dev/null 2>&1; cat $T/gen-create2/journeys/Admin/create-save.journey.json"
# E2E-9: a field that names its attribute adds the own-row check (the run's own ${RUN_ID} row, expect 1); none is warned
python3 -c "import json; d=json.load(open('$FX/journeys/create-spec.json')); d['fields'][0]['attr']='Name'; json.dump(d, open('$T/create-spec-attr.json', 'w'))"
ctl gen-create-own-row-pass 0 "SELECT COUNT\\(\\*\\) AS n FROM Shop.Item WHERE Name = 'Item \\$\\{RUN_ID\\}'" '"expect": 1' -- sh -c "$GJ --out-dir $T/gen-create3 --create $T/create-spec-attr.json --data-rung > /dev/null 2>&1; cat $T/gen-create3/journeys/Admin/create-save.journey.json"
ctl gen-create-own-row-missing-catch 0 'no field names its attribute.*own .*row' -- $GJ --out-dir $T/gen-create4 --create $FX/journeys/create-spec.json --data-rung
# R1: a "path" in the spec puts its clicks between the menu item and the New button, in order (Vendors overview link)
python3 -c "import json; d=json.load(open('$FX/journeys/create-spec.json')); d['path']=[{'widget':'linkVendors','label':'Vendors overview'}]; json.dump(d, open('$T/create-spec-path.json', 'w'))"
ctl gen-create-path-pass 0 '"do": "nav"[^}]*}, \{"do": "click", "widget": "linkVendors", "label": "Vendors overview"}, \{"do": "click", "widget": "[A-Za-z0-9]+", "label": "New"}' -- sh -c "$GJ --out-dir $T/gen-create5 --create $T/create-spec-path.json > /dev/null 2>&1; python3 -c \"import json,sys; d=json.load(open('$T/gen-create5/journeys/Admin/create-save.journey.json')); print(json.dumps(d['steps'][0]['actions']))\""
ctl gen-create-nopath-catch 0 '"do": "nav"[^}]*}, \{"do": "click", "widget": "[A-Za-z0-9]+", "label": "New"}' '!linkVendors' -- sh -c "$GJ --out-dir $T/gen-create6 --create $FX/journeys/create-spec.json > /dev/null 2>&1; python3 -c \"import json,sys; d=json.load(open('$T/gen-create6/journeys/Admin/create-save.journey.json')); print(json.dumps(d['steps'][0]['actions']))\""
ctl gen-create-bare-warns 0 'warning: create-save: spec has no textPresent' -- $GJ --out-dir $T/gen-create3 --create $FX/journeys/create-spec-bare.json
# v3.1 E7-2: a microflow menu target that shows two pages gets a union guard (either branch passes); a branch page
# without a landing widget is a todo with _branches, never the first page. E6-18: guards exist on the OLD page too.
for v in menu-old menu-new; do model $v > /dev/null; done
cp $FX/journeys/impact-menu.json $T/impact-menu.json
GM=$T/gen-menu; (cd / && python3 $B/gen_journeys.py $T/impact-menu.json --out-dir $GM --roles-with-users Admin > $T/gen-menu.out 2>&1)
ctl gen-branches-union-catch 0 '"ready": ".mx-name-teamDetailView, .mx-name-teamsGrid"' '"_branches"' -- cat $GM/journeys/Admin/menu_Teams-Admin.journey.json
ctl gen-branches-single-pass 0 '"ready": ".mx-name-teamDetailView"' '!_branches' -- cat $GM/journeys/Admin/menu_One-Admin.journey.json
ctl gen-branches-todo-catch 0 "todo menu:Bare .*Shop.Bare.*'widget': None" '!menu_Bare' -- sh -c "python3 -c \"import json; p=json.load(open('$GM/plan.json')); [print('todo', t['id'], t['_branches']) for t in p['todo'] if t.get('_branches')]\"; ls $GM/journeys/Admin"
ctl gen-old-model-catch 0 '"ready": ".mx-name-providerGrid"' '!idpPanel' -- cat $GM/journeys/Admin/menu_Saml-Admin.journey.json
ctl gen-old-model-unchanged-pass 0 '"ready": ".mx-name-freshGrid"' -- cat $GM/journeys/Admin/menu_Fresh-Admin.journey.json
ctl gen-old-model-none-catch 0 '"ready": ".mx-page"' 'no landing widget on both the old and the new page \(new only: newGrid\)' -- sh -c "cat $GM/journeys/Admin/menu_Rebuilt-Admin.journey.json; cat $T/gen-menu.out"
# E6-20 + F24 (Purchase Request 10.24, user decision): module-pages proves every page a user can reach; a page no entry
# point reaches (dead in the UI, before and after) is listed as unreachable (INFO), the single-page rule, never silent
ctl gen-module-pages-targets-pass 0 "^targets \['Shop.Home'\] dead \['Shop.Orphan'\]$" -- python3 -c "import json; p=json.load(open('$GM/plan.json')); [print('targets', r['targets'], 'dead', r.get('dead')) for r in p['not_browser'] if r['id'] == 'module-pages:Shop']"
ctl gen-module-pages-dead-catch 0 '^page:Shop.Orphan module-pages:Shop$' '!page:Shop.Home' -- python3 -c "import json; p=json.load(open('$GM/plan.json')); [print(r['id'], r.get('module_pages')) for r in p['unreachable']]"
# F24: a page with a URL is an entry point (address bar, bookmark), so a URL page is never dead
ER="import sys; sys.path.insert(0, '$B'); import gen_journeys as g
class D:
    def __init__(s, t, url=''): s.type, s.module, s.data = t, 'M', {'Url': url}
class Mo:
    def __init__(s, url): s.docs = {'M.Page': D('Forms\$Page', url), 'M.Sub': D('Forms\$Page')}
    def navigation(s): return {}
    def refs(s, q): return ['M.Sub'] if q == 'M.Page' else []"
ctl gen-entry-url-pass 0 "^\['M.Page', 'M.Sub'\]$" -- python3 -c "$ER
print(sorted(g.entry_reach(Mo('/p/page'))))"
ctl gen-entry-nourl-catch 0 '^\[\]$' -- python3 -c "$ER
print(sorted(g.entry_reach(Mo('  '))))"
# Batch 1 (T1-25, T2-10, T2-11, T4-6, T4-7, T4-8, T6-14): journeys that FAILed or stayed INVALID on healthy OLD apps for
# instrument reasons. impact-guard.json holds role facts as the old impact_map wrote them; gen_journeys re-checks them.
model guard > /dev/null
cp $FX/journeys/impact-guard.json $T/impact-guard.json
GG=$T/gen-guard; (cd / && python3 $B/gen_journeys.py $T/impact-guard.json --out-dir $GG --roles-with-users Worker,Manager,Inspector,Planner > $T/gen-guard.out 2>&1)
ctl gen-journeys-guard-in-listview-catch 0 '"ready": ".mx-name-layoutGrid1"' '!T_ButtonContainer6' -- cat $GG/journeys/Worker/login-Worker.journey.json
ctl gen-journeys-guard-in-listview-note 0 'login-Worker: landing guard T_ButtonContainer6 is not a widget that renders once' -- cat $T/gen-guard.out
ctl gen-journeys-guard-param-catch 0 '"ready": ".mx-name-dataView2"' '!NotificationFilterHelperNP' -- cat $GG/journeys/Worker/menu_Notifications-Worker.journey.json
ctl gen-journeys-guard-snippet-param-catch 0 '"ready": ".mx-name-label3"' '!ClientFilterHelperNP' '!snippetCall1' -- cat $GG/journeys/Manager/login-Manager.journey.json
ctl gen-journeys-guard-dataview-pass 0 '^Shop.Board boardView$' '^Shop.Phone_Home label9$' '^Shop.Inbox layoutGrid1$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$M/guard'); [print(q, I.landing_widget(m, q)['widget']) for q in ('Shop.Board','Shop.Phone_Home','Shop.Inbox')]"
GTA="import json; [print(r, json.load(open('$GG/journeys/%s/login-%s.journey.json' % (r, r)))['steps'][0]['ui'].get('textAbsent')) for r in ('Worker','Manager','Planner')]"
ctl gen-journeys-textabsent-own-caption-catch 0 "^Worker \['Board'\]$" "^Manager \['Inbox', 'Board', 'Notifications'\]$" "^Planner \['An error occurred', 'You do not have access', 'Access denied'\]$" -- python3 -c "$GTA"
# S: guest access off (guard fixture: EnableGuestAccess false) gives a null anonymous_role, so no anonymous denominator
ctl gen-anonymous-role-off-pass 0 '^None$' -- python3 -c "import json; print(json.load(open('$GG/plan.json'))['anonymous_role'])"
ctl gen-journeys-textabsent-omitted-noted 0 "Buffer', 'Client Configuration'\]: not asserted absent" -- cat $GG/journeys/Worker/login-Worker.journey.json
ctl gen-journeys-phone-layout-catch 0 'layout renders another menu than the Responsive profile' '"Scan the next inspection lot"' '!"Inbox"' -- cat $GG/journeys/Inspector/login-Inspector.journey.json
ctl gen-journeys-microflow-home-closes-pass 0 '^closes \[.home:Shop.NAV_Planner.\]$' "^covered home:Shop.NAV_Planner login-Planner$" '^todo \[.create-save.\]$' -- python3 -c "import json; j=json.load(open('$GG/journeys/Planner/login-Planner.journey.json')); p=json.load(open('$GG/plan.json')); print('closes', j.get('closes')); [print('covered', c['id'], c.get('closed_by')) for c in p['covered'] if c.get('closed_by')]; print('todo', [t['id'] for t in p['todo']])"
# the closing login journey must prove the microflow's page opened: its landing widget and no error text, never the
# bare .mx-page + menu captions an error or fallback page also shows; a shown page with no guard keeps the home a todo
ctl gen-journeys-microflow-home-guard-catch 0 '"ready": ".mx-name-boardView"' '"An error occurred"' -- cat $GG/journeys/Planner/login-Planner.journey.json
sed 's/NAV_Planner/NAV_Bare/g' $FX/journeys/impact-guard.json > $T/impact-guard-bare.json
GB=$T/gen-guard-bare; (cd / && python3 $B/gen_journeys.py $T/impact-guard-bare.json --out-dir $GB --roles-with-users Worker,Manager,Inspector,Planner > /dev/null 2>&1)
ctl gen-journeys-microflow-home-unguarded-catch 0 '^closes None$' "^todo \['create-save', 'home:Shop.NAV_Bare'\]$" '!covered home:Shop.NAV_Bare' -- python3 -c "import json; j=json.load(open('$GB/journeys/Planner/login-Planner.journey.json')); p=json.load(open('$GB/plan.json')); print('closes', j.get('closes')); [print('covered', c['id']) for c in p['covered']]; print('todo', [t['id'] for t in p['todo']])"
ctl gen-journeys-layout-signout-catch 0 '"group": "Account"' '"item": "Sign out"' 'menu widget menuBar2' -- cat $GG/journeys/Worker/sign-out.journey.json
# Batch 2 (B2-2, B2-3, G-3, T2R3-4, N1R2-3): guards that exist but are not visible, an API-only role, an icon-only layout
# user menu, page texts that are not on screen. impact-guard2.json holds role facts as the old impact_map wrote them.
model guard2 > /dev/null
cp $FX/journeys/impact-guard2.json $T/impact-guard2.json
G2=$T/gen-guard2; (cd / && python3 $B/gen_journeys.py $T/impact-guard2.json --out-dir $G2 --roles-with-users ApiUser,Desk,Planner,Inspector,Clerk > $T/gen-guard2.out 2>&1)
ctl gen-journeys-guard-title-over-dataview-catch 0 '"ready": ".mx-name-pageTitle1"' '!dataView1' -- cat $G2/journeys/Desk/login-Desk.journey.json
ctl gen-journeys-guard-title-repick-note 0 'login-Planner: landing guard dataView1 is a data view and the page has a title widget.*\(B2-2\); using pageTitle1' -- cat $T/gen-guard2.out
ctl gen-journeys-guard-dataview-no-title-pass 0 '^Shop.Board boardView$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$M/guard'); print('Shop.Board', I.landing_widget(m, 'Shop.Board')['widget'])"
ctl gen-journeys-guard-tabpage-catch 0 '"ready": ".mx-name-tabControl1"' '!dataView2' -- cat $G2/journeys/Planner/menu_Offline-Planner.journey.json
ctl gen-journeys-guard-tabpage-default-pass 0 '"ready": ".mx-name-dataView2"' -- cat $G2/journeys/Planner/menu_Offline_default-Planner.journey.json
ctl gen-journeys-guard-hide-on-catch 0 '"ready": ".mx-name-label6"' '!dataView3' -- cat $G2/journeys/Planner/menu_Hidden-Planner.journey.json
ctl gen-journeys-guard-hide-on-pass 0 '"ready": ".mx-name-dataView3"' -- cat $G2/journeys/Planner/menu_Shown-Planner.journey.json
ctl gen-journeys-api-only-role-catch 0 'not_browser login-ApiUser API-only role: its home page is the login page Shop.Login.*not a licence or session-cap failure, B2-3' '!^skipped login-ApiUser' '^dirs Clerk Desk Inspector Planner$' '^personas Desk Planner$' -- python3 -c "import json, os; p=json.load(open('$G2/plan.json')); [print('skipped', s['id'], s['why']) for s in p['skipped']]; [print('not_browser', s['id'], s['why']) for s in p['not_browser']]; print('dirs', *sorted(os.listdir('$G2/journeys'))); print('personas', *sorted({j['role'] for j in p['journeys'] if j['id'].startswith(('mfa', 'sign-out', 'menu'))}))"
ctl gen-journeys-api-only-role-pass 0 '"id": "login-Clerk"' -- cat $G2/journeys/Clerk/login-Clerk.journey.json
# T7 (template-upgrade batch 1): a Set URL / timer / listen-to widget renders nothing, and as the guard it was the first
# DOM match, so every login journey FAILed on a healthy app. Fixture modelled on the field report, not captured live.
model guard-invisible > /dev/null
cp $FX/journeys/impact-guard-invisible.json $T/impact-guard-invisible.json
GI=$T/gen-guard-invisible; (cd / && python3 $B/gen_journeys.py $T/impact-guard-invisible.json --out-dir $GI --roles-with-users Desk,Planner,Clerk,Inspector,Auditor,Lead > $T/gen-guard-invisible.out 2>&1)
ctl gen-journeys-guard-seturl-catch 0 '"ready": ".mx-name-label3"' '!setURL' -- cat $GI/journeys/Desk/login-Desk.journey.json
ctl gen-journeys-guard-timer-listento-catch 0 '"ready": ".mx-name-label4"' '!timer1' '!listenTo1' -- cat $GI/journeys/Planner/login-Planner.journey.json
ctl gen-journeys-guard-seturl-only-catch 0 '"ready": ".mx-page"' '!setURL' -- cat $GI/journeys/Clerk/login-Clerk.journey.json
ctl gen-journeys-guard-seturl-renamed-catch 0 '"ready": ".mx-name-label11"' '!redirectTarget' -- cat $GI/journeys/Auditor/login-Auditor.journey.json
ctl gen-journeys-guard-generic-name-catch 0 '"ready": ".mx-name-label12"' '!timer2' -- cat $GI/journeys/Lead/login-Lead.journey.json
ctl gen-journeys-guard-visible-widget-pass 0 '"ready": ".mx-name-label9"' -- cat $GI/journeys/Inspector/login-Inspector.journey.json
ctl gen-journeys-layout-signout-icon-catch 0 '^click menuBar2-1 None$' '^click menuBar2-1-1 Sign out$' '^from layout of Shop.Dashboard, menu widget menuBar2$' '!nav' -- python3 -c "import json; j=json.load(open('$G2/journeys/Desk/sign-out.journey.json')); [print(a['do'], a.get('widget'), a.get('label')) for a in j['steps'][0]['actions']]; print('from', j['_sign_out_from'])"
ctl gen-journeys-layout-signout-icon-pass 0 "^\{'path': \['Account', 'Sign out'\], 'widget': 'menuBar2', 'clicks': \['menuBar2-0', 'menuBar2-0-1'\], 'by': 'action', 'detail': 'Forms\\\$SignOutClientAction'\}$" -- python3 -c "import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$M/guard'); print(I.layout_sign_out(m, 'Shop.Inbox'))"
ctl gen-journeys-home-texts-placeholder-catch 0 '"Find a work order"' '!Type search text' '!"Home"' -- cat $G2/journeys/Inspector/login-Inspector.journey.json
ctl gen-journeys-home-texts-title-widget-pass 0 '"Orders overview"' '!Type search text' -- cat $G2/journeys/Clerk/login-Clerk.journey.json
ctl gen-journeys-home-texts-popup-title-pass 0 "^Shop.Popup_Title \['Confirm your account', 'Enter the code'\]$" "^Shop.Search_Home \['Find a work order'\]$" -- python3 -c "import sys; sys.path.insert(0,'$B'); import gen_journeys as G, mprmodel; m=mprmodel.Model.load('$M/guard2'); [print(q, G.home_texts(m, q)) for q in ('Shop.Popup_Title', 'Shop.Search_Home')]"
# B4T2-4: a layout menu-bar sign-out that is no Forms$SignOutClientAction: a microflow/nanoflow that reaches a sign-out
# (direct or two calls deep), or a sign-out caption; inferred, marked _sign_out_by; nothing found names every menu
# looked at and why it failed (add-on menu document missing, items listed). guard5.json: one role per case.
model guard5 > /dev/null
cp $FX/journeys/impact-guard5.json $T/impact-guard5.json
G5=$T/gen-guard5; for r in Flow Caption Deep Addon,None Both; do (cd / && python3 $B/gen_journeys.py $T/impact-guard5.json --out-dir $G5/$r --roles-with-users $r > $G5-$r.out 2>&1); done
SO5() { python3 -c "import json; j=json.load(open('$G5/$1/journeys/$1/sign-out.journey.json')); [print(a['do'], a.get('widget') or a.get('group'), a.get('item') or a.get('label')) for a in j['steps'][0]['actions']]; print('by', j.get('_sign_out_by')); print('ready', j['steps'][0]['ui']['ready'])"; }
ctl gen-journeys-signout-flow-catch 0 '^click menuBar2-0 None$' '^click menuBar2-0-1 Sign out$' '^by inferred from the flow: MicroflowAction reaches Shop.ACT_Logout' '^ready .mx-name-loginButton$' -- SO5 Flow
ctl gen-journeys-signout-caption-catch 0 "^nav None Log out$" "^by inferred from the caption: caption 'Log out'" -- SO5 Caption
ctl gen-journeys-signout-deep-catch 0 '^nav Account Leave$' '^by inferred from the flow: MicroflowAction reaches Shop.JS_SignOut' -- SO5 Deep
ctl gen-journeys-signout-action-wins-pass 0 '^by None$' '^nav None Sign out$' '!Log out' -- SO5 Both
ctl gen-journeys-signout-why-catch 0 'Shop.Layout_D.menuBar2 \(menu EXFN_Addon.User_Menu\): menu document not in the model' "Shop.Layout_E.menuBar2 \(menu Shop.User_Menu_None\): 3 items, none signs out: 'Help' FormAction" '!^sign-out\.journey\.json$' -- sh -c "ls $G5/Addon,None/journeys/*/ ; python3 -c \"import json; [print(t['id'], t['why']) for t in json.load(open('$G5/Addon,None/plan.json'))['todo'] if t['id']=='sign-out']\""
ctl gen-journeys-signout-probe-pass 0 "^Shop.Home_A flow \['menuBar2-0', 'menuBar2-0-1'\]$" '^Shop.Home_B caption ' '^Shop.Home_C flow ' '^Shop.Home_D None$' '^Shop.Home_E None$' '^Shop.Home_F action ' -- python3 -c "import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$M/guard5'); [print(q, *((r['by'], r.get('clicks')) if (r:=I.layout_sign_out(m, q)) else (None,))) for q in ['Shop.Home_'+c for c in 'ABCDEF']]"
# T6R-3: a data view on a microflow/nanoflow/association/association-path source renders only with data: no guard, nor
# anything inside it; a widget around one is the last resort; a page-parameter data view stays a guard; nothing left: todo
model guard3 > /dev/null
G3PY="import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$M/guard3'); w=lambda p: (I.landing_widget(m, 'Shop.' + p) or {}).get('widget')"
ctl gen-journeys-guard-dataview-microflow-catch 0 '^Home_Mf actionButton2$' '!dataView3' '!label3' -- python3 -c "$G3PY; print('Home_Mf', w('Home_Mf'))"
ctl gen-journeys-guard-dataview-sources-catch 0 '^Home_Nf label4$' '^Home_Path label5$' '^Home_Assoc label6$' -- python3 -c "$G3PY; [print(p, w(p)) for p in ('Home_Nf', 'Home_Path', 'Home_Assoc')]"
ctl gen-journeys-guard-dataview-page-param-pass 0 '^Order_Edit dataView7$' -- python3 -c "$G3PY; print('Order_Edit', w('Order_Edit'))"
ctl gen-journeys-guard-dataview-around-last-pass 0 '^Grid_Only layoutGrid3$' -- python3 -c "$G3PY; print('Grid_Only', w('Grid_Only'))"
ctl gen-journeys-guard-dataview-only-catch 0 '^Only_Dependent None$' -- python3 -c "$G3PY; print('Only_Dependent', w('Only_Dependent'))"
cp $FX/journeys/impact-guard3.json $T/impact-guard3.json
G3=$T/gen-guard3; (cd / && python3 $B/gen_journeys.py $T/impact-guard3.json --out-dir $G3 --roles-with-users Inspector,Planner > /dev/null 2>&1)
ctl gen-journeys-guard-dataview-home-closes-pass 0 "^ready .mx-name-actionButton2 closes \['home:Shop.NAV_Inspector'\]$" -- python3 -c "import json; j=json.load(open('$G3/journeys/Inspector/login-Inspector.journey.json')); print('ready', j['steps'][0]['ui']['ready'], 'closes', j.get('closes'))"
ctl gen-journeys-guard-dataview-home-todo-catch 0 '^closes None$' 'home:Shop.NAV_Only: no landing widget' -- python3 -c "import json; j=json.load(open('$G3/journeys/Planner/login-Planner.journey.json')); print('closes', j.get('closes')); print(j.get('_closes_not'))"
# T6R-3b: a microflow home that shows its page through a sub-microflow (T6R Admin/DepartmentManager: DeepLink, then a
# sub-microflow) is resolved through the calls (3 levels) and closed by login-<role>; a home whose page is still not
# resolved stays a todo whose why says exactly that, never "role home of a role with no login journey" when it has one
model guard4 > /dev/null
cp $FX/journeys/impact-guard4.json $T/impact-guard4.json
G4=$T/gen-guard4; (cd / && python3 $B/gen_journeys.py $T/impact-guard4.json --out-dir $G4 --roles-with-users Admin,Deep,Service > /dev/null 2>&1)
G4P="import json; p=json.load(open('$G4/plan.json')); [print('todo', t['id'], t['why']) for t in p['todo'] if t['id'].startswith('home:')]; [print('covered', c['id'], c.get('closed_by')) for c in p['covered']]"
ctl gen-journeys-home-subflow-resolve-pass 0 "^Shop.NAV_Admin \['Shop.Settings_Overview'\]$" "^Shop.NAV_Service \[\]$" -- python3 -c "import sys; sys.path.insert(0,'$B'); import gen_journeys as G, mprmodel; m=mprmodel.Model.load('$M/guard4'); [print(q, G.shown_pages(m, q)) for q in ('Shop.NAV_Admin', 'Shop.NAV_Service')]"
ctl gen-journeys-home-subflow-closes-pass 0 "^ready .mx-name-settingsTitle closes \['home:Shop.NAV_Admin'\]$" -- python3 -c "import json; j=json.load(open('$G4/journeys/Admin/login-Admin.journey.json')); print('ready', j['steps'][0]['ui']['ready'], 'closes', j.get('closes'))"
ctl gen-journeys-home-subflow-covered-pass 0 '^covered home:Shop.NAV_Admin login-Admin$' '!todo home:Shop.NAV_Admin' -- python3 -c "$G4P"
ctl gen-journeys-home-subflow-depth-catch 0 '^todo home:Shop.NAV_Deep login-Deep walks this role home but cannot close it: .*shows no page we can resolve.*calls deeper than 3 levels not followed \(Shop.L4\)' '!covered home:Shop.NAV_Deep' -- python3 -c "$G4P"
ctl gen-journeys-home-no-page-catch 0 '^todo home:Shop.NAV_Service login-Service walks this role home but cannot close it: .*microflow Shop.NAV_Service shows no page we can resolve: no show-page action in it and it calls no microflow' '!covered home:Shop.NAV_Service' -- python3 -c "$G4P"
ctl gen-journeys-home-todo-text-catch 0 '^todo home:Shop.NAV_Clerk role home of Clerk: none of these roles has a login journey' '!todo home:Shop.NAV_(Admin|Deep|Service) role home of' -- python3 -c "$G4P"
# a microflow home closed by login-<role> takes that journey's verdict (FAIL stays FAIL, never INFO)
mkdir -p $T/gen-mfh $T/rjmf/after $T/rjmf2/after
echo '{"journeys": [], "skipped": [], "todo": [], "covered": [{"id": "home:Shop.NAV_Planner", "role": "Planner", "closed_by": "login-Planner", "why": "walked by login-Planner"}], "unreachable": []}' > $T/gen-mfh/plan.json
echo '{"journeys": {"login-Planner": {"role": "Planner", "verdict": "FAIL", "closes": ["home:Shop.NAV_Planner"]}}, "roles": {}}' > $T/rjmf/after/summary.json
echo '{"journeys": {"login-Planner": {"role": "Planner", "verdict": "PASS", "closes": ["home:Shop.NAV_Planner"]}}, "roles": {}}' > $T/rjmf2/after/summary.json
ctl journeys-microflow-home-closed-fail-catch 1 'FAIL +home:Shop.NAV_Planner .*closed by login-Planner' -- python3 $B/run_journeys.py $T/gen-mfh --label after --work $T/rjmf --rejudge
ctl journeys-microflow-home-closed-pass 0 'PASS +home:Shop.NAV_Planner .*closed by login-Planner' '!INFO' -- python3 $B/run_journeys.py $T/gen-mfh --label after --work $T/rjmf2 --rejudge
# E7-12: the positive control holds when every ui-landing mutant is caught; UNPROVEN rungs are INFO, not misses
cat > $T/ctlv.py <<'PYEOF2'
import json, sys
sys.path.insert(0, sys.argv[1]); from run_journeys import control_verdict
rows = json.load(open(sys.argv[2]))["results"]
c, bad, _ = control_verdict(rows)
print("counts", " ".join(f"{k}={v}" for k, v in c.items()))
for b in bad: print("MISS", b)
sys.exit(1 if bad else 0)
PYEOF2
U='this journey declares nothing this mutant can break, this rung is UNPROVEN for j'
printf '{"results":[{"rung":"control","name":"j · ui-landing: x","verdict":"PASS","detail":"caught"},{"rung":"control","name":"j · trace-order: y","verdict":"INVALID","detail":"%s"}]}' "$U" > $T/ctl-ok.json
printf '{"results":[{"rung":"control","name":"j · ui-landing: x","verdict":"INVALID","detail":"not caught"},{"rung":"control","name":"j · trace-order: y","verdict":"INVALID","detail":"%s"}]}' "$U" > $T/ctl-miss.json
printf '{"results":[{"rung":"control","name":"j · trace-order: y","verdict":"INVALID","detail":"%s"}]}' "$U" > $T/ctl-none.json
ctl control-unproven-info-pass 0 'counts PASS=1 FAIL=0 INVALID=0 INFO=1' '!MISS' -- python3 $T/ctlv.py $B $T/ctl-ok.json
ctl control-landing-miss-catch 1 'MISS INVALID j · ui-landing: x' -- python3 $T/ctlv.py $B $T/ctl-miss.json
ctl control-no-landing-catch 1 'MISS no ui-landing control row' -- python3 $T/ctlv.py $B $T/ctl-none.json
E7CTL=$LAB/e5/run3/work/e2e-control/before/Administrator-journey-findings-control.json
if [ -f $E7CTL ]; then
  ctl field-e7-control-unproven-pass 0 'counts PASS=5 FAIL=0 INVALID=0 INFO=16' '!MISS' -- python3 $T/ctlv.py $B $E7CTL
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); r=[x for x in d['results'] if x['rung']=='control' and 'ui-landing' in x['name']][0]; r['verdict']='INVALID'; r['detail']='not caught'; json.dump(d, open(sys.argv[2],'w'))" $E7CTL $T/e7ctl-miss.json
  ctl field-e7-control-landing-miss-catch 1 'MISS INVALID create-save · ui-landing' -- python3 $T/ctlv.py $B $T/e7ctl-miss.json
else
  skip field-e7-control-unproven-pass "no E7 control findings"; skip field-e7-control-landing-miss-catch "no E7 control findings"
fi
mkdir -p $T/gen-info && python3 -c "import json; json.dump({'journeys': [], 'skipped': [], 'todo': [], 'covered': [{'id': 'home:X', 'why': 'walked by login-A'}], 'unreachable': [{'id': 'page:Y', 'why': 'dead'}]}, open('$T/gen-info/plan.json', 'w'))"
ctl journeys-info-not-invalid-pass 0 'INFO +home:X' '0 INVALID, 2 INFO' -- python3 $B/run_journeys.py $T/gen-info --label info --port 1 --admin-port 2 --admin-pass x --users $FX/journeys/no-users.json --work $T/e2e-info
python3 -c "import json; json.dump({'journeys': [], 'skipped': [{'id': 'anonymous-Guest', 'why': 'anonymous role'}], 'todo': [], 'covered': [], 'unreachable': []}, open('$T/gen-info/plan.json', 'w'))"
ctl journeys-anonymous-invalid-catch 3 'INVALID +anonymous-Guest' -- python3 $B/run_journeys.py $T/gen-info --label info2 --port 1 --admin-port 2 --admin-pass x --users $FX/journeys/no-users.json --work $T/e2e-info2
# E5b-8: a relative --work and journeys dir resolve to absolute paths (the runner was looked up under engine/<work>/...)
ctl journeys-relative-work-pass 3 'INVALID +anonymous-Guest' '^summary in .*/e2e-rel' -- sh -c "cd $T && python3 $B/run_journeys.py gen-info --label rel --port 1 --admin-port 2 --admin-pass x --users $FX/journeys/no-users.json --work e2e-rel; rc=\$?; ls -d $T/e2e-rel/* | sed 's/^/summary in /'; exit \$rc"

# --- baseline: a fresh database copy per snapshot (E4-21: a probe wrote to the DB, the second snapshot was polluted) ---------
L=$T/ledger.txt
ctl snapshot-ledger-fresh-pass 0 'snap-a: entities' '!REFUSED' -- python3 $B/snapshot.py --label snap-a --out $T/snap-a.json --psql "false -d fx_a" --ledger $L
ctl snapshot-ledger-reuse-catch 2 'REFUSED, fx_a was already used \(snapshot snap-a' -- python3 $B/snapshot.py --label snap-b --out $T/snap-b.json --psql "false -d fx_a" --ledger $L
ctl snapshot-frozen-catch 2 'REFUSED, app_frozen is a frozen database' -- python3 $B/snapshot.py --label snap-f --out $T/snap-f.json --psql "false -d app_frozen"
# NR2-9: --admin-url without --admin-pass uses runapp's fixed password (it was a fault, 'NoneType ... encode', and a lost before)
ctl snapshot-admin-default-pass 0 'snap-adm: entities 0, .*faults \[\]' '!NoneType' -- python3 $B/snapshot.py --label snap-adm --out $T/snap-adm.json --admin-url http://127.0.0.1:1/
ctl snapshot-mark-used 0 'ledger: fx_c probe' -- python3 $B/snapshot.py --ledger $L --mark-used fx_c --use probe
ctl snapshot-mark-used-catch 2 'REFUSED, fx_c was already used \(probe' -- python3 $B/snapshot.py --label snap-c --out $T/snap-c.json --psql "false -d fx_c" --ledger $L
# v3.1 E6-16, E7-8: the refusal names the ledger line; a hand-written note is called out as such
echo "fx_h copy of frozen" >> $L
ctl snapshot-ledger-hand-line-catch 2 'ledger line [0-9]+ of .*: fx_h copy of frozen' 'not in the form snapshot.py writes' 'Never write ledger lines by hand' -- python3 $B/snapshot.py --label snap-h --out $T/snap-h.json --psql "false -d fx_h" --ledger $L
ctl snapshot-ledger-own-line-pass 2 'ledger line 1 of .*: fx_a snapshot snap-a' '!not in the form' -- python3 $B/snapshot.py --label snap-b --out $T/snap-b.json --psql "false -d fx_a" --ledger $L
ctl snapshot-no-ledger-warns 0 'WARNING, no --ledger' -- python3 $B/snapshot.py --label snap-d --out $T/snap-d.json --psql "false -d fx_d"

# --- release_impact.py (V31-RI): the release-note rows of a jump, from the brain's version tables -------------------------
RB=$FX/brain; RI=$T/ri; mkdir -p $RI
ctl release-impact-java21-catch 0 'Studio Pro 2 rows' '^\| 1 \| 10\.21\.0 \| removal \| runtime \| Removed support for Java 11 and Java 17' '!Fixture removal at the from version' '!above the to version' '!Fixture fix row' -- sh -c "python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --out $RI/a.md && cat $RI/a.md"
ctl release-impact-across-majors-pass 0 'Studio Pro 2 rows \(breaking 2\)' '\| 10\.24\.17 \| breaking' '\| 11\.0\.0 \| breaking' '!11\.12\.3' -- sh -c "python3 $B/release_impact.py --brain $RB --from 10.24.16.96987 --to 11.12.2 --out $RI/x.md && cat $RI/x.md"
ctl release-impact-module-catch 0 'Module TaskQueueHelpers \(2\.0\.2 to 3\.1\.0, 2 rows' '\| 3\.1\.0 \| requirement \| Module upgraded to require Mendix 10\.24\.0 minimum' 'modules/oqlmodule\.md by content id 66876' '!Fixture row at the old version' '!Upgraded widgets' -- sh -c "python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --plan $FX/release-impact/plan.txt --out $RI/m.md && cat $RI/m.md"
ctl release-impact-types-pass 0 '\| 3\.1\.0 \| improvement \| Upgraded widgets' 'Fixture fix row' -- sh -c "python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --plan $FX/release-impact/plan.txt --types requirement,improvement,fix,removal --out $RI/t.md && cat $RI/t.md"
# QW-1: migration-step is a module row type shipped by publishers ("Replace snippet X with Y"); the default dropped it (WorkflowCommons 4.0.0, 24 rows unflagged)
cp -R $RB $RI/brain-mig; echo '| 3.1.0 | migration-step | Replace snippet Snip_Old with Snip_New. | Snip_Old | Snip_New |' >> $RI/brain-mig/baseline/versions/modules/task-queue-helpers.md
ctl release-impact-migration-step-catch 0 'Module TaskQueueHelpers \(2\.0\.2 to 3\.1\.0, 3 rows' '\| 3\.1\.0 \| migration-step \| Replace snippet Snip_Old with Snip_New' 'module rows also: migration-step' -- sh -c "python3 $B/release_impact.py --brain $RI/brain-mig --from 10.12.9 --to 10.24.16 --plan $FX/release-impact/plan.txt --out $RI/mig.md && cat $RI/mig.md"
ctl release-impact-migration-step-narrowed-pass 0 'Module TaskQueueHelpers \(2\.0\.2 to 3\.1\.0, 2 rows' '!migration-step' -- sh -c "python3 $B/release_impact.py --brain $RI/brain-mig --from 10.12.9 --to 10.24.16 --plan $FX/release-impact/plan.txt --types requirement,removal --out $RI/mig2.md && cat $RI/mig2.md"
ctl release-impact-empty-pass 0 'Studio Pro 0 rows \(none\), modules 0 rows, not covered 0' -- python3 $B/release_impact.py --brain $RB --from 10.24.16 --to 10.24.16 --out $RI/e.md
ctl release-impact-empty-check-pass 0 '0 of 0 rows handled' -- python3 $B/release_impact.py --check $RI/e.md
ctl release-impact-unknown-catch 2 'UNKNOWN FakeModuleXyz: no brain file' 'not covered 1' -- python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --plan $FX/release-impact/plan-unknown.txt --out $RI/u.md
ctl release-impact-unknown-listed 0 '^## Not covered \(1\)' '\| FakeModuleXyz \| UNKNOWN \|' -- cat $RI/u.md
ctl release-impact-no-old-catch 2 'UNKNOWN OQL: plan line 1 has no old version' -- sh -c "echo '66876 4.2.0 OQL' > $RI/p1.txt; python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --plan $RI/p1.txt --out $RI/p1.md"
ctl release-impact-check-catch 1 '^OPEN Studio Pro row 1: 10\.21\.0 removal' '0 of 2 rows handled' -- python3 $B/release_impact.py --check $RI/a.md
[ -f $RI/a.md ] && sed -E 's/^(\| 1 \|.*\|) +\|$/\1 handled: commit abc1234 (Java 21 toolset) |/; s/^(\| 2 \|.*\|) +\|$/\1 not relevant: no such feature in the app |/' $RI/a.md > $RI/a-done.md
ctl release-impact-check-pass 0 '2 of 2 rows handled or not relevant, 0 open' -- python3 $B/release_impact.py --check $RI/a-done.md
# FM-7: "not relevant: (deployed app) ..." and "not relevant for the deployed app: ..." are entries; a rejected text names the expected form
[ -f $RI/a-done.md ] && sed -E 's/not relevant: no such feature in the app/not relevant: (deployed app) the feature is not used there/' $RI/a-done.md > $RI/a-paren.md
ctl release-impact-check-paren-after-colon-pass 0 '2 of 2 rows handled or not relevant, 0 open' -- python3 $B/release_impact.py --check $RI/a-paren.md
[ -f $RI/a-done.md ] && sed -E 's/not relevant: no such feature in the app/not relevant for the deployed app: the feature is not used there/' $RI/a-done.md > $RI/a-for.md
ctl release-impact-check-not-relevant-for-pass 0 '2 of 2 rows handled or not relevant, 0 open' -- python3 $B/release_impact.py --check $RI/a-for.md
[ -f $RI/a-done.md ] && sed -E 's/not relevant: no such feature in the app/probably fine/' $RI/a-done.md > $RI/a-bad.md
ctl release-impact-check-rejected-names-form-catch 1 '^OPEN Studio Pro row 2' 'not an entry .*Expected: `handled: <evidence path or commit>` or `not relevant: <reason>`' -- python3 $B/release_impact.py --check $RI/a-bad.md
# MC-15: a handled row that says REVIEW is counted, named, and does not fail the check
[ -f $RI/a-done.md ] && sed 's/handled: commit abc1234 (Java 21 toolset)/handled: REVIEW the pager after the grid update/' $RI/a-done.md > $RI/a-rev.md
ctl release-impact-check-review-marked-pass 0 '2 of 2 rows handled or not relevant, 0 open \(1 handled row\(s\) marked REVIEW\)' '^REVIEW-MARKED .*Studio Pro row 1' -- python3 $B/release_impact.py --check $RI/a-rev.md
[ -f $RI/a-done.md ] && sed 's/handled: commit abc1234 (Java 21 toolset)/handled:/' $RI/a-done.md > $RI/a-blank.md
ctl release-impact-check-blank-catch 1 'OPEN Studio Pro row 1' -- python3 $B/release_impact.py --check $RI/a-blank.md
# M5: a pipe inside an entry is written \| and the reader splits only on an UNESCAPED pipe: a row whose change holds a pipe is
# neither cut in two (its handled cell stays the last cell) nor read as open when handled; an open one still reads open
{ printf '# Release impact: Mendix 10.0.0 to 10.1.0\n\n## Studio Pro (2 rows)\n\n| # | version | type | area | change | affected | source | handled |\n|---|---|---|---|---|---|---|---|\n'
  printf '| 1 | 10.1.0 | improvement | runtime | Removed the a \\| b setting | a \\| b | [n](x) | not relevant: a \\| b is not set anywhere |\n'
  printf '| 2 | 10.1.0 | improvement | runtime | Changed x \\| y handling | x \\| y | [n](x) | |\n'; } > $RI/pipe.md
ctl release-impact-check-pipe-catch 1 '^OPEN Studio Pro row 2: 10\.1\.0 improvement Changed x \| y handling' '1 of 2 rows handled or not relevant, 1 open' '!OPEN Studio Pro row 1' -- python3 $B/release_impact.py --check $RI/pipe.md
sed 's/^\(| 2 .*\)| |$/\1| handled: x \\| y is not used |/' $RI/pipe.md > $RI/pipe-done.md
ctl release-impact-check-pipe-pass 0 '2 of 2 rows handled or not relevant, 0 open' -- python3 $B/release_impact.py --check $RI/pipe-done.md
ctl release-impact-pipe-write-warns 0 "entry contains '\|'" 'a\\\|b$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.esc('a|b'))"
[ -f $RI/a-done.md ] && cp $RI/a-done.md $RI/keep.md
# NR1-21/22/23 (notification-service run): the unsound check covers every row type, "not scanned" is no evidence, and a row
# with a written finding ("open: ...") is counted apart from one nobody touched
{ printf '# Release impact: Mendix 9.24.0 to 10.24.0\n\n## Studio Pro (4 rows)\n\n| # | version | type | area | change | affected | source | handled |\n|---|---|---|---|---|---|---|---|\n'
  printf '| 1 | 10.0.0 | requirement | runtime | The setting StrictChangeBehavior is on by default | all | [n](x) | not relevant: setting is not set |\n'
  printf '| 2 | 10.0.0 | removal | runtime | Removed the setting FooBar | all | [n](x) | not relevant: FooBar is not set, not scanned |\n'
  printf '| 3 | 10.0.0 | breaking | runtime | Changed a thing | all | [n](x) | open: needs a decision from the owner |\n'
  printf '| 4 | 10.0.0 | breaking | runtime | Changed another thing | all | [n](x) | |\n'; } > $RI/nr1.md
ctl release-impact-nr1-requirement-flip-catch 1 '^UNSOUND Studio Pro row 1: 10\.0\.0 requirement' -- python3 $B/release_impact.py --check $RI/nr1.md
ctl release-impact-nr1-not-scanned-catch 1 '^UNSOUND Studio Pro row 2: 10\.0\.0 removal' '^unsound closures: 2 ' -- python3 $B/release_impact.py --check $RI/nr1.md
ctl release-impact-nr1-blocked-apart 1 '^BLOCKED Studio Pro row 3' '^OPEN Studio Pro row 4' '^blocked: 1 \(finding written\), untouched: 1, unsound: 2$' '^auto: 0, human: 0, open: 4$' -- python3 $B/release_impact.py --check $RI/nr1.md
sed -e 's/setting is not set |/setting is not set; scan of the model: 0 hits |/' -e 's/not set, not scanned/not set; grep of javasource: 0 hits/' $RI/nr1.md > $RI/nr1-sound.md
ctl release-impact-nr1-evidence-pass 1 '!UNSOUND' '^blocked: 1 \(finding written\), untouched: 1, unsound: 0$' -- python3 $B/release_impact.py --check $RI/nr1-sound.md
# NR1-2: more phrasings of "the module needs Mendix X minimum" are read as the version-only requirement they are
ctl release-impact-nr1-min-mendix-variants-catch 0 '^yes 9\.12\.0 Minimal required version of Studio Pro is v9\.12\.0$' '^yes 9\.24\.1 Minimum Mendix version set to 9\.24\.1$' '^yes 10\.24\.0 Module upgraded to require Mendix 10\.24\.0 minimum$' '^yes 10\.24\.0 Requires Mendix 10\.24\.0 or higher$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r
for t in ['Minimal required version of Studio Pro is v9.12.0','Minimum Mendix version set to 9.24.1','Module upgraded to require Mendix 10.24.0 minimum','Requires Mendix 10.24.0 or higher']:
    m = r.min_mendix_match(t); print('yes' if m else 'no', m and m.group(1), t)"
ctl release-impact-nr1-min-mendix-other-pass 0 '^no None Upgraded widgets$' '^no None Minimum Mendix version set to 9.24.1 and removed the Foo setting$' '^yes 10.24.0 Upgraded the module to Mendix 10.24.0$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r
for t in ['Upgraded widgets','Minimum Mendix version set to 9.24.1 and removed the Foo setting','Upgraded the module to Mendix 10.24.0']:
    m = r.min_mendix_match(t); print('yes' if m else 'no', m and m.group(1), t)"
# QJ-2 closure rule: "not set, so not relevant" on a removed setting / flipped default stays open (b5-forms row 230, verbatim)
RCL=$FX/release-impact/closure.md
ctl release-impact-closure-unsound-catch 1 '^UNSOUND Studio Pro row 230: 11\.0\.0 removal Removed deprecated Objects\.SetSystemAttributesOnChange' '4 of 5 rows handled or not relevant, 1 open' '^unsound closures: 1 ' '!row 45' '!row 52' '!row 231' '!row 229' -- python3 $B/release_impact.py --check $RCL
sed 's/| not relevant: setting never set (0 custom runtime settings.*|$/| not relevant: setting never set; replacement_check R30 clear (no changedDate read in logic) |/' $RCL > $RI/closure-scan.md
ctl release-impact-closure-scan-pass 0 '5 of 5 rows handled or not relevant, 0 open' '!UNSOUND' '!unsound closures' -- python3 $B/release_impact.py --check $RI/closure-scan.md
ctl release-impact-rerun-keeps-pass 0 'handled: commit abc1234' -- sh -c "python3 $B/release_impact.py --brain $RB --from 10.12.9 --to 10.24.16 --out $RI/keep.md >/dev/null && python3 $B/release_impact.py --check $RI/keep.md >/dev/null && cat $RI/keep.md"
# batch 1 (T3-4, T4-10, T5-20, T6-18, T7-23 ...): --auto --facts pre-fills rows a rule and an app fact settle; rows about
# a used or unknown feature stay open. fixtures/brain-auto: 9.24.2 -> 10.8.0, newest 10.x row 10.8.0.
RA=$FX/brain-auto; RF=$FX/release-impact
ctl release-impact-auto-db-vendor-pass 1 'MariaDB 10\.3 and MySQL 5\.7.*\| not relevant \(auto\): other-db-vendor: row is about mariadb, mysql; db_vendor=postgresql \(facts-auto\.json\) \|' 'PostgreSQL 11, no longer.*\| not relevant \(auto\): other-db-version: row is about postgresql 11; db_version=16' '^OPEN Studio Pro row 4: .*dropped support for PostgreSQL 16' '^OPEN Studio Pro row 5: .*PostgreSQL versions below 17' '^OPEN Studio Pro row 6: .*Amazon S3' -- sh -c "python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto --facts $RF/facts-auto.json --out $RI/auto.md >/dev/null; cat $RI/auto.md; python3 $B/release_impact.py --check $RI/auto.md"
ctl release-impact-auto-rules-pass 1 '\| 9\.24\.5 \| removal .*not relevant \(auto\): source-line-patch: 9\.24\.5 is a 9\.24\.x patch above the source 9\.24\.2 on a path to 10\.x' '\| studio-pro-ide \|.*not relevant \(auto\): studio-pro-ide' '\| Published OData services .*feature-absent: row is about published OData; odata_published=0' 'WorkflowUserTask_Assignee .*feature-absent: row is about workflows; workflows=0' '\| CodePush .*feature-absent: row is about native; native_profile=false' '\| Duplicate column names in OQL .*feature-absent: row is about OQL; oql=0' '\| Deprecated Core\.executeVoid .*java-deprecation: no own Java action; own_java=0' 'document template widget .*feature-absent: row is about document templates' '\| 2\.31\.0 \| requirement .*min-mendix-met: the module needs Mendix 10\.4\.0, the target is 10\.8\.0' 'kept-module: FixtureKept is kept' '^OPEN Studio Pro row 13: 10\.6\.0 breaking Fixture runtime breaking change without a feature token' '^OPEN Studio Pro row 15: 10\.6\.0 removal Removed Core\.retrieveXPathQuery' '^OPEN Studio Pro row 16: 10\.7\.0 breaking Fixed XML parser in web service' '^OPEN Studio Pro row 9: 10\.2\.0 removal' '^OPEN Module DataGrid row 23: 3\.0\.0 requirement' '^OPEN Studio Pro row 18: 10\.8\.0 breaking Curly braces in placeholder' '^OPEN Studio Pro row 19: 10\.8\.0 requirement New projects will now use Java 21' '^OPEN Studio Pro row 20: 10\.8\.0 requirement External Database Connector' '^auto: 12, human: 0, open: 13$' -- sh -c "cat $RI/auto.md; python3 $B/release_impact.py --check $RI/auto.md"
# the catch: the app PUBLISHES OData, so the breaking OData row stays open for a scan or journey
ctl release-impact-auto-keeps-breaking-open-catch 1 '^OPEN Studio Pro row 8: 10\.2\.0 breaking Published OData services' '!\| Published OData services .*not relevant \(auto\)' -- sh -c "python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto --facts $RF/facts-odata-used.json --out $RI/auto-od.md >/dev/null; cat $RI/auto-od.md; python3 $B/release_impact.py --check $RI/auto-od.md"
# a test_inventory.py --json is read for what it knows (published OData 1, own Java 3); what it does not know stays unknown
ctl release-impact-auto-inventory-pass 0 'auto: 4 of 25 rows' 'feature-absent: row is about workflows; workflows=0 \(inventory\.json\)' '!feature-absent: row is about published OData: row is about published OData' '!java-deprecation' -- sh -c "python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto --facts $RF/inventory.json --out $RI/auto-inv.md; cat $RI/auto-inv.md"
# review of PR 10: a db vendor no rule can name fires no db rule (it may be one the row names)
sed 's/"postgresql"/"yugabyte"/' $RF/facts-auto.json > $RI/facts-yb.json
ctl release-impact-auto-unknown-vendor-catch 1 '^OPEN Studio Pro row 2: 10\.0\.0 removal Dropped support for MariaDB' '^OPEN Studio Pro row 3: 10\.0\.0 removal Dropped support for PostgreSQL 11' -- sh -c "python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --auto --facts $RI/facts-yb.json --out $RI/auto-yb.md >/dev/null; python3 $B/release_impact.py --check $RI/auto-yb.md"
ctl release-impact-auto-needs-facts-catch 1 'auto needs facts' '--facts-from-mpr app/<App>\.mpr --db-vendor postgresql --db-version 16 --runtime-os linux --facts-out facts\.json' --  python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --auto --out $RI/auto-nf.md
# a human line always wins over an auto line on rerun; an auto line is recomputed (here: the facts now say OData is used)
[ -f $RI/auto.md ] && sed -E 's/^(\| 2 \|.*\|) not relevant \(auto\)[^|]*\|$/\1 handled: evidence\/diff.md row 12 (MariaDB checked by hand) |/' $RI/auto.md > $RI/auto-human.md
ctl release-impact-auto-human-wins-pass 1 '\| 2 \|.*\| handled: evidence/diff\.md row 12 \(MariaDB checked by hand\) \|' '^OPEN Studio Pro row 8: 10\.2\.0 breaking Published OData' '^auto: 10, human: 1, open: 14$' -- sh -c "python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto --facts $RF/facts-odata-used.json --out $RI/auto-human.md >/dev/null; cat $RI/auto-human.md; python3 $B/release_impact.py --check $RI/auto-human.md"
# T3F-11: OData consumed through a Marketplace connector (SAPODataConnector) is no consumed-OData document: the built-in
# count says 0. A connector reference count > 0 keeps the consumed-OData row open; both 0 closes it; the key missing is unknown
cp -R $RA $RI/brain-odc; echo '| 10.5.0 | Mar 5 | deprecation | odata-rest | Fixture consumed OData now sends a changed Accept header. | consumed OData | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.5/) |' >> $RI/brain-odc/baseline/versions/studio-pro-upgrade-10.md
RIO="python3 $B/release_impact.py --brain $RI/brain-odc --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto"
python3 -c "import json; d=json.load(open('$RF/facts-auto.json')); d.pop('odata_consumed_connector'); json.dump(d, open('$RI/facts-noconn.json','w'))"
ctl release-impact-odata-connector-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.5\.0 deprecation Fixture consumed OData' '!Fixture consumed OData.*not relevant \(auto\)' -- sh -c "$RIO --facts $RF/facts-odata-connector.json --out $RI/odc.md >/dev/null; python3 $B/release_impact.py --check $RI/odc.md"
ctl release-impact-odata-connector-unknown-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.5\.0 deprecation Fixture consumed OData' '!Fixture consumed OData.*not relevant \(auto\)' -- sh -c "$RIO --facts $RI/facts-noconn.json --out $RI/odn.md >/dev/null; python3 $B/release_impact.py --check $RI/odn.md"
ctl release-impact-odata-connector-absent-pass 1 'Fixture consumed OData.*not relevant \(auto\): feature-absent: row is about consumed OData; odata_consumed=0 \(facts-auto\.json\), odata_consumed_connector=0' -- sh -c "$RIO --facts $RF/facts-auto.json --out $RI/oda.md >/dev/null; cat $RI/oda.md; python3 $B/release_impact.py --check $RI/oda.md"
# the producers: the model (facts-from-mpr) and the catalog (test_inventory)
model odata-conn > /dev/null; model odata-conn-unused > /dev/null; model facts-clean > /dev/null
ctl release-impact-facts-from-mpr-odata-connector-catch 0 'odata_consumed = 0' 'odata_consumed_connector = 1' -- python3 $B/release_impact.py --facts-from-mpr $M/odata-conn/App.mpr --facts-out $RI/foc.json
ctl release-impact-facts-from-mpr-odata-connector-unused-pass 0 'odata_consumed_connector = 0' -- python3 $B/release_impact.py --facts-from-mpr $M/odata-conn-unused/App.mpr --facts-out $RI/fou.json
ctl release-impact-facts-from-mpr-odata-connector-clean-pass 0 'odata_consumed_connector = 0' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-clean/App.mpr --facts-out $RI/fcl.json
ctl release-impact-odata-connector-end-to-end-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.5\.0 deprecation Fixture consumed OData' '!Fixture consumed OData.*not relevant \(auto\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/odata-conn/App.mpr --db-vendor postgresql --db-version 16 --runtime-os linux --facts-out $RI/foc2.json >/dev/null; $RIO --facts $RI/foc2.json --out $RI/ode.md >/dev/null; python3 $B/release_impact.py --check $RI/ode.md"
if python3 -c "import sqlite3" 2>/dev/null; then
  OC=$T/ti-odc; mkdir -p $OC/.mxcli
  python3 - $OC/.mxcli/catalog.db <<'PYEOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for t, cols in {"modules_data": "Name, Source, AppStoreVersion", "entities_data": "QualifiedName, ModuleName, EntityType, Generalization, AttributeCount, AssociationCount, HasEventHandlers",
                "published_rest_operations_data": "ServiceQualifiedName, HttpMethod, Path, Microflow", "rest_clients_data": "QualifiedName, BaseUrl, OperationCount",
                "activities_data": "ActionType", "odata_services_data": "QualifiedName, Path, EntitySetCount", "odata_clients_data": "QualifiedName, MetadataUrl",
                "scheduled_events_data": "QualifiedName, Microflow, Enabled, RepeatDescription", "java_actions_data": "ModuleName",
                "navigation_role_homes": "ProfileName, UserRole, Page, Microflow", "navigation_menu_items": "TargetPage", "widgets_data": "WidgetType",
                "jar_dependencies_data": "ModuleName, Coordinate, Version", "workflows_data": "QualifiedName", "business_event_services_data": "QualifiedName",
                "refs": "SourceName, RefKind, TargetName"}.items():
    c.execute(f"create table {t} ({cols})")
c.execute("insert into modules_data values ('SAPODataConnector', 'Marketplace', '7.1.6'), ('SAP', NULL, NULL)")
c.execute("insert into entities_data values ('SAP.Product', 'SAP', 'PERSISTENT', 'SAPODataConnector.OdataObject', 3, 0, 0)")
c.execute("insert into refs values ('SAP.DS_GetProducts', 'call', 'SAPODataConnector.GetList'), ('SAP.Product', 'generalize', 'SAPODataConnector.OdataObject'), ('SAP.A', 'call', 'Other.X')")
c.commit()
PYEOF
  ctl test-inventory-odata-connector-catch 0 '"odata_consumed_connector": \[' '"source": "SAP.DS_GetProducts"' '"source": "SAP.Product"' '!Other\.X' '^\| OData published / consumed \| 0 / 0 \(built-in client\); 2 references into OData connector modules \(SAPODataConnector\)' -- sh -c "python3 $B/test_inventory.py $OC --json $OC/inv.json; cat $OC/inv.json"
  ctl test-inventory-odata-connector-facts-catch 0 '^\(2, ' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.load_facts(['$OC/inv.json'])['odata_consumed_connector'])"
  # an empty refs table in a catalog with no generalization: unknown, never a clean 0 (a fast-mode catalog leaves tables empty)
  python3 -c "
import sqlite3; c=sqlite3.connect('$OC/.mxcli/catalog.db'); c.execute('delete from refs'); c.execute('delete from entities_data'); c.commit()"
  ctl test-inventory-odata-connector-unknown-catch 0 'connector modules: UNKNOWN \(connector references unknown: refs is empty' -- python3 $B/test_inventory.py $OC
  ctl test-inventory-odata-connector-unknown-facts-catch 0 '^None$' -- sh -c "python3 $B/test_inventory.py $OC --json $OC/inv0.json >/dev/null; python3 -c \"import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.load_facts(['$OC/inv0.json']).get('odata_consumed_connector'))\""
fi
# T5-20: "handled (...)" and "handled - ..." are entries; a bare "handled" is not
[ -f $RI/a.md ] && sed -E 's/^(\| 1 \|.*\|) +\|$/\1 handled (RISK accepted, evidence\/build.log) |/; s/^(\| 2 \|.*\|) +\|$/\1 handled - commit abc1234 |/' $RI/a.md > $RI/a-variants.md
ctl release-impact-check-variants-pass 0 '2 of 2 rows handled or not relevant, 0 open' '^auto: 0, human: 2, open: 0$' -- python3 $B/release_impact.py --check $RI/a-variants.md
# review of PR 10: an empty "handled ()" or "handled - -" is no entry
[ -f $RI/a.md ] && sed -E 's/^(\| 1 \|.*\|) +\|$/\1 handled () |/; s/^(\| 2 \|.*\|) +\|$/\1 handled - - |/' $RI/a.md > $RI/a-empty.md
ctl release-impact-check-empty-variant-catch 1 '0 of 2 rows handled or not relevant, 2 open' -- python3 $B/release_impact.py --check $RI/a-empty.md
# T1-8, T2-19, T7-6: --to above the newest row of its major's table is not covered, never silently empty
ctl release-impact-to-above-table-catch 2 'UNKNOWN rows for 10\.9\.0 not in brain \(newest 10\.8\.0\): read the release notes of 10\.9\.x versions above 10\.8\.0 on docs\.mendix\.com/releasenotes/studio-pro/' 'the brain.s version table needs a data refresh by whoever owns the brain, this tool never writes it \(T2F-1\)' -- python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.9.0 --out $RI/above.md
ctl release-impact-to-in-table-pass 0 '!not in brain' -- python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0.12345 --out $RI/in.md
# T1-9, T8-6: a renamed module is found by its content id; by name alone it is UNKNOWN
ctl release-impact-plan-by-cid-pass 0 '## Module DataGrid \(1\.0\.0 to 3\.0\.0, 4 rows, brain file modules/data-widgets\.md by content id 116540\)' -- sh -c "python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --plan $RF/plan-auto.txt --out $RI/cid.md; cat $RI/cid.md"
ctl release-impact-plan-by-name-catch 2 'UNKNOWN DataGrid: no brain file for DataGrid' -- python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --plan $RF/plan-by-name.txt --out $RI/name.md
# T1-31: the plan from the two projects: paired by content id (DataGrid -> DataWidgets), kept / new / removed listed
model ri-old > /dev/null; model ri-new > /dev/null
ctl release-impact-from-mpr-pass 0 '## Module DataWidgets \(1\.0\.0 to 3\.0\.0, 4 rows, brain file modules/data-widgets\.md by content id 116540\)' '\| DataWidgets \(was DataGrid\) \| 116540 \| 1\.0\.0 \| 3\.0\.0 \| updated' '\| FixtureKept \| 900001 \| 1\.0\.0 \| 1\.0\.0 \| kept' '\| NanoNew \| 900003 \|  \| 2\.0\.0 \| new' '\| GoneModule \| 900002 \| 1\.0\.0 \|  \| removed' '!Module FixtureKept' '!MyOwn' -- sh -c "python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --from-mpr $M/ri-old/App.mpr --to-mpr $M/ri-new/App.mpr --out $RI/mpr.md; cat $RI/mpr.md"
# T6R-4: a module updated by mxcli/stepupdate has no content id in the new project: the old project's id finds the brain
# file (AnyChart_BuildingBlocks is anychart.md); --slug Module=slug for what neither finds; --from-mpr still needs --from/--to
model ri-cidlost-old > /dev/null; model ri-cidlost-new > /dev/null
ctl release-impact-from-mpr-cid-lost-pass 0 '## Module DataGrid \(1\.0\.0 to 3\.0\.0, 4 rows, brain file modules/data-widgets\.md by content id 116540\)' '\| DataGrid \| 116540 \| 1\.0\.0 \| 3\.0\.0 \| updated' '!UNKNOWN DataGrid' -- sh -c "python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --from-mpr $M/ri-cidlost-old/App.mpr --to-mpr $M/ri-cidlost-new/App.mpr --out $RI/cidlost.md; cat $RI/cidlost.md"
ctl release-impact-slug-given-pass 0 'brain file modules/data-widgets\.md by given' '!UNKNOWN DataGrid' -- sh -c "python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --plan $RF/plan-by-name.txt --slug DataGrid=data-widgets --out $RI/slug.md; cat $RI/slug.md"
ctl release-impact-slug-wrong-catch 2 'UNKNOWN DataGrid: no brain file modules/nope\.md' -- python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --plan $RF/plan-by-name.txt --slug DataGrid=nope --out $RI/slug2.md
ctl release-impact-slug-malformed-catch 1 "--slug 'DataGrid': write Module=brain-slug" -- python3 $B/release_impact.py --brain $RA --from 10.8.0 --to 10.8.0 --plan $RF/plan-by-name.txt --slug DataGrid --out $RI/slug3.md
ctl release-impact-from-mpr-needs-versions-catch 2 '--from and --to are required.*--from-mpr/--to-mpr give the module plan only.*ri-cidlost-old/App\.mpr is 10\.24\.16\.96987' -- python3 $B/release_impact.py --brain $RA --from-mpr $M/ri-cidlost-old/App.mpr --to-mpr $M/ri-cidlost-new/App.mpr
# T6R-5: the tool areas (git-teamserver, mxbuild-cli), java-actions removals by grep, module library bumps by grep.
# fixtures/brain-tools holds the real T6R row texts; lib/mkjavaproj.py the project folder the greps read.
RT="python3 $B/release_impact.py --brain $FX/brain-tools --from 9.24.2 --to 10.22.0 --plan $FX/release-impact/plan-tools.txt --auto"
for v in plain:  own:--own-uses jar:--jar-hit git:--git; do
  python3 $here/lib/mkjavaproj.py $RI/jp-${v%%:*} ${v#*:}
  printf '{"project_dir": "%s"}\n' $RI/jp-${v%%:*} > $RI/tools-${v%%:*}.json
done
printf '{"project_dir": "%s", "vcs": "git"}\n' $RI/jp-git > $RI/tools-git.json
echo '{"own_java": 1}' > $RI/tools-none.json
ctl release-impact-tools-rules-pass 1 '\| 1 \| 10\.0\.0 \| removal .*java-symbol-absent: AdminException, IMxRuntime: 0 hits in .*jp-plain/javasource \(3 \.java, proxies excluded\), .*jp-plain/userlib \(1 jars\)' '\| 4 \| .*java-symbol-absent: bundleComponentLoaded: 0 hits' '\| 8 \| 10\.7\.0 .*not relevant \(auto\): git-teamserver: area git-teamserver is version control' '\| 9 \| 10\.18\.0 .*not relevant \(auto\): mxbuild-cli: area mxbuild-cli is the build host' '\| 12 \| 4\.1\.0 .*module-library-bump: com\.nimbusds, net\.minidev is used only by javasource/mendixsso/ \(0 imports in the other 2 \.java' '\| 15 \| 9\.4\.2 .*module-library-bump: io\.netty, org\.apache\.hc' '^OPEN Studio Pro row 2: .*rollbackTransAction' '^OPEN Studio Pro row 3: .*Mendix Runtime API' '^OPEN Studio Pro row 5: 10\.0\.0 breaking IDataTable' '^OPEN Studio Pro row 6: .*SVN' '^OPEN Studio Pro row 7: 10\.3\.0 breaking' '^OPEN Studio Pro row 10: .*dotnet runtime' '^OPEN Studio Pro row 11: 10\.22\.0 removal Retracted' '^OPEN Module MendixSSO row 14: .*commons-lang3' '^OPEN Module MendixSSO row 16: .*fixture-unmapped-lib' '^OPEN Module MendixSSO row 17: 9\.5\.0 breaking' '^auto: 7, human: 0, open: 10$' -- sh -c "$RT --facts $RI/tools-plain.json --out $RI/tools.md >/dev/null; cat $RI/tools.md; python3 $B/release_impact.py --check $RI/tools.md"
ctl release-impact-tools-own-uses-catch 1 '^OPEN Studio Pro row 1: .*AdminException' '^OPEN Module MendixSSO row 12: ' '^OPEN Module MendixSSO row 13: ' '\| 15 \| 9\.4\.2 .*module-library-bump' '!java-symbol-absent: AdminException' -- sh -c "$RT --facts $RI/tools-own.json --out $RI/tools-own.md >/dev/null; cat $RI/tools-own.md; python3 $B/release_impact.py --check $RI/tools-own.md"
ctl release-impact-tools-jar-hit-catch 1 '^OPEN Studio Pro row 1: ' '^OPEN Studio Pro row 4: .*bundleComponentLoaded' '!java-symbol-absent' -- sh -c "$RT --facts $RI/tools-jar.json --out $RI/tools-jar.md >/dev/null; python3 $B/release_impact.py --check $RI/tools-jar.md"
ctl release-impact-tools-svn-git-pass 1 '\| 6 \| 10\.0\.0 \| removal .*git-teamserver: the row is about SVN; the project is under Git, vcs=git \(tools-git\.json\)' '^auto: 8, human: 0, open: 9$' -- sh -c "$RT --facts $RI/tools-git.json --out $RI/tools-git.md >/dev/null; cat $RI/tools-git.md; python3 $B/release_impact.py --check $RI/tools-git.md"
# PV-4: the Java is read as it was at the run start (the "original:" commit), not after the port. A symbol that was there and
# is gone now is "handled (auto): java-symbol-ported" with the commit; one still there stays open; no git, the tree as it is.
for v in ported unported; do
  python3 $here/lib/mkjavaproj.py $RI/jp-$v --own-uses
  (cd $RI/jp-$v && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm "original: run start")
  printf '{"project_dir": "%s"}\n' $RI/jp-$v > $RI/tools-$v.json
done
(cd $RI/jp-ported && printf 'package myfirstmodule.actions;\nclass Keep {}\n' > javasource/myfirstmodule/actions/Keep.java \
  && git -c user.email=c@c -c user.name=ctl commit -qam "java: port Keep off AdminException")
ctl release-impact-java-ported-catch 0 '\| 1 \| 10\.0\.0 \| removal .*handled \(auto\): java-symbol-ported: AdminException occurred in the kept Java at [0-9a-f]{9} \(the run start\) and is gone now \(AdminException: [0-9a-f]+ java: port Keep off AdminException\)' '!\| 1 \| 10\.0\.0 \| removal .*not relevant \(auto\): java-symbol-absent' -- sh -c "$RT --facts $RI/tools-ported.json --out $RI/tools-ported.md >/dev/null; cat $RI/tools-ported.md"
ctl release-impact-java-ported-check-pass 1 '!OPEN Studio Pro row 1: ' -- sh -c "$RT --facts $RI/tools-ported.json --out $RI/tools-ported.md >/dev/null; python3 $B/release_impact.py --check $RI/tools-ported.md"
ctl release-impact-java-unported-catch 1 '^OPEN Studio Pro row 1: .*AdminException' '!java-symbol-ported' -- sh -c "$RT --facts $RI/tools-unported.json --out $RI/tools-unported.md >/dev/null; cat $RI/tools-unported.md; python3 $B/release_impact.py --check $RI/tools-unported.md"
ctl release-impact-java-rev-explicit-catch 0 'handled \(auto\): java-symbol-ported: AdminException' -- sh -c "$RT --java-rev HEAD~1 --facts $RI/tools-ported.json --out $RI/tools-ported2.md >/dev/null; cat $RI/tools-ported2.md"
ctl release-impact-tools-no-project-catch 1 '^OPEN Studio Pro row 1: ' '^OPEN Module MendixSSO row 13: ' '\| 8 \| 10\.7\.0 .*git-teamserver: area' '!java-symbol-absent' '!module-library-bump' '^auto: 2, human: 0, open: 15$' -- sh -c "$RT --facts $RI/tools-none.json --out $RI/tools-none.md >/dev/null; cat $RI/tools-none.md; python3 $B/release_impact.py --check $RI/tools-none.md"
mkdir -p $RI/fp; cp $M/facts-clean/App.mpr $RI/fp/; python3 $here/lib/mkjavaproj.py $RI/fp --git
ctl release-impact-tools-facts-pass 0 '"project_dir": ".*/fp"' '"vcs": "git"' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $RI/fp/App.mpr --facts-out $RI/fp-facts.json >/dev/null; cat $RI/fp-facts.json"
mkdir -p $RI/fnj; cp $M/facts-clean/App.mpr $RI/fnj/
ctl release-impact-tools-facts-no-javasource-catch 0 'own_java, own_jdbc, dev_servlet: no javasource folder' '!project_dir' '!"vcs"' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $RI/fnj/App.mpr --facts-out $RI/fnj-facts.json; cat $RI/fnj-facts.json"
# N1-9, T2F-2..5: rows one fact decides (.NET host, language codes, dev servlet, JDBC, db date phrase), facts from the project,
# --auto without the mpr pair, orphan entries, would-auto report. fixtures/brain-n19: 12 rows of the real 11.x wording.
RN=$FX/brain-n19; RIN="python3 $B/release_impact.py --brain $RN --from 11.6.3 --to 11.12.3"
model facts-clean > /dev/null; model facts-used > /dev/null
echo '{"db_vendor": "postgresql", "db_version": "16"}' > $RI/facts-n19-min.json
ctl release-impact-n19-pass 1 '\| 11\.6\.5 \|.*dotnet-ide-host: row is about the \.NET of the Studio Pro host.*runtime_os=linux \(facts-n19\.json\)' '\| 11\.6\.7 \|.*dotnet-ide-host' 'Hebrew language code changed.*language-code: row is about he_IL, iw_IL; the app.s languages do not include them \(languages=\["en_US"\]' 'in_ID.*language-code: row is about id_ID, in_ID' 'sr_CS.*language-code: row is about sr_CS, sr_ME, sr_RS' 'Core\.addDevelopmentServlet .*dev-servlet-unused: .*dev_servlet=0 \(facts-n19\.json\)' 'upgraded PostgreSQL JDBC driver.*jdbc-unused: .*own_jdbc=0' 'Database Connector module may need.*jdbc-unused: .*own_jdbc=0 \(facts-n19\.json\), database_connector=0' 'PostgreSQL 13 and MariaDB 10\.6 will be dropped.*other-db-version: row is about postgresql 13; db_version=16' 'This run: 10 auto, 0 kept from a person, 2 open\.' '^OPEN Studio Pro row 4: 11\.6\.8 breaking Studio Pro on macOS' '^OPEN Studio Pro row 5: 11\.7\.0 deprecation From July 6, 2026, support for PostgreSQL 16' '^auto: 10, human: 0, open: 2$' -- sh -c "$RIN --auto --facts $RF/facts-n19.json --out $RI/n19.md >/dev/null; cat $RI/n19.md; python3 $B/release_impact.py --check $RI/n19.md"
# the catch: the facts say the feature IS used (Windows hosts, Hebrew kept, own JDBC, the Database Connector, the dev servlet)
ctl release-impact-n19-used-catch 1 '^OPEN Studio Pro row 1: 11\.6\.5' '^OPEN Studio Pro row 3: 11\.6\.7' '^OPEN Studio Pro row 6: 11\.8\.0 deprecation Hebrew' '^OPEN Studio Pro row 10: 11\.9\.1' '^OPEN Studio Pro row 11: 11\.9\.2' '^OPEN Studio Pro row 12: 11\.12\.3 breaking Requests to servlets' '!^OPEN Studio Pro row 7:' '^auto: 4, human: 0, open: 8$' -- sh -c "$RIN --auto --facts $RF/facts-n19-used.json --out $RI/n19u.md >/dev/null; python3 $B/release_impact.py --check $RI/n19u.md"
# a fact not given leaves its rows open, and a language row of the IDE area is no longer closed by the IDE rule
ctl release-impact-n19-unknown-facts-catch 1 '^OPEN Studio Pro row 1: 11\.6\.5' '^OPEN Studio Pro row 6: 11\.8\.0 deprecation Hebrew' '^OPEN Studio Pro row 8: 11\.8\.1 deprecation Deprecated Serbian' '^OPEN Studio Pro row 10: 11\.9\.1' '^OPEN Studio Pro row 12: 11\.12\.3' '!other-db-version: row is about postgresql 42' -- sh -c "$RIN --auto --facts $RI/facts-n19-min.json --out $RI/n19m.md >/dev/null; python3 $B/release_impact.py --check $RI/n19m.md"
# T2F-2: facts counted from the project: the clean model gives zeros, the used one counts workflows, own JDBC, the dev servlet; unknown stays out
ctl release-impact-facts-from-mpr-pass 0 'languages = \["en_US"\]' 'workflows = 0' 'own_jdbc = 0' 'dev_servlet = 0' 'database_connector = 0' 'db_vendor = "postgresql"' 'runtime_os = "linux"' '!unknown, left out' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-clean/App.mpr --db-vendor postgresql --db-version 16 --runtime-os linux --facts-out $RI/fc.json
ctl release-impact-facts-from-mpr-unknown-pass 0 'unknown, left out: db_vendor: pass --db-vendor' 'unknown, left out: runtime_os: pass --runtime-os linux' '!db_vendor =' '!runtime_os =' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-clean/App.mpr --facts-out $RI/fc0.json
ctl release-impact-facts-from-mpr-used-catch 0 'workflows = 1' 'own_jdbc = 1' 'dev_servlet = 1' 'own_java = 1' 'languages = \["en_US", "de_DE"\]' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-used/App.mpr --facts-out $RI/fu.json
# the same count on a real 11.x model (public in the repo): the always-present workflow settings part and native layout slot are no use
CUSTM=$(ls "$CUSTDIR"/*.mpr 2>/dev/null | head -1)
if [ -f "$CUSTM" ]; then
  ctl field-release-impact-facts-customer-pass 0 'workflows = 0' 'native_profile = false' 'rest_consumed = 1' 'odata_consumed = 0' 'rest_published = 0' '!unknown, left out: (native_profile|odata|rest)' 'languages = \["en_US"\]' 'own_jdbc = 0' -- python3 $B/release_impact.py --facts-from-mpr "$CUSTM" --facts-out $RI/cust.json
else skip field-release-impact-facts-customer-pass "no $CUSTM"; fi
# T2R3-3, N1R2-5: native_profile from the navigation profiles only. Atlas_Core BuildingBlocks with Platform Native and a
# Phone browser profile are no native use (false); a NativeNavigationProfile is (true); a profile of unknown kind is unknown
model facts-native-atlas > /dev/null; model facts-native > /dev/null; model facts-native-unknown > /dev/null
ctl release-impact-facts-native-atlas-pass 0 'native_profile = false' '!native_profile = true' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-native-atlas/App.mpr --facts-out $RI/fna.json
ctl release-impact-facts-native-profile-catch 0 'native_profile = true' 'native_profile: navigation profile Native_phone \(NativeNavigationProfile\)' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-native/App.mpr --facts-out $RI/fnn.json
ctl release-impact-facts-native-unknown-catch 0 'unknown, left out: native_profile: navigation profile of unknown kind: Watch_web \(NavigationProfile Watch\)' '!native_profile = ' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-native-unknown/App.mpr --facts-out $RI/fnu.json
RIF="python3 $B/release_impact.py --brain $RA --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto"
ctl release-impact-native-atlas-end-to-end-pass 1 '\| CodePush .*feature-absent: row is about native; native_profile=false \(fna2\.json\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/facts-native-atlas/App.mpr --facts-out $RI/fna2.json >/dev/null 2>&1; $RIF --facts $RI/fna2.json --out $RI/fna.md >/dev/null; cat $RI/fna.md; python3 $B/release_impact.py --check $RI/fna.md"
ctl release-impact-native-end-to-end-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.4\.0 removal Discontinued CodePush' '!CodePush .*not relevant \(auto\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/facts-native/App.mpr --facts-out $RI/fnn2.json >/dev/null 2>&1; $RIF --facts $RI/fnn2.json --out $RI/fnn.md >/dev/null; python3 $B/release_impact.py --check $RI/fnn.md"
ctl release-impact-native-unknown-end-to-end-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.4\.0 removal Discontinued CodePush' '!CodePush .*not relevant \(auto\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/facts-native-unknown/App.mpr --facts-out $RI/fnu2.json >/dev/null 2>&1; $RIF --facts $RI/fnu2.json --out $RI/fnu.md >/dev/null; python3 $B/release_impact.py --check $RI/fnu.md"
# T2R3-3: odata_consumed counts consumed services (documents), not element types (79 types were 1 service); an OData
# element with no OData document anywhere is unknown, never 0. T8R-11: rest_consumed = consumed REST documents plus REST
# call actions, SendRestRequestAction included (the old type count missed it: an app calling REST that way read 0)
model facts-services > /dev/null; model facts-odata-stray > /dev/null; model facts-rest-send > /dev/null
ctl release-impact-facts-services-count-pass 0 'odata_consumed = 1$' 'odata_published = 1$' 'rest_published = 0$' 'rest_consumed = 4$' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-services/App.mpr --facts-out $RI/fsv.json
ctl release-impact-facts-odata-stray-unknown-catch 0 'unknown, left out: odata_consumed: no odata consumed document, but Rest\$ODataRemoteEntitySource in other units' '!odata_consumed = ' 'odata_published = 0' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-odata-stray/App.mpr --facts-out $RI/fos.json
ctl release-impact-facts-rest-send-catch 0 'rest_consumed = 1$' -- python3 $B/release_impact.py --facts-from-mpr $M/facts-rest-send/App.mpr --facts-out $RI/frs.json
cp -R $RA $RI/brain-rest; echo '| 10.5.0 | Mar 5 | deprecation | odata-rest | Fixture: the Call REST service action now sends a changed User-Agent header. | consumed REST | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.5/) |' >> $RI/brain-rest/baseline/versions/studio-pro-upgrade-10.md
RIR="python3 $B/release_impact.py --brain $RI/brain-rest --from 9.24.2 --to 10.8.0 --plan $RF/plan-auto.txt --auto"
ctl release-impact-rest-send-end-to-end-catch 1 '^OPEN Studio Pro row [0-9]+: 10\.5\.0 deprecation Fixture: the Call REST service action' '!User-Agent.*not relevant \(auto\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/facts-rest-send/App.mpr --facts-out $RI/frs2.json >/dev/null 2>&1; $RIR --facts $RI/frs2.json --out $RI/frs.md >/dev/null; python3 $B/release_impact.py --check $RI/frs.md"
ctl release-impact-rest-absent-end-to-end-pass 1 'User-Agent.*not relevant \(auto\): feature-absent: row is about consumed REST; rest_consumed=0 \(fcr\.json\)' -- sh -c "python3 $B/release_impact.py --facts-from-mpr $M/facts-clean/App.mpr --facts-out $RI/fcr.json >/dev/null 2>&1; $RIR --facts $RI/fcr.json --out $RI/fcr.md >/dev/null; cat $RI/fcr.md; python3 $B/release_impact.py --check $RI/fcr.md"
# T8R-11 (RI-1): a test_inventory --json gives rest_consumed = REST clients + call activities; without the activity count: unknown
python3 -c "import json; d=json.load(open('$RF/inventory.json')); d['rest_call_activities']=[{'n': 4}]; json.dump(d, open('$RI/inv-calls.json','w')); d['rest_call_activities']=[{'n': 0}]; json.dump(d, open('$RI/inv-nocalls.json','w'))"
ctl release-impact-inventory-rest-calls-catch 0 '^\(4, .inv-calls\.json.\)$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.load_facts(['$RI/inv-calls.json'])['rest_consumed'])"
ctl release-impact-inventory-rest-none-pass 0 '^\(0, .inv-nocalls\.json.\)$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.load_facts(['$RI/inv-nocalls.json'])['rest_consumed'])"
ctl release-impact-inventory-rest-unknown-catch 0 '^None$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import release_impact as r; print(r.load_facts(['$RF/inventory.json']).get('rest_consumed'))"
# N1-9: --auto with one mpr (or none, with a facts file): works, and says what is lost
ctl release-impact-auto-one-mpr-pass 0 'facts: 1[0-9] counted from .*facts-clean/App\.mpr' 'auto cannot use: module rows and the kept/stranded rule: only one of --from-mpr/--to-mpr given' 'auto cannot use: runtime_os: unknown' 'auto cannot use: db_vendor: unknown' 'language-code' '!dotnet-ide-host' -- sh -c "$RIN --auto --from-mpr $M/facts-clean/App.mpr --out $RI/one.md; cat $RI/one.md"
ctl release-impact-auto-one-mpr-flags-pass 0 'facts: 1[0-9] counted from' '!auto cannot use: runtime_os' '!auto cannot use: db_vendor' 'dotnet-ide-host' 'other-db-version: row is about postgresql 13' -- sh -c "$RIN --auto --from-mpr $M/facts-clean/App.mpr --db-vendor postgresql --db-version 16 --runtime-os linux --out $RI/one2.md; cat $RI/one2.md"
ctl release-impact-one-mpr-no-auto-catch 1 'go together' -- $RIN --from-mpr $M/facts-clean/App.mpr --out $RI/one3.md
# T2F-4: an entry whose row the brain reworded is listed, kept across reruns, and returns with its row
cp -r $RN $RI/brain-n19b; sed -i 's/Intel-based Macs are no longer supported/Intel Macs are dropped/' $RI/brain-n19b/baseline/versions/studio-pro-upgrade-11.md
[ -f $RI/n19.md ] && sed -E 's/^(\| 4 \|.*\|) +\|$/\1 handled: evidence\/mac.md (arm64 checked) |/' $RI/n19.md > $RI/n19h.md
ctl release-impact-orphan-catch 0 'orphan entries: 1 handled entries matched no row' '^## Entries that matched no row \(1\)' '\| o1 \| Studio Pro \| 11\.6\.8 \| Studio Pro on macOS now runs natively on Apple Silicon \(arm64\)\. Intel-based Macs are no longer supported\. \| handled: evidence/mac\.md' -- sh -c "python3 $B/release_impact.py --brain $RI/brain-n19b --from 11.6.3 --to 11.12.3 --auto --facts $RF/facts-n19.json --out $RI/n19h.md; cat $RI/n19h.md"
ctl release-impact-orphan-check-pass 1 '^auto: 10, human: 0, open: 2$' '!OPEN .*o1' -- python3 $B/release_impact.py --check $RI/n19h.md
ctl release-impact-orphan-returns-pass 0 '\| 4 \| 11\.6\.8 \| breaking .*\| handled: evidence/mac\.md \(arm64 checked\) \|' '!Entries that matched no row' 'This run: 10 auto, 1 kept from a person, 1 open\.' -- sh -c "$RIN --auto --facts $RF/facts-n19.json --out $RI/n19h.md >/dev/null; cat $RI/n19h.md"
# T2F-3, T2F-5: a human entry where auto would also decide is counted, and a differing kind is listed
sed -E 's/^(\| 1 \|.*\|) not relevant \(auto\)[^|]*\|$/\1 handled: evidence\/dotnet.md |/; s/^(\| 3 \|.*\|) not relevant \(auto\)[^|]*\|$/\1 not relevant: own words |/' $RI/n19.md > $RI/n19w.md
ctl release-impact-would-auto-catch 0 'auto would also decide 2 rows that carry a human entry; 1 of them differ in kind \(auto says not relevant, the person says handled\)' 'row 1 \(11\.6\.5\): human `handled: evidence/dotnet\.md` vs not relevant \(auto\): dotnet-ide-host' 'This run: 8 auto, 2 kept from a person, 2 open\.' '!row 3 \(11\.6\.7\): human' -- sh -c "$RIN --auto --facts $RF/facts-n19.json --out $RI/n19w.md; cat $RI/n19w.md"
ctl release-impact-would-auto-quiet-pass 0 '!auto would also decide' -- sh -c "$RIN --auto --facts $RF/facts-n19.json --out $RI/n19q.md"
BRV=${UPG_BRAIN:-$HOME/Mendix/<company>-brain}
if [ -f $BRV/baseline/versions/studio-pro-upgrade-10.md ] && [ -f $BRV/baseline/versions/modules/task-queue-helpers.md ]; then
  # the real brain, read only. The 3.1.0 jump has no ShowSystemQueuesInCharts row in the brain (a gap, FEEDBACK V31-RI),
  # so the module catch uses the 3.1.0 requirement row.
  ctl brain-release-impact-java21-catch 0 '10\.21\.0 \| removal \| runtime \| Removed support for Java 11 and Java 17, please use Java 21' -- sh -c "python3 $B/release_impact.py --brain $BRV --from 10.12.9 --to 10.24.16 --out $RI/b.md && cat $RI/b.md"
  echo 'TaskQueueHelpers 2.0.2->3.1.0' > $RI/bp.txt
  ctl brain-release-impact-tqh-catch 0 '\| 3\.1\.0 \| requirement \| Module upgraded to require Mendix 10\.24\.0 minimum' -- sh -c "python3 $B/release_impact.py --brain $BRV --from 10.12.9 --to 10.24.16 --plan $RI/bp.txt --out $RI/bt.md && cat $RI/bt.md"
  ctl brain-release-impact-empty-pass 0 'Studio Pro 0 rows' -- python3 $B/release_impact.py --brain $BRV --from 10.24.16 --to 10.24.16 --out $RI/be.md
  echo 'NoSuchModuleQq 1.0.0->2.0.0' > $RI/bu.txt
  ctl brain-release-impact-unknown-catch 2 'UNKNOWN NoSuchModuleQq' -- python3 $B/release_impact.py --brain $BRV --from 10.24.16 --to 10.24.16 --plan $RI/bu.txt --out $RI/bu.md
else
  for n in java21-catch tqh-catch empty-pass unknown-catch; do skip brain-release-impact-$n "no brain version tables at $BRV"; done
fi

# --- replacement_check.py (B6): deprecated modules and patterns the app holds, whatever their version window -----------------
# One catch per detection kind (module, module version range, java, js, widget, native profile), a clean pass, a row the
# jump does not reach, a version that is no version number (UNKNOWN), and an app that cannot be read. Every run must list
# all 37 rows: a row is never dropped.
RC="python3 $B/replacement_check.py"
for v in replace-clean replace-sso replace-datagrid2 replace-java replace-metrics replace-metrics-new replace-js replace-chart replace-native replace-hashver replace-dojo replace-expr replace-strict replace-settings-924 replace-settings-set replace-react19 replace-react19-unused replace-react-bundled replace-react-fresh replace-mxlogger replace-mxlogger-quiet replace-java-id replace-java-id-ok replace-wc3 replace-wc3-absent replace-wc3-v2 replace-wc4; do model $v > /dev/null; done
ctl replace-clean-pass 0 '37 rows: 0 HIT \(open\), 0 UNKNOWN \(open\)' '!^HIT' '^NOT APPLICABLE R8 ' '^clear +R3 ' -- $RC $M/replace-clean --to 10.24.16
ctl replace-clean-11-pass 0 '37 rows: 0 HIT \(open\), 0 UNKNOWN \(open\)' '^clear +R9 .*' 'no widgets/ folder next to the \.mpr \(0 files\)' -- $RC $M/replace-clean --to 11.12.5
ctl replace-module-catch 1 '^HIT +R3 +MendixSSO module' 'evidence: module MendixSSO 3\.2\.1 \(Marketplace\)' '37 rows: 1 HIT' -- $RC $M/replace-sso --to 10.24.16
ctl replace-modver-catch 1 '^HIT +R11 ' 'evidence: module DataWidgets 2\.30\.4 \(Marketplace\) is <3\.0\.0' -- $RC $M/replace-datagrid2 --to 10.24.16
ctl replace-java-catch 1 '^HIT +R18 ' 'in javasource/myown/actions/Old\.java \(1\)' -- $RC $M/replace-java --to 11.12.5
# PV-5: IMendixIdentifier.getEntityId() (removed in 11) is a hit of R18; getType() and a longer method name are not
ctl replace-java-entityid-catch 1 '^HIT +R18 ' 'in javasource/myown/actions/Ids\.java \(1\)' -- $RC $M/replace-java-id --to 11.12.5
ctl replace-java-entityid-ok-pass 0 '!^HIT +R18' '37 rows: 0 HIT' -- $RC $M/replace-java-id-ok --to 11.12.5
# NS-1: the Mx10 metrics API (Core.metrics().counters()/timers()/gauges()) is gone in 11; DatadogConnector before 076dca76
ctl replace-metrics-catch 1 '^HIT +R18 ' 'in javasource/datadogconnector/connector/DatadogConnector\.java \(3\)' -- $RC $M/replace-metrics --to 11.12.5
ctl replace-metrics-new-pass 0 '^clear +R18 ' '!^HIT' -- $RC $M/replace-metrics-new --to 11.12.5
ctl replace-js-catch 1 '^HIT +R19 ' 'mx\\\.logger.* in javascriptsource/myown/actions/Log\.js \(1\)' 'dojo.* in javascriptsource/myown/actions/Dlg\.js \(1\)' '!node_modules' -- $RC $M/replace-js --to 11.12.5
ctl replace-js-jump-na-pass 0 '^NOT APPLICABLE R19 ' 'applies_on_jump ->11: not reached' '!^HIT' -- $RC $M/replace-js --to 10.24.16
ctl replace-widget-catch 1 '^HIT +R10 ' 'evidence: widget .* on MyOwn\.Home \(own\)' -- $RC $M/replace-chart --to 11.12.5
ctl replace-widget-jump-na-pass 0 '^NOT APPLICABLE R10 ' '!^HIT' -- $RC $M/replace-chart --to 10.24.16
ctl replace-native-catch 1 '^HIT +R23 ' 'evidence: a native navigation profile' -- $RC $M/replace-native --to 10.24.16
ctl replace-hashver-unknown-catch 1 '^UNKNOWN +R7 ' "Atlas_Core version '73355' is no version number" '37 rows: 0 HIT \(open\), 2 UNKNOWN' -- $RC $M/replace-hashver --to 11.12.5
# R30 (behaviour rule S1, b5-forms): expr: finds changedDate read in a microflow expression, not a longer name
ctl replace-expr-catch 1 '^HIT +R30 ' "MyOwn\\.ACT_Submit Microflows\\\$CreateVariableAction: 'secondsBetween\\(\\\$Response/createdDate, \\\$Response/changedDate\\)'" '!ACT_Local' 'jump crosses 10\.20|unchecked: whether the read happens BEFORE a Commit' -- $RC $M/replace-expr --to 11.12.5
ctl replace-expr-jump-na-pass 0 '^NOT APPLICABLE R30 .*' 'applies_on_jump 10->10\.20,10\.20->11\.0: not reached' '!^HIT' -- $RC $M/replace-expr --from 11.1.0 --to 11.12.5
# R31 (behaviour rule S2, StrictChangeBehavior): a by-name setValue in own Java and a call to ObjectHandling's by-name
# setter; a typed proxy setter and Marketplace Java (objecthandling/ORM.java) are no hit
ctl replace-strict-catch 1 '^HIT +R31 ' 'in javasource/myown/actions/SetByName\.java \(1\)' 'ObjectHandling\.setMemberValueByMemberName referenced by MyOwn\.ACT_SetByName' '!Typed\.java' '!objecthandling/ORM' 'StrictChangeBehavior was set to false' '37 rows: 1 HIT' -- $RC $M/replace-strict --to 11.12.5
ctl replace-strict-jump-na-pass 0 '^NOT APPLICABLE R31 ' 'applies_on_jump 9->10\.0,10\.0->11\.0: not reached' '!^HIT' -- $RC $M/replace-strict --from 11.1.0 --to 11.12.5
# NS-9: the three settings notification-service af8a3709 changed on the 10.24 rung (9.24 source: OQL v2 and the
# certificate algorithm absent, strict page URL check False); -set = the af8a3709 values, the jump forced across 10.24
ctl replace-settings-catch 1 '^HIT +R32 ' 'UseOQLVersion2 is absent' '^HIT +R33 ' 'StrictPageUrlCheck is False' '^HIT +R34 ' '37 rows: 3 HIT' -- $RC $M/replace-settings-924 --to 10.24.16
ctl replace-settings-set-pass 0 '^clear +R32 ' 'UseOQLVersion2 is True' '^clear +R33 ' '^clear +R34 ' 'SslCertificateAlgorithm is PKIX' '!^HIT' -- $RC $M/replace-settings-set --from 9.24.40 --to 10.24.16
ctl replace-settings-jump-na-pass 0 '^NOT APPLICABLE R32 ' '^NOT APPLICABLE R34 ' '!^HIT' -- $RC $M/replace-settings-set --to 11.12.5
# PRR-1: R37 predicts CE6779 (WorkflowCommons 4.x view entities need OQL v2) from the OLD model: WorkflowCommons <4.0.0 and UseOQLVersion2 false or
# absent, on a jump that reaches 11. Purchase Request had 3.12.1 + false and stopped at the build with 5 CE6779. Cleared by v2 on, by an installed 4.x
# (CE6779 would already show in the old model), and not reached by a 10.x target.
ctl replace-oql2-wc4-catch 1 '^HIT +R37 ' 'evidence: module WorkflowCommons 3\.12\.1 \(Marketplace\) is <4\.0\.0' 'evidence: setting Settings\$ModelSettings\.UseOQLVersion2 is False' -- $RC $M/replace-wc3 --to 11.12.5
ctl replace-oql2-wc4-absent-catch 1 '^HIT +R37 ' 'UseOQLVersion2 is absent' -- $RC $M/replace-wc3-absent --to 11.12.5
ctl replace-oql2-wc4-v2on-pass 1 '^clear +R37 ' 'UseOQLVersion2 is True' '!^HIT +R37 ' -- $RC $M/replace-wc3-v2 --to 11.12.5
ctl replace-oql2-wc4-installed4-pass 0 '^clear +R37 ' 'module WorkflowCommons 4\.10\.0 is not <4\.0\.0' '!^HIT' -- $RC $M/replace-wc4 --to 11.12.5
ctl replace-oql2-wc4-jump-na-pass 1 '^NOT APPLICABLE R37 ' 'applies_on_jump ->11: not reached' '!^HIT +R37 ' -- $RC $M/replace-wc3 --to 10.24.16
# NR2-24: R35 reads the JavaScript of widgets/*.mpk for React 19 removed APIs and joins it with the widgets pages use. Two packages call
# findDOMNode, only DropdownContainer (2 instances) is used; --no-newer turns that hit into a BLOCKER (owner stranded).
ctl replace-react19-catch 1 '^HIT +R35 ' 'evidence: widgets/DropdownContainer\.mpk 1\.2\.0 runs /.*findDOMNode.*/ in its JavaScript and widget DropdownContainer\.widget\.DropdownContainer is used 2 time\(s\) on MyOwn\.Home' '!widgets/ListViewControls' '!widgets/Markdown\.mpk' '!widgets/Guarded' '!^blockers:' -- $RC $M/replace-react19 --to 11.12.6
ctl replace-react19-blocker-catch 1 '^HIT +R35 ' 'evidence: BLOCKER \(no newer version: dropdowncontainer\): widgets/DropdownContainer\.mpk' '^blockers: R35: no update can fix these' -- $RC $M/replace-react19 --to 11.12.6 --no-newer DropdownContainer
ctl replace-react19-unused-pass 1 '^clear +R35 ' 'package\(s\) with /.*findDOMNode.* in their JavaScript, but no page uses them: widgets/DropdownContainer\.mpk, widgets/ListViewControls\.mpk' '!^HIT +R35' -- $RC $M/replace-react19-unused --to 11.12.6
ctl replace-react19-jump-na-pass 0 '^NOT APPLICABLE R35 ' '!^HIT +R35' -- $RC $M/replace-react19 --to 10.24.16
# MC-19: R36 reads widgets/*.mpk for a bundled older React (react.element without react.transitional.element) that a page uses.
# Viewer (used) bundles React 18; Fresh bundles 19 (carries both symbols); Plain loads React from the platform; Mention only compares against the element symbol (react-is style, Data Widgets 3.x); Spare is old and unused.
ctl replace-react-bundled-catch 1 '^HIT +R36 ' 'evidence: widgets/Viewer\.mpk 4\.0\.0 runs /.*react.*/ in its JavaScript and widget Viewer\.widget\.Viewer is used 1 time\(s\) on MyOwn\.Home' '!widgets/Fresh' '!widgets/Plain' '!widgets/Mention' '!widgets/Spare' -- $RC $M/replace-react-bundled --to 11.12.6
ctl replace-react-bundled-blocker-catch 1 '^HIT +R36 ' 'evidence: BLOCKER \(no newer version: viewer\): widgets/Viewer\.mpk' '^blockers: R36: no update can fix these' -- $RC $M/replace-react-bundled --to 11.12.6 --no-newer Viewer
ctl replace-react-bundled-fresh-pass 1 '^clear +R36 ' 'package\(s\) with /.*react.* in their JavaScript, but no page uses them: widgets/Spare\.mpk' '!^HIT +R36' -- $RC $M/replace-react-fresh --to 11.12.6
ctl replace-react-bundled-jump-na-pass 0 '^NOT APPLICABLE R36 ' '!^HIT +R36' -- $RC $M/replace-react-bundled --to 10.24.16
# V3D-1: the evidence of R36 names the library whose React copy it is (spinningBubbles marker = react-loading).
ctl replace-react-bundled-library-catch 1 '^HIT +R36 ' 'widget Viewer\.widget\.Viewer is used 1 time\(s\) on MyOwn\.Home \(own\); the bundled copy belongs to react-loading 2\.x' -- $RC $M/replace-react-bundled --to 11.12.6
# V3D-2: a patched package still matches (the dead copy stays in the file): accepted by the sha256 of that exact file, with a reason.
VSHA=$(shasum -a 256 $M/replace-react-bundled/widgets/Viewer.mpk | cut -d' ' -f1)
printf '# patched by a person\n%s spinner replaced, owner informed\n' "$VSHA" > $T/accept-viewer.txt
printf '%s spinner replaced, owner informed\n' "0000000000000000000000000000000000000000000000000000000000000000" > $T/accept-other.txt
printf 'notasha reason\n' > $T/accept-bad.txt
ctl replace-react-bundled-accept-pass 1 '^clear +R36 ' 'accepted by checksum, not reported: widgets/Viewer\.mpk 4\.0\.0 \(sha256 [0-9a-f]{12}: spinner replaced, owner informed\)' '!^HIT +R36' '!^blockers:' -- $RC $M/replace-react-bundled --to 11.12.6 --no-newer Viewer --accept $T/accept-viewer.txt
ctl replace-react-bundled-accept-other-file-catch 1 '^HIT +R36 ' 'evidence: BLOCKER \(no newer version: viewer\): widgets/Viewer\.mpk' '^blockers: R36' -- $RC $M/replace-react-bundled --to 11.12.6 --no-newer Viewer --accept $T/accept-other.txt
ctl replace-accept-badline-catch 2 "want '<sha256 of the .mpk> <reason>'" -- $RC $M/replace-react-bundled --to 11.12.6 --accept $T/accept-bad.txt
# QI-3: R38 reads the JavaScript of widgets/*.mpk for mx.logger (removed in 11.0) and joins it with the pages that use the widget.
ctl replace-mxlogger-catch 1 '^HIT +R38 ' 'evidence: widgets/Logger\.mpk 1\.3\.16 runs /.*mx.*logger.*/ in its JavaScript and widget Logger\.widget\.Logger is used 1 time\(s\) on MyOwn\.Home' '!widgets/Quiet' '!widgets/Spare\.mpk 1' -- $RC $M/replace-mxlogger --to 11.12.6
ctl replace-mxlogger-blocker-catch 1 '^HIT +R38 ' 'evidence: BLOCKER \(no newer version: logger\): widgets/Logger\.mpk' '^blockers: R38: no update can fix these' -- $RC $M/replace-mxlogger --to 11.12.6 --no-newer Logger
ctl replace-mxlogger-unused-pass 1 '^clear +R38 ' 'package\(s\) with /.*mx.*logger.* in their JavaScript, but no page uses them: widgets/Spare\.mpk' '!^HIT +R38' -- $RC $M/replace-mxlogger-quiet --to 11.12.6
ctl replace-mxlogger-jump-na-pass 0 '^NOT APPLICABLE R38 ' '!^HIT +R38' -- $RC $M/replace-mxlogger --to 10.24.16
ctl replace-out-md-pass 1 '^\| R3 \| HIT \| MendixSSO module' '^\| R8 \| NOT APPLICABLE \|' '\| handled \|$' -- sh -c "$RC $M/replace-sso --to 10.24.16 --out $T/replace-sso.md >/dev/null; rc=\$?; cat $T/replace-sso.md; exit \$rc"
# --- B6-2: brain_mine.py, replacement candidates from the brain's release-note tables (no LLM) ---
BM="python3 $B/brain_mine.py"
ctl brain-mine-pass 0 '^brain-mine: 2 deprecated components, 1 recurring successors, 4 rows, 3 new' '^\| Combo Box \| 2 \| 2 \| Alpha Module .*Beta Widget .*\| R8(, R[0-9]+)* \|$' '!Fixed a typo' -- sh -c "$BM --brain $FX/brain-mine --out $T/brain-mine.md >/dev/null && cat $T/brain-mine.md"
ctl brain-mine-new-catch 0 '^\| \[Gamma Legacy Picker\].*\| \*\*new\*\* \|$' '^\| \[Mendix SSO\].*\| R3 \|$' '^\| Beta Widget .* deprecation .*Zeta Element widget \| \*\*new\*\* \|' -- sh -c "$BM --brain $FX/brain-mine --out $T/brain-mine-new.md >/dev/null && cat $T/brain-mine-new.md"
ctl brain-mine-to-pass 0 '^brain-mine: 2 deprecated components, 0 recurring successors, 1 rows' -- $BM --brain $FX/brain-mine --to 9.24 --out $T/brain-mine-to.md
ctl brain-mine-nobrain-catch 2 'no brain module tables at ' -- $BM --brain $T/no-brain --out $T/brain-mine-x.md
ctl replace-deprecated-widgets-catch 1 '^HIT +R25 ' '^HIT +R26 ' 'evidence: widget .*MicroflowTimer.* on MyOwn\.Home \(own\)' -- $RC $M/replace-dojo --to 11.12.5
ctl replace-deprecated-widgets-jump-na-pass 1 '^HIT +R25 ' '^NOT APPLICABLE R26 ' -- $RC $M/replace-dojo --to 10.24.16
# --- B6-4: dojo_report.py, Dojo to React client per widget package (fixtures/dojo-successors.tsv is a control table) ---
DR="python3 $B/dojo_report.py"; DRT=$FX/dojo-successors.tsv
model dojo-react > /dev/null
ctl dojo-react-11-advisory-pass 0 '^dojo-react dojo-react: 5 packages, 1 ready, 1 can move, 1 delete, 1 can.t move, 1 not researched, 0 unreadable; legacy core widgets 1 in 1 documents; modules not React-ready 1; Dojo JS 1 files; ADVISORY for 11\.12\.5$' -- $DR $M/dojo-react --to 11.12.5 --table $DRT
ctl dojo-react-12-blocking-catch 1 'BLOCKING for 12\.0$' -- $DR $M/dojo-react --to 12.0 --table $DRT
ctl dojo-react-md-catch 0 '^\| can.t move \| Stuck\.mpk \| 1\.1 \| Stuck\.widget\.Stuck \(1\) \| rebuild' '^\| can move \| Moving\.mpk \| 2\.0\.0 \| Moving\.widget\.Moving \(2\) \| newer-pluggable: .*\(Mendix 10\.6\.0\+\) \| .*\[partial\] \|$' '^\| not researched \| Fresh\.mpk ' '^\| delete \| Unused\.mpk \| 3\.0\.0 \| none ' '^\| Template grid \(legacy\) \| 1 \| MyOwn\.Home \| Gallery ' '^\| javascriptsource/myown/actions/Dlg\.js \| myown \(own\) \| dojo, mx\.ui\.openForm \|$' '^theme/web/index\.html: compare' '^\| Old Chart module \| OldChart \| New Chart widget \| https://example\.invalid/oldchart \[partial\] \|$' 'pluggable-widget-tools 9\.4\.1' '!Clean\.js' -- sh -c "$DR $M/dojo-react --to 11.12.5 --table $DRT --out $T/dojo-react.md >/dev/null && cat $T/dojo-react.md"
ctl dojo-react-clean-12-pass 0 '^dojo-react replace-clean: 0 packages, .* Dojo JS 0 files; ready for 12\.0$' -- $DR $M/replace-clean --to 12.0 --table $DRT
ctl dojo-react-overview-pass 0 '^\| Moving\.mpk \| 1 \| 2 \| dojo-react: can move \|' '!Markdown\.mpk' -- sh -c "$DR $M/dojo-react $M/replace-clean --to 11.12.5 --table $DRT --out $T/dojo-out --overview $T/dojo-ov.md >/dev/null && test -f $T/dojo-out/replace-clean.md && cat $T/dojo-ov.md"
ctl dojo-react-playbook-pass 0 'ADVISORY for 11\.12\.5$' -- $DR $M/replace-clean --to 11.12.5
printf 'match\tcomponent\tinstalled\tstatus\treact_path\tmin_mendix\tsource\tverified\tnote\nX\tX\t-\tmaybe\t-\t-\t-\tno\t-\n' > $T/dojo-bad.tsv
ctl dojo-react-badtable-catch 2 "status 'maybe' is not one of" -- $DR $M/replace-clean --to 11.12.5 --table $T/dojo-bad.tsv
# NS-5: bin/vendorjava.py, Marketplace Java switched off by hand. DatadogConnector before and after 076dca76 (three
# metric bodies commented out); ported = the same file on the 11 API; own = the same edit in an own module.
model vendorjava > /dev/null; VJ=$T/vj; VJF=$FX/vendorjava; VJB="python3 $B/vendorjava.py"; VJD=javasource/datadogconnector/connector/DatadogConnector.java
for k in catch ported own; do rm -rf $VJ/$k; mkdir -p $VJ; cp -R $M/vendorjava $VJ/$k
  (cd $VJ/$k && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm base); done
cp $VJF/DatadogConnector-076dca76.java $VJ/catch/$VJD; cp $VJF/DatadogConnector-ported.java $VJ/ported/$VJD
sed 's/package datadogconnector.connector;/package myown.metrics;/; s/class DatadogConnector/class OwnMetrics/' $VJF/DatadogConnector-076dca76.java > $VJ/own/javasource/myown/metrics/OwnMetrics.java
ctl vendorjava-commented-catch 1 '^COMMENTED-OUT javasource/datadogconnector/connector/DatadogConnector\.java \(datadogconnector\): 10 code line' '^EMPTIED +.*DatadogConnector\.java .*count\(3 parameters\)' '^EMPTIED +.*time\(3 parameters\)' '^EMPTIED +.*gauge\(3 parameters\)' 'Marketplace modules of the \.mpr' '^verdict: REVIEW' '!proxies' -- $VJB $VJ/catch --base HEAD
# PLM-31: the same switched-off code arrives with a module update commit ("step:"): the vendor's own edit, skipped and
# counted; a later hand commit on the same file is still a finding.
for k in upd hand; do rm -rf $VJ/$k; cp -R $M/vendorjava $VJ/$k
  (cd $VJ/$k && git init -q && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm base && cp $VJF/DatadogConnector-076dca76.java $VJD \
   && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm "step: DatadogConnector 3.0.0 (stepupdate, idcheck PASS)"); done
(cd $VJ/hand && echo '// local note' >> $VJD && git add -A . && git -c user.email=c@c -c user.name=ctl commit -qm "disable datadog until fixed")
ctl vendorjava-update-commit-pass 0 '^verdict: PASS' '1 skipped: changed only by a module update commit' '!COMMENTED-OUT' -- $VJB $VJ/upd --base HEAD~1
ctl vendorjava-update-then-hand-catch 1 '^COMMENTED-OUT javasource/datadogconnector' '^verdict: REVIEW' '!skipped' -- $VJB $VJ/hand --base HEAD~2
ctl vendorjava-ported-pass 0 '1 Java files compared with HEAD: 0 with newly commented-out code, 0 emptied methods' '^verdict: PASS' -- $VJB $VJ/ported --base HEAD
ctl vendorjava-own-module-pass 0 '^verdict: PASS' '!OwnMetrics' -- $VJB $VJ/own --base HEAD
ctl vendorjava-modules-arg-catch 1 '^EMPTIED +javasource/myown/metrics/OwnMetrics\.java' '\(--modules\)' -- $VJB $VJ/own --base HEAD --modules MyOwn
ctl vendorjava-bad-base-catch 2 'not a commit in the git repository' -- $VJB $VJ/catch --base no-such-rev
mkdir -p $T/replace-noapp
ctl replace-noapp-catch 2 'cannot read the app .*expected exactly one \.mpr, found 0' -- $RC $T/replace-noapp --to 11.12.5
if [ -f "$CUSTM" ]; then
  ctl field-replace-customer-pass 1 '37 rows: 1 HIT \(open\), 0 UNKNOWN' '^HIT +R9 ' '!^HIT +R12 ' '^NOT APPLICABLE R20 ' -- $RC "$CUSTM" --to 11.12.5
else skip field-replace-customer-pass "no $CUSTM"; fi

# --- RD-1: test-readiness scorecard (readiness.py): what triage can tell before any upgrade work -----------------------
# Work dirs are copies (readiness.py writes readiness.md/json into the work dir); synthetic names only. Each case is
# modelled on a 13 and 14 Oct run: notif R2 (57% of generated journeys fail on the OLD app), notif R1 (UNKNOWN consumed
# endpoints), PLM and PV360 (guest access, no confirmed anonymous process), an empty frozen database, a Teamcenter app.
RD=$B/readiness.py; RDW=$T/readiness; rm -rf $RDW; cp -R $FX/readiness $RDW
RDM=$(model rd-roles); RDG=$(model rd-guest); RDT=$(model rd-tc); echo dump > $T/rd-demo.sql
ctl readiness-journeys-57-catch 3 '^# Test readiness \(baseline\)' '^best reachable verdict: INVALID unless journeys: confirmed key-user processes' \
  '\| journeys \| CANNOT JUDGE \(blocks\) \| 233 of 406 actions fail on the OLD app \(57% > 30%\)' '\| data \| READY \(fallback: seeded rows\)' \
  'then at best: PASS \(on stand-in APIs: Payments, Shipping; on seeded rows\)' -- python3 $RD $RDW/seeded-57 --app $RDM
echo '{"coverage": {"G": 100, "D": 20, "A": 90}}' > $T/rd-under-bar.json
ctl readiness-journeys-under-bar-pass 4 '\| journeys \| READY \| 20 of 100 fail on the old app \(<= 30%\)' '!CANNOT JUDGE' \
  -- python3 $RD $RDW/seeded-57 --app $RDM --journeys-summary $T/rd-under-bar.json
ctl readiness-unknown-apis-catch 3 '^# Test readiness \(triage\)' '^best reachable verdict: INVALID unless apis: test-system URLs for Ledger, Payments' \
  '\| apis \| NEEDS 3 UNKNOWN endpoints classified or test-system URLs \(blocks\)' \
  '1 URL constant no modelled call reads \(classify with a reason\), 1 location from data \(seed the /a/ URL\), 1 hard-coded URL' \
  -- python3 $RD $RDW/unknown-apis --app $RDM
ctl readiness-test-systems-close-unknown-pass 4 '\| apis \| READY \|' '!UNKNOWN endpoints classified' \
  -- sh -c "printf 'Payments https://pay.test.invalid\nLedger https://ledger.test.invalid # sandbox\n' > $T/rd-ts.txt; python3 $RD $RDW/unknown-apis --app $RDM --test-systems $T/rd-ts.txt"
ctl readiness-anonymous-catch 3 '^best reachable verdict: INVALID unless journeys: a key user confirms one process an anonymous visitor follows' \
  '\| journeys \| NEEDS a confirmed key-user process as Guest \(blocks\) \| guest access is on \(role Guest\).*\(no processes\.md\)' \
  -- python3 $RD $RDW/anonymous-only --app $RDG
ctl readiness-anonymous-confirmed-pass 4 '^best reachable verdict: PASS \(on stand-in APIs: Payments, Shipping; on seeded rows\)$' '!as Guest' \
  -- python3 $RD $RDW/anonymous-confirmed --app $RDG
ctl readiness-no-data-catch 3 '^best reachable verdict: INVALID unless data: a demo data snapshot or a copy of a test database' \
  '\| data \| CANNOT JUDGE \(blocks\) \| the frozen database holds 0 rows outside System \(3 entities\)' -- python3 $RD $RDW/no-data --app $RDM
ctl readiness-plain-pass 0 '^best reachable verdict: PASS$' '\| data \| READY \| route a: ' '\| apis \| READY \| .*every system has a test URL' \
  -- python3 $RD $RDW/clean --app $RDM --test-systems $RDW/clean/test-systems.txt --data $T/rd-demo.sql
ctl readiness-stand-in-pass 4 '^best reachable verdict: PASS \(on stand-in APIs: Payments, Shipping; on seeded rows\)$' \
  '\| apis \| NEEDS test-system URLs or accept stand-in APIs \(fallback: stand-in\)' -- python3 $RD $RDW/clean --app $RDM
ctl readiness-tc-no-proof-catch 4 '^best reachable verdict: PASS \(on seeded rows; except Teamcenter: connector pages\)$' \
  '\| connectors \| NEEDS connector proof values \(fallback: except\) \| Teamcenter connector present and no connectors\.md' \
  -- python3 $RD $RDW/tc --app $RDT --test-systems $RDW/tc/test-systems.txt
ctl readiness-tc-proof-pass 4 '\| connectors \| READY \| 1 connector block\(s\) with proof values and mock signs' '!except Teamcenter' \
  -- python3 $RD $RDW/tc-proof --app $RDT
ctl readiness-no-model-invalid 2 '^best reachable verdict: NOT JUDGED until read: no model \(--app\)' '^Not read: no model' '!verdict: PASS' \
  -- python3 $RD $RDW/clean --md $T/rd-nm.md --json $T/rd-nm.json
ctl readiness-json-pass 3 '"rung": "journeys"' '"status": "CANNOT JUDGE"' '"exit": 3' '"phase": "baseline"' \
  -- sh -c "python3 $RD $RDW/seeded-57 --app $RDM >/dev/null; rc=\$?; cat $RDW/seeded-57/readiness.json; exit \$rc"
ctl readiness-no-workdir-invalid 2 'not a directory' -- python3 $RD $T/rd-nonexistent
# field: the 13 and 14 Oct evidence. Each top line must predict what the gate found later (outputs go to $T, never the lab)
if [ -f "$LAB/notif/r2/work/original/NotificationService.mpr" ]; then
  ctl field-readiness-notif-r2-catch 3 '233 of 406 actions fail on the OLD app \(57% > 30%\)' '\| apis \| NEEDS 34 UNKNOWN' \
    -- python3 $RD $LAB/notif/r2/work --app $LAB/notif/r2/work/original/NotificationService.mpr --md $T/rd-r2.md --json $T/rd-r2.json
else skip field-readiness-notif-r2-catch "no $LAB/notif/r2"; fi
if [ -f "$LAB/tc-apps/plm/work/original.mpr" ]; then
  ctl field-readiness-plm-catch 3 'NEEDS a confirmed key-user process as Anonymous \(blocks\)' 'except Teamcenter: connector pages' \
    -- python3 $RD $LAB/tc-apps/plm/work --app $LAB/tc-apps/plm/work/original.mpr --md $T/rd-plm.md --json $T/rd-plm.json
else skip field-readiness-plm-catch "no $LAB/tc-apps/plm"; fi

# --- field controls on the E1 / E5 evidence -------------------------------------------------------------------------------
echo "== field controls ($LAB)"
E1=$LAB/f1/runs/e1/app; E5=$LAB/e5/run/app; E1W=$LAB/f1/runs/e1/work; E5W=$LAB/e5/run/work
F=$T/field
e1mpr() { local n=${1//^/p}; [ -f $F/e1-$n.mpr ] || git -C $E1 show "$1:common-parts-app.mpr" > $F/e1-$n.mpr; echo $F/e1-$n.mpr; }
tree() { local repo=$1 rev=$2 d=$F/$3-${2//^/p}; shift 3; [ -d $d ] || { mkdir -p $d; git -C $repo archive "$rev" -- "$@" | tar -x -C $d; }; echo $d; }
bs_export() {  # the root files of commit $1 whose names hold a backslash, into $2 (names as git stores them)
  git -C $E1 ls-tree -z --name-only $1 | tr '\0' '\n' | grep -F '\' | while IFS= read -r n; do git -C $E1 cat-file blob "$1:$n" > "$2/$n"; done; }
if [ -d $E1/.git ]; then
  O=$(e1mpr e5b9c07)
  ctl field-e1-constcheck-catch 1 'CHANGED +MFAmodule\.EnabledMFA' -- python3 $B/constcheck.py $O $(e1mpr cdffd75)
  echo 'SAML20.KeystorePassword # control: the environment sets it' > $T/e1-allow.txt
  # since v3 an added behaviour switch is REVIEW; this control is about EnabledMFA, so the six added switches are accepted
  printf '%s # control: added switch, not what this control judges\n' 'MFAmodule.DatadogCloudSIEMLogging' 'MFAmodule.WebAuthn_*' 'TaskQueueHelpers.ShowSystemQueuesInCharts' 'UserCommons.DisableMxAdmin' >> $T/e1-allow.txt
  ctl field-e1-constcheck-pass 0 '!EnabledMFA' -- python3 $B/constcheck.py $O $(e1mpr 693f127) --allow $T/e1-allow.txt
  ctl field-e1-step-idcheck-catch 1 'RED +REMOVED +attribute +MFAmodule\.MFA\.QR_Url' -- python3 $B/idcheck.py $(e1mpr 39d137f^) $(e1mpr 39d137f)
  ctl field-e1-step-idcheck-pass 0 'findings: 0 total' -- python3 $B/idcheck.py $(e1mpr 702ea9b^) $(e1mpr 702ea9b)
  ctl field-e1-vs-original-blind 1 'findings: [1-9]' -- python3 $B/idcheck.py $O $(e1mpr 702ea9b)
  ctl field-e1-netzero-catch 1 'RED +REMOVED +attribute +SAML20\.SSOConfiguration\.UserType' -- python3 $B/idcheck.py $(e1mpr 588c241^) $(e1mpr 588c241)
  ctl field-e1-netzero-pass 0 'transient: not in the original app, net zero' -- python3 $B/idcheck.py $(e1mpr 588c241^) $(e1mpr 588c241) --baseline $O
  ctl field-e1-replay-guid-catch 1 'GUID_CHANGED +attribute +MFAmodule\.MFA\.QR_Url' -- python3 $B/idcheck.py $O $(e1mpr e7afde1^)
  cp $(e1mpr e7afde1^) $F/restored.mpr
  ctl field-e1-restore-guid 0 'written' -- python3 $B/restore_guid.py $F/restored.mpr MFAmodule.MFA.QR_Url --from $O
  ctl field-e1-restore-guid-identical 0 -- cmp $F/restored.mpr $(e1mpr e7afde1)
  ctl field-e1-missing-deps-catch 1 'UserCommons' -- python3 $B/repair/missing_deps.py $(tree $E1 702ea9b e1 common-parts-app.mpr widgets)
  ctl field-e1-missing-deps-pass 0 '!MISSING' -- python3 $B/repair/missing_deps.py $(tree $E1 57b9c94 e1 common-parts-app.mpr widgets)
  if [ -s ~/.mxcli/marketplace-catalog-default.json ]; then
    ctl field-catalog-missing-deps-catch 1 '^  Marketplace: content 115826 .Pop-up Menu.' '^  Marketplace: content 223053 .UserCommons.' -- python3 $B/repair/missing_deps.py --catalog ~/.mxcli/marketplace-catalog-default.json $M/missing-deps
  else skip field-catalog-missing-deps-catch "no ~/.mxcli/marketplace-catalog-default.json"; fi
  ctl field-e1-jardedupe-catch 1 '87 ' -- python3 $B/repair/jardedupe.py $(tree $E1 a3a18f9^ e1 userlib vendorlib)
  ctl field-e1-jardedupe-pass 0 -- python3 $B/repair/jardedupe.py $(tree $E1 a3a18f9 e1 userlib vendorlib)
  bsd=$F/e1-bs; mkdir -p $bsd
  bs_export ccf8ac2 $bsd
  ctl field-e1-backslash-catch 1 '17 ' -- python3 $B/repair/backslash_paths.py $bsd
  bsp=$F/e1-bs-fixed; mkdir -p $bsp
  bs_export f290355 $bsp
  ctl field-e1-backslash-pass 0 -- python3 $B/repair/backslash_paths.py $bsp
  ctl field-e1-checkdiff-catch 1 'WORSE.*CE2729' -- python3 $B/checkdiff.py $E1W/check-1.log $E1W/check-6.log
  ctl field-e1-checkdiff-pass 0 '^OK' -- python3 $B/checkdiff.py $E1W/check-6.log $E1W/check-7.log
  ctl field-e1-logdiff-catch 1 'REVIEW +NEW.*EnabledWebAuthn' -- python3 $B/logdiff.py $LAB/f1/mig/logs/runtime-e1old.log $LAB/f1/mig/logs/runtime-e1new.log
  ctl field-e1-logdiff-pass 0 'REVIEW 0' -- python3 $B/logdiff.py $LAB/f1/mig/logs/runtime-e1old.log $LAB/f1/mig/logs/runtime-e1old.log
  # finding of this rework, not of the E1 run: the final E1 MDA lost the SAML20.KeystorePassword value the old app had
  ctl field-e1-mda-keystore-finding 1 'CHANGED +SAML20\.KeystorePassword' -- python3 $B/constcheck.py $E1W/old-10.12.9-fallback.mda $E1W/new-10.24.16.mda
  # journeys (steps/journeys.md): the impact map must surface the E1 defect; a role without a test user is INVALID, never PASS
  ctl field-e1-impact-catch 0 'high.*MFAmodule\.EnabledMFA.*True.*False.*startup tree' -- python3 $B/impact_map.py $O $(e1mpr cdffd75) --md /dev/stdout --out $F/impact-e1.json
  ctl field-e1-impact-pass 0 '^0 changes' -- python3 $B/impact_map.py $O $O --out $F/impact-e1-same.json
  ctl field-e1-gen-mfa-journey 0 'mfa-password-only-refused' -- sh -c "python3 $B/gen_journeys.py $F/impact-e1.json --out-dir $F/gen-e1 --roles-with-users User > /dev/null && cat $F/gen-e1/plan.json"
  echo '{}' > $F/no-users.json
  ctl field-e1-journeys-no-user-invalid 3 'INVALID +login-User .*no test user' 'skipped: no test user' 'todo: ' '!^ +PASS ' -- \
    python3 $B/run_journeys.py $F/gen-e1 --label nouser --port 1 --admin-port 2 --admin-pass x --users $F/no-users.json --work $F/e2e-nouser
  for d in $LAB/f1/mig/tools/mxbuild-10.24.16 $LAB/f1/mig/tools/runtime-10.24.16; do
    [ -d $d ] && ctl field-mxversion-$(basename $d) 0 '^10\.24\.16\.96987$' -- python3 $B/mxversion.py $d
  done
else skip field-e1 "no $E1"; fi
if [ -d $E5/.git ]; then
  ctl field-e5-widget-broken-catch 1 'BROKEN widget package ListViewControls\.mpk' -- python3 $B/repair/missing_deps.py $(tree $E5 HEAD e5 "$(git -C $E5 ls-tree --name-only HEAD | grep '\.mpr$' | head -1)" widgets)
  ctl field-e5-javafinal-catch 1 'ContentType' -- python3 $B/javafinal.py $(tree $E5 71aa03c^ e5 javasource)
  ctl field-e5-javafinal-pass 0 -- python3 $B/javafinal.py $(tree $E5 71aa03c e5 javasource)
  ctl field-e5-scancover-catch 1 'NO COVERAGE' -- python3 $B/scancover.py $E5W/findings.json
  ctl field-e5-restcontract-pass 0 '^PASS' '!^FAIL' -- python3 $B/restcontract.py $E5W/rest-before $E5W/rest-after
  ctl field-e5-new-endpoint-catch 2 'NEW_ENDPOINT 4' -- python3 $B/diff.py $E5W/before.json $E5W/after.json --allow $E5W/allow.txt
  { cat $E5W/allow.txt; echo 'http./rest-doc/*/openapi.json # control: 10.x serves openapi.json where 9.x had swagger.json'; } > $T/e5-allow.txt
  ctl field-e5-new-endpoint-pass 0 'NEW_ENDPOINT 0' -- python3 $B/diff.py $E5W/before.json $E5W/after.json --allow $T/e5-allow.txt
else skip field-e5 "no $E5"; fi

# --- field controls on the E4 / E5b evidence (screens, constants, toolsets, polluted baseline) ---------------------------------
E4W=$LAB/f1/runs/e4/work; E5BW=$LAB/e5/run2/work
if [ -d $E4W/e2e-after ]; then
  ctl field-e4-shotdiff-catch 1 '^REVIEW +shots-Administrator/menu_.*TaskQueueMonitoring.*empty now' -- python3 $B/shotdiff.py $E4W/e2e-before-picked $E4W/e2e-after
  ctl field-e4-shotdiff-pass 0 'REVIEW 0' 'INVALID 0' -- python3 $B/shotdiff.py $E4W/e2e-base-run $E4W/e2e-base-run2
  ctl field-e4-journeys-screen-catch 1 'SCREEN REVIEW' -- python3 $B/run_journeys.py x --label after --work $E4W/e2e-after --compare $E4W/e2e-before-picked --rejudge
  ctl field-e4-constcheck-catch 1 'REVIEW +ADDED +TaskQueueHelpers\.ShowSystemQueuesInCharts' -- python3 $B/constcheck.py $E4W/old-10.12.9.mda $E4W/new-10.24.16.mda
  ctl field-e4-polluted-baseline-catch 1 'FAIL' -- python3 $B/diff.py $E4W/before.json $E4W/before2.json
  ctl field-e4-polluted-baseline-pass 0 'FAIL 0' -- python3 $B/diff.py $E4W/before2.json $E4W/before2.json
  ctl field-e4-localedits-unknown-catch 1 'UNKNOWN \(not judged\): [1-9]' 'GoogleAuthenticator .*package made before 9\.18' 'CSV .*jar-only edits' 'Atlas_Web_Content .*verified=false \(91' -- \
    env UPG_MXCLI=/usr/bin/false FAKE_DIFF=$E4W/localedits-diff.json python3 $B/localedits.py $E4W/original.mpr --proxy ExcelImporter=10.7.4 --proxy OQL=3.0.0 --proxy XLSReport=7.5.2 --mxcli-diff --mxcli-cmd "python3 $here/lib/fakemxdiff.py"
  ctl field-e4-impact-excluded-pass 0 'FeedbackModule\.ACT_ClearForm.*Nanoflow removed' '!ShareFeedback_Logo.*still references' '!SE_LogCleanUp.*removed' -- python3 $B/impact_map.py $E4W/original.mpr $LAB/f1/runs/e4/app --md /dev/stdout --out $F/imp-e4.json
  (cd / && python3 $B/gen_journeys.py $E4W/impact.json --out-dir $F/gen-e4 > $F/gen-e4.out 2>&1)
  ctl field-e4-gen-anonymous-catch 0 'anonymous-Guest' -- python3 -c "import json; print([e['id'] for e in json.load(open('$F/gen-e4/plan.json'))['skipped']])"
  ctl field-e4-gen-popup-home-catch 0 'no menu in its layout' 'Please scan the QR Code' -- sh -c "grep -l 'no menu in its layout' $F/gen-e4/journeys/*/login-*.journey.json | xargs cat"
  ctl field-e4-checkdiff-cascade-pass 0 '^CASCADE: .*CE1613 \(121 -> 0\) is gone.*CE0463 217' -- python3 $B/checkdiff.py $E4W/check-3.log $E4W/check-4.log --fixed CE1613
  if [ -f "$LAB/e5/run3/app/themesource/platformdesignsystem/web/design-properties.json" ]; then
    # field E7-5: the real design-properties files of the E7 app (copied, never touched): only platformdesignsystem is
    # picked, its 27 property-level oldNames are hidden for the rename, the copy is restored byte for byte
    FP=$F/pds7; for d in $LAB/e5/run3/app/themesource/*/web; do m=${d%/web}; m=${m##*/}; mkdir -p $FP/themesource/$m/web; cp $d/design-properties.json $FP/themesource/$m/web/ 2>/dev/null; done; : > $FP/App.mpr
    printf '#!/bin/bash\npython3 -c "import json,sys; d=json.load(open(sys.argv[1])); n=sum(1 for ps in d.values() for q in ps if \\"oldNames\\" in q); print(\\"pds clean at rename\\" if n == 0 else f\\"{n} property-level oldNames at rename\\")" %s/themesource/platformdesignsystem/web/design-properties.json\n' $FP > $F/pds7mx.sh; chmod +x $F/pds7mx.sh
    ctl field-e7-pds-oldnames-catch 0 'hidden 27 property-level oldNames .*platformdesignsystem' 'Margin top <- Spacing top' 'pds clean at rename' 'restored 1 ' -- env UPG_PDS_MX=$F/pds7mx.sh zsh $B/repair/pds_oldnames.sh 10.24.16 $FP/App.mpr
    ctl field-e7-pds-oldnames-restored-pass 0 -- cmp $LAB/e5/run3/app/themesource/platformdesignsystem/web/design-properties.json $FP/themesource/platformdesignsystem/web/design-properties.json
  fi
  ctl field-e4-checkdiff-worse-catch 1 '^WORSE: errors 121 -> 219' -- python3 $B/checkdiff.py $E4W/check-3.log $E4W/check-4.log
  ctl field-e4-logdiff-moved-catch 1 'REVIEW +MOVED +ERROR SAML_SSO: Unable to initialize the Servlet configuration' '!NEW_ERROR' -- python3 $B/logdiff.py $E4W/logs/runtime-old-base.log $E4W/logs/runtime-new-after.log
  ctl field-e4-diff-log-allow-pass 1 'PASS\* \| log\.start\.NEW .*accepted: SAML20 4\.x' 'REVIEW 0' -- python3 $B/diff.py $E4W/before2.json $E4W/after.json --log-allow $E4W/log-allow.txt
  ctl field-e4-gen-menu-home-pass 0 '"textPresent"' '!no menu in its layout' -- cat $F/gen-e4/journeys/Administrator/login-Administrator.journey.json
  if [ -f "$LAB/e5/run3/work/impact.json" ] && [ -f "$LAB/f1/runs/e6/work/impact.json" ]; then
    # field E7-2: Producers Home calls ACT_ProducerHomePage (team detail page or teams overview); field E6-18: the SAML
    # page's snippetCallWidget1 never rendered on the old app, the guard must come from inside the snippet on both
    (cd / && python3 $B/gen_journeys.py $LAB/e5/run3/work/impact.json --out-dir $F/gen-e7 --roles-with-users Administrator > /dev/null 2>&1)
    (cd / && python3 $B/gen_journeys.py $LAB/f1/runs/e6/work/impact.json --out-dir $F/gen-e6 --roles-with-users Administrator > /dev/null 2>&1)
    ctl field-e7-gen-branches-catch 0 '"ready": ".mx-name-[A-Za-z_0-9]+, .mx-name-' 'Producer_Team_DetailPage' 'Producer_Teams_Overview' -- cat "$F/gen-e7/journeys/Administrator/menu_Producers_Home-Administrator.journey.json"
    ctl field-e6-gen-old-model-catch 0 '"ready": ".mx-name-tabControl"' '!snippetCallWidget1' -- cat $F/gen-e6/journeys/Administrator/menu_SAML_Configuration-Administrator.journey.json
  fi
else skip field-e4 "no $E4W"; fi
[ -d $LAB/f1/mig/tools/mxbuild-10.24.16 ] && ctl field-toolset-incomplete-catch 2 'REFUSED, incomplete toolset' -- zsh $B/toolcheck.sh $LAB/f1/mig/tools/mxbuild-10.24.16 mxbuild
if [ -d $E5BW/hand-journeys ]; then
  mkdir -p $F/e5b-old $F/e5b-new; cp $E5BW/hand-journeys/dash-old-9060.png $F/e5b-old/dash.png; cp $E5BW/hand-journeys/dash-new-9080.png $F/e5b-new/dash.png
  ctl field-e5b-shotdiff-catch 1 '^REVIEW +dash\.png .*empty now' -- python3 $B/shotdiff.py $F/e5b-old $F/e5b-new
  ctl field-e5b-constcheck-catch 1 'REVIEW +ADDED +TaskQueueHelpers\.ShowSystemQueuesInCharts' -- python3 $B/constcheck.py $E5BW/old-9.24.32.mda $E5BW/new-10.24.16.mda
  ctl field-e5b-constcheck-override-pass 0 "INFO +ADDED +TaskQueueHelpers\.ShowSystemQueuesInCharts .*environment sets 'true'" -- python3 $B/constcheck.py $E5BW/old-9.24.32.mda $E5BW/new-10.24.16.mda --overrides $E5BW/env-values.json
  ctl field-toolset-complete-pass 0 '!REFUSED' '!WARNING' -- zsh $B/toolcheck.sh $LAB/e5/run2/tools/mxbuild-9.24.32 mxbuild
  ctl field-e5b-localedits-layout-catch 0 'ui +CHANGED +page +TaskQueueHelpers\.MonitoringDashboard +layout Atlas_Core\.Atlas_Default ->' 'force-ui: TaskQueueHelpers' -- env UPG_MXCLI=/usr/bin/false python3 $B/localedits.py $E5BW/original.mpr --module TaskQueueHelpers
  ctl field-e5b-localedits-layout-pass 0 'UI edits \(pages, layouts\): 0' -- env UPG_MXCLI=/usr/bin/false python3 $B/localedits.py $E5BW/original.mpr --module WebActions
  ctl field-e5b-localedits-logic-catch 0 'logic +REMOVED +microflow +MendixSSO\.MendixSSO_AfterStartup' 'LOGIC edits \(documents added or deleted, contents not compared\): 4' -- env UPG_MXCLI=/usr/bin/false python3 $B/localedits.py $E5BW/original.mpr --module MendixSSO
  ctl field-e5b-localedits-logic-pass 0 'LOGIC edits \(documents added or deleted, contents not compared\): 0' -- env UPG_MXCLI=/usr/bin/false python3 $B/localedits.py $E5BW/original.mpr --module WebActions
  (cd / && python3 $B/gen_journeys.py $E5BW/impact.json --out-dir $F/gen-e5b --roles-with-users Administrator,User > $F/gen-e5b.out 2>&1)
  ctl field-e5b-gen-landing-catch 0 'landing guard container1 is also a layout widget name' -- cat $F/gen-e5b.out
  ctl field-e5b-gen-landing-pass 0 '"ready": ".mx-name-layoutGrid1"' '!container1' -- cat $F/gen-e5b/journeys/Administrator/login-Administrator.journey.json
  ctl field-e5b-gen-nomenu-catch 0 '"Teams Overview"' '!"Producers Home"' -- cat $F/gen-e5b/journeys/User/login-User.journey.json
  ctl field-e5b-gen-unreachable-catch 0 "unreachable.*Admin_Recipient_NewEdit.*Footer_View.*MessagesIntegration_Overview" "covered.*home:AdminBackend.Home_Web" -- \
    python3 -c "import json; p=json.load(open('$F/gen-e5b/plan.json')); print('unreachable', [e['id'] for e in p['unreachable']]); print('covered', [e['id'] for e in p['covered']])"
  ctl field-e5b-gen-reachable-pass 0 "todo.*page:MessageTemplate.CreateMessage_Summary" -- python3 -c "import json; print('todo', [e['id'] for e in json.load(open('$F/gen-e5b/plan.json'))['todo']])"
  ctl field-e5b-impact-shared-name-pass 0 'tree 29 -> 29|tree [0-9]+ -> [0-9]+' '!DeleteExpiredAuthRequests.*removed' '!after-startup call tree' -- python3 $B/impact_map.py $E5BW/original.mpr $LAB/e5/run2/app --md /dev/stdout --out $F/imp-e5b.json
  ctl field-e5b-gen-signout-catch 0 'Sign Out' -- cat $F/gen-e5b/journeys/Administrator/sign-out.journey.json
else skip field-e5b "no $E5BW"; fi

# --- field controls on the E6 / E7 evidence (v3.1) ---------------------------------------------------------------------------
if [ -f "$LAB/f1/runs/e6/work/db-ledger.txt" ]; then
  # E6-16: the real E6 ledger holds hand-written notes ("e6_x_smoke copy of e6_x_frozen ..."): named as such, read only
  cp $LAB/f1/runs/e6/work/db-ledger.txt $F/e6-ledger.txt
  ctl field-e6-ledger-hand-line-catch 2 'ledger line 4 of .*e6_x_smoke copy of e6_x_frozen' 'not in the form snapshot.py writes' -- python3 $B/snapshot.py --label x --out $F/e6-x.json --psql "false -d e6_x_smoke" --ledger $F/e6-ledger.txt
  ctl field-e6-ledger-own-line-pass 2 'ledger line 7 of .*e6_x_after snapshot after' '!not in the form' -- python3 $B/snapshot.py --label x --out $F/e6-x.json --psql "false -d e6_x_after" --ledger $F/e6-ledger.txt
else skip field-e6-ledger "no E6 ledger"; fi

# --- gate driver (N1-13): bin/gate.sh over stub instruments ---------------------------------------------------------------
# UPG_GATE_BIN points at a folder of stubs (fixtures/bin/gate-stub.py under every instrument's name; rc and output from
# GATE_STUB_RC_<name> / GATE_STUB_OUT_<name>), so the driver's own logic is what is judged: path checks, rc mapping,
# summary, exit code. UPG_NODE=python3 runs the stub smokewalk.js without Node.
GB=$T/gate-bin; GI=$T/gate-in; mkdir -p "$GB" "$GI/jd" "$GI/jb" "$GI/sb" "$GI/rd1" "$GI/rd2" "$GI/am"
for n in idcheck.py constcheck.py diff.py logdiff.py shotdiff.py run_journeys.py release_impact.py restcontract.py smokewalk.js smokewalk_gen.py apimock.py widgetcover.py layoutdiff.py; do
  cp "$FX/bin/gate-stub.py" "$GB/$n"
done
for n in old.mda new.mda before.json after.json old.log new.log smoke-before.json smoke-plan.json users.json release-impact.md build.log \
         allow.txt log-allow.txt shot-accept.txt; do echo x > "$GI/$n"; done
echo "BUILD SUCCEEDED" > "$GI/build.log"
# gcase LABEL [GATE_*=v ...] [gate.sh args]: every rung configured, stubs, then the summary printed; exit = gate.sh's
# (GATE_BIN_DIR=folder replaces the stub folder, E2E-15: the real apimock.py among stubs)
gcase() {
  local label=$1; shift
  ( while [ $# -gt 0 ]; do case "$1" in GATE_*=*) export "$1"; shift;; *) break;; esac; done
    export UPG_GATE_BIN=${GATE_BIN_DIR:-$GB} UPG_PYTHON=python3 UPG_NODE=python3 GATE_STUB_LOG=$GI/stub-$label.log
    bash $B/gate.sh WORK=$GI/w LABEL=$label BUILD_LOG=$GI/build.log OLD_MDA=$GI/old.mda NEW_MDA=$GI/new.mda \
      BEFORE_JSON=$GI/before.json AFTER_JSON=$GI/after.json ALLOW=$GI/allow.txt LOG_ALLOW=$GI/log-allow.txt \
      REST_BEFORE=$GI/rd1 REST_AFTER=$GI/rd2 OLD_LOG=$GI/old.log NEW_LOG=$GI/new.log SMOKE_URL=http://localhost:8080 \
      SMOKE_BEFORE=$GI/smoke-before.json SMOKE_PLAN=$GI/smoke-plan.json 'SMOKE_USER=Administrator=smoke_admin:S3cret-pw!' \
      JOURNEYS_DIR=$GI/jd JOURNEYS_BEFORE=$GI/jb USERS=$GI/users.json PORT=8080 ADMIN_PORT=8090 ADMIN_PASS=adm1n-s3cret \
      SMOKE_BEFORE_SHOTS=$GI/sb SMOKE_SHOT_ACCEPT=$GI/shot-accept.txt JOURNEY_SHOT_ACCEPT=$GI/shot-accept.txt RELEASE_IMPACT=$GI/release-impact.md APIMOCK=$GI/am "$@"
    rc=$?; [ -f "$GI/w/gate$label/gate-summary.md" ] && cat "$GI/w/gate$label/gate-summary.md"; exit $rc )
}
mkdir -p "$GI/w"
ctl gate-dry-run-pass 0 '^\[build\]' '^\[idcheck\] .*idcheck\.py' '^\[const\] .*constcheck\.py' '^\[data\] .*diff\.py' '^\[rest\] .*restcontract\.py' \
  '^\[logdiff\] .*logdiff\.py' '^\[smoke\] .*smokewalk\.js .*--user' '^\[journeys\] .*run_journeys\.py .*--compare' '^\[screens\] .*shotdiff\.py' \
  '^\[release\] .*release_impact\.py --check' '!S3cret|adm1n-s3cret' 'dry-run: nothing was run' -- gcase dry --dry-run
# T7R-12, T8R-8: SMOKE_REPEAT reaches smokewalk as --repeat N; without it no --repeat is passed
ctl gate-smoke-repeat-pass 0 '^\[smoke\] .*smokewalk\.js .*--repeat 3' -- gcase dryrep --dry-run SMOKE_REPEAT=3
ctl gate-smoke-login-path-catch 0 '^\[smoke\] .*smokewalk\.js .*--login-path /login-without-sso\.html' -- gcase dryloginp --dry-run SMOKE_LOGIN_PATH=/login-without-sso.html
ctl gate-smoke-no-login-path-pass 0 '^\[smoke\] .*smokewalk\.js' '!--login-path' -- gcase dryloginp2 --dry-run
ctl gate-smoke-no-repeat-pass 0 '^\[smoke\] .*smokewalk\.js' '!--repeat' -- gcase dry2 --dry-run
ctl gate-dry-run-writes-nothing-pass 0 'no stub log' '!gate-summary' -- sh -c "test ! -e $GI/stub-dry.log && test ! -e $GI/w/gatedry && echo 'no stub log'"
ctl gate-all-pass 0 'Overall: \*\*PASS\*\*' '\| 1 \| build \| PASS \|' '\| 4 \| data \| PASS\* \|' '\| 5 \| rest \| PASS \|' '\| 11 \| release \| PASS \|' '!FAIL \||INVALID \||\| (build|idcheck|const|data|rest|logdiff|smoke|layout|journeys|screens|release|apis|widgets) \| NOT RUN \|' \
  -- gcase pass GATE_STUB_OUT_diff='INVALID 0 | FAIL 0 | REVIEW 0 | PASS* 3 | PASS 84' WIDGETS_APP=$GI LAYOUT_OLD=$FX/layout/old LAYOUT_NEW=$FX/layout/old
# --- report words and the progress line (positive-verdict.md; PV-POS-1): the human layer over the unchanged codes ------------
# 12 rungs, all configured in gcase (rest, apis, widgets with WIDGETS_APP): owed = 12 rungs + owner sign-off = 13
ctl gate-regression-never-complete-catch 1 'Overall: \*\*FAIL\*\*' 'Progress: [0-9]+ of 13 checks closed' '1 with REGRESSIONS to fix' 'journeys: REGRESSION to fix' '!0 with REGRESSIONS' '!complete' \
  -- gcase regr GATE_STUB_RC_run_journeys=1 GATE_STUB_OUT_run_journeys='journeys: 99 PASS, 2 REGRESSION' WIDGETS_APP=$GI
ctl gate-review-only-decision-pass 1 'needs a decision' '0 with REGRESSIONS to fix, 1 need a decision' '!REGRESSION to fix: .*screens' \
  -- gcase rev GATE_STUB_RC_shotdiff=1 GATE_STUB_OUT_shotdiff='screens: 140 PASS, 0 PASS*, 3 REVIEW, 0 INVALID' WIDGETS_APP=$GI
ctl gate-review-with-fail-is-regression-catch 1 'screens: REGRESSION to fix' '1 with REGRESSIONS to fix, 0 need a decision' \
  -- gcase revf GATE_STUB_RC_shotdiff=1 GATE_STUB_OUT_shotdiff='screens: 140 PASS, 1 FAIL, 3 REVIEW, 0 INVALID' WIDGETS_APP=$GI
ctl gate-unparsable-fail-is-regression-catch 1 'REGRESSION to fix: .*logdiff' '1 with REGRESSIONS to fix' -- gcase unp GATE_STUB_RC_logdiff=1 WIDGETS_APP=$GI
# Run-6 shape: 0 FAIL, INVALID only skipped, per-item FAIL lines that failed on the OLD app too (BASELINE DEFECT), screens waiting
# on a person. Not a regression: "needs a decision", Progress and GRADE count it the same way. A real regression beside the same
# baseline lines still reads "REGRESSION to fix".
R6OUT=$'journeys: 119 PASS, 0 FAIL, 142 INVALID, 32 PASS* (baseline defect)\n  FAIL    act-Mod.Page.actionButton1 FAIL open Mod.Page: never appeared [BASELINE DEFECT (before FAIL): no evidence]\nscreens: 1 PASS, 0 PASS*, 17 REVIEW, 0 INVALID'
ctl gate-run6-shape-not-regression-pass 1 'journeys: needs a decision' '0 with REGRESSIONS to fix, 1 need a decision' '!REGRESSION to fix: .*journeys' '!open regression [1-9]' 'waiting on a person 1' \
  -- gcase r6 GATE_STUB_RC_run_journeys=1 "GATE_STUB_OUT_run_journeys=$R6OUT" WIDGETS_APP=$GI
ctl gate-run6-shape-plus-real-regression-catch 1 'journeys: REGRESSION to fix' '1 with REGRESSIONS to fix' 'open regression 1' \
  -- gcase r6r GATE_STUB_RC_run_journeys=1 "GATE_STUB_OUT_run_journeys=$R6OUT"$'\n  FAIL    act-Mod.Page.actionButton2 FAIL open Mod.Page: never appeared' WIDGETS_APP=$GI
# bin/cloud/resume.sh after a container restart: relaunch only unfinished run folders (fake folders, no docker), never --from
RS=$T/resume; mkdir -p $RS
for n in fin stop live; do mkdir -p $RS/$n/work/state; done; mkdir -p $RS/half/work/state $RS/bare
for n in fin stop live half; do printf '#!/bin/bash\necho "launched $*" >> "%s/%s/launches"\n' "$RS" "$n" > $RS/$n/run-pipeline.sh; done
touch $RS/fin/work/state/gate.done; printf 'journeys running\nexit 12\n' > $RS/stop/pipeline.log
printf 'build running\n' > $RS/half/pipeline.log; touch $RS/half/work/state/build.done
mkdir -p $RS/nodocker; for n in docker dockerd; do printf "#!/bin/sh\nexit 1\n" > $RS/nodocker/$n; chmod +x $RS/nodocker/$n; done
resume() { UPG_RESUME_NO_DOCKER=1 UPG_RESUME_FOREGROUND=1 bash $B/cloud/resume.sh "$@"; }
ctl resume-skips-finished-pass 0 'SKIP .*/fin: finished' 'SKIP .*/stop: stopped on its own' 'SKIP .*/bare: no run-pipeline' -- resume $RS/fin $RS/stop $RS/bare
ctl resume-no-launch-of-finished-pass 0 'no launches' -- sh -c "cd $RS && ls fin/launches stop/launches bare/launches 2>/dev/null; echo 'no launches'; ! ls fin/launches stop/launches >/dev/null 2>&1"
ctl resume-relaunches-unfinished-catch 0 'RESUME .*/half' -- resume $RS/fin $RS/half
ctl resume-launch-appends-log-no-from-catch 0 '^launched $' '^exit 0$' '!--from' -- sh -c "cat $RS/half/launches $RS/half/pipeline.log; test -f $RS/half/work/state/build.done"
ctl resume-docker-never-up-catch 3 'docker did not start' -- env UPG_RESUME_DOCKER_WAIT=1 PATH=$RS/nodocker:$PATH bash $B/cloud/resume.sh $RS/half
# The Progress figure is never 100% (sign-off is never closed by a machine). The Grade line (bin/grade.py, rungs only) may say 100%,
# so this checks the Progress line, not the whole output (night/main merge: both metrics now print).
ctl gate-all-green-never-100-pass 0 'Progress: 12 of 13 checks closed \(92%\)' 'owner sign-off pending' '!Progress: .*\(100%\)' \
  -- gcase pass2 GATE_STUB_OUT_diff='INVALID 0 | FAIL 0 | REVIEW 0 | PASS* 3 | PASS 84' WIDGETS_APP=$GI
ctl gate-ran-every-rung-pass 0 'idcheck' 'constcheck' 'diff' 'logdiff' 'smokewalk' 'run_journeys' 'shotdiff' 'release_impact' 'restcontract' 'apimock' -- cut -d' ' -f1 "$GI/stub-pass.log"
ctl gate-invalid-rc2-catch 2 'Overall: \*\*INVALID\*\*' '\| data \| INVALID \| 2 \|' 'data +INVALID +rc=2' '!Overall: \*\*PASS' -- gcase rc2 GATE_STUB_RC_diff=2
ctl gate-journeys-rc2-catch 2 '\| journeys \| INVALID \| 2 \|' 'journeys: 3 PASS, 0 FAIL, 3 INVALID' '!Overall: \*\*PASS' \
  -- gcase jrc2 GATE_STUB_RC_run_journeys=2 GATE_STUB_OUT_run_journeys='journeys: 3 PASS, 0 FAIL, 3 INVALID'
ctl gate-fail-wins-catch 1 'Overall: \*\*FAIL\*\*' '\| logdiff \| FAIL \| 1 \|' '\| data \| INVALID \|' -- gcase fail GATE_STUB_RC_logdiff=1 GATE_STUB_RC_diff=2
ctl gate-release-rc1-invalid-catch 2 '\| release \| INVALID \| 1 \|' -- gcase rel GATE_STUB_RC_release_impact=1
ctl gate-timeout-invalid-catch 2 '\| smoke \| INVALID \| 124 \|' 'timed out' -- gcase tmo GATE_TIMEOUT=1 GATE_STUB_SLEEP_smokewalk=5
# C6: no `timeout` on the host (macOS): the bash watchdog still ends a hung rung as INVALID 124, says so, and a quick rung passes
ctl gate-timeout-watchdog-invalid-catch 2 '\| smoke \| INVALID \| 124 \|' 'timed out' 'WARN no timeout or gtimeout' -- gcase tmow GATE_NO_TIMEOUT_BIN=1 GATE_TIMEOUT=1 GATE_STUB_SLEEP_smokewalk=5
# PV-12: the watchdog warning is printed once per gate run, not once per rung
warncount() { gcase "$@" 2>&1 | grep -c 'WARN no timeout or gtimeout'; }
ctl gate-watchdog-warn-once-pass 0 '^1$' -- warncount wdw GATE_NO_TIMEOUT_BIN=1
ctl gate-timeout-watchdog-kills-catch 2 '\| smoke \| INVALID \| 124 \|' -- gcase tmok GATE_NO_TIMEOUT_BIN=1 GATE_TIMEOUT=1 GATE_STUB_SLEEP_smokewalk=5 GATE_STUB_DONE_smokewalk=$GI/done-tmok
# the watchdog must KILL the hung rung, not just report rc 124 after it ended by itself: the stub writes this file only when it survives its pause
ctl gate-timeout-watchdog-killed-pass 0 'not survived' -- sh -c "test ! -e $GI/done-tmok && echo 'not survived'"
ctl gate-timeout-watchdog-pass 0 'Overall: \*\*PASS' '!timed out' '!INVALID \|' -- gcase tmop GATE_NO_TIMEOUT_BIN=1 GATE_TIMEOUT=30
# U11: a literal $G in a value is the gate folder (work/gate<label>), not a path under the config folder; a plain relative path still is
mkdir -p $GI/w/gateu11; : > $GI/w/gateu11/after2.json; mkdir -p $GI/u11; : > $GI/u11/rel.json
printf 'AFTER_JSON=$G/after2.json\n' > $GI/u11/gate.conf; printf 'AFTER_JSON=rel.json\n' > $GI/u11/rel.conf
ctl gate-g-var-arg-catch 0 "^\[data\] .*diff\.py .* $GI/w/gateu11/after2\.json" '!\$G' -- gcase u11 --dry-run 'AFTER_JSON=$G/after2.json'
ctl gate-g-var-braced-catch 0 "^\[data\] .*diff\.py .* $GI/w/gateu11/after2\.json" -- gcase u11 --dry-run 'AFTER_JSON=${G}/after2.json'
ctl gate-g-var-config-catch 0 "^\[data\] .*diff\.py .* $GI/w/gateu11/after2\.json" -- bash -c "cd $GI && UPG_PYTHON=python3 UPG_NODE=python3 UPG_GATE_BIN=$GB bash $B/gate.sh --dry-run --config $GI/u11/gate.conf WORK=$GI/w LABEL=u11 BEFORE_JSON=$GI/before.json" 
ctl gate-relative-value-config-pass 0 "^\[data\] .*diff\.py .* $GI/u11/rel\.json" -- bash -c "cd $GI && UPG_PYTHON=python3 UPG_NODE=python3 UPG_GATE_BIN=$GB bash $B/gate.sh --dry-run --config $GI/u11/rel.conf WORK=$GI/w LABEL=u11 BEFORE_JSON=$GI/before.json"
ctl gate-missing-input-catch 2 "rung journeys: JOURNEYS_DIR: no such folder: $GI/no-such-journeys" 'INPUT ERROR, nothing was run' 'Overall: \*\*INVALID' '\| journeys \| NOT RUN \| - \| not run: an input check failed' \
  -- gcase miss JOURNEYS_DIR=$GI/no-such-journeys
ctl gate-missing-input-ran-nothing-pass 0 'no stub log' -- sh -c "test ! -e $GI/stub-miss.log && echo 'no stub log'"
ctl gate-missing-file-dry-catch 2 "rung data: AFTER_JSON: no such file: $GI/no-after.json" '!\[data\]' -- gcase missd --dry-run AFTER_JSON=$GI/no-after.json
ctl gate-partial-config-catch 2 'rung smoke: SMOKE_BEFORE is not set' 'rung smoke: neither SMOKE_PLAN nor SMOKE_APP_DIR' -- bash $B/gate.sh WORK=$GI/w LABEL=part SMOKE_URL=http://localhost:8080 --dry-run
ctl gate-unknown-key-catch 2 "unknown key 'JOURNEYS_FOLDER'" -- bash $B/gate.sh JOURNEYS_FOLDER=x --dry-run
# one accept file per rung (gate.md): the old shared key is refused, not silently applied to both
ctl gate-old-shot-accept-key-catch 2 "unknown key 'SHOT_ACCEPT'" -- bash $B/gate.sh SHOT_ACCEPT=x --dry-run
# "BUILD SUCCEEDED" alone is not a clean build: an "ERROR at" line in the same log fails the rung
printf 'BUILD SUCCEEDED\nERROR at Module.Page: x\n' > "$GI/build-err.log"
ctl gate-build-error-lines-catch 1 '\| 1 \| build \| FAIL \|' 'Overall: \*\*FAIL' -- gcase berr BUILD_LOG=$GI/build-err.log
ctl gate-not-run-catch 2 'Overall: \*\*INVALID' '\| 9 \| journeys \| NOT RUN \| - \| skipped on request: no browser here' '\| 7 \| smoke \| NOT RUN \| - \| not selected' \
  -- gcase notrun --only build,idcheck,const,data,rest,logdiff,journeys,screens,release --skip journeys='no browser here'
ctl gate-not-configured-catch 2 '\| 1 \| build \| NOT RUN \| - \| not configured' '\| 4 \| data \| PASS \|' 'Overall: \*\*INVALID' \
  -- env UPG_GATE_BIN=$GB UPG_PYTHON=python3 bash -c "bash $B/gate.sh WORK=$GI/w LABEL=nc BEFORE_JSON=$GI/before.json AFTER_JSON=$GI/after.json; rc=\$?; cat $GI/w/gatenc/gate-summary.md; exit \$rc"
ctl gate-rest-optional-pass 0 'Overall: \*\*PASS' '\| 5 \| rest \| NOT RUN \| - \| not configured.*\(optional rung\)' -- gcase norest REST_BEFORE= REST_AFTER=
ctl gate-pre-fail-catch 2 '\| data \| INVALID \| 3 \| PRE_data failed rc=3' -- gcase pre 'PRE_data=exit 3'
ctl gate-pre-produces-pass 0 'Overall: \*\*PASS' -- gcase prep AFTER_JSON=$GI/produced.json "PRE_data=echo x > $GI/produced.json"
ctl gate-pre-absent-output-catch 2 '\| data \| INVALID \| 2 \| input missing after PRE_data: AFTER_JSON: no such file' -- gcase prem AFTER_JSON=$GI/never.json 'PRE_data=true'
ctl gate-rejudge-dry-pass 0 '^\[journeys\] .*--rejudge' '!\[journeys\] .*--admin-pass' -- gcase rj --dry-run JOURNEYS_REJUDGE=1
ctl gate-secrets-masked-pass 0 '\[journeys\] .*--admin-pass \*\*\*' '\[smoke\] .*Administrator=smoke_admin:\*\*\*' '!adm1n-s3cret|S3cret' -- gcase mk --dry-run
# E2E-9: JOURNEY_PSQL becomes run_journeys --psql (its password masked), JOURNEY_EFFECT_ACCEPT --effect-accept
ctl gate-journey-psql-dry-pass 0 "^\\[journeys\\] .*--psql PGPASSWORD=\\*\\*\\* psql.*opc_after_x --compare .*--effect-accept $GI/shot-accept.txt" '!pg-s3cret' -- gcase pq --dry-run 'JOURNEY_PSQL=PGPASSWORD=pg-s3cret psql -h db -d opc_after_x' JOURNEY_EFFECT_ACCEPT=$GI/shot-accept.txt
ctl gate-journey-effect-accept-missing-catch 2 'JOURNEY_EFFECT_ACCEPT: no such file' -- gcase pq2 --dry-run JOURNEY_EFFECT_ACCEPT=$GI/nope.txt
# E2E-11: ACTIONS -> --actions (the coverage denominator), ACTIONS_WAIVE -> --no-actions, JOURNEY_EVIDENCE -> --baseline-evidence
echo '{"actions": []}' > $GI/actions.json; echo '# none' > $GI/evidence.txt
ctl gate-journey-actions-dry-pass 0 "^\\[journeys\\] .*--compare .*--actions $GI/actions\\.json --baseline-evidence $GI/evidence\\.txt" '!--no-actions' \
  -- gcase ac --dry-run ACTIONS=$GI/actions.json JOURNEY_EVIDENCE=$GI/evidence.txt
ctl gate-journey-actions-waive-dry-pass 0 '^\[journeys\] .*--no-actions no\\ model\\ here' '!--actions ' -- gcase acw --dry-run 'ACTIONS_WAIVE=no model here'
ctl gate-journey-actions-missing-catch 2 'ACTIONS: no such file' -- gcase acm --dry-run ACTIONS=$GI/nope-actions.json
ctl gate-journey-evidence-missing-catch 2 'JOURNEY_EVIDENCE: no such file' -- gcase evm --dry-run JOURNEY_EVIDENCE=$GI/nope-ev.txt
JOUTC=$'journeys: 4 PASS, 1 FAIL, 0 INVALID\nactions 6 found · 4 generated (2 todo: combobox 1, no journey 1) · 3 pass on baseline (1 defect) · 3 pass on new · 0 regression · coverage 3/6 (50%)\ndefects: 1 failing on the baseline: 1 with evidence (OLD-APP 1) = 1 PASS*, 0 without (INVALID)'
ctl gate-journey-coverage-passstar-pass 0 '\| 9 \| journeys \| PASS\* \| 0 \| journeys: 4 PASS, 1 FAIL, 0 INVALID;actions 6 found · 4 generated' -- gcase jcov GATE_STUB_OUT_run_journeys="$JOUTC"
JOUTI=$'journeys: 5 PASS, 0 FAIL, 0 INVALID\nactions 6 found · 4 generated (2 todo: combobox 1, no journey 1) · 4 pass on baseline (0 defect) · 4 pass on new · 0 regression · coverage 4/6 (66%)\n  coverage INVALID: journey set changed since the baseline (sha256 aaaaaaaaaaaa then, bbbbbbbbbbbb now): run before-picked again on this set\nverdict: INVALID only (exit 3): no REGRESSION, no open REVIEW; 0 journeys INVALID, 0 SCREEN INVALID, 0 failing on the baseline, 0 EFFECT INVALID, 1 coverage rules broken'
ctl gate-journey-coverage-rc3-catch 2 '\| 9 \| journeys \| INVALID \| 3 \| INVALID only \(exit 3\).*1 coverage rules broken; coverage INVALID: journey set changed since the baseline .*; actions 6 found · ' \
  '!\| journeys \| (FAIL|PASS)' -- gcase jcovi GATE_STUB_RC_run_journeys=3 GATE_STUB_OUT_run_journeys="$JOUTI"
# Field run: the summary line counts FAIL, but when every per-journey FAIL line is a tagged BASELINE DEFECT the rung needs
# a decision, not a fix; one untagged FAIL line keeps it a regression
JOUTB=$'journeys: 4 PASS, 1 FAIL, 0 INVALID\n  FAIL    j3-User  x [BASELINE DEFECT (before FAIL): no evidence]'
JOUTU=$'journeys: 3 PASS, 2 FAIL, 0 INVALID\n  FAIL    j3-User  x [BASELINE DEFECT (before FAIL): no evidence]\n  FAIL    j4-User  y'
ctl gate-journey-baseline-only-decision-pass 1 'journeys: needs a decision' '!journeys: REGRESSION to fix' -- gcase jbd GATE_STUB_RC_run_journeys=1 GATE_STUB_OUT_run_journeys="$JOUTB"
ctl gate-journey-untagged-fail-regression-catch 1 'journeys: REGRESSION to fix' -- gcase jbu GATE_STUB_RC_run_journeys=1 GATE_STUB_OUT_run_journeys="$JOUTU"
# the config file: relative paths resolve against the config's own folder, so a worker's cwd cannot break them
printf 'WORK=w\nLABEL=cf\nBEFORE_JSON=before.json\nAFTER_JSON=after.json\n' > "$GI/gate.conf"
ctl gate-config-relative-pass 0 "\[data\] .*diff\.py $GI/before\.json $GI/after\.json" -- sh -c "cd / && UPG_GATE_BIN=$GB UPG_PYTHON=python3 bash $B/gate.sh --config $GI/gate.conf --dry-run"
printf 'BEFORE_JSON=before.json\nAFTER_JSON=gone/after.json\n' > "$GI/bad.conf"
ctl gate-config-relative-catch 2 "AFTER_JSON: no such file: $GI/gone/after\.json" -- sh -c "cd / && bash $B/gate.sh --config $GI/bad.conf --dry-run"
# N1R2-8 / T2R3-11: run_journeys exit 3 (INVALID only) is INVALID with its advice as the line, never FAIL
JOUT3=$'journeys: 3 PASS, 1 FAIL, 0 INVALID\nscreens: 1 PASS, 0 PASS*, 0 REVIEW, 0 INVALID\nverdict: INVALID only (exit 3): no REGRESSION, no open REVIEW; 0 journeys INVALID, 0 SCREEN INVALID, 1 failing on the baseline\n  baseline: howto-User fail on the OLD app too: drop or fix these journeys (they say nothing about the upgrade), then run before-picked again on its own fresh copy'
ctl gate-journeys-rc3-invalid-catch 2 '\| 9 \| journeys \| INVALID \| 3 \| INVALID only \(exit 3\).*; baseline: howto-User .*drop or fix' 'Overall: \*\*INVALID\*\*' '!Overall: \*\*FAIL|\| journeys \| FAIL' \
  -- gcase jrc3 GATE_STUB_RC_run_journeys=3 "GATE_STUB_OUT_run_journeys=$JOUT3"
# N1R2-9a / T2R3-10a: a key produced by an earlier rung's PRE counts for a later rung; a later rung's PRE does not
ctl gate-pre-earlier-rung-produces-pass 0 'Overall: \*\*PASS' '\| 6 \| logdiff \| PASS \|' -- gcase prel NEW_LOG=$GI/w/prel-new.log "PRE_data=echo x > $GI/w/prel-new.log"
ctl gate-pre-later-rung-produces-catch 2 "rung logdiff: NEW_LOG: no such file: $GI/w/prlt-new.log" 'INPUT ERROR' -- gcase prlt NEW_LOG=$GI/w/prlt-new.log "PRE_smoke=echo x > $GI/w/prlt-new.log"
# N1R2-9b: PRE commands see G, WORK, RUN and every key; a PRE writing $G/after.json feeds the data rung
ctl gate-pre-env-produces-pass 0 '\| 4 \| data \| PASS \|' -- gcase penv RUN=r7 AFTER_JSON=$GI/w/gatepenv/after.json 'PRE_data=echo "G=$G WORK=$WORK RUN=$RUN AFTER=$AFTER_JSON USERS=$USERS" > "$G/after.json"'
ctl gate-pre-env-pass 0 "^G=$GI/w/gatepenv WORK=$GI/w RUN=r7 AFTER=$GI/w/gatepenv/after.json USERS=$GI/users.json\$" -- cat $GI/w/gatepenv/after.json
# B4T2-12: the CONST_OVERRIDES key is a path; gate exports it to PRE commands and runapp.py reads the path (it read it as
# JSON: "Expecting value", every PRE rung rc 1). An unset key no longer clears the caller's own JSON CONST_OVERRIDES.
printf '#!/bin/bash\npython3 -c "import sys; sys.path.insert(0, \\"%s\\"); import runapp; print(runapp.const_overrides())" > "$1" 2>&1\n' "$B" > $T/coprobe.sh
gco() { local l=$1; shift; gcase $l "PRE_data=bash $T/coprobe.sh $GI/w/$l.txt" "$@" > /dev/null 2>&1; cat $GI/w/$l.txt; }
gcoenv() ( export CONST_OVERRIDES='{"Mod.Url": "from-env"}'; gco "$@" )
ctl gate-const-path-pre-pass 0 "^\{'Mod.Url': 'http://mock:8080'\}$" -- gco cop CONST_OVERRIDES=$CO/ov.json
ctl gate-const-env-kept-pass 0 "^\{'Mod.Url': 'from-env'\}$" -- gcoenv coe
ctl gate-const-key-wins-pass 0 "^\{'Mod.Url': 'http://mock:8080'\}$" -- gcoenv cok CONST_OVERRIDES=$CO/ov.json
ctl gate-const-none-pass 0 '^\{\}$' -- gco con
ctl gate-help-full-header-pass 0 '^#   logdiff    OLD_LOG NEW_LOG' 'B4T2-12' 'GATE_TIMEOUT \(seconds per instrument' '!^set -u' -- bash $B/gate.sh -h
# T2R3-10e: {RUN} in any value is the invocation id (given, or the UTC time)
ctl gate-run-placeholder-pass 0 '^\[data\] PRE: createdb -T x_frozen x_after_r42$' -- gcase rph --dry-run RUN=r42 'PRE_data=createdb -T x_frozen x_after_{RUN}'
ctl gate-run-placeholder-default-pass 0 '^\[data\] PRE: createdb x_after_[0-9]{14}$' '!\{RUN\}' -- gcase rpd --dry-run 'PRE_data=createdb x_after_{RUN}'
ctl gate-run-bad-id-catch 2 'RUN=a-b: letters, digits and _ only' -- bash $B/gate.sh RUN=a-b --dry-run
# T2R3-10c / N1R2-9: --only merges into the existing gate-summary.md: carried rows keep their verdict (a FAIL stays FAIL)
ctl gate-only-merge-first-run 1 '\| 6 \| logdiff \| FAIL \| 1 \|' -- gcase mrg GATE_STUB_RC_logdiff=1 WIDGETS_APP=$GI LAYOUT_OLD=$FX/layout/old LAYOUT_NEW=$FX/layout/old
ctl gate-only-merge-catch 1 'Overall: \*\*FAIL\*\*' '\| 6 \| logdiff \| FAIL \| 1 \| \(earlier run [0-9T:-]+Z\) ' '\| 9 \| journeys \| INVALID \| 3 \|' '\| 4 \| data \| PASS \| 0 \| \(earlier run ' 'Merged \(--only journeys\)' '!not selected' \
  -- gcase mrg GATE_STUB_RC_run_journeys=3 --only journeys
ctl gate-only-merge-carry-invalid-catch 2 'Overall: \*\*INVALID\*\*' '\| 6 \| logdiff \| PASS \| 0 \| logdiff: stub ok \|$' '\| 9 \| journeys \| INVALID \| 3 \|' -- gcase mrg --only logdiff
ctl gate-only-merge-again-pass 0 'Overall: \*\*PASS\*\*' '\| 9 \| journeys \| PASS \| 0 \|' '\| 6 \| logdiff \| PASS \| 0 \| \(earlier run [0-9T:-]+Z\) logdiff: stub ok \|' '!\(earlier run [^)]*\) \(earlier run' -- gcase mrg --only journeys
ctl gate-only-no-summary-pass 2 '\| 4 \| data \| NOT RUN \| - \| not selected' '!Merged' -- gcase mrgnew --only journeys
# RT-11: --seed-from copies an earlier gate's summary into a new GATE_DIR (a remedy trial's label), so --only merges
ctl gate-seed-from-pass 0 'gate: seeded ' '\| 6 \| logdiff \| PASS \| 0 \| \(earlier run ' '\| 9 \| journeys \| PASS \| 0 \|' '!\| (build|idcheck|const|data|rest|logdiff|smoke|layout|journeys|screens|release|apis|widgets) \| NOT RUN \|' 'Overall: \*\*PASS' -- gcase seed1 --only journeys --seed-from $GI/w/gatemrg
ctl gate-seed-from-no-only-catch 2 'seed-from needs --only' -- gcase seed2 --seed-from $GI/w/gatemrg
ctl gate-seed-from-missing-catch 2 'seed-from .*: no gate-summary\.md there' -- gcase seed3 --only journeys --seed-from $GI/nonexistent
ctl gate-timeout-hint-catch 2 '\| smoke \| INVALID \| 124 \| timed out after 1s \(raise GATE_TIMEOUT\)' 'raise GATE_TIMEOUT \(smoke: steps x roles x repeat\)' -- gcase tmoh GATE_TIMEOUT=1 GATE_STUB_SLEEP_smokewalk=5

# --- external APIs (E2E-13, E2E-14): bin/apimock.py and its gate wiring -------------------------------------------------
# Goldens captured from the public Marketplace PFEP 1.4.1 (MendixSSO roles call + the Teamcenter connector's SendService)
# and Kanban 1.0.0 (a consumed OData service + an Opcenter REST call whose URL comes from data) by lib/capture_units.py,
# never hand-written. The stand-in listens on 127.0.0.1 only (port 0: the OS picks a free one); nothing real is called.
# E2E-16: calls that share one route and template are told apart by what the request holds (apimock.discriminate): the
# fixed pairs of a POST body template, the literal names of a {N} path segment, the query names. Synthetic inventory.
cat > "$T/am-pick.py" <<'EOF'
import sys, json
sys.path.insert(0, sys.argv[1]); import apimock
def ep(i, m, tpl, params=(), body=None):
    return {"id": i, "kind": "rest", "method": m, "template": tpl, "params": list(params), "routes": [("const", "M.Host")],
            "body": {}, "status": "MOCKED", "system": "", "seg_hints": apimock.segment_hints(tpl, list(params)),
            "req_fixed": apimock.fixed_pairs(body)}
eps = [ep("rest:A.Sign", "POST", "/Api/Execute", body='{{"api_name": "Sign", "x": "{1}"}}'),
       ep("rest:A.Zone", "POST", "/Api/Execute", body='{{"api_name": "TimeZone"}}'),
       ep("rest:A.Co", "GET", "/OData/{2}?filter={3}&orderby={4}", ["h", "if $a then 'GetDoneCo' else 'GetActiveCo'"]),
       ep("rest:A.Mission", "GET", "/OData/{2}?filter={3}&orderby={4}", ["h", "'GetMissions'"]),
       ep("rest:A.MissionPaged", "GET", "/OData/{2}?filter={3}&orderby={4}&top={5}&skip={6}", ["h", "'GetMissions'"])]
st = apimock.Stand({"endpoints": eps, "metadata": {}}, "/tmp", None)
def pick(m, path, q="", body=None): return st.pick(m, "/c/M.Host" + path, body, q)[0]["id"]
print(pick("POST", "/Api/Execute", body='{"api_name": "TimeZone"}'))
print(pick("POST", "/Api/Execute", body='{"api_name": "Sign"}'))
print(pick("GET", "/OData/GetActiveCo", "filter=a&orderby=b"))
print(pick("GET", "/OData/GetMissions", "filter=a&orderby=b"))
print(pick("GET", "/OData/GetMissions", "filter=a&orderby=b&top=1&skip=0"))
EOF
ctl apimock-pick-body-segment-query 0 '^rest:A\.Zone$' '^rest:A\.Sign$' '^rest:A\.Co$' '^rest:A\.Mission$' '^rest:A\.MissionPaged$' -- python3 -I "$T/am-pick.py" "$B"
AM=$T/am; mkdir -p "$AM"
cat > "$AM/fetch.py" <<'EOF'
# fetch.py STATE METHOD PATH [MODEL MAPPING]: one request to the stand-in (no proxy), then (optionally) every JsonPath of
# the import mapping must occur in the body (apimock.shape_paths), so "a body of the mapped shape" is checked, not assumed
import json, sys, urllib.request
sys.path.insert(0, sys.argv[1]); import apimock, mprmodel
st, meth, path = sys.argv[2:5]
base = open(f"{st}/ready").read().strip()
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
try:
    r = op.open(urllib.request.Request(base + path, method=meth, data=b"{}" if meth == "POST" else None), timeout=10); code, body = r.status, r.read()
except urllib.error.HTTPError as e:
    code, body = e.code, e.read()
print(f"status {code}"); print("body " + body.decode()[:200])
if len(sys.argv) > 6:
    m = mprmodel.Model.load(sys.argv[5])
    want = {n["JsonPath"] for n in apimock.nodes(m.docs[sys.argv[6]].data.get("Elements") or []) if isinstance(n.get("JsonPath"), str) and n["JsonPath"]}
    miss = want - apimock.shape_paths(json.loads(body))
    print(f"shape: {len(want) - len(miss)} of {len(want)} mapped paths in the body" + (f"; missing {sorted(miss)}" if miss else ""))
    sys.exit(1 if miss or not want else 0)
EOF
if python3 -c 'import bson' 2>/dev/null; then
  for g in pfep-sso-tc kanban-odata-opc; do python3 "$here/lib/capture_units.py" build "$FX/apimock/$g.json" "$T/m/$g" > /dev/null; done
  PF=$T/m/pfep-sso-tc/App.mpr; KB=$T/m/kanban-odata-opc/App.mpr
  # inventory: a constant-routed REST call is MOCKED, the Teamcenter connector EXCLUDED by name, the coverage line exact
  ctl apimock-inventory-pass 0 '^MOCKED +rest:MendixSSO\.RetrieveUserRoles +GET /api/approles/v1/environment/\{2\}/user/\{3\} +via constant MendixSSO\.RolesLocation +\[mapping MendixSSO\.AppRolesResponse' \
    '^EXCLUDED \(Teamcenter\) +rest:TcConnector\.SendService .*matched TcConnector\*' '^apis 2 found · mocked 1 · excluded 1 \(Teamcenter\) · unknown 0$' -- python3 $B/apimock.py inventory $PF --exclude Teamcenter
  # catch: a location read from data is UNKNOWN (exit 3, INVALID) with the /a/ seed advice, never MOCKED
  ctl apimock-unknown-invalid-catch 3 '^UNKNOWN +rest:OpcenterConnector\.ExecuteOpcenterQuery_Custom .*via data EXFN_Authentication\.ClientConfiguration\.OpcenterEXFNUrl' \
    '^MOCKED +odata:EmployeeManagement\.ODATA_EmployeeManagement .*via constant EmployeeManagement\.ODATA_EmployeeManagement_Location' '^apis 2 found · mocked 1 · excluded 0 · unknown 1$' -- python3 $B/apimock.py inventory $KB
  # catch: without --exclude the Teamcenter call is not quietly excluded: UNKNOWN, exit 3
  ctl apimock-no-exclude-catch 3 '^UNKNOWN +rest:TcConnector\.SendService' '!EXCLUDED' '· unknown 1$' -- python3 $B/apimock.py inventory $PF
  # --classify needs a reason; with one, the line classifies (the reason is printed)
  echo 'rest:OpcenterConnector.* MOCKED' > "$AM/cls-noreason.txt"
  ctl apimock-classify-reason-catch 2 'reason' -- python3 $B/apimock.py inventory $KB --classify "$AM/cls-noreason.txt"
  echo 'rest:OpcenterConnector.* MOCKED # control: the seed data points ClientConfiguration.OpcenterEXFNUrl at /a/' > "$AM/cls.txt"
  ctl apimock-classify-pass 0 '^MOCKED +rest:OpcenterConnector\.ExecuteOpcenterQuery_Custom .*control: the seed data' '^apis 2 found · mocked 2 · excluded 0 · unknown 0$' -- python3 $B/apimock.py inventory $KB --classify "$AM/cls.txt"
  # B4T2-6 / B4N1-9: an add-on module (modules/*.mxmodule, a zip whose project.mpr is ONE bson document) is one UNKNOWN
  # endpoint naming its URL constants and URL attributes, so "unknown 0" is never claimed beside an add-on. Golden:
  # fixtures/apimock/addon-exfn-auth.json, verbatim nodes of the public Opcenter EX Starter Kit's EXFN_Authentication.
  cat > "$AM/mkxm.py" <<'EOF'
# mkxm.py GOLDEN OUT.mxmodule: the golden's nodes packed the way Studio Pro packs an add-on (package.xml + bson project.mpr)
import bson, sys, zipfile
from bson import json_util
g = json_util.loads(open(sys.argv[1]).read())
doc = {"_ProductVersion": g["_ProductVersion"], "Contents": {"$Type": "Projects$Project", "Modules": [2, {
    "$Type": "Projects$ModuleImpl", "Name": g["module"], "Documents": [2] + g["nodes"]}]}}
with zipfile.ZipFile(sys.argv[2], "w") as z:
    z.writestr("package.xml", f'<package><modelerProject><module name="{g["module"]}" /><projectFile path="project.mpr" /></modelerProject></package>')
    z.writestr("project.mpr", bson.encode(doc))
EOF
  rm -rf "$AM/pfa"; cp -r "$T/m/pfep-sso-tc" "$AM/pfa"; mkdir -p "$AM/pfa/modules"; PFA=$AM/pfa/App.mpr
  python3 "$AM/mkxm.py" "$FX/apimock/addon-exfn-auth.json" "$AM/pfa/modules/EXFN_Authentication.mxmodule"
  ctl apimock-addon-unknown-catch 3 '^UNKNOWN +addon:EXFN_Authentication .*via constant EXFN_Authentication\.APPBaseUrl, constant EXFN_Authentication\.UMCBaseUrl' \
    'URL-named attributes it reads: EXFN_Authentication\.ClientConfiguration\.OpcenterEXFNUrl' '^apis 3 found · mocked 1 · excluded 1 \(Teamcenter\) · unknown 1$' '!ClientId' '!unknown 0' \
    -- python3 $B/apimock.py inventory $PFA --exclude Teamcenter
  rm -rf "$AM/pfb"; cp -r "$AM/pfa" "$AM/pfb"; echo notazip > "$AM/pfb/modules/Broken.mxmodule"; PFB=$AM/pfb/App.mpr
  ctl apimock-addon-unreadable-catch 3 '^UNKNOWN +addon:Broken .*not readable as a zip' '· unknown 2$' -- python3 $B/apimock.py inventory $PFB --exclude Teamcenter
  # MOCKED on an endpoint the stand-in has no route to (a location a protected add-on builds from data) stays UNKNOWN
  echo 'addon:Broken MOCKED # control: claimed stood in' > "$AM/cls-noroute.txt"
  ctl apimock-classify-mocked-no-route-catch 3 '^UNKNOWN +addon:Broken .*classified MOCKED \(addon:Broken\) but the stand-in has no route to it' '!^MOCKED +addon:Broken' \
    -- python3 $B/apimock.py inventory $PFB --exclude Teamcenter --classify "$AM/cls-noroute.txt"
  # a LOCATION line names where the URL comes from (const: overridden by serve, data: the /a/ URL to seed); then MOCKED holds
  printf '%s\n' 'addon:EXFN_Authentication LOCATION const:EXFN_Authentication.APPBaseUrl # control: the add-on reads APPBaseUrl' \
    'addon:EXFN_Authentication MOCKED # control: the stand-in answers its calls' > "$AM/cls-loc.txt"
  ctl apimock-classify-location-pass 0 '^MOCKED +addon:EXFN_Authentication .*via constant EXFN_Authentication\.APPBaseUrl' 'location constant EXFN_Authentication\.APPBaseUrl declared' '· unknown 0$' \
    -- python3 $B/apimock.py inventory $PFA --exclude Teamcenter --classify "$AM/cls-loc.txt"
  printf '%s\n' 'addon:Broken LOCATION data:EXFN_Authentication.ClientConfiguration.OpcenterEXFNUrl # control: the protected microflow reads this' \
    'addon:Broken MOCKED # control: seed data points it at /a/' 'addon:EXFN_Authentication MOCKED # control' > "$AM/cls-locdata.txt"
  ctl apimock-classify-location-data-pass 0 '^MOCKED +addon:Broken .*via data EXFN_Authentication\.ClientConfiguration\.OpcenterEXFNUrl' '· unknown 0$' \
    -- python3 $B/apimock.py inventory $PFB --exclude Teamcenter --classify "$AM/cls-locdata.txt"
  echo 'addon:Broken LOCATION http://x # control' > "$AM/cls-locbad.txt"
  ctl apimock-classify-location-syntax-catch 2 'LOCATION wants const:<Module\.Constant> or data:<Module\.Entity\.Attribute>' -- python3 $B/apimock.py inventory $PFB --classify "$AM/cls-locbad.txt"
  # an endpoint id carries a '#2' suffix (rest:Mod.Mf#2): the '#' inside the pattern is not the reason separator
  echo 'rest:Mod.Mf#2 EXCLUDED IdP # control: the pattern holds a hash' > "$AM/cls-hash.txt"
  ctl apimock-classify-hash-in-pattern-pass 3 '· unknown 2$' '!--classify' -- python3 $B/apimock.py inventory $PFB --exclude Teamcenter --classify "$AM/cls-hash.txt"
  # B4T2-5: --public-host means an app in a container calls it, so the default bind is 0.0.0.0, the URLs the public host
  ctl apimock-serve-public-host-bind-pass 0 'apimock: listening on 0\.0\.0\.0:' '^MendixSSO\.RolesLocation=http://host\.docker\.internal:[0-9]+/c/' \
    -- python3 $B/apimock.py serve $PF --exclude Teamcenter --state $AM/stph --port 0 --public-host host.docker.internal --background
  [ -f $AM/stph/pid ] && python3 $B/apimock.py stop --state $AM/stph > /dev/null
  # serve: ONE stand-in for both models (old and new app); a mocked REST call answers a body of the mapped shape
  S=$AM/st
  ctl apimock-serve-pass 0 '^MendixSSO\.RolesLocation=http://127\.0\.0\.1:[0-9]+/c/MendixSSO\.RolesLocation$' '^EmployeeManagement\.ODATA_EmployeeManagement_Location=http://127\.0\.0\.1:' \
    '^apis 4 found · mocked 2 · excluded 1 \(Teamcenter\) · unknown 1$' 'apimock: listening on 127\.0\.0\.1:' -- python3 $B/apimock.py serve $PF $KB --exclude Teamcenter --state $S --port 0 --background
  ctl apimock-rest-shape-pass 0 '^status 200$' '^shape: 3 of 3 mapped paths in the body$' -- python3 $AM/fetch.py $B $S GET /c/MendixSSO.RolesLocation/api/approles/v1/environment/env1/user/u1 $PF MendixSSO.AppRolesResponse
  ctl apimock-odata-pass 0 '^status 200$' '"@odata\.context": "\$metadata#Employees"' '"FirstName": "FirstName 1"' -- python3 $AM/fetch.py $B $S GET /c/EmployeeManagement.ODATA_EmployeeManagement_Location/Employees
  ctl apimock-excluded-503-pass 0 '^status 503$' 'EXCLUDED: Teamcenter' -- python3 $AM/fetch.py $B $S POST /a/TcConnector.SoaServiceRequest.ServiceURL
  ctl apimock-log-pass 0 '"endpoint": "rest:MendixSSO\.RetrieveUserRoles", "status": "MOCKED"' '"status": "EXCLUDED", "system": "Teamcenter"' -- cat $S/requests.jsonl
  # check: everything answered, but the UNKNOWN Opcenter endpoint keeps the rung INVALID (exit 3)
  ctl apimock-check-unknown-catch 3 '^requests 3 · mocked 2 · excluded 1 · unknown 0 · unmatched 0$' 'verdict: INVALID: 1 endpoints UNKNOWN' '!verdict: PASS' -- python3 $B/apimock.py check --state $S --exclude-systems Teamcenter
  # a request no endpoint owns is UNMATCHED (404) and INVALID too, even with every endpoint classified
  [ -f $S/pid ] && python3 $B/apimock.py stop --state $S > /dev/null   # started by apimock-serve-pass unless --only skipped it
  S2=$AM/st2
  python3 $B/apimock.py serve $PF --exclude Teamcenter --state $S2 --port 0 --background > /dev/null
  ctl apimock-standin-uncalled-pass 0 '^  STAND-IN \(MendixSSO\) endpoint rest:MendixSSO\.RetrieveUserRoles: 0 requests answered$' '^stand-in endpoints 1 · requests answered 0$' -- python3 $B/apimock.py standin --state $S2
  # B4N1-11: every endpoint MOCKED and nothing called is no proof at all (Opcenter b4: PASS on 0 requests): INVALID
  ctl apimock-check-zero-traffic-catch 3 '^requests seen: 0$' '^  NOT EXERCISED endpoint rest:MendixSSO\.RetrieveUserRoles: 0 requests answered: no proof' \
    'verdict: INVALID: 1 endpoints MOCKED and 0 requests answered' '!verdict: PASS' -- python3 $B/apimock.py check --state $S2 --exclude-systems Teamcenter
  python3 $AM/fetch.py $B $S2 GET /c/MendixSSO.RolesLocation/api/approles/v1/environment/env1/user/u1 > /dev/null
  ctl apimock-check-except 4 '^requests seen: 1$' '!NOT EXERCISED' '^  NOT CHECKED \(excluded: Teamcenter\) endpoint rest:TcConnector\.SendService$' 'verdict: PASS except Teamcenter: 1 endpoints NOT CHECKED' '!verdict: PASS$' -- python3 $B/apimock.py check --state $S2 --exclude-systems Teamcenter
  ctl apimock-check-unnamed-system-catch 3 'excluded for a system not in EXCLUDE_SYSTEMS \(Teamcenter\)' -- python3 $B/apimock.py check --state $S2
  python3 $AM/fetch.py $B $S2 GET /nowhere > /dev/null
  ctl apimock-check-unmatched-catch 3 '^  UNMATCHED request GET /nowhere' 'verdict: INVALID: 1 requests to UNKNOWN or UNMATCHED' -- python3 $B/apimock.py check --state $S2 --exclude-systems Teamcenter
  ctl apimock-stop-pass 0 'apimock: stopped' -- python3 $B/apimock.py stop --state $S2
  [ -f $S2/pid ] && python3 $B/apimock.py stop --state $S2 > /dev/null   # never leave a stand-in behind (--only)
  # E2E-15: standin lists every MOCKED endpoint (called or not) with the requests it answered; EXCLUDED and UNKNOWN are not
  # stand-in answers (they are NOT CHECKED or INVALID elsewhere). $S: apimock-serve-pass + the fetches above.
  ctl apimock-standin-pass 0 '^  STAND-IN \(MendixSSO\) endpoint rest:MendixSSO\.RetrieveUserRoles: 1 requests answered$' \
    '^  STAND-IN \(EmployeeManagement\) endpoint odata:EmployeeManagement\.ODATA_EmployeeManagement: 1 requests answered$' \
    '^stand-in systems: EmployeeManagement, MendixSSO$' '^stand-in endpoints 2 · requests answered 2$' '!STAND-IN \((Teamcenter|OpcenterConnector)' -- python3 $B/apimock.py standin --state $S
  # B4N1-11: a MOCKED endpoint nobody called is NOT EXERCISED; INVALID unless an UNEXERCISED line waives it with a reason.
  # $S4: both models; Opcenter MOCKED (seed data) but never called, waived; the OData service reached under a path prefix.
  S4=$AM/st4
  printf '%s\n' 'rest:OpcenterConnector.* MOCKED # control: the seed data points ClientConfiguration.OpcenterEXFNUrl at /a/' \
    'rest:OpcenterConnector.* UNEXERCISED # control: no journey opens the Opcenter query page' > "$AM/cls-unex.txt"
  python3 $B/apimock.py serve $PF $KB --exclude Teamcenter --classify "$AM/cls-unex.txt" --state $S4 --port 0 --background > /dev/null
  python3 $AM/fetch.py $B $S4 GET /c/MendixSSO.RolesLocation/api/approles/v1/environment/env1/user/u1 > /dev/null
  ctl apimock-odata-prefix-pass 0 '^status 200$' '"@odata\.context": "\$metadata#Employees"' -- python3 $AM/fetch.py $B $S4 GET /c/EmployeeManagement.ODATA_EmployeeManagement_Location/x/odata/Employees
  python3 $B/apimock.py stop --state $S4 > /dev/null
  ctl apimock-check-unexercised-waived-pass 4 '^requests seen: 2$' '^  NOT EXERCISED endpoint rest:OpcenterConnector\.ExecuteOpcenterQuery_Custom: 0 requests answered \(waived: control: no journey' \
    'verdict: PASS except Teamcenter' -- python3 $B/apimock.py check --state $S4 --exclude-systems Teamcenter
  rm -rf "$AM/st4u" "$AM/st4z"; cp -r "$S4" "$AM/st4u"; cp -r "$S4" "$AM/st4z"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); [e.pop("unexercised", None) for e in d["endpoints"]]; json.dump(d, open(p, "w"))' "$AM/st4u/inventory.json"
  ctl apimock-check-unexercised-catch 3 'NOT EXERCISED endpoint rest:OpcenterConnector\.ExecuteOpcenterQuery_Custom: 0 requests answered: no proof' \
    'verdict: INVALID: 1 MOCKED endpoints NOT EXERCISED' '!verdict: PASS' -- python3 $B/apimock.py check --state $AM/st4u --exclude-systems Teamcenter
  # zero traffic is never waivable, even with every MOCKED endpoint waived
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); [e.update(unexercised="control") for e in d["endpoints"] if e["status"] == "MOCKED"]; json.dump(d, open(p, "w"))' "$AM/st4z/inventory.json"
  : > "$AM/st4z/requests.jsonl"
  ctl apimock-check-zero-traffic-waived-catch 3 '^requests seen: 0$' '\(waived: control\)' 'verdict: INVALID: 3 endpoints MOCKED and 0 requests answered' '!verdict: PASS' \
    -- python3 $B/apimock.py check --state $AM/st4z --exclude-systems Teamcenter
  # end to end with the REAL apimock.py (other instruments stubbed): a gate whose every rung passes on the stand-in is
  # never plain PASS. $S3: PFEP, Teamcenter excluded, the MendixSSO roles call answered once.
  S3=$AM/st3; GB3=$T/gate-bin-am; mkdir -p "$GB3"; cp "$GB"/* "$GB3"/; cp $B/apimock.py $B/mprmodel.py "$GB3"/
  python3 $B/apimock.py serve $PF --exclude Teamcenter --state $S3 --port 0 --background > /dev/null
  python3 $AM/fetch.py $B $S3 GET /c/MendixSSO.RolesLocation/api/approles/v1/environment/env1/user/u1 > /dev/null
  python3 $B/apimock.py stop --state $S3 > /dev/null
  ctl gate-standin-real-catch 4 'Overall: \*\*PASS \(on stand-in APIs: MendixSSO; except Teamcenter: 1 items\)\*\* \(exit 4\)' '\| 12 \| apis \| EXCEPT \| 4 \|' \
    '^- STAND-IN \(MendixSSO\) endpoint rest:MendixSSO\.RetrieveUserRoles: 1 requests answered$' 'Real-system behaviour was NOT checked' '!Overall: \*\*PASS\*\*' '!\(exit 0\)' \
    '\| 12 \| apis \| EXCEPT \| 4 \| .*requests seen: 1' -- gcase sireal GATE_BIN_DIR=$GB3 APIMOCK=$S3 EXCLUDE_SYSTEMS=Teamcenter
  # B4N1-11 through the gate: the same stand-in with no request logged is INVALID, never PASS-on-stand-in
  rm -rf "$AM/st3z"; cp -r "$S3" "$AM/st3z"; : > "$AM/st3z/requests.jsonl"
  ctl gate-apis-zero-traffic-catch 2 '\| 12 \| apis \| INVALID \| 3 \| .*requests seen: 0' 'Overall: \*\*INVALID' '!Overall: \*\*PASS' \
    -- gcase sizero GATE_BIN_DIR=$GB3 APIMOCK=$AM/st3z EXCLUDE_SYSTEMS=Teamcenter
else
  for c in inventory-pass unknown-invalid-catch no-exclude-catch classify-reason-catch classify-pass serve-pass rest-shape-pass odata-pass excluded-503-pass \
           log-pass check-unknown-catch check-except check-unnamed-system-catch check-unmatched-catch stop-pass standin-pass standin-uncalled-pass \
           addon-unknown-catch addon-unreadable-catch classify-mocked-no-route-catch classify-location-pass classify-location-data-pass \
           classify-location-syntax-catch serve-public-host-bind-pass check-zero-traffic-catch odata-prefix-pass check-unexercised-waived-pass \
           check-unexercised-catch check-zero-traffic-waived-catch; do skip apimock-$c "no python bson"; done
  skip gate-standin-real-catch "no python bson"; skip gate-apis-zero-traffic-catch "no python bson"
fi

# --- direct API test (bin/apidirect.py, steps/apis.md): every consumed REST call on the old and the new app ------------
# compare reads the stored runs (no app): per call the requests sent to the stand-in, the result read, the error path of a
# stand-in 500 and of a malformed body. A request, a response mapping and an error path difference each FAIL; a call that
# could not be measured is INVALID with its reason; an excluded system is INFO.
if python3 -c 'import bson' 2>/dev/null; then
AD=$T/ad; mkdir -p "$AD"
for v in pass request response error invalid info; do python3 "$here/lib/apidirect_state.py" "$AD/$v" $v; done
ctl apidirect-compare-pass 0 'PASS 1' '!FAIL' -- python3 $B/apidirect.py compare --state $AD/pass
ctl apidirect-check-pass 0 'direct API test: PASS 1 · FAIL 0 · INVALID 0 · INFO 0 \(measured 1 of 1 REST calls' 'verdict: PASS$' -- python3 $B/apidirect.py check --state $AD/pass
ctl apidirect-request-diff-catch 0 'FAIL 1' -- python3 $B/apidirect.py compare --state $AD/request
ctl apidirect-request-diff-check-catch 1 'FAIL endpoint rest:A\.Get: request difference \(ok run\): request1\.query' 'verdict: FAIL: 1 REST calls differ' '!verdict: PASS' -- python3 $B/apidirect.py check --state $AD/request
ctl apidirect-response-diff-catch 0 'FAIL 1' -- python3 $B/apidirect.py compare --state $AD/response
ctl apidirect-response-diff-check-catch 1 'FAIL endpoint rest:A\.Get: response difference \(ok run\): result\.ok\.objects\[0\]\.attributes\.Name\.value' '!verdict: PASS' -- python3 $B/apidirect.py check --state $AD/response
ctl apidirect-error-diff-catch 0 'FAIL 1' -- python3 $B/apidirect.py compare --state $AD/error
ctl apidirect-error-diff-check-catch 1 'FAIL endpoint rest:A\.Get: error difference \(500 run\): result' 'one app failed, the other handled it' '!verdict: PASS' -- python3 $B/apidirect.py check --state $AD/error
ctl apidirect-invalid-catch 0 'INVALID 1' 'PASS 1' -- python3 $B/apidirect.py compare --state $AD/invalid
ctl apidirect-invalid-check-catch 3 'INVALID endpoint rest:A\.Needs: needs input recipe: parameter X: entity System\.HttpResponse' 'verdict: INVALID: 1 REST calls could not be measured' '!verdict: PASS' -- python3 $B/apidirect.py check --state $AD/invalid
ctl apidirect-info-pass 0 'INFO 1' 'PASS 1' -- python3 $B/apidirect.py compare --state $AD/info
ctl apidirect-info-check-pass 0 'INFO \(excluded: IdP\) endpoint rest:A\.Login: check at deploy' 'verdict: PASS \(INFO: 1 excluded endpoints, check at deploy\)' '!verdict: INVALID' -- python3 $B/apidirect.py check --state $AD/info
# volatile values (ids, timestamps, the stand-in's host) never make a difference
python3 - "$AD" <<'EOF'
import json, shutil, sys
from pathlib import Path
d = Path(sys.argv[1]); n = d / "volatile"
shutil.copytree(d / "pass", n, dirs_exist_ok=True)
rows = [json.loads(x) for x in (n / "results-new.jsonl").read_text().splitlines()]
for r in rows:
    for o in (r["response"].get("objects") or []):
        o["guid"] = "999999999999"
(n / "results-new.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
EOF
ctl apidirect-volatile-ids-pass 0 'PASS 1' '!FAIL' -- python3 $B/apidirect.py compare --state $AD/volatile
# apimock check: a --classify EXCLUDED line is INFO (exit 0), and --direct measured endpoints need no journey hit
python3 - "$AD" <<'EOF'
import json, sys
from pathlib import Path
d = Path(sys.argv[1]) / "am"; d.mkdir(exist_ok=True)
eps = [{"id": "rest:A.Get", "kind": "rest", "module": "A", "doc": "A.Get", "method": "GET", "template": "", "routes": [["const", "A.Host"]],
        "status": "MOCKED", "system": "", "why": "", "shape": "x"},
       {"id": "rest:A.Login", "kind": "rest", "module": "A", "doc": "A.Login", "method": "POST", "template": "", "routes": [["const", "A.IdP"]],
        "status": "EXCLUDED", "system": "IdP", "why": "classified EXCLUDED (rest:A.Login*): the IdP", "classified": True, "shape": "x"}]
(d / "inventory.json").write_text(json.dumps({"models": [], "endpoints": eps, "constants": {}, "metadata": {}, "excludes": []}))
(d / "requests.jsonl").write_text(json.dumps({"t": "2026-01-01T00:00:00Z", "method": "GET", "path": "/c/A.Host/x", "endpoint": "rest:A.Get", "status": "MOCKED", "code": 200}) + "\n")
(d / "idle").mkdir(exist_ok=True)
(d / "idle" / "inventory.json").write_text((d / "inventory.json").read_text())
(d / "idle" / "requests.jsonl").write_text(json.dumps({"t": "2026-01-01T00:00:00Z", "method": "GET", "path": "/nowhere", "endpoint": "rest:A.Other", "status": "MOCKED", "code": 200}) + "\n")
EOF
ctl apimock-check-classified-info-pass 0 'INFO \(excluded: IdP\) endpoint rest:A\.Login: check at deploy' 'verdict: PASS \(INFO: 1 endpoints of IdP are excluded, check at deploy\)' '!NOT CHECKED' '!INVALID' -- python3 $B/apimock.py check --state $AD/am
ctl apimock-check-direct-pass 0 'direct API test: PASS 1' 'verdict: PASS' '!NOT EXERCISED' -- python3 $B/apimock.py check --state $AD/am/idle --direct $AD/pass
ctl apimock-check-direct-fail-catch 1 'FAIL endpoint rest:A\.Get: request difference' 'verdict: FAIL' '!verdict: PASS' -- python3 $B/apimock.py check --state $AD/am/idle --direct $AD/request
ctl apimock-check-direct-invalid-catch 3 'INVALID endpoint rest:A\.Needs' 'verdict: INVALID' '!verdict: PASS' -- python3 $B/apimock.py check --state $AD/am/idle --direct $AD/invalid
# the stand-in's control endpoint and fault modes: a request is logged with its call, side, mode, headers (secrets masked) and body
ctl apidirect-standin-modes-pass 0 'ctx=\{"call": "A.Get", "side": "old", "mode": "ok"\}' 'ok: 200 ' '500: 500 ' 'malformed: 200 not-json' 'secret masked' 'logged 3 with call' -- python3 - $B <<'EOF'
import json, sys, threading, urllib.request, tempfile
from pathlib import Path
sys.path.insert(0, sys.argv[1]); import apimock
inv = {"endpoints": [{"id": "rest:A.Get", "kind": "rest", "module": "A", "doc": "A.Get", "method": "GET", "template": "", "params": [], "routes": [("const", "A.Host")],
                      "body": {"value": []}, "content_type": "application/json", "shape": "x", "status": "MOCKED", "system": ""}], "metadata": {}}
st = Path(tempfile.mkdtemp())
stand = apimock.Stand(inv, st, None)
from http.server import ThreadingHTTPServer
srv = ThreadingHTTPServer(("127.0.0.1", 0), apimock.make_handler(stand))
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_address[1]}"
def go(path, body=None, headers=None):
    rq = urllib.request.Request(base + path, data=body, headers=headers or {}, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(rq, timeout=10) as r: return r.status, r.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()
print("ctx=" + json.dumps(json.loads(go("/__ad/call", b'{"call": "A.Get", "side": "old", "mode": "ok"}')[1])["ctx"]))
print("ok:", go("/c/A.Host/x?q=1", headers={"Authorization": "Bearer SECRETTOKEN"})[0], "")
go("/__ad/call", b'{"call": "A.Get", "side": "old", "mode": "500"}'); print("500:", go("/c/A.Host/x")[0], "")
go("/__ad/call", b'{"call": "A.Get", "side": "old", "mode": "malformed"}'); s, b = go("/c/A.Host/x")
try: json.loads(b); print("malformed: json")
except ValueError: print("malformed:", s, "not-json")
go("/__ad/end", b"{}")
log = [json.loads(x) for x in (st / "requests.jsonl").read_text().splitlines()]
print("secret masked" if all("SECRETTOKEN" not in json.dumps(r) for r in log) else "SECRET LEAKED")
print("logged", sum(1 for r in log if r.get("call") == "A.Get"), "with call")
EOF
ctl apidirect-normalize-pass 0 'hash ignored' 'order ignored' 'error layout ignored' 'real error difference kept' 'real value difference kept' -- python3 - $B <<'EOF'
import sys
sys.path.insert(0, sys.argv[1]); import apidirect as A
def resp(objs, guids):
    return A.norm_response({"http": 200, "response": {"objects": objs, "actionResult": {"resultGuids": guids}}})
o = lambda g, h, v: {"objectType": "M.E", "guid": g, "hash": h, "attributes": {"N": {"value": v}}}
print("hash ignored" if resp([o("111111111111", "v2:aaa", "x")], ["111111111111"]) == resp([o("222222222222", "v2:bbb", "x")], ["222222222222"]) else "HASH DIFFERS")
a = resp([o("111111111111", "h", "x"), o("111111111112", "h", "y")], ["111111111111"])
b = resp([o("222222222221", "h", "y"), o("222222222222", "h", "x")], ["222222222222"])
print("order ignored" if a == b else "ORDER DIFFERS")
old = "ERROR - Connector: An error has occurred while handling the request. | com.mendix.modules.microflowengine.MicroflowException: Error calling REST service | at A.F (CallRest : 'Get') | Caused by: x: 500: Internal Server Error"
new = "ERROR - Connector: An error has occurred while handling the request.: Error calling REST service | at A.F (CallRest : 'Get') | Advanced stacktrace: | y"
print("error layout ignored" if A.norm_error(old) == A.norm_error(new) else "LAYOUT DIFFERS " + A.norm_error(old) + " / " + A.norm_error(new))
print("real error difference kept" if A.norm_error(old) != A.norm_error(new.replace("Error calling REST service", "Error parsing JSON")) else "ERROR MASKED")
print("real value difference kept" if resp([o("1", "h", "x")], []) != resp([o("2", "h", "z")], []) else "VALUE MASKED")
EOF
else
  for c in apidirect-compare-pass apidirect-check-pass apidirect-request-diff-catch apidirect-request-diff-check-catch apidirect-response-diff-catch apidirect-response-diff-check-catch apidirect-error-diff-catch apidirect-error-diff-check-catch apidirect-invalid-catch apidirect-invalid-check-catch apidirect-info-pass apidirect-info-check-pass apidirect-volatile-ids-pass apimock-check-classified-info-pass apimock-check-direct-pass apimock-check-direct-fail-catch apimock-check-direct-invalid-catch apidirect-standin-modes-pass apidirect-normalize-pass; do skip $c "no python bson"; done
fi
ctl apimock-check-no-state-catch 2 'no .*inventory\.json' -- python3 $B/apimock.py check --state $AM/none
ctl apimock-standin-no-state-catch 2 'no .*inventory\.json' -- python3 $B/apimock.py standin --state $AM/none
# attribution (E2E-14): a FAIL step is NOT CHECKED only when a call into an excluded system lies strictly inside its window
# and no UNKNOWN / UNMATCHED call lies around it; every other FAIL stays FAIL. Synthetic logs in the form serve writes.
mkdir -p "$AM/a1" "$AM/a2" "$AM/a3" "$AM/a4"
amlog() { local d=$1; shift; : > "$AM/$d/requests.jsonl"; while [ $# -gt 0 ]; do
  printf '{"t": "2026-01-01T10:00:%s+00:00", "method": "POST", "path": "/a/x", "query": "", "endpoint": "%s", "status": "%s", "system": "%s", "code": 200, "match": "template"}\n' "$1" "$2" "$3" "$4" >> "$AM/$d/requests.jsonl"; shift 4; done; }
amlog a1 02.000 rest:TcConnector.SendService EXCLUDED Teamcenter 03.000 rest:MendixSSO.RetrieveUserRoles MOCKED ''
amlog a2 03.000 rest:MendixSSO.RetrieveUserRoles MOCKED ''
amlog a3 05.500 rest:TcConnector.SendService EXCLUDED Teamcenter
amlog a4 02.000 rest:TcConnector.SendService EXCLUDED Teamcenter 03.000 rest:OpcenterConnector.ExecuteOpcenterQuery_Custom UNKNOWN ''
echo '{"roles": [{"role": "Administrator", "steps": [{"caption": "Parts", "target": "PFEP.Part_Overview", "verdict": "FAIL", "t0": "2026-01-01T10:00:00.000Z", "t1": "2026-01-01T10:00:05.000Z"}, {"caption": "Home", "target": "PFEP.Home", "verdict": "PASS", "t0": "2026-01-01T10:00:06.000Z", "t1": "2026-01-01T10:00:07.000Z"}]}]}' > "$AM/smoke-after.json"
ctl apimock-attribute-smoke-except 4 '^  NOT CHECKED \(excluded: Teamcenter\) smoke Administrator: Parts -> PFEP\.Part_Overview: .*POST /a/x \(rest:TcConnector\.SendService\)' 'every FAIL step \(1\) called only an excluded system' \
  -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a1 --exclude-systems Teamcenter
ctl apimock-attribute-smoke-mocked-only-catch 1 '^  still FAIL Administrator: Parts .*fails with no call into an excluded system' '!NOT CHECKED \(' -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a2 --exclude-systems Teamcenter
ctl apimock-attribute-smoke-outside-window-catch 1 '^  still FAIL Administrator: Parts' '!NOT CHECKED \(' -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a3 --exclude-systems Teamcenter
ctl apimock-attribute-smoke-unknown-catch 1 '^  still FAIL Administrator: Parts .*UNKNOWN call POST /a/x' '!NOT CHECKED \(' -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a4 --exclude-systems Teamcenter
ctl apimock-attribute-smoke-other-system-catch 1 '^  still FAIL Administrator: Parts' -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a1 --exclude-systems SAP
ctl apimock-attribute-smoke-no-systems-catch 2 'exclude-systems is empty' -- python3 $B/apimock.py attribute-smoke $AM/smoke-after.json --state $AM/a1
# run_journeys --apimock-log (E2E-14): the same rule per journey step window; exit 4 = only NOT CHECKED besides PASS
JA=$T/rja; mkdir -p $JA/new/after $JA/old/before
amj() {  # amj VERDICT_OF_dashboard: the new run, one journey with a failing step 1 (10:00:00-05) and a passing step 2
  echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "'$1'", "not_pass": ["FAIL text Parts"], "windows": [{"n": 1, "t0": "2026-01-01T10:00:00.000Z", "t1": "2026-01-01T10:00:05.000Z", "ok": false}, {"n": 2, "t0": "2026-01-01T10:00:06.000Z", "t1": "2026-01-01T10:00:07.000Z", "ok": true}], "effects": [{"n": 1, "changed": {}}]}, "login-Administrator": {"role": "Administrator", "verdict": "PASS", "effects": [{"n": 1, "changed": {}}]}}, "roles": {}, "journey_set": {"sha256": "c0ffee"}}' > $JA/new/after/summary.json; }
amj FAIL
ctl journeys-apimock-except 4 '^  NOT CHECKED \(excluded: Teamcenter\) journey dashboard-Administrator: step1: POST /a/x \(rest:TcConnector\.SendService\)' '^journeys: 1 PASS, 0 FAIL, 0 INVALID, 1 NOT CHECKED \(excluded: Teamcenter\)$' \
  -- python3 $B/run_journeys.py x --label after --work $JA/new --rejudge --apimock-log $AM/a1/requests.jsonl --exclude-systems Teamcenter
ctl journeys-apimock-mocked-only-catch 1 '^journeys: 1 PASS, 1 FAIL, 0 INVALID$' '!NOT CHECKED' -- python3 $B/run_journeys.py x --label after --work $JA/new --rejudge --apimock-log $AM/a2/requests.jsonl --exclude-systems Teamcenter
ctl journeys-apimock-no-systems-catch 1 '^journeys: 1 PASS, 1 FAIL, 0 INVALID$' -- python3 $B/run_journeys.py x --label after --work $JA/new --rejudge --apimock-log $AM/a1/requests.jsonl
ctl journeys-apimock-unknown-catch 1 '^journeys: 1 PASS, 1 FAIL' '!NOT CHECKED \(' -- python3 $B/run_journeys.py x --label after --work $JA/new --rejudge --apimock-log $AM/a4/requests.jsonl --exclude-systems Teamcenter
# with --compare (coverage waived, both runs pinned to one journey set, E2E-11): a NOT CHECKED journey is no REGRESSION,
# and its screen pair (charts gone) is not judged; the other pair is
cp -R $SH/old/shots-Administrator $JA/old/before/; cp -R $SH/empty/shots-Administrator $JA/new/after/
echo '{"journeys": {"dashboard-Administrator": {"role": "Administrator", "verdict": "PASS", "effects": [{"n": 1, "changed": {}}]}, "login-Administrator": {"role": "Administrator", "verdict": "PASS", "effects": [{"n": 1, "changed": {}}]}}, "roles": {}, "journey_set": {"sha256": "c0ffee"}}' > $JA/old/before/summary.json
ctl journeys-apimock-compare-except 4 '^  NOT CHECKED dashboard-Administrator ' '!REGRESSION' '!verdict: INVALID only' '^journeys: 1 PASS, 0 FAIL, 0 INVALID, 1 NOT CHECKED' \
  -- python3 $B/run_journeys.py x --label after --work $JA/new --compare $JA/old --rejudge --apimock-log $AM/a1/requests.jsonl --exclude-systems Teamcenter "${NOACT[@]}"
ctl journeys-apimock-compare-regression-catch 1 '^  FAIL +dashboard-Administrator .*\[REGRESSION\]' -- python3 $B/run_journeys.py x --label after --work $JA/new --compare $JA/old --rejudge --apimock-log $AM/a2/requests.jsonl --exclude-systems Teamcenter "${NOACT[@]}"
# gate.sh (stubs): EXCEPT is listed by name and the overall verdict is "PASS (except ...)", exit 4, never plain PASS
NC1='journeys: 3 PASS, 0 FAIL, 0 INVALID, 1 NOT CHECKED (excluded: Teamcenter)
  NOT CHECKED (excluded: Teamcenter) journey parts-Administrator: step1: POST /a/x (rest:TcConnector.SendService)'
ctl gate-apis-dry-pass 0 "^\\[apis\\] .*apimock\\.py check --state $GI/am --exclude-systems Teamcenter\$" "^\\[journeys\\] .*--apimock-log $GI/am/requests\\.jsonl --exclude-systems Teamcenter" -- gcase amd --dry-run EXCLUDE_SYSTEMS=Teamcenter
# MC-19: the optional widgets rung (bin/widgetcover.py): dry-run command, rc 3 (a used widget no walk renders) is INVALID, not configured is NOT RUN
ctl gate-widgets-dry-pass 0 "^\\[widgets\\] .*widgetcover\\.py $GI --journeys $GI/jd\$" 'dry-run: nothing was run' -- gcase wdry --dry-run WIDGETS_APP=$GI
ctl gate-widgets-unrendered-invalid 2 '\| 13 \| widgets \| INVALID \| 3 \|' 'Overall: \*\*INVALID' '!Overall: \*\*PASS' -- gcase wunr GATE_STUB_RC_widgetcover=3 "GATE_STUB_OUT_widgetcover=verdict: UNRENDERED (1 of 2 used package(s))" WIDGETS_APP=$GI
ctl gate-widgets-pass 0 '\| 13 \| widgets \| PASS \| 0 \|' 'Overall: \*\*PASS' -- gcase wpass WIDGETS_APP=$GI
# NMR-4 (--only leaves the other rungs NOT RUN, so the gate itself exits 2; the widgets line is what is judged): the REAL widgetcover with every gap waived reaches the gate as PASS* (reason in the detail), a full render stays PASS
printf 'Shop.Home_Overview\nShop.Viewer_Panel\n' > $T/wc-rendered-all.txt
printf 'Viewer.mpk # licensed viewer, walked by hand\nMarkdown.mpk # shown on a rarely used page\n' > $T/wc-waive-all.txt
ctl gate-widgets-waived-passstar-pass 2 '^\[widgets\] PASS\* rc=0 +verdict: PASS\* 2 waived of 2 .*licensed viewer' '!\[widgets\] PASS rc' -- gcase wwv GATE_BIN_DIR=$B WIDGETS_APP=$M/widgetcover WIDGETS_WAIVE=$T/wc-waive-all.txt --only widgets
ctl gate-widgets-rendered-plain-pass 2 '^\[widgets\] PASS rc=0 +verdict: PASS \(every' '!\[widgets\] PASS\* rc' -- gcase wfull GATE_BIN_DIR=$B WIDGETS_APP=$M/widgetcover WIDGETS_RENDERED=$T/wc-rendered-all.txt --only widgets
ctl gate-widgets-not-configured-pass 0 '\| 13 \| widgets \| NOT RUN \| - \| not configured .*\(optional rung\)' 'Overall: \*\*PASS' -- gcase wnone
ctl gate-except-pass 4 'Overall: \*\*PASS \(except Teamcenter: 1 items\)\*\*' '\| 9 \| journeys \| EXCEPT \| 4 \| 1 NOT CHECKED \(excluded: Teamcenter\)' '^- journeys: NOT CHECKED \(excluded: Teamcenter\) journey parts-Administrator' \
  '\| 12 \| apis \| PASS \|' '!Overall: \*\*PASS\*\*' -- gcase exc GATE_STUB_RC_run_journeys=4 "GATE_STUB_OUT_run_journeys=$NC1" EXCLUDE_SYSTEMS=Teamcenter
ctl gate-except-no-systems-catch 2 '\| 9 \| journeys \| INVALID \| 4 \|' 'Overall: \*\*INVALID' '!Overall: \*\*PASS' -- gcase exn GATE_STUB_RC_run_journeys=4 "GATE_STUB_OUT_run_journeys=$NC1"
ctl gate-except-unnamed-catch 2 '\| 9 \| journeys \| INVALID \| 4 \| rc 4 but no NOT CHECKED item named' '!Overall: \*\*PASS' -- gcase exu GATE_STUB_RC_run_journeys=4 EXCLUDE_SYSTEMS=Teamcenter
ctl gate-except-fail-wins-catch 1 'Overall: \*\*FAIL\*\*' '\| 9 \| journeys \| EXCEPT \|' '\| 6 \| logdiff \| FAIL \|' '!Overall: \*\*PASS' -- gcase exf GATE_STUB_RC_run_journeys=4 "GATE_STUB_OUT_run_journeys=$NC1" GATE_STUB_RC_logdiff=1 EXCLUDE_SYSTEMS=Teamcenter
ctl gate-except-needs-apimock-catch 2 'EXCLUDE_SYSTEMS' -- gcase exa EXCLUDE_SYSTEMS=Teamcenter APIMOCK=off --dry-run
ctl gate-apis-invalid-catch 2 '\| 12 \| apis \| INVALID \| 3 \|' 'Overall: \*\*INVALID' -- gcase api3 GATE_STUB_RC_apimock=3 'GATE_STUB_OUT_apimock=apis 3 found · mocked 2 · excluded 0 · unknown 1'
# smoke: rc 1 whose FAIL steps attribute-smoke clears (exit 4 + a named item) is EXCEPT; a plain smoke FAIL stays FAIL
ctl gate-smoke-except-pass 4 '\| 7 \| smoke \| EXCEPT \| 4 \|' '\| 12 \| apis \| EXCEPT \| 4 \|' 'Overall: \*\*PASS \(except Teamcenter: 2 items\)\*\*' \
  -- gcase sme GATE_STUB_RC_smokewalk=1 GATE_STUB_RC_apimock=4 'GATE_STUB_OUT_apimock=  NOT CHECKED (excluded: Teamcenter) smoke Administrator: Parts -> PFEP.Part_Overview: POST /a/x' EXCLUDE_SYSTEMS=Teamcenter
ctl gate-smoke-fail-stays-catch 1 '\| 7 \| smoke \| FAIL \| 1 \|' 'Overall: \*\*FAIL' -- gcase smf GATE_STUB_RC_smokewalk=1 GATE_STUB_RC_apimock=1 EXCLUDE_SYSTEMS=Teamcenter
# E2E-15: the stand-in is a stopgap. Any endpoint it answered for = "PASS (on stand-in APIs: <systems>)", exit 4, the
# endpoints listed by name and "real-system behaviour was NOT checked"; never plain PASS, never 0. FAIL/INVALID still win.
SI1='  STAND-IN (OpcenterConnector) endpoint rest:OpcenterConnector.ExecuteOpcenterQuery: 4 requests answered
  STAND-IN (EmployeeManagement) endpoint odata:EmployeeManagement.ODATA_EmployeeManagement: 0 requests answered
stand-in systems: EmployeeManagement, OpcenterConnector
stand-in endpoints 2 · requests answered 4'
ctl gate-standin-pass 4 'Overall: \*\*PASS \(on stand-in APIs: EmployeeManagement, OpcenterConnector\)\*\* \(exit 4\)' '\| 12 \| apis \| PASS \|' \
  '^ON STAND-IN APIs \(E2E-15\): 2 endpoints were answered by apimock\.py' 'Real-system behaviour was NOT checked' \
  '^- STAND-IN \(OpcenterConnector\) endpoint rest:OpcenterConnector\.ExecuteOpcenterQuery: 4 requests answered$' '!Overall: \*\*PASS\*\*' -- gcase si "GATE_STUB_OUT_apimock_standin=$SI1"
ctl gate-standin-except-pass 4 'Overall: \*\*PASS \(on stand-in APIs: EmployeeManagement, OpcenterConnector; except Teamcenter: 1 items\)\*\*' '^- journeys: NOT CHECKED \(excluded: Teamcenter\)' \
  '^- STAND-IN \(EmployeeManagement\)' -- gcase sie GATE_STUB_RC_run_journeys=4 "GATE_STUB_OUT_run_journeys=$NC1" "GATE_STUB_OUT_apimock_standin=$SI1" EXCLUDE_SYSTEMS=Teamcenter
# catch: every rung PASS and the apis rung "verdict: PASS", one endpoint on the stand-in (no systems line: the driver
# takes the name from the item) -> still exit 4, never "Overall: **PASS**" or exit 0
ctl gate-standin-not-plain-catch 4 'Overall: \*\*PASS \(on stand-in APIs: OpcenterConnector\)\*\*' '!Overall: \*\*PASS\*\*' '!\(exit 0\)' \
  -- gcase sinp GATE_STUB_OUT_apimock='verdict: PASS' "GATE_STUB_OUT_apimock_standin=$(printf '  STAND-IN (OpcenterConnector) endpoint rest:OpcenterConnector.Q: 1 requests answered\nstand-in endpoints 1 · requests answered 1')"
ctl gate-standin-unreadable-catch 2 'Overall: \*\*INVALID\*\*' 'apimock\.py standin --state .* failed \(rc 2' '!Overall: \*\*PASS' -- gcase siu GATE_STUB_RC_apimock_standin=2 GATE_STUB_OUT_apimock_standin='apimock: no inventory.json'
ctl gate-standin-fail-wins-catch 1 'Overall: \*\*FAIL\*\*' '\| 6 \| logdiff \| FAIL \|' '!Overall: \*\*PASS' -- gcase sif GATE_STUB_RC_logdiff=1 "GATE_STUB_OUT_apimock_standin=$SI1"
# without APIMOCK nothing is stood in: a clean gate stays plain PASS, exit 0, and the driver never asks apimock.py
ctl gate-no-apimock-plain-pass 0 'Overall: \*\*PASS\*\* \(exit 0\)' '\| 12 \| apis \| NOT RUN \| - \| not configured.*\(optional rung\)' '!Overall: .*stand-in|^ON STAND-IN|STAND-IN \(' -- gcase noam APIMOCK=
ctl gate-no-apimock-not-asked-pass 0 'not asked' -- sh -c "! grep -q '^apimock' $GI/stub-noam.log && echo 'not asked'"

# E2E-8: bin/action_inventory.py, every clickable action of the old model (the journey denominator). The golden is
# captured from the real Marketplace Opcenter EX Starter Kit 2.1.0 (lib/capture_units.py), never hand-written: the four
# home-page cards of T2R3 HANDWORK row 14, the add-on card, and the Client Configuration grid New button (create-spec).
AI=$T/ai; mkdir -p "$AI"
aimut() {  # aimut NAME DOC WIDGET NEW_TYPE: the golden with one widget's OnClickAction type replaced, built to $T/m/NAME
  python3 - "$FX/actions/t2-home-cards.json" "$AI/$1.json" "$2" "$3" "$4" <<'EOF'
import json, sys
src, out, doc, w, t = sys.argv[1:]
fx = json.load(open(src)); hit = []
def walk(x):
    if isinstance(x, dict):
        if x.get("Name") == w and isinstance(x.get("OnClickAction"), dict):
            x["OnClickAction"]["$Type"] = t; hit.append(1)
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
for u in fx["units"]:
    if u["data"].get("Name") == doc:
        walk(u["data"])
assert len(hit) == 1, f"want one {doc}.{w} in the golden, found {len(hit)}"
json.dump(fx, open(out, "w"))
EOF
  python3 "$here/lib/capture_units.py" build "$AI/$1.json" "$T/m/$1" > /dev/null
}
if python3 -c 'import bson' 2>/dev/null; then
  python3 "$here/lib/capture_units.py" build "$FX/actions/t2-home-cards.json" "$T/m/t2cards" > /dev/null
  ctl action-inventory-hw14-cards-pass 0 \
    '^StarterKit\.Home_Gallery\.container1 \[DivContainer\] open-page -> open-page StarterKit\.Contents .*as Administrator: menu Responsive: Home -> StarterKit\.Home_Web -> click container1$' \
    '^StarterKit\.Home_Gallery\.container5 \[DivContainer\] nanoflow -> open-page StarterKit\.ACT_Open_HowTo \| roles User \| as User: home Responsive \(User\) -> StarterKit\.Home_Web -> click container5$' \
    '^StarterKit\.Home_Gallery\.container9 \[DivContainer\] open-page -> open-page StarterKit\.LinksAndInfos .*click container9$' \
    '^StarterKit\.Home_Gallery\.container13 \[DivContainer\] open-page -> open-page StarterKit\.Widgets .*click container13$' \
    '^StarterKit\.Home_Gallery\.container14 .*UNKNOWN flow EXFN_Authentication\.Nav_ClientConfiguration_Overview is not in the model \(module EXFN_Authentication unreadable: protected add-on\)' \
    '^actions 9 found · by kind create 1, delete 1, open-page 5, unknown 2 · todo 4 by reason no-click-path 4 · unknown 5 ' \
    -- python3 $B/action_inventory.py $T/m/t2cards/App.mpr
  # create-spec.json's newButton1 is a Mendix 9 grid New button: no Action key, entity and page on the widget itself.
  # Only an add-on microflow opens its page, so the path is unknown, never reported as absent.
  ctl action-inventory-newbutton-pass 0 \
    '^OpcenterEXFN_VendorDesignSystem\.Snippet_Configuration\.newButton1 \[GridNewButton\] create -> create OpcenterEXFN_VendorDesignSystem\.ClientConfiguration_NewEdit .*the click path is unknown, not absent' \
    'ClientConfiguration_NewEdit\.actionButton1 .*UNKNOWN part of the flow is not in the model: EXFN_Authentication\.ACT_ClientConfiguration_NewEdit \(kind is a lower bound\)' \
    '"summary_line": "actions 9 found' -- sh -c "python3 $B/action_inventory.py $T/m/t2cards/App.mpr --out $AI/a.json && cat $AI/a.json"
  # B4T2-14: a no-click-path plan row is UNREACHABLE (PASS*, its own count) only with checked evidence. On this real
  # golden the protected EXFN_Authentication add-on opens ClientConfiguration_Overview (create-save walks it on the
  # field run): an add-on that names any document on the way to the page refuses it; the add-on files are stand-ins
  UR=$T/unr; mkdir -p $UR/gen $UR/w/after $UR/addon-opens $UR/addon-silent
  python3 $B/action_inventory.py $T/m/t2cards/App.mpr --out $UR/a.json > /dev/null
  python3 -c "import json; d=json.load(open('$UR/a.json')); [x.update(todo=['no-click-path (a non-click caller reaches it: entry_reach)']) for x in d['actions']]; json.dump(d, open('$UR/a-caller.json', 'w'))
d=json.load(open('$UR/a.json')); d['model']='$UR/gone.mpr'; json.dump(d, open('$UR/a-nomodel.json', 'w'))"
  echo '{"skipped": [{"id": "act-OpcenterEXFN_VendorDesignSystem.Snippet_Configuration.newButton1", "action": "OpcenterEXFN_VendorDesignSystem.Snippet_Configuration.newButton1", "why": "action todo: no-click-path"}, {"id": "act-OpcenterEXFN_VendorDesignSystem.ClientConfiguration_NewEdit.actionButton1", "action": "OpcenterEXFN_VendorDesignSystem.ClientConfiguration_NewEdit.actionButton1", "why": "action todo: no-click-path"}]}' > $UR/gen/plan.json
  echo '{"journeys": {}, "roles": {}}' > $UR/w/after/summary.json
  printf 'EXFN_Authentication.Nav_ClientConfiguration_Overview -> OpcenterEXFN_VendorDesignSystem.ClientConfiguration_Overview\n' > $UR/addon-opens/flows.txt
  printf 'EXFN_Authentication.Login -> EXFN_Authentication.Home\n' > $UR/addon-silent/flows.txt
  ure() { printf 'act-OpcenterEXFN_VendorDesignSystem.* UNREACHABLE %s # control\n' "$2" > $UR/$1.txt; }
  ure ev-ok "$UR/a.json EXFN_Authentication=addon-silent"; ure ev-opens "$UR/a.json EXFN_Authentication=addon-opens"
  ure ev-noaddon "$UR/a.json"; ure ev-caller "$UR/a-caller.json EXFN_Authentication=addon-silent"; ure ev-nomodel "$UR/a-nomodel.json EXFN_Authentication=addon-silent"
  RJU="python3 $B/run_journeys.py $UR/gen --label after --work $UR/w --rejudge"
  ctl journeys-unreachable-pass 0 '^  UNREACHABLE act-OpcenterEXFN_VendorDesignSystem\.Snippet_Configuration\.newButton1 +UNREACHABLE: actions\.json: no entry point reaches .*named in EXFN_Authentication \(1 files\)' \
    '^journeys: 0 PASS, 0 FAIL, 0 INVALID, 2 PASS\* \(unreachable in the OLD UI, evidence checked\)$' '^actions 9 found .*coverage 0/9 \(0%\) · 2 todo unreachable in the OLD UI \(evidenced, PASS\*\)$' \
    -- $RJU --actions $UR/a.json --baseline-evidence $UR/ev-ok.txt
  ctl journeys-unreachable-addon-opens-catch 3 'ClientConfiguration_NewEdit\.actionButton1 .*UNREACHABLE refused, .*EXFN_Authentication names OpcenterEXFN_VendorDesignSystem\.ClientConfiguration_Overview \(flows\.txt\), which leads to OpcenterEXFN_VendorDesignSystem\.ClientConfiguration_NewEdit' \
    '^journeys: 0 PASS, 0 FAIL, 2 INVALID$' -- $RJU --actions $UR/a.json --baseline-evidence $UR/ev-opens.txt
  ctl journeys-unreachable-no-addon-catch 3 'UNREACHABLE refused, .*give EXFN_Authentication=<its project.mpr' '!PASS\* \(unreachable' -- $RJU --actions $UR/a.json --baseline-evidence $UR/ev-noaddon.txt
  ctl journeys-unreachable-no-actions-catch 3 'UNREACHABLE refused, .*--actions .*none given' '!PASS\* \(unreachable' -- $RJU --baseline-evidence $UR/ev-ok.txt
  ctl journeys-unreachable-other-inventory-catch 3 'UNREACHABLE refused, .*a-caller\.json: not the --actions file' -- $RJU --actions $UR/a.json --baseline-evidence $UR/ev-caller.txt
  ctl journeys-unreachable-caller-catch 3 'UNREACHABLE refused, .*a non-click caller reaches it.*reachable, not dead in the UI' -- $RJU --actions $UR/a-caller.json --baseline-evidence $UR/ev-caller.txt
  ctl journeys-unreachable-no-model-catch 3 'UNREACHABLE refused, .*gone\.mpr: not found\): give model=' -- $RJU --actions $UR/a-nomodel.json --baseline-evidence $UR/ev-nomodel.txt
else
  skip journeys-unreachable-pass 'python3 has no bson (pip install pymongo): the golden model cannot be built'
fi
# journey scope (journey_scope.py): only what is used and reachable counts toward the journeys rung. fixtures/models/scope.json
# is a field app in miniature (Home shows OrderEdit and Custom; Orphan, Orphan_Child, ViaExcluded are dead, CodeOpened is
# opened by Java by name, the generated proxies file names Orphan and must not count); fixtures/scope/ holds its actions,
# localedits and usage. One catch and one pass per class, then the gate effect through gen_journeys --scope and run_journeys.
if python3 -c 'import bson' 2>/dev/null; then
  model scope > /dev/null
  SC=$T/scope; mkdir -p $SC/gen $SC/gen-none $SC/gen-oos $SC/gen-causes $SC/w/after
  JS="python3 $B/journey_scope.py $FX/scope/actions.json --model $T/m/scope/App.mpr --localedits $FX/scope/localedits.json"
  jsmd() { $JS "$@" --md $SC/s.md > /dev/null && cat $SC/s.md; }
  ctl journey-scope-line-pass 0 '^journeys in scope: 4 reachable, 7 out of scope \(unreachable 4, marketplace 2, no-role 1\)$' \
    '^testability work: 3 reachable actions have no click path yet \(record a click path, or test at deploy\)$' '!unused' -- $JS --out $SC/s.json
  ctl journey-scope-unreachable-catch 0 '^- Shop\.Orphan\.btn: no route from any navigation entry' '^- Shop\.Orphan_Child\.btn: no route' \
    '^- Shop\.ViaExcluded\.btn: no route' -- jsmd
  ctl journey-scope-unreachable-pass 0 '!^- Shop\.OrderEdit\.save: ' '!^- Shop\.CodeOpened\.btn: ' '!^- Shop\.Home\.btnA: ' \
    '^- Shop\.CodeOpened\.btn$' -- jsmd
  ctl journey-scope-marketplace-catch 0 '^- Administration\.Account_Overview\.btn: Administration is a Marketplace module the app does not customise \(no local edits\)' \
    '^- MxModelReflection\.MxObject_Overview\.btn: .*edits unknown' -- jsmd
  ctl journey-scope-marketplace-pass 0 '!^- Administration\.Custom\.btn: ' '^- Administration\.Custom\.btn$' '^- UserCommons\.Settings\.btn: no route' \
    '!^- UserCommons\.Settings\.btn: UserCommons is a Marketplace' -- jsmd
  ctl journey-scope-norole-catch 0 '^- Shop\.NoRolePage\.btn: no user role may open the page and run the flow' -- jsmd
  ctl journey-scope-norole-pass 0 '!^- Shop\.OrderEdit\.save: no user role' '!^- Shop\.Home\.btnA: ' -- jsmd
  ctl journey-scope-nopath-testability-catch 0 '^## testability work: reachable, no click path yet \(3\)' '^- Shop\.OrderEdit\.save$' -- jsmd
  ctl journey-scope-usage-catch 0 '^journeys in scope: 1 reachable, 10 out of scope \(unreachable 4, marketplace 2, no-role 1, unused 3\)$' \
    -- $JS --usage $FX/scope/usage.json
  ctl journey-scope-no-model-catch 1 'journey_scope: model .*gone\.mpr: not found' -- python3 $B/journey_scope.py $FX/scope/actions.json --model $SC/gone.mpr
  # the gate: out of scope is INFO, never INVALID; a reachable action with no path stays INVALID; without --scope nothing changes
  $JS --out $SC/s.json > /dev/null
  # click_causes.py: one cause per reachable action without a click path; gen_journeys --causes writes it into the skipped row
  python3 $B/click_causes.py $FX/scope/actions.json --model $T/m/scope/App.mpr --scope $SC/s.json --out $SC/c.json --md $SC/c.md > $SC/c.out 2>&1
  ctl click-causes-line-catch 0 '^click causes: 3 actions without a click path: unknown 3$' -- cat $SC/c.out
  ctl click-causes-nocause-pass 0 '!combobox-change' '!dynamic-name' -- cat $SC/c.md
  python3 $B/gen_journeys.py --actions $FX/scope/actions.json --scope $SC/s.json --causes $SC/c.json --out-dir $SC/gen-causes --roles-with-users Clerk > $SC/gen-causes.out 2>&1
  ctl click-causes-plan-catch 0 'cause unknown: no caller found for Shop\.OrderEdit' -- python3 -c "
import json
[print(x['action'], x['why']) for x in json.load(open('$SC/gen-causes/plan.json'))['skipped']]"
  python3 $B/gen_journeys.py --actions $FX/scope/actions.json --scope $SC/s.json --out-dir $SC/gen --roles-with-users Clerk > $SC/gen.out 2>&1
  python3 $B/gen_journeys.py --actions $FX/scope/actions.json --out-dir $SC/gen-none --roles-with-users Clerk > $SC/gen-none.out 2>&1
  python3 -c "import json; p=json.load(open('$SC/gen/plan.json')); p['skipped']=[]; json.dump(p, open('$SC/gen-oos/plan.json','w'))"
  echo '{"journeys": {}, "roles": {}}' > $SC/w/after/summary.json
  RJS="python3 $B/run_journeys.py"
  python3 -c "
import json
a=json.load(open('$FX/scope/actions.json')); p=json.load(open('$SC/gen-oos/plan.json'))
o={x['action'] for x in p['out_of_scope']}
a['actions']=[x for x in a['actions'] if x['id'] in o]; json.dump(a, open('$SC/oos-actions.json','w'))"
  ctl journey-scope-gen-catch 0 '^actions 11 found · 0 generated · 0 by --create override · 4 not generated by reason no-click-path 4 · 7 out of scope \(marketplace-module 2, no-role 1, unreachable 4\)$' \
    -- cat $SC/gen.out
  ctl journey-scope-gen-none-pass 0 '^actions 11 found · 0 generated · 0 by --create override · 11 not generated by reason no-click-path 11$' '!out of scope \(' -- cat $SC/gen-none.out
  ctl journey-scope-gate-info-pass 0 '^journeys: 0 PASS, 0 FAIL, 0 INVALID, 7 INFO \(covered, unreachable or out of scope, listed only\)$' \
    '^actions 7 found .*coverage 0/0 .*7 out of scope, INFO \(marketplace-module 2, no-role 1, unreachable 4\)$' '!^  INVALID' -- $RJS $SC/gen-oos --label after --work $SC/w --rejudge --actions $SC/oos-actions.json
  ctl journey-scope-gate-nopath-invalid-catch 3 '^  INVALID act-Shop\.OrderEdit\.save ' '^  INVALID act-Shop\.CodeOpened\.btn ' '^  INVALID act-Administration\.Custom\.btn ' \
    '^journeys: 0 PASS, 0 FAIL, 4 INVALID, 7 INFO' '^actions 11 found .*coverage 0/4 ' '!^  INVALID act-Shop\.Orphan\.btn' \
    -- $RJS $SC/gen --label after --work $SC/w --rejudge --actions $FX/scope/actions.json
  ctl journey-scope-gate-without-scope-catch 3 '^journeys: 0 PASS, 0 FAIL, 11 INVALID$' '^actions 11 found .*coverage 0/11 ' '^  INVALID act-Shop\.Orphan\.btn ' '!out of scope' \
    -- $RJS $SC/gen-none --label after --work $SC/w --rejudge --actions $FX/scope/actions.json
else
  skip journey-scope-line-pass 'python3 has no bson (pip install pymongo): the synthetic model cannot be built'
fi
# menu hops (action_inventory.py menu_hops, gen_journeys menuitem, journey-verbs.js menuitem): a layout's menu bar shows a
# menu document; its items open pages. fixtures/models/menuhop.json: Settings and Tools only through the items of Side,
# Orphan through nothing. Without the hop the first two had "no click path" (a field app: 105 of 303).
if python3 -c 'import bson' 2>/dev/null; then
  model menuhop > /dev/null
  MH=$T/menuhop; mkdir -p $MH
  python3 $B/action_inventory.py $T/m/menuhop/App.mpr --out $MH/a.json > $MH/inv.out 2>&1
  python3 -c "
import json
a=json.load(open('$MH/a.json'))
for x in a['actions']:
    if x['path']: x.update(todo=[], action='microflow', kind='no-db-effect', unknown=[], reach_unknown=[])
json.dump(a, open('$MH/g.json','w'))"
  python3 $B/gen_journeys.py --actions $MH/g.json --out-dir $MH/gen --roles-with-users Clerk > $MH/gen.out 2>&1
  MHS="import json,glob
for f in sorted(glob.glob('$MH/gen/journeys/*/*.journey.json')):
    for s in json.load(open(f))['steps']:
        [print(f.split('/')[-1][4:-13], a['do'], a['widget'], a['nth'], a['label']) for a in s['actions'] if a['do'] == 'menuitem']"
  ctl menuhop-path-catch 0 'Shop\.Settings\.saveBtn .*home Responsive -> Shop\.Home -> click sideBar -> Shop\.Settings -> click saveBtn' \
    'Shop\.Tools\.runBtn .*click sideBar -> Shop\.Tools -> click runBtn' -- cat $MH/inv.out
  ctl menuhop-orphan-pass 0 'Shop\.Orphan\.lostBtn .*no path' '!Shop\.Orphan\.lostBtn .*click sideBar' -- cat $MH/inv.out
  ctl menuhop-journey-catch 0 '^Shop\.Settings\.saveBtn menuitem sideBar 0 Settings$' '^Shop\.Tools\.runBtn menuitem sideBar 1 Tools$' \
    '!Orphan' -- python3 -c "$MHS"
  # UPG_PAGE_COMBOS: a master-detail page needs a pick before its content shows; the journey picks first, on that page only
  echo '{"Shop.Settings": "woCombo"}' > $MH/combos.json
  UPG_PAGE_COMBOS=$MH/combos.json python3 $B/gen_journeys.py --actions $MH/g.json --out-dir $MH/genc --roles-with-users Clerk > $MH/genc.out 2>&1
  MHC="import json,glob,sys
for f in sorted(glob.glob(sys.argv[1] + '/journeys/*/*.journey.json')):
    for s in json.load(open(f))['steps']:
        [print(f.split('/')[-1][4:-13], a['do'], a['widget']) for a in s['actions'] if a['do'] == 'combo']"
  ctl pagecombo-pick-catch 0 '^Shop\.Settings\.saveBtn combo woCombo$' '!Tools' -- python3 -c "$MHC" $MH/genc
  ctl pagecombo-off-pass 0 '!combo' -- python3 -c "$MHC" $MH/gen
  # the page step of the LAST hop waits for the combo too (not for the widget that shows only after the pick): without it
  # the step failed on the healthy old app before the pick (SNIP_AnnexReview_VerticalBar, a field app: 6 journeys)
  MHR="import json,glob,sys
for f in sorted(glob.glob(sys.argv[1] + '/journeys/*/*.journey.json')):
    for s in json.load(open(f))['steps']:
        if s['name'].startswith('open Shop.Settings'): print(f.split('/')[-1][4:-13], 'ready', s['ui']['ready'])"
  ctl pagecombo-lasthop-ready-catch 0 '^Shop\.Settings\.saveBtn ready \.mx-name-woCombo$' '!ready \.mx-name-saveBtn' -- python3 -c "$MHR" $MH/genc
  ctl pagecombo-lasthop-off-pass 0 '^Shop\.Settings\.saveBtn ready \.mx-name-saveBtn$' '!woCombo' -- python3 -c "$MHR" $MH/gen
  # D96 UPG_PAGE_PREPS: what a person does on a page before its buttons work (an upload that enables Sign). "actions" run before
  # a click that leaves the page and before the action's own click; "not_for" skips the click that is itself the preparation
  echo '{"Shop.Settings": {"actions": [{"do": "upload", "widget": "fileMgr", "file": "f.pdf"}], "not_for": ["noneSuch"]}}' > $MH/preps.json
  UPG_PAGE_PREPS=$MH/preps.json python3 $B/gen_journeys.py --actions $MH/g.json --out-dir $MH/genp --roles-with-users Clerk > $MH/genp.out 2>&1
  echo '{"Shop.Settings": {"actions": [{"do": "upload", "widget": "fileMgr", "file": "f.pdf"}], "not_for": ["saveBtn"]}}' > $MH/preps-nf.json
  UPG_PAGE_PREPS=$MH/preps-nf.json python3 $B/gen_journeys.py --actions $MH/g.json --out-dir $MH/gennf --roles-with-users Clerk > $MH/gennf.out 2>&1
  echo '{"Shop.Settings": {"actions": [{"do": "upload", "widget": "fileMgr", "file": "f.pdf"}], "only_for": ["otherBtn"]}}' > $MH/preps-of.json
  UPG_PAGE_PREPS=$MH/preps-of.json python3 $B/gen_journeys.py --actions $MH/g.json --out-dir $MH/genof --roles-with-users Clerk > $MH/genof.out 2>&1
  MHP="import json,glob,sys
for f in sorted(glob.glob(sys.argv[1] + '/journeys/*/*.journey.json')):
    for s in json.load(open(f))['steps']:
        [print(f.split('/')[-1][4:-13], a['do'], a['widget'], a['file']) for a in s['actions'] if a['do'] == 'upload']"
  ctl pagepreps-run-catch 0 '^Shop\.Settings\.saveBtn upload fileMgr f\.pdf$' '!Tools' -- python3 -c "$MHP" $MH/genp
  ctl pagepreps-off-pass 0 '!upload' -- python3 -c "$MHP" $MH/gen
  ctl pagepreps-not-for-pass 0 '!upload' -- python3 -c "$MHP" $MH/gennf
  ctl pagepreps-only-for-pass 0 '!upload' -- python3 -c "$MHP" $MH/genof
  # UPG_UPLOAD_FILE: the file an upload field takes (default upg-seed.jpeg), for a field that only accepts a PDF
  ctl upload-file-env-catch 0 "^\[\{'do': 'upload', 'widget': 'fileManager1', 'file': 'sample.pdf'\}\] None None$" \
    -- env UPG_UPLOAD_FILE=sample.pdf python3 -c "import sys; sys.path.insert(0, '$B'); import gen_journeys as g; print(*g.fill_field({'widget': 'fileManager1', 'input': 'file', 'attr_type': {'type': 'none'}}, 1, 'x'))"
  # D97 mission_pick.py: a task page shows the widgets of ONE mission type at ONE status; the journey opens the type's row of the
  # list (nth) instead of the first row, then answers the "release the current Task?" dialog (optional). A journey that does
  # not click the list is left alone; --status N drops the journeys of other statuses.
  MP=$T/mpick; mkdir -p $MP/j/R $MP/o/R
  echo '{"list": "TaskList", "types": ["MOVE", "WAIT", "TEST"], "groups": {}, "open": "OpenBtn"}' > $MP/m.json
  python3 -c "
import json
def j(i, shown, lst=True):
    acts = [{'do': 'row', 'widget': 'TaskList', 'nth': 0}] if lst else [{'do': 'click', 'widget': 'x'}]
    return {'id': i, 'steps': [{'name': 'a', 'actions': acts}, {'name': 'b', 'actions': [{'do': 'menuitem', 'widget': 'OpenBtn', 'nth': 0}], 'shown_if': shown}]}
for d in ('j', 'o'):
    json.dump(j('act-A.waitBtn', ['g: \$Mission/Missiontype = MissionsModule.ENUM_MissionType.WAIT) and \$Mission/TaskStatus = 0']), open('$MP/%s/R/act-A.waitBtn.journey.json' % d, 'w'))
    json.dump(j('act-A.doneBtn', ['g: (\$Mission/Missiontype = M.ENUM_MissionType.TEST) and \$Mission/TaskStatus = 2']), open('$MP/%s/R/act-A.doneBtn.journey.json' % d, 'w'))
    json.dump(j('act-A.plainBtn', [], lst=False), open('$MP/%s/R/act-A.plainBtn.journey.json' % d, 'w'))
"
  python3 $B/mission_pick.py $MP/j $MP/m.json > $MP/pick.out 2>&1
  python3 $B/mission_pick.py $MP/o $MP/m.json --status 0 > $MP/pick0.out 2>&1
  MPS="import json,glob,sys
for f in sorted(glob.glob(sys.argv[1] + '/R/*.json')):
    j = json.load(open(f)); r = [a for s in j['steps'] for a in s['actions'] if a.get('do') == 'row']
    c = [a for s in j['steps'] for a in s['actions'] if a.get('do') == 'confirm']
    print(j['id'], 'nth', r[0]['nth'] if r else None, 'confirm', len(c), j.get('_mission'))"
  ctl missionpick-row-catch 0 "^act-A.waitBtn nth 1 confirm 1 .*'type': 'WAIT', 'status': 0" "^act-A.doneBtn nth 2 confirm 1 .*'type': 'TEST', 'status': 2" -- python3 -c "$MPS" $MP/j
  ctl missionpick-no-list-pass 0 "^act-A.plainBtn nth None confirm 0 None$" -- python3 -c "$MPS" $MP/j
  ctl missionpick-status-filter-pass 0 "^act-A.waitBtn nth 1" '!doneBtn' -- python3 -c "$MPS" $MP/o
  # D94 UPG_NAME_HOPS: an action only reached through a flow run BY NAME (cause dynamic-name) has no click path; a rule names the
  # clicks that make the app run it (a field app: 187 buttons on the Task execution page). name_hops builds the path from a donor.
  NHP="import sys; sys.path.insert(0, '$B'); import gen_journeys as g
donor = {'id': 'd', 'path': [{'entry': 'home'}, {'page': 'Shop.Home'}, {'click': 'x', 'on': 'Shop.Home'}]}
rule = [{'flow': 'Shop.ShowTask', 'pages': ['Shop.Task'], 'entry_of': 'd', 'hops': [{'click': 'card', 'on': 'Shop.Home', 'id': 'h1'}, {'click': 'open', 'on': 'Shop.Home', 'id': 'h2'}]}]
def run(cause, via):
    x = {'id': 'a', 'widget': 'go', 'host': 'Shop.Task', 'action': 'microflow', 'via_pages': via, 'roles': ['Clerk'], 'path': [], 'todo': ['no-click-path: x']}
    y = g.name_hops(x, cause, rule, {'d': donor})
    print(cause and cause['cause'], via, [h.get('click') or h.get('page') or h.get('entry') for h in y['path']], y['todo'])
run({'cause': 'dynamic-name', 'detail': 'flow Shop.ShowTask'}, ['Shop.Task'])
run({'cause': 'dynamic-name', 'detail': 'flow Shop.Other'}, ['Shop.Task'])
run({'cause': 'dynamic-name', 'detail': 'flow Shop.ShowTask'}, ['Shop.Elsewhere'])
run({'cause': 'other', 'detail': 'flow Shop.ShowTask'}, ['Shop.Task'])"
  ctl namehops-path-catch 0 "^dynamic-name \['Shop.Task'\] \['home', 'Shop.Home', 'card', 'Shop.Home', 'open', 'Shop.Home', 'go'\] \[\]$" -- python3 -c "$NHP"
  ctl namehops-other-flow-pass 0 "^dynamic-name \['Shop.Task'\] \[\] \['no-click-path: x'\]$" -- python3 -c "$NHP"
  ctl namehops-other-page-pass 0 "^dynamic-name \['Shop.Elsewhere'\] \[\] \['no-click-path: x'\]$" -- python3 -c "$NHP"
  ctl namehops-other-cause-pass 0 "^other \['Shop.Task'\] \[\] \['no-click-path: x'\]$" -- python3 -c "$NHP"
  python3 $B/run_journeys.py x --label x --work $MH --patch-engine $MH/engine-copy > $MH/patch.out 2>&1
  ctl menuhop-engine-verb-pass 0 "case 'menuitem'" 'V\.menuitem\(page' -- sh -c "grep -h \"case 'menuitem'\\|V.menuitem(page\" $MH/engine-copy/*.js"
else
  skip menuhop-path-catch 'python3 has no bson (pip install pymongo): the synthetic model cannot be built'
fi
# BT-4: an app with no sign-out UI. The sign-out todo is INVALID unless a NO-SIGNOUT line holds: the plan row is the generator's
# own todo AND the OLD model has no sign-out item or button anywhere. base has none (pass); guard has a menu item that signs
# out (catch: the app has one, write the journey); a todo the generator wrote for an unreadable add-on menu is no proof.
NS=$T/nosignout; mkdir -p $NS/gen $NS/w/after
echo '{"journeys": [], "todo": [{"id": "sign-out", "why": "no tested role has a sign-out item in its menu or home layout: write the sign-out journey by hand. Layout menus looked at: Home: L.menu (profile Responsive): 4 items, none signs out"}]}' > $NS/gen/plan.json
mkdir -p $NS/gen-addon; echo '{"journeys": [], "todo": [{"id": "sign-out", "why": "no tested role has a sign-out item in its menu or home layout: write the sign-out journey by hand. Layout menus looked at: L.menu (menu X.Menu): menu document not in the model (unreadable add-on module?)"}]}' > $NS/gen-addon/plan.json
echo '{"journeys": {}, "roles": {}}' > $NS/w/after/summary.json
nse() { printf 'sign-out NO-SIGNOUT %s # control\n' "$2" > $NS/$1.txt; }
nse ev-base "$(model base)/App.mpr"; nse ev-guard "$(model guard)/App.mpr"; nse ev-gone "$NS/gone.mpr"
RJN() { python3 $B/run_journeys.py $NS/$1 --label after --work $NS/w --rejudge --baseline-evidence $NS/$2.txt; }
ctl journeys-no-signout-pass 0 '^  UNREACHABLE sign-out +NO-SIGNOUT: no page, layout, snippet, menu or navigation profile of App\.mpr has a sign-out item' \
  '^journeys: 0 PASS, 0 FAIL, 0 INVALID, 1 PASS\* \(unreachable in the OLD UI, evidence checked\)$' -- RJN gen ev-base
ctl journeys-no-signout-has-one-catch 3 'sign-out .*NO-SIGNOUT refused|UNREACHABLE refused, .*NO-SIGNOUT: Shop\.User_Menu: menu item Account > Sign out signs out \(action' '!PASS\* \(unreachable' -- RJN gen ev-guard
ctl journeys-no-signout-unreadable-menu-catch 3 'UNREACHABLE refused, .*the todo lists a menu the model cannot read' '!PASS\* \(unreachable' -- RJN gen-addon ev-base
ctl journeys-no-signout-no-model-catch 3 'UNREACHABLE refused, .*gone\.mpr is not readable' '!PASS\* \(unreachable' -- RJN gen ev-gone
# BT-12: no free-standing create. ok: every create is dead in the UI or needs a row; catch: one has a plain click path
mkdir -p $NS/gen-cs
python3 - $NS <<'PYEOF'
import json, sys
ns = sys.argv[1]
mk = lambda i, todo=None, path=None: {"id": i, "kind": "create", "todo": todo or [], "path": path or []}
plain = [{"entry": "menu"}, {"page": "S.P"}, {"click": "newButton"}]
rowc = [{"entry": "menu"}, {"page": "S.P"}, {"click": "c1", "row": "grid1", "row_only": True}]
cond = [{"entry": "menu"}, {"page": "S.P"}, {"click": "b3", "shown_if": ["b3: S.W.State in ['A']"]}]
dead = ["no-click-path (no entry point reaches it: entry_reach)"]
for n, acts in (("ok", [mk("S.D.b1", dead), mk("S.R.c1", None, rowc), mk("S.C.b3", None, cond)]),
                ("plain", [mk("S.D.b1", dead), mk("S.P.newButton", None, plain)])):
    json.dump({"actions": acts}, open(f"{ns}/a-{n}.json", "w"))
PYEOF
echo '{"journeys": [], "todo": [{"id": "create-save", "why": "no --create spec: write one core create-and-save spec per app at baseline (widget names are app-specific)"}]}' > $NS/gen-cs/plan.json
python3 -c "import json; d=json.load(open('$NS/a-ok.json')); d['note']='another inventory'; json.dump(d, open('$NS/a-ok2.json', 'w'))"
printf 'create-save NO-CREATE %s/a-ok.json # control\n' $NS > $NS/ev-cs-ok.txt; printf 'create-save NO-CREATE %s/a-plain.json # control\n' $NS > $NS/ev-cs-plain.txt
RJC() { python3 $B/run_journeys.py $NS/gen-cs --label after --work $NS/w --rejudge --actions $NS/$1 --baseline-evidence $NS/$2; }
ctl journeys-no-create-pass 0 '^  UNREACHABLE create-save +NO-CREATE: actions\.json has 3 create action\(s\): 1 dead in the UI, 2 only on an existing row' '^journeys: 0 PASS, 0 FAIL, 0 INVALID, 1 PASS\* \(unreachable' -- RJC a-ok.json ev-cs-ok.txt
ctl journeys-no-create-plain-catch 3 'UNREACHABLE refused, .*NO-CREATE: S\.P\.newButton is a create with a plain click path' '!PASS\* \(unreachable' -- RJC a-plain.json ev-cs-plain.txt
ctl journeys-no-create-other-inventory-catch 3 'UNREACHABLE refused, .*a-ok\.json: not the --actions file' '!PASS\* \(unreachable' -- RJC a-ok2.json ev-cs-ok.txt
# the pipeline hands baseline-evidence.txt to the basewalk and the after-journeys runs, not only to the gate (else the line is never read)
ctl pipeline-baseline-evidence-wired-catch 0 'basewalk 1' 'afterjourneys 1' -- sh -c "awk '/^step_basewalk\\(\\)/{f=\"basewalk\"} /^step_journeys\\(\\)/{f=\"afterjourneys\"} /^step_diff\\(\\)|^# diff:|^heal_drop\\(\\)/{f=\"\"} f&&/--baseline-evidence/{n[f]++} END{print \"basewalk\", n[\"basewalk\"]+0; print \"afterjourneys\", n[\"afterjourneys\"]+0}' $here/../bin/cloud/upgrade-pipeline.sh"
if python3 -c 'import bson' 2>/dev/null; then
  # catch: a card whose action is removed drops out of the count (the denominator follows the model) ...
  aimut noaction Home_Gallery container1 'Forms$NoAction'
  ctl action-inventory-noaction-catch 0 '^actions 8 found' '!Home_Gallery\.container1 ' 'Home_Gallery\.container5 ' -- python3 $B/action_inventory.py $T/m/noaction/App.mpr
  # ... and an action type the tool does not know is listed as unknown with a todo, never dropped
  aimut futureaction Home_Gallery container1 'Forms$FutureClientAction'
  ctl action-inventory-unknown-type-catch 0 '^StarterKit\.Home_Gallery\.container1 \[DivContainer\] unknown -> unknown .*TODO unknown-action: Forms\$FutureClientAction' 'action type Forms\$FutureClientAction is not known' '^actions 9 found .*unknown 3' -- python3 $B/action_inventory.py $T/m/futureaction/App.mpr
  # E2E-10: gen_journeys.py --actions, one journey per action without a todo, walked as the recorded role. Every
  # action is counted: generated + --create override + skipped (with its reason) = found, never silently dropped.
  GAJ="python3 $B/gen_journeys.py --actions $AI/a.json"
  ctl gen-actions-cards-pass 0 '^actions 9 found · 5 generated · 0 by --create override · 4 not generated by reason no-click-path 4$' \
    '^5 journeys, .*4 skipped' -- $GAJ --out-dir $T/gen-act
  ctl gen-actions-walk-pass 0 '"persona": "Administrator"' '"do": "nav"' '"item": "Home"' '"ready": "\.mx-name-container1"' '"do": "click"' '"widget": "container1"' '"_guard": "StarterKit\.Contents: no landing widget' \
    -- cat $T/gen-act/journeys/Administrator/act-StarterKit.Home_Gallery.container1.journey.json
  ctl gen-actions-role-pass 0 'act-StarterKit\.Home_Gallery\.container5\.journey\.json' -- ls $T/gen-act/journeys/User
  ctl gen-actions-todo-skipped-catch 0 "skipped act-OpcenterEXFN_VendorDesignSystem\.Snippet_Configuration\.newButton1 \['no-click-path'\] action todo: no-click-path" '^skipped 4$' \
    -- python3 -c "import json; s=json.load(open('$T/gen-act/plan.json'))['skipped']; [print('skipped', e['id'], e['reasons'], e['why']) for e in s]; print('skipped', len(s))"
  # catch: a todo added to one action turns its journey into a skipped entry; the count still follows the model
  python3 -c "import json; d=json.load(open('$AI/a.json')); [a.update(todo=['combobox: mutant']) for a in d['actions'] if a['id'].endswith('.container1')]; json.dump(d, open('$AI/a-todo.json', 'w'))"
  ctl gen-actions-mutant-todo-catch 0 '^actions 9 found · 4 generated · 0 by --create override · 5 not generated by reason combobox 1, no-click-path 4$' \
    -- sh -c "python3 $B/gen_journeys.py --actions $AI/a-todo.json --out-dir $T/gen-act-todo; ls $T/gen-act-todo/journeys/Administrator"
  ctl gen-actions-mutant-todo-gone-catch 1 -- test -e $T/gen-act-todo/journeys/Administrator/act-StarterKit.Home_Gallery.container1.journey.json
  ctl gen-actions-no-user-catch 0 '^actions 9 found · 1 generated .*no-user 4' -- $GAJ --out-dir $T/gen-act-nouser --roles-with-users User
  ctl gen-actions-no-user-why-catch 0 'no test user for role Administrator' -- cat $T/gen-act-nouser/plan.json
  # the T2R3 create-spec (copied from the run branch) walks newButton1 + the form's actionButton1: it wins per action
  ctl gen-actions-override-pass 0 '^actions 9 found · 5 generated · 2 by --create override · 2 not generated by reason no-click-path 2$' \
    -- $GAJ --out-dir $T/gen-act-ov --create $FX/actions/t2r3-create-spec.json
  ctl gen-actions-override-closes-pass 0 "closes \['act-OpcenterEXFN_VendorDesignSystem\.Snippet_Configuration\.newButton1', 'act-OpcenterEXFN_VendorDesignSystem\.ClientConfiguration_NewEdit\.actionButton1'\]" 'covered .*newButton1 create-save' \
    -- python3 -c "import json; print('closes', json.load(open('$T/gen-act-ov/journeys/Administrator/create-save.journey.json'))['closes']); [print('covered', c['id'], c['closed_by']) for c in json.load(open('$T/gen-act-ov/plan.json'))['covered']]"
  # E2E-11 link: run_journeys counts coverage by each journey's "action" / "covers" (raw action ids). Before the r7
  # integration the generator wrote only "_action" / "closes" (act- ids), so every action stayed ungenerated (G=0).
  JSL="import sys,json; sys.path.insert(0,'$B'); import run_journeys as r; l=r.journey_set(sys.argv[1])['links']; [print(k, v) for k, v in sorted(l.items())]; print('linked', sum(1 for v in l.values() if v))"
  ctl gen-actions-coverage-link-pass 0 "^act-StarterKit\.Home_Gallery\.container1 \['StarterKit\.Home_Gallery\.container1'\]" \
    "^create-save \['OpcenterEXFN_VendorDesignSystem\.ClientConfiguration_NewEdit\.actionButton1', 'OpcenterEXFN_VendorDesignSystem\.Snippet_Configuration\.newButton1'\]" '^linked 6$' \
    -- python3 -c "$JSL" $T/gen-act-ov
  # catch: a generated journey without the link is counted as linking nothing
  rm -rf $T/gen-act-nolink && cp -r $T/gen-act-ov $T/gen-act-nolink && python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop('action'); json.dump(d, open(p,'w'))" $T/gen-act-nolink/journeys/Administrator/act-StarterKit.Home_Gallery.container1.journey.json
  ctl gen-actions-coverage-link-catch 0 '^act-StarterKit\.Home_Gallery\.container1 \[\]$' '^linked 5$' -- python3 -c "$JSL" $T/gen-act-nolink
  ctl gen-actions-override-nomatch-catch 0 'warning: create-save: the --create spec matches no action in --actions' '0 by --create override' -- $GAJ --out-dir $T/gen-act-nm --create $FX/journeys/create-spec.json
  # the home / menu / sign-out journeys of an impact map are byte-identical with and without --actions
  (cd / && $GJ --out-dir $T/gen-nav-act --roles-with-users Admin,Clerk --actions $AI/a.json > /dev/null 2>&1)
  ctl gen-actions-impact-unchanged-pass 0 '^same$' -- sh -c "diff -r $G/journeys $T/gen-nav-act/journeys > /dev/null && echo same || diff -r $G/journeys $T/gen-nav-act/journeys"
  # B4T2-11, B4N1-8: a widget on a tab page not shown first gets a tab click in the step that lands on its page. The
  # golden with card container1 (snippet Home_Gallery, on page Home_Web) moved onto tab page 2 of a tab control
  # (Forms$TabControl shape of a real 10.x/11.x model: TabPages list, DefaultPagePointer, ActivePageAttributeRef).
  aitab() {  # aitab NAME DEFAULT_INDEX attr|no: build $T/m/NAME and its actions.json $AI/NAME.json
    python3 - "$FX/actions/t2-home-cards.json" "$AI/$1-units.json" "$2" "$3" <<'EOF'
import base64, hashlib, json, sys
src, out, default, attr = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "attr"
fx = json.load(open(src)); hit = []
bid = lambda k: {"$binary": {"base64": base64.b64encode(hashlib.md5(k.encode()).digest()).decode(), "subType": "00"}}
txt = lambda k, v: {"$ID": bid("tx" + k), "$Type": "Texts$Text", "Items": [{"$numberInt": "3"},
      {"$ID": bid("tr" + k), "$Type": "Texts$Translation", "LanguageCode": "en_US", "Text": v}]}
def walk(x):
    if isinstance(x, dict):
        ws = x.get("Widgets")
        for i, w in enumerate(ws if isinstance(ws, list) else []):
            if isinstance(w, dict) and w.get("Name") == "container1":
                pages = [{"$ID": bid(f"tp{j}"), "$Type": "Forms$TabPage", "Name": f"tabPage9{j}", "Caption": txt(f"tp{j}", c),
                          "ConditionalVisibilitySettings": None, "Widgets": [{"$numberInt": "3"}] + ([w] if j == 1 else [])}
                         for j, c in enumerate(["Overview", "Cards"])]
                ws[i] = {"$ID": bid("tc"), "$Type": "Forms$TabControl", "Name": "tabControl9", "ConditionalVisibilitySettings": None,
                         "TabPages": [{"$numberInt": "3"}] + pages, "DefaultPagePointer": pages[default]["$ID"],
                         "ActivePageAttributeRef": {"$ID": bid("ar"), "$Type": "DomainModels$AttributeRef",
                                                    "Attribute": "StarterKit.Tabs.Active"} if attr else None}
                hit.append(1); return
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
for u in fx["units"]:
    if u["data"].get("Name") == "Home_Gallery":
        walk(u["data"])
assert len(hit) == 1, f"want one Home_Gallery.container1 in the golden, found {len(hit)}"
json.dump(fx, open(out, "w"))
EOF
    python3 "$here/lib/capture_units.py" build "$AI/$1-units.json" "$T/m/$1" > /dev/null
    python3 $B/action_inventory.py $T/m/$1/App.mpr --out $AI/$1.json > /dev/null
  }
  aitab tab1 0 no; aitab tab0 1 no; aitab tabattr 0 attr
  TJ=journeys/Administrator/act-StarterKit.Home_Gallery.container1.journey.json
  TSTEPS="import json,sys; j=json.load(open(sys.argv[1])); [print('step', s['name'], '|', ' '.join(a['do'] + ':' + str(a.get('widget') or a.get('item')) for a in s['actions']), '| ready', s['ui']['ready']) for s in j['steps']]; print('tabs', j.get('_tabs')); print('unchecked', j.get('_tabs_unchecked'))"
  ctl gen-actions-tab-catch 0 '^tabs: 1 journeys with tab steps · 1 tab clicks · 0 uncertain$' '^actions 9 found · 5 generated ' -- python3 $B/gen_journeys.py --actions $AI/tab1.json --out-dir $T/gen-act-tab
  ctl gen-actions-tab-step-pass 0 "^step open StarterKit\.Home_Web via Home > tab 'Cards' \| nav:Home click:tabPage91 \| ready \.mx-name-container1$" "^step open-page 'container1' .*\| click:container1 \| ready" "'tab': 'tabPage91', 'caption': 'Cards', 'control': 'tabControl9'" \
    -- python3 -c "$TSTEPS" $T/gen-act-tab/$TJ
  ctl gen-actions-tab-default-pass 0 '^tabs: 0 journeys with tab steps · 0 tab clicks · 0 uncertain$' -- python3 $B/gen_journeys.py --actions $AI/tab0.json --out-dir $T/gen-act-tab0
  ctl gen-actions-tab-default-nostep-pass 0 '^step open StarterKit\.Home_Web via Home \| nav:Home \| ready' '!tabPage9' -- python3 -c "$TSTEPS" $T/gen-act-tab0/$TJ
  ctl gen-actions-tab-attr-catch 0 '^tabs: 1 journeys with tab steps · 1 tab clicks · 1 uncertain$' -- python3 $B/gen_journeys.py --actions $AI/tabattr.json --out-dir $T/gen-act-taba
  ctl gen-actions-tab-attr-why-pass 0 "'why': 'tab control tabControl9 picks its tab from an attribute or variable: tabPage91 clicked, not proven needed'" 'click:tabPage91' -- python3 -c "$TSTEPS" $T/gen-act-taba/$TJ
  # the page Home_Web has a container1 of its own (not on a tab): only the host snippet's widget answers
  ctl gen-actions-tab-host-catch 0 "^page \(\[\], None\)$" "^host \(\[\{'tab': 'tabPage91', 'caption': 'Cards', 'control': 'tabControl9'\}\], None\)$" \
    -- python3 -c "import sys; sys.path.insert(0,'$B'); import impact_map as I, mprmodel; m=mprmodel.Model.load('$T/m/tab1'); print('page', I.tab_path(m, 'StarterKit.Home_Web', 'container1')); print('host', I.tab_path(m, 'StarterKit.Home_Web', 'container1', host='StarterKit.Home_Gallery'))"
  # the actions model not on this machine (a worker's path): said on stderr, in the plan and per journey, never silent
  python3 -c "import json; d=json.load(open('$AI/tab1.json')); d['model']='/nowhere/original.mpr'; json.dump(d, open('$AI/tab-gone.json', 'w'))"
  ctl gen-actions-tab-unchecked-catch 0 'note: actions model /nowhere/original\.mpr not loaded: tab steps NOT checked' '^tabs: NOT checked, actions model not loaded$' -- python3 $B/gen_journeys.py --actions $AI/tab-gone.json --out-dir $T/gen-act-tabg
  ctl gen-actions-tab-unchecked-journey-catch 0 '^unchecked model not loaded: a widget on a tab page not shown first gets no tab step' '!tabPage91' -- python3 -c "$TSTEPS" $T/gen-act-tabg/$TJ
  ctl gen-actions-tab-actions-model-pass 0 '^tabs: 1 journeys with tab steps · 1 tab clicks · 0 uncertain$' '!NOT checked' -- python3 $B/gen_journeys.py --actions $AI/tab-gone.json --actions-model $T/m/tab1/App.mpr --out-dir $T/gen-act-tabm
  # PR-F30: a process step on a tab page not shown first gets the tab click, and the step before waits for the tab
  # (Purchase Request pipe-22: the Approver's "Assign to me" behind the Task Inbox's "Open tasks" tab FAILed the leg)
  PTJ=$T/proc-tab/journeys/Administrator/proc-p20-01.journey.json
  ctl process-tab-step-pass 0 "^step 1\. Click the \"Contents\" card \| click:tabPage91 click:container1 \| ready" "^step 1\. open Home \| nav:Home \| ready \.mx-name-tabPage91$" \
    -- sh -c "python3 $B/process_journeys.py $FX/processes/cards-tab.md --actions $AI/tab1.json --out-dir $T/proc-tab > /dev/null && python3 -c \"\$0\" $PTJ" "$TSTEPS"
  ctl process-tab-default-catch 0 '!tabPage9' '^step 1\. Click the "Contents" card \| click:container1 \| ready' \
    -- sh -c "python3 $B/process_journeys.py $FX/processes/cards-tab.md --actions $AI/tab0.json --out-dir $T/proc-tab0 > /dev/null && python3 -c \"\$0\" $T/proc-tab0/journeys/Administrator/proc-p20-01.journey.json" "$TSTEPS"
  ctl process-tab-unchecked-catch 0 'note: actions model /nowhere/original\.mpr not loaded: tab steps NOT added' -- python3 $B/process_journeys.py $FX/processes/cards-tab.md --actions $AI/tab-gone.json --out-dir $T/proc-tabg
  # every generated verb is a case of the patched engine's act() and every step has a guard (no unknown verb, no bare step)
  if [ -f ${TOOLKIT_E2E:-$B/../vendor/e2e}/journey-runner.js ]; then
    python3 $B/run_journeys.py x --label x --work $T --patch-engine $T/engine-e2e10 > /dev/null 2>&1
    cat > $T/verbcheck.py <<'EOF'
import glob, json, re, sys
eng = open(sys.argv[1]).read(); act = eng[eng.index("async function act("):]
verbs = set(re.findall(r"case '([a-zA-Z]+)'", act[:act.index("default: throw")]))
bad, n = [], 0
for d in sys.argv[2:]:
    for f in glob.glob(d + "/journeys/*/*.journey.json"):
        j = json.load(open(f)); n += 1
        for s in j["steps"]:
            if not (s.get("name") and isinstance(s.get("actions"), list) and s["ui"].get("ready")): bad.append((f, "step"))
            bad += [(f, a["do"]) for a in s["actions"] if a["do"] not in verbs]
print(f"{n} journeys; verbs {' '.join(sorted(verbs))}; unknown {len(bad)}", bad[:3])
EOF
    ctl gen-actions-verbs-pass 0 '^11 journeys; verbs .*\bconfirm\b.*\brow\b.*; unknown 0 \[\]$' -- python3 $T/verbcheck.py $T/engine-e2e10/journey-runner.js $T/gen-act $T/gen-act-ov
    ctl gen-actions-tab-verbs-pass 0 '^5 journeys; verbs .*; unknown 0 \[\]$' -- python3 $T/verbcheck.py $T/engine-e2e10/journey-runner.js $T/gen-act-tab
    printf '{"id":"x","steps":[{"name":"s","actions":[{"do":"teleport"}],"ui":{"ready":".mx-page"}}]}' > $T/gen-act-ov/journeys/Administrator/bad.journey.json
    ctl gen-actions-verbs-catch 0 "unknown 1 \[\(.*bad\.journey\.json', 'teleport'\)\]" -- python3 $T/verbcheck.py $T/engine-e2e10/journey-runner.js $T/gen-act-ov
    ctl gen-actions-engine-syntax-pass 0 -- node --check $T/engine-e2e10/journey-runner.js
  else for c in verbs-pass verbs-catch engine-syntax-pass tab-verbs-pass; do skip gen-actions-$c "no shared journey engine"; done; fi
else
  for c in hw14-cards-pass newbutton-pass noaction-catch unknown-type-catch; do skip action-inventory-$c "no python bson"; done
  for c in cards-pass walk-pass role-pass todo-skipped-catch mutant-todo-catch mutant-todo-gone-catch no-user-catch no-user-why-catch \
    override-pass override-closes-pass override-nomatch-catch impact-unchanged-pass verbs-pass verbs-catch engine-syntax-pass \
    tab-catch tab-step-pass tab-default-pass tab-default-nostep-pass tab-attr-catch tab-attr-why-pass tab-host-catch \
    tab-unchecked-catch tab-unchecked-journey-catch tab-actions-model-pass tab-verbs-pass; do skip gen-actions-$c "no python bson"; done
fi
# F23 (Purchase Request 10.24, real run): 17 impact todos (task pages, their data-source microflows) stayed INVALID
# though generated action journeys walked them. A todo is closed by the action whose click path walks its page, or
# whose click target is its microflow, or whose walked page (or snippet in it) uses it as a data source. Catches: a
# page off the path, a microflow another button clicks (not a data source), a reference through a non-snippet
TC="python3 $here/todo_closers_control.py"
ctl gen-todo-closers-pass 0 '^page:M\.Task M\.Task\.btnComplete$' '^client_microflow:M\.DS_Task M\.Task\.btnComplete$' '^client_microflow:M\.DS_Owner M\.Task\.btnComplete$' '!OPEN' -- $TC base
ctl gen-todo-closers-offpath-catch 0 '^page:M\.Task OPEN$' '^client_microflow:M\.DS_Owner OPEN$' -- $TC off-path
ctl gen-todo-closers-clicked-ds-catch 0 '^client_microflow:M\.DS_Task OPEN$' '^client_microflow:M\.DS_Owner M\.Task\.btnComplete$' -- $TC clicked-ds
ctl gen-todo-closers-not-snippet-catch 0 '^client_microflow:M\.DS_Owner OPEN$' '^client_microflow:M\.DS_Task M\.Task\.btnComplete$' -- $TC not-snippet
# F21 (Purchase Request 10.24, real run): a debug app held 8080, docker run failed (125) and the build filed "needs
# judgment". runapp.py probes both host ports first; a taken one is an INFRA exit 3, a free one is not reported
PB="import socket, sys; sys.path.insert(0, '$B'); import runapp as r; s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen(); busy = s.getsockname()[1]; f = socket.socket(); f.bind(('127.0.0.1', 0)); free = f.getsockname()[1]; f.close()"
ctl runapp-port-busy-catch 0 '^busy a non-container process$' -- python3 -c "$PB; print('busy', r.port_busy(busy))"
ctl runapp-port-free-pass 0 '^free None$' -- python3 -c "$PB; print('free', r.port_busy(free))"
ctl pipeline-infra-rc-pass 0 '^ +infra_rc "\$rc" quick$' '^  infra_rc "\$rc" "\$1"$' -- grep -E '^ *infra_rc "\$rc"' $B/cloud/upgrade-pipeline.sh
# F22 (Purchase Request 10.24, real run): journeys ran without --actions, so coverage was "no actions.json" on every
# run. The inventory is built from the OLD model and goes to gen_journeys and both run_journeys calls
ctl pipeline-actions-wired-pass 0 'action_inventory\.py" "\$WORK/original\.mpr" --out "\$WORK/actions\.json"' 'gen_journeys\.py.*\$\{act\[@\]' 'e2e-before-picked.*\$\{act\[@\]' 'e2e-after.*\$\{act\[@\]' \
  -- grep -E 'action_inventory\.py|\$\{act\[@\]' $B/cloud/upgrade-pipeline.sh
# T2R3-16b: the pipeline writes users.json (one smoke user per role) for the baseline and the picked walks, and all
# three journey runs read it
ctl pipeline-users-json-pass 0 '^\[ "\$DRY" = 1 \] \|\| write_users' '^\[ -f "\$WORK/users\.json" \] \|\| \[ "\$DRY" = 1 \] \|\| write_users' 'users\.json" .*--work "\$WORK/e2e-base"' 'users\.json" .*--work "\$WORK/e2e-before-picked"' 'users\.json" .*--work "\$WORK/e2e-after"' \
  -- sh -c "grep -E 'write_users \"|--users \"' $B/cloud/upgrade-pipeline.sh | sed 's/^ *//'"
# E2E-10: field values by attribute type; a field whose value the model does not give is unfilled with its reason
GF="import sys, json; sys.path.insert(0, '$B'); import gen_journeys as g"
ctl gen-actions-fill-string-pass 0 "^\[\{'do': 'fill', 'widget': 't1', 'value': 'U-\\$\{RUN_ID\}-3'\}\] Subject None$" -- python3 -c "$GF; print(*g.fill_field({'widget': 't1', 'input': 'text', 'attribute': 'Subject', 'attr_type': {'type': 'String', 'length': 200}}, 3, 'pw'))"
ctl gen-actions-fill-short-catch 0 "^\[\{'do': 'fill', 'widget': 't1', 'value': 'U3'\}\] None None$" -- python3 -c "$GF; print(*g.fill_field({'widget': 't1', 'input': 'text', 'attribute': 'Code', 'attr_type': {'type': 'String', 'length': 5}}, 3, 'pw'))"
ctl gen-actions-fill-password-catch 0 "'value': 'PW'\}\] None None$" '!RUN_ID' -- python3 -c "$GF; print(*g.fill_field({'widget': 'p', 'input': 'text', 'password': True, 'attribute': 'Password', 'attr_type': {'type': 'String'}}, 4, 'PW'))"
ctl gen-actions-fill-enum-pass 0 "'do': 'select', 'widget': 'e', 'match': 'Open'" -- python3 -c "$GF; print(*g.fill_field({'widget': 'e', 'input': 'select', 'attr_type': {'type': 'Enumeration', 'enum_first_caption': 'Open'}}, 7, 'x'))"
ctl gen-actions-fill-reference-pass 0 "'do': 'select', 'widget': 'r', 'first': True" -- python3 -c "$GF; print(*g.fill_field({'widget': 'r', 'input': 'reference', 'attr_type': {}}, 6, 'x'))"
ctl gen-actions-fill-reference-form-catch 0 '^\[\] None reference selector rendered as Form' -- python3 -c "$GF; print(*g.fill_field({'widget': 'r', 'input': 'reference', 'render': 'Form', 'attr_type': {}}, 6, 'x'))"
ctl gen-actions-fill-checkbox-catch 0 '^\[\] None check box left as it is' -- python3 -c "$GF; print(*g.fill_field({'widget': 'c', 'input': 'toggle', 'attr_type': {'type': 'Boolean'}}, 5, 'x'))"
ctl gen-actions-date-custom-pass 0 "^\('15-01-2026 at 12:00', None\)$" -- env JOURNEY_YEAR=2026 python3 -c "$GF; print(g.date_value({'DateFormat': 'Custom', 'Custom': \"dd-MM-yyyy 'at' HH:mm\"}))"
ctl gen-actions-date-custom-catch 0 "token\(s\) QQ not generated" -- python3 -c "$GF; print(g.date_value({'DateFormat': 'Custom', 'Custom': 'dd QQ yyyy'}))"
ctl gen-actions-no-input-catch 2 'give an impact map, --actions actions.json, or both' -- python3 $B/gen_journeys.py --out-dir $T/gen-act-none
ctl gen-actions-not-inventory-catch 2 'no "actions" list \(not an action_inventory\.py --out file\)' -- python3 $B/gen_journeys.py --actions $FX/actions/t2r3-create-spec.json --out-dir $T/gen-act-bad
ctl action-inventory-missing-model-catch 1 'not found' '!^actions ' -- python3 $B/action_inventory.py $AI/none.mpr
printf 'not a sqlite file\n' > "$AI/bad.mpr"
ctl action-inventory-unreadable-model-catch 1 'cannot read|no documents read' '!^actions ' -- python3 $B/action_inventory.py $AI/bad.mpr
# field: the customer model in the repo (Mendix 11): a combobox trigger and an external REST call are todo, with their reason
if [ -f "$CUSTM" ]; then
  ctl field-action-inventory-customer-pass 0 'combobox: the action fires on a change of combobox comboBox1' 'FeedbackModule\.ShareFeedback\.feedback_submit .*external-call: RestCallAction' '^actions 21 found · by kind ' 'todo 16 by reason combobox 2, external-call 1' -- python3 $B/action_inventory.py "$CUSTM"
  # E2E-10 field: the ShareFeedback submit buttons fill Subject / Description and, with the data rung, ask for the run's own row
  python3 $B/action_inventory.py "$CUSTM" --out $AI/cust.json > /dev/null
  ctl field-gen-actions-customer-pass 0 '^actions 21 found · 5 generated · 0 by --create override · 16 not generated by reason combobox 2, external-call 1, no-click-path 14, no-role 1$' \
    -- python3 $B/gen_journeys.py --actions $AI/cust.json --out-dir $T/gen-act-cust --data-rung
  # PR-P5: FeedbackModule.Feedback is a NON-persistable entity (Persistable: false in the model): it has no table, so the
  # own-row check this control used to expect would be rejected ("OQL returned nothing"); the typed value stays, the check is gone
  ctl field-gen-actions-customer-own-row-pass 0 '!"oql"' '!FROM FeedbackModule\.Feedback' '"value": "U-\$\{RUN_ID\}-1"' \
    -- cat $T/gen-act-cust/journeys/User/act-FeedbackModule.ShareFeedback.actionButton4.journey.json
  ctl field-gen-actions-customer-no-rung-catch 0 '!"oql"' '"value": "U-\$\{RUN_ID\}-1"' -- sh -c "python3 $B/gen_journeys.py --actions $AI/cust.json --out-dir $T/gen-act-cust2 > /dev/null; cat $T/gen-act-cust2/journeys/User/act-FeedbackModule.ShareFeedback.actionButton4.journey.json"
else skip field-action-inventory-customer-pass "no $CUSTM"; for c in pass own-row-pass no-rung-catch; do skip field-gen-actions-customer-$c "no $CUSTM"; done; fi
# --- PR-F25: the Purchase Request wizard (pipe-18: 51 of 106 baseline defects had no workflow row to click) ----------
# Dates go one year past generation ("must be in the future"); a combo box is filled, not a todo; a wizard page is
# filled before the hop that leaves it; journeys whose path needs data run in a second pass; confirmed processes are
# compiled by the pipeline. Fixture: the wizard rows of the real Purchase Request inventory (action_inventory.py output)
NY=$(( $(date +%Y) + 1 ))
ctl gen-actions-date-next-year-pass 0 "^\\('1/15/$NY', None\\)$" -- env -u JOURNEY_YEAR python3 -c "$GF; print(g.date_value({'DateFormat': 'Date'}))"
ctl gen-actions-fill-combobox-enum-pass 0 "'do': 'combo', 'widget': 'd', 'match': 'Marketing'" -- python3 -c "$GF; print(*g.fill_field({'widget': 'd', 'input': 'combobox', 'attr_type': {'type': 'Enumeration', 'enum_first_caption': 'Marketing'}}, 7, 'x'))"
ctl gen-actions-fill-combobox-ref-pass 0 "'do': 'combo', 'widget': 'r', 'first': True" '!no proven verb' -- python3 -c "$GF; print(*g.fill_field({'widget': 'r', 'input': 'combobox', 'attr_type': {}}, 7, 'x'))"
WZ=$FX/actions/pr-wizard.json
python3 $B/gen_journeys.py --actions $WZ --out-dir $T/wz --roles-with-users Requester > /dev/null 2>&1
ctl gen-actions-wizard-fill-pass 0 '"widget": "textBox1",' '"do": "combo",' '"widget": "dropDown1",' '"match": "Marketing"' '"value": "1/15/' '"click": "navigationList2"|"widget": "navigationList2"' \
  -- cat $T/wz/journeys/Requester/act-PurchaseApprovals.NewRequest_Step3.actionButton1.journey.json
python3 -c "import json; d=json.load(open('$WZ')); [a.update(kind='open-page') for a in d['actions'] if a['id'].endswith('MyRequests.actionButton2')]; json.dump(d, open('$T/wz-nocreate.json', 'w'))"
ctl gen-actions-wizard-no-create-catch 0 '!"do": "fill"' -- sh -c "python3 $B/gen_journeys.py --actions $T/wz-nocreate.json --out-dir $T/wz2 --roles-with-users Requester > /dev/null 2>&1; python3 -c \"import json; j=json.load(open('$T/wz2/journeys/Requester/act-PurchaseApprovals.NewRequest_Step3.actionButton1.journey.json')); print(json.dumps(j['steps'][:-1]))\""
# data waves: a journey whose path needs a row runs after every role's first pass, as <role>~data
mkdir -p $T/dw/journeys/A $T/dw/journeys/B
printf '{"id":"a1","steps":[]}' > $T/dw/journeys/A/a1.journey.json
printf '{"id":"a2","steps":[],"_path_needs":["a row in DataGrid x"]}' > $T/dw/journeys/A/a2.journey.json
printf '{"id":"b1","steps":[]}' > $T/dw/journeys/B/b1.journey.json
DWC="import sys; sys.path.insert(0, '$B'); import run_journeys as r; from pathlib import Path; print(' | '.join(k + ':' + ','.join(f.name.split('.')[0] for f in fs) for k, _, _, fs in r.data_waves(Path('$T/dw/journeys'), '$T/dw')))"
ctl journeys-data-waves-pass 0 '^A:a1 \| B:b1 \| A~data:a2$' -- python3 -c "$DWC"
printf '{"id":"a2","steps":[]}' > $T/dw/journeys/A/a2.journey.json
ctl journeys-data-waves-none-catch 0 '^A:a1,a2 \| B:b1$' -- python3 -c "$DWC"
# PR-F35: a destructive journey whose path needs data (a delete, a workflow operation) runs after EVERY role's data
# pass, so an admin's Abort cannot take the task a later role's data pass needs (Purchase Request pipe-30)
printf '{"id":"a3","steps":[],"_path_needs":["a workflow"],"_destructive":"x"}' > $T/dw/journeys/A/a3.journey.json
printf '{"id":"b2","steps":[],"_path_needs":["a task"]}' > $T/dw/journeys/B/b2.journey.json
ctl journeys-data-waves-last-pass 0 '^A:a1,a2 \| B:b1 \| B~data:b2 \| A~last:a3$' -- python3 -c "$DWC"
rm -f $T/dw/journeys/A/a3.journey.json $T/dw/journeys/B/b2.journey.json
# PR-P4: a journey whose action wipes or reseeds shared data (scope identity / delete-all / reimport) runs after every
# other pass, alone in its own runner process, with or without needs ("Reset" has none and ran first, as the Administrator,
# before every other role); a row-scope delete keeps its old place. Seeding report 1
printf '{"id":"r1","steps":[],"_scope":"reimport","resetsData":true}' > $T/dw/journeys/A/r1.journey.json
printf '{"id":"r2","steps":[],"_scope":"identity","_path_needs":["a row"]}' > $T/dw/journeys/B/r2.journey.json
printf '{"id":"r3","steps":[],"_scope":"row"}' > $T/dw/journeys/B/r3.journey.json
ctl journeys-data-waves-destructive-pass 0 '^A:a1,a2 \| B:b1,r3 \| A~destructive1:r1 \| B~destructive1:r2$' -- python3 -c "$DWC"
rm -f $T/dw/journeys/A/r1.journey.json $T/dw/journeys/B/r2.journey.json $T/dw/journeys/B/r3.journey.json
ctl journeys-data-wave-key-pass 0 '^True True False False$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r; print(r.data_wave('A~data'), r.data_wave('A~destructive2'), r.data_wave('A'), r.data_wave('A~data2'))"
ctl journeys-scopes-agree-pass 0 '^True True$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r, gen_journeys as g, action_inventory as a; print(r.DESTRUCTIVE_SCOPES == g.DESTRUCTIVE_SCOPES, a.SCOPES[:3] == r.DESTRUCTIVE_SCOPES)"
# the main ratio leaves them out and says so; the destructive line counts them apart; a login that fails after one is CONTAMINATED
CVD="import sys; sys.path.insert(0, '$B'); import run_journeys as r; acts = {i: {} for i in 'abc'}
cs = {'sha256': 'x', 'links': {'j1': ['a'], 'j2': ['b'], 'j3': ['c']}}
if len(sys.argv) > 1: cs['destructive'] = ['j3']
js = {'j1': {'verdict': 'PASS'}, 'j2': {'verdict': 'FAIL'}, 'j3': {'verdict': 'FAIL'}}
o = r.coverage(js, {}, cs, None, acts, None, [], False); print('G', o['G'], 'B', o['B'], 'D', o['D']); print(o['line'])"
ctl journeys-coverage-destructive-apart-pass 0 '^G 2 B 1 D 1$' 'coverage 1/2 \(50%\) · 1 destructive run apart \(own line\)$' -- python3 -c "$CVD" apart
ctl journeys-coverage-destructive-none-catch 0 '^G 3 B 1 D 2$' 'coverage 1/3 \(33%\)$' '!destructive' -- python3 -c "$CVD"
# a destructive journey that fails on the OLD app is judged like any other: evidence needed, else INVALID; with a checked
# OLD-APP line it is a baseline defect; one that PASSed on the old app is no defect (a REGRESSION stays a REGRESSION)
CVE="import sys, os; sys.path.insert(0, '$B'); import run_journeys as r; acts = {i: {} for i in 'abc'}
cs = {'sha256': 'x', 'links': {'j1': ['a'], 'j2': ['b'], 'j3': ['c']}, 'destructive': ['j3']}
bef = {'j1': {'verdict': 'PASS'}, 'j2': {'verdict': 'PASS'}, 'j3': {'verdict': sys.argv[1]}}
js = {'j1': {'verdict': 'PASS'}, 'j2': {'verdict': 'PASS'}, 'j3': {'verdict': 'FAIL'}}
open(sys.argv[2], 'w').write('old app error\n')
ev = [('j3', 'OLD-APP', [sys.argv[2]], '', 1)] if len(sys.argv) > 3 else []
o = r.coverage(js, bef, cs, cs, acts, None, ev, True)
print('defects', o['defects']); print('invalid', [i for i in o['invalid'] if 'evidence' in i])"
ctl journeys-coverage-destructive-evidence-pass 0 "^defects \{'j3': \('OLD-APP', 'OLD-APP: old-app-d.log" '^invalid \[\]$' -- python3 -c "$CVE" FAIL $T/old-app-d.log with
ctl journeys-coverage-destructive-no-evidence-catch 0 "^defects \{'j3': \(None, 'no evidence'\)\}" 'invalid \[.1 baseline defects without evidence' -- python3 -c "$CVE" FAIL $T/old-app-d.log
ctl journeys-coverage-destructive-old-pass-pass 0 '^defects \{\}$' '^invalid \[\]$' -- python3 -c "$CVE" PASS $T/old-app-d.log with
ctl journeys-destructive-line-pass 0 '^destructive: 1/1 of 4 \(identity 2, delete-all 1, reimport 1; 1 CONTAMINATED; 1 INVALID; shared database, run after the main set, not in the coverage ratio\)$' \
  -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r; print(r.destructive_summary({'a': {'verdict': 'PASS', 'destructive': 'identity'}, 'b': {'verdict': 'FAIL', 'destructive': 'reimport'}, 'c': {'verdict': 'CONTAMINATED', 'destructive': 'delete-all'}, 'd': {'verdict': 'INVALID', 'destructive': 'identity'}, 'e': {'verdict': 'PASS'}})['line'])"
ctl journeys-destructive-line-none-pass 0 '^None$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r; print(r.destructive_summary({'e': {'verdict': 'PASS'}}))"
LO="import sys; sys.path.insert(0, '$B'); import run_journeys as r; print(r.login_outcome({'verdict': sys.argv[1]} if sys.argv[1] != 'none' else None, sys.argv[2] or None))"
ctl journeys-login-contaminated-catch 0 "^\('CONTAMINATED', 'CONTAMINATED', 'CONTAMINATED: login FAIL after reset \(reimport\) ran on the same database" -- python3 -c "$LO" FAIL 'reset (reimport)'
ctl journeys-login-contaminated-fail-pass 0 "^\('FAIL', 'FAIL', ''\)$" -- python3 -c "$LO" FAIL ''
ctl journeys-login-contaminated-invalid-pass 0 "^\('INVALID', 'INVALID', ''\)$" -- python3 -c "$LO" INVALID 'reset (reimport)'
ctl journeys-login-contaminated-pass-pass 0 "^\('PASS', None, ''\)$" -- python3 -c "$LO" PASS 'reset (reimport)'
# the loop hands the previous destructive journey to login_outcome (a live walk needs the engine and a database; this checks the wiring)
ctl journeys-login-contaminated-wired-pass 0 'lword, lverdict, lwhy = login_outcome\(login, prior_dirty\)' 'prior_dirty = dirty$' 'if DESTR_WAVE in key and files:' 'dirty = f"\{read_journey\(files\[0\]\)\[.id.\]\} \(\{destructive_scope\(read_journey\(files\[0\]\)\)\}\)"' -- cat $B/run_journeys.py
# gen_journeys: the tag journey-proof reads by hand ("resetsData") comes from the model's scope; a row delete is not tagged
# (golden: the destructive and workflow-op entries of the real Purchase Request inventory)
python3 $B/gen_journeys.py --actions $FX/actions/pr-destructive.json --out-dir $T/gd > /dev/null 2>&1
SCJ="import json,glob,sys; [print(json.load(open(f))['id'].split('.')[-2] + '.' + json.load(open(f))['id'].split('.')[-1], json.load(open(f)).get('_scope'), json.load(open(f)).get('resetsData'), [a.get('nth') for s in json.load(open(f))['steps'] for a in s['actions'] if a['do'] == 'row']) for f in sorted(glob.glob(sys.argv[1] + '/journeys/*/*.journey.json'))]"
ctl gen-actions-scope-identity-catch 0 '^MendixSSOUserOverview.actionButton2 identity True \[\]$' '^Task_POCreator.actionButton10 reimport True \[\]$' -- python3 -c "$SCJ" $T/gd
ctl gen-actions-scope-row-pass 0 '^Comments_TaskInbox.actionButton16 row None \[\]$' -- python3 -c "$SCJ" $T/gd
ctl gen-actions-workflow-rows-pass 0 '^Snip_Workflow_MoreActions.actionButton13 None None \[None\]$' '^Snip_Workflow_MoreActions.actionButton14 None None \[1\]$' '^Snip_Workflow_MoreActions.actionButton15 None None \[2\]$' '^Snip_Workflow_MoreActions.actionButton16 None None \[3\]$' -- python3 -c "$SCJ" $T/gd
# --- PR-F36: a rerun --from journeys wrote over the previous run's per-journey results before anyone read them
# (Purchase Request pipe-30 -> pipe-31). The text evidence is kept, the screenshots and the engine copy are not
arch_list() { bash $B/archive_journeys.sh "$1"; [ ! -d "$1/archive" ] || (cd "$1/archive" && find . -type f | sort); }
AW=$T/aw; mkdir -p $AW/logs $AW/journeys/A $AW/e2e-before-picked/before-picked/run-A $AW/e2e-before-picked/engine
echo out > $AW/journeys-after.out; echo log > $AW/logs/journeys.log; echo '{}' > $AW/journeys/A/a1.journey.json
echo '{}' > $AW/e2e-before-picked/before-picked/run-A/a1.journey.json; echo x > $AW/e2e-before-picked/before-picked/run-A/a1.png
echo js > $AW/e2e-before-picked/engine/helpers.js
ctl journeys-archive-none-pass 0 'no previous journeys run' '!kept' -- arch_list $AW
echo out > $AW/journeys-before-picked.out; touch -t 202610120102.03 $AW/journeys-before-picked.out
ctl journeys-archive-keep-pass 0 'kept 5 files .*/archive/journeys-20261012T010203Z$' 'journeys-20261012T010203Z/journeys-before-picked.out$' \
  'journeys-20261012T010203Z/logs/journeys.log$' 'run-A/a1.journey.json$' 'journeys/A/a1.journey.json$' '!\.png' '!engine/' '!\.files' -- arch_list $AW
echo changed > $AW/logs/journeys.log
ctl journeys-archive-once-pass 0 'already kept' '!kept [0-9]' -- arch_list $AW
ctl journeys-archive-usage-catch 2 'usage' -- bash $B/archive_journeys.sh $T/nope
# --- PR-F35: a Pop-up menu's items render only once it is opened (Purchase Request pipe-30: the admin's 7 workflow
# actions in "Possible actions" FAILed "not visible" on the healthy OLD app). Golden: WorkflowCommons'
# Snip_Workflow_MoreActions captured from the real model (pop_upMenu5: text1 in menuTrigger, actionButton13-19 in
# customItems), lib/capture_units.py
python3 "$here/lib/capture_units.py" build "$FX/actions/pr-moreactions-units.json" "$T/m/pr-menu" > /dev/null
PMC="import sys; sys.path.insert(0, '$B'); import impact_map as I, mprmodel; m = mprmodel.Model.load('$T/m/pr-menu'); [print(w, I.tab_path(m, 'WorkflowCommons.Snip_Workflow_MoreActions', w)) for w in sys.argv[1:]]"
ctl impact-popup-menu-item-catch 0 "^actionButton13 \(\[\{'menu': 'pop_upMenu5', 'caption': 'menu', 'control': 'pop_upMenu5'\}\], None\)$" "^actionButton19 \(\[\{'menu': 'pop_upMenu5'" -- python3 -c "$PMC" actionButton13 actionButton19
ctl impact-popup-menu-trigger-pass 0 "^text1 \(\[\], None\)$" -- python3 -c "$PMC" text1
ctl gen-actions-menu-step-pass 0 "^\[\{'do': 'menu', 'widget': 'pop_upMenu5'\}\]$" \
  -- python3 -c "$GF; import mprmodel; x = type('X', (), {'model': mprmodel.Model.load('$T/m/pr-menu')})(); print(g.ActionGen.tab_acts(x, {'click': 'actionButton13'}, 'WorkflowCommons.Snip_Workflow_MoreActions')[0])"
ctl journeys-menu-verb-pass 0 '^function$' -- node -e "console.log(typeof require('$B/journey-verbs.js').menu)"
# PR-F35: a Data grid 2 header button (filtersPlaceholder) acts on the selection: select the first row when the grid
# selects, else click it as it is (pipe-30: "Select Vendor" on Task_POCreator ran with nothing selected). Field only:
# the page is 805 KB captured, so it is cut from the real model at run time (UPG_PR_MPR), never committed
PRM=${UPG_PR_MPR:-}
if [ -n "$PRM" ] && [ -f "$PRM" ]; then
  python3 "$here/lib/capture_units.py" capture "$PRM" $T/pr-po.json --doc PurchaseApprovals.Task_POCreator > /dev/null
  python3 -c "import json,sys; s=open(sys.argv[1]).read(); assert s.count('\"Selection\": \"Single\"') == 1; open(sys.argv[2],'w').write(s.replace('\"Selection\": \"Single\"', '\"Selection\": \"None\"'))" $T/pr-po.json $T/pr-po-nosel.json
  for v in pr-po pr-po-nosel; do python3 "$here/lib/capture_units.py" build $T/$v.json $T/m/$v > /dev/null; python3 $B/action_inventory.py $T/m/$v/App.mpr --out $AI/$v.json > /dev/null; done
  POC="import json,sys; d=json.load(open(sys.argv[1])); [print(a['id'].split('.')[-1], a.get('click')) for a in d['actions'] if a['id'] in ('PurchaseApprovals.Task_POCreator.actionButton1', 'PurchaseApprovals.Task_POCreator.actionButton15')]"
  ctl field-action-inventory-grid-header-select-pass 0 "^actionButton1 \{'row': 'grid1', 'row_only': False\}$" "^actionButton15 \{'within': 'listView2'\}$" -- python3 -c "$POC" $AI/pr-po.json
  ctl field-action-inventory-grid-header-noselect-catch 0 "^actionButton1 \{\}$" -- python3 -c "$POC" $AI/pr-po-nosel.json
else for c in select-pass noselect-catch; do skip field-action-inventory-grid-header-$c "no UPG_PR_MPR"; done; fi
ctl gen-actions-wizard-path-needs-pass 0 '"_path_needs"' -- sh -c "cat $T/wz/journeys/Requester/*.journey.json"
# processes: "Select the first in" a combo box; back on the page a popup closed, in one leg (not a new request from home)
ctl process-wizard-compile-pass 0 '^COMPILED P01 +Submit a purchase request +legs proc-p01-01$' '^processes 1 confirmed · 1 compiled · 0 invalid' \
  -- python3 $B/process_journeys.py $FX/processes/pr-submit.md --actions $WZ --out-dir $T/wzp
ctl process-wizard-journey-pass 0 '"do": "combo", "widget": "referenceSelector2", "first": true' '"do": "combo", "widget": "dropDown1", "match": "Marketing"' "Title = 'Req \\\$\{RUN_ID\}'" \
  -- python3 -c "import json; print(json.dumps(json.load(open('$T/wzp/journeys/Requester/proc-p01-01.journey.json'))))"
sed 's/Select the first in "referenceSelector2"/Select the first in "Quantity"/' $FX/processes/pr-submit.md > $T/pr-first-text.md
ctl process-wizard-first-text-catch 3 'the first. works on a combo box only' -- python3 $B/process_journeys.py $T/pr-first-text.md --actions $WZ --out-dir $T/wzp2
# PR-F31: "View" (an open-task button: no target page) continues in place onto the task page its path opens, in one
# leg (Purchase Request pipe-23: "Assign to me" on the task page was walked from home and reopened the task from the
# empty "My Tasks" list); a path that opens the task from another page is not that task page and still walks from home
PT=$FX/actions/pr-task.json; PTS="import json,sys; j=json.load(open(sys.argv[1])); [print('step', s['name'], '|', ' '.join(a['do'] + ':' + str(a.get('widget') or a.get('item')) for a in s['actions'])) for s in j['steps']]"
ctl process-open-task-pass 0 '^COMPILED P02 +Approve a purchase request +legs proc-p02-01$' -- python3 $B/process_journeys.py $FX/processes/pr-approve.md --actions $PT --out-dir $T/ptk
ctl process-open-task-steps-pass 0 '^step 1\. Click "View" \| click:actionButton7$' '^step 2\. Click "Assign to me" \| click:actionButton19$' '!container25' \
  -- python3 -c "$PTS" $T/ptk/journeys/Approver/proc-p02-01.journey.json
# PR-F42: the open-task click carries near ${RUN_ID} (the walk's own task), the task page's clicks do not
ctl process-open-task-near-pass 0 '"widget": "actionButton7", "near": "\$\{RUN_ID\}"' '!"widget": "actionButton19", "near"' \
  -- python3 -c "import json,sys; [print(json.dumps(a)) for s in json.load(open(sys.argv[1]))['steps'] for a in s['actions']]" $T/ptk/journeys/Approver/proc-p02-01.journey.json
cp $PT $T/pr-task-other.json
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [h.update(on='PurchaseApprovals.MyRequests') for x in d['actions'] for h in x.get('path') or [] if h.get('action') == 'open-task' and h.get('id', '').endswith('container25')]; json.dump(d, open(sys.argv[1], 'w'))" $T/pr-task-other.json
ctl process-open-task-other-page-catch 0 '^COMPILED P02 +Approve a purchase request +legs proc-p02-01, proc-p02-02$' -- python3 $B/process_journeys.py $FX/processes/pr-approve.md --actions $T/pr-task-other.json --out-dir $T/ptk2
# PR-P2: a step that clicks a task outcome (kind task-outcome: Approve) asserts no dialog is open after the click; the
# steps before it (View, Assign to me) do not (Purchase Request: "Received" over a Warning box passed on .mx-page)
NOD="import json,sys; [print('step', i, 'noDialog', bool(s['ui'].get('noDialog'))) for i, s in enumerate(json.load(open(sys.argv[1]))['steps'], 1)]"
ctl process-outcome-nodialog-catch 0 '^step 4 noDialog True$' -- python3 -c "$NOD" $T/ptk/journeys/Approver/proc-p02-01.journey.json
ctl process-outcome-nodialog-pass 0 '^step 1 noDialog False$' '^step 2 noDialog False$' '^step 3 noDialog False$' -- python3 -c "$NOD" $T/ptk/journeys/Approver/proc-p02-01.journey.json
# PR-F33: "park: <n> after leg <k>" compiles to plan.json processes.park; a leg past the last and a malformed line
# are INVALID, never a silent no-op (Purchase Request pipe-28: 44 of 97 baseline defects had no task). PR-F34: the
# last leg is legal (pipe-29 ran without P02 because "6 after leg 2" of a 2-leg process was refused)
sed 's/^expect text:/park: 3 after leg 1\nexpect text:/' $FX/processes/pr-approve.md > $T/pr-park.md
ctl process-park-compile-pass 0 '^PARK +P02 +3 after leg 1 \(proc-p02-01\)$' '^COMPILED P02 ' \
  -- python3 $B/process_journeys.py $T/pr-park.md --actions $T/pr-task-other.json --out-dir $T/ppk
ctl process-park-plan-pass 0 '^\[\{"n": 3, "after": 1, "legs": \["proc-p02-01"\], "process": "P02"\}\]$' \
  -- python3 -c "import json; print(json.dumps(json.load(open('$T/ppk/plan.json'))['processes']['park']))"
sed 's/^park: 3 after leg 1/park: 3 after leg 2/' $T/pr-park.md > $T/pr-park-last.md
ctl process-park-last-leg-pass 0 '^PARK +P02 +3 after leg 2 \(proc-p02-01, proc-p02-02\)$' '!^INVALID' \
  -- python3 $B/process_journeys.py $T/pr-park-last.md --actions $T/pr-task-other.json --out-dir $T/ppk2
sed 's/^park: 3 after leg 1/park: 3 after leg 3/' $T/pr-park.md > $T/pr-park-past.md
ctl process-park-past-last-catch 3 '^INVALID +P02 +park .3 after leg 3.: leg 3 is not a leg of this process \(2 legs\)' '!^PARK ' \
  -- python3 $B/process_journeys.py $T/pr-park-past.md --actions $T/pr-task-other.json --out-dir $T/ppk4
sed 's/^park: 3 after leg 1/park: plenty/' $T/pr-park.md > $T/pr-park-bad.md
ctl process-park-syntax-catch 3 "^INVALID +P02 +park 'plenty': write it as" -- python3 $B/process_journeys.py $T/pr-park-bad.md --actions $T/pr-task-other.json --out-dir $T/ppk3
# PR-B1 (owner-approved): an action a compiled leg clicks is walked in its process context, so its generated one-click
# journey is set aside and the leg alone is the action's coverage unit (Purchase Request: Task_POCreator.10/5/9 passed in
# proc-p02-03, but act-* opened the first task in the wrong state and a unit needs EVERY linked journey to pass).
python3 $B/gen_journeys.py --actions $PT --out-dir $T/b1 > /dev/null 2>&1
cp -r $T/b1 $T/b1pre
sed 's/^status: confirmed/status: draft/' $FX/processes/pr-approve.md > $T/pr-approve-draft.md
sed 's/=> PurchaseApprovals.Task_Approver.actionButton9/=> Nope.Missing.button1/' $FX/processes/pr-approve.md > $T/pr-approve-bad.md
cp -r $T/b1pre $T/b1i
ctl process-supersede-line-pass 0 '^SUPERSEDE act-PurchaseApprovals\.TaskInbox\.actionButton7 by proc-p02-01 ' '^SUPERSEDE act-PurchaseApprovals\.Task_Approver\.actionButton19 by proc-p02-01 ' \
  '^SUPERSEDE act-PurchaseApprovals\.Task_Approver\.actionButton9 by proc-p02-01 ' -- python3 $B/process_journeys.py $FX/processes/pr-approve.md --actions $PT --out-dir $T/b1
ctl process-supersede-files-pass 0 '^proc-p02-01\.journey\.json$' '!^act-' -- sh -c "ls $T/b1/journeys/Approver | grep -v superseded"
ctl process-supersede-plan-pass 0 '^act-PurchaseApprovals\.Task_Approver\.actionButton9 proc-p02-01$' '^journeys proc-p02-01$' \
  -- python3 -c "import json,sys; p=json.load(open(sys.argv[1])); [print(e['id'], e['closed_by']) for e in p['covered']]; print('journeys', ' '.join(e['id'] for e in p['journeys']))" $T/b1/plan.json
CVU="import sys; sys.path.insert(0, '$B'); import run_journeys as r; cs = r.journey_set(sys.argv[1]); js = {j: {'verdict': sys.argv[2] if j.startswith('proc-') else sys.argv[3]} for j in cs['links']}; o = r.coverage(js, {}, cs, None, r.read_actions('$PT'), None, [], False); print('G', o['G'], 'B', o['B'], 'D', o['D'])"
# the leg passes and the one-click journey would fail: the unit passes (the walk replaces it); the leg fails: the unit FAILs
ctl process-supersede-unit-pass 0 '^G 3 B 3 D 0$' -- python3 -c "$CVU" $T/b1 PASS FAIL
ctl process-supersede-unit-catch 0 '^G 3 B 0 D 3$' -- python3 -c "$CVU" $T/b1 FAIL PASS
# the set is hash-visible: putting the one-click journeys back changes the sha256
cp -r $T/b1 $T/b1x
for f in $T/b1x/journeys/*/*.superseded; do [ -e "$f" ] && mv "$f" "${f%.superseded}"; done
ctl process-supersede-hash-pass 0 '^changed$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import run_journeys as r; print('changed' if r.journey_set('$T/b1')['sha256'] != r.journey_set('$T/b1x')['sha256'] else 'same')"
ctl process-supersede-invalid-pass 3 '^INVALID +P02 ' '!^SUPERSEDE' -- python3 $B/process_journeys.py $T/pr-approve-bad.md --actions $PT --out-dir $T/b1i
ctl process-supersede-invalid-kept-pass 0 '^act-PurchaseApprovals\.TaskInbox\.actionButton7\.journey\.json$' '^act-PurchaseApprovals\.Task_Approver\.actionButton9\.journey\.json$' '!superseded' -- ls $T/b1i/journeys/Approver
ctl process-supersede-restore-pass 3 '!^SUPERSEDE' -- python3 $B/process_journeys.py $T/pr-approve-draft.md --actions $PT --out-dir $T/b1
ctl process-supersede-restore-files-pass 0 '^act-PurchaseApprovals\.Task_Approver\.actionButton19\.journey\.json$' '!superseded' '!proc-' -- ls $T/b1/journeys/Approver
# PR-P4: the scope of a delete (identity / delete-all / reimport / row), from the flow's own content and the association
# delete behaviour. Golden: CreatePurchaseOrder (retrieves the request's PO list, deletes it, creates POs: reimport),
# ACT_Comment_Delete (deletes the object it is given: row) and the domain models, captured from the real Purchase Request
# model. Mutants of the same units: the retrieve with its XPath removed (delete-all), the deleted object an identity entity
UPS=$FX/actions/pr-scope-units.json
python3 -c "import sys; s=open(sys.argv[1]).read(); k='\"XpathConstraint\": \"[PurchaseApprovals.PurchaseOrder_Request = \$Request]\"'; assert s.count(k) == 1; open(sys.argv[2],'w').write(s.replace(k, '\"XpathConstraint\": \"\"'))" $UPS $T/pr-scope-all.json
python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); n = 0
def walk(x):
    global n
    if isinstance(x, dict):
        if x.get('\$Type') == 'Microflows\$MicroflowParameter' and x.get('Name') == 'WorkflowComment':
            x['VariableType']['Entity'] = 'MendixSSO.MendixSSOUser'; n += 1
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
for u in d['units']:
    if u['data'].get('Name') == 'ACT_Comment_Delete': walk(u['data'])
assert n == 1
json.dump(d, open(sys.argv[2], 'w'))" $UPS $T/pr-scope-id.json
python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); n = 0
for u in d['units']:
    if u['data'].get('\$Type') == 'DomainModels\$DomainModel':
        for a in u['data'].get('Associations') or []:
            if a.get('Name') == 'AccountPasswordData_MendixSSOUser':
                a['DeleteBehavior']['ParentDeleteBehavior'] = 'DeleteMeAndReferences'; n += 1
assert n == 1
json.dump(d, open(sys.argv[2], 'w'))" $UPS $T/pr-scope-casc.json
for v in base all id casc; do f=$UPS; [ $v = base ] || f=$T/pr-scope-$v.json; python3 "$here/lib/capture_units.py" build $f "$T/m/pr-scope-$v" > /dev/null; done
SCP="import sys; sys.path.insert(0, '$B'); import mprmodel, action_inventory as A; inv = A.Inventory(mprmodel.Model.load(sys.argv[1] + '/App.mpr'))
for qn in ('PurchaseApprovals.CreatePurchaseOrder', 'WorkflowCommons.ACT_Comment_Delete'):
    f = inv.flow(qn); print(qn.split('.')[1], inv.scope_of(f['deletes'], f['written'], f['docs']))
print('apd', inv.scope_of([{'entity': 'MendixSSO.AccountPasswordData', 'all': False}], set(), []))
print('identity', ','.join(sorted(inv.identity_entities())))
print('cascade', ','.join(sorted(inv.cascade({'WorkflowCommons.DashboardContext'}))))
print('keep', ','.join(sorted(inv.cascade({'WorkflowCommons.WorkflowCommentHelper'}))))"
ctl action-inventory-scope-reimport-pass 0 '^CreatePurchaseOrder reimport$' '^ACT_Comment_Delete row$' '^apd row$' -- python3 -c "$SCP" $T/m/pr-scope-base
ctl action-inventory-scope-delete-all-catch 0 '^CreatePurchaseOrder delete-all$' '^ACT_Comment_Delete row$' -- python3 -c "$SCP" $T/m/pr-scope-all
ctl action-inventory-scope-identity-catch 0 '^ACT_Comment_Delete identity$' '^CreatePurchaseOrder reimport$' -- python3 -c "$SCP" $T/m/pr-scope-id
# an association whose delete behaviour cascades into the identity entity makes the delete identity (real association
# AccountPasswordData_MendixSSOUser, its parent delete behaviour set to "delete me and references"); as captured it keeps the user
ctl action-inventory-scope-cascade-identity-catch 0 '^apd identity$' -- python3 -c "$SCP" $T/m/pr-scope-casc
ctl action-inventory-scope-identity-set-pass 0 '^identity Administration\.Account,MendixSSO\.MendixSSOUser,System\.User$' -- python3 -c "$SCP" $T/m/pr-scope-base
ctl action-inventory-scope-cascade-pass 0 '^cascade .*WorkflowCommons\.WorkflowSeries' '^cascade .*WorkflowCommons\.WorkflowSummary' '^keep WorkflowCommons\.WorkflowCommentHelper$' -- python3 -c "$SCP" $T/m/pr-scope-base
# the page-level Delete of an identity entity's list (Administration.Account_Overview) is identity too, and counted
cat > $T/pagescope.py <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d["actions"]:
    if a["kind"] == "delete":
        print(a["id"].split(".")[-1], a.get("scope"))
print("scopes", json.dumps(d["summary"].get("scopes")))
PYEOF
python3 $B/action_inventory.py $T/m/pr-scope-base/App.mpr --out $T/pr-scope-ai.json > /dev/null
ctl action-inventory-scope-page-identity-catch 0 '^actionButton4 identity$' '^scopes \{"identity": 1, "row": 2\}$' -- python3 $T/pagescope.py $T/pr-scope-ai.json
# PR-P5: the data rung's own-row check on a field of a NON-persistable entity (Purchase Request: the comment box of
# Snip_WorkflowView_CommentsAndAttachments_Admin is WorkflowCommentHelper.Content; the helper has no table, the query was
# rejected: "OQL returned nothing - admin API unreachable or query rejected", INVALID). The flow copies it into a persistent
# entity ($WorkflowCommentHelper/Content -> WorkflowComment.Content): the check is made there. Golden: the snippet, its
# microflow and the domain models captured from the real model
PAS="import json,sys; [print(a['id'].split('.')[-1], f['attribute'].split('.')[-2], f['attr_type'].get('persistable'), f.get('persisted_as')) for a in json.load(open(sys.argv[1]))['actions'] for f in a['fields'] if 'Comment' in f['attribute']]"
ctl action-inventory-persisted-as-catch 0 '^actionButton1 WorkflowCommentHelper False WorkflowCommons\.WorkflowComment\.Content$' -- python3 -c "$PAS" $T/pr-scope-ai.json
OWN="import sys; sys.path.insert(0, '$B'); import gen_journeys as g; f = {'widget': 'w', 'input': 'text', 'attribute': 'M.E.A', 'attr_type': {'type': 'String'}}; f.update(eval(sys.argv[1])); print(g.fill_field(f, 3, 'x')[1])"
ctl gen-actions-own-row-npe-catch 0 '^WorkflowCommons\.WorkflowComment\.Content$' -- python3 -c "$OWN" "{'attr_type': {'type': 'String', 'persistable': False}, 'persisted_as': 'WorkflowCommons.WorkflowComment.Content'}"
ctl gen-actions-own-row-npe-none-catch 0 '^None$' -- python3 -c "$OWN" "{'attr_type': {'type': 'String', 'persistable': False}}"
ctl gen-actions-own-row-persistent-pass 0 '^M\.E\.A$' -- python3 -c "$OWN" "{}"
# PR-P3: a Data grid 2 whose onClickTrigger is double fires its row action on a double click (Purchase Request: a single
# click on a Product / Vendor / User overview row only focuses the cell, 3 baseline defects). Golden: Product_Overview
# captured from the real model; the twin is the same model with the trigger set to single
python3 "$here/lib/capture_units.py" build "$FX/actions/pr-grid-dblclick-units.json" "$T/m/pr-grid-dbl" > /dev/null
python3 -c "import sys; s=open(sys.argv[1]).read(); assert s.count('\"PrimitiveValue\": \"double\"') == 1; open(sys.argv[2],'w').write(s.replace('\"PrimitiveValue\": \"double\"', '\"PrimitiveValue\": \"single\"'))" "$FX/actions/pr-grid-dblclick-units.json" $T/pr-grid-single.json
python3 "$here/lib/capture_units.py" build $T/pr-grid-single.json "$T/m/pr-grid-single" > /dev/null
for v in dbl single; do python3 $B/action_inventory.py $T/m/pr-grid-$v/App.mpr --out $T/pr-grid-$v-ai.json > /dev/null; done
GRC="import json,sys; [print(a['id'].split('.')[-1], json.dumps(a['click'], sort_keys=True)) for a in json.load(open(sys.argv[1]))['actions']]"
ctl action-inventory-row-trigger-catch 0 '^grid1 \{"row": "grid1", "row_only": true, "trigger": "double"\}$' -- python3 -c "$GRC" $T/pr-grid-dbl-ai.json
ctl action-inventory-row-trigger-pass 0 '^grid1 \{"row": "grid1", "row_only": true\}$' '^actionButton3 \{"row": "grid1", "row_only": false\}$' '^actionButton1 \{"within": "grid1"\}$' '!trigger' -- python3 -c "$GRC" $T/pr-grid-single-ai.json
ctl gen-actions-row-dblclick-catch 0 '^\[\{"do": "row", "widget": "grid1", "dblclick": true\}\]$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import gen_journeys as g, json; print(json.dumps(g.click_acts({'row': 'grid1', 'row_only': True, 'trigger': 'double'})))"
ctl gen-actions-row-dblclick-pass 0 '^\[\{"do": "row", "widget": "grid1"\}\]$' '^\[\{"do": "row", "widget": "grid1"\}, \{"do": "click", "widget": "actionButton3"\}\]$' -- python3 -c "import sys; sys.path.insert(0, '$B'); import gen_journeys as g, json; print(json.dumps(g.click_acts({'row': 'grid1', 'row_only': True}))); print(json.dumps(g.click_acts({'row': 'grid1', 'row_only': False, 'click': 'actionButton3'})))"
# QW-2 (Purchase Request baseline, "Assign to me" cost 13): the button shows only while Assignees = empty, and a role with one
# user gets its tasks assigned. Golden: P02 of the real processes.md (4 "Assign to me" steps) and the 21 actions it pins,
# captured from the real model; users-sole.json = one user per role, users-two.json = two
PAS=$FX/processes; PAA=$FX/actions/pr-assign-sole.json
ctl process-assign-sole-invalid-catch 3 "^INVALID +P02 +step 15 'Assign to me' \[Approver\]; step 18 'Assign to me' \[PurchaseOrderCreator\]; step 28 'Assign to me' \[Receiver\]; step 31 'Assign to me' \[InvoiceProcessor\]: shown only if Assignees = empty; the role has 1 user, its tasks arrive assigned: remove the step or add a 2nd user" '0 compiled · 1 invalid' '!^COMPILED' \
  -- python3 $B/process_journeys.py $PAS/pr-assign-sole.md --actions $PAA --users $PAS/users-sole.json --out-dir $T/pas1
ctl process-assign-sole-not-dropped-catch 0 'process:P02' 'shown only if Assignees = empty' -- python3 -c "import json; print(json.dumps(json.load(open('$T/pas1/plan.json'))['skipped']))"
ctl process-assign-two-users-pass 0 '^COMPILED P02 ' '1 compiled · 0 invalid' '!INVALID' -- python3 $B/process_journeys.py $PAS/pr-assign-sole.md --actions $PAA --users $PAS/users-two.json --out-dir $T/pas2
ctl process-assign-no-users-pass 0 '^COMPILED P02 ' '!INVALID' -- python3 $B/process_journeys.py $PAS/pr-assign-sole.md --actions $PAA --out-dir $T/pas3
ctl draft-process-assign-sole-catch 0 "^NOTE left out 'Assign to me' \(PurchaseApprovals\.Task_Approver\.actionButton19\): shown only for unassigned tasks and role Approver has 1 user" "^NOTE left out 'Assign to me' \(PurchaseApprovals\.Task_POCreator\.actionButton19\)" "^NOTE left out 'Assign to me' \(PurchaseApprovals\.Task_Receiver\.actionButton19\)" "^NOTE left out 'Assign to me' \(PurchaseApprovals\.Task_InvoiceProcessor\.actionButton19\)" '!^DRAFT .*Assign to me' \
  -- sh -c "python3 $B/draft_processes.py --actions $PAA --users $PAS/users-sole.json --max 40 --out $T/pas-d1.md; grep -c 'actionButton19' $T/pas-d1.md || true"
ctl draft-process-assign-sole-file-pass 0 '^0$' -- sh -c "grep -c 'Assign to me' $T/pas-d1.md || true"
ctl draft-process-assign-two-users-pass 0 '^DRAFT P[0-9]+ Assign to me on Task_Approver ' '!^NOTE left out' -- python3 $B/draft_processes.py --actions $PAA --users $PAS/users-two.json --max 40 --out $T/pas-d2.md
# PR-F43: an input of a list inside the button's form ("row_fields") is a field of that form, filled in every shown row
# (Purchase Request pipe-34: PromiseDate, required, sits in listView1 of PurchaseOrder_Edit; every leg-3 walk stopped at
# Save, so Receiver, InvoiceProcessor and Admin got no task). Golden: PurchaseOrder_Edit captured from the real model
python3 "$here/lib/capture_units.py" build "$FX/actions/pr-po-edit-units.json" "$T/m/pr-po-edit" > /dev/null
python3 $B/action_inventory.py $T/m/pr-po-edit/App.mpr --out $T/pr-po-edit-ai.json > /dev/null
ctl action-inventory-row-fields-pass 0 '^datePicker1 date listView1$' '^datePicker2 date listView1$' '^textBox2 text listView1$' '^fields 0$' \
  -- python3 -c "import json,sys; a=[x for x in json.load(open(sys.argv[1]))['actions'] if x['id'].endswith('PurchaseOrder_Edit.actionButton1')][0]; print('fields', len(a['fields'])); [print(f['widget'], f['input'], f['list']) for f in a.get('row_fields') or []]" $T/pr-po-edit-ai.json
ctl process-row-fields-pass 0 '^COMPILED P03 ' '^\{"do": "fill", "widget": "datePicker2", "value": "1/20/2027", "rows": true\}$' \
  -- sh -c "python3 $B/process_journeys.py $FX/processes/pr-po.md --actions $FX/actions/pr-po-edit.json --out-dir $T/prf && python3 -c \"import json,sys; [print(json.dumps(a)) for s in json.load(open(sys.argv[1]))['steps'] for a in s['actions']]\" $T/prf/journeys/PurchaseOrderCreator/proc-p03-01.journey.json"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [a.pop('row_fields') for a in d['actions']]; json.dump(d, open(sys.argv[2], 'w'))" $FX/actions/pr-po-edit.json $T/pr-po-edit-norf.json
ctl process-row-fields-catch 3 "^INVALID +P03 .*no field\(s\) of the form of PurchaseApprovals\.PurchaseOrder_Edit\.actionButton1 match 'PromiseDate'" \
  -- python3 $B/process_journeys.py $FX/processes/pr-po.md --actions $T/pr-po-edit-norf.json --out-dir $T/prf2
ctl journeys-fields-verb-pass 0 '^function$' -- node -e "console.log(typeof require('$B/journey-verbs.js').fields)"
# PR-F44: a file input is filled by upload (a generated .jpeg, journey-verbs.js upload), in a process Fill step and in a
# generated form journey (Purchase Request: the workflow attachment views need an attachment; "file upload: no verb")
ctl process-upload-pass 0 '^COMPILED P04 ' '^\{"do": "upload", "widget": "fileManager1", "file": "upg-seed\.jpeg"\}$' \
  -- sh -c "python3 $B/process_journeys.py $FX/processes/pr-attach.md --actions $FX/actions/pr-attach.json --out-dir $T/pup && python3 -c \"import json,sys; [print(json.dumps(a)) for s in json.load(open(sys.argv[1]))['steps'] for a in s['actions']]\" $T/pup/journeys/Administrator/proc-p04-01.journey.json"
sed 's/Fill "fileManager1" with "upg-seed.jpeg"/Select "upg-seed.jpeg" in "fileManager1"/' $FX/processes/pr-attach.md > $T/pr-attach-select.md
ctl process-upload-select-catch 3 '^INVALID +P04 .*field fileManager1 is input file: no select verb for it' \
  -- python3 $B/process_journeys.py $T/pr-attach-select.md --actions $FX/actions/pr-attach.json --out-dir $T/pup2
ctl gen-actions-fill-file-pass 0 "^\[\{'do': 'upload', 'widget': 'fileManager1', 'file': 'upg-seed.jpeg'\}\] None None$" \
  -- python3 -c "import sys; sys.path.insert(0, '$B'); import gen_journeys as g; print(*g.fill_field({'widget': 'fileManager1', 'input': 'file', 'attr_type': {'type': 'none'}}, 1, 'x'))"
# the pipeline compiles confirmed processes into the journeys gen dir, after gen_journeys
ctl pipeline-processes-wired-pass 0 'process_journeys\.py" "\$WORK/processes\.md" --actions "\$WORK/actions\.json" --out-dir "\$WORK/journeys"' \
  -- grep -A5 'gen_journeys\.py" "\$WORK/impact\.json"' $B/cloud/upgrade-pipeline.sh
# the engine runs the combo verb (journey-verbs.js combo)
ctl journeys-engine-combo-patch-pass 0 "case 'combo'" 'V\.combo\(page' -- sh -c "grep -h \"case 'combo'\\|V.combo(page\" $T/engine-copy/*.js"
# --- PR-F26: navigation list items, distinct hop guards, re-login (pipe-19: the Step 3 hop clicked the whole list, ------
# landed on Step 2, the guard actionButton1 matched Step 2's Discard, Submit ended the session, no later journey signed in)
ctl gen-actions-nav-item-pass 0 '"do": "item",' '"nth": 2,' '"of": 3' \
  -- cat $T/wz/journeys/Requester/act-PurchaseApprovals.NewRequest_Step3.actionButton1.journey.json
# a hop guard whose name the left page also renders is swapped for a widget only the landing page has (stub model)
DR="$GF; a=g.ActionGen({'actions': []}, set(), None); a.names=lambda q: {'S2': {'actionButton1', 'textBox2'}, 'S3': {'actionButton1', 'textBox3'}}.get(q, set()); a.landing=lambda q, away=None: 'textBox3' if q == 'S3' else None"
ctl gen-actions-distinct-guard-pass 0 "^\('\.mx-name-textBox3', .*'was': 'actionButton1'" -- python3 -c "$DR; print(a.distinct_ready('.mx-name-actionButton1', 'S3', 'S2'))"
ctl gen-actions-distinct-guard-weak-catch 0 "^\('\.mx-name-actionButton1', .*weak guard" -- python3 -c "$DR; a.landing=lambda q, away=None: None; print(a.distinct_ready('.mx-name-actionButton1', 'S3', 'S2'))"
ctl gen-actions-distinct-guard-own-catch 0 "^\('\.mx-name-textBox3', None\)$" -- python3 -c "$DR; print(a.distinct_ready('.mx-name-textBox3', 'S3', 'S2'))"
# PR-F37: a swapped landing guard sits on the tab the page shows first, so a tab click in the same step hid it (pipe-30:
# 14 comments/attachments journeys FAILed on the healthy OLD app). Land on the guard, then a tab step waits for the widget
TSJ="$DR; a.names=lambda q: {'S2': {'actionButton1'}, 'S3': {'actionButton1', 'dv1'}}.get(q, set()); a.landing=lambda q, away=None: 'dv1' if q == 'S3' else None
tabs = {'actionButton1': ([{'do': 'click', 'widget': 'tabPage2', 'settleMs': 800}], [{'tab': 'tabPage2', 'caption': 'Comments', 'widget': 'actionButton1'}])}
a.tab_acts = lambda h, page: tabs.get(h['click'], ([], [])) if page == 'S3' and len(sys.argv) < 2 else ([], [])
x = {'id': 'M.S3.actionButton1', 'action': 'microflow', 'kind': 'commit', 'host': 'S3', 'widget': 'actionButton1', 'caption': 'Submit', 'path_role': 'R',
     'path': [{'via': 'home', 'page': 'S1'}, {'click': 'b1', 'on': 'S1', 'page': 'S2'}, {'click': 'go', 'on': 'S2', 'page': 'S3'}, {'click': 'actionButton1', 'on': 'S3'}]}
[print(s['name'], '|', ','.join(str(b.get('widget')) for b in s['actions']), '|', s['ui']['ready']) for s in a.journey(x)['steps']]"
ctl gen-actions-tab-guard-split-pass 0 '^open S3 \| go \| \.mx-name-dv1$' "^open S3 > tab 'Comments' \| tabPage2 \| \.mx-name-actionButton1$" '!go,tabPage2' -- python3 -c "$TSJ"
ctl gen-actions-tab-guard-nosplit-catch 0 '^open S3 \| go \| \.mx-name-dv1$' '!tabPage2' '!mx-name-actionButton1$' '!^open S3 > ' -- python3 -c "$TSJ" notab
# PR-F38: a widget drawn only when a condition holds names that condition on its hop, its journey step and its FAIL
# (Purchase Request pipe-30: 62 of 91 baseline FAILs clicked such a widget, e.g. "Open parent workflow" shown only for a
# sub-workflow in an app that has none); a path prefers an always-shown hop; a module-role condition limits the role
AIS="import sys; sys.path.insert(0, '$B'); import action_inventory as ai"
ctl inventory-shown-if-text-pass 0 "^container1: \\\$W/P != empty; module roles M\.Admin \['M\.Admin'\]$" "^tab: M\.E\.State in \['Failed'\] \[\]$" \
  -- python3 -c "$AIS
for n, cv in [('container1', {'Expression': ' \$W/P != empty ', 'ModuleRoles': ['M.Admin']}),
              ('tab', {'Attribute': 'M.E.State', 'Conditions': [{'AttributeValue': 'Failed', 'EditableVisible': True}, {'AttributeValue': 'Done', 'EditableVisible': False}]})]:
    s = ai.shown_if(n, cv); print(s['text'], s['roles'])"
AIR="$AIS; i = object.__new__(ai.Inventory); i.m = type('M', (), {'docs': {}})(); i.roles = type('R', (), {'of_module_roles': lambda s, m: {'Admin'}, 'of_doc': lambda s, q: {'Admin', 'User'}})()
p = {'action': 'open', 'conditional': [{'widget': 'b', 'text': 'b: module roles M.Admin', 'roles': ['M.Admin']}]}"
ctl inventory-shown-if-role-pass 0 '^User False Admin True$' -- python3 -c "$AIR; print('User', i.may('User', p, 'B'), 'Admin', i.may('Admin', p, 'B'))"
ctl inventory-shown-if-norole-catch 0 '^User True$' -- python3 -c "$AIR; p['conditional'][0]['roles'] = []; print('User', i.may('User', p, 'B'))"
AIB="$AIS; i = object.__new__(ai.Inventory); i.m = type('M', (), {'docs': {'A': type('D', (), {'type': 'Forms\$Page', 'data': {}})()}})()
i.entries = lambda role: [('home', 'A', {})]; i.targets = lambda p: p['t']; i.supplies = lambda p, t: True; i.may = lambda r, p, t: True
i.points = {'A': [{'widget': 'hidden', 't': ['B'], 'conditional': [{'text': 'x'}]}] + ([] if len(sys.argv) > 1 else [{'widget': 'plain', 't': ['B'], 'conditional': []}])}
print('B via', i.bfs({'A': ['A'], 'B': ['B']}, False)['B'][1]['widget'])"
ctl inventory-bfs-unconditional-first-pass 0 '^B via plain$' -- python3 -c "$AIB"
ctl inventory-bfs-conditional-only-catch 0 '^B via hidden$' -- python3 -c "$AIB" only-hidden
GSJ="$DR; a.names=lambda q: set(); a.landing=lambda q, away=None: None; a.tab_acts = lambda h, page: ([], [])
x = {'id': 'M.S3.actionButton1', 'action': 'microflow', 'kind': 'commit', 'host': 'S3', 'widget': 'actionButton1', 'caption': 'Retry', 'path_role': 'R',
     'path': [{'via': 'home', 'page': 'S1'}, {'click': 'b1', 'on': 'S1', 'page': 'S2'}, {'click': 'go', 'on': 'S2', 'page': 'S3', 'shown_if': ['go: \$W/P != empty']},
              {'click': 'actionButton1', 'on': 'S3', 'shown_if': ['actionButton1: M.W.State in [\'Failed\']']}]}
[print(s['name'].split(' (')[0], '|', s.get('shown_if')) for s in a.journey(x)['steps']]"
ctl gen-actions-shown-if-pass 0 '^role home S1 \| None$' "^open S2 \| \['go: \\\$W/P != empty'\]$" \
  "^open S3 \| \['go: \\\$W/P != empty', \"actionButton1: M\.W\.State in \['Failed'\]\"\]$" "^microflow 'Retry' on S3 \| \[\"actionButton1: M\.W\.State in \['Failed'\]\"\]$" \
  -- python3 -c "$GSJ"
RJS="import sys; sys.path.insert(0, '$B'); import run_journeys as rj
j = {'steps': [{}, {'shown_if': ['go: c']}, {}]}; P, F = {'checks': [{'verdict': 'PASS'}]}, {'checks': [{'verdict': 'FAIL'}]}"
ctl journeys-shown-if-at-pass 0 "^fail \['go: c'\] stopped \['go: c'\] first None all None$" \
  -- python3 -c "$RJS; print('fail', rj.shown_if_at(j, [P, F]), 'stopped', rj.shown_if_at(j, [P]), 'first', rj.shown_if_at(j, [F]), 'all', rj.shown_if_at(j, [P, P, P]))"
ctl journeys-shown-if-printed-pass 0 "^FAIL x \[shown only if go: c; x: d\]\|$" -- python3 -c "$RJS; print('FAIL x' + rj.shown_tag({'shown_if': ['go: c', 'x: d']}) + '|' + rj.shown_tag({}))"
# the engine runs the item verb and signs in again when the previous journey ended the session
ctl journeys-engine-item-relogin-patch-pass 0 "case 'item'" 'V\.item\(page' 'signed in again' -- sh -c "grep -h \"case 'item'\\|V.item(page\\|signed in again\" $T/engine-copy/*.js"
# the pipeline rewrites actions.json when action_inventory.py is newer (pipe-19 reused a stale inventory)
ctl pipeline-actions-refresh-pass 0 'actions\.json" -nt "\$B/action_inventory\.py"' -- grep 'actions.json" -nt' $B/cloud/upgrade-pipeline.sh
# --- PR-F27: a wizard's Next validates the form even when the action only opens a page (pipe-19: Step1 Next empty,
# Step 2 never opened); the engine types a date in the picker's own format (11.12.5: "dd mmm yyyy")
WF="python3 -c \"import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['steps'][-1]['actions']))\""
ctl gen-actions-wizard-final-fill-pass 0 '"do": "fill", "widget": "textBox1"' '"do": "combo", "widget": "dropDown1"' '"click", "widget": "actionButton1"' \
  -- sh -c "$WF $T/wz/journeys/Requester/act-PurchaseApprovals.NewRequest_Step1.actionButton1.journey.json"
ctl gen-actions-wizard-final-fill-catch 0 '^\[\{"do": "click", "widget": "actionButton1"\}\]$' \
  -- sh -c "python3 $B/gen_journeys.py --actions $T/wz-nocreate.json --out-dir $T/wz3 --roles-with-users Requester > /dev/null 2>&1; $WF $T/wz3/journeys/Requester/act-PurchaseApprovals.NewRequest_Step1.actionButton1.journey.json"
ctl journeys-engine-date-patch-pass 0 'V\.dateAs\(await el\.getAttribute' 'fill: \$\{fv\.note\}' -- sh -c "grep -h 'V.dateAs\\|fv.note' $T/engine-copy/*.js"
# --- E2E-16: processes (bin/draft_processes.py, bin/process_journeys.py, run_journeys.py's process line) -------------------
# A process is drafted from the model, a manual and a key-user interview, always as status: draft; only a human confirms.
# Confirmed processes compile to journeys (one leg per role) or come out INVALID with the reason, never dropped.
PF=$FX/processes; PA=$AI/a.json; PJ="python3 $B/process_journeys.py"; PRJ="python3 $B/run_journeys.py"
if python3 -c 'import bson' 2>/dev/null; then
  [ -f $PA ] || python3 $B/action_inventory.py $T/m/t2cards/App.mpr --out $PA > /dev/null
  DP="python3 $B/draft_processes.py --actions $PA"
  # model only: the home cards write nothing, so the model drafts nothing (no invented process)
  ctl process-draft-model-none-catch 0 '^drafted 0 \(model 0, manual 0, interview 0\)' '!^DRAFT ' -- $DP --out $T/pd-model.md
  ctl process-draft-manual-pass 0 '^drafted 3 \(model 0, manual 3, interview 0\)' '^status: draft$' '!^status: confirmed' \
    '^2\. Click the "Contents" card to see what the kit holds\.  => StarterKit\.Home_Gallery\.container1$' '^1\. Open the client configuration card\.  => \?$' \
    'candidates: none in the model' 'source: manual: manual-starterkit\.md §Client configuration \(line 16\)' \
    -- sh -c "$DP --out $T/pd-man.md --manual $PF/manual-starterkit.md && cat $T/pd-man.md"
  ctl process-draft-interview-pass 0 '^drafted 3 \(model 0, manual 0, interview 3\)' '!^status: confirmed' \
    '^1\. \[User\] Click the "How To" card  => StarterKit\.Home_Gallery\.container5$' 'item 2 \(line 15\)' \
    '^expect: EXFN_Authentication\.ClientConfiguration where Alias = "Plant \$\{RUN_ID\}"$' '^notes: breaking: The configuration grid stays empty after Save\.$' \
    -- sh -c "$DP --out $T/pd-int.md --interview $PF/interview-starterkit.md && cat $T/pd-int.md"
  ctl process-draft-never-confirmed-pass 0 '^ *3 status: draft$' '!confirmed' -- sh -c "grep '^status:' $T/pd-int.md | sort | uniq -c"
  cp $T/pd-int.md $T/pd-both.md
  ctl process-draft-keeps-existing-pass 0 'kept 3 existing · 3 already there by name' '^DRAFT P04 Finding your way' '^same$' \
    -- sh -c "$DP --out $T/pd-both.md --interview $PF/interview-starterkit.md --manual $PF/manual-starterkit.md && head -c \$(wc -c < $T/pd-int.md) $T/pd-both.md | cmp -s - $T/pd-int.md && echo same"
  # compile: confirmed processes become legs; the draft P16 is listed and never compiled
  ctl process-compile-pass 0 '^COMPILED P10 +Read the contents +legs proc-p10-01$' '^COMPILED P11 .*legs proc-p11-01, proc-p11-02$' \
    '^DRAFT +P16 .*not compiled' '^role order: Administrator -> User$' '^processes 2 confirmed · 2 compiled · 0 invalid · 1 draft \(not compiled\)$' \
    -- $PJ $PF/cards-confirmed.md --actions $PA --out-dir $T/pc
  ctl process-compile-journey-pass 0 '"process": "P10"' '"process:P10"' '"do": "nav"' '"item": "Home"' '"ready": "\.mx-name-container1"' '"widget": "container1"' \
    -- cat $T/pc/journeys/Administrator/proc-p10-01.journey.json
  ctl process-handoff-leg-pass 0 '"persona": "User"' '"leg": 2' '"legs": 2' '"widget": "container5"' -- cat $T/pc/journeys/User/proc-p11-02.journey.json
  ctl process-draft-not-compiled-catch 0 '^none$' -- sh -c "ls $T/pc/journeys/*/proc-p16-* 2>/dev/null || echo none"
  ctl process-draft-only-catch 3 '^processes 0 confirmed · 0 compiled · 0 invalid · 3 draft \(not compiled\)$' 'no confirmed process' '!^COMPILED' \
    -- $PJ $T/pd-int.md --actions $PA --out-dir $T/pdo
  # a human confirms one draft (status and outcome): only that one compiles
  sed -e '/^## P02:/,/^## P03/s/^status: draft/status: confirmed/' -e '/^## P02:/,/^## P03/s/^expect: ?/expect text: "Links"/' $T/pd-int.md > $T/pd-conf.md
  ctl process-confirm-by-human-pass 0 '^COMPILED P02 ' '^processes 1 confirmed · 1 compiled · 0 invalid · 2 draft' -- $PJ $T/pd-conf.md --actions $PA --out-dir $T/pdc
  # unresolvable: each reason INVALID (a plan skipped row), none dropped
  ctl process-unresolvable-catch 3 '^INVALID +P12 .*a role acts again after another one' '^INVALID +P11 .*contradict the order another confirmed process needs' \
    '^INVALID +P14 .*newButton1 is not on the current page .*has no recorded click path' '^INVALID +P15 .*"Click "card"": no action matches it' \
    '^INVALID +P17 .*expect is not scoped to this run' '^INVALID +P18 .*not pinned \(=> \?\)' '^COMPILED P13 ' \
    '^processes 7 confirmed · 1 compiled · 6 invalid · 0 draft \(not compiled\)$' -- $PJ $PF/cards-invalid.md --actions $PA --out-dir $T/pi
  ctl process-unresolvable-plan-catch 0 '^process:P12 process:P11 process:P14 process:P15 process:P17 process:P18$' \
    -- python3 -c "import json; print(*[s['id'] for s in json.load(open('$T/pi/plan.json'))['skipped'] if s['id'].startswith('process:')])"
  # run_journeys.py: the role order from the plan, and the process line next to the action line (rejudge, no browser)
  RD="import sys; sys.path.insert(0, '$B'); from pathlib import Path; from run_journeys import role_dirs"
  ctl process-role-order-pass 0 "^\['User', 'Administrator'\]$" -- python3 -c "$RD; print([d.name for d in role_dirs(Path('$T/pi/journeys'), '$T/pi')])"
  ctl process-role-order-default-catch 0 "^\['Administrator', 'User'\]$" -- python3 -c "$RD; print([d.name for d in role_dirs(Path('$T/pi/journeys'), '$T/nothere')])"
  psum() { mkdir -p $1; python3 -c "import json,sys; v=dict(x.split('=') for x in sys.argv[1].split(','))
json.dump({'journeys': {j: {'role': 'User' if j.endswith('-02') else 'Administrator', 'verdict': s} for j, s in v.items()}, 'roles': {}}, open('$1/summary.json', 'w'))" "$2"; }
  psum $T/prj/old/before 'proc-p10-01=PASS,proc-p11-01=PASS,proc-p11-02=PASS'
  psum $T/prj/ok/after 'proc-p10-01=PASS,proc-p11-01=PASS,proc-p11-02=PASS'
  psum $T/prj/bad/after 'proc-p10-01=PASS,proc-p11-01=PASS,proc-p11-02=FAIL'
  psum $T/prj/half/after 'proc-p10-01=PASS,proc-p11-01=PASS'
  ctl process-line-pass 0 '^processes 2 confirmed · 2 compiled · 0 invalid · 2 pass · 1 draft \(not compiled\)$' -- $PRJ $T/pc --label after --work $T/prj/ok --rejudge "${NOACT[@]}"
  ctl process-line-regression-catch 1 '^processes 2 confirmed · 2 compiled · 0 invalid · 1 pass · 2 pass on baseline · 1 regression · 1 draft' 'FAIL +proc-p11-02 .*REGRESSION' \
    -- $PRJ $T/pc --label after --work $T/prj/bad --compare $T/prj/old --rejudge "${NOACT[@]}"
  ctl process-line-leg-missing-catch 0 '^processes 2 confirmed · 2 compiled · 0 invalid · 1 pass · ' -- $PRJ $T/pc --label after --work $T/prj/half --rejudge "${NOACT[@]}"
  ctl process-leg-missing-verdict-catch 0 '"P11": "INVALID"' '"P10": "PASS"' \
    -- python3 -c "import json, sys; sys.path.insert(0, '$B'); from run_journeys import process_coverage as pc
print(json.dumps(pc(json.load(open('$T/prj/half/after/summary.json'))['journeys'], json.load(open('$T/pc/plan.json')))['verdicts']))"
  psum $T/prj/inv/after 'proc-p13-01=PASS,proc-p13-02=PASS'
  ctl process-line-invalid-catch 3 '^  INVALID process:P14 +skipped: process INVALID' '^processes 7 confirmed · 1 compiled · 6 invalid · 1 pass' \
    -- $PRJ $T/pi --label after --work $T/prj/inv --rejudge "${NOACT[@]}"
  mkdir -p $T/pdo/journeys/Administrator; psum $T/prj/none/after 'login-Administrator=PASS'
  ctl process-line-none-confirmed-catch 3 '^processes 0 confirmed · 0 compiled · 0 invalid · 0 pass · 3 draft \(not compiled\) \(INVALID: no confirmed process' '^verdict: INVALID only' \
    -- $PRJ $T/pdo --label after --work $T/prj/none --rejudge "${NOACT[@]}"
  # B5-3, --bar processes (the user's PASS bar): the confirmed processes decide; other INVALID journeys are reported only
  psum $T/prj/bar/after 'proc-p10-01=PASS,proc-p11-01=PASS,proc-p11-02=PASS,other-x=INVALID'
  ctl process-bar-pass 0 '^bar: key processes · 2/2 pass · 2 confirmed · 0 regression · not blocking: 1 other journeys INVALID' '!^verdict: INVALID' \
    -- $PRJ $T/pc --label after --work $T/prj/bar --rejudge "${NOACT[@]}" --bar processes
  ctl process-bar-default-all-catch 3 '^verdict: INVALID only' '!^bar: ' -- $PRJ $T/pc --label after --work $T/prj/bar --rejudge "${NOACT[@]}"
  ctl process-bar-regression-catch 1 '^bar: key processes · 1/2 pass · 2 confirmed · 1 regression' \
    -- $PRJ $T/pc --label after --work $T/prj/bad --compare $T/prj/old --rejudge "${NOACT[@]}" --bar processes
  ctl process-bar-leg-missing-catch 3 '^verdict: INVALID only \(exit 3\) under the key-process bar: process P11 INVALID' \
    -- $PRJ $T/pc --label after --work $T/prj/half --rejudge "${NOACT[@]}" --bar processes
  ctl process-bar-none-confirmed-catch 3 'under the key-process bar: no confirmed process; a human confirms the drafts: P[0-9]' \
    -- $PRJ $T/pdo --label after --work $T/prj/none --rejudge "${NOACT[@]}" --bar processes
  ctl process-bar-compile-invalid-catch 3 'under the key-process bar: .*process P14 INVALID' \
    -- $PRJ $T/pi --label after --work $T/prj/inv --rejudge "${NOACT[@]}" --bar processes
  # S: guest access on (plan anonymous_role) needs one process that PASSes as the anonymous role, else the gate is INVALID;
  # an always-on journey INVALID blocks under --bar processes too (it used to be counted as "other journeys", not blocking)
  # own plans (no reliance on the compile controls above, which --only may skip): confirmed cards, compiled
  rm -rf $T/anon-gen $T/anon-off; $PJ $PF/cards-confirmed.md --actions $PA --out-dir $T/anon-off > /dev/null
  cp -R $T/anon-off $T/anon-gen
  python3 -c "import json; p='$T/anon-gen/plan.json'; d=json.load(open(p)); d['anonymous_role']='Guest'; d['skipped'].append({'id': 'anonymous-Guest', 'role': 'Guest', 'why': 'anonymous role: needs an anonymous journey (open the app without signing in); write it by hand'}); json.dump(d, open(p, 'w'))"
  asum() { mkdir -p $1; python3 -c "import json,sys; js={}
for kv in sys.argv[2].split(','):
    j, rv = kv.split('='); r, v = rv.split(':'); js[j] = {'role': r, 'verdict': v}
json.dump({'journeys': js, 'roles': {}}, open(sys.argv[1] + '/summary.json', 'w'))" "$1" "$2"; }
  asum $T/anon/none/after 'proc-p10-01=Administrator:PASS,proc-p11-01=Administrator:PASS,proc-p11-02=User:PASS'
  ctl journeys-anonymous-catch 3 '^anonymous process: 0 of 1 required \(role Guest; no confirmed process runs as it\)$' \
    '^  INVALID +anonymous-Guest +anonymous role: no process PASSes as it' '^verdict: INVALID only \(exit 3\)' '!^bar: ' \
    -- $PRJ $T/anon-gen --label after --work $T/anon/none --rejudge "${NOACT[@]}"
  ctl journeys-anonymous-bar-catch 3 '^verdict: INVALID only \(exit 3\) under the key-process bar: always-on journeys INVALID: anonymous-Guest; anonymous process: 0 of 1 required' \
    -- $PRJ $T/anon-gen --label after --work $T/anon/none --rejudge "${NOACT[@]}" --bar processes
  asum $T/anon/ok/after 'proc-p10-01=Guest:PASS,proc-p11-01=Administrator:PASS,proc-p11-02=User:PASS'
  ctl journeys-anonymous-pass 0 '^anonymous process: 1 of 1 required \(role Guest; 1 process\(es\) run as it\)$' \
    '^  PASS +anonymous-Guest +anonymous process P10 PASS' '!^verdict: INVALID' -- $PRJ $T/anon-gen --label after --work $T/anon/ok --rejudge "${NOACT[@]}"
  ctl journeys-anonymous-bar-pass 0 '^bar: key processes · 2/2 pass · 2 confirmed · 0 regression · not blocking: 0 other journeys INVALID' '!^verdict: INVALID' \
    -- $PRJ $T/anon-gen --label after --work $T/anon/ok --rejudge "${NOACT[@]}" --bar processes
  asum $T/alw/after 'proc-p10-01=Administrator:PASS,proc-p11-01=Administrator:PASS,proc-p11-02=User:PASS,login-User=User:INVALID'
  ctl journeys-always-on-bar-catch 3 '^verdict: INVALID only \(exit 3\) under the key-process bar: always-on journeys INVALID: login-User$' \
    '^bar: key processes · 2/2 pass · 2 confirmed · 0 regression · not blocking: 0 other journeys INVALID' \
    -- $PRJ $T/anon-off --label after --work $T/alw --rejudge "${NOACT[@]}" --bar processes
  # B2-3 after QJ-5: an API-only role is a not_browser row, never an always-on INVALID (no browser journey could clear it)
  rm -rf $T/api-gen; cp -R $T/anon-off $T/api-gen
  python3 -c "import json; p='$T/api-gen/plan.json'; d=json.load(open(p)); d.setdefault('not_browser', []).append({'id': 'login-ApiUser', 'role': 'ApiUser', 'check': 'API-only role: no browser home', 'targets': ['Shop.Login'], 'why': 'API-only role'}); json.dump(d, open(p, 'w'))"
  asum $T/api/after 'proc-p10-01=Administrator:PASS,proc-p11-01=Administrator:PASS,proc-p11-02=User:PASS'
  ctl journeys-api-only-bar-pass 0 '^bar: key processes · 2/2 pass · 2 confirmed · 0 regression · not blocking: 0 other journeys INVALID' '!^verdict: INVALID' '!always-on journeys INVALID' \
    -- $PRJ $T/api-gen --label after --work $T/api --rejudge "${NOACT[@]}" --bar processes
else
  for c in draft-model-none-catch draft-manual-pass draft-interview-pass draft-never-confirmed-pass draft-keeps-existing-pass compile-pass \
    compile-journey-pass handoff-leg-pass draft-not-compiled-catch draft-only-catch confirm-by-human-pass unresolvable-catch \
    unresolvable-plan-catch role-order-pass role-order-default-catch line-pass line-regression-catch line-leg-missing-catch leg-missing-verdict-catch \
    line-invalid-catch line-none-confirmed-catch bar-pass bar-default-all-catch bar-regression-catch bar-leg-missing-catch \
    bar-none-confirmed-catch bar-compile-invalid-catch; do skip process-$c "no python bson"; done
  for c in journeys-anonymous-catch journeys-anonymous-bar-catch journeys-anonymous-pass journeys-anonymous-bar-pass journeys-always-on-bar-catch journeys-api-only-bar-pass; do skip $c "no python bson"; done
fi
# E2E-16 field: the customer model, the customer functional specification (public, in the repo) as the manual, and the
# EXAMPLE interview fixture; the three interview drafts confirmed as a key user would (sed), then compiled
MES=${UPG_CUSTOMER_SPEC:-$(ls $ICE/*/*Functional_Specification*.md 2>/dev/null | head -1)}
if [ -f "$CUSTM" ] && [ -f "$MES" ]; then
  [ -f $AI/cust.json ] || python3 $B/action_inventory.py "$CUSTM" --out $AI/cust.json > /dev/null
  DPU="python3 $B/draft_processes.py --actions $AI/cust.json"
  ctl field-process-customer-draft-model-pass 0 '^drafted 2 \(model 2, manual 0, interview 0\)' '^## P01: Take Screenshot on ShareFeedback$' '!^status: confirmed' \
    '^expect: FeedbackModule\.Feedback where Subject = "Subject \$\{RUN_ID\}"$' -- sh -c "$DPU --out $T/pu-model.md && cat $T/pu-model.md"
  ctl field-process-customer-draft-pass 0 '^drafted 12 \(model 0, manual 9, interview 3\) · kept 0 existing · not written 5 \(--max 12\)$' \
    "replaces model draft 'Take Screenshot on ShareFeedback'" 'FL-09 \(line 153\)' '^1\. Submit/Approve/Release/Retire  => \?$' 'one action per step' '!^status: confirmed' \
    -- sh -c "$DPU --out $T/pu.md --manual \"$MES\" --interview $PF/interview-customer-feedback.md && cat $T/pu.md"
  sed -e '/^## P0[123]:/,/^## P04/s/^status: draft/status: confirmed/' -e '/^## P01:/,/^## P02/s/^expect: ?/expect: FeedbackModule.Feedback where Subject = "Printer jam ${RUN_ID}"/' \
      -e '/^## P02:/,/^## P03/s/^expect: ?/expect: FeedbackModule.Feedback where Subject = "Label photo ${RUN_ID}"/' $T/pu.md > $T/pu-conf.md
  ctl field-process-customer-compile-pass 3 '^COMPILED P01 .*legs proc-p01-01$' '^COMPILED P02 .*legs proc-p02-01$' '^INVALID +P03 .*feedback_submit: action todo: external-call' \
    '^processes 3 confirmed · 2 compiled · 1 invalid · 9 draft \(not compiled\)$' -- $PJ $T/pu-conf.md --actions $AI/cust.json --out-dir $T/pu-gen
  ctl field-process-customer-outcome-pass 0 "SELECT COUNT\\(\\*\\) AS n FROM FeedbackModule\.Feedback WHERE Subject = 'Printer jam \\\$\\{RUN_ID\\}'" '"widget": "feedback_subject"' '"widget": "actionButton4"' \
    -- cat $T/pu-gen/journeys/User/proc-p01-01.journey.json
else for c in draft-model-pass draft-pass compile-pass outcome-pass; do skip field-process-customer-$c "no customer model or MES spec"; done; fi

# --- start control: the mandatory quick start of the new app ---------------------------------------------------------------
if [ $fast = 1 ]; then skip start-quick "--fast"
elif [ -n "$only" ] && ! echo start-quick | grep -Eq "$only"; then :
elif ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mig-pg; then skip start-quick "no running mig-pg"
elif [ ! -d $LAB/f1/mig/tools/runtime-10.24.16 ] || [ ! -f $E1W/new-10.24.16.mda ]; then skip start-quick "no E1 MDA or runtime"
else
  bash $here/start-control.sh "$T" && { npass=$((npass + 1)); echo "ok    start-quick"; } || { nfail=$((nfail + 1)); failed="$failed start-quick"; echo "FAIL  start-quick"; }
fi

# --- journey control: the always-on MFA journey must FAIL on a planted fault (EnabledMFA=false) -------------------------------
if [ $fast = 1 ]; then skip journey-mfa "--fast"
elif [ -n "$only" ] && ! echo journey-mfa | grep -Eq "$only"; then :
elif ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mig-pg; then skip journey-mfa "no running mig-pg"
elif [ ! -d $LAB/f1/runs/e1/app/.git ] || [ ! -f $E1W/new-10.24.16.mda ] || [ ! -d "${PLAYWRIGHT_NODE_PATH:-$HOME/mendix-playwright/node_modules}" ]; then
  skip journey-mfa "no E1 evidence or no Playwright"
else
  bash $here/journey-control.sh "$T" && { npass=$((npass + 1)); echo "ok    journey-mfa"; } || { nfail=$((nfail + 1)); failed="$failed journey-mfa"; echo "FAIL  journey-mfa"; }
fi

# --- cost ledger (quality-judgement-plan.md item 4): bin/cost_ledger.py, measurement only -------------------------------
# add -> report: per-layer totals, "no cost line" for every layer without one, denominator "N of 9" (never silent 0)
CL="python3 $B/cost_ledger.py"; CD=$T/cost-pass; rm -rf "$CD"
ctl cost-ledger-add-report-pass 0 '^L0 +1 +3\.00 +1200 +4\.50 +mx check$' '^L2 +1 +14\.50 +52000 +6\.00 +bar impact walk$' \
  '^L1b +no cost line$' '^total +2 +17\.50 +53200 +10\.50' '^layers with a cost line: 2 of 9$' \
  -- sh -c "$CL add --work $CD --layer L0 --step 'mx check' --wall 3 --tokens 1200 --review 4.5 >/dev/null && $CL add --work $CD --layer L2 --step 'bar impact walk' --wall 14.5 --tokens 52000 --review 6 >/dev/null && $CL report --work $CD"
# a '-' (not known) is not a zero: the total counts only the lines that gave a number
ctl cost-ledger-dash-not-zero-pass 0 '^L5 +1 +2\.00 +- \(1 not given\) +- \(1 not given\) +snapshot diff$' '^layers with a cost line: 1 of 9$' '!^L5 +1 +2\.00 +0 ' '^total +1 +2\.00 +- +- ' \
  -- sh -c "$CL add --work $CD-d --layer L5 --step 'snapshot diff' --wall 2 >/dev/null && $CL report --work $CD-d"
# missing layers are named, never left out of the denominator
ctl cost-ledger-missing-layers-pass 0 '^layers with a cost line: 1 of 9$' '^L6 +no cost line$' '^C +no cost line$' '^L4 +1 +' \
  -- sh -c "$CL add --work $CD-m --layer L4 --step 'every page' --wall 9 --tokens - --review 2 >/dev/null && $CL report --work $CD-m"
ctl cost-ledger-empty-report-pass 0 'no lines yet' '^C +no cost line$' '^layers with a cost line: 0 of 9$' -- $CL report --work $CD-none
# unknown layer (or a phase named as one) is refused with exit 2, and no line is written
ctl cost-ledger-unknown-layer-catch 2 "unknown layer 'L9'" 'known layers: L0 L1 L1b L2 L3 L4 L5 L6 C' -- $CL add --work $CD-u --layer L9 --step x --wall 1
ctl cost-ledger-triage-layer-catch 2 "unknown layer 'triage'" -- $CL add --work $CD-u --layer triage --step x --wall 1
ctl cost-ledger-unknown-layer-no-line-pass 0 'no line written' -- sh -c "$CL add --work $CD-u --layer L9 --step x --wall 1 >/dev/null 2>&1; test ! -e $CD-u/cost-ledger.tsv && echo 'no line written'"
# a malformed line is named and the report exits 1 (it never reads as a total)
printf 'L0\tmx check\tabc\n' > "$T/cost-bad.tsv"; mkdir -p "$T/cost-bad"; mv "$T/cost-bad.tsv" "$T/cost-bad/cost-ledger.tsv"
ctl cost-ledger-malformed-catch 1 'line 1 is malformed' -- $CL report --work $T/cost-bad
# gate.sh prints the report when $W/cost-ledger.tsv exists, and a failing report never changes the verdict
GCW=$T/cost-gate; rm -rf "$GCW"; $CL add --work "$GCW" --layer L1 --step 'stub rung' --wall 2 >/dev/null
ctl cost-ledger-gate-report-pass 0 '^gate: PASS \(exit 0\)' '^layers with a cost line: 1 of 9$' '^L1 +1 +2\.00 +- \(1 not given\) +- \(1 not given\) +stub rung$' '!cost-ledger report failed' \
  -- gcase costg WORK=$GCW
GCB=$T/cost-gate-bad; rm -rf "$GCB"; mkdir -p "$GCB"; printf 'L0\tmx check\tabc\n' > "$GCB/cost-ledger.tsv"
ctl cost-ledger-gate-nonblocking-pass 0 '^gate: PASS \(exit 0\)' 'line 1 is malformed' 'cost-ledger report failed \(measurement only, verdict unchanged\)' -- gcase costbad WORK=$GCB
ctl cost-ledger-gate-no-ledger-pass 0 '^gate: PASS \(exit 0\)' '!cost ledger|layers with a cost line' -- gcase costnone WORK=$T/cost-gate-none
# --- impact actions (quality-judgement-plan.md item 6a, section 3): bin/impact_actions.py over action_inventory.py's reach ----
# The synthetic model (fixtures/models/impact-actions.json) has a two-level sub-flow chain behind Home.btnDeep, a flow no
# click reaches down a chain (Home.btnPlain) and a button on another page (Other.btnOther). mkmodel writes a button's
# microflow action as Forms$MicroflowClientAction, which Mendix does not write: imodel retypes it to Forms$MicroflowAction,
# the type action_inventory.py reads. t2cards (the golden with a protected add-on) gives unknown reach and an add-on module.
IAF=$FX/impact-actions; IA=$T/ia; mkdir -p $IA
imodel() {  # imodel NAME: fixtures/models/impact-actions.json built to $T/m/NAME with the microflow action type of Mendix
  [ -f "$T/m/$1/App.mpr" ] && { echo "$T/m/$1"; return; }
  python3 "$here/lib/mkmodel.py" "$FX/models/impact-actions.json" "$T/m/$1" > /dev/null || { echo "mkmodel $1 failed"; exit 2; }
  python3 - "$T/m/$1/App.mpr" <<'PYEOF'
import sqlite3, sys, bson
con = sqlite3.connect(sys.argv[1])
def fix(x):
    if isinstance(x, dict):
        return {k: ("Forms$MicroflowAction" if v == "Forms$MicroflowClientAction" else fix(v)) for k, v in x.items()}
    if isinstance(x, list):
        return [fix(v) for v in x]
    return x
for uid, blob in con.execute("select UnitID, Contents from Unit").fetchall():
    if blob:
        con.execute("update Unit set Contents=? where UnitID=?", (bson.encode(fix(bson.decode(blob))), uid))
con.commit(); con.close()
PYEOF
  echo "$T/m/$1"
}
if python3 -c 'import bson' 2>/dev/null; then
  IM=$(imodel impact-actions)
  python3 $B/action_inventory.py $IM/App.mpr --out $IA/shop.json > /dev/null
  [ -f $T/m/t2cards/App.mpr ] || python3 "$here/lib/capture_units.py" build "$FX/actions/t2-home-cards.json" "$T/m/t2cards" > /dev/null
  python3 $B/action_inventory.py $T/m/t2cards/App.mpr --out $IA/t2.json > /dev/null
  python3 -c "import json; d = json.load(open('$IA/shop.json')); [a.pop(k, None) for a in d['actions'] for k in ('reach', 'reach_unknown')]; json.dump(d, open('$IA/shop-noreach.json', 'w'))"
  IAC="python3 $B/impact_actions.py"
  printf '{bad' > $IA/bad.json
  ctl impact-actions-two-level-catch 0 '^TOUCHED Shop\.Home\.btnDeep: impact Shop\.SUB_Leaf \(document change: microflow changed\)$' \
    '^untouched Shop\.Home\.btnPlain$' '^untouched Shop\.Other\.btnOther$' '^source not provided: repaired \(no --repaired given\)$' \
    '^touched 1 of 3 actions \(sources provided: 2 of 7\)$' -- $IAC $IA/shop.json --impact $IAF/impact-leaf.json
  ctl impact-actions-untouched-pass 0 '^untouched Shop\.Home\.btnDeep$' '^TOUCHED Shop\.Home\.btnPlain: impact Shop\.ACT_Plain' \
    '!TOUCHED Shop\.Home\.btnDeep|TOUCHED Shop\.Other' '^touched 1 of 3 actions' -- $IAC $IA/shop.json --impact $IAF/impact-plain.json
  ctl impact-actions-repaired-catch 0 '^TOUCHED Shop\.Home\.btnDeep: repaired Shop\.SUB_Mid \(repaired document\)$' '^untouched Shop\.Home\.btnPlain$' \
    '^source not provided: impact \(no --impact given\)$' '^touched 1 of 3 actions \(sources provided: 2 of 7\)$' -- $IAC $IA/shop.json --repaired $IAF/repaired.txt
  ctl impact-actions-modules-catch 0 '^TOUCHED Shop\.Home\.btnPlain: modules Shop \(updated module\)$' '^touched 3 of 3 actions \(sources provided: 2 of 7\)$' \
    -- $IAC $IA/shop.json --updated-modules $IAF/modules.txt
  ctl impact-actions-module-change-catch 0 '^TOUCHED Shop\.Other\.btnOther: impact Shop \(module change: 2\.0\.0 -> 2\.1\.0\)$' '^touched 3 of 3 actions' \
    -- $IAC $IA/shop.json --impact $IAF/impact-module.json
  ctl impact-actions-l1-unchanged-catch 0 '^TOUCHED Shop\.Home\.btnDeep: l1 Shop\.SUB_Leaf \(L1 hit R31\)$' '^untouched Shop\.Home\.btnPlain$' \
    '^touched 1 of 3 actions \(sources provided: 3 of 7\)$' -- $IAC $IA/shop.json --impact $IAF/impact-empty.json --l1 $IAF/l1-leaf.json
  ctl impact-actions-l1-nodoc-catch 0 '^TOUCHED Shop\.Home\.btnDeep: l1 \(L1 hit R31 names no document: cannot be placed\)$' \
    '^touched 3 of 3 actions' -- $IAC $IA/shop.json --l1 $IAF/l1-nodoc.json
  ctl impact-actions-replacement-locate-pass 0 '^TOUCHED Shop\.Home\.btnPlain: replacements Shop\.ACT_Plain \(HIT R4\)$' '^untouched Shop\.Home\.btnDeep$' \
    '!R9|names no document' -- $IAC $IA/shop.json --replacements $IAF/replacements-locate.json
  ctl impact-actions-replacement-unlocatable-catch 0 '^TOUCHED Shop\.Home\.btnDeep: replacements \(HIT R9 names no document: cannot be placed\)$' \
    '^touched 3 of 3 actions' -- $IAC $IA/shop.json --replacements $IAF/replacements-unlocatable.json
  ctl impact-actions-convertcheck-pass 0 '^TOUCHED Shop\.Other\.btnOther: convertcheck Shop\.Other \(call-site mappings rewritten \(INFO\)\)$' \
    '^untouched Shop\.Home\.btnDeep$' -- $IAC $IA/shop.json --convertcheck $IAF/convert-mappings.json
  # unknown reach is TOUCHED whatever the sources say: the golden's add-on flow (container14) and the add-on module itself
  ctl impact-actions-unknown-reach-catch 0 '^TOUCHED StarterKit\.Home_Gallery\.container14: reach \(unknown reach: EXFN_Authentication\.Nav_ClientConfiguration_Overview\)' \
    '^TOUCHED StarterKit\.Home_Gallery\.container14: .*addons EXFN_Authentication \(unreadable add-on module in reach\)' \
    '^untouched StarterKit\.Home_Gallery\.container1$' '^source not provided: impact' -- $IAC $IA/t2.json
  ctl impact-actions-no-reach-catch 0 '^TOUCHED Shop\.Home\.btnPlain: reach \(unknown reach: the inventory gives no reach for this action\)$' \
    '^touched 3 of 3 actions \(sources provided: 1 of 7\)$' -- $IAC $IA/shop-noreach.json
  ctl impact-actions-not-provided-pass 0 '^source not provided: impact \(no --impact given\)$' '^source not provided: l1 \(no --l1 given\)$' \
    '^touched 0 of 3 actions \(sources provided: 1 of 7\)$' '!^TOUCHED' -- $IAC $IA/shop.json
  ctl impact-actions-out-pass 0 '^False 1 \{.actions.: 3, .touched.: 0, .untouched.: 3, .unknown_reach.: 0\}$' -- sh -c "$IAC $IA/shop.json --out $IA/out.json > /dev/null && python3 -c \"import json; d = json.load(open('$IA/out.json')); print(d['sources']['impact']['provided'], d['sources_provided'], d['summary'])\""
  ctl impact-actions-malformed-catch 1 'malformed input: impact file .*no "changes" list' '!^touched|^TOUCHED|^untouched' -- $IAC $IA/shop.json --impact $IAF/impact-bad.json
  ctl impact-actions-malformed-json-catch 1 'malformed input: actions file .*not JSON' -- $IAC $IA/bad.json
  ctl impact-actions-malformed-l1-catch 1 'malformed input: L1 file .*hit 0 needs a rule' -- $IAC $IA/shop.json --l1 $IAF/l1-bad.json
  ctl impact-actions-malformed-modules-catch 1 'malformed input: updated modules .*line 1: .Shop\.Pag. is not a module name' -- $IAC $IA/shop.json --updated-modules $IAF/modules-bad.txt
  ctl impact-actions-usage-catch 2 'no such file' -- $IAC $IA/none.json
  ctl impact-actions-no-actions-catch 2 'the following arguments are required: actions' -- $IAC
else
  for c in two-level-catch untouched-pass repaired-catch modules-catch module-change-catch l1-unchanged-catch l1-nodoc-catch \
           replacement-locate-pass replacement-unlocatable-catch convertcheck-pass unknown-reach-catch no-reach-catch not-provided-pass \
           out-pass malformed-catch malformed-json-catch malformed-l1-catch malformed-modules-catch usage-catch no-actions-catch; do
    skip impact-actions-$c "no python bson"
  done
fi

# --- access matrix (quality-judgement-plan.md L1b, item 9): bin/access_matrix.py over fixtures/models/access-*.json ----
# access-base.json: two entities with access rules (member rights, an association member, an XPath), two pages, a microflow
# and three user roles (Clerk, Manager, Guest). Each other access-*.json is a variant with one change (mkmodel "from").
# access-protected.json gives Clerk a module role of a module the model does not hold: not compared, never silent.
AMF=$FX/models; AM=$T/am; mkdir -p $AM
AM_NAMES="denominator-pass same-pass page-gain-catch write-lost-catch entity-gain-catch xpath-catch xpath-whitespace-pass
          role-removed-catch protected-catch unreadable-catch unreadable-diff-catch not-matrix-catch json-pass usage-catch"
if python3 -c 'import bson' 2>/dev/null; then
  for v in access-base access-gain-page access-lose-write access-gain-entity access-xpath access-xpath-ws access-role-removed access-protected; do
    python3 "$here/lib/mkmodel.py" "$AMF/$v.json" "$AM/$v" > /dev/null || { echo "mkmodel $v failed"; exit 2; }
  done
  mkdir -p $AM/garbage; printf 'this is not a database\n' > $AM/garbage/App.mpr
  printf '{"a": 1}' > $AM/notmatrix.json
  AMC="python3 $B/access_matrix.py"; A=$AM
  $AMC matrix $A/access-base --out $AM/base.json > /dev/null
  ctl access-matrix-denominator-pass 0 '^access matrix: 3 user roles × 2 entities, 2 pages, 1 flows$' '!REVIEW' -- $AMC matrix $A/access-base
  ctl access-matrix-same-pass 0 '^access diff: 5 objects × 3 roles compared, 0 gained, 0 lost, 0 xpath changed$' '!REVIEW|not compared' \
    -- $AMC diff $A/access-base $A/access-base
  ctl access-matrix-page-gain-catch 1 '^REVIEW Clerk: gained page Shop\.Admin$' '^access diff: 5 objects × 3 roles compared, 1 gained, 0 lost, 0 xpath changed$' \
    -- $AMC diff $A/access-base $A/access-gain-page
  ctl access-matrix-write-lost-catch 1 '^REVIEW Clerk: lost write Shop\.Order\.Total$' '^access diff: 5 objects × 3 roles compared, 0 gained, 1 lost, 0 xpath changed$' \
    -- $AMC diff $A/access-base $A/access-lose-write
  ctl access-matrix-entity-gain-catch 1 '^REVIEW Clerk: gained create Shop\.Customer$' '^REVIEW Clerk: gained read Shop\.Customer\.Name$' \
    -- $AMC diff $A/access-base $A/access-gain-entity
  ctl access-matrix-xpath-catch 1 "^REVIEW Clerk: xpath Shop\.Order: .*and Shop\.Order\.Total > 0\]$" '^access diff: 5 objects × 3 roles compared, 0 gained, 0 lost, 1 xpath changed$' \
    -- $AMC diff $A/access-base $A/access-xpath
  ctl access-matrix-xpath-whitespace-pass 0 '^access diff: 5 objects × 3 roles compared, 0 gained, 0 lost, 0 xpath changed$' '!REVIEW' \
    -- $AMC diff $A/access-base $A/access-xpath-ws
  ctl access-matrix-role-removed-catch 1 '^REVIEW Clerk: lost role \(exists only in OLD, 8 rights\)$' '^access diff: 5 objects × 2 roles compared' \
    -- $AMC diff $A/access-base $A/access-role-removed
  ctl access-matrix-protected-catch 3 '^not compared: Ext \(OLD: module role Ext\.User' '^access_matrix: the comparison is partial' \
    -- $AMC diff $A/access-protected $A/access-protected
  ctl access-matrix-unreadable-catch 3 '^access_matrix: cannot read: .*/garbage: DatabaseError: file is not a database$' -- $AMC matrix $AM/garbage
  ctl access-matrix-unreadable-diff-catch 3 '^access_matrix: cannot read: .*/garbage: DatabaseError' -- $AMC diff $AM/garbage $A/access-base
  ctl access-matrix-not-matrix-catch 3 'not an access matrix' -- $AMC diff $AM/notmatrix.json $AM/base.json
  ctl access-matrix-json-pass 0 '^access diff: 5 objects × 3 roles compared, 0 gained, 0 lost, 0 xpath changed$' '!REVIEW' \
    -- $AMC diff $AM/base.json $AM/base.json
  ctl access-matrix-usage-catch 2 'the following arguments are required: new' -- $AMC diff $AM/base.json
else
  for c in $AM_NAMES; do skip access-matrix-$c "no python bson"; done
fi

# --- D2 effect values (quality-judgement-plan.md item 5): bin/effect_values.py compares the VALUES a journey wrote -------
# compare controls read fixtures/effect-values/ (no database); snap controls run on the sqlite stand-in with the synthetic
# shop fixture (no Postgres needed). Planted defects: Qty 42 -> 0 (the zero), a changed association target, a dropped
# column, a dropped entity; the must-not-fire cases are changed ids, createddate / changeddate, AutoNumber, row order and a
# raw hash value (present / absent only).
EV="python3 $B/effect_values.py"; EVF=$FX/effect-values; EVSQ="python3 $here/lib/sqlitepsql.py"; EVE=Shop.Base,Shop.Tag,Shop.Item,System.Session   # System.Session: skipped (pgmap.NOISE)
mkdir -p $T/ev
ctl effect-values-same-pass 0 'same +Shop\.Item \(2 rows old, 2 rows new\)' 'effect values: 2 same, 0 REVIEW, 0 INVALID \(2 entities\)' '!REVIEW  ' \
  -- $EV compare $EVF/base.json $EVF/base.json
ctl effect-values-zero-catch 1 'REVIEW +Shop\.Item: 2 rows old, 2 rows new' 'Qty: old 42, new 0 \(row "Apple"\)' 'effect values: 1 same, 1 REVIEW, 0 INVALID' \
  -- $EV compare $EVF/base.json $EVF/new-zero.json
ctl effect-values-volatile-pass 0 'same +Shop\.Item' 'effect values: 2 same, 0 REVIEW, 0 INVALID' '!REVIEW  ' '!Qty' \
  -- $EV compare $EVF/base.json $EVF/new-volatile.json
ctl effect-values-hash-raw-pass 0 'effect values: 2 same, 0 REVIEW, 0 INVALID' '!REVIEW  ' -- $EV compare $EVF/base.json $EVF/new-hash-raw.json
ctl effect-values-hash-absent-catch 1 'Pwd: old present, new absent \(row "Apple"\)' 'effect values: 1 same, 1 REVIEW, 0 INVALID' -- $EV compare $EVF/base.json $EVF/new-hash-absent.json
ctl effect-values-assoc-catch 1 'REVIEW +Shop\.Item: 2 rows old' 'Shop\.Item_Category: old .*Fruit.*, new .*Veg' 'effect values: 1 same, 1 REVIEW' \
  -- $EV compare $EVF/base.json $EVF/new-assoc.json
ctl effect-values-missing-catch 3 'INVALID +Shop\.Item: missing from the new model' 'same +Shop\.Tag' 'effect values: 1 same, 0 REVIEW, 1 INVALID' \
  -- $EV compare $EVF/base.json $EVF/new-missing.json
ctl effect-values-absent-catch 3 'INVALID +Shop\.Item: no entity in the new snapshot' 'effect values: 1 same, 0 REVIEW, 1 INVALID' \
  -- $EV compare $EVF/base.json $EVF/new-absent.json
ctl effect-values-column-gone-catch 1 'Qty: old present, new absent' 'effect values: 1 same, 1 REVIEW' -- $EV compare $EVF/base.json $EVF/new-column-gone.json
ctl effect-values-accepted-pass 0 'same +Shop\.Item .*accepted: Qty:' 'effect values: 2 same, 0 REVIEW, 0 INVALID' 'effect values: 1 difference\(s\) accepted' \
  -- $EV compare $EVF/base.json $EVF/new-zero.json --accept $EVF/accept.txt
ctl effect-values-accept-noreason-usage 2 "no '# reason': " -- $EV compare $EVF/base.json $EVF/new-zero.json --accept $EVF/accept-noreason.txt
ctl effect-values-format-usage 2 'not an effect-values/1 snapshot' -- $EV compare $EVF/base.json $EVF/bad-format.json
ctl effect-values-noise-pass 0 'skipped as runtime housekeeping: System\.Session' '!^INVALID|^REVIEW' -- $EV compare $EVF/base.json $EVF/base.json
ctl effect-values-no-psql-catch 2 'snap needs --psql' -- env -u UPG_PSQL -u UPG_PGMAP $EV snap --no-model --entities Shop.Item --out $T/ev/none.json
ctl effect-values-model-required-catch 2 "snap needs --model APP" -- $EV snap --psql true --entities Shop.Item --out $T/ev/none.json
# the real snap, on the sqlite stand-in: c.db (Shop.Bad_Category removed, so Shop.Item is measurable), d.db (planted)
rm -f $T/ev/*.db; $EVSQ $T/ev/c.db --init $FX/pgmap/shop.sql; $EVSQ $T/ev/a.db --init $FX/pgmap/shop.sql
echo 'DELETE FROM "mendixsystem$association" WHERE association_name = '"'"'Shop.Bad_Category'"'"'' | $EVSQ $T/ev/c.db
cp $T/ev/c.db $T/ev/d.db
echo 'UPDATE "shop$item" SET price = 0 WHERE id = 1' | $EVSQ $T/ev/d.db
echo 'UPDATE "shop$base" SET "shop$base_tag" = NULL WHERE id = 1' | $EVSQ $T/ev/d.db
ctl effect-values-stand-in-pass 0 'effect values snap: 3 entities, 5 rows, 0 not measured, 0 missing from the model, 1 skipped' 'effect values: 3 same, 0 REVIEW, 0 INVALID' \
  -- sh -c "$EV snap --no-model --psql '$EVSQ $T/ev/c.db' --entities $EVE --out $T/ev/c.json && $EV compare $T/ev/c.json $T/ev/c.json"
ctl effect-values-stand-in-zero-catch 1 'REVIEW +Shop\.Item' 'Price: old 1\.5, new 0 \(row' 'REVIEW +Shop\.Base' 'Shop\.Base_Tag: old' 'REVIEW +Shop\.Tag' \
  -- sh -c "$EV snap --no-model --psql '$EVSQ $T/ev/c.db' --entities $EVE --out $T/ev/c.json && $EV snap --no-model --psql '$EVSQ $T/ev/d.db' --entities $EVE --out $T/ev/d.json && $EV compare $T/ev/c.json $T/ev/d.json"
# an entity the model does not have is never "same": Shop.Remote (an external entity, no table) is INVALID on both sides
ctl effect-values-stand-in-missing-catch 3 'missing from the model: Shop\.Remote' 'INVALID +Shop\.Remote: missing from the old model; missing from the new model' 'same +Shop\.Base' \
  -- sh -c "$EV snap --no-model --psql '$EVSQ $T/ev/c.db' --entities Shop.Base,Shop.Remote --out $T/ev/r.json && $EV compare $T/ev/r.json $T/ev/r.json"
ctl effect-values-refused-catch 3 'not measured: Shop\.Item: mapping problem: association Shop\.Bad_Category' 'INVALID +Shop\.Item' \
  -- sh -c "$EV snap --no-model --psql '$EVSQ $T/ev/a.db' --entities Shop.Base,Shop.Item --out $T/ev/a.json && $EV compare $T/ev/a.json $T/ev/a.json"
# --- D2 --model (item 5 follow-up): column classes from the domain model; the name heuristic only without --model -------
# models/effect-values.json: Shop.Account with AutoNumber Code, Integer Qty, HashString Secret (NOT named password), String
# Label; fixtures/effect-values/model-shop.sql is its stand-in database (Secret holds a fake value, never a real secret).
EVM=$(model effect-values); EVMP=$(model effect-values-partial)
mkdir -p $T/ev/mh; rm -f $T/ev/mh/*
$EVSQ $T/ev/mh/a.db --init $FX/effect-values/model-shop.sql; cp $T/ev/mh/a.db $T/ev/mh/b.db; cp $T/ev/mh/a.db $T/ev/mh/c.db; cp $T/ev/mh/a.db $T/ev/mh/d.db
echo 'UPDATE "shop$account" SET secret = '"'"'h$2b$12$sekret-BBB'"'"' WHERE id = 1' | $EVSQ $T/ev/mh/b.db
echo 'UPDATE "shop$account" SET code = 1005 WHERE id = 1' | $EVSQ $T/ev/mh/c.db
echo 'UPDATE "shop$account" SET qty = 0 WHERE id = 1' | $EVSQ $T/ev/mh/d.db
ctl effect-values-model-hash-pass 0 'same +Shop\.Account \(1 row old, 1 row new\)' 'effect values: 1 same, 0 REVIEW, 0 INVALID' '!column classes' 'hash stored as presence: classes_from model, no raw secret' \
  -- sh -c "$EV snap --psql '$EVSQ $T/ev/mh/a.db' --model $EVM --entities Shop.Account --out $T/ev/mh/a.json && $EV snap --psql '$EVSQ $T/ev/mh/b.db' --model $EVM --entities Shop.Account --out $T/ev/mh/b.json && $EV compare $T/ev/mh/a.json $T/ev/mh/b.json && grep -q '\"classes_from\": \"model\"' $T/ev/mh/a.json && ! grep -q sekret $T/ev/mh/a.json && echo 'hash stored as presence: classes_from model, no raw secret'"
ctl effect-values-model-autonumber-pass 0 'same +Shop\.Account' 'effect values: 1 same, 0 REVIEW, 0 INVALID' '!REVIEW  ' \
  -- sh -c "$EV snap --psql '$EVSQ $T/ev/mh/a.db' --model $EVM --entities Shop.Account --out $T/ev/mh/a.json && $EV snap --psql '$EVSQ $T/ev/mh/c.db' --model $EVM --entities Shop.Account --out $T/ev/mh/c.json && $EV compare $T/ev/mh/a.json $T/ev/mh/c.json && grep -q '\"Code\": \"sequence\"' $T/ev/mh/a.json && echo 'AutoNumber class sequence from the model'"
ctl effect-values-model-integer-zero-catch 1 'REVIEW +Shop\.Account' 'Qty: old 42, new 0' \
  -- sh -c "$EV snap --psql '$EVSQ $T/ev/mh/a.db' --model $EVM --entities Shop.Account --out $T/ev/mh/a.json && $EV snap --psql '$EVSQ $T/ev/mh/d.db' --model $EVM --entities Shop.Account --out $T/ev/mh/d.json && $EV compare $T/ev/mh/a.json $T/ev/mh/d.json"
ctl effect-values-model-undeclared-catch 3 'not translated: attribute Shop\.Account\.Secret is not declared in the model' 'INVALID +Shop\.Account: old snapshot: not translated' \
  -- sh -c "$EV snap --psql '$EVSQ $T/ev/mh/a.db' --model $EVMP --entities Shop.Account --out $T/ev/mh/p.json && $EV compare $T/ev/mh/p.json $T/ev/mh/p.json"
ctl effect-values-heuristic-note-pass 0 'heuristic note on stderr: 1 time' 'column classes: heuristic on OLD/NEW' 'classes_from recorded: name heuristic' \
  -- sh -c "n=\$($EV snap --no-model --psql '$EVSQ $T/ev/mh/a.db' --entities Shop.Account --out $T/ev/mh/h.json 2>&1 >/dev/null | grep -c 'name heuristic'); echo \"heuristic note on stderr: \$n time\"; [ \"\$n\" = 1 ] && $EV snap --no-model --psql '$EVSQ $T/ev/mh/a.db' --entities Shop.Account --out $T/ev/mh/h2.json >/dev/null 2>&1 && $EV compare $T/ev/mh/h.json $T/ev/mh/h2.json && grep -q '\"classes_from\": \"name heuristic (no --model)\"' $T/ev/mh/h.json && echo 'classes_from recorded: name heuristic'"

# --- seeded faults (quality plan item 8): controls/lib/mutate_mpr.py applies ONE fault to a copy of an app's model;
# bin/replay_faults.py replays a faults file through the static layers. fixtures/models/seeded.json is a page with allowed
# roles, a domain model with two attributes (one path through a list element with a leading marker), a constant (so
# constcheck runs). fixtures/seeded/faults.jsonl: S01 applies and is caught by L1b, S02 and S05 apply and no static layer
# sees an attribute default as WRONG; impact (a selecting layer) does see S02 / S05 since impact_map diffs domain models.
# S03 / S04 / S06 cannot apply (INVALID seeds).
# fixtures/seeded/inert.jsonl: S07 changes the roles of the Excluded microflow ACT_Old (an INERT seed).
if python3 -c 'import bson' 2>/dev/null; then
  SM=$(model seeded); SF=$FX/seeded/faults.jsonl; SS=$T/sm; mkdir -p $SS
  MUT="python3 $here/lib/mutate_mpr.py"
  for n in 1 3 4 5 6; do sed -n "${n}p" $SF > $SS/fault$n.json; done
  cat > $SS/check_list.py <<'EOF'
# the list-element mapping: the change lands on the attribute named Note, never on its neighbour Qty (raw index vs norm index)
import sys; sys.path.insert(0, sys.argv[1]); import mprmodel
ents = mprmodel.Model.load(sys.argv[2]).docs['Shop.$DomainModel'].data['Entities']
attrs = {a['Name']: a for e in ents if not isinstance(e, int) and e.get('Name') == 'Order' for a in e['Attributes'] if not isinstance(a, int)}
print('Qty default', attrs['Qty']['Value'].get('DefaultValue', '(none)'))
print('Note default', attrs['Note']['Value'].get('DefaultValue', '(none)'))
EOF
  cat > $SS/mkv2.py <<'EOF'
# an MPR v2 copy of a v1 model: every unit moves to mprcontents/<uuid>.mxunit and its Contents column goes NULL
import os, shutil, sqlite3, sys, uuid
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(dst, 'mprcontents'))
shutil.copy(os.path.join(src, 'App.mpr'), os.path.join(dst, 'App.mpr'))
con = sqlite3.connect(os.path.join(dst, 'App.mpr'))
for uid, blob in con.execute('select UnitID, Contents from Unit').fetchall():
    if blob is None:
        continue
    open(os.path.join(dst, 'mprcontents', str(uuid.UUID(bytes_le=bytes(uid))) + '.mxunit'), 'wb').write(blob)
    con.execute('update Unit set Contents=NULL where UnitID=?', (uid,))
con.commit(); con.close()
EOF
  ctl seeded-mutate-page-pass 0 '^mutated S01: Shop\.Admin AllowedModuleRoles: \[3, "Shop\.Manager"\] -> \[3, "Shop\.Clerk", "Shop\.Manager"\]$' \
    -- $MUT $SS/fault1.json $SM $SS/s01
  ctl seeded-mutate-list-element-pass 0 '^mutated S05: Shop\.\$DomainModel Entities\[Name=Order\]/Attributes\[Name=Note\]/Value/DefaultValue: \(absent\) -> "none yet"$' \
    -- $MUT $SS/fault5.json $SM $SS/s05
  ctl seeded-mutate-list-element-check-pass 0 '^Qty default \(none\)$' '^Note default none yet$' -- python3 $SS/check_list.py $B $SS/s05
  ctl seeded-mutate-skipkey-catch 1 'cannot apply: path does not resolve: .*\$ID is not part of the model' '!^mutated' \
    -- sh -c "$MUT $SS/fault6.json $SM $SS/s06; rc=\$?; [ ! -e $SS/s06 ] && exit \$rc"
  ctl seeded-mutate-unresolved-catch 1 'cannot apply: Widgets: 0 list elements match' '!^mutated' \
    -- sh -c "$MUT $SS/fault3.json $SM $SS/s03; rc=\$?; [ ! -e $SS/s03 ] && exit \$rc"
  ctl seeded-mutate-find-absent-catch 1 'cannot apply: find text not present under AllowedModuleRoles: .Shop\.Nobody.' \
    -- sh -c "$MUT $SS/fault4.json $SM $SS/s04; rc=\$?; [ ! -e $SS/s04 ] && exit \$rc"
  python3 $SS/mkv2.py $SM $SS/v2model
  ctl seeded-mutate-v2-pass 0 '^mutated S01: Shop\.Admin AllowedModuleRoles' -- $MUT $SS/fault1.json $SS/v2model $SS/v2out
  ctl seeded-replay-catch 0 '^S01 caught by: L1b \| selected for runtime walk by: impact \|' '^S02 caught by: none \| selected for runtime walk by: impact \|' '^S05 caught by: none \| selected for runtime walk by: impact \|' \
    '^S03 INVALID seed: mutate_mpr: S03: cannot apply: Widgets: 0 list elements match' '^S04 INVALID seed: .*find text not present' \
    '^S06 INVALID seed: .*drops it' '^noise seeded: impact 0 changes, access 0 REVIEW' '^invalid seeds: 3 \(S03, S04, S06\)$' \
    '^caught 1 / seeded 6 \(static judging layers\); selected 2 \(a runtime layer must judge them\); unseen 0 \(no layer saw it\)$' \
    -- python3 $B/replay_faults.py $SF --apps-root $T/m --work $SS/work --out $SS/report.json
  # an Excluded document is not built: a fault in it cannot misbehave, so it is INERT, never caught / selected / unseen
  ctl seeded-replay-inert-catch 0 '^S07 caught by: .*\(INERT: the document is Excluded, not built\)$' \
    '; inert 1 \(Excluded document, not built\): S07$' \
    -- python3 $B/replay_faults.py $FX/seeded/inert.jsonl --apps-root $T/m --work $SS/work-inert
  ctl seeded-replay-report-pass 0 '"caught": 1' '"selected": 2' '"unseen": 0' '"invalid": 3' '"needs_runtime": 2' -- cat $SS/report.json
  printf '{"id": "X1", "app": "seeded"}\n' > $SS/bad.jsonl
  ctl seeded-replay-malformed-catch 1 'line 1: .doc. must be a non-empty string' \
    -- python3 $B/replay_faults.py $SS/bad.jsonl --apps-root $T/m --work $SS/work2
  ctl seeded-replay-usage-catch 2 'the following arguments are required: --work' -- python3 $B/replay_faults.py $SF --apps-root $T/m
else skip seeded-controls "no python bson"; fi

# --- Plan 9b: theme clash (bin/theme_clash.py): does the app's own SCSS bind to a name the NEW Atlas Core removed?
# fixtures/theme/atlas-old and atlas-new are the two Atlas trees; app-<case> is the app's own styling, put in the NEW app.
TC=$B/theme_clash.py; TH9=$T/theme9
mk9() { local d=$TH9/$1; rm -rf "$d"; mkdir -p "$d/old" "$d/new"; cp -R $FX/theme/atlas-old/. "$d/old/"; cp -R $FX/theme/atlas-new/. "$d/new/"; [ "$2" = - ] || cp -R $FX/theme/$2/. "$d/new/"; echo "$d"; }
D=$(mk9 variable app-variable)
ctl theme-clash-variable-catch 1 '^CLASH variable \$old-var: used in theme/web/main\.scss:1, defined in old Atlas themesource/atlas_core/web/_variables\.scss:3, gone in new Atlas$' '^theme clash: 1 clashes \(1 variables, 0 mixins, 0 classes, 0 extends\); Atlas 3\.0\.8 -> 3\.14\.4$' -- python3 $TC diff $D/old $D/new
D=$(mk9 mixin app-mixin)
ctl theme-clash-mixin-catch 1 '^CLASH mixin old-mixin: used in theme/web/main\.scss:1, defined in old Atlas themesource/atlas_core/web/main\.scss:1, gone in new Atlas$' '^theme clash: 1 clashes \(0 variables, 1 mixins, 0 classes, 0 extends\)' -- python3 $TC diff $D/old $D/new
D=$(mk9 class app-class)
ctl theme-clash-class-catch 1 '^CLASH class \.btn-old: used in theme/web/main\.scss:1, defined in old Atlas themesource/atlas_core/web/main\.scss:7, gone in new Atlas$' '^theme clash: 1 clashes \(0 variables, 0 mixins, 1 classes, 0 extends\)' -- python3 $TC diff $D/old $D/new
D=$(mk9 extend app-extend)
ctl theme-clash-extend-catch 1 '^CLASH extend %ph-old: used in theme/web/main\.scss:2, defined in old Atlas themesource/atlas_core/web/main\.scss:9, gone in new Atlas$' '^CLASH extend \.btn-old: used in theme/web/main\.scss:1, defined in old Atlas themesource/atlas_core/web/main\.scss:7, gone in new Atlas$' '^theme clash: 2 clashes \(0 variables, 0 mixins, 0 classes, 2 extends\)' -- python3 $TC diff $D/old $D/new
# the app's own $old-var and old-mixin are the app's names: defined, not clashes
D=$(mk9 defined-pass app-defined-pass)
ctl theme-clash-defined-pass 0 '^theme clash: 0 clashes \(0 variables, 0 mixins, 0 classes, 0 extends\)' 'new app uses 1 variables, 1 mixins, 2 classes, 0 extend targets' '!CLASH' -- python3 $TC diff $D/old $D/new
# comments, string contents and #{} are not uses: only $kept_var (underscore alias of kept-var, still in Atlas) and kept-mixin count
D=$(mk9 comment-pass app-comment-pass)
ctl theme-clash-comment-pass 0 '^theme clash: 0 clashes' 'new app uses 1 variables, 1 mixins, 3 classes, 0 extend targets' '!CLASH' -- python3 $TC diff $D/old $D/new
# a Marketplace package under themesource (.version) is vendor: not the app's own styling, never judged
D=$(mk9 vendor app-vendor)
ctl theme-clash-vendor-pass 0 '^theme clash: 0 clashes' '!CLASH' -- python3 $TC diff $D/old $D/new
ctl theme-clash-vendor-listed-pass 0 'vendor-skipped=nanoflowcommons' '^info: app own styling files=1 modules=- ' -- sh -c "python3 $TC snap $D/new -o $D/v.json"
# identical Atlas and app: 0 clashes, exit 0 (the same app against itself)
D=$(mk9 variable app-variable)
# a class the new VENDOR module still styles is reported with that hint (the reviewer decides; it stays a CLASH)
D=$(mk9 vendor-hint app-vendor-hint)
ctl theme-clash-vendor-hint-catch 1 '^CLASH class \.btn-old: used in theme/web/main\.scss:1, defined in old Atlas themesource/atlas_core/web/main\.scss:7, gone in new Atlas \(still defined in new vendor module themesource/nanoflowcommons/web/main\.scss:1' '^theme clash: 1 clashes \(0 variables, 0 mixins, 1 classes, 0 extends\)' -- python3 $TC diff $D/old $D/new
ctl theme-clash-identical-pass 0 '^theme clash: 0 clashes \(0 variables, 0 mixins, 0 classes, 0 extends\); Atlas 3\.0\.8 -> 3\.0\.8$' '!CLASH' -- python3 $TC diff $D/old $D/old
# no themesource/atlas_core on one side: not compared, exit 3 (never "no clash")
N=$TH9/noatlas; rm -rf $N; mkdir -p $N/old $N/new/theme; cp -R $FX/theme/atlas-old/. $N/old/; cp -R $FX/theme/app-variable/theme/. $N/new/theme/
ctl theme-clash-no-atlas-new-invalid 3 '^theme clash: not compared \(no themesource/atlas_core in new app ' '!theme clash: [0-9]' -- python3 $TC diff $N/old $N/new
ctl theme-clash-no-atlas-old-invalid 3 '^theme clash: not compared \(no themesource/atlas_core in old app ' -- python3 $TC diff $N/new $N/old
# the snapshot round trip: snap the new app to JSON, then diff the JSON against the old app: the same clash
D=$(mk9 variable app-variable)
ctl theme-clash-json-catch 1 '^CLASH variable \$old-var: used in theme/web/main\.scss:1' '^theme clash: 1 clashes \(1 variables, 0 mixins, 0 classes, 0 extends\)' -- sh -c "python3 $TC snap $D/new -o $D/new.json >/dev/null 2>&1 && python3 $TC diff $D/old $D/new.json"
echo '{"schema": 0}' > $TH9/bad.json
ctl theme-clash-bad-json-invalid 2 'is not a schema 1 snapshot' -- python3 $TC diff $TH9/bad.json $D/new
ctl theme-clash-missing-dir-invalid 2 'not a directory' -- python3 $TC diff $D/old $TH9/nonexistent
ctl theme-clash-usage-invalid 2 'the following arguments are required' -- python3 $TC diff $D/old

# --- PR-C1 (Purchase Request run 4): the one-click "Assign to me" journey opens an UNASSIGNED task. The Task Inbox's first
# list ("My Tasks", listView5) holds only tasks assigned to the user (XPath Assignees = '[%CurrentUser%]'), so no row of it
# shows a button that renders only for Assignees = empty; the first list that is not so filtered ("Open tasks", listView4)
# does. Golden: TaskInbox captured from the real model (pr-inbox-units.json); actions: the same inventory's records, verbatim
python3 "$here/lib/capture_units.py" build "$FX/actions/pr-inbox-units.json" "$T/m/pr-inbox" > /dev/null
python3 $B/action_inventory.py $T/m/pr-inbox/App.mpr --out $T/pr-inbox-ai.json > /dev/null
INBX="import json,sys; [print(a['id'].split('.')[-1], json.dumps(a['click'], sort_keys=True)) for a in json.load(open(sys.argv[1]))['actions']]"
ctl action-inventory-assigned-to-me-catch 0 '^container25 \{"assigned_to_me": true, "within": "listView5"\}$' '^actionButton12 \{"assigned_to_me": true, "within": "listView5"\}$' -- python3 -c "$INBX" $T/pr-inbox-ai.json
ctl action-inventory-assigned-to-me-pass 0 '^container20 \{"within": "listView4"\}$' '^actionButton8 \{"within": "listView4"\}$' -- python3 -c "$INBX" $T/pr-inbox-ai.json
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['actions']=[a for a in d['actions'] if not a['id'].endswith('TaskInbox.container20')]; json.dump(d, open(sys.argv[2], 'w'))" $FX/actions/pr-unassigned.json $T/pr-unassigned-alone.json
python3 $B/gen_journeys.py --actions $FX/actions/pr-unassigned.json --out-dir $T/gun > /dev/null 2>&1
python3 $B/gen_journeys.py --actions $T/pr-unassigned-alone.json --out-dir $T/gun2 > /dev/null 2>&1
UNJ="import json,sys; j=json.load(open(sys.argv[1])); print('route:', j.get('_route')); [print('act', a['do'], a.get('widget'), a.get('unassigned'), a.get('has')) for s in j['steps'] for a in s['actions'] if a['do'] != 'wait']"
ctl gen-journeys-unassigned-route-pass 0 '^route: container25 lists only the tasks assigned to the user .*container20 \(listView4\) can hold an unassigned one: took it$' '^act click container20 True Assign to me$' '^act click actionButton19 None None$' '!^act click container25' \
  -- python3 -c "$UNJ" $T/gun/journeys/Approver/act-PurchaseApprovals.Task_Approver.actionButton19.journey.json
ctl gen-journeys-unassigned-no-route-catch 0 '^route: container25 lists only the tasks assigned to the user and no other open-task action on PurchaseApprovals\.TaskInbox lists unassigned ones: the button has no route' '^act click container25 True Assign to me$' \
  -- python3 -c "$UNJ" $T/gun2/journeys/Approver/act-PurchaseApprovals.Task_Approver.actionButton19.journey.json
ctl gen-journeys-unassigned-own-list-catch 0 '^route: actionButton12 sits in listView5, which holds only the tasks assigned to the user .* it can never render there$' \
  -- python3 -c "$UNJ" $T/gun/journeys/Approver/act-PurchaseApprovals.TaskInbox.actionButton12.journey.json
ctl gen-journeys-unassigned-assigned-task-pass 0 '^route: None$' '^act click container25 None None$' '^act click actionButton8 None None$' '!unassigned' '!True' \
  -- python3 -c "$UNJ" $T/gun/journeys/Approver/act-PurchaseApprovals.Task_Approver.actionButton8.journey.json
ctl journeys-engine-unassigned-patch-pass 0 'V\.topmost\(page, a\.widget, a\.near, a\.unassigned \? \{ has: a\.has \} : null\)' -- grep -F "a.unassigned" $B/run_journeys.py
# --- PR-B7 / PR-B8 (run 3): a pinned popup action right after a click that left the page unknown stays on its page; the
# step with a Pop-up menu item has no guard on the closed menu. Golden: P05's New Attachment / Add records, verbatim
ctl process-popup-unknown-landing-pass 0 '^COMPILED P05 +Add a wizard attachment +legs proc-p05-01$' -- python3 $B/process_journeys.py $FX/processes/pr-popup-unknown.md --actions $FX/actions/pr-popup-unknown.json --out-dir $T/ppu
sed 's/^1\. \[Requester\] Click "New Attachment".*$/1. [Requester] Fill "fileManager1" with "upg-seed.jpeg"/; /^2\. \[Requester\] Fill/d; s/^3\. /2. /' $FX/processes/pr-popup-unknown.md > $T/pr-popup-first.md
PPS="import json,sys; j=json.load(open(sys.argv[1])); [print('step', s['name'], '|', ' '.join(a['do'] + ':' + str(a.get('widget') or a.get('item')) for a in s['actions'])) for s in j['steps']]"
ctl process-popup-unknown-landing-steps-pass 0 '^step 1\. open PurchaseApprovals\.NewRequest_Step1 \(actionButton2\) \| click:actionButton2$' '^step 1\. Click "New Attachment" \| click:actionButton5$' '^step 2\. Fill "fileManager1" with "upg-seed\.jpeg"; 3\. Click "Add" \| upload:fileManager1 click:actionButton1$' '!container25' -- python3 -c "$PPS" $T/ppu/journeys/Requester/proc-p05-01.journey.json
# the same "Add" as the FIRST step of a leg is not on a known page: it is walked from the role home (no guard fires)
python3 $B/process_journeys.py $T/pr-popup-first.md --actions $FX/actions/pr-popup-unknown.json --out-dir $T/ppu2 > /dev/null 2>&1
ctl process-popup-first-step-catch 0 '^step 2\. open PurchaseApprovals\.Task_Approver \(container25\) \| click:container25$' '!actionButton5' -- python3 -c "$PPS" $T/ppu2/journeys/Requester/proc-p05-01.journey.json
PTB="import sys; sys.path.insert(0, '$B'); import process_journeys as P; c = object.__new__(P.Compiler)
class G:
    def __init__(s, t): s.t = t
    def tab_acts(s, h, page): return s.t, []
op = {'name': 'n', 'actions': [{'do': 'click', 'widget': 'actionButton16'}], 'need': '.mx-name-actionButton16'}
for t in ([{'do': 'menu', 'widget': 'pop_upMenu5'}], [{'do': 'click', 'widget': 'tabPage2', 'settleMs': 800}], []):
    c.gen = G(t); r = c.tabbed({'click': 'actionButton16'}, 'P.Page', dict(op, actions=list(op['actions']))); print([a['do'] for a in r['actions']], r['need'])"
ctl process-tabbed-menu-no-guard-pass 0 "^\['menu', 'click'\] None$" -- python3 -c "$PTB"
ctl process-tabbed-tab-keeps-guard-catch 0 "^\['click', 'click'\] \.mx-name-tabPage2$" "^\['click'\] \.mx-name-actionButton16$" -- python3 -c "$PTB"

# --- change ledger (trust.md section 3): trailers, appcommit.sh, changelog.py, the gate's Changes line ---------------------------
# A fixture app repo is built here with labelled and unlabelled commits (no model needed: the ledger reads git only).
# TR-3: stepupdate's commits carry Changed-By / Upgrade-Change; hand commits go through appcommit.sh; a bare commit is "unlabelled".
CL=$T/cl; rm -rf "$CL"; mkdir -p "$CL"
tr_commit() { # tr_commit REPO SUBJECT [BY KIND RULE]: toolkit-style commit (with trailers when BY is given) of one new file
  local r=$1 s=$2; echo "$s" > "$r/f-$(echo "$s" | tr -c 'A-Za-z0-9\n' _ | head -c 20).txt"; git -C "$r" add -A .
  if [ -n "${3:-}" ]; then git -C "$r" commit -qm "$s" -m "$(printf 'Changed-By: %s\nUpgrade-Change: %s %s' "$3" "$4" "$5")"; else git -C "$r" commit -qm "$s"; fi
}
mkledger() { # mkledger NAME [unlabelled]: before-run commit, the run-start marker, 2 toolkit, 1 agent, 1 person [, 1 bare commit]
  local r=$CL/$1; rm -rf "$r"; mkdir -p "$r"; git -C "$r" init -q
  tr_commit "$r" "before the run" ; tr_commit "$r" "original" toolkit config run-start
  tr_commit "$r" "step: ModA 1.0 (stepupdate, idcheck PASS)" toolkit module-update stepupdate
  tr_commit "$r" "convert 11.12.6" toolkit convert mx-convert
  echo agent > "$r/page.txt"; bash $B/appcommit.sh --app "$r" --by agent --kind repair --rule repair-row-22 --why "snippet carrier replaced: WorkflowView to System.Workflow" -- page.txt > /dev/null
  echo person > "$r/App.mpr"; bash $B/appcommit.sh --app "$r" --by person --kind config --rule "decision S-1" --why "kept Viewer3D at the old version" -- App.mpr > /dev/null
  [ "${2:-}" != unlabelled ] || tr_commit "$r" "quick fix by hand"
}
mkledger lg unlabelled; mkledger lgok
printf 'Customer.Name # a renamed label the owner approved\nlog.start Warning # known noise of the old build\n' > $CL/allow.txt
printf 'S-1 | modules: Viewer3D | module | keep old version | no successor yet | Pat | CONFIRMED | closes by: widgets PASS\n' > $CL/DECISIONS.md
CHG="python3 $B/changelog.py --app $CL/lg --work $CL/w --accept ALLOW=$CL/allow.txt --decisions $CL/DECISIONS.md"
ctl changelog-counts-pass 0 '^Changes: 5 \(toolkit 2, agent 1, person 1, unlabelled 1\)$' -- $CHG
ctl changelog-clean-counts-pass 0 '^Changes: 4 \(toolkit 2, agent 1, person 1, unlabelled 0\)$' -- python3 $B/changelog.py --app $CL/lgok --work $CL/wok
ctl changelog-unlabelled-listed-catch 0 '\| unlabelled \| - \| - \| quick fix by hand' '1 unlabelled commit\(s\) need a decision' -- cat $CL/w/CHANGES.md
ctl changelog-clean-no-decision-pass 0 '!unlabelled \|' '!need a decision' '!quick fix' -- cat $CL/wok/CHANGES.md
ctl changelog-by-kind-rule-why-pass 0 '\| toolkit \| module-update \| stepupdate \| step: ModA 1\.0' '\| agent \| repair \| repair-row-22 \| snippet carrier replaced: WorkflowView to System\.Workflow' \
  '\| person \| config \| decision S-1 \| kept Viewer3D at the old version' -- cat $CL/w/CHANGES.md
ctl changelog-model-changed-pass 0 '\| person \| config \| decision S-1 .*model changed' -- cat $CL/w/CHANGES.md
ctl changelog-marker-excluded-pass 0 '!before the run' '!\| original' 'Run start \(not a change\): `[0-9a-f]+ original' -- cat $CL/w/CHANGES.md
ctl changelog-allow-reason-pass 0 '## Accepted differences' 'ALLOW \| Customer\.Name \| a renamed label the owner approved' 'ALLOW \| log\.start Warning \| known noise of the old build' -- cat $CL/w/CHANGES.md
ctl changelog-decisions-pass 0 '## Decisions' 'S-1 \| modules: Viewer3D \| module \| keep old version \| no successor yet \| Pat \| CONFIRMED' -- cat $CL/w/CHANGES.md
# a commit with only one of the two trailers is not labelled
git clone -q $CL/lgok $CL/lgpart; git -C $CL/lgpart commit -q --allow-empty -m "half labelled" -m "Changed-By: toolkit"
ctl changelog-partial-trailer-catch 0 '^Changes: 5 \(toolkit 2, agent 1, person 1, unlabelled 1\)$' -- python3 $B/changelog.py --app $CL/lgpart --work $CL/wp
ctl changelog-since-pass 0 '^Changes: 2 \(toolkit 0, agent 1, person 1, unlabelled 0\)$' -- python3 $B/changelog.py --app $CL/lgok --work $CL/ws --since HEAD~2
ctl changelog-not-git-invalid 2 'is not a git repository' -- python3 $B/changelog.py --app $CL/w --work $CL/wn
# appcommit.sh: explicit paths only
git clone -q $CL/lgok $CL/ac; echo a > $CL/ac/a.txt; echo b > $CL/ac/b.txt; echo c > $CL/ac/c-unnamed.txt; git -C $CL/ac add b.txt
ctl appcommit-all-refused-catch 2 'refused: -A commits more than the paths' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r --why w -A
ctl appcommit-no-paths-catch 2 'refused: no paths after --' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r --why w --
ctl appcommit-no-dashdash-catch 2 'unknown argument' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r --why w a.txt
ctl appcommit-dot-refused-catch 2 "refused: path '.'" -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r --why w -- .
ctl appcommit-outside-refused-catch 2 'is outside the repository' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r --why w -- /etc/hostname
ctl appcommit-by-toolkit-refused-catch 2 '--by agent\|person' -- bash $B/appcommit.sh --app $CL/ac --by toolkit --kind repair --rule r --why w -- a.txt
ctl appcommit-bad-kind-refused-catch 2 '--kind:' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind fix --rule r --why w -- a.txt
ctl appcommit-no-why-catch 2 '--why is required' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule r -- a.txt
ctl appcommit-named-path-pass 0 'committed [0-9a-f]+ \(agent, repair repair-row-9\): fix a' -- bash $B/appcommit.sh --app $CL/ac --by agent --kind repair --rule repair-row-9 --why "fix a" -- a.txt
ctl appcommit-trailers-pass 0 '^Changed-By: agent$' '^Upgrade-Change: repair repair-row-9$' -- git -C $CL/ac log -1 --format=%B
ctl appcommit-other-index-untouched-pass 0 '^A  b\.txt$' '^\?\? c-unnamed\.txt$' '!a\.txt' -- git -C $CL/ac status --short
ctl appcommit-nothing-changed-pass 0 'nothing changed in the given paths' -- bash $B/appcommit.sh --app $CL/ac --by person --kind config --rule c --why "again" -- a.txt
# slice 5: commits name their step (Upgrade-Step trailer); changelog.py hands them to steps.py done. A made-up shop app: modules step, a P-n alias step.
SX=$T/stx; rm -rf $SX; mkdir -p $SX/w $SX/w-none; SX=$(cd $SX && pwd -P); SXS="python3 $B/steps.py"
$SXS open --work $SX/w --topic modules --title "Routine module updates" --say "The plan holds 2 module updates." > /dev/null
$SXS open --work $SX/w --topic widget:Gridmod --title "Order grid" --say "The order grid needs a decision." --alias P-3 > /dev/null
mkdir -p $SX/app; git -C $SX/app init -q; echo shop > $SX/app/shop.txt; git -C $SX/app add -A .
git -C $SX/app commit -qm "original" -m "$(printf 'Changed-By: toolkit\nUpgrade-Change: config run-start')"
echo s1 > $SX/app/s1.txt; echo s2 > $SX/app/s2.txt; echo s3 > $SX/app/s3.txt; echo s4 > $SX/app/s4.txt
ctl appcommit-step-unknown-refused-catch 2 "unknown step 'S-9'" -- bash $B/appcommit.sh --app $SX/app --by agent --kind repair --rule repair-row-9 --why "fix the order grid" --step S-9 --work $SX/w -- s1.txt
ctl appcommit-step-unknown-nothing-committed-pass 0 '^0$' -- sh -c "git -C $SX/app log --oneline --grep='fix the order grid' | wc -l | tr -d ' '"
ctl appcommit-step-needs-work-catch 2 '--step needs the run.s work folder' -- env -u UPG_STEPS_WORK -u UPG_STEP bash $B/appcommit.sh --app $SX/app --by agent --kind repair --rule r --why "fix it" --step S-1 -- s1.txt
ctl appcommit-step-trailer-pass 0 'committed [0-9a-f]+ \(agent, repair repair-row-9, step S-1\): fix the order grid' -- bash $B/appcommit.sh --app $SX/app --by agent --kind repair --rule repair-row-9 --why "fix the order grid" --step S-1 --work $SX/w -- s1.txt
ctl appcommit-step-trailer-in-commit-pass 0 '^Changed-By: agent$' '^Upgrade-Change: repair repair-row-9$' '^Upgrade-Step: S-1$' -- git -C $SX/app log -1 --format=%B
ctl appcommit-step-alias-written-as-step-pass 0 '^Upgrade-Step: S-2$' '!P-3' -- sh -c "bash $B/appcommit.sh --app $SX/app --by agent --kind convert --rule decision-alias --why 'swap the order grid' --step P-3 --work $SX/w -- s2.txt > /dev/null; git -C $SX/app log -1 --format=%B"
ctl appcommit-no-step-no-trailer-pass 0 '^Changed-By: person$' '!Upgrade-Step' -- sh -c "bash $B/appcommit.sh --app $SX/app --by person --kind config --rule c --why 'tidy the shop theme' -- s3.txt > /dev/null; git -C $SX/app log -1 --format=%B"
# steps.py trailer: what the toolkit's own scripts add
ctl steps-trailer-module-update-pass 0 '^Upgrade-Step: S-1$' -- env UPG_STEPS_WORK=$SX/w $SXS trailer --kind module-update
ctl steps-trailer-kind-without-step-catch 0 '^rc=0$' '^end$' '!Upgrade-Step' -- sh -c "UPG_STEPS_WORK=$SX/w $SXS trailer --kind config; echo rc=\$?; echo end"
ctl steps-trailer-env-step-wins-pass 0 '^Upgrade-Step: S-2$' -- env UPG_STEPS_WORK=$SX/w UPG_STEP=P-3 $SXS trailer --kind config
ctl steps-trailer-no-steps-file-pass 0 '!Upgrade-Step' -- env UPG_STEPS_WORK=$SX/w-none $SXS trailer --kind module-update
# changelog.py: the step column, "no step", and steps.py done once per commit
git -C $SX/app commit -q --allow-empty -m "bare tweak by hand" -m "$(printf 'Changed-By: agent\nUpgrade-Change: repair repair-row-1')"
git -C $SX/app commit -q --allow-empty -m "repair: a step nobody opened" -m "$(printf 'Changed-By: agent\nUpgrade-Change: repair repair-row-1\nUpgrade-Step: S-9')"
python3 $B/changelog.py --app $SX/app --work $SX/w > /dev/null
ctl changelog-step-column-pass 0 '\| fix the order grid \(`[0-9a-f]{7}`\) \|.* \| S-1 \|$' '\| swap the order grid \(`[0-9a-f]{7}`\) \|.* \| S-2 \|$' '\| evidence \| step \|' -- cat $SX/w/CHANGES.md
ctl changelog-no-step-listed-catch 0 '\| tidy the shop theme .* \| no step \|$' '\| bare tweak by hand .* \| no step \|$' '2 commit\(s\) name no step' -- cat $SX/w/CHANGES.md
ctl changelog-unknown-step-catch 0 '\| repair: a step nobody opened .* \| unknown step S-9 \|$' -- cat $SX/w/CHANGES.md
ctl changelog-done-second-step-pass 0 '^S-2 commits: 1 swap the order grid$' -- sh -c "python3 $B/steps.py show --work $SX/w --json | python3 -c 'import json,sys; r=json.load(sys.stdin)[1]; print(r[\"id\"], \"commits:\", len(r[\"done\"][\"commits\"]), r[\"done\"][\"commits\"][0][\"say\"])'"
ctl changelog-done-say-is-the-subject-pass 0 '^S-1 commits: 1 fix the order grid$' -- sh -c "python3 $B/steps.py show --work $SX/w --json | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r[\"id\"], \"commits:\", len(r[\"done\"][\"commits\"]), r[\"done\"][\"commits\"][0][\"say\"])'"
ctl changelog-rerun-adds-no-event-pass 0 '^same$' -- sh -c "a=\$(wc -l < $SX/w/steps.jsonl); python3 $B/changelog.py --app $SX/app --work $SX/w > /dev/null; [ \$a = \$(wc -l < $SX/w/steps.jsonl) ] && echo same || echo changed"
ctl changelog-unknown-step-not-recorded-catch 0 '^0$' -- sh -c "grep -c 'S-9' $SX/w/steps.jsonl || true"
ctl changelog-without-steps-file-pass 0 '\| S-1 \|$' '!name no step' '!CREATED' -- sh -c "python3 $B/changelog.py --app $SX/app --work $SX/w-none --out $SX/none.md > /dev/null; cat $SX/none.md; test -f $SX/w-none/steps.jsonl && echo CREATED; true"
# the gate summary: the Changes line right after the Progress line; unlabelled commits are a decision item, never a FAIL
ctl gate-changes-line-pass 0 'Overall: \*\*PASS\*\*' '^Changes: 4 \(toolkit 2, agent 1, person 1, unlabelled 0\)$' '!changes: needs a decision' -- gcase chok APP_REPO=$CL/lgok
gcount() { gcase "$@" | grep -c '^Changes:'; }   # the line is printed on stdout AND written into the summary: 2
ctl gate-changes-stdout-line-pass 0 '^2$' -- gcount chcnt APP_REPO=$CL/lgok
ctl gate-changes-after-progress-pass 0 '^Progress: ' '^Changes: 4 ' -- sh -c "grep -A1 '^Progress:' $GI/w/gatechok/gate-summary.md"
ctl gate-changes-unlabelled-catch 0 'Overall: \*\*PASS\*\*' '^Changes: 5 \(toolkit 2, agent 1, person 1, unlabelled 1\)$' '^- changes: needs a decision: 1 commit\(s\) in the app repo carry no Changed-By' -- gcase chun APP_REPO=$CL/lg
ctl gate-changes-unlabelled-keeps-rungs-pass 0 '\| 1 \| build \| PASS \|' '!\| FAIL \|' -- cat $GI/w/gatechun/gate-summary.md
ctl gate-changes-no-repo-pass 0 'Overall: \*\*PASS\*\*' '!Changes:' -- gcase chno
ctl gate-changes-ledger-written-pass 0 '^Changes: 5 ' -- sh -c "head -3 $GI/w/CHANGES.md | tail -1"
ctl gate-changes-accept-files-pass 0 '\| ALLOW \| x \| \(no reason written\)' '\| SMOKE_SHOT_ACCEPT \| x \|' '\| LOG_ALLOW \| x \|' '!\| JOURNEY_SHOT_ACCEPT' -- sh -c "grep -E 'ALLOW|ACCEPT' $GI/w/CHANGES.md"
# stepupdate and the pipeline: the toolkit's own commits carry the trailers
S=$T/step; newapp trl '1 1.0 Fine\n'
ctl stepupdate-trailers-pass 0 'committed [0-9a-f]{7}' -- env UPG_UPDATE_CMD="bash $FX/bin/fake-update.sh $S {module} {mpr}" bash $B/stepupdate.sh $S/trl $S/trl.plan
ctl stepupdate-trailers-step-commit-catch 0 '^step: Fine 1\.0 \(stepupdate, idcheck PASS\)$' '^Changed-By: toolkit$' '^Upgrade-Change: module-update stepupdate$' -- git -C $S/trl log -1 --format=%B
ctl stepupdate-trailers-gitignore-commit-pass 0 '^stepupdate: ignore \.stepupdate/$' '^Changed-By: toolkit$' '^Upgrade-Change: config stepupdate-gitignore$' -- git -C $S/trl log --grep='^stepupdate: ignore' -1 --format=%B
ctl stepupdate-trailers-changelog-pass 0 '^Changes: 2 \(toolkit 2, agent 0, person 0, unlabelled 0\)$' -- python3 $B/changelog.py --app $S/trl --work $CL/wt --since HEAD~2
newapp stp '1 1.0 Fine\n'; newapp stq '1 1.0 Fine\n'
ctl stepupdate-step-trailer-pass 0 'committed [0-9a-f]{7}' -- env UPG_STEPS_WORK=$SX/w UPG_UPDATE_CMD="bash $FX/bin/fake-update.sh $S {module} {mpr}" bash $B/stepupdate.sh $S/stp $S/stp.plan
ctl stepupdate-step-trailer-in-commit-pass 0 '^step: Fine 1\.0 \(stepupdate, idcheck PASS\)$' '^Upgrade-Change: module-update stepupdate$' '^Upgrade-Step: S-1$' -- git -C $S/stp log -1 --format=%B
ctl stepupdate-no-steps-no-trailer-catch 0 'committed [0-9a-f]{7}' -- env UPG_STEPS_WORK=$SX/w-none UPG_UPDATE_CMD="bash $FX/bin/fake-update.sh $S {module} {mpr}" bash $B/stepupdate.sh $S/stq $S/stq.plan
ctl stepupdate-no-steps-no-trailer-in-commit-pass 0 '^Changed-By: toolkit$' '!Upgrade-Step' -- git -C $S/stq log -1 --format=%B
ctl pipeline-dry-trailers-pass 0 "commit -am 'repair: sync java dependencies, jardedupe' \(Upgrade-Change: repair repair-row-2-3\)" "commit -am 'build: regenerated stubs' \(Upgrade-Change: config build-stubs\)" -- bash $B/cloud/upgrade-pipeline.sh --app-dir $V/papp --source 10.24.26.1 --target 11.15.0.1 --work $V/pw --only build --dry-run
newapp jt '1 1.0 Fine\n'
mkdir -p $S/jt/userlib $S/jt/vendorlib; : > $S/jt/userlib/pdfbox-2.0.30.jar; : > $S/jt/vendorlib/pdfbox-3.0.7.jar
(cd $S/jt && git add userlib vendorlib && git commit -qm "base jars")
ctl stepupdate-trailers-jar-run-pass 0 'jar cleanup \(jardedupe --apply\)' -- env UPG_VENDORLIB_SYNCED=1 UPG_UPDATE_CMD="bash $FX/bin/fake-update.sh $S {module} {mpr}" bash $B/stepupdate.sh $S/jt $S/jt.plan
ctl stepupdate-trailers-jar-commit-catch 0 '^jar: jardedupe --apply after module updates$' '^Changed-By: toolkit$' '^Upgrade-Change: repair repair-row-3$' -- git -C $S/jt log --grep='^jar:' -1 --format=%B
# the pipeline's commit_app (extracted from the script, run on a throwaway repo): subject unchanged, trailers from its arguments
PL=$T/plapp; rm -rf $PL; mkdir -p $PL; git -C $PL init -q; echo a > $PL/a.txt; git -C $PL add a.txt; git -C $PL commit -qm base
pl_commit() { ( APP=$PL; DRY=0; LOG=$T/pl.log; say() { :; }; eval "$(sed -n '/^git_app()/p;/^commit_app()/,/^}/p' $B/cloud/upgrade-pipeline.sh)"; echo b > $PL/b.txt; commit_app "convert 11.12.6" convert mx-convert; git -C $PL log -1 --format=%B ); }
ctl pipeline-commit-app-trailers-catch 0 '^convert 11\.12\.6$' '^Changed-By: toolkit$' '^Upgrade-Change: convert mx-convert$' -- pl_commit
# --- proposal (trust spec section 2, TR-1): the upgrade proposal a person signs before anything changes -----------------
# The work folders are built by the REAL triage tools over fixture models (localedits.py, replacement_check.py,
# dojo_report.py, release_impact.py), so the parsers in bin/proposal.py read real output; plan.txt, kept.txt and stranded.md
# are written by hand because a person or the triage skill writes them. Each must-catch has a must-pass next to it.
if [ -z "$only" ] || printf '%s\n' proposal-x pipeline-propose-x gate-proposal-x | grep -Eq "$only"; then
PR=$T/proposal; rm -rf $PR; mkdir -p $PR
for m in dojo-react replace-wc3 local-edit pkg-administration replace-snippet replace-oidc2; do model $m > /dev/null; done
# mkw NAME [kept]: work folder $PR/NAME with the triage outputs; with "kept" DataWidgets is on kept.txt
mkw() {
  local w=$PR/$1; mkdir -p $w/state $PR/cache-$1
  (cd $M/pkg-administration && python3 -c "import zipfile; z=zipfile.ZipFile('$PR/cache-$1/23513-4.1.0.mpk','w'); z.write('App.mpr'); z.close()")
  UPG_CACHE=$PR/cache-$1 UPG_MXCLI=/usr/bin/false python3 $B/localedits.py $M/local-edit/App.mpr --module Administration --json $w/localedits.json --md $w/localedits.md > /dev/null
  python3 $B/dojo_report.py $M/dojo-react --to 11.12.5 --table $FX/dojo-successors.tsv --out $w/dojo-react.md > /dev/null
  python3 $B/replacement_check.py $M/replace-wc3 --to 11.12.5 --out $w/replacements.md > /dev/null
  python3 $B/release_impact.py --brain $RB --from 10.24.16 --to 11.12.2 --out $w/release-impact.md > /dev/null
  printf '# plan\n23513 4.1.0 Administration\n116540 3.11.7 DataWidgets\n99 1.0.0 Plainmod\n' > $w/plan.txt
  printf 'Administration 4.0.0 -> 4.1.0\nDataWidgets 2.30.4 -> 3.11.7\nPlainmod 0.9.0 -> 1.0.0\n' > $w/module-jumps.txt
  printf -- '- PDFReader: only 1.0.0 exists, jars pdfbox\n' > $w/stranded.md
  printf 'app: 10.24.26.1\n' > $w/versions.txt
  [ "${2:-}" != kept ] || printf 'DataWidgets pre-convert update refused\n' > $w/kept.txt
}
cat > $PR/prop.sh <<'SH'
#!/bin/bash
# prop.sh WORK [proposal.py args]: one proposal run, the exit code is proposal.py's
w=$1; shift
PROPOSAL_TODAY=2026-10-15 python3 "$B/proposal.py" --work "$w" --source 10.24.26.1 --target 11.15.0.1 "$@"
SH
cat > $PR/sec.sh <<'SH'
#!/bin/bash
# sec.sh WORK N: print section N of PROPOSAL.md
sed -n "/^## $2\\./,/^## $(($2 + 1))\\./p" "$1/PROPOSAL.md"
SH
chmod +x $PR/prop.sh $PR/sec.sh
export B
mkw kept kept; mkw plain
bash $PR/prop.sh $PR/kept > /dev/null; bash $PR/prop.sh $PR/plain > /dev/null
# the catch: kept module, RED local edit, stranded module and a widget with no successor are decisions, never "done by the toolkit"
ctl proposal-unsigned-exit14-catch 14 'proposal awaits sign-off' 'PROPOSAL\.md' -- bash $PR/prop.sh $PR/kept
ctl proposal-kept-widget-section3-catch 0 '^- \[P-[0-9]+\] module: DataWidgets$' '^- \[P-[0-9]+\] widget: Stuck\.mpk' '^- \[P-[0-9]+\] module: Administration$' '^- \[P-[0-9]+\] module: PDFReader$' \
  'evidence: .*kept at its version by the update step' -- bash $PR/sec.sh $PR/kept 3
ctl proposal-kept-widget-not-in-section2-catch 0 'module update Plainmod 0\.9\.0 -> 1\.0\.0' 'predicted repair R37 .*repair row 21 \(CE6779\)' '!DataWidgets' '!Stuck' '!Administration' '!PDFReader' -- bash $PR/sec.sh $PR/kept 2
ctl proposal-plain-module-section2-pass 0 'module update DataWidgets 2\.30\.4 -> 3\.11\.7' 'module update Plainmod' -- bash $PR/sec.sh $PR/plain 2
ctl proposal-plain-module-not-section3-pass 0 '!module: DataWidgets' '!module: Plainmod' 'widget: Stuck\.mpk' -- bash $PR/sec.sh $PR/plain 3
# re-architecture catalogue (playbooks/rearchitecture.md): a section-3 item that fits RA-1's match gets the RA options and cites the id; a non-matching item does not
mkw ra kept; python3 - "$PR/ra/dojo-react.md" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read().splitlines()
i = next(k for k, l in enumerate(t) if l.startswith("| can't move") and "Stuck" in l)
t.insert(i + 1, t[i].replace("Stuck.mpk", "com.mendix.widget.custom.mxtreetable.MxTreeTable").replace("Stuck", "MxTreeTable"))
open(p, "w").write("\n".join(t) + "\n")
PY
bash $PR/prop.sh $PR/ra > /dev/null
ctl proposal-ra1-match-prefills-catch 0 '^- \[P-[0-9]+\] widget: com\.mendix\.widget\.custom\.mxtreetable' 'nested Data grid 2.*\[RA-1, idea, playbooks/rearchitecture\.md\]' 'replace by Data grid 2 with a parent-child expand' -- bash $PR/sec.sh $PR/ra 3
ctl proposal-ra1-nonmatch-untouched-pass 0 '^- \[P-[0-9]+\] widget: Stuck\.mpk' '\[RA-10, ' '!RA-1,' -- sh -c "sed -n '/widget: Stuck.mpk/,/answer:/p' $PR/ra/PROPOSAL.md"
# RA-19 (HTML/JavaScript Snippet) and RA-20 (OIDC version upgrade): the triage tools run over models that hold the Dojo snippet packages and OIDC 2.4.0 without UserCommons
mkw sn kept
python3 $B/dojo_report.py $M/replace-snippet --to 11.12.5 --table $B/../playbooks/dojo-successors.tsv --out $PR/sn/dojo-react.md > /dev/null
python3 $B/replacement_check.py $M/replace-oidc2 --to 11.12.5 --out $PR/sn/replacements.md > /dev/null
bash $PR/prop.sh $PR/sn > /dev/null
ctl proposal-ra19-snippet-prefills-catch 0 '^- \[P-[0-9]+\] widget: HTMLSnippet\.mpk 3\.9\.7' '^- \[P-[0-9]+\] widget: snippetjs\.mpk 1\.3\.1' 'pure HTML to the HTML Element widget .* \| JavaScript with behaviour to a JavaScript action called from a nanoflow, triggered by the Events widget .* \| DOM-heavy or reusable UI to a pluggable' '\[RA-19, idea, playbooks/rearchitecture\.md\]' '!\[RA-9, ' -- bash $PR/sec.sh $PR/sn 3
ctl proposal-ra20-oidc-prefills-catch 0 '^- \[P-[0-9]+\] module: R2 OIDC SSO without User Commons' 'step through the breaking versions in order.*\[RA-20, idea, playbooks/rearchitecture\.md\]' '!\[RA-16, ' -- bash $PR/sec.sh $PR/sn 3
# RA-19 must bind to the snippet package item only: an item that merely lists HTMLSnippet.mpk among many widgets (R9, found on a real app) is not a snippet decision
ctl proposal-ra19-evidence-mention-not-matched-pass 0 '^R9 item: RA-19 no$' '^snippet item: RA-19 yes$' '^snippet item: RA-9 no$' -- python3 -I -c "
import sys; sys.path.insert(0, '$B'); import proposal
ra = {e['id']: e['rx'] for e in proposal.load_ra()}
r9 = 'widget R9 React 19 (Studio Pro 11.6): every widget at its latest version replacements.md row R9 HIT: widgets/: Badge.mpk, Charts.mpk, HTMLSnippet.mpk ... (38 files)'
sn = 'widget HTMLSnippet.mpk 3.9.8 dojo-react.md: can move: HTMLSnippet.widget.HTMLSnippet (28); the successor depends on the content of each snippet'
yn = lambda b: 'yes' if b else 'no'
print('R9 item: RA-19', yn(ra['RA-19'].search(r9)))
print('snippet item: RA-19', yn(ra['RA-19'].search(sn)))
print('snippet item: RA-9', yn(ra['RA-9'].search(sn)))
"
ctl proposal-ra19-ra20-nonmatch-untouched-pass 0 '^- \[P-[0-9]+\] widget: Stuck\.mpk' '!RA-19' '!RA-20' -- sh -c "sed -n '/widget: Stuck.mpk/,/answer:/p' $PR/ra/PROPOSAL.md"
mkw ra-none kept
ctl proposal-ra-missing-file-pass 0 'widget: Stuck\.mpk' 'widget: com\.mendix\.widget\.custom\.mxtreetable|widget: Stuck' '!\[RA-' -- sh -c "bash $PR/prop.sh $PR/ra-none --ra-file /nonexistent > /dev/null; sed -n '/^## 3\\./,/^## 4\\./p' $PR/ra-none/PROPOSAL.md"
ctl proposal-six-sections-in-order-pass 0 '^## 1\. Summary\|## 2\. Done by the toolkit\|## 3\. Needs your decision before we start\|## 4\. Needs a person anyway\|## 5\. Human effort\|## Testing plan\|## 6\. Sign-off\|$' -- sh -c "grep -E '^## ' $PR/kept/PROPOSAL.md | tr '\n' '|'; echo"
# signed -> 0 (the unanswered items take their recommendation, P-n lines CONFIRMED); the same folder first answered P-1 by hand
mkw signed kept; bash $PR/prop.sh $PR/signed > /dev/null
printf 'P-1 | Administration | module | replace with the Marketplace equivalent | owner chose | Jan | CONFIRMED | closes by: x\n' > $PR/signed/DECISIONS.md
sedi 's/^Status: open$/Signed-off: Jan Jansen 2026-10-15/' $PR/signed/PROPOSAL.md
ctl proposal-signed-continues-pass 0 'signed by Jan Jansen on 2026-10-15' '[0-9] unanswered section-3 item' -- bash $PR/prop.sh $PR/signed
ctl proposal-signed-records-p-lines-pass 0 '^P-1 .*replace with the Marketplace equivalent' '^P-[2-9] .*accepted with the sign-off of Jan Jansen .*\| CONFIRMED \|' '!ASSUMED' -- cat $PR/signed/DECISIONS.md
ctl proposal-signed-status-pass 0 '^signed$' -- python3 $B/proposal.py --status --work $PR/signed
# PAUSED -> 15
mkw paused kept; bash $PR/prop.sh $PR/paused > /dev/null; sedi 's/^Status: open$/Status: PAUSED waiting for the vendor of PDFReader/' $PR/paused/PROPOSAL.md
ctl proposal-paused-exit15-catch 15 'PAUSED by the owner: waiting for the vendor of PDFReader' 'Resume' -- bash $PR/prop.sh $PR/paused
ctl proposal-unsigned-status-pass 0 '^unsigned$' -- python3 $B/proposal.py --status --work $PR/kept
ctl proposal-no-file-status-pass 0 '^none$' -- python3 $B/proposal.py --status --work $PR/cache-kept
# a Signed-off line without a date or a Status line without a reason is not a sign-off
mkw halfsigned kept; bash $PR/prop.sh $PR/halfsigned > /dev/null; sedi 's/^Status: open$/Signed-off: Jan Jansen/' $PR/halfsigned/PROPOSAL.md
ctl proposal-signoff-without-date-catch 14 'awaits sign-off' -- bash $PR/prop.sh $PR/halfsigned
# unattended: nothing signed, ASSUMED (unattended) recorded, exit 0; an attended run writes no ASSUMED line
mkw unatt kept
ctl proposal-unattended-assumed-catch 0 'not signed \(unattended\)' -- bash $PR/prop.sh $PR/unatt --unattended
ctl proposal-unattended-decisions-catch 0 '^P-0 \| proposal .*\| ASSUMED \(unattended\) \|' '^P-[1-9] .*\| ASSUMED \(unattended\) \|' '!CONFIRMED' -- cat $PR/unatt/DECISIONS.md
ctl proposal-unattended-stays-unsigned-catch 0 '^unsigned$' -- python3 $B/proposal.py --status --work $PR/unatt
ctl proposal-attended-no-assumed-pass 0 '!ASSUMED' 'no DECISIONS.md' -- sh -c "test -e $PR/kept/DECISIONS.md && cat $PR/kept/DECISIONS.md || echo 'no DECISIONS.md'"
# a changed plan after the sign-off clears it and asks again; an unchanged plan keeps it
mkw changed kept; bash $PR/prop.sh $PR/changed > /dev/null; sedi 's/^Status: open$/Signed-off: Jan Jansen 2026-10-15/' $PR/changed/PROPOSAL.md
ctl proposal-unchanged-plan-keeps-signoff-pass 0 'signed by Jan Jansen' -- bash $PR/prop.sh $PR/changed
printf '88 2.0.0 Newmod\n' >> $PR/changed/plan.txt
ctl proposal-changed-plan-reasks-catch 14 'awaits sign-off' -- bash $PR/prop.sh $PR/changed
ctl proposal-changed-block-catch 0 '^## Changed since signed \(Jan Jansen, 2026-10-15\)' '^- added: 2: - module update Newmod \? -> 2\.0\.0' '^Previously signed-off: Jan Jansen 2026-10-15 \(cleared' '!^Signed-off:' -- cat $PR/changed/PROPOSAL.md
ctl proposal-changed-status-unsigned-catch 0 '^unsigned$' -- python3 $B/proposal.py --status --work $PR/changed
sedi 's/^Status: open$/Signed-off: Jan Jansen 2026-10-16/' $PR/changed/PROPOSAL.md
ctl proposal-changed-resigned-pass 0 'signed by Jan Jansen on 2026-10-16' -- bash $PR/prop.sh $PR/changed
# --- step records written by proposal.py (STEP-RECORDS-PLAN.md sections 3 and 6, slice 2) ---
# ssum.sh WORK: one line per step: id, topic, alias, approval state, by, source, whether found and proposed are set
cat > $PR/ssum.sh <<'SH'
#!/bin/bash
python3 "$B/steps.py" show --work "$1" --json | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    a = r.get("approval") or {}
    print("%s %s alias=%s approval=%s by=%s source=%s found=%s proposed=%s" % (r["id"], r["topic"], r.get("alias", "-"), a.get("state", "none"),
          a.get("by", "-"), a.get("source", "-"), bool(r["found"].get("say")), bool(r["proposed"].get("say"))))'
SH
chmod +x $PR/ssum.sh
# the attended, unsigned run opens a step for every item of sections 2, 3 and 4, each with found and proposed, none approved yet
ctl proposal-steps-opened-catch 0 '^S-[0-9]+ modules alias=- approval=none .* found=True proposed=True$' '^S-[0-9]+ module:DataWidgets alias=P-[0-9]+ approval=none .* found=True proposed=True$' \
  '^S-[0-9]+ widget:Stuck\.mpk 1\.1 alias=P-[0-9]+ ' '^S-[0-9]+ person:go-live alias=- ' '!found=False' '!proposed=False' '!approval=approved' '!approval=assumed' -- bash $PR/ssum.sh $PR/kept
# routine module updates are ONE step for the topic row (Plainmod is one of several updates); the module that is a decision has its own step
ctl proposal-steps-routine-updates-one-step-pass 0 '^1$' -- sh -c "python3 $B/steps.py show --work $PR/plain --json | python3 -c 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r[\"topic\"] == \"modules\"))'"
# PROPOSAL.md keeps its [P-n] item lines (the parsers read them); the P-n to S-n mapping lives in steps.jsonl as the alias field
ctl proposal-steps-alias-in-steps-file-pass 0 '^- \[P-[0-9]+\] module: Administration$' '!\[S-' '"field": "alias", "value": "P-[0-9]+"' -- sh -c "grep -E '^- \[' $PR/kept/PROPOSAL.md; cat $PR/kept/steps.jsonl"
# a rerun, and a rerun on a changed plan, keep the ids and add no step; unchanged input adds no event at all
ctl proposal-steps-rerun-no-duplicates-catch 0 '^same events: yes$' '^same steps: yes$' '^plan change keeps ids: yes$' -- sh -c "
  cp -R $PR/kept $PR/rerun; a=\$(wc -l < $PR/rerun/steps.jsonl); b=\$(bash $PR/ssum.sh $PR/rerun | cut -d' ' -f1,2 | tr '\\n' ' ')
  bash $PR/prop.sh $PR/rerun > /dev/null; [ \$a = \$(wc -l < $PR/rerun/steps.jsonl) ] && echo 'same events: yes'
  [ \"\$b\" = \"\$(bash $PR/ssum.sh $PR/rerun | cut -d' ' -f1,2 | tr '\\n' ' ')\" ] && echo 'same steps: yes'
  printf '88 2.0.0 Newmod\n' >> $PR/rerun/plan.txt; bash $PR/prop.sh $PR/rerun > /dev/null
  [ \"\$b\" = \"\$(bash $PR/ssum.sh $PR/rerun | cut -d' ' -f1,2 | tr '\\n' ' ')\" ] && echo 'plan change keeps ids: yes'"
ctl proposal-steps-plan-change-updates-found-pass 0 'plan holds 2 module updates' -- sh -c "grep -Eo 'plan holds [0-9]+ module updates?' $PR/rerun/steps.jsonl | tail -1"
# unattended: every step has an approval, assumed, by agent, source unattended; none is approved
ctl proposal-steps-unattended-assumed-catch 0 '^S-[0-9]+ modules .* approval=assumed by=agent source=unattended ' '^S-[0-9]+ module:DataWidgets .* approval=assumed by=agent source=unattended ' '!approval=none' '!approval=approved' -- bash $PR/ssum.sh $PR/unatt
# signed: every step is approved with the signer; the item Jan answered by hand (P-1) is approved by Jan, not by the signer
ctl proposal-steps-signed-approved-pass 0 '^S-[0-9]+ modules .* approval=approved by=Jan Jansen source=signoff ' '^S-[0-9]+ person:go-live .* approval=approved by=Jan Jansen source=signoff ' \
  '^S-[0-9]+ module:Administration alias=P-1 approval=approved by=Jan source=decisions ' '!approval=none' '!approval=assumed' '!by=agent' -- bash $PR/ssum.sh $PR/signed
# a person's own answer survives the sign-off: reject one step, sign again, it stays rejected
ctl proposal-steps-own-answer-survives-signoff-pass 0 'approval=rejected by=Ana ' '!approval=approved by=Jan Jansen source=signoff .*widget:Stuck' -- sh -c "
  cp -R $PR/signed $PR/own; python3 $B/steps.py approve --work $PR/own --id \$(python3 $B/steps.py show --work $PR/own --json | python3 -c 'import json,sys; print([r[\"id\"] for r in json.load(sys.stdin) if r[\"topic\"].startswith(\"widget:Stuck.mpk\")][0])') --state rejected --by Ana > /dev/null
  bash $PR/prop.sh $PR/own > /dev/null; bash $PR/ssum.sh $PR/own | grep 'widget:Stuck'"
# the signed run twice adds no event
ctl proposal-steps-signed-rerun-no-events-pass 0 '^events unchanged$' -- sh -c "a=\$(wc -l < $PR/signed/steps.jsonl); bash $PR/prop.sh $PR/signed > /dev/null; [ \$a = \$(wc -l < $PR/signed/steps.jsonl) ] && echo 'events unchanged'"
# a missing input is listed as not measured, never skipped; a present one is not
mkw missing kept; rm $PR/missing/release-impact.md $PR/missing/dojo-react.md $PR/missing/stranded.md
bash $PR/prop.sh $PR/missing > /dev/null
ctl proposal-missing-input-not-measured-catch 0 'not measured: release-impact\.md' 'not measured: dojo-react\.md' 'not measured: stranded\.md' -- bash $PR/sec.sh $PR/missing 5
ctl proposal-missing-input-still-asks-catch 14 'awaits sign-off' -- bash $PR/prop.sh $PR/missing
ctl proposal-missing-input-widget-gone-catch 0 '!Stuck' '!module: PDFReader' -- bash $PR/sec.sh $PR/missing 3
ctl proposal-present-input-measured-pass 0 '!not measured: release-impact\.md' '!not measured: dojo-react\.md' '!not measured: stranded\.md' '!not measured: localedits\.json' '!not measured: replacements\.md' -- bash $PR/sec.sh $PR/kept 5
ctl proposal-not-before-convert-listed-pass 0 'not measured: widgetcover\.py' 'not measured: theme_clash\.py' 'not measured: rolecheck\.py' 'not measured: usercode\.py' -- bash $PR/sec.sh $PR/kept 5
# pipeline: step propose between basewalk and convert; exit 14 unsigned, 15 PAUSED, 0 signed; unattended goes on
PNJ=$PR/pipe; mkdir -p $PNJ/app $PNJ/tools/mxbuild-10.24.26.1 $PNJ/tools/mxbuild-11.15.0.1 $PNJ/tools/runtime-10.24.26.1 $PNJ/tools/runtime-11.15.0.1; touch $PNJ/app/App.mpr
printf '#!/bin/sh\nexit 0\n' > $PNJ/tools/mxcli-linux; chmod +x $PNJ/tools/mxcli-linux
pipe() { # pipe WORKNAME [pipeline args]: the propose step alone, MXCLI unset, then NEEDS-JUDGMENT.md when there is one; exit = the pipeline's
  local wn=$1; shift
  PATH=$PR/fakebin:$PATH MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $PNJ/app --source 10.24.26.1 --target 11.15.0.1 --work $PNJ/$wn --only propose "$@"; local rc=$?
  [ ! -f $PNJ/$wn/NEEDS-JUDGMENT.md ] || cat $PNJ/$wn/NEEDS-JUDGMENT.md; return $rc
}
mkdir -p $PR/fakebin; printf '#!/bin/sh\nexit 0\n' > $PR/fakebin/docker; chmod +x $PR/fakebin/docker   # preflight asks `docker info`; no step here starts a container
for wn in pp ps pr; do mkw pipe/$wn kept; bash $PR/prop.sh $PNJ/$wn > /dev/null; done
mkw pipe/pu kept; mkw pipe/pa kept
ctl pipeline-propose-between-basewalk-convert-pass 0 '^STEPS=\(fetch triage baseline basewalk propose convert update ' -- grep -E '^STEPS=' $B/cloud/upgrade-pipeline.sh
ctl pipeline-propose-unsigned-exit14-catch 14 'needs judgment \(exit 14\)' 'Upgrade proposal awaits sign-off: read .*/PROPOSAL\.md' 'upgrade-pipeline\.sh .*--only propose --from propose$' 'Nothing in the app model has changed' '!mx convert' -- pipe pu
ctl pipeline-propose-not-done-when-unsigned-catch 0 'no propose.done' -- sh -c "test ! -e $PNJ/pu/state/propose.done && echo 'no propose.done'"
sedi 's/^Status: open$/Status: PAUSED vendor decision pending/' $PNJ/pp/PROPOSAL.md
ctl pipeline-propose-paused-exit15-catch 15 'needs judgment \(exit 15\)' 'PAUSED by the owner' 'vendor decision pending' '--from propose' -- pipe pp
sedi 's/^Status: open$/Signed-off: Jan Jansen 2026-10-15/' $PNJ/ps/PROPOSAL.md
ctl pipeline-propose-signed-exit0-pass 0 'propose +done' '!needs judgment' -- pipe ps
ctl pipeline-propose-signed-writes-done-pass 0 'propose.done present' -- sh -c "test -f $PNJ/ps/state/propose.done && echo 'propose.done present'"
ctl pipeline-propose-unattended-assumed-catch 0 'propose +done' '!needs judgment' -- sh -c "PATH=$PR/fakebin:\$PATH UPG_INTERVIEW_MODE=unattended MXCLI= bash -c 'bash $B/cloud/upgrade-pipeline.sh --app-dir $PNJ/app --source 10.24.26.1 --target 11.15.0.1 --work $PNJ/pa --only propose'; grep -c 'ASSUMED (unattended)' $PNJ/pa/DECISIONS.md; grep 'proposal not signed' $PNJ/pa/state/notes.txt"
ctl pipeline-propose-dry-run-pass 0 'proposal\.py --work .* \(exit 14 unsigned, 15 PAUSED' -- bash $B/cloud/upgrade-pipeline.sh --app-dir $PNJ/app --source 10.24.26.1 --target 11.15.0.1 --work $PNJ/dry --only propose --dry-run
# a plan input edited after the sign-off stops the step after propose (convert here), exit 14, sign-off cleared
sedi 's/^Status: open$/Signed-off: Jan Jansen 2026-10-15/' $PNJ/pr/PROPOSAL.md
printf '1 1.0 Added\n' >> $PNJ/pr/plan.txt; printf '# nothing before the convert\n' > $PNJ/pr/plan-pre.txt
ctl pipeline-propose-plan-change-stops-convert-catch 14 'needs judgment \(exit 14\)' 'Changed since signed|PROPOSAL\.md' '!mx convert exit' -- sh -c "PATH=$PR/fakebin:\$PATH MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $PNJ/app --source 10.24.26.1 --target 11.15.0.1 --work $PNJ/pr --from convert --only convert; rc=\$?; cat $PNJ/pr/NEEDS-JUDGMENT.md; grep '^- added' $PNJ/pr/PROPOSAL.md; exit \$rc"
ctl pipeline-propose-summary-wired-pass 0 'signed\|none\) ;;' '\*\) printf .proposal not signed: %s/PROPOSAL\.md has no Signed-off line' -- grep -E 'signed\|none\) ;;|printf .proposal not signed' $B/cloud/upgrade-pipeline.sh
# gate summary: an unsigned proposal is named in the report; a signed one and a work folder without PROPOSAL.md are not
mkdir -p $PR/gw-unsigned $PR/gw-signed $PR/gw-none; cp $PR/kept/PROPOSAL.md $PR/gw-unsigned/; cp $PR/signed/PROPOSAL.md $PR/gw-signed/
gcasew() { # gcasew LABEL WORKDIR: the gcase rungs and stubs with WORK=WORKDIR, then that folder's gate-summary.md
  local label=$1 w=$2
  ( export UPG_GATE_BIN=$GB UPG_PYTHON=python3 UPG_NODE=python3 GATE_STUB_LOG=$GI/stub-$label.log GATE_STUB_OUT_diff='INVALID 0 | FAIL 0 | REVIEW 0 | PASS* 3 | PASS 84'
    bash $B/gate.sh WORK=$w LABEL=$label BUILD_LOG=$GI/build.log OLD_MDA=$GI/old.mda NEW_MDA=$GI/new.mda \
      BEFORE_JSON=$GI/before.json AFTER_JSON=$GI/after.json ALLOW=$GI/allow.txt LOG_ALLOW=$GI/log-allow.txt \
      REST_BEFORE=$GI/rd1 REST_AFTER=$GI/rd2 OLD_LOG=$GI/old.log NEW_LOG=$GI/new.log SMOKE_URL=http://localhost:8080 \
      SMOKE_BEFORE=$GI/smoke-before.json SMOKE_PLAN=$GI/smoke-plan.json 'SMOKE_USER=Administrator=smoke_admin:S3cret-pw!' \
      JOURNEYS_DIR=$GI/jd JOURNEYS_BEFORE=$GI/jb USERS=$GI/users.json PORT=8080 ADMIN_PORT=8090 ADMIN_PASS=adm1n-s3cret \
      SMOKE_BEFORE_SHOTS=$GI/sb SMOKE_SHOT_ACCEPT=$GI/shot-accept.txt JOURNEY_SHOT_ACCEPT=$GI/shot-accept.txt RELEASE_IMPACT=$GI/release-impact.md APIMOCK=$GI/am WIDGETS_APP=$GI > $w/gate.stdout 2>&1
    rc=$?; cat $w/gate.stdout | grep -v '^\[' ; [ -f "$w/gate$label/gate-summary.md" ] && cat "$w/gate$label/gate-summary.md"; exit $rc )
}
ctl gate-proposal-not-signed-catch 0 'Overall: \*\*PASS\*\*' 'proposal not signed: .*/gw-unsigned/PROPOSAL\.md has no Signed-off line' 'Proposal not signed\.' -- gcasew pns $PR/gw-unsigned
ctl gate-proposal-signed-pass 0 'Overall: \*\*PASS\*\*' '!roposal not signed' -- gcasew pss $PR/gw-signed
ctl gate-proposal-absent-pass 0 'Overall: \*\*PASS\*\*' '!roposal not signed' -- gcasew pnone $PR/gw-none
fi
# RM: remedy.py turns the gate verdict and the kept modules into decision cards (steps/remedy.md).
RF=$FX/remedy; RT=$T/remedy; mkdir -p $RT; RM="python3 $B/remedy.py"
ctl remedy-dw3-autotry-catch 3 '^C1 AUTO-TRY dw3-dropdown-captions' '^    C   AUTO-TRY S keep DataWidgets 3\.x and add the global \.sr-only' '^    B   AUTO-TRY S keep DataWidgets 3\.x and write the old caption back' '^    A   HUMAN    L pin DataWidgets .*\[DISPROVEN: disproven \(notif RT r1 at 10\.24\.27' 'next: AUTO-TRY C: bash \$B/remedy_apply\.sh' 'instrument gaps 2; gate INVALID' -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --out $RT/dw3.md --json $RT/dw3.json
ctl remedy-dw3-report-pass 0 '^## C1 DataWidgets 3 drop-down filter' 'dw3-dropdown-captions' '"mode": "AUTO-TRY"' -- sh -c "cat $RT/dw3.md $RT/dw3.json"
ctl remedy-dw3-tried-fail-next-catch 3 '\[tried FAIL gate-b/gate-summary\.md\]' 'next: AUTO-TRY C' '!next: AUTO-TRY A' -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --tried $RF/dw3/tried-a-fail.txt --out $RT/dw3f.md --json $RT/dw3f.json
ctl remedy-dw3-tried-pass-resolved-pass 0 '^C1 RESOLVED dw3-dropdown-captions' '\[tried PASS commit abc1234 eye=shots/filter-after\.png\]' '0 AUTO-TRY waiting, 0 HUMAN, 1 resolved' -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --tried $RF/dw3/tried-b-pass.txt --out $RT/dw3p.md --json $RT/dw3p.json
ctl remedy-tried-bad-invalid 2 "want '<card key> <option> PASS\|FAIL <evidence>'" -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --tried $RF/dw3/tried-bad.txt --out $RT/x.md --json $RT/x.json
ctl remedy-dropdown-human-catch 1 '^C1 HUMAN    react19-dropdowncontainer' '^    B3  HUMAN ' '!^ +[A-D][0-9]? +AUTO-TRY' 'GAP .*journeys' -- $RM --work $RF/dropdown --gate $RF/dropdown/gate-a/gate-summary.md --release $RF/dropdown/release-impact.md --out $RT/dd.md --json $RT/dd.json
ctl remedy-regression-generic-catch 1 '^C1 HUMAN    generic-regression:smoke' 'stay on 10\.24 LTS' '!react19-dropdowncontainer' -- $RM --work $RF/regression --gate $RF/regression/gate-a/gate-summary.md --release $RF/regression/release-impact.md --out $RT/rg.md --json $RT/rg.json
ctl remedy-viewer3d-gate-pass-still-catch 1 'gate PASS' '^C1 HUMAN    react-bundled-viewer3d' 'stay on 10\.24 LTS \(the source is 10\.12\.2\.41995' '!^ +[A-D][0-9]? +AUTO-TRY' -- $RM --work $RF/viewer3d --gate $RF/viewer3d/gate-a/gate-summary.md --release $RF/viewer3d/release-impact.md --kept-file $RF/viewer3d/kept.txt --findings $RF/viewer3d/findings.txt --out $RT/v3.md --json $RT/v3.json
# QI-4: a widget package that calls mx.logger gets its own card (no more "no remedy row"); R38 is the replacement row
mkdir -p $RT/mxl; : > $RT/mxl/tried-none.txt
ctl remedy-mxlogger-card-catch 1 '^C1 HUMAN    widget-mxlogger' '^    B   HUMAN ' '^    B2  HUMAN ' '^    B3  HUMAN ' '^    D   HUMAN .*stay on 10\.24 LTS' '!no remedy row' '!^ +[A-D][0-9]? +AUTO-TRY' -- $RM --work $RT/mxl --finding 'replacement: R37 HIT evidence: widgets/ListViewControls.mpk 1.3.16 runs /mx.logger/ in its JavaScript' --from 10.24.27 --to 11.12.6 --out $RT/mxl/o.md --json $RT/mxl/o.json
# V3D-3/4/5: the 3D viewer card names the cause, offers B2 (another licensed version, R36 first), C2 (spinner patch, HUMAN only) and
# a D whose evidence is "the page renders on the stay version"
ctl remedy-viewer3d-options-catch 1 '^C1 HUMAN    react-bundled-viewer3d: 3D Viewer widget bundles react-loading' '^    B2  HUMAN +S another 3DViewer.mpk version you are licensed for' '^    C2  HUMAN +S patch the bundled spinner' '!^ +[A-D][0-9]? +AUTO-TRY' -- $RM --work $RF/viewer3d --gate $RF/viewer3d/gate-a/gate-summary.md --release $RF/viewer3d/release-impact.md --kept-file $RF/viewer3d/kept.txt --findings $RF/viewer3d/findings.txt --out $RT/v3b.md --json $RT/v3b.json
ctl remedy-viewer3d-d-evidence-pass 0 'the blocked page renders on the stay version' 'below 19' -- sh -c "$RM --work $RF/viewer3d --gate $RF/viewer3d/gate-a/gate-summary.md --release $RF/viewer3d/release-impact.md --kept-file $RF/viewer3d/kept.txt --findings $RF/viewer3d/findings.txt --out $RT/v3c.md --json $RT/v3c.json >/dev/null; cat $RT/v3c.md"
# V3D-6: a tried line for something that is not an option of the card (X:<label>) is an extra row and never resolves the card
printf 'react-bundled-viewer3d X:patch-spinner PASS mc/remedy-3dv/probe.json # lab patch\nreact-bundled-viewer3d B FAIL licence-404\n' > $RT/tried-x.txt
ctl remedy-tried-extra-catch 1 '^    X:patch-spinner EXTRA +\(not on the card\) \[tried PASS mc/remedy-3dv/probe\.json\]' '^C1 HUMAN    react-bundled-viewer3d' 'extra tried and PASS, not on the card: X:patch-spinner' '!RESOLVED' '^    B +HUMAN .*\[tried FAIL licence-404\]' -- $RM --work $RF/viewer3d --gate $RF/viewer3d/gate-a/gate-summary.md --release $RF/viewer3d/release-impact.md --kept-file $RF/viewer3d/kept.txt --findings $RF/viewer3d/findings.txt --tried $RT/tried-x.txt --out $RT/v3d.md --json $RT/v3d.json
ctl remedy-tried-extra-md-pass 0 '^- extra, not an option of this card: X:patch-spinner, tried: PASS' -- sh -c "cat $RT/v3d.md"
# QI-5: the default output is remedy-cards.md (never REMEDIATION.md: one file on a case-insensitive disk), and a gate FOLDER is accepted
rm -rf $RT/dflt; mkdir -p $RT/dflt; cp -R $RF/viewer3d/. $RT/dflt/; echo merged > $RT/dflt/REMEDIATION.md
ctl remedy-default-name-catch 1 '^C1 HUMAN    react-bundled-viewer3d' -- $RM --work $RT/dflt --gate $RT/dflt/gate-a --release $RT/dflt/release-impact.md --kept-file $RT/dflt/kept.txt --findings $RT/dflt/findings.txt
ctl remedy-default-name-pass 0 '^remedy-cards.md$' '^remediation.json$' '^merged$' -- sh -c "ls $RT/dflt | grep -E '^(remedy-cards.md|remediation.json)$'; cat $RT/dflt/REMEDIATION.md"
ctl remedy-gate-folder-nosummary-catch 2 'is a folder with no gate-summary\.md' -- $RM --work $RT/dflt --gate $RT/dflt/gate-a/.. --release $RT/dflt/release-impact.md --out $RT/x.md --json $RT/x.json
ctl remedy-kept-kinds-catch 1 '^C1 HUMAN    kept-administration-account' '^C2 HUMAN    generic-kept-edits:MxGenAIConnector' '^C3 HUMAN    generic-kept-unproven:GenAICommons' 'keptdeps not shown clean for the kept modules that may call GenAICommons' '^C4 HUMAN    generic-kept-unproven:OtherMod' '^CHOICE kept line .OQL skipped by --skip.: skipped by choice' '!GAP kept: .*OQL' '!TaskQueueHelpers' -- $RM --work $RF/kept --kept-file $RF/kept/kept.txt --from 10.24.8 --to 11.12.6 --out $RT/k.md --json $RT/k.json
# FM-5: the Feedback widget whose target container is absent in a custom layout gets a card with a unit-patch option (AUTO-TRY A)
ctl remedy-feedback-target-catch 3 '^C1 AUTO-TRY sprintr-feedback-target' '^    A   AUTO-TRY S in the app-owned snippet that holds the widget, set showAdvancedSettings' '^    C   HUMAN ' 'next: AUTO-TRY A' -- $RM --work $RF/feedback --gate $RF/feedback/gate-a/gate-summary.md --release $RF/feedback/release-impact.md --findings $RF/feedback/findings.txt --from 11.10.0 --to 11.12.6 --out $RT/fb.md --json $RT/fb.json
ctl remedy-feedback-target-unrelated-pass 1 '!sprintr-feedback-target' -- $RM --work $RF/viewer3d --gate $RF/viewer3d/gate-a/gate-summary.md --release $RF/viewer3d/release-impact.md --kept-file $RF/viewer3d/kept.txt --findings $RF/viewer3d/findings.txt --out $RT/v3b.md --json $RT/v3b.json
ctl remedy-table-autotry-c-invalid 2 'AUTO-TRY on option C: only A \(keep or pin\) and B \(swap\)' -- $RM --work $RF/kept --kept-file $RF/kept/kept.txt --table $RF/bad-table.tsv --out $RT/x.md --json $RT/x.json
ctl remedy-table-autotry-noapply-invalid 2 'AUTO-TRY needs apply' -- $RM --work $RF/kept --kept-file $RF/kept/kept.txt --table $RF/bad-noapply.tsv --out $RT/x.md --json $RT/x.json
ctl remedy-clean-pass 0 '^remedy: 0 cards' 'instrument gaps 0; gate PASS' -- $RM --work $RF/clean --out $RT/c.md --json $RT/c.json
ctl remedy-no-work-invalid 2 'not a folder' -- $RM --work $RF/nonexistent --out $RT/x.md --json $RT/x.json
ctl remedy-shipped-table-pass 0 '^remedy: 0 cards' -- $RM --work $RF/clean --table $TK/playbooks/remedies.tsv --out $RT/c2.md --json $RT/c2.json
# RT-1: options rank by evidence (verified yes first, partial next, disproven or tried FAIL last), the letter only breaks ties
rmorder() { $RM "$@" | awk '/^    [A-D][0-9]? /{printf "%s", $1} END{print ""}'; }
ctl remedy-rank-evidence-pass 0 '^CBA$' -- rmorder --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --out $RT/ro.md --json $RT/ro.json
# RT-3: a disproven row is never AUTO-TRY (the table refuses it) and is listed apart in the HUMAN choice
ctl remedy-table-autotry-disproven-invalid 2 'AUTO-TRY on a disproven row' -- $RM --work $RF/kept --kept-file $RF/kept/kept.txt --table $RF/bad-disproven.tsv --out $RT/x.md --json $RT/x.json
ctl remedy-disproven-choice-catch 1 '^C1 HUMAN    dw3-dropdown-captions' 'next: HUMAN: no untried option left: decide .* \(disproven: A\) \(tried and failed: B, C\)' -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --tried $RF/dw3/tried-cb-fail.txt --out $RT/dcb.md --json $RT/dcb.json
# RT-6: a PASS of a row whose regate names eye needs eye=<shot> in the tried line, else the card stays HUMAN
ctl remedy-eye-pass-needs-shot-catch 1 '^C1 HUMAN    dw3-dropdown-captions' 'B PASS needs a by-eye screens verdict' '!RESOLVED dw3' -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --tried $RF/dw3/tried-b-pass-noeye.txt --out $RT/dne.md --json $RT/dne.json
# RT-4: the .sr-only base-layer card outside DataWidgets (paging text twice) on the shipped table
ctl remedy-sr-only-base-catch 3 '^C1 AUTO-TRY atlas-sr-only-base' '^    B   AUTO-TRY S add the global \.sr-only' 'then a by-eye look at the screens' -- $RM --work $RF/clean --findings $RF/srbase-findings.txt --out $RT/sr.md --json $RT/sr.json
# RT-8: prove-clean B of an unproven kept module is AUTO-TRY only when keptdeps shows no other kept module calls it
ctl remedy-keptdeps-dependent-catch 1 '^C2 HUMAN    generic-kept-unproven:AuthMod' 'kept UpdConn calls AuthMod \(keptdeps, keptdeps\.py run\)' '^    B2  HUMAN    M update AuthMod together with UpdConn in one step' -- $RM --work $RF/kept --kept-file $RF/kept/kept-deps.txt --app $M/keptdeps-ok --out $RT/kd1.md --json $RT/kd1.json
ctl remedy-keptdeps-clean-pass 3 '^C2 AUTO-TRY generic-kept-unproven:AuthMod' '^    B   AUTO-TRY S prove AuthMod unedited' '!B2 ' -- $RM --work $RF/kept --kept-file $RF/kept/kept-deps.txt --app $M/keptdeps-none --out $RT/kd2.md --json $RT/kd2.json
ctl remedy-keptdeps-file-catch 1 '^C2 HUMAN    generic-kept-unproven:AuthMod' 'keptdeps, .*keptdeps-authmod\.txt' -- $RM --work $RF/kept --kept-file $RF/kept/kept-deps.txt --keptdeps $RF/kept/keptdeps-authmod.txt --out $RT/kd3.md --json $RT/kd3.json
ctl remedy-keptdeps-unknown-catch 1 '^C2 HUMAN    generic-kept-unproven:AuthMod' 'keptdeps not shown clean .*give --app' -- $RM --work $RF/kept --kept-file $RF/kept/kept-deps.txt --out $RT/kd4.md --json $RT/kd4.json
# RT-9: a module that left the kept list since the snapshot keeps its card and a WARN; a tried line for no card warns
cp $RF/kept/kept.txt $RT/kept-snap.txt; rm -f $RT/snap.txt
ctl remedy-snapshot-first-pass 1 '^C3 HUMAN    generic-kept-unproven:GenAICommons' '!WARN' -- $RM --work $RF/kept --kept-file $RT/kept-snap.txt --kept-snapshot $RT/snap.txt --out $RT/sn1.md --json $RT/sn1.json
grep -v GenAICommons $RF/kept/kept.txt > $RT/kept-snap.txt
ctl remedy-snapshot-shrink-catch 1 '^WARN kept list shrank: GenAICommons is in the snapshot' 'generic-kept-unproven:GenAICommons' -- $RM --work $RF/kept --kept-file $RT/kept-snap.txt --kept-snapshot $RT/snap.txt --out $RT/sn2.md --json $RT/sn2.json
ctl remedy-snapshot-reset-pass 1 '!WARN kept list shrank' '!GenAICommons' -- $RM --work $RF/kept --kept-file $RT/kept-snap.txt --kept-snapshot $RT/snap.txt --reset-kept-snapshot --out $RT/sn3.md --json $RT/sn3.json
printf 'nonexistent-card A FAIL gate-x/gate-summary.md\n' > $RT/tried-orphan.txt
ctl remedy-tried-orphan-catch 3 "^WARN tried line 'nonexistent-card A FAIL' matches no card" -- $RM --work $RF/dw3 --gate $RF/dw3/gate-a/gate-summary.md --release $RF/dw3/release-impact.md --from 9.24.32 --to 10.24.27 --tried $RT/tried-orphan.txt --out $RT/to.md --json $RT/to.json

# RT-10 (BACKLOG #86, RM-3): remedy_apply.sh applies one option on its own branch of a git app, checks, builds, re-gates
# with gate.sh --only --seed-from over the stub instruments, records the tried line, pauses for by-eye and release rows.
# fixtures/remedy/apply: table (card fx-card: A, B eye, B2 release, B3, B4, C HUMAN), recipes, gate.conf, remedy.conf
# (stub mx check and build); copied to a temp folder with a two-file git app (App.mpr, widgets/w.mpk).
AW=$T/rapply; rm -rf $AW; cp -R $RF/apply $AW
echo "BUILD SUCCEEDED" > $AW/build.log; echo x > $AW/old.mda; echo x > $AW/new.mda; echo x > $AW/release-impact.md; echo x > $AW/shot.png
mkdir -p $AW/app/widgets; echo "model v1" > $AW/app/App.mpr; echo "widget v1" > $AW/app/widgets/w.mpk
RAENV="env GIT_AUTHOR_NAME=ctl GIT_AUTHOR_EMAIL=ctl@example.invalid GIT_COMMITTER_NAME=ctl GIT_COMMITTER_EMAIL=ctl@example.invalid GIT_CONFIG_NOSYSTEM=1 UPG_GATE_BIN=$GB UPG_PYTHON=python3 UPG_NODE=python3"
$RAENV sh -c "git -C $AW/app init -q -b main && git -C $AW/app add -A && git -C $AW/app commit -q -m base"
(cd $AW && $RAENV bash $B/gate.sh --config gate.conf --only build,idcheck,release > /dev/null 2>&1; true)
(cd $AW && $RM --work $AW --gate $AW/gate-orig/gate-summary.md --findings findings.txt --table table.tsv > /dev/null)
rapply() { (while [ $# -gt 0 ]; do case "$1" in GATE_STUB_*=*) export "$1"; shift;; *) break;; esac; done
            $RAENV bash $B/remedy_apply.sh --config $AW/remedy.conf "$@"); }
ctl remedy-apply-dry-run-pass 0 'dry run, nothing changed' 'branch remedy-fx-card-a from main' 'gate\.sh --config .*gate\.conf --only build,idcheck --seed-from .*/gate-orig LABEL=-remedy-fx-card-a' -- rapply fx-card A --dry-run
ctl remedy-apply-human-catch 2 'fx-card C is HUMAN: a person chooses it; pass --human' -- rapply fx-card C
ctl remedy-apply-no-recipe-catch 2 'no recipe for fx-card C: write it as .*/recipes/fx-card\.C\.sh' -- rapply fx-card C --human
ctl remedy-apply-fail-catch 1 'widget mpk changed: widgets/w\.mpk' 'rung idcheck FAIL' 'recorded in .*: fx-card A FAIL .*/gate-remedy-fx-card-a/gate-summary\.md # branch remedy-fx-card-a on main \([0-9a-f]+\), abandoned' \
  'app back on main' 'next: AUTO-TRY B: ' -- rapply GATE_STUB_RC_idcheck=1 fx-card A
ctl remedy-apply-fail-branch-kept-pass 0 '^main$' 'remedy-fx-card-a' 'model v1' '!fixA' -- sh -c "git -C $AW/app branch --show-current; git -C $AW/app branch --list 'remedy-*'; cat $AW/app/App.mpr"
ctl remedy-apply-tried-again-catch 2 'already tried: fx-card A FAIL' -- rapply fx-card A
ctl remedy-apply-check-fail-catch 1 'mx check rc 0, error lines 1: FAIL' 'fx-card B3 FAIL .*remedy-check-fx-card-b3\.log' -- rapply fx-card B3 'CHECK_CMD=echo "[error] CE0001 broken"'
ctl remedy-apply-release-pause-catch 5 'rung release INVALID' 'PAUSED for a person \(release\): .*remedy-todo-fx-card-b2\.md' '!recorded in' -- rapply GATE_STUB_RC_release_impact=1 fx-card B2
ctl remedy-apply-release-todo-pass 0 '^## Release rows' '\| 10 \| release \| INVALID \|' 'finish fx-card B2 PASS' -- cat $AW/remedy-todo-fx-card-b2.md
ctl remedy-apply-finish-fail-catch 1 'fx-card B2 FAIL .* finished by a person: rows stay open' 'app back on main' -- rapply --finish fx-card B2 FAIL --note 'rows stay open'
ctl remedy-apply-eye-pause-catch 5 'rung idcheck PASS' 'PAUSED for a person \(eye\)' -- rapply fx-card B
ctl remedy-apply-eye-todo-pass 0 '^## By eye' 'eye <the shot you looked at>' -- cat $AW/remedy-todo-fx-card-b.md
ctl remedy-apply-finish-noeye-catch 2 'PASS of fx-card B needs --eye <shot path>' -- rapply --finish fx-card B PASS
ctl remedy-apply-finish-eye-pass 0 'fx-card B PASS .*/gate-remedy-fx-card-b/gate-summary\.md eye=.*/shot\.png' 'app stays on remedy-fx-card-b' '^  C1 RESOLVED fx-card' -- rapply --finish fx-card B PASS --eye $AW/shot.png
ctl remedy-apply-cleaned-pass 0 'no trial mda' '!remedy-todo-fx-card-b\.md' -- sh -c "ls $AW; ls $AW/remedy-*.mda > /dev/null 2>&1 || echo 'no trial mda'"
ctl remedy-apply-not-judged-catch 4 'rung idcheck INVALID' 'not judged: idcheck\(INVALID\)' '!recorded in' -- rapply GATE_STUB_RC_idcheck=2 fx-card B4
ctl remedy-apply-resume-gate-pass 0 'fx-card B4 PASS .* # branch remedy-fx-card-b4 on remedy-fx-card-b ' '!mx check clean' -- rapply fx-card B4 --from gate

# Completion grade (bin/grade.py, steps/report.md, READING-THE-VERDICT.md section 6): fixtures/grade/*.md are small gate summaries.
GR=$FX/grade; GRADE="python3 $B/grade.py"
ctl grade-pass 0 'GRADE 100% \(9 of 9 required rungs done\): proven 6, accepted 3, waiting on a person 0, not testable here 0, open regression 0 \| verdict PASS$' \
  'accepted +const, data, journeys' '!open and pending work' -- $GRADE $GR/pass.md
ctl grade-mixed-invalid-catch 0 'GRADE 67% \(6 of 9 required rungs done\): proven 5, accepted 1, waiting on a person 3, not testable here 0, open regression 0 \| verdict INVALID$' \
  'waiting on a person +journeys, screens, release' '\[person\] release: .*2 open' 'not graded \(optional\): apis EXCEPT' -- $GRADE $GR/mixed.md
ctl grade-fail-never-done-catch 0 'GRADE 70% \(7 of 10 required rungs done\).*\| verdict FAIL$' 'open regression +data, smoke' \
  'not testable here +journeys' '\[customer\] journeys: needs the licence key' '\[toolkit\] smoke' 'proven .*widgets' -- $GRADE $GR/fail.md
ctl grade-note-downgrade-catch 0 'GRADE 89% \(8 of 9 required rungs done\).*open regression 1 \| verdict PASS$' '\[toolkit\] screens: second note' \
  '\[person\] -: confirm the guest process' '!3D viewer needs a licence' -- $GRADE $GR/pass.md --notes $GR/notes.tsv
ctl grade-note-raise-refused-catch 1 'a note cannot raise a rung' '!GRADE' -- $GRADE $GR/pass.md --notes $GR/notes-raise.tsv
ctl grade-missing-summary-catch 1 'no such summary' -- $GRADE $T/no-such-summary.md
# --stamp puts one Grade: line after Overall: and replaces it on a second run; the verdict line is untouched
cp $GR/mixed.md $T/grade-stamp.md; $GRADE $T/grade-stamp.md --stamp > /dev/null 2>&1; $GRADE $T/grade-stamp.md --stamp > /dev/null 2>&1
ctl grade-stamp-pass 0 '^Overall: \*\*INVALID\*\*' '^Grade: 67% \(6 of 9 required rungs done\)' -- sh -c "head -4 $T/grade-stamp.md; echo lines=\$(grep -c '^Grade: ' $T/grade-stamp.md)"
ctl grade-stamp-once-pass 0 'lines=1' -- sh -c "echo lines=\$(grep -c '^Grade: ' $T/grade-stamp.md)"
# --history adds a row, then updates the same run id in place
HF=$T/HISTORY.md
$GRADE $GR/mixed.md --history $HF --run RX --app 'fixture app' --path '10.1 > 10.2' --toolkit abc1234 --duration 1h00 --date 2026-01-01 --regressions '0 / 0' --kept 0 --lesson FX > /dev/null 2>&1
$GRADE $GR/pass.md --history $HF --run RX > /dev/null 2>&1
$GRADE $GR/fail.md --history $HF --run RY --app 'second app' --date 2026-01-02 > /dev/null 2>&1
ctl grade-history-update-pass 0 '^\| 2026-01-01 \| RX \| fixture app \| 10\.1 > 10\.2 \| abc1234 \| 1h00 \| PASS \| 100% \(9/9\) \|' 'rows=2' '^\| 2026-01-02 \| RY \| second app .*\| FAIL \| 70% \(7/10\) \|' '!INVALID' \
  -- sh -c "grep -E '^\| 2026' $HF; echo rows=\$(grep -cE '^\| 2026' $HF)"
ctl grade-history-header-pass 0 '^\| date \| run id \| app \| Mendix path \| toolkit commit \| duration \| gate verdict \| grade \| regressions found/fixed \| kept modules \| open items \| lesson prefix \|$' -- head -9 $HF
# the pipeline writes the run row to $WORK/history-row.md by default, never into the toolkit (record_grade, steps/report.md)
PW=$T/pipe-hist; mkdir -p $PW/work $PW/tk/runs; cp $GR/mixed.md $PW/work/gate-summary.md
sed -n '/^record_grade() {/,/^}/p' $B/cloud/upgrade-pipeline.sh > $PW/fn.sh
ctl pipeline-history-default-target-pass 0 '^\| .* \| 20260101000000 \| unnamed app \| a > b \|' 'toolkit-runs=0' '!RUN-APP-NAME' \
  -- sh -c ". $PW/fn.sh; WORK=$PW/work B=$B TK=$PW/tk RUN=$PW/RUN-APP-NAME SOURCE=a TARGET=b record_grade > /dev/null 2>&1; grep -E '^\| 20' $PW/work/history-row.md; echo toolkit-runs=\$(ls $PW/tk/runs | wc -l | tr -d ' ')"
ctl pipeline-history-override-pass 0 'UPG_HISTORY=ok' -- sh -c ". $PW/fn.sh; WORK=$PW/work B=$B TK=$PW/tk RUN=$PW/r SOURCE=a TARGET=b UPG_HISTORY=$PW/other.md UPG_APP_NAME=generic record_grade > /dev/null 2>&1; grep -q ' generic ' $PW/other.md && echo UPG_HISTORY=ok"
# the committed runs/HISTORY.md: every row has 12 cells and a run id once
ctl history-committed-shape-pass 0 'rows=14 bad=0 dup=0' -- python3 -I -c "
import re,sys,collections
ls=[l for l in open('$TK/runs/HISTORY.md').read().split('\n') if l.startswith('| ') and not l.startswith('| date |')]
bad=sum(1 for l in ls if len(l.strip().strip('|').split(' | '))!=12)
ids=collections.Counter(l.split(' | ')[1] for l in ls)
print('rows=%d bad=%d dup=%d'%(len(ls),bad,sum(1 for v in ids.values() if v>1)))"
# gate.sh stamps the grade into its summary and prints it (stub instruments)
ctl gate-grade-stamp-pass 0 'Overall: \*\*PASS\*\*' '^  GRADE 100% \(9 of 9 required rungs done\): proven' '^Grade: 100% \(9 of 9 required rungs done\)' '!Grade: .*INVALID' -- gcase gradestamp

# customer names: bin/customer_names_check.sh fails on a name from the private list (bin/private_names.sh, outside the
# repo) in tracked files; the mirror's scrub script is exempt; no list = nothing to check, said as such. Made-up name.
mkdir -p $T/cn-catch $T/cn-pass $T/cn-exempt
printf '# made-up customer\n\\bAcmecorp\\b\n' > $T/cn-names.txt
printf 'ran against the Acmecorp app\n' > $T/cn-catch/notes.md
printf 'ran against a customer app\n' > $T/cn-pass/notes.md
printf 'Acmecorp\n' > $T/cn-exempt/sync-from-personal.sh
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl customer-names-catch 1 'notes\.md:1:' 'customer names in tracked files' -- bash $B/customer_names_check.sh $T/cn-catch
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl customer-names-pass 0 'customer-names: clean' -- bash $B/customer_names_check.sh $T/cn-pass
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl customer-names-exempt-pass 0 'customer-names: clean' -- bash $B/customer_names_check.sh $T/cn-exempt
UPG_PRIVATE_NAMES=$T/no-such-list ctl customer-names-no-list-pass 0 'no private list' -- bash $B/customer_names_check.sh $T/cn-catch
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl customer-names-list-not-in-repo-pass 0 '!Acmecorp' -- cat $B/customer_names_check.sh $B/private_names.sh
ctl customer-names-tracked-toolkit-pass 0 'customer-names: (clean|no private list)' -- bash $B/customer_names_check.sh $TK

# export-public.sh: whitelist export of committed files, refused on a real deployment host (a mendixcloud.com or an
# internal domain) and exported with the licence; the public sandbox.mxapps.io of the release notes passes. Mini repo.
xp_repo() {  # $1 dir, $2 text of the one exported step file
  mkdir -p $1/upgrade-toolkit/bin $1/upgrade-toolkit/steps
  cp $B/export-public.sh $B/private_names.sh $B/private_hosts.sh $1/upgrade-toolkit/bin/
  cp $TK/PUBLIC-README.md $TK/PUBLIC-LICENSE $1/upgrade-toolkit/
  printf '%s\n' "$2" > $1/upgrade-toolkit/steps/x.md
  git -C $1 init -q && git -C $1 add -A && git -C $1 -c user.email=ctl@example.invalid -c user.name=ctl commit -qm x
}
xp_repo $T/xp-catch "constant https://acme-accp.mendix""cloud.com/odata/v1"   # split, so this file passes the check
xp_repo $T/xp-pass 'license check for sandbox.mxapps.io domain, advisory on advisories.example-vendor.com'
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl export-public-host-catch 1 'REFUSED: real deployment or internal hostnames' 'steps/x\.md:1:acme-accp\.mendixcloud\.com' -- bash $T/xp-catch/upgrade-toolkit/bin/export-public.sh $T/xp-out-catch
UPG_PRIVATE_NAMES=$T/cn-names.txt ctl export-public-sandbox-pass 0 '^export .* Not pushed\.$' '!REFUSED' -- bash $T/xp-pass/upgrade-toolkit/bin/export-public.sh $T/xp-out-pass
ctl export-public-licence-pass 0 'Apache License' -- head -3 $T/xp-out-pass/LICENSE

# run log (bin/runlog.py -> FIELD-RUNS.md). Fixture controls/fixtures/runlog/b6checklist = a real gate-summary, SCORECARD,
# HANDWORK, DECISIONS and the journeys lines of a field run (Checklist 9.24 to 11.12.5, branch runs/b6-checklist), with the
# Progress line gate.sh prints for that summary added (that run predates the line) and the Grade line grade.py stamps.
export UPG_PRIVATE_NAMES=$T/cn-names.txt   # every later control: the made-up list, never this machine's
RL=$T/runlog; mkdir -p $RL; RLF=$TK/controls/fixtures/runlog/b6checklist
rl() { python3 -I $B/runlog.py "$@"; }
cp -R $RLF $RL/w1
ctl runlog-append-row-pass 0 '^\| 20261013041248 \| CODE-A \| template app \| 10\.24\.27\.128337 → 11\.12\.5 \| yes \| yes \| 7 of 10 \(70%\) · INVALID \(exit 2\) \| 0 \| old app 53 pass / 126 fail; 0 regression\(s\); coverage 53/295 \(17%\) \| .* \| smoke NOT RUN; journeys INVALID; owner sign-off pending \| 2026-10-13 \| not recorded \| not recorded \|$' 'rows=1' \
  -- sh -c "python3 -I $B/runlog.py --work $RL/w1 --log $RL/log1.md --app CODE-A --type 'template app' > /dev/null 2>&1; grep -E '^\| 2' $RL/log1.md; echo rows=\$(grep -c '^| 2' $RL/log1.md)"
# no Progress line in the summary (an older run): the cell says so, it does not compute one
mkdir -p $RL/w2; grep -v '^Progress:' $RLF/gate-summary.md > $RL/w2/gate-summary.md
ctl runlog-no-progress-line-catch 0 '\| progress not recorded · INVALID \(exit 2\) \|' '!\| 7 of 10' '\| 20261013041248 \| not recorded \| not recorded \| not recorded \| yes \| yes \| progress not recorded' \
  -- python3 -I $B/runlog.py --work $RL/w2 --log $RL/log2.md --dry-run
# nothing in the folder but a run id: every value is "not recorded", none guessed
mkdir -p $RL/w3
ctl runlog-unknown-not-recorded-catch 0 '^\| RID-1 \| (not recorded \| ){12}not recorded \|$' -- python3 -I $B/runlog.py --work $RL/w3 --run-id RID-1 --log $RL/log3.md --dry-run
ctl runlog-no-run-id-catch 2 'no run id in' 'pass --run-id' -- python3 -I $B/runlog.py --work $RL/w3 --log $RL/log3.md
# duplicate run id: second call exits 3, prints the existing row, appends nothing
ctl runlog-duplicate-refused-catch 0 'rc1=0' 'rc2=3' 'already in the log' '^\| 20261013041248 \| CODE-A ' 'rows=1' \
  -- sh -c "L=$RL/log4.md; python3 -I $B/runlog.py --work $RL/w1 --log \$L --app CODE-A > /dev/null 2>&1; echo rc1=\$?; python3 -I $B/runlog.py --work $RL/w1 --log \$L --app CODE-B 2>&1; echo rc2=\$?; echo rows=\$(grep -c '^| 2' \$L)"
# customer name (from the private names list) in --app: refused, exit 4, nothing written
ctl runlog-customer-name-refused-catch 0 'rc=4' 'contains a customer name' 'Pass --app and --type' 'log=absent' \
  -- sh -c "python3 -I $B/runlog.py --work $RL/w1 --log $RL/log5.md --app 'the Acmecorp app' 2>&1; echo rc=\$?; [ -e $RL/log5.md ] && echo log=present || echo log=absent"
ctl runlog-code-name-accepted-pass 0 'rc=0' '!customer name' 'rows=1' \
  -- sh -c "python3 -I $B/runlog.py --work $RL/w1 --log $RL/log6.md --app CODE-A --type 'template app' 2>&1 >/dev/null; echo rc=\$?; echo rows=\$(grep -c '^| 2' $RL/log6.md)"
# backfill: a root with two run folders (one copy of the fixture, one more); dry run prints and writes nothing
mkdir -p $RL/root/a/work $RL/root/b/work; cp -R $RLF/. $RL/root/a/work/; cp -R $RLF/. $RL/root/b/work/
sed -i 's/ 20261013041248\./ 20261013999999./' $RL/root/b/work/gate-summary.md
ctl runlog-backfill-dry-run-catch 0 '^ADD +a/work' '^ADD +b/work' '2 run folders under .*: 2 to add' 'Dry run: nothing written' 'log=absent' \
  -- sh -c "python3 -I $B/runlog.py --backfill $RL/root --log $RL/log7.md --app CODE-A; [ -e $RL/log7.md ] && echo log=present || echo log=absent"
ctl runlog-backfill-write-pass 0 '^ADDED +a/work' '2 added' 'rows=2' \
  -- sh -c "python3 -I $B/runlog.py --backfill $RL/root --log $RL/log8.md --app CODE-A --write; echo rows=\$(grep -c '^| 2' $RL/log8.md)"
ctl runlog-backfill-rerun-duplicates-pass 0 '^DUP +a/work' '^DUP +b/work' '0 added, 2 duplicate' 'rows=2' \
  -- sh -c "python3 -I $B/runlog.py --backfill $RL/root --log $RL/log8.md --app CODE-A --write; echo rows=\$(grep -c '^| 2' $RL/log8.md)"
# --match limits the backfill to the folders whose path contains the text
ctl runlog-backfill-match-pass 0 '1 run folders under .*: 1 to add' '^ADD +b/work' '!^ADD +a/work' -- python3 -I $B/runlog.py --backfill $RL/root --log $RL/log9.md --app CODE-A --match /b/
# backfill refuses a customer name that reaches a row (here through --type); the other folders are not touched
MC=Acmecorp
ctl runlog-backfill-name-refused-catch 0 '^REFUSED a/work' '0 added, 0 duplicate, 2 refused' 'log=absent' \
  -- sh -c "python3 -I $B/runlog.py --backfill $RL/root --log $RL/log10.md --app CODE-A --type '$MC app' --write; [ -e $RL/log10.md ] && echo log=present || echo log=absent"
# version detection (gate.conf), --explain, --summary
mkdir -p $RL/w4; cp $RLF/gate-summary.md $RL/w4/; printf 'SOURCE=9.24.2\nTARGET=10.24.27.128337\nTARGET2=11.12.5.77990\n' > $RL/w4/gate.conf
ctl runlog-version-from-gate-conf-catch 0 '\| 9\.24\.2 → 11\.12\.5\.77990 \|' 'version source gate\.conf: 9\.24\.2 → 11\.12\.5\.77990' -- python3 -I $B/runlog.py --work $RL/w4 --log $RL/log11.md --app CODE-A --verbose --dry-run
mkdir -p $RL/xroot/x1 $RL/xroot/x2; cp -R $RLF/. $RL/xroot/x1/; printf '# journal\n' > $RL/xroot/x2/JOURNAL.md
ctl runlog-explain-skipped-reason-catch 0 '^x1: WOULD-ADD' '^x2: SKIPPED no gate-summary\.md and no SCORECARD verdict' 'log=absent' \
  -- sh -c "python3 -I $B/runlog.py --explain $RL/xroot --log $RL/log12.md --app CODE-A; [ -e $RL/log12.md ] && echo log=present || echo log=absent"
mkdir -p $RL/sroot/a $RL/sroot/b; cp -R $RLF/. $RL/sroot/a/; cp -R $RLF/. $RL/sroot/b/
sed -i 's/ 20261013041248\./ 20261015999999./; s/2026-10-13T/2026-10-15T/' $RL/sroot/b/gate-summary.md
ctl runlog-summary-latest-per-app-idempotent-pass 0 '^- \*\*CODE-A\*\* \(template app\): latest run 2026-10-15; highest version reached 11\.12\.5; .*; 2 runs$' 'same=yes' 'apps=1' \
  -- sh -c "L=$RL/log13.md; python3 -I $B/runlog.py --backfill $RL/sroot --log \$L --app CODE-A --type 'template app' --write >/dev/null; python3 -I $B/runlog.py --summary --log \$L >/dev/null; a=\$(md5sum < \$L); python3 -I $B/runlog.py --summary --log \$L >/dev/null; [ \"\$a\" = \"\$(md5sum < \$L)\" ] && echo same=yes; grep '^- \*\*' \$L; echo apps=\$(grep -c '^- \*\*' \$L)"
# the pipeline hook: record_runlog and cleanup, extracted and run under the pipeline's own set -Eeu / ERR trap
RP=$T/rl-pipe; mkdir -p $RP/bin-fail $RP/bin-ok $RP/work; cp $RLF/gate-summary.md $RP/work/
{ sed -n '/^record_runlog() {/,/^}/p;/^timing_open() {/,/^}/p;/^timing_close() {/,/^}/p;/^cleanup() {/,/^}/p' $B/cloud/upgrade-pipeline.sh; sed -n '/^now_utc() /p;/^TIMING_STEP=/p' $B/cloud/upgrade-pipeline.sh; } > $RP/fn.sh
printf 'import sys\nprint("boom: runlog is broken on purpose", file=sys.stderr)\nsys.exit(5)\n' > $RP/bin-fail/runlog.py
cp $B/runlog.py $B/customer_names_check.sh $RP/bin-ok/
rpcase() { # rpcase BINDIR EXITCODE: run the extracted hook the way the pipeline's EXIT trap does, a gate step that exits $2
  bash -c "set -Eeu; trap 'exit 4' ERR; . $RP/fn.sh; APPS_UP=(); B=$1; WORK=$RP/work; TK=$RP/tk; STEP=gate; DRY=0; trap cleanup EXIT; exit $2"; echo "gate-rc=$?"; }
ctl pipeline-runlog-failure-keeps-exit-code-catch 0 '^WARN +runlog: no row added \(runlog\.py exit 5\): boom: runlog is broken on purpose' 'gate-rc=12' '!gate-rc=4' '!row added to' -- rpcase $RP/bin-fail 12
ctl pipeline-runlog-failure-keeps-exit-zero-catch 0 '^WARN +runlog: no row added' 'gate-rc=0' -- rpcase $RP/bin-fail 0
UPG_APP_NAME=CODE-A UPG_FIELD_RUNS=$RP/FIELD-RUNS.md ctl pipeline-runlog-ok-reminder-pass 0 '^runlog: row added to .*FIELD-RUNS\.md\. Commit FIELD-RUNS\.md and CHANGES\.md' 'gate-rc=12' '!WARN' -- rpcase $RP/bin-ok 12
ctl pipeline-runlog-row-written-pass 0 '^\| 20261013041248 \| CODE-A \|' -- grep -E '^\| 2' $RP/FIELD-RUNS.md
ctl pipeline-runlog-wired-pass 0 '^  record_runlog \|\| true$' 'STEP:-\}" = gate \].*record_runlog' 'python3 -I "\$B/runlog\.py" --work "\$WORK"' -- grep -E 'record_runlog|runlog\.py' $B/cloud/upgrade-pipeline.sh

# --- MET-1 / MET-2: step timing and the automatic run log. Golden: the REAL gate-summary of the Purchase Request re-run
# (controls/fixtures/runlog/gate-summary.run6.md, run id 20261022075034). timing.tsv is never written by hand: the pipeline's own
# run_step / timing_open / timing_close / cleanup are extracted and run under its set -Eeu / ERR / EXIT traps, with a clock
# fed from a list (a `date` function shadows the command) and stub steps. controls/fixtures/runlog/old-12col-log.md =
# the header and three real rows of FIELD-RUNS.md as they were with 12 columns.
TM=$T/timing; mkdir -p $TM; GS=$here/fixtures/runlog/gate-summary.run6.md
{ sed -n '/^say() /p;/^quoted() /p;/^now_utc() /p;/^TIMING_STEP=/p' $B/cloud/upgrade-pipeline.sh
  for f in nj_add rerun_cmd nj_flush timing_open timing_close cleanup run_step decisions_apply; do sed -n "/^$f() {/,/^}/p" $B/cloud/upgrade-pipeline.sh; done; } > $TM/fn.sh
cat > $TM/h.sh <<'HEOF'
# h.sh WORK TIMES STEP...: run_step for each STEP the way main does, stub steps, a clock from the TIMES list
set -Eeu
trap 'exit 4' ERR
WORK=$1; TIMES=$2; shift 2
. "$FN"
date() { local n; n=$(cat "$WORK/.tick" 2> /dev/null || echo 0); n=$((n + 1)); echo "$n" > "$WORK/.tick"; sed -n "${n}p" "$TIMES"; }
mkdir -p "$WORK/state" "$WORK/logs"
ONLY=""; FROM=""; DRY=${DRY:-0}; NJ_TMP="$WORK/state/nj.tmp"; NJ_CODE=0; RUN=$WORK; SOURCE=10.24.0.1; TARGET=11.12.5; ARGS_ORIG=(); SELF=pipeline; STEP=""; LOG=$WORK/logs/x.log; APPS_UP=()
mxcli_pin() { :; }; proposal_recheck() { :; }; cockpit_regen() { :; }
step_build() { if [ -n "${STUB_FAIL:-}" ] && [ ! -f "$WORK/fixed" ]; then false; fi; }
step_journeys() { if [ ! -f "$WORK/fixed" ]; then nj_add 11 "journeys" "stub stop"; fi; }
trap cleanup EXIT
for s in "$@"; do run_step "$s"; done
HEOF
cat > $TM/times-a.txt <<'EOF'
2026-10-20T10:00:00Z
2026-10-20T10:12:00Z
2026-10-20T10:12:00Z
2026-10-20T10:12:00Z
2026-10-20T10:20:00Z
2026-10-20T13:20:00Z
2026-10-20T14:00:00Z
2026-10-20T14:00:00Z
EOF
cat > $TM/times-b.txt <<'EOF'
2026-10-20T10:00:00Z
2026-10-20T10:05:00Z
2026-10-20T12:05:00Z
2026-10-20T12:17:00Z
2026-10-20T12:17:00Z
EOF
tmrun() { FN=$TM/fn.sh B=$B bash $TM/h.sh "$@"; echo "rc=$?"; }
# A: build ok, journeys stops (exit 11) after 8 minutes; the person fixes it; 3 hours after the stop the pipeline runs again
tmrun $TM/wa $TM/times-a.txt build journeys > /dev/null 2>&1
cp $TM/wa/state/timing.tsv $TM/wa-first.tsv
touch $TM/wa/fixed
tmrun $TM/wa $TM/times-a.txt build journeys > /dev/null 2>&1
tmshow() { echo "header=$(grep -c '^step	start_utc	end_utc	exit$' $1)"; echo "rows=$(grep -c '^[a-z]*	2026' $1)"; tr '\t' ' ' < $1; }
ctl timing-rows-per-attempt-catch 0 'header=1' 'rows=3' '^build 2026-10-20T10:00:00Z 2026-10-20T10:12:00Z 0$' \
  '^journeys 2026-10-20T10:12:00Z 2026-10-20T10:20:00Z 11$' '^journeys 2026-10-20T13:20:00Z 2026-10-20T14:00:00Z 0$' -- tmshow $TM/wa/state/timing.tsv
# resume: the earlier rows are byte for byte the same, and the done step (build) is not run or logged again
ctl timing-resume-appends-never-rewrites-pass 0 'prefix=same' 'build-rows=1' 'journeys-rows=2' \
  -- sh -c "n=\$(wc -l < $TM/wa-first.tsv); head -n \$n $TM/wa/state/timing.tsv | cmp -s - $TM/wa-first.tsv && echo prefix=same; echo build-rows=\$(grep -c '^build' $TM/wa/state/timing.tsv); echo journeys-rows=\$(grep -c '^journeys' $TM/wa/state/timing.tsv)"
# the stop keeps its own exit code (the judgment stop is the pipeline's result, timing never changes it)
ctl timing-stop-keeps-exit-code-pass 0 'rc=11' '!rc=4' -- tmrun $TM/wc $TM/times-a.txt build journeys
# an unexpected failure (ERR trap, exit 4) still leaves its row, with exit 4; the rerun a few hours later gets its own row
STUB_FAIL=1 tmrun $TM/wb $TM/times-b.txt build > /dev/null 2>&1; touch $TM/wb/fixed
STUB_FAIL=1 tmrun $TM/wb $TM/times-b.txt build > /dev/null 2>&1
ctl timing-failed-step-row-catch 0 'rows=2' '^build 2026-10-20T10:00:00Z 2026-10-20T10:05:00Z 4$' '^build 2026-10-20T12:05:00Z 2026-10-20T12:17:00Z 0$' -- tmshow $TM/wb/state/timing.tsv
# a dry run writes no timing file
DRY=1 tmrun $TM/wd $TM/times-a.txt build > /dev/null 2>&1
ctl timing-dry-run-no-file-pass 0 'timing=absent' -- sh -c "[ -e $TM/wd/state/timing.tsv ] && echo timing=present || echo timing=absent"

# person-wait split (bin/runlog.py --time-line): machine = the rows, wait = from a stop until the pipeline ran again
ctl timing-person-wait-split-catch 0 '^Time: build 12m, journeys 48m; machine 1h; person wait 3h$' '!machine 4h' -- python3 -I $B/runlog.py --time-line --work $TM/wa
# B: exit 4 is a failure, not a person: the 2 hours between the runs are NOT person wait
ctl timing-failure-gap-is-not-person-wait-pass 0 '^Time: build 17m; machine 17m; person wait 0m$' -- python3 -I $B/runlog.py --time-line --work $TM/wb
# a stop nobody has resumed yet is not counted (the first attempt alone)
mkdir -p $TM/we/state; cp $TM/wa-first.tsv $TM/we/state/timing.tsv
ctl timing-open-stop-not-counted-pass 0 '^Time: build 12m, journeys 8m; machine 20m; person wait 0m$' -- python3 -I $B/runlog.py --time-line --work $TM/we
mkdir -p $TM/wn; ctl timing-line-none-not-recorded-pass 0 '^Time: not recorded$' -- python3 -I $B/runlog.py --time-line --work $TM/wn
# every stop code is person time (10 to 15, not only 12); the other codes are not
for c in 10 11 12 13 14 15; do
  mkdir -p $TM/wx$c/state; printf 'step\tstart_utc\tend_utc\texit\ngate\t2026-10-20T10:00:00Z\t2026-10-20T10:01:00Z\t%s\ngate\t2026-10-20T10:31:00Z\t2026-10-20T10:32:00Z\t0\n' $c > $TM/wx$c/state/timing.tsv
  ctl timing-stop-exit-$c-is-person-wait-catch 0 '^Time: gate 2m; machine 2m; person wait 30m$' -- python3 -I $B/runlog.py --time-line --work $TM/wx$c
done
for c in 0 2 3 4; do
  mkdir -p $TM/wy$c/state; printf 'step\tstart_utc\tend_utc\texit\ngate\t2026-10-20T10:00:00Z\t2026-10-20T10:01:00Z\t%s\ngate\t2026-10-20T10:31:00Z\t2026-10-20T10:32:00Z\t0\n' $c > $TM/wy$c/state/timing.tsv
  ctl timing-exit-$c-is-not-person-wait-pass 0 '^Time: gate 2m; machine 2m; person wait 0m$' -- python3 -I $B/runlog.py --time-line --work $TM/wy$c
done

# gate-summary.md gets the Time: line right after the Work: line; stamping twice leaves exactly one; nothing else changes
mkdir -p $TM/ws/state; cp $GS $TM/ws/gate-summary.md; cp $TM/wa/state/timing.tsv $TM/ws/state/
python3 -I $B/runlog.py --stamp-time --work $TM/ws > /dev/null; python3 -I $B/runlog.py --stamp-time --work $TM/ws > /dev/null
ctl timing-stamp-gate-summary-catch 0 'time-lines=1' 'line-after-work=yes' 'rest-unchanged=yes' '^Time: build 12m, journeys 48m; machine 1h; person wait 3h$' \
  -- sh -c "echo time-lines=\$(grep -c '^Time: ' $TM/ws/gate-summary.md); [ \"\$(grep -A1 '^Work: ' $TM/ws/gate-summary.md | tail -n 1 | cut -c1-5)\" = 'Time:' ] && echo line-after-work=yes; grep -v '^Time: ' $TM/ws/gate-summary.md | cmp -s - $GS && echo rest-unchanged=yes; grep '^Time: ' $TM/ws/gate-summary.md"
mkdir -p $TM/wsn; cp $GS $TM/wsn/gate-summary.md
ctl timing-stamp-without-timing-pass 0 'not stamped' 'unchanged=yes' -- sh -c "python3 -I $B/runlog.py --stamp-time --work $TM/wsn; cmp -s $TM/wsn/gate-summary.md $GS && echo unchanged=yes"

# FIELD-RUNS columns: the row of a run with timing ends in machine time and person wait; without timing.tsv, not recorded
ctl runlog-timing-columns-catch 0 '^\| 20261022075034 \| PR \| purchase request \| .* \| 2026-10-22 \| 1h \| 3h \|$' -- sh -c "python3 -I $B/runlog.py --work $TM/ws --log $TM/f1.md --app PR --type 'purchase request' --dry-run | grep '^| 2'"
ctl runlog-no-timing-not-recorded-pass 0 '^\| 20261022075034 \| PR \| .* \| 2026-10-22 \| not recorded \| not recorded \|$' -- sh -c "python3 -I $B/runlog.py --work $TM/wsn --log $TM/f2.md --app PR --dry-run | grep '^| 2'"
ctl runlog-new-log-has-14-columns-pass 0 'cols=14' 'row-cells=14' -- sh -c "python3 -I $B/runlog.py --work $TM/ws --log $TM/f3.md --app PR > /dev/null 2>&1; echo cols=\$(grep '^| run id' $TM/f3.md | awk -F' [|] ' '{print NF}'); echo row-cells=\$(grep '^| 2' $TM/f3.md | awk -F' [|] ' '{print NF}')"
# old rows (12 columns): kept byte for byte, read as before, header widened, the new row has 14
cp $FX/runlog/old-12col-log.md $TM/old.md
ctl runlog-old-log-new-row-header-widened-catch 0 'old-rows-same=yes' 'header-cols=14' 'sep-cols=14' 'row-cells=14' '^\| run id .* \| date \| run time \(machine\) \| person wait \|$' \
  -- sh -c "python3 -I $B/runlog.py --work $TM/wsn --run-id 20261030000001 --log $TM/old.md --app PR > /dev/null 2>&1; n=0; for i in 1 2; do l=\$(grep '^| 2' $FX/runlog/old-12col-log.md | sed -n \${i}p); grep -qxF \"\$l\" $TM/old.md && n=\$((n+1)); done; [ \$n = 2 ] && echo old-rows-same=yes; echo header-cols=\$(grep '^| run id' $TM/old.md | awk -F' [|] ' '{print NF}'); echo sep-cols=\$(grep '^|---' $TM/old.md | awk -F'---' '{print NF-1}'); echo row-cells=\$(grep '^| 20261030000001' $TM/old.md | awk -F' [|] ' '{print NF}'); grep '^| run id' $TM/old.md"
cp $FX/runlog/old-12col-log.md $TM/old2.md
ctl runlog-old-row-duplicate-refused-catch 0 'rc=3' 'already in the log' 'rows=2' -- sh -c "python3 -I $B/runlog.py --work $TM/ws --log $TM/old2.md --app PR 2>&1; echo rc=\$?; echo rows=\$(grep -c '^| 2' $TM/old2.md)"
ctl runlog-old-log-summary-pass 0 'rc=0' '^- \*\*NOTIF\*\* ' '^- \*\*PR\*\* \(purchase request\): latest run 2026-10-22; highest version reached 11\.12\.5; .*; 1 run$' -- sh -c "python3 -I $B/runlog.py --summary --log $TM/old2.md > /dev/null; echo rc=\$?; grep '^- \*\*' $TM/old2.md"
# mixed log (12-column rows and a 14-column row): the summary counts both widths
ctl runlog-mixed-width-summary-pass 0 'apps=2' 'runs-PR=2' -- sh -c "python3 -I $B/runlog.py --summary --log $TM/old.md > /dev/null; echo apps=\$(grep -c '^- \*\*' $TM/old.md); grep '^- \*\*PR\*\*' $TM/old.md | grep -q '; 2 runs\$' && echo runs-PR=2"
mkdir -p $TM/xr/w; cp $GS $TM/xr/w/gate-summary.md
ctl runlog-mixed-width-explain-logged-pass 0 '^w: LOGGED$' -- python3 -I $B/runlog.py --explain $TM/xr --log $TM/old.md --app PR
# --require-app: refused without a code name (exit 2), nothing written; with one, written
ctl runlog-require-app-refused-catch 0 'rc=2' 'no app code name' 'log=absent' -- sh -c "python3 -I $B/runlog.py --work $TM/wsn --run-id RID-9 --require-app --log $TM/f4.md 2>&1; echo rc=\$?; [ -e $TM/f4.md ] && echo log=present || echo log=absent"
ctl runlog-require-app-with-app-pass 0 'rc=0' 'rows=1' -- sh -c "python3 -I $B/runlog.py --work $TM/wsn --run-id RID-9 --require-app --app CODE-A --log $TM/f5.md > /dev/null 2>&1; echo rc=\$?; echo rows=\$(grep -c '^| RID' $TM/f5.md)"

# the automatic call at the end of the gate step: record_runlog, extracted, under the pipeline's traps. A refusal never fails
# the run: the reason goes to the console, gate-summary.md and NEEDS-JUDGMENT.md; the exit code stays the step's own.
AR=$T/autorl; mkdir -p $AR
arcase() { # arcase NAME EXITCODE [VAR=VALUE...]: a new work folder (golden gate-summary + timing), the gate step exits $2
  local n=$1 ec=$2; shift 2
  mkdir -p "${AR:?}/$n/work/state"; cp $GS $AR/$n/work/gate-summary.md; cp $TM/wa/state/timing.tsv $AR/$n/work/state/
  [ -z "${AR_LOG:-}" ] || cp "$AR_LOG" $AR/$n/FIELD-RUNS.md
  [ -z "${AR_APP:-}" ] || printf '%s\n' "$AR_APP" > $AR/$n/work/state/app-code
  [ -z "${AR_NJ:-}" ] || printf '# NEEDS JUDGMENT: step gate, exit 12\n' > $AR/$n/work/NEEDS-JUDGMENT.md
  env ${1:+"$@"} UPG_FIELD_RUNS=$AR/$n/FIELD-RUNS.md bash -c "set -Eeu; trap 'exit 4' ERR; . $RP/fn.sh; APPS_UP=(); B=$B; WORK=$AR/$n/work; TK=$RP/tk; STEP=gate; DRY=0; trap cleanup EXIT; exit $ec"; echo "gate-rc=$?"
}
arshow() { echo "summary-run-log=$(grep -c '^Run log: no row added' $AR/$1/work/gate-summary.md)"; echo "nj=$(cat $AR/$1/work/NEEDS-JUDGMENT.md 2> /dev/null | grep -c '^## Run log not added')"; echo "rows=$(cat $AR/$1/FIELD-RUNS.md 2> /dev/null | grep -c '^| 2')"; }
# ok: the row carries timing, the Time: line is stamped, the commit hint is printed
ctl pipeline-autorunlog-ok-pass 0 'gate-rc=0' '^runlog: row added to .*FIELD-RUNS\.md\. Commit FIELD-RUNS\.md and CHANGES\.md .*toolkit PR' '!WARN' -- arcase ok 0 UPG_APP_CODE=PR UPG_APP_TYPE=pr-type
ctl pipeline-autorunlog-ok-row-pass 0 '^\| 20261022075034 \| PR \| pr-type \| .* \| 1h \| 3h \|$' 'Time: build 12m, journeys 48m; machine 1h; person wait 3h' -- sh -c "grep -h -E '^\| 2|^Time: ' $AR/ok/FIELD-RUNS.md $AR/ok/work/gate-summary.md"
# the older name and the state file stand in when UPG_APP_CODE is unset
ctl pipeline-autorunlog-app-name-fallback-pass 0 'gate-rc=0' '^runlog: row added' -- arcase oldname 0 UPG_APP_NAME=PR
AR_APP=PR ctl pipeline-autorunlog-state-file-pass 0 'gate-rc=0' '^runlog: row added' -- arcase state 0
ctl pipeline-autorunlog-state-file-row-pass 0 '^\| 20261022075034 \| PR \|' -- grep '^| 2' $AR/state/FIELD-RUNS.md
# refusals: duplicate (exit 3), customer name (exit 4), no app code name (exit 2): reason shown, gate exit code unchanged
AR_LOG=$FX/runlog/old-12col-log.md ctl pipeline-autorunlog-duplicate-refused-catch 0 'gate-rc=0' '!gate-rc=3' '^WARN +runlog: no row added \(runlog\.py exit 3\): the run id is already in the log' -- arcase dup 0 UPG_APP_CODE=PR
ctl pipeline-autorunlog-duplicate-reported-catch 0 'summary-run-log=1' 'nj=1' 'rows=2' -- arshow dup
ctl pipeline-autorunlog-duplicate-needs-judgment-text-catch 0 'information only, the run result is unchanged' 'already in the log' 'toolkit PR' -- cat $AR/dup/work/NEEDS-JUDGMENT.md
CNAME="the Acmecorp app"
ctl pipeline-autorunlog-customer-name-refused-catch 0 'gate-rc=12' '!gate-rc=4' '^WARN +runlog: no row added \(runlog\.py exit 4\): the row holds a customer name' -- arcase cname 12 "UPG_APP_CODE=$CNAME"
ctl pipeline-autorunlog-customer-name-reported-catch 0 'summary-run-log=1' 'nj=1' 'rows=0' -- arshow cname
ctl pipeline-autorunlog-no-app-refused-catch 0 'gate-rc=0' '^WARN +runlog: no row added \(runlog\.py exit 2\): runlog\.py needs an app code name' 'UPG_APP_CODE' -- arcase noapp 0
ctl pipeline-autorunlog-no-app-reported-catch 0 'summary-run-log=1' 'nj=1' 'rows=0' -- arshow noapp
# a gate step that stopped for judgment already wrote NEEDS-JUDGMENT.md: the information section is appended, the stop text stays
AR_NJ=1 ctl pipeline-autorunlog-appends-to-existing-needs-judgment-catch 0 'gate-rc=12' '!gate-rc=4' -- arcase njappend 12
ctl pipeline-autorunlog-needs-judgment-kept-catch 0 '^# NEEDS JUDGMENT: step gate, exit 12$' '^## Run log not added' '!information only, the run result is unchanged' -- cat $AR/njappend/work/NEEDS-JUDGMENT.md

# --- PRC-4 (Purchase Request run 4): the diff step names the app's git repo in gate.conf (APP_REPO), so gate.sh prints its
# `Changes:` line when the app is not under $WORK/app. Golden: the step's own dry-run output (the conf it would write).
DG=$T/dg; rm -rf "$DG"; mkdir -p "$DG/app/.git" "$DG/plain" "$DG/w"
{ sed -n '/^say() {/p;/^mda_old() {/p;/^mda_new() {/p;/^login_path() /p' $B/cloud/upgrade-pipeline.sh; sed -n '/^step_diff() {/,/^}/p' $B/cloud/upgrade-pipeline.sh; echo 'xo() { return 0; }'; } > $DG/fn.sh
dgcase() { sh -c "true" ; bash -c "set -Eeu; . $DG/fn.sh; B=$B; WORK=$DG/w; SOURCE=10.24.0; TARGET=11.12.5; OLD_MDA=''; DRY=1; APP=$1; step_diff"; }
ctl pipeline-diff-app-repo-catch 0 "^  APP_REPO=$DG/app\$" -- dgcase $DG/app
ctl pipeline-diff-app-repo-plain-pass 0 '^  BUILD_LOG=' '!APP_REPO' -- dgcase $DG/plain
# PRC-8: with the journeys stage's stored results in the work folder the diff step has the gate judge them again (no app)
mkdir -p "$DG/w2/e2e-after/after" "$DG/w2/e2e-before-picked" "$DG/w2/journeys"; echo '{}' > "$DG/w2/e2e-after/after/summary.json"; echo '{"actions": []}' > "$DG/w2/actions.json"
dgcase2() { bash -c "set -Eeu; . $DG/fn.sh; B=$B; WORK=$1; SOURCE=10.24.0; TARGET=11.12.5; OLD_MDA=''; DRY=1; APP=$DG/plain; step_diff"; }
ctl pipeline-diff-journeys-rejudge-catch 0 "^  JOURNEYS_DIR=$DG/w2/journeys\$" "^  JOURNEYS_BEFORE=$DG/w2/e2e-before-picked\$" '^  JOURNEYS_REJUDGE=1$' "^  ACTIONS=$DG/w2/actions\.json\$" -- dgcase2 $DG/w2
ctl pipeline-diff-journeys-none-pass 0 '^  BUILD_LOG=' '!JOURNEYS' -- dgcase2 $DG/w

# --- PRC-6 (Purchase Request run 4): a page widget named like a LAYOUT widget is not generated (the guard `.mx-name-<w>` is
# met by the layout on any page). Golden: MyRequests.container6 / Atlas_TopBar_Customized.container6 in the real run's
# actions.json; here the pr-unassigned.json records plus one layout action named like Task_Approver.actionButton8.
NC=$T/nc; rm -rf "$NC"; mkdir -p "$NC"
python3 -c "
import json,copy,sys
d=json.load(open(sys.argv[1])); a=next(x for x in d['actions'] if x['id'].endswith('Task_Approver.actionButton8'))
for name,w in (('same',a['widget']),('other','actionButton99')):
    v=copy.deepcopy(d); l=copy.deepcopy(a); l.update(id='PurchaseApprovals.TopBar.'+w, host='PurchaseApprovals.TopBar', host_type='Layout', widget=w, path=[], todo=['no-click-path'])
    v['actions'].append(l); json.dump(v, open(sys.argv[2]+'/'+name+'.json','w'))" $FX/actions/pr-unassigned.json $NC
python3 $B/gen_journeys.py --actions $NC/same.json --out-dir $NC/gs > /dev/null 2>&1
python3 $B/gen_journeys.py --actions $NC/other.json --out-dir $NC/go > /dev/null 2>&1
NCP="import json,sys; p=json.load(open(sys.argv[1])); print('skipped', [(s['id'].split('.')[-1], s.get('reasons')) for s in p['skipped'] if s['id'].endswith('Task_Approver.actionButton8')]); print('journeys', len([j for j in p['journeys'] if j['id'].endswith('Task_Approver.actionButton8')]))"
ctl gen-journeys-name-collision-catch 0 "^skipped \[\('actionButton8', \['name-collision'\]\)\]\$" '^journeys 0$' -- python3 -c "$NCP" $NC/gs/plan.json
ctl gen-journeys-name-collision-other-name-pass 0 '^skipped \[\]$' '^journeys 1$' -- python3 -c "$NCP" $NC/go/plan.json

# --- PRC-7 (Purchase Request run 4): gen_journeys.py removes the generated journeys of an earlier run before it writes: an action
# that became a todo or was skipped no longer runs from a stale file; a hand-written journey (no "_why") and a process leg
# (proc-*, process_journeys.py's) stay.
SD=$NC/stale; rm -rf "$SD"
python3 $B/gen_journeys.py --actions $NC/other.json --out-dir $SD > /dev/null 2>&1
mkdir -p $SD/journeys/Approver
echo '{"id": "hand-1", "steps": []}' > $SD/journeys/Approver/hand-1.journey.json
echo '{"id": "proc-p01-01", "_why": ["process P01"], "steps": []}' > $SD/journeys/Approver/proc-p01-01.journey.json
python3 $B/gen_journeys.py --actions $NC/same.json --out-dir $SD > $NC/stale.out 2>&1
ctl gen-journeys-stale-journey-removed-catch 0 '^note: removed [0-9]+ journey file\(s\) of an earlier generation' -- cat $NC/stale.out
ctl gen-journeys-stale-journey-gone-catch 0 '^hand-1\.journey\.json$' '^proc-p01-01\.journey\.json$' '!actionButton8' -- ls $SD/journeys/Approver
ctl gen-journeys-stale-journey-kept-pass 0 'actionButton19' -- ls $SD/journeys/Approver

# --- PRF-1 (Purchase Request, owner decision D5, 2026-10-19): a confirmed process may fill a conditionally visible field (the
# comment box under State = InProgress) when an earlier step of the same process opened the task; without that step the compiler
# still refuses. Golden: TaskInbox.actionButton7 (open-task) and Comments_TaskInbox.actionButton1 of the real model's actions.json.
PH=$FX/processes; PHA=$FX/actions/pr-comment-hidden.json
ctl process-hidden-field-after-open-task-pass 0 '^COMPILED P09 +Approver writes a comment +legs proc-p09-01$' '1 compiled · 0 invalid' -- python3 $B/process_journeys.py $PH/pr-comment-hidden.md --actions $PHA --out-dir $T/phf1
ctl process-hidden-field-no-open-task-catch 3 '^INVALID +P09 .*field textArea3 is conditionally visible \(dataView7\): no earlier step of this process opens the task that shows it' -- python3 $B/process_journeys.py $PH/pr-comment-hidden-nostate.md --actions $PHA --out-dir $T/phf2

# --- PRF-2 (Purchase Request, owner decision D6): an action shown only for an unassigned task ("Assign to me") of a role with ONE
# user can never render; gen_journeys.py --users lists it as todo assign-to-me-dead (skipped, never dropped) and the coverage line
# names it. Golden: pr-assign-sole.json (the 21 actions of the real P02, 4 of them "Assign to me"), users-sole / users-two.
PAS=$FX/processes; PAA=$FX/actions/pr-assign-sole.json
python3 $B/gen_journeys.py --actions $PAA --users $PAS/users-sole.json --out-dir $T/ad1 > $T/ad1.out 2>&1
python3 $B/gen_journeys.py --actions $PAA --users $PAS/users-two.json --out-dir $T/ad2 > $T/ad2.out 2>&1
python3 $B/gen_journeys.py --actions $PAA --out-dir $T/ad3 > $T/ad3.out 2>&1
ADP="import json,sys; p=json.load(open(sys.argv[1])); print('skipped', sorted((s['id'].split('.')[-1], tuple(s['reasons'])) for s in p['skipped'])); print('journeys', len(p['journeys'])); print('accounted', len(p['journeys']) + len(p['skipped']))"
ctl gen-journeys-assign-dead-catch 0 "^skipped \[\('actionButton19', \('assign-to-me-dead',\)\), \('actionButton19', \('assign-to-me-dead',\)\), \('actionButton19', \('assign-to-me-dead',\)\), \('actionButton19', \('assign-to-me-dead',\)\)\]\$" '^journeys 17$' '^accounted 21$' '17 generated.*4 not generated by reason assign-to-me-dead 4' -- sh -c "python3 -c \"\$0\" $T/ad1/plan.json; cat $T/ad1.out" "$ADP"
ctl gen-journeys-assign-two-users-pass 0 '^skipped \[\]$' '^journeys 21$' -- python3 -c "$ADP" $T/ad2/plan.json
ctl gen-journeys-assign-no-users-pass 0 '^skipped \[\]$' '^journeys 21$' -- python3 -c "$ADP" $T/ad3/plan.json
# the Administrator's "Assign to user" (workflow admin pages: every task, assigned or not) PASSED on the old app: not dead, a journey
python3 $B/gen_journeys.py --actions $FX/actions/pr-assign-admin.json --users $PAS/users-sole-admin.json --out-dir $T/ad4 > $T/ad4.out 2>&1
ADA="import json,sys; p=json.load(open(sys.argv[1])); print('dead', sorted(s['id'].split('.')[-2] + '.' + s['id'].split('.')[-1] for s in p['skipped'] if 'assign-to-me-dead' in s['reasons'])); print('admin journey', [j['id'] for j in p['journeys'] if 'Snip_UserTaskView_Details.actionButton10' in j['id']])"
ctl gen-journeys-assign-admin-kept-pass 0 "^dead \\['Task_Approver\\.actionButton19', 'Task_InvoiceProcessor\\.actionButton19', 'Task_POCreator\\.actionButton19', 'Task_Receiver\\.actionButton19'\\]\$" "^admin journey \\['act-WorkflowCommons\\.Snip_UserTaskView_Details\\.actionButton10'\\]\$" -- python3 -c "$ADA" $T/ad4/plan.json
# the coverage line of run_journeys.py names the reason; the action is a todo, not a defect (G and D unchanged by it)
CVP="import sys; sys.path.insert(0, '$B'); import run_journeys as r
acts = {'a.One': {'id': 'a.One'}, 'a.Two': {'id': 'a.Two'}, 'a.Assign': {'id': 'a.Assign'}}
js = {'j1': {'verdict': 'PASS'}, 'j2': {'verdict': 'PASS'}}
cur = {'links': {'j1': ['a.One'], 'j2': ['a.Two']}}
c = r.coverage(js, {}, cur, None, acts, None, [], False, {'a.Assign': 'assign-to-me-dead'})
print(c['line']); print('G', c['G'], 'D', c['D'], 'T', c['T'])"
ctl journeys-coverage-assign-dead-catch 0 '1 todo: assign-to-me-dead 1' '^G 2 D 0 T 1$' -- python3 -c "$CVP"
ctl journeys-coverage-no-reason-pass 0 '1 todo: no journey 1' '!assign-to-me-dead' -- sh -c "python3 -c \"\$(echo \"\$0\" | sed 's/, {.a.Assign.: .assign-to-me-dead.})/)/')\"" "$CVP"

# --- batch-templates fixes (BT-n; golden input = captured output of the batch runs, controls/fixtures/batch-bt/) ---
BTF=$FX/batch-bt
# BT-10: a full disk reads as "An error occurred while creating the deployment package". Golden: the tail of the real DOCGEN
# baseline.log (ENOSPC inside DotNetZip) and the same log without the IOException chain.
ctl bt10-diskcheck-enospc-log-catch 1 'DISK FULL: the log holds an out-of-space error' 'This is the host, not the app' 'Fix: free ' -- env UPG_FREE_MB=50000 bash $B/diskcheck.sh --need-mb 300 --log $BTF/baseline-enospc.log $T
ctl bt10-diskcheck-low-free-catch 1 'DISK FULL: only 235 MB are free' -- env UPG_FREE_MB=235 bash $B/diskcheck.sh --need-mb 2000 --log $BTF/baseline-plain-fail.log $T
ctl bt10-diskcheck-plain-failure-pass 0 'disk ok: 50000 MB free' '!DISK FULL' -- env UPG_FREE_MB=50000 bash $B/diskcheck.sh --need-mb 300 --log $BTF/baseline-plain-fail.log $T
# a minimal run folder for pipeline controls of the batch-templates fixes: fake docker (preflight asks `docker info`), an empty app
BTR=$T/btrun; mkdir -p $BTR/app $BTR/bin $BTR/tools/mxbuild-10.24.26.1 $BTR/tools/mxbuild-11.15.0.1 $BTR/tools/runtime-10.24.26.1 $BTR/tools/runtime-11.15.0.1 $BTR/work/state; touch $BTR/app/App.mpr
printf '#!/bin/sh\nexit 0\n' > $BTR/tools/mxcli-linux; chmod +x $BTR/tools/mxcli-linux
printf '#!/bin/sh\nexit 0\n' > $BTR/bin/docker; chmod +x $BTR/bin/docker
BTP=$BTR/work
btpipe() { local e=(); while [ "${1:-}" != "" ] && [[ "$1" == *=* ]]; do e+=("$1"); shift; done; env PATH=$BTR/bin:$PATH MXCLI= ${e[@]+"${e[@]}"} bash $B/cloud/upgrade-pipeline.sh --app-dir $BTR/app --source 10.24.26.1 --target 11.15.0.1 --work $BTP "$@"; }
ctl bt10-pipeline-baseline-gate-catch 3 "step 'baseline': DISK FULL: only 12 MB are free" '!mxbuild' -- btpipe UPG_FREE_MB=12 --only baseline
# the two helpers themselves: a full disk adds the DISK FULL judgment item; a plain build failure adds none
sed -n '/^disk_gate() {/,/^}/p;/^disk_cause() {/,/^}/p' $B/cloud/upgrade-pipeline.sh > $BTR/disk-fn.sh
btdisk() { ( B=$B; WORK=$T; DRY=0; LOG=$BTF/baseline-enospc.log; NJ_TMP=$BTR/nj.tmp; : > $NJ_TMP; NJ_CODE=0
  nj_add() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }; . $BTR/disk-fn.sh; "$@"; echo "rc=$?" ); }
ctl bt10-disk-cause-enospc-catch 0 '^10\|DISK FULL, not an app defect\|DISK FULL: the log holds' -- env UPG_FREE_MB=50000 bash -c "$(declare -f btdisk); B=$B BTF=$BTF BTR=$BTR T=$T; btdisk disk_cause"
ctl bt10-disk-cause-plain-failure-pass 0 '!DISK FULL' 'rc=0' -- env UPG_FREE_MB=50000 bash -c "$(declare -f btdisk); B=$B BTF=$BTF BTR=$BTR T=$T; btdisk disk_cause $BTF/baseline-plain-fail.log"
ctl bt10-pipeline-steps-wired-pass 0 '^ +disk_gate baseline$' '^ +disk_cause$' '^  disk_gate build$' '^    disk_cause "\$WORK/build-\$TARGET.log"$' '^  disk_gate convert$' -- grep -E '^ *disk_(gate|cause)' $B/cloud/upgrade-pipeline.sh

# BT-9: old-app run directories and a shipped deployment/ folder fill the disk. Golden layout: the top-level names of a real
# unpacked MDA (model, native, sass, tmp, web) plus data/ as runapp.py makes it and the evidence files it writes.
BT9=$T/bt9; mkdir -p $BT9/bin
cat > $BT9/bin/docker <<'EOF2'
#!/bin/sh
case "$1" in
  ps) printf '%s\n' $BT9_NAMES;;
  logs) echo "log of $2";;
esac
exit 0
EOF2
chmod +x $BT9/bin/docker
bt9run() { # bt9run WORK NAME: a run/<name> folder as runapp.py leaves it after a start
  local r=$1/run/$2; rm -rf $r; mkdir -p $r/model $r/native $r/sass $r/tmp $r/web $r/data/files $r/data/tmp $r/data/database $r/data/model-upload
  head -c 2000000 /dev/zero > $r/model/model.mdp; head -c 1000000 /dev/zero > $r/web/mxclientsystem.js; head -c 3000 /dev/zero > $r/data/database/x.db
  echo content > $r/data/files/doc1; echo "HARNESS CONDITION: login" > $r/harness-login-override.txt; echo fx_db > $r/runapp-db.txt; }
bt9py() { env PATH=$BT9/bin:$PATH BT9_NAMES="${BT9_NAMES:-mig-pg}" WORKDIR=$BT9/w python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print('freed', runapp.prune_run('old'))"; }
bt9run $BT9/w old
ctl bt9-prune-frees-catch 0 '^runapp: pruned run/old: 3 MB freed' '^freed 30[0-9]{5}$' -- bt9py
ctl bt9-prune-bulk-gone-catch 0 '^data$' '^data/files$' '^harness-login-override.txt$' '^runapp-db.txt$' '!model' '!web' '!native' '!sass' '!database' -- sh -c "cd $BT9/w/run/old && find . -mindepth 1 | sed 's#^\./##' | grep -vE '/' ; cd $BT9/w/run/old && find data -maxdepth 1 -mindepth 1 | sed 's#^#data/#;s#^data/data#data#'"
ctl bt9-prune-keeps-evidence-pass 0 '^content$' '^HARNESS CONDITION: login$' '^fx_db$' -- sh -c "cat $BT9/w/run/old/data/files/doc1 $BT9/w/run/old/harness-login-override.txt $BT9/w/run/old/runapp-db.txt"
bt9run $BT9/w old
ctl bt9-prune-container-present-pass 0 '^freed None$' -- env BT9_NAMES="mig-pg mig-old" bash -c "$(declare -f bt9py); BT9=$BT9 B=$B; bt9py"
ctl bt9-prune-container-present-kept-pass 0 'model.mdp' -- ls $BT9/w/run/old/model
ctl bt9-prune-keep-run-env-pass 0 '^freed None$' -- env UPG_KEEP_RUN=1 bash -c "$(declare -f bt9py); BT9=$BT9 B=$B; bt9py"
bt9run $BT9/w old
ctl bt9-stop-prunes-catch 0 'stopped mig-old' 'pruned run/old' -- env -u UPG_NAME PATH=$BT9/bin:$PATH BT9_NAMES=mig-pg UPG_ALLOW_DEFAULT_PREFIX=1 WORKDIR=$BT9/w python3 $B/runapp.py stop old
# fetch: the deployment/ folder beside the .mpr is not unpacked; javasource and a deployment/ deeper in the tree are
BT9Z=$BT9/zip; mkdir -p $BT9Z/src/shop/deployment/model $BT9Z/src/shop/javasource/deployment $BT9Z/src/shop/theme; echo m > $BT9Z/src/shop/App.mpr
echo big > $BT9Z/src/shop/deployment/model/model.mdp; echo j > $BT9Z/src/shop/javasource/deployment/Keep.java; echo t > $BT9Z/src/shop/theme/a.css
(cd $BT9Z/src && zip -qr ../shop.mpk shop)
mkdir -p $BT9Z/run1 $BT9Z/run2; cp -r $BTR/tools $BT9Z/run1/tools; cp -r $BTR/tools $BT9Z/run2/tools
bt9fetch() { env PATH=$BTR/bin:$PATH MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-zip $BT9Z/shop.mpk --source 10.24.26.1 --target 11.15.0.1 --work $1/work --only fetch; }
ctl bt9-fetch-skips-deployment-catch 2 '^theme/a.css$' '^javasource/deployment/Keep.java$' '!deployment/model' -- sh -c "$(declare -f bt9fetch); BTR=$BTR B=$B BT9Z=$BT9Z; bt9fetch $BT9Z/run1 >/dev/null 2>&1; cd $BT9Z/run1/app/shop && find . -type f ! -path './.git/*' | sed 's#^\./##' | sort; cd $BT9Z/run1/app/shop; bash -c 'exit 2'"
ctl bt9-fetch-note-pass 0 'fetch: the package ships a deployment/ folder' -- cat $BT9Z/run1/work/state/notes.txt

# BT-11: a module in both plan-pre.txt and plan.txt: the post-convert line starts from the pre-convert target. Golden: the real
# DOCGEN plan-pre.txt and plan.txt (Atlas_Core 3.21.1 then 4.5.1, DataWidgets once); installed versions from its PROPOSAL.md.
BT11=$T/bt11; mkdir -p $BT11/state
cp $BTF/docgen-plan-pre.txt $BT11/plan-pre.txt; cp $BTF/docgen-plan.txt $BT11/plan.txt
printf 'Atlas_Core 3.19.0 -> 4.5.1\nDataWidgets 3.11.4 -> 3.11.7\nAtlas_Web_Content 3.9.0 -> 4.4.0\nNanoflowCommons 5.2.1 -> 7.4.0\n' > $BT11/module-jumps.txt
python3 $B/proposal.py --work $BT11 --source 10.24.21.108016 --target 11.12.5 > /dev/null 2>&1
ctl bt11-second-pass-starts-from-first-catch 0 'module update Atlas_Core 3\.19\.0 -> 3\.21\.1 \(before the convert\)' 'module update Atlas_Core 3\.21\.1 -> 4\.5\.1 \(after the convert\)' '!Atlas_Core 3\.19\.0 -> 4\.5\.1' -- grep 'module update' $BT11/PROPOSAL.md
ctl bt11-single-pass-installed-pass 0 'module update Atlas_Web_Content 3\.9\.0 -> 4\.4\.0 \(after the convert\)' 'module update DataWidgets 3\.11\.4 -> 3\.11\.7 \(before the convert\)' 'module update NanoflowCommons 5\.2\.1 -> 7\.4\.0' -- grep 'module update' $BT11/PROPOSAL.md

# BT-8: `--only propose` needs no toolset, runtime or mxcli. A run folder whose tools/ folder is empty (the source runtime was
# deleted for disk room) still regenerates PROPOSAL.md; the same folder stops a step that does need them. Golden message:
# "missing runtime" / exit 3, as the DOCGEN and CMPL workers met it.
BT8=$T/bt8; mkdir -p $BT8/app $BT8/tools $BT8/work/state; touch $BT8/app/App.mpr
bt8() { env MXCLI= UPG_FREE_MB=90000 bash $B/cloud/upgrade-pipeline.sh --app-dir $BT8/app --source 10.24.26.1 --target 11.15.0.1 --work $BT8/work "$@"; }
ctl bt8-propose-without-tools-catch 14 'needs judgment \(exit 14\)' '!missing' '!setup\.sh' -- bt8 --only propose
ctl bt8-triage-without-tools-pass 3 "missing source mxbuild toolset: $BT8/tools/mxbuild-10.24.26.1" -- bt8 --only triage
ctl bt8-baseline-without-tools-pass 3 'missing source mxbuild toolset' -- bt8 --only baseline

# BT-2: a module-only template (the INCL Incentro Layouts shape: layouts, no navigation home page, no theme) stops at triage with a
# plain "module, not an app" item, not at the baseline as "OLD app does not build". The model is synthetic (the real INCL app was
# deleted after the batch); the condition is the one mxbuild reported: "Select a default home page for this profile".
BT2=$T/bt2; mkdir -p $BT2/mod $BT2/app
python3 $B/../controls/lib/mkmodel.py $FX/models/module-only.json $BT2/mod > /dev/null; python3 $B/../controls/lib/mkmodel.py $FX/models/nav.json $BT2/app > /dev/null
ctl bt2-appshape-module-only-catch 1 '^appshape: MODULE-ONLY; modules: IncentroLayouts; navigation profiles: 1; home pages set: 0; theme: no design-properties' -- python3 $B/appshape.py $BT2/mod
ctl bt2-appshape-app-pass 0 '^appshape: APP; .*home pages set: [1-9]' -- python3 $B/appshape.py $BT2/app/App.mpr
ctl bt2-appshape-unreadable-pass 2 '^appshape: UNKNOWN' -- python3 $B/appshape.py $(model base)
bt2() { local d=$1; shift; rm -rf $BT2/r-$d; mkdir -p $BT2/r-$d/work/state; cp -r $BT2/$d $BT2/r-$d/app; cp -r $BTR/tools $BT2/r-$d/tools
  env MXCLI= "$@" bash $B/cloud/upgrade-pipeline.sh --app-dir $BT2/r-$d/app --source 10.24.26.1 --target 11.15.0.1 --work $BT2/r-$d/work --only triage; local rc=$?
  [ ! -f $BT2/r-$d/work/NEEDS-JUDGMENT.md ] || cat $BT2/r-$d/work/NEEDS-JUDGMENT.md; return $rc; }
ctl bt2-triage-module-only-stops-catch 13 'needs judgment \(exit 13\)' 'The source is a module, not an app: it needs a host app' 'home pages set: 0' 'wrap it in a host app' '!OLD app does not build' -- bt2 mod UPG_X=1
ctl bt2-triage-app-goes-on-pass 0 '!source is a module' -- sh -c "$(declare -f bt2); B=$B BT2=$BT2 BTR=$BTR; bt2 app UPG_X=1; true"
ctl bt2-triage-module-only-allowed-pass 0 '!source is a module' -- sh -c "$(declare -f bt2); B=$B BT2=$BT2 BTR=$BTR; bt2 mod UPG_ALLOW_MODULE_ONLY=1; true"

# BT-6: renamed or republished Marketplace modules, as data (playbooks/module-renames.tsv). Golden: the real localedits.json entries of
# TOUR (DataGrid 1.1.3, content 116540, UNKNOWN: download HTTP 500) and DOCGEN (ApprontoLicenser 7.0.1, content 1445; DataWidgets
# 3.11.4, content 116540, which already carries the new name and must not be flagged).
LR=$BTF/localedits-renamed.json
ctl bt6-renamed-datagrid-catch 1 '^RENAMED DataGrid 1\.1\.3 \(content 116540\) -> DataWidgets: .*do not plan DataGrid as a version update' -- python3 $B/renamed_modules.py $LR
ctl bt6-republished-licenser-catch 1 '^REPUBLISHED ApprontoLicenser 7\.0\.1 \(content 1445\) -> Emixa Licenser module: .*not an update of the installed 7\.x' -- python3 $B/renamed_modules.py $LR
ctl bt6-new-name-not-flagged-pass 1 '!(RENAMED|REPUBLISHED) DataWidgets' '!CommunityCommons' '!WorkflowCommons' -- python3 $B/renamed_modules.py $LR
python3 -c "import json; d=json.load(open('$LR')); json.dump([m for m in d if m['name'] in ('WorkflowCommons','DataWidgets','CommunityCommons')], open('$T/le-clean.json','w'))"
ctl bt6-clean-modules-pass 0 'none of the installed modules is in playbooks/module-renames.tsv' '!RENAMED ' -- python3 $B/renamed_modules.py $T/le-clean.json
python3 -c "import json; d=json.load(open('$LR')); [m.update(cid=0) for m in d if m['name']=='DataGrid']; json.dump(d, open('$T/le-nocid.json','w'))"
ctl bt6-no-content-id-by-name-catch 1 '^RENAMED DataGrid 1\.1\.3 \(content 116540\) -> DataWidgets' -- python3 $B/renamed_modules.py $T/le-nocid.json
ctl bt6-unreadable-input-catch 2 'cannot read' -- python3 $B/renamed_modules.py $T/none.json
# the proposal: a decision item per hit, no version-update line for it
BT6=$T/bt6; mkdir -p $BT6/state; cp $LR $BT6/localedits.json; printf '116540 3.11.7 DataGrid\n99 1.0.0 Plainmod\n' > $BT6/plan.txt; printf 'DataGrid 1.1.3 -> 3.11.7\nPlainmod 0.9.0 -> 1.0.0\n' > $BT6/module-jumps.txt
python3 $B/proposal.py --work $BT6 --source 10.24.26.1 --target 11.15.0.1 > /dev/null 2>&1
ctl bt6-proposal-decision-item-catch 0 '^- \[P-[0-9]+\] renamed module: DataGrid$' 'RENAMED on the Marketplace: content 116540 is now .DataWidgets.' '^- \[P-[0-9]+\] renamed module: ApprontoLicenser$' 'REPUBLISHED on the Marketplace: content 1445' -- sed -n '/^## 3\./,/^## 4\./p' $BT6/PROPOSAL.md
ctl bt6-proposal-no-update-line-catch 0 '!module update DataGrid' '!module update ApprontoLicenser' 'module update Plainmod 0\.9\.0 -> 1\.0\.0' -- sed -n '/^## 2\./,/^## 3\./p' $BT6/PROPOSAL.md
BT6B=$T/bt6b; mkdir -p $BT6B/state; python3 -c "import json; json.dump([m for m in json.load(open('$LR')) if m['name']=='DataWidgets'], open('$BT6B/localedits.json','w'))"; printf '116540 3.11.7 DataWidgets\n' > $BT6B/plan.txt; printf 'DataWidgets 3.11.4 -> 3.11.7\n' > $BT6B/module-jumps.txt
python3 $B/proposal.py --work $BT6B --source 10.24.26.1 --target 11.15.0.1 > /dev/null 2>&1
ctl bt6-proposal-new-name-updates-pass 0 'module update DataWidgets 3\.11\.4 -> 3\.11\.7' '!renamed module' -- grep -E 'module update|renamed module' $BT6B/PROPOSAL.md
ctl bt6-triage-writes-renamed-wired-pass 0 'renamed_modules\.py" "\$WORK/localedits.json"' -- grep 'renamed_modules.py' $B/cloud/upgrade-pipeline.sh

# BT-3: the login override. Golden: real web/ files of a 10.24 app (controls/fixtures/batch-bt/web: the stock login.html, the SSO
# redirect login-with-mendixsso-automatically.html, the form without SSO, and index.html whose own browser check is
# window.location.replace(appUrl + "unsupported-browser.html")). APPR: the SSO login.html and a backup of the stock page under
# another name; TOUR: login-without-sso.html that carries the browser check. The page names are the ones the batch met.
W3=$BTF/web; B3=$T/bt3; rm -rf $B3; mkdir -p $B3
bt3dir() { mkdir -p $B3/$1/web; }
bt3dir appr; cp $W3/login-with-mendixsso-automatically.html $B3/appr/web/login.html; cp $W3/login.html $B3/appr/web/login_backup_2022-12-12_10-33.html
bt3dir apprnoform; cp $W3/login-with-mendixsso-automatically.html $B3/apprnoform/web/login.html; printf '<html><body>Please wait</body></html>' > $B3/apprnoform/web/login_backup_2022-12-12_10-33.html
bt3dir tour; cp $W3/login-with-mendixsso-automatically.html $B3/tour/web/login.html
python3 - $W3 $B3 <<'PY'
import re, sys
w, b = sys.argv[1:3]
idx = open(w + "/index.html").read()
chk = re.search(r"<script type=\"text/javascript\">.*?</script>", idx, re.S).group(0)
for d, name in (("tour", "login-without-sso.html"), ("tourlogin", "login.html")):
    import os
    os.makedirs(f"{b}/{d}/web", exist_ok=True)
    open(f"{b}/{d}/web/{name}", "w").write(open(w + "/login-without-mendixsso.html").read().replace("</head>", chk + "</head>", 1))
PY
lo3() { python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; m=runapp.apply_login_override('$B3/$1','auto','$1'); print(m or 'UNTOUCHED')"; }
ctl bt3-sso-redirect-still-detected-catch 0 '^True$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.login_redirects_off_app(open('$W3/login-with-mendixsso-automatically.html').read()))"
ctl bt3-browser-check-is-not-sso-pass 0 '^False$' -- python3 -c "import sys; sys.path.insert(0,'$B'); import runapp; print(runapp.login_redirects_off_app(open('$W3/index.html').read()))"
ctl bt3-appr-backup-page-catch 0 'HARNESS CONDITION: appr: web/login.html replaced by login_backup_2022-12-12_10-33.html' -- lo3 appr
ctl bt3-appr-backup-page-bytes-pass 0 'usernameInput' '!self\.location' -- cat $B3/appr/web/login.html
ctl bt3-appr-backup-without-form-not-used-catch 0 'no stock login page' 'INVALID' '!replaced by' -- lo3 apprnoform
ctl bt3-tour-browser-check-page-used-catch 0 'HARNESS CONDITION: tour: web/login.html replaced by login-without-sso.html' -- lo3 tour
ctl bt3-stock-login-with-browser-check-untouched-pass 0 '^UNTOUCHED$' -- lo3 tourlogin

# BT-7: a role refused by the runtime's session limit is run again after the sessions expired. Golden: the engine's own INVALID text
# for a faulted login (vendor/e2e/journey-runner.js) with the real reason the COLLAB roles CustomerContact and SupplierContact met
# ("credentials rejected"). The runner is faked (node writes the findings file); everything else in run_journeys.py is real.
BT7=$T/bt7; mkdir -p $BT7/bin $BT7/gen/journeys/RoleA $BT7/gen/journeys/RoleB
echo '{"journeys": [], "skipped": [], "todo": [], "covered": [], "unreachable": []}' > $BT7/gen/plan.json
for r in RoleA RoleB; do echo '{"id": "login-'$r'", "role": "'$r'", "steps": [{"n": 1, "ui": {"ready": ".mx-navbar"}}]}' > $BT7/gen/journeys/$r/login-$r.journey.json; done
echo '{"RoleA": {"user": "smoke_a", "pass": "x"}, "RoleB": {"user": "smoke_b", "pass": "x"}}' > $BT7/users.json
cat > $BT7/bin/node <<'EOF2'
#!/usr/bin/env python3
import json, os
u = os.environ["TEST_USER"]; f = os.environ["BT7_COUNT"] + "." + u
n = (int(open(f).read()) if os.path.exists(f) else 0) + 1; open(f, "w").write(str(n))
os.makedirs("artifacts", exist_ok=True)
if u == "smoke_b" and n <= int(os.environ.get("BT7_REFUSALS", "0")):
    v, d = "INVALID", 'login faulted: "credentials rejected" \u2014 not a credential failure. The runtime refused the session (measured cause on 2026-08-18: trial-licence concurrent-session cap). Check the runtime log; no rung below this ran.'
else:
    v, d = "PASS", u
json.dump({"results": [{"rung": "ui", "name": "login", "verdict": v, "detail": d}], "walks": []}, open("artifacts/journey-findings.json", "w"))
EOF2
chmod +x $BT7/bin/node
bt7() { local w=$1 refusals=$2; shift 2; rm -f $BT7/count.*; env PATH=$BT7/bin:$PATH BT7_COUNT=$BT7/count BT7_REFUSALS=$refusals python3 $B/run_journeys.py $BT7/gen --label before --port 1 --admin-port 2 --admin-pass x --users $BT7/users.json --psql "$SHOP" --work $BT7/$w "$@"; }
bt7sum() { python3 -c "import json; r=json.load(open('$BT7/$1/before/summary.json'))['roles']; print({k: (v['login'], v.get('session_retries', 0)) for k, v in sorted(r.items())})"; }
ctl bt7-retry-after-refusal-catch 0 'session cap: RoleB refused by the runtime.s session limit; waiting 1s for sessions to expire, retry 1 of 2' -- bash -c "$(declare -f bt7); BT7=$BT7 B=$B SHOP=\"$SHOP\"; bt7 w1 1 --session-wait 1 >/dev/null 2>$BT7/w1.err; cat $BT7/w1.err | grep 'session cap'"
ctl bt7-retry-recovers-login-catch 0 "^{'RoleA': \('PASS', 0\), 'RoleB': \('PASS', 1\)}\$" -- bt7sum w1
ctl bt7-retry-count-pass 0 '^2$' -- cat $BT7/count.smoke_b
ctl bt7-persistent-refusal-stays-invalid-catch 0 "^{'RoleA': \('PASS', 0\), 'RoleB': \('INVALID', 2\)}\$" -- bash -c "$(declare -f bt7 bt7sum); BT7=$BT7 B=$B SHOP=\"$SHOP\"; bt7 w2 9 --session-wait 1 >/dev/null 2>&1; bt7sum w2"
ctl bt7-no-retries-option-pass 0 "^{'RoleA': \('PASS', 0\), 'RoleB': \('INVALID', 0\)}\$" -- bash -c "$(declare -f bt7 bt7sum); BT7=$BT7 B=$B SHOP=\"$SHOP\"; bt7 w3 1 --session-wait 1 --session-retries 0 >/dev/null 2>&1; bt7sum w3"
ctl bt7-clean-run-no-retry-pass 0 "^{'RoleA': \('PASS', 0\), 'RoleB': \('PASS', 0\)}\$" -- bash -c "$(declare -f bt7 bt7sum); BT7=$BT7 B=$B SHOP=\"$SHOP\"; bt7 w4 0 --session-wait 1 >/dev/null 2>&1; bt7sum w4"

# BT-1: the Mendix 9 mxbuild before 9.20 is Mono-era (modeler/mxbuild.exe and mx.exe, no native launcher). The layout is the one the
# batch met (INCL 9.3, TOUR 9.4, COLLAB 9.18: "mx9.sh: no .../modeler/mxbuild"); the recipe is the worker's, now committed: Mono
# image (bin/docker/Dockerfile.mx9-mono), launcher shims (bin/mono-shim.sh), image choice in bin/mx9.sh.
M1=$T/bt1; mkdir -p $M1
mkmono() { local d=$M1/$1/mxbuild-$2/modeler; rm -rf $M1/$1; mkdir -p $d/runtemplates/deployment $d/tools/node/node_modules; : > $d/mxbuild.exe; : > $d/mx.exe; }
mkmono mono 9.3.0.22930; mkmono shimmed 9.3.0.22930; mkmono native 9.24.32.1
printf '#!/bin/sh\n# the native launcher of 9.20 and later\n' > $M1/native/mxbuild-9.24.32.1/modeler/mxbuild; chmod +x $M1/native/mxbuild-9.24.32.1/modeler/mxbuild
ctl bt1-toolcheck-names-mono-catch 2 'Mono-era toolset \(before 9\.20\)' 'mono-shim\.sh' 'e5-mx9-mono' -- zsh $B/toolcheck.sh $M1/mono/mxbuild-9.3.0.22930 mxbuild
ctl bt1-shim-written-catch 0 'modeler/mxbuild and modeler/mx run through mono' -- bash $B/mono-shim.sh $M1/shimmed/mxbuild-9.3.0.22930
ctl bt1-shim-content-pass 0 '^exec mono "\$\(dirname "\$0"\)/mxbuild\.exe" "\$@"$' '^# mono-shim' -- cat $M1/shimmed/mxbuild-9.3.0.22930/modeler/mxbuild
ctl bt1-shim-mx-content-pass 0 '^exec mono "\$\(dirname "\$0"\)/mx\.exe" "\$@"$' -- cat $M1/shimmed/mxbuild-9.3.0.22930/modeler/mx
ctl bt1-shim-executable-pass 0 '^ok$' -- sh -c "test -x $M1/shimmed/mxbuild-9.3.0.22930/modeler/mxbuild && test -x $M1/shimmed/mxbuild-9.3.0.22930/modeler/mx && echo ok"
ctl bt1-shim-idempotent-pass 0 'run through mono' -- bash $B/mono-shim.sh $M1/shimmed/mxbuild-9.3.0.22930
ctl bt1-shim-native-untouched-pass 0 'native modeler/mxbuild launcher: nothing to do' -- bash $B/mono-shim.sh $M1/native/mxbuild-9.24.32.1
ctl bt1-shim-native-bytes-pass 0 '^# the native launcher of 9.20 and later$' '!mono' -- cat $M1/native/mxbuild-9.24.32.1/modeler/mxbuild
ctl bt1-shim-not-a-toolset-catch 2 'not an mxbuild toolset' -- bash $B/mono-shim.sh $T/bt1-nothing
ctl bt1-mx9-picks-mono-image-catch 0 'e5-mx9-mono /.*mxbuild-9\.3\.0\.22930/modeler/mxbuild' '!e5-mx9 /' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$M1/mono zsh $B/mx9.sh 9.3.0.22930 mxbuild --target=package x.mpr
ctl bt1-mx9-native-keeps-image-pass 0 'e5-mx9 /.*mxbuild-9\.24\.32\.1/modeler/mxbuild' '!e5-mx9-mono' -- env "PATH=$T/fakedocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$M1/native zsh $B/mx9.sh 9.24.32.1 mxbuild --target=package x.mpr
ctl bt1-mx9-image-override-pass 0 'myimage /' '!e5-mx9' -- env "PATH=$T/fakedocker:$PATH" UPG_IMAGE9=myimage UPG_ROOT=$T UPG_TOOLS=$M1/shimmed zsh $B/mx9.sh 9.3.0.22930 mxbuild --target=package x.mpr
mkdir -p $T/noimgdocker; printf '#!/bin/sh\n[ "$1 $2" = "image inspect" ] && exit 1\necho "docker $*"\n' > $T/noimgdocker/docker; chmod +x $T/noimgdocker/docker
ctl bt1-mx9-missing-image-says-how-catch 3 'needs the image e5-mx9-mono: docker build --network host -t e5-mx9-mono -f .*Dockerfile\.mx9-mono' '!^docker run' -- env "PATH=$T/noimgdocker:$PATH" UPG_ROOT=$T UPG_TOOLS=$M1/shimmed zsh $B/mx9.sh 9.3.0.22930 mxbuild --target=package x.mpr
ctl bt1-dockerfile-mono-pass 0 '^FROM eclipse-temurin:11-jdk$' 'mono-runtime mono-devel' 'libicu-dev libgdiplus git' -- grep -E '^FROM|apt-get install' $B/docker/Dockerfile.mx9-mono
ctl bt1-setup-builds-mono-image-pass 0 'need_mono\(\)' 'docker build .* -t e5-mx9-mono -f "\$TK/bin/docker/Dockerfile\.mx9-mono"' 'mono-shim\.sh' -- grep -E 'need_mono|e5-mx9-mono|mono-shim' $B/cloud/setup.sh
ctl bt1-setup-container-builds-mono-image-pass 0 '-t e5-mx9-mono -f "\$TK/bin/docker/Dockerfile\.mx9-mono"' 'mono-shim\.sh' -- grep -E 'e5-mx9-mono|mono-shim' $B/setup-container.sh

# --- jquery_classify (RA-19 recipe step 1): synthetic fixtures, hand-written (fixtures/jquery/README) ---
JQ=$FX/jquery
ctl jquery-classify-categories-catch 0 '1 unit\(s\) of 1 file\(s\), 10 jQuery call\(s\), 3 need code' '^classes: HTML-only 0, JS-light 0, JS-DOM 1$' '^\| TOTAL \| \| 2 \| 2 \| 1 \| 1 \| 1 \| 1 \| 2 \|$' 'plugin +1 +-> Marketplace pluggable widget +\[needs code\]' 'ajax +1 +-> microflow REST call$' -- python3 -I $B/jquery_classify.py $JQ/actions-synthetic.js
ctl jquery-classify-snippets-units-catch 0 '5 unit\(s\) of 1 file\(s\)' '^classes: HTML-only 1, JS-light 2, JS-DOM 2$' 'snippets-synthetic\.json:Home\.fetch \| JS-light \| 0 \| 0 \| 1 ' 'snippets-synthetic\.json:Home\.htmlOnly \| HTML-only \| 0 ' 'snippets-synthetic\.json:Home\.log \| JS-light \| 0 ' 'snippets-synthetic\.json:Home\.toggle \| JS-DOM \| 1 \| 2 \| 0 \| 0 \| 0 \| 0 \| 0 \|' 'snippets-synthetic\.json:Order\.form \| JS-DOM \| 0 \| 0 \| 1 \| 1 \| 0 \| 1 \| 0 \|' -- python3 -I $B/jquery_classify.py $JQ/snippets-synthetic.json
ctl jquery-classify-real-snippet-pass 0 '1 unit\(s\) of 1 file\(s\), 0 jQuery call\(s\), 0 need code' '^classes: HTML-only 0, JS-light 0, JS-DOM 1$' 'snippet-real-scroll\.json:WizardStep\.scrollToTop \| JS-DOM \|' -- python3 -I $B/jquery_classify.py $JQ/snippet-real-scroll.json
ctl jquery-classify-field-shape-flags-catch 0 '1 unit\(s\) of 1 file\(s\), 5 jQuery call\(s\), 0 need code' '^flags: bind-once 1, programmatic-click 1, dead-code 1$' 'bind-once: .*Menu\.jqueryNoRefresh: Refresh on context change is No: handlers bind once' 'programmatic-click: .*Set Storage Item' 'dead-code: .*likely dead, no live call: SaveLocal$' '^\| .*Menu\.jqueryNoRefresh \| JS-DOM \| 2 \| 3 \| 0 \|' -- python3 -I $B/jquery_classify.py $JQ/snippet-field-shape-synthetic.json
ctl jquery-classify-refresh-yes-no-bind-once-pass 0 '^flags: bind-once 0, programmatic-click 0, dead-code 0$' -- python3 -I $B/jquery_classify.py $JQ/snippet-real-scroll.json $JQ/snippets-synthetic.json
ctl jquery-classify-no-jquery-pass 0 '0 jQuery call\(s\), 0 need code' -- python3 -I $B/jquery_classify.py $FX/dojo-successors.tsv
ctl jquery-classify-missing-path-catch 2 'no such path' -- python3 -I $B/jquery_classify.py $JQ/nonexistent

# --- widget_defaults (playbooks/widget-config-defaults.tsv): defaults for properties with no counterpart, recorded in CHANGES.md ---
WD=$T/wd; rm -rf $WD; mkdir -p $WD/app $WD/w; git -C $WD/app init -q; echo a > $WD/app/page.txt; git -C $WD/app add page.txt; git -C $WD/app -c user.name=t -c user.email=t@t commit -qm original
echo b > $WD/app/page.txt
ctl widget-defaults-lists-unmapped-catch 0 '^defaulted: tabletItems = 1 \(widget default, https://raw\.githubusercontent\.com/mendix/web-widgets/.*Gallery\.xml\)$' '^defaulted: pageSize = 20 ' '!desktopItems' 'Gallery: 8 table row\(s\), 1 mapped, 7 defaulted, 0 not defaulted' -- python3 $B/widget_defaults.py --widget Gallery --mapped desktopItems
ctl widget-defaults-doc-row-best-practice-catch 0 '^defaulted: lazyLoading = true \(best practice, https://docs\.mendix\.com/appstore/widgets/combobox/\)$' -- python3 $B/widget_defaults.py --widget Combobox
ctl widget-defaults-unverified-not-applied-catch 0 '^not defaulted: title \(unverified, ' '^not defaulted: openOnHover ' 'DropdownContainer: 2 table row\(s\), 0 mapped, 0 defaulted, 2 not defaulted' '!^defaulted:' -- python3 $B/widget_defaults.py --widget DropdownContainer
ctl widget-defaults-unknown-widget-catch 2 'no row for target widget Nope' -- python3 $B/widget_defaults.py --widget Nope
ctl widget-defaults-commit-pass 0 'committed .*widget-defaults-gallery|Gallery: 8 table row' -- python3 $B/widget_defaults.py --widget Gallery --mapped desktopItems --commit $WD/app --subject "swap TemplateGrid to Gallery on Home" -- page.txt
ctl widget-defaults-changes-md-catch 0 '^Changes: 1 \(toolkit 0, agent 1, person 0, unlabelled 0\)$' -- python3 $B/changelog.py --app $WD/app --work $WD/w
ctl widget-defaults-changes-md-text-catch 0 'swap TemplateGrid to Gallery on Home; defaulted: tabletItems = 1 \(widget default' 'defaulted: pagination = buttons' 'widget-defaults-gallery' -- cat $WD/w/CHANGES.md

# --- mxcli v0.28.0 adoption: one version per run (bin/mxcli_pin.sh), the association refusal (#1502), the target.mpk tool error,
#     MXCLI_REF in both setup scripts. The logs under fixtures/mxcli-0.28.0/ are REAL captures (CAPTURE.txt); the stub binaries
#     print the one line a real `mxcli --version` prints ("mxcli version v0.28.0", "mxcli version 78bdfa5 (2026-10-14T00:13:40Z)").
PN=$T/pin; mkdir -p $PN/h
printf '#!/bin/sh\necho "mxcli version v0.28.0"\n' > $PN/mx-new
printf '#!/bin/sh\necho "mxcli version 78bdfa5 (2026-10-14T00:13:40Z)"\n' > $PN/mx-old
printf '#!/bin/sh\nexit 0\n' > $PN/mx-mute; printf '#!/bin/sh\n# another build\nexit 0\n' > $PN/mx-mute2
cp $PN/mx-old $PN/h/mxcli; chmod +x $PN/mx-* $PN/h/mxcli
ctl mxcli-pin-record-pass 0 'this run uses mxcli v0\.28\.0 \(recorded in ' -- bash $B/mxcli_pin.sh record $PN/st1 $PN/mx-new
ctl mxcli-pin-state-file-pass 0 '^v0\.28\.0$' '^# recorded ' -- cat $PN/st1
ctl mxcli-pin-check-same-pass 0 '!REFUSED' -- bash $B/mxcli_pin.sh check $PN/st1 $PN/mx-new
ctl mxcli-pin-check-other-catch 3 'REFUSED, this run was started with mxcli v0\.28\.0' 'mx-old is 78bdfa5' '--from triage' -- bash $B/mxcli_pin.sh check $PN/st1 $PN/mx-old
ctl mxcli-pin-two-binaries-catch 3 'REFUSED, this run would use two different mxcli versions: .*mx-new is v0\.28\.0, .*mx-old is 78bdfa5' -- bash $B/mxcli_pin.sh record $PN/st2 $PN/mx-new $PN/mx-old
ctl mxcli-pin-two-binaries-nothing-recorded-pass 1 -- test -e $PN/st2
ctl mxcli-pin-unrunnable-sha-pass 0 'this run uses mxcli sha256:[0-9a-f]{12}' -- bash $B/mxcli_pin.sh record $PN/st3 $PN/mx-mute
ctl mxcli-pin-unrunnable-other-catch 3 'REFUSED, this run was started with mxcli sha256:[0-9a-f]{12}' 'mx-mute2 is sha256:' -- bash $B/mxcli_pin.sh check $PN/st3 $PN/mx-mute2
ctl mxcli-pin-env-binary-catch 3 'REFUSED, this run was started with mxcli v0\.28\.0' -- env MXCLI=$PN/mx-old bash $B/mxcli_pin.sh check $PN/st1
ctl mxcli-pin-env-binary-pass 0 '!REFUSED' -- env MXCLI=$PN/mx-new bash $B/mxcli_pin.sh check $PN/st1
ctl mxcli-pin-host-update-cmd-catch 3 'REFUSED, this run would use two different mxcli versions' -- env MXCLI=$PN/mx-new PATH=$PN/h:$PATH UPG_UPDATE_CMD='mxcli marketplace update {cid}' bash $B/mxcli_pin.sh record $PN/st4
ctl mxcli-pin-container-update-cmd-pass 0 'this run uses mxcli v0\.28\.0' '!REFUSED' -- env MXCLI=$PN/mx-new PATH=$PN/h:$PATH UPG_UPDATE_CMD='bin/mxcli-container.sh marketplace update {cid}' bash $B/mxcli_pin.sh record $PN/st5
ctl mxcli-pin-host-abs-path-catch 3 'REFUSED, this run would use two different mxcli versions' -- env MXCLI=$PN/mx-new UPG_UPDATE_CMD="$PN/h/mxcli marketplace update {cid} --to {version}" bash $B/mxcli_pin.sh record $PN/st6
ctl mxcli-pin-custom-update-cmd-no-binary-pass 0 'this run uses mxcli v0\.28\.0' '!REFUSED' -- env MXCLI=$PN/mx-new PATH=$PN/h:$PATH UPG_UPDATE_CMD='bash fake-update.sh x {module} {mpr}' bash $B/mxcli_pin.sh record $PN/st7
ctl mxcli-pin-no-binary-says-so-pass 0 'no mxcli binary found .* not pinned or checked' -- env -u MXCLI -u UPG_MXCLI -u UPG_TOOLS bash $B/mxcli_pin.sh check $PN/st1
# stepupdate.sh reads the pipeline's state file (UPG_MXCLI_STATE): another mxcli = exit 3 before anything runs
FUP="bash $FX/bin/fake-update.sh $S {module} {mpr}"
newapp pn1 '1 1.0 Fine\n'; printf 'v0.0.1\n' > $PN/st-bad
ctl stepupdate-pin-mismatch-catch 3 'REFUSED, this run was started with mxcli v0\.0\.1' 'stepupdate: not run: the mxcli differs' '!== step' '!committed' -- env UPG_MXCLI_STATE=$PN/st-bad MXCLI=$PN/mx-new bash $B/stepupdate.sh $S/pn1 $S/pn1.plan
newapp pn2 '1 1.0 Fine\n'
ctl stepupdate-pin-same-pass 0 'committed' '!REFUSED' -- env UPG_UPDATE_CMD="$FUP" UPG_MXCLI_STATE=$PN/st1 MXCLI=$PN/mx-new bash $B/stepupdate.sh $S/pn2 $S/pn2.plan
# the pipeline: triage records, every later step that uses mxcli compares (the NJ harness above: an mxcli stub that prints nothing)
NJP=$NJ   # the app must sit inside the run folder (the NJ harness: run folder = $NJ)
mkdir -p $PN/dk; printf '#!/bin/sh\nexit 0\n' > $PN/dk/docker; chmod +x $PN/dk/docker   # `docker info` only: the pin runs before any step uses it
pipe() { local w=$1; shift; PATH=$PN/dk:$PATH MXCLI= bash $B/cloud/upgrade-pipeline.sh --app-dir $NJ/app --source 10.24.26.1 --target 11.15.0.1 --work $NJP/$w "$@"; }
ctl pipeline-pin-late-record-pass 0 'WARN    mxcli version: no pin from triage .* recording it now' '^sha256:[0-9a-f]{12}$' -- bash -c "$(declare -f pipe); NJ=$NJ NJP=$NJP B=$B PN=$PN; pipe wp1 --from convert --only convert; cat $NJP/wp1/state/mxcli-version | head -1"
mkdir -p $NJP/wp2/state; printf 'v0.0.1\n' > $NJP/wp2/state/mxcli-version
ctl pipeline-pin-mismatch-catch 0 'REFUSED, this run was started with mxcli v0\.0\.1' "step 'convert' not run: mxcli version pin \(exit 3\)" 'exit=3' '!running' '!needs judgment' -- bash -c "$(declare -f pipe); NJ=$NJ NJP=$NJP B=$B PN=$PN; pipe wp2 --from convert --only convert; echo exit=\$?"
mkdir -p $NJP/wp3/state; bash $B/mxcli_pin.sh record $NJP/wp3/state/mxcli-version $NJ/tools/mxcli-linux > /dev/null
ctl pipeline-pin-same-pass 0 'convert +running' '!REFUSED' '!WARN    mxcli version' -- bash -c "$(declare -f pipe); NJ=$NJ NJP=$NJP B=$B PN=$PN; pipe wp3 --from convert --only convert; true"
mkdir -p $NJP/wp4/state; printf 'v0.0.1\n' > $NJP/wp4/state/mxcli-version
ctl pipeline-pin-triage-rerecords-catch 0 '!REFUSED' '^sha256:[0-9a-f]{12}$' '!^v0\.0\.1$' -- bash -c "$(declare -f pipe); NJ=$NJ NJP=$NJP B=$B PN=$PN; pipe wp4 --from triage --only triage > /dev/null 2>&1; cat $NJP/wp4/state/mxcli-version | head -1"
ctl pipeline-pin-rung2-inherits-pass 0 'rung2/state/mxcli-version' -- grep -F 'rung2/state/mxcli-version' $B/cloud/upgrade-pipeline.sh
ctl pipeline-pin-dry-run-skips-pass 0 '!mxcli_pin' -- bash -c "$(declare -f pipe); NJ=$NJ NJP=$NJP B=$B PN=$PN; pipe wp5 --from convert --only convert --dry-run"
# the association refusal of mxcli v0.28.0 (#1502): REAL logs
L28=$FX/mxcli-0.28.0
export FAKE_SAVED_ASSOC=$L28/saved-edits/MendixSSO
FLG="bash $FX/bin/fake-log.sh {mpr}"
newapp as1 '111349 10.6.2 MendixSSO\n'
ctl stepupdate-assoc-refusal-catch 2 'ASSOCIATIONS: 6 association\(s\) owned by other modules reach into MendixSSO' 'PurchaseApprovals\.Request_MendixSSOUser_FirstApprover' 'MendixSSO has local LOGIC edits \(ASSOCIATION ENTITY JAR_DEPENDENCY \)' 'STOP: update of MendixSSO refused for local edits' '!committed' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-assoc.log bash $B/stepupdate.sh $S/as1 $S/as1.plan
newapp as2 '23513 4.5.0 Administration\n'
ctl stepupdate-assoc-refusal-pages-catch 2 'ASSOCIATIONS: 1 association\(s\) owned by other modules reach into Administration \(WorkflowCommons\.TaskAssignmentHelper_Account\)' 'STOP: update of Administration refused for local edits' '!committed' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-assoc-admin.log bash $B/stepupdate.sh $S/as2 $S/as2.plan
newapp as3 '111349 10.6.2 MendixSSO\n'
ctl stepupdate-old-wording-refusal-pass 2 'MendixSSO has local LOGIC edits \(ENTITY JAR_DEPENDENCY \)' 'STOP: update of MendixSSO refused for local edits' '!ASSOCIATIONS' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-old-78bdfa5.log bash $B/stepupdate.sh $S/as3 $S/as3.plan
# a convert-made verdict must not force over associations the convert did not make; without them it still forces
convapp as4 MendixSSO; printf '111349 10.6.2 MendixSSO\n' > $S/as4.plan
ctl stepupdate-assoc-convert-made-not-forced-catch 2 'CONVERT-MADE does not cover MendixSSO: association\(s\) of OTHER modules reach into it \(PurchaseApprovals\.Request_MendixSSOUser_FirstApprover,' 'Use --force-ui MendixSSO' 'STOP: update of MendixSSO refused for local edits' '!updating with --force' '!committed' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-assoc.log FAKE_OK=$M/step1-adds/App.mpr bash $B/stepupdate.sh $S/as4 $S/as4.plan
convapp as5 MendixSSO; printf '111349 10.6.2 MendixSSO\n' > $S/as5.plan
ctl stepupdate-convert-made-without-assoc-pass 0 'CONVERT-MADE: MendixSSO was installed pristine' 'updating with --force' 'committed' '!CONVERT-MADE does not cover' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-old-78bdfa5.log FAKE_OK=$M/step1-adds/App.mpr bash $B/stepupdate.sh $S/as5 $S/as5.plan
# --force-ui: the saved association-*.mdl files are listed after the step, recorded, and repeated in the summary
newapp as6 '111349 10.6.2 MendixSSO\n'
ctl stepupdate-assoc-saved-listed-catch 0 'ASSOCIATIONS-SAVED: 6 association\(s\) of other modules reached into MendixSSO' 'association-PurchaseApprovals_Request_MendixSSOUser_Requester\.mdl' 'association-PurchaseApprovals_Request_MendixSSOUser_SecondApprover\.mdl' 'restore_guid\.py puts the original back' 'committed' '^stepupdate: ASSOCIATIONS-SAVED \(owned by other modules' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-assoc.log FAKE_SAVED=$FAKE_SAVED_ASSOC FAKE_OK=$M/step1-adds/App.mpr bash $B/stepupdate.sh $S/as6 $S/as6.plan --force-ui MendixSSO
ctl stepupdate-assoc-saved-ledger-pass 0 '^MendixSSO 10\.6\.2: 6 association\(s\) in .*/MendixSSO/association-\*\.mdl$' -- cat $S/as6/.stepupdate/assoc-saved.txt
newapp as7 '1 1.0 UiEdit\n'
ctl stepupdate-no-assoc-saved-not-listed-pass 0 'saved edits for replay' 'committed' '!ASSOCIATIONS-SAVED' -- env UPG_UPDATE_CMD="$FUP" bash $B/stepupdate.sh $S/as7 $S/as7.plan --force-ui UiEdit
# v0.28.0's own update fails after the gate: a TOOL ERROR (exit 3, tree reverted, nothing recorded), not a refusal of the module
newapp as8 '111349 10.6.2 MendixSSO\n'
ctl stepupdate-target-mpk-tool-error-catch 3 'STOP: TOOL ERROR in the update of MendixSSO \(open package target\.mpk: open /tmp/mxu[0-9]+/target\.mpk: no such file or directory' 'tree reverted' 'rerun with --from MendixSSO' '!committed' '!KEPT' -- env UPG_UPDATE_CMD="$FLG" FAKE_REFUSE=$L28/update-refused-assoc.log FAKE_FORCE=$L28/update-force-saveedits.log bash $B/stepupdate.sh $S/as8 $S/as8.plan --unattended --force-ui MendixSSO
ctl stepupdate-target-mpk-reverted-pass 0 '^clean$' -- sh -c "cd $S/as8 && test -z \"\$(git status --porcelain --untracked-files=no)\" && ! test -s .stepupdate/kept.txt && echo clean"
# the pipeline notes a saved association that no replay script creates
AU=$T/assoc-unreplayed; mkdir -p $AU/saved-edits/MendixSSO $AU/replay
cp $L28/saved-edits/MendixSSO/association-PurchaseApprovals_Request_MendixSSOUser_Requester.mdl $AU/saved-edits/MendixSSO/
ctl pipeline-assoc-unreplayed-catch 0 'NOT replayed' 'association PurchaseApprovals\.Request_MendixSSOUser_Requester \(owned by another module, removed by the MendixSSO update\)' -- bash -c "WORK=$AU DRY=0 NOTES=$AU/state; mkdir -p \$NOTES; note() { echo \"\$*\"; }; $(sed -n '/^assoc_unreplayed() {/,/^}/p' $B/cloud/upgrade-pipeline.sh); assoc_unreplayed"
printf 'create or modify association PurchaseApprovals.Request_MendixSSOUser_Requester\nfrom PurchaseApprovals.Request to MendixSSO.MendixSSOUser;\n' > $AU/replay/MendixSSO.mdl
ctl pipeline-assoc-replayed-pass 0 '!NOT replayed' -- bash -c "WORK=$AU DRY=0; note() { echo \"\$*\"; }; $(sed -n '/^assoc_unreplayed() {/,/^}/p' $B/cloud/upgrade-pipeline.sh); assoc_unreplayed"
# MXCLI_REF: both setup scripts build the pinned ref (never HEAD) and stamp it
ctl setup-mxcli-ref-default-catch 0 'mxcli: mxcli version 78bdfa5 \(MXCLI_REF=78bdfa51a2e0a84b971093ebd7b6b82e7596c950\)' '!WARNING' -- macsetup ref1 FAKE_UNAME=Linux UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-ref-fetched-pass 0 '^fetch -q --depth 1 origin 78bdfa51a2e0a84b971093ebd7b6b82e7596c950$' '^checkout -q -f --detach FETCH_HEAD$' '!clone' '!origin HEAD' -- sh -c "sed 's/^git -C [^ ]* //' $SC/ref1/git.log"
ctl setup-mxcli-ref-stamped-pass 0 '^GOOS=linux GOARCH=amd64 build VERSION=78bdfa5 BUILD_DIR=' -- cat $SC/ref1/make.log
ctl setup-mxcli-ref-env-catch 0 'mxcli: mxcli version v0\.27\.1 \(MXCLI_REF=v0\.27\.1\)' -- macsetup ref2 FAKE_UNAME=Linux MXCLI_REF=v0.27.1 UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-ref-env-fetched-pass 0 'origin v0\.27\.1$' '!v0\.28\.0' -- sh -c "grep fetch $SC/ref2/git.log"
# an earlier build of another ref in the run folder is rebuilt; a binary somebody put there is kept and warned about
mkdir -p $SC/run-ref3/tools/mxcli-bin $SC/ref3; printf '#!/bin/sh\necho "mxcli version v0.27.0"\n' > $SC/run-ref3/tools/mxcli-bin/mxcli; chmod +x $SC/run-ref3/tools/mxcli-bin/mxcli; ln -s $SC/run-ref3/tools/mxcli-bin/mxcli $SC/run-ref3/tools/mxcli-linux
ctl setup-mxcli-own-old-build-rebuilt-catch 0 'tools/mxcli-linux is not 78bdfa5 \(mxcli version v0\.27\.0\): rebuilding' 'mxcli: mxcli version 78bdfa5 \(MXCLI_REF=78bdfa51a2e0a84b971093ebd7b6b82e7596c950\)' -- macsetup ref3 FAKE_UNAME=Linux UPG_SETUP_STEPS=mxcli
mkdir -p $SC/run-ref4/tools $SC/ref4; printf '#!/bin/sh\necho "mxcli version v0.27.0"\n' > $SC/run-ref4/tools/mxcli-linux; chmod +x $SC/run-ref4/tools/mxcli-linux
ctl setup-mxcli-user-binary-kept-catch 0 "WARNING: tools/mxcli-linux reports 'mxcli version v0\.27\.0', MXCLI_REF is 78bdfa51a2e0a84b971093ebd7b6b82e7596c950" -- macsetup ref4 FAKE_UNAME=Linux UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-user-binary-not-built-pass 1 -- test -e $SC/ref4/make.log
mkdir -p $SC/run-ref5/tools/mxcli-bin $SC/ref5; printf '#!/bin/sh\necho "mxcli version 78bdfa5 (2026-10-14T00:13:40Z)"\n' > $SC/run-ref5/tools/mxcli-bin/mxcli; chmod +x $SC/run-ref5/tools/mxcli-bin/mxcli; ln -s $SC/run-ref5/tools/mxcli-bin/mxcli $SC/run-ref5/tools/mxcli-linux
ctl setup-mxcli-own-current-kept-pass 0 'mxcli: mxcli version 78bdfa5 \(2026-10-14T00:13:40Z\) \(MXCLI_REF=78bdfa51a2e0a84b971093ebd7b6b82e7596c950\)' '!rebuilding' -- macsetup ref5 FAKE_UNAME=Linux UPG_SETUP_STEPS=mxcli
ctl setup-mxcli-own-current-not-built-pass 1 -- test -e $SC/ref5/make.log
# bin/cloud/setup.sh: --check says NOT done for a binary of another ref, done for the pinned one; the run builds at the ref
CS=$T/cloudsetup; mkdir -p $CS/h1/.local/bin $CS/h2/.local/bin $CS/run1/tools/mxcli-bin $CS/run2/tools/mxcli-bin
for k in 1 2; do v=$([ $k = 1 ] && echo 'mxcli version v0.27.0' || echo 'mxcli version 78bdfa5 (2026-10-14T00:13:40Z)'); printf '#!/bin/sh\necho "%s"\n' "$v" > $CS/run$k/tools/mxcli-bin/mxcli; chmod +x $CS/run$k/tools/mxcli-bin/mxcli
  ln -s $CS/run$k/tools/mxcli-bin/mxcli $CS/run$k/tools/mxcli-linux; ln -s $CS/run$k/tools/mxcli-bin/mxcli $CS/h$k/.local/bin/mxcli; done
csetup() { local k=$1; shift; env HOME=$CS/h$k bash $B/cloud/setup.sh --run-dir $CS/run$k --source 10.24.26.1 --target 11.15.0.1 "$@"; }
ctl cloud-setup-mxcli-old-ref-not-done-catch 3 'check mxcli: NOT done' -- csetup 1 --check --only mxcli
ctl cloud-setup-mxcli-pinned-ref-done-pass 0 'check mxcli: done' -- csetup 2 --check --only mxcli
ctl cloud-setup-mxcli-ref-default-pass 0 'MXCLI_REF=\$\{MXCLI_REF:-78bdfa51a2e0a84b971093ebd7b6b82e7596c950\}' -- grep -F 'MXCLI_REF=${MXCLI_REF:-78bdfa51a2e0a84b971093ebd7b6b82e7596c950}' $B/cloud/setup.sh
ctl cloud-setup-mxcli-no-head-clone-pass 1 -- grep -E 'git clone .*--depth 1 .*mendixlabs/mxcli' $B/cloud/setup.sh $B/setup-container.sh
ctl cloud-setup-mxcli-version-stamped-pass 0 'make build VERSION="\$MXCLI_VER"' -- grep -F 'make build VERSION="$MXCLI_VER"' $B/cloud/setup.sh $B/setup-container.sh


# --- heal (steps/heal.md): bin/heal.py on a synthetic work folder (lib/mkheal.py), one failing row per class, offline ------------
HL=$T/heal; rm -rf "$HL"; mkdir -p "$HL"
python3 $here/lib/mkheal.py $HL/h1 && python3 $B/heal.py plan --work $HL/h1 --round 1 > $HL/plan1.out 2>&1
hcls() { python3 -I -c "
import json,sys
for r in json.load(open('$HL/h1/heal.json'))['rows']:
    if r['id']==sys.argv[1]: print(r['id'], '=>', r['class'], '/', r['heal_kind'], '/', r['evidence'])" "$1"; }
ctl heal-classes-line-pass 0 'classes: startup-noise 1, no-test-data 1, no-click-path 1, outside-call 1, test-setup 4, real-regression 3, likely-real 2' 'CHANGED 6' -- cat $HL/plan1.out
ctl heal-startup-noise-evidence-catch 0 'data:Shop\.Item\.changedDate => startup-noise / allow / start noise: .* also differs between two starts of the SAME old app' -- hcls data:Shop.Item.changedDate
ctl heal-allow-line-reason-pass 0 '^Shop\.Item\.changedDate 3 rows differ # start noise: ' '!Shop\.Customer' '!Shop\.Order' -- cat $HL/h1/heal-allow.txt
ctl heal-no-twin-no-noise-catch 0 'data:Shop\.Customer\.name => likely-real' '!startup-noise' -- hcls data:Shop.Customer.name
ctl heal-lost-rows-real-regression-catch 0 'data:Shop\.Order\.total => real-regression / None' 'missing after the upgrade' -- hcls data:Shop.Order.total
ctl heal-harness-log-accepted-catch 0 'test-setup / logallow / known harness line: .*SessionTimeout 30000' -- hcls 'log:log.start.NEW_WARNING:WARNING_Configuration_Using_derived_value_for_Se'
ctl heal-log-allow-line-pass 0 '^WARNING Configuration: Using derived value for SessionKeepAliveUpdatesInterval\* # test harness: ' '!Something else' -- cat $HL/h1/heal-log-allow.txt
ctl heal-new-error-never-accepted-catch 0 'log:log\.start\.NEW_ERROR:.* => real-regression / None' -- hcls 'log:log.start.NEW_ERROR:ERROR_Shop_failed_to_start_the_queue'
ctl heal-unknown-log-line-stays-open-catch 0 'Something_else_changed => likely-real' 'not a known harness line' -- hcls 'log:log.start.NEW_WARNING:WARNING_Something_else_changed'
ctl heal-effective-allow-has-both-pass 0 '^# written by heal.py' 'Shop\.Item\.changedDate' -- cat $HL/h1/allow-effective.txt
ctl heal-no-test-data-seed-catch 0 'journey:j-empty => no-test-data / seed / the page Shop\.Empty shows an empty list' -- hcls journey:j-empty
ctl heal-seed-entity-in-plan-pass 0 '"Shop\.Thing"' '!Shop\.Item"' -- sh -c "sed -n '/\"seed\"/,/\]/p' $HL/h1/heal-plan.json"
ctl heal-outside-call-standin-catch 0 'journey:j-outside => outside-call / standin' -- hcls journey:j-outside
ctl heal-runner-did-not-run-rerun-catch 0 'journey:j-flake => test-setup / rerun' -- hcls journey:j-flake
ctl heal-selection-gated-patch-catch 0 'journey:j-gated => test-setup / patch / buttonEdit on Shop\.Overview is shown only for a SELECTED row' -- hcls journey:j-gated
ctl heal-no-click-path-no-heal-pass 0 'journey:j-nopath => no-click-path / None' -- hcls journey:j-nopath
ctl heal-regression-not-healed-catch 0 'journey:j-regress => real-regression / None / passes on the old app, fails on the new one' -- hcls journey:j-regress
ctl heal-fails-on-old-too-no-heal-pass 0 'journey:j-both => test-setup / None / fails on the old app too' -- hcls journey:j-both
ctl heal-passing-journey-not-a-row-pass 1 '^0$' -- grep -c j-fine $HL/h1/heal.json
ctl heal-md-written-pass 0 '^# Heal report' 'journey:j-gated' '!j-nopath' 'no-click-path.*counted above' -- cat $HL/h1/heal.md
# the patch: a row-select step goes right before the click, the original is kept, a second patch changes nothing
python3 $B/heal.py patch --work $HL/h1 > $HL/patch.out 2>&1
JP=$HL/h1/journeys/journeys/Admin/j-gated.journey.json
ctl heal-patch-reported-pass 0 'heal patch: 1 of 1 journey\(s\) patched' -- cat $HL/patch.out
ctl heal-patch-row-before-click-catch 0 '"do": "row"' '"widget": "itemGrid"' -- sh -c "python3 -I -c \"import json;d=json.load(open('$JP'));a=d['steps'][1]['actions'];print([x['do'] for x in a]);print(json.dumps(a[0]))\""
ctl heal-patch-order-row-then-click-pass 0 "\['row', 'click'\]" -- sh -c "python3 -I -c \"import json;d=json.load(open('$JP'));print([x['do'] for x in d['steps'][1]['actions']])\""
ctl heal-patch-ready-is-the-grid-pass 0 '"ready": ".mx-name-itemGrid"' -- sh -c "python3 -I -c \"import json;d=json.load(open('$JP'));print(json.dumps(d['steps'][0]['ui']))\""
ctl heal-patch-original-kept-pass 0 '"do": "click"' '!"do": "row"' -- cat $HL/h1/heal/journeys-orig/Admin/j-gated.journey.json
cp $JP $HL/patched1.json; python3 $B/heal.py patch --work $HL/h1 > /dev/null 2>&1
ctl heal-patch-twice-same-pass 0 -- cmp $HL/patched1.json $JP
# the merge: rerun rows replace the stored ones, the old summary is kept, the healed ids are listed
mkdir -p $HL/ro/before-picked $HL/rn/after
echo '{"journeys": {"j-flake": {"verdict": "PASS"}, "j-gated": {"verdict": "PASS"}}}' > $HL/ro/before-picked/summary.json
echo '{"journeys": {"j-flake": {"verdict": "PASS", "compare": "x"}, "j-gated": {"verdict": "PASS"}}}' > $HL/rn/after/summary.json
# the rerun's screenshots replace the stale ones of the same journey in the compared run (shots-<role>), other journeys stay
mkdir -p $HL/h1/e2e-after/after/shots-Admin $HL/rn/after/shots-Admin
: > $HL/h1/e2e-after/after/shots-Admin/j-flake-step2-NOT-REACHED.png; : > $HL/h1/e2e-after/after/shots-Admin/j-other-step1.png
echo fresh > $HL/rn/after/shots-Admin/j-flake-step1.png; echo fresh > $HL/rn/after/shots-Admin/j-flake-step2.png
python3 $B/heal.py merge --work $HL/h1 --old $HL/ro --new $HL/rn > $HL/merge.out 2>&1
ctl heal-merge-shots-replaced-pass 0 '^j-flake-step1\.png$' '^j-flake-step2\.png$' '^j-other-step1\.png$' '!NOT-REACHED' -- ls $HL/h1/e2e-after/after/shots-Admin
ctl heal-merge-reported-pass 0 'heal merge: 2 journey\(s\) merged' -- cat $HL/merge.out
ctl heal-merge-replaces-row-catch 0 '"j-flake":\{"verdict":"PASS"\}' '"healed":\[' -- sh -c "tr -d '\n ' < $HL/h1/e2e-after/after/summary.json | sed 's/,\"/,\n\"/g'"
ctl heal-merge-keeps-backup-pass 0 '"verdict": "INVALID"' -- cat $HL/h1/e2e-after/after/summary.pre-heal.json
ctl heal-merge-drops-compare-pass 0 '!"compare"' -- cat $HL/h1/e2e-after/after/summary.json
# round 2 (convergence): the healed rows are not healed again; a rerun that passes is a pass, one that fails is likely-real
python3 $B/heal.py finalize --work $HL/h1 > /dev/null 2>&1
python3 $B/heal.py plan --work $HL/h1 --round 2 > $HL/plan2.out 2>&1
ctl heal-round2-changes-nothing-catch 0 'CHANGED 0' -- cat $HL/plan2.out
ctl heal-finalize-pass-result-pass 0 'passes on the old and the new app' -- sh -c "python3 -I -c \"import json;print([r['result'] for r in json.load(open('$HL/h1/heal.json'))['rows'] if r['id']=='journey:j-flake'])\""
ctl heal-open-rows-nj-text-catch 0 'real-regression: 3 row\(s\)' 'Options: fix the app' 'Recommendation: ' 'likely-real: ' -- python3 $B/heal.py nj --work $HL/h1
ctl heal-summary-line-pass 0 '^heal: [0-9]+ failing row\(s\) classified, [0-9]+ accepted with a written reason' 'stay open \(3 real-regression' -- python3 $B/heal.py summary --work $HL/h1
# a rerun that still fails turns the row into likely-real (the heal did not work), never into a pass
python3 $here/lib/mkheal.py $HL/h3 && python3 $B/heal.py plan --work $HL/h3 --round 1 > /dev/null 2>&1
mkdir -p $HL/ro3/before-picked $HL/rn3/after
echo '{"journeys": {"j-flake": {"verdict": "FAIL"}}}' > $HL/ro3/before-picked/summary.json
echo '{"journeys": {"j-flake": {"verdict": "FAIL", "not_pass": ["x"]}}}' > $HL/rn3/after/summary.json
python3 $B/heal.py merge --work $HL/h3 --old $HL/ro3 --new $HL/rn3 > /dev/null 2>&1; python3 $B/heal.py finalize --work $HL/h3 > /dev/null 2>&1
ctl heal-rerun-still-fails-likely-real-catch 0 "\['still FAIL on the new app, old app FAIL'\]" 'likely-real' -- sh -c "python3 -I -c \"import json;r=[r for r in json.load(open('$HL/h3/heal.json'))['rows'] if r['id']=='journey:j-flake'][0];print([r['result']], r['class'])\""
# a rerun that now FAILs on the new app while the old app passes is a regression
echo '{"journeys": {"j-flake": {"verdict": "PASS"}}}' > $HL/ro3/before-picked/summary.json
python3 $B/heal.py merge --work $HL/h3 --old $HL/ro3 --new $HL/rn3 > /dev/null 2>&1; python3 $B/heal.py finalize --work $HL/h3 > /dev/null 2>&1
ctl heal-rerun-regression-catch 0 'REGRESSION: passes on the old app, fails on the new one' 'real-regression' -- sh -c "python3 -I -c \"import json;r=[r for r in json.load(open('$HL/h3/heal.json'))['rows'] if r['id']=='journey:j-flake'][0];print(r['result'], r['class'])\""
# seedname (a seeded value used as an entity or member name): the classifier, the plan, the owner note, and bin/seedname_fix.py itself
python3 $here/lib/mkheal.py $HL/h4 > /dev/null 2>&1
python3 -I - $HL/h4 <<'PY'
import json, os, sys
W = sys.argv[1]
for rel, k, v in (("e2e-after/after/summary.json", "j-seed", {"verdict": "FAIL", "not_pass": ['FAIL microflow \'Edit\' on Shop.Cfg (create): page does NOT say "An error occurred" rendered']}),
                  ("e2e-before-picked/before-picked/summary.json", "j-seed", {"verdict": "PASS"}),
                  ("e2e-after/after/summary.json", "j-noerr", {"verdict": "FAIL", "not_pass": ["FAIL open Shop.Cfg2: the title changed"]}),
                  ("e2e-before-picked/before-picked/summary.json", "j-noerr", {"verdict": "PASS"})):
    f = os.path.join(W, rel); d = json.load(open(f)); d["journeys"][k] = v; json.dump(d, open(f, "w"))
os.makedirs(os.path.join(W, "logs"), exist_ok=True)
open(os.path.join(W, "logs/runtime-newjp.log"), "w").write("2026-10-29 ERROR - Core: Entity does not exist: s9x2\n")
PY
python3 $B/heal.py plan --work $HL/h4 --round 1 > $HL/plan4.out 2>&1
ctl heal-seedname-classified-catch 0 'journey:j-seed => test-setup / seedname / .*"?does not exist: s9x2' 'Combo box now loads its options when the page opens' -- python3 -I -c "
import json
for r in json.load(open('$HL/h4/heal.json'))['rows']:
    if r['id']=='journey:j-seed': print(r['id'], '=>', r['class'], '/', r['heal_kind'], '/', r['evidence'])"
ctl heal-seedname-needs-the-error-dialog-pass 0 'journey:j-noerr => real-regression / None' -- python3 -I -c "
import json
for r in json.load(open('$HL/h4/heal.json'))['rows']:
    if r['id']=='journey:j-noerr': print(r['id'], '=>', r['class'], '/', r['heal_kind'])"
ctl heal-seedname-in-plan-pass 0 '"seedname": \[' '"s9x2"' '"journey:j-seed"|"j-seed"' -- cat $HL/h4/heal-plan.json
ctl heal-seedname-owner-note-catch 0 'Behaviour change seen through a test-data heal \(1 journey\(s\), seeded value\(s\) s9x2\)' 'wrong now shows an error dialog on page open, not on dropdown open|wrong now shows an error dialog on page open' 'production configuration' -- cat $HL/h4/gate-notes-effective.txt
printf 'a person note\n' > $HL/h4/gate-notes.txt; python3 $B/heal.py plan --work $HL/h4 --round 2 > /dev/null 2>&1
ctl heal-seedname-note-keeps-person-notes-pass 0 '^a person note$' -- cat $HL/h4/gate-notes-effective.txt
# second round after the heal ran: a journey that still fails is a regression, never healed twice
ctl heal-seedname-not-healed-twice-pass 0 'journey:j-seed => real-regression / None / still fails after the seeded names were made valid' -- python3 -I -c "
import json
for r in json.load(open('$HL/h4/heal.json'))['rows']:
    if r['id']=='journey:j-seed': print(r['id'], '=>', r['class'], '/', r['heal_kind'], '/', r['evidence'])"
SN=$T/seedname.db; python3 $here/lib/sqlitepsql.py $SN --init $FX/heal/seedname.sql; SNP="python3 $here/lib/sqlitepsql.py $SN"
ctl seedname-fix-dry-run-catch 0 'UPDATE "cfg\$provisioning" SET "customentity" = .System\.User.' 'SET "customentitymember" = .Name.' '!SET "identifier"' '!SET "label"' -- python3 $B/seedname_fix.py --psql "$SNP" --value s9x2 --dry-run
ctl seedname-fix-name-only-entity-pass 0 'identifier also holds s9x2 but its name does not say entity: not changed' -- python3 $B/seedname_fix.py --psql "$SNP" --value s9x2 --dry-run
ctl seedname-fix-apply-pass 0 'committed 2 update\(s\)' -- python3 $B/seedname_fix.py --psql "$SNP" --value s9x2
ctl seedname-fix-rows-valid-pass 0 '^1\|System\.User\|Name\|s9x2\|s9x2$' '^2\|System\.User\|Name\|s9x3\|s9x3$' '^3\|Real\.Entity\|RealMember\|keep\|keep$' -- python3 -I -c "
import sqlite3
for r in sqlite3.connect('$SN').execute('select * from \"cfg\$provisioning\" order by id'): print('|'.join(map(str, r)))"
ctl seedname-fix-twice-nothing-pass 0 'no seeded rows changed' -- python3 $B/seedname_fix.py --psql "$SNP" --value s9x2
ctl seedname-fix-refuses-real-value-catch 1 'not a seeded value' -- python3 $B/seedname_fix.py --psql "$SNP" --value Real.Entity
ctl seedname-fix-unknown-entity-catch 1 'is not in the mapping tables' -- python3 $B/seedname_fix.py --psql "$SNP" --value s9x2 --entity Nope.Entity
ctl seedname-fix-explicit-set-pass 0 'cfg.provisioning\.label: 2 row\(s\) -> Hello \(explicit --set\)' -- python3 $B/seedname_fix.py --psql "$SNP" --set 'cfg$provisioning.label=Hello' --dry-run
ctl seedname-pipeline-wired-pass 0 'seedname_fix\.py' 'gate-notes-effective' -- grep -ho 'seedname_fix\.py\|gate-notes-effective' $B/cloud/upgrade-pipeline.sh
# test fixtures (steps/heal.md): setup_sql.py (the app's test-setup rows, same file on both sides), natsfixture.py (broker config, certificate key hash), the wiring
SQ=$T/setupsql.db; python3 $here/lib/sqlitepsql.py $SQ --init /dev/null; printf 'create table setup(id integer, ws text);\ninsert into setup values (1, '"'"'real'"'"');\n' > $T/setup-base.sql
python3 $here/lib/sqlitepsql.py $SQ --init $T/setup-base.sql; SQP="python3 $here/lib/sqlitepsql.py $SQ"
printf -- '-- why: the page reads this row\ninsert into setup values (2, '"'"'TESTWS1'"'"');\n' > $T/test-setup.sql
ctl setup-sql-applies-pass 0 'setup_sql: applied test-setup.sql' -- python3 $B/setup_sql.py --psql "$SQP" --file $T/test-setup.sql
ctl setup-sql-row-present-pass 0 '^1\|real$' '^2\|TESTWS1$' -- python3 -I -c "
import sqlite3
for r in sqlite3.connect('$SQ').execute('select * from setup order by id'): print('|'.join(map(str, r)))"
printf 'insert into nosuchtable values (1);\n' > $T/bad-setup.sql
ctl setup-sql-bad-sql-catch 1 'setup_sql: failed' 'no such table' -- python3 $B/setup_sql.py --psql "$SQP" --file $T/bad-setup.sql
ctl setup-sql-no-file-pass 0 'nothing to apply' -- python3 $B/setup_sql.py --psql "$SQP" --file $T/none-such.sql
NF=$T/natsfx/natsfixture; mkdir -p $NF
openssl req -x509 -newkey rsa:2048 -nodes -keyout $NF/k.pem -out $NF/server-cert.pem -days 2 -subj /CN=nats-test >/dev/null 2>&1
printf '{"seed": "S", "public": "UPUBKEYTEST", "issuer_seed": "I"}' > $NF/nkey.json
ctl nats-spki-matches-openssl-pass 0 "^$(openssl x509 -in $NF/server-cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64 | tr -d "\n" | sed "s/[+]/[+]/g")\$" -- python3 $B/natsfixture.py spki --work $T/natsfx
ctl nats-conf-websocket-catch 0 'websocket \{' 'port: 8443' 'no_auth_user: "browser"' 'nkey: UPUBKEYTEST' 'user: "browser"' -- python3 -I -c "
import sys; sys.path.insert(0, '$B'); import natsfixture as n; from pathlib import Path
n.write_conf(Path('$NF')); print(open('$NF/nats-server.conf').read())"
ctl nats-ws-port-published-pass 0 '127\.0\.0\.1:\{a\.ws_port\}:8443' -- grep -o '127[.]0[.]0[.]1:{a[.]ws_port}:8443' $B/natsfixture.py
ctl nats-ws-token-second-broker-catch 0 'token: "standin-tok"' 'websocket \{' 'port: 4223' -- python3 -I -c "
import sys; sys.path.insert(0, '$B'); import natsfixture as n; from pathlib import Path
n.write_conf(Path('$NF'), 'standin-tok'); print(open('$NF/nats-ws.conf').read())"
ctl nats-ws-token-main-broker-no-websocket-pass 0 '^main-broker-websocket: none$' -- python3 -I -c "
import sys; sys.path.insert(0, '$B'); import natsfixture as n; from pathlib import Path
n.write_conf(Path('$NF'), 'standin-tok'); print('main-broker-websocket:', 'present' if 'websocket' in open('$NF/nats-server.conf').read() else 'none')"
ctl pipeline-fixture-users-hook-pass 0 'fixture_users_db "\$db"' -- grep -o 'fixture_users_db "[$]db"' $B/cloud/upgrade-pipeline.sh
ctl fixtures-wired-pass 0 'fixture_db' 'fixtures_start' 'setup_sql\.py' 'UPG_BROWSER_SPKI' -- grep -ho 'fixture_db\|fixtures_start\|setup_sql\.py\|UPG_BROWSER_SPKI' $B/cloud/upgrade-pipeline.sh
ctl fixtures-browser-trust-and-storage-pass 0 'ignore-certificate-errors-spki-list' 'UPG_BROWSER_STORAGE' -- grep -ho 'ignore-certificate-errors-spki-list\|UPG_BROWSER_STORAGE' $here/../vendor/e2e/helpers.js
# the data result column: diff.py again with the effective allow files says what was accepted and why
# the grids subcommand needs its arguments
ctl heal-grids-usage-catch 2 -- python3 $B/heal.py grids
# gate: L55 (smoke rung from stored results) and L56 (notes file) and the heal line
printf '# a comment\nthe layout of the home page changed on purpose: confirm with the key user\n\n' > $GI/notes.txt
mkdir -p $GI/hw; printf '{"rows": [], "rounds": []}\n' > $GI/hw/heal.json
echo '{}' > $GI/smoke-after.json; cp $GI/smoke-after.json $GI/w/smoke-after.json
ctl gate-heal-notes-listed-catch 0 'notes: needs a decision: the layout of the home page changed on purpose' '[1-9][0-9]* need a decision' '!a comment' -- gcase hnotes PORT=8080 GATE_NOTES=$GI/notes.txt
ctl gate-heal-notes-absent-pass 0 '!notes: needs a decision' -- gcase hnone --dry-run
ctl gate-heal-line-printed-pass 0 '^heal: 0 failing row\(s\) classified' -- gcase hline PORT=8080 HEAL_JSON=$GI/hw/heal.json
ctl gate-heal-smoke-rejudge-catch 0 '^\[smoke\] .*smokewalk\.js .*--rejudge .*smoke-after\.json .*--compare ' '!smokewalk\.js .*--user ' -- gcase hrej --dry-run SMOKE_REJUDGE=1
# a re-judge writes nothing: the stored after-walk screenshots stay and no plan is generated (the first live use deleted them)
mkdir -p $GI/w/gatehkeep/smoke-after-shots $GI/appdir; echo keep > $GI/w/gatehkeep/smoke-after-shots/keep.txt; echo '{}' > $GI/w/gatehkeep/smoke-after.json
(gcase hkeep PORT=8080 SMOKE_REJUDGE=1 SMOKE_PLAN= SMOKE_APP_DIR=$GI/appdir > $GI/hkeep.out 2>&1)
ctl gate-heal-smoke-rejudge-keeps-shots-catch 0 '^keep$' -- cat $GI/w/gatehkeep/smoke-after-shots/keep.txt
ctl gate-heal-smoke-rejudge-no-plan-generation-catch 0 '!smokewalk_gen' '!plan generation failed' -- cat $GI/hkeep.out $GI/stub-hkeep.log
ctl gate-heal-smoke-live-still-user-pass 0 '^\[smoke\] .*smokewalk\.js .*--user' '!--rejudge' -- gcase hlive --dry-run

# --- proposal: the Testing plan section (204 / 170 / 34 shape) ---------------------------------------------------------------
TP=$T/tplan; mkdir -p $TP/w
python3 - $TP/w <<'TEOF'
import json, sys
eps = [{"id": f"e{i}", "doc": f"Shop.Call{i}", "status": "MOCKED", "system": "Erp"} for i in range(5)] + \
      [{"id": f"u{i}", "doc": f"Shop.Unknown{i}", "status": "UNKNOWN", "system": ""} for i in range(2)]
json.dump({"endpoints": eps}, open(sys.argv[1] + "/apimock-inventory.json", "w"))
json.dump({"summary": {"actions": 12}, "actions": []}, open(sys.argv[1] + "/actions.json", "w"))
TEOF
python3 $B/proposal.py --work $TP/w --source 10.24.13 --target 11.12.6 --original $TP/none.mpr > /dev/null 2>&1
ctl proposal-testing-plan-numbers-catch 0 '^## Testing plan' '7 endpoints and constants found, 5 can be answered by the stand-in \(apimock\.py\), 2 are UNKNOWN' '2 of 7 external endpoints are UNKNOWN' '12 actions in the inventory' -- cat $TP/w/PROPOSAL.md
ctl proposal-testing-plan-gaps-closed-pass 0 'classify every UNKNOWN endpoint' 'owner: a named person' 'apis rung against a real test system before go-live' -- cat $TP/w/PROPOSAL.md
ctl proposal-testing-plan-before-signoff-pass 0 '## 5\. Human effort\|## Testing plan\|## 6\. Sign-off\|$' -- sh -c "grep -E '^## ' $TP/w/PROPOSAL.md | tail -3 | tr '\\n' '|'; echo"
mkdir -p $TP/w0; python3 $B/proposal.py --work $TP/w0 --source 10.24.13 --target 11.12.6 --original $TP/none.mpr > /dev/null 2>&1
ctl proposal-testing-plan-no-inventory-says-so-pass 0 'external calls: not measured \(no apimock-inventory\.json\)' 'action count not measured' -- cat $TP/w0/PROPOSAL.md


# build loop (steps/heal.md): the fixed repair rows run again while they lower the error count, at most UPG_BUILD_ROUNDS (default 2) more rounds
ctl pipeline-build-loop-bounded-pass 0 'UPG_BUILD_ROUNDS:-2' 'no progress: stop' -- sh -c "sed -n '/^step_build() {/,/^}/p' $B/cloud/upgrade-pipeline.sh | grep -oE 'UPG_BUILD_ROUNDS:-2|no progress: stop' | sort -u"
ctl pipeline-build-loop-skipped-in-dry-run-pass 0 'DRY" != 1 .*UPG_BUILD_ROUNDS' -- sh -c "sed -n '/^step_build() {/,/^}/p' $B/cloud/upgrade-pipeline.sh | grep -E 'DRY.* != 1 .*UPG_BUILD_ROUNDS'"
ctl pipeline-heal-step-order-pass 0 'journeys heal apidirect diff gate' -- sh -c "grep -E '^STEPS=' $B/cloud/upgrade-pipeline.sh | sed 's/.*afterwalk //; s/)//'"

# --- cockpit page (bin/cockpitpage.py) and the decision ledger (bin/decisions.py) on fixtures/cockpit (a made-up shop app) -------------
CK="bash $here/cockpit_control.sh"
ctl cockpit-render-five-phases-catch 0 '"id": "find"' '"id": "plan"' '"id": "upgrade"' '"id": "test"' '"id": "golive"' -- $CK render
ctl cockpit-render-versions-from-run-pass 0 '10\.24\.1\.1 \\u2192 11\.1\.0|10\.24\.1\.1 .{1,3} 11\.1\.0' '!HTMLSnippet' -- $CK render
ctl cockpit-render-needs-you-from-run-catch 0 '"id": "regression:overlay"' '"id": "regression:Gridmod"' '"id": "confirm:D2"' '"id": "signoff"' '"id": "P-1"' -- $CK render
ctl cockpit-render-effort-from-proposal-catch 0 '"Gridmod", "kept at its version|"Gridmod", "local edits refuse the update[^"]*", "M"' '"Themepack styles", "[^"]*", "S"' -- $CK render
ctl cockpit-render-upgrade-from-git-log-catch 0 '"Widgetpack 2\.0\.0", "Automatic module update' '"Repair D2"' '"Rebuilds"' -- $CK render
ctl cockpit-render-gate-and-heal-catch 0 'Click through pages|"Smoke"' '[0-9] real problem' '"1 check not run"' '1 of 2 page checks fails\. Cause: Gridmod\.' 'Replace Gridmod' 'Overlay blocks 2 clicks' -- $CK render
ctl cockpit-render-time-from-timing-pass 0 'Shop|App upgrade' '1 h 40|1 h 30' -- $CK render
ctl cockpit-page-content-only-pass 0 'no page skeleton tags' '^<title>' -- $CK nodoc
ctl cockpit-no-hardcoded-run-pass 0 'no hard-coded run names' -- $CK nohard
ctl cockpit-db-pattern-pass 0 'has claude\.use\("db"\)' 'has claude\.use\("user"\)' 'decisions"\)\.doc\(it\.id\)\.set' 'signoffs"\)\.doc\(await user\.id\(\)\)\.set' 'decisions"\)\.onSnapshot' 'never reads window\.claude\.db' -- $CK pattern
ctl cockpit-flag-regenerates-only-pass 0 'COCKPIT\.html written' -- $CK cockpit-flag
ctl decisions-add-last-wins-pass 0 'P-1 = o2 by Ana via chat' 'P-1 = rec by Ben via chat' '"by": "Ana"' '"by": "Ben"' -- $CK add
ctl decisions-add-unknown-item-catch 2 'unknown item' -- $CK add-bad
ctl decisions-signoff-chat-refused-catch 0 'sign the plan with the page button' 'rc=2' 'ledger untouched' -- $CK signoff-chat
ctl decisions-signoff-chat-never-signs-pass 0 '^0$' -- $CK signoff-chat-apply
ctl decisions-import-idempotent-pass 0 'imported 1 row' 'imported 0 row' '"by": "Cleo"' '"source": "page"' -- $CK import
ctl decisions-apply-writes-by-who-via-what-catch 0 'by Ana via chat: intended' 'P-1 \| Gridmod \| module \| replace with the Marketplace equivalent.*DECIDED' -- $CK apply
ctl decisions-apply-idempotent-pass 0 'same after second apply' '^1$' -- $CK apply-idem
ctl decisions-apply-changed-answer-removes-line-pass 0 '^0$' -- $CK apply-change
ctl decisions-signoff-page-writes-signed-off-catch 0 'Signed-off line written for Cleo Vos' '^Signed-off: Cleo Vos 2026-01-03$' '^1$' '^signed$' -- $CK signoff-page
ctl decisions-signoff-stale-plan-ignored-pass 0 'sign-off ignored' '^0$' -- $CK signoff-stale
ctl decisions-signoff-viewer-id-not-a-name-pass 0 'is a viewer id, not a name' '^0$' -- $CK signoff-noname
ctl decisions-signoff-import-chat-row-refused-pass 0 'not source page' '^0$' -- $CK signoff-import-chat
# a ledger row whose item is a step id (or the P-n alias of a step) writes that step's approval; a rerun of import adds nothing
ctl decisions-step-row-writes-approval-catch 0 'S-3 = approve by Ana via chat' '^S-3: approved by Ana via chat$' '^approval events: 1$' -- $CK step-add
ctl decisions-step-last-row-wins-pass 0 '^S-3: rejected by Ana via chat$' '^S-3 later: approved by Ben via chat$' '^approval events: 2$' -- $CK step-reject
ctl decisions-step-alias-import-catch 0 'imported 2 row' '^S-1: approved by Cleo via page$' '^S-3: rejected by Cleo via page$' '^S-2: none by - via -$' -- $CK step-alias-import
ctl decisions-step-import-rerun-adds-nothing-catch 0 'imported 0 row' '^steps file unchanged by the second import$' '^ledger rows: 2$' -- $CK step-alias-import
ctl decisions-step-assumption-yields-pass 0 '^S-3: approved by Ana via page$' -- $CK step-assumed-yields
ctl decisions-step-unknown-id-catch 0 "unknown item 'S-9'" '^rc=2$' '^ledger untouched$' -- $CK step-unknown
ctl decisions-step-bad-choice-catch 0 'approve or reject' '^rc=2$' '^S-3: none by - via -$' -- $CK step-bad-choice
ctl decisions-step-signoff-still-refused-pass 0 'sign the plan with the page button' '^rc=2$' '^steps untouched$' '^ledger untouched$' -- $CK step-signoff-refused
ctl decisions-step-apply-notes-step-pass 0 'S-3: a step, its approval is in steps.jsonl' '^S-3: approved by Ana via chat$' '^approvals after apply: 1$' -- $CK step-apply
ctl decisions-pending-lists-ids-options-catch 0 'open items \(6\)' '^regression:overlay ' 'fix \(recommended\)' 'chat: decisions\.py add .*--source chat' 'sign the plan with the page button' -- $CK pending
ctl decisions-pending-drops-decided-pass 0 'open items \(5\)' '!^P-2 ' -- $CK pending-after
ctl cockpit-words-no-plural-marker-pass 0 'plural-marker count: 0' 'raw gate text count: 0' 'Testing found 2 real problems, 4 things need you' -- $CK words
ctl decisions-signed-plan-leaves-needs-you-pass 0 '^0$' -- $CK signed-page
ctl cockpit-matrix-missing-file-grey-pass 0 'cells: 32 ok cells: 0 chips ok: 0' -- $CK matrix-missing-empty
ctl cockpit-matrix-missing-gate-grey-pass 0 'runtime test cell: none Not yet' -- $CK matrix-missing-gate
ctl cockpit-matrix-kinds-four-tiles-catch 0 'every row and chip has a kind: True' "'regression:overlay': 'owner'" "'signoff': 'owner'" "'payment-gateway': 'testgap'" 'no old prob tile: True' 'tile buttons: 4' -- $CK matrix-kinds
ctl cockpit-matrix-tiles-match-rows-pass 0 'tiles match rows' '!TILES DIFFER' -- $CK matrix-tiles
ctl cockpit-matrix-no-proposal-visible-catch 0 'non-green rows without proposal: [1-9]' 'literal in page: True' -- $CK matrix-noprop
ctl cockpit-matrix-no-proposal-with-items-catch 0 'non-green rows without proposal: [1-9]' 'literal in page: True' -- $CK matrix-noprop-merged
ctl cockpit-matrix-items-file-merge-pass 0 'proposal: Find the layer' 'loop: 1' 'new row group: setup late: True deploy: True' 'chip: bad Message broker missing' 'chip row link: payment-gateway' 'feed: Test broker started' -- $CK matrix-merge
ctl cockpit-matrix-stale-judgment-closed-by-gate-pass 0 'regressions tile: 0' 'overlay test cell: ok Fixed' 'purple regression cells: 0' 'triage outline on late find: True Not flagged' -- $CK matrix-stale
ctl cockpit-matrix-triage-seen-keeps-status-pass 0 'triage: Seen in triage False' -- $CK matrix-seen
ctl cockpit-matrix-seen-and-decided-plan-status-pass 0 'triage: Seen in triage False' 'plan: Decided during the run False' -- $CK matrix-seen-decided
ctl cockpit-matrix-seen-never-called-missed-pass 0 'plan: Not in the plan yet False' '!True' -- $CK matrix-seen
ctl cockpit-matrix-open-regression-red-with-proposal-pass 0 'regressions tile: 1' 'red regression rows: 1 \[.bad.\] \[True\]' 'stale heal rows still red: 0' -- $CK matrix-openreg
ctl cockpit-matrix-triage-not-seen-flagged-pass 0 'triage: Not flagged True' -- $CK matrix-seen-not
ctl cockpit-matrix-open-question-no-own-row-pass 0 'judgment rows: 0' 'purple judgment cells: 1' 'closed in feed: False' -- $CK matrix-judg-open
ctl cockpit-matrix-closed-question-only-in-feed-pass 0 'judgment rows: 0' 'purple judgment cells: 0' 'closed in feed: True' -- $CK matrix-judg-closed
ctl cockpit-matrix-one-row-per-item-pass 0 'rows named Overlay: 1' -- $CK matrix-onerow
ctl cockpit-matrix-twelve-chips-pass 0 'chips: 12' 'grey chips: [1-9]' 'clickable when not ok: True' -- $CK matrix-chips
ctl cockpit-matrix-you-cells-are-open-decisions-pass 0 'you cells: 4 open decision items: 4' -- $CK matrix-you
ctl cockpit-matrix-no-app-name-pass 0 'no app names in page or generator' 'external requests only fonts: 0' -- $CK matrix-nohard
ctl cockpit-matrix-no-dashes-pass 0 'dash count: 0' 'generator dash count: 0' -- $CK matrix-dashes
# the drawer trail (work/cockpit-trail.json): actions land under their row, an unknown row id is dropped, a malformed file
# gives no trail; the plan view reads PROPOSAL.md into sections with its P-n items, and no PROPOSAL.md gives none
ctl cockpit-matrix-trail-pass 0 "^rows with a trail: \{'modules': 2\}$" '^commits: 1 \| tests: 1$' -- $CK matrix-trail
ctl cockpit-matrix-trail-malformed-catch 0 '^rows with a trail: 0$' -- $CK matrix-trail-bad
ctl cockpit-matrix-plan-pass 0 "^plan items: \[\('P-1', 'module', 'Gridmod'\), \('P-2', 'theme', 'Themepack styles'\)\]$" "Sign-off'\]$" -- $CK matrix-plan
ctl cockpit-matrix-plan-none-pass 0 '^plan sections: 0$' -- $CK matrix-plan-none
ctl cockpit-band-renders-without-js-pass 0 'band without JS: True' 'headline without JS: True' 'matrix cells without JS: 52 of 52' 'feed and readiness without JS: True True' 'viewport meta: True' 'closed total = sum of chips: True \| exactly two numbers: True' -- $CK matrix-band-static
ctl cockpit-band-positive-framing-pass 0 'no dashed late marker: True' 'legend only for states on the page: True' 'no unstable or failures wording: True' -- $CK matrix-framing
ctl cockpit-band-kpi-overrides-pass 0 'closed chip added: True \| renamed count: 2' 'open added: True \| hidden gone: True' 'shown without JS: True' -- $CK matrix-kpi
ctl cockpit-band-counts-from-gate-rungs-pass 0 "'journeys pass': 12" "'journeys behave as on the old app': 4" "'constants checked': 9" "'release notes handled': 20" 'no rest chip when the rung is missing: True' -- $CK matrix-rungs
ctl cockpit-band-no-app-names-pass 0 'no app or module names in the band code' -- $CK matrix-band-nostrings
# slice 7: work/steps.jsonl (the made-up shop fixture) gives one row per step; missing or damaged, the older inputs are used as before
ctl cockpit-steps-rows-pass 0 '^page rc=0$' "^groups: \['app', 'steps', 'setup', 'golive'\]$" "^step rows: \[\('S-1', 'Widgetpack module update', 'steps'\), \('S-2', 'jQuery scripts on the React client', 'steps'\), \('S-3', 'Themepack styles', 'steps'\)\]$" \
  "^S-1 \{'triage': 'Found', 'plan': 'Approved', 'upgrade': '1 change', 'test': 'Passed'\}$" "^S-2 \{'triage': 'Found', 'plan': 'Needs your OK', 'upgrade': '2 changes', 'test': 'Passed'\}$" \
  "^S-3 \{'triage': 'Found', 'plan': 'Approved', 'upgrade': '1 change', 'test': 'Test gap'\}$" '^steps file flag: True \| trail file ignored: True$' '^signoff meta: \[.1 choice was assumed by the agent.\]$' -- $CK matrix-steps-rows
ctl cockpit-steps-drawer-shows-the-record-pass 0 '^S-2 found: The new React client cannot run the snippet widget' '^S-2 proposed: Keep every script' '^S-2 why: Same behaviour as today' '^S-2 who: Assumed by the agent\. It needs your OK\.$' '^S-2 other options: 2$' \
  "^S-2 commits: \['2222222', '3333333'\]$" "^S-2 tests: \[\('Click through pages', 'pass'\), \('User journeys', 'pass'\), \('Screens', 'pass'\)\]$" '^S-2 proof behind toggle: 3$' '^S-1 who: Approved by Ana on 2026-01-02\.$' '^S-1 commits: 1 \| tests: 2$' 'JS skips the old plan box for step rows: True' -- $CK matrix-steps-drawer
ctl cockpit-steps-no-test-shows-a-gap-not-a-pass-catch 0 "^S-3 test: \[\['Linked checks', 'gap', 'No check is linked to this step, so nothing tested it\.'\]\] wait$" -- $CK matrix-steps-drawer
ctl cockpit-steps-assumed-step-in-open-topics-catch 0 "\('Your call', 'jQuery scripts on the React client', 'you'\)" "\('Coverage', 'Themepack styles: Test gap', 'agent'\)" '^routine step in open band: False$' '^you tile: [0-9]+ \| S-2 kind: owner \| S-3 kind: testgap$' -- $CK matrix-steps-band
ctl cockpit-steps-missing-file-falls-back-pass 0 '^page rc=0$' '^step rows: 0$' "^groups: \['app', 'setup', 'golive'\]$" '^steps file flag: False$' "^old trail used: \['modules'\]$" "^damage notice: \[\]$" '^signoff meta: \[.4 choices were assumed by the agent.\]$' -- $CK matrix-steps-none
ctl cockpit-steps-malformed-file-caught-catch 0 '^page rc=0$' '^step rows: 0$' '^steps file flag: False$' "^old trail used: \['modules'\]$" 'The step records are damaged \(line 3 is not an event\), so this page shows the older inputs\.' '^signoff meta: \[.4 choices were assumed by the agent.\]$' -- $CK matrix-steps-bad
ctl cockpit-steps-incomplete-record-caught-catch 0 '^page rc=0$' '^step rows: 0$' 'The step records are damaged \(step S-1 is incomplete\)' -- $CK matrix-steps-incomplete
# slice 8: Approve and Reject in the drawer of an assumed step; the page answer goes through decisions.py import
ctl cockpit-steps-ask-buttons-only-on-assumed-step-catch 0 "^S-1 buttons: False \| answer: \{'state': 'approved', 'by': 'Ana', 'day': '2026-01-02', 'reason': ''\} \| plan cell: Approved$" "^S-2 buttons: True \| answer: None \| plan cell: Needs your OK$" \
  "^S-3 buttons: False \| answer: \{'state': 'approved', 'by': 'Ana'" 'page has data-sid=' 'page has data-choice="approve"' 'page has data-choice="reject"' 'page has class="reason"' '^buttons only when it.ask: 1$' '^step answer goes to the decisions collection: 1$' -- $CK matrix-steps-ask
ctl cockpit-steps-ask-page-answer-becomes-approval-pass 0 'imported 1 row' '^S-2: approved by Cleo via page$' "^S-2 buttons: False \| answer: \{'state': 'approved', 'by': 'Cleo', 'day': '2026-01-04', 'reason': 'Bridge is fine for now'\} \| plan cell: Approved$" \
  '^open topics naming jQuery: \[\]$' '^reason kept: Bridge is fine for now$' '^rerun adds nothing$' -- $CK matrix-steps-ask-approve
ctl cockpit-steps-ask-reject-is-recorded-catch 0 'imported 1 row' '^S-2: rejected by Cleo via page$' "^S-2 buttons: False \| answer: \{'state': 'rejected', 'by': 'Cleo', 'day': '2026-01-04', 'reason': ''\} \| plan cell: Rejected$" \
  "^open topics naming jQuery: \[\('To fix', 'agent'\)\]$" -- $CK matrix-steps-ask-reject
ctl cockpit-steps-ask-garbage-row-refused-catch 0 'imported 0 row\(s\), skipped 3' "skipped row for 'S-99'" '^S-2: assumed by agent via mid-run$' '^steps file untouched$' -- $CK matrix-steps-ask-garbage

# --- step records (bin/steps.py) on a made-up shop app: the event fold, the refusals, check, the derived status (STEP-RECORDS-PLAN.md sections 2, 4, 6)
SC="bash $here/steps_control.sh"
ctl steps-fold-last-approve-wins-catch 0 '^approval: approved by Ana$' '^approve lines in file: 2$' '^first approve: "state": "assumed"$' -- $SC fold-last-wins
ctl steps-fold-single-approve-pass 0 '^approval: assumed$' '^lines: 11$' -- $SC fold-only-assumed
ctl steps-open-next-id-pass 0 '^S-1$' '^S-2$' -- $SC open-ids
ctl steps-open-evidence-and-options-kept-pass 0 "^evidence: \['work/triage.md'\]$" '^options: 2 recommend: 0$' -- $SC open-evidence-kept
ctl steps-refuse-unknown-id-propose-catch 0 'unknown step .S-9.' '^rc=2$' '^file untouched$' -- $SC unknown-id
ctl steps-refuse-unknown-id-approve-catch 0 'unknown step .S-7.' -- $SC unknown-id-approve
ctl steps-refuse-say-with-path-catch 0 'plain words' '^rc=2$' '^lines: 10$' -- $SC say-path
ctl steps-refuse-say-with-filename-catch 0 'plain words' '^rc=2$' -- $SC say-filename
ctl steps-refuse-say-with-code-catch 0 'plain words' '^rc=2$' -- $SC say-code
ctl steps-refuse-bad-state-catch 0 "bad state .maybe." '^rc=2$' -- $SC bad-state
ctl steps-refuse-bad-verdict-catch 0 "bad verdict .GREAT." '^rc=2$' -- $SC bad-verdict
ctl steps-say-plain-words-pass 0 '^rc=0$' '!plain words' -- $SC say-plain
ctl steps-say-slash-words-pass 0 '^rc=0$' -- $SC slash-words
ctl steps-propose-valid-pass 0 '^rc=0$' '^say: Keep the old grid for now\.$' -- $SC good-propose
ctl steps-check-complete-pass 0 '^steps: complete$' '^rc=0$' -- $SC check-complete
ctl steps-check-incomplete-catch 0 '^MISSING S-1: approved but no done commit and no gap$' '^MISSING S-1: no tested result for smoke$' '^MISSING S-1: no tested result for journeys$' '^rc=1$' -- $SC check-incomplete
ctl steps-check-no-approval-catch 0 '^MISSING S-1: no approval$' '^rc=1$' -- $SC check-no-approval
ctl steps-check-gap-counts-as-written-pass 0 '^steps: complete$' '^rc=0$' -- $SC check-gap-covers
ctl steps-check-assumed-is-a-note-not-a-failure-pass 0 '^note: S-1: assumed by agent' '^rc=0$' '!MISSING' -- $SC check-assumed
ctl steps-status-done-pass 0 '^full: done$' -- $SC status
ctl steps-status-open-when-assumed-pass 0 '^assumed: open$' -- $SC status-open-assumed
ctl steps-status-open-when-test-missing-catch 0 '^missing test: open$' -- $SC status-open-missing-test
ctl steps-status-blocked-on-fail-catch 0 '^fail: blocked$' -- $SC status-blocked-fail
ctl steps-status-blocked-on-reject-catch 0 '^rejected: blocked$' -- $SC status-blocked-rejected
ctl steps-status-never-written-pass 0 '^status in file: 0$' -- $SC status-never-written
# slice 4: a mid-run decision opens a step (assumed by the agent, needs a person); a D row with no step fails the check in plain words
ctl steps-new-step-assumed-by-agent-catch 0 '^S-1$' '^rc=0$' '^approval: assumed by agent source mid-run$' "^needs: the owner's OK$" '^decisions: \[.D71.\]$' '^status: open$' -- $SC new-step
ctl steps-new-step-needs-found-catch 0 'steps: --new needs --found' '^rc=2$' '^file untouched$' -- $SC new-step-no-found
ctl steps-new-step-plain-words-catch 0 'plain words' '^rc=2$' '^file untouched$' -- $SC new-step-path
ctl steps-new-step-refuses-id-catch 0 'takes no --id' '^rc=2$' -- $SC new-step-with-id
ctl steps-drow-without-step-catch 0 '^MISSING D71: the agent decided "Move order scripts into actions" but no step holds it' 'Open one with steps.py propose --new' '^rc=1$' -- $SC drow-no-step
ctl steps-drow-with-step-pass 0 '^steps: complete$' '^rc=0$' '!MISSING' "^note: S-1: assumed by agent, an open topic" -- $SC drow-with-step
ctl steps-drow-unknown-step-catch 0 '^MISSING D71: the row names S-5, but there is no such step' '^rc=1$' -- $SC drow-unknown-step
ctl steps-drow-file-in-parent-folder-catch 0 '^MISSING D80: the agent decided "Drop the old theme"' '^rc=1$' -- $SC drow-in-parent
ctl steps-phase-split-keeps-each-version-catch 0 '^found in 11\.12\.7: rc=1$' "^S-1 10\.24\.0 \['PASS', 'NOT RUN'\]$" "^S-2 11\.12\.7 \['PASS', 'PASS'\]$" '^S-1$' -- $SC phase-split
ctl steps-standins-one-step-per-version-pass 0 "^S-1 10\.24\.0 approved \| The app makes 2 outside calls on Mendix 10\.24\.0\. 2 can be answered by a stand-in\.$" '^S-2 11\.12\.7 assumed \| .*1 gets its address from data.*Compared with the previous version: 1 new, 1 gone, 0 changed\.$' '!^S-3' -- $SC standins
ctl cockpit-ladder-and-test-health-pass 0 "^ladder \[\('9\.24\.2\.1', 'done'\), \('10\.24\.13\.1', 'done'\), \('11\.12\.7', 'now'\)\]$" "^health \[\('10\.24\.13', \[41, 12\], \[135, 2, 38\], \[258, 224\], 1\)\]$" '^no ladder: \[\] True$' -- $SC cockpit-ladder
ctl steps-find-topic-pass 0 '^found: S-1$' '^rc=1$' -- $SC find-topic
# slice 6: the gate links its rungs to the steps; a missing test is a gap in plain words, never a pass
ctl steps-gate-links-pass-and-accepted-pass 0 '^rc=0$' "^results: \[\('smoke', 'PASS'\), \('journeys', 'PASS\*'\)\]$" '^say: The page walk-through passed on the new app\.$' "^proof: \['g/gate-summary.md', 'row: journeys: 12 PASS'\]$" '^gaps: \[\]$' '^status: done$' -- $SC gate-pass
ctl steps-gate-links-fail-catch 0 "^results: \[\('smoke', 'PASS'\), \('journeys', 'FAIL'\)\]$" 'found a problem on the new app\. 2 click paths work on the old app and fail on the new one\.$' '^status: blocked$' -- $SC gate-fail
ctl steps-gate-fail-elsewhere-is-not-proven-catch 0 "^results: \[\('smoke', 'PASS'\), \('journeys', 'NOT RUN'\)\]$" '^gap: The click paths found a problem elsewhere in the app, not in this step, so this step is not proven yet\.$' '^status: open$' -- $SC gate-fail-elsewhere
ctl steps-gate-build-fail-fails-every-step-catch 0 "^build: \['FAIL'\]$" -- $SC gate-fail-build
ctl steps-gate-not-run-is-a-gap-catch 0 "^results: \[\('smoke', 'PASS'\), \('journeys', 'NOT RUN'\)\]$" '^gap: The click paths did not run, so nothing has shown that this works\.$' '^status: open$' -- $SC gate-gap
ctl steps-gate-invalid-is-a-gap-catch 0 '^smoke: NOT RUN / The page walk-through could not judge, so nothing has shown that this works\.$' -- $SC gate-invalid-is-gap
ctl steps-gate-missing-row-is-a-gap-catch 0 '^journeys: NOT RUN / No result for the click paths was found, so nothing tested this\.$' -- $SC gate-missing-row
ctl steps-gate-step-without-closes-by-is-a-gap-catch 0 '^results: 0$' '^gap: No check is linked to this step, so nothing tested it\.$' '^status: open$' -- $SC gate-no-link
ctl steps-gate-later-gap-replaces-earlier-pass-catch 0 '^first: done$' "^later: open journeys \['NOT RUN'\]$" -- $SC gate-replaces-pass
ctl steps-gate-rerun-adds-nothing-pass 0 '^added on rerun: 0$' -- $SC gate-rerun
ctl steps-gate-without-summary-refused-catch 0 'no gate-summary.md' '^rc=2$' -- $SC gate-no-summary
# gate.sh runs it after the rungs and its own verdict stays what it was
gsteps() {   # gsteps LABEL RUNG [GATE_*=v ...]: a work folder with one step that closes by RUNG, the gate over the stubs, then the folded step
  local label=$1 rung=$2; shift 2; local W=$GI/ws-$label; rm -rf "$W"; mkdir -p "$W"
  python3 $B/steps.py open --work "$W" --topic modules:Gridmod --title "Order grid update" --say "The order grid cannot show rows on the new client." >/dev/null
  python3 $B/steps.py propose --work "$W" --id S-1 --say "Update the grid module." --closes-by "$rung" >/dev/null
  gcase "$label" "$@" WORK=$W WIDGETS_APP=$GI > "$GI/gs-$label.out" 2>&1; local rc=$?
  grep -E '^gate: (PASS|FAIL|INVALID)|steps: tested --gate' "$GI/gs-$label.out" | sed 's/ from .*//; s/ (exit.*//'; echo "gate rc=$rc"
  python3 $B/steps.py show --work "$W" S-1 --json | python3 -c 'import json,sys; d=json.load(sys.stdin)[0]; print("step:", [(r["rung"], r["verdict"]) for r in d["tested"]["results"]], d["status"])'
}
ctl gate-steps-linked-after-rungs-pass 0 'steps: tested --gate: 1 event' '^gate: PASS$' '^gate rc=0$' "^step: \[\('build', 'PASS'\)\] open$" -- gsteps gst1 build
ctl gate-steps-failing-rung-keeps-verdict-catch 0 '^gate: FAIL$' '^gate rc=1$' "^step: \[\('journeys', 'FAIL'\)\] blocked$" -- gsteps gst2 journeys GATE_STUB_RC_run_journeys=1 GATE_STUB_OUT_run_journeys='journeys: 9 PASS, 2 FAIL in Gridmod'
gnosteps() { gcase "$1" WORK=$GI/ws-$1 WIDGETS_APP=$GI 2>&1 | grep -E '^gate: PASS|steps: tested' | sed 's/ (exit.*//; s/;.*//'; test -f "$GI/ws-$1/steps.jsonl" && echo "steps file made" || echo "no steps file"; }
ctl gate-steps-absent-file-nothing-written-pass 0 '^gate: PASS$' '^no steps file$' '!steps: tested' -- gnosteps gst3

# slice 9: a plan that converts opens a convert step; housekeeping config commits read "housekeeping", not "no step"
ctl proposal-steps-convert-step-opened-catch 0 '^S-[0-9]+ convert alias=- approval=none .* found=True proposed=True$' -- bash ${PR:-}/ssum.sh ${PR:-}/kept
HK=$T/hk; rm -rf $HK; mkdir -p $HK/w; HK=$(cd $HK && pwd -P)
git -C $HK init -q; echo shop > $HK/shop.txt; git -C $HK add -A .
git -C $HK commit -qm "original" -m "$(printf 'Changed-By: toolkit\nUpgrade-Change: config run-start')"
git -C $HK commit -q --allow-empty -m "stub the build inputs" -m "$(printf 'Changed-By: toolkit\nUpgrade-Change: config build-stubs')"
git -C $HK commit -q --allow-empty -m "tidy the shop theme" -m "$(printf 'Changed-By: person\nUpgrade-Change: config theme-tidy')"
python3 $B/steps.py open --work $HK/w --topic modules --title "Routine module updates" --say "The plan holds 2 module updates." > /dev/null
python3 $B/changelog.py --app $HK --work $HK/w > /dev/null
ctl changelog-housekeeping-listed-pass 0 '\| stub the build inputs .* \| housekeeping \|$' -- cat $HK/w/CHANGES.md
ctl changelog-housekeeping-person-still-no-step-catch 0 '\| tidy the shop theme .* \| no step \|$' '1 commit\(s\) name no step' -- cat $HK/w/CHANGES.md

# slice 9: the optional rung trail (step records complete), import-legacy, convert and housekeeping steps
gtrail() {   # gtrail LABEL MODE [GATE_*=v ...]: a work folder (MODE ok | notest | nodrow | nofile), the gate over the stubs, the trail row and the verdict
  local label=$1 mode=$2; shift 2; local W=$GI/wt-$label; rm -rf "$W"; mkdir -p "$W"
  if [ $mode != nofile ]; then
    python3 $B/steps.py open --work "$W" --topic modules:Gridmod --title "Order grid update" --say "The order grid cannot show rows on the new client." >/dev/null
    python3 $B/steps.py propose --work "$W" --id S-1 --say "Update the grid module." --closes-by $([ $mode = notest ] && echo rest || echo build) >/dev/null
    python3 $B/steps.py approve --work "$W" --id S-1 --state approved --by Ana --source page >/dev/null
    python3 $B/steps.py done --work "$W" --id S-1 --commit abc1234 --say "Grid module moved to version 2." >/dev/null
  fi
  [ $mode = nodrow ] && printf '# Agent decisions\n\n| id | decision |\n|---|---|\n| D1 | Moved the cart scripts |\n' > "$W/AGENT-DECISIONS.md"
  local extra=""; [ $mode = notest ] && extra="--skip rest=no_rest_service"
  gcase "$label" "$@" WORK=$W WIDGETS_APP=$GI $extra > "$GI/gt-$label.out" 2>&1; local rc=$?
  grep -E '^\| 14 \| trail \|' "$W/gate$label/gate-summary.md" | cut -c1-170; grep -oE '^gate: (PASS|FAIL|INVALID)' "$GI/gt-$label.out"; echo "gate rc=$rc"
}
ctl gate-trail-complete-pass 0 '^\| 14 \| trail \| PASS \| 0 \| trail: complete, 1 steps' '^gate: PASS' '^gate rc=0$' -- gtrail gt1 ok
ctl gate-trail-missing-test-warns-catch 0 '^\| 14 \| trail \| NOT RUN \| - \| WARNING: trail: 1 gap' '^gate: PASS' '^gate rc=0$' -- gtrail gt2 notest
ctl gate-trail-unnamed-d-row-warns-catch 0 '^\| 14 \| trail \| NOT RUN \| - \| WARNING: trail: ' '^gate: PASS' '^gate rc=0$' -- gtrail gt3 nodrow
ctl gate-trail-optional-never-fails-pass 0 '^gate: PASS' '!^gate: (FAIL|INVALID)' '^gate rc=0$' -- gtrail gt4 notest
ctl gate-trail-required-switch-invalid-catch 0 '^\| 14 \| trail \| INVALID \|' '^gate: INVALID' '^gate rc=2$' -- gtrail gt5 notest TRAIL_REQUIRED=1
ctl gate-trail-required-complete-pass 0 '^\| 14 \| trail \| PASS \|' '^gate: PASS' '^gate rc=0$' -- gtrail gt6 ok TRAIL_REQUIRED=1
ctl gate-trail-no-step-file-not-run-pass 0 '^\| 14 \| trail \| NOT RUN \| - \| no step records in this run' '^gate: PASS' '^gate rc=0$' -- gtrail gt7 nofile
ctl steps-legacy-import-fixture-pass 0 '^rc=0$' '^steps: 12$' '^assumed: 7 approved: 5 none: 0$' '^all events source legacy: True$' -- $SC legacy-import
ctl steps-legacy-rerun-adds-nothing-pass 0 '^lines before: +148 after: +148$' -- $SC legacy-rerun
ctl steps-legacy-jquery-assumed-step-catch 0 'jQuery scripts moved into JavaScript actions \| assumed by agent source legacy' -- $SC legacy-jquery
ctl steps-legacy-merge-pass 0 'order-grid steps under one topic: 2' '^unclaimed D rows with a step of their own: ' -- $SC legacy-merge
ctl steps-legacy-person-answer-kept-pass 0 '^S-10: approved by Ana$' -- $SC legacy-person-answer-kept
ctl steps-legacy-gaps-plain-pass 0 'This is not linked in this run\.' -- $SC legacy-gaps-plain
ctl steps-legacy-log-row-is-routine-no-topic-catch 0 '^run-notes: approved by agent source routine$' '^raw log row in the evidence: True$' '^steps for D6: 0$' '^assumed steps holding D6: 0$' -- $SC legacy-log-routine
ctl steps-legacy-choice-row-opens-one-topic-pass 0 '^open topics: .*decision:D7' '^D7 title: A choice about Cart_Util$' '^D7 raw text in evidence: True$' '^D7 title and say plain: True$' -- $SC legacy-choice-open
ctl steps-legacy-duplicate-topics-merge-pass 0 '^jQuery steps: 1$' "^D3 and D3a together: \\['S-[0-9]+'\\]$" -- $SC legacy-dup-merge
ctl steps-kind-choice-or-log-pass 0 '^choice <- OPEN: cart page' '^log <- mx check is 0 errors' '^choice <- jQuery scripts' '^log <- Two stale script tags' '^choice <- Gridmod' -- $SC kind-choice-log
ctl steps-check-log-row-names-parent-pass 0 '^steps: complete$' '^rc=0$' '!MISSING' -- $SC check-log-names-parent
ctl steps-legacy-commits-pass 0 'cart page commits: 1' -- $SC legacy-commits
ctl steps-legacy-match-by-d-number-pass 0 '^swap the carousel \(D4\) -> S-5 \| matched by D4 \| legacy$' '^repair D2b: Themepack style files +-> S-9 \| matched by D2 \| legacy$' -- $SC legacy-match
ctl steps-legacy-match-by-module-name-pass 0 '^step: Cartkit 3.0.0 \(stepupdate, i -> S-2 \| matched by module name \| legacy$' '^step: Shopkit 1.0.0 \(stepupdate, i -> S-1 \| matched as a routine module update \| legacy$' -- $SC legacy-match
ctl steps-legacy-match-housekeeping-not-listed-catch 0 ' 1 housekeeping, 2 unmatched$' '!unmatched: .*regenerated stubs' -- $SC legacy-match
ctl steps-legacy-match-unmatched-listed-not-guessed-catch 0 '^  unmatched: tidy the footer colours  \(no step names it\)$' '^  unmatched: convert 11\.12\.6  \(this run has no convert step\)$' '!(tidy|convert).* -> S-' -- $SC legacy-match
ctl steps-legacy-rungs-from-kind-pass 0 '^Keep or update module Cartkit closes by build, idcheck, smoke, journeys$' '^Themepack style files closes by smoke, screens, journeys$' \
    '^module step results: build PASS, idcheck NOT RUN, smoke PASS, journeys PASS$' '^result proof: legacy \| matched by the kind of step: .* \| gate/gate-summary\.md$' -- $SC legacy-rungs
ctl steps-legacy-no-rung-stays-a-gap-in-plain-words-catch 0 '^no rung: Order export \| No check of the gate fits this step, because .* It stays a gap\. The run.s own note says' -- $SC legacy-rungs
ctl steps-legacy-match-rerun-adds-nothing-pass 0 '^rerun added nothing$' '!added events' -- $SC legacy-match-rerun
ctl steps-title-bare-module-refused-catch 0 '^rc=2$' 'one bare name or id' 'Keep or update module OIDC' -- $SC title-bare-module-refused
ctl steps-title-decision-id-refused-catch 0 '^rc=2$' 'names a decision id' 'A choice about <topic>' -- $SC title-decision-id-refused
ctl steps-title-lowercase-capitalised-pass 0 '^title: Seed a real work order$' -- $SC title-lowercase-capitalised
ctl steps-title-templates-pass 0 '^module -> Keep or update module OIDC$' '^theme -> How to keep the Atlas_Web_Content style edits$' '^Java -> Keep or replace the Java library ZipUtil$' \
    '^widget -> Keep or replace the widget Charts 3.x$' '^page -> Cart page carousel$' '^row -> Seed data for the journeys$' '^row -> How the test walks sign in$' \
    '^row -> How test-side problems are healed$' '^row -> Keep or update module UserCommons \(2.4.0 to 3.0.0\)$' '^row -> A choice about Cart_Util$' '^row -> A choice made during the run$' -- $SC title-templates
ctl steps-legacy-titles-plain-pass 0 '^titles with a problem: 0$' '^module step title: Keep or update module Cartkit$' '^theme step title: ' -- $SC legacy-titles-plain
ctl cockpit-confirm-row-dropped-when-steps-cover-it-pass 0 "^confirm items: \['confirm', 'confirm:D9'\]$" -- $CK confirm-covered
ctl cockpit-confirm-group-gone-when-all-covered-pass 0 '^confirm items: \[\]$' -- $CK confirm-all-covered
ctl steps-legacy-trail-complete-pass 0 '^trail: complete, 12 steps; 7 assumed' -- $SC legacy-trail

# --- LAY: layout rung (bin/layoutdiff.py, layoutwalk.js, geometry.js, gate rung layout, theme_clash dojo-table) -----------
# fixtures/layout/{old,prefix,wrapper}: .geo.json files (trimmed) from the LineApp 10.24.13 -> 11.12.6 React run. prefix =
# the new app before the fix: Task List gallery at half width (dataView2/table1 1149 -> 581 px at 1280), images grown
# (staticImage2 40 -> 358 px). wrapper = old with one wrapper name (reactWrap) on every key and the table halved: the
# client named a wrapper the old one did not, the blind-pairing trap (no key paired, the page PASSed).
LD=$B/layoutdiff.py; LF=$FX/layout; LT=$T/layout; mkdir -p $LT
ctl layoutdiff-prefix-catch 1 '^layout: 6 pages, 3 PASS, 0 PASS\*, 3 FAIL, 0 MISSING, 0 INVALID' \
  '^FAIL +1280x800/operator-task-list\.geo\.json' 'WIDTH dataView2/table1#1: 1149 -> 581 px' '^FAIL +1024x744/operator-task-list\.geo\.json' 'WIDTH dataView2/table1#1: 923 -> 498 px' \
  '^FAIL +1280x800/operator-save-workstation\.geo\.json' 'IMAGE .*staticImage2 .*Search_Icon\.svg: 40x30 -> 358x269' -- python3 $LD $LF/old $LF/prefix
ctl layoutdiff-same-pass 0 '^layout: 6 pages, 6 PASS, 0 PASS\*, 0 FAIL, 0 MISSING, 0 INVALID' '!^FAIL' -- python3 $LD $LF/old $LF/old
mkdir -p $LT/old1/1280x800 $LT/wrap1/1280x800; cp $LF/old/1280x800/operator-task-list.geo.json $LT/old1/1280x800/; cp $LF/wrapper/1280x800/operator-task-list.geo.json $LT/wrap1/1280x800/
ctl layoutdiff-wrapper-name-catch 1 '^layout: 1 pages, 0 PASS, 0 PASS\*, 1 FAIL' 'WIDTH dataView2/table1#1: 1149 -> 574 px' '!^PASS' -- python3 $LD $LT/old1 $LT/wrap1
ctl layoutdiff-wrapper-same-pass 0 '^layout: 1 pages, 1 PASS' -- python3 $LD $LT/old1 $LT/old1
# mutation test of the catch above: with align() switched off, the wrapper page PASSes blind (the trap). The mutant must NOT catch.
sed 's/^    old, new, wrap = align(old, new)$/    wrap = {}/' $LD > $LT/layoutdiff-noalign.py
ctl layoutdiff-mutant-no-align-blind 0 '^layout: 1 pages, 1 PASS' '!^FAIL' -- python3 $LT/layoutdiff-noalign.py $LT/old1 $LT/wrap1
ctl layoutdiff-mutant-differs 1 'differ' -- sh -c "cmp -s $LD $LT/layoutdiff-noalign.py || { echo differ; exit 1; }"
# a page the old run saved and the new run did not = MISSING = failure (never skipped)
mkdir -p $LT/miss/1280x800; cp $LF/prefix/1280x800/admin-home.geo.json $LT/miss/1280x800/
ctl layoutdiff-missing-catch 1 '^MISSING +1280x800/admin-users\.geo\.json' 'no new layout for this page' '2 MISSING|[1-9] MISSING' -- python3 $LD $LF/old/1280x800/.. $LT/miss
ctl layoutdiff-nothing-paired-invalid 2 'nothing paired' -- python3 $LD $LF/old $T/nonexistent-layout
# a side without widgets, or another viewport, cannot be judged: exit 3, never a pass
mkdir -p $LT/vp/1280x800; python3 -c "
import json,sys
d=json.load(open('$LF/old/1280x800/admin-home.geo.json')); d['viewport']={'w':1000,'h':700}
json.dump(d,open('$LT/vp/1280x800/admin-home.geo.json','w'))"
mkdir -p $LT/oldhome/1280x800; cp $LF/old/1280x800/admin-home.geo.json $LT/oldhome/1280x800/
ctl layoutdiff-viewport-invalid 3 '^INVALID +1280x800/admin-home\.geo\.json' 'viewport' '1 INVALID' '!PASS$' -- python3 $LD $LT/oldhome $LT/vp
printf '1280x800/operator-save-workstation* # smaller icons on purpose, looked at both shots\n1280x800/operator-task-list* # looked at\n1024x744/operator-task-list* # looked at\n' > $LT/accept.txt
ctl layoutdiff-accept-pass 0 '^layout: 6 pages, 3 PASS, 3 PASS\*, 0 FAIL' 'accepted: smaller icons on purpose' -- python3 $LD $LF/old $LF/prefix --accept $LT/accept.txt
printf '1280x800/operator-task-list*\n' > $LT/accept-noreason.txt
ctl layoutdiff-accept-needs-reason 1 'accept line without a reason' -- python3 $LD $LF/old $LF/prefix --accept $LT/accept-noreason.txt
ctl layoutdiff-md-written-pass 0 '^layout: 6 pages' -- sh -c "python3 $LD $LF/old $LF/old --md $LT/out.md >/dev/null && head -3 $LT/out.md"
if command -v node >/dev/null 2>&1; then
  ctl geometry-loads-pass 0 'snapshot writeGeometry' -- node -e "const g=require('$B/geometry.js'); console.log(Object.keys(g).join(' '))"
  ctl layoutwalk-syntax-pass 0 -- node --check $B/layoutwalk.js
  ctl layoutwalk-usage-invalid 2 'layoutwalk: need --plan, --url and --out' -- node $B/layoutwalk.js
  mkdir -p $LT/nohome
  ctl layoutwalk-no-playwright-invalid 2 'layoutwalk: playwright not found \(set PLAYWRIGHT_DIR\)' -- env -u NODE_PATH HOME=$LT/nohome PLAYWRIGHT_DIR=$LT/nohome/none sh -c "cd $LT/nohome && node $B/layoutwalk.js --plan x --url http://localhost:1 --out $LT/nohome/o"
else skip layoutwalk "no node"; fi
# gate rung layout: not configured = NOT RUN (optional, never PASS); configured = layoutdiff.py on the two folders
ctl gate-layout-not-configured-pass 0 '\| 8 \| layout \| NOT RUN \| - \| not configured .*\(optional rung\)' 'Overall: \*\*PASS' '!\| layout \| PASS' -- gcase lnone
ctl gate-layout-dry-run-pass 0 '^\[layout\] .*layoutdiff\.py .*fixtures/layout/old .*fixtures/layout/prefix .*layoutdiff\.md' -- gcase ldry --dry-run LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/prefix
ctl gate-layout-stub-pass 0 '\| 8 \| layout \| PASS \| 0 \|' 'Overall: \*\*PASS' -- gcase lpass LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/old
ctl gate-layout-fail-catch 1 '\| 8 \| layout \| FAIL \| 1 \|' 'Overall: \*\*FAIL' 'layout: REGRESSION to fix' 'layout: 6 pages, 3 PASS, 0 PASS\*, 3 FAIL' \
  -- gcase lfail GATE_STUB_RC_layoutdiff=1 'GATE_STUB_OUT_layoutdiff=layout: 6 pages, 3 PASS, 0 PASS*, 3 FAIL, 0 MISSING, 0 INVALID' LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/prefix
ctl gate-layout-missing-is-fail-catch 1 '\| 8 \| layout \| FAIL \| 1 \|' 'Overall: \*\*FAIL' 'layout: REGRESSION to fix' \
  -- gcase lmiss GATE_STUB_RC_layoutdiff=1 'GATE_STUB_OUT_layoutdiff=layout: 6 pages, 3 PASS, 0 PASS*, 0 FAIL, 3 MISSING, 0 INVALID' LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/old
ctl gate-layout-invalid-catch 2 '\| 8 \| layout \| INVALID \| 3 \|' 'Overall: \*\*INVALID' '!Overall: \*\*PASS' \
  -- gcase linv GATE_STUB_RC_layoutdiff=3 'GATE_STUB_OUT_layoutdiff=layout: 6 pages, 5 PASS, 0 PASS*, 0 FAIL, 0 MISSING, 1 INVALID' LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/old
ctl gate-layout-one-folder-input-error 2 'rung layout: LAYOUT_NEW is not set' 'nothing was run' -- gcase lone LAYOUT_OLD=$LF/old
ctl gate-layout-no-folder-input-error 2 'rung layout: LAYOUT_NEW: no such folder' -- gcase lnofold LAYOUT_OLD=$LF/old LAYOUT_NEW=$T/no-such-layout
# the real layoutdiff.py among stubs: the golden catch through the gate, then the same folders against themselves
GB4=$T/gate-bin-layout; mkdir -p $GB4; cp $GB/* $GB4/; cp $B/layoutdiff.py $GB4/layoutdiff.py
ctl gate-layout-real-catch 1 '\| 8 \| layout \| FAIL \| 1 \| layout: 6 pages, 3 PASS, 0 PASS\*, 3 FAIL' 'Overall: \*\*FAIL' 'layout: REGRESSION to fix' \
  -- gcase lreal GATE_BIN_DIR=$GB4 LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/prefix
ctl gate-layout-real-pass 0 '\| 8 \| layout \| PASS \| 0 \| layout: 6 pages, 6 PASS' 'Overall: \*\*PASS' -- gcase lreal2 GATE_BIN_DIR=$GB4 LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/old
ctl gate-layout-real-accept-pass 0 '\| 8 \| layout \| PASS\* \| 0 \|' 'Overall: \*\*PASS' -- gcase lreal3 GATE_BIN_DIR=$GB4 LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/prefix LAYOUT_ACCEPT=$LT/accept.txt
# theme_clash dojo-table: Dojo mxui table rules on React layout containers, in vendor and own styling
for c in vendor own pass; do mk9 dt-$c app-dojo-table-$c > /dev/null; done
D=$TH9/dt-vendor
ctl theme-clash-dojo-table-vendor-catch 1 '^CLASH dojo-table \.mx-scrollcontainer-horizontal: display: table; table-layout: fixed in themesource/core_delta/web/_mxui\.scss:5 \(vendor core_delta module\)' \
  '^CLASH dojo-table \.mx-scrollcontainer-horizontal: display: table-cell in themesource/core_delta/web/_mxui\.scss:10 ' '^theme clash: 2 clashes \(0 variables, 0 mixins, 0 classes, 0 extends, 2 dojo-table\)' '!mx-templategrid-item' -- python3 $TC diff $D/old $D/new
D=$TH9/dt-own
ctl theme-clash-dojo-table-own-catch 1 '^CLASH dojo-table \.mx-scrollcontainer-horizontal: display: table in theme/web/main\.scss:3 \(own styling\)' '^theme clash: 1 clashes \(0 variables, 0 mixins, 0 classes, 0 extends, 1 dojo-table\)' '!mx-scrollcontainer-wrapper' -- python3 $TC diff $D/old $D/new
D=$TH9/dt-vendor
ctl theme-clash-dojo-table-dojo-client-pass 0 '^theme clash: 0 clashes \(0 variables, 0 mixins, 0 classes, 0 extends\)' '!dojo-table' -- python3 $TC diff $D/old $D/new --client dojo
D=$TH9/dt-pass
ctl theme-clash-dojo-table-flex-override-pass 0 '^theme clash: 0 clashes \(0 variables, 0 mixins, 0 classes, 0 extends\)' '!CLASH' -- python3 $TC diff $D/old $D/new
sed 's/^            flexed.add(stack\[-1\]\[1\])/            pass/' $TC > $T/tc-noflex.py
ctl theme-clash-dojo-table-mutant-no-flex-excusal 1 '^CLASH dojo-table' -- python3 $T/tc-noflex.py diff $D/old $D/new
ctl theme-clash-dojo-table-mutant-no-flex-differs 1 'differ' -- sh -c "cmp -s $TC $T/tc-noflex.py || { echo differ; exit 1; }"
ctl theme-clash-dojo-table-snap-pass 0 'dojo_table' -- sh -c "python3 $TC snap $TH9/dt-vendor/new | grep dojo_table"
# LAY-12: a padding 0 rule scoped under .mx-scrollcontainer-* that hits .mx-layoutgrid* (React adds a scroll container region)
mk9 rw app-react-wrapper > /dev/null; D=$TH9/rw
ctl theme-clash-react-wrapper-catch 1 '^CLASH react-wrapper \.mx-layoutgrid: padding: 0 in theme/web/main\.scss:1 \(own styling\)' '^theme clash: 1 clashes \(0 variables, 0 mixins, 0 classes, 0 extends, 1 react-wrapper\)' '!main\.scss:4' '!main\.scss:7' -- python3 $TC diff $D/old $D/new
sed 's/^WRAP_CHAIN_RE = .*/WRAP_CHAIN_RE = re.compile(r"(?!)")/' $TC > $T/tc-nowrap.py
ctl theme-clash-react-wrapper-mutant-blind 0 '^theme clash: 0 clashes' '!react-wrapper' -- python3 $T/tc-nowrap.py diff $D/old $D/new
ctl theme-clash-react-wrapper-mutant-differs 1 'differ' -- sh -c "cmp -s $TC $T/tc-nowrap.py || { echo differ; exit 1; }"
D=$TH9/dt-pass
ctl theme-clash-react-wrapper-clean-app-pass 0 '!react-wrapper' '^theme clash: 0 clashes' -- python3 $TC diff $D/old $D/new

# LAY-9: layout runs before journeys (journeys change data, a later layout compare fails against a fresh-data baseline)
ctl gate-layout-before-journeys-pass 0 '\| 7 \| smoke \|' '\| 8 \| layout \|' '\| 9 \| journeys \|' '\| 10 \| screens \|' -- gcase lord GATE_STUB_OUT_diff='INVALID 0 | FAIL 0 | REVIEW 0 | PASS* 3 | PASS 84' LAYOUT_OLD=$LF/old LAYOUT_NEW=$LF/old
ctl gate-layout-order-doc-pass 0 'smoke layout journeys screens' -- grep -o 'smoke layout journeys screens' $B/gate.sh
ctl gate-layout-order-step-pass 0 '^7b\. Layout .*runs BEFORE journeys' -- grep -E '^7b\. Layout' $B/../steps/gate.md


# LAY-7: the Static image row of the shipped playbook carries the unit rule and the mxcli fix
PB=$B/../playbooks/dojo-successors.tsv
ctl playbook-static-image-unit-catch 0 'CARRY OVER the width and height unit' 'Auto stays auto, pixels stay pixels, percentage stays percentage' 'ALTER PAGE M\.P \{ set \(WidthUnit: auto\) on <widget>; \}' 'mx update-widgets' -- grep -E '^Forms\\\$StaticImageViewer' $PB
ctl playbook-static-image-row-pass 0 '^static image row: 9 columns$' -- awk -F'\t' '/^Forms\\\$StaticImageViewer/{ if (NF == 9) print "static image row: 9 columns"; else print "static image row: " NF " columns" }' $PB
ctl playbook-image-wrapper-catch 0 'div\.mx-image-viewer' '\.mx-image-viewer\.mx-image-viewer-responsive > img, \.mx-image-viewer > img \{max-width:100%; max-height:100%\}' -- grep -E '^Forms\\\$StaticImageViewer' $PB
ctl playbook-combobox-placeholder-catch 0 'min-width 135px' 'placeholder position absolute; min-width 0' -- grep -E '^Forms\\\$ReferenceSelector' $PB
ctl playbook-htmlsnippet-events-catch 0 '\.widget-events with flex 1 1 auto' 'zeroes grids that were not nested on Dojo' -- grep -E '^HTMLSnippet' $PB
ctl playbook-lay-rows-9-columns-pass 0 '^LAY rows: 9 columns$' -- awk -F'\t' '/^(Forms\\\$StaticImageViewer|Forms\\\$ReferenceSelector|Forms\\\$ReferenceSetSelector|Forms\\\$InputReferenceSetSelector|Forms\\\$DropDown|HTMLSnippet)/{ if (NF != 9) bad=1 } END{ print bad ? "LAY rows: bad column count" : "LAY rows: 9 columns" }' $PB


echo
echo "controls: $npass passed, $nfail failed, $nskip skipped"
[ -n "$failed" ] && echo "failed:$failed"
[ -n "$skipped" ] && echo "skipped:$skipped"
[ $nfail = 0 ]
