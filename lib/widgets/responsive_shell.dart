import 'package:flutter/material.dart';

/// Caps content width on wide viewports.
///
/// boskale.com is a web product, but the betting-analysis screens (bulletin,
/// coupon builder, bankroll, analysis, coupon feed, tipster profile) shipped
/// without any width constraint while the older screens all had one. On a
/// 1920px display their odds rows and coupon lines stretched the full width,
/// which is unreadable. This is the single place that decides how wide a
/// column may get, so the two halves of the app stop disagreeing.
///
/// [maxWidth] defaults to the same 600px the bottom navigation already uses in
/// `main_layout.dart`; screens with denser tables can widen it deliberately.
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({
    super.key,
    required this.child,
    this.maxWidth = defaultMaxWidth,
  });

  /// Matches `_shellMaxWidth` in `main_layout.dart`.
  static const double defaultMaxWidth = 600;

  /// For screens that carry side-by-side comparison tables.
  static const double wideMaxWidth = 760;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
