class KCoinPackage {
  final String id;
  final String title;
  final int coinAmount;
  final double priceUsd;
  final String? storeProductId;
  final String? displayPrice;

  KCoinPackage({
    required this.id,
    required this.title,
    required this.coinAmount,
    required this.priceUsd,
    this.storeProductId,
    this.displayPrice,
  });

  factory KCoinPackage.fromJson(Map<String, dynamic> json) {
    return KCoinPackage(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coinAmount: _asInt(json['coin_amount']),
      priceUsd: _asDouble(json['price_usd']),
      storeProductId: _stringOrNull(json['store_product_id']),
    );
  }

  KCoinPackage copyWith({
    String? id,
    String? title,
    int? coinAmount,
    double? priceUsd,
    String? storeProductId,
    String? displayPrice,
  }) {
    return KCoinPackage(
      id: id ?? this.id,
      title: title ?? this.title,
      coinAmount: coinAmount ?? this.coinAmount,
      priceUsd: priceUsd ?? this.priceUsd,
      storeProductId: storeProductId ?? this.storeProductId,
      displayPrice: displayPrice ?? this.displayPrice,
    );
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _asDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
