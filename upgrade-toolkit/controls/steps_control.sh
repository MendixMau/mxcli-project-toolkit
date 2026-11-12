#!/bin/bash
# steps_control.sh CASE: controls for bin/steps.py on a made-up shop app (Gridmod and Themepack are Marketplace-style names).
# Builds a throwaway work folder, runs one case and prints what it saw.
set -u
here=$(cd "$(dirname "$0")" && pwd); B=$(cd "$here/.." && pwd)/bin
case_=$1; T=${TMPDIR:-/tmp}/steps-ctl.$$; trap 'rm -rf "$T"' EXIT
W=$T/work; mkdir -p "$W"
st() { python3 "$B/steps.py" "$@" --work "$W"; }
fieldof() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$@"; }
# one complete step: found, proposed, approved, one commit, two passing tests
mk() {
  st open --topic modules:Gridmod --title "Order grid update" --say "The order grid cannot show rows on the new client." --stage triage --evidence "work/triage.md" >/dev/null
  st propose --id S-1 --say "Update the grid module to the version for the new client." --why "Same behaviour at the lowest cost." \
     --option "Update now (recommended)" --option "Keep the old grid" --recommend 0 --closes-by smoke --closes-by journeys >/dev/null
}
full() {
  mk; st approve --id S-1 --state approved --by Ana --source page >/dev/null
  st done --id S-1 --commit abc1234 --say "Grid module moved to version 2." >/dev/null
  st tested --id S-1 --rung smoke --verdict PASS --say "4 of 4 pages open without errors." --proof gate/smoke.json >/dev/null
  st tested --id S-1 --rung journeys --verdict PASS --say "12 of 12 click paths end the same." >/dev/null
}
# gsum DIR SMOKE_VERDICT [JOURNEYS_VERDICT]: a gate-summary.md with the two rungs the step closes by (a missing third argument leaves the journeys row out)
gsum() {
  mkdir -p "$1"; { echo "# Gate summary"; echo; echo "| # | rung | verdict | rc | one line |"; echo "|---|---|---|---|---|"
    echo "| 1 | build | PASS | 0 | BUILD SUCCEEDED |"; echo "| 7 | smoke | $2 | 0 | steps: PASS 4 \\| FAIL 0 |"
    [ -z "${3:-}" ] || echo "| 8 | journeys | $3 | 0 | journeys: 12 PASS |"; } > "$1/gate-summary.md"
}
# lg: copy the legacy fixture (work/ and AGENT-DECISIONS.md) beside $W and run import-legacy; LOUT/LRC hold its output and exit code
lg() { cp "$here/fixtures/legacy/work/"* "$W/"; cp "$here/fixtures/legacy/AGENT-DECISIONS.md" "$T/"
  LOUT=$(st import-legacy --decisions "$T/AGENT-DECISIONS.md" 2>&1); LRC=$?; }
# lgrepo: a tiny git repo R of made-up commits that the fixture steps can be matched to
lgrepo() { R=$T/repo; git init -q "$R"; git -C "$R" config user.email a@b; git -C "$R" config user.name a; local n=0
  for m in "swap the carousel (D4)" "repair D2b: Themepack style files deleted again" "step: Cartkit 3.0.0 (stepupdate, idcheck PASS)" \
           "step: Shopkit 1.0.0 (stepupdate, idcheck PASS)" "build: regenerated stubs" "tidy the footer colours" "convert 11.12.6"; do
    n=$((n + 1)); echo $n > "$R/f$n"; git -C "$R" add "f$n"; git -C "$R" commit -qm "$m"; done; }
