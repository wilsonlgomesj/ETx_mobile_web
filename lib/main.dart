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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        '/home':      (_) => const HomeScreen(),
        '/campaigns': (_) => const CampaignsScreen(),
        '/reports':   (_) => const ReportsScreen(),
        '/calendar':  (_) => const CalendarScreen(),
        '/profile':   (_) => const ProfileScreen(),
        '/login':     (_) => const LoginScreen(),
      },
    );
  }
}

/// Decides between LoginScreen and HomeScreen based on the restored auth
/// session. Runs once at app start; navigation after that uses named routes.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return AuthService.instance.isAuthenticated
        ? const HomeScreen()
        : const LoginScreen();
  }
}
