---
name: lens
description: Adversarial review through a named review lens — kernel developer, SRE, distributed-systems engineer, privacy lawyer, security researcher, etc. Lenses are namespaced into saas / systems / generic categories. Each lens is a hard-coded role prefix that wraps /self-review or /codex-review to focus the model's attention on one perspective. Invoke with /lens <name> "<scope>".
---

# /lens — adversarial review through a named lens

Anvil's `/self-review` and `/codex-review` are generic adversarial sweeps. Sometimes you want the review to land in a specific lens — "what would the kernel developer flag?", "what would the 3 a.m. on-call see?", "would the architecture reviewer accept this layer crossing?". This skill wraps the existing review skills with a hard-coded role prefix per lens.

Lenses are namespaced into three categories:

- **`systems/`** — systems / software-engineering lenses. Kernel, SRE, embedded, distributed-systems, performance, compiler/build, OSS maintainer, architecture reviewer. Use these for infrastructure, library, runtime, kernel, embedded, distributed, and architecture-stable code review.
- **`saas/`** — product / service-business lenses. Privacy lawyer, payment risk, angry customer, competitor recon, end-user, journalist. Use these for product / B2C / B2B SaaS surfaces where compliance, payments, support, and brand exposure are first-order.
- **`generic/`** — domain-neutral lenses that work across both. Security researcher, new engineer, vendor / license auditor.

## When to invoke

- Operator says "fire the kernel developer", "run lens <name>", "/lens <name>".
- Mid-grind for high-stakes diffs (kernel, distributed-state, money, auth, photos, prompt-bearing surfaces).
- Before merging a slice that touches a regulated or invariant-sensitive surface — file a lens-flavoured review as paper trail.

## When NOT to use

- For broad review of an unfocused diff — use `/self-review` or `/codex-review` directly.
- When the lens doesn't apply (e.g. `/lens saas/payment-risk` on a kernel-only PR).

## Args

| Arg | Required | Description |
|---|---|---|
| `<name>` | yes | Review lens to invoke. Supports `<category>/<name>` (e.g. `systems/kernel-developer`) or bare `<name>` (looks up across categories; errors on ambiguity). See "Available lenses" below. |
| `<scope>` | yes | What to review (same shape as `/self-review`): PR number, branch, SHA, or "uncommitted". |
| `--reviewer <self\|codex\|dual>` | no | Which review backend (default: `self`). `dual` runs `/dual-review` if codex is available. |
| `--project-context <text>` | no | One-paragraph project context the lens references. If omitted, reads from `.anvil/lens-context.md` if present; otherwise the lens uses generic framing. |

## Available lenses

19 lenses across 3 categories. Each is a prompt prefix at `lenses/<category>/<name>.md`. The procedure injects the prefix before the diff text + the standard adversarial framing.

### `systems/` — systems + software-engineering lenses (8)

| Lens | Focus | Best for |
|---|---|---|
| `systems/kernel-developer` | memory safety, locking discipline, ABI, syscall correctness | kernel modules, drivers, anything with explicit lock hierarchies, RCU, unsafe paths |
| `systems/sre-incident-responder` | observability, runbooks, blast radius | service code, queue/job pipelines, anything that pages at 3 a.m. |
| `systems/embedded-engineer` | real-time constraints, resource limits, WCET, ISR safety | firmware, RTOS, MCU code, hard-real-time paths |
| `systems/distributed-systems` | consensus, partition tolerance, idempotency, retry semantics | replicated state, leader election, cross-region paths, message queues |
| `systems/performance-engineer` | hot paths, cache behavior, allocation, syscall overhead | latency-critical code, throughput-bound code, scale-ceiling work |
| `systems/compiler-build-engineer` | toolchain correctness, reproducibility, hermetic builds | build scripts, compiler flags, package manifests, CI pipelines |
| `systems/open-source-maintainer` | PR triage, contributor UX, API/ABI stability | external contributor PRs, public-surface changes, deprecation paths |
| `systems/architecture-reviewer` | boundaries, layering, dependencies, coupling | cross-module changes, layer crossings, abstraction-stability decisions |

### `saas/` — product / service-business lenses (6)

