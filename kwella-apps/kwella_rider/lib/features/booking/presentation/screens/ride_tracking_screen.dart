import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/kwella_map_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RideTrackingScreen
// Active ride / en-route live tracking screen.
//
// The driver's live position and matched driver/vehicle details are sourced
// from riderTripStateProvider (populated by the tripMatchConfirmed WebSocket
// event) and rendered as a real marker via KwellaMapView. The widget's
// constructor defaults are used only as a pre-match fallback, before that
// event has arrived.
// ─────────────────────────────────────────────────────────────────────────────

class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({
    super.key,
    this.driverName = 'Sipho M.',
    this.driverRating = '4.9',
    this.vehicleDescription = 'White Toyota Quantum',
    this.licensePlate = 'CA 567-890',
    this.etaMinutes = 3,
  });

  final String driverName;
  final String driverRating;
  final String vehicleDescription;
  final String licensePlate;
  final int etaMinutes;

  @override
  ConsumerState<RideTrackingScreen> createState() =>
      _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  late String _driverName = widget.driverName;
  late String _driverRating = widget.driverRating;
  late String _vehicleDescription = widget.vehicleDescription;
  late String _licensePlate = widget.licensePlate;

  void _showCancelDialog() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x85000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
        title: const Text(
          'Cancel Ride?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Cancelling after the driver is en route may result in a cancellation fee. Are you sure?',
          style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Keep Ride',
              style: TextStyle(color: Color(0xFFDFFF00), fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              'Cancel Ride',
              style: TextStyle(color: Color(0xFFFF5370)),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3C3C3C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Chat with $_driverName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            const _ChatBubble(
              message: 'I\'m on my way, 3 minutes away!',
              isDriver: true,
            ),
            const SizedBox(height: 8),
            const _ChatBubble(
              message: 'Great, I\'m at the gate.',
              isDriver: false,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    child: const Text(
                      'Type a message…',
                      style: TextStyle(
                        color: Color(0xFF606060),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDFFF00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Color(0xFF1A1A00),
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RiderTripState? state = ref.watch(riderTripStateProvider).asData?.value;
    final DriverLocation? driverLocation = state?.currentDriverLocation;
    _driverName = state?.driverName ?? widget.driverName;
    _driverRating = state?.driverRating ?? widget.driverRating;
    _vehicleDescription = state?.vehicleDescription ?? widget.vehicleDescription;
    _licensePlate = state?.licensePlate ?? widget.licensePlate;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────
          Positioned.fill(
            child: KwellaMapView(driverLocation: driverLocation),
          ),
          // ── Driver info top card ───────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2C)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x50000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Back button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Driver avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF242424),
                          border: Border.all(
                            color: const Color(0xFFDFFF00),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _driverName.isNotEmpty
                                ? _driverName[0].toUpperCase()
                                : 'D',
                            style: const TextStyle(
                              color: Color(0xFFDFFF00),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name + vehicle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driverName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFDFFF00),
                                  size: 13,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$_driverRating  ·  $_licensePlate',
                                  style: const TextStyle(
                                    color: Color(0xFF808080),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Contact icons
                      Row(
                        children: [
                          _ContactIcon(
                            icon: Icons.chat_bubble_outline_rounded,
                            onTap: _showChatSheet,
                          ),
                          const SizedBox(width: 8),
                          _ContactIcon(
                            icon: Icons.phone_rounded,
                            onTap: () {
                              // TODO: launch tel:
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Bottom sheet ───────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3C3C3C),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ETA chip
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A00),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0x4DDFFF00)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    color: Color(0xFFDFFF00),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${widget.etaMinutes} min away',
                                    style: const TextStyle(
                                      color: Color(0xFFDFFF00),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              key: const Key('cancel_ride_button'),
                              onPressed: _showCancelDialog,
                              icon: const Icon(Icons.close_rounded,
                                  size: 16, color: Color(0xFFFF5370)),
                              label: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFFFF5370),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Vehicle info
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF242424),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.airport_shuttle_rounded,
                                color: Color(0xFFA0A0A0),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _vehicleDescription,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _licensePlate,
                                  style: const TextStyle(
                                    color: Color(0xFFA0A0A0),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Safety tools row
                        Row(
                          children: [
                            _SafetyChip(
                              icon: Icons.share_location_rounded,
                              label: 'Share Trip',
                              onTap: () {},
                            ),
                            const SizedBox(width: 10),
                            _SafetyChip(
                              icon: Icons.sos_rounded,
                              label: 'Emergency',
                              onTap: () {},
                              color: const Color(0xFFFF5370),
                            ),
                            const SizedBox(width: 10),
                            _SafetyChip(
                              icon: Icons.report_outlined,
                              label: 'Report',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ContactIcon extends StatelessWidget {
  const _ContactIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3C3C3C)),
        ),
        child: Icon(icon, color: const Color(0xFFA0A0A0), size: 20),
      ),
    );
  }
}

class _SafetyChip extends StatelessWidget {
  const _SafetyChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF606060),
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isDriver});

  final String message;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isDriver ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDriver
              ? const Color(0xFF242424)
              : const Color(0xFF1A1A00),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isDriver ? 4 : 16),
            bottomRight: Radius.circular(isDriver ? 16 : 4),
          ),
          border: isDriver
              ? Border.all(color: const Color(0xFF3C3C3C))
              : Border.all(color: const Color(0x4DDFFF00)),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isDriver ? Colors.white : const Color(0xFFDFFF00),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

