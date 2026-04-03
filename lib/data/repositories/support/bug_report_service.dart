import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final bugReportServiceProvider = Provider((ref) => BugReportService());

class BugReportService {
  final _client = Supabase.instance.client;

  Future<void> submitFeedback(String message, Uint8List? screenshot) async {
    try {
      String? screenshotUrl;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = _client.auth.currentUser?.id ?? 'anonymous';

      if (screenshot != null) {
        final path = '$userId/feedback_$timestamp.png';
        const supabaseUrl = SupabaseService.projectUrl;
        if (supabaseUrl.isEmpty) {
          throw StateError('SUPABASE_URL is not configured.');
        }

        final url = Uri.parse(
            '$supabaseUrl/storage/v1/object/feedback-screenshots/$path');
        final accessToken = _client.auth.currentSession?.accessToken;
        final headers = {
          'Content-Type': 'image/png',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        };

        final response = await http.post(
          url,
          headers: headers,
          body: screenshot,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          screenshotUrl = path;
        } else {
          debugPrint(
              'Screenshot upload failed: ${response.statusCode} - ${response.body}');
        }
      }

      String osVersion = 'Unknown';
      String deviceModel = 'Unknown';
      String appVersion = 'Unknown';

      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (_) {}

      try {
        final deviceInfo = DeviceInfoPlugin();
        if (kIsWeb) {
          osVersion = 'Web';
        } else if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          osVersion = 'Android ${androidInfo.version.release}';
          deviceModel = '${androidInfo.brand} ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          osVersion = 'iOS ${iosInfo.systemVersion}';
          deviceModel = iosInfo.utsname.machine;
        }
      } catch (_) {}

      await _client.from('feedbacks').insert({
        'user_id': _client.auth.currentUser?.id,
        'feedback_type': 'feedback',
        'message': message,
        'screenshot_url': screenshotUrl,
        'app_version': appVersion,
        'os_version': osVersion,
        'device_info': {'model': deviceModel},
        'status': 'new',
      });
    } catch (e) {
      throw Exception('Geri bildirim gönderilemedi: $e');
    }
  }
}
