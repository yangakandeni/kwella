// Driver full-flow E2E suite.
//
// This is a PLAIN `flutter_test` file — not the device-bound `integration_test`
// package, and it never touches `IntegrationTestWidgetsFlutterBinding`.
//
// Deviation from the original plan's exact path: this suite was originally
// meant to live at the top-level `integration_test/driver_full_flow_e2e_test.dart`,
// runnable via `flutter test integration_test` with no device. In practice,
// the Flutter SDK in this environment (3.44.8 stable) special-cases *any*
// top-level directory literally named `integration_test` — `flutter test
// integration_test` unconditionally refuses to run without `-d <device>`,
// and running with `-d` then hard-requires a real dependency on
// `package:integration_test` (which this plain-flutter_test file
// deliberately does not use), regardless of the file's own content. That
// contradicts the "plain flutter_test, no device" requirement outright, so
// this suite instead lives at `test/integration_test/`, nested under the
// ordinary `test/` tree, which sidesteps that special-casing entirely. It
// runs headlessly with `flutter test test/integration_test` (no device), and
// is also picked up automatically by a plain `flutter test`.
//
// It exercises the driver app's full lifecycle end-to-end against fake
// WebSocket/location services, with the WS wire contract (the exact JSON
// shape of every outgoing frame) as the primary assertion surface:
//   1. Onboarding (document uploads) -> profile setup -> back to marketplace.
//   2. Going online, receiving a `rideOfferAvailable` offer, and submitting a
//      bid — asserting the `sendBid` frame carries `riderId`/`tripId`/`amount`
//      correctly (the regression this suite exists to guard).
//   3. A ride offer's 15s countdown auto-expiring when left unanswered.
//   4. The full trip lifecycle: `bidSelected` -> `driverArrived` ->
//      `startTrip` -> `updateLocation` (x N) -> `confirmArrival` ->
//      `WalletSettled` -> post-trip screen.
//   5. Post-trip star rating submission (`submitRating`, target `RIDER`).
//
// Test-time caveats (see inline comments at each point of use):
//   - `tester.pumpAndSettle()` cannot be used once the driver goes "online"
//     or the geofence overlay is showing: the bidding-connecting layout's
//     `CircularProgressIndicator` and the geofence overlay's pulsing
//     indicator both run indeterminate/never-ending animations, which would
//     make `pumpAndSettle()` hang forever waiting for animations to finish.
//     Explicit `tester.pump(duration)` calls are used instead from that point
//     on.
//   - `testWidgets` runs inside flutter_test's fake-async zone, so every
//     `Timer`/`Timer.periodic` created during the test — including the
//     ride-offer countdown and SnackBar/EarningsToast auto-dismiss timers —
//     is bound to that zone's fake clock, not real wall-clock time.
//     `tester.pump(duration)` is what advances it and fires due timers
//     synchronously; `tester.runAsync` escapes to a *different*, real-time
//     zone and does NOT advance that fake clock, so it must not be used to
//     make one of these timers fire (see the countdown test's comment for
//     what that looked like when it was tried).
//   - `DriverProfileSetupScreen._submit()` constructs its own `Dio` instance
//     internally with no dependency-injection seam, and hits real
//     `identity/upsert` / `identity/vehicle` HTTP endpoints. This project has
//     no HTTP-mocking dependency installed, and the empty-form validation
//     path is already covered by `driver_profile_setup_screen_test.dart`, so
//     — per the plan's guidance to call a screen's underlying
//     callback/effect directly when a UI interaction is awkward to simulate,
//     rather than block on it — this suite simulates a successful
//     submission's only externally-visible effect (`Navigator.pop`) directly
//     instead of tapping the real submit button and hitting live network IO.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kwella_core/kwella_core.dart';

import 'package:kwella_driver/features/bidding/presentation/screens/bidding_marketplace_screen.dart';
import 'package:kwella_driver/features/bidding/presentation/screens/driver_onboarding_screen.dart';
import 'package:kwella_driver/features/bidding/presentation/screens/driver_profile_setup_screen.dart';
import 'package:kwella_driver/features/bidding/presentation/screens/post_trip_screen.dart';
import 'package:kwella_driver/features/bidding/presentation/screens/trip_navigation_screen.dart';
import 'package:kwella_driver/features/bidding/providers/bidding_provider.dart';
import 'package:kwella_driver/features/bidding/services/driver_document_upload_service.dart';
import 'package:kwella_driver/features/location/presentation/controllers/kwella_telemetry_controller.dart';

