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

## Core Engineering Governance & Guardrails

* **Anti-Over-Engineering Mandate:** AI agents and developers must strictly prioritize production-grade, open-source packages and native platform SDKs over building custom internal algorithms or utilities (e.g., custom polyline decoders or math-heavy coordinate interpolators). If a stable out-of-the-box solution exists, it must be used. Custom logic is strictly an exception requiring explicit business justification.

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

### D. Asynchronous Push Notification Fallback Infrastructure (Phase 16)
- **Mobile Client:** Added push notification deep-linking in `lib/main.dart` using `FirebaseMessaging.onMessageOpenedApp.listen`. When a driver taps a notification with `action: "rideOfferAvailable"`, the client reads `tripId`, `base_fare`, and coordinate payload fields, then forwards the data to `KwellaTelemetryController.handlePushNotificationClick`.
- **State & Reconnaissance:** `KwellaTelemetryController` now forces a WebSocket reconnect via `KwellaWebSocketService.connect()` whenever the app resumes from a disconnected socket state before hydrating `TelemetryState.activeOffer`.
- **Offer Hydration:** Push notification payloads are deserialized into `ActiveRideOffer` using a new `fromPushNotification()` factory, and the standard 15-second countdown timer is started exactly as with normal WebSocket offers.
- **Test Coverage:** Added targeted unit test coverage in `test/features/location/presentation/controllers/kwella_telemetry_controller_test.dart` validating push-click offer hydration, countdown initialization, and WebSocket reconnection behavior.

### E. Mobile App Split & Rider Companion State Machine (Phase 17)
- **Monorepo Refactor:** The mobile application workspace has been split into two separate Flutter clients under `kwella-apps/`: `kwella_driver` (existing driver app) and `kwella_rider` (new rider companion app).
- **Rider State Machine:** `kwella_rider` now includes an incoming WebSocket event multiplexer in `lib/features/booking/presentation/controllers/kwella_rider_controller.dart` with a `RiderTripStatus` lifecycle of `idle`, `searching`, `biddingOpen`, `accepted`, `arrived`, and `completed`.
- **Event Transitions:** The rider controller maps `driverBidReceived` to `biddingOpen`, `tripMatchConfirmed` to `accepted`, `geofenceTrigger` to `arrived`, and a `status` field of `WalletSettled` to `completed`.
- **Controller Validation:** The new suite includes `test/kwella_rider_controller_test.dart`, which asserts that an incoming driver bid event transitions the status to `biddingOpen`.
- **Rider Booking UI:** Added `kwella_app_rider/lib/features/booking/presentation/screens/rider_booking_screen.dart` with the initial Rider booking layout, including a placeholder map container, sliding bottom sheet, destination input row, passenger count selector for 1-6 passengers, and a high-contrast `Request Ride` button wired to `KwellaRiderController.requestTrip()`.
- **Multi-Driver Bids Carousel Overlay:** Implemented a horizontal bid carousel overlay in `kwella-apps/kwella_rider/lib/features/booking/presentation/screens/rider_booking_screen.dart` that appears when `RiderTripStatus.biddingOpen`; it uses Riverpod `StreamProvider`s to stream `availableBids`, and renders a smooth `ListView.builder` of bid cards directly above the bottom sheet.
- **Driver Bid Card Widget:** Added `kwella-apps/kwella_rider/lib/features/booking/presentation/widgets/driver_bid_card.dart` with Community Cream background, Deep Slate typography, and a CATA Transit Green accept button. The card displays driver name, rating, vehicle details, license plate, and CATA sticker.
- **Bid Selection Controller:** Added `KwellaRiderController.selectBid(String driverId)` in `kwella-apps/kwella_rider/lib/features/booking/presentation/controllers/kwella_rider_controller.dart`, which serializes and pushes `{"action":"selectBid","tripId":"...","driverId":"..."}` over the WebSocket sink and transitions the state to `accepted`.
- **Test Coverage:** Added `test/features/booking/presentation/widgets/driver_bid_card_test.dart` verifying that bid metadata, vehicle registration details, and custom fare price render correctly in the layout.
- **Live Telematics Map Stream:** Added `liveDriverLocation` payload parsing in `kwella-apps/kwella_rider/lib/features/booking/presentation/controllers/kwella_rider_controller.dart`, stored in `RiderTripState.currentDriverLocation`, and surface a moving marker UI in `kwella-apps/kwella_rider/lib/features/booking/presentation/screens/rider_booking_screen.dart` when `RiderTripStatus` is `accepted` or `arrived`.
- **Geofence Arrival Overlay:** Implemented instant overlay banner text for `geofenceTrigger` events with `geofence_status: ARRIVED` on the rider booking screen.
- **Widget-Level Tracking Tests:** Added `kwella-apps/kwella_rider/test/features/booking/presentation/screens/rider_booking_map_widget_test.dart` validating live driver location animation updates for `RiderTripStatus.accepted` and arrival overlay rendering for `RiderTripStatus.arrived`, preventing silent regression in marker rendering and arrival banner visibility.

