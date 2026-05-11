# Recap — fixture-sprint

## TLDR

Three slices shipped under the fixture plan with two assumption shifts captured. One assumption shifted around event-log shape after the first slice merged. Architectural drift introduced an additional indirection layer in the resolver. Residual risk lives in the offline mode fallback for PR resolution.

## What shipped

- S1 — slice-1 lifted (#1010).
- S2 — slice-2 wired the resolver (#1011).
- S3 — slice-3 added the citation pass (#1012).

## What assumptions changed

- We assumed event-log shape was append-only without revisions; the new resume event broke that. See README.md:1 and #1010.
- We assumed the resolver script could resolve all forms with the same regex; the SHA form required a separate path (#1011).

## What architectural drift

- Resolver script grew a third resolution branch for SHAs (#1012).
- Event log now carries a non-additive `resume` event family (README.md:1).

## What residual risk

- Offline mode depends on an allowlist file that operators may forget to commit (#1010).
- Long SHAs (40 chars) untested across all git host configs (#1011).
