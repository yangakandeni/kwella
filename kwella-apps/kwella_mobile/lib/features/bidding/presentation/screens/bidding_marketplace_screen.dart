import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildBodyForState(context, biddingState),
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
}
