import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';

/// Handles the one-time background-location permission request and the
/// degraded-mode state used to show the Home banner.
class LocationPermissionFlow {
  static const _kAsked = 'loc_perm_asked'; // explanation shown once per install
  static const _kDegraded = 'loc_perm_degraded'; // not "always" granted

  static Future<bool> isDegraded() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kDegraded) ?? false;
  }

  static Future<void> _setDegraded(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDegraded, v);
  }

  static Future<void> openSettings() => openAppSettings();

  /// Called once after login (and on every Home open). Shows the explanation
  /// dialog + OS prompt EXACTLY once per install; afterwards only re-checks the
  /// current status silently (never re-prompts) and refreshes the banner state.
  static Future<void> ensureRequestedOnce(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    final askedBefore = p.getBool(_kAsked) ?? false;

    if (askedBefore) {
      await _refreshSilently();
      return;
    }
    await p.setBool(_kAsked, true);

    // explanation BEFORE the OS prompt
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location for attendance'),
          content: const Text(
            "This app records your location only between 9:00–9:30 AM and "
            "8:30–9:00 PM for attendance purposes. No tracking happens at any "
            "other time.\n\nPlease select 'Allow all the time' on the next screen.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    }

    // Android needs foreground location granted before background ("always").
    await Permission.locationWhenInUse.request();
    final always = await Permission.locationAlways.request();

    if (always.isGranted) {
      await _setDegraded(false);
      await configureLocationService();
      await startLocationServiceIfNeeded();
    } else {
      await _setDegraded(true);
    }
  }

  /// Re-evaluate permission on later launches WITHOUT prompting the OS again.
  static Future<void> _refreshSilently() async {
    final always = await Permission.locationAlways.status;
    if (always.isGranted) {
      await _setDegraded(false);
      await configureLocationService();
      await startLocationServiceIfNeeded();
    } else {
      await _setDegraded(true);
    }
  }
}
