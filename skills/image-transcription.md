# Image Transcription — Describing Every Unique Picture, Once

**Applies to:** any mxcli project. Triggers whenever `bin/images-to-md.sh` (or the "Images to
read (vision)" line `bin/html-to-md.sh`/`documents-index.md` prints) has left pictures unread.

**Purpose:** Turn "someone should look at the pictures" into a durable file another session can
cite. `bin/images-to-md.sh` is the SCRIPT half: it collects every unique image in the source
corpus (loose files, HTML sidecars, pptx/docx media, PDF objects), dedupes by content, and
writes `analysis/knowledge-base/images/worklist.md` — one entry per image still owed a
description. This skill is the MODEL half: read each pixel, write down what it actually shows,
never what its caption promises (skills-over-scripts.md — judgement never lives in the script).

**Upstream:** `bin/images-to-md.sh <project>` (run after `bin/html-to-md.sh` when the corpus has
HTML) — its worklist is what you read.
**Downstream:** `bin/images-to-md.sh <project> --check` re-reads what you wrote, verifies it,
and — once every image is described — inlines the verbatim text and summary right under the
page's own `![alt](path)` line, so a later session's ONE read of the page covers text and
pictures. `bin/source-ledger.sh mark` (the exact command, with the right `--media` count, is
printed by `--check` once it's clean) records that the container/page was actually read.

---

## Why this exists (2026-09-14)

A 25-slide functional-description deck — 22 distinct PNGs, 1,173 words of slide text — was read
as prose at Stage P. Nobody opened the pictures. Twenty days later, at the point someone finally
did (by hand: `slides.json`, `media/slideNN-N.png`, a README table), the pictures **overturned an
analysis conclusion and closed four open questions** that had sat open the whole time because the
answer was drawn, not typed. The hand capture got the content right but left no per-image file —
nothing downstream could point at "img-014 says X" the way a BRD points at a source line. That is
the gap this skill closes: **one description file per unique image, at a path a citation can name.**

## The template

Write `analysis/knowledge-base/images/<id>.md` (the exact path the worklist gives you) with
these headings, in this order, verbatim:

```markdown
# <id> — <one-line title>

Source: <path from the worklist>
Appears on: <every location the worklist lists for this id>

## Kind
screenshot | diagram | table | photo | logo/chrome | other

## Verbatim text
ALL legible text, in quotes, in reading order. Menus/columns/labels as lists; a table as a
Markdown table. Keep German (or any other language) AS IS — do not translate it.

## Structure
Fields, buttons, states, arrows, columns, legend — what is greyed out, bold, red, disabled.

## Implied requirements and rules
Each one tied to a quoted string from the picture. Never invent a rule the picture does not show.

## Uncertain
Anything illegible or ambiguous, named specifically ("the third column header is cut off by
the window edge" — not "some text is unclear").

## Summary
3–5 lines: what the picture actually shows, versus what its title or caption promises.
```

`--check` verifies exactly these six headings are present, the file is non-empty, and stops
there — it has no opinion on whether the description is *good*, only whether it exists
(skills-over-scripts.md: judgement is this skill's job, never the script's).

## The six rules, and the wrong answer each one prevents

1. **Verbatim, in quotes, never translated.** A description that paraphrases "Status: Aktiv |
   Inaktiv" as "the status field has two values" has already lost the exact string a rule might
   need to reference later. Quote it: `"Status: Aktiv | Inaktiv"`. A German screen stays German.
2. **No inference beyond the pixels.** The wrong answer looks like: a "Submit" button plus a
   red asterisk on "Email" becomes "email is validated server-side with a regex" — nothing in
   the picture says that. The right answer stops at what is drawn: `"Email *"` is present; a red
   asterisk conventionally means required; whether it is enforced how is **not** in this picture
   and belongs in `## Uncertain`, not invented in `## Implied requirements and rules`.
3. **A repeated image is described once.** The worklist already folded duplicates by content
   (sha256) — if `img-005` appears on slide 1 and slide 3, describe it once at
   `images/img-005.md`; both slides get the same file inlined under their own image line by
   `--inline`. Never create a second file for the same picture under a different name.
4. **Write the file, then run `--check`.** Don't report "described" in chat without it —
   `--check` is the mechanical proof (`described N of M`, denominator included), and it is what
   unlocks the printed `bin/source-ledger.sh mark ... --media N` command for that source file.

5. **Personal data in a screenshot is counted, not copied.** A user-management grid full of
   real names, logins and e-mail addresses goes into the file as the column headers plus
   `"<36 rows of user records visible>"` — never the rows. The wrong answer (first field run,
   2026-09-14) was 36 lines of `"Frau", "<surname>", "<first name>", "<login>"` in a file that
   lives in the project repo for good. Roles, flags, station codes and menu labels are not
   personal data; a person's name, login, phone or address is.
6. **Small text misreads — cross-check any string a rule will hang on.** Same field run, Haiku
   reads: a 298px-wide menu gave `"Einfall"` for `Entfall`, a dense grid gave `"benöden"` for
   `beenden`, `"Enfall"`, `"Datensatzgruppung"` for `Datensatzsperrungen`, and one whole column
   of a detail panel (six labelled fields) was skipped. Roughly one string in fifteen on
   small or dense images. So before a quoted string becomes an entity name, a status value or a
   legend meaning in `## Implied requirements and rules`, find it a second time — in the slide
   text, in another image where the same word recurs, or by re-reading the crop — and put a
   string you could not confirm under `## Uncertain` with the reading you got.

## How to dispatch

Two ways to work the worklist, either is fine:

- **Read it yourself.** Open `analysis/knowledge-base/images/worklist.md`, work down the
  sections in order, write each `.md`, then `bin/images-to-md.sh <project> --check`.
- **Fan out to subagents in batches of 5–8 images.** Give each subagent: its slice of the
  worklist (the sections for its batch — id, dimensions, every location, the exact output
  path), this template, and the image file at the `path` the worklist/manifest names. Each
  subagent must return the description file it wrote — not a summary of what it saw — so the
  dispatching session can confirm the file landed before moving to the next batch, and run
  `--check` once every batch reports back. `described N of M` is the completion bound: **N
  equals M, or the pass is not done.**
