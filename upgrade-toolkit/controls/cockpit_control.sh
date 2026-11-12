#!/bin/bash
# cockpit_control.sh CASE: controls for bin/cockpitpage.py and bin/decisions.py on fixtures/cockpit (a made-up shop app).
# Builds a throwaway copy with an app git repo, then runs one case and prints what it saw.
set -u
here=$(cd "$(dirname "$0")" && pwd); B=$(cd "$here/.." && pwd)/bin
case_=$1; T=${TMPDIR:-/tmp}/cockpit-ctl.$$; trap 'rm -rf "$T"' EXIT
mkdir -p "$T"; cp -R "$here/fixtures/cockpit/run" "$T/run"; W=$T/run/work
mkdir -p "$T/run/app"; (cd "$T/run/app" && git init -q && git config user.email t@t && git config user.name t \
  && for m in "original" "step: Widgetpack 2.0.0 (stepupdate, idcheck PASS)" "convert 11.1.0" "repair D2: remove the feedback button (VISIBLE UI change)" "build: regenerated stubs"; do
       echo "$m" >> f.txt; git add f.txt; git commit -q -m "$m"; done)
HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cnt() { grep -c "$@" || true; }
ck() { python3 "$B/cockpitpage.py" --work "$W" --out "$T/out.html"; }
dec() { python3 "$B/decisions.py" "$@" --work "$W"; }
st() { python3 "$B/steps.py" "$@" --work "$W"; }
# three steps on the shop fixture: S-1 is P-1 (Gridmod), S-2 is P-2, S-3 has no P-n alias
mkst() {
  st open --topic module:Gridmod --title "Gridmod grid module" --say "A grid module has local edits." --alias P-1 >/dev/null
  st open --topic theme:Themepack --title "Themepack styles" --say "The theme package has local edits." --alias P-2 >/dev/null
  st open --topic change:overlay --title "Checkout overlay" --say "A layer covers the checkout button." >/dev/null
}
stapp() { st show "$1" --json | python3 -c 'import json,sys; a=json.load(sys.stdin)[0].get("approval") or {}; print(a.get("state","none"), "by", a.get("by","-"), "via", a.get("source","-"))'; }
nev() { grep -c "\"id\": \"$1\", \"field\": \"approval\"" "$W/steps.jsonl" || true; }
case $case_ in
  confirm-covered) mkst; st propose --id S-1 --say "Update the grid." --decision D3 >/dev/null
            printf 'D3: Gridmod 2.0.0 rework, please confirm it looks right. D9: Cart banner moved, please confirm.\n' > "$W/gate-notes.txt"
            python3 - "$B" "$W" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
import cockpitpage as cp
m = cp.build_model(sys.argv[2])
print("confirm items:", sorted(i["id"] for i in m["items"] if i["id"].startswith("confirm")))
PY
            ;;
  confirm-all-covered) mkst; st propose --id S-1 --say "Update the grid." --decision D3 >/dev/null
            printf 'D3: Gridmod 2.0.0 rework, please confirm it looks right.\n' > "$W/gate-notes.txt"
            python3 - "$B" "$W" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
