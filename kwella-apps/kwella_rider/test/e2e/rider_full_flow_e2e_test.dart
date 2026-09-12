// ─────────────────────────────────────────────────────────────────────────────
// Rider full-flow E2E test.
//
// A plain `flutter_test` spec (NOT the device-bound `integration_test`
// package — no IntegrationTestWidgetsFlutterBinding) that pumps the real
// KwellaRiderApp screens/routes end-to-end: phone auth -> OTP -> booking ->
// payment method -> fare offer -> requestTrip -> live bidding -> accept ->
// trip lifecycle -> completion -> rating. Runnable via plain
// `flutter test` (this file, or the whole suite) with no emulator/device.
//
// Deliberately located under test/e2e/, NOT integration_test/, despite that
// being this task's original brief. Verified against this repo's installed
// Flutter SDK (3.44.8, packages/flutter_tools/lib/src/commands/test.dart,
// `_shouldRunAsIntegrationTests`): `flutter test` unconditionally treats ANY
// test file whose path lives under a directory literally named
// `integration_test` as a device-bound integration test — regardless of
// whether that file actually imports `package:integration_test` or uses
// `IntegrationTestWidgetsFlutterBinding` — and then requires both a
// connected device and that package as a dependency. Confirmed empirically
// too: running this exact file from `integration_test/` via
// `-d flutter-tester` (the one device flutter_tools will accept without a
// real emulator) switches the test to `LiveTestWidgetsFlutterBinding`
// instead of the normal `AutomatedTestWidgetsFlutterBinding`, which does NOT
// install the default mock plugin channel handlers the widget-test binding
// provides — causing MissingPluginException crashes (geolocator, Google Maps
// platform views) that don't occur, and aren't related to, anything this
// suite is testing. Placing the file under test/e2e/ keeps it a plain,
// headless, no-device `flutter_test` spec exactly as specified, runnable via
// `flutter test` (whole suite) or `flutter test test/e2e`.
//
// All outbound WebSocket traffic is captured (and inbound frames injected)
// through a single [FakeWebSocketGateway] shared with
// test/kwella_rider_controller_test.dart (see test/support/fake_websocket_gateway.dart),
// wired into one [KwellaRiderController] instance that every screen resolves
// to via a `kwellaRiderControllerProvider` override — so the whole flow
// exercises one real, shared piece of trip state exactly as the app does at
// runtime.
//
// Known, pre-existing, out-of-scope gaps this suite documents rather than
// works around or fixes:
//   - Declining a bid and cancelling an active search (both now covered
//     below via ActiveSearchScreen) are client-local only — no backend
//     route exists for either, by deliberate choice (see the plan's
//     Context section): lower risk than inventing more backend surface.
//   - `handleIncomingWebSocketEvent`'s `driverBidReceived` branch only reads
//     a wrapped `bidMetrics` list field, not the flat
//     {action, tripId, driverId, amount, driverName, ...} shape the backend's
//     bidding_engine handler.py actually sends over the wire, and
//     DriverBidCard reads `bid['fare'] ?? bid['bidAmount']`, not `amount`.
//     This predates the prior task's gateway-wiring work (confirmed via git
//     diff), so it is left as-is here; the bid frame below is built in the
//     wrapped/renamed shape the controller and card actually read today,
//     per this task's instruction to adapt to what the code does rather than
//     the wire contract it should eventually match.
//   - `handleIncomingWebSocketEvent` has no branch for `tripStarted` at all
//     (only `geofenceTrigger` for "arrived" and `liveDriverLocation`/
//     `WalletSettled`), so this suite doesn't push or assert on it.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:kwella_rider/features/auth/presentation/screens/phone_entry_screen.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/active_search_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/payment_method_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rate_driver_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/ride_fare_offer_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/ride_tracking_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

import '../features/auth/support/mock_cognito.dart';
import '../support/fake_websocket_gateway.dart';

/// Pinput captures keystrokes through a single hidden EditableText, not the
/// Key('otp_pinput') widget itself — enterText must target that descendant.
/// (Same finder as otp_verification_screen_test.dart.)
final Finder _pinInputField = find.descendant(
  of: find.byKey(const Key('otp_pinput')),
  matching: find.byType(EditableText),
);

