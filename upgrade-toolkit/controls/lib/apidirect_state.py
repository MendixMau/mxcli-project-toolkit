#!/usr/bin/env python3
"""apidirect_state.py DIR VARIANT: a synthetic state folder for apidirect.py compare (calls-old/new.json, results-*.jsonl,
standin/requests.jsonl), no app and no model. Variants: pass, request, response, error, invalid, info.
Each variant has the call A.Get (a GET with a query and a header, a result object) and, where named, one more difference."""
import json, sys
from pathlib import Path

d, variant = Path(sys.argv[1]), sys.argv[2]
d.mkdir(parents=True, exist_ok=True)


def call(mf, eid, status="MOCKED", system="", reasons=()):
    return {"microflow": mf, "type": "Microflow", "excluded": False, "params": [{"kind": "string", "entity": "", "enum": "", "name": "Id"}],
            "returns": {"kind": "object", "entity": "A.Root", "enum": ""}, "reasons": list(reasons), "wrapper": "T_0001",
            "actions": [{"id": eid, "status": status, "system": system, "why": ""}]}


def calls(side):
    cs = [call("A.Get", "rest:A.Get")]
    if variant == "invalid":
        cs.append(call("A.Needs", "rest:A.Needs", reasons=["parameter X: entity System.HttpResponse is not in the model"]))
    if variant == "info":
        cs.append(call("A.Login", "rest:A.Login", status="EXCLUDED", system="IdP"))
    return {"side": side, "model": "x.mpr", "calls": cs}


def result(side, mode):
    if mode == "ok":
        v = "changed" if (variant == "response" and side == "new") else "same"
        return {"http": 200, "response": {"objects": [{"guid": "123456789012", "attributes": {"Name": {"value": v}}}]}}
    if mode == "500":
        if variant == "error" and side == "new":
            return {"http": 560, "response": {"type": "exception", "result": 560},
                    "log_error": "ERROR - MicroflowEngine: Call REST failed: 500 | at A.Get (Call REST service)"}
        return {"http": 200, "response": {"objects": []}}
    return {"http": 200, "response": {"objects": []}}


reqs = []
for side in ("old", "new"):
    (d / f"calls-{side}.json").write_text(json.dumps(calls(side)))
    with open(d / f"results-{side}.jsonl", "a" if False else "w") as f:
        for mode in ("ok", "500", "malformed"):
            r = result(side, mode)
            r.update(call="A.Get", wrapper="T_0001", side=side, mode=mode, ms=5)
            f.write(json.dumps(r) + "\n")
            q = "id=1" if not (variant == "request" and side == "new") else "id=2"
            reqs.append({"call": "A.Get", "side": side, "mode": mode, "endpoint": "rest:A.Get", "method": "GET", "path": "/c/A.Host/items",
                         "query": q, "headers": {"accept": "application/json", "authorization": "Bearer <redacted>"}, "body": "",
                         "t": "2026-01-01T00:00:00Z"})
(d / "standin").mkdir(exist_ok=True)
(d / "standin" / "requests.jsonl").write_text("".join(json.dumps(r) + "\n" for r in reqs))
