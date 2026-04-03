import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart' show debugPrint;

final bugReportServiceProvider = Provider((ref) => BugReportService());

class BugReportService {
  final _client = Supabase.instance.client;

  Future<void> submitFeedback(String message, Uint8List? screenshot) async {
    try {
      String? screenshotUrl;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      
      // Upload screenshot if provided
      if (screenshot != null) {
        final path = '$userId/feedback_$timestamp.png';
        const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nigatikzsnxdqdwwqewr.supabase.co');
        final url = Uri.parse('$supabaseUrl/storage/v1/object/feedback-screenshots/$path');
        
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
          screenshotUrl = '$supabaseUrl/storage/v1/object/public/feedback-screenshots/$path';
        } else {
          debugPrint('Screenshot upload failed: ${response.statusCode} - ${response.body}');
        }
      }

      String osVersion = 'Unknown';
      String deviceModel = 'Unknown';
      String appVersion = 'Unknown';

      // Get App Version
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (_) {}

      // Get Device Info
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

      // Save to Supabase
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