import cockpitpage as cp
m = cp.build_model(sys.argv[2])
print("confirm items:", sorted(i["id"] for i in m["items"] if i["id"].startswith("confirm")))
PY
            ;;
  step-add)   mkst; dec add --item S-3 --choice approve --by Ana --source chat; echo "S-3: $(stapp S-3)"; echo "approval events: $(nev S-3)" ;;
  step-reject) mkst; dec add --item S-3 --choice reject --by Ana --source chat >/dev/null; echo "S-3: $(stapp S-3)"
            dec add --item S-3 --choice approve --by Ben --source chat >/dev/null; echo "S-3 later: $(stapp S-3)"; echo "approval events: $(nev S-3)" ;;
  step-alias-import) mkst; echo '{"decisions":[{"item":"P-1","choice":"o2","by":"u_1","at":"2026-01-02T00:00:00Z","source":"page"},{"item":"S-3","choice":"reject","by":"u_1","at":"2026-01-02T00:00:00Z","source":"page"}],"signoffs":[]}' > "$T/e.json"
            echo '{"u_1":"Cleo"}' > "$T/n.json"; dec import --json "$T/e.json" --names "$T/n.json"; echo "S-1: $(stapp S-1)"; echo "S-3: $(stapp S-3)"
            cp "$W/steps.jsonl" "$T/before"; dec import --json "$T/e.json" --names "$T/n.json"; cmp "$T/before" "$W/steps.jsonl" && echo "steps file unchanged by the second import"
            echo "ledger rows: $(grep -c '"item"' "$W/decisions.json")"; echo "S-2: $(stapp S-2)" ;;
  step-assumed-yields) mkst; st approve --id S-3 --state assumed --by agent --source unattended >/dev/null; dec add --item S-3 --choice approve --by Ana --source page; echo "S-3: $(stapp S-3)" ;;
  step-unknown) mkst; dec add --item S-9 --choice approve --by Ana --source chat; echo "rc=$?"; test ! -f "$W/decisions.json" && echo "ledger untouched" ;;
  step-bad-choice) mkst; dec add --item S-3 --choice o1 --by Ana --source chat; echo "rc=$?"; echo "S-3: $(stapp S-3)" ;;
  step-signoff-refused) mkst; cp "$W/steps.jsonl" "$T/before"; dec add --item signoff --choice sign --by Ana --source chat; echo "rc=$?"
            cmp "$T/before" "$W/steps.jsonl" && echo "steps untouched"; test ! -f "$W/decisions.json" && echo "ledger untouched" ;;
  step-apply) mkst; dec add --item S-3 --choice approve --by Ana --source chat >/dev/null; dec apply; echo "S-3: $(stapp S-3)"; echo "approvals after apply: $(nev S-3)" ;;
  render)   ck && cat "$T/out.html" ;;
  nodoc)    ck >/dev/null && head -c 400 "$T/out.html"; echo; ! grep -Eqi '<(!doctype|html|head|body)[ >]' "$T/out.html" && echo "no page skeleton tags" ;;
  nohard)   ck >/dev/null; ! grep -Eq 'HTMLSnippet|run2' "$T/out.html" && echo "no hard-coded run names" ;;
  pattern)  ck >/dev/null; for p in 'claude.use\("db"\)' 'claude.use\("user"\)' 'collection\("decisions"\).doc\(it.id\).set' 'collection\("signoffs"\).doc\(await user.id\(\)\).set' 'collection\("decisions"\).onSnapshot'; do grep -Eq "$p" "$T/out.html" && echo "has $p" | tr -d '\\'; done; ! grep -q 'window.claude.db' "$T/out.html" && echo "never reads window.claude.db" ;;
  add)      dec add --item P-1 --choice o2 --by Ana --source chat && dec add --item P-1 --choice rec --by Ben --source chat && cat "$W/decisions.json" ;;
  add-bad)  dec add --item nope --choice x --by Ana --source chat ;;
  signoff-chat) dec add --item signoff --choice sign --by Ana --source chat; echo "rc=$?"; test ! -f "$W/decisions.json" && echo "ledger untouched" ;;
  signoff-chat-apply) dec add --item signoff --choice sign --by Ana --source chat >/dev/null 2>&1; dec apply; cnt '^Signed-off:' "$W/PROPOSAL.md" ;;
  import)   echo '{"decisions":[{"item":"regression:overlay","choice":"accept","by":"u_1","at":"2026-01-02T00:00:00Z","source":"page"}],"signoffs":[]}' > "$T/e.json"
            echo '{"u_1":"Cleo"}' > "$T/n.json"; dec import --json "$T/e.json" --names "$T/n.json" && dec import --json "$T/e.json" --names "$T/n.json" && cat "$W/decisions.json" ;;
  apply)    dec add --item P-1 --choice o2 --by Ana --source chat >/dev/null; dec add --item regression:overlay --choice accept --by Ana --source chat --reason "intended" >/dev/null
            dec apply; echo ---; grep '^P-1' "$W/DECISIONS.md"; cat "$W/regression-decisions.txt" ;;
  apply-idem) dec add --item regression:overlay --choice accept --by Ana --source chat >/dev/null; dec apply >/dev/null; cp "$W/regression-decisions.txt" "$T/a"; dec apply >/dev/null; cmp "$T/a" "$W/regression-decisions.txt" && echo "same after second apply"; cnt 'item:regression:overlay' "$W/regression-decisions.txt" ;;
  apply-change) dec add --item regression:overlay --choice accept --by Ana --source chat >/dev/null; dec apply >/dev/null; dec add --item regression:overlay --choice fix --by Ana --source chat >/dev/null; dec apply >/dev/null; cnt 'Shop.Home' "$W/regression-decisions.txt" ;;
  signoff-page) echo "{\"signoffs\":[{\"id\":\"u_1\",\"plan\":\"$HASH\",\"at\":\"2026-01-03T08:00:00Z\",\"source\":\"page\"}]}" > "$T/e.json"; echo '{"u_1":"Cleo Vos"}' > "$T/n.json"
            dec import --json "$T/e.json" --names "$T/n.json" >/dev/null; dec apply; dec apply >/dev/null; grep '^Signed-off:' "$W/PROPOSAL.md"; cnt '^Signed-off:' "$W/PROPOSAL.md"; python3 "$B/proposal.py" --status --work "$W" ;;
  signoff-stale) echo '{"signoffs":[{"id":"u_1","plan":"bbbb","at":"2026-01-03T08:00:00Z","source":"page"}]}' > "$T/e.json"; echo '{"u_1":"Cleo"}' > "$T/n.json"
            dec import --json "$T/e.json" --names "$T/n.json" >/dev/null; dec apply; cnt '^Signed-off:' "$W/PROPOSAL.md" ;;
  signoff-noname) echo "{\"signoffs\":[{\"id\":\"u_1\",\"plan\":\"$HASH\",\"at\":\"2026-01-03T08:00:00Z\",\"source\":\"page\"}]}" > "$T/e.json"
            dec import --json "$T/e.json" >/dev/null; dec apply; cnt '^Signed-off:' "$W/PROPOSAL.md" ;;
  signoff-import-chat) echo "{\"signoffs\":[{\"id\":\"u_1\",\"plan\":\"$HASH\",\"at\":\"2026-01-03T08:00:00Z\",\"source\":\"chat\"}]}" > "$T/e.json"
            dec import --json "$T/e.json" --names <(echo '{"u_1":"Cleo"}'); dec apply; cnt '^Signed-off:' "$W/PROPOSAL.md" ;;
  words)    ck >/dev/null; echo "plural-marker count: $(cnt '(s)' "$T/out.html")"; echo "raw gate text count: $(cnt -E '(PASS|FAIL|INVALID|REVIEW|SKIPPED)\*? [0-9]|[0-9] (PASS|FAIL|INVALID|SKIPPED)\b|PASS\* [0-9]' "$T/out.html")"; echo "one thing: $(python3 - "$T/out.html" <<'PY'
