class StoreProduct {
  final String id;
  final String productCode;
  final String title;
  final String description;
  final int price;
  final String productType; // 'subscription', 'lifetime', 'consumable'
  final int? durationDays;
  final bool isActive;
  final DateTime createdAt;

  StoreProduct({
    required this.id,
    required this.productCode,
    required this.title,
    required this.description,
    required this.price,
    required this.productType,
    this.durationDays,
    required this.isActive,
    required this.createdAt,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) {
    return StoreProduct(
      id: json['id'],
      productCode: json['product_code'],
      title: json['title'],
      description: json['description'] ?? '',
      price: json['price'] ?? 0,
      productType: json['product_type'],
      durationDays: json['duration_days'],
      isActive: json['is_active'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
