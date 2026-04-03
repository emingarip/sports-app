import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sports_app/services/supabase_service.dart';

class RevenueCatService {
  // Keys are injected via --dart-define at build time for production
  // Defaults to test keys for local development
  static const String _appleApiKey = String.fromEnvironment('REVENUECAT_APPLE_KEY', defaultValue: 'appl_YOUR_APPLE_API_KEY_HERE');
  static const String _googleApiKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY', defaultValue: 'goog_YOUR_GOOGLE_API_KEY_HERE');

  static Future<void> initialize() async {
    // RevenueCat only works on iOS, Android, and macOS.
    if (kIsWeb) return;

    await Purchases.setLogLevel(LogLevel.debug);

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

  /// Syncs the Supabase user ID with RevenueCat so that purchases are tracked per-user.
  static Future<void> _syncUserIfLoggedIn() async {
    if (kIsWeb) return;
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser != null) {
      try {
        await Purchases.logIn(currentUser.id);
      } catch (e) {
        debugPrint('RevenueCat login failed: \$e');
      }
    }
  }

  /// Logs the user into RevenueCat (Call this immediately after Supabase login)
  static Future<void> login(String userId) async {
    if (kIsWeb) return;
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('RevenueCat login failed: \$e');
    }
  }

  /// Logs the user out of RevenueCat (Call this immediately after Supabase logout)
  static Future<void> logout() async {
    if (kIsWeb) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('RevenueCat logout failed: \$e');
    }
  }

  /// Fetches all active packages available for purchase (e.g. 500 K-Coin Pack)
  static Future<List<Package>> getKCoinPackages() async {
    if (kIsWeb) return [];
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        return offerings.current!.availablePackages;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching offerings: \$e');
      return [];
    }
  }

  /// Triggers the native Apple/Google purchase flow
  static Future<bool> purchasePackage(Package package) async {
    if (kIsWeb) {
      debugPrint('In-App Purchases are not supported on web natively. Use Stripe Checkout instead.');
      return false;
    }
    
    try {
      // This will show the native OS payment sheet (FaceID/Fingerprint)
      await Purchases.purchasePackage(package);
      
      // If payment is successful, RevenueCat backend immediately triggers your Supabase Webhook. 
      // The Webhook grants the K-Coins.
      return true;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase error: \$e');
      }
      return false;
    } catch (e) {
      debugPrint('Unknown purchase error: \$e');
      return false;
    }
  }
}
