import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/k_coin_package.dart';

void main() {
  test('KCoinPackage deserializes correctly from JSON', () {
    final json = {
      'id': 'pkg_123',
      'title': '100 Coins',
      'coin_amount': 100,
      'price_usd': 0.99,
      'store_product_id': 'com.app.100coins'
    };
    
    final pkg = KCoinPackage.fromJson(json);
    
    expect(pkg.id, 'pkg_123');
    expect(pkg.title, '100 Coins');
    expect(pkg.coinAmount, 100);
    expect(pkg.priceUsd, 0.99);
    expect(pkg.storeProductId, 'com.app.100coins');
  });
}