import '../support/fake_kwella_location_service.dart';
import '../support/fake_kwella_websocket_service.dart';
import '../support/pre_authenticated_session.dart';

const _driverId = 'USR#drv-12345';

/// Builds the app shell shared by every stage of this suite: one
/// [ProviderScope] with [telemetryControllerProvider] and [biddingProvider]
/// both wired to the *same* fake WebSocket service — exactly as production
/// wires both providers to the same `KwellaWebSocketService.instance`
/// singleton — plus the same named-route table as `lib/main.dart`.
Widget _buildDriverApp({
  required FakeKwellaWebSocketService wsService,
  required FakeKwellaLocationService locationService,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return ProviderScope(
    overrides: [
      telemetryControllerProvider.overrideWith(
        (ref) => KwellaTelemetryController(
          locationService: locationService,
          wsService: wsService,
        ),
      ),
      biddingProvider.overrideWith(
        (ref) => BiddingNotifier(wsService: wsService),
      ),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: const BiddingMarketplaceScreen(),
      routes: {
        '/driver/onboarding': (_) => const DriverOnboardingScreen(),
        '/driver/profile-setup': (_) => const DriverProfileSetupScreen(),
        '/driver/navigation': (_) => const TripNavigationScreen(),
        '/driver/post-trip': (_) => const PostTripScreen(),
      },
    ),
  );
}

/// The `rideOfferAvailable` frame as `kwella-backend/src/lambdas/
/// bidding_engine/handler.py` emits it — coordinate pairs, a string
/// `base_fare`, a relative `expires_in_seconds`, and no address strings
/// anywhere. Copied from the producing handler so this e2e exercises the
/// real contract rather than whatever the parser tolerates.
Map<String, dynamic> _rideOfferPayload({
  required String tripId,
  required String riderId,
  double baseFare = 100.0,
}) {
  return {
    'action': 'rideOfferAvailable',
    'tripId': tripId,
    'rider_id': riderId,
    'pickup_location': const [-33.9249, 18.4241],
    'dropoff_location': const [-33.9581, 18.6961],
    'passenger_count': 3,
    'base_fare': baseFare.toString(),
    'expires_in_seconds': 15,
  };
}

/// Advances time without ever calling `pumpAndSettle()` — see the file-level
/// caveat about indeterminate animations once the driver is online.
///
/// Deliberately a *single* large jump rather than many small increments:
/// some entrance animations in this app use `Curves.easeOutBack`, which
/// legitimately overshoots past 1.0 (and dips below 0.0) at intermediate
/// points along its timeline before settling — `bidding_marketplace_screen.dart`'s
/// geofence overlay feeds that raw curved value straight into an `Opacity`,
/// whose value must stay within [0.0, 1.0], so sampling an intermediate
/// frame at exactly the wrong moment trips that assertion. A single pump
/// covering the whole window advances the animation controller straight to
/// its value at the final elapsed time in one step, without rendering the
/// intermediate overshoot frame — the same reason `pumpAndSettle()` isn't
/// used, just without the indeterminate-animation hang. This is a test-only
/// workaround for a pre-existing UI polish issue unrelated to the WS wiring
/// this suite exists to verify, so it is not modified here.
Future<void> _pumpFrames(WidgetTester tester, [int totalMs = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: totalMs));
}

/// Pumps in many small steps (10s total) until any pending `Timer`s bound to
/// the test's fake clock — SnackBar show/auto-dismiss timers, the
/// EarningsToast's 4s auto-dismiss `Future.delayed` — have fired and
/// completed. `flutter_test` hard-fails a test that ends with any such timer
/// still pending, and (per the call sites below) these specific timers only
/// arm on a later *frame* once their own entrance animation reports
/// complete, so they need small incremental pumps rather than
/// `_pumpFrames`'s single big jump (which exists specifically to dodge an
/// unrelated curve-overshoot bug — see its doc comment).
Future<void> _drainPendingTimers(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Fakes `image_picker` so onboarding document uploads never touch the
/// camera. Mirrors the pattern in `driver_onboarding_screen_test.dart`.
class _FakeImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile('/tmp/fake_doc.jpg');
}

/// Fakes the S3 presign + upload round trip so onboarding never touches the
/// network. Mirrors the pattern in `driver_onboarding_screen_test.dart`.
class _FakeUploadService extends DriverDocumentUploadService {
  _FakeUploadService() : super(tokenVault: TokenVault(), onRefreshNeeded: () async => false);