case $case_ in
  # slice 9: import-legacy on the made-up shop run in fixtures/legacy (work/ and AGENT-DECISIONS.md one level up, like run2)
  # legacy matching: commits and rungs to steps. A tiny git repo with made-up commits beside the made-up shop fixture
  legacy-match) lg >/dev/null; lgrepo; st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" > "$T/imp.txt"; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"\n".join("%s -> %s | %s | %s" % (c["say"][:34], r["id"], c["why"], c["source"]) for r in d for c in r["done"]["commits"])'
            grep -E '^steps: import-legacy: [0-9]+ commit|unmatched:' "$T/imp.txt" | sed 's/^\(  unmatched: \)[0-9a-f]* /\1/' ;;
  legacy-match-rerun) lg >/dev/null; lgrepo; mkdir -p "$T/gate"; gsum "$T/gate" PASS PASS
            st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" >/dev/null; st tested --gate "$T/gate" >/dev/null; a=$(wc -l < "$W/steps.jsonl")
            st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" >/dev/null; st tested --gate "$T/gate" >/dev/null
            b=$(wc -l < "$W/steps.jsonl"); echo "lines before: $a after: $b"; [ $((a)) = $((b)) ] && echo "rerun added nothing" || echo "rerun added events" ;;
  legacy-rungs) lg >/dev/null; lgrepo; mkdir -p "$T/gate"; gsum "$T/gate" PASS PASS
            st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" >/dev/null; st tested --gate "$T/gate" >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"\n".join("%s closes by %s" % (r["title"], ", ".join(r["proposed"]["closes_by"])) for r in d if r["topic"] in ("module:Cartkit", "theme:Themepack style files", "order-grid") and r["proposed"].get("closes_by"))'
            fieldof "$T/s.json" '"no rung: " + [r["title"] for r in d if not r["proposed"].get("closes_by") and r["topic"] == "order-grid"][0] + " | " + [r["gaps"]["tested"] for r in d if r["title"] == "Order export"][0]'
            fieldof "$T/s.json" '"module step results: " + ", ".join("%s %s" % (t["rung"], t["verdict"]) for r in d if r["topic"] == "module:Cartkit" for t in r["tested"]["results"])'
            fieldof "$T/s.json" '"result proof: %s | %s | %s" % ([t["source"] for r in d if r["topic"] == "module:Cartkit" for t in r["tested"]["results"]][0], [t["why"] for r in d if r["topic"] == "module:Cartkit" for t in r["tested"]["results"]][0], [t["proof"] for r in d if r["topic"] == "module:Cartkit" for t in r["tested"]["results"]][0][0])' ;;
  legacy-import) lg; echo "rc=$LRC"; echo "$LOUT"; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"steps: %d" % len(d)'
            fieldof "$T/s.json" '"assumed: %d approved: %d none: %d" % tuple(sum(1 for r in d if (r.get("approval") or {}).get("state", "none") == k) for k in ("assumed", "approved", "none"))'
            python3 -c 'import json,sys; ev=[json.loads(l) for l in open(sys.argv[1])]; print("all events source legacy:", all(e.get("source")=="legacy" for e in ev))' "$W/steps.jsonl" ;;
  legacy-jquery) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '[ "%s | %s | %s by %s source %s | decisions %s" % (r["id"], r["title"], r["approval"]["state"], r["approval"]["by"], r["approval"]["source"], r["proposed"]["decisions"]) for r in d if "jQuery" in r["title"] ][0]'
            fieldof "$T/s.json" '[ "found: " + r["found"]["say"] for r in d if "jQuery" in r["title"] ][0]'
            fieldof "$T/s.json" '[ "gaps: " + ",".join(sorted(r["gaps"])) for r in d if "jQuery" in r["title"] ][0]' ;;
  legacy-merge) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '[ "%s %s approval %s decisions %s" % (r["id"], r["title"], r["approval"]["state"], r["proposed"]["decisions"]) for r in d if r["topic"] == "cart-page" ][0]'
            fieldof "$T/s.json" '[ "%s approved by %s" % (r["id"], r["approval"]["by"]) for r in d if r["topic"].startswith("page:") ][0]'
            fieldof "$T/s.json" '"order-grid steps under one topic: %d" % sum(1 for r in d if r["topic"] == "order-grid")'
            fieldof "$T/s.json" '"unclaimed D rows with a step of their own: %s" % sorted(r["topic"] for r in d if r["topic"].startswith("decision:"))' ;;
  legacy-rerun) lg >/dev/null; a=$(wc -l < "$W/steps.jsonl"); st import-legacy --decisions "$T/AGENT-DECISIONS.md" >/dev/null; echo "lines before: $a after: $(wc -l < "$W/steps.jsonl")" ;;
  legacy-person-answer-kept) lg >/dev/null; st approve --id S-10 --state approved --by Ana --source page >/dev/null
            st import-legacy --decisions "$T/AGENT-DECISIONS.md" >/dev/null; st show S-10 --json > "$T/s.json"
            fieldof "$T/s.json" '"S-10: %s by %s" % (d[0]["approval"]["state"], d[0]["approval"]["by"])' ;;
  legacy-gaps-plain) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"order export: " + [r for r in d if r["title"] == "Order export"][0]["approval"]["source"] + " approval, no gap"'
            fieldof "$T/s.json" '"done gap: " + [r for r in d if r["title"] == "Order export"][0]["gaps"]["done"]' ;;
  legacy-commits) lg >/dev/null; R=$T/repo; git init -q "$R"; git -C "$R" config user.email a@b; git -C "$R" config user.name a
            echo 1 > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm "swap the carousel (D4)"
            echo 2 > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm "unrelated tidy"
            st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" >/dev/null; st import-legacy --decisions "$T/AGENT-DECISIONS.md" --app "$R" >/dev/null
            st show --json > "$T/s.json"
            fieldof "$T/s.json" '"cart page commits: %d (%s)" % (len([r for r in d if r["topic"] == "cart-page"][0]["done"]["commits"]), [r for r in d if r["topic"] == "cart-page"][0]["done"]["commits"][0]["say"])'
            fieldof "$T/s.json" '"steps with a commit: %d" % sum(1 for r in d if r["done"]["commits"])' ;;
  legacy-log-routine) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '[ "run-notes: %s by %s source %s" % (r["approval"]["state"], r["approval"]["by"], r["approval"]["source"]) for r in d if r["topic"] == "run-notes" ][0]'
            fieldof "$T/s.json" '"raw log row in the evidence: %s" % any("Cart_Util.java" in e and "19 errors" in e for r in d if r["topic"] == "run-notes" for e in r["found"]["evidence"])'
            fieldof "$T/s.json" '"steps for D6: %d" % sum(1 for r in d if r["topic"] == "decision:D6")'
            fieldof "$T/s.json" '"assumed steps holding D6: %d" % sum(1 for r in d if "D6" in str(r) and (r.get("approval") or {}).get("state") == "assumed")' ;;
  title-bare-module-refused) st open --topic module:OIDC --title OIDC --say "A module has local edits."; echo "rc=$?" ;;
  title-decision-id-refused) st propose --new --topic decision:D8 --title "The agent chose how to handle decision D8" --found "The agent met a choice." --say "The agent picked one way."; echo "rc=$?" ;;
  title-lowercase-capitalised) st open --topic seed --title "seed a real work order" --say "The journeys need data." >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"title: " + d[0]["title"]' ;;
  title-templates) python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import steps
