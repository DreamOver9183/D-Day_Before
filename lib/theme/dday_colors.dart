import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Colors for one D-Day in the current theme.
class DdayResolvedColors {
  const DdayResolvedColors({
    required this.accent,
    required this.iconBackground,
    required this.highlightBackground,
    required this.highlightForeground,
  });

  /// Day count and category icon color.
  final Color accent;

  /// Soft tinted circle behind the category icon.
  final Color iconBackground;

  /// Pill behind the count on the day itself (D-Day).
  final Color highlightBackground;
  final Color highlightForeground;
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

  DdayResolvedColors resolve(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final base = key == null ? scheme.primary : accentColor;
    // Lift custom colors a little on dark backgrounds so text stays legible.
    final accent = isDark && key != null
        ? Color.lerp(base, Colors.white, 0.25)!
        : base;
    final onBase = ThemeData.estimateBrightnessForColor(base) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return DdayResolvedColors(
      accent: accent,
      iconBackground: base.withValues(alpha: isDark ? 0.22 : 0.12),
      highlightBackground: base,
      highlightForeground: key == null ? scheme.onPrimary : onBase,
    );
  }
}

class DdayColors {
  DdayColors._();

  static const DdayColorPreset defaultPreset = DdayColorPreset(
    key: null,
    label: '預設',
    accentColor: kAppCoral,
  );

  static const List<DdayColorPreset> presets = <DdayColorPreset>[
    defaultPreset,
    DdayColorPreset(key: 'indigo', label: '靛藍', accentColor: Color(0xFF3F51B5)),
    DdayColorPreset(key: 'rose', label: '玫瑰', accentColor: Color(0xFFE11D48)),
    DdayColorPreset(key: 'amber', label: '琥珀', accentColor: Color(0xFFD97706)),
    DdayColorPreset(
      key: 'emerald',
      label: '翡翠',
      accentColor: Color(0xFF059669),
    ),
    DdayColorPreset(key: 'sky', label: '天藍', accentColor: Color(0xFF0284C7)),
    DdayColorPreset(
      key: 'violet',
      label: '紫羅蘭',
      accentColor: Color(0xFF7C3AED),
    ),
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
