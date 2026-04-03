import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/web_bridge.dart';

class MiniGameScreen extends StatefulWidget {
  final String roomId;
  final String gameId;
  final String? gameType;

  const MiniGameScreen({
    super.key,
    required this.roomId,
    required this.gameId,
    this.gameType,
  });

  @override
  State<MiniGameScreen> createState() => _MiniGameScreenState();
}

class _MiniGameScreenState extends State<MiniGameScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController();

    try {
      if (!kIsWeb) {
        _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        _controller.setBackgroundColor(const Color(0x00000000));
      }

      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });

            if (!kIsWeb) {
              final session = Supabase.instance.client.auth.currentSession;
              final refreshToken = session?.refreshToken;
              if (session != null &&
                  refreshToken != null &&
                  refreshToken.isNotEmpty) {
                final payload = jsonEncode({
                  'type': 'INIT_AUTH',
                  'accessToken': session.accessToken,
                  'refreshToken': refreshToken,
                });
                _controller.runJavaScript(
                    "window.postMessage($payload, window.location.origin);");
              }
            }
          },
        ),
      );

      _controller.addJavaScriptChannel(
        'MiniGameBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            if (data['type'] == 'GAME_OVER' && !_hasPopped && mounted) {
              _hasPopped = true;
              Navigator.pop(context, data);
            }
          } catch (e) {
            debugPrint('Error parsing JS message: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('WebView configuration warning: $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    }

    if (kIsWeb) {
      listenToWebMessages((String msg) {
        try {
          final data = jsonDecode(msg);
          if (data['type'] == 'GAME_OVER' && mounted && !_hasPopped) {
            _hasPopped = true;
            Navigator.pop(context, data);
          }
        } catch (e) {
          debugPrint('Failed to parse web message: $e');
        }
      });

      final session = Supabase.instance.client.auth.currentSession;
      final refreshToken = session?.refreshToken;
      if (session != null && refreshToken != null && refreshToken.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), () {
          sendToWebGame('INIT_AUTH', session.accessToken, refreshToken);
        });
        Future.delayed(const Duration(seconds: 4), () {
          sendToWebGame('INIT_AUTH', session.accessToken, refreshToken);
        });
      }
    }

    String gameUrl = 'https://games.boskale.com/';
    gameUrl = '$gameUrl?roomId=${widget.roomId}&gameId=${widget.gameId}';
    if (widget.gameType != null) {
      gameUrl += '&gameType=${widget.gameType}';
    }

    _controller.loadRequest(Uri.parse(gameUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            top: false,
            bottom: false,
            child: WebViewWidget(controller: _controller),
          ),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 16),
                  Text('Oyun yükleniyor...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
