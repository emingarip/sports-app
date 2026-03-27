import 'dart:html' as html;

void listenToWebMessages(void Function(String message) onMessageReceived) {
  html.window.onMessage.listen((event) {
    if (event.data is String) {
      onMessageReceived(event.data as String);
    }
  });
}
