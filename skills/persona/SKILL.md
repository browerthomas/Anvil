---
name: persona
description: Adversarial review through a named persona's lens — privacy lawyer, security researcher, on-call engineer, angry customer, etc. Each persona is a hard-coded role prefix that wraps /self-review or /codex-review to focus the model's attention on one perspective. Invoke with /persona <name> "<scope>".
---

# /persona — adversarial review through a named lens

Anvil's /self-review and /codex-review are generic adversarial sweeps. Sometimes you want the review to land in a specific lens — "what would the privacy lawyer flag?", "what would the 3 a.m. on-call see?". This skill wraps the existing review skills with a hard-coded role prefix per persona.

## When to invoke

- Operator says "fire the privacy lawyer", "run persona <name>", "/persona <name>".
- Mid-grind for high-stakes diffs (money, auth, photos, prompt-bearing surfaces).
- Before merging a slice that touches a regulated surface — file a persona-flavoured review as paper trail.

## When NOT to use

- For broad review of an unfocused diff — use /self-review or /codex-review directly.
- When the persona's lens doesn't apply (e.g. /persona-payment-risk on a docs-only PR).

## Args

| Arg | Required | Description |
|---|---|---|
| `<name>` | yes | One of: `privacy-lawyer`, `payment-risk`, `security-researcher`, `angry-customer`, `vendor-tos-auditor`, `new-engineer`, `oncall-3am`, `competitor-recon`, `end-user`, `journalist` |
| `<scope>` | yes | What to review (same shape as /self-review): PR number, branch, SHA, or "uncommitted" |
| `--reviewer <self\|codex\|dual>` | no | Which review backend (default: `self`). `dual` runs /dual-review if codex is available. |
| `--project-context <text>` | no | One-paragraph project context the persona references. If omitted, reads from `.anvil/persona-context.md` if present; otherwise the persona uses a generic framing. |

## Available personas

Each persona is a hard-coded prompt prefix stored at `personas/<name>.md`. The procedure injects the prefix before the diff text + the standard adversarial framing.

| Persona | Lens | Best for |
|---|---|---|
| `privacy-lawyer` | GDPR/CCPA/COPPA + data-retention + consent flow | privacy paths, photo handling, PII, retention windows |
| `payment-risk` | refund/dispute/chargeback + merchant-of-record | Stripe webhooks, refund logic, evidence capture, delivery gating |
| `security-researcher` | exploitable bugs (IDOR, auth bypass, data exfil) | auth/upload/token/payment surfaces |
| `angry-customer` | customer-support ticket framing of a failure | product-quality regressions, order-fulfilment errors |
| `vendor-tos-auditor` | external API ToS compliance | prompt-bearing surfaces, training-opt-out, rate-limit respect |
| `new-engineer` | day-one onboarding gaps | architecture clarity, documentation, naming |
| `oncall-3am` | incident response readiness | observability, dashboards, remediation paths |
| `competitor-recon` | reverse-engineering the moat | product/funnel/pricing surfaces |
| `end-user` | end-user perspective (vs. operator's lens) | UX, copy, accessibility |
| `journalist` | investigative-reporter framing | trust/safety surfaces, dark patterns, training-data exposure |

## Procedure

### Step 1: Resolve persona

```bash
PERSONA_FILE="<anvil-root>/skills/persona/personas/<name>.md"
if [ ! -f "$PERSONA_FILE" ]; then
  echo "Unknown persona '<name>'. See available personas above."
  exit 1
fi
PERSONA_PREFIX=$(cat "$PERSONA_FILE")
```

### Step 2: Resolve project context

If `--project-context` is passed, use it. Else if `.anvil/persona-context.md` exists, read it. Else use empty (the persona's prompt has fallback wording).

### Step 3: Build the assembled prompt

```
<PERSONA_PREFIX>

Project context: <PROJECT_CONTEXT>

Diff under review: <SCOPE_REF>

Review the diff through the persona's lens. Output: P0/P1/P2/P3 findings with file:line citations. Same shape as /self-review.
```

### Step 4: Dispatch to the chosen reviewer

- `--reviewer self` (default): invoke /self-review with the assembled prompt as a custom prefix.
- `--reviewer codex`: invoke /codex-review with the assembled prompt.
- `--reviewer dual`: invoke /dual-review with the assembled prompt (Claude + Codex parallel).

### Step 5: Save the persona-flavoured review

```bash
.codex-log/$(date +%Y%m%d-%H%M%S)-persona-<name>.md
```

So the persona review is distinguishable from regular /self-review output in the audit trail.

## Persona prompts

Each persona's role prefix lives at `personas/<name>.md`. Operators can add their own personas by dropping a new `<custom-name>.md` file in `personas/` — `/persona <custom-name>` will pick it up automatically.

The shipped personas are generic enough for any project. Project-specific framing comes from `--project-context` or `.anvil/persona-context.md`.

## Example

```
/persona privacy-lawyer "PR #1115" --reviewer self
```

Output: a /self-review-shaped findings table where each finding is scored through the privacy-lawyer's lens (GDPR/CCPA/COPPA + data-retention + consent flow).

```
/persona oncall-3am "uncommitted" --reviewer self
```

Reviews the current uncommitted changes through the lens of a 3 a.m. on-call responder. Useful before pushing a change to a service-impacting path — catches "would we know if this broke at midnight?" gaps.

## Composition

- Wraps `/self-review` (default), `/codex-review`, or `/dual-review`.
- Reads from `.anvil/persona-context.md` for project context (optional).
- Saves to `.codex-log/` alongside other reviews for audit-trail consistency.

## Extending

Add a custom persona: create `personas/<your-persona>.md` with a paragraph describing the role. Use `{{project_context}}` as a placeholder where project-specific framing belongs. See `personas/privacy-lawyer.md` for the canonical shape.
