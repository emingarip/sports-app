import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/match.dart' as model;
import '../providers/favorites_provider.dart';
import '../screens/match_detail_screen.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import 'notification_permission_dialog.dart';

class MatchCard extends ConsumerWidget {
  final model.Match match;
  final bool hasBorder;
  final String? reasonLabel;
  final String? statusLabel;
  final String? secondaryLabel;
  final String? highlightQuery;

  const MatchCard({
    super.key,
    required this.match,
    required this.hasBorder,
    this.reasonLabel,
    this.statusLabel,
    this.secondaryLabel,
    this.highlightQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = match.status == model.MatchStatus.live;
    final isFavorite = ref.watch(favoritesProvider).contains(match.id);
    final effectiveStatusLabel = statusLabel ?? _defaultStatusLabel(match);
    final normalizedHighlightQuery = highlightQuery?.trim() ?? '';
    final leagueName = match.leagueName?.trim() ?? '';
    final showLeagueContext =
        normalizedHighlightQuery.isNotEmpty && leagueName.isNotEmpty;
    final teamNameStyle = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final teamHighlightStyle = teamNameStyle.copyWith(
      color: context.colors.onPrimaryContainer,
      backgroundColor: context.colors.primaryContainer,
      fontWeight: FontWeight.w900,
      decoration: TextDecoration.underline,
      decorationColor: context.colors.primary,
      decorationThickness: 2,
    );

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatchDetailScreen(match: match)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          border: hasBorder
              ? Border(
                  bottom: BorderSide(color: context.colors.surfaceContainerLow),
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLeagueContext) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 56,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        context.colors.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: context.colors.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 12,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Lig: ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: context.colors.textMedium,
                        ),
                      ),
                      Flexible(
                        child: _buildHighlightedText(
                          context,
                          leagueName,
                          query: normalizedHighlightQuery,
                          baseStyle: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textHigh,
                          ),
                          highlightStyle: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: context.colors.onPrimaryContainer,
                            backgroundColor: context.colors.primaryContainer,
                            decoration: TextDecoration.underline,
                            decorationColor: context.colors.primary,
                            decorationThickness: 2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  child: isLive
                      ? PulsingLiveText(
                          child: Column(
                            children: [
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: context.colors.error,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                effectiveStatusLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: context.colors.error,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Text(
                              effectiveStatusLabel.replaceAll(' ', '\n'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: context.colors.textLow,
                                letterSpacing: 0.5,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Hero(
                              tag: 'match-${match.id}-home-logo',
                              child: Material(
                                color: Colors.transparent,
                                child: Image.network(
                                  match.homeLogo,
                                  width: 28,
                                  height: 28,
                                  errorBuilder: (ctx, err, _) =>
                                      const Icon(Icons.shield),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildHighlightedText(
                              context,
                              match.homeTeam,
                              query: normalizedHighlightQuery,
                              baseStyle: teamNameStyle,
                              highlightStyle: teamHighlightStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: match.status == model.MatchStatus.upcoming
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: context.colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: context.colors.textLow,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              )
                            : FittedBox(
                                child: Row(
                                  children: [
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      transitionBuilder: (child, animation) {
                                        return ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        );
                                      },
                                      child: Text(
                                        match.homeScore ?? '-',
                                        key: ValueKey(match.homeScore),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: isLive
                                              ? context.colors.textHigh
                                              : context.colors.textLow,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '-',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: context.colors.surfaceContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      transitionBuilder: (child, animation) {
                                        return ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        );
                                      },
                                      child: Text(
                                        match.awayScore ?? '-',
                                        key: ValueKey(match.awayScore),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: context.colors.textHigh,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Hero(
                              tag: 'match-${match.id}-away-logo',
                              child: Material(
                                color: Colors.transparent,
                                child: Image.network(
                                  match.awayLogo,
                                  width: 28,
                                  height: 28,
                                  errorBuilder: (ctx, err, _) =>
                                      const Icon(Icons.shield),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildHighlightedText(
                              context,
                              match.awayTeam,
                              query: normalizedHighlightQuery,
                              baseStyle: teamNameStyle,
                              highlightStyle: teamHighlightStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    ref
                        .read(favoritesProvider.notifier)
                        .toggleFavorite(match.id);
                    if (!isFavorite) {
                      await Future.delayed(const Duration(milliseconds: 200));
                      if (!context.mounted) return;
                      final notDetermined = await ref
                          .read(pushNotificationServiceProvider)
                          .isPermissionNotDetermined();
                      if (notDetermined && context.mounted) {
                        await NotificationPermissionDialog.show(context);
                      }
                    }
                  },
                  padding: const EdgeInsets.all(12.0),
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite
                        ? context.colors.primary
                        : context.colors.textLow,
                    size: 24,
                  ),
                )
              ],
            ),
            if (reasonLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (reasonLabel != null) _ReasonChip(label: reasonLabel!),
                  if (secondaryLabel != null)
                    Text(
                      secondaryLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textMedium,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _defaultStatusLabel(model.Match match) {
    final isLive = match.status == model.MatchStatus.live;
    if (isLive) return match.liveMinute ?? 'LIVE';
    if (match.status == model.MatchStatus.finished) return 'Full Time';
    return _formatTime(match.startTime);
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildHighlightedText(
    BuildContext context,
    String text, {
    required String query,
    required TextStyle baseStyle,
    required TextStyle highlightStyle,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign? textAlign,
  }) {
    if (query.trim().isEmpty || !_hasHighlightMatch(text, query)) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final ranges = _buildHighlightRanges(text, query);
    if (ranges.every((highlighted) => !highlighted)) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    var activeHighlight = ranges.first;

    for (var index = 0; index < text.length; index++) {
      final nextHighlight = ranges[index];
      if (nextHighlight != activeHighlight) {
        spans.add(
          TextSpan(
            text: buffer.toString(),
            style: activeHighlight ? highlightStyle : baseStyle,
          ),
        );
        buffer.clear();
        activeHighlight = nextHighlight;
      }
      buffer.write(text[index]);
    }

    if (buffer.isNotEmpty) {
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: activeHighlight ? highlightStyle : baseStyle,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  bool _hasHighlightMatch(String text, String query) {
    if (text.isEmpty || query.trim().isEmpty) {
      return false;
    }

    final normalizedText = text.toLowerCase();
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    return tokens.any(normalizedText.contains);
  }

  List<bool> _buildHighlightRanges(String text, String query) {
    final normalizedText = text.toLowerCase();
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList()
      ..sort((left, right) => right.length.compareTo(left.length));

    final highlights = List<bool>.filled(text.length, false);

    for (final token in tokens) {
      var searchStart = 0;
      while (searchStart < normalizedText.length) {
        final matchIndex = normalizedText.indexOf(token, searchStart);
        if (matchIndex == -1) {
          break;
        }

        final matchEnd = (matchIndex + token.length).clamp(0, text.length);
        for (var index = matchIndex; index < matchEnd; index++) {
          highlights[index] = true;
        }
        searchStart = matchIndex + token.length;
      }
    }

    return highlights;
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;

  const _ReasonChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isCritical = label == 'Canli kritik';
    final isSoon = label == 'Yakinda basliyor';

    final backgroundColor = isCritical
        ? context.colors.error.withValues(alpha: 0.12)
        : isSoon
            ? context.colors.secondaryContainer.withValues(alpha: 0.22)
            : context.colors.primaryContainer;
    final foregroundColor = isCritical
        ? context.colors.error
        : isSoon
            ? context.colors.secondaryContainer
            : context.colors.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class PulsingLiveText extends StatefulWidget {
  final Widget child;

  const PulsingLiveText({super.key, required this.child});

  @override
  State<PulsingLiveText> createState() => _PulsingLiveTextState();
}

class _PulsingLiveTextState extends State<PulsingLiveText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    var isTest = false;
    try {
      if (!kIsWeb) isTest = Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {}

    if (!isTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: widget.child,
    );
  }
}
