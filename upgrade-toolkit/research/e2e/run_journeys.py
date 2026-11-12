#!/usr/bin/env python3
"""Run generated journeys with the shared journey-runner.js, once per role, and summarise per journey.

    run_journeys.py <gen-dir> --label NAME --port 8680 --admin-port 8690 --admin-pass PASS \
                    --users users.json --work DIR [--positive-control]

users.json (local, never committed): {"<Role>": {"user": "...", "pass": "..."}, "_mfa": {"user": "...", "pass": "..."}}

The engine (journey-runner.js and what it requires) is COPIED from the shared toolkit into
<work>/engine; the toolkit itself is only read. A small project.config.js is written next to it.
journey-runner.js logs in once per invocation as TEST_USER, so each role folder is one invocation.
FALLBACK_USER is set empty: a run that cannot log in as the role is a FAIL/INVALID, never an admin run.

Exit 0 only when every journey is PASS. Output: <work>/<label>/summary.json and one findings file per role.
"""
import argparse, json, os, shutil, subprocess, sys, time
from pathlib import Path

TOOLKIT_E2E = Path(os.environ.get("TOOLKIT_E2E", "~/Mendix/mxcli-project-toolkit/project-tests/e2e")).expanduser()
ENGINE = ["journey-runner.js", "helpers.js", "config.js", "otel.js"]
NODE_PATH = os.environ.get("PLAYWRIGHT_NODE_PATH", str(Path("~/mendix-playwright/node_modules").expanduser()))

PROJECT_CONFIG = """'use strict';
// Written by run_journeys.py: the minimum journey-runner.js needs. Credentials come from env per role.
const path = require('path');
module.exports = {
  root: %(root)s,
  mpr: null,
  mxcli: process.env.MXCLI || 'mxcli',
  dsCss: null,
  defaultPort: %(port)s,
  // helpers.loginOnce waits for one of these after submitting. They must NOT match the login page or the
  // guest home: on E1 the anonymous home is a Mendix page, so '.mx-page' resolved before the login request
  // finished, the runner reported "login PASS" and the next page.goto aborted the login (measured).
  readySelectors: (process.env.READY_SELECTORS || '.mx-navigationtree,.mx-navbar').split(','),
  NAV: {},
  TARGETS: { 'full-app': [] },
  credentials: () => ({ user: process.env.TEST_USER, pass: process.env.TEST_PASS,
                        fallbackUser: process.env.FALLBACK_USER ?? '', fallbackPass: process.env.FALLBACK_PASS ?? '' }),
};
"""


