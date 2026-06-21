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
  final List<Map<String, dynamic>> bidMetrics;
  final Map<String, dynamic>? latestEvent;

  const RiderTripState({
    this.status = RiderTripStatus.idle,
    this.bidMetrics = const [],
    this.latestEvent,
  });

  RiderTripState copyWith({
    RiderTripStatus? status,
    List<Map<String, dynamic>>? bidMetrics,
    Map<String, dynamic>? latestEvent,
  }) {
    return RiderTripState(
      status: status ?? this.status,
      bidMetrics: bidMetrics ?? this.bidMetrics,
      latestEvent: latestEvent ?? this.latestEvent,
    );
  }
}
