import 'package:flutter/material.dart';
import 'api_service.dart';
import 'widgets.dart';
import 'theme_controller.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.load();
  await ThemeController.instance.load();
  runApp(const AttendanceApp());
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
          title: 'NHS HRMS',
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
