# kwella Developer Guide & Commands

## Core Commands
* **Python Backend Test:** `pytest kwella-backend/tests/test_bidding_engine.py`[cite: 1]
* **Python Backend Compile Check:** `python3 -m py_compile kwella-backend/src/lambdas/bidding_engine/handler.py`[cite: 1]
* **Flutter App Analyze:** `flutter analyze` (Run across `kwella_core`, `kwella_driver_app`, and `kwella_rider_app`)[cite: 1]
* **Local E2E Matrix Run:** `./scripts/run_local_e2e_matrix.sh`[cite: 1]

## Core Requirements & Context Retrieval Rules
* Always use the `/graphify` skill for quick and token-efficient reads and context gathering.
* Always elicit more information from the user before even generating a plan to ensure that the coding assistant and the user are on the same level of understanding with regards to the feature that needs to be implemented or issue that needs to be addressed.

## Multi-Agent Architecture (Luke's Missions Architecture)
Work follows a strict three-role multi-agent workflow to prevent context drift and ensure quality[cite: 2]:

* **Orchestrator Agent:** Scopes task boundaries, checks requirements, generates feature plans, and defines an independent **Validation Contract** before code is written[cite: 2].
* **Worker Agent:** Operates with a clean context, implements features (Flutter/Amplify), and commits code via Git[cite: 2].
* **Validator Agent:** Operates adversarially with a fresh context window to run tests, inspect UI/UX, and verify assertions against the Validation Contract[cite: 2].

## Serial Screen-by-Screen Quality Gate Workflow
Work is executed serially—one screen/feature loop at a time[cite: 2]. No new screen development proceeds until all quality gates pass[cite: 2]:

1. **Orchestrator Phase:** Write Validation Contract (Assertions & UI Specs)[cite: 2].
2. **Worker Phase:** Build Flutter UI + Amplify/AWS Integration[cite: 2].
3. **Scrutiny Validator:** Run `flutter test`, linter, and type checks[cite: 2].
4. **QA Validator:** Execute Widget/Integration tests and screen behavior checks[cite: 2].
5. **Lock & Proceed:** Git commit and move to the next screen upon all gates passing[cite: 2].

## Target Execution Stack & Region
* **Target Execution Window:** August 2026 – October 2026[cite: 2]
* **AWS Region Target:** `af-south-1` (Cape Town)[cite: 2]
* **Architecture Strategy:** AWS Amplify-driven serverless setup (Amplify Auth, AppSync/GraphQL Data, DynamoDB, S3 Storage) with Flutter SDK bindings[cite: 2].

## Engineering Governance Guardrails
* **Do Not Reinvent the Wheel Mandate (Package-First / Anti-Over-Engineering):** *This is the primary engineering principle.* Before writing any custom code, check pub.dev (Flutter), PyPI (Python), and industry-standard open-source repositories for battle-tested solutions[cite: 1]. **Mandatory evaluation criteria:** maintenance activity, community adoption (GitHub stars, downloads), documentation quality, security posture, and version compatibility. **Standard e-hailing mechanics** (place search/autocomplete, OTP input pins, map polylines, real-time location streaming, haul calculations, sliding bottom sheets, phone number formatting, push notifications) must ALWAYS use established packages—never build custom implementations[cite: 1]. Only implement custom code when: (1) no suitable package exists for the specific use case, (2) all candidate packages fail strict evaluation criteria, or (3) the behavior is a core product differentiator or kwella-specific competitive advantage[cite: 1]. This is not a guideline—it is a mandate that applies to every feature and bug fix[cite: 1].
* **Zero-Hardcoded-Secrets Mandate:** Absolutely zero private keys or plaintext environment secrets in tracked source code[cite: 1, 3]. Inject client keys at build-time via git-ignored properties files[cite: 1, 3].
* **Strict TDD Mandate:** Modify or write test suites *prior* to extending application features[cite: 1]. If a test suite fails, application code must be refactored until it passes; do not alter test criteria to bypass a code error[cite: 1].
* **State Machine Integrity:** All real-time trip modifications must strictly align with the 7-phase execution path and flat JSON wire contract across the Flutter apps and AWS Lambda handlers[cite: 1].

## Domain & Business Logic Rules
* **Target Vehicle Scope:** Strictly 7-seater vehicles (*amaphela*)[cite: 3, 4]. Minibus taxis and split-fare shared routes are strictly out of scope for MVP[cite: 3, 4].
* **Operating Geography:** Philippi, Nyanga, and Gugulethu (Cape Town)[cite: 3, 4].
* **Verification & Trust Anchors:** Vehicle/driver verification uses CarScanAI, valid license disc, driver PrDP, clear criminal-record checks (HURU/CarScan when switching to Driver role), and physical CATA sticker identifiers[cite: 3, 4].
* **UI/UX Brand Palette:** CATA Transit Green (`#1E4620`), Community Cream (`#F4F4EA`), and Deep Slate/Obsidian Black (`#111111`) with sliding bottom-sheet ergonomics[cite: 2, 3].
* **Server-Side Fare Floor:** Baseline fares scale dynamically based on distance, time of day, passenger count (1–6), and fuel prices[cite: 3, 4]. Minimum fare floor rule: Total trip fare cannot fall below `(flat_rate x 6 seats)`[cite: 3, 4].
* **Cancellation Debt & Platform Fee Holiday:** Late cash cancellations put rider accounts on Debt Status (`is_suspended = True`) until settled[cite: 3, 4]. kwella waives its 10% platform commission for the affected driver on subsequent trips as a credit until the owed penalty amount is balanced[cite: 3, 4].