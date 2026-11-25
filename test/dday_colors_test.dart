import 'package:dday_before/models/dday.dart';
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
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      );
      final dark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      );

      final rose = DdayColors.byKey('rose');
      final lightResolved = rose.resolve(light, isPinned: true, isToday: false);
      final darkResolved = rose.resolve(dark, isPinned: false, isToday: true);

      expect(lightResolved.accentColor, rose.accentColor);
      expect(darkResolved.badgeBackground, rose.accentColor);
      expect(lightResolved.cardBackground, isNot(equals(darkResolved.cardBackground)));
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