for k, n in (("module", "OIDC"), ("theme", "Atlas_Web_Content themesource edits"), ("Java", "ZipUtil"), ("widget", "Charts 3.x"), ("renamed module", "Gridmod"), ("page", "Cart page carousel"), ("re-architecture", "Checkout")):
    print(k, "->", steps.item_title(k, n))
for t in ("PROPOSAL: seed a real work order with annexes, alerts and samples", "basewalk exit 11: walk cannot log in (the login page is an SSO page)", "Heal policy: heal test-side causes automatically", "UserCommons 2.4.0 -> 3.0.0", "Cart_Util.java calls the removed cart API", "x"):
    print("row ->", steps.plain_title(t, "D9"))' "$B" ;;
  legacy-titles-plain) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"titles with a problem: %d" % sum(1 for r in d if __import__("sys").path.insert(0, "'"$B"'") or __import__("steps").title_problem(r["title"]))'
            fieldof "$T/s.json" '"module step title: " + [r["title"] for r in d if r["topic"] == "module:Cartkit"][0]'
            fieldof "$T/s.json" '"theme step title: " + [r["title"] for r in d if r["topic"].startswith("theme:")][0]' ;;
  legacy-choice-open) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"open topics: %s" % sorted(r["topic"] for r in d if (r.get("approval") or {}).get("state") == "assumed")'
            fieldof "$T/s.json" '[ "D7 title: " + r["title"] for r in d if r["topic"] == "decision:D7" ][0]'
            fieldof "$T/s.json" '"D7 raw text in evidence: %s" % any("Cart_Util.java" in e for r in d if r["topic"] == "decision:D7" for e in r["found"]["evidence"])'
            fieldof "$T/s.json" '"D7 title and say plain: %s" % all(__import__("sys").path.insert(0, "'"$B"'") or __import__("steps").plain(t) for r in d if r["topic"] == "decision:D7" for t in (r["title"], r["found"]["say"], r["proposed"]["say"]))' ;;
  legacy-dup-merge) lg >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"jQuery steps: %d" % sum(1 for r in d if "jQuery" in r["title"])'
            fieldof "$T/s.json" '"D3 and D3a together: %s" % [ r["id"] for r in d if "D3a" in str(r) and "D3" in str(r) ]' ;;
  kind-choice-log) for t in "OPEN: cart page carousel swapped|Options: (1) swap, (2) keep" "mx check is 0 errors, but mxbuild fails on Java compile|Retried twice" "jQuery scripts moved into JavaScript actions|Every script runs from an action, instead of being rewritten" "Two stale script tags in index.html|Removed" "Gridmod 1.4.0 -> 2.0.0|UPDATE in two steps"; do
              echo "$(python3 "$B/steps.py" kind --title "${t%%|*}" --choice "${t##*|}") <- ${t%%|*}"; done ;;
  check-log-names-parent) mk; st approve --id S-1 --state approved --by agent --source routine >/dev/null; st gap --id S-1 --field done --say "No change needed." >/dev/null; st gap --id S-1 --field tested --say "Not run." >/dev/null
            printf '| ID | Title | Choice | Why |\n|---|---|---|---|\n| D90 (agent, log) S-1 | mxbuild printed 19 errors | Retried twice | Tool output only |\n' > "$W/AGENT-DECISIONS.md"; st check; echo "rc=$?" ;;
  legacy-trail) lg >/dev/null; st trail --decisions "$T/AGENT-DECISIONS.md"; echo "rc=$?"; st check --decisions "$T/AGENT-DECISIONS.md" | grep -v '^note' ; echo "rc=$?" ;;
  fold-last-wins) mk; st approve --id S-1 --state assumed --by agent >/dev/null; st approve --id S-1 --state approved --by Ana >/dev/null
            st show S-1 --json > "$T/s.json"; echo "approval: $(fieldof "$T/s.json" 'd[0]["approval"]["state"]') by $(fieldof "$T/s.json" 'd[0]["approval"]["by"]')"
            echo "approve lines in file: $(grep -c '"field": "approval"' "$W/steps.jsonl")"; echo "first approve: $(grep '"field": "approval"' "$W/steps.jsonl" | head -1 | grep -o '"state": "[a-z]*"')" ;;
  fold-only-assumed) mk; st approve --id S-1 --state assumed --by agent >/dev/null; st show S-1 --json > "$T/s.json"
            echo "approval: $(fieldof "$T/s.json" 'd[0]["approval"]["state"]')"; echo "lines: $(wc -l < "$W/steps.jsonl" | tr -d ' ')" ;;
  open-ids) st open --topic a --title "First title" --say "First." ; st open --topic b --title "Second title" --say "Second." ;;
  open-evidence-kept) mk; st show S-1 --json > "$T/s.json"; echo "evidence: $(fieldof "$T/s.json" 'd[0]["found"]["evidence"]')"; echo "options: $(fieldof "$T/s.json" 'len(d[0]["proposed"]["options"])') recommend: $(fieldof "$T/s.json" 'd[0]["proposed"]["recommend"]')" ;;
  unknown-id) st propose --id S-9 --say "Update it."; echo "rc=$?"; test ! -f "$W/steps.jsonl" && echo "file untouched" ;;
  unknown-id-approve) mk; st approve --id S-7 --state approved --by Ana; echo "rc=$?" ;;
  say-path) mk; st propose --id S-1 --say "Change the file work/plan/notes in the app."; echo "rc=$?"; echo "lines: $(wc -l < "$W/steps.jsonl" | tr -d ' ')" ;;
  say-filename) st open --topic a --title "First title" --say "Edit the settings.json to fix it."; echo "rc=$?" ;;
  say-code) st open --topic a --title "First title" --say 'Run the `build` command again.'; echo "rc=$?" ;;
  say-plain) st open --topic a --title "First title" --say "The grid shows 4 of 5 rows, and the totals still add up."; echo "rc=$?" ;;
  bad-state) mk; st approve --id S-1 --state maybe --by Ana; echo "rc=$?" ;;
  bad-verdict) mk; st tested --id S-1 --rung smoke --verdict GREAT --say "All fine."; echo "rc=$?" ;;
  slash-words) mk; st propose --id S-1 --say "Keep the old and/or new look, as on React 18/19."; echo "rc=$?" ;;
  good-propose) mk; st propose --id S-1 --say "Keep the old grid for now." --option "Keep it" --recommend 0; echo "rc=$?"; st show S-1 --json > "$T/s.json"; echo "say: $(fieldof "$T/s.json" 'd[0]["proposed"]["say"]')" ;;
  check-complete) full; st check; echo "rc=$?" ;;
  check-incomplete) mk; st approve --id S-1 --state approved --by Ana >/dev/null; st check; echo "rc=$?" ;;
  check-no-approval) mk; st check; echo "rc=$?" ;;
  check-gap-covers) mk; st approve --id S-1 --state approved --by Ana >/dev/null; st gap --id S-1 --field done --say "No change needed." >/dev/null
            st gap --id S-1 --field tested --say "The test rungs did not run in this run." >/dev/null; st check; echo "rc=$?" ;;
  check-assumed) mk; st approve --id S-1 --state assumed --by agent >/dev/null; st tested --id S-1 --rung smoke --verdict PASS --say "Pages open." >/dev/null
            st tested --id S-1 --rung journeys --verdict PASS --say "Paths end the same." >/dev/null; st check; echo "rc=$?" ;;
  status) full; echo "full: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')" ;;
  status-open-assumed) mk; st approve --id S-1 --state assumed --by agent >/dev/null; st tested --id S-1 --rung smoke --verdict PASS --say "Pages open." >/dev/null
            st tested --id S-1 --rung journeys --verdict PASS --say "Paths end the same." >/dev/null; echo "assumed: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')" ;;
  status-open-missing-test) mk; st approve --id S-1 --state approved --by Ana >/dev/null; st tested --id S-1 --rung smoke --verdict 'PASS*' --say "Pages open." >/dev/null
            echo "missing test: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')" ;;
  status-blocked-fail) full; st tested --id S-1 --rung journeys --verdict FAIL --say "3 of 12 click paths end differently." >/dev/null
            echo "fail: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')"; st check >/dev/null; echo "check rc=$?" ;;
  status-blocked-rejected) mk; st approve --id S-1 --state rejected --by Ana >/dev/null
            echo "rejected: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')" ;;
  status-never-written) full; echo "status in file: $(grep -c '"field": "status"' "$W/steps.jsonl")" ;;
  # slice 4: a decision the agent makes mid-run opens its own step, and a D row without a step fails the check
  new-step) st propose --new --topic "scripts:Gridmod" --title "Order scripts on the new client" --found "The new client cannot run 12 order scripts." \
              --say "Run each script from a JavaScript action." --why "Same behaviour at the lowest cost." --option "Bridge now (recommended)" --option "Rewrite as widgets" --recommend 0 --decision D71
            echo "rc=$?"; st show S-1 --json > "$T/s.json"
            echo "approval: $(fieldof "$T/s.json" 'd[0]["approval"]["state"]') by $(fieldof "$T/s.json" 'd[0]["approval"]["by"]') source $(fieldof "$T/s.json" 'd[0]["approval"]["source"]')"
            echo "needs: $(fieldof "$T/s.json" 'd[0]["approval"]["needs"]')"; echo "decisions: $(fieldof "$T/s.json" 'd[0]["proposed"]["decisions"]')"
            echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  new-step-no-found) st propose --new --topic "scripts:Gridmod" --title "Order scripts" --say "Run each script from a JavaScript action."; echo "rc=$?"; test ! -f "$W/steps.jsonl" && echo "file untouched" ;;
  new-step-path) st propose --new --topic "scripts:Gridmod" --title "Order scripts" --found "Scripts break." --say "Edit the file work/plan/orders in the app."; echo "rc=$?"; test ! -f "$W/steps.jsonl" && echo "file untouched" ;;
  new-step-with-id) mk; st propose --new --id S-1 --topic a --title b --found "Scripts break." --say "Fix them."; echo "rc=$?" ;;
  drow-no-step) printf '| ID | Title | Choice | Why |\n|---|---|---|---|\n| D71 (agent) | Move order scripts into actions | bridge | cheapest |\n' > "$W/AGENT-DECISIONS.md"; st check; echo "rc=$?" ;;
  drow-with-step) st propose --new --topic "scripts:Gridmod" --title "Order scripts" --found "The new client cannot run 12 order scripts." --say "Run each script from a JavaScript action." --decision D71 >/dev/null
            printf '| ID | Title | Choice | Why |\n|---|---|---|---|\n| D71 (agent) S-1 | Move order scripts into actions | bridge | cheapest |\n| D71b (agent) | Same, second batch | bridge | same |\n' > "$W/AGENT-DECISIONS.md"; st check; echo "rc=$?" ;;
  drow-unknown-step) printf '| D71 (agent) S-5 | Move order scripts into actions | bridge | cheapest |\n' > "$W/AGENT-DECISIONS.md"; mk; st approve --id S-1 --state approved --by Ana >/dev/null; st gap --id S-1 --field done --say "No change needed." >/dev/null
            st gap --id S-1 --field tested --say "Not run." >/dev/null; st check; echo "rc=$?" ;;
  drow-in-parent) mkdir -p "$T/run"; printf '| D80 (agent) | Drop the old theme | drop | unused |\n' > "$T/run/AGENT-DECISIONS.md"; mkdir -p "$T/run/work"; W=$T/run/work; st check; echo "rc=$?" ;;
  # slice 6: the gate links its rungs to the steps (tested --gate), as a pass, a fail or a gap
  gate-pass) mk; st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "PASS*"; st tested --gate "$T/g"; echo "rc=$?"
            st show S-1 --json > "$T/s.json"; echo "results: $(fieldof "$T/s.json" '[(r["rung"], r["verdict"]) for r in d[0]["tested"]["results"]]')"
            echo "say: $(fieldof "$T/s.json" 'd[0]["tested"]["results"][0]["say"]')"; echo "proof: $(fieldof "$T/s.json" 'd[0]["tested"]["results"][1]["proof"]')"
            echo "gaps: $(fieldof "$T/s.json" 'list(d[0]["gaps"])')"; echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  gate-fail) mk; st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "FAIL"
            printf '{"rows":[{"id":"journey:act-Gridmod.Grid.refreshButton","class":"real-regression"},{"id":"journey:act-Gridmod.Grid.exportButton","class":"real-regression"},{"id":"journey:act-Shop.Home.menuButton","class":"real-regression"},{"id":"data:x","class":"real-regression"}]}' > "$W/heal.json"
            st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "results: $(fieldof "$T/s.json" '[(r["rung"], r["verdict"]) for r in d[0]["tested"]["results"]]')"
            echo "say: $(fieldof "$T/s.json" 'd[0]["tested"]["results"][1]["say"]')"; echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  # a FAIL row fails only the steps it names: a click path of another module leaves this step not proven (a gap), never red
  gate-fail-elsewhere) mk; st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "FAIL"
            printf '{"rows":[{"id":"journey:act-Shop.Home.menuButton","class":"real-regression"}]}' > "$W/heal.json"
            st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "results: $(fieldof "$T/s.json" '[(r["rung"], r["verdict"]) for r in d[0]["tested"]["results"]]')"
            echo "gap: $(fieldof "$T/s.json" 'd[0]["gaps"]["tested:journeys"]')"; echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  gate-fail-build) mk; st propose --id S-1 --say "Update the grid module to the version for the new client." --closes-by build >/dev/null
            gsum "$T/g" "PASS" "PASS"; sed -i.bak 's/| build | PASS |/| build | FAIL |/' "$T/g/gate-summary.md"; st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "build: $(fieldof "$T/s.json" '[r["verdict"] for r in d[0]["tested"]["results"] if r["rung"]=="build"]')" ;;
  gate-gap) mk; st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "NOT RUN"; st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "results: $(fieldof "$T/s.json" '[(r["rung"], r["verdict"]) for r in d[0]["tested"]["results"]]')"
            echo "gap: $(fieldof "$T/s.json" 'd[0]["gaps"]["tested:journeys"]')"; echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  gate-invalid-is-gap) mk; gsum "$T/g" "INVALID" "PASS"; st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "smoke: $(fieldof "$T/s.json" 'd[0]["tested"]["results"][0]["verdict"]') / $(fieldof "$T/s.json" 'd[0]["gaps"]["tested:smoke"]')" ;;
  gate-missing-row) mk; gsum "$T/g" "PASS"; st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "journeys: $(fieldof "$T/s.json" 'd[0]["tested"]["results"][1]["verdict"]') / $(fieldof "$T/s.json" 'd[0]["gaps"]["tested:journeys"]')" ;;
  gate-no-link) st open --topic modules:Gridmod --title "Order grid update" --say "The order grid cannot show rows on the new client." >/dev/null
            st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "PASS"; st tested --gate "$T/g" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "results: $(fieldof "$T/s.json" 'len(d[0]["tested"]["results"])')"; echo "gap: $(fieldof "$T/s.json" 'd[0]["gaps"]["tested"]')"
            echo "status: $(fieldof "$T/s.json" 'd[0]["status"]')" ;;
  gate-replaces-pass) mk; st approve --id S-1 --state approved --by Ana >/dev/null; gsum "$T/g" "PASS" "PASS"; st tested --gate "$T/g" >/dev/null
            echo "first: $(st show S-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')"
            gsum "$T/g2" "PASS" "NOT RUN"; st tested --gate "$T/g2" >/dev/null; st show S-1 --json > "$T/s.json"
            echo "later: $(fieldof "$T/s.json" 'd[0]["status"]') journeys $(fieldof "$T/s.json" '[r["verdict"] for r in d[0]["tested"]["results"] if r["rung"]=="journeys"]')" ;;
  gate-rerun) mk; gsum "$T/g" "PASS" "PASS"; st tested --gate "$T/g" >/dev/null; n=$(wc -l < "$W/steps.jsonl"); st tested --gate "$T/g"; echo "added on rerun: $(( $(wc -l < "$W/steps.jsonl") - n ))" ;;
  gate-no-summary) mk; mkdir -p "$T/empty"; st tested --gate "$T/empty"; echo "rc=$?" ;;
  # two-version upgrade: UPG_PHASE gives each step its version; the same module is a step per version and gate 2 leaves gate 1's results alone
  phase-split) UPG_PHASE=10.24.0 mk; UPG_PHASE=10.24.0 st approve --id S-1 --state approved --by Ana >/dev/null
            gsum "$T/g1" "PASS" "FAIL"; UPG_PHASE=10.24.0 st tested --gate "$T/g1" >/dev/null
            UPG_PHASE=11.12.7 st find --topic modules:Gridmod >/dev/null; echo "found in 11.12.7: rc=$?"
            UPG_PHASE=11.12.7 st open --topic modules:Gridmod --title "Order grid update" --say "The grid needs its 11 version." >/dev/null
            UPG_PHASE=11.12.7 st propose --id S-2 --say "Update the grid again." --closes-by smoke --closes-by journeys >/dev/null
            gsum "$T/g2" "PASS" "PASS"; UPG_PHASE=11.12.7 st tested --gate "$T/g2" >/dev/null; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"\n".join("%s %s %s" % (r["id"], r.get("phase"), [t["verdict"] for t in r["tested"]["results"]]) for r in d)'
            st find --topic modules:Gridmod; echo "no phase set: rc=$?" ;;
  standins) echo '{"endpoints":[{"id":"pay","status":"MOCKED"},{"id":"mail","status":"MOCKED"}]}' > "$T/i1.json"
            echo '{"endpoints":[{"id":"pay","status":"MOCKED"},{"id":"maps","status":"UNKNOWN"}]}' > "$T/i2.json"
            UPG_PHASE=10.24.0 st standins --inventory "$T/i1.json"; UPG_PHASE=10.24.0 st standins --inventory "$T/i1.json"
            UPG_PHASE=11.12.7 st standins --inventory "$T/i2.json" --previous "$T/i1.json"; st show --json > "$T/s.json"
            fieldof "$T/s.json" '"\n".join("%s %s %s | %s" % (r["id"], r.get("phase"), r["approval"]["state"], r["found"]["say"]) for r in d)' ;;
  cockpit-ladder) mkdir -p "$W/state" "$W/rung2/state"; touch "$W/state/fetch.done"; touch "$W/rung2/state/fetch.done"
            echo '{"route":["9.24.2.1","10.24.13.1","11.12.7"]}' > "$W/ladder.json"
            gsum "$W" PASS; echo "Overall: **PASS**" >> "$W/gate-summary.md"
            echo '| 8 | journeys | PASS | 0 | journeys: 135 PASS, 2 FAIL, 38 INVALID;actions 258 found · 224 generated (22 todo) |' >> "$W/gate-summary.md"
            echo '{"rounds":[{"round":1,"new_heals":41,"rows":63},{"round":2,"new_heals":12,"rows":19}],"rows":[{"class":"real-regression"},{"class":"test-setup"}]}' > "$W/heal.json"
            python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import cockpitmatrix as m
for w in sys.argv[2:]:
    print("ladder", [(x["v"], x["state"]) for x in m.ladder(w)])
    print("health", [(h["v"], [r["fixed"] for r in h["rounds"]], h["paths"], h["actions"], h["real"]) for h in m.health(w)])' "$B" "$W" "$W/rung2"
            python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import cockpitmatrix as m; print("no ladder:", m.ladder(sys.argv[2]), m.h_ladder([]) == "")' "$B" "$T" ;;
  find-topic) mk; echo "found: $(st find --topic modules:Gridmod)"; st find --topic nothing; echo "rc=$?" ;;
  *) echo "unknown case $case_"; exit 64 ;;
esac
