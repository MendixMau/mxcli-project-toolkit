#!/usr/bin/env bash
# baseline-lock.sh — the shared lock behind every ratchet baseline a person must approve.
#
# WHY (#348, 2026-10-14). `lint-gate.sh --update-baseline` took `--approved-in-chat` as the
# proof that the user said yes. The agent whose script caused the rise could type that flag
# itself, so "re-baselining is the user's call" was honour-system. A baseline that LOOSENS now
# moves only against a row in .claude/baseline-approvals.tsv whose sha256 is the exact
# proposed content — a row only bin/baseline-approve.sh writes, from a terminal, after a person
# reads the change and types `approve`.
#
# THE RECORD IS CHECKED, NOT BELIEVED (#375 review). Every instrument write is logged with a
# snapshot of its content, and `verify` replays the log: each recorded write must be no looser
# than the one before it, or carry an approval. So appending a row by hand — or running
# `record` directly after a hand edit — does not launder a rise: the forged row is looser than
# its predecessor and verify says FAIL. Only content can pass, never a claim about content.
#
# GIT IS THE MEMORY (#375 confirmation review). Rows git HEAD has committed must all still be in
# the log: removing or truncating them is FAIL, not "predates the lock". A loosening is MANUAL
# only when a merge produced it (a looser row from a merge's other parent, or merge-made baseline
# content); a plain one-parent commit of it stays FAIL. An approval covers only the state it saw
# when given: a later write supersedes it. The user's `approve --current` re-anchors the replay
# at that row, so it clears every earlier FAIL or MANUAL (rule 7). The instruments refuse any
# un-approved write unless verify says PASS, and gate-check blocks on FAIL and MANUAL alike: no
# state but PASS passes without a person.
#
# What it does NOT stop, said plainly: a forged row in baseline-approvals.tsv (Claude Code denies
# the approve command, file-tool edits and shell redirection into it — bin/install-claude-
# permissions.sh — but an agent determined to evade those, e.g. via an interpreter, can still
# write one); a harness with no deny rules whose agent terminal is a real TTY, or a TTY faked by
# a pty wrapper; and edits to rows not yet committed (outside git, or before the commit, the log
# is only as tamper-evident as the working tree). Each is a deliberate forgery, not a flag the
# rule allowed.
#
# Covered baselines (kind -> file, relative to the project root):
#   lint         .claude/lint-baseline.json     project-bin/lint-gate.sh
#   conformance  docs/conformance/baseline.tsv  project-bin/conformance-check.sh
# "Looser" means: lint — any rule's count above the previous one; conformance — any row OK in the
# previous baseline and present but not OK now. Content is compared with CR stripped, so a CRLF
# checkout (Windows autocrlf) hashes the same as LF.
#
# Records (commit them with the baseline):
#   .claude/baseline-approvals.tsv            ts kind sha256 by note   — ONLY baseline-approve.sh
#   .claude/baseline-writes.tsv               ts kind sha256 basis     — every write an instrument made
#   .claude/baseline-history/<kind>/<sha256>  the content of each recorded write
#   .claude/baseline-pending/<kind>[.summary] the refused proposal, for the person to review
#
# Usage (instruments, baseline-approve.sh and gate-check call it; a person never needs to):
#   baseline-lock.sh file     <kind>                         print the baseline path (relative)
#   baseline-lock.sh sha      <file>                         sha256 of the file, CR stripped
#   baseline-lock.sh now                                     the records' timestamp (microseconds)
#   baseline-lock.sh verify   <root> <kind>                  print STATE<TAB>note, exit 0
#       NONE    no baseline and no record                    (a first write needs no approval)
#       GONE    no baseline, but records exist               (re-creating it needs approval)
#       PASS    no looser than the last verified write (replayed from the latest approval)
#       FAIL    looser than it with no approval, a recorded write that loosened without one
#               (a forged record), a missing snapshot, or committed rows missing from the log
#       MANUAL  no record at all (predates the lock, or the log was removed outside git), or a
#               loosening a git merge produced. Blocks like FAIL; cleared by approve --current
#   baseline-lock.sh approved <root> <kind> <sha>            exit 0 iff an approval newer than every write matches
#   baseline-lock.sh record   <root> <kind> <basis>          log the baseline now on disk
#   baseline-lock.sh propose  <root> <kind> <file> <summary> save the proposal, print the ask
#
# Producer of the records: the two instruments above (writes, proposals) and
# project-bin/baseline-approve.sh (approvals). Consumer: those instruments and
# bin/gate-check.sh's "Baselines" line (toolkit copy, run against the project root).
set -uo pipefail

