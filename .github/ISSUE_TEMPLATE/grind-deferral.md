---
name: Grind deferral
about: Auto-filed by /grind when a slice deferred mid-run. Operator triages.
labels: anvil, grind-deferral
---

## Slice

**Plan:** <plan-path>
**Slice ID:** <id>
**Deferred at:** <iso-timestamp>

## Reason

<one-line summary; populated by the orchestrator>

Possible classes:
- [ ] CI failure (real test failure — investigate)
- [ ] Pre-merge gate block (forbidden pattern, fitness ratchet, etc.)
- [ ] Adversarial review found P0/P1 (see linked finding below)
- [ ] Rebase conflict requiring human resolution
- [ ] Agent dispatch repeatedly failed
- [ ] Operator rejected the slice
- [ ] Other (see details)

## Details

```
<full error / output / review finding from the orchestrator>
```

## Event log tail

```
<last 5-10 events from .anvil/grind-events.jsonl that involve this slice>
```

## To resume

After fixing the underlying issue:

```bash
~/Desktop/anvil/skills/grind/scripts/state.sh replay <slice-id>
# then re-run /grind <plan-path>  (it picks up from this slice)
```

If the slice cannot be salvaged, mark it skipped:

```bash
~/Desktop/anvil/skills/grind/scripts/state.sh mark <slice-id> skipped "<reason>"
```

## Related

- Plan: <link to plan file/folder>
- PR (if any): <link>
- Original issue (if from audit): <link>
