'use strict';
// Pipeline config resolution — one place, so run.js, merger.js and generate-report.js cannot
// disagree about which file they read.
//
// The tracked pipeline/config.json is a TEMPLATE. A project keeps its own copy in its own repo
// (suggested: <project-root>/analysis/<source-name>/pipeline-config.json) and points the
// pipeline at it, so the shared toolkit clone is never edited and two projects can run side by
// side (real incident: the only way to run was to overwrite the tracked file with real local
// paths, in a clone several sessions share — issue #643).
//
// Lookup order (first hit wins):
//   1. --config <path> / --config=<path> on the command line
//   2. MXTK_PIPELINE_CONFIG environment variable
//   3. pipeline/config.json (the template) — only runs if its paths are real, see below
//
// Relative paths inside a project config resolve against the config file's own directory, so a
// project config can say "knowledgeBaseDir": "knowledge-base" and stay portable.
const fs   = require('fs');
const path = require('path');

const PIPELINE_ROOT = path.join(__dirname, '..');
const TEMPLATE_PATH = path.join(PIPELINE_ROOT, 'config.json');
const PATH_KEYS = ['javaSourceDir', 'angularSourceDir', 'dbDir', 'knowledgeBaseDir', 'blueprintDir',
                   'projectRoot', 'appSummaryFile'];
const PLACEHOLDER_RE = /\/path\/to\/your|<[a-z-]+>/i;

/** Splits `--config X` / `--config=X` out of argv; returns { configArg, rest }. */
function splitConfigArg(argv) {
  const rest = [];
  let configArg = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--config') { configArg = argv[++i] || ''; continue; }
    if (a.startsWith('--config=')) { configArg = a.slice('--config='.length); continue; }
    rest.push(a);
  }
  return { configArg, rest };
}

function resolvePaths(config, baseDir) {
  const abs = (v) => (typeof v === 'string' && v && !path.isAbsolute(v)) ? path.resolve(baseDir, v) : v;
  for (const k of PATH_KEYS) if (config[k]) config[k] = abs(config[k]);
  if (Array.isArray(config.sources)) {
    for (const s of config.sources) {
      if (s.javaSourceDir)    s.javaSourceDir    = abs(s.javaSourceDir);
      if (s.angularSourceDir) s.angularSourceDir = abs(s.angularSourceDir);
    }
  }
  return config;
}

function placeholderPaths(config) {
  const vals = PATH_KEYS.map(k => config[k]);
  for (const s of (config.sources || [])) vals.push(s.javaSourceDir, s.angularSourceDir);
  return vals.filter(v => typeof v === 'string' && PLACEHOLDER_RE.test(v));
}

/**
 * Loads the pipeline config. Returns { config, configPath, isTemplate }.
 * Throws with a usable message when the file is missing, or when it is the untouched template.
 */
function loadConfig({ argv = [], env = process.env } = {}) {
  const { configArg } = splitConfigArg(argv);
  const chosen = configArg || env.MXTK_PIPELINE_CONFIG || '';
  const configPath = chosen ? path.resolve(chosen) : TEMPLATE_PATH;
  if (!fs.existsSync(configPath)) {
    throw new Error(`pipeline config not found: ${configPath}` +
      (configArg ? ' (from --config)' : chosen ? ' (from MXTK_PIPELINE_CONFIG)' : ''));
  }
  const config = resolvePaths(JSON.parse(fs.readFileSync(configPath, 'utf8')), path.dirname(configPath));
  const isTemplate = configPath === TEMPLATE_PATH;
  const placeholders = placeholderPaths(config);
  if (placeholders.length) {
    throw new Error(`pipeline config ${configPath} still has placeholder paths (${placeholders[0]}). ` +
      'Copy pipeline/config.json into your project (e.g. <project-root>/analysis/<source-name>/pipeline-config.json), ' +
      'fill it in, and run with --config <that file> or MXTK_PIPELINE_CONFIG=<that file>. ' +
      'Do not edit the tracked template in the shared toolkit clone.');
  }
  return { config, configPath, isTemplate };
}

module.exports = { loadConfig, splitConfigArg, resolvePaths, TEMPLATE_PATH, PIPELINE_ROOT };
