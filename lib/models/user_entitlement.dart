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
      id: json['id'],
      userId: json['user_id'],
      productCode: json['product_code'],
      purchasedAt: DateTime.parse(json['purchased_at']),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      isActive: json['is_active'] ?? false,
    );
  }

  bool get isValid {
    if (!isActive) return false;
    if (expiresAt == null) return true; // Lifetime
    return expiresAt!.isAfter(DateTime.now());
  }
}
