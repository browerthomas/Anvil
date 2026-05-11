# Recap — fixture-sprint

## TLDR

Three slices shipped under the fixture plan with two assumption shifts captured. One assumption shifted around event-log shape after the first slice merged. Architectural drift introduced an additional indirection layer in the resolver. Residual risk lives in the offline mode fallback for PR resolution.

## What shipped

- S1 — slice-1 lifted.

## What assumptions changed

- We assumed event-log shape was append-only without revisions; see README.md:999999.

## What architectural drift

- Resolver script grew a third branch for SHAs (#1012).

## What residual risk

- Offline mode depends on an allowlist (#1010).
