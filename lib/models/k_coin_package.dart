class KCoinPackage {
  final String id;
  final String title;
  final int coinAmount;
  final double priceUsd;
  final String? storeProductId;

  KCoinPackage({
    required this.id,
    required this.title,
    required this.coinAmount,
    required this.priceUsd,
    this.storeProductId,
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
}
