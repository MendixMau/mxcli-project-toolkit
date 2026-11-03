# page-fidelity-popup — a popup wireframe and the popup page it draws (#471)

`product-newedit-describe-v023.mdl` is **verbatim** `mxcli describe page Sales.Product_NewEdit`
output (mxcli v0.23.0, Mendix 11.14.0, captured 2026-10-05), copied unchanged from
`tests/wave2/fixtures/context-pack/capture/describe/PAGE__Sales.Product_NewEdit.out`. It is a
real popup page: `Layout: Atlas_Core.PopupLayout`, a form grid, Cancel and Save in a footer.

`product-newedit-popup.html` is **hand-drawn**, because issue #471 quotes the shape of the field
wireframe, not the file: `.popup-stage > .shell-behind + .dialog-scrim > .dialog`. The shell
behind holds the caller's page as such wireframes draw it (a sidebar, a `div.main` with a page
head, its `<h1>` and a card), and the dialog holds the popup page's own title, fields, help
texts and buttons, taken from the describe above. The `wf-bar` and `wf-note` annotation
siblings are the toolkit's own convention.

On master the scorer chose `div.main` inside `.shell-behind` and printed 18%, every miss from
the shell (the issue measured 29% on the field popup and 13% on a throwaway one, the same way).
With the fix it scores the dialog: 100%.

Re-capture the wireframe from a real popup wireframe when one can be shared.
