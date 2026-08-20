# Microflow popup navigation — always close before you show

**Applies to:** any microflow that can `show page` a popup while another popup from the
same flow (or the flow that triggered it) is still open.

## The rule

**Before every `show page` that targets a popup, ask: is a popup already open on this
client? If yes, `close page;` first.** Never assume the previous `show page` in the same
microflow, or the page that triggered this microflow, has already been dismissed.

```mdl
-- Wrong — stacks a second dialog on top of the first
if $NextAvailable != empty then
  show page Module.SomePopup($Param = $NextAvailable);
end if;

-- Right — swap, don't stack
if $NextAvailable != empty then
  close page;
  show page Module.SomePopup($Param = $NextAvailable);
end if;
```

## Why

`show page` / `close page` are client-side navigation-stack operations. A microflow has
no idea whether it's "inside" the page that invoked it — it's just told to push or pop.
A microflow triggered by popup A is free to `show page A` again (e.g. a retry/validation-
failure branch), and Mendix will happily stack a second instance of A on top of the
first instead of replacing it, unless you `close page;` first.

Confirmed on a module's claim microflow: the happy path
did `close page; show page ...Overview;` (correct), but the race-condition retry branch
did only `show page ...Claim(...)` with no preceding `close page;` — so a second collision
would have stacked a third dialog. One line (`close page;`) fixed it.

## How to catch this in review

Grep any microflow for `show page` and check every occurrence has a `close page;`
immediately before it (or is provably the first popup in the flow — e.g. one invoked from
a non-popup page). Don't just check the "success" branch; retry/error/race-condition
branches are the ones most likely to be missed because they get less testing attention.
