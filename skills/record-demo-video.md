# Record a Demo Video — narrated screen recording of a running app

**Applies to:** any mxcli project
**Purpose:** producing a screen recording a human will actually watch — a
narrated product demo, not a test artifact — with a repeatable technique for
opening on the app instead of a blank frame, and for keeping narration synced
to what's on screen.
**Source:** field-tested on a live mxcli project's Playwright demo-recording
script (mobile tour, two roles), 2026-09.

## When to use this skill

- The user asks for a demo, a recording, a walkthrough video, or "show me the
  app".
- You are about to write or change a recording script (pacing, captions,
  steps, trimming) — read this first.
- A recording came back and the feedback was some version of *"nothing
  happens"*, *"you're not explaining the steps"*, or *"it feels robotic"*.

For assertion-style browser testing use `e2e-harness-base.md` instead. A demo
video **is not a test**: it must never fail a build, and its job is to be
legible to a person who has never seen the app.

## The nine rules

### 1. Open on the app, never on a blank frame

Playwright's `recordVideo` starts recording when the **context** is created,
not when the first pixel paints. A cold Mendix client can take 10–20s to boot,
and every second of that lands at the head of the video as a blank gradient.
This is the single most common complaint about a generated demo: *"the first
20 seconds nothing happens."*

**Do not trim by the clock.** Playwright's video timeline does not track
wall-clock time. Measured on the source project: a lead-in measured at 13.0s
of wall clock landed roughly 28s into the recording, and after trimming 13s
off the head the login form still hadn't painted until 15.1s of video time.
Four successive clock-derived offsets all produced a blank frame 0. A
clock-based trim is a guess, not a measurement.

**Use a clapper board instead** — a marker painted into the picture itself,
which cannot drift relative to the frames:

1. Warm up on a throwaway, non-recorded context (navigate, wait for the
   password field, close). This shortens the boot but does not make it
   predictable — keep it anyway, it's still worth the time it saves.
2. Create the recorded context, navigate, wait for the login form to be
   visible.
3. Flash a full-viewport slab of an unmistakable colour, **forcing the
   compositor to actually submit frames while it's up**:

   ```js
   const CLAP_RGB = [255, 0, 255]; // magenta — nothing in the app is this
   async function clap(page) {
     await page.evaluate(({ rgb }) => {
       const d = document.createElement('div');
       d.id = '__e2e-clap';
       d.style.cssText = `position:fixed;inset:0;z-index:2147483647;background:rgb(${rgb.join(',')})`;
       document.body.appendChild(d);
     }, { rgb: CLAP_RGB }).catch(() => {});
     // Chromium's screencast is driven by compositor frame submission, not by
     // a timer: an idle page that changes once and then sits still can submit
     // NO new frame at all, and the marker never reaches the video. Measured —
     // a 1.5s magenta slab held with only a background colour change produced
     // zero magenta frames in the recording; the same slab with
     // page.screenshot() taken repeatedly over it showed up cleanly, because
     // a screenshot forces a raster. Force several across the hold.
     for (let i = 0; i < 6; i++) {
       await page.screenshot().catch(() => {});
       await page.waitForTimeout(200);
     }
     await page.evaluate(() => document.getElementById('__e2e-clap')?.remove()).catch(() => {});
     for (let i = 0; i < 3; i++) {
       await page.screenshot().catch(() => {});
       await page.waitForTimeout(150);
     }
   }
   ```

4. In post, decode the raw video small and fast and find the **last** frame
   that is the marker colour. That timestamp plus a small settle is the true
   start:

   ```js
   // ffmpeg -i raw.webm -vf fps=10,scale=16:16,format=rgb24 -f rawvideo -
   // → scan each 16x16x3 frame; marker if R>200 && B>200 && G<90
   const trim = clapEnd >= 0 ? clapEnd + 0.25 : fallbackFromClock;
   ```

   Keep the clock-derived value only as a fallback for when the scan finds no
   marker at all (an errored run, or a browser that never painted).

