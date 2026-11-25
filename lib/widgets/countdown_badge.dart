import 'package:flutter/material.dart';

/// Size presets matching the two badge sizes used in the app.
enum CountdownBadgeSize {
  /// Home list and edit preview.
  regular,

  /// Settings widget preview.
  compact,
}

/// Rounded countdown label such as `D-30`, `D-Day` or `第 12 天`.
///
/// Scales down instead of overflowing when the system font is very large.
class CountdownBadge extends StatelessWidget {
  const CountdownBadge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.size = CountdownBadgeSize.regular,
    this.textKey,
  });

  static const double maxWidth = 140;

  final String text;
  final Color background;
  final Color foreground;
  final CountdownBadgeSize size;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = size == CountdownBadgeSize.compact;
    final baseStyle =
        compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
          ),
          child: Text(
            text,
            key: textKey,
            style: baseStyle?.copyWith(
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
