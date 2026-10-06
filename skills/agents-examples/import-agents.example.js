'use strict';
// ============================================================================
// Agent import driver — upload .agent.json through Agents ▸ Import
// ----------------------------------------------------------------------------
// WHAT THIS DOES. Read this before reaching for it as a fix.
//
// The import is a two-dialog flow:
//
//   1. "Import Agent With File"        — file input + Import
//   2. "Check Agent settings after import"
//          Agent version in use      [ v1 · IN USE ]
//          Model for the selected version  [ combobox ]
//          [ Not now ]  [ Confirm ]
//
// Dialog 2 is the ONLY place in the app where a deployed model is bound to an
// agent version, so this script is the agent half of GenAI configuration, not
// merely a bulk-loader for new agents. It reports the contents of that model
// combobox per file, because an EMPTY list is the whole diagnosis: it means
// GenAICommons has no DeployedModel rows, which means the MxCloud keys imported
// without models (see configure-genai.js), which means every agent will render
// a chat panel and answer nothing.
//
// On the object itself a re-import is a no-op. AgentCommons.Agent_GetCreate_AgentImport
// retrieves an Agent by the UUID in the uploaded JSON and returns it UNCHANGED when one
// exists. So re-importing creates no duplicate and makes NO EDIT — an edited prompt or
// setting in the file silently does not land. What a plain re-import is good for is
// reaching dialog 2 to (re)bind a model. To make an edited file land, REPLACE=1 deletes
// the agent with the same Title first (row menu > Delete), then imports.
//
// Usage (copy next to the harness helpers.js; TEST_USER needs AgentCommons.AgentAdmin):
//   node tests/e2e/import-agents.js [outDir] [file.agent.json ...]
//   AGENT_MODEL='<caption>'   pick that model in dialog 2 instead of the first
//   REPLACE=1                 delete the agent with the same Title first (row menu > Delete), so an
//                             edited JSON actually lands. Without it a changed file is silently ignored
//                             (the import matches on UUID and keeps the old object). Dev data only.
// Defaults to every resources/agents/*.agent.json in the project.
//   AGENTS_URL                the Agents overview (AgentCommons.Agent_Overview), default /p/agents
//
// Exit 1 when: the model combobox is not found, a file reaches dialog 2 with no model to
// bind, or AGENT_MODEL matches no option. Each of those leaves an agent that answers nothing
// while the run itself looks clean.
//
// Field run 2026-10-06 (Mendix 11.15, Agent Commons 4.3.1): a single-call agent replaced and
// bound to a Sonnet 5 model; OQL on AgentCommons.Version read the binding back; the app's
// chat then answered 3/3 questions from the model.
// ============================================================================
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..', '..');
const BASE = process.env.APP_BASE || `http://localhost:${process.env.APP_PORT || 8080}`;
const H = require('./helpers.js');               // the toolkit e2e harness: login() reads TEST_USER/TEST_PASS
const AGENTS_URL = process.env.AGENTS_URL || '/p/agents';
const WANT_MODEL = process.env.AGENT_MODEL || null;

const args = process.argv.slice(2);
const OUT = (args[0] && !args[0].endsWith('.json'))
  ? args.shift()
  : path.join(__dirname, 'artifacts', 'screenshots', 'agent-import');
fs.mkdirSync(OUT, { recursive: true });

const FILES = args.length ? args.map((f) => path.resolve(f)) : (() => {
  const dir = path.join(ROOT, 'resources', 'agents');
  return fs.readdirSync(dir).filter((f) => f.endsWith('.agent.json')).map((f) => path.join(dir, f));
})();

const REPLACE = /^(1|true|yes)$/i.test(process.env.REPLACE || '');

