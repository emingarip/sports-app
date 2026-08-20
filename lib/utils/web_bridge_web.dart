import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementation of the mini-game bridge.
///
/// Uses `package:web` + `dart:js_interop`; `dart:html` is deprecated and is
/// not available under Wasm, which `deploy/publish.ps1` now builds with.
void listenToWebMessages(void Function(String message) onMessageReceived) {
  web.window.onMessage.listen((web.MessageEvent event) {
    if (!_isTrustedOrigin(event.origin)) return;
    final data = event.data;
    if (data.isA<JSString>()) {
      onMessageReceived((data as JSString).toDart);
    }
  });
}

void sendToWebGame(String type, String accessToken, String refreshToken) {
  final payload = jsonEncode({
    'type': type,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  });

  final iframes = web.document.getElementsByTagName('iframe');
  for (var i = 0; i < iframes.length; i++) {
    final element = iframes.item(i);
    if (element is web.HTMLIFrameElement) {
      element.contentWindow?.postMessage(
        payload.toJS,
        _gamesOrigin.toJS,
      );
    }
  }
}

const String _gamesOrigin = 'https://games.boskale.com';

/// Exact-match origins only. A substring check on "localhost" would trust
/// `https://localhost.example.com`, which an attacker can register.
bool _isTrustedOrigin(String origin) {
  if (origin == _gamesOrigin) return true;
  final uri = Uri.tryParse(origin);
  return uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
}
