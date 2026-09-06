import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bidding/models/active_ride_offer.dart';
import '../../../location/presentation/controllers/kwella_telemetry_controller.dart';
import '../../models/bidding_state.dart';
import '../../providers/bidding_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BiddingMarketplaceScreen — v2 Electric Lime Dark Mode
//
// ALL existing state machine logic, WebSocket dispatch, geofence overlay,
// EarningsToast, and SlideToConfirm button are preserved exactly.
// Only the visual layer has been updated to the #121212 / #DFFF00 spec.
// ─────────────────────────────────────────────────────────────────────────────

class BiddingMarketplaceScreen extends ConsumerStatefulWidget {
  const BiddingMarketplaceScreen({super.key});

  @override
  ConsumerState<BiddingMarketplaceScreen> createState() =>
      _BiddingMarketplaceScreenState();
}

class _BiddingMarketplaceScreenState
    extends ConsumerState<BiddingMarketplaceScreen> {
  String? _submittingBidType;

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
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTelemetryPanel(context, telemetryState, telemetryController),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBodyForState(context, biddingState, telemetryState),
                  ),
                ),
              ],
            ),
            // Ride-offer overlay
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: telemetryState.activeOffer != null
                  ? _buildRideOfferOverlay(
                      context,
                      telemetryState.activeOffer!,
                      telemetryState.offerSecondsRemaining,
                    )
                  : const SizedBox.shrink(key: ValueKey('no_offer_overlay')),
            ),
            // Geofence overlay
            if (telemetryState.isWithinGeofenceRadius)
              _buildGeofenceOverlay(context, telemetryState, telemetryController),
          ],
        ),
      ),
    );
  }

  // ── Body state switcher ─────────────────────────────────────────────────────

  Widget _buildBodyForState(
      BuildContext context, BiddingState state, TelemetryState tel) {
    switch (state) {
      case BiddingStateInitial():
        if (tel.isTracking) {
          return _buildConnectingLayout(context);
        }
        return _buildOfflineLayout(context, tel);
      case BiddingStateConnecting():
        return _buildConnectingLayout(context);
      case BiddingStateError(message: final errorMsg):
        return _buildErrorLayout(context, errorMsg);
      case BiddingStateActive(activeBids: final bids):
        return _buildOnlineMapLayout(context, bids);
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
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDFFF00)),
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

  // ── Offline "GO" puck layout ────────────────────────────────────────────────

  Widget _buildOfflineLayout(BuildContext context, TelemetryState tel) {
    final isOnline = tel.isTracking;
    return Container(
      key: const ValueKey('offline_layout'),
      color: const Color(0xFF0E1217),
      child: Stack(
        children: [
          CustomPaint(
            painter: _DarkGridPainter(),
            size: Size.infinite,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // GO puck
                GestureDetector(
                  onTap: () {
                    final ctrl =
                        ref.read(telemetryControllerProvider.notifier);
                    if (isOnline) {
                      ctrl.stopDriverTracking();
                    } else {
                      ctrl.startDriverTracking(driverId: 'USR#drv-12345');
                      ref.read(biddingProvider.notifier).connectAndSubscribe();
                    }
                  },
                  child: AnimatedContainer(
                    key: const Key('go_puck'),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    width: isOnline ? 140 : 160,
                    height: isOnline ? 140 : 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFDFFF00),
                      boxShadow: [
                        BoxShadow(
                          color: isOnline
                              ? Colors.transparent
                              : const Color(0x60DFFF00),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                      border: Border.all(
                        color: isOnline
                            ? const Color(0xFF2C2C2C)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        isOnline ? 'GO\nOFFLINE' : 'GO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isOnline
                              ? const Color(0xFFA0A0A0)
                              : const Color(0xFF1A1A00),
                          fontSize: isOnline ? 20 : 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: isOnline ? 1.5 : -1.0,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isOnline ? 'You are online' : 'You are offline',
                  style: TextStyle(
                    color: isOnline
                        ? const Color(0xFF69FF47)
                        : const Color(0xFFA0A0A0),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isOnline
                      ? 'Searching for trip requests…'
                      : 'Tap GO to start receiving trip requests',
                  style: const TextStyle(
                    color: Color(0xFF606060),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Online map layout (bids list) ───────────────────────────────────────────

  Widget _buildOnlineMapLayout(
      BuildContext context, List<Map<String, dynamic>> bids) {
    if (bids.isEmpty) {
      return Container(
        key: const ValueKey('active_empty_state'),
        color: const Color(0xFF0E1217),
        child: Stack(
          children: [
            CustomPaint(painter: _DarkGridPainter(), size: Size.infinite),
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.radar_rounded,
                    color: Color(0xFF2C2C2C),
                    size: 64,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Listening for trip requests…',
                    style: TextStyle(
                      color: Color(0xFF606060),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('active_bids_list'),
      padding: const EdgeInsets.all(16),
      itemCount: bids.length,
      itemBuilder: (context, index) {
        final bid = bids[index];
        final driverId = bid['driverId']?.toString() ?? 'Unknown';
        final amountValue = bid['amount'];
        String amountText;
        if (amountValue is num) {
          amountText = '\$${amountValue.toStringAsFixed(2)}';
        } else if (amountValue is String &&
            double.tryParse(amountValue) != null) {
          amountText = '\$${double.parse(amountValue).toStringAsFixed(2)}';
        } else {
          amountText = '\$$amountValue';
        }

        return Container(
          key: ValueKey('bid_card_$index'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bid['estimatedPickup']?.toString() ?? 'N/A',
                      style: const TextStyle(
                        color: Color(0xFF808080),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                amountText,
                style: const TextStyle(
                  color: Color(0xFFDFFF00),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Accepted bid from $driverId for $amountText'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDFFF00),
                  foregroundColor: const Color(0xFF1A1A00),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: const Size(0, 40),
                  elevation: 0,
                ),
                child: const Text(
                  'Accept Bid',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Error layout ────────────────────────────────────────────────────────────

  Widget _buildErrorLayout(BuildContext context, String message) {
    return Center(
      key: const ValueKey('error_state'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF5370).withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF5370), size: 52),
              const SizedBox(height: 16),
              const Text(
                'Connection Failure',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Telemetry panel (top earnings bar) ─────────────────────────────────────

  Widget _buildTelemetryPanel(
    BuildContext context,
    TelemetryState state,
    KwellaTelemetryController controller,
  ) {
    final isOnline = state.isTracking;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline
              ? const Color(0x4DDFFF00)
              : const Color(0xFF2C2C2C),
        ),
      ),
      child: Row(
        children: [
          // Online indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline
                  ? const Color(0xFF69FF47)
                  : const Color(0xFF606060),
              boxShadow: isOnline
                  ? const [
                      BoxShadow(
                        color: Color(0x6069FF47),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: isOnline
                        ? const Color(0xFF69FF47)
                        : const Color(0xFF606060),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFFDFFF00),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'ZAR ${state.dailyEarningsTotal.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'today',
                      style: TextStyle(
                        color: Color(0xFF606060),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Go online / offline button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isOnline
                  ? const Color(0xFF242424)
                  : const Color(0xFFDFFF00),
              foregroundColor: isOnline
                  ? const Color(0xFFA0A0A0)
                  : const Color(0xFF1A1A00),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 40),
              elevation: 0,
              side: isOnline
                  ? const BorderSide(color: Color(0xFF3C3C3C))
                  : BorderSide.none,
            ),
            onPressed: () {
              if (isOnline) {
                controller.stopDriverTracking();
              } else {
                controller.startDriverTracking(driverId: 'USR#drv-12345');
                ref.read(biddingProvider.notifier).connectAndSubscribe();
              }
            },
            child: Text(
              isOnline ? 'Go Offline' : 'Go Online',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ride offer overlay ──────────────────────────────────────────────────────

  Widget _buildRideOfferOverlay(
    BuildContext context,
    ActiveRideOffer offer,
    int secondsRemaining,
  ) {
    final progress = secondsRemaining / 15.0;
    final fareText = 'R${offer.baseFare.toStringAsFixed(0)}';

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(offer.tripId),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, (1 - value) * 80),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x4DDFFF00)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40DFFF00),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A1A00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_taxi_rounded,
                        color: Color(0xFFDFFF00),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'New Trip Request',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // Countdown badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: secondsRemaining <= 5
                            ? const Color(0xFFFF5370).withOpacity(0.2)
                            : const Color(0xFF1A1A00),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: secondsRemaining <= 5
                              ? const Color(0xFFFF5370)
                              : const Color(0xFFDFFF00),
                        ),
                      ),
                      child: Text(
                        '${secondsRemaining}s',
                        style: TextStyle(
                          color: secondsRemaining <= 5
                              ? const Color(0xFFFF5370)
                              : const Color(0xFFDFFF00),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Locations
                _OfferLocationRow(
                  icon: Icons.trip_origin_rounded,
                  iconColor: const Color(0xFFDFFF00),
                  label: 'Pickup',
                  value: offer.pickupLocation,
                ),
                const SizedBox(height: 8),
                _OfferLocationRow(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFFFF5370),
                  label: 'Dropoff',
                  value: offer.dropoffLocation,
                ),
                const SizedBox(height: 14),
                // Fare
                Row(
                  children: [
                    const Text(
                      'BASE FARE',
                      style: TextStyle(
                        color: Color(0xFF606060),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      fareText,
                      style: const TextStyle(
                        color: Color(0xFFDFFF00),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Quick counter-bid row
                Row(
                  children: [
                    Expanded(
                      child: _buildBidButton(
                        key: const Key('bid_accept_base'),
                        label: 'Accept',
                        amount: offer.baseFare,
                        bidType: 'base',
                        backgroundColor: const Color(0xFFDFFF00),
                        foregroundColor: const Color(0xFF1A1A00),
                        offer: offer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBidButton(
                        key: const Key('bid_counter_r15'),
                        label: '+R15',
                        amount: offer.baseFare + 15,
                        bidType: 'r15',
                        backgroundColor: const Color(0xFF1E1E1E),
                        foregroundColor: const Color(0xFFDFFF00),
                        borderColor: const Color(0x4DDFFF00),
                        offer: offer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBidButton(
                        key: const Key('bid_counter_r30'),
                        label: '+R30',
                        amount: offer.baseFare + 30,
                        bidType: 'r30',
                        backgroundColor: const Color(0xFF1E1E1E),
                        foregroundColor: const Color(0xFFDFFF00),
                        borderColor: const Color(0x4DDFFF00),
                        offer: offer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                _RideOfferCountdownBar(progress: progress),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bid button builder ──────────────────────────────────────────────────────

  Widget _buildBidButton({
    required Key key,
    required String label,
    required double amount,
    required String bidType,
    required Color backgroundColor,
    required Color foregroundColor,
    Color? borderColor,
    required ActiveRideOffer offer,
  }) {
    final isThisSubmitting = _submittingBidType == bidType;
    final anySubmitting = _submittingBidType != null;

    return ElevatedButton(
      key: key,
      onPressed: anySubmitting
          ? null
          : () => _submitBid(offer: offer, bidType: bidType, bidAmount: amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: isThisSubmitting
            ? backgroundColor.withOpacity(0.5)
            : backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: backgroundColor.withOpacity(0.3),
        disabledForegroundColor: foregroundColor.withOpacity(0.4),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: borderColor != null
              ? BorderSide(color: borderColor)
              : BorderSide.none,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isThisSubmitting
            ? SizedBox(
                key: const ValueKey('loading'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Column(
                key: ValueKey('bid_label_$bidType'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'R${amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _submitBid({
    required ActiveRideOffer offer,
    required String bidType,
    required double bidAmount,
  }) async {
    if (_submittingBidType != null) return;
    setState(() => _submittingBidType = bidType);
    try {
      final controller = ref.read(telemetryControllerProvider.notifier);
      await controller.submitBid(
        driverId: 'USR#drv-12345',
        tripId: offer.tripId,
        bidAmount: bidAmount,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF1A1A00), size: 20),
                const SizedBox(width: 8),
                Text('Bid submitted: R${bidAmount.toStringAsFixed(0)}'),
              ],
            ),
            backgroundColor: const Color(0xFFDFFF00),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingBidType = null);
    }
  }

  // ── Geofence overlay (preserved, re-skinned) ────────────────────────────────

  Widget _buildGeofenceOverlay(
    BuildContext context,
    TelemetryState state,
    KwellaTelemetryController controller,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, (1 - value) * 100),
            child: Opacity(opacity: value, child: child),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x4DDFFF00)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40DFFF00),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const _PulsingGeofenceIndicator(),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Destination Reached',
                            style: TextStyle(
                              color: Color(0xFFDFFF00),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Within 50m geofence. Confirm arrival.',
                            style: TextStyle(
                              color: Color(0xFFA0A0A0),
                              fontSize: 13,
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
                    await controller.driverArrived(driverId: 'USR#drv-12345');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF1A1A00), size: 20),
                              SizedBox(width: 8),
                              Text('Arrival confirmed successfully!'),
                            ],
                          ),
                          backgroundColor: const Color(0xFFDFFF00),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                      Navigator.of(context).pushNamed('/driver/navigation');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PulsingGeofenceIndicator (preserved, re-skinned to Electric Lime)
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingGeofenceIndicator extends StatefulWidget {
  const _PulsingGeofenceIndicator();

  @override
  State<_PulsingGeofenceIndicator> createState() =>
      _PulsingGeofenceIndicatorState();
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
                color: const Color(0xFFDFFF00).withOpacity(
                  0.15 * (1 - _pulseController.value),
                ),
                border: Border.all(
                  color: const Color(0xFFDFFF00).withOpacity(
                    0.6 * (1 - _pulseController.value),
                  ),
                  width: 3 * _pulseController.value,
                ),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDFFF00),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x60DFFF00),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF1A1A00),
                size: 20,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SlideToConfirmButton (preserved, re-skinned to Electric Lime)
// ─────────────────────────────────────────────────────────────────────────────

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
      _dragOffset =
          (_dragOffset + details.delta.dx).clamp(0.0, maxDistance);
    });
  }

  void _onDragEnd(DragEndDetails details, double maxDistance) {
    if (_dragOffset >= maxDistance * 0.85) {
      setState(() => _dragOffset = maxDistance);
      widget.onConfirm();
    } else {
      _springAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
        CurvedAnimation(
            parent: _springController, curve: Curves.easeOut),
      );
      _springController.forward(from: 0.0).then((_) {
        setState(() => _dragOffset = 0.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDistance = trackWidth - _knobSize - 8.0;
        final currentOffset =
            _springController.isAnimating ? _springAnimation.value : _dragOffset;
        final opacityVal =
            (1.0 - (currentOffset / maxDistance)).clamp(0.0, 1.0);

        return Container(
          width: trackWidth,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF3C3C3C)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Opacity(
                  opacity: opacityVal,
                  child: const Text(
                    'Slide to Confirm Arrival',
                    style: TextStyle(
                      color: Color(0xFF808080),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: currentOffset + 4.0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) =>
                      _onDragUpdate(d, maxDistance),
                  onHorizontalDragEnd: (d) => _onDragEnd(d, maxDistance),
                  child: Container(
                    width: _knobSize,
                    height: _knobSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFDFFF00),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x60DFFF00),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF1A1A00),
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

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets (preserved exactly, type-safe)
// ─────────────────────────────────────────────────────────────────────────────

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
                  color: Color(0xFF606060),
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

class _RideOfferCountdownBar extends StatelessWidget {
  final double progress;
  const _RideOfferCountdownBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final Color barColor = progress > 0.5
        ? const Color(0xFFDFFF00)
        : progress > 0.25
            ? const Color(0xFFFFAB40)
            : const Color(0xFFFF5370);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OFFER EXPIRES IN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF606060),
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
                begin: progress + (1 / 15), end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFF2C2C2C),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EarningsToast (preserved, re-skinned to Electric Lime)
// ─────────────────────────────────────────────────────────────────────────────

void showEarningsToast(BuildContext context, double netEarnings) {
  final overlayState = Overlay.of(context);
  late OverlayEntry overlayEntry;
  overlayEntry = OverlayEntry(
    builder: (context) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: EarningsToast(
          netEarnings: netEarnings,
          onDismiss: () => overlayEntry.remove(),
        ),
      ),
    ),
  );
  overlayState.insert(overlayEntry);
}

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

class _EarningsToastState extends State<EarningsToast>
    with SingleTickerProviderStateMixin {
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
        parent: _controller, curve: Curves.easeOutBack));
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
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
    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x4DDFFF00)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40DFFF00),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFDFFF00),
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
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'You earned ZAR ${widget.netEarnings.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFFDFFF00),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// Dark grid painter for map placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _DarkGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1E24)
      ..strokeWidth = 1.0;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
