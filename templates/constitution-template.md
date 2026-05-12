# Project constitution

> **What this file is.** A short, durable statement of your project's ethos — the
> north star, the inviolable principles, the things that are out of scope for
> every slice. This is the strategic frame a smart engineer would internalise
> before touching anything. It is **prepended to every dispatched-agent prompt**
> by `/dispatch-slice`, so every agent sees it.
>
> **What this file is NOT.** Mechanical config. Forbidden grep patterns belong
> in `.anvil/forbidden-patterns.txt`. Per-slice constraints belong in
> `dispatch-defaults.txt` or the operator-supplied `--constraints` flag. Test
> baselines, repo-identity boilerplate, vendor-SDK boundaries → those are
> mechanical and live elsewhere.
>
> **Keep it lean.** A warning fires at 2KB; a stronger warning fires at 8KB.
> The constitution is paid-for context on every dispatch — every byte should
> earn its place.
>
> **Replace the placeholder text below.** Three sections are scaffolded as
> starting points; delete what doesn't fit, add what does.

---

## North star

> One paragraph. The single thing your project is optimising for above all
> else — the trade-off you'd never reverse, the direction every slice should
> push. If two slices are both correct but one moves the north-star needle
> further, that's the one that ships.

(Replace this placeholder with your project's north star.)

## Inviolable principles

> 3–7 bullets. Things that are non-negotiable. Not "preferences" — actual
> bright lines. If a slice violates one of these, the slice is wrong by
> construction and should be revised, not merged. Examples of the right
> shape (not your principles — your principles will be specific to your
> domain):
>
> - User data is never persisted past its useful lifetime.
> - The hot path must remain idempotent end-to-end.
> - We do not ship features that require operator intervention to recover.

- (Replace this with your first inviolable principle.)
- (Replace this with your second inviolable principle.)
- (Replace this with your third inviolable principle.)

## Out of scope for every slice

> 3–7 bullets. Things that are explicitly NOT a goal — directions a smart
> engineer might reasonably push toward that would actually be wrong for this
> project. State them here so dispatched agents don't waste cycles
> rediscovering the answer.
>
> - We are not optimising for scale beyond N concurrent users.
> - We are not building a multi-tenant abstraction.
> - We are not adding a plugin system.

- (Replace this with the first thing that is out of scope.)
- (Replace this with the second thing that is out of scope.)
- (Replace this with the third thing that is out of scope.)
