# Live Demo Autopilot — a scripted demo that runs live, with a control panel to take over

**Applies to:** any mxcli project
**Purpose:** running a customer demo LIVE (no video) where Playwright drives the real app through
scripted scenes, captions say what and why, and the presenter can pause and take over, resume,
redo, skip, restart or stop at any moment.
**Source:** two field builds, 2026-10. Project A: a manufacturing app, desktop window and phone
window side by side, offline web app scenes, 4 scenes / 4 users, all scenes passing. Project B: a
process hub plus two domain apps (three Mendix apps, five personas), 6 scenes / 28 steps; final
test run 28/28 with one app killed mid-run and an 11 minute pause. This skill keeps the best of
both: A's layout, traceability and password-free sign-in, B's reliability layer.

Not this skill: a film someone watches later → `record-demo-video.md` and `demo-recording-polish.md`.
A demo video is not a test; this autopilot IS one — it reports `X/N` steps every run.

## 1. The three pieces

| Piece | Presenter sees | Built as |
|---|---|---|
| **Launcher** | one local page: a light per app, licence minutes left, Start apps / Fresh restart / Start demo / Stop, links to deck and click list | ~140 lines of Node `http`; polls `/api/status` every 3 s; spawns your start scripts; no password passes through it |
| **App window(s)** | the real app, a drawn pointer that glides to each target and ripples on click, a caption plate (step + WHY line), a scene card at each scene start | Playwright, visible Chrome (`channel: 'chrome'`) |
| **Control panel** | scene list with pass/fail dots, the current step, the line to say, the process step and model element on screen | second window with `panel.html`; buttons talk back through `page.exposeBinding('demoCtl', ...)` |

A control file (`ctl.sh pause|resume|redo|skip|restart|stop` appends to `/tmp/<app>-live.ctl`,
polled every 300 ms) lets a clicker, a Stream Deck or a test watcher drive it too.

## 2. The script is data

```js
const SCRIPT = [{ title, why, who, device /* or app */, win, steps: [
  { id, short, cap, why, say, proc, element } ] }];
const ACTIONS = { 'l-list': async page => { /* clicks */ } };   // one function per step id
const BEFORE  = { 3: async () => { /* arm a fault, start a case through the API */ } };
```
- `cap` caption, `why` second caption line (why it matters to the business), `say` presenter line (panel only).
- `proc` the requirement / process step id (e.g. `P4-01`) and `element` the model element on screen
  (`Module.PageName · NF_Submit`): the panel shows both, so every step traces to a requirement.
- Every step lingers ≥ 3 s. Each scene starts with an **anchor** that puts the right user on the
  right page, so Redo and Skip always start from a known state.

## 3. Choose the window layout

| Story | Layout |
|---|---|
| Desktop + phone (offline web app) | two windows side by side, placed with CDP `Browser.setWindowBounds`; arrow pointer on desktop, touch dot on the phone (`matchMedia('(pointer: coarse)')`); offline scenes with `context.setOffline(true)` |
| Many users across several apps | ONE visible window; switch user by swapping session cookies, then click the sidebar link (no reload flash). Count full page loads and report them |

## 4. Sign-in without a password on screen

1. **Best: demo sign-in tiles** in the app (one tap per persona). No password in the script at all.
   Tiles are an authentication bypass: build them only into a demo or dev build, behind a constant
   that is **off by default**, never in a deployed or shared environment, and check that constant
   is off before any deploy.
2. Else: sign in **off screen** in a headless browser and hand the session cookies to the visible
   window. Passwords from env or a gitignored `.env`, never logged. Never parse them out of model
   or seed scripts.
3. Set the persona's UI language during sign-in: a language stored per user survives reseeds,
   and one user left in another language breaks every text selector.

## 5. Reliability rules (each one broke a run before it existed)

1. **Every click goes through `gate()`**: that is where pause, skip, redo and stop take effect.
   After a pause, re-check the session and return to the page — the presenter clicked around.
