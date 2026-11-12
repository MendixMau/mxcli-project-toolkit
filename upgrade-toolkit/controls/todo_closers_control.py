#!/usr/bin/env python3
"""todo_closers_control.py CASE: F23, gen_journeys.todo_closers on a fake model. Prints one line per todo:
"<todo id> <closing action id|OPEN>". Cases: base (pass), and mutants that must leave a todo OPEN:
  off-path     the task page is not on any walkable action's path
  clicked-ds   the 'data source' is in fact run by a button on the page whose own journey was skipped
  not-snippet  the microflow is referenced by a page that is NOT shown on the walked page (a popup it opens)"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin"))
import gen_journeys as G  # noqa: E402


class Doc:
    def __init__(self, type_):
        self.type = type_


class Model:
    def __init__(self, refs, types):
        self._refs, self.docs = refs, {q: Doc(t) for q, t in types.items()}

    def refs(self, q):
        return self._refs.get(q, [])


def main():
    case = sys.argv[1]
    types = {"M.Inbox": "Forms$Page", "M.Task": "Forms$Page", "M.Popup": "Forms$Page", "M.Comments": "Forms$Snippet",
             "M.DS_Task": "Microflows$Microflow", "M.DS_Owner": "Microflows$Microflow", "M.Complete": "Microflows$Microflow",
             "M.Assign": "Microflows$Microflow"}
    refs = {"M.Task": ["M.Comments", "M.DS_Task", "M.Complete", "M.Popup"], "M.Comments": ["M.DS_Owner"]}
    todo = [{"id": f"page:M.Task"}, {"id": "client_microflow:M.Complete"}, {"id": "client_microflow:M.DS_Task"},
            {"id": "client_microflow:M.DS_Owner"}]
    walk = {"id": "M.Task.btnComplete", "host": "M.Task", "host_type": "Page", "target": "M.Complete",
            "path": [{"page": "M.Inbox"}, {"click": "row"}, {"page": "M.Task"}]}
    every = [walk]
    if case == "off-path":
        walk["path"] = [{"page": "M.Inbox"}]; walk["host"] = "M.Inbox"
    elif case == "clicked-ds":  # a skipped combobox action on the task page runs DS_Task
        every = every + [{"id": "M.Task.combo1", "host": "M.Task", "host_type": "Page", "target": "M.DS_Task"}]
    elif case == "not-snippet":  # DS_Owner moves from the shown snippet to a popup page the task page only opens
        refs = {"M.Task": ["M.Comments", "M.DS_Task", "M.Complete", "M.Popup"], "M.Popup": ["M.DS_Owner"]}
    elif case != "base":
        sys.exit(f"unknown case {case}")
    got = G.todo_closers(todo, [walk], [Model(refs, types)], every)
    by = {t: a for a, ts in got.items() for t in ts}
    for e in todo:
        print(e["id"], by.get(e["id"], "OPEN"))


if __name__ == "__main__":
    main()
