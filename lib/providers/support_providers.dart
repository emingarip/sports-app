import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/support/live_chat_service.dart';
import '../data/repositories/support/crisp_live_chat_service.dart';

final liveChatServiceProvider = Provider<LiveChatService>((ref) {
  final service = CrispLiveChatService();
  service.initialize();
  return service;
});
