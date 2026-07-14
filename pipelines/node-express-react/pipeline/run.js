#!/usr/bin/env node
'use strict';

const { spawn } = require('child_process');
const path      = require('path');
const fs        = require('fs');

const ROOT   = __dirname;
const CONFIG = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
// Per-project analysis folder — see migration-pipeline.md "Project Workspace Convention".
// Falls back to local knowledge-base/ (gitignored) only for standalone testing.
const KB_DIR = CONFIG.knowledgeBaseDir || path.join(ROOT, 'knowledge-base');
fs.mkdirSync(KB_DIR, { recursive: true });

const args  = process.argv.slice(2);
const phase = args[0] || '2';   // '1' | '2' | '3' | 'all'
const only  = args[1] || '';    // 'backend' | 'frontend' | ''

if (!['1', '2', '3', 'all'].includes(phase)) {
  console.error('Usage: node run.js <1|2|3|all> [backend|frontend]');
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
      else console.log(out.trim());
      resolve({ label, ok: code === 0, output: out });
    });
  });
}

async function phase1() {
  console.log('\n=== PHASE 1: Sampling ===');
  console.log('Skipped — no sampler needed for this stack (small, well-structured source).');
}

async function phase2() {
  console.log('\n=== PHASE 2: Full Extraction ===');
  fs.mkdirSync(path.join(ROOT, 'errors'), { recursive: true });

  const jobs = [];
  if (!only || only === 'backend') {
    jobs.push(run('node', [
      path.join('extractors', 'backend-extractor.js'),
      CONFIG.sourceDir,
      KB_DIR,
    ], 'backend-extractor'));
  }
  if (!only || only === 'frontend') {
    jobs.push(run('node', [
      path.join('extractors', 'frontend-extractor.js'),
      CONFIG.sourceDir,
      KB_DIR,
    ], 'frontend-extractor'));
  }

  const results = await Promise.all(jobs);
  const failed  = results.filter(r => !r.ok);
  if (failed.length) {
    for (const r of failed) {
      fs.writeFileSync(path.join(ROOT, 'errors', `${r.label}.log`), r.output, 'utf8');
    }
    console.warn(`Warning: ${failed.length} extractor(s) failed. See errors/ directory.`);
  }

  console.log('\nRunning merger...');
  const { Merger } = require('./lib/merger');
  const merger = new Merger({
    extractedDir:     path.join(KB_DIR, 'extracted'),
    knowledgeBaseDir: KB_DIR,
    logger:           console,
  });
  await merger.run();
  console.log(`Phase 2 complete. Knowledge base: ${KB_DIR}`);
}

async function phase3() {
  console.log('\n=== PHASE 3: BRD Generation ===');
  const { generate } = require('./generators/brd-mappers/index');
  const outDir = path.join(KB_DIR, 'brd');
  const report = await generate(KB_DIR, outDir, { brdGrouping: CONFIG.brdGrouping || {} });
  console.log(`Phase 3 complete. ${report.modulesGenerated} BRD file(s) → ${outDir}`);
  if (report.warnings.length) {
    console.warn(`Warnings: ${report.warnings.length}`);
    report.warnings.forEach(w => console.warn(`  [${w.module}] ${w.issue}`));
  }
}

(async () => {
  if (phase === '1' || phase === 'all') await phase1();
  if (phase === '2' || phase === 'all') await phase2();
  if (phase === '3' || phase === 'all') await phase3();
  console.log('\nDone.');
})().catch(e => { console.error(e); process.exit(1); });
