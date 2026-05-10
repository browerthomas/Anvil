**Source:** {{review-path}} — adversarial review of [#{{pr-number}}]({{pr-url}}).

P0/P1 findings are being addressed by a fix-up agent on the same PR. This issue tracks the P2/P3 followups deferred to a separate cleanup pass.

{{#if p2-list}}
## P2 ({{p2-count}} — non-blocking but worth fixing)

{{p2-list}}
{{/if}}

{{#if p3-list}}
## P3 ({{p3-count}} — cleanup)

{{p3-list}}
{{/if}}

{{#if cross-critic-areas}}
## Cross-critic risk areas (advisory)

{{cross-critic-areas}}
{{/if}}

## Cadence

These can land before the next dependent slice ships (recommended for hygiene) OR after the slice/sprint ships as a single cleanup PR. None of them block the migration cadence on the parent plan.

Each finding above carries a file:line citation in the source review markdown — link there for the full explanation + suggested fix.
