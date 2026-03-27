import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../utils/web_bridge.dart';

class MiniGameScreen extends StatefulWidget {
  final String roomId;
  final String gameId;
  
  const MiniGameScreen({super.key, required this.roomId, required this.gameId});

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
    }

    // Determine URL based on platform or use the Vercel production URL
    String gameUrl = 'https://sports-app-psi.vercel.app/';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
       gameUrl = 'http://10.0.2.2:5175/';
    }
    
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      gameUrl = '$gameUrl?token=${session.accessToken}&roomId=${widget.roomId}&gameId=${widget.gameId}';
    }

    // Use cleartext HTTP for local dev
    _controller.loadRequest(Uri.parse(gameUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for games
      appBar: AppBar(
        title: const Text('Canlı Maç Etkinliği', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          SafeArea(
             top: false,
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
        ],
      ),
    );
  }
}
