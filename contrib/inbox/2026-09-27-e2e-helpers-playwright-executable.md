# project-tests/e2e/helpers.js: no executablePath fallback when the pinned browser is missing

**Source:** marketplace-rnd `tests/e2e/helpers.js` (2026-09-27). **Status:** unreviewed.

In cloud containers the pinned headless shell (rev 1243) is absent; only
`/opt/pw-browsers/chromium` (1194) exists, so every e2e launch fails before testing anything.
Project fix:
```js
const exe = process.env.PW_EXECUTABLE
  || (require('fs').existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
if (exe) launchOpts.executablePath = exe;
```
Port to the shipped helper (env override first; probe path second).
