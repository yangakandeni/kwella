import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/destination_editor_panel.dart';
import '../../../location/services/places_autocomplete_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DestinationSelectionScreen — full-screen route wrapper around
// DestinationEditorPanel, kept for deep-linking / back-navigation contexts.
// The primary rider flow now expands the same panel inline from the booking
// card (see RiderBookingScreen) instead of pushing this route.
// ─────────────────────────────────────────────────────────────────────────────

class DestinationSelectionScreen extends ConsumerStatefulWidget {
  const DestinationSelectionScreen({
    super.key,
    this.controller,
    this.placesService,
    this.initialDropoff,
  });

  final KwellaRiderController? controller;
  final PlacesAutocompleteService? placesService;
  final String? initialDropoff;

  @override
  ConsumerState<DestinationSelectionScreen> createState() =>
      _DestinationSelectionScreenState();
}

class _DestinationSelectionScreenState
    extends ConsumerState<DestinationSelectionScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialDropoff != null) {
      final KwellaRiderController controller =
          widget.controller ?? ref.read(kwellaRiderControllerProvider);
      controller.updateDropoffLocation(widget.initialDropoff!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller != null) {
      final controller = widget.controller!;
      return StreamBuilder<RiderTripState>(
        stream: controller.stateStream,
        initialData: controller.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? controller.state;
          return _buildScaffold(controller, state);
        },
      );
    }

    final controller = ref.watch(kwellaRiderControllerProvider);
    final stateAsync = ref.watch(riderTripStateProvider);
    final RiderTripState state = stateAsync.asData?.value ?? controller.state;
    return _buildScaffold(controller, state);
  }

  Widget _buildScaffold(KwellaRiderController controller, RiderTripState state) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          // DestinationEditorPanel is a fixed-height widget that scrolls its
          // own suggestions list internally — this outer view existed only
          // as an overflow safety net, and letting it scroll too fights the
          // suggestions list for drag gestures.
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: DestinationEditorPanel(
            controller: controller,
            state: state,
            onClose: () => Navigator.pop(context),
            placesService: widget.placesService,
          ),
        ),
      ),
    );
  }
}
