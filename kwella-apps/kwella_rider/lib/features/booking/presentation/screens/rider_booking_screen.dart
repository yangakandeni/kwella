import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/driver_bid_card.dart';

class RiderBookingScreen extends ConsumerStatefulWidget {
  const RiderBookingScreen({super.key});

  @override
  ConsumerState<RiderBookingScreen> createState() => _RiderBookingScreenState();
}

class _RiderBookingScreenState extends ConsumerState<RiderBookingScreen> {
  late final TextEditingController _pickupController;
  late final TextEditingController _dropoffController;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController();
    _dropoffController = TextEditingController();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  Widget _buildLocationField({
    required String label,
    required TextEditingController controller,
    required Key fieldKey,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF111111)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF111111)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildPassengerSelector(
    RiderTripState state,
    KwellaRiderController controller,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (index) {
          final int passengerCount = index + 1;
          final bool isSelected = state.passengerCount == passengerCount;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
              child: GestureDetector(
                key: Key('passenger_$passengerCount'),
                onTap: () => controller.setPassengerCount(passengerCount),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1E4620)
                        : const Color(0xFFF4F4EA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF1E4620)
                          : const Color(0xFFCCCCCC),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      passengerCount.toString(),
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF111111),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Alignment _mapAlignmentForLocation(DriverLocation location) {
    const double latitudeCenter = -34.0012;
    const double longitudeCenter = 18.6013;
    const double latitudeSpan = 0.14;
    const double longitudeSpan = 0.2;

    final double normalizedX =
        ((location.longitude - longitudeCenter) / (longitudeSpan / 2)).clamp(
          -1.0,
          1.0,
        );
    final double normalizedY =
        -((location.latitude - latitudeCenter) / (latitudeSpan / 2)).clamp(
          -1.0,
          1.0,
        );

    return Alignment(normalizedX, normalizedY);
  }

  Widget _buildTrackingMap(RiderTripState state) {
    final DriverLocation? location = state.currentDriverLocation;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF152E44), Color(0xFF0A1720)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF192D3F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12, width: 1.2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  location != null
                      ? 'Tracking driver at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
                      : 'Waiting for driver telemetry…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (location != null)
            AnimatedAlign(
              alignment: _mapAlignmentForLocation(location),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOut,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Container(
                  key: const Key('driver_marker'),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E4620),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.32),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          if (location == null)
            const Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Driver telemetry is coming live. Hold tight.',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(kwellaRiderControllerProvider);
    final stateAsync = ref.watch(riderTripStateProvider);
    final availableBidsAsync = ref.watch(availableBidsProvider);
    final RiderTripState state = stateAsync.asData?.value ?? controller.state;

    if (_pickupController.text != state.pickupLocation) {
      _pickupController.text = state.pickupLocation;
    }
    if (_dropoffController.text != state.dropoffLocation) {
      _dropoffController.text = state.dropoffLocation;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Stack(
        children: [
          Positioned.fill(
            child:
                state.status == RiderTripStatus.accepted ||
                    state.status == RiderTripStatus.arrived
                ? _buildTrackingMap(state)
                : Container(
                    color: const Color(0xFF111111),
                    child: const Center(
                      child: Text(
                        'Map placeholder',
                        style: TextStyle(color: Colors.white70, fontSize: 18),
                      ),
                    ),
                  ),
          ),
          if (state.latestEvent != null &&
              state.latestEvent!['action'] == 'geofenceTrigger' &&
              state.latestEvent!['geofence_status'] == 'ARRIVED')
            Positioned(
              left: 16,
              right: 16,
              top: 56,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E4620),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Your driver has arrived! Meet them at the pickup point.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (state.status == RiderTripStatus.biddingOpen)
            Positioned(
              left: 16,
              right: 16,
              bottom: 310,
              child: SizedBox(
                height: 188,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Live driver bids',
                        style: TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: availableBidsAsync.when(
                        data: (bids) {
                          if (bids.isEmpty) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Center(
                                child: Text(
                                  'Waiting for the next best bid...',
                                  style: TextStyle(color: Color(0xFF111111)),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: bids.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> bid = bids[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: index == bids.length - 1 ? 0 : 12,
                                ),
                                child: DriverBidCard(
                                  driverId: bid['driverId'] as String? ?? '',
                                  driverName:
                                      bid['driverName'] as String? ?? 'Unknown',
                                  driverRating: bid['rating'] != null
                                      ? '${bid['rating']} ★'
                                      : '— ★',
                                  vehicleDescription:
                                      '${bid['vehicleColor'] ?? 'White'} ${bid['vehicleModel'] ?? bid['vehicle'] ?? 'Suzuki Ertiga'}',
                                  licensePlate:
                                      bid['licensePlate'] as String? ??
                                      'CAA 123-456',
                                  cataSticker:
                                      bid['cataSticker'] as String? ?? 'M02356',
                                  fareLabel:
                                      'Accept R${bid['fare'] ?? bid['bidAmount'] ?? 0}',
                                  onAccept: () => controller.selectBid(
                                    bid['driverId'] as String? ?? '',
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1E4620),
                            ),
                          ),
                        ),
                        error: (_, __) => Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: Text(
                              'Unable to load bids',
                              style: TextStyle(color: Color(0xFF111111)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF4F4EA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildLocationField(
                          label: 'Pickup location',
                          controller: _pickupController,
                          fieldKey: const Key('pickup_input'),
                          onChanged: controller.updatePickupLocation,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildLocationField(
                          label: 'Drop-off location',
                          controller: _dropoffController,
                          fieldKey: const Key('dropoff_input'),
                          onChanged: controller.updateDropoffLocation,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Passengers',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildPassengerSelector(state, controller),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const Key('request_ride_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E4620),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: controller.requestTrip,
                      child: const Text(
                        'Request Ride',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
