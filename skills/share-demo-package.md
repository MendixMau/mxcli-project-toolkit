# Shipping a demo package outside the repo

**Applies to:** any mxcli project that sends a demo guide, screenshots or a quickstart doc to
someone outside the working tree — customer, prospect, SME reviewer, a colleague on email
**Purpose:** make the package survive the trip. Everything that works because the file is sitting
in your repo — relative image paths, "the name shown above", a token you happen to have — is
exactly what breaks once the file is detached from it.

## The failure this exists to prevent

Two defects shipped in one package on a real project (2026-09-02, MOC/PSSR app replacement).
Neither was visible from inside the repo, and both were found by the customer:

| What the sender saw | What the customer got |
|---|---|
| A guide with eight annotated screenshots, opened from the repo folder | A guide with **eight broken image boxes** — `<img src="beat3.png">` resolves to nothing once the HTML travels alone |
| A cast table reading "Somchai · Initiator", and a fallback section saying "sign in manually with the account name shown above" | A login rejected. The real account name was `demo.initiator`; the customer typed `Somchai`, then `Admin`, and stopped |

Both files *rendered perfectly* on the sender's machine. That is the whole trap: the working tree
supplies the missing half, and only the recipient ever sees the package as it actually is.

**The rule.** A shared package is broken until it has been checked in the shape it will be
received: one file, no repo, no you.

## Step 1 — inline every image; do not ship a relative path

A delivered HTML file has no sibling files. Email strips them, file-delivery tools send one
artifact, a customer forwards the attachment and not the folder. So every `<img>` carries its
bytes:

```html
<img src="data:image/png;base64,iVBORw0KGgoAAAANS..." alt="Step 2 — submit the request">
```

Encode from wherever the screenshots actually live in your project (`base64 -w0 <file>` on Linux,
`base64 -i <file>` on macOS) and substitute each `src`. Keep the originals in the repo; the
inlined copy is the delivered artifact.

**Done when both greps agree, and you state the denominator:**

```sh
ls <screenshot-dir>/*.png | wc -l          # N — the images the guide is supposed to carry
grep -c 'data:image/png;base64' <guide>    # must equal N
grep -c '\.png"' <guide>                   # must be 0 — any survivor is a path that will break
```

`8 / 8 / 0` is a pass. `8 / 8 / 2` is not — two images are still reaching for the folder. Anything
other than an exact match is a fail, including "the extra ones are just decorative".

Same rule for CSS, fonts and logos: inline, or drop them. A stylesheet `<link>` to a repo path
degrades quietly, which is worse than an image — the guide still renders, just unstyled, and
nobody reports it.

## Step 2 — the guide lists real usernames, read fresh from the model

A demo login panel shows whatever display name it was given; the sign-in field wants the account
name. These differ in most projects, and the difference is invisible to the person who built it.

Never write the list from memory or from the character names in the BRD. Read it from the model,
then cross-check it against the page the customer will actually be looking at:

1. Ask the model: `mxcli ... SHOW DEMO USERS` (or your project's equivalent query — see
   `skills/query-the-model.md`). This is the authority for what exists.
2. Grep the login page itself for the attribute that carries the username into the sign-in field.
   **Find that attribute; do not assume this project's.** The theme file, its name and the
   attribute all vary per project:

   ```sh
   grep -rn 'data-user\|data-username\|data-login\|value=' <theme-web-dir>/*.html
   ```

   One project's panel used `data-user="demo.initiator"` on each character button; yours may use
   a `value=`, a JS array, or nothing at all — in which case the panel is not the authority and
   step 1 is.
3. Reconcile the two lists. A name in the model that the panel does not offer, or a panel entry
   that the model does not have, is a finding to fix before sending — not a footnote.

Then write the table with **both columns and the username first**, and say the quiet part out loud:

> Sign in with the **username** (left column), not the display name. The display name is only the
> label on the demo panel.

**Done when:** every row of the cast table carries a username that appeared in *both* the model
query and the login page grep — count them and say so ("6 of 6 reconciled") — and any
"sign in manually" fallback section names the usernames inline rather than pointing at
"the name shown above". A cross-reference to information the reader cannot see is the same defect
as a broken image path.

## Step 3 — every credential is issued for this recipient

Any MCP/API token, key or connection string in the package is replaced with one issued fresh for
that specific recipient. Never an internal test token, never a shared one, never the placeholder
left in the template.

```sh
grep -rn 'token\|api[_-]key\|secret\|Bearer\|<YOUR_\|xxx' <package-dir>
```

**Done when:** every hit is either a value issued for this recipient today, or a placeholder the
recipient is explicitly told to replace and *cannot* mistake for a working value. A live-looking
token that is actually yours is worse than a blank — it half-works, and it is yours.

## Step 4 — the pre-send check, in the receiving shape

Copy the package to an empty directory outside the repo, open it there, and read it as the
recipient. This is the only step that catches what the other three missed.

- [ ] Guide opened from a directory containing **only** the delivered file(s) — all images visible
- [ ] `data:image/png;base64` count == PNG count; `\.png"` count == 0
- [ ] Every username in the guide reconciled against model **and** login page (N of N)
- [ ] The guide says "use the username, not the display name" in the words a reader will hit first
- [ ] No cross-reference to information not present in the package ("shown above", "in the repo",
      "see the other file")
- [ ] Every credential issued for this recipient; no internal or test token in the diff
- [ ] Every file the covering message promises is attached — a quickstart that references a guide
      it was not sent with is the step-2 defect at package level

A box you cannot tick is a send you do not make. "Probably fine" is how both of the defects above
shipped.
