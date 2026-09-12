# kwella Platform - Master Context & Architecture Blueprint

Welcome to the core repository for kwella. This document serves as the absolute source of truth and state-of-mind reference for all autonomous engineering agents, IDE code interpreters, and developers operating within this workspace.

## 1. Executive Vision & Target Market
kwella is a premium, on-demand, point-to-point e-hailing platform built strictly for township commuter ecosystems in South Africa (initially launching out of the Cape Flats, grounded at Philippi, Nyanga and Gugulethu area since that is where these 7-seater (commonly known as "amaphela") operate).
*   **Target Vehicle Scope:** Exclusively 7-seater amaphela (e.g., Suzuki Ertiga, Toyota Avanza) taxis (vans) and split-fare shared rides are strictly out of scope for the MVP to prevent transit association friction.

*   **Core Trust Anchor:** To mitigate risk of extortion, which is unfortunately rampant in these areas, vehicle and driver verifications will be done via the [CarScanAI](https://www.carscan.ai/) app. We (kwella) will need to contact the carscan people, at some point, and register our platform on their end. Vehicles must be linked to a valid license disc, driver PrDP, and a unique, physical **CATA (Cape Amalgamated Taxi Association) sticker number** visible on the bodywork[cite: 1, 2]. If the vehicle verification was done by the owner of the vehicle, any driver assigned to a vehicle must meet the driving criteria e.g. copy of ID, proof of address, driver's license with PrDP we need to ensure that the app only accepts drivers with a clear criminal record, this can be done via the carscan app or a driver may need to get a HURU criminal background check at an participating facility e.g. PostNet. These requirements should not be required if the owner is "just an owner" and not a driver, these requirements should be required for any entity that wants to switch from either Rider or Owner to Driver. In order to protect the drivers, every rider will need to upload a copy of their ID and proof of address (among other requirements) during the onboarding phase.
---

## 2. Technical Stack Boundaries
The platform architecture enforces a strict decoupling between the client presentation layer and the cloud computing boundaries:
*   **Frontend Mobile Client:** Built using **Flutter with Dart** for native, high-performance rendering on low-end Android mobile engines[cite: 1, 2].
*   **Cloud Backend Infrastructure:** Managed via **Terraform** and deployed to the **`af-south-1` (Cape Town)** region[cite: 1, 2].
*   **Backend Compute Runtime:** **Python 3.12** running inside AWS Lambda microservices[cite: 1, 2]. Dependencies must be isolated inside a shared Lambda Layer to minimize cold starts and deploy light packages[cite: 1].
*   **Database Engine:** **Amazon DynamoDB** utilizing a highly optimized **Single-Table Design** pattern[cite: 1, 2].

---

## 3. Core Business Logic & Algorithmic Engines

### A. Dynamic Passenger-Scaled Bidding
*   Riders select a passenger count from **1 to 6**[cite: 1, 2].
*   The backend calculates a baseline recommended fare that scales dynamically by passenger count before broadcasting the request to the live WebSocket pool[cite: 1, 2].
*   The calculated rate can never be lower than the flat rate charged for a single passenger, multiplied by the number of empty seats that the vehicle will have because it is transporting a single passenger.. for example, if the current flat rate is R10 the calculated total fee cannot be less than R10 x 6 seats! This aligns with the current setup where if a passenger is at the mall (for example) and they request a "special trip" from iphela (singular of "amaphela"), if the passenger wants the driver to drop them directly at home, without picking up any other passengers on the way, the trip costs the "flat rate x number of passenger seats". So in theory, the every trip calculation by kwella should be ("flat rate x 6 seats + (calculated fare according to factors such as destination distance, current fuel price, number of passengers (more passenger, more strain on vehicle), time of day [day time? => peak or off-peak traffic, night time? => driver is taking risks etc])) Just a note on the flat rate, this will need to be set on the config level because it often increases based on fuel price hikes.
*   **The fare formula (as implemented, 2026-09 revision).** The description above stated the model in prose; the engine in `kwella-backend/src/layers/kwella_shared/python/fare_calculator.py` implements it as:

    ```
    subtotal   = base_fare
               + (cost_per_minute x duration_minutes)
               + (cost_per_km     x distance_km)
               + passenger_surcharge
               + night_risk_premium

    total_fare = max(quantize_to_50c(subtotal), flat_rate x 6 seats)
    ```

    with every rate expressed as a factor of the config-level `flat_rate`
    (`KWELLA_FLAT_RATE_ZAR`, default R10) so a fuel-price hike moves one knob:

    | Term | Factor | At `flat_rate` = R10 |
    | --- | --- | --- |
    | `base_fare` | `(flat_rate / 2) x 6 seats` | R30.00 per trip |
    | `cost_per_km` | `0.75 x flat_rate` | R7.50 / km |
    | `cost_per_minute` | `0.08 x flat_rate` | R0.80 / min |
    | `passenger_surcharge` | `0.25 x flat_rate` per extra passenger | R2.50 each |
    | `night_risk_premium` | `0.50 x flat_rate` (22:00–05:00 SAST) | R5.00 |
    | peak multiplier | `1.15` on the distance **and** time terms | 06:00–09:00, 16:00–19:00 SAST |
    | floor | `flat_rate x 6 seats` | R60.00 |
    | cash quantum | `total_fare` lifted to the next `R0.50` | R77.10 → R77.50 |

    Three points where the implementation is deliberately narrower than the
    prose above:

    *   **`base_fare` is charged once per trip, not per passenger.** The
        `x 6 seats` term already prices the whole vehicle, so multiplying it
        by passenger count would charge for the same seats twice. Passenger
        scaling lives in `passenger_surcharge` instead.
    *   **`flat_rate x 6 seats` is a floor on the final total**, not an
        additive base term. It preserves the "special trip" rule — a lone
        passenger paying for all 6 seats — but only binds on very short hops
        (past roughly 1.5 km the formula clears it unaided).
    *   **Every rider-facing amount lands on a R0.50 quantum**, lifted up
        (never down), because kwella trips settle in cash and 1c/2c/5c coins
        are effectively out of circulation: R95.21 is a fare nobody at the
        kerb can hand over. The same gate applies to amounts the apps name —
        a rider's sweetened offer via `updateFare` and a driver's
        counter-offer via `sendBid` are both rejected off-quantum.

    **Nothing is added to the rider's side of the fare.** kwella's 10% is a
    driver-side commission, deducted from the fare the two parties agree on:
    a rider who offers R80 against a driver's R100 counter-offer pays R100,
    of which kwella takes R10 and the driver banks R90. It is the same rate
    the cancellation-debt "platform fee holiday" (§3B) waives, and it lives in
    one place — `PLATFORM_COMMISSION_RATE` in the shared fare engine, which
    the bidding engine, the ledger service and the mock orchestrator all
    import rather than restate.

    A useful consequence of the 50c quantum: 10% of any multiple of 50c is a
    whole number of cents, so the commission split is exact and needs no rule
    about who absorbs a half-cent.

    An earlier revision also added 10% to the rider's quote as a `booking_fee`
    on top of the subtotal, which charged the same commission twice — once to
    the rider up front, once to the driver on settlement.

*   **Duration is derived server-side** as `distance_km / 25 km/h`, never taken
    from the client — the engine refuses to trust a client-supplied
    `suggested_base_fare` for the same reason, and a client-supplied duration
    would reopen that hole. `KwellaFareEstimator` in `kwella_core` mirrors the
    Python engine term for term (including its straight-line distance measure)
    so the fare quoted in the rider app is the fare the server broadcasts.
    Their two test suites assert the same worked examples; if the engines drift
    apart, one of them goes red.
*   Drivers can instantly accept the base bid or return incremental counter-offer chips (+R5, +R10, +R15)[cite: 2].

### B. The Self-Balancing Cancellation & Ledger Engine
To protect driver fuel and time on a hybrid platform (supporting Cash & SA Digital Card Gateways), the following zero-tolerance cancellation logic is enforced[cite: 2]:
1.  **Distance Tiers:** Canceled when driver is >2km out = R0; 1km–2km out = R15 penalty; <1km out = R30 penalty[cite: 2].
2.  **Card Trip Cancellations:** The penalty is instantly captured from the pre-authorized gateway hold and deposited to the driver's virtual wallet[cite: 2].
3.  **Cash Trip Cancellations (The Protocol):**
    *   *Option A:* Rider pays driver cash physically on the spot; driver taps "Received Cash Penalty" to instantly restore rider standing[cite: 2].
    *   *Option B (Platform Fee Holiday):* If rider walks away, rider profile is locked with a negative balance[cite: 2]. kwella immediately waives its standard **10% platform commission fee** for that specific driver on their subsequent successful trips[cite: 2]. This 0% commission holiday continues until the sum of the waived fees exactly balances the outstanding debt owed to the driver (e.g., waiving R10 commission across 3 subsequent R100 trips to reconcile a R30 penalty)[cite: 2]. This money is then recouped from the passenger, they cannot use the app until they clear out their cancellation penalty flag by paying the amount they owe for cancelling the trip.

---

## 4. Database Schema Specification (DynamoDB Single-Table)
Table Name: `kwella-core-production`[cite: 1]
GSI1 Name: `GSI1`[cite: 2]

| Entity Type | Partition Key (PK) | Sort Key (SK) | GSI1_PK | GSI1_SK | Core Attributes Included |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Rider Profile** | `USR#<RiderId>` | `PROFILE` | *None* | *None* | `email`, `phone`, `cancellation_debt` |
| **Driver Profile** | `USR#<DriverId>` | `PROFILE` | `VEH#<CataSticker>` | `DRIVER` | `assigned_cata_sticker`, `fee_holiday_balance` |
| **Owner Profile** | `USR#<OwnerId>` | `PROFILE` | *None* | *None* | `fleet_revenue_map` |
| **Vehicle Asset** | `VEH#<CataSticker>` | `METADATA` | `USR#<OwnerId>` | `VEHICLE` | `license_disc`, `make`, `model`, `year` |

*Note: The unique CATA sticker number acts directly as the Partition Key for vehicle rows to enforce absolute database-level uniqueness[cite: 2].*

---

## 5. Directory Mapping Blueprint
Autonomous agents must strictly respect this workspace tree when generating infrastructure or application logic:

```text
.
├── dist/                           # Compiled production build outputs
├── docs/                           # Central platform documentation
│   ├── api/                        # OpenAPI / Swagger contract specifications
│   └── deployment/                 # Cloud deployment guides and architectural notes
├── kwella-apps/                    # Frontend Client Applications
│   ├── kwella_dashboard/           # Next.js / Node.js Admin Web Portal
│   │   ├── app/                    # Dashboard core views and routing layouts
│   │   ├── node_modules/           # Local web dependencies
│   │   └── public/                 # Static web assets and brand logos
│   ├── kwella_driver/              # Flutter Driver Mobile Client
│   │   ├── android/                # Native Android application configuration
│   │   ├── ios/                    # Native iOS application configuration
│   │   ├── lib/                    # Dart source (Riverpod providers & WebSocket architecture)
│   │   ├── linux/                  # Linux desktop platform wrapper
│   │   ├── macos/                  # macOS desktop platform wrapper
│   │   ├── test/                   # Flutter widget and unit test suites
│   │   ├── web/                    # Web-app mobile container configuration
│   │   └── windows/                # Windows desktop platform wrapper
│   └── kwella_rider/               # Flutter Rider Companion Client
│       ├── android/                # Native Android application configuration
│       ├── ios/                    # Native iOS application configuration
│       ├── lib/                    # Dart source (Riverpod providers & WebSocket architecture)
│       ├── linux/                  # Linux desktop platform wrapper
│       ├── macos/                  # macOS desktop platform wrapper
│       ├── test/                   # Flutter widget and unit test suites
│       ├── web/                    # Web-app mobile container configuration
│       └── windows/                # Windows desktop platform wrapper
├── kwella-backend/                 # Serverless Backend System (AWS Stack)
│   ├── build/                      # Shared dependency packaging workspace
│   │   └── python/                 # Python pip environment matrix for Lambda Layers
│   ├── dist/                       # Packaged Lambda source zip archives
│   ├── src/                        # Core Application Source Code
│   │   ├── lambdas/                # AWS Lambda Microservices (Auth, Ledger, Bidding Engine)
│   │   └── layers/                 # Custom shared Lambda dependency wheels (Pydantic, etc.)
│   ├── terraform/                  # Infrastructure-as-Code Configuration (af-south-1)
│   └── tests/                      # Pytest Suite (Deterministic backend unit and integration tests)
│       └── __pycache__/            # Cached Python bytecodes (git-ignored)
└── scripts/                        # Automated platform tooling, CI/CD utility hooks, and build binaries
```

---

## 6. Local Development & Setup

### A. Prerequisites
* **Python 3.12** (backend Lambda runtime) — a virtualenv is expected at `.venv/` in the repo root.
* **Node.js 20+** and a package manager (`npm`, `yarn`, `pnpm`, or `bun`) for the `kwella_dashboard` Next.js admin portal.
* **Flutter 3.x / Dart `^3.10.4`** for the `kwella_driver` and `kwella_rider` mobile clients (`flutter doctor` should report no blocking issues for at least one of Android/iOS toolchains).
* **Terraform `>= 1.6.0`** — only required if you intend to plan/apply infrastructure changes against AWS (`af-south-1`); not required for local backend testing.
* **AWS CLI v2** — only required for deploying/inspecting the live stack.

### B. Environment Variables
Kwella has no tracked `.env` file (per the Zero-Hardcoded-Secrets Mandate — see `CLAUDE.md`). Create your own `.env` at the repo root; it is already git-ignored. At minimum, the local scripts and smoke tests expect:

```bash
# AWS credentials (only needed for hitting a real/staging deployment)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=af-south-1

# Cognito (from Terraform outputs / AWS console)
COGNITO_USER_POOL_ID=
COGNITO_CLIENT_ID_MOBILE=
COGNITO_CLIENT_ID_DASHBOARD=

# API Gateway endpoints (Terraform outputs: http_api_endpoint / websocket endpoint)
KWELLA_API_URL=
KWELLA_WS_URL=ws://localhost:3001

# A valid bearer token accepted by the custom authorizer, for smoke_test.sh
TEST_MOCK_JWT=
```

Mobile client SDK keys (e.g. Google Maps) are injected at build time via git-ignored `local.properties`-style files per the platform's manifest placeholders — never hardcode them in tracked Dart/Kotlin/Swift source.

### C. Backend (Python / AWS Lambda)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r kwella-backend/tests/requirements-test.txt

# Run the full backend test suite
pytest kwella-backend/tests/

# Or a single suite, e.g. the bidding engine
pytest kwella-backend/tests/test_bidding_engine.py

# Compile-check a single handler without running it
python3 -m py_compile kwella-backend/src/lambdas/bidding_engine/handler.py
```

### D. Infrastructure (Terraform) — optional, only for deploying
```bash
cd kwella-backend/terraform
terraform init
terraform plan -var-file=production.tfvars
```

### E. Admin Dashboard (Next.js)
```bash
cd kwella-apps/kwella_dashboard
npm install
npm run dev   # http://localhost:3000
```

### F. Mobile Clients (Flutter)
```bash
# Driver app
cd kwella-apps/kwella_driver
flutter pub get
flutter run

# Rider app
cd kwella-apps/kwella_rider
flutter pub get
flutter run
```

Run `flutter analyze` from each of `kwella_core`, `kwella_driver`, and `kwella_rider` before committing Flutter changes.

### G. Local Marketplace Simulation
Use the root wrapper script to execute an end-to-end verification loop against the live backend gateway and local trip simulator.

Run:

```bash
./scripts/smoke_test.sh
```

This script performs a complete marketplace lifecycle validation, including:

* Rider Booking
* Driver Counter-Bid
* Match
* Pickup Geofence
* In-Transit Stream
* Payout Settlement
* Mutual 5-Star Rating

A clean run prints a fully green pass summary at the end, confirming the workflow has progressed through all seven phases successfully.

### H. Dual-Client Interactive E2E Matrix
To drive the rider and driver apps side-by-side against a booted iOS Simulator and Android Emulator simultaneously:

```bash
./scripts/run_local_e2e_matrix.sh
```

This targets the staging AWS stack (`KWELLA_ENV=staging`), since the phone/OTP `CUSTOM_AUTH` Lambda triggers are only wired up there — see `scripts/run_local_e2e_matrix.sh` for prerequisites (a booted simulator/emulator visible to `flutter devices`).
