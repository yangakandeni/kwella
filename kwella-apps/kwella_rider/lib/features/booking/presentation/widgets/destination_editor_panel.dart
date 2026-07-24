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

/// Which location field, if any, currently owns the suggestions dropdown.
enum _ActiveField { none, from, to }

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

  /// Fraction of the screen height the panel occupies once expanded. Fixed
  /// for the panel's whole lifetime so it never grows/shrinks as suggestions
  /// come and go — only the reserved area's *contents* change.
  static const double _panelHeightFraction = 0.72;

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final PlacesAutocompleteService _placesService;

  _ActiveField _activeField = _ActiveField.none;
  List<PlaceSuggestion> _suggestions = const [];
  bool _isLoadingSuggestions = false;
  String _lastSearchedQuery = '';
  Timer? _debounceTimer;

  /// Once the rider starts editing either field, the reserved area below
  /// switches from the passenger selector to the suggestions zone and stays
  /// there — even if the field is cleared back to empty — for the rest of
  /// this panel's lifetime, so clearing text never pops the layout back.
  bool _hasActivatedSearch = false;

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
        _hasActivatedSearch = true;
        _activeField = _ActiveField.none;
        _suggestions = const [];
        _isLoadingSuggestions = false;
        _lastSearchedQuery = '';
      });
      return;
    }

    setState(() {
      _hasActivatedSearch = true;
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
      widget.controller.updateDropoffLocation(suggestion.description);
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

  String? _formatDistance(int? distanceMeters) {
    if (distanceMeters == null) return null;
    if (distanceMeters < 1000) return '$distanceMeters m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  // The reserved area below the fields is given a fixed height by the
  // caller (see `_buildReservedArea`/`build`), so every branch here must
  // avoid stretching to fill it — `Align` pins small states to the top and
  // leaves the rest of the space blank instead of centering within it.
  Widget _buildSuggestionsArea() {
    if (_isLoadingSuggestions) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          key: Key('suggestions_loading'),
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFDFFF00),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Searching…',
                style: TextStyle(color: Color(0xFF808080), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      if (_lastSearchedQuery.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          key: const Key('suggestions_empty_state'),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const Icon(
                Icons.search_off_rounded,
                color: Color(0xFF606060),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No matching locations for "$_lastSearchedQuery". Try a different search.',
                  style: const TextStyle(
                    color: Color(0xFF808080),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fills the reserved area (roughly 5-6 rows tall) and scrolls
    // internally once there are more results than fit, rather than growing
    // the panel.
    return ListView.separated(
      key: const Key('destination_suggestions_list'),
      itemCount: _suggestions.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFF2C2C2C)),
      itemBuilder: (context, index) {
        final PlaceSuggestion suggestion = _suggestions[index];
        final String? distanceLabel = _formatDistance(
          suggestion.distanceMeters,
        );
        return GestureDetector(
          key: Key('suggestion_${suggestion.placeId}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectSuggestion(suggestion),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF808080),
                  size: 20,
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
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            suggestion.secondaryText,
                            style: const TextStyle(
                              color: Color(0xFF808080),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (distanceLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    distanceLabel,
                    style: const TextStyle(
                      color: Color(0xFF808080),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

    // Fixed for the panel's lifetime: only the reserved area's contents
    // (below) change afterwards, so the panel itself never resizes once
    // opened, regardless of loading/empty/populated suggestion states.
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
          // Reserved area: comfortably fits ~5-6 suggestion rows. Its
          // *contents* swap between the passenger selector and the
          // suggestions zone, but this slot's height never does.
          Expanded(child: _buildReservedArea(state, controller)),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReservedArea(
    RiderTripState state,
    KwellaRiderController controller,
  ) {
    if (!_hasActivatedSearch) {
      return Align(
        alignment: Alignment.topCenter,
        child: Column(
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
        ),
      );
    }

    return _buildSuggestionsArea();
  }
}
