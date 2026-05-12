# /recap v2 — structured WHY prompt template

> Filled by `build-recap.sh --v2` and handed to the model. The model
> returns markdown matching the exact shape below. The script then
> runs citation resolution on the output. Sections 3-5 MUST cite using
> the three-form vocabulary.

---

## Inputs

**Plan:** `{{plan_path}}`
**Window:** `{{since}}` → `{{until}}`
**Event log:** `{{events_count}}` events parsed from `{{events_path}}`
**PRs in window:** `{{pr_count}}`
**Commits in window:** `{{commit_count}}`

### Event-log excerpt

```jsonl
{{events_excerpt}}
```

### PRs merged in window

```
{{pr_list}}
```

### Plan tasks.md excerpt

```
{{plan_excerpt}}
```

### Decisions logged in window (`type:decision` rows from `.anvil/learnings.jsonl`)

```
{{decisions_excerpt}}
```

### Slice-merged diff stats

```
{{diff_stats}}
```

### Token / cost rollup (folded from event log)

```
{{cost_summary}}
```

---

## Task

Produce a markdown recap with the EXACT structure below. Section order is
non-negotiable. The TLDR is the first thing the operator reads — write
sentences they can scan in 5 seconds.

If the cost rollup above carries a non-zero total, surface it explicitly in
the TLDR (e.g. "X slices shipped at total cost $Y.YY"). If the rollup reads
`(no cost data reported)`, omit any cost claim — the runtime did not surface
the fields, so any number would be a guess.

Use the three-form citation vocabulary in sections 3-5:

- `path/to/file.ext:N` — file + line number
- `#PR_NUMBER` — open or merged PR
- `<commit-sha>` — short or long git SHA

A citation MUST resolve in the post-processing pass. Do NOT invent PR
numbers, file paths, or SHAs to round out a sentence. If you don't have
a citation for a claim, drop the claim.

---

## Output shape (fill below this line)

# Recap — {{slug}}

## TLDR

<4 sentences total, one per WHY section. Sentence 1 covers WHAT shipped
(factual headline). Sentence 2 covers ASSUMPTIONS that changed. Sentence 3
covers ARCHITECTURAL DRIFT. Sentence 4 covers RESIDUAL RISK. The TLDR
sentences may be uncited — the citations live in the WHY sections below.>

## What shipped

<Bulleted list of concrete shippings. Each bullet 1 line. Cite optional;
this section is factual.>

## What assumptions changed

<Bulleted list. Each bullet MUST end with at least one citation in one of
the three forms (`path:N` / `#PR` / `<sha>`). If an assumption changed but
you can't cite it, omit the bullet.>

## What architectural drift

<Bulleted list. Same citation rule.>

## What residual risk

<Bulleted list. Same citation rule.>
