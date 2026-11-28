import 'dart:io';

import 'package:flutter/material.dart';

import '../models/dday.dart';
import '../services/background_images.dart';
import '../theme/app_theme.dart';
import '../theme/dday_colors.dart';
import '../theme/dday_icons.dart';
import '../utils/day_calc.dart';
import 'countdown_badge.dart';
import 'soft_card.dart';

/// Precomputed display values for one D-Day, independent of theme.
@immutable
class DdayCardData {
  const DdayCardData({
    required this.item,
    required this.badge,
    required this.subtitle,
    required this.isToday,
    this.photo,
  });

  factory DdayCardData.fromItem(DdayItem item, DateTime today) {
    final diff = effectiveDayDiff(item, today: today);
    final displayDate = formatDisplayDateZh(
      effectiveTargetDate(item, today: today),
    );
    // The repeat icon already says "yearly", so keep only the anniversary count.
    final repeatNote = _shortAnniversary(
      anniversarySubtitle(item, today: today),
    );
    return DdayCardData(
      item: item,
      badge: formatCountdown(item, today: today),
      subtitle: repeatNote == null ? displayDate : '$displayDate・$repeatNote',
      isToday: diff == 0 && !item.countFromOne,
      photo: BackgroundImages.fileFor(item.backgroundImage),
    );
  }

  final DdayItem item;
  final String badge;
  final String subtitle;
  final bool isToday;

  /// Background photo on disk, or null (no photo, or file missing).
  final File? photo;
}

const String _repeatLabel = '每年重複';

String? _shortAnniversary(String? note) {
  if (note == null || note == _repeatLabel) return null;
  const prefix = '$_repeatLabel・';
  return note.startsWith(prefix) ? note.substring(prefix.length) : note;
}

/// Screen-reader summary of a card, e.g. `期末考，2026/12/25 (五)，D-30，已置頂`.
String ddaySemanticLabel({
  required String title,
  required String subtitle,
  required String badge,
  bool pinned = false,
  bool repeatYearly = false,
}) {
  final parts = <String>[
    title,
    subtitle,
    badge,
    if (repeatYearly && !subtitle.contains(_repeatLabel)) _repeatLabel,
    if (pinned) '已置頂',
  ];
  return parts.join('，');
}

/// The three places a D-Day is drawn.
enum DdayCardVariant {
  /// Interactive row inside the home list group.
  list,

  /// Live preview at the top of the edit screen.
  editPreview,

  /// Home-screen widget preview in settings.
  widgetPreview,
}

/// Category icon in a softly tinted circle.
class DdayIconBubble extends StatelessWidget {
  const DdayIconBubble({
    super.key,
    required this.iconKey,
    required this.colors,
    this.size = 40,
  });

  final String? iconKey;
  final DdayResolvedColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.iconBackground,
        shape: BoxShape.circle,
      ),
      child: Icon(
        DdayIcons.byKey(iconKey).icon,
        size: size * 0.52,
        color: colors.accent,
      ),
    );
  }
}

/// Shared D-Day presentation used by the home list, edit preview and widget
/// preview. Semantics expose one summary label, plus tap / long-press hints
/// only when interactive.
class DdayCard extends StatelessWidget {
  const DdayCard({
    super.key,
    required this.variant,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.colors,
    this.iconKey,
    this.pinned = false,
    this.highlighted = false,
    this.repeatYearly = false,
    this.hasReminders = false,
    this.onTap,
    this.onLongPress,
    this.badgeKey,
    this.boxKey,
    this.photo,
  });

  static const String longPressHint = '開啟選單：置頂或刪除';

  final DdayCardVariant variant;
  final String title;
  final String subtitle;
  final String badge;
  final DdayResolvedColors colors;
  final String? iconKey;
  final bool pinned;

  /// Emphasize the count (used on the day itself).
  final bool highlighted;
  final bool repeatYearly;
  final bool hasReminders;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Key placed on the count text (kept for existing tests).
  final Key? badgeKey;

  /// Key placed on the widget-preview box (kept for existing tests).
  final Key? boxKey;

  /// Background photo; when set the card is drawn as a photo card.
  final File? photo;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final card = switch (variant) {
      DdayCardVariant.list =>
        photo != null
            ? _buildPhotoCard(context, photo, height: 132)
            : _buildListRow(context),
      DdayCardVariant.editPreview => _buildEditPreview(context),
      DdayCardVariant.widgetPreview => _buildWidgetPreview(context),
    };

