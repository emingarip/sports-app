class StorePurchaseResult {
  final bool success;
  final int? newBalance;
  final String? transactionId;
  final String? entitlementId;
  final String productCode;
  final String productCategory;
  final String? themeCode;

  const StorePurchaseResult({
    required this.success,
    required this.productCode,
    required this.productCategory,
    this.newBalance,
    this.transactionId,
    this.entitlementId,
    this.themeCode,
  });

  bool get isThemePurchase => productCategory == 'app_theme';

  factory StorePurchaseResult.fromJson(Map<String, dynamic> json) {
    return StorePurchaseResult(
      success: json['success'] == true,
      productCode: json['product_code']?.toString() ?? '',
      productCategory: json['product_category']?.toString() ?? 'general',
      newBalance: _asNullableInt(json['new_balance']),
      transactionId: _stringOrNull(json['transaction_id']),
      entitlementId: _stringOrNull(json['entitlement_id']),
      themeCode: _stringOrNull(json['theme_code']),
    );
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
