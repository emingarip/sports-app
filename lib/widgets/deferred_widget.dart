import 'package:flutter/material.dart';

/// Dynamically loads a deferred Dart library and renders a loading spinner 
/// while the browser fetches the specific `.wasm` / `.js` bundle fragment.
class DeferredWidget extends StatefulWidget {
  final Future<void> Function() libraryLoader;
  final Widget Function() createWidget;
  final Widget? placeholder;

  const DeferredWidget({
    super.key,
    required this.libraryLoader,
    required this.createWidget,
    this.placeholder,
  });

  @override
  State<DeferredWidget> createState() => _DeferredWidgetState();
}

class _DeferredWidgetState extends State<DeferredWidget> {
  Widget? _loadedWidget;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      await widget.libraryLoader();
      if (mounted) {
        setState(() {
          _loadedWidget = widget.createWidget();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint("Failed to load deferred library: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          const Center(
            child: CircularProgressIndicator(),
          );
    }
    
    if (_loadedWidget == null) {
      return const Center(child: Text("Sayfa yüklenemedi."));
    }

    return _loadedWidget!;
  }
}
