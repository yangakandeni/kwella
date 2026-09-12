import 'dart:math' as math;

/// Client-side mirror of the server's fare engine.
///
/// The authoritative implementation is
/// `kwella-backend/src/layers/kwella_shared/python/fare_calculator.py`. This
/// class exists so the rider app can quote a fare *before* `requestTrip`
/// without guessing: every constant and every term below is a deliberate
/// copy of that file, so the number shown on the fare-offer screen is the
/// number the backend will broadcast as `calculated_fare`.
///
/// There is deliberately no rider-side fee term. kwella's 10% is a
/// driver-side commission deducted from the fare the two parties agree on:
/// a rider who offers R80 against a driver's R100 counter pays R100, of
/// which kwella takes R10 and the driver banks R90. An earlier revision
/// also added 10% on top of the rider's quote, charging it twice.
///
/// That matters because the backend refuses to trust the client's
/// `suggested_base_fare` — it recomputes from scratch and its answer wins.
/// Any drift between this file and the Python one is therefore a product
/// bug, not a rounding nicety: the rider is shown a fare that cannot be
/// honoured. **If you change one, change both**, and keep
/// `kwella_fare_estimator_test.dart` in step with
/// `kwella-backend/tests/test_fare_calculator.py`.
///
/// Two consequences of that mirroring worth knowing:
///
///  * **Distance is straight-line, not road distance.** The server computes
///    a haversine distance from the four pickup/dropoff coordinates, so this
///    estimator must too — see [estimateFromCoordinates]. Feeding it Google's
///    road distance would inflate the quote above what the server charges.
///    The route polyline on the map still shows real road distance; it is
///    for the rider's orientation, not for pricing.
///  * **Duration is derived, not measured.** Both sides derive minutes from
///    distance at [assumedAverageSpeedKmh] rather than taking a Directions
///    API duration, so neither side needs a network call to agree.
///  * **Totals land on a R0.50 quantum.** See [quantizeFareZar] — cash
///    trips cannot settle in cents nobody carries.
class KwellaFareEstimator {
  const KwellaFareEstimator({this.flatRateZar = defaultFlatRateZar});

  /// Matches `KWELLA_FLAT_RATE_ZAR`'s server-side default. Injectable so a
  /// fuel-price change can be reflected without editing this class.
  final double flatRateZar;

  /// Server default for `KWELLA_FLAT_RATE_ZAR`.
  static const double defaultFlatRateZar = 10.0;

  /// Seats in a standard amaphela (7-seater minus the driver).
  static const int seatsPerVehicle = 6;

  static const double _baseFareFactor = 0.50;
  static const double _perKmRateFactor = 0.75;
  static const double _perMinuteRateFactor = 0.08;
  static const double _perExtraPassengerFactor = 0.25;
  static const double _peakHourMultiplier = 1.15;
  static const double _nightRiskFactor = 0.50;

  /// The coin granularity every rider-facing amount is expressed in.
  ///
  /// Most kwella trips settle in cash and 1c/2c/5c coins are effectively out
  /// of circulation in South Africa, so an R95.21 quote is one nobody at the
  /// kerb can actually settle. Mirrors `FARE_QUANTUM_ZAR` server-side.
  static const double fareQuantumZar = 0.50;

  /// Assumed average road speed used to derive duration from distance.
  static const double assumedAverageSpeedKmh = 25.0;

  /// Earth radius in metres, for the haversine distance.
  static const double _earthRadiusM = 6371000.0;

  /// `(flat_rate / 2) x 6 seats` — charged once per trip, never per
  /// passenger: the seat multiplier already prices the whole vehicle.
  double get baseFare => _baseFareFactor * flatRateZar * seatsPerVehicle;

  /// The `flat_rate x 6 seats` floor applied to the final total.
  double get floorFare => flatRateZar * seatsPerVehicle;

  /// Lifts [amount] to the next payable multiple of [fareQuantumZar].
  ///
  /// One-directional, like the server's `quantize_fare_zar`: rounding to
  /// nearest would sometimes quote under what the formula priced, which on a
  /// cash trip means the driver making up the difference out of their own
  /// earnings.
  ///
  /// Worked in whole cents rather than on the doubles directly — a double
  /// division can land a hair above an exact multiple and push the ceiling a
  /// full 50c too far.
  static double quantizeFareZar(double amount) {
    const int stepCents = 50;
    final int cents = (amount * 100).round();
    final int lifted = ((cents + stepCents - 1) ~/ stepCents) * stepCents;
    return lifted / 100;
  }

  /// Whether [amount] is one the backend's wire contract will accept.
  ///
  /// Lets the apps keep an un-payable rider offer or driver counter-offer off
  /// the wire instead of learning about it from a 400.
  static bool isQuantizedFare(num amount) {
    final double cents = amount * 100;
    // Sub-cent amounts are out regardless of where they sit on the quantum.
    if ((cents - cents.roundToDouble()).abs() > 1e-6) return false;
    return cents.round() % 50 == 0;
  }

