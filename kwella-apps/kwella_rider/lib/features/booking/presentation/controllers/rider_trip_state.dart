enum RiderTripStatus {
  idle,
  searching,
  biddingOpen,
  accepted,
  arrived,
  completed,
}

/// Lifecycle of the pickup point's default-to-device-location lookup.
enum PickupLocationStatus {
  /// Coordinates and/or address are still being retrieved.
  loading,

  /// The device location was resolved into [RiderTripState.pickupLocation].
  resolved,

  /// Location access was denied/disabled, or the lookup failed — the rider
  /// must set a pickup point manually.
  unavailable,
}

class DriverLocation {
  final double latitude;
  final double longitude;

  const DriverLocation({required this.latitude, required this.longitude});
}

class RiderTripState {
  final RiderTripStatus status;
  final int passengerCount;
  final String pickupLocation;
  final PickupLocationStatus pickupLocationStatus;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffLocation;
  final double? dropoffLat;
  final double? dropoffLng;
  final String tripId;
  final List<Map<String, dynamic>> bidMetrics;
  final DriverLocation? currentDriverLocation;
  final Map<String, dynamic>? latestEvent;
  final String? driverName;
  final String? driverRating;
  final String? vehicleDescription;
  final String? licensePlate;

  const RiderTripState({
    this.status = RiderTripStatus.idle,
    this.passengerCount = 1,
    this.pickupLocation = '',
    this.pickupLocationStatus = PickupLocationStatus.loading,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLocation = '',
    this.dropoffLat,
    this.dropoffLng,
    this.tripId = '',
    this.bidMetrics = const [],
    this.currentDriverLocation,
    this.latestEvent,
    this.driverName,
    this.driverRating,
    this.vehicleDescription,
    this.licensePlate,
  });

  List<Map<String, dynamic>> get availableBids => List.unmodifiable(bidMetrics);

  RiderTripState copyWith({
    RiderTripStatus? status,
    int? passengerCount,
    String? pickupLocation,
    PickupLocationStatus? pickupLocationStatus,
    double? pickupLat,
    double? pickupLng,
    String? dropoffLocation,
    double? dropoffLat,
    double? dropoffLng,
    String? tripId,
    List<Map<String, dynamic>>? bidMetrics,
    DriverLocation? currentDriverLocation,
    Map<String, dynamic>? latestEvent,
    String? driverName,
    String? driverRating,
    String? vehicleDescription,
    String? licensePlate,
  }) {
    return RiderTripState(
      status: status ?? this.status,
      passengerCount: passengerCount ?? this.passengerCount,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      pickupLocationStatus: pickupLocationStatus ?? this.pickupLocationStatus,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      tripId: tripId ?? this.tripId,
      bidMetrics: bidMetrics ?? this.bidMetrics,
      currentDriverLocation:
          currentDriverLocation ?? this.currentDriverLocation,
      latestEvent: latestEvent ?? this.latestEvent,
      driverName: driverName ?? this.driverName,
      driverRating: driverRating ?? this.driverRating,
      vehicleDescription: vehicleDescription ?? this.vehicleDescription,
      licensePlate: licensePlate ?? this.licensePlate,
    );
  }
}
