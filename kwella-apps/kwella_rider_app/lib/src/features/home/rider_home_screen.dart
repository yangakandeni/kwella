import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';

import '../bidding/bidding_provider.dart';
import '../tracking/driver_tracking_notifier.dart';

// ---------------------------------------------------------------------------
// Rider Home screen – Phase 2: Booking layout shell
// ---------------------------------------------------------------------------

/// Full-screen booking layout.
///
/// Layout contract:
/// ┌──────────────────────────────────┐
/// │                                  │  ← ~60 % of screen height
/// │   Map placeholder (grey tint)    │
/// │                                  │
/// ├──────────────────────────────────┤
/// │ ╭──────────────────────────────╮ │  ← persistent bottom sheet
/// │ │  Drag handle                 │ │
/// │ │  ─────────────────────────── │ │
/// │ │  Destination input placeholder│ │
/// │ │  ─────────────────────────── │ │
/// │ │  Passenger count selector    │ │
/// │ ╰──────────────────────────────╯ │
/// └──────────────────────────────────┘
class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  int _passengerCount = 1;
  String? _selectedBidId;

  @override
  Widget build(BuildContext context) {
    final biddingState = ref.watch(riderBiddingProvider);
    final bids = biddingState.bids;
    final biddingStatus = biddingState.status;

    // Listen reactively to accepted bid and display success Snackbar.
    ref.listen<RiderBiddingState>(riderBiddingProvider, (previous, next) {
      if (next.status == BiddingStatus.tripConfirmed && next.acceptedBid != null) {
        final driverName = next.acceptedBid!.driverName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ride accepted! Driver $driverName is on their way.',
              style: const TextStyle(
                color: KwellaColors.deepSlate,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: KwellaColors.cataTransitGreen,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _selectedBidId = null;
        });
        ref.read(riderBiddingProvider.notifier).reset();
      }
    });

    final showBids = biddingStatus == BiddingStatus.searching ||
        biddingStatus == BiddingStatus.activeBids;

    return Scaffold(
      backgroundColor: KwellaColors.communityCream,
      body: _BookingShellLayout(
        showBids: showBids,
        biddingStatus: biddingStatus,
        onCancelBids: () {
          ref.read(riderBiddingProvider.notifier).cancelBroadcast();
          setState(() {
            _selectedBidId = null;
          });
        },
        bidsCarousel: biddingStatus == BiddingStatus.searching
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          KwellaColors.cataTransitGreen,
                        ),
                        strokeWidth: 2.5,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Searching for nearby drivers...',
                        style: TextStyle(
                          color: KwellaColors.textOnLightMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : DriverBidCarousel(
                bids: bids,
                selectedBidId: _selectedBidId,
                onSelected: (bidId) {
                  setState(() {
                    _selectedBidId = bidId;
                  });
                },
              ),
        acceptButton: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            key: const Key('rider_accept_ride_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: KwellaColors.cataTransitGreen,
              foregroundColor: KwellaColors.deepSlate,
              disabledBackgroundColor:
                  KwellaColors.cataTransitGreen.withValues(alpha: 0.4),
              disabledForegroundColor:
                  KwellaColors.deepSlate.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: _selectedBidId != null
                ? () {
                    ref
                        .read(riderBiddingProvider.notifier)
                        .acceptBid(_selectedBidId!);
                  }
                : null,
            child: const Text('Accept Ride'),
          ),
        ),
        mapSection: _RiderMap(
          onSignOut: () =>
              ref.read(kwellaAuthNotifierProvider.notifier).signOut(),
        ),
        sheetContent: _BookingSheetContent(
          passengerCount: _passengerCount,
          onPassengerCountChanged: (v) => setState(() => _passengerCount = v),
          onDestinationTapped: () {
            setState(() {
              _selectedBidId = null;
            });
            ref.read(riderBiddingProvider.notifier).startBroadcast();
          },
        ),
      ),
    );
  }
}

/// Positions the map and the bottom sheet using a [Stack].
class _BookingShellLayout extends StatelessWidget {
  const _BookingShellLayout({
    required this.mapSection,
    required this.sheetContent,
    required this.showBids,
    required this.bidsCarousel,
    required this.acceptButton,
    required this.onCancelBids,
    required this.biddingStatus,
  });

