import 'package:meta/meta.dart';

/// A robust, immutable data class representation of the bidding screen state.
/// Implemented as a Dart 3 sealed union style class to support pattern matching.
@immutable
sealed class BiddingState {
  const BiddingState();

  const factory BiddingState.initial() = BiddingStateInitial;
  const factory BiddingState.connecting() = BiddingStateConnecting;
  const factory BiddingState.active({required List<Map<String, dynamic>> activeBids}) = BiddingStateActive;
  const factory BiddingState.error({required String message}) = BiddingStateError;
}

/// The initial state prior to attempting any connection.
class BiddingStateInitial extends BiddingState {
  const BiddingStateInitial();

  @override
  bool operator ==(Object other) => identical(this, other) || other is BiddingStateInitial;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BiddingState.initial()';
}

/// The state while establishing the WebSocket connection.
class BiddingStateConnecting extends BiddingState {
  const BiddingStateConnecting();

  @override
  bool operator ==(Object other) => identical(this, other) || other is BiddingStateConnecting;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BiddingState.connecting()';
}

/// The active state with one or more received driver bids.
class BiddingStateActive extends BiddingState {
  final List<Map<String, dynamic>> activeBids;

  const BiddingStateActive({required this.activeBids});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BiddingStateActive && _listEquals(activeBids, other.activeBids);

  @override
  int get hashCode => Object.hashAll(activeBids.map((bid) =>
      Object.hashAll(bid.entries.map((e) => Object.hash(e.key, e.value)))));

  @override
  String toString() => 'BiddingState.active(activeBids: $activeBids)';
}

/// The error state when the connection fails or an error is encountered.
class BiddingStateError extends BiddingState {
  final String message;

  const BiddingStateError({required this.message});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BiddingStateError && message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'BiddingState.error(message: $message)';
}

/// Deep list equality checker for standard types and maps.
bool _listEquals(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!_mapEquals(a[i], b[i])) return false;
  }
  return true;
}

/// Deep map equality checker.
bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    final valA = a[key];
    final valB = b[key];
    if (valA is Map && valB is Map) {
      if (!_mapEquals(Map<String, dynamic>.from(valA), Map<String, dynamic>.from(valB))) return false;
    } else if (valA is List && valB is List) {
      // In case there are nested lists inside bids
      if (valA.length != valB.length) return false;
      for (int i = 0; i < valA.length; i++) {
        if (valA[i] != valB[i]) return false;
      }
    } else if (valA != valB) {
      return false;
    }
  }
  return true;
}
