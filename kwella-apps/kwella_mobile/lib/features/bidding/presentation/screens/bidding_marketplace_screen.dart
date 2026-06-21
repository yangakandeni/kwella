import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bidding/models/active_ride_offer.dart';
import '../../../bidding/services/kwella_websocket_service.dart';
import '../../../location/presentation/controllers/kwella_telemetry_controller.dart';
import '../../models/bidding_state.dart';
import '../../providers/bidding_provider.dart';

/// A production-grade, responsive Flutter screen widget displaying the live bidding marketplace.
class BiddingMarketplaceScreen extends ConsumerStatefulWidget {
  const BiddingMarketplaceScreen({super.key});

  @override
  ConsumerState<BiddingMarketplaceScreen> createState() => _BiddingMarketplaceScreenState();
}

class _BiddingMarketplaceScreenState extends ConsumerState<BiddingMarketplaceScreen> {
  @override
  Widget build(BuildContext context) {
    final biddingState = ref.watch(biddingProvider);
    final telemetryState = ref.watch(telemetryControllerProvider);
    final telemetryController = ref.read(telemetryControllerProvider.notifier);

    ref.listen<TelemetryState>(telemetryControllerProvider, (previous, next) {
      if (next.lastNetEarnings != null) {
        showEarningsToast(context, next.lastNetEarnings!);
        telemetryController.clearLastNetEarnings();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Live Bidding Marketplace',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTelemetryPanel(context, telemetryState, telemetryController),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBodyForState(context, biddingState),
                  ),
                ),
              ],
            ),
            // Ride-offer overlay — rendered above the map / bid list.
            if (telemetryState.activeOffer != null)
              _buildRideOfferOverlay(
                context,
                telemetryState.activeOffer!,
                telemetryState.offerSecondsRemaining,
              ),
            // Geofence overlay — rendered on top of everything else.
            if (telemetryState.isWithinGeofenceRadius)
              _buildGeofenceOverlay(context, telemetryState, telemetryController),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyForState(BuildContext context, BiddingState state) {
    switch (state) {
      case BiddingStateInitial() || BiddingStateConnecting():
        return _buildConnectingLayout(context);
      case BiddingStateError(message: final errorMsg):
        return _buildErrorLayout(context, errorMsg);
      case BiddingStateActive(activeBids: final bids):
        return _buildActiveBidsLayout(context, bids);
    }
  }