  final Widget mapSection;
  final Widget sheetContent;
  final bool showBids;
  final Widget bidsCarousel;
  final Widget acceptButton;
  final VoidCallback onCancelBids;
  final BiddingStatus biddingStatus;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Map region (60 % of screen) ───────────────────────────────
        Positioned.fill(
          child: Column(
            children: [
              Expanded(flex: 60, child: mapSection),
              // Reserve space so content isn't hidden beneath the sheet.
              // The sheet itself floats above this via the Stack.
              const Expanded(flex: 40, child: SizedBox()),
            ],
          ),
        ),

        // ── Floating overlay right above the sheet ─────────────────────
        if (showBids)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).size.height * 0.42 + 12,
            child: Card(
              color: KwellaColors.communityCream,
              elevation: 10,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: KwellaColors.creamBorder, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              biddingStatus == BiddingStatus.searching
                                  ? Icons.sensors_rounded
                                  : Icons.bolt_rounded,
                              color: KwellaColors.cataTransitGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              biddingStatus == BiddingStatus.searching
                                  ? 'Broadcasting Request...'
                                  : 'Live Driver Bids',
                              style: const TextStyle(
                                color: KwellaColors.textOnLight,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(100),
                            onTap: onCancelBids,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: KwellaColors.textOnLightMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    bidsCarousel,
                    const SizedBox(height: 16),
                    acceptButton,
                  ],
                ),
              ),
            ),
          ),

        // ── Persistent bottom sheet (40 % of screen) ──────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.42, // slightly taller to account for safe area
            widthFactor: 1.0,
            child: _RiderBottomSheet(child: sheetContent),
          ),
        ),
      ],
    );
  }
}

/// Live Google Map with a driver marker layer and a sign-out FAB in the
/// top-right corner.
///
/// Watches [driverTrackingProvider] and renders a rotated driver marker
/// once a live telematics fix arrives. The initial camera centres on the
/// session's anchor fix (the first position received this session); once
/// that anchor arrives, the camera animates to it.
class _RiderMap extends ConsumerStatefulWidget {
  const _RiderMap({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  ConsumerState<_RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends ConsumerState<_RiderMap> {
  // Fallback centre used until a live driver fix anchors the session.
  static const LatLng _fallbackCenter = LatLng(-33.9249, 18.4241);
  static const String _driverMarkerId = 'driver';

  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(driverTrackingProvider);

    ref.listen<DriverTrackingState>(driverTrackingProvider, (previous, next) {
      final justAnchored = previous?.anchorLatitude == null &&
          next.anchorLatitude != null &&
          next.anchorLongitude != null;
      if (justAnchored) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(next.anchorLatitude!, next.anchorLongitude!),
          ),
        );
      }
    });

    final initialCenter =
        tracking.anchorLatitude != null && tracking.anchorLongitude != null
            ? LatLng(tracking.anchorLatitude!, tracking.anchorLongitude!)
            : _fallbackCenter;

    final markers = <Marker>{
      if (tracking.isActive)
        Marker(
          markerId: const MarkerId(_driverMarkerId),
          position: LatLng(tracking.latitude, tracking.longitude),
          rotation: tracking.bearing,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
    };

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCenter,
            zoom: 15,
          ),
          markers: markers,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) => _mapController = controller,
        ),

        // ── Sign-out button (top-right) ───────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: Material(
            color: KwellaColors.communityCream,
            borderRadius: BorderRadius.circular(12),
            elevation: 3,
            shadowColor: Colors.black12,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onSignOut,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: KwellaColors.textOnLight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Community Cream container with rounded top corners that holds the
/// booking controls.
class _RiderBottomSheet extends StatelessWidget {
  const _RiderBottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KwellaColors.communityCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Booking controls rendered inside the bottom sheet.
class _BookingSheetContent extends StatelessWidget {
  const _BookingSheetContent({
    required this.passengerCount,
    required this.onPassengerCountChanged,
    required this.onDestinationTapped,
  });

