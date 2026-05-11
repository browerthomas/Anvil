# Anvil positioning + state-as-product sprint

> Reposition anvil around its actual moat — durable repo-native workflow state — and rename `/persona` to `/lens` for professionalism. Adds 4 new skills that surface the state model, closes the existing backlog of quality follow-ups, and locks down pre-merge discipline so future work doesn't ship the leak classes that surfaced today.

**Status:** locked
**Author:** maintainer
**Date:** 2026-05-11
**Plan ID:** positioning-and-state-product
**Layout:** folder

---

## Goal

End-state: anvil reads as state infrastructure for agentic coding workflows, not as a command suite. Visitors land on the page and see (a) the actual pain anvil solves, (b) the moat (state lives in your repo, not in chat), and (c) the smallest win (one skill they can run today). The product surface still ships ~16 skills + the lens family, but the docs lead with WHY, not WHAT. Three new state-introspection primitives — `/anvil-status`, `/grind --resume`, `/decide` — make the durable state model visible + recoverable. A recap engine v2 captures WHY (assumptions, drift, residual risk) not just WHAT. `/persona` becomes `/lens` everywhere. Quality fences (pre-merge leak grep, expanded smoke tests) prevent the leak classes that surfaced during dogfood.

---

## Why now

- **Critic feedback** from a 2026-05-11 product review surfaced two convergent gaps: insider language buries the value prop, and the state model is invisible.
- **State infrastructure is part of the moat** — anyone can copy slash-command prompts in a weekend; few teams build durable + resumable + repo-native workflow state. The skill suite + codex integration is the on-boarding hook; state is what keeps adopters at sprint 4+. Position as: "Claude Code workflows + durable state that survives interruption."
- **Existing backlog** has 9 open issues (#24, #27-#30, plus 4 from 4-critic adversarial pass) that need to land before the next adoption push.
- **TOS arch-standardisation grind is paused at 9/16** to make room. Anvil quality compounds across remaining 7 TOS slices + every future grind.

## Honest cost

**Working time: 12-16 calendar-days (~2-3 weeks)**, not "1 week." This reflects the actual scope per phase + codex retros + ASK delays. See design.md risk register row 2 for per-phase breakdown.

Slip risk: high. If the sprint runs past 2026-06-07, the default-Opus subscription window closes and per-slice cost goes up. Plan to compress D5 if needed (drop it to follow-up) to keep E1 on schedule.

---

## Scope

### In scope

- **Phase A — Positioning + copy (5 slices).** Hero rewrite around state-not-chat, strip insider language across landing + README, collapse audience grid to one wedge, drop forge metaphor + decorative imagery, README structural refresh.
- **Phase B — New state-introspection skills (4 slices).** `/anvil-status` text dashboard; `/grind --resume` from event log; `/decide` decision-memory sibling of `/learn`; recap engine v2 capturing WHY.
- **Phase C — `/persona` → `/lens` hard rename (3 slices).** Directory + skill name + all references; one-shot migrator for operator's local install; back-compat alias for grace window.
- **Phase D — Quality fences + backlog rollup (5 slices).** Pre-merge leak-grep script + CI hook; smoke-test extension to new skills; close #24 + #28 + #29 + #30.
- **Phase E — Release wrap (1 slice).** Version bump to v0.6.0, CHANGELOG consolidation, release notes.

### Out of scope

- **TUI for /anvil-status.** Text dashboard ships in this sprint; the bats/ncurses TUI version is a separate follow-up.
- **Cloud-side anything.** Anvil stays repo-native + local. No SaaS, no GitHub App.
- **Major architecture refactors.** No state-schema changes, no skill restructuring beyond /persona → /lens.
- **Other personas in the lens family.** The 17 lenses stay as-is content-wise; only the wrapping skill renames.
- **TOS arch-standardisation slices.** Pause maintained through entire sprint. Resume C1 (recordRefund + recordPaymentFailure) only after E1 lands.
- **Star-count / social-proof additions.** "Battle-tested" pill stays grounded in real numbers (104 tests, N PRs); no fake metrics.

---

## Stakeholders

- **Maintainer** — approves design decisions at:
  - A5 (review-lens copy: drop "review lenses, 3 namespaces" vs keep the namespace surface)
  - C1 (hard-rename ACK: confirm operator will update their local install post-merge)
  - B4 (recap engine v2: free-form prompt vs structured schema)

No other humans loop in.

---

## Success criteria

- [ ] Hero on landing reads "Ship large Claude Code tasks without losing state" or equivalent state-not-chat framing; "Forge ideas into shipped code" tagline removed.
- [ ] Insider language gone: no "OpenSpec-style", no "ASK verbs", no "multi-slice" without inline explanation on first occurrence.
- [ ] Audience grid reduced from 4 cards to 1 primary card + 1 "also useful for" line. Primary wedge: solo/small-team engineers running multi-PR Claude Code work.
- [ ] Forge metaphor stripped: hammer SVG, "billet," "lay-strike-stamp," and decorative imagery removed from landing. Skill name "anvil" stays.
- [ ] `/anvil-status <plan-path>` exists + emits a text dashboard (slice tree + PR linkage + blocked nodes + cumulative test delta + open follow-ups). Closes #27.
- [ ] `/grind --resume <plan-path>` exists + replays from last successful event in grind-events.jsonl. Idempotent.
- [ ] `/decide <key>` skill exists + writes to `.anvil/decisions.jsonl`. Sibling of /learn. Auto-injected into future /dispatch-slice briefs when relevant.
- [ ] Recap engine v2 captures WHY (assumptions changed, residual risk, architectural drift) in addition to WHAT.
- [ ] `/persona` → `/lens` hard rename complete: directory renamed, SKILL.md frontmatter renamed, README + landing + CHANGELOG + plugin.json + tests all reference `/lens`. The operator's local install rebuilt via `bin/install.sh`.
- [ ] Pre-merge leak-grep script exists at `bin/check-leaks.sh` + runs in CI on every PR. Catches: project codenames (theirownstory, BookGen), named-individual references, internal codenames (TOS), stale `<<<<<<<` markers.
- [ ] Smoke-test suite extended to cover the 4 new skills (B1-B4). All tests green.
- [ ] anvil#24, #28, #29, #30 closed.
- [ ] `make smoke` passes at the end of the sprint. CI green.
- [ ] Version bumped to v0.6.0; CHANGELOG entry covers the sprint.
- [ ] No project-private references in any committed file (verified by `bin/check-leaks.sh`).

## Phase A.5 conditional rollback trigger

A3 (audience wedge collapse) is a positioning bet without measurement. If by 2026-06-08 the 7-day star + clone count drops more than 20% vs the prior 7-day baseline taken at A3 merge time, **Phase A.5 fires** — revert A3 to a 4-audience single-column layout (no metaphor return, just structural). Other Phase A slices stay. Captured in the plan's `## Operator decision records` post-merge.

If the metric is unmeasurable (e.g. GitHub Insights latency), default to "operator inspects landing analytics manually + decides." No automated revert.