| Lens | Focus | Best for |
|---|---|---|
| `saas/privacy-lawyer` | GDPR/CCPA/COPPA + data-retention + consent flow | privacy paths, PII, photo handling, retention windows |
| `saas/payment-risk` | refund/dispute/chargeback + merchant-of-record | Stripe webhooks, refund logic, evidence capture, delivery gating |
| `saas/angry-customer` | customer-support ticket framing of a failure | product-quality regressions, order-fulfilment errors |
| `saas/competitor-recon` | reverse-engineering the moat | product/funnel/pricing surfaces |
| `saas/end-user` | end-user perspective (vs. operator's lens) | UX, copy, accessibility, output quality |
| `saas/journalist` | investigative-reporter framing | trust/safety surfaces, dark patterns, training-data exposure |

### `generic/` — domain-neutral lenses (3)

| Lens | Focus | Best for |
|---|---|---|
| `generic/security-researcher` | exploitable bugs (IDOR, auth bypass, injection, exfil) | any auth/upload/token/privileged surface |
| `generic/new-engineer` | day-one onboarding gaps | architecture clarity, documentation, naming |
| `generic/vendor-tos-auditor` | external-dependency licenses + ToS + AUP | any external dep — library, compiler, runtime, cloud, model vendor |

## Procedure

### Step 1: Resolve lens

```bash
PROMPT=$(bash "<anvil-root>/skills/lens/scripts/resolve-lens.sh" "<name>")
# Status 0: $PROMPT holds the prompt body.
# Status 1: unknown lens — abort.
# Status 2: ambiguous bare name — abort and report match list.
```

Bare names are resolved by looking across categories. If exactly one match: use it. If zero: error. If multiple: error with the disambiguation list.

The script emits a one-time deprecation notice for the legacy `oncall-3am` name and rewrites to `systems/sre-incident-responder` automatically.

### Step 2: Resolve project context

If `--project-context` is passed, use it. Else if `.anvil/lens-context.md` exists, read it. Else use empty (the lens prompt has fallback wording via the `{{project_context}}` placeholder).

### Step 3: Build the assembled prompt

```
<LENS_PROMPT>

Project context: <PROJECT_CONTEXT>

Diff under review: <SCOPE_REF>

Review the diff through the lens. Output: P0/P1/P2/P3 findings with file:line citations. Same shape as /self-review.
```

### Step 4: Dispatch to the chosen reviewer

- `--reviewer self` (default): invoke `/self-review` with the assembled prompt as a custom prefix.
- `--reviewer codex`: invoke `/codex-review` with the assembled prompt.
- `--reviewer dual`: invoke `/dual-review` with the assembled prompt (Claude + Codex parallel).

### Step 5: Save the lens-flavoured review

```bash
.codex-log/$(date +%Y%m%d-%H%M%S)-lens-<category>-<name>.md
```

So the lens review is distinguishable from regular `/self-review` output in the audit trail.

## Lens prompts

Each lens's role prefix lives at `lenses/<category>/<name>.md`. Operators can add their own lenses by dropping a new `<custom-name>.md` file into one of the three category dirs — `/lens <category>/<custom-name>` will pick it up automatically. The bare-name lookup will also find a custom lens as long as the bare name is unique across all three categories.

The shipped lenses are generic enough for any project that lives in their category. Project-specific framing comes from `--project-context` or `.anvil/lens-context.md`.

## Example

```
/lens systems/kernel-developer "uncommitted" --reviewer self
```

Reviews the current uncommitted changes through a kernel developer's lens (memory safety, locking, ABI, syscall correctness). Useful before pushing a change to a driver / unsafe path / locking hierarchy.

```
/lens saas/privacy-lawyer "PR #1115" --reviewer self
```

Reviews PR #1115 through a privacy-lawyer lens (GDPR/CCPA/COPPA + retention + consent). Useful before merging a path that touches PII or retention.

```
/lens generic/security-researcher "uncommitted" --reviewer dual
```

Runs both Claude + Codex in parallel through a security-researcher lens.

## Manual smoke test

```bash
bash skills/lens/scripts/resolve-lens.sh systems/sre-incident-responder
# expect: outputs the prompt body with {{project_context}} placeholder intact. status 0.

bash skills/lens/scripts/resolve-lens.sh oncall-3am
# expect: outputs systems/sre-incident-responder prompt body + deprecation notice on stderr. status 0.

bash skills/lens/scripts/resolve-lens.sh privacy-lawyer
# expect: bare-name lookup finds saas/privacy-lawyer. status 0.

bash skills/lens/scripts/resolve-lens.sh does-not-exist
# expect: error on stderr. status 1.
```

## Composition

- Wraps `/self-review` (default), `/codex-review`, or `/dual-review`.
- Reads from `.anvil/lens-context.md` for project context (optional).
- Saves to `.codex-log/` alongside other reviews for audit-trail consistency.

## Extending

Add a custom lens: create `lenses/<category>/<your-lens>.md` with a paragraph describing the role. Use `{{project_context}}` as a placeholder where project-specific framing belongs. See `lenses/systems/kernel-developer.md` or `lenses/saas/privacy-lawyer.md` for the canonical shape.

Choosing a category:

- **`systems/`** if the lens reasons about code-level invariants (memory, locking, ABI, layering, performance, build hermeticity).
- **`saas/`** if the lens reasons about end-user / customer / business-risk surface (privacy, payments, support, brand, GTM).
- **`generic/`** if the lens reasons about a concern that crosses both (security, onboarding, external-dependency compliance).
