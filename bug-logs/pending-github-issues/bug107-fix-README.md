**Companion to:** `bug107-workflow-call-microflow-with-unquoted-value-segfault.md`
**Patch:** `bug107-fix.patch` (git format-patch, authored as Maurits Visser)
**Status:** patch verified 2026-09-03 against `mendixlabs/mxcli` HEAD `191a0c9`; NOT YET submitted — mxcli's
CONTRIBUTING requires the issue to be filed and approved before a PR

---

# BUG-107 fix — how to turn the patch into the PR

The fix is intentionally minimal (3 files, +66/−3), the shape a maintainer approves fast:

- `mdl/visitor/visitor_workflow.go` — one nil-safe accessor for the mapping expression, used by
  both the call-microflow and call-workflow builders (both dereferenced the nil token).
- `mdl/executor/validate_workflow_refs.go` — the "parameter is not mapped" hint now shows the
  quoted form, so the tool stops recommending the crashing spelling.
- `mdl/visitor/visitor_workflow_with_unquoted_test.go` — regression test: bare value on either
  statement → error, never panic; quoted value → parses clean.

**Verified** (Claude Code web container, Go 1.26.6, parser regenerated with ANTLR 4.13.2):
baseline test captured the nil-pointer panic at both sites; after the fix `go test ./mdl/...`
= 35 packages ok, 0 failures; `gofmt` / `go vet` clean; the real binary on the repro prints
`line 3:44 mismatched input '$WorkflowContext' expecting STRING_LITERAL` instead of a SIGSEGV.

**Steps (mxcli CONTRIBUTING, Steps 1–6):**

1. File the issue from the companion draft. Wait for the maintainer's "let's do it", assign yourself.
2. Fork `mendixlabs/mxcli`, then:
   ```bash
   git clone git@github.com:<you>/mxcli && cd mxcli
   git checkout -b fix/<issue>-workflow-with-unquoted-segfault
   git am ~/Mendix/mxcli-project-toolkit/bug-logs/pending-github-issues/bug107-fix.patch
   # replace the "#<issue>" placeholder in the commit subject:
   git commit --amend   # edit "(closes #<issue>)" → "(closes #NNN)"; drop trailers you do not want upstream
   pip install 'antlr4-tools==0.2.2' && export ANTLR4_TOOLS_ANTLR_VERSION=4.13.2
   make build && make test && make lint
   ./bin/mxcli check <the repro .mdl from the issue>      # syntax error, no panic
   ```
3. Push, open the PR: "Closes #NNN", what it does (three bullets above), `make test`/`make lint`
   pass, Mendix validation = the quoted form's existing end-to-end verification on 11.14.0
   (`exec`, native `mx check` 0 errors, `DESCRIBE` round-trip) — this change touches no BSON.

**Not in this patch, worth mentioning in the issue as a follow-up:** extending the grammar so a
bare expression is *accepted* (`qualifiedName EQUALS (STRING_LITERAL | expression)`). That is a
design call for the maintainers — it changes what `describe` must emit — so it stays out of a
first PR.
