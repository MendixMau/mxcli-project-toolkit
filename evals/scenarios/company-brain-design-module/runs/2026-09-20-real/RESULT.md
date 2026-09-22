# Run 2 — 2026-09-20 — the real theme module and brand guide

Run 1 used a stand-in component. This one uses the company's actual Mendix theme module
(a full module export, 56 MB, adding `themesource/usi_theme_module/`) and its corporate UI/UX
guide PDF. Same app, same two arms, prompt reworded to the fixture's real stage (run-1 defect D1).

## Result

| Arm | n | Named the module | Primary colour | Button styles | ≥2 other hexes | Understood the deviation | Fell back to Atlas |
|---|---|---|---|---|---|---|---|
| control (no brain) | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| treatment, pointer in `CLAUDE.local.md` only | 3 | **2** | 2 | 2 | 2 | 2 | 1 |
| treatment, pointer on every surface (after the fix) | 3 | **3** | 3 | 3 | 3 | 3 | 0 |

Re-score: `bash ../grade-real.sh`. Markers were grepped for absence in both arms first.

## The miss, and what it taught

One wired session of three scored MISSED. Its own file list explains it: it read `AGENTS.md`,
`CLAUDE.md`, `PROJECT.md`, `intake.md`, the knowledge base and the toolkit's design skill — and
never opened `CLAUDE.local.md`, the only file carrying the pointer. It then proposed stock Atlas
with four cited reasons and flagged the branding gate as unasked. **Nothing about that session
was wrong. The company brain was invisible to it.**

That is a single point of failure in the wiring, not a retrieval failure in the model, and the
toolkit already had the rule that would have caught it: *a citation is not a read — wire the
dispatch*. `bin/wire-company-brain.sh` now writes the block into every instruction surface the
project already has (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`,
copilot-instructions), creating none that the project chose not to have. Re-running the three
treatment sessions against the fixed wiring: 3/3, and two of them reached the brain via
`CLAUDE.md` rather than `CLAUDE.local.md`.

## What the treatment arm got right that a project could not have known

All retrieving sessions reported the colour deviation correctly and refused to "fix" it: the
theme's `$brand-primary` is `#0C4C8A` (the guide's Extended→Bright row, Pantone 541C) while the
corporate blue `#002662` (Pantone 655C) is logo and print only. All four theme brand colours are
exactly that Bright row, so the deviation is deliberate and consistent. Typography is the same
shape: the guide's print face is Helvetica, the theme ships Open Sans for web.

This is the class of knowledge with nowhere else to live. It is not in the app, not in the
toolkit, and a per-project session that rediscovered it would plausibly "correct" the theme and
break it. It is now one paragraph in the component manifest.

Sessions also, unprompted: flagged that the module's import method is unverified on any mxcli
version (the manifest says so and they read it), questioned whether the module's dependency
footprint (CommunityCommons, OIDC, ~40 jars) deserves a register line on a POC, and noted the
project's requirements are not actually closed.

## Privacy findings on the real drop

1. The brand guide arrived with an individual's name in its **filename**, and carries a
   corporate email inside a compressed PDF stream. Company-brain rule 2 allows client and
   company names, never personal contact details. The file was renamed on intake and the email
   kept out of the manifest.
2. The template's `leak-check.sh` **passed both files silently** — it delegated to a guard that
   scans tracked *text* files, so a folder holding a PDF and a package reported "no scannable
   tracked files" and exited 0; outside git it printed git errors and still exited 0. Rewritten:
   filenames are checked, the pre-git case is handled, unscannable binaries are reported out
   loud. Four fixture assertions cover it.

## Still not tested

Install. There is no mxcli binary in this container, so whether a session probes before choosing
CLI, MCP or Studio Pro remains Part B of the rubric and remains open. Every retrieving session
did at least *say* the method was unverified, which is the manifest working, not the probe.
