import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../models/previous_destination.dart';
import '../../../location/services/places_autocomplete_service.dart';
import 'autocomplete_suggestions_list.dart';
import 'location_input_field.dart';
import 'passenger_stepper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DestinationEditorPanel — the From/To + passenger-count editor body shared
// between the dedicated destination route and the inline expanding panel on
// RiderBookingScreen. Purely presentational: all trip state lives on the
// shared KwellaRiderController, so callers just need to forward it and the
// latest RiderTripState snapshot.
// ─────────────────────────────────────────────────────────────────────────────

/// Which location field, if any, currently owns the suggestions dropdown.
enum _ActiveField { none, from, to }

class DestinationEditorPanel extends StatefulWidget {
  const DestinationEditorPanel({
    super.key,
    required this.controller,
    required this.state,
    required this.onClose,
    this.placesService,
    this.previousDestinations = mockPreviousDestinations,
    this.onContinue,
  });

  final KwellaRiderController controller;
  final RiderTripState state;
  final VoidCallback onClose;
  final PlacesAutocompleteService? placesService;
  final List<PreviousDestination> previousDestinations;

  /// Invoked instead of the default fare-offer navigation when the rider
  /// taps `continue_button`, letting callers interpose a step (e.g.
  /// RiderBookingScreen's inline usage routes through `/rider/payment-method`
  /// first). Defaults to `null`, preserving the original direct-to-fare-offer
  /// behavior for callers that don't need the extra step (e.g.
  /// DestinationSelectionScreen's standalone deep-link route).
  final VoidCallback? onContinue;

  @override
  State<DestinationEditorPanel> createState() => _DestinationEditorPanelState();
}

class _DestinationEditorPanelState extends State<DestinationEditorPanel> {
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  /// Fraction of the screen height the panel occupies once expanded. Fixed
  /// for the panel's whole lifetime so it never grows/shrinks as suggestions
  /// come and go.
  static const double _panelHeightFraction = 0.72;

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final PlacesAutocompleteService _placesService;

  _ActiveField _activeField = _ActiveField.none;
  List<PlaceSuggestion> _suggestions = const [];
  bool _isLoadingSuggestions = false;
  String _lastSearchedQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _placesService = widget.placesService ?? PlacesAutocompleteService();
    _fromController = TextEditingController(text: widget.state.pickupLocation);
    _toController = TextEditingController(text: widget.state.dropoffLocation);
    // Show previous destinations as the default suggestions on open, rather
    // than an empty list, without touching the Places API.
    _suggestions = widget.previousDestinations
        .map((destination) => destination.toPlaceSuggestion())
        .toList();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _onFieldChanged(String value, {required bool isPickup}) {
    if (isPickup) {
      widget.controller.updatePickupLocation(value);
    } else {
      widget.controller.updateDropoffLocation(value);
    }

    _debounceTimer?.cancel();
    final String trimmed = value.trim();
    if (trimmed.length < 3) {
      setState(() {
        _activeField = _ActiveField.none;
        _suggestions = const [];
        _isLoadingSuggestions = false;
        _lastSearchedQuery = '';
      });
      return;
    }

    setState(() {
      _activeField = isPickup ? _ActiveField.from : _ActiveField.to;
    });

    _debounceTimer = Timer(_debounceDelay, () async {
      setState(() => _isLoadingSuggestions = true);
      final List<PlaceSuggestion> results = await _placesService.searchPlaces(
        trimmed,
        originLat: widget.state.pickupLat,
        originLng: widget.state.pickupLng,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isLoadingSuggestions = false;
        _lastSearchedQuery = trimmed;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final bool isPickup = _activeField == _ActiveField.from;
    final TextEditingController fieldController = isPickup
        ? _fromController
        : _toController;

    fieldController.text = suggestion.description;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = const [];
      _activeField = _ActiveField.none;
      _lastSearchedQuery = '';
    });

    if (!isPickup) {
      widget.controller.updateDropoffLocation(
        suggestion.description,
        lat: suggestion.lat,
        lng: suggestion.lng,
      );
      return;
    }

    // Resolve the picked pickup point's coordinates so subsequent Places
    // lookups (for either field) can bias toward it.
    widget.controller.updatePickupLocation(suggestion.description);
    final PlaceLocation? location = await _placesService.getPlaceDetails(
      suggestion.placeId,
    );
    if (!mounted || location == null) return;
    widget.controller.updatePickupLocation(
      suggestion.description,
      lat: location.lat,
      lng: location.lng,
    );
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

    final bool canContinue =
        state.pickupLocation.trim().isNotEmpty &&
        state.dropoffLocation.trim().isNotEmpty;

    // Fixed for the panel's lifetime: the panel never resizes once opened,
    // regardless of loading/empty/populated suggestion states.
    final double panelHeight =
        MediaQuery.of(context).size.height * _panelHeightFraction;

    return SizedBox(
      height: panelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enter your route',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              GestureDetector(
                key: const Key('close_button'),
                onTap: widget.onClose,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF242424),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LocationInputField(
            label: 'From',
            controller: _fromController,
            fieldKey: const Key('from_input'),
            onChanged: (value) => _onFieldChanged(value, isPickup: true),
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
            onChanged: (value) => _onFieldChanged(value, isPickup: false),
            prefixIcon: Icons.search_rounded,
            dotColor: const Color(0xFFFF5370),
          ),
          const SizedBox(height: 12),
          // Autocomplete results own only this slot — they can never hide
          // or resize the passenger selector below, which stays visible
          // throughout regardless of loading/empty/populated states.
          Expanded(
            child: AutocompleteSuggestionsList(
              isLoading: _isLoadingSuggestions,
              suggestions: _suggestions,
              lastSearchedQuery: _lastSearchedQuery,
              onSelect: _selectSuggestion,
            ),
          ),
          const SizedBox(height: 12),
          _buildPassengerSelectorSection(state, controller),
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
                  ? () => widget.onContinue != null
                      ? widget.onContinue!()
                      : Navigator.pushNamed(context, '/rider/fare-offer')
                  : null,
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerSelectorSection(
    RiderTripState state,
    KwellaRiderController controller,
  ) {
    return Column(
      key: const Key('passenger_selector_section'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 10),
        PassengerStepper(
          count: state.passengerCount,
          onChanged: controller.setPassengerCount,
        ),
      ],
    );
  }
}
