# Kwella Platform - Master Context & Architecture Blueprint

Welcome to the core repository for Kwella. This document serves as the absolute source of truth and state-of-mind reference for all autonomous engineering agents, IDE code interpreters, and developers operating within this workspace. 

## 1. Executive Vision & Target Market
Kwella is a premium, on-demand, point-to-point e-hailing platform built strictly for township commuter ecosystems in South Africa (initially launching out of the Cape Flats, grounded at Philippi Village). 
*   **Target Vehicle Scope:** Exclusively 7-seater amaphela (e.g., Suzuki Ertiga, Toyota Avanza). Minibus taxis (vans) and split-fare shared rides are strictly out of scope for the MVP to prevent transit association friction.
*   **Core Trust Anchor:** Mandatory physical auditing at the Philippi Village office[cite: 2]. Vehicles must be linked to a valid license disc, driver PrDP, and a unique, physical **CATA (Cape Amalgamated Taxi Association) sticker number** visible on the bodywork[cite: 1, 2].

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
*   Drivers can instantly accept the base bid or return incremental counter-offer chips (+R5, +R10, +R15)[cite: 2].

### B. The Self-Balancing Cancellation & Ledger Engine
To protect driver fuel and time on a hybrid platform (supporting Cash & SA Digital Card Gateways), the following zero-tolerance cancellation logic is enforced[cite: 2]:
1.  **Distance Tiers:** Canceled when driver is >2km out = R0; 1km–2km out = R15 penalty; <1km out = R30 penalty[cite: 2].
2.  **Card Trip Cancellations:** The penalty is instantly captured from the pre-authorized gateway hold and deposited to the driver's virtual wallet[cite: 2].
3.  **Cash Trip Cancellations (The Protocol):**
    *   *Option A:* Rider pays driver cash physically on the spot; driver taps "Received Cash Penalty" to instantly restore rider standing[cite: 2].
    *   *Option B (Platform Fee Holiday):* If rider walks away, rider profile is locked with a negative balance[cite: 2]. Kwella immediately waives its standard **10% platform commission fee** for that specific driver on their subsequent successful trips[cite: 2]. This 0% commission holiday continues until the sum of the waived fees exactly balances the outstanding debt owed to the driver (e.g., waiving R10 commission across 3 subsequent R100 trips to reconcile a R30 penalty)[cite: 2].

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