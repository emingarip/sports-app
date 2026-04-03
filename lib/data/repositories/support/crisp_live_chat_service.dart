import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crisp_chat/crisp_chat.dart';
import 'live_chat_service.dart';

class CrispLiveChatService implements LiveChatService {
  late final String _websiteId;

  @override
  Future<void> initialize() async {
    _websiteId = dotenv.env['CRISP_WEBSITE_ID'] ?? '';
  }

  @override
  Future<void> openChat(BuildContext context) async {
    if (_websiteId.isEmpty) {
      debugPrint('Crisp Website ID is empty. Cannot open chat.');
      return;
    }

    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sağ alt köşedeki destek ikonuna tıklayarak işlemi başlatabilirsiniz.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Mobile specific (Android/iOS)
    final config = CrispConfig(websiteID: _websiteId);
    await FlutterCrispChat.openCrispChat(config: config);
  }
}
