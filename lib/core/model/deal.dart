/// A "bon plan": an offer the merchant publishes to customers of the Djassa
/// app for a limited time. Deals need the network (they exist to be seen by
/// others), so unlike sales there is no offline queue for them.
class Deal {
  const Deal({
    required this.id,
    required this.title,
    required this.endsAt,
    required this.isFeatured,
    this.description,
    this.discountPercent,
    this.price,
    this.originalPrice,
  });

  factory Deal.fromJson(Map<String, Object?> json) => Deal(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        discountPercent: json['discount_percent'] as int?,
        price: json['price'] as int?,
        originalPrice: json['original_price'] as int?,
        endsAt: _parseUtc(json['ends_at'] as String),
        isFeatured: json['is_featured'] as bool? ?? false,
      );

  final int id;
  final String title;
  final String? description;
  final int? discountPercent;

  /// Whole francs CFA.
  final int? price;
  final int? originalPrice;
  final DateTime endsAt;

  /// Promoted by Djassa (paid placement). The merchant cannot set this.
  final bool isFeatured;
}

/// What the merchant is about to publish.
class DealDraft {
  const DealDraft({
    required this.title,
    required this.duration,
    this.description,
    this.discountPercent,
    this.price,
    this.originalPrice,
  });

  final String title;
  final String? description;
  final int? discountPercent;
  final int? price;
  final int? originalPrice;
  final Duration duration;

  /// The server's own rules, checked before sending so the merchant gets the
  /// answer without waiting on the network. Returns null when valid.
  String? validate({
    required String titleTooShort,
    required String nothingOffered,
    required String percentRange,
    required String priceNotLower,
  }) {
    if (title.trim().length < 3) return titleTooShort;
    if (discountPercent == null && price == null) return nothingOffered;
    final pct = discountPercent;
    if (pct != null && (pct < 1 || pct > 90)) return percentRange;
    final p = price, o = originalPrice;
    if (p != null && o != null && p >= o) return priceNotLower;
    return null;
  }

  Map<String, Object?> toJson(DateTime now) => {
        'title': title.trim(),
        if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
        if (discountPercent != null) 'discount_percent': discountPercent,
        if (price != null) 'price': price,
        if (originalPrice != null) 'original_price': originalPrice,
        'ends_at': now.toUtc().add(duration).toIso8601String(),
      };
}

/// The backend sends naive UTC timestamps.
DateTime _parseUtc(String value) {
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.parse(hasZone ? value : '${value}Z').toLocal();
}
