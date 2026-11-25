import 'package:flutter/material.dart';

import '../models/dday.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
import 'countdown_badge.dart';

/// Precomputed display values for one D-Day, independent of theme.
@immutable
class DdayCardData {
  const DdayCardData({
    required this.item,
    required this.badge,
    required this.subtitle,
    required this.isToday,
  });

  factory DdayCardData.fromItem(DdayItem item, DateTime today) {
    final diff = effectiveDayDiff(item, today: today);
    final displayDate = formatDisplayDateZh(effectiveTargetDate(item, today: today));
    final repeatNote = anniversarySubtitle(item, today: today);
    return DdayCardData(
      item: item,
      badge: formatCountdown(item, today: today),
      subtitle: repeatNote == null ? displayDate : '$displayDate・$repeatNote',
      isToday: diff == 0 && !item.countFromOne,
    );
  }

  final DdayItem item;
  final String badge;
  final String subtitle;
  final bool isToday;
}

/// Screen-reader summary of a card, e.g. `期末考，2026/12/25 (五)，D-30，已置頂`.
String ddaySemanticLabel({
  required String title,
  required String subtitle,
  required String badge,
  bool pinned = false,
}) {
  final parts = <String>[title, subtitle, badge, if (pinned) '已置頂'];
  return parts.join('，');
}

/// The three places a D-Day card is drawn.
enum DdayCardVariant {
  /// Interactive card in the home list.
  list,

  /// Live preview at the top of the edit screen.
  editPreview,

  /// Home-screen widget preview in settings.
  widgetPreview,
}

/// Shared D-Day card used by the home list, edit preview and widget preview.
///
/// Each variant reproduces the layout it replaced exactly; semantics expose a
/// single summary label, and tap / long-press hints only when interactive.
class DdayCard extends StatelessWidget {
  const DdayCard({
    super.key,
    required this.variant,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.colors,
    this.pinned = false,
    this.showAccentBar = true,
    this.repeatYearly = false,
    this.hasReminders = false,
    this.onTap,
    this.onLongPress,
    this.badgeKey,
    this.boxKey,
  });

  static const String longPressHint = '開啟選單：置頂或刪除';

  final DdayCardVariant variant;
  final String title;
  final String subtitle;
  final String badge;
  final DdayResolvedColors colors;
  final bool pinned;
  final bool showAccentBar;
  final bool repeatYearly;
  final bool hasReminders;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Key placed on the badge text (kept for existing tests).
  final Key? badgeKey;

  /// Key placed on the widget-preview box (kept for existing tests).
  final Key? boxKey;

  @override
  Widget build(BuildContext context) {
    final card = switch (variant) {
      DdayCardVariant.list => _buildList(context),
      DdayCardVariant.editPreview => _buildEditPreview(context),
      DdayCardVariant.widgetPreview => _buildWidgetPreview(context),
    };

    final label = ddaySemanticLabel(
      title: title,
      subtitle: subtitle,
      badge: badge,
      pinned: pinned,
    );

    if (onTap == null && onLongPress == null) {
      // Static previews: one read-only summary, no interaction hints.
      return Semantics(container: true, label: label, child: card);
    }

    // The focusable InkWell forms its own node; merging folds its tap and
    // long-press actions into the same node as the summary label.
    return MergeSemantics(
      child: Semantics(
        label: label,
        button: onTap != null ? true : null,
        onLongPressHint: onLongPress != null ? longPressHint : null,
        child: card,
      ),
    );
  }

  Widget _badge(CountdownBadgeSize size) {
    return CountdownBadge(
      text: badge,
      background: colors.badgeBackground,
      foreground: colors.badgeForeground,
      size: size,
      textKey: badgeKey,
    );
  }

  Widget _accentBar(double height) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: colors.accentColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      semanticContainer: false,
      color: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (showAccentBar) ...[
                  _accentBar(40),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (pinned) ...[
                            Icon(
                              Icons.push_pin,
                              size: 16,
                              color: colors.accentColor,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (repeatYearly) ...[
                            Icon(
                              Icons.repeat,
                              size: 14,
                              color: colors.accentColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (hasReminders) ...[
                            Icon(
                              Icons.notifications_active_outlined,
                              size: 14,
                              color: colors.accentColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _badge(CountdownBadgeSize.regular),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      semanticContainer: false,
      color: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderColor),
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '即時預覽',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.accentColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _badge(CountdownBadgeSize.regular),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWidgetPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: boxKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderColor),
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            _accentBar(36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pinned ? '📌 $title' : title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _badge(CountdownBadgeSize.compact),
          ],
        ),
      ),
    );
  }
}
