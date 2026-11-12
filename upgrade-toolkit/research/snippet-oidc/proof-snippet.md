# RA-19 on a public template: what ran and what was measured (2026-10-23)

App: a public Marketplace showcase app (content id 225845, app 4.2.0, Mendix 10.24.13.86719). 28 HTML/JavaScript Snippet widgets, one per
page, all content type JavaScript, all with the same 181-character script (a smooth scroll of a page container to the top inside
`mx.addOnLoad`), no jQuery. Class by `bin/jquery_classify.py`: JS-DOM (28 of 28; it queries `.mx-scrollcontainer-wrapper` and scrolls it).

This was NOT the full pipeline run. The pipeline needs the 10.24.13 build tools and runtime for the baseline (about 1.5 GB) and the
container had 2 GB free; an earlier template run in the same container stopped on a full disk. What ran instead, with the shared 11.12.5 tools:

| step | tool | result |
|---|---|---|
| convert 10.24.13 to 11.12.5 | `mx convert --in-place` (11.12.5) | "6 errors, 68 warnings, 46 deprecations" at convert |
| check | `mx check` | 5 errors, all "External Database Connector marketplace module is not compatible" (a module update, not a snippet); 0 errors name a snippet |
| detect | `bin/dojo_report.py` | `HTMLSnippet.mpk 3.9.8 ... HTMLSnippet.widget.HTMLSnippet (28)` as "can move"; the same count as the model read (28) |
| propose | `bin/proposal.py --unattended` | section-3 item `P-4 widget: HTMLSnippet.mpk 3.9.8` with the RA-19 options and `[RA-19, idea, playbooks/rearchitecture.md]`; nothing signed, DECISIONS.md holds `ASSUMED (unattended)` lines. It also showed that the R9 item ("every widget at its latest version", which lists HTMLSnippet.mpk among 38 files) matched RA-19 by mistake; the match now binds to the package item only (control proposal-ra19-evidence-mention-not-matched-pass) |
| apply the recipe | `mxcli exec snippet-recipe-scroll-to-top.mdl` | new module with a JavaScript action (`document.querySelectorAll(".mx-scrollcontainer-wrapper")` then `scrollTo` top, smooth) and a nanoflow calling it; on each of the 28 pages the snippet is replaced by an Events widget (on load, delay 100 ms) calling the nanoflow |
| check again | `mx check` | the same 5 errors, no new one; `bin/dojo_report.py`: "0 can move", the HTMLSnippet package now listed as unused ("delete") |

Not measured: that the page scrolls to the top in the React client (no build, no run, no screen comparison, no journey), and the gate. The
5 External Database Connector errors were left: `mxcli marketplace update` refused because 17 elements of the module could not be read to prove it
unedited, and forcing it would skip that guard. So RA-19 stays `idea`: the structural half of the recipe ran and was checked by `mx check`;
the behavioural half did not.

Things the run showed that the entry now says: the snippet content is not in the describe output of a page (mxcli prints the widget with
its content type only), so the inventory has to read the content from the model, not from a page dump; and `mx check` is silent about
snippets, so only the inventory finds them ("it still loads" is not "it works").
