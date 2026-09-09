import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Global light/dark theme controller, persisted with flutter_secure_storage.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final ThemeController instance = ThemeController._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'theme_mode';

  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      value = v == 'dark'
          ? ThemeMode.dark
          : v == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
    } catch (_) {
      value = ThemeMode.system;
    }
  }

  bool isDark(BuildContext context) =>
      value == ThemeMode.dark ||
      (value == ThemeMode.system &&
          MediaQuery.of(context).platformBrightness == Brightness.dark);

  Future<void> toggle(BuildContext context) async {
    final dark = isDark(context);
    value = dark ? ThemeMode.light : ThemeMode.dark;
    try {
      await _storage.write(key: _key, value: dark ? 'light' : 'dark');
    } catch (_) {}
  }
}
