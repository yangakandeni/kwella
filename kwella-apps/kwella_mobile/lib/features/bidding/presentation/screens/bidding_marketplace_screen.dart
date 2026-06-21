import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
