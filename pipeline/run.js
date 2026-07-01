#!/usr/bin/env node
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs   = require('fs');

const ROOT   = __dirname;
const CONFIG = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));

const args   = process.argv.slice(2);
const phase  = args[0] || '1';          // '1' | '2' | 'all'
const only   = args[1] || '';           // 'xml' | 'cs' | 'js' | 'db' | 'excel' | 'docs' | ''

if (!['1', '2', '3', 'all'].includes(phase)) {
  console.error('Usage: node run.js <1|2|3|all> [xml|cs|js|db|excel|docs]');
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
  console.log('\n=== PHASE 1: Sampling ===');
  fs.mkdirSync(path.join(ROOT, 'samples'), { recursive: true });

  const jobs = [];
  if (!only || only === 'xml')
    jobs.push(run('node', [path.join('samplers', 'xml-sampler.js'), CONFIG.blueprintDir, '8'], 'xml-sampler'));
  if (!only || only === 'cs')
    jobs.push(run('node', [path.join('samplers', 'cs-sampler.js'), path.join(CONFIG.shareDir, 'Outsystems_output_sourcecode', 'full'), '10'], 'cs-sampler'));
  if (!only || only === 'js')
    jobs.push(run('node', [path.join('samplers', 'js-sampler.js'), path.join(CONFIG.shareDir, 'Outsystems_output_sourcecode', 'full', 'scripts'), '10'], 'js-sampler'));
  if (!only || only === 'db')
    jobs.push(run('python', [path.join('samplers', 'db-sampler.py'), CONFIG.dbDir, '--sample-n', '5'], 'db-sampler'));
  if (!only || only === 'excel')
    jobs.push(run('python', [path.join('samplers', 'excel-sampler.py'), CONFIG.docsDir, '--sample-n', '5'], 'excel-sampler'));
  if (!only || only === 'docs')
    jobs.push(run('python', [path.join('samplers', 'doc-sampler.py'), CONFIG.docsDir, '--sample-n', '5'], 'doc-sampler'));

  const results = await Promise.all(jobs);
  const failed = results.filter(r => !r.ok);

  // Merge individual schema JSONs
  const schemas = {};
  for (const f of fs.readdirSync(path.join(ROOT, 'samples')).filter(n => n.endsWith('-schema.json'))) {
    const key = f.replace('-schema.json', '');
    try { schemas[key] = JSON.parse(fs.readFileSync(path.join(ROOT, 'samples', f), 'utf8')); } catch (_) {}
  }
  fs.writeFileSync(path.join(ROOT, 'samples', 'schema.json'), JSON.stringify(schemas, null, 2), 'utf8');

  console.log(`\nPhase 1 complete. schema.json written.`);
  if (failed.length) console.warn(`Warning: ${failed.length} sampler(s) failed: ${failed.map(r => r.label).join(', ')}`);
}

async function phase2() {
  console.log('\n=== PHASE 2: Full Extraction ===');
  fs.mkdirSync(path.join(ROOT, 'errors'), { recursive: true });

  const jobs = [];
  if (!only || only === 'xml')
    jobs.push(run('node', [path.join('extractors', 'xml-extractor.js'), CONFIG.blueprintDir], 'xml-extractor'));
  if (!only || only === 'cs')
    jobs.push(run('node', [path.join('extractors', 'cs-extractor.js'), path.join(CONFIG.shareDir, 'Outsystems_output_sourcecode', 'full')], 'cs-extractor'));
  if (!only || only === 'js')
    jobs.push(run('node', [path.join('extractors', 'js-extractor.js'), path.join(CONFIG.shareDir, 'Outsystems_output_sourcecode', 'full', 'scripts')], 'js-extractor'));
  if (!only || only === 'db')
    jobs.push(run('python', [path.join('extractors', 'db-extractor.py'), CONFIG.dbDir], 'db-extractor'));
  if (!only || only === 'excel')
    jobs.push(run('python', [path.join('extractors', 'excel-extractor.py'), CONFIG.docsDir], 'excel-extractor'));
  if (!only || only === 'docs')
    jobs.push(run('python', [path.join('extractors', 'doc-extractor.py'), CONFIG.docsDir], 'doc-extractor'));

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
  console.log(`Phase 2 complete. Knowledge base: ${path.join(ROOT, 'knowledge-base')}`);
}

async function phase3() {
  console.log('\n=== PHASE 3: BRD Generation ===');
  const { generate } = require('./generators/brd-mappers/index');
  const kbDir  = path.join(ROOT, 'knowledge-base');
  const outDir = path.join(ROOT, 'knowledge-base', 'brd');
  const report = await generate(kbDir, outDir, { blueprintDir: CONFIG.blueprintDir });
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
