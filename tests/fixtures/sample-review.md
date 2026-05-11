# Adversarial review — fixture

Diff: example/feature-x.ts (~120 LoC added)

## P0 findings

- [P0] CSRF token not checked on POST /api/widget — file: web/routes/widget.ts:42
  Suggested fix: wrap handler with the existing csrfProtect middleware used by adjacent routes.

- [P0] Stripe webhook handler missing idempotency guard — file: web/routes/webhook.ts:88
  Suggested fix: pass eventId through withIdempotency.

## P1 findings

- [P1] Race condition in OrderRepo.markPaid — file: core/order-repo.ts:120
  Two concurrent calls could double-mark. Suggested fix: SELECT ... FOR UPDATE within a transaction.

- [P1] Missing rate limit on /auth/magic — file: web/routes/auth.ts:55

## P2 findings

- [P2] Inconsistent error message format on 4xx — multiple files
- [P2] TODO comment left in src/lib/foo.ts:200

## P3 findings

- [P3] Trailing whitespace in two files

## Verdict

Verdict: BLOCK — two P0s must be fixed before merge.
