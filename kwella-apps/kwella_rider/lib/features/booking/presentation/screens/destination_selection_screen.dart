import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/location_input_field.dart';
import '../widgets/passenger_stepper.dart';
import '../../../location/services/places_autocomplete_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DestinationSelectionScreen — dedicated screen for choosing pickup/dropoff
// and passenger count, replacing the old inline booking-sheet expansion.
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
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final PlacesAutocompleteService _placesService;

  List<PlaceSuggestion> _suggestions = const [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _placesService = widget.placesService ?? PlacesAutocompleteService();

    final KwellaRiderController controller =
        widget.controller ?? ref.read(kwellaRiderControllerProvider);
    _fromController = TextEditingController(text: controller.state.pickupLocation);
    _toController = TextEditingController(
      text: widget.initialDropoff ?? controller.state.dropoffLocation,
    );
    if (widget.initialDropoff != null) {
      controller.updateDropoffLocation(widget.initialDropoff!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _onDropoffChanged(KwellaRiderController controller, String value) {
    controller.updateDropoffLocation(value);
    _debounceTimer?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounceTimer = Timer(_debounceDelay, () async {
      final List<PlaceSuggestion> results =
          await _placesService.searchPlaces(value);
      if (!mounted) return;
      setState(() => _suggestions = results);
    });
  }

  void _selectSuggestion(KwellaRiderController controller, PlaceSuggestion suggestion) {
    _toController.text = suggestion.description;
    controller.updateDropoffLocation(suggestion.description);
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = const []);
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
          return _buildContent(context, controller, state);
        },
      );
    }

    final controller = ref.watch(kwellaRiderControllerProvider);
    final stateAsync = ref.watch(riderTripStateProvider);
    final RiderTripState state = stateAsync.asData?.value ?? controller.state;
    return _buildContent(context, controller, state);
  }

  Widget _buildContent(
    BuildContext context,
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    if (_fromController.text != state.pickupLocation) {
      _fromController.text = state.pickupLocation;
    }
    if (_toController.text != state.dropoffLocation) {
      _toController.text = state.dropoffLocation;
    }

    final bool canContinue = state.pickupLocation.trim().isNotEmpty &&
        state.dropoffLocation.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Enter your route',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const Key('close_button'),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LocationInputField(
                label: 'From',
                controller: _fromController,
                fieldKey: const Key('from_input'),
                onChanged: controller.updatePickupLocation,
                prefixIcon: Icons.trip_origin_rounded,
                dotColor: const Color(0xFFDFFF00),
                isLoading:
                    state.pickupLocationStatus == PickupLocationStatus.loading,
              ),
              const SizedBox(height: 10),
              LocationInputField(
                label: 'To',
                controller: _toController,
                fieldKey: const Key('to_input'),
                onChanged: (value) => _onDropoffChanged(controller, value),
                prefixIcon: Icons.search_rounded,
                dotColor: const Color(0xFFFF5370),
              ),
              const SizedBox(height: 16),
              if (_suggestions.isNotEmpty)
                Expanded(
                  child: ListView.separated(
                    key: const Key('destination_suggestions_list'),
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final PlaceSuggestion suggestion = _suggestions[index];
                      return GestureDetector(
                        key: Key('suggestion_${suggestion.placeId}'),
                        onTap: () => _selectSuggestion(controller, suggestion),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: Color(0xFF808080),
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      suggestion.mainText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (suggestion.secondaryText.isNotEmpty)
                                      Text(
                                        suggestion.secondaryText,
                                        style: const TextStyle(
                                          color: Color(0xFF808080),
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Passengers',
                      style: TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${state.passengerCount} pax',
                      style: const TextStyle(
                        color: Color(0xFFDFFF00),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PassengerStepper(
                  count: state.passengerCount,
                  onChanged: controller.setPassengerCount,
                ),
                const Spacer(),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: const Key('continue_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    disabledBackgroundColor: const Color(0xFF242424),
                    disabledForegroundColor: const Color(0xFF606060),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: canContinue
                      ? () => Navigator.pushNamed(context, '/rider/fare-offer')
                      : null,
                  child: const Text(
                    'Continue',
                    style: TextStyle(
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
    );
  }
}
