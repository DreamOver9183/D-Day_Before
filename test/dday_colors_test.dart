import 'package:dday_before/models/dday.dart';
import 'package:dday_before/theme/app_theme.dart';
import 'package:dday_before/theme/dday_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DdayColors', () {
    test('normalizeKey accepts valid keys and falls back to null on unknown', () {
      expect(DdayColors.normalizeKey('rose'), 'rose');
      expect(DdayColors.normalizeKey('indigo'), 'indigo');
      expect(DdayColors.normalizeKey('unknown_color'), isNull);
      expect(DdayColors.normalizeKey('  '), isNull);
      expect(DdayColors.normalizeKey(null), isNull);
    });

    test('resolve produces light and dark colors cleanly', () {
      final light = ColorScheme.fromSeed(
        seedColor: kAppCoral,
        brightness: Brightness.light,
      );
      final dark = ColorScheme.fromSeed(
        seedColor: kAppCoral,
        brightness: Brightness.dark,
      );

      final rose = DdayColors.byKey('rose');
      final lightResolved = rose.resolve(light);
      final darkResolved = rose.resolve(dark);

      expect(lightResolved.accent, rose.accentColor);
      expect(darkResolved.highlightBackground, rose.accentColor);
      expect(darkResolved.accent, isNot(equals(rose.accentColor)),
          reason: 'lifted for contrast on dark backgrounds');
      expect(lightResolved.iconBackground,
          isNot(equals(darkResolved.iconBackground)));
    });

    test('default preset follows the theme primary', () {
      final light = ColorScheme.fromSeed(seedColor: kAppCoral);
      final resolved = DdayColors.defaultPreset.resolve(light);
      expect(resolved.accent, light.primary);
      expect(resolved.highlightForeground, light.onPrimary);
    });

    test('DdayItem copyWith can clear colorKey back to null', () {
      final item = DdayItem.create(
        id: 'c1',
        title: '配色測試',
        date: '2026-12-25',
        colorKey: 'emerald',
      );
      expect(item.colorKey, 'emerald');

      final cleared = item.copyWith(colorKey: null);
      expect(cleared.colorKey, isNull);
    });
  });
}
