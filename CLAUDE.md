# Kwella Developer Guide & Commands

## Core Commands
* **Python Backend Test:** `pytest kwella-backend/tests/test_bidding_engine.py`
* **Python Backend Compile Check:** `python3 -m py_compile kwella-backend/src/lambdas/bidding_engine/handler.py`
* **Flutter App Analyze:** `flutter analyze` (Run across kwella_core, kwella_driver_app, and kwella_rider_app)
* **Local E2E Matrix Run:** `./scripts/run_local_e2e_matrix.sh`

## Engineering Governance Guardrails
* **Anti-Over-Engineering Mandate:** Prioritize production-grade open-source packages and native SDKs. Do not build custom internal utilities if a stable out-of-the-box solution exists.
* **Zero-Hardcoded-Secrets Mandate:** Absolutely zero private keys or plaintext environment secrets in tracked source code. Inject client keys at build-time via git-ignored properties files.
* **Strict TDD Mandate:** Modify or write test suites *prior* to extending application features. If a test suite fails, application code must be refactored until it passes; do not alter test criteria to bypass a code error.
* **State Machine Integrity:** All real-time trip modifications must strictly align with the 7-phase execution path and flat JSON wire contract across the Flutter apps and Python AWS Lambda handlers.