    final label = ddaySemanticLabel(
      title: title,
      subtitle: subtitle,
      badge: badge,
      pinned: pinned,
      repeatYearly: repeatYearly,
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

  Widget _count(CountdownBadgeSize size, {bool onPhoto = false}) {
    return CountdownBadge(
      text: badge,
      color: onPhoto ? Colors.white : colors.accent,
      highlighted: highlighted,
      highlightBackground: onPhoto ? Colors.white : colors.highlightBackground,
      highlightForeground: onPhoto ? colors.accent : colors.highlightForeground,
      size: size,
      textKey: badgeKey,
    );
  }

  /// Photo card: the photo fills the card, a dark gradient keeps the white
  /// title, date and day count legible.
  Widget _buildPhotoCard(
    BuildContext context,
    File photo, {
    required double height,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  DdayIcons.byKey(iconKey).icon,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              if (pinned) ...[
                const Icon(
                  Icons.push_pin_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: _textShadow,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (repeatYearly) ...[
                const Icon(
                  Icons.repeat_rounded,
                  size: 13,
                  color: Colors.white70,
                ),
                const SizedBox(width: 3),
              ],
              if (hasReminders) ...[
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 13,
                  color: Colors.white70,
                ),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    shadows: _textShadow,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              _count(CountdownBadgeSize.regular, onPhoto: true),
            ],
          ),
        ],
      ),
    );

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DdayPhoto(file: photo, fallbackColor: colors.accent),
            const DecoratedBox(decoration: _photoScrim),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: ExcludeSemantics(child: content),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Icon, title / date column and the day count.
  Widget _content(BuildContext context, {required double iconSize}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        DdayIconBubble(iconKey: iconKey, colors: colors, size: iconSize),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (pinned) ...[
                    Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 4),
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
              const SizedBox(height: 2),
              Row(
                children: [
                  if (repeatYearly) ...[
                    Icon(Icons.repeat_rounded, size: 13, color: muted),
                    const SizedBox(width: 3),
                  ],
                  if (hasReminders) ...[
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 13,
                      color: muted,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
        _count(CountdownBadgeSize.regular),
      ],
    );
  }

  Widget _buildListRow(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _content(context, iconSize: 40),
        ),
      ),
    );
  }

  Widget _buildEditPreview(BuildContext context) {
    final theme = Theme.of(context);
    final photo = this.photo;
    if (photo != null) {
      return _buildPhotoCard(context, photo, height: 160);
    }
    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '即時預覽',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _content(context, iconSize: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetPreview(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = this.photo;
    final onPhoto = photo != null;
    final titleColor = onPhoto ? Colors.white : null;
    final subColor = onPhoto
        ? Colors.white.withValues(alpha: 0.9)
        : scheme.onSurfaceVariant;

    final content = ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pinned ? '\u{1F4CC} $title' : title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: subColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _count(CountdownBadgeSize.compact, onPhoto: onPhoto),
        ],
      ),
    );

    // Mirrors the Android widget: a text banner along the bottom with the
    // title and date on the left and the count on the right.
    return Container(
      key: boxKey,
      height: 120,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: softCardColor(scheme),
        borderRadius: BorderRadius.circular(18),
        border: onPhoto
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Stack(
        children: [
          if (photo != null) ...[
            Positioned.fill(
              child: DdayPhoto(file: photo, fallbackColor: colors.accent),
            ),
            const Positioned.fill(
              child: DecoratedBox(decoration: _widgetScrim),
            ),
          ],
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

const List<Shadow> _textShadow = <Shadow>[
  Shadow(color: Color(0x66000000), blurRadius: 6),
];

/// Darkens the photo towards the bottom-left where the text sits.
const BoxDecoration _photoScrim = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: <Color>[Color(0x99000000), Color(0x33000000)],
  ),
);

/// Matches the Android widget scrim (`widget_scrim.xml`): dark at the bottom
/// where the text banner sits, clear at the top.
const BoxDecoration _widgetScrim = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[Color(0xA6000000), Color(0x33000000), Color(0x00000000)],
  ),
);

/// A stored background photo, decoded at screen size. Falls back to a solid
/// accent color if the file cannot be decoded.
class DdayPhoto extends StatelessWidget {
  const DdayPhoto({super.key, required this.file, required this.fallbackColor});

  final File file;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final decodeWidth = (media.size.width * media.devicePixelRatio)
        .clamp(320, 1600)
        .round();
    // The accent color shows while the photo decodes or if it cannot load.
    return ColoredBox(
      color: fallbackColor,
      child: Image(
        image: ResizeImage(FileImage(file), width: decodeWidth),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      ),
    );
  }
}
