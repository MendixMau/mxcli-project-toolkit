'use strict';

const fs      = require('fs');
const fsp     = require('fs/promises');
const path    = require('path');
const { glob: globFn } = require('glob');
const iconv   = require('iconv-lite');

class FileReader {
  async readText(filePath) {
    const buf = await fsp.readFile(filePath);
    const detected = this._detectEncoding(buf);
    return iconv.decode(buf, detected);
  }

  readTextSync(filePath) {
    const buf = fs.readFileSync(filePath);
    return iconv.decode(buf, this._detectEncoding(buf));
  }

  _detectEncoding(buf) {
    if (buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) return 'utf8';
    try {
      const str = buf.toString('utf8');
      if (!str.includes('�')) return 'utf8';
    } catch (_) {}
    return 'Shift_JIS';
  }

  async glob(baseDir, pattern) {
    const results = await globFn(pattern, {
      cwd: baseDir,
      absolute: true,
      windowsPathsNoEscape: true,
      nodir: true,
    });
    return results;
  }

  async sampleFiles(filePaths, n) {
    if (filePaths.length <= n) return filePaths;
    const withSize = filePaths.map(f => {
      try { return { f, size: fs.statSync(f).size }; }
      catch (_) { return { f, size: 0 }; }
    }).sort((a, b) => a.size - b.size);

    const step = Math.max(1, Math.floor(withSize.length / n));
    const sample = [];
    for (let i = 0; i < n && i * step < withSize.length; i++) {
      sample.push(withSize[i * step].f);
    }
    return sample;
  }
}

module.exports = { FileReader };
