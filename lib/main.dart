import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/dday_store.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DdayApp(store: DdayStore()));
}

class DdayApp extends StatefulWidget {
  const DdayApp({
    super.key,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayStore store;
  final DateTime Function() clock;

  @override
  State<DdayApp> createState() => _DdayAppState();
}

class _DdayAppState extends State<DdayApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final loaded = await widget.store.loadThemeMode();
    if (!mounted) return;
    setState(() {
      _themeMode = loaded;
    });
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() {
      _themeMode = mode;
    });
    await widget.store.saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'D-Day Before',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const <Locale>[
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(
        store: widget.store,
        clock: widget.clock,
        themeMode: _themeMode,
        onThemeModeChanged: _changeThemeMode,
      ),
    );
  }
}
