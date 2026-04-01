import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  // Key for storing the referrer ID
  static const String _referrerKey = 'referral_inviter_id';

  Future<void> initialize() async {
    _appLinks = AppLinks();

    // Check initial link if app was cold-started
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("AppLinks cold start init error: $e");
    }

    // Listen to incoming links while app is open
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint("AppLinks captured URI: $uri");
    
    // Check for referral deep link e.g., sportsapp://invite?ref=USER_ID
    if (uri.queryParameters.containsKey('ref')) {
      final refId = uri.queryParameters['ref'];
      if (refId != null && refId.isNotEmpty) {
        debugPrint("Captured referral ID: $refId");
        await _saveReferrerId(refId);
      }
    }
  }

  Future<void> _saveReferrerId(String refId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_referrerKey, refId);
      debugPrint("Referrer ID $refId saved to SharedPreferences.");
    } catch (e) {
      debugPrint("Failed to save referrer ID: $e");
    }
  }

  Future<String?> getSavedReferrerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_referrerKey);
    } catch (e) {
      debugPrint("Failed to get referrer ID: $e");
      return null;
    }
  }

  Future<void> clearReferrerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_referrerKey);
      debugPrint("Referrer ID cleared from SharedPreferences.");
    } catch (e) {
      debugPrint("Failed to clear referrer ID: $e");
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
