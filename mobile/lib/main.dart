import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'widgets.dart';
import 'theme_controller.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  // Guard the whole startup: on some OEM devices a plugin init (secure storage,
  // background service) can throw on cold start — never let that hard-crash the
  // app back to the launcher. Each step is isolated so the UI always renders.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await ApiService.instance.load();
    } catch (_) {}
    try {
      await ThemeController.instance.load();
    } catch (_) {}
    // Location is captured only on demand when the user taps Mark Attendance —
    // there is no background service to start at launch.
    runApp(const AttendanceApp());
  }, (error, stack) {
    // swallow uncaught async errors so the app stays alive
  });
}

ThemeData _appTheme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryBlue,
      brightness: brightness,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'N-Air HVAC Solutions',
          debugShowCheckedModeBanner: false,
          theme: _appTheme(Brightness.light),
          darkTheme: _appTheme(Brightness.dark),
          themeMode: mode,
          home: ApiService.instance.isLoggedIn
              ? const HomeShell()
              : const LoginScreen(),
        );
      },
    );
  }
}
