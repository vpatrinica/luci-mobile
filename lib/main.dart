import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/main_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/screens/splash_screen.dart';

Future<void> _appendErrorLog(String text) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/luci_error_log.txt');
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString('[$timestamp] $text\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // Best-effort only; don't crash the app while logging errors
  }
}

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    // Preserve normal behavior
    FlutterError.presentError(details);
    // Write to persistent log for retrieval via adb
    unawaited(_appendErrorLog('FlutterError: ${details.exceptionAsString()}\n${details.stack}'));
  };

  runZonedGuarded(() {
    runApp(ProviderScope(child: const LuCIApp()));
  }, (error, stack) {
    unawaited(_appendErrorLog('Uncaught Error: $error\n$stack'));
    // Also print so it appears in logs
    Zone.current.handleUncaughtError(error, stack);
  });
}

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    return MaterialApp(
      title: 'LuCI Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        // Edge-to-edge display handled natively in MainActivity
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        // Edge-to-edge display handled natively in MainActivity
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      themeMode: appState.themeMode,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
