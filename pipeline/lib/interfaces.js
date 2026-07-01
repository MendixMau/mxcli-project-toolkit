'use strict';

class ExtractionResult {
  constructor({ source, items = [], errors = [], meta = {} }) {
    this.source = source;
    this.items  = items;
    this.errors = errors;
    this.meta   = meta;
  }

  static merge(a, b) {
    if (a.source !== b.source) throw new Error(`Cannot merge results from different sources: ${a.source} vs ${b.source}`);
    return new ExtractionResult({
      source: a.source,
      items:  [...a.items, ...b.items],
      errors: [...a.errors, ...b.errors],
      meta:   {
        ...a.meta,
        fileCount: (a.meta.fileCount || 0) + (b.meta.fileCount || 0),
        duration:  (a.meta.duration  || 0) + (b.meta.duration  || 0),
      }
    });
  }
}

class BaseExtractor {
  constructor({ fileReader, logger }) {
    this.fileReader = fileReader;
    this.logger     = logger || console;
  }

  run(_filePaths, _options) {
    throw new Error('run() not implemented');
  }

  get supportedExtensions() {
    throw new Error('supportedExtensions not implemented');
  }
}

module.exports = { BaseExtractor, ExtractionResult };
