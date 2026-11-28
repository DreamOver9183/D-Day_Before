import 'package:flutter/material.dart';

/// Size presets for the day count.
enum CountdownBadgeSize {
  /// Home list and edit preview.
  regular,

  /// Settings widget preview.
  compact,
}

/// The day count (`D-30`, `D-Day`, `365天`) drawn as large colored text.
///
/// On the day itself it sits in a filled pill so it stands out. Scales down
/// instead of overflowing when the system font is very large.
class CountdownBadge extends StatelessWidget {
  const CountdownBadge({
    super.key,
    required this.text,
    required this.color,
    this.highlighted = false,
    this.highlightBackground,
    this.highlightForeground,
    this.size = CountdownBadgeSize.regular,
    this.textKey,
  });

  static const double maxWidth = 150;

  final String text;
  final Color color;
  final bool highlighted;
  final Color? highlightBackground;
  final Color? highlightForeground;
  final CountdownBadgeSize size;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = size == CountdownBadgeSize.compact;
    final baseStyle = compact
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleLarge;
    final pill = highlighted && highlightBackground != null;

    Widget label = Text(
      text,
      key: textKey,
      maxLines: 1,
      style: baseStyle?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: pill ? highlightForeground : color,
      ),
    );
    if (pill) {
      label = DecoratedBox(
        decoration: BoxDecoration(
          color: highlightBackground,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 3 : 4,
          ),
          child: label,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(fit: BoxFit.scaleDown, child: label),
    );
  }
}
