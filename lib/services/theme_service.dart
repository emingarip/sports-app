import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_theme_definition.dart';

class ThemeService {
  final SupabaseClient _client;

  ThemeService(this._client);

  Future<List<AppThemeDefinition>> getPublishedThemes() async {
    final response = await _client
        .from('app_themes')
        .select()
        .eq('is_active', true)
        .eq('status', 'published')
        .order('name', ascending: true);

    return (response as List)
        .map((json) => AppThemeDefinition.fromJson(
              Map<String, dynamic>.from(json as Map),
            ))
        .toList();
  }

  Future<AppThemeDefinition?> getThemeByCode(String themeCode) async {
    final response = await _client
        .from('app_themes')
        .select()
        .eq('theme_code', themeCode)
        .eq('is_active', true)
        .eq('status', 'published')
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return AppThemeDefinition.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<Map<String, dynamic>> setActiveTheme(String themeCode) async {
    final response = await _client.rpc(
      'set_active_theme',
      params: {'p_theme_code': themeCode},
    );

    if (response is Map<String, dynamic>) {
      return response;
    }

    if (response is Map) {
      return response.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return <String, dynamic>{'success': false};
  }
}