  Widget _buildConnectingLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('connecting_state'),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connecting to Kwella live bidding marketplace...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorLayout(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('error_state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.error.withOpacity(0.5), width: 1.5),
          ),
          color: colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Connection Failure',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onErrorContainer.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveBidsLayout(BuildContext context, List<Map<String, dynamic>> bids) {
    if (bids.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        key: const ValueKey('active_empty_state'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.gavel_rounded,
              size: 64,
              color: colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No active bids at the moment',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for drivers to submit offers...',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('active_bids_list'),
      padding: const EdgeInsets.all(16.0),
      itemCount: bids.length,
      itemBuilder: (context, index) {
        final bid = bids[index];
        final driverId = bid['driverId']?.toString() ?? 'Unknown Driver';
        final amountValue = bid['amount'];
        final estimatedPickup = bid['estimatedPickup']?.toString() ?? '';

        // Formats the display of bid amounts nicely
        String amountText;
        if (amountValue is num) {
          amountText = '\$${amountValue.toStringAsFixed(2)}';
        } else if (amountValue is String && double.tryParse(amountValue) != null) {
          amountText = '\$${double.parse(amountValue).toStringAsFixed(2)}';
        } else {
          amountText = '\$$amountValue';
        }

        return Card(
          key: ValueKey('bid_card_$index'),
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_pin_circle_rounded, size: 20, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              driverId,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            estimatedPickup.isNotEmpty ? estimatedPickup : 'N/A pickup time',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    amountText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Accepted bid from $driverId for $amountText'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Accept Bid'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetryPanel(
    BuildContext context,
    TelemetryState state,
    KwellaTelemetryController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOnline = state.isTracking;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isOnline
              ? [Colors.teal.shade700, Colors.green.shade900]
              : [colorScheme.surfaceVariant, colorScheme.surfaceVariant.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (isOnline ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOnline ? 'DRIVER ACTIVE' : 'DRIVER INACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: isOnline ? Colors.teal.shade100 : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOnline ? 'Online & Streaming Location' : 'Offline — Tracking Paused',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.white : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.white.withOpacity(0.12) : colorScheme.outline.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 16,
                          color: isOnline ? Colors.greenAccent : colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Shift Earnings: ZAR ${state.dailyEarningsTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isOnline ? Colors.white : colorScheme.onSurfaceVariant,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOnline ? Colors.white : colorScheme.primary,
                foregroundColor: isOnline ? Colors.teal.shade900 : colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 2,
              ),
              onPressed: () {
                if (isOnline) {
                  controller.stopDriverTracking();
                } else {
                  controller.startDriverTracking(driverId: 'USR#drv-12345');
                }
              },
              child: Text(
                isOnline ? 'Go Offline' : 'Go Online',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ride Offer Overlay
  // ---------------------------------------------------------------------------

  Widget _buildRideOfferOverlay(
    BuildContext context,
    ActiveRideOffer offer,
    int secondsRemaining,
  ) {
    final progress = secondsRemaining / 15.0;
    final fareText =
        'R\${offer.baseFare.toStringAsFixed(2)}';

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(offer.tripId),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, (1 - value) * -80),
              child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
            );
          },
          child: Material(
            elevation: 14,
            borderRadius: BorderRadius.circular(20),
            shadowColor: Colors.black38,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0D1B2A),
                    const Color(0xFF1A3A5C),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Header row ----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_taxi_rounded,
                          color: Colors.blueAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'New Ride Offer',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      // ---- Countdown badge ----
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: secondsRemaining <= 5
                              ? Colors.redAccent.withOpacity(0.85)
                              : Colors.blueAccent.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: secondsRemaining <= 5
                                ? Colors.redAccent
                                : Colors.blueAccent.withOpacity(0.6),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${secondsRemaining}s',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: secondsRemaining <= 5
                                ? Colors.white
                                : Colors.blueAccent.shade100,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ---- Locations ----
                  _OfferLocationRow(
                    icon: Icons.trip_origin_rounded,
                    iconColor: const Color(0xFF4CAF50),
                    label: 'Pickup',
                    value: offer.pickupLocation,
                  ),
                  const SizedBox(height: 8),
                  _OfferLocationRow(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.redAccent,
                    label: 'Dropoff',
                    value: offer.dropoffLocation,
                  ),

                  const SizedBox(height: 14),

                  // ---- Fare + CTA row ----
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BASE FARE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white54,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fareText,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton(
                        key: const Key('accept_base_fare_button'),
                        onPressed: () => _acceptBaseFare(offer),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Accept Base Fare',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ---- Progress bar ----
                  _RideOfferCountdownBar(progress: progress),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dispatches a `sendBid` action payload to the cloud over the shared
  /// [KwellaWebSocketService] sink, accepting the server's base fare.
  void _acceptBaseFare(ActiveRideOffer offer) {
    final payload = jsonEncode({
      'action': 'sendBid',
      'tripId': offer.tripId,
      'amount': offer.baseFare.toStringAsFixed(2),
      'bidType': 'BASE_FARE_ACCEPT',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    debugPrint('[BiddingMarketplaceScreen] Dispatching sendBid: $payload');
    KwellaWebSocketService.instance.sink.add(payload);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Bid accepted for R${offer.baseFare.toStringAsFixed(2)}!'),
            ],
          ),
          backgroundColor: const Color(0xFF1565C0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Geofence Overlay (existing)
  // ---------------------------------------------------------------------------

  Widget _buildGeofenceOverlay(
    BuildContext context,
    TelemetryState state,
    KwellaTelemetryController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, (1 - value) * 100),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Card(
            elevation: 12,
            shadowColor: Colors.black45,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    colorScheme.errorContainer.withOpacity(0.95),
                    colorScheme.onErrorContainer.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const _PulsingGeofenceIndicator(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destination Arrived',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.error,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Within 50m geofence. Please confirm arrival.',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SlideToConfirmButton(
                    onConfirm: () async {
                      await controller.confirmArrival(
                        driverId: 'USR#drv-12345',
                        tripId: 'trip-arrived-123',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle, color: colorScheme.onPrimary),
                                const SizedBox(width: 8),
                                const Text('Arrival confirmed & dispatched successfully!'),
                              ],
                            ),
                            backgroundColor: Colors.green.shade600,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingGeofenceIndicator extends StatefulWidget {
  const _PulsingGeofenceIndicator();

  @override
  State<_PulsingGeofenceIndicator> createState() => _PulsingGeofenceIndicatorState();
}

class _PulsingGeofenceIndicatorState extends State<_PulsingGeofenceIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.error.withOpacity(0.2 * (1 - _pulseController.value)),
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.8 * (1 - _pulseController.value)),
                  width: 3 * _pulseController.value,
                ),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.error,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.error.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: colorScheme.onError,
                size: 20,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SlideToConfirmButton extends StatefulWidget {
  final VoidCallback onConfirm;

  const _SlideToConfirmButton({required this.onConfirm});

  @override
  State<_SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<_SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;

  final double _knobSize = 48.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _springAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDistance) {
    if (_springController.isAnimating) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, maxDistance);
    });
  }

  void _onDragEnd(DragEndDetails details, double maxDistance) {
    if (_dragOffset >= maxDistance * 0.85) {
      setState(() {
        _dragOffset = maxDistance;
      });
      widget.onConfirm();
    } else {
      _springAnimation = Tween<double>(
        begin: _dragOffset,
        end: 0.0,
      ).animate(
        CurvedAnimation(parent: _springController, curve: Curves.easeOut),
      );
      _springController.forward(from: 0.0).then((_) {
        setState(() {
          _dragOffset = 0.0;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDistance = trackWidth - _knobSize - 8.0;

        final currentOffset = _springController.isAnimating
            ? _springAnimation.value
            : _dragOffset;

        final opacityVal = (1.0 - (currentOffset / maxDistance)).clamp(0.0, 1.0);

        return Container(
          width: trackWidth,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Opacity(
                  opacity: opacityVal,
                  child: Text(
                    'Slide to Confirm Arrival',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: currentOffset + 4.0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onDragUpdate(details, maxDistance),
                  onHorizontalDragEnd: (details) => _onDragEnd(details, maxDistance),
                  child: Container(
                    width: _knobSize,
                    height: _knobSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Ride-Offer helper widgets
// ---------------------------------------------------------------------------

/// A single location row (pickup or dropoff) inside the ride-offer card.
class _OfferLocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _OfferLocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 0.9,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An animated linear progress bar mapping the remaining countdown [0.0–1.0]
/// to a coloured fill that transitions from blue → amber → red as time runs out.
class _RideOfferCountdownBar extends StatelessWidget {
  final double progress; // 1.0 = full time, 0.0 = expired

  const _RideOfferCountdownBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final Color barColor = progress > 0.5
        ? const Color(0xFF1E88E5)
        : progress > 0.25
            ? Colors.amber.shade600
            : Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OFFER EXPIRES IN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: progress + (1 / 15), end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Earnings Toast Floating Overlay
// ---------------------------------------------------------------------------

/// Inserts a global animated [EarningsToast] overlay at the top of the screen.
void showEarningsToast(BuildContext context, double netEarnings) {
  final overlayState = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: EarningsToast(
          netEarnings: netEarnings,
          onDismiss: () {
            overlayEntry.remove();
          },
        ),
      ),
    ),
  );

  overlayState.insert(overlayEntry);
}

/// A premium animated floating toast displaying the driver's earnings upon
/// successful trip settlement.
class EarningsToast extends StatefulWidget {
  final double netEarnings;
  final VoidCallback onDismiss;

  const EarningsToast({
    super.key,
    required this.netEarnings,
    required this.onDismiss,
  });

  @override
  State<EarningsToast> createState() => _EarningsToastState();
}

class _EarningsToastState extends State<EarningsToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();

    // Auto-dismiss the toast after 4 seconds of display.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0F2027),
                  const Color(0xFF203A43),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: Colors.teal.withOpacity(0.35),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trip Completed!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'You earned ZAR ${widget.netEarnings.toStringAsFixed(2)}!',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
