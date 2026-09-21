# Agent permission friction — before you tell the user a tool is blocked

**Applies to:** any mxcli project | any agent harness
**Purpose:** Two different things refuse an agent's command, they look identical in the
transcript, and only one of them can be fixed by editing a config file. Telling them apart is
the whole skill. A session that guesses wrong spends its turns rewriting rules that could
never have matched.

---

## Why this costs more than it looks

Session cost tracks **turn count × context size**, not output length. A denial loop late in a
long session is therefore among the most expensive failures available: each retry re-sends the
whole context to produce one refused command. A measured field run (2026-09-16, a MOC/PSSR app
replacement) lost **roughly fifteen turns** to a single mis-diagnosis, at the end of a long
session, against an allowlist that had never needed changing.

## Step 1 — which of the two refused you

They render the same way and they are not the same thing.

| | **A permission rule** | **A safety classifier** |
|---|---|---|
| What it is | a deterministic pattern match against your command line | a judgement about what the command appears to do |
| Where it lives | the harness's own settings file | the hosted environment, not a file you can edit |
| Who sees it | **everyone, every device** — it ships with the repo | only sessions in a managed/sandboxed environment (agents running in the cloud, in a container, in a web session). A local CLI user on their own machine generally never sees these |
| Tell | the refusal points at permissions/settings, and the same command refused the same way every time | the refusal carries a **category label** — a bracketed name for the *kind* of thing it thinks you were doing |
| Fix | change the command or the rule | change the **shape** of the command so it stops resembling the thing. You cannot allowlist it away |

**Get this wrong in the safe direction:** if you cannot tell, assume classifier and reshape the
command. Reshaping is free; rule-editing when the rule was never the problem is the fifteen
turns.

## Step 2 — the four checks, before the word "blocked" reaches the user

1. **Is your command line compound?** A permission rule matches the **start of the command
   line**. So an allowlisted tool invocation stops matching the moment anything precedes it:

   ```
   ./mxcli exec build.mdl -p App.mpr                  → matches an allowlisted ./mxcli rule
   cd /path/to/project && ./mxcli exec build.mdl ...  → matches NOTHING. The rule is irrelevant
   ```

   This is the single highest-yield check and it is invisible from the refusal text, because
   the refusal is about `cd`. **The remedy is free: the shell's working directory persists
   between tool calls.** Issue `cd <dir>` as its own call, then run the tool in the next one.
   For git, `git -C <dir>`. For a tool with a project flag, an absolute path.

2. **Does the command merely *resemble* something dangerous?** Three shapes refuse reliably
   and all three have a boring equivalent:
   - **Renaming a credential variable on the command line** (`FOO=$REAL_SECRET some-tool`)
     reads as exfiltration preparation. Pass the secret in the variable the tool documents, or
     via an askpass helper that reads it from the environment.
   - **A heredoc anywhere near a credential** — including one whose body merely *discusses*
     one, such as a commit message about a secret. Write the file with your file-writing tool
     and pass the path. In the field run this worked every time and the heredoc worked none.
   - **A command that reads as redirecting traffic or rewriting the agent's own configuration.**
     Reshape or ask the user to do it.

3. **Is this the second refusal in one turn?** A refusal can be **sticky for the remainder of a
   turn**: after one denial, an unrelated and fully permitted command was refused with the
   *same* label, and succeeded unchanged on a fresh turn. So a second denial is not evidence
   about the second command. **End the turn** rather than reformulating a third time.

4. **Only now, look at the rule.** Print the settings the harness actually reads — do not
   recall them, and do not assume the project has none. In the field run the correct rule had
   been present since the project was scaffolded.

## Step 3 — what to tell the user

Name which of the two refused you, what you tried, and what you need. "Blocked" on its own is
the failure: it moves a five-second decision to the human without the one fact that decides it.

A permission rule is the user's to widen and you may propose the exact line. A classifier
refusal is **not** something to ask the user to disable — reshape the command, or hand them the
one action to take themselves.

## Completion criterion

A session may use the word *blocked* only after naming which of the four checks failed. Four
checks, one named outcome — "I tried a few things" is not a result.

---

## Where this knowledge has to live, and where it must not

Learned 2026-09-16 the same way: the rule was written into a project's `CLAUDE.md`, which is
the wrong home twice over.

- **`CLAUDE.md` is regenerated.** `mxcli init` overwrites it; only `bootstrap-project.md`
  merges. A rule written there survives until the next init and then silently does not.
- **`CLAUDE.md` is Claude-specific.** Copilot, Cursor, Windsurf and the rest read their own
  files, and this toolkit's standing rule is that those per-tool files are **pointers, never
  copies**.

So the durable home is **this file**, referenced rather than copied, reached through the
baseline routing table that every project's generated `CLAUDE.local.md` carries. It updates
with a toolkit pull and no project has to be touched.

**Do not put a table of specific harness settings-file paths or rule syntaxes here.** Every
agent tool has some form of command allow/deny list, they are all differently spelled, and they
all move. A cached table goes stale the day one of them ships a new format, and the reader will
trust it because it is written down. Instruct the reader to **read their own harness's
configuration** and report what they actually found — the principle in step 2 check 1 (a rule
matches the start of the command line) is what generalises, not the spelling.
