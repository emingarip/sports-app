class StoreProduct {
  final String id;
  final String productCode;
  final String title;
  final String description;
  final int price;
  final String productType; // 'subscription', 'lifetime', 'consumable'
  final int? durationDays;
  final bool isActive;
  final String productCategory;
  final String? themeCode;
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
    this.productCategory = 'general',
    this.themeCode,
    required this.createdAt,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) {
    return StoreProduct(
      id: json['id']?.toString() ?? '',
      productCode: json['product_code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: _asInt(json['price']),
      productType: json['product_type']?.toString() ?? 'consumable',
      durationDays: _asNullableInt(json['duration_days']),
      isActive: _asBool(json['is_active']),
      productCategory: json['product_category']?.toString() ?? 'general',
      themeCode: _stringOrNull(json['theme_code']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isThemeProduct => productCategory == 'app_theme';
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

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return false;
}
