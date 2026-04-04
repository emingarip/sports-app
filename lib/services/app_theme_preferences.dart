import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_theme_definition.dart';
import '../theme/app_theme.dart';

class AppThemePreferences {
  static SharedPreferences? _prefs;

  static const _themeModeKey = 'theme_mode';
  static const _activeThemeCodeKey = 'active_theme_code';
  static const _activeThemeDefinitionKey = 'active_theme_definition_json';

  static Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static ThemeMode get themeMode {
    final raw = _prefs?.getString(_themeModeKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString(_themeModeKey, _themeModeToString(mode));
  }

  static String get activeThemeCode =>
      _prefs?.getString(_activeThemeCodeKey) ?? AppTheme.classicThemeCode;

  static Future<void> setActiveThemeCode(String themeCode) async {
    await _prefs?.setString(_activeThemeCodeKey, themeCode);
  }

  static AppThemeDefinition? get cachedActiveThemeDefinition {
    final raw = _prefs?.getString(_activeThemeDefinitionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AppThemeDefinition.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCachedActiveThemeDefinition(
    AppThemeDefinition? definition,
  ) async {
    if (definition == null) {
      await _prefs?.remove(_activeThemeDefinitionKey);
      return;
    }

    await _prefs?.setString(
      _activeThemeDefinitionKey,
      jsonEncode(definition.toJson()),
    );
  }

  static Future<void> clearPremiumThemeCache() async {
    await _prefs?.remove(_activeThemeCodeKey);
    await _prefs?.remove(_activeThemeDefinitionKey);
  }

  static String _themeModeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
