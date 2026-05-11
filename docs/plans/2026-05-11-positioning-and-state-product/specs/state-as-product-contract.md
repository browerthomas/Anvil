# Spec: state-as-product contract

> Phase A and B both rest on the same load-bearing claim: anvil's value IS the durable repo-native state model. Every user-facing surface must reflect this, and every new skill (B1-B4) must surface (or operate on) the existing state — not invent new state surfaces.

---

## What "state" means in anvil

Three on-disk surfaces, all repo-native:

1. **Plan files** — `docs/plans/<slug>/{proposal,design,tasks,specs/*}.md` or `docs/plans/<slug>.md`. The intent + decomposition. Human-curated.
2. **Event log** — `.anvil/grind-events.jsonl`. Append-only. Records every `slice-dispatched`, `slice-reviewed`, `slice-merged`, `slice-deferred`, `plan-revised`, etc.
3. **Worktrees** — `<repo-parent>/<repo-name>-<slice-id>/`. The physical isolation of each slice's work. Git knows about them via `.git/worktrees/<name>/`.

Plus two append-only logs that are sibling-data, not core state:

4. **Learnings log** — `.anvil/learnings.jsonl`. Per-project gotchas + invariants. Written by `/learn`.
5. **Decisions log** — `.anvil/decisions.jsonl` (new in B3). Per-project architectural decisions. Written by `/decide`.

**This is the moat.** All of it is markdown / jsonl / yaml. Operator can grep, version-control, and survive Claude crashes by reading the disk.

---

## Acceptance — user-facing surfaces

Phase A landing + README rewrites must satisfy:

**Given** a first-time visitor lands on `docs/index.html`
**When** they read the hero (above the fold)
**Then** they can name (in their own words) the actual product within 30 seconds: "anvil keeps Claude Code work alive across context loss by storing state in your repo."

**Given** a visitor reads the README "Who it's for" section
**When** they finish the section
**Then** they can place themselves: "this is for me / this is not for me" without ambiguity.

**Given** a visitor opens the skill table
**When** they read any skill description
**Then** no decorative metaphor (forge, strike, billet, quench) appears; every description is one plain-English line.

---

## Acceptance — new skills surface state

Every new skill in Phase B operates on the existing state model. None invent new state:

**B1 /anvil-status**:
- READS plan files + grind-events.jsonl + gh PR state. Writes nothing.

**B2 /grind --resume**:
- READS grind-events.jsonl. Appends one event (`resume`). Doesn't rewrite existing events.

**B3 /decide**:
- WRITES `.anvil/decisions.jsonl`. New file. Sibling of `.anvil/learnings.jsonl`. Same shape rules (append-only, json-line-per-row).

**B4 /recap v2**:
- READS plan files + grind-events.jsonl + gh PR + merged-diff history. Writes a recap HTML file (output artifact, not state).

---

## Anti-patterns to avoid

- A skill that introduces a SQLite-backed state store. The repo-native promise breaks.
- A skill that depends on a cloud service for state retrieval. The repo-native promise breaks.
- A skill that requires a long-running daemon. The "stop and resume" promise breaks.
- Marketing copy that hedges on the local-only stance. "Repo-native first, cloud sync coming soon" reads as "we'll change our mind under VC pressure."

---

## The one-sentence test

If a reader of the landing page can finish this sentence in their own words after 30 seconds, the positioning is right:

> Anvil stores my multi-PR workflow state in my repo so that ___________.

Right answers: "Claude crashes don't lose my context" / "I can resume tomorrow" / "the work doesn't depend on a chat window" / "I can grep my history."

Wrong answers: "I get more skills" / "it forges my code" / "AI does my PRs."