import re,sys,json
t=open(sys.argv[1]).read()
d=json.loads(re.search(r"const D=(.*?);\n", t, re.S).group(1))
print(d['state']['text'])
PY
)" ;;
  pending)  dec pending ;;
  pending-after) dec add --item P-2 --choice rec --by Ana --source chat >/dev/null; dec pending ;;
  signed-page) echo "{\"signoffs\":[{\"id\":\"u_1\",\"plan\":\"$HASH\",\"at\":\"2026-01-03T08:00:00Z\",\"source\":\"page\"}]}" > "$T/e.json"; echo '{"u_1":"Cleo"}' > "$T/n.json"
            dec import --json "$T/e.json" --names "$T/n.json" >/dev/null; dec apply >/dev/null; ck >/dev/null; python3 - "$T/out.html" <<'PY'
import re,sys,json
d=json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1))
print(sum(1 for i in d["items"] if i["id"]=="signoff"))
PY
;;
  cockpit-flag) cp -R "$here/fixtures/cockpit/run" "$T/r2"; bash "$B/cloud/upgrade-pipeline.sh" --cockpit --work "$T/r2/work" && test -s "$T/r2/work/COCKPIT.html" && echo "COCKPIT.html written" ;;
  matrix-*) # the matrix page: read the embedded data with a small python helper, print what it saw
            mx() { python3 - "$@" <<'PY'
import re,sys,json
t=open(sys.argv[1]).read()
D=json.loads(re.search(r"const D=(.*?);\n", t, re.S).group(1)); M=D["matrix"]
case=sys.argv[2]; ST=("triage","plan","upgrade","test")
cells=[c for r in M["rows"] for c in r["cells"].values()]
if case=="missing-empty":
    print("cells:", len(cells), "ok cells:", sum(1 for c in cells if c["s"]=="ok"), "chips ok:", sum(1 for c in M["ready"] if c["s"]=="ok"))
elif case=="missing-gate":
    print("runtime test cell:", M["rows"][0]["cells"]["test"]["s"], M["rows"][0]["cells"]["test"]["l"])
elif case=="tiles":
    rows=M["rows"]; up=[r for r in rows if r["group"]!="golive" and r["cells"]["upgrade"]["s"]!="none"]
    t=[r for r in rows if r["cells"]["test"]["s"]!="none"]
    you=sum(1 for r in rows for k in ST if r["cells"][k]["s"]=="you")
    T=M["tiles"]
    ok=(T["up"]==[sum(1 for r in up if r["cells"]["upgrade"]["s"]=="ok"),len(up)] and T["you"]==you
        and T["tested"][0]==sum(1 for r in t if r["cells"]["test"]["s"]=="ok")
        and sum(T["tested"])==len(t) and T["reg"]==sum(1 for r in rows if r["regression"]))
    print("tiles match rows" if ok else "TILES DIFFER", T["up"], T["reg"], T["upg"], T["gap"], T["own"], T["gol"], T["tested"], T["you"])
elif case=="kinds":
    K=("upgrade","testgap","owner","golive"); by={r["id"]:r["kind"] for r in M["rows"]}; T=M["tiles"]
    print("every row and chip has a kind:", all(r.get("kind") in K for r in M["rows"]+M["ready"]))
    print("kinds:", {i: by[i] for i in ("regression:overlay","confirm:D2","signoff","payment-gateway") if i in by})
    print("tiles:", T["upg"], T["gap"], T["own"], T["gol"], "no old prob tile:", "prob" not in T)
    print("tile buttons:", sum(1 for k in K if 'data-kind="%s"'%k in t or "KT(\"%s\""%k in t))
elif case=="noprop":
    bad=[r["name"] for r in M["rows"] if any(c["s"] in ("wait","bad") for c in r["cells"].values()) and not r["fix"]]
    print("non-green rows without proposal:", len(bad)); print("literal in page:", "No proposal yet" in t)
elif case=="merge":
    r=next(x for x in M["rows"] if x["id"]=="regression:overlay"); p=next(x for x in M["rows"] if x["id"]=="payment-gateway")
    print("proposal:", r["fix"]["proposal"]); print("loop:", r["fix"]["loop"]); print("new row group:", p["group"], "late:", p["cells"]["triage"]["late"], "deploy:", p["cells"]["test"]["deploy"])
    b=next(c for c in M["ready"] if c["id"]=="broker"); f=next(c for c in M["ready"] if c["id"]=="files")
    print("chip:", b["s"], b["l"], "|", b["fix"]["proposal"]); print("chip row link:", f["row"], f["s"])
    print("feed:", M["feed"][0]["text"] if any(x["text"]=="Test broker started" for x in M["feed"]) else "missing")
elif case=="stale":
    ov=next(r for r in M["rows"] if r["id"]=="regression:overlay")
    print("regressions tile:", M["tiles"]["reg"]); print("overlay test cell:", ov["cells"]["test"]["s"], ov["cells"]["test"]["l"])
    print("purple regression cells:", sum(1 for r in M["rows"] if r["id"].startswith("regression:") for c in r["cells"].values() if c["s"]=="you"))
    print("triage outline on late find:", ov["cells"]["triage"]["late"], ov["cells"]["triage"]["l"])
elif case=="seen":
    ov=next(r for r in M["rows"] if r["id"]=="regression:overlay")
    print("triage:", ov["cells"]["triage"]["l"], ov["cells"]["triage"]["late"]); print("plan:", ov["cells"]["plan"]["l"], ov["cells"]["plan"]["late"])
elif case=="openreg":
    rr=[r for r in M["rows"] if r["regression"]]
    print("regressions tile:", M["tiles"]["reg"]); print("red regression rows:", len(rr), [r["cells"]["test"]["s"] for r in rr], [bool(r["fix"] and r["fix"]["proposal"]) for r in rr])
    print("stale heal rows still red:", sum(1 for r in M["rows"] if r["id"]=="regression:overlay" and r["cells"]["test"]["s"]!="ok"))
elif case=="judg":
    print("judgment rows:", sum(1 for r in M["rows"] if r["id"].startswith("judgment:") or r["name"].startswith("How do you")))
    print("purple judgment cells:", sum(1 for r in M["rows"] for c in r["cells"].values() if (c.get("dec") or "").startswith("judgment:") and c["s"]=="you"))
    print("closed in feed:", any(f["text"].startswith("Question closed") for f in M["feed"]))
elif case=="oneRow":
    print("rows named Overlay:", sum(1 for r in M["rows"] if "overlay" in r["id"].lower() or "overlay" in r["name"].lower()))
    ids=[r["id"] for r in M["rows"]]; print("order:", [i for i in ids if i in ("payment-gateway","gift-wrap")])
elif case=="chips":
    print("chips:", len(M["ready"]), [c["id"] for c in M["ready"]]); print("grey chips:", sum(1 for c in M["ready"] if c["s"]=="none"))
    print("clickable when not ok:", "data-ready" in t and "c.s===\"ok\"?" in t)
elif case=="you":
    items=[i for i in D["items"] if not i.get("hidden")]
    yc=[c for r in M["rows"] for c in r["cells"].values() if c["s"]=="you"]
    print("you cells:", len(yc), "open decision items:", sum(1 for i in items if not (i.get("decided") and i["kind"]!="signoff") and i.get("open",1)))
PY
            }
            band() { python3 - "$@" <<'PY'
import re,sys,json
t=open(sys.argv[1]).read(); case=sys.argv[2]
D=json.loads(re.search(r"const D=(.*?);\n", t, re.S).group(1)); B=D["matrix"]["band"]
ns=re.sub(r"<script>.*?</script>","",t,flags=re.S)      # what a viewer without JavaScript gets
chips={c["label"]:c["n"] for c in B["closed"]["chips"]}
if case=="static":
    print("band without JS:", 'class="hero' in ns and "items closed successfully" in ns and "open topics still to validate" in ns)
    print("headline without JS:", bool(re.search(r"<b>The app (runs|builds) on Mendix [\d.]+</b>|Upgrade to Mendix [\d.]+ in progress", ns)))
    print("matrix cells without JS:", len(re.findall(r'data-i="\d+" data-s="', ns)), "of", 4*len(D["matrix"]["rows"]))
    print("feed and readiness without JS:", ns.count("<li>")>0, ns.count('data-ready=')+ns.count('class="chip ok"')>0)
    print("viewport meta:", 'name="viewport" content="width=device-width,initial-scale=1"' in ns)
    print("closed total = sum of chips:", B["closed"]["n"]==sum(chips.values()), "| exactly two numbers:", ns.count('class="kpi ')==2)
elif case=="framing":
    legend=re.search(r'<div class="legend">(.*?)</div>', ns, re.S).group(1)
    used={c["s"] for r in D["matrix"]["rows"] for c in r["cells"].values()}|{c["s"] for c in D["matrix"]["ready"]}
    print("no dashed late marker:", "late" not in " ".join(re.findall(r'class="chip[^"]*"', ns)) and "dashed" not in ns.split("<script>")[0])
    print("legend only for states on the page:", all((("var(--%s)"%k) in legend)==(k in used) for k in ("ok","wait","bad","you","none")))
    print("no unstable or failures wording:", not re.search(r"unstable|failures", ns, re.I))
elif case=="kpi":
    o=[x["text"] for x in B["open"]["items"]]
    print("closed chip added:", chips.get("custom checks passed")==7, "| renamed count:", chips.get("test gaps closed"))
    print("open added:", "Pick a launch date" in o, "| hidden gone:", not any("sign-off" in x.lower() for x in o))
    print("shown without JS:", "custom checks passed" in ns and "Pick a launch date" in ns)
elif case=="rungs":
    print("chips:", {k:chips.get(k) for k in ("journeys pass","journeys behave as on the old app","constants checked","release notes handled")})
    print("no rest chip when the rung is missing:", "REST calls match the old app" not in chips)
PY
            }
            case $case_ in
              matrix-missing-empty) mkdir -p "$T/e/work"; python3 "$B/cockpitpage.py" --work "$T/e/work" --out "$T/out.html" >/dev/null && mx "$T/out.html" missing-empty ;;
              matrix-missing-gate)  rm -f "$W/gate-summary.md"; ck >/dev/null && mx "$T/out.html" missing-gate ;;
              matrix-tiles)         cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null && mx "$T/out.html" tiles ;;
              matrix-kinds)         cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null && mx "$T/out.html" kinds ;;
              matrix-noprop)        ck >/dev/null && mx "$T/out.html" noprop ;;
              matrix-noprop-merged) cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null && mx "$T/out.html" noprop ;;
              matrix-merge)         cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null && mx "$T/out.html" merge ;;
              matrix-stale)         echo "Grade: 80% (8 of 10 required rungs done): proven 8, open regression 0 | verdict PASS" >> "$W/gate-summary.md"; ck >/dev/null && mx "$T/out.html" stale ;;
              matrix-seen)          echo "Overlay layer found by triage" > "$W/jarclash.md"; ck >/dev/null && mx "$T/out.html" seen ;;
              matrix-seen-decided)  echo "Overlay layer found by triage" > "$W/jarclash.md"; echo '| D90 (agent) | Overlay layer closed | The overlay layer covered the checkout button. | None. | |' >> "$W/AGENT-DECISIONS.md"; ck >/dev/null && mx "$T/out.html" seen ;;
              matrix-openreg)       echo "Grade: 70% (7 of 10 required rungs done): proven 7, open regression 1 | verdict FAIL" >> "$W/gate-summary.md"
                                    echo "heal: 5 failing row(s) classified, 0 stay open (0 real-regression, 0 likely-real)" >> "$W/gate-summary.md"
                                    echo '| D91 (agent) | CANDIDATE REAL REGRESSION: Login settings page | The settings page shows an error on the new app only. | Option 1: capture the failing request. Option 2: reseed the data. | OPEN |' >> "$W/AGENT-DECISIONS.md"; ck >/dev/null && mx "$T/out.html" openreg ;;
              matrix-seen-not)      ck >/dev/null && mx "$T/out.html" seen ;;
              matrix-judg-open)     echo '{"items":[{"id":"widgets-open","question":"How do you handle the open widget rows?","step":"widgets","recommended":"a","what":"3 rows are open","options":[{"key":"a","label":"Accept","effort":"S"},{"key":"b","label":"Fix","effort":"M"}]}]}' > "$W/decisions-open.json"; ck >/dev/null && mx "$T/out.html" judg ;;
              matrix-judg-closed)   echo '{"items":[{"id":"widgets-open","question":"How do you handle the open widget rows?","step":"widgets","recommended":"a","what":"3 rows are open","options":[{"key":"a","label":"Accept","effort":"S"},{"key":"b","label":"Fix","effort":"M"}]}]}' > "$W/decisions-open.json"; echo "Grade: 80% (8 of 10 required rungs done): proven 8, open regression 0 | verdict PASS" >> "$W/gate-summary.md"; ck >/dev/null && mx "$T/out.html" judg ;;
              matrix-onerow)        cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null && mx "$T/out.html" oneRow ;;
              matrix-chips)         ck >/dev/null && mx "$T/out.html" chips ;;
              matrix-you)           ck >/dev/null && mx "$T/out.html" you ;;
              matrix-nohard)        cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null
                                    ! grep -Eq 'HTMLSnippet|run2|NATS' "$T/out.html" "$B/cockpitmatrix.py" && echo "no app names in page or generator"
                                    ! grep -Eq '(^|[^a-z])https?://' "$T/out.html" | grep -v fonts.googleapis.com; echo "external requests only fonts: $(grep -Eo 'https?://[^"'"'"' )]+' "$T/out.html" | grep -vc 'fonts.googleapis.com')" ;;
              matrix-band-static)   ck >/dev/null && band "$T/out.html" static ;;
              matrix-framing)       ck >/dev/null && band "$T/out.html" framing ;;
              matrix-kpi)           python3 - "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["kpi"]={"closed":[{"n":7,"label":"custom checks passed"},{"n":2,"label":"test gaps closed"}],
  "open":[{"group":"Your call","text":"Pick a launch date","owner":"you"}],"hide":["Plan sign-off"]}
