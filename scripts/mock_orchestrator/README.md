# Kwella Mock Marketplace Orchestrator

A scriptable mock of the bidding-engine backend (`kwella-backend/src/lambdas/
bidding_engine/handler.py`) so you can manually test **one** Flutter app —
rider *or* driver — on an Android emulator against realistic multi-driver /
multi-rider background actors, without a second live app instance and
without an AWS backend.

It implements the same action/status JSON contract the real API Gateway
WebSocket route speaks (verified field-for-field against `handler.py` on
2026-09-06 — see `contract.py`'s module docstring for the one deliberate
hardening it adds over the real Lambda).

## Install

```bash
cd scripts/mock_orchestrator
python3 -m venv .venv && source .venv/bin/activate   # or reuse the repo's kwella-backend/.venv
pip install -r requirements.txt
```

## Run

```bash
# Testing the RIDER app — bots play multiple drivers:
python3 server.py --role rider --scenario scenarios/rider_mode.json

# Testing the DRIVER app — bots play multiple riders:
python3 server.py --role driver --scenario scenarios/driver_mode.json
```

Then:
- Open **http://localhost:8789** for the dashboard.
- Point the app under test's WebSocket at **`ws://10.0.2.2:8788`** (the
  Android emulator's alias for your host machine — see wiring below).

`--host`, `--app-port` (default 8788), and `--control-port` (default 8789)
are all overridable; run `python3 server.py --help`.

## Wiring each app to the mock

The two apps configure their WebSocket endpoint completely differently
today — this isn't something the mock server can paper over, so wire
whichever one you're testing:

### Rider app (`kwella_rider`)

A `local` environment was added to `kwella_core/lib/src/config/
environment.dart` alongside the existing `production`/`staging` split. Run:

```bash
flutter run --dart-define=KWELLA_ENV=local
```

