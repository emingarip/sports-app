import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../utils/web_bridge.dart';

class MiniGameScreen extends StatefulWidget {
  final String roomId;
  final String gameId;
  final String? gameType;
  
  const MiniGameScreen({super.key, required this.roomId, required this.gameId, this.gameType});

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
    
    // Create the WebView Controller
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
            // Native postMessage after load
            if (!kIsWeb) {
              final session = Supabase.instance.client.auth.currentSession;
              if (session != null) {
                _controller.runJavaScript("window.postMessage('{\"type\":\"INIT_AUTH\",\"token\":\"${session.accessToken}\"}', '*');");
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
              // Game finished, pop with data to show reward info
              Navigator.pop(context, data);
            }
          } catch (e) {
            debugPrint("Error parsing JS message: \$e");
          }
        },
      );
    } catch (e) {
      debugPrint("WebView Configuration Warning (Safe to ignore on web): \$e");
      // On web, sometimes these throw UnimplementedError. We still need to clear loading state.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() { _isLoading = false; });
        }
      });
    }

    // Set up Web message listener for Flutter Web iframe communication
    if (kIsWeb) {
      listenToWebMessages((String msg) {
        try {
          final data = jsonDecode(msg);
          if (data['type'] == 'GAME_OVER' && mounted && !_hasPopped) {
            _hasPopped = true;
            Navigator.pop(context, data);
          }
        } catch (e) {
          debugPrint("Failed to parse web message: \$e");
        }
      });
      
      // On web, we cannot use runJavaScript on the iframe directly via WebViewController 
      // when it's cross origin. We send it continuously until picked up or just after delay.
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        Future.delayed(const Duration(seconds: 2), () {
          sendToWebGame('INIT_AUTH', session.accessToken);
        });
        // Try again just in case it takes longer to load
        Future.delayed(const Duration(seconds: 4), () {
          sendToWebGame('INIT_AUTH', session.accessToken);
        });
      }
    }

    String gameUrl = 'https://games.boskale.com/';
    
    // Pass roomId and gameId in URL, NO SECRETS
    gameUrl = '$gameUrl?roomId=${widget.roomId}&gameId=${widget.gameId}';
    if (widget.gameType != null) {
      gameUrl += '&gameType=${widget.gameType}';
    }

    // Use cleartext HTTP for local dev
    _controller.loadRequest(Uri.parse(gameUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for games
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
                   Text("Oyun Yükleniyor...", style: TextStyle(color: Colors.white70))
                 ],
               )
             ),
          // Floating Back/Close Button
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
