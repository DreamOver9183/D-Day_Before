import 'package:flutter/material.dart';

/// A category icon a D-Day can show next to its title.
class DdayIconPreset {
  const DdayIconPreset({
    required this.key,
    required this.label,
    required this.icon,
  });

  /// Stored in JSON; null means the default calendar icon.
  final String? key;
  final String label;
  final IconData icon;
}

class DdayIcons {
  DdayIcons._();

  static const DdayIconPreset defaultPreset = DdayIconPreset(
    key: null,
    label: '一般',
    icon: Icons.event_rounded,
  );

  static const List<DdayIconPreset> presets = <DdayIconPreset>[
    defaultPreset,
    DdayIconPreset(key: 'love', label: '情侶', icon: Icons.favorite_rounded),
    DdayIconPreset(key: 'birthday', label: '生日', icon: Icons.cake_rounded),
    DdayIconPreset(
      key: 'celebration',
      label: '紀念',
      icon: Icons.celebration_rounded,
    ),
    DdayIconPreset(key: 'exam', label: '考試', icon: Icons.edit_note_rounded),
    DdayIconPreset(key: 'school', label: '學校', icon: Icons.school_rounded),
    DdayIconPreset(key: 'work', label: '工作', icon: Icons.work_rounded),
    DdayIconPreset(key: 'travel', label: '旅行', icon: Icons.flight_rounded),
    DdayIconPreset(key: 'baby', label: '寶寶', icon: Icons.child_care_rounded),
    DdayIconPreset(key: 'pet', label: '寵物', icon: Icons.pets_rounded),
    DdayIconPreset(
      key: 'fitness',
      label: '運動',
      icon: Icons.fitness_center_rounded,
    ),
    DdayIconPreset(
      key: 'health',
      label: '健康',
      icon: Icons.favorite_border_rounded,
    ),
  ];

  static DdayIconPreset byKey(String? key) {
    if (key == null) return defaultPreset;
    for (final preset in presets) {
      if (preset.key == key) return preset;
    }
    return defaultPreset;
  }

  /// Returns a known icon key or null (unknown keys fall back to default).
  static String? normalizeKey(dynamic rawKey) {
    if (rawKey is! String) return null;
    final trimmed = rawKey.trim();
    for (final preset in presets) {
      if (preset.key != null && preset.key == trimmed) return preset.key;
    }
    return null;
  }
}
