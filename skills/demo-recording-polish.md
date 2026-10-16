# Demo recording polish — 60 fps capture, a visible cursor, eased scrolling, zoom afterwards

**Applies to:** any project that records a demo film with Playwright (see `record-demo-video.md`)
**Purpose:** making a recorded walkthrough look produced rather than captured: smooth motion, a
pointer the viewer can follow, scrolling that glides, and a camera that pushes in where a page is
dense. The style is the one Screen Studio made familiar.
**Helpers:** `project-tests/e2e/demo-polish.js` (installed as `tests/e2e/demo-polish.js`), with
its selftest `demo-polish.selftest.js`. No dependencies beyond Playwright and ffmpeg.
**Source:** field run on a three-app Mendix demo, 2026-10-15. One read-only scene was recorded
both ways against the same data. The measurements are in "What it measured" below.

## When to use this skill

- A film is being recorded and someone will watch it: a pitch, a customer demo, a LinkedIn cut.
- Feedback on a film was "it looks janky", "I can't see where it clicks", "the scroll jumps", or
  "I can't read that table".
- Not for test evidence. A journey video that only has to prove a path ran does not need any of
  this.

`record-demo-video.md` still owns the content rules: opening on the app, narration synced to the
pixels, human speed, deterministic data, checking claims against frames. This skill owns how the
picture moves.

## Why the default recording looks rough

Playwright's `recordVideo` is built for test evidence, not film. In playwright-core 1.59 its
`videoRecorder.js` encodes at a fixed **25 fps** with `vp8 -deadline realtime -speed 8 -b:v 1M`,
so the result is 25 fps at 1 Mbit/s. Fine text smears, and motion steps. On top of that, the
usual scripts:

- scroll with `scrollIntoView({behavior:'smooth'})`, which has the browser's duration and curve
  and cannot be tuned, or with raw `mouse.wheel` jumps, which teleport;
- show no pointer, so a click is a page that changes for no visible reason;
- have no way to zoom. A 1920 px dashboard shown at 1920 px is unreadable on a laptop screen,
  and even more so on a phone.

## The method

### 1. Capture: CDP screencast at device pixels, assembled at 60 fps

```js
const polish = require('./demo-polish');
const browser = await chromium.launch({args: polish.launchArgs(2)});
const ctx = await browser.newContext({viewport: {width: 1920, height: 1080}, deviceScaleFactor: 2});
await polish.prepare(ctx);                 // cursor, ripple and scroll helpers; survive navigation
const page = await ctx.newPage();
// ... log in and set up off camera ...
const rec = await polish.startCapture(page, {dir: 'take/'});
// ... the scene ...
await rec.stop();                          // frames/*.jpg + frames.json + events.json
```

- `Page.startScreencast` sends a JPEG each time the compositor paints, with a wall-clock
  timestamp. `rec.stop()` writes the timestamps beside the frames, and the assembler gives each
  frame its real duration, then resamples to a constant 60 fps (`libx264 -crf 18 -preset slow`,
  yuv420p, tagged bt709). Narration offsets stay wall-clock, the same as before: a line said at
  `t` lands at `t`.
- **The screencast ignores `deviceScaleFactor`.** Measured: with `deviceScaleFactor: 2` alone,
  the frames are 1920x1080, in both the headless shell and new headless. Only the launch flag
  `--force-device-scale-factor=2` (`polish.launchArgs(2)`) makes it send 3840x2160 frames.
  Without the flag, a 1.75x zoom upscales a 1097 px crop to 1920 px and the text goes soft.
  `frames.json` records `meta.frameSize`. Check it.
- The capture starts when you call `startCapture`, so the take starts on the app. The clapper
  board in `record-demo-video.md` rule 1 is only needed for `recordVideo`.
- Idle stretches produce no frames. That is correct: the last frame is held until the next paint.
  `polish.sourceStats(dir)` reports the gaps between frames during motion. That number, not the
  container's 60/1, is the real smoothness.

### 2. In the page: eased scroll, a drawn cursor, a click ripple

| Helper | What it does | Knobs (in `KNOBS`) |
|---|---|---|
| `scrollTo(page, loc, {block})` | requestAnimationFrame scroll of the element's **real scroll container** (on Mendix that is `.mx-scrollcontainer-*`, never `window`), easeInOutCubic | duration `clamp(400 + 0.5 × px, 600, 1400)` ms, then wait 400–600 ms |
| `moveTo(page, x, y)` | drawn arrow cursor glides on a slightly bowed cubic Bezier; the real pointer lands at the end, so hover states are real | 500–900 ms per move by distance; arrow 30 px tall at 1080p |
| `click(page, loc, {zoom, park})` | scroll if needed → glide → pause → ripple → real `mouse.click` → park | pause 150–250 ms; ripple: a dark 4 px ring with a white halo, 0→60 px over 450 ms, opacity held near 0.9 to half-way, then 0. The zoom region is measured **after** the click, once the target is visible. Then the cursor parks (`park: false` to stay) |
| `park(page, {near})` | rests the cursor beside `near` (the next target), or in the nearest side gutter, 32 px in from the edge | 800 ms glide, 450 ms after a click |
| `focus(page, loc)` | a camera note without a click: "this region is worth a zoom" | — |
| `bottomPad(page, px)` | tells the scroller a fixed caption band covers the bottom px, so "center" means the visible area | — |

