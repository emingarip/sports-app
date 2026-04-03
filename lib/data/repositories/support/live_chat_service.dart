import 'package:flutter/material.dart';

abstract class LiveChatService {
  /// Initializes the live chat service with required credentials
  Future<void> initialize();

  /// Opens the live chat UI.
  /// Needs context for potential web fallbacks or modal presentations.
  Future<void> openChat(BuildContext context);
}
