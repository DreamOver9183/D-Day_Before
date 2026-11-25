import 'package:flutter/material.dart';

class DdayResolvedColors {
  const DdayResolvedColors({
    required this.cardBackground,
    required this.borderColor,
    required this.accentColor,
    required this.badgeBackground,
    required this.badgeForeground,
  });

  final Color cardBackground;
  final Color borderColor;
  final Color accentColor;
  final Color badgeBackground;
  final Color badgeForeground;
}

class DdayColorPreset {
  const DdayColorPreset({
    required this.key,
    required this.label,
    required this.accentColor,
  });

  final String? key;
  final String label;
  final Color accentColor;

  DdayResolvedColors resolve(
    ColorScheme scheme, {
    bool isPinned = false,
    bool isToday = false,
  }) {
    if (key == null) {
      return DdayResolvedColors(
        cardBackground: scheme.surfaceContainerLow,
        borderColor: isPinned
            ? scheme.primary.withValues(alpha: 0.5)
            : scheme.outlineVariant,
        accentColor: scheme.primary,
        badgeBackground: isToday ? scheme.primary : scheme.primaryContainer,
        badgeForeground:
            isToday ? scheme.onPrimary : scheme.onPrimaryContainer,
      );
    }

    final isDark = scheme.brightness == Brightness.dark;
    final cardBg = Color.alphaBlend(
      accentColor.withValues(alpha: isDark ? 0.16 : 0.09),
      scheme.surfaceContainerLow,
    );
    final badgeBg = isToday
        ? accentColor
        : Color.alphaBlend(
            accentColor.withValues(alpha: isDark ? 0.28 : 0.18),
            scheme.surface,
          );
    final badgeFg = isToday
        ? (ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
            ? Colors.white
            : Colors.black87)
        : (isDark
            ? Color.lerp(accentColor, Colors.white, 0.55)!
            : Color.lerp(accentColor, Colors.black, 0.35)!);

    return DdayResolvedColors(
      cardBackground: cardBg,
      borderColor: accentColor.withValues(alpha: isPinned ? 0.8 : 0.4),
      accentColor: accentColor,
      badgeBackground: badgeBg,
      badgeForeground: badgeFg,
    );
  }
}

class DdayColors {
  DdayColors._();

  static const DdayColorPreset defaultPreset = DdayColorPreset(
    key: null,
    label: '預設',
    accentColor: Color(0xFF3F51B5),
  );

  static const List<DdayColorPreset> presets = <DdayColorPreset>[
    defaultPreset,
    DdayColorPreset(key: 'indigo', label: '靛藍', accentColor: Color(0xFF3F51B5)),
    DdayColorPreset(key: 'rose', label: '玫瑰', accentColor: Color(0xFFE11D48)),
    DdayColorPreset(key: 'amber', label: '琥珀', accentColor: Color(0xFFD97706)),
    DdayColorPreset(key: 'emerald', label: '翡翠', accentColor: Color(0xFF059669)),
    DdayColorPreset(key: 'sky', label: '天藍', accentColor: Color(0xFF0284C7)),
    DdayColorPreset(key: 'violet', label: '紫羅蘭', accentColor: Color(0xFF7C3AED)),
    DdayColorPreset(key: 'coral', label: '珊瑚', accentColor: Color(0xFFEA580C)),
    DdayColorPreset(key: 'teal', label: '青綠', accentColor: Color(0xFF0D9488)),
  ];

  static DdayColorPreset byKey(String? key) {
    if (key == null) return defaultPreset;
    for (final preset in presets) {
      if (preset.key == key) {
        return preset;
      }
    }
    return defaultPreset;
  }

  static String? normalizeKey(dynamic rawKey) {
    if (rawKey is! String) return null;
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty) return null;
    for (final preset in presets) {
      if (preset.key == trimmed) {
        return preset.key;
      }
    }
    return null;
  }
}