def verdict(vs):
    return "FAIL" if "FAIL" in vs else "INVALID" if "INVALID" in vs or not vs else "PASS"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gen_dir")
    ap.add_argument("--label", required=True)
    ap.add_argument("--port", required=True)
    ap.add_argument("--admin-port", required=True)
    ap.add_argument("--admin-pass", required=True)
    ap.add_argument("--users", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--positive-control", action="store_true")
    ap.add_argument("--only", help="comma list of journey ids")
    ap.add_argument("--pause", type=int, default=0,
                    help="seconds to wait between role runs, so expired sessions are freed on a trial runtime (6 session cap)")
    a = ap.parse_args()

    users = json.load(open(a.users))
    work = Path(a.work).expanduser()
    eng = work / "engine"
    eng.mkdir(parents=True, exist_ok=True)
    for f in ENGINE:
        shutil.copy2(TOOLKIT_E2E / f, eng / f)
    # ENGINE PATCH (proposed upstream; the toolkit copy is never edited): the runner's `fill` looks for an
    # input INSIDE .mx-name-<w>. Mendix login widgets (LoginIdTextBox, PasswordTextBox) render the <input>
    # itself with that class, so a journey could not type into a model login page (measured on E1).
    jr = (eng / "journey-runner.js").read_text()
    old = "page.locator(`.mx-name-${a.widget} input, .mx-name-${a.widget} textarea`)"
    if old in jr:
        jr = jr.replace(old, "page.locator(`.mx-name-${a.widget} input, .mx-name-${a.widget} textarea, input.mx-name-${a.widget}`)")
        (eng / "journey-runner.js").write_text(jr)
        patches = ["fill: also input.mx-name-<widget> (login widgets)"]
    else:
        patches = ["fill patch NOT applied: runner text changed upstream; check whether it is still needed"]
    (eng / "project.config.js").write_text(PROJECT_CONFIG % {"root": json.dumps(str(work)), "port": json.dumps(str(a.port))})
    out = work / a.label
    out.mkdir(parents=True, exist_ok=True)
    only = set(a.only.split(",")) if a.only else None

    summary = {"label": a.label, "port": a.port, "engine_patches": patches, "roles": {}, "journeys": {}}
    for role_dir in sorted((Path(a.gen_dir) / "journeys").iterdir()):
        role = role_dir.name
        files = sorted(role_dir.glob("*.journey.json"))
        if only:
            files = [f for f in files if json.load(open(f))["id"] in only]
        if not files:
            continue
        cred = users.get(role)
        if not cred:
            for f in files:
                summary["journeys"][json.load(open(f))["id"]] = {"role": role, "verdict": "INVALID", "why": "no test user for role"}
            continue
        run = out / f"run-{role}"
        if run.exists():
            shutil.rmtree(run)
        run.mkdir()
        mfa = users.get("_mfa", {})
        for f in files:  # run copy with the MFA placeholders filled in; the generated file keeps none
            t = f.read_text().replace("${MFA_USER}", mfa.get("user", "")).replace("${MFA_PASS}", mfa.get("pass", ""))
            (run / f.name).write_text(t)
        ready = ".mx-navigationtree,.mx-navbar"
        lj = role_dir / f"login-{role}.journey.json"
        if lj.exists():
            ready = json.load(open(lj))["steps"][0]["ui"].get("ready") or ready
        env = dict(os.environ, READY_SELECTORS=ready, APP_PORT=str(a.port), M2EE_ADMIN_PORT=str(a.admin_port), M2EE_ADMIN_PASS=a.admin_pass,
                   TEST_USER=cred["user"], TEST_PASS=cred["pass"], FALLBACK_USER="", NODE_PATH=NODE_PATH,
                   MXCLI=os.environ.get("MXCLI", str(Path("~/.local/bin/mxcli").expanduser())))
        art = eng / "artifacts"
        if art.exists():
            shutil.rmtree(art)
        cmd = ["node", str(eng / "journey-runner.js"), *map(str, sorted(run.glob("*.journey.json")))]
        if a.positive_control:
            cmd.append("--positive-control")
        if a.pause and summary["roles"]:
            time.sleep(a.pause)
        p = subprocess.run(cmd, env=env, cwd=str(eng), capture_output=True, text=True)
        (out / f"{role}.log").write_text(p.stdout + "\n--- stderr\n" + p.stderr)
        name = "journey-findings-control.json" if a.positive_control else "journey-findings.json"
        fj = art / name
        if not fj.exists():
            summary["roles"][role] = {"exit": p.returncode, "login": "INVALID", "why": "runner wrote no findings; see log"}
            for f in files:
                summary["journeys"][json.load(open(f))["id"]] = {"role": role, "verdict": "INVALID", "why": "runner did not run"}
            continue
        shutil.copy2(fj, out / f"{role}-{name}")
        shots = out / f"shots-{role}"
        if shots.exists():
            shutil.rmtree(shots)
        shutil.copytree(art, shots, ignore=shutil.ignore_patterns("*.json"))
        F = json.load(open(fj))
        login = next((r for r in F["results"] if r["rung"] == "ui" and r["name"] == "login"), None)
        summary["roles"][role] = {"exit": p.returncode, "user": cred["user"], "login": login["verdict"] if login else "INVALID",
                                  "login_detail": login["detail"] if login else ""}
        if a.positive_control:
            ctl = [r for r in F["results"] if r["rung"] == "control"]
            summary["roles"][role]["control"] = {v: sum(1 for r in ctl if r["verdict"] == v) for v in ("PASS", "FAIL", "INVALID")}
            summary["roles"][role]["control_rows"] = [f"{r['verdict']} {r['name']}" for r in ctl]
            continue
        walked = {w["journey"]: w for w in F.get("walks", [])}
        for f in files:
            jid = json.load(open(f))["id"]
            w = walked.get(jid)
            if login is None or login["verdict"] != "PASS":
                summary["journeys"][jid] = {"role": role, "verdict": "INVALID" if not login or login["verdict"] == "INVALID" else "FAIL",
                                            "why": f"login {login['verdict'] if login else 'missing'}: {login['detail'] if login else ''}"}
                continue
            if not w:
                summary["journeys"][jid] = {"role": role, "verdict": "INVALID", "why": "journey not walked (seed or earlier fault)"}
                seed = [r for r in F["results"] if r["name"].startswith(f"{jid}: seeds")]
                if seed:
                    summary["journeys"][jid]["why"] = seed[0]["detail"]
                continue
            checks = [c for s in w["steps"] for c in s["checks"]]
            failed = [f"{c['verdict']} {c['name']} {c['detail']}".strip() for c in checks if c["verdict"] != "PASS"]
            # a journey whose last step never ran is not a PASS even if every recorded check passed
            complete = len(w["steps"]) == len(json.load(open(f))["steps"])
            v = verdict([c["verdict"] for c in checks] + ([] if complete else ["INVALID"]))
            summary["journeys"][jid] = {"role": role, "verdict": v, "checks": len(checks), "not_pass": failed[:6],
                                        "shots": [s["shot"]["file"] for s in w["steps"] if s.get("shot")]}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"== {a.label} (:{a.port})")
    for r, s in summary["roles"].items():
        print(f"  role {r:24} login {s['login']:7} {s.get('login_detail', '')[:60]}" + (f"  control {s['control']}" if "control" in s else ""))
    for j, s in summary["journeys"].items():
        print(f"  {s['verdict']:7} {j:55} {('; '.join(s.get('not_pass', [])) or s.get('why', ''))[:150]}")
    bad = [s for s in summary["journeys"].values() if s["verdict"] != "PASS"]
    bad += [s for s in summary["roles"].values() if s.get("control", {}).get("FAIL") or s.get("control", {}).get("INVALID")]
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