json.dump(d,open(sys.argv[2],"w"))
PY
                                    ck >/dev/null && band "$T/out.html" kpi ;;
              matrix-rungs)         printf '%s\n' '| 6 | journeys | FAIL | 1 | journeys: 12 PASS, 0 FAIL, 3 INVALID, 4 PASS* (baseline defect);actions 9 found |' '| 7 | const | PASS | 0 | FAIL 0 \| PASS* 0 \| INFO 1 \| PASS 9 |' '| 8 | release | INVALID | 1 | release-impact check: 20 of 25 rows handled or not relevant, 5 open |' >> "$W/gate-summary.md"; ck >/dev/null && band "$T/out.html" rungs ;;
              matrix-band-nostrings) ! sed -n '/^def closed_items/,/^# ---- page ----/p' "$B/cockpitmatrix.py" | grep -Eqi 'HTMLSnippet|NATS|OIDC|Dojo|React|run2|Shop|Widgetpack' && echo "no app or module names in the band code" ;;
              matrix-trail)         cp "$here/fixtures/cockpit/trail.json" "$W/cockpit-trail.json"; ck >/dev/null && python3 - "$T/out.html" <<'PY'
import re,sys,json
t=open(sys.argv[1]).read(); M=json.loads(re.search(r"const D=(.*?);\n", t, re.S).group(1))["matrix"]
tr={r["id"]:len(r.get("trail") or []) for r in M["rows"] if r.get("trail")}
print("rows with a trail:", tr)
a=M["rows"][[r["id"] for r in M["rows"]].index("modules")]["trail"][0]["stages"]
print("commits:", sum(1 for p in a["upgrade"]["proof"] if p["kind"]=="commit"), "| tests:", len(a["test"]["results"]))
PY
;;
              matrix-trail-bad)     echo '{"rows":["not","a","map"]}' > "$W/cockpit-trail.json"; ck >/dev/null && python3 - "$T/out.html" <<'PY'
