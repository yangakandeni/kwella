enum RiderTripStatus {
  idle,
  searching,
  biddingOpen,
  accepted,
  arrived,
  completed,
}

class RiderTripState {
  final RiderTripStatus status;
  final int passengerCount;
  final String pickupLocation;
  final String dropoffLocation;
  final List<Map<String, dynamic>> bidMetrics;
  final Map<String, dynamic>? latestEvent;

  const RiderTripState({
    this.status = RiderTripStatus.idle,
    this.passengerCount = 1,
    this.pickupLocation = '',
    this.dropoffLocation = '',
    this.bidMetrics = const [],
    this.latestEvent,
  });

  RiderTripState copyWith({
    RiderTripStatus? status,
    int? passengerCount,
    String? pickupLocation,
    String? dropoffLocation,
    List<Map<String, dynamic>>? bidMetrics,
    Map<String, dynamic>? latestEvent,
  }) {
    return RiderTripState(
      status: status ?? this.status,
      passengerCount: passengerCount ?? this.passengerCount,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      bidMetrics: bidMetrics ?? this.bidMetrics,
      latestEvent: latestEvent ?? this.latestEvent,
    );
  }
}
