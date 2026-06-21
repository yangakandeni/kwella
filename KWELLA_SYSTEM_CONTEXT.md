# kwella - System Architecture & Business Logic Master Blueprint

## 1. Product Context & Target Market
* **Name:** kwella (Township Mobility Platform)
* **Target Vehicle Scope:** Strictly 7-seater vehicles (*amaphela*). Minibus taxis (vans) are explicitly out of scope for MVP.
* **Trip Type:** Dedicated, private point-to-point trips only (no shared routes).
* **Physical Hub:** Onboarding, manual document audits, and physical inspections occur at Philippi Village, Cape Town.
* **UI/UX Aesthetic:** High-contrast CATA Transit Green (`#1E4620`), Community Cream (`#F4F4EA`), and Deep Slate/Obsidian Black (`#111111`) following universal e-hailing ergonomics (sliding bottom-sheet model).

## 2. Core Technological Constraints
* **Mobile App Framework:** Flutter + Dart (Feature-First architecture layout).
* **Cloud Infrastructure:** AWS Serverless managed exclusively via Terraform.
* **Backend Compute Runtime:** Python 3.12 (AWS Lambda).
* **Real-Time Communications:** Amazon API Gateway WebSocket API (No heavy HTTP polling to preserve rider/driver data bundles).
* **Local Development Mock:** LocalStack Community Edition + wscat CLI for WebSocket simulation.

## 3. Core Database Strategy (DynamoDB Single-Table Design)
* **Table Name:** `kwella-core-production`
* **Keys:** Partition Key (`PK` - String), Sort Key (`SK` - String).
* **Global Secondary Index:** `GSI1` (Hash Key: `GSI1_PK`, Range Key: `GSI1_SK`).
* **Entity Mapping Conventions:**
    * Rider Profile: `PK = USR#<RiderId>`, `SK = PROFILE`
    * Driver Profile: `PK = USR#<DriverId>`, `SK = PROFILE`, `GSI1_PK = VEH#<AssignedCataSticker>`, `GSI1_SK = DRIVER`
    * Owner Profile: `PK = USR#<OwnerId>`, `SK = PROFILE`
    * Vehicle Asset: `PK = VEH#<CataSticker>`, `SK = METADATA`, `GSI1_PK = USR#<OwnerId>`, `GSI1_SK = VEH#<CataSticker>`
* **CATA Sticker Validation:** The vehicle's physical CATA sticker identifier serves as a unique `PK` prefix to enforce uniqueness natively.

## 4. Advanced Bidding & Cancellation Ledger Engine Rules
* **Bidding Marketplace:** Premium dynamic bidding engine. Base price scales on distance + passenger count adjustments (1 to 6 passengers).
* **Payment Rail:** Hybrid Model (Cash + Digital Card Pre-authorization).
* **Algorithmic Cancellation Logic:**
    * Rider cancels late on a card trip: Auto-charge card penalty, settle driver wallet instantly.
    * Rider cancels late on a cash trip: Rider account hits Debt Status. kwella waives its 10% platform fee for that specific driver on subsequent rides (0% Platform Fee Holiday) until the waived sum equals the cancellation penalty amount (tiered up to R30 based on driver proximity). The platform collects the balance back when the rider settles their debt to clear the account suspension.
    * Driver cancels trip: Drastic star-rating penalty deducted automatically based on proximity to pickup. Suspension kicks in if rating drops below 4.0 stars.

## 5. Engineering Governance
* **Code Quality & Stability Constraints:** All code generation tasks must strictly adhere to the anti-deprecation and security guardrails outlined in `KWELLA_CODE_GOVERNANCE.md`.

## 6. Current State of Implementation (Phases 12-15)

The following core modules are fully implemented, thoroughly tested (144+ automated tests), and live in the workspace:

### A. Telematics & Geofencing Ingestion Layer (Phases 12 & 13)
- **Backend:** `geofence_utils.py` contains optimized Haversine formula logic using an explicit Earth radius constant of `6371000.0` meters. 
- **WebSocket Loop:** The `bidding_engine` Lambda handler processes incoming `"updateLocation"` payload actions. It computes the distance between the vehicle coordinates and an active trip's destination. If the driver is within `50.0` meters, it injects a transient `"flags": {"geofence_status": "ARRIVED"}` into the synchronous gateway reply without mutating the database record.
- **Mobile Client:** `KwellaTelemetryController` intercepts this arrived flag via Riverpod. It maps the state change to display an interactive, manual drag-gesture `_SlideToConfirmButton` component on the map screen, leaving final trip lifecycle confirmation under the driver's manual control (Sovereignty Rule).

### B. Marketplace Matching & Live Bidding Tiers (Phase 14)
- **Backend:** The `"requestTrip"` route executes a multi-page paginated DynamoDB table scan (`LastEvaluatedKey` tracking) to capture all active driver records containing `SK = "TELEMETRY"`. It filters and flags drivers inside a `5000.0`-meter radius, sending them a `"action": "rideOfferAvailable"` broadcast package over their API Gateway socket connections.
- **Mobile Client:** Driver screens intercept this offer broadcast, spinning up a 15-second ticking decay timer overlay card. It contains an animated progress bar and a multi-tier quick counter-bidding button row:
  - `bid_accept_base` (Accept Base Fare)
  - `bid_counter_r15` (Base Fare + R15)
  - `bid_counter_r30` (Base Fare + R30)
- Tapping any tier immediately locks user input, stops the countdown timer, clears the active offer state context, and dispatches a `"action": "sendBid"` payload back up the socket.

### C. Financial Payout & Wallet Ledger (Phase 15)
- **Backend:** Tapping arrival triggers a `"confirmArrival"` action. The backend executes an atomic DynamoDB `TransactWriteItems` operation:
  - Verifies the Trip status is `'ACCEPTED'` or `'ARRIVED'`, then sets it to `'COMPLETED'`.
  - Increments the Driver's Wallet balance and `daily_total` record (`SK = "WALLET"`) by exactly 85% of the final agreed bid using strict Python `Decimal` precision currency calculations.
- **Mobile Client:** Intercepts `"status": "WalletSettled"`, updates the top-header permanent shift earnings tally container, and renders a micro-animated floating success `EarningsToast` notification overlay built on Flutter's overlay framework with an elastic animation curve (`Curves.easeOutBack`).
