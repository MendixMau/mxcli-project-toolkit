'use strict';

const path = require('path');
const { BaseExtractor, ExtractionResult } = require('../lib/interfaces');
const { ASTParser } = require('../lib/ast-parser');

const SAP_NAMESPACES = ['SAP', 'SapConnector', 'BAPI', 'RFC'];

class CsExtractor extends BaseExtractor {
  constructor(deps) { super(deps); this.astParser = new ASTParser(); }
  get supportedExtensions() { return ['.cs']; }

  async run(filePaths, _options = {}) {
    const start = Date.now();
    const items  = [];
    const errors = [];

    for (const filePath of filePaths) {
      try {
        const { tree, src } = this.astParser.parseFile(filePath, 'csharp');
        const classes = this.astParser.query(tree, '(class_declaration name: (identifier) @name)');

        for (const cls of classes) {
          const methods = this.astParser.query(cls.parent || tree.rootNode,
            '(method_declaration name: (identifier) @name)');
          const usings = this.astParser.query(tree.rootNode,
            '(using_directive (qualified_name) @name)');
          const isSap = usings.some(u => SAP_NAMESPACES.some(s => u.text.includes(s)));

          items.push({
            type:        'cs-class',
            linkId:      `cs:class:${cls.text}`,
            name:        cls.text,
            sourceFile:  path.basename(filePath),
            methods:     methods.map(m => m.text),
            isSapIntegration: isSap,
            usings:      usings.map(u => u.text),
            _source:     filePath,
          });
        }
      } catch (err) {
        this.logger.error(`[cs-extractor] Failed: ${filePath} — ${err.message}`);
        errors.push({ file: filePath, error: err.message });
      }
    }

    return new ExtractionResult({
      source: 'cs',
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
  const extractor = new CsExtractor({ fileReader: reader, logger: console });
  (async () => {
    const files = await reader.glob(dir, '**/*.cs');
    console.error(`Extracting from ${files.length} C# files...`);
    const result = await extractor.run(files, {});
    fs.mkdirSync('knowledge-base/extracted', { recursive: true });
    fs.writeFileSync('knowledge-base/extracted/cs.json', JSON.stringify(result, null, 2));
    console.error(`Done. Items: ${result.items.length}, Errors: ${result.errors.length}`);
  })();
}

module.exports = { CsExtractor };
