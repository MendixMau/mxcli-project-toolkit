#!/usr/bin/env python3
"""keptdeps.py: does an UPDATED module need something a KEPT module does not have (T6R-7, T6-1)?

The other direction of crosscalls.py. crosscalls asks, before the plan, whether a module that stays calls the old API of
a planned one. This asks, after (or before) a keep, whether a module that WAS updated now reaches into a module that
stayed at its installed version. T6R: stepupdate committed AmazonTranslateConnector 3.1.1 (needs AWSAuthentication 4.x)
and then kept AWSAuthentication 2.1.2 on an idcheck REVIEW; nothing said so until mx check (12 CE1613 in batch 2, 27 in
batch 1) and javac. MendixSSO 10.x calls Administration.MendixSSO_CreateUser with an EmailAddress parameter that the
kept Administration 2.1.2 lacks (CE0117). The keep decision was made without either fact.

For every pair (updated module U, kept module K, U != K) it lists the references from U into K and checks each one
against K as it is in the model now (and the other way round, K into U, against U as updated):
  K.Name        a document, entity, association or enumeration of K (microflow, Java action, page, constant ...);
                missing in K = MISSING.
  K.Doc.Member  a parameter of a microflow, nanoflow, rule, Java action or JavaScript action of K, an attribute of an
                entity of K, a value of an enumeration of K (a parameter mapping, an attribute read, an enum literal);
                missing = MISSING. Members of other kinds (layout placeholders, page parameters) are not judged here.
  java import   `import <k>.x.C;` in javasource/<u>/ where <k> is K's Java package (its name, lower case); no
                javasource/<k>/x/C.java (or folder x for `.*`) = MISSING.
Excluded documents do not build and are not scanned. A name check proves presence, not a matching signature or
type, so a pair whose references all resolve is REVIEW, never PASS: mx check and javac on this commit decide it.

Usage:
  keptdeps.py APP (--kept A,B | --kept-file kept.txt) (--updated C,D | --updated-from-git) [--javasource DIR] [--json out.json]
  APP                 the app folder (the .mpr, mprcontents/ and javasource/ side by side) or the .mpr itself
  --kept-file         stepupdate's .stepupdate/kept.txt: one module per line, the first word is the module
  --kept ''           an explicitly empty kept list is legal (nothing stays); giving neither kept option is an input
                      error, so a forgotten argument is never read as "nothing is kept"
  --updated-from-git  the modules with a "step: <Module> <version>" commit in APP's git history (stepupdate's commits)
A module that is both kept and updated is a kept module (a later refusal kept it; stepupdate drops a module from
kept.txt when a later pass commits it).

Output: a header with the denominators (kept, updated, documents and Java files scanned), then per pair
  FAIL <U> <ver> needs kept <K> <ver>: <n> of <m> references missing in <K> (e.g. ...)
  FAIL kept <K> <ver> calls updated <U> <ver>: <n> of <m> references missing in <U> (e.g. ...)
  REVIEW <U> <ver> needs kept <K> <ver>: <m> references, all present by name (e.g. ...)
  NOTE kept <K> <ver> calls updated <U> <ver>: all present by name (crosscalls.py's class, capped by major at triage)
and a closing verdict line. Exit: 0 = no updated module reaches into a kept one, 1 = FAIL or REVIEW (the verdict line
says which), 2 = input error (a named module is not in the model, no model, no kept or updated option, no git).
FAIL: update K too (then rerun), hold U at a version built against the kept K, or port the missing elements; never keep
K silently. REVIEW: mx check and the build after this commit must show no error in U naming K; write that in the journal.
"""
import argparse, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mprmodel  # noqa: E402
from crosscalls import JIMPORT, KIND, names, read_first_words  # noqa: E402

QN3 = re.compile(r"^([A-Za-z_]\w*)\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)$")
FLOWS = ("Microflows$Microflow", "Microflows$Nanoflow", "Microflows$Rule", "JavaActions$JavaAction",
         "JavaScriptActions$JavaScriptAction", "Microflows$JavaScriptAction")