PY=""
for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
  case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
  if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY="$_c"; break; fi
done
[ -n "$PY" ] || { echo "baseline-lock: Python 3 is required and was not found" >&2; exit 2; }

IFS= read -r -d '' _LOCK_PY <<'PY' || true
import datetime, hashlib, json, os, shutil, subprocess, sys

FILES = {"lint": ".claude/lint-baseline.json", "conformance": "docs/conformance/baseline.tsv"}
APPROVALS, WRITES, HISTORY = ".claude/baseline-approvals.tsv", ".claude/baseline-writes.tsv", ".claude/baseline-history"

def norm(b):
    return b.replace(b"\r", b"")

def now():
    # Microseconds: an approval and the write it covers can land in the same second, and the
    # order between them is the whole check (live(), justified()).
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

def sha_bytes(b):
    return hashlib.sha256(norm(b)).hexdigest()

def sha_file(p):
    return sha_bytes(open(p, "rb").read())

def rows(root, name, kind):
    p = os.path.join(root, name)
    if not os.path.isfile(p):
        return []
    out = []
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.rstrip("\r\n").split("\t")
        if len(f) >= 3 and f[1] == kind and f[0] != "ts":
            out.append(f)
    return out

def load(kind, b):
    t = norm(b).decode("utf-8", "replace")
    if kind == "lint":
        return {k: int(v) for k, v in (json.loads(t).get("counts") or {}).items()}
    d = {}
    for line in t.splitlines():
        f = line.split("\t")
        if len(f) >= 3 and f[0]:
            d[(f[0], f[1])] = f[2]
    return d

def looser(kind, prev, new):
    if kind == "lint":
        return [r for r in sorted(new) if new[r] > prev.get(r, 0)]
    return ["%s %s" % k for k in sorted(new) if prev.get(k) == "OK" and new[k] != "OK"]

def git(root, *a):
    try:
        r = subprocess.run(["git", "-C", root] + list(a), capture_output=True, timeout=30)
        return r.stdout if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None

_LINES = {}
def lines_at(root, rev, rel):
    if (rev, rel) in _LINES:
        return _LINES[(rev, rel)]
    b = git(root, "show", "%s:./%s" % (rev, rel))
    _LINES[(rev, rel)] = norm(b).decode("utf-8", "replace").splitlines() if b is not None else []
    return _LINES[(rev, rel)]

def merged_in(root, line):
    # True when `line` reached HEAD's log through a merge: present on a non-first parent of a
    # merge commit and absent from its first parent. A row committed on the mainline is not.
    out = git(root, "log", "--merges", "--format=%H %P", "--", WRITES) or b""
    for m in out.decode().splitlines():
        ps = m.split()[1:]
        if len(ps) > 1 and line not in lines_at(root, ps[0], WRITES) \
           and any(line in lines_at(root, p, WRITES) for p in ps[1:]):
            return True
    return False