import re,sys,json
M=json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1))["matrix"]
print("rows with a trail:", sum(1 for r in M["rows"] if r.get("trail")))
PY
;;
              matrix-plan)          ck >/dev/null && python3 - "$T/out.html" <<'PY'
import re,sys,json
P=json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1))["matrix"]["plan"]
print("sections:", [s["h"] for s in P])
print("plan items:", [(i.get("id"), i.get("kind"), i.get("name")) for s in P for i in s["items"] if i.get("id")])
PY
;;
              matrix-plan-none)     rm -f "$W/PROPOSAL.md"; ck >/dev/null && python3 - "$T/out.html" <<'PY'
import re,sys,json
print("plan sections:", len(json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1))["matrix"]["plan"]))
PY
;;
  matrix-steps-ask|matrix-steps-ask-*) # slice 8: Approve and Reject in the drawer of an assumed step; the page row goes to decisions.py import
                            cp "$here/fixtures/cockpit/steps.jsonl" "$W/steps.jsonl"
                            echo '{"u_1":"Cleo"}' > "$T/n.json"
                            pg() { python3 - "$T/out.html" "$1" <<'PY'
import re,sys,json
D=json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1)); M=D["matrix"]
rows={r["id"]:r for r in M["rows"]}
for i in ("S-1","S-2","S-3"):
    r=rows[i]; print(i, "buttons:", r["ask"], "| answer:", r.get("ans"), "| plan cell:", r["cells"]["plan"]["l"])