def param_names(x, out):
    """Names of the parameter nodes of a flow or action ($Type ...Parameter or ...ParameterObject, by version)."""
    if isinstance(x, dict):
        t = x.get("$Type", "")
        if (t.endswith("Parameter") or t.endswith("ParameterObject")) and isinstance(x.get("Name"), str):
            out.add(x["Name"])
        for v in x.values():
            param_names(v, out)
    elif isinstance(x, list):
        for v in x:
            param_names(v, out)
    return out


class Index:
    """What a module has, by qualified name: documents, entities (with attributes), associations, enum values, params."""

    def __init__(self, model):
        self.model = model
        self.kind = {}      # qn -> kind
        self.members = {}   # qn -> set of member names (only for the kinds judged at member level)
        for d in model.all_docs:
            qn = f"{d.module}.{d.data.get('Name')}"
            k = KIND.get(d.type) or d.type.split("$")[-1].lower()
            self.kind.setdefault(qn, k)
            if d.type in FLOWS:
                self.members[qn] = param_names(d.data, set())
            elif d.type == "Enumerations$Enumeration":
                self.members[qn] = {v.get("Name") for v in d.data.get("Values") or [] if isinstance(v, dict)}
        for d in model.docs.values():
            if d.type != "DomainModels$DomainModel":
                continue
            for e in d.data.get("Entities") or []:
                if isinstance(e, dict) and e.get("Name"):
                    qn = f"{d.module}.{e['Name']}"
                    self.kind[qn] = "entity"
                    self.members[qn] = {a.get("Name") for a in e.get("Attributes") or [] if isinstance(a, dict)}
            for key in ("Associations", "CrossAssociations"):
                for a in d.data.get(key) or []:
                    if isinstance(a, dict) and a.get("Name"):
                        self.kind[f"{d.module}.{a['Name']}"] = "association"

    def check(self, s, kept):
        """[(kind, target, present)] for the references into kept modules inside one BSON string."""
        out = []
        m3 = QN3.match(s)
        if m3 and m3.group(1) in kept:
            doc = f"{m3.group(1)}.{m3.group(2)}"
            if doc in self.members:
                k = self.kind.get(doc)
                what = {"entity": "attribute", "enumeration": "enumeration value"}.get(k, "parameter")
                out.append((f"{what} of {k}", s, m3.group(3) in self.members[doc]))
        for mod, name in mprmodel.QN.findall(s):
            if mod in kept:
                tq = f"{mod}.{name}"
                k = self.kind.get(tq)
                out.append((k or "name", tq, k is not None))
        return out


def model_refs(model, idx, frm, into):
    """{(F, T): {(kind, from, target, present)}} over every non-excluded document of a module in frm (and its domain
    model), for the references into a module in into."""
    out, ndocs = {}, 0
    docs = list(model.all_docs) + [d for d in model.docs.values() if d.type == "DomainModels$DomainModel"]
    for d in docs:
        if d.module not in frm or d.data.get("Excluded"):
            continue
        ndocs += 1
        src = f"{d.module} domain model" if d.type == "DomainModels$DomainModel" else f"{d.module}.{d.data.get('Name')}"
        for s in mprmodel.strings(d.data):
            for kind, tgt, ok in idx.check(s, into - {d.module}):
                out.setdefault((d.module, tgt.split(".")[0]), set()).add((kind, src, tgt, ok))
    return out, ndocs


def proxy_refs(idx, k, rest, text):
    """[(import text, present)] for an import of a GENERATED proxy class (NR2-12). `<k>.proxies.*` is made by the build and
    is not in git, so a missing file proves nothing: judge the model instead. `proxies.microflows.Microflows` is judged per
    call (`Microflows.decrypt(` -> microflow K.Decrypt, case-insensitive); `proxies.<Name>` is the entity or enumeration."""
    low = {q.lower(): kd for q, kd in idx.kind.items()}
    if rest == "proxies.microflows.Microflows":
        calls = sorted(set(re.findall(r"\bMicroflows\.(\w+)\s*\(", text)))
        return [(f"{rest}.{c}", low.get(f"{k}.{c}".lower()) in ("microflow", "nanoflow", "java action", "javascript action", "rule")
                 or any(q.startswith(f"{k}.{c}".lower()) and kd == "microflow" for q, kd in low.items()))
                for c in calls] or [(rest, True)]
    m = re.fullmatch(r"proxies\.(\w+)", rest)
    if m:
        return [(rest, low.get(f"{k}.{m.group(1)}".lower()) in ("entity", "enumeration"))]
    return None


