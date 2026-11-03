Repo: mendixlabs/mxcli
Source: toolkit issue #284 (field retro 2026-10-12, three apps under `mxcli run --local --watch`) and its 2026-10-14 recurrence comment; related toolkit issues #275, #282, #285, #337
Status: **DRAFT — NOT FILED**. Not retested on a neutral app yet, and no duplicate search of mendixlabs/mxcli done: do both before filing. Every number below comes from the field run's watch output and runtime logs as recorded in #284; nothing was re-measured for this draft.

--- everything above this line is stripped before filing ---

**Title:** `run --local --watch`: a theme-only rebuild deletes `dist/pages` and reports a successful reload

## Environment

- mxcli **v0.26.0**
- Mendix **11.15.0**
- `mxcli run --local --watch`, one app per localhost port, three apps in one field run

## Bug: a theme-only rebuild deletes the page bundles

1. Start an app with `mxcli run --local --watch` and open any page.
2. Edit any `theme/web/*.scss` file.
3. Watch prints "Change detected, rebuilding", and the reload reports success.
4. `deployment/web/dist/pages/` is now gone. Only `chunks/` and `index.js` remain.
5. Every page fails in the browser with
   `Failed to fetch dynamically imported module ... dist/pages/<Page>.js`
   (a 404 in the runtime log). The user sees "An error occurred".

Reproduced on two consecutive theme-only builds in one app (2026-10-14). A full restart of
`mxcli run` restored all 135 page bundles every time. The same symptom appeared in the first run
(2026-10-12): one SCSS edit dropped the `deployment/web/pages` bundles (404s), and another left a
grid column at 24 px instead of the stored 120/240 until a restart.

**Expected:** a theme-only rebuild either regenerates `dist/pages`, or prints "restart needed"
instead of reporting a successful reload.

**Cost beyond the 404s:** the only fix is a restart, and each restart signs every user out. One
app's runtime log shows 7 starts in about 90 minutes of theme work.

## Other changes watch does not apply

In the same run, these edits were not picked up while the app was already running. The
implementer saw the old behaviour until the app was restarted:

- a microflow dropped and recreated (the old version kept serving);
- a new microflow grant;
- a new attribute, stored or calculated;
- a `Url` added to an existing page (the route table predates it; the deep link lands on Home);
- a new page.

While stale, the app showed symptoms that look like real defects: security errors on pages, a
`NoClassDefFoundError` for a widget class, and a picker error. Each cost a diagnosis round before
anyone suspected a stale runtime. 16 task-ledger lines carry a needs-restart status, roughly 26
restarts across the three apps.

## Timings (watch output, 79 build lines, one night, three apps)

| Build class | Builds | Median | Max | Total |
|---|---|---|---|---|
| reload | 35 | 3.8 s | 8.3 s | not recorded |
| restart | 44 | 19.2 s | 55.2 s | 928 s |

Also in the same night: 39 cold starts of the run command.

## Questions

1. Which change classes need a restart and which a reload? Can watch detect the restart classes
   and print "restart needed" (or restart by itself) instead of serving stale code?
2. Why is a restart-class build about 5× a reload (median 19.2 s against 3.8 s)?
3. After a microflow is dropped and recreated, does the runtime keep serving the old compiled
   version by name? What would make watch pick up the new one?

## Workaround in use

Stop the app, edit the theme, start it again. For the other classes, restart the app after the
edit. The restart itself is cheap once someone knows it is needed; the expensive part is telling
a stale runtime from a real defect.
