# Keeping a project aligned with Mendix Team Server

**Applies to:** any mxcli project whose model is built on git (GitHub, GitLab, a bare remote) and
also lives in a Mendix Team Server repository that other people open in Studio Pro.

**Purpose:** the recurring operation, not the setup. Which remote is authoritative, what order to
push in, and the four checks to run before telling the user a Team Server push is blocked.

**Not this file:** creating the app, PAT scopes, adopting an existing model without rewriting
history, deploying, Free App limits. That is `skills/platform-link.md`, which is the birth skill —
read it once per project. This one is read every session that pushes.

**Field run:** one. A MOC/PSSR app replacement, 2026-09-07 → 2026-09-12. A push to Team Server was
reported to the user as blocked **three times across two sessions, and it was not blocked any of
those times.** The project had a skill covering it the whole time; the skill was project-local and
situational, so no session read it before reporting the block.

---

## 1. Never assume which remote is authoritative — read it

A project on Team Server usually has **three or more** remotes, and at least one of them is a dead
app id from an earlier attempt. Pushing to the wrong one is silent: git reports success and the
team still runs yesterday's model.

Do not carry a remote table in your head or in a skill file — it goes stale the day someone adds
a fourth. List them at the start of any session that will push:

```
git remote -v
```

Then find which one the project has declared authoritative. In order:

1. The project's own `CLAUDE.md` / `CLAUDE.local.md`, or a project-local skill under
   `.ai-context/skills/`.
2. `PROJECT.md`, if a gate decision recorded it.
3. Ask the user. One question, two named remotes, your recommendation.

**"Push to Team Server" with no remote named is not self-evident** when two remotes are Team Server
URLs. Resolve it before the push, not after.

## 2. Order of operations: settle incoming, then push

The user pushes their own commits, so the git-side remote moves underneath you.

```
git fetch origin
git merge --no-edit origin/main
git push -u origin main
git push <teamserver-remote> main:main
```

`git pull --ff-only` failing here is **not an error to route around.** It means both sides carry
real commits and a merge is the correct answer. Reaching for `--rebase` or `--force` because
`--ff-only` refused is how a Studio Pro checkout gets orphaned.

## 3. Before reporting a Team Server push as blocked — four checks, in order

This is the section that exists because of the field run. Three reports of "blocked", zero actual
blocks. Run all four before the word *blocked* reaches the user.

1. **The credential is probably already in the environment.** Look for it before concluding one is
   missing. A single guess at a variable name returning empty is not evidence of absence. If you
   cannot find it, ask the user which variable holds it.

2. **A wrong username fails identically to a wrong token.** Team Server answers
   `fatal: Authentication failed` for both. The identity it wants is the user's **Mendix login** —
   not the GitHub handle, not `git`, not `oauth2`, not any of the service placeholders other hosts
   accept. If you hold a credential and auth still fails, suspect the username first, not the
   token.

3. **Probe with `git ls-remote`, printing a fixed label only.** Never build a probe whose output
   interpolates the credential. On 2026-09-11 a loop that echoed each candidate leaked a live token
   into the transcript and cost a rotation — because the token itself was one of the candidates
   being tried. The probe prints `OK` or `FAIL`, nothing else, ever.

4. **An inline `credential.helper` shell function is refused** by a sandboxed environment as
   credential exploration, and the refusal looks like a git failure. Supply the credential through
   git's askpass mechanism, reading it from the environment, so it never touches disk or a config
   file.

Two messages that are **normal** against Team Server and are not the block:

```
warning: --negotiate-only requires protocol v2 (or later)
push negotiation failed; proceeding anyway
```

The push still lands. Verify by reading the remote back — `git ls-remote <remote> main` and compare
the sha to your local head — never by the absence of an error.

## 4. Never

- Never `git push --force` to a Team Server remote. Studio Pro checkouts diverge from a rewritten
  history and the team cannot recover without re-cloning.
- Never write the credential into a URL, a script body, a config file, a log, a commit, or a
  `.git/config`. Store it outside any git repo.
- Never report a push as blocked without having run all four checks in §3 and saying which one
  failed. "It seems to be blocked" is the output this skill exists to retire.

## 5. Completion criterion

A session that pushed is done when it can state **the remote name, the sha it pushed, and the sha
`git ls-remote` reads back** — three values, matching. A session that did not push is done when it
names which of the four checks in §3 failed. Silence is not a verdict; see
`skills/degrade-to-judgement.md`.