def java_refs(jdir, frm, into, idx=None):
    """{(F, T): {("java import", file, import, present)}} from javasource/<f>/**.java importing T's package."""
    out, nfiles = {}, 0
    if not os.path.isdir(jdir):
        return out, 0
    pk = {k.lower(): k for k in into}
    dirs = {d.lower(): d for d in os.listdir(jdir)}
    for u in frm:
        ud = dirs.get(u.lower())
        if not ud:
            continue
        for root, _, files in os.walk(os.path.join(jdir, ud)):
            for f in sorted(files):
                if not f.endswith(".java"):
                    continue
                nfiles += 1
                rel = os.path.relpath(os.path.join(root, f), jdir)
                text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                for pkg, rest in JIMPORT.findall(text):
                    k = pk.get(pkg.lower())
                    if not k or k == u:
                        continue
                    parts = [dirs.get(pkg.lower(), pkg)] + rest.split(".")
                    if idx is not None and rest.startswith("proxies.") and not any(
                            os.path.isfile(os.path.join(jdir, *parts[:i]) + ".java") for i in range(2, len(parts) + 1)):
                        judged = proxy_refs(idx, k, rest, text)
                        if judged is not None:
                            for imp, ok in judged:
                                out.setdefault((u, k), set()).add(("java import", rel, f"{pkg}.{imp}", ok))
                            continue
                    if parts[-1] == "*":
                        ok = os.path.isdir(os.path.join(jdir, *parts[:-1]))
                    else:  # a.b.C, a.b.C.Inner, static a.b.C.member: some prefix is a .java file
                        ok = any(os.path.isfile(os.path.join(jdir, *parts[:i]) + ".java") for i in range(2, len(parts) + 1))
                    out.setdefault((u, k), set()).add(("java import", rel, f"{pkg}.{rest}", ok))
    return out, nfiles