  /// Great-circle distance in kilometres — the same measure the server's
  /// `calculate_distance` uses on the coordinates sent with `requestTrip`.
  static double haversineKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    double toRad(double d) => d * math.pi / 180.0;
    final double p1 = toRad(fromLat);
    final double p2 = toRad(toLat);
    final double dPhi = toRad(toLat - fromLat);
    final double dLambda = toRad(toLng - fromLng);
    final double a = math.pow(math.sin(dPhi / 2), 2) +
        math.cos(p1) * math.cos(p2) * math.pow(math.sin(dLambda / 2), 2);
    return (2 * _earthRadiusM * math.asin(math.sqrt(a))) / 1000.0;
  }

  /// Expected trip duration in minutes, derived from [distanceKm].
  double estimateDurationMinutes(double distanceKm) =>
      (distanceKm / assumedAverageSpeedKmh) * 60.0;

  /// Full fare breakdown for a trip, mirroring the server's
  /// `calculate_trip_fare_breakdown`.
  ///
  /// [requestTime] is only used to evaluate the peak/night surcharges and is
  /// interpreted in SAST (UTC+2, no DST); it defaults to now.
  KwellaFareBreakdown estimate({
    required double distanceKm,
    int passengerCount = 1,
    DateTime? requestTime,
  }) {
    final int passengers = passengerCount.clamp(1, seatsPerVehicle);
    final DateTime sast =
        (requestTime ?? DateTime.now()).toUtc().add(const Duration(hours: 2));
    final int hour = sast.hour;
    final bool peak = (hour >= 6 && hour < 9) || (hour >= 16 && hour < 19);
    final bool night = hour >= 22 || hour < 5;

    final double durationMinutes = estimateDurationMinutes(distanceKm);

    double distanceFare = _perKmRateFactor * flatRateZar * distanceKm;
    double timeFare = _perMinuteRateFactor * flatRateZar * durationMinutes;
    if (peak) {
      distanceFare *= _peakHourMultiplier;
      timeFare *= _peakHourMultiplier;
    }

    final double passengerSurcharge =
        _perExtraPassengerFactor * flatRateZar * (passengers - 1);
    final double nightRiskPremium = night ? flatRateZar * _nightRiskFactor : 0.0;

    // Round each component to cents before summing, exactly as the Python
    // engine quantizes before it adds — otherwise the two can disagree by a
    // cent on some routes.
    double cents(double v) => (v * 100).roundToDouble() / 100;

    final double roundedBase = cents(baseFare);
    final double roundedTime = cents(timeFare);
    final double roundedDistance = cents(distanceFare);
    final double roundedPassengers = cents(passengerSurcharge);
    final double roundedNight = cents(nightRiskPremium);

    final double subtotal = cents(roundedBase +
        roundedTime +
        roundedDistance +
        roundedPassengers +
        roundedNight);
    final double formulaTotal = quantizeFareZar(subtotal);
    final double floor = quantizeFareZar(floorFare);
    final double total = math.max(formulaTotal, floor);

    return KwellaFareBreakdown(
      baseFare: roundedBase,
      durationMinutes: durationMinutes,
      timeFare: roundedTime,
      distanceFare: roundedDistance,
      passengerSurcharge: roundedPassengers,
      nightRiskPremium: roundedNight,
      subtotal: subtotal,
      totalFare: total,
      floorFare: floor,
      floorApplied: total > formulaTotal,
      peakHour: peak,
    );
  }

  /// Convenience wrapper that derives the distance from the trip's pickup and
  /// dropoff coordinates the same way the server does, so callers can't
  /// accidentally feed in a road distance.
  KwellaFareBreakdown estimateFromCoordinates({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    int passengerCount = 1,
    DateTime? requestTime,
  }) {
    return estimate(
      distanceKm: haversineKm(
        fromLat: pickupLat,
        fromLng: pickupLng,
        toLat: dropoffLat,
        toLng: dropoffLng,
      ),
      passengerCount: passengerCount,
      requestTime: requestTime,
    );
  }
}

/// Every component that produced a fare, so the rider's fare sheet can
/// explain the total rather than merely assert it.
class KwellaFareBreakdown {
  const KwellaFareBreakdown({
    required this.baseFare,
    required this.durationMinutes,
    required this.timeFare,
    required this.distanceFare,
    required this.passengerSurcharge,
    required this.nightRiskPremium,
    required this.subtotal,
    required this.totalFare,
    required this.floorFare,
    required this.floorApplied,
    required this.peakHour,
  });

  final double baseFare;
  final double durationMinutes;
  final double timeFare;
  final double distanceFare;
  final double passengerSurcharge;
  final double nightRiskPremium;
  final double subtotal;

  /// What the rider is quoted, and what the server should broadcast back as
  /// `calculated_fare` for the same trip.
  ///
  /// This is the whole of what the rider pays — kwella's 10% is taken out of
  /// the driver's side of the agreed fare on settlement, never added here.
  final double totalFare;

  final double floorFare;

  /// True when [floorFare] overrode the formula — a very short hop.
  final bool floorApplied;

  final bool peakHour;
}