5. **Do the precise cut during a re-encode, not a stream copy.** `ffmpeg -ss
   <t> -i in.webm -c copy out.webm` can only land on a keyframe — with a long
   lead-in it silently rewinds to the keyframe *before* the clapper, which can
   put the clapper flash itself back at frame 0. Use the stream copy only to
   cheaply drop the bulk of the lead-in (seek to a couple of seconds *before*
   the clapper, not to it), then find the clapper again in that shorter file
   and make the frame-accurate cut on the re-encode pass:

   ```bash
   # cheap: drop most of the lead-in, keep the clapper inside the result
   ffmpeg -y -ss <trim - 2.0> -i raw.webm -c copy short.webm
   # precise: re-encode with an accurate -ss found from the clapper in short.webm
   ffmpeg -y -ss <clapEndInShort + 0.35> -i short.webm -c:v libx264 -preset veryfast \
     -crf 26 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -movflags +faststart out.mp4
   ```

Dead air in the **middle** is a separate problem and the clock cannot help
there either. Find it with `freezedetect`, which reports `freeze_start` /
`freeze_duration` / `freeze_end` on **stderr**:

```bash
ffmpeg -i trimmed.webm -vf "freezedetect=n=-55dB:d=5" -f null - 2>&1 | grep freeze
```

Keep ~1.5s of each freeze and drop the rest with a `select`/`setpts` pair. On
the source project that squeezed 6–20s out of a 100–150s tour without cutting
a single caption short.

Two things that do **not** work, so don't spend time on them: `signalstats`
metadata printing emitted nothing in the ffmpeg build tested (neither `-vf
signalstats,metadata=print` nor `ffprobe -f lavfi -i "movie=…,signalstats"`),
and a "first non-frozen frame" head anchor just re-derives the same wrong
offset the clock gives you.

Also check what your own login helper does. On the source project,
`loginOnce()` began with `clearCookies()` + `page.goto()`, which forced a
**second** full client cold boot after the recorder had already navigated —
invisible in a headless test run, 13 extra seconds of blank screen in a
recording. Skip the navigation when a login form is already on screen; there
is no session to clear anyway.

Check the result before shipping it — extract the first frames and look:

```bash
for t in 0 1 3; do ffmpeg -y -loglevel error -ss $t -i out.mp4 -frames:v 1 f_$t.png; done
```

Frame 0 must show the app.

### 2. Two-beat narration — the caption always matches the pixels

A caption written once per step and left up through a navigation narrates a
screen the viewer has already moved past. Watching frame-by-frame you see
"Opening a technique." over a detail page that opened four seconds ago, and
the demo reads as unnarrated even though captions are rendering.

Every step is **two** captions:

| Beat | When | Length | Example |
|------|------|--------|---------|
| **Intent** | *before* the click | short, 1.2–1.5s | "Next, the schedule." |
| **Landing** | *after* the new screen paints | fuller, 2.2–2.8s | "Plan. Every class this week, with spots left and who is coaching." |

Build this into the helper so it cannot be forgotten:

```js
async function tapTab(page, tabName, intent, landed) {
  await say(page, intent, 1200);
  await H.humanClick(page, w(page, tabName));
  await page.waitForTimeout(ms(2200));
  if (landed) await say(page, landed, 2400);
}
```

