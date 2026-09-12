import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';

/// Deliberate mirror of `kwella-backend/tests/test_fare_calculator.py`.
///
/// The assertions below use the same worked examples as the Python suite, so
/// if the two engines ever drift apart one of the two suites goes red rather
/// than a rider being quoted a fare the server won't honour.
void main() {
  // 12:00 SAST — off peak, daytime.
  final DateTime offPeakDaytime = DateTime.utc(2026, 6, 21, 10);
  // 08:30 SAST — morning peak.
  final DateTime peakMorning = DateTime.utc(2026, 6, 21, 6, 30);
  // 23:00 SAST — night.
  final DateTime night = DateTime.utc(2026, 6, 21, 21);

  const KwellaFareEstimator estimator = KwellaFareEstimator();

  group('KwellaFareEstimator — parity with the server engine', () {
    test('the worked example: 5 km, 1 passenger, off-peak => R77.50', () {
      final KwellaFareBreakdown b = estimator.estimate(
        distanceKm: 5.0,
        passengerCount: 1,
        requestTime: offPeakDaytime,
      );

      expect(b.baseFare, 30.00); // (10/2) x 6 seats
      expect(b.durationMinutes, closeTo(12.0, 0.001)); // 5 km @ 25 km/h
      expect(b.timeFare, 9.60); // 0.08 x 10 x 12
      expect(b.distanceFare, 37.50); // 0.75 x 10 x 5
      expect(b.passengerSurcharge, 0.00);
      expect(b.nightRiskPremium, 0.00);
      expect(b.subtotal, 77.10);
      // No rider-side fee: kwella's 10% comes out of the driver's side of
      // the agreed fare, not off the rider's quote. R77.10 is lifted to the
      // next 50c the rider can actually pay in cash.
      expect(b.totalFare, 77.50);
      expect(b.floorApplied, isFalse);
    });

    test('duration is derived from distance at the assumed average speed', () {
      expect(estimator.estimateDurationMinutes(5.0), closeTo(12.0, 0.001));
      expect(estimator.estimateDurationMinutes(0.0), 0.0);
      expect(
        estimator.estimateDurationMinutes(10.0),
        greaterThan(estimator.estimateDurationMinutes(5.0)),
      );
    });

    test('base fare is charged once per trip, not per passenger', () {
      final KwellaFareBreakdown one = estimator.estimate(
        distanceKm: 5.0, passengerCount: 1, requestTime: offPeakDaytime);
      final KwellaFareBreakdown six = estimator.estimate(
        distanceKm: 5.0, passengerCount: 6, requestTime: offPeakDaytime);

      expect(one.baseFare, 30.00);
      expect(six.baseFare, 30.00);
      // Six passengers still cost more, via the surcharge: 0.25 x 10 x 5.
      expect(six.passengerSurcharge, 12.50);
      expect(six.totalFare, greaterThan(one.totalFare));
    });

    test('nothing is added on top of the subtotal', () {
      // Regression guard for the 10% that used to be added here. The
      // commission is deducted from the driver's payout on settlement; it is
      // not a surcharge on the rider's quote.
      final KwellaFareBreakdown b = estimator.estimate(
        distanceKm: 8.0, passengerCount: 3, requestTime: offPeakDaytime);
      expect(b.totalFare, KwellaFareEstimator.quantizeFareZar(b.subtotal));
      expect(b.totalFare - b.subtotal,
          lessThan(KwellaFareEstimator.fareQuantumZar));
    });

    test('every quoted total lands on the R0.50 cash quantum', () {
      for (final double km in <double>[3.333, 7.77, 12.345, 0.5, 25.36]) {
        final double total =
            estimator.estimate(distanceKm: km, requestTime: offPeakDaytime)
                .totalFare;
        expect((total * 100).round() % 50, 0, reason: 'km=$km => R$total');
      }
    });

    test('quantizeFareZar lifts to the next 50c, matching the server', () {
      // Mirrors test_quantize_fare_zar_lifts_to_the_next_fifty_cents.
      expect(KwellaFareEstimator.quantizeFareZar(95.21), 95.50);
      expect(KwellaFareEstimator.quantizeFareZar(95.01), 95.50);
      expect(KwellaFareEstimator.quantizeFareZar(95.50), 95.50);
      expect(KwellaFareEstimator.quantizeFareZar(95.51), 96.00);
      expect(KwellaFareEstimator.quantizeFareZar(95.00), 95.00);
      expect(KwellaFareEstimator.quantizeFareZar(0), 0.00);
    });

    test('isQuantizedFare gates the amounts the server would reject', () {
      expect(KwellaFareEstimator.isQuantizedFare(80), isTrue);
      expect(KwellaFareEstimator.isQuantizedFare(100.0), isTrue);
      expect(KwellaFareEstimator.isQuantizedFare(95.50), isTrue);
      expect(KwellaFareEstimator.isQuantizedFare(95.21), isFalse);
      expect(KwellaFareEstimator.isQuantizedFare(95.99), isFalse);
    });

    test('the flat_rate x 6 floor still binds on a zero-distance trip', () {
      final KwellaFareBreakdown b = estimator.estimate(
        distanceKm: 0.0, passengerCount: 1, requestTime: offPeakDaytime);
      // The formula alone gives R30.00; the floor overrides it.
      expect(b.subtotal, 30.00);
      expect(b.totalFare, 60.00);
      expect(b.floorApplied, isTrue);
      expect(b.floorFare, 60.00);
    });

    test('fare rises with distance, passengers, peak and night', () {
      final double short = estimator
          .estimate(distanceKm: 1.0, requestTime: offPeakDaytime)
          .totalFare;
      final double long = estimator
          .estimate(distanceKm: 20.0, requestTime: offPeakDaytime)
          .totalFare;
      expect(long, greaterThan(short));

      final double offPeak = estimator
          .estimate(distanceKm: 10.0, requestTime: offPeakDaytime)
          .totalFare;
      expect(
        estimator.estimate(distanceKm: 10.0, requestTime: peakMorning).totalFare,
        greaterThan(offPeak),
      );
      expect(
        estimator.estimate(distanceKm: 10.0, requestTime: night).totalFare,
        greaterThan(offPeak),
      );
    });

    test('passenger count is clamped into the 1-6 seat range', () {
      double fareFor(int pax) => estimator
          .estimate(
              distanceKm: 5.0, passengerCount: pax, requestTime: offPeakDaytime)
          .totalFare;

      expect(fareFor(0), fareFor(1));
      expect(fareFor(9), fareFor(6));
    });

    test('a higher flat rate lifts both the floor and the variable component',
        () {
      const KwellaFareEstimator dearer =
          KwellaFareEstimator(flatRateZar: 15.0);
      final double low = estimator
          .estimate(distanceKm: 5.0, requestTime: offPeakDaytime)
          .totalFare;
      final double high =
          dearer.estimate(distanceKm: 5.0, requestTime: offPeakDaytime).totalFare;

      expect(high, greaterThan(low));
      expect(high, greaterThanOrEqualTo(15.0 * 6));
    });
  });

  group('KwellaFareEstimator — distance measure', () {
    test('haversineKm matches the server\'s great-circle measure', () {
      // Philippi anchor -> Nyanga, the pair used by the mock scenarios.
      final double km = KwellaFareEstimator.haversineKm(
        fromLat: -34.0103967,
        fromLng: 18.6156183,
        toLat: -33.9930,
        toLng: 18.5920,
      );
      // contract.py::_haversine_m reports ~2912 m for this pair.
      expect(km, closeTo(2.912, 0.01));
    });

    test('estimateFromCoordinates agrees with estimate() on the same distance',
        () {
      const double pickupLat = -34.0103967;
      const double pickupLng = 18.6156183;
      const double dropoffLat = -33.9930;
      const double dropoffLng = 18.5920;

      final double km = KwellaFareEstimator.haversineKm(
        fromLat: pickupLat,
        fromLng: pickupLng,
        toLat: dropoffLat,
        toLng: dropoffLng,
      );

      expect(
        estimator
            .estimateFromCoordinates(
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              dropoffLat: dropoffLat,
              dropoffLng: dropoffLng,
              requestTime: offPeakDaytime,
            )
            .totalFare,
        estimator.estimate(distanceKm: km, requestTime: offPeakDaytime).totalFare,
      );
    });
  });
}
