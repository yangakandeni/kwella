import 'package:flutter/material.dart';

import '../../../location/services/places_autocomplete_service.dart';
import '../../../location/utils/location_display_formatter.dart';

/// Renders the Google Places autocomplete results for the destination
/// editor's From/To fields — loading, empty, and populated states.
///
/// Deliberately owns *only* the results list (no passenger selector, no
/// fields) so that whatever this widget does in response to suggestions
/// changing can never hide or resize sibling controls on the panel that
/// embeds it.
class AutocompleteSuggestionsList extends StatefulWidget {
  const AutocompleteSuggestionsList({
    super.key,
    required this.isLoading,
    required this.suggestions,
    required this.lastSearchedQuery,
    required this.onSelect,
  });

  final bool isLoading;
  final List<PlaceSuggestion> suggestions;
  final String lastSearchedQuery;
  final ValueChanged<PlaceSuggestion> onSelect;

  @override
  State<AutocompleteSuggestionsList> createState() =>
      _AutocompleteSuggestionsListState();
}

class _AutocompleteSuggestionsListState
    extends State<AutocompleteSuggestionsList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String? _formatDistance(int? distanceMeters) {
    if (distanceMeters == null) return null;
    if (distanceMeters < 1000) return '$distanceMeters m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
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

    if (widget.suggestions.isEmpty) {
      if (widget.lastSearchedQuery.isEmpty) return const SizedBox.shrink();
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
                  'No matching locations for "${widget.lastSearchedQuery}". Try a different search.',
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

    // Fills whatever space the parent reserves for it and scrolls internally
    // once there are more results than fit, rather than growing. A visible
    // thumb signals there's more to browse, and the dedicated controller
    // lets a Scrollbar attach without relying on a PrimaryScrollController
    // from an ancestor.
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.separated(
        key: const Key('destination_suggestions_list'),
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.suggestions.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
        itemBuilder: (context, index) {
          final PlaceSuggestion suggestion = widget.suggestions[index];
          final String? distanceLabel = _formatDistance(
            suggestion.distanceMeters,
          );
          return GestureDetector(
            key: Key('suggestion_${suggestion.placeId}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect(suggestion),
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
                              formatLocationLabel(suggestion.secondaryText),
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
      ),
    );
  }
}