/// Advances past a route's page-transition animation. Not pumpAndSettle:
/// several screens on this trip's stack have infinite/pulsing animations
/// (the "Finding drivers…" spinner, DriverBidCard's pulsing accept button)
/// that never let pumpAndSettle converge. 600ms comfortably covers both a
/// plain push's default ~300ms transition and pushNamedAndRemoveUntil's
/// slightly longer compound push-and-remove settle (empirically ~500-600ms).
Future<void> _pumpPastTransition(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeWebSocketGateway fakeGateway;
  late KwellaRiderController controller;
  late ProviderContainer container;

  const String riderPhoneNumber = '+27717662280';
  const String riderId = 'rider-e2e-1';
  const String accessToken = 'token-e2e-1';
  const double pickupLat = -33.9249;
  const double pickupLng = 18.4241;
  const double dropoffLat = -33.9581;
  const double dropoffLng = 18.6961;
  const String tripId = 'trip-e2e-1';
  const String driverId = 'driver-e2e-1';

  setUp(() {
    fakeGateway = FakeWebSocketGateway();
    controller = KwellaRiderController(gateway: fakeGateway);
    container = ProviderContainer(
      overrides: [
        // Real KwellaAuthNotifier, wired to a mocked Cognito Dio interceptor
        // (same pattern as phone_entry_screen_test.dart /
        // otp_verification_screen_test.dart) so the auth screens exercise
        // their real request/response handling with no network calls.
        kwellaAuthNotifierProvider.overrideWith(
          (ref) => buildMockAuthNotifier(
            MockCognitoInterceptor(MockOtpVerifyMode.correct),
          ),
        ),
        // Every booking/tracking/rating screen that reads this provider
        // (instead of taking an explicit `controller:` constructor param)
        // resolves to the SAME controller/fake-gateway instance used
        // throughout this test, so trip state is one consistent stream
        // regardless of which screen is currently on top of the Navigator
        // stack.
        kwellaRiderControllerProvider.overrideWith((ref) => controller),
      ],
    );
  });

  tearDown(() async {
    controller.dispose();
    await fakeGateway.disconnect();
    container.dispose();
  });

  /// Builds the same named-route map as `main.dart`'s KwellaRiderApp,
  /// trimmed to just the routes this flow visits (welcome, destination, and
  /// profile are unrelated to this trip lifecycle). RiderBookingScreen is
  /// given the shared `controller` explicitly — this is a deliberate,
  /// documented deviation from main.dart's plain `(_) => const
  /// RiderBookingScreen()`: with no controller injected, its initState calls
  /// `_connectRiderWebSocket`, which reads a real, un-mocked `TokenVault()`
  /// (a plain FlutterSecureStorage-backed class with no DI seam and no
  /// Riverpod provider to override) and would hit a real platform channel in
  /// this widget-test environment. Injecting the controller explicitly skips
  /// that call entirely; this test instead calls `controller.connect(...)`
  /// itself against the fake gateway below, which is the deterministic,
  /// no-real-I/O equivalent of what that production code path would do for
  /// an authenticated rider. Every other screen below is reached via its
  /// plain default constructor and resolves the same controller purely
  /// through the `kwellaRiderControllerProvider` override.
  Widget buildApp() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: '/auth/phone',
        routes: {
          '/auth/phone': (_) => const PhoneEntryScreen(),
          '/auth/otp': (_) => const OtpVerificationScreen(),
          // placesService/directionsService: both real service classes read
          // `dotenv.env[...]` for their API key when not given one
          // explicitly, and `dotenv.load()` is never called in this test
          // (no main() run) — DotEnv.env throws NotInitializedError
          // unconditionally when uninitialized, regardless of which key is
          // looked up. Supplying an explicit apiKey short-circuits that read
          // entirely; neither service's network methods are ever invoked in
          // this flow (pickup/dropoff/route are driven directly through the
          // controller), so a real network key isn't needed either.
          '/rider/home': (_) => RiderBookingScreen(
                controller: controller,
                placesService: PlacesAutocompleteService(apiKey: 'test-key'),
              ),
          '/rider/payment-method': (_) => const PaymentMethodScreen(),
          '/rider/fare-offer': (_) => RideFareOfferScreen(
                directionsService: DirectionsService(apiKey: 'test-key'),
              ),
          '/rider/tracking': (_) => const RideTrackingScreen(),
          '/rider/rating': (_) => const RateDriverScreen(),
        },
      ),
    );
  }

  testWidgets(
    'rider trip lifecycle: auth -> booking -> payment -> fare offer -> '
    'bidding -> accept -> tracking -> completion -> rating',
    (WidgetTester tester) async {
      // ── 1. AUTH ──────────────────────────────────────────────────────
      // Phone entry -> OTP -> land on /rider/home (RiderBookingScreen).
      await tester.pumpWidget(buildApp());

      await tester.enterText(
        find.byKey(const Key('phone_input')),
        '0717662280',
      );
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('send_otp_button')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('send_otp_button')));
      // Avoid pumpAndSettle across this transition: the destination
      // (OtpVerificationScreen) starts a 60-second periodic countdown Timer
      // in initState, which never lets "no pending frames" converge —
      // exactly the caveat documented in otp_verification_screen_test.dart.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.byKey(const Key('otp_pinput')), findsOneWidget);
      expect(
        container.read(kwellaAuthNotifierProvider).pendingPhoneNumber,
        riderPhoneNumber,
      );

      await tester.enterText(_pinInputField, '123456');
      // Pinput's onCompleted fires verification as soon as the 6th digit
      // lands (no separate tap needed) — same rationale as
      // otp_verification_screen_test.dart for avoiding pumpAndSettle here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(
        container.read(kwellaAuthNotifierProvider).status,
        KwellaAuthStatus.authenticated,
      );
      expect(find.byKey(const Key('search_bar')), findsOneWidget);

      // ── 2. Connect the rider's real-time WebSocket gateway ─────────────
      // Deterministic stand-in for the production `_connectRiderWebSocket`
      // path that RiderBookingScreen's initState skips when a controller is
      // injected explicitly (see buildApp's doc comment above).
      await controller.connect(riderId: riderId, accessToken: accessToken);
      expect(fakeGateway.connected, isTrue);
      expect(fakeGateway.lastAccessToken, equals(accessToken));

      // ── 3. Set pickup/dropoff, continue -> payment method -> fare offer ─
      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pump();

      expect(find.byKey(const Key('from_input')), findsOneWidget);
      expect(find.byKey(const Key('continue_button')), findsOneWidget);

      // Set pickup/dropoff (with coordinates) directly on the controller
      // rather than through Places/GPS-backed widget interaction — the
      // point of this suite is the WebSocket contract, not the map/places
      // picker widgets (already covered by their own tests), and this
      // mirrors how DestinationEditorPanel's `_selectSuggestion` ultimately
      // updates the very same controller methods.
      controller.updatePickupLocation(
        '23 West Drive, Khayelitsha, Cape Town',
        lat: pickupLat,
        lng: pickupLng,
      );
      controller.updateDropoffLocation(
        'Zevenwacht Mall, Van Riebeeck Road, Kuils River',
        lat: dropoffLat,
        lng: dropoffLng,
      );
      await tester.pump();

      final ElevatedButton continueButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('continue_button')),
      );
      expect(continueButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('continue_button')));
      await tester.pump();
      await tester.pump();

      // Now on /rider/payment-method (PaymentMethodScreen) — this route is
      // only reachable at all thanks to the `onContinue` seam added to
      // DestinationEditorPanel/RiderBookingScreen as part of this task (see
      // report: the button previously navigated straight to fare-offer with
      // no way to reach payment-method from a fresh idle rider).
      expect(find.byKey(const Key('payment_continue_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('payment_continue_button')));
      await tester.pump();
      await tester.pump();

      // Now on /rider/fare-offer (RideFareOfferScreen).
      expect(find.byKey(const Key('find_drivers_button')), findsOneWidget);
      expect(controller.state.paymentMethod, equals('CASH'));

      // ── 4. Request the trip ─────────────────────────────────────────────
      await tester.ensureVisible(find.byKey(const Key('find_drivers_button')));
      await tester.tap(find.byKey(const Key('find_drivers_button')));
      // Not pumpAndSettle: the destination (ActiveSearchScreen) has an
      // indeterminate "Finding drivers…" CircularProgressIndicator, which
      // never settles.
      await tester.pump();
      await tester.pump();

      final Map<String, dynamic> requestTripFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'requestTrip');
      expect(requestTripFrame['riderId'], equals(riderId));
      expect(requestTripFrame['pickup_latitude'], equals(pickupLat));
      expect(requestTripFrame['pickup_longitude'], equals(pickupLng));
      expect(requestTripFrame['dropoff_latitude'], equals(dropoffLat));
      expect(requestTripFrame['dropoff_longitude'], equals(dropoffLng));
      expect(requestTripFrame['passenger_count'], equals(1));
      // The rider's own offer now travels as `suggested_base_fare`. No route
      // resolves under `flutter test` (the real DirectionsService's HTTP call
      // is blocked), so RideFareOfferScreen stays on its R60 fallback
      // recommendation and offers exactly that.
      expect(requestTripFrame['suggested_base_fare'], equals(60.0));
      expect(controller.state.status, equals(RiderTripStatus.searching));
      expect(controller.state.offeredFare, equals(60.0));

      // `_findDrivers` now pushes a dedicated ActiveSearchScreen (replacing
      // the old pop-back-to-booking-screen behavior).
      await _pumpPastTransition(tester);
      expect(find.byType(ActiveSearchScreen), findsOneWidget);
      expect(find.byKey(const Key('active_search_offer_value')), findsOneWidget);
      // Rendered from the rider's own offer, BEFORE the TripBroadcast frame
      // below — this used to read "R0".
      expect(
        tester
            .widget<Text>(find.byKey(const Key('active_search_offer_value')))
            .data,
        equals('R60'),
      );

      // ── 4b. TripBroadcast sets the real server fare, then raise it ──────
      fakeGateway.simulateIncomingFrame(jsonEncode({
        'status': 'TripBroadcast',
        'tripId': tripId,
        'matched_drivers': 2,
        'passenger_count': 1,
        'calculated_fare': '60',
      }));
      await tester.pump();
      await tester.pump();

      expect(controller.state.tripId, equals(tripId));
      expect(controller.state.offeredFare, equals(60.0));

      await tester.tap(find.byKey(const Key('active_search_increase_fare_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('raise_fare_button')));
      await tester.pump();

      final Map<String, dynamic> updateFareFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'updateFare');
      expect(updateFareFrame['tripId'], equals(tripId));
      expect(updateFareFrame['riderId'], equals(riderId));
      expect(updateFareFrame['new_fare'], equals(65.0));
      expect(controller.state.offeredFare, equals(65.0));

      fakeGateway.simulateIncomingFrame(jsonEncode({
        'status': 'FareUpdated',
        'tripId': tripId,
        'base_fare': '65',
      }));
      await tester.pump();
      await tester.pump();
      expect(controller.state.offeredFare, equals(65.0));

      // ── 4c. nearbyDriverUpdate populates idle-driver markers on the map ──
      fakeGateway.simulateIncomingFrame(jsonEncode({
        'action': 'nearbyDriverUpdate',
        'driverId': 'driver-idle-1',
        'latitude': -33.93,
        'longitude': 18.45,
        'status': 'idle',
      }));
      await tester.pump();
      await tester.pump();

      expect(controller.state.nearbyDrivers['driver-idle-1'], isNotNull);
      // Scoped to ActiveSearchScreen's own map: earlier routes
      // (RideFareOfferScreen, RiderBookingScreen, ...) stay mounted offstage
      // (MaterialPageRoute's default maintainState) and each has its own
      // KwellaMapView carrying the same non-unique `kwella_map_view` key.
      final GoogleMap activeSearchMap = tester.widget<GoogleMap>(
        find.descendant(
          of: find.byType(ActiveSearchScreen),
          matching: find.byKey(const Key('kwella_map_view')),
        ),
      );
      expect(
        activeSearchMap.markers
            .any((m) => m.markerId == const MarkerId('nearby_driver-idle-1')),
        isTrue,
      );

      // ── 5. Bidding: push a driverBidReceived frame ──────────────────────
      Map<String, dynamic> bidFrame() => {
            'action': 'driverBidReceived',
            'tripId': tripId,
            'bidMetrics': [
              {
                'driverId': driverId,
                'driverName': 'Sipho M.',
                'rating': 4.8,
                'vehicleColor': 'White',
                'vehicleModel': 'Toyota Quantum',
                'licensePlate': 'CA 123-456',
                'cataSticker': 'M02356',
                'bidAmount': 55,
                'etaMinutes': 6,
              },
            ],
          };

      // RiderBookingScreen (and every other earlier route) stays mounted
      // offstage (MaterialPageRoute's default maintainState) and reacts to
      // the same shared controller/state — its own bid carousel renders a
      // second DriverBidCard the instant status flips to biddingOpen, so
      // every DriverBidCard-related finder below is scoped to
      // ActiveSearchScreen's own subtree to disambiguate.
      Finder onActiveSearchScreen(Finder matching) => find.descendant(
            of: find.byType(ActiveSearchScreen),
            matching: matching,
          );

      fakeGateway.simulateIncomingFrame(jsonEncode(bidFrame()));
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, equals(RiderTripStatus.biddingOpen));
      expect(onActiveSearchScreen(find.byKey(const Key('driver_name'))),
          findsOneWidget);
      expect(onActiveSearchScreen(find.text('Sipho M.')), findsOneWidget);
      expect(onActiveSearchScreen(find.byKey(const Key('accept_button'))),
          findsOneWidget);
      expect(onActiveSearchScreen(find.text('6 min away')), findsOneWidget);

      // ── 5b. Decline the bid — client-local only, no wire call — then a
      // fresh bid arrives and the sheet shows it again ────────────────────
      final Finder declineButton =
          onActiveSearchScreen(find.byKey(const Key('decline_button')));
      await tester.ensureVisible(declineButton);
      await tester.tap(declineButton);
      await tester.pump();

      expect(controller.state.bidMetrics, isEmpty);
      expect(find.byKey(const Key('active_search_offer_value')), findsOneWidget);
      expect(
        fakeGateway.sentPayloads.where((m) => m['action'] == 'declineBid'),
        isEmpty,
      );

      fakeGateway.simulateIncomingFrame(jsonEncode(bidFrame()));
      await tester.pump();
      await tester.pump();
      expect(onActiveSearchScreen(find.byKey(const Key('accept_button'))),
          findsOneWidget);

      // ── 6. Accept the bid ────────────────────────────────────────────────
      // A coordinate-based tap on `accept_button` (DriverBidCard's
      // `_PulseButton`) intermittently misses in this harness: its infinite
      // pulse AnimationController rebuilds the button via AnimatedBuilder on
      // every tick, and WidgetController.tap's precomputed getCenter()
      // offset can land a frame behind that rebuild. Reading the real
      // ElevatedButton's onPressed and invoking it directly exercises the
      // exact same DriverBidCard.onAccept -> controller.selectBid wiring a
      // tap would, without depending on that per-frame geometry timing.
      final Finder activeSearchAcceptButton =
          onActiveSearchScreen(find.byKey(const Key('accept_button')));
      await tester.ensureVisible(activeSearchAcceptButton);
      final ElevatedButton acceptButton = tester.widget<ElevatedButton>(
        find.descendant(
          of: activeSearchAcceptButton,
          matching: find.byType(ElevatedButton),
        ),
      );
      acceptButton.onPressed!();
      await tester.pump();

      final Map<String, dynamic> selectBidFrame =
          fakeGateway.sentPayloads.singleWhere((m) => m['action'] == 'selectBid');
      expect(selectBidFrame['tripId'], equals(tripId));
      expect(selectBidFrame['driverId'], equals(driverId));
      expect(controller.state.status, equals(RiderTripStatus.accepted));

      // ActiveSearchScreen auto-navigates to /rider/tracking via a
      // post-frame callback once accepted.
      await _pumpPastTransition(tester);
      expect(find.byKey(const Key('cancel_ride_button')), findsOneWidget);

      fakeGateway.simulateIncomingFrame(jsonEncode({
        'action': 'tripMatchConfirmed',
        'tripId': tripId,
        'driverId': driverId,
        'riderId': riderId,
        'driverName': 'Sipho M.',
        'rating': 4.8,
        'vehicleMake': 'Toyota',
        'vehicleModel': 'Quantum',
        'vehicleColor': 'White',
        'licensePlate': 'CA 123-456',
        'cataSticker': 'M02356',
      }));
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, equals(RiderTripStatus.accepted));
      expect(controller.state.driverName, equals('Sipho M.'));
      expect(controller.state.driverRating, equals('4.8'));
      expect(controller.state.vehicleDescription, equals('White Quantum'));
      expect(controller.state.licensePlate, equals('CA 123-456'));

      // ── 7. Trip lifecycle: already on tracking, push live updates ──────

      const List<List<double>> driverPath = [
        [-33.94, 18.50],
        [-33.945, 18.55],
        [-33.955, 18.60],
      ];
      for (final coords in driverPath) {
        fakeGateway.simulateIncomingFrame(jsonEncode({
          'action': 'liveDriverLocation',
          'tripId': tripId,
          'driverId': driverId,
          'latitude': coords[0],
          'longitude': coords[1],
        }));
        await tester.pump();
        await tester.pump();

        expect(controller.state.currentDriverLocation?.latitude,
            equals(coords[0]));
        expect(controller.state.currentDriverLocation?.longitude,
            equals(coords[1]));
      }

      // `handleIncomingWebSocketEvent` reacts to `geofenceTrigger` (not
      // `driverArrived`) for the "arrived" transition — confirmed by reading
      // the controller rather than assuming the backend contract's naming.
      fakeGateway.simulateIncomingFrame(jsonEncode({
        'action': 'geofenceTrigger',
        'tripId': tripId,
        'geofence_status': 'ARRIVED',
      }));
      await tester.pump();
      await tester.pump();
      expect(controller.state.status, equals(RiderTripStatus.arrived));

      // ── 8. Completion -> navigates to rating ────────────────────────────
      fakeGateway.simulateIncomingFrame(jsonEncode({
        'status': 'WalletSettled',
        'tripId': tripId,
        'net_earnings': 45.5,
        'currency': 'ZAR',
        'updated_daily_total': 120.0,
      }));
      await tester.pump();
      await tester.pump();
      expect(controller.state.status, equals(RiderTripStatus.completed));

      // RideTrackingScreen's ref.listen navigates to /rider/rating via a
      // post-frame callback — an extra pump lets that callback fire.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('submit_rating_button')), findsOneWidget);

      // ── 9. Rating ────────────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('star_5')));
      await tester.pump();

      final ElevatedButton submitRatingButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_rating_button')),
      );
      expect(submitRatingButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('submit_rating_button')));
      await tester.pump();
      await tester.pump();

      final Map<String, dynamic> submitRatingFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'submitRating');
      expect(submitRatingFrame['tripId'], equals(tripId));
      expect(submitRatingFrame['rating'], equals(5));
      expect(submitRatingFrame['target'], equals('DRIVER'));
    },
  );

  testWidgets(
    'cancelling an active search from ActiveSearchScreen resets state and '
    'lands back on /rider/home',
    (WidgetTester tester) async {
      // Abbreviated setup — auth -> booking -> payment -> fare offer -> Find
      // Drivers — mirrors steps 1-4 of the main lifecycle test above without
      // re-asserting every intermediate step, since those are already
      // covered there; this scenario only needs to reach ActiveSearchScreen.
      await tester.pumpWidget(buildApp());

      await tester.enterText(
        find.byKey(const Key('phone_input')),
        '0717662280',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send_otp_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      await tester.enterText(_pinInputField, '123456');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      await controller.connect(riderId: riderId, accessToken: accessToken);

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pump();

      controller.updatePickupLocation(
        '23 West Drive, Khayelitsha, Cape Town',
        lat: pickupLat,
        lng: pickupLng,
      );
      controller.updateDropoffLocation(
        'Zevenwacht Mall, Van Riebeeck Road, Kuils River',
        lat: dropoffLat,
        lng: dropoffLng,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('continue_button')));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('payment_continue_button')));
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('find_drivers_button')));
      await tester.tap(find.byKey(const Key('find_drivers_button')));
      await _pumpPastTransition(tester);

      expect(find.byType(ActiveSearchScreen), findsOneWidget);

      fakeGateway.simulateIncomingFrame(jsonEncode({
        'action': 'driverBidReceived',
        'tripId': tripId,
        'bidMetrics': [
          {'driverId': driverId, 'driverName': 'Sipho M.', 'bidAmount': 55},
        ],
      }));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('cancel_request_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel_request_button')));
      await _pumpPastTransition(tester);

      expect(controller.state.status, equals(RiderTripStatus.idle));
      expect(controller.state.bidMetrics, isEmpty);
      // pushNamedAndRemoveUntil('/rider/home', ...) clears the whole stack
      // back to RiderBookingScreen.
      expect(find.byKey(const Key('search_bar')), findsOneWidget);
      expect(find.byType(ActiveSearchScreen), findsNothing);
    },
  );
}