### F. Local Integration Simulation Orchestration (Phase 18)
- **Local Simulator:** Added `scripts/simulate_marketplace_trip.py`, a pure Python 3.12 standard-library WebSocket lifecycle simulator for LocalStack/API Gateway WebSocket local testing.
- **Shell Hook Wrapper:** Added `scripts/smoke_test.sh` as the companion shell execution hook that validates local environment setup, launches the Python simulator, and captures non-zero simulator exits with a clear failure banner.
- **Dual-Client Parallelism:** The simulator spawns concurrent `mock_rider_client()` and `mock_driver_client()` flows to execute a full lifecycle against the live WebSocket bidding plane.
- **WebSocket Auth Handshake:** The local simulator now constructs dedicated rider and driver URIs from `KWELLA_WS_URL`, injecting mock `Authorization` and `userId` query parameters per backend authorizer expectations. It supports both local and remote API Gateway WebSocket endpoints without stripping stage path suffixes.
- **WebSocket Route Deployment:** The backend Terraform now includes explicit `requestTrip` WebSocket route and response configuration for the bidding engine integration, aligning deployed infrastructure with the backend route handler.
- **Smoke Test Fallback:** The smoke test wrapper exports a local default for `KWELLA_WS_URL` when it is not already set, so local verification can target `ws://localhost:3001` without requiring explicit setup.
- **Lifecycle Coverage:** The orchestrator drives `requestTrip`, `rideOfferAvailable`, `sendBid`, `selectBid`, `updateLocation`, `confirmArrival`, `startTrip`, and `submitRating` actions, validating the backend's `WalletSettled` settlement event and rider driver-location sync.
- **Timeout & State Assertions:** The script enforces 5-second per-step timeouts and aborts on invalid payload contracts, with color-coded console phase blocks for each major lifecycle stage.

## 7. Phase 18: Hybrid Payment Rails & Debt Ledger

### A. Transactional Late-Cancellation Ledger Keys
- **Rider Debt State Entity:** Cash-trip late cancellations now write a dedicated debt item using `PK = USER#<rider_id>` and `SK = DEBT#<trip_id>`.
- **Rider Debt Attributes:** Each debt record stores `amount` (`Decimal`), `timestamp` (UTC ISO-8601), `status = PENDING_SETTLEMENT`, and `reason = LATE_CANCELLATION`.
- **Driver Compensation Ledger Entity:** The paired zero-commission driver credit writes to `PK = USER#<driver_id>` and `SK = LEDGER#<timestamp>`.
- **Driver Credit Attributes:** Each compensating entry stores `amount`, `timestamp`, `trip_id`, `rider_id`, `reason = LATE_CANCELLATION`, `platform_commission_rate = 0.00`, and `platform_commission_amount = 0.00`.

### B. Ledger Service Enforcement Rule
- **Owning Module:** `kwella-backend/src/lambdas/ledger_service/cancellation_handler.py` now owns the hybrid payment late-cancellation transaction assembly.
- **API Surface:** API Gateway route `POST /ledger/cancellation` and the WebSocket action key `ledger_cancellation` are now fully wired to the `PROCESS_CANCELLATION` action in `kwella-backend/src/lambdas/ledger_service/handler.py`.
- **Infrastructure Alignment:** Terraform now binds `ledger_cancellation` to the `aws_apigatewayv2_integration.ledger_service` target as a clean inbound route without an accompanying synchronous HTTP-style response resource.
- **Strict Input Contract:** The route accepts `tripId`, `amount`, `driverEnRouteAt` and `cancelledAt` from the request body and computes `driverInTransitSeconds` when needed.
- **Validation Response:** Missing mandatory timing markers now return a clean `400` payload with `Missing mandatory transaction markers`.
- **Eligibility Gate:** The transaction only executes when the rider cancels after the driver has been in transit for more than 180 seconds (3 minutes).
- **Atomic Write Contract:** The backend issues a single DynamoDB `TransactWriteItems` call containing exactly two conditional `Put` operations: the rider debt item and the driver compensating credit item.
- **Rollback Guarantee:** If either conditional write fails, DynamoDB cancels the entire transaction so no partial debt or credit record is persisted.

## 8. Phase 19: Fleet Operational Clearing Layout

### A. Data Layer Schema Mapping
- **Vehicle Ownership Association Record:** Fleet ownership maps explicitly via:
  - `PK = VEHICLE#<vehicle_id>`
  - `SK = OWNERSHIP`
- **Ownership Attributes:**
  - `owner_id` (Formatted as `DRIVER#<driver_id>` or `FLEET#<owner_id>`)
  - `status = ACTIVE`

### B. Route Clearing House Logic
- **Module:** `kwella-backend/src/lambdas/ledger_service/clearing_house.py`
- **Method:** `get_settlement_recipient(vehicle_id)`
- **Behavior:**
  1. Queries DynamoDB for the vehicle's `VEHICLE#<vehicle_id>` ownership association record under the `OWNERSHIP` sort key.
  2. If an active record is found, extracts and returns the configured `owner_id` (routing 100% of gross weekly earnings to that target).
  3. If no active ownership record exists, defaults the routing target to the active driver assigned to the vehicle by querying the GSI1 index (`GSI1_PK = VEH#<vehicle_id>`, `GSI1_SK = DRIVER`) and formatting the result as `DRIVER#<driver_id>`.
  4. If no driver profile is found, defaults to `DRIVER#UNKNOWN` as a safe fallback.
