'use strict';
// Independent endpoint count (the validator's "different mechanism" rule from
// extractor-quality-loop.md): a comment-stripped regex over each controller file's raw text,
// never the AST. Every mapping annotation on a method of a *Controller-stereotyped class is
// expected to land as an endpoint; any shortfall is reported, never dropped.

// One left-to-right pass, so a literal is consumed before it can open a comment and a comment
// before it can open a literal: `@GetMapping("/static/**")` must not swallow code up to the next
// `*/`, and `"http://x"` must not truncate its line.
const STRIP_RE = /"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\/\*[\s\S]*?\*\/|\/\/[^\n]*/g;
function stripCommentsAndStrings(text) {
  return text.replace(STRIP_RE, t => (t[0] === '"' ? '""' : t[0] === "'" ? "''" : ' '));
}

function regexEndpointCount(text) {
  const code = stripCommentsAndStrings(text);
  if (!/@\w*Controller\b/.test(code)) return null;
  const firstType = code.search(/\b(class|interface|enum|record)\s+\w+/);
  let count = 0;
  const re = /@(Get|Post|Put|Delete|Patch|Request)Mapping\b/g;
  let m;
  while ((m = re.exec(code))) {
    if (m[1] === 'Request' && firstType >= 0 && m.index < firstType) continue; // class-level base path
    count++;
  }
  return count;
}

module.exports = { stripCommentsAndStrings, regexEndpointCount };