// Delete the agent row titled `title` through its row menu, then confirm. Returns what happened.
async function deleteAgent(page, title) {
  const row = page.locator('[role="row"]', { hasText: title }).first();
  if (!(await row.isVisible({ timeout: 3000 }).catch(() => false))) return 'absent';
  // A JS click does not open the popup menu; it needs a real pointer click on the trigger.
  await row.locator('.popupmenu-trigger').click();
  const del = page.locator('.popupmenu-custom-item', { hasText: /^\s*Delete\s*$/ }).first();
  if (!(await del.isVisible({ timeout: 5000 }).catch(() => false))) return 'no-delete-item';
  await del.click();
  await page.waitForTimeout(1500);
  // Confirmation: a Mendix dialog (never a browser alert). Take its affirmative button.
  const r = await jsClickByText(page, '.modal-dialog, .mx-dialog', /^(delete|yes|ok|confirm|proceed)$/);
  await page.waitForSelector('.mx-underlay', { state: 'detached', timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2500);
  return 'deleted (' + r + ')';
}

let shotN = 0;
async function shot(page, name) {
  shotN += 1;
  const f = path.join(OUT, `${String(shotN).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f });
  console.log('  shot:', path.basename(f));
}

// Mendix lays a .mx-underlay over the document for every modal, so a physical
// pointer click is intercepted. Fire the DOM click on the real element instead.
function jsClickByText(page, scopeSel, re) {
  return page.evaluate(({ scopeSel, reSrc }) => {
    const scope = scopeSel ? document.querySelector(scopeSel) : document;
    if (!scope) return 'no-scope';
    const rx = new RegExp(reSrc, 'i');
    const b = [...scope.querySelectorAll('button')].find((x) => rx.test(x.innerText || ''));
    if (!b) return 'no-button';
    b.click();
    return 'clicked';
  }, { scopeSel, reSrc: re.source });
}

function jsClickNav(page, title) {
  return page.evaluate((t) => {
    const a = [...document.querySelectorAll('.mx-navigationtree a')]
      .find((x) => x.getAttribute('title') === t);
    if (!a) return false;
    a.scrollIntoView({ block: 'nearest' });
    a.click();
    return true;
  }, title);
}

async function drainDialogs(page, { max = 4 } = {}) {
  const seen = [];
  for (let i = 0; i < max; i += 1) {
    const dlg = page.locator('.mx-dialog, .modal-dialog').filter({ has: page.locator('button:text-is("OK")') }).first();
    if (!(await dlg.isVisible({ timeout: 1200 }).catch(() => false))) break;
    seen.push((await dlg.innerText().catch(() => '')).replace(/\s+/g, ' ').trim());
    await jsClickByText(page, null, /^OK$/);
    await page.waitForTimeout(600);
  }
  return seen;
}

// Titles currently listed in the Agents grid. This is a DataGrid2
// (.widget-datagrid): it renders neither <td> nor .mx-datagrid2, and an earlier
// selector built on those reported an empty grid while two agents were plainly
// on screen. Read [role="row"] and drop the header.
async function agentTitles(page) {
  return page.evaluate(() => {
    const grid = document.querySelector('.widget-datagrid') || document;
    return [...grid.querySelectorAll('[role="row"]')]
      .map((r) => (r.innerText || '').split('\n')[0].trim())
      .filter((t) => t && t !== 'Title');
  });
}

// Dialog 2's model combobox. Opening it is the only way to see the options, so
// this both enumerates and (optionally) selects. Returns { options, picked }.
async function chooseModel(page, want) {
  const opened = await page.evaluate(() => {
    // AgentCommons 4.3.x: the class .combobox-model-selection is gone. Take the combobox under the
    // "Model for the selected version" label, else the last combobox in the open dialog.
    let input = document.querySelector('.combobox-model-selection .widget-combobox-input');
    if (!input) {
      const dlg = [...document.querySelectorAll('.modal-dialog, .mx-dialog')].pop();
      const groups = dlg ? [...dlg.querySelectorAll('.form-group, .mx-compound-control, div')] : [];
      const g = groups.find((x) => /model for the selected version/i.test(x.querySelector('label')?.innerText || '') && x.querySelector('.widget-combobox'));
      const boxes = dlg ? [...dlg.querySelectorAll('.widget-combobox')] : [];
      const box = g ? g.querySelector('.widget-combobox') : boxes[boxes.length - 1];
      input = box && (box.querySelector('.widget-combobox-input') || box.querySelector('input') || box);
    }
    if (!input) return false;
    input.click();
    return true;
  });
  if (!opened) return { options: null, picked: null };  // dialog shape changed
  await page.waitForTimeout(1200);

  const options = await page.evaluate(() =>
    [...document.querySelectorAll('.combobox-model-selection [role="option"], .widget-combobox-menu-list [role="option"], .widget-combobox-menu [role="option"], [role="listbox"] [role="option"]')]
      .map((o) => (o.innerText || '').trim())
      .filter(Boolean));

  let picked = null;
  if (options.length) {
    picked = await page.evaluate((w) => {
      const opts = [...document.querySelectorAll('.combobox-model-selection [role="option"], .widget-combobox-menu-list [role="option"], .widget-combobox-menu [role="option"], [role="listbox"] [role="option"]')];
      const target = w ? opts.find((o) => (o.innerText || '').includes(w)) : opts[0];
      if (!target) return null;
      target.click();
      return (target.innerText || '').trim();
    }, want);
  } else {
    // Close the empty menu so it does not swallow the next click.
    await page.keyboard.press('Escape').catch(() => {});
  }
  await page.waitForTimeout(800);
  return { options, picked };
}

(async () => {
  console.log('Importing:', FILES.map((f) => path.basename(f)).join(', '));
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    headless: process.env.HEADED ? false : true,
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(25000);
  const summary = { before: [], after: [], perFile: [] };

  try {
    await H.login(page);
    await page.goto(BASE + AGENTS_URL);
    await page.waitForTimeout(3500);
    await shot(page, 'agents-overview-before');
    summary.before = await agentTitles(page);
    console.log('Agents before:', JSON.stringify(summary.before));

    for (const file of FILES) {
      const name = path.basename(file);
      const stem = name.replace(/\.agent\.json$/, '');
      const uuid = (() => { try { return JSON.parse(fs.readFileSync(file, 'utf8')).UUID; } catch { return null; } })();
      console.log(`\n${name} (UUID ${uuid || 'unreadable'}): importing…`);
      if (REPLACE) {
        const title = (() => { try { return JSON.parse(fs.readFileSync(file, 'utf8')).Title; } catch { return null; } })();
        if (title) {
          console.log('   replace:', await deleteAgent(page, title), '→ agents now', JSON.stringify(await agentTitles(page)));
          await shot(page, `after-delete-${stem}`);
        }
      }

      // ── dialog 1: file ──
      if ((await jsClickByText(page, '.mx-page, .mx-name-mainGrid', /^\s*import\s*$/)) !== 'clicked') {
        throw new Error('Import button not found on Agents overview');
      }
      await page.waitForSelector('.modal-dialog input[type="file"]', { timeout: 20000 });
      await shot(page, `import-dialog-${stem}`);
      await page.locator('.modal-dialog input[type="file"]').first().setInputFiles(file);
      await page.waitForTimeout(1500);
      await jsClickByText(page, '.modal-dialog', /^import$/);
      await page.waitForTimeout(3500);

      // ── dialog 2: agent settings / model binding ──
      const rec = { file: name, uuid, modelOptions: null, modelPicked: null, dialogs: [] };
      const settings = page.locator('.modal-dialog').filter({ hasText: /Check Agent settings after import/i }).first();
      if (await settings.isVisible({ timeout: 8000 }).catch(() => false)) {
        rec.reachedDialog2 = true;
        await shot(page, `settings-dialog-${stem}`);
        const { options, picked } = await chooseModel(page, WANT_MODEL);
        rec.modelOptions = options;
        rec.modelPicked = picked;
        console.log('   model options:', options === null ? '(combobox not found)' : JSON.stringify(options));

        // Confirm only binds something when a model was actually picked;
        // otherwise dismiss, so we never confirm an empty binding.
        await jsClickByText(page, '.modal-dialog', picked ? /^confirm$/ : /^not now$/);
        await page.waitForTimeout(2500);
      } else {
        console.log('   no settings dialog appeared');
      }

      rec.dialogs = await drainDialogs(page);
      rec.dialogs.forEach((m) => console.log('   dialog:', m));

      // Anything still standing gets closed.
      await jsClickByText(page, '.modal-dialog', /^(cancel|close|not now)$/);
      await page.waitForSelector('.mx-underlay', { state: 'detached', timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(1500);
      summary.perFile.push(rec);
      await shot(page, `after-import-${stem}`);
    }

    summary.after = await agentTitles(page);
    console.log('\nAgents after:', JSON.stringify(summary.after));
    await shot(page, 'agents-overview-after');
  } finally {
    // The trial runtime caps concurrent sessions; a run that never logs out
    // burns a slot and the next run's valid password reads as "Sign in failed".
    await page.evaluate(() => window.mx && mx.logout && mx.logout()).catch(() => {});
    await page.waitForTimeout(1200);
    await browser.close();
  }

  fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 2));
  const added = summary.after.filter((t) => !summary.before.includes(t));
  console.log(added.length ? `\nNew agents: ${added.join(', ')}` : '\nNo new agents (expected for a re-import or a REPLACE of the same Title).');

  // An import that reaches dialog 2 with an empty model list has NOT produced a
  // working agent, however cleanly it ran. Say so with a non-zero exit.
  const noBox = summary.perFile.filter((r) => r.reachedDialog2 && r.modelOptions === null);
  if (noBox.length) {
    console.error(`\nFAIL: the model combobox was not found in dialog 2 for ${noBox.map((r) => r.file).join(', ')} —`);
    console.error('the dialog markup changed (Agent Commons 4.3.x dropped .combobox-model-selection). Nothing was bound.');
    process.exit(1);
  }
  const notPicked = summary.perFile.filter((r) => WANT_MODEL && Array.isArray(r.modelOptions) && r.modelOptions.length && !r.modelPicked);
  if (notPicked.length) {
    console.error(`\nFAIL: AGENT_MODEL='${WANT_MODEL}' matched no option for ${notPicked.map((r) => r.file).join(', ')}; "Not now" was clicked.`);
    process.exit(1);
  }
  const noModels = summary.perFile.filter((r) => Array.isArray(r.modelOptions) && r.modelOptions.length === 0);
  if (noModels.length) {
    console.error(`\nFAIL: ${noModels.length} agent(s) had NO model to bind — GenAICommons has no`);
    console.error('DeployedModel rows. Run configure-genai.js and check runtime.log for');
    console.error('"Host not in allowlist"; the keys import but the models never arrive.');
    process.exit(1);
  }
})().catch((e) => { console.error('import-agents FAILED:', e.message); process.exit(1); });
