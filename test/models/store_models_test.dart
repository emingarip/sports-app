import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/store_product.dart';
import 'package:sports_app/models/user_entitlement.dart';

void main() {
  group('Store models', () {
    test('parse store product without exact primitive casts', () {
      final product = StoreProduct.fromJson({
        'id': 123,
        'product_code': 456,
        'title': 789,
        'description': null,
        'price': '99',
        'product_type': null,
        'duration_days': 30.0,
        'is_active': 'true',
        'product_category': 100,
        'theme_code': 200,
        'created_at': '2026-05-08T00:00:00Z',
      });

      expect(product.id, '123');
      expect(product.productCode, '456');
      expect(product.title, '789');
      expect(product.price, 99);
      expect(product.durationDays, 30);
      expect(product.isActive, isTrue);
      expect(product.productCategory, '100');
      expect(product.themeCode, '200');
    });

    test('parse user entitlement without exact primitive casts', () {
      final entitlement = UserEntitlement.fromJson({
        'id': 123,
        'user_id': 456,
        'product_code': 789,
        'purchased_at': '2026-05-08T00:00:00Z',
        'expires_at': null,
        'is_active': 1,
      });

      expect(entitlement.id, '123');
      expect(entitlement.userId, '456');
      expect(entitlement.productCode, '789');
      expect(entitlement.isActive, isTrue);
      expect(entitlement.expiresAt, isNull);
    });
  });
}