print("open topics naming jQuery:", [(o["group"], o["owner"]) for o in M["band"]["open"]["items"] if "jQuery" in o["text"]])
PY
                            }
                            case $case_ in
                              matrix-steps-ask) ck >/dev/null; pg x; P=$T/out.html
                                for t in 'data-sid=' 'data-choice="approve"' 'data-choice="reject"' 'class="reason"' 'decideStep'; do grep -q "$t" "$P" && echo "page has $t"; done
                                echo "buttons only when it.ask: $(grep -c 'it.fromSteps&&it.ask?' "$P")"
                                echo "step answer goes to the decisions collection: $(grep -c 'collection("decisions").doc(row.item).set(row)' "$P")" ;;
                              matrix-steps-ask-approve) echo '{"decisions":[{"item":"S-2","choice":"approve","by":"u_1","at":"2026-01-04T09:00:00Z","source":"page","reason":"Bridge is fine for now"}],"signoffs":[]}' > "$T/e.json"
                                dec import --json "$T/e.json" --names "$T/n.json"; echo "S-2: $(stapp S-2)"; ck >/dev/null; pg x
                                st show S-2 --json | python3 -c 'import json,sys; print("reason kept:", json.load(sys.stdin)[0]["approval"].get("reason"))'
                                cp "$W/steps.jsonl" "$T/before"; dec import --json "$T/e.json" --names "$T/n.json"; cmp "$T/before" "$W/steps.jsonl" && echo "rerun adds nothing" ;;
                              matrix-steps-ask-reject) echo '{"decisions":[{"item":"S-2","choice":"reject","by":"u_1","at":"2026-01-04T09:00:00Z","source":"page"}],"signoffs":[]}' > "$T/e.json"
                                dec import --json "$T/e.json" --names "$T/n.json"; echo "S-2: $(stapp S-2)"; ck >/dev/null; pg x ;;
                              matrix-steps-ask-garbage) echo '{"decisions":[{"item":"S-2","choice":"maybe","by":"u_1","at":"2026-01-04T09:00:00Z","source":"page"},{"item":"S-99","choice":"approve","by":"u_1","at":"2026-01-04T09:00:00Z","source":"page"},{"item":"S-2","choice":"approve","at":"2026-01-04T09:00:00Z","source":"page"}],"signoffs":[]}' > "$T/e.json"
                                cp "$W/steps.jsonl" "$T/before"; dec import --json "$T/e.json" --names "$T/n.json"; echo "S-2: $(stapp S-2)"; cmp "$T/before" "$W/steps.jsonl" && echo "steps file untouched" ;;
                            esac ;;
              matrix-steps-*) # slice 7: work/steps.jsonl (the made-up shop fixture) drives the rows; a missing or damaged file falls back
                            case $case_ in
                              matrix-steps-bad)   printf '%s\n' "$(sed -n 1,2p "$here/fixtures/cockpit/steps.jsonl")" 'this is not an event' > "$W/steps.jsonl"; cp "$here/fixtures/cockpit/trail.json" "$W/cockpit-trail.json" ;;
                              matrix-steps-none)  cp "$here/fixtures/cockpit/trail.json" "$W/cockpit-trail.json" ;;
                              matrix-steps-incomplete) echo '{"id":"S-1","field":"topic","value":"a","by":"x","at":"2026-01-01T00:00:00Z"}
{"id":"S-1","field":"commit:abc1234","value":{"say":"no sha here"},"by":"x","at":"2026-01-01T00:00:01Z"}' > "$W/steps.jsonl" ;;
                              *) cp "$here/fixtures/cockpit/steps.jsonl" "$W/steps.jsonl"; cp "$here/fixtures/cockpit/trail.json" "$W/cockpit-trail.json" ;;
                            esac
                            ck >/dev/null; rc=$?; echo "page rc=$rc"; python3 - "$T/out.html" "$case_" <<'PY'
