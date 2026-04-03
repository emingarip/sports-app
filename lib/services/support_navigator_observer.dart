import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/support_providers.dart';

class SupportNavigatorObserver extends NavigatorObserver {
  final WidgetRef ref;

  SupportNavigatorObserver(this.ref);

  // List of route names where the support button should be hidden
  static const Set<String> hiddenRoutes = {
    'splash',
    'login',
    'verification',
    'success',
    'private_chat',
  };

  void _updateVisibility(Route<dynamic>? route) {
    if (route == null) return;
    
    final name = route.settings.name;
    final shouldHide = hiddenRoutes.contains(name);
    
    // Using microtask to avoid building during navigation
    Future.microtask(() {
      ref.read(supportButtonVisibilityProvider.notifier).setVisible(!shouldHide);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateVisibility(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateVisibility(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateVisibility(newRoute);
  }
}
