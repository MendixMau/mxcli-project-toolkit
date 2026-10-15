"""Split a describe script into top-level statements, shared by topo-order-mdl.py and
compare-mdl.py. A statement ends at a column-0 line that ends in ';' — but only when that line
starts and ends OUTSIDE a string literal ('…', doubled quote escapes), a $$…$$ block (Java/JS
bodies, JSON samples) or a comment (-- to end of line, /* … */). The GenAI showcase app (increment 2)
has microflows returning multi-line JSON string literals whose inner lines sit at column 0 and
end in ';', and the plain column-0 rule cut those flows into fragments that were then reordered.
Text is passed through byte-for-byte: no newline translation (CRLF inside literals is load-bearing)."""
import re
OPENER = re.compile(r'^(create|grant|revoke|alter|drop|delete|mdl|@|/\*|--)')
# after an INDENTED terminator only a keyword, an annotation or a doc comment at column 0 closes the
# statement (`  );` then `@Position(380, 130)` + `create … entity`: ChatCompletions_FunctionCalling)
STRONG = re.compile(r'^(create |grant |revoke |alter |drop |delete |@[A-Za-z]|/\*\*)')
def split_statements(text):
    stmts, cur, state, pending = [], [], 'code', None       # state: code | str | dollar | block
    for ln in text.split('\n'):
        start = state
        # a candidate boundary closes only when the next non-blank line opens a statement: Studio Pro
        # emits multi-line expressions with continuation lines at column 0 ("else $X, Y = $Z);")
        if pending and ln.strip():
            if start == 'code' and (OPENER if pending == 'col0' else STRONG).match(ln):
                stmts.append('\n'.join(cur)); cur = []
            pending = None
        i, n, comment = 0, len(ln), False
        while i < n:
            c = ln[i]
            if state == 'code':
                if c == "'": state = 'str'
                elif ln.startswith('$$', i): state = 'dollar'; i += 1
                elif ln.startswith('--', i): comment = True; break  # comment to end of line
                elif ln.startswith('/*', i): state = 'block'; i += 1
            elif state == 'str':
                if c == "'": state = 'code'                        # '' escape toggles twice, net unchanged
            elif state == 'dollar':
                if ln.startswith('$$', i): state = 'code'; i += 1
            elif state == 'block':
                if ln.startswith('*/', i): state = 'code'; i += 1
            i += 1
        cur.append(ln)
        # the line may START inside a $$ body: java/javascript actions end with a column-0 `$$;`
        # (GenAI showcase app: 15 java actions of GenAICommons merged into one "statement", and check's
        # statement numbers no longer matched ours). The opener lookahead above still guards the
        # multi-line-literal case.
        # a json structure with a CUSTOM NAME map ends on an indented `  );` (GenAI showcase app, 2026-10-13:
        # 4 modules split 1-9 statements short of mxcli's count, so check's `statement N:` mapped onto
        # the wrong statement or past the end — field run defect E1b). An indented terminator closes only when
        # the next non-blank line opens with a column-0 keyword.
        if state == 'code' and not comment and ln.rstrip().endswith(';'):
            pending = 'col0' if not ln[0].isspace() else 'indent'
    if pending and cur: stmts.append('\n'.join(cur)); cur = []
    return stmts, '\n'.join(cur)

def strip_deferred(s):
    """Drop the leading `-- deferred: …` reason lines a statement carries from an earlier pass."""
    ls = s.split('\n')
    while ls and (ls[0].startswith('-- deferred:') or not ls[0].strip()): ls.pop(0)
    return '\n'.join(ls)
