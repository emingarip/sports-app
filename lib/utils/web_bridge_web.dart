import 'dart:html' as html;

void listenToWebMessages(void Function(String message) onMessageReceived) {
  html.window.onMessage.listen((event) {
    if (event.origin != 'https://games.boskale.com' && !event.origin.contains('localhost')) {
      return; 
    }
    if (event.data is String) {
      onMessageReceived(event.data as String);
    }
  });
}

void sendToWebGame(String type, String token) {
  // Find iframe and postMessage
  final iframes = html.document.getElementsByTagName('iframe');
  for (var frame in iframes) {
    if (frame is html.IFrameElement) {
      frame.contentWindow?.postMessage('{"type":"$type","token":"$token"}', 'https://games.boskale.com');
    }
  }
}
