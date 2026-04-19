import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'api/auth_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/campaigns_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/sync_diagnostics_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite, flutter_secure_storage and geolocator are not supported on web
  // or desktop. Show a clear error rather than crashing at runtime.
  if (kIsWeb) {
    runApp(const _UnsupportedPlatformApp());
    return;
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  final appState = AppState();
  await appState.init();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const EcoFlowApp(),
    ),
  );
}

class EcoFlowApp extends StatelessWidget {
  const EcoFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoFlowApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const _AuthGate(),
      routes: {
        '/home':             (_) => const HomeScreen(),
        '/campaigns':        (_) => const CampaignsScreen(),
        '/reports':          (_) => const ReportsScreen(),
        '/calendar':         (_) => const CalendarScreen(),
        '/profile':          (_) => const ProfileScreen(),
        '/login':            (_) => const LoginScreen(),
        '/sync-diagnostics': (_) => const SyncDiagnosticsScreen(),
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return AuthService.instance.isAuthenticated
        ? const HomeScreen()
        : const LoginScreen();
  }
}

/// Shown when the app is launched on an unsupported platform (web, desktop).
class _UnsupportedPlatformApp extends StatelessWidget {
  const _UnsupportedPlatformApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.smartphone, size: 64, color: Color(0xFF1A8A8A)),
                const SizedBox(height: 24),
                const Text(
                  'EcoFlowApp',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  'Este aplicativo é compatível apenas com Android e iOS.\n'
                  'Por favor, instale-o em um dispositivo móvel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