  @override
  Future<PresignedUpload> requestPresignedUploadUrl({
    required String userId,
    required String docType,
    String contentType = 'image/jpeg',
  }) async => PresignedUpload(
        uploadUrl: 'https://example.com/upload',
        s3Key: 'drivers/$userId/$docType/fake.jpg',
      );

  @override
  Future<void> uploadFile({
    required String uploadUrl,
    required File file,
    required String contentType,
  }) async {}
}

void main() {
  testWidgets(
    'driver completes onboarding and profile setup, returning to the marketplace home',
    (tester) async {
      await seedPreAuthenticatedSession();

      final fakeWs = FakeKwellaWebSocketService();
      final fakeLocation = FakeKwellaLocationService();
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(_buildDriverApp(
        wsService: fakeWs,
        locationService: fakeLocation,
        navigatorKey: navigatorKey,
      ));
      await tester.pump();

      // Pre-authenticate the Riverpod auth state directly (the same pattern
      // driver_onboarding_screen_test.dart uses), rather than relying on
      // KwellaAuthNotifier's real async persisted-session check racing with
      // the first upload tap.
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BiddingMarketplaceScreen)));
      container.read(kwellaAuthNotifierProvider.notifier).state = const KwellaAuthState(
        status: KwellaAuthStatus.authenticated,
        userId: 'drv-e2e-1',
      );

      navigatorKey.currentState!.push(MaterialPageRoute(
        builder: (_) => DriverOnboardingScreen(
          uploadService: _FakeUploadService(),
          imagePicker: _FakeImagePicker(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DriverOnboardingScreen), findsOneWidget);

      // Driver's Licence and PrDP start pre-verified/uploaded; complete the
      // remaining three pending documents.
      for (final docType in [
        'VEHICLE_REGISTRATION',
        'CATA_STICKER_PHOTO',
        'SELFIE_VERIFICATION',
      ]) {
        final uploadKey = Key('upload_button_$docType');
        expect(find.byKey(uploadKey), findsOneWidget,
            reason: '$docType should still be pending before upload');
        // The doc checklist can overflow the test viewport, so the button
        // may start outside the scrollable's visible bounds — scroll it
        // into view before tapping to avoid mis-hitting the wrong widget.
        await tester.ensureVisible(find.byKey(uploadKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(uploadKey));
        await tester.pumpAndSettle();
      }

      final submitOnboardingButton =
          tester.widget<ElevatedButton>(find.byKey(const Key('submit_onboarding_button')));
      expect(submitOnboardingButton.onPressed, isNotNull,
          reason: 'all 5 documents should be completed by now');

      await tester.tap(find.byKey(const Key('go_to_profile_setup_button')));
      await tester.pumpAndSettle();

      expect(find.byType(DriverProfileSetupScreen), findsOneWidget);

      // See the file-level caveat: simulate a successful submission's only
      // externally-visible effect (returning to the previous screen) rather
      // than driving _submit()'s real, unmockable network calls.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(DriverOnboardingScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('submit_onboarding_button')));
      await tester.pumpAndSettle();

      expect(find.byType(BiddingMarketplaceScreen), findsOneWidget);
      expect(find.byType(DriverOnboardingScreen), findsNothing);
      expect(find.byType(DriverProfileSetupScreen), findsNothing);
    },
  );

  testWidgets(
    'an unanswered ride offer auto-expires and clears from state after the 15s countdown',
    (tester) async {
      final fakeWs = FakeKwellaWebSocketService();
      final fakeLocation = FakeKwellaLocationService();

      await tester.pumpWidget(_buildDriverApp(wsService: fakeWs, locationService: fakeLocation));
      await tester.pump();

      await tester.tap(find.byKey(const Key('go_puck')));
      await _pumpFrames(tester);

      expect(fakeWs.connectCalled, isTrue);

      fakeWs.emit(_rideOfferPayload(tripId: 'TRIP#expire-e2e', riderId: 'USR#rider-e2e-1'));
      await _pumpFrames(tester);

      expect(find.text('New Trip Request'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.byType(BiddingMarketplaceScreen)));
      expect(container.read(telemetryControllerProvider).activeOffer, isNotNull);

      // `testWidgets` runs inside flutter_test's fake-async zone, which is
      // exactly why this is fast and deterministic instead of a real 16s
      // wait: `Timer`/`Timer.periodic` created during the test (including
      // the controller's countdown ticker) are bound to that zone's fake
      // clock, and `tester.pump(duration)` is what advances it — firing
      // every tick due within that window synchronously. (`tester.runAsync`
      // would do the opposite: it escapes to a *real* time zone, which
      // never advances the fake clock the timer actually lives on — real
      // wall-clock time can elapse there forever without the countdown ever
      // firing, which is what the first version of this test actually hit.)
      await tester.pump(const Duration(seconds: 16));
      // Let the offer overlay's AnimatedSwitcher exit transition (300ms)
      // finish so the old "New Trip Request" card is actually removed from
      // the tree, not just mid-fade.
      await _pumpFrames(tester);

      expect(container.read(telemetryControllerProvider).activeOffer, isNull);
      expect(find.text('New Trip Request'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  testWidgets(
    'bidding, matching, and the full trip lifecycle dispatch the correct WS contract frames',
    (tester) async {
      const tripId = 'TRIP#e2e-live-001';
      const riderId = 'USR#rider-e2e-live';
      const bidAmount = 100.0;

      final fakeWs = FakeKwellaWebSocketService();
      final fakeLocation = FakeKwellaLocationService();
      final positionController = StreamController<Position>();
      fakeLocation.fakeStream = positionController.stream;
      addTearDown(positionController.close);

      await tester.pumpWidget(_buildDriverApp(wsService: fakeWs, locationService: fakeLocation));
      await tester.pump();

      // ── Go online ──────────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('go_puck')));
      await _pumpFrames(tester);
      expect(fakeWs.connectCalled, isTrue);

      // ── A ride offer arrives ──────────────────────────────────────────
      fakeWs.emit(_rideOfferPayload(tripId: tripId, riderId: riderId, baseFare: bidAmount));
      await _pumpFrames(tester);

      expect(find.text('New Trip Request'), findsOneWidget);
      expect(find.textContaining('15s'), findsOneWidget);
      expect(find.byKey(const Key('bid_accept_base')), findsOneWidget);

      // ── Submit the base-fare bid ────────────────────────────────────────
      await tester.tap(find.byKey(const Key('bid_accept_base')));
      await _pumpFrames(tester);

      final sendBidFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'sendBid').toList();
      expect(sendBidFrames, hasLength(1),
          reason: 'exactly one sendBid frame should have been dispatched');
      final sendBid = sendBidFrames.single;
      expect(sendBid['driverId'], isNotNull);
      expect(sendBid['riderId'], equals(riderId));
      expect(sendBid['tripId'], equals(tripId));
      expect(sendBid['amount'], equals(bidAmount));

      // The offer overlay should have cleared once the bid was submitted.
      expect(find.text('New Trip Request'), findsNothing);

      // ── The rider selects this driver's bid ─────────────────────────────
      fakeWs.emit({
        'action': 'bidSelected',
        'tripId': tripId,
        'driverId': _driverId,
        'riderId': riderId,
      });
      await _pumpFrames(tester);

      final container =
          ProviderScope.containerOf(tester.element(find.byType(BiddingMarketplaceScreen)));
      expect(container.read(telemetryControllerProvider).activeTripId, equals(tripId));

      // ── Driver reaches the pickup geofence ──────────────────────────────
      fakeWs.emit({'flags': {'geofence_status': 'ARRIVED'}});
      await _pumpFrames(tester);

      expect(find.text('Destination Reached'), findsOneWidget);

      // Slide-to-confirm is a raw drag gesture on the knob icon. A large
      // delta guarantees crossing the 85% confirmation threshold regardless
      // of the exact rendered track width.
      await tester.drag(find.byIcon(Icons.arrow_forward_rounded), const Offset(1000, 0));
      await _pumpFrames(tester);

      final driverArrivedFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'driverArrived').toList();
      expect(driverArrivedFrames, hasLength(1));
      expect(driverArrivedFrames.single['tripId'], equals(tripId));

      expect(find.byType(TripNavigationScreen), findsOneWidget);

      // ── TripNavigationScreen.initState() fires startTrip on mount ───────
      final startTripFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'startTrip').toList();
      expect(startTripFrames, hasLength(1));
      expect(startTripFrames.single['tripId'], equals(tripId));
      expect(startTripFrames.single['driverId'], equals(_driverId));

      // ── Drive the scripted GPS stream through and assert updateLocation ─
      positionController.add(
        makeFakePosition(latitude: -33.9, longitude: 18.4, heading: 90, speed: 5),
      );
      positionController.add(
        makeFakePosition(latitude: -33.91, longitude: 18.41, heading: 92, speed: 7),
      );
      await _pumpFrames(tester);

      final updateLocationFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'updateLocation').toList();
      expect(updateLocationFrames.length, greaterThanOrEqualTo(2));
      expect(updateLocationFrames.first['driverId'], equals(_driverId));
      expect(updateLocationFrames.first.containsKey('latitude'), isTrue);
      expect(updateLocationFrames.first.containsKey('longitude'), isTrue);

      // Two SnackBars were queued via the (single, app-wide)
      // ScaffoldMessenger — "Bid submitted" from the marketplace step, then
      // "Arrival confirmed" from the pickup-arrival slide above — and they
      // float above whichever route is on top, including this freshly
      // pushed screen. Left showing, they physically overlap the
      // bottom-of-screen slide-to-confirm control below and steal the drag
      // gesture's hit test. Let them finish showing/auto-dismissing (each
      // queued one only starts its own hide timer once the previous one's
      // exit animation completes) before interacting with anything below
      // them. Many small pumps, not one big jump: a SnackBar's hide timer
      // is only armed on a later frame once its own entrance animation
      // reports complete, so jumping straight to a far-future time in one
      // step (as `_pumpFrames` deliberately does, to dodge a curve-overshoot
      // bug elsewhere — see its doc comment) skips over the frame where that
      // arming would happen.
      await _drainPendingTimers(tester);

      // ── Destination slide-to-confirm ────────────────────────────────────
      await tester.drag(
        find.text('Slide to confirm arrival →'),
        const Offset(1000, 0),
      );
      await _pumpFrames(tester);

      final confirmArrivalFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'confirmArrival').toList();
      expect(confirmArrivalFrames, hasLength(1));
      expect(confirmArrivalFrames.single['tripId'], equals(tripId));
      expect(confirmArrivalFrames.single['driverId'], equals(_driverId));
      // Key regression assertion: the final bid amount echoed back must
      // match the amount actually bid in the marketplace step above, not a
      // hardcoded/zero placeholder.
      expect(confirmArrivalFrames.single['final_bid_amount'], equals(bidAmount));

      expect(find.byType(PostTripScreen), findsOneWidget);

      // ── Wallet settlement push arrives ──────────────────────────────────
      fakeWs.emit({
        'status': 'WalletSettled',
        'tripId': tripId,
        'net_earnings': 85.0,
        'currency': 'ZAR',
        'updated_daily_total': 85.0,
      });
      await _pumpFrames(tester);

      // `lastNetEarnings` is intentionally transient: BiddingMarketplaceScreen
      // (still mounted underneath, listening via ref.listen even while
      // obscured by the pushed trip/post-trip routes) shows a one-shot toast
      // the instant it goes non-null and immediately calls
      // clearLastNetEarnings() in the same notification — so by the time
      // this line runs it may already be back to null. dailyEarningsTotal is
      // the persistent half of the same update and is what's asserted here.
      expect(container.read(telemetryControllerProvider).dailyEarningsTotal, equals(85.0));
      expect(find.byType(PostTripScreen), findsOneWidget);

      // ── Post-trip rating ─────────────────────────────────────────────────
      // Tap the 4th star (0-indexed i=3) to set a rating of 4.
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(3));
      await _pumpFrames(tester);

      await tester.tap(find.byKey(const Key('submit_rating_button')));
      await _pumpFrames(tester);

      final submitRatingFrames =
          fakeWs.sentMessages.where((m) => m['action'] == 'submitRating').toList();
      expect(submitRatingFrames, hasLength(1));
      final submitRating = submitRatingFrames.single;
      expect(submitRating['driverId'], equals(_driverId));
      expect(submitRating['tripId'], equals(tripId));
      expect(submitRating['rating'], equals(4));
      expect(submitRating['target'], equals('RIDER'));

      // popUntil(isFirst) after submitting the rating returns to the
      // marketplace home, dropping the trip/post-trip screens.
      expect(find.byType(BiddingMarketplaceScreen), findsOneWidget);
      expect(find.byType(PostTripScreen), findsNothing);
      expect(find.byType(TripNavigationScreen), findsNothing);

      // The WalletSettled push above armed the EarningsToast's 4s
      // auto-dismiss `Future.delayed` on the marketplace screen underneath.
      // flutter_test hard-fails any test that ends with a `Timer` still
      // pending, so let it finish before the test body returns.
      await _drainPendingTimers(tester);
    },
  );
}