import re,sys,json
D=json.loads(re.search(r"const D=(.*?);\n", open(sys.argv[1]).read(), re.S).group(1)); M=D["matrix"]; c=sys.argv[2]
rows={r["id"]:r for r in M["rows"]}
sr=[r for r in M["rows"] if r.get("fromSteps")]
op=M["band"]["open"]["items"]
if c=="matrix-steps-rows":
    print("groups:", [g["key"] for g in M["groups"]])
    print("step rows:", [(r["id"], r["name"], r["group"]) for r in sr])
    for i in ("S-1","S-2","S-3"):
        print(i, {k: rows[i]["cells"][k]["l"] for k in ("triage","plan","upgrade","test")})
    print("steps file flag:", M["stepsFile"], "| trail file ignored:", not any(r.get("trail") and not r.get("fromSteps") for r in M["rows"]))
    print("signoff meta:", [i["meta"] for i in D["items"] if i["id"]=="signoff"])
elif c=="matrix-steps-drawer":
    a=rows["S-2"]["trail"][0]["stages"]; b=rows["S-1"]["trail"][0]["stages"]
    print("S-2 found:", a["triage"]["say"])
    print("S-2 proposed:", a["plan"]["say"]); print("S-2 why:", a["plan"]["why"]); print("S-2 who:", a["plan"]["who"]); print("S-2 other options:", len(a["plan"]["options"]))
    print("S-2 commits:", [p["h"] for p in a["upgrade"]["proof"]]); print("S-2 tests:", [(r[0], r[1]) for r in a["test"]["results"]]); print("S-2 proof behind toggle:", len(a["test"]["proof"]))
    print("S-1 who:", b["plan"]["who"]); print("S-1 commits:", len(b["upgrade"]["proof"]), "| tests:", len(b["test"]["results"]))
    print("S-3 test:", rows["S-3"]["trail"][0]["stages"]["test"]["results"], rows["S-3"]["cells"]["test"]["s"])
    print("JS skips the old plan box for step rows:", "!it.fromSteps?propBox" in open(sys.argv[1]).read())
