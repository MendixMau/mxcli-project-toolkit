'use strict';

const Parser   = require('tree-sitter');
const { Query } = Parser;
const JS       = require('tree-sitter-javascript');
const CSharp   = require('tree-sitter-c-sharp');

const LANGUAGES = { javascript: JS, csharp: CSharp };

class ASTParser {
  constructor() {
    this._parsers = {};
  }

  _getParser(language) {
    if (!LANGUAGES[language]) throw new Error(`Unsupported language: ${language}. Supported: ${Object.keys(LANGUAGES).join(', ')}`);
    if (!this._parsers[language]) {
      const p = new Parser();
      p.setLanguage(LANGUAGES[language]);
      this._parsers[language] = p;
    }
    return this._parsers[language];
  }

  parseSource(sourceCode, language) {
    const parser = this._getParser(language);
    return parser.parse(sourceCode);
  }

  parseFile(filePath, language) {
    const { FileReader } = require('./file-reader');
    const reader = new FileReader();
    const src = reader.readTextSync(filePath);
    return { tree: this.parseSource(src, language), src };
  }

  query(tree, sExpr) {
    const lang = tree.language;
    const q = new Query(lang, sExpr);
    const matches = q.matches(tree.rootNode);
    const results = [];
    for (const match of matches) {
      for (const capture of match.captures) {
        results.push(capture.node);
      }
    }
    return results;
  }
}

module.exports = { ASTParser };