The cursor is a DOM overlay at the top z-index with `pointer-events:none`. It is captured at 2x,
like everything else, so it stays sharp under a 1.75x zoom.

### 3. Zoom afterwards, never in the page

The recorder does not zoom. It logs `{t, kind, bbox}` for every click, focus and scroll to
`events.json`. `render()` plans the camera from that log and draws every output frame on a
canvas from a fractional source rectangle:

```js
await polish.render('take/', 'take.mp4', {fps: 60, keepBottom: 120}); // writes take/shots.json too
polish.assemble('take/', 'flat.mp4');                                 // same frames, no camera
```

Why afterwards:

- **A CSS transform on the page breaks the page.** `position:fixed` caption bands become
  relative to the transformed ancestor, popups and dropdowns land in the wrong place, and
  hit-testing for the next click moves.
- **Re-framing becomes a re-render, not a re-shoot.** The camera is a pure function of the log.
  Change a knob, run `render` again; the app is not touched. That matters for any scene that
  changes data.
- **Plain ffmpeg `zoompan` judders.** It rounds the crop to whole source pixels each frame, and a
  slow push-in visibly steps. Drawing the frame with `drawImage` at fractional coordinates
  removes the stepping. The compositor runs in headless Chromium, so it needs nothing beyond
  Playwright. It served the frames over a `page.route` origin because file:// images taint the
  canvas.
- **A kept bottom band stays still.** `keepBottom: 120` composites the bottom 120 px (the caption
  strip) unzoomed over the zoomed picture, and frames the region inside the area above it.

### Camera rules (enforced by the planner, checked by the selftest)

| Rule | Value |
|---|---|
| Zoom | fit the **element itself** with 8% padding per side, **capped at 1.75x**; a region that only earns < 1.25x gets **no** zoom (a full-width grid is not "dense", it is wide) |
| Push-in | starts 400 ms before the click, lasts 700 ms, easeInOutCubic |
| Hold | at least 2 s after the last note, or until the narration line ends (`say` → `holdUntil`) |
| Zoom-out | 800 ms |
| One zoom per shot | notes less than 2.5 s apart merge into one shot framing all of them |
| No cursor-follow | the camera holds still while the cursor moves inside the shot |
| Boundaries | the camera must be back at 1x **before** the next scroll or unzoomed cursor move starts; a shot that cannot hold 800 ms before then is dropped, not squeezed |
| Centred or nothing | the target's centre must land within 0.5 ± 0.2 of the zoomed frame (`shots.json` records `u`, `v`). Near a frame edge the camera clamps and the target slides off-centre, and a lower zoom only widens the rect and makes that worse, so an edge target gets no zoom |
| Cut targets | a target partly outside the frame is clipped to what shows and never zoomed past 1.25x |
| Narration holds | a line playing when the shot starts, or starting during it, keeps the shot until the line ends (bounded by the next scroll or move) |
| Ends zoomed out | every take ends at 1x; a note too close to the end is dropped |

Dropped notes are listed in `shots.json` → `skipped` with the reason. Read them: a note that
never zoomed is a decision the planner made for you.

`zoom: true` on a click frames a region of at least 960x540 around the click (~1.7x), not the
bare button: a 1.75x push-in on a 140 px button is a close-up of a button. Pass a Locator to
frame a specific card or grid instead: the grid, not the pane around it, or a short grid
leaves the bottom of the zoom empty.

## Cursor and outline

- **Park between actions.** A cursor left where it last clicked sits on the content the viewer is
  reading. `click` parks it in the side gutter by default; before a beat whose target is known,
  `park(page, {near: next})` puts it just beside that target, so the next glide is short.
- **No outline on clicked elements.** The cursor and ripple already say "here". Keep an outline
  only for point-at beats with no click.

## Where to zoom

- Zoom where the viewer must **read** something small: a KPI row, a filter on a grid, a status
  chip, a table's first rows. Don't zoom on navigation or on a page's first appearance.
- Aim for one or two zooms a minute. A camera that zooms on every click feels nervous.
- Never zoom over a page that is about to change. Click → navigate is a 1x moment.

## Verify — the numbers and the stills

```bash
ffprobe -v error -select_streams v -show_entries stream=r_frame_rate,avg_frame_rate,width,height -of compact take.mp4
node tests/e2e/demo-polish.js stats take/      # capture fps, frame-gap p50/p90 during motion
node tests/e2e/demo-polish.selftest.js         # camera rules
for t in 3 9 15 21; do ffmpeg -y -loglevel error -ss $t -i take.mp4 -frames:v 1 still-$t.png; done
```