elif c=="matrix-steps-band":
    print("open topics:", [(o["group"], o["text"], o["owner"]) for o in op if "S-" not in o["text"]][:0] or [(o["group"], o["text"], o["owner"]) for o in op if any(n in o["text"] for n in ("jQuery","Themepack","Widgetpack"))])
    print("routine step in open band:", any("Widgetpack" in o["text"] for o in op))
    print("you tile:", M["tiles"]["you"], "| S-2 kind:", rows["S-2"]["kind"], "| S-3 kind:", rows["S-3"]["kind"])
elif c in ("matrix-steps-none","matrix-steps-bad","matrix-steps-incomplete"):
    print("step rows:", len(sr)); print("groups:", [g["key"] for g in M["groups"]]); print("steps file flag:", M["stepsFile"])
    print("old trail used:", sorted(r["id"] for r in M["rows"] if r.get("trail")))
    print("damage notice:", [o["text"] for o in op if "damaged" in o["text"]])
    print("signoff meta:", [i["meta"] for i in D["items"] if i["id"]=="signoff"])
PY
;;
              matrix-dashes)        cp "$here/fixtures/cockpit/items.json" "$W/cockpit-items.json"; ck >/dev/null
                                    echo "dash count: $(cnt -E $'\xe2\x80\x94|\xe2\x80\x93' "$T/out.html")"; echo "generator dash count: $(cnt -E $'\xe2\x80\x94|\xe2\x80\x93' "$B/cockpitmatrix.py")" ;;
            esac ;;
  *) echo "unknown case $case_"; exit 2 ;;
esac