  final int passengerCount;
  final ValueChanged<int> onPassengerCountChanged;
  final VoidCallback onDestinationTapped;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KwellaColors.creamBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Section label ────────────────────────────────────────────
            const Text(
              'Where to?',
              style: TextStyle(
                color: KwellaColors.textOnLight,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),

            // ── Destination input placeholder ────────────────────────────
            _DestinationInputPlaceholder(onTap: onDestinationTapped),
            const SizedBox(height: 16),

            // ── Divider ──────────────────────────────────────────────────
            const Divider(
              color: KwellaColors.creamBorder,
              height: 1,
            ),
            const SizedBox(height: 16),

            // ── Passenger count selector ─────────────────────────────────
            _PassengerSelector(
              count: passengerCount,
              onChanged: onPassengerCountChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable destination input placeholder.
class _DestinationInputPlaceholder extends StatelessWidget {
  const _DestinationInputPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KwellaColors.creamCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('rider_destination_field'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KwellaColors.creamBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KwellaColors.cataTransitGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: KwellaColors.cataTransitGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enter destination…',
                  style: TextStyle(
                    color: KwellaColors.textOnLightMuted,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: KwellaColors.textOnLightMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline passenger count stepper (− count +).
class _PassengerSelector extends StatelessWidget {
  const _PassengerSelector({
    required this.count,
    required this.onChanged,
  });

  final int count;
  final ValueChanged<int> onChanged;

  static const int _min = 1;
  static const int _max = 6;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Label side ────────────────────────────────────────────────
        const Icon(
          Icons.people_outline_rounded,
          color: KwellaColors.textOnLightMuted,
          size: 22,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Passengers',
            style: TextStyle(
              color: KwellaColors.textOnLight,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // ── Stepper controls ─────────────────────────────────────────
        _StepperButton(
          key: const Key('rider_passenger_decrement'),
          icon: Icons.remove_rounded,
          enabled: count > _min,
          onPressed: () => onChanged(count - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '$count',
            style: const TextStyle(
              color: KwellaColors.textOnLight,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _StepperButton(
          key: const Key('rider_passenger_increment'),
          icon: Icons.add_rounded,
          enabled: count < _max,
          onPressed: () => onChanged(count + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: KwellaColors.cataTransitGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: KwellaColors.cataTransitGreen,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Bid Components
// ---------------------------------------------------------------------------

class DriverBidCard extends StatelessWidget {
  final DriverBid bid;
  final bool isSelected;
  final VoidCallback onTap;

  const DriverBidCard({
    super.key,
    required this.bid,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 250,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KwellaColors.creamCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? KwellaColors.cataTransitGreen
                  : KwellaColors.creamBorder,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: KwellaColors.cataTransitGreen.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Row(
            children: [
              // Avatar placeholder circle
              CircleAvatar(
                radius: 22,
                backgroundColor: KwellaColors.creamBorder,
                child: Text(
                  _getInitials(bid.driverName),
                  style: const TextStyle(
                    color: KwellaColors.deepSlate,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      bid.driverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KwellaColors.textOnLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: KwellaColors.warningAmber,
                          size: 16,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          bid.rating,
                          style: const TextStyle(
                            color: KwellaColors.textOnLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          bid.eta,
                          style: const TextStyle(
                            color: KwellaColors.textOnLightMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Pricing pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KwellaColors.deepSlate,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  bid.price,
                  style: const TextStyle(
                    color: KwellaColors.communityCream,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class DriverBidCarousel extends StatelessWidget {
  final List<DriverBid> bids;
  final String? selectedBidId;
  final ValueChanged<String> onSelected;

  const DriverBidCarousel({
    super.key,
    required this.bids,
    required this.selectedBidId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: bids.length,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemBuilder: (context, index) {
          final bid = bids[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index == bids.length - 1 ? 0 : 12,
            ),
            child: DriverBidCard(
              bid: bid,
              isSelected: bid.id == selectedBidId,
              onTap: () => onSelected(bid.id),
            ),
          );
        },
      ),
    );
  }
}