def blob_merged(root, rel, s, recorded):
    # The current content is git HEAD's, and the commit that last changed it on the mainline is a
    # merge that produced it (or took it from a side that recorded it). A single-parent commit of a
    # loosening is not a merge: FAIL (#375 confirmation review, H2).
    hb = git(root, "show", "HEAD:./" + rel)
    if hb is None or sha_bytes(hb) != s:
        return False
    c = (git(root, "log", "-1", "--first-parent", "--format=%P", "--", rel) or b"").decode().split()
    if len(c) < 2:
        return False
    sides = {sha_bytes(git(root, "show", "%s:./%s" % (p, rel)) or b"") for p in c}
    return s not in sides or s in recorded

def verify(root, kind):
    rel = FILES[kind]
    path = os.path.join(root, rel)
    w, a = rows(root, WRITES, kind), rows(root, APPROVALS, kind)
    line = lambda r: "\t".join(r)
    def justified(i):  # a human approved exactly this write, after the write before it
        prev = w[i - 1][0] if i else ""
        return any(ap[2] == w[i][2] and prev <= ap[0] <= w[i][0] for ap in a)
    k = max([i for i in range(len(w)) if justified(i)], default=None)
    # Committed rows are a required prefix: a record git has seen cannot be deleted or edited
    # away (#375 confirmation review, H1). Only a human approval written after them supersedes.
    ingit = git(root, "rev-parse", "--is-inside-work-tree") is not None
    if ingit:
        comm = [l for l in lines_at(root, "HEAD", WRITES) if l.split("\t")[1:2] == [kind]]
        have = {line(r) for r in w}
        missing = [l for l in comm if l not in have]
        anchor = line(w[k]) if k is not None else None
        superseded = anchor is not None and (anchor not in comm or
                     all(comm.index(m) < comm.index(anchor) for m in missing))
        if missing and not superseded:
            return "FAIL", ("%d committed record(s) missing from %s (first: %s) — the log was truncated or "
                            "rewritten; restore it from git, or the user approves the current state: "
                            "bin/baseline-approve.sh %s --current" % (len(missing), WRITES, missing[0][:40], kind))
    start = k if k is not None else 0
    last, manual = None, None
    for i in range(start, len(w)):
        r = w[i]
        snap = os.path.join(root, HISTORY, kind, r[2])
        if not os.path.isfile(snap) or sha_file(snap) != r[2]:
            return "FAIL", "recorded write %s (%s) has no matching snapshot under %s — the record cannot be checked; the user can re-anchor: bin/baseline-approve.sh %s --current" % (r[2][:12], r[0], HISTORY, kind)
        try:
            c = load(kind, open(snap, "rb").read())
        except ValueError:
            return "FAIL", "recorded write %s (%s) is not a readable %s baseline" % (r[2][:12], r[0], kind)
        up = [] if i == start or justified(i) else looser(kind, last, c)
        via_merge = bool(ingit and line(r) in comm and merged_in(root, line(r)))
        if up and via_merge:
            manual = ("recorded write %s (%s) is looser than the row before it (%s) and came in through a merge "
                      "— the user reviews it and runs: bin/baseline-approve.sh %s --current" % (r[2][:12], r[0], ", ".join(up[:5]), kind))
        elif up:
            return "FAIL", ("recorded write %s (%s, basis %s) loosens the baseline (%s) and no approval matches it — "
                            "a record is checked against its content, not believed" % (r[2][:12], r[0], r[3] if len(r) > 3 else "?", ", ".join(up[:5])))
        elif i == start or justified(i) or not via_merge:
            manual = None  # a later approval or mainline write clears a merge's MANUAL (M2)
        last = c
    if not os.path.isfile(path):
        if w or a:
            return "GONE", "%s is missing but was recorded before — re-creating it needs a person: bin/baseline-approve.sh %s" % (rel, kind)
        return "NONE", "no %s baseline yet" % kind
    raw = open(path, "rb").read()
    s = sha_bytes(raw)
    if last is None:
        return "MANUAL", ("%s has no write record (it predates the lock, or the log was removed) — the user "
                          "approves it once: bin/baseline-approve.sh %s --current" % (rel, kind))
    try:
        cur = load(kind, raw)
    except ValueError:
        return "FAIL", "%s is not a readable %s baseline" % (rel, kind)
    up = looser(kind, last, cur)
    if up and ingit and blob_merged(root, rel, s, {r[2] for r in w}):
        return "MANUAL", ("%s is looser than its last recorded write (%s) and was produced by a merge — the user "
                          "reviews it and runs: bin/baseline-approve.sh %s --current" % (rel, ", ".join(up[:5]), kind))
    if up:
        return "FAIL", ("%s moved without approval: looser than its last recorded write (%s) — a person reviews it and runs: "
                        "bin/baseline-approve.sh %s --current" % (rel, ", ".join(up[:5]), kind))
    return ("MANUAL", manual) if manual else ("PASS", "%s is no looser than its last recorded write" % rel)

