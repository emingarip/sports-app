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
      id: json['id'] as String,
      title: json['title'] as String,
      coinAmount: json['coin_amount'] as int,
      priceUsd: (json['price_usd'] as num).toDouble(),
      storeProductId: json['store_product_id'] as String?,
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