This points `KwellaEnvironment.current.webSocketEndpointUrl` at
`ws://10.0.2.2:8788` (10.0.2.2 is the Android emulator's alias for the host
machine's `localhost`). On a physical device on the same LAN, override the
host: `--dart-define=KWELLA_ENV=local --dart-define=KWELLA_MOCK_HOST=<your-lan-ip>`.
If you changed `--app-port`, also pass `--dart-define=KWELLA_MOCK_PORT=<port>`.

The rider app still appends `?Authorization=<cognito-token>` to the
connection URL as usual — the mock server doesn't verify it, it's only
logged.

### Driver app (`kwella_driver`)

The driver app reads its endpoint from `kwella_driver/.env`
(`flutter_dotenv`), which is git-ignored — just edit it locally for the
session:

```
API_BASE_URL_WS=ws://10.0.2.2:8788
```

Revert it to the real `wss://...` endpoint when you're done. Note the
driver app sends **no** query params or identifying info at connect time —
the mock only learns the driver's real ID from the first message it sends
(typically `updateLocation`, fired automatically once you go online in the
app). **Go online in the driver app before triggering a rider request from
the dashboard**, or the mock has nowhere to route the offer yet — this
mirrors a real limitation of the actual backend too (see `handler.py`'s
`$connect` telemetry pre-seeding).

## The dashboard

Three columns:
- **Personas** — the bot actors on the "other side" of whichever app you're
  testing (drivers, if you're testing the rider app; riders, if you're
  testing the driver app). Each has a `behavior`:
  - `auto` — bids/selects/rates and drives its own scripted route
    automatically, with no input from you.
  - `manual` — waits for you to click a button (send bid, mark arrived,
    start trip, confirm arrival...).
  - `ignore` — never bids/selects. Combine with the app under test's own
    offer-timeout behavior to test the "ignored, then resurfaced" flow.
  - Add ad-hoc personas from the form at the bottom of the column.
- **Trips** — every in-flight trip, its bids, and a "Select <driver>"
  button per bid (acts as if the rider tapped that bid in the UI — see the
  concurrency scenario below).
- **Event log** — every action, push, and network-simulation event, live.

Network conditions (top of the Personas column) apply **only** to pushes
delivered to the real app under test — latency delays delivery, drop rate
silently drops a push, so you can test how the app behaves under a flaky
connection.

## Mapping the requested scenarios to what's actually implemented

- **Multiple idle drivers on the rider map (pre-trip):** the mock pushes a
  `nearbyDriverUpdate` action every ~3s per idle driver persona once a rider
  app connects. **The rider app currently has no code path that renders
  this** — `kwella_rider`'s map only ever tracks a single assigned driver's
  location (`RiderTripState.currentDriverLocation`, fed only by
  `liveDriverLocation` during an active trip). The push is real and
  observable in the dashboard log / a raw WS client, but you won't see
  markers in the app until a multi-driver map provider is added there — a
  Flutter app change, out of scope for this server.
- **Distinct bids from multiple drivers:** implemented — each driver
  persona with `behavior: auto` bids with its own `bidOffset`/`etaMinutes`
  after a randomized "thinking" delay.
- **Driver A accepts, Driver B ignores, Driver C's late accept errors with
  "Trip no longer available":** implemented via `selectBid`'s race guard
  (`contract.py::select_bid`) — once a trip is no longer `BROADCASTING`, any
  further `selectBid` (from the real rider app tapping a second bid card,
  or from the dashboard's "Select <driver>" button) gets rejected with
  `{"error": "TripNoLongerAvailable", "detail": "Trip no longer available"}`.
  Set persona B's behavior to `ignore` so it never bids; tap/select persona
  A first, then attempt to select persona C to see the error.
- **Scripted driver movement, arrival, start, completion:** implemented —
  once a driver persona (real or bot) is selected, an `auto` persona drives
  itself through pickup → `driverArrived` → `startTrip` → dropoff →
  `confirmArrival` → `submitRating` automatically (`bots.py`). A `manual`
  persona instead waits for the dashboard's per-step buttons.
- **Multiple concurrent ride requests at a driver:** implemented — trigger
  the dashboard's "Request Trip" form for two or more rider personas in
  quick succession against the same connected real driver app. Note
  `kwella_driver`'s `KwellaTelemetryController` currently tracks only one
  `activeOffer` at a time (the second `rideOfferAvailable` push overwrites
  the first in app state) — a real, observable app-side limitation worth
  testing against, not a mock deficiency.
- **Ignore → timeout → resurface:** implemented generically for any offer
  target (real app or persona) via `offerTimeoutSeconds`/
  `resurfaceDelaySeconds` in the scenario file (defaults 15s/20s, matching
  the real backend's `_RIDE_OFFER_TTL_SECONDS`).
- **Decline/cancel → never reappears:** implemented — the dashboard's
  "Decline offer" button (or `declineOffer` control command) permanently
  blocklists that driver for that trip; the resurface watchdog checks the
  blocklist before ever re-pushing.

## Scenario file format

See `scenarios/rider_mode.json` and `scenarios/driver_mode.json`. Top-level
keys: `offerTimeoutSeconds`, `resurfaceDelaySeconds`,
`riderAutoSelectWindowSeconds` (driver-mode: how long an auto rider persona
waits to collect bids before selecting the cheapest), `driveIntervalSeconds`
/ `driveSteps` (rider-mode: pacing of a driver persona's scripted route),
and `personas` (array of `{id, name, latitude, longitude, behavior,
bidOffset, etaMinutes, vehicleMake, vehicleModel, vehicleColor,
licensePlate, rating}` — driver-only fields are ignored for rider personas).

## Known constraints

- One real app connection at a time (by design — this is for
  single-app-isolation testing, not multi-app orchestration).
- The mock doesn't touch DynamoDB/AWS at all; it's pure in-memory state that
  resets when the process restarts.
- The dashboard's "Select `<driver>`" trip button and the driver-mode auto
  rider persona both call `selectBid` on the trip's behalf — in rider-mode
  the real rider app is expected to be the one calling `selectBid` normally
  (by tapping a bid in its own UI); the dashboard button exists mainly as
  the deterministic race-condition injector described above.
