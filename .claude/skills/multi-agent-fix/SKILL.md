---
name: multi-agent-fix
description: "Applies the Kwella blueprint's Orchestrator/Worker/Validator multi-agent strategy to a bug fix or small feature. Trigger: user says 'fix using the multi-agent strategy', 'use the orchestrator/worker/validator flow', references the Kwella-Platform-Master-Handover-Blueprint's multi-agent section, or asks for adversarial QA on a fix. Use for scoped, well-defined fixes (1-5 files) — not full screen builds, which follow the blueprint's separate Screen-by-Screen Quality Gate (Section 4)."
metadata:
  author: kwella
  version: "1.0.0"
---

# Multi-Agent Fix Workflow

Operationalizes Section 3 of `Kwella-Platform-Master-Handover-Bluepr.md` ("Multi-Agent Strategy — Luke's Missions Architecture") for concrete, scoped fixes. Three roles, one after another, each with a clean context boundary — this is what actually prevents context drift and rubber-stamped QA, not just running more agents.

## When to use this vs. plain editing

Use this workflow when a fix is non-trivial enough that an implementer could plausibly miss an edge case, AND correctness matters enough to be worth an independent adversarial check — e.g. changes to the bidding/trip state machine, wire-contract payload shapes, or anything spanning the Flutter apps + backend Lambda boundary. Skip it for one-line typo fixes, pure formatting, or doc-only edits — the overhead isn't worth it there.

For a full screen build (new UI screen end to end), use the blueprint's **Screen-by-Screen Quality Gate** (Section 4) instead — that's a different, heavier loop (Orchestrator writes a Validation Contract with UI/UX assertions, Worker builds the screen, then a *Scrutiny Validator* and a separate *QA Validator* both gate before the screen is locked and the next one starts). This skill is the lighter-weight version for fixes, not new screens.

## The three roles

### 1. Orchestrator (you, in the main conversation — do not delegate this phase)

- Read the actual code for every file the issue touches. Don't take the issue description at face value — grep for the real function/route, read its full context, and check for an existing analogous pattern elsewhere in the codebase (there almost always is one in this repo — e.g. `selectBid`'s `tripMatchConfirmed` push is the canonical pattern for driver-profile/vehicle enrichment; other routes should match it, not invent their own shape).
- Check existing tests for the code path first (Strict TDD Mandate in `CLAUDE.md` — tests are updated *alongside* implementation, not bolted on after).
- Write a **Validation Contract**: a numbered list of concrete, checkable assertions — file/line-level where possible, not vague goals. Each assertion should be something a Validator with zero implementation context could verify by running a command or reading a diff.
- Decide scope boundaries explicitly, especially when investigation surfaces a bigger, adjacent problem (this happens often — e.g. fixing a pubspec path can surface an unrelated stale test or a transitive version conflict). Write the boundary into the contract: what's in scope, what's a flagged follow-up the Worker must surface but not silently fix or silently ignore.

### 2. Worker (spawn via the `Agent` tool, `general-purpose` type)

Give the Worker prompt:
- The full Validation Contract, with concrete file paths, line ranges, and the exact pattern to mirror (paste the reference code, don't just describe it).
- An explicit instruction not to expand scope beyond the contract, and what to do if it hits the kind of adjacent problem you already anticipated (e.g. "skip it visibly with `@Skip(...)` and a comment explaining why + what would restore it — do not silently delete or silently fix it").
- An explicit instruction **not to `git add` or `git commit`** — that decision belongs to the human, per this repo's general safety rules (this overrides the blueprint's literal "Worker commits via git" language from Section 3.1 — treat commits as the human's call unless they've said otherwise for the session).
- The validation commands to run before it considers itself done (compile checks, the specific pytest/flutter test invocations, from `CLAUDE.md`'s Core Commands section), and a request for a structured handoff report (Changes Made / Command Results / Discovered Issues / Unaddressed Tasks) under ~400 words as its final message.

Run the Worker in the foreground (`run_in_background: false`) when you're about to hand its output straight to the Validator — there's no useful parallel work to do while a single scoped fix is being implemented.

### 3. Validator (spawn via a **second, separate** `Agent` call — never let the Worker validate itself)

- Give it the Validation Contract, and nothing else — no summary of what the Worker did, no hint about which files changed. It must run `git status`/`git diff` itself and re-derive the facts.
- Tell it explicitly to verify claims independently rather than trust the Worker's own comments (e.g. "read the target pubspec's `name:` field yourself, don't assume the Worker got it right").
- Ask for a per-assertion verdict (PASS/FAIL/CONCERN) with one line of evidence each, plus an overall verdict and a punch-list of anything that must go back to the Worker.
- If the Validator returns FAIL or CONCERNs that matter, send the punch-list back to the *same* Worker agent via `SendMessage` (reuse its agent id — it already has the context) rather than re-briefing a fresh Worker from scratch, unless the required change is large enough that a clean slate is actually better.

## After validation passes

Report the outcome to the human with the diff summary and validator verdict. Do not commit unless the human asks — surface that changes are staged-and-ready, not committed, and let them decide (this matches this repo's general git safety posture, which takes precedence over the blueprint's more autonomous framing).

## Worked example

2026-08-24: applied this exact loop to two fixes in one pass — `kwella_core/pubspec.yaml`'s broken dev_dependency paths (`kwella_rider_app`/`kwella_driver_app` → `kwella_rider`/`kwella_driver`, which also required renaming the yaml keys to match each target's real `name:` field, not just the path string) and `sendBid`'s `driverBidReceived` push missing driver name/rating/vehicle fields (fixed by mirroring `selectBid`'s existing `tripMatchConfirmed` resolution pattern). The Orchestrator phase caught that the pubspec fix alone wouldn't be sufficient — a stale end-to-end test imported packages/files that no longer exist under the current app architecture — and scoped that as "Worker must visibly skip with a reason, not silently patch or delete," which is exactly what surfaced (plus an unrelated `flutter_dotenv` transitive version conflict between the two sibling apps) and got handled correctly. The Validator independently re-derived every claim and returned overall PASS with one justified CONCERN (the dependency_override), rather than rubber-stamping the Worker's own report.