def git_updated(app_dir):
    try:
        r = subprocess.run(["git", "-C", app_dir, "log", "--format=%s"], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as e:
        return None, str(e).strip() or "git log failed"
    mods = []
    for line in r.stdout.splitlines():
        m = re.match(r"step: (\S+) \S+", line)
        if m and m.group(1) not in mods:
            mods.append(m.group(1))
    return sorted(mods), None


def eg(rows, n=3):
    return "; ".join(f"{kind} {src} -> {tgt}" for kind, src, tgt, _ in sorted(rows)[:n])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("app")
    ap.add_argument("--kept")
    ap.add_argument("--kept-file")
    ap.add_argument("--updated")
    ap.add_argument("--updated-from-git", action="store_true")
    ap.add_argument("--javasource")
    ap.add_argument("--json")
    a = ap.parse_args()

    if a.kept is None and not a.kept_file:
        print("keptdeps: give --kept A,B (or --kept '' for none) or --kept-file kept.txt", file=sys.stderr)
        return 2
    if a.updated is None and not a.updated_from_git:
        print("keptdeps: give --updated C,D or --updated-from-git", file=sys.stderr)
        return 2
    if a.kept_file and not os.path.isfile(a.kept_file):
        print(f"keptdeps: no kept file {a.kept_file}", file=sys.stderr)
        return 2
    kept = names(a.kept) + ([n for n, _ in read_first_words(a.kept_file, False)] if a.kept_file else [])
    kept = list(dict.fromkeys(kept))
    try:
        model = mprmodel.Model.load(a.app)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    base = os.path.dirname(os.path.abspath(model.path))
    updated = names(a.updated)
    if a.updated_from_git:
        g, err = git_updated(base)
        if g is None:
            print(f"keptdeps: --updated-from-git: {err} (nothing judged)", file=sys.stderr)
            return 2
        updated += g
    updated = list(dict.fromkeys(updated))
    both = [n for n in updated if n in kept]
    updated = [n for n in updated if n not in kept]
    unknown = [n for n in kept + updated if n not in model.modules]
    if unknown:
        print(f"keptdeps: not a module of the model: {', '.join(unknown)} (a typo or a removed module; nothing judged)", file=sys.stderr)
        return 2
    jdir = a.javasource or os.path.join(base, "javasource")

    idx = Index(model)
    ver = lambda mod: model.modules[mod].get("version") or "version unknown"  # noqa: E731
    # both directions: an updated module needing the kept one (T6R-7), and the kept one calling the updated one's new
    # API (T5F-4, the crosscalls class, here judged against the model as it is after the update)
    dirs = {}
    ndocs = nfiles = 0
    for d, frm, into in (("needs", updated, kept), ("calls", kept, updated)):
        mr, nd = model_refs(model, idx, set(frm), set(into))
        jr, nf = java_refs(jdir, frm, into, idx)
        ndocs += nd
        nfiles += nf
        for src in (mr, jr):
            for key, v in src.items():
                dirs.setdefault((d,) + key, set()).update(v)

    print(f"keptdeps: kept {len(kept)} ({', '.join(kept) or '-'}), updated {len(updated)} ({', '.join(updated) or '-'}); "
          f"scanned {ndocs} documents and {nfiles} Java files of these modules under {jdir}")
    if both:
        print(f"note: {', '.join(both)} is on both lists: treated as kept, not updated")
    fails, reviews, res, notes = 0, 0, [], []
    for (d, f, t) in sorted(dirs, key=lambda x: (x[0] != "needs", x[1], x[2])):
        rows = dirs[(d, f, t)]
        u, k = (f, t) if d == "needs" else (t, f)
        head = f"{u} {ver(u)} needs kept {k} {ver(k)}" if d == "needs" else f"kept {k} {ver(k)} calls updated {u} {ver(u)}"
        miss = [r for r in rows if not r[3]]
        entry = {"updated": u, "updated_version": ver(u), "kept": k, "kept_version": ver(k), "direction": d,
                 "references": len(rows), "missing": [list(r[:3]) for r in sorted(miss)],
                 "present": [list(r[:3]) for r in sorted(rows) if r[3]]}
        if miss:
            fails += 1
            entry["verdict"] = "FAIL"
            print(f"FAIL {head}: {len(miss)} of {len(rows)} references missing in {t} (e.g. {eg(miss)})")
            for r in sorted(miss)[3:]:
                print(f"   missing: {r[0]} {r[1]} -> {r[2]}")
        elif d == "calls":
            # a kept module calling an updated one with every name present: crosscalls.py's class (CAP by major at
            # triage); listed, not a REVIEW here, or every kept module on Atlas_Core layouts would be one
            entry["verdict"] = "NOTE"
            notes.append(f"NOTE {head}: {len(rows)} references, all present by name (crosscalls.py judged the major at triage)")
        else:
            reviews += 1
            entry["verdict"] = "REVIEW"
            print(f"REVIEW {head}: {len(rows)} references, all present by name (e.g. {eg(rows)})")
        res.append(entry)
    for n in notes:
        print(n)
    verdict = "FAIL" if fails else "REVIEW" if reviews else "PASS"
    quiet = len([u for u in updated if not any(u in (f, t) for _, f, t in dirs)])
    print(f"keptdeps: verdict {verdict} ({fails} FAIL, {reviews} REVIEW pair(s); {quiet} of {len(updated)} updated module(s) "
          f"share no reference with a kept module)")
    if fails:
        print("  FAIL: update the kept module too (then rerun), hold the updated module at a version built against it, or port")
        print("  the missing elements; a keep with a FAIL pair is never silent (report it with the pair)")
    if reviews:
        print("  REVIEW: names resolve, signatures and types are not proven: mx check and the build after this commit must")
        print("  show no error in either module of the pair naming the other; write that in the journal")
    if a.json:
        json.dump({"kept": kept, "updated": updated, "verdict": verdict, "pairs": res}, open(a.json, "w"), indent=1)
    return 1 if fails or reviews else 0


if __name__ == "__main__":
    sys.exit(main())
