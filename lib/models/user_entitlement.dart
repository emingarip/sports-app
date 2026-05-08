class UserEntitlement {
  final String id;
  final String userId;
  final String productCode;
  final DateTime purchasedAt;
  final DateTime? expiresAt;
  final bool isActive;

  UserEntitlement({
    required this.id,
    required this.userId,
    required this.productCode,
    required this.purchasedAt,
    this.expiresAt,
    required this.isActive,
  });

  factory UserEntitlement.fromJson(Map<String, dynamic> json) {
    return UserEntitlement(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      productCode: json['product_code']?.toString() ?? '',
      purchasedAt: DateTime.tryParse(json['purchased_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      isActive: _asBool(json['is_active']),
    );
  }

  bool get isValid {
    if (!isActive) return false;
    if (expiresAt == null) return true; // Lifetime
    return expiresAt!.isAfter(DateTime.now());
  }
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return false;
}
