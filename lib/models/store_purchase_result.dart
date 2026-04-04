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
      productCode: json['product_code'] as String? ?? '',
      productCategory: json['product_category'] as String? ?? 'general',
      newBalance: (json['new_balance'] as num?)?.toInt(),
      transactionId: json['transaction_id'] as String?,
      entitlementId: json['entitlement_id'] as String?,
      themeCode: json['theme_code'] as String?,
    );
  }
}