def live(root, kind, s):
    # An approval covers the state it approved when it was given: it must postdate every
    # recorded write (#375 confirmation review, M3).
    w = rows(root, WRITES, kind)
    after = w[-1][0] if w else ""
    return any(ap[2] == s and ap[0] > after for ap in rows(root, APPROVALS, kind))

def record(root, kind, basis):
    path = os.path.join(root, FILES[kind])
    raw = open(path, "rb").read()
    s = sha_bytes(raw)
    d = os.path.join(root, HISTORY, kind)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, s), "wb").write(norm(raw))
    p = os.path.join(root, WRITES)
    new = not os.path.isfile(p)
    with open(p, "a") as f:
        if new:
            f.write("ts\tkind\tsha256\tbasis\n")
        f.write("%s\t%s\t%s\t%s\n" % (now(), kind, s, basis))
    for n in (kind, kind + ".summary"):
        try:
            os.remove(os.path.join(root, ".claude", "baseline-pending", n))
        except OSError:
            pass

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "now":
    print(now())
elif cmd == "sha":
    print(sha_file(args[0]))
elif cmd == "verify":
    st, note = verify(args[0], args[1])
    print("%s\t%s" % (st, note))
elif cmd == "approved":
    sys.exit(0 if live(args[0], args[1], args[2]) else 1)
elif cmd == "record":
    record(args[0], args[1], args[2])
PY

_file() {
  case "$1" in
    lint)        echo ".claude/lint-baseline.json" ;;
    conformance) echo "docs/conformance/baseline.tsv" ;;
    *) echo "baseline-lock: unknown kind '$1' (lint | conformance)" >&2; return 2 ;;
  esac
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  file)
    _file "$1" ;;
  sha)
    "$PY" -c "$_LOCK_PY" sha "$1" ;;
  now)
    "$PY" -c "$_LOCK_PY" now ;;
  verify|approved)
    _file "$2" >/dev/null || exit 2
    "$PY" -c "$_LOCK_PY" "$cmd" "$@" ;;
  record)
    _file "$2" >/dev/null || exit 2
    "$PY" -c "$_LOCK_PY" record "$@" ;;
  propose)
    root="$1"; kind="$2"; src="$3"; summary="$4"
    d="$root/.claude/baseline-pending"; mkdir -p "$d"
    cp "$src" "$d/$kind" && printf '%s\n' "$summary" > "$d/$kind.summary"
    echo "" >&2
    echo "   Moving this baseline is the user's call, and a flag the agent can type is not their" >&2
    echo "   answer. Show the user the change above, then ask THEM to run, in a separate terminal" >&2
    echo "   window (not the agent's, and not Claude Code's ! mode, which has no TTY):" >&2
    echo "       bin/baseline-approve.sh $kind" >&2
    echo "   (it shows the proposal and asks them to type 'approve'). Agents: do not run it —" >&2
    echo "   it is denied to you and refuses without a terminal. Then re-run the same command." >&2
    ;;
  *)
    sed -n '2,65p' "$0"; exit 2 ;;
esac
