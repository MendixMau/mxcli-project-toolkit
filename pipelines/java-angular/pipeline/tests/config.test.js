'use strict';
// Issue #643: config is project-owned; the tracked pipeline/config.json is a template.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { loadConfig, splitConfigArg, TEMPLATE_PATH } = require('../lib/config');

function projectConfig(obj) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ja-proj-'));
  const file = path.join(dir, 'pipeline-config.json');
  fs.writeFileSync(file, JSON.stringify(obj));
  return { dir, file };
}

test('splitConfigArg strips both flag spellings and keeps positional args', () => {
  assert.deepStrictEqual(splitConfigArg(['2', '--config', 'a.json', 'java']), { configArg: 'a.json', rest: ['2', 'java'] });
  assert.deepStrictEqual(splitConfigArg(['--config=b.json', '3']), { configArg: 'b.json', rest: ['3'] });
});

test('--config wins over MXTK_PIPELINE_CONFIG; relative paths resolve against the config file', () => {
  const a = projectConfig({ javaSourceDir: 'src/main/java', knowledgeBaseDir: 'kb', sources: [{ name: 'x', javaSourceDir: 'svc/java' }] });
  const b = projectConfig({ knowledgeBaseDir: 'other' });
  const { config, configPath, isTemplate } = loadConfig({ argv: ['2', '--config', a.file], env: { MXTK_PIPELINE_CONFIG: b.file } });
  assert.strictEqual(configPath, a.file);
  assert.strictEqual(isTemplate, false);
  assert.strictEqual(config.knowledgeBaseDir, path.join(a.dir, 'kb'));
  assert.strictEqual(config.javaSourceDir, path.join(a.dir, 'src', 'main', 'java'));
  assert.strictEqual(config.sources[0].javaSourceDir, path.join(a.dir, 'svc', 'java'));
  assert.strictEqual(loadConfig({ argv: [], env: { MXTK_PIPELINE_CONFIG: b.file } }).config.knowledgeBaseDir, path.join(b.dir, 'other'));
});

test('the untouched tracked template is refused with a pointer to --config', () => {
  assert.ok(fs.existsSync(TEMPLATE_PATH));
  assert.throws(() => loadConfig({ argv: [], env: {} }), /placeholder paths.*--config/s);
  assert.throws(() => loadConfig({ argv: ['--config', '/nonexistent/x.json'], env: {} }), /not found.*from --config/);
});

test('run.js end to end with a project-local config: extracts and never touches the template', () => {
  const before = fs.readFileSync(TEMPLATE_PATH, 'utf8');
  const src = path.join(__dirname, 'fixtures', 'openwms', 'openwms-tms', 'src', 'main', 'java');
  const p = projectConfig({ javaSourceDir: src, angularSourceDir: '', knowledgeBaseDir: 'kb' });
  const env = { ...process.env };
  delete env.MXTK_PIPELINE_CONFIG;
  execFileSync(process.execPath, [path.join(__dirname, '..', 'run.js'), '2', 'java', '--config', p.file], { env, stdio: 'pipe' });
  assert.ok(fs.existsSync(path.join(p.dir, 'kb', 'extracted', 'java.json')));
  assert.ok(fs.existsSync(path.join(p.dir, 'kb', 'logics.json')), 'merger child read the same project config');
  assert.strictEqual(fs.readFileSync(TEMPLATE_PATH, 'utf8'), before);
  const refused = spawnSync(process.execPath, [path.join(__dirname, '..', 'run.js'), '2'], { env, encoding: 'utf8' });
  assert.strictEqual(refused.status, 1);
  assert.match(refused.stderr, /--config/);
});
