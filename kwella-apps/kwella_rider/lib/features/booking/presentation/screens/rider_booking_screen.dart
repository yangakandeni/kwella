import 'package:flutter/material.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';

class RiderBookingScreen extends StatefulWidget {
  const RiderBookingScreen({super.key, this.controller});

  final KwellaRiderController? controller;

  @override
  State<RiderBookingScreen> createState() => _RiderBookingScreenState();
}

class _RiderBookingScreenState extends State<RiderBookingScreen> {
  late final KwellaRiderController _controller;
  late final bool _ownsController;
  late final TextEditingController _pickupController;
  late final TextEditingController _dropoffController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KwellaRiderController();
    _pickupController = TextEditingController(
      text: _controller.state.pickupLocation,
    );
    _dropoffController = TextEditingController(
      text: _controller.state.dropoffLocation,
    );
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
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

  Widget _buildPassengerSelector(RiderTripState state) {
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
                onTap: () => _controller.setPassengerCount(passengerCount),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: StreamBuilder<RiderTripState>(
        stream: _controller.stateStream,
        initialData: _controller.state,
        builder: (context, snapshot) {
          final RiderTripState state = snapshot.data ?? _controller.state;

          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF111111),
                  child: const Center(
                    child: Text(
                      'Map placeholder',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
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
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
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
                              onChanged: _controller.updatePickupLocation,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildLocationField(
                              label: 'Drop-off location',
                              controller: _dropoffController,
                              fieldKey: const Key('dropoff_input'),
                              onChanged: _controller.updateDropoffLocation,
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
                      _buildPassengerSelector(state),
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
                          onPressed: _controller.requestTrip,
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
          );
        },
      ),
    );
  }
}
