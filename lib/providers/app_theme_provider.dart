import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_theme_definition.dart';
import '../models/store_product.dart';
import '../models/user_entitlement.dart';
import '../services/app_theme_preferences.dart';
import '../services/supabase_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'store_provider.dart';

part 'app_theme_provider.g.dart';

class AppThemeState {
  final ThemeMode themeMode;
  final String activeThemeCode;
  final AppThemeDefinition? activeThemeDefinition;
  final bool isSyncing;

  const AppThemeState({
    required this.themeMode,
    required this.activeThemeCode,
    required this.activeThemeDefinition,
    required this.isSyncing,
  });

  bool get isClassicTheme => activeThemeCode == AppTheme.classicThemeCode;

  AppThemeState copyWith({
    ThemeMode? themeMode,
    String? activeThemeCode,
    AppThemeDefinition? activeThemeDefinition,
    bool resetActiveThemeDefinition = false,
    bool? isSyncing,
  }) {
    return AppThemeState(
      themeMode: themeMode ?? this.themeMode,
      activeThemeCode: activeThemeCode ?? this.activeThemeCode,
      activeThemeDefinition: resetActiveThemeDefinition
          ? null
          : (activeThemeDefinition ?? this.activeThemeDefinition),
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

@riverpod
ThemeService? themeService(Ref ref) {
  try {
    return ThemeService(SupabaseService.client);
  } catch (_) {
    return null;
  }
}

@Riverpod(keepAlive: true)
class ThemeCatalog extends _$ThemeCatalog {
  @override
  Future<List<AppThemeDefinition>> build() async {
    final service = ref.watch(themeServiceProvider);
    if (service == null) {
      return [];
    }

    return service.getPublishedThemes();
  }
}

@riverpod
Set<String> ownedThemeCodes(Ref ref) {
  final entitlements =
      ref.watch(entitlementsProvider).asData?.value ??
      const <UserEntitlement>[];
  final products =
      ref.watch(storeProductsProvider).asData?.value ?? const <StoreProduct>[];
  final ownedProductCodes = entitlements
      .where((entitlement) => entitlement.isValid)
      .map((entitlement) => entitlement.productCode)
      .toSet();

  final ownedThemeCodes = <String>{AppTheme.classicThemeCode};
  for (final product in products) {
    if (!product.isThemeProduct ||
        product.themeCode == null ||
        !ownedProductCodes.contains(product.productCode)) {
      continue;
    }

    ownedThemeCodes.add(product.themeCode!);
  }

  return ownedThemeCodes;
}

@Riverpod(keepAlive: true)
class AppThemeController extends _$AppThemeController {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  AppThemeState build() {
    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    _registerAuthListener();
    Future<void>.microtask(syncWithRemote);

    final hasAuthenticatedUser = _resolveClient()?.auth.currentUser != null;
    final cachedThemeCode = hasAuthenticatedUser
        ? AppThemePreferences.activeThemeCode
        : AppTheme.classicThemeCode;
    final cachedDefinition =
        hasAuthenticatedUser && cachedThemeCode != AppTheme.classicThemeCode
            ? AppThemePreferences.cachedActiveThemeDefinition
            : null;

    return AppThemeState(
      themeMode: AppThemePreferences.themeMode,
      activeThemeCode: cachedThemeCode,
      activeThemeDefinition: cachedDefinition,
      isSyncing: false,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await AppThemePreferences.setThemeMode(mode);
  }

  Future<void> applyTheme(String themeCode) async {
    if (themeCode == AppTheme.classicThemeCode) {
      await _applyClassicTheme();
      return;
    }

    final service = ref.read(themeServiceProvider);
    if (service == null) {
      throw Exception('Theme service is unavailable.');
    }

    final currentUser = _resolveClient()?.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please sign in before applying premium themes.');
    }

    state = state.copyWith(isSyncing: true);
    try {
      final result = await service.setActiveTheme(themeCode);
      if (result['success'] != true) {
        throw Exception(
          result['error']?.toString() ?? 'Theme could not be applied.',
        );
      }

      final definition = await service.getThemeByCode(themeCode);
      if (definition == null) {
        throw Exception('Theme definition is not available.');
      }

      await _setResolvedTheme(
        activeThemeCode: themeCode,
        definition: definition,
      );
    } finally {
      if (state.isSyncing) {
        state = state.copyWith(isSyncing: false);
      }
    }
  }

  Future<void> syncWithRemote() async {
    final client = _resolveClient();
    final service = ref.read(themeServiceProvider);
    if (client == null || service == null) {
      return;
    }

    final user = client.auth.currentUser;
    if (user == null) {
      if (!state.isClassicTheme) {
        await _setResolvedTheme(
          activeThemeCode: AppTheme.classicThemeCode,
          definition: null,
        );
      }
      return;
    }

    state = state.copyWith(isSyncing: true);
    try {
      final profile = await SupabaseService().getUserProfile(user.id);
      final remoteThemeCode =
          (profile?['active_theme_code'] as String?)?.trim().isNotEmpty == true
              ? profile!['active_theme_code'] as String
              : AppTheme.classicThemeCode;

      if (remoteThemeCode == AppTheme.classicThemeCode) {
        await _setResolvedTheme(
          activeThemeCode: AppTheme.classicThemeCode,
          definition: null,
        );
        return;
      }

      final definition = await service.getThemeByCode(remoteThemeCode);
      if (definition == null) {
        await _setResolvedTheme(
          activeThemeCode: AppTheme.classicThemeCode,
          definition: null,
        );
        return;
      }

      await _setResolvedTheme(
        activeThemeCode: remoteThemeCode,
        definition: definition,
      );
    } finally {
      if (state.isSyncing) {
        state = state.copyWith(isSyncing: false);
      }
    }
  }

  Future<void> refreshCatalog() async {
    ref.invalidate(themeCatalogProvider);
    await ref.read(themeCatalogProvider.future);
  }

  void _registerAuthListener() {
    if (_authSubscription != null) {
      return;
    }

    final client = _resolveClient();
    if (client == null) {
      return;
    }

    _authSubscription = client.auth.onAuthStateChange.listen((_) {
      unawaited(syncWithRemote());
    });
  }

  SupabaseClient? _resolveClient() {
    try {
      return SupabaseService.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyClassicTheme() async {
    final service = ref.read(themeServiceProvider);
    final user = _resolveClient()?.auth.currentUser;

    state = state.copyWith(isSyncing: true);
    try {
      if (service != null && user != null) {
        final result = await service.setActiveTheme(AppTheme.classicThemeCode);
        if (result['success'] != true) {
          throw Exception(
            result['error']?.toString() ??
                'Classic theme could not be applied.',
          );
        }
      }

      await _setResolvedTheme(
        activeThemeCode: AppTheme.classicThemeCode,
        definition: null,
      );
    } finally {
      if (state.isSyncing) {
        state = state.copyWith(isSyncing: false);
      }
    }
  }

  Future<void> _setResolvedTheme({
    required String activeThemeCode,
    required AppThemeDefinition? definition,
  }) async {
    state = state.copyWith(
      activeThemeCode: activeThemeCode,
      activeThemeDefinition: definition,
      resetActiveThemeDefinition: definition == null,
      isSyncing: false,
    );
    await AppThemePreferences.setActiveThemeCode(activeThemeCode);
    await AppThemePreferences.setCachedActiveThemeDefinition(definition);
  }
}

@riverpod
ThemeData resolvedLightTheme(Ref ref) {
  final themeState = ref.watch(appThemeControllerProvider);
  return AppTheme.buildTheme(
    brightness: Brightness.light,
    definition: themeState.activeThemeDefinition,
  );
}

@riverpod
ThemeData resolvedDarkTheme(Ref ref) {
  final themeState = ref.watch(appThemeControllerProvider);
  return AppTheme.buildTheme(
    brightness: Brightness.dark,
    definition: themeState.activeThemeDefinition,
  );
}