The same shape applies to a form save: intent ("Saving it."), then the landing
beat that says what *changed* ("Saved — the new entry is at the top of the
log, and it feeds the streak and the monthly stats on Home.").

### 3. The caption strip must not cover the app

A strip pinned at `bottom: 0` sits on top of whatever the app puts at the
bottom of the screen — on a Mendix mobile layout that's typically the bottom
tab bar, which a naively-added caption strip hides for the whole video.

Fix it in the injected CSS, not by moving the caption somewhere worse: give
the strip a known height and lift the app's own bottom chrome by exactly that
much.

```css
#__e2e-banner { position: fixed; bottom: 0; min-height: 92px; }
.bottom-tabs { bottom: 92px !important; }   /* sticky bottom:0 -> sits above the strip */
.fab         { bottom: calc(96px + 92px) !important; }
.main        { padding-bottom: calc(96px + 92px) !important; }
```

Verify by extracting a frame from a tabbed page and looking for the tab
labels.

### 4. Make each caption *read as a new caption*

Text swapped in place looks like one long static banner. Three cheap signals
turn a strip into narration:

- a **step counter** (`07/34`) so the viewer knows where they are and that
  something advanced;
- a **short entry animation** on text change (~0.34s fade + 7px rise) —
  restart it by removing the class, forcing a reflow, re-adding it;
- a **dwell timer bar** across the top of the strip, animated to the exact
  hold duration, so the pace is visible.

### 5. Human speed is a number, not a vibe

Dwell must be long enough to *read*. A caption of N words needs roughly
`N / 2.5` seconds plus ~0.6s of settle. In practice:

| Beat | Hold |
|------|------|
| Short intent ("Adding a technique.") | 1.2–1.4s |
| Landing description of a screen | 2.2–2.8s |
| A caveat or a bug callout the viewer must absorb | 3.2–4.0s |
| After a click, before the landing caption | 1.4–2.2s |

Type with a human-like per-character delay and click with an animated
cursor-move-then-press helper — instant `fill()` and `click()` read as a
machine. Inject a visible cursor: a click with no visible pointer is invisible
on playback.

### 6. Show scrolling

A demo that never scrolls is a slide deck of screenshots — the viewer never
learns the page continues below the fold. On every content-rich screen,
scroll slowly down through the content and back up:

```js
async function showcase(page, distance = 320) {
  await humanScroll(page, { distance, axis: 'down' });
  await page.waitForTimeout(ms(900));
  await humanScroll(page, { distance, axis: 'up' });
  await page.waitForTimeout(ms(500));
}
```

Target the app's real scroll port, not `window` — on a Mendix page with Atlas
UI that's `.mx-scrollcontainer-center`; scrolling `window` does nothing.

### 7. Show state changing, don't just claim it

The moments worth recording are the ones where the app *responds*: a Book
button turning into Cancel, a favourite toggle flipping, a saved row appearing
at the top of a list, a badge incrementing. Structure each act so the video
contains before → action → after, and let the landing caption name the
change. A demo of pure navigation proves nothing works.

### 8. Only real user paths, and show the warts

- Navigate the way a user can. If a page is only reachable from a desktop
  menu, do not deep-link to it on a phone recording — say so in a caption
  instead ("Messages exists, but only in the desktop menu"). A screen the
  user cannot reach is not a feature.
- When a known bug is on the path, **record it and caption it** rather than
  editing around it. A demo that hides a blocking overlay is a demo nobody can
  trust. Caption it plainly, do the workaround on camera, carry on.
- When the environment — not the app — is the reason something looks broken,
  say which, and be specific about what you actually verified rather than
  guessing. Worked example: a technique page's embedded `youtube.com/embed`
  iframe rendered correctly in the DOM, but the recording ran inside a sandbox
  whose egress proxy denied most of the domains a YouTube embed needs beyond
  the page shell itself (`www.google.com`, `accounts.google.com`, and
  crucially the per-video `*.googlevideo.com` CDN host that serves the actual
  media bytes — opening just `www.youtube.com` + `i.ytimg.com` was not
  enough), and the bundled headless Chromium had no H.264 decoder either. That
  belongs in the caption; without it, the viewer reads a working feature as a
  broken one.

### 9. Deterministic demo data, every time

Tours write to the database, so run N leaves litter that run N+1 shows.
Before every recording:

1. Clean up what previous runs created (a project-specific cleanup script).
2. Re-apply the masterdata the demo depends on. Key seeds on a **business
   key**, never on object ids: ids only hold for one database, and an
   id-keyed seed silently updates nothing after a rebuild.
3. Restart or reload the app — direct SQL bypasses the runtime's object
   cache (see `demo-data.md` / the project's own data skill).

Also undo state the *tour itself* toggles. A favourite left on from the last
run hides the "Favourite" button, and the step silently vanishes from the
recording.

---

## Structure of a good tour

Aim for **90–150 seconds** per role, 25–35 narrated beats. Longer and it stops
being watched; shorter and nothing is explained.

```
Open        1 beat    Name the app and the role.        "BJJ App -- the practitioner's view. Signing in."
Per screen  2-5 beats intent -> land -> showcase (scroll) -> one interaction -> its result
Gaps        1 beat    Anything the viewer would look for and not find.
Close       1 beat    "That's the practitioner's app. Signing out."
```

Order the screens the way a user's day runs, not the way the nav happens to
be sorted.

## Instrumentation you always want

- **A step index in the console log.** The run log is the shooting script; a
  reviewer reads it in seconds instead of scrubbing the video.
- **Never let a step silently no-op.** `locator.isVisible()` does *not*
  poll — it checks once, immediately, regardless of any `{timeout}` passed.
  Use `waitFor({ state: 'visible' })` and log loudly when the element never
  came:

  ```js
  async function visible(page, locator, what, timeout = 20000) {
    const ok = await locator.waitFor({ state: 'visible', timeout }).then(() => true).catch(() => false);
    if (!ok) console.log(`    (skipped -- ${what} did not appear within ${timeout}ms)`);
    return ok;
  }
  ```

  A skipped step is a hole in the demo; it must be loud, not silent.
- **Always sign out at the end.** An unlicensed Mendix runtime caps
  concurrent sessions and a killed browser does **not** release one — leak a
  few and the next recording cannot log in at all.

## Delivering the file

- Ship **`.mp4`** (H.264, `+faststart`). The raw `.webm` Playwright produces
  will not preview in most chat clients or on iOS.
- Commit both files under the project's test-artifacts directory — they are
  the review record for that commit.
- Before sending, sanity-check the artifact rather than trusting the run log:
  duration, and a handful of frames.

  ```bash
  ffprobe -v error -show_entries format=duration -of csv=p=0 out.mp4
  for t in 0 15 45 90; do ffmpeg -y -loglevel error -ss $t -i out.mp4 -frames:v 1 f_$t.png; done
  ```

  You are looking for: frame 0 shows the app; every sampled frame has a
  caption that matches what is on screen; the app's own bottom chrome is not
  covered.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| First ~20s blank | `recordVideo` starts at context creation; cold runtime | Rule 1 — warm up, clapper board, trim |
| Frame 0 still blank after trimming the measured lead-in | Playwright's video timeline does not track wall-clock time | Rule 1 — trim from the clapper, never from the clock |
| Clapper never found in the recording even though it painted in the DOM | Chromium's screencast submits frames on compositor activity, not on a timer; an idle page with one style change can submit zero new frames | Rule 1 — force rasters with `page.screenshot()` across the hold |
| Frame 0 is the clapper flash itself, not the app | A stream-copy `-ss` can only land on a keyframe and silently rewinds past the requested cut point | Rule 1 — cut cheaply well before the clapper with `-c copy`, then make the precise cut on the re-encode pass |
| 13s of blank bolted on *after* the trim | `loginOnce()` re-navigates and forces a second client cold boot | Rule 1 — skip the goto when a login form is already up |
| Long still stretches mid-video | Waits for slow pages, unavoidable at record time | Rule 1 — `freezedetect` + `select`/`setpts` squeeze |
| "You're not explaining the steps" | One caption per step, left up through the navigation | Rule 2 — two-beat narration |
| Bottom tab bar invisible all video | Caption strip pinned over the app's bottom chrome | Rule 3 — lift the app chrome by the strip's measured height |
| Video reads as static | No scrolling, no state changes, captions never visibly change | Rules 4, 6, 7 |
| A step is missing from the recording | `isVisible()` used instead of `waitFor`, or leftover state from the last run | Instrumentation + Rule 9 |
| An embedded YouTube video's frame is black | Sandbox egress opened only the page-shell domain, not the CDN host that serves media (`*.googlevideo.com`), and/or the headless browser has no H.264 decoder | Not an app defect — caption it (Rule 8); confirm which domains are actually open before assuming egress alone will fix it |
