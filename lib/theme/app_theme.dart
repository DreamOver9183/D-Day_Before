import 'package:flutter/material.dart';

/// D-Day Before's own coral accent.
const Color kAppCoral = Color(0xFFEE5A62);

/// Warm off-white page background used in light mode.
const Color _warmBackground = Color(0xFFFAF6F5);

/// Builds the app theme: warm background, white rounded cards without
/// outlines, and a coral accent for numbers, switches and the add button.
ThemeData buildAppTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  var scheme = ColorScheme.fromSeed(
    seedColor: kAppCoral,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  if (isLight) {
    scheme = scheme.copyWith(
      primary: kAppCoral,
      onPrimary: Colors.white,
      surface: _warmBackground,
      surfaceContainerLowest: Colors.white,
    );
  }

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: softCardColor(scheme),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: const CircleBorder(),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
  );
}

/// Background for raised content: white in light mode, a lifted surface in
/// dark mode.
Color softCardColor(ColorScheme scheme) => scheme.brightness == Brightness.light
    ? scheme.surfaceContainerLowest
    : scheme.surfaceContainerHigh;

/// Soft drop shadow for cards (light mode only; dark mode relies on tone).
List<BoxShadow> softCardShadow(ColorScheme scheme) =>
    scheme.brightness == Brightness.light
    ? const <BoxShadow>[
        BoxShadow(
          color: Color(0x0D3A1F1F),
          blurRadius: 20,
          offset: Offset(0, 2),
        ),
      ]
    : const <BoxShadow>[];