2. **Same URL is not proof you are there.** Mendix opens forms and detail pages without changing
   the URL; on a list URL require a visible list row before skipping the navigation click.
3. **Off-screen sessions expire** (10 min idle is common; an SSO app then shows its identity-provider
   page). Track last use per persona; idle > 8 min → fresh sign-in before switching. Detect the
   login and SSO pages and recover.
4. **Before each scene, every app must answer.** A dead app is named in the panel and the demo
   waits (5 min) instead of failing on `fetch failed`.
5. **A step that needs state from a skipped step** (a case number) finds it on screen instead.
6. **Tag everything the demo types** (`ZZTEST-LIVE`, `CR-LIVE-<hhmmss>`) so reset-and-seed removes it.
7. **Word guard**: a MutationObserver rewrites words that must never be on screen ("mock" →
   "stand-in") and the run log counts the hits.
8. **Honest summary**: `steps passed X/N failed F gaps G`. A step the UI cannot do is a GAP, never
   a pass. `--proof` saves a screenshot per scene end; read them back.

## 6. Mendix trial-licence traps

| Symptom | Cause | Fix |
|---|---|---|
| App "crashes" after a while: `ERR_EMPTY_RESPONSE`, a defunct java process | the trial licence stops the runtime 2–4 h after start (one field run, 2026-10-30: 2.5 h): `LicenseService: Maximum run time exceeded` in the runtime log. Both trial limits: `load-test.md` §9 | launcher shows minutes left (last "Runtime successfully started" line); **Fresh restart < 1 h before presenting**; the demo warns at start when < 35 min |
| `Maximum number of sessions exceeded` | 6 concurrent sessions; tests leak them | sign out, then **prove it**: the `System.Session` count (OQL) must drop after each logout and be 0 after the run. A 200 proves nothing: `testing-shape.md` (UI, logout helper) measured POST `/xas/` `{"action":"logout"}` returning 200 with the session alive (Mendix 11.14). In the 2026-10-30 field run the same call freed the slot only when sent with the CSRF token, after `mx.session.getConfig().csrftoken` existed, network idle + 1.5 s. If the count does not drop, use `mx.logout()`. Count sessions before starting too |

## 7. Control-path traps

| Symptom | Cause | Fix |
|---|---|---|
| Run sits paused right at the start | the new panel window steals focus; a Space typed elsewhere lands in it | tag key commands `key:`; ignore them for 3 s after the panel opens and in unattended runs (`--no-keys`) |
| Stop leaves sessions behind | Playwright closes the browsers on SIGTERM before your handler signs out | `chromium.launch({ handleSIGTERM: false, handleSIGINT: false, handleSIGHUP: false })`; freeze `gate()` while signing out |
| `mx.session.getConfig()` throws | session not loaded yet | call it inside try/catch in `waitForFunction` |

## 8. Prove the autopilot before the customer does

```bash
node live-demo.mjs --proof --exit-when-done --no-keys > run.out   # unattended run
```
Inject the failures that will happen on the day with a watcher that reacts to **log lines**, not
timers (a timer drifts): kill an app after scene N and restart it once the log says `APP DOWN`;
`ctl.sh pause` for 11 min after scene M, then resume. Pass = `X/N` with the denominator, and
the session count back to 0 after the run. Write the result to a report file.

## 9. Optional: change it live

The strongest close: approve a small change request in the room, then show it built, on a
**copy or branch** of the demo model, never the one the scenes run on. Before
screenshot → CR script → `mxcli check` → `bin/exec.sh` → restart → after screenshot. Pick a
one-page change (a column, a caption) and keep a spare; anything needing a new attribute on a
row object goes to the next change round, not the stage.

## Portability

Proven on macOS only (window placement, `open`, `pgrep`). Resolve Playwright with
`createRequire` from your global install instead of a hard-coded path. Windows: not field-run yet.
