# A tolerant parser upstream of a strict one is a silent-failure machine — and HTTP 200 is not an oracle for anything a human reads

**From:** Maurits Visser, from a MOC/PSSR app replacement
**Date:** 2026-09-16
**Kind:** learning
**Field evidence:** two confirmed defects on a real deployment, measured. Numbers below.
**Proposed target:** `skills/testing-shape.md` — specifically its false-green register, which
is exactly where both of these belong. The guard-string convention may also want a line in
whatever skill covers integration error handling.

---

## Finding 1 — validate a secret at ingest, by shape, never by whether something accepted it

A Mendix GenAI configuration key supplied as an environment variable was **1345 characters
long**. `1345 % 4 == 1`, which base64 can never be: there was a stray trailing `=`.

- **Node's base64 decoder is tolerant.** It swallowed the extra character without a word, so
  every script that touched the value reported success.
- **Mendix's decoder is strict.** It rejected the import with
  *"Something went wrong while importing the configuration. Make sure you have copied the
  correct key from the Mendix Portal."* — a message that points the reader at the portal,
  i.e. at the one place that was not the problem.

Dropping the one character imports cleanly. The wrapper script now strips it and says it did,
which fixes the symptom on this deployment and leaves the value wrong wherever it is actually
set, so the next environment hits the same wall.

**The general shape:** whenever a secret crosses from one runtime to another, the two ends
have different tolerance, and the lenient end is the one you are testing with. The check is
free and does not require the value:

- length, and `length % 4` for base64
- does it decode strictly (`Buffer.from(s, 'base64').toString('base64') === s`)
- leading/trailing whitespace, a trailing newline from a copy-paste, smart quotes
- and **report all of that without ever printing the value** — length and a verdict is the
  entire output.

Five seconds at ingest against a failure that surfaces as a wrong-pointing error message in
a different runtime hours later.

## Finding 2 — HTTP 200 is not an oracle for anything a human reads

The chat path in the same app: two client-callable microflows called in order, both returning
**HTTP 200**, the user's message landing with `Status "Success"` — and the assistant's reply
staying `Status "Loading"` with empty `Content` past **153 seconds**, with no trace or span
rows at all, meaning the model was never called. Every green signal available was green.

This is the same false-green family the toolkit already records, in a new place: the transport
succeeded and the *product* did not happen. The oracle for a feature a human reads is the text
a human reads, and nothing cheaper substitutes for it.

## The convention that did work, and is worth copying

The graph integration in the same app, when it had no credentials, answered with a guard
string rather than an empty result:

```
GRAPH_NOT_CONFIGURED: the knowledge-graph connection has no credentials on this
environment, so I cannot look anything up in the change history. This is a
configuration gap, not an empty graph.
```

That one string literal is the difference between *"the graph is empty"*, *"the graph is
broken"* and *"the graph was never configured"* — three states that are indistinguishable
from an empty result set, have three different owners, and get three different fixes. Its
siblings in the same integration are `GRAPH_ERROR: <http status>` for a transport failure and
real data for success, which makes a one-line verification possible after any deploy: ask the
feature a question and read which of the three you get back.

**Proposed rule:** any integration that can be *unconfigured* as distinct from *empty* names
which state it is in, in the text it returns. The cost is a string literal; the alternative is
a human deciding, from a blank screen, which of three things went wrong.
