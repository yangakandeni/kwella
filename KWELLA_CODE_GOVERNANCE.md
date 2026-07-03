# kwella - Code Governance & Anti-Deprecation Directives

This document defines strict technical constraints for code generation. Agents must validate all generated code against these rules before presentation.

## 1. Terraform & Infrastructure-as-Code (IaC)
* [cite_start]**Minimum Version:** Always target Terraform `>= 1.6.0`[cite: 1].
* [cite_start]**Provider Syntax:** Explicitly use the modern `required_providers` block specifying the HashiCorp source and version constraints (`~> 5.0`)[cite: 1].
* [cite_start]**Deprecated Blocks:** * NEVER use the inline `tags` argument inside separate resources if a global `default_tags` block is configured in the provider[cite: 1].
  * [cite_start]NEVER use `type = "string"` (lowercase); always use built-in types precisely: `type = string`[cite: 9, 10].
* **Installation:** If providing local setup instructions, always use modern package managers directly without obsolete tapping methods.

## 2. Python 3.12 (AWS Lambda Compute)
* **Runtime Standards:** Code must strictly use features compatible with Python 3.12.
* **Typing:** Use native Python 3.9+ type hinting standards (e.g., `list[str]` or `dict[str, Any]`). DO NOT import `List` or `Dict` from the legacy `typing` module.
* **AWS SDK (Boto3):**
  * Connection pooling clients (`boto3.resource` or `boto3.client`) MUST be initialized globally outside the Lambda handler execution loop to enable connection reuse.
  * Explicitly handle `botocore.exceptions.ClientError` for all DynamoDB operations.
* **Data Validation:** Use **Pydantic v2** syntax. DO NOT use Pydantic v1 patterns (e.g., use `model_validator` instead of `@root_validator`, and `model_dump()` instead of `.dict()`).

## 3. Flutter & Dart (Client Mobile Application)
* **Dart Version:** Target Dart 3.x with strict Sound Null Safety enforced.
* **State Management:** Keep presentation components decoupled from business logic using clean Streams, ValueNotifiers, or modern asynchronous Controllers.
* **Networking:** Use the `web_socket_channel` package cleanly. Explicitly manage socket sinks by implementing complete object disposal states to prevent persistent memory leaks on low-end devices.

## 4. Security & Hardcoding Guardrails
* **No Hardcoded Secrets:** NEVER generate files containing mock or hardcoded API tokens, AWS keys, or private salts. Always source configurations via `os.environ` or environment variable parameters.
* **Least Privilege:** When drafting IAM roles or resource policies, never use wildcard permissions (`*`). Specify exact actions (e.g., `dynamodb:GetItem`, `dynamodb:PutItem`).

## 5. Workspace Hygiene & Version Control
* **Git Maintenance Engine:** Before completing any implementation task that introduces new languages, packages, dependencies, or runtime environments, the agent MUST review the root `.gitignore` file.
* **Auto-Appends:** If the new task creates files that should not be tracked globally (e.g., `.env` files, build caches, or temporary runtime configs), the agent must autonomously append the relevant rule to the `.gitignore` under the correct category before declaring the task finished.

## 6. Strict TDD Mandate & Simulator Synchronization
* **Test-First Execution:** Agents must write or modify test suites *prior* to implementing or extending application features. Every new feature must achieve 100% test coverage alignment.
* **Test Integrity Overrides:** If a test suite fails, the application code must be refactored until the tests pass. Modifying existing test criteria to bypass a code error is strictly prohibited unless there is an explicitly documented, architecturally sound justification.
* **Simulator/Emulator Realignment:** Any changes altering backend schemas, payload contracts, or state machine transitions must be instantly mirrored in the local Python marketplace simulator (`scripts/simulate_marketplace_trip.py`) and companion simulation hooks to ensure the 7-phase execution path remains completely green.
