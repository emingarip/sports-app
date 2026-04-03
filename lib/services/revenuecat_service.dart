import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sports_app/services/supabase_service.dart';

class RevenueCatService {
  static const String _appleApiKey =
      String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const String _googleApiKey =
      String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  static bool get isConfiguredForCurrentPlatform {
    if (kIsWeb) return false;
    if (Platform.isAndroid) return _googleApiKey.isNotEmpty;
    if (Platform.isIOS || Platform.isMacOS) return _appleApiKey.isNotEmpty;
    return false;
  }

  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!isConfiguredForCurrentPlatform) {
      debugPrint('RevenueCat disabled: missing platform API key.');
      return;
    }

    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

    PurchasesConfiguration? configuration;

    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(_googleApiKey);
    } else if (Platform.isIOS || Platform.isMacOS) {
      configuration = PurchasesConfiguration(_appleApiKey);
    }

    if (configuration != null) {
      await Purchases.configure(configuration);
      _syncUserIfLoggedIn();
    }
  }

  static Future<void> _syncUserIfLoggedIn() async {
    if (kIsWeb || !isConfiguredForCurrentPlatform) return;
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser != null) {
      try {
        await Purchases.logIn(currentUser.id);
      } catch (e) {
        debugPrint('RevenueCat login failed: $e');
      }
    }
  }

  static Future<void> login(String userId) async {
    if (kIsWeb || !isConfiguredForCurrentPlatform) return;
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('RevenueCat login failed: $e');
    }
  }

  static Future<void> logout() async {
    if (kIsWeb || !isConfiguredForCurrentPlatform) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('RevenueCat logout failed: $e');
    }
  }

  static Future<List<Package>> getKCoinPackages() async {
    if (!isConfiguredForCurrentPlatform) return [];
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null &&
          offerings.current!.availablePackages.isNotEmpty) {
        return offerings.current!.availablePackages;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching offerings: $e');
      return [];
    }
  }

  static Future<bool> purchasePackage(Package package) async {
    if (!isConfiguredForCurrentPlatform) {
      debugPrint(
          'Purchase disabled: RevenueCat is not configured for this platform.');
      return false;
    }

    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase error: $e');
      }
      return false;
    } catch (e) {
      debugPrint('Unknown purchase error: $e');
      return false;
    }
  }
}
