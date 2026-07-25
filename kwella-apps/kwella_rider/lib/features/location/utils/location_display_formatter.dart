/// Shortens a location string for display within the Cape Town-only service
/// area. The rider always knows every trip is local, so trailing
/// "South Africa" / "Cape Town" segments add clutter without adding
/// information — this only affects what's rendered; callers should keep
/// passing the original, unmodified string to state/APIs.
///
/// Examples:
///   "23 West Drive, Khayelitsha, Cape Town, South Africa" -> "23 West Drive, Khayelitsha"
///   "Long Street, Cape Town" -> "Long Street"
///   "Cape Town, South Africa" -> "Cape Town"
String formatLocationLabel(String rawAddress) {
  final List<String> parts = rawAddress
      .split(',')
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return rawAddress;

  if (parts.last.toLowerCase() == 'south africa') {
    parts.removeLast();
  }
  if (parts.length > 1 && parts.last.toLowerCase() == 'cape town') {
    parts.removeLast();
  }

  if (parts.isEmpty) return rawAddress;
  return parts.join(', ');
}

/// Splits a formatted location label (see [formatLocationLabel]) into a
/// primary line (place/street name) and a secondary line (area/suburb), for
/// two-line destination displays.
///
/// Examples:
///   "Liberty Promenade, Mitchells Plain" -> ("Liberty Promenade", "Mitchells Plain")
///   "Long Street" -> ("Long Street", "")
class LocationLabelParts {
  const LocationLabelParts(this.primary, this.secondary);

  final String primary;
  final String secondary;
}

LocationLabelParts splitLocationLabel(String formattedAddress) {
  final int commaIndex = formattedAddress.indexOf(',');
  if (commaIndex == -1) {
    return LocationLabelParts(formattedAddress.trim(), '');
  }
  return LocationLabelParts(
    formattedAddress.substring(0, commaIndex).trim(),
    formattedAddress.substring(commaIndex + 1).trim(),
  );
}
