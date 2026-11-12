#!/usr/bin/env python3
"""Compare two snapshots (before / after an upgrade) and give each check a verdict: PASS, FAIL, INVALID or INFO.

  diff.py snap-before.json snap-after.json [--emit-allow noise.txt] [--allow allow.txt] [--log-allow log-allow.txt] [--md report.md] [--db-only]

--db-only compares the db rows alone: the mutant control (a db-only snapshot of an unstarted copy) then shows the planted
FAIL without http "endpoint not probed" and log rows next to it (E6-11, E7-18). System.User.Password and changedDate of
the local admin still differ when one side was started (runapp.py sets its password on start): expected, allow it.

Exit: 0 = nothing open, 1 = at least one FAIL or REVIEW, 2 = no FAIL/REVIEW but at least one INVALID or NEW_ENDPOINT.

Verdict rules (data-survival test: the after app was started on a COPY of the before database):
  db.entity     after count < before count                     FAIL (rows lost)
                entity gone from the after model                FAIL (table dropped or renamed)
  db.attribute  column gone, fewer non-null values, or values changed (md5)   FAIL
  db.assoc      fewer pairs or pairs changed, association gone  FAIL
  http          before 2xx and after not 2xx                    FAIL; before not 2xx: INVALID (baseline cannot judge)
                before 404 and after 2xx                        NEW_ENDPOINT (open until allow-listed: a new surface,
                                                                for example /rest-doc/<svc>/openapi.json on 9 -> 10)
                contract (swagger.json or openapi.json) lost an operation, a response code or a parameter, or got
                a new required parameter                                     FAIL; additions INFO
  db.identity   an old model GUID of that name is gone (same name, new GUID: dropped and re-created)   FAIL
                Compared as SETS per name: System.owner / System.changedBy have one row per entity, so a new
                entity adds a GUID without removing one (that is PASS).
  known.anonymous_users  (PLM-27) the Mx10 runtime deletes session-less Anonymous_* users at start. When both snapshots
                carry the "anonymous" section (snapshot.py records System.User, its attributes and role links for the NAMED
                users alone) the System.User rows are judged on named users, and the lost anonymous users are ONE row,
                PASS* "known platform behaviour", not 14 FAIL rows. Older snapshots: the FAIL rows say so.
  log           ERROR/CRITICAL signature that did not exist before           FAIL
  log.start     start window (logdiff.py): start failed or new ERROR          FAIL; after-startup INFO/WARNING line
                changed, new or gone, or a new WARNING                       REVIEW (accept in writing or fix)
  admin         after runtime not running                       INVALID for the whole run
  vacuous       before has 0 rows in all non-system entities   INVALID (nothing to survive)
New entities, attributes, endpoints and growth are INFO. Volatile System entities (sessions, tokens, queues) are INFO.

allow.txt: one line per accepted change: "<check pattern> [<detail pattern>] # reason". Both are fnmatch patterns; the
check pattern matches the check id, the optional detail pattern matches the row's detail text (the value), so an
acceptance can be narrower than a whole check ("db.attr.System.User.Password values changed (non-null 3 -> 3)").
A matching FAIL, REVIEW, INVALID or NEW_ENDPOINT becomes PASS* (accepted, reason printed). Use it for changes the
upgrade is SUPPOSED to make (a module that drops an entity by design), never to hide noise.
log-allow.txt: the logdiff.py allow file ("<signature pattern> # reason"), applied to the log.start rows, so a line
accepted once for logdiff is accepted here too and diff exits 0 with it (E4 23). A REVIEW row can also be accepted in
allow.txt ("log.start.CHANGED *MFA* # reason").
"""
import argparse, fnmatch, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logdiff  # noqa: E402

