import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../../../location/services/places_autocomplete_service.dart';
import 'location_input_field.dart';
import 'passenger_stepper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DestinationEditorPanel — the From/To + passenger-count editor body shared
// between the dedicated destination route and the inline expanding panel on
// RiderBookingScreen. Purely presentational: all trip state lives on the
// shared KwellaRiderController, so callers just need to forward it and the
// latest RiderTripState snapshot.
// ─────────────────────────────────────────────────────────────────────────────

class DestinationEditorPanel extends StatefulWidget {
  const DestinationEditorPanel({
    super.key,
    required this.controller,
    required this.state,
    required this.onClose,
    this.placesService,
  });

  final KwellaRiderController controller;
  final RiderTripState state;
  final VoidCallback onClose;
  final PlacesAutocompleteService? placesService;

  @override
  State<DestinationEditorPanel> createState() => _DestinationEditorPanelState();
}

class _DestinationEditorPanelState extends State<DestinationEditorPanel> {
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
    _fromController = TextEditingController(text: widget.state.pickupLocation);
    _toController = TextEditingController(text: widget.state.dropoffLocation);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _onDropoffChanged(String value) {
    widget.controller.updateDropoffLocation(value);
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

  void _selectSuggestion(PlaceSuggestion suggestion) {
    _toController.text = suggestion.description;
    widget.controller.updateDropoffLocation(suggestion.description);
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final RiderTripState state = widget.state;
    final KwellaRiderController controller = widget.controller;

    if (_fromController.text != state.pickupLocation) {
      _fromController.text = state.pickupLocation;
    }
    if (_toController.text != state.dropoffLocation) {
      _toController.text = state.dropoffLocation;
    }

    final bool canContinue = state.pickupLocation.trim().isNotEmpty &&
        state.dropoffLocation.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LocationInputField(
          label: 'From',
          controller: _fromController,
          fieldKey: const Key('from_input'),
          onChanged: controller.updatePickupLocation,
          prefixIcon: Icons.trip_origin_rounded,
          dotColor: const Color(0xFFDFFF00),
          isLoading: state.pickupLocationStatus == PickupLocationStatus.loading,
        ),
        const SizedBox(height: 10),
        LocationInputField(
          label: 'To',
          controller: _toController,
          fieldKey: const Key('to_input'),
          onChanged: _onDropoffChanged,
          prefixIcon: Icons.search_rounded,
          dotColor: const Color(0xFFFF5370),
        ),
        const SizedBox(height: 16),
        if (_suggestions.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              key: const Key('destination_suggestions_list'),
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final PlaceSuggestion suggestion = _suggestions[index];
                return GestureDetector(
                  key: Key('suggestion_${suggestion.placeId}'),
                  onTap: () => _selectSuggestion(suggestion),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
        else
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
              const Icon(
                Icons.person_rounded,
                color: Color(0xFFDFFF00),
                size: 18,
              ),
            ],
          ),
        if (_suggestions.isEmpty) ...[
          const SizedBox(height: 10),
          PassengerStepper(
            count: state.passengerCount,
            onChanged: controller.setPassengerCount,
          ),
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
    );
  }
}
