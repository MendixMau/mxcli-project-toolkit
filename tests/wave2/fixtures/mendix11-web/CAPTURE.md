# Mendix 11 web pages, captured

`index.html` and `login.html` are verbatim copies of `deployment/web/` from a Mendix 11.13.0 test
app (a 5-page purchase-request app built with mxbuild 11.13.0), captured 2026-11-09. Nothing in them
is project-specific: the numbers in `?639…` are the build's cache-bust stamps.

What they show, and why `tests/wave2/test-app-readiness.sh` serves them:
- `login.html` contains none of `mxui`, `mx-name`, `Mendix`, `mxclientsystem`;
- `index.html` contains `Mendix` only in its `<title>`, and loads the client as
  `<script src="dist/index.js?…" type="module">`.
