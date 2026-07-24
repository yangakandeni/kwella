import '../../../location/services/places_autocomplete_service.dart';

/// A destination the rider has been to before, offered as a one-tap
/// shortcut instead of retyping the address. Carries both a short label for
/// compact display and the full place description/coordinates needed to act
/// on selection exactly like a fresh Places Autocomplete pick.
class PreviousDestination {
  const PreviousDestination({
    required this.placeId,
    required this.shortName,
    required this.description,
    required this.lat,
    required this.lng,
  });

  final String placeId;
  final String shortName;
  final String description;
  final double lat;
  final double lng;

  /// Converts to the shape [AutocompleteSuggestionsList] already knows how
  /// to render and select, so picking a previous destination behaves exactly
  /// like picking a live autocomplete result.
  PlaceSuggestion toPlaceSuggestion() {
    final String prefix = '$shortName, ';
    final String secondaryText = description.startsWith(prefix)
        ? description.substring(prefix.length)
        : description;
    return PlaceSuggestion(
      placeId: placeId,
      description: description,
      mainText: shortName,
      secondaryText: secondaryText,
      lat: lat,
      lng: lng,
    );
  }
}

/// Mock previous-destination history for a Cape Town rider. Stands in for a
/// real recents store until one exists — see the destination editor and
/// booking screen for where this is offered as a selection shortcut.
const List<PreviousDestination> mockPreviousDestinations = [
  PreviousDestination(
    placeId: 'previous-liberty-promenade',
    shortName: 'Liberty Promenade',
    description: 'Liberty Promenade, Mitchells Plain, Cape Town',
    lat: -34.0555,
    lng: 18.6288,
  ),
  PreviousDestination(
    placeId: 'previous-zevenwacht-mall',
    shortName: 'Zevenwacht Mall',
    description: 'Zevenwacht Mall, Van Riebeeck Road, Kuils River',
    lat: -33.9581,
    lng: 18.6961,
  ),
  PreviousDestination(
    placeId: 'previous-shoprite-blue-downs',
    shortName: 'Shoprite Blue Downs',
    description:
        'Shoprite Blue Downs, Robert Sobukwe Road, Blue Downs, Cape Town',
    lat: -34.0004,
    lng: 18.6889,
  ),
  PreviousDestination(
    placeId: 'previous-cape-town-station',
    shortName: 'Cape Town Station',
    description: 'Cape Town Station, Adderley Street, Cape Town',
    lat: -33.9249,
    lng: 18.4241,
  ),
  PreviousDestination(
    placeId: 'previous-canal-walk',
    shortName: 'Canal Walk',
    description: 'Canal Walk, Century Boulevard, Century City, Cape Town',
    lat: -33.8931,
    lng: 18.5121,
  ),
  PreviousDestination(
    placeId: 'previous-tyger-valley-centre',
    shortName: 'Tyger Valley Centre',
    description:
        'Tyger Valley Centre, Willie van Schoor Drive, Bellville, Cape Town',
    lat: -33.8722,
    lng: 18.6280,
  ),
  PreviousDestination(
    placeId: 'previous-vangate-mall',
    shortName: 'Vangate Mall',
    description: 'Vangate Mall, Vanguard Drive, Athlone, Cape Town',
    lat: -33.9628,
    lng: 18.5182,
  ),
  PreviousDestination(
    placeId: 'previous-somerset-mall',
    shortName: 'Somerset Mall',
    description:
        'Somerset Mall, Voortrekker Road, Somerset West, Cape Town',
    lat: -34.0797,
    lng: 18.8503,
  ),
  PreviousDestination(
    placeId: 'previous-kenilworth-centre',
    shortName: 'Kenilworth Centre',
    description: 'Kenilworth Centre, Main Road, Kenilworth, Cape Town',
    lat: -33.9944,
    lng: 18.4739,
  ),
  PreviousDestination(
    placeId: 'previous-blue-route-mall',
    shortName: 'Blue Route Mall',
    description: 'Blue Route Mall, Tokai Road, Tokai, Cape Town',
    lat: -34.0447,
    lng: 18.4256,
  ),
];
