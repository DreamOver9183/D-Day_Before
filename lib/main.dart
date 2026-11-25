import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/dday_store.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DdayApp(store: DdayStore()));
}

class DdayApp extends StatelessWidget {
  const DdayApp({
    super.key,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayStore store;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D-Day Before',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const <Locale>[
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.light,
        ),
      ),
      home: HomeScreen(
        store: store,
        clock: clock,
      ),
    );
  }
}
