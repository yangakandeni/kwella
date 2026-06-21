import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';

void main() {
  group('KwellaRiderController', () {
    test('captures incoming driver bid and transitions to biddingOpen', () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'bidMetrics': [
          {'bidAmount': 120, 'driverId': 'driver-123', 'etaSeconds': 180},
        ],
      });

      expect(controller.state.status, equals(RiderTripStatus.biddingOpen));
      expect(controller.state.bidMetrics, isNotEmpty);
      expect(controller.state.bidMetrics.first['bidAmount'], equals(120));

      controller.dispose();
    });
  });
}
