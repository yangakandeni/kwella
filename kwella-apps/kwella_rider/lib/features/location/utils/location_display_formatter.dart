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
