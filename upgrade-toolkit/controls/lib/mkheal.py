#!/usr/bin/env python3
"""mkheal.py DIR: a synthetic work folder for the heal.py controls (no app, no docker, no customer data).
One failing row per heal class: see the ids in the controls (heal-*) in run-controls.sh."""
import json, os, sys

W = sys.argv[1]


def put(rel, text):
    p = os.path.join(W, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(text if isinstance(text, str) else json.dumps(text, indent=1))


put("diff.md", "# diff\n\n## All rows\n"
    "- FAIL Shop.Item.changedDate: 3 rows differ\n"
    "- FAIL Shop.Order.total: 5 -> 4 rows\n"
    "- FAIL Shop.Customer.name: 2 rows differ\n"
    "- REVIEW log.start.NEW_WARNING: WARNING Configuration: Using derived value for SessionKeepAliveUpdatesInterval (SessionTimeout 30000)\n"
    "- REVIEW log.start.NEW_ERROR: ERROR Shop failed to start the queue\n"
    "- REVIEW log.start.NEW_WARNING: WARNING Something else changed\n"
    "- PASS Shop.Other: same\n")
put("twin-old.md", "# twin\n\n## All rows\n- FAIL Shop.Item.changedDate: 3 rows differ\n")
J = {
    "j-gated": {"verdict": "FAIL", "not_pass": ['FAIL open Shop.Overview: reached "buttonEdit" never appeared'], "shots": []},
    "j-empty": {"verdict": "FAIL", "not_pass": ['FAIL open Shop.Empty: reached "btnX" never appeared'], "shots": ["j-empty-step2-NOT-REACHED.png"]},
    "j-flake": {"verdict": "INVALID", "why": "runner did not run: the role pass wrote no findings"},
    "j-outside": {"verdict": "INVALID", "why": "external-call only: calls https://erp.example.test"},
    "j-nopath": {"verdict": "INVALID", "why": "no-click-path: no menu item reaches it"},
    "j-regress": {"verdict": "FAIL", "not_pass": ["FAIL open Shop.Home: the title changed"]},
    "j-both": {"verdict": "FAIL", "not_pass": ["FAIL open Shop.Home2: the title changed"]},
    "j-fine": {"verdict": "PASS"},
}
B = {"j-gated": {"verdict": "FAIL"}, "j-empty": {"verdict": "FAIL"}, "j-flake": {"verdict": "PASS"}, "j-regress": {"verdict": "PASS"},
     "j-both": {"verdict": "FAIL"}, "j-fine": {"verdict": "PASS"}}
put("e2e-after/after/summary.json", {"journeys": J, "journey_set": "x"})
put("e2e-before-picked/before-picked/summary.json", {"journeys": B, "journey_set": "x"})
put("e2e-after/j-empty-step2-NOT-REACHED.txt", "Shop Empty\nNo items found\n")
put("actions.json", {"actions": [{"id": "Shop.Overview.buttonEdit", "shown_if": ["$currentObject/Shop.Item_Cat != empty"]},
                                 {"id": "Shop.Empty.btnX", "shown_if": []}]})
put("heal-grids.json", {"Shop.Overview": {"grid": "itemGrid", "entity": "Shop.Item"}, "Shop.Empty": {"grid": "emptyGrid", "entity": "Shop.Thing"}})
put("journeys/journeys/Admin/j-gated.journey.json", {"id": "j-gated", "steps": [
    {"name": "open Shop.Overview", "ui": {"ready": ".mx-name-buttonEdit"}, "actions": [{"do": "fill", "widget": "search", "value": "a"}]},
    {"name": "click buttonEdit", "actions": [{"do": "click", "widget": "buttonEdit"}]}]})
