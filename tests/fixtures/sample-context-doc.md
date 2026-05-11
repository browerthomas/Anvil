# Sample CLAUDE.md context doc — fixture

## What to Avoid

- DO NOT commit `.env` files or credentials.
- Never use `--no-verify` on push unless the operator explicitly requests it.
- Don't bypass the pre-merge gate.

## Test infrastructure invariants

- Every PR must keep architecture fitness ratchets green.
- Always run `npm run lint` before commit.
- Tests must hit baseline-or-better; current test target is 906 passing.

## Known chronic issues

- Vitest worker-crash flake under CPU contention is intermittent — retry once.
- Pre-push hook may fail when iCloud Drive evicts node_modules; chronic.
