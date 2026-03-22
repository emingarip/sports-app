import 'package:flutter/material.dart';

/// An alternative to `IndexedStack` that only initializes its children 
/// when their index becomes active for the very first time.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final StackFit sizing;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.sizing = StackFit.loose,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late List<bool> _initializedChildren;

  @override
  void initState() {
    super.initState();
    _initializedChildren = List.generate(
      widget.children.length,
      (index) => index == widget.index,
    );
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.length != oldWidget.children.length) {
      _initializedChildren = List.generate(
        widget.children.length,
        (index) => index == widget.index,
      );
    } else {
      _initializedChildren[widget.index] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      alignment: widget.alignment,
      textDirection: widget.textDirection,
      sizing: widget.sizing,
      children: List.generate(widget.children.length, (i) {
        if (_initializedChildren[i]) {
          return widget.children[i];
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }
}