Look at five stills: mid-scroll, cursor plus ripple, each zoomed hold, the cursor at rest, and the last frame
(must be at 1x). Things to look for: a zoom framing the wrong area (the region moved after the
note), a zoomed target off-centre (`u`/`v` in `shots.json`), a cursor resting on content or a tooltip, the caption band doubled (`keepBottom` missing), soft text
(`frameSize` is 1920 wide, so the launch flag is missing).

## What it measured

One read-only scene in a Mendix app, 82 s (hub → two tabs → a graph page), recorded both ways
against the same data on 2026-10-16 (1920x1080 viewport, playwright-core 1.59.1, headless
Chromium on macOS). The changed-frame counts use ffmpeg `mpdecimate=hi=64*4:lo=64*2:frac=0.1`.
The two takes differ by a few hundred ms in their timing, so the windows are approximate for the old take.

| | old path (`recordVideo` → mux) | new path (`demo-polish`) |
|---|---|---|
| ffprobe | h264 1920x1080, `r_frame_rate=30/1`, nb_frames 2466, 4.63 MB (source webm vp8 `25/1`) | h264 1920x1080, `r_frame_rate=60/1`, nb_frames 4940, 5.75 MB |
| Changed frames, whole clip | 223/2466 | 761/4940 |
| Changed frames, 1.3 s cursor glide + click | 1/39 (no cursor; only the page change) | 33/78 |
| Changed frames, 0.8 s scroll | 6/24 | 32/48 |
| Changed frames, 1.0 s push-in | — (no camera) | 57/60 |
| Source frames | 1920x1080 | 3840x2160; frame gap during motion p50 22.6 ms, p90 31 ms |
| Camera | none | 2 shots: 1.256x on a 4-row grid (u .49, v .54), 1.379x on a network canvas (u .50, v .51); each held to its narration line's end (14 s, 10 s); 0 skipped |
| Render | — | 53 s for 82 s of 60 fps output |

Read it honestly:

- **The motion is about 44 Hz in a 60 fps container.** A Mendix page painting at 4K is the limit:
  the p50 gap is 22.6 ms. On a light local page the same capture managed 16–18 ms, and JPEG
  quality 88, 70 and 55 changed nothing. The assembler repeats frames to reach 60.
- **Zooms show neighbours cut at the frame edge.** The target is whole and centred, but slivers
  of the cards beside it are cut by the frame. That is what a zoom is; it is not a framing error.
- **Edge cards get no zoom.** In this app the facts card and the footprint card sit against a
  frame edge. A 1.75x zoom put the facts card off-centre in the first round, so both became
  point-at beats with an outline.
- **The ripple is deliberately neutral.** An orange ripple vanished against an orange highlight
  outline the recorder already drew. Keep the ripple's colour away from any highlight colour.
- **Re-framing really is a re-render.** A planner bug (a narration hold logged 1 s before the
  push-in was ignored, so a zoom held 2 s instead of 14) was fixed and re-rendered from the same
  take without touching the app.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Zoomed text is soft | screencast frames at 1920x1080 although `deviceScaleFactor: 2` | launch with `polish.launchArgs(2)`; check `meta.frameSize` |
| `toDataURL` "Tainted canvases may not be exported" | compositor page loads frames over file:// | serve them over `page.route` (the helper does) |
| The zoom shows the page after it scrolled away | camera hold crossed a scroll | the planner treats scroll starts as boundaries; log scrolls through `scrollTo`, not raw `mouse.wheel` |
| Caption band appears twice or zoomed | bottom band zoomed with the page | `render(..., {keepBottom: <band px>})` |
| A planned zoom never happened | region too wide (< 1.25x) or no room to hold before the next move | read `shots.json` → `skipped` |
| Stutter despite "60 fps" in ffprobe | the container is 60/1, the source painted less often | `stats` gap p90; lower JPEG quality or the DSF if p90 is far above 16.7 ms |
| `scrollTo` does nothing | the element's scroll container is not `window` and has no overflow | the helper walks up to the first scrollable ancestor; check the page really scrolls |
| Ripple invisible in the take | ripple colour equals a highlight outline on the same element, or opacity faded out within the first frames | `KNOBS.rippleColor` contrasting with every highlight; keep opacity up to mid-animation |
| `boundingBox` timeout on a zoom Locator | the region (a tab pane, a dialog) is hidden until the click | the helper measures the region after the click and waits up to 5 s for it to be visible |
| The first zoom is cut short | a zoom note at t≈0, or a scroll right after it | give the scene ~1.5 s at 1x first and about 3.5 s after the note before the next scroll |
| A zoom slid off-centre against a frame edge | the camera clamps at the edge; lowering the zoom widens the rect and makes it worse | the planner skips targets outside the centre band (`centreBand`); make the beat a point-at, or pick an element away from the edge |
| A zoom held 2 s although the line runs on | the narration hold was logged before the push-in started | fixed: any line playing at the shot's start holds it; re-render the take |
