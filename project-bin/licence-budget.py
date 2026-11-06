#!/usr/bin/env python3
"""licence-budget.py: gate before launching parallel test runs against a local Mendix app.

A local app without a licence (trial) allows 6 concurrent users and stops itself after a
random 2-4 hours ("LicenseService: Maximum run time exceeded"). Both look like test
failures when they hit: journeys go INVALID on "Maximum number of sessions exceeded!", or
die mid-run on a dead runtime. This gate checks both BEFORE the runs start.

Facts it fetches (no judgement beyond the arithmetic):
  - is the runtime on a trial licence      (runtime.log, since the last licence init)
  - seats in use right now                 (M2EE admin API runtime_statistics)
  - how long the runtime has been up       (runtime.log, last "Runtime successfully started")

Usage:
  licence-budget.py <project-root> --runs N [--seats-per-run 1] [--minutes 30]
                    [--cap 6] [--window 120]

  --runs           runs you are about to start in parallel
  --seats-per-run  logins one run holds at once (a journey = 1 persona = 1 seat)
  --minutes        how long the batch will take
  --cap            concurrent-user cap (Mendix docs: 6 for an unlicensed app)
  --window         minutes from start you can count on (docs: random 2-4 h, so 120)

Exit: 0 go, 1 no-go (prints the largest batch that fits / what to do), 2 cannot measure
(app not running, admin API unreachable): never treat 2 as a pass.
"""
import argparse, base64, datetime as dt, json, os, re, sys, urllib.request


def fail_measure(msg):
    print(f"CANNOT MEASURE: {msg}")
    print("  Not a pass. Start the app (or fix the admin API) and re-run the gate.")
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--runs", type=int, required=True)
    ap.add_argument("--seats-per-run", type=int, default=1)
    ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--cap", type=int, default=6)
    ap.add_argument("--window", type=float, default=120)
    a = ap.parse_args()

    mx = os.path.join(a.project, ".mxcli")
    try:
        local = json.load(open(os.path.join(mx, "run-local.json")))
    except OSError as e:
        fail_measure(f"no run-local.json in {mx} ({e.strerror}): app not started, or mid-restart")

    # Trial or licensed: read the licence block of the most recent start.
    trial = started = None
    try:
        log = open(os.path.join(mx, "runtime.log"), errors="replace").read()
        last = log.rfind("Initializing license subsystem")
        m = re.search(r"has concurrent user restrictions: (true|false)", log[last:] if last >= 0 else log)
        trial = m and m.group(1) == "true"
        st = re.findall(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ INFO - Core: Mendix Runtime successfully started",
                        log[last:] if last >= 0 else log, re.M)
        started = st and dt.datetime.strptime(st[-1], "%Y-%m-%d %H:%M:%S")
    except OSError:
        pass
    if trial is None:
        fail_measure("runtime.log has no licence block for the current start")
    if not started:
        fail_measure("runtime.log shows no completed start since the last licence init (still booting?)")

    # Seats in use now.
    auth = base64.b64encode(local["adminPass"].encode()).decode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{local['adminPort']}/",
        data=json.dumps({"action": "runtime_statistics", "params": {}}).encode(),
        headers={"Content-Type": "application/json", "X-M2EE-Authentication": auth})
    try:
        s = json.load(urllib.request.urlopen(req, timeout=5))["feedback"]["sessions"]
    except Exception as e:
        fail_measure(f"admin API on port {local['adminPort']} did not answer ({e})")
    live = s.get("named_user_sessions", 0) + s.get("anonymous_sessions", 0)

    up = (dt.datetime.now() - started).total_seconds() / 60  # log times are local
    left = a.window - up
    need = a.runs * a.seats_per_run
    name = os.path.basename(os.path.abspath(a.project))

    print(f"{name}: licence {'TRIAL' if trial else 'licensed'}, up {up:.0f} min, "
          f"seats in use {live}" + (f"/{a.cap}" if trial else ""))
    if not trial:
        print(f"GO: licensed runtime, no seat or run-time cap ({need} seats requested).")
        return 0

    ok = True
    if live + need > a.cap:
        ok = False
        fit = max(0, (a.cap - live) // a.seats_per_run)
        print(f"NO-GO seats: {a.runs} runs x {a.seats_per_run} = {need} + {live} in use = "
              f"{live + need} > cap {a.cap}. Largest batch that fits now: {fit}.")
        if live:
            print(f"  {live} seat(s) already held: a hung runner or a journey that did not log out. "
                  "Clear those first (sessions free on logout, timeout or restart).")
    else:
        print(f"ok seats: {live} + {need} = {live + need} of {a.cap}.")

    if a.minutes > left:
        ok = False
        print(f"NO-GO time: batch needs {a.minutes:.0f} min, only {max(left, 0):.0f} min left of the "
              f"{a.window:.0f}-min safe window (runtime stops at a random 2-4 h). "
              "Restart the app first for a fresh window, or split the batch.")
    else:
        print(f"ok time: {a.minutes:.0f} min fits in the {left:.0f} min left of the safe window.")

    print("GO" if ok else "NO-GO")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