VOLATILE = ["System.Session", "System.XASInstance", "System.TokenInformation", "System.ScheduledEventInformation", "System.QueuedTask",
            "System.ProcessedQueueTask", "System.SynchronizationError*", "System.UserReportInfo", "System.Error*", "System.ClusterLock*",
            "System.HttpHeader", "System.HttpMessage", "System.HttpRequest", "System.HttpResponse", "System.ODataResponse", "System.Paging",
            "System.SoapFault", "System.WorkflowEndedUserTask*", "System.UnreferencedFile*"]


def volatile(name):
    return any(fnmatch.fnmatch(name, p) or fnmatch.fnmatch(name, p + ".*") for p in VOLATILE)


def _ops(c):
    """contract value per verb: old snapshots hold a list of response codes, new ones {responses, params}."""
    return c if isinstance(c, dict) else {"responses": c or [], "params": None}


def contract_diff(cb, ca):
    lost, gained = [], []
    for pp, ops in cb.items():
        for v, ob in ops.items():
            ob = _ops(ob)
            if pp not in ca or v not in ca[pp]:
                lost.append(f"{v.upper()} {pp} (operation)"); continue
            oa = _ops(ca[pp][v])
            lost += [f"{v.upper()} {pp} response {c}" for c in ob["responses"] if c not in oa["responses"]]
            if ob["params"] is not None and oa["params"] is not None:
                pb = {x.rsplit(":", 1)[0]: x for x in ob["params"]}; pa = {x.rsplit(":", 1)[0]: x for x in oa["params"]}
                lost += [f"{v.upper()} {pp} parameter {k}" for k in pb if k not in pa]
                lost += [f"{v.upper()} {pp} parameter {k} became required" for k in pa if k in pb and pa[k].endswith(":req") and not pb[k].endswith(":req")]
                lost += [f"{v.upper()} {pp} new required parameter {k}" for k in pa if k not in pb and pa[k].endswith(":req")]
                gained += [f"{v.upper()} {pp} optional parameter {k}" for k in pa if k not in pb and not pa[k].endswith(":req")]
    gained += [f"{v.upper()} {pp}" for pp, ops in ca.items() for v in ops if pp not in cb or v not in cb[pp]]
    return lost, gained


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before"); ap.add_argument("after")
    ap.add_argument("--allow"); ap.add_argument("--md")
    ap.add_argument("--log-allow", help="logdiff allow file for the log.start rows")
    ap.add_argument("--db-only", action="store_true",
                    help="compare the db section only (the mutant control: a db-only snapshot of a copy; E6-11, E7-18)")
    ap.add_argument("--emit-allow", dest="emit_allow",
                    help="the restart control (PV-7): write one allow.txt line per FAIL or REVIEW row of this diff, as start noise")
    a = ap.parse_args()
    B, A = json.load(open(a.before)), json.load(open(a.after))
    allow = []
    if a.allow:
        for l in open(a.allow):
            if l.strip() and not l.startswith("#"):
                pat, _, why = l.partition("#")
                cpat, _, dpat = pat.strip().partition(" ")
                allow.append((cpat, dpat.strip(), why.strip()))
    rows = []

    def add(check, verdict, detail):
        if verdict in ("FAIL", "REVIEW", "INVALID", "NEW_ENDPOINT"):
            for cpat, dpat, why in allow:
                if fnmatch.fnmatch(check, cpat) and (not dpat or fnmatch.fnmatch(detail, dpat)):
                    verdict, detail = "PASS*", f"{detail} (accepted: {why})"; break
        rows.append((verdict, check, detail))

    for side, s in (("before", B), ("after", A)):
        for f in s.get("faults", []): add(f"snapshot.{side}", "INVALID", f)

    st = ((A.get("admin") or {}).get("runtime_status") or {}).get("status")
    if A.get("admin") is not None and not a.db_only:
        add("admin.after_running", "PASS" if st == "running" else "INVALID", f"runtime_status={st}")
    vb = ((B.get("admin") or {}).get("about") or {}).get("version"); va = ((A.get("admin") or {}).get("about") or {}).get("version")
    add("admin.versions", "INFO", f"{vb} -> {va}")

    db_b, db_a = B.get("db"), A.get("db")
    anb, ana = ((db_b or {}).get("anonymous") or {}), ((db_a or {}).get("anonymous") or {})
    anon = bool(anb and ana)    # PLM-27: both snapshots know which System.User rows are anonymous
    hint = "" if anon else " (if these are Anonymous_* users the Mx10 runtime deletes at start, re-take both snapshots with this snapshot.py: it records named users apart and diff groups them)"
    if db_b and db_a:
        user_rows = sum(v or 0 for k, v in db_b["entities"].items() if not k.startswith("System."))
        if user_rows == 0: add("db.vacuous", "INVALID", "before snapshot has no rows outside System: the survival test proves nothing")
        for e, nb in sorted(db_b["entities"].items()):
            na = db_a["entities"].get(e, "missing")
            cid = f"db.entity.{e}"
            if e == "System.User" and anon and isinstance(nb, int) and isinstance(na, int):
                nb, na = anb["total"] - anb["users"], ana["total"] - ana["users"]
                lost = anb["users"] - ana["users"]
                if lost > 0:
                    rows.append(("PASS*", "db.known.anonymous_users",
                                 f"{lost} anonymous System.User rows gone ({anb['users']} -> {ana['users']}) with their attributes and role links: "
                                 f"known behaviour, the Mx10 runtime deletes session-less Anonymous_* users at start (accepted by rule)"))
                if na < nb: add(cid, "FAIL", f"named user rows {nb} -> {na}")
                else: add(cid, "PASS", f"named user rows {nb} -> {na}")
                continue
            if na == "missing": add(cid, "INFO" if volatile(e) or nb == 0 and e.startswith("System.") else "FAIL", f"{nb} rows before, entity not in after model")
            elif nb is None or na is None: add(cid, "INVALID", f"table missing: before={nb} after={na}")
            elif volatile(e): add(cid, "INFO", f"{nb} -> {na} (volatile)")
            elif na < nb: add(cid, "FAIL", f"rows {nb} -> {na}" + (hint if e == "System.User" else ""))
            elif nb == 0: add(cid, "INFO", f"0 -> {na} (no baseline data: survival not tested)")
            else: add(cid, "PASS", f"rows {nb} -> {na}")
        for e in sorted(set(db_a["entities"]) - set(db_b["entities"])): add(f"db.entity.{e}", "INFO", f"new entity, {db_a['entities'][e]} rows")
        for at, rb in sorted(db_b["attributes"].items()):
            ent = at.rsplit(".", 1)[0]
            if volatile(ent) or rb["nonnull"] == 0 and at in db_a["attributes"]: continue
            ra = db_a["attributes"].get(at); cid = f"db.attr.{at}"
            if anon and at in anb["attrs"] and at in ana["attrs"]:
                rb, ra = anb["attrs"][at], ana["attrs"][at]
                if rb["nonnull"] == 0: continue
            if ra is None: add(cid, "FAIL" if rb["nonnull"] else "INFO", f"column gone ({rb['nonnull']} non-null values before)")
            elif ra["nonnull"] < rb["nonnull"]: add(cid, "FAIL", f"non-null {rb['nonnull']} -> {ra['nonnull']}" + (" (named users)" if anon and at in anb["attrs"] else hint if at.startswith("System.User.") else ""))
            elif ra["md5"] != rb["md5"]: add(cid, "FAIL", f"values changed (non-null {rb['nonnull']} -> {ra['nonnull']})")
            else: add(cid, "PASS", f"{rb['nonnull']} values identical")
        for at in sorted(set(db_a["attributes"]) - set(db_b["attributes"])):
            add(f"db.attr.{at}", "INFO", f"new column, {db_a['attributes'][at]['nonnull']} non-null")
        for asn, rb in sorted(db_b["associations"].items()):
            ra = db_a["associations"].get(asn, "missing"); cid = f"db.assoc.{asn}"
            if rb is None: continue
            if anon and asn in anb["assoc"] and asn in ana["assoc"]:
                rb, ra = anb["assoc"][asn], ana["assoc"][asn]
            if asn.startswith("System.") and rb["pairs"] == 0: continue
            if ra == "missing" or ra is None: add(cid, "FAIL" if rb["pairs"] else "INFO", f"association gone ({rb['pairs']} pairs before)")
            elif ra["pairs"] < rb["pairs"]: add(cid, "FAIL", f"pairs {rb['pairs']} -> {ra['pairs']}")
            elif ra["md5"] != rb["md5"] and ra["pairs"] == rb["pairs"]: add(cid, "FAIL", "same pair count, different pairs")
            elif rb["pairs"] == 0: add(cid, "INFO", f"0 -> {ra['pairs']} (no baseline data)")
            else: add(cid, "PASS", f"pairs {rb['pairs']} -> {ra['pairs']}")
        ib, ia = db_b.get("idsets") or {}, db_a.get("idsets") or {}
        if not (ib and ia):  # older snapshots: one id per name
            ib = {k: [v] for k, v in (db_b.get("ids") or {}).items()}; ia = {k: [v] for k, v in (db_a.get("ids") or {}).items()}
        if ib and ia:  # identity check: works without any data, and explains silent drops
            for k in sorted(set(ib) & set(ia)):
                lost = sorted(set(ib[k]) - set(ia[k]))
                if lost:
                    new = sorted(set(ia[k]) - set(ib[k]))
                    add(f"db.identity.{k}", "FAIL", f"same name, model id gone ({', '.join(x[:8] for x in lost)} -> {', '.join(x[:8] for x in new) or 'none'}): the runtime dropped and re-created it, existing values or pairs are lost. Usual cause: a local edit to a Marketplace module re-applied after a module update")
                elif len(ib[k]) > 1 or len(ia[k]) > 1:
                    add(f"db.identity.{k}", "PASS", f"all {len(ib[k])} old ids present ({len(ia[k])} after)")
        elif ib or ia:
            add("db.identity", "INVALID", "model ids recorded on one side only (re-take the older snapshot with this snapshot.py)")
    else:
        add("db", "INVALID", "db section missing in one snapshot")

    if a.db_only:
        add("scope", "INFO", "--db-only: http, log and admin rows not compared")
        print("diff: --db-only: http, log and admin rows not compared")
        for k in ("http", "log"): B.pop(k, None); A.pop(k, None)
        A["log"] = {"errors": {}}; B["log"] = {"errors": {}}
    hb, ha = B.get("http") or {}, A.get("http") or {}
    for p, rb in sorted(hb.items()):
        ra = ha.get(p); cid = f"http.{p}"
        ok_b = rb.get("status") and 200 <= rb["status"] < 300
        if ra is None: add(cid, "FAIL" if ok_b else "INFO", "endpoint not probed/discovered after"); continue
        ok_a = ra.get("status") and 200 <= ra["status"] < 300
        if not ok_b:
            if rb.get("status") == 404 and ok_a:
                add(cid, "NEW_ENDPOINT", f"status 404 -> {ra['status']}: endpoint did not exist before"); continue
            add(cid, "INFO" if ra.get("status") == rb.get("status") else "INVALID", f"baseline status {rb.get('status')}, after {ra.get('status')}"); continue
        if not ok_a: add(cid, "FAIL", f"status {rb['status']} -> {ra.get('status')} {ra.get('error', '')}"); continue
        if "contract" in rb:
            lost, gained = contract_diff(rb["contract"], ra.get("contract", {}))
            if lost: add(cid, "FAIL", "contract lost: " + "; ".join(lost[:6]) + (f" (+{len(lost) - 6} more)" if len(lost) > 6 else ""))
            else: add(cid, "PASS", f"contract kept ({sum(len(o) for o in rb['contract'].values())} operations)" + (f"; added {gained[:6]}" if gained else ""))
        elif rb.get("shape") and ra.get("shape") != rb.get("shape"): add(cid, "FAIL", "JSON shape changed")
        else: add(cid, "PASS", f"status {rb['status']} -> {ra['status']}, {rb.get('bytes')} -> {ra.get('bytes')} bytes")
    for p in sorted(set(ha) - set(hb)): add(f"http.{p}", "INFO", f"new endpoint, status {ha[p].get('status')}")

    lb, la = (B.get("log") or {}).get("errors", {}), (A.get("log") or {}).get("errors", {})
    if A.get("log") is None: add("log", "INVALID", "no after log")
    for s in sorted(set(la) - set(lb)): add("log.new_error", "FAIL", f"{la[s]}x {s}")
    for s in sorted(set(lb) & set(la)): add("log.known_error", "INFO", f"also in baseline: {s}")
    for s in sorted(set(lb) - set(la)): add("log.error_gone", "INFO", s)
    sb, sa = (B.get("log") or {}).get("start"), (A.get("log") or {}).get("start")
    if sb and sa:
        lallow = []
        if a.log_allow:
            for line in open(a.log_allow):
                if line.strip() and not line.lstrip().startswith("#"):
                    pat, _, why = line.partition("#"); lallow.append((pat.strip(), why.strip() or "allowed"))
        lrows, _ = logdiff.compare(sb, B["log"].get("started"), sa, A["log"].get("started"), lallow,
                                   set(B["log"].get("error_sigs") or ()))
        for v, kind, sg, d in lrows:
            add(f"log.start.{kind}", v, f"{sg} {d}".strip())
    elif sb or sa:
        add("log.start", "INVALID", "start window recorded on one side only (re-take the older snapshot with this snapshot.py)")

    order = {"INVALID": 0, "FAIL": 1, "REVIEW": 2, "NEW_ENDPOINT": 3, "PASS*": 4, "PASS": 5, "INFO": 6}
    rows.sort(key=lambda r: (order[r[0]], r[1]))
    counts = {k: sum(1 for r in rows if r[0] == k) for k in order}
    head = f"# Upgrade regression diff: {B.get('label')} -> {A.get('label')}\n\n" + " | ".join(f"{k} {v}" for k, v in counts.items()) + "\n\n"
    table = "| verdict | check | detail |\n|---|---|---|\n" + "\n".join(f"| {v} | {c} | {d} |" for v, c, d in rows if v != "PASS" and v != "INFO") + "\n"
    table += f"\n{counts['PASS']} PASS and {counts['INFO']} INFO rows omitted from the table (in --md output only as counts).\n"
    if a.emit_allow:
        # NMR-1: a line is "check detail # why". A check id alone would accept EVERY later row of that check (one noise
        # error in log.new_error would accept a NullPointerException), so the detail of the noise row itself is the pattern.
        why = f"start noise: differs between two starts of the same old app ({B.get('label')} -> {A.get('label')})"
        noise, refused = [], 0
        for v, c, d in sorted({(v, c, d) for v, c, d in rows if v in ("FAIL", "REVIEW")}, key=lambda r: (r[1], r[2])):
            dpat = "".join("[" + ch + "]" if ch in "*?[" else "?" if ch in "#\r\n" else ch for ch in d.strip())
            if not dpat or " " in c:
                refused += 1; continue
            noise.append(f"{c} {dpat} # {why}\n")
        open(a.emit_allow, "w").write("".join(noise))
        print(f"--emit-allow: {len(noise)} check(s) written to {a.emit_allow}; read each one before the gate uses the file"
              + (f"; {refused} row(s) with no detail to match were NOT written (accept them by hand)" if refused else ""))
    if a.md:
        open(a.md, "w").write(head + table + "\n## All rows\n\n" + "\n".join(f"- {v} {c}: {d}" for v, c, d in rows) + "\n")
    print(head + table)
    sys.exit(1 if counts["FAIL"] or counts["REVIEW"] else 2 if counts["INVALID"] or counts["NEW_ENDPOINT"] else 0)


if __name__ == "__main__":
    main()
