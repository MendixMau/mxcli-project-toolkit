#!/usr/bin/env node
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs   = require('fs');

const ROOT   = __dirname;
const CONFIG = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
// Per-project analysis folder (see migration-pipeline.md's "Project Workspace Convention") —
// falls back to a local knowledge-base/ (gitignored) only if config.json has no knowledgeBaseDir set.
const KB_DIR = CONFIG.knowledgeBaseDir || path.join(ROOT, 'knowledge-base');
fs.mkdirSync(KB_DIR, { recursive: true });

const args   = process.argv.slice(2);
const phase  = args[0] || '1';          // '1' | '2' | '3' | 'all'
const only   = args[1] || '';           // 'java' | 'angular' | ''

if (!['1', '2', '3', 'all'].includes(phase)) {
  console.error('Usage: node run.js <1|2|3|all> [java|angular]');
  process.exit(1);
}

function run(cmd, cmdArgs, label) {
  return new Promise((resolve) => {
    console.log(`  [START] ${label}`);
    const child = spawn(cmd, cmdArgs, { cwd: ROOT, shell: true, stdio: 'pipe' });
    let out = '';
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { out += d; });
    child.on('close', code => {
      const status = code === 0 ? 'OK' : 'FAILED';
      console.log(`  [${status}] ${label}`);
      if (code !== 0) console.log(out.trim());
      resolve({ label, ok: code === 0, output: out });
    });
  });
}

async function phase1() {
  // No samplers yet — this pilot source is small enough (3 backend domains, ~9 Angular
  // screens) that schema sampling wasn't needed to write the extractors. Add
  // samplers/{java,angular}-sampler.js here first if a future, larger source needs it.
  console.log('\n=== PHASE 1: Sampling ===');
  console.log('Skipped — no samplers built yet for this stack (see comment in run.js).');
}

async function phase2() {
  console.log('\n=== PHASE 2: Full Extraction ===');
  fs.mkdirSync(path.join(ROOT, 'errors'), { recursive: true });

  const jobs = [];
  if (!only || only === 'java')
    jobs.push(run('node', [path.join('extractors', 'java-extractor.js'), CONFIG.javaSourceDir, KB_DIR], 'java-extractor'));
  if (!only || only === 'angular')
    jobs.push(run('node', [path.join('extractors', 'angular-extractor.js'), CONFIG.angularSourceDir, KB_DIR], 'angular-extractor'));

  const results = await Promise.all(jobs);
  const failed = results.filter(r => !r.ok);

  if (failed.length) {
    for (const r of failed) {
      fs.writeFileSync(path.join(ROOT, 'errors', `${r.label}.log`), r.output, 'utf8');
    }
    console.warn(`Warning: ${failed.length} extractor(s) failed. Check errors/ directory.`);
  }

  console.log('\nRunning merger...');
  await run('node', [path.join('lib', 'merger.js')], 'merger');
  console.log(`Phase 2 complete. Knowledge base: ${KB_DIR}`);
}

async function phase3() {
  console.log('\n=== PHASE 3: BRD Generation ===');
  const { generate } = require('./generators/brd-mappers/index');
  const kbDir  = KB_DIR;
  const outDir = path.join(KB_DIR, 'brd');
  const report = await generate(kbDir, outDir, {});
  console.log(`Phase 3 complete. ${report.modulesGenerated} BRD files → ${outDir}`);
  if (report.warnings.length) console.warn(`Warnings: ${report.warnings.length}. See ${path.join(outDir, 'generation-report.json')}`);
}

(async () => {
  try {
    if (phase === '1' || phase === 'all') await phase1();
    if (phase === 'all') {
      console.log('\nPhase 1 done. Review samples/schema.json, then press Enter to continue Phase 2...');
      await new Promise(r => process.stdin.once('data', r));
    }
    if (phase === '2' || phase === 'all') await phase2();
    if (phase === '3') await phase3();
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
})();
