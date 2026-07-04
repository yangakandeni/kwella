class DriverBid {
  final String id;
  final String driverName;
  final String rating;
  final String eta;
  final String price;

  const DriverBid({
    required this.id,
    required this.driverName,
    required this.rating,
    required this.eta,
    required this.price,
  });

  /// Factory method to create a DriverBid from a JSON map (useful for future AWS integration).
  factory DriverBid.fromJson(Map<String, dynamic> json) {
    return DriverBid(
      id: json['id'] as String,
      driverName: json['driverName'] as String,
      rating: json['rating'] as String,
      eta: json['eta'] as String,
      price: json['price'] as String,
    );
  }

  /// Converts this DriverBid to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverName': driverName,
      'rating': rating,
      'eta': eta,
      'price': price,
    };
  }

  /// Creates a copy of this DriverBid with the given fields replaced by the new values.
  DriverBid copyWith({
    String? id,
    String? driverName,
    String? rating,
    String? eta,
    String? price,
  }) {
    return DriverBid(
      id: id ?? this.id,
      driverName: driverName ?? this.driverName,
      rating: rating ?? this.rating,
      eta: eta ?? this.eta,
      price: price ?? this.price,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverBid &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          driverName == other.driverName &&
          rating == other.rating &&
          eta == other.eta &&
          price == other.price;

  @override
  int get hashCode =>
      id.hashCode ^
      driverName.hashCode ^
      rating.hashCode ^
      eta.hashCode ^
      price.hashCode;

  @override
  String toString() {
    return 'DriverBid(id: $id, driverName: $driverName, rating: $rating, eta: $eta, price: $price)';
  }
}
