'use strict';

const path = require('path');
const { BaseExtractor, ExtractionResult } = require('../lib/interfaces');
const { ASTParser } = require('../lib/ast-parser');

const API_CALL_PATTERN = '(call_expression function: (member_access_expression name: (identifier) @name))';
const FUNC_PATTERN     = '(function_declaration name: (identifier) @name)';
const ARROW_PATTERN    = '(variable_declarator name: (identifier) @name)';

class JsExtractor extends BaseExtractor {
  constructor(deps) { super(deps); this.astParser = new ASTParser(); }
  get supportedExtensions() { return ['.js']; }

  async run(filePaths, _options = {}) {
    const start = Date.now();
    const items  = [];
    const errors = [];

    for (const filePath of filePaths) {
      try {
        const { tree } = this.astParser.parseFile(filePath, 'javascript');
        const functions = [
          ...this.astParser.query(tree, FUNC_PATTERN),
          ...this.astParser.query(tree, ARROW_PATTERN),
        ];
        const apiCalls = this.astParser.query(tree, API_CALL_PATTERN)
          .map(n => n.text)
          .filter(name => /^(get|post|put|delete|fetch|ajax|call)/i.test(name));

        if (functions.length || apiCalls.length) {
          items.push({
            type:       'js-module',
            linkId:     `js:module:${path.basename(filePath, '.js')}`,
            name:       path.basename(filePath, '.js'),
            functions:  functions.map(n => n.text),
            apiCalls:   [...new Set(apiCalls)],
            _source:    filePath,
          });
        }
      } catch (err) {
        this.logger.error(`[js-extractor] Failed: ${filePath} — ${err.message}`);
        errors.push({ file: filePath, error: err.message });
      }
    }

    return new ExtractionResult({
      source: 'js',
      items,
      errors,
      meta: { fileCount: filePaths.length, itemCount: items.length, duration: Date.now() - start }
    });
  }
}

if (require.main === module) {
  const { FileReader } = require('../lib/file-reader');
  const fs = require('fs');
  const [,, dir] = process.argv;
  const reader    = new FileReader();
  const extractor = new JsExtractor({ fileReader: reader, logger: console });
  (async () => {
    const files = await reader.glob(dir || '.', '**/*.js');
    console.error(`Extracting from ${files.length} JS files...`);
    const result = await extractor.run(files, {});
    fs.mkdirSync('knowledge-base/extracted', { recursive: true });
    fs.writeFileSync('knowledge-base/extracted/js.json', JSON.stringify(result, null, 2));
    console.error(`Done. Items: ${result.items.length}, Errors: ${result.errors.length}`);
  })();
}

module.exports = { JsExtractor };
