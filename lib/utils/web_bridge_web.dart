import 'dart:convert';
import 'dart:html' as html;

void listenToWebMessages(void Function(String message) onMessageReceived) {
  html.window.onMessage.listen((event) {
    if (event.origin != 'https://games.boskale.com' &&
        !event.origin.contains('localhost')) {
      return;
    }
    if (event.data is String) {
      onMessageReceived(event.data as String);
    }
  });
}

void sendToWebGame(String type, String accessToken, String refreshToken) {
  final payload = jsonEncode({
    'type': type,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  });

  final iframes = html.document.getElementsByTagName('iframe');
  for (var frame in iframes) {
    if (frame is html.IFrameElement) {
      frame.contentWindow?.postMessage(payload, 'https://games.boskale.com');
    }
  }
}
