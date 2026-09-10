import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Background location tracking, ACTIVE ONLY during two fixed daily windows:
///   Morning  09:00 - 09:30
///   Evening  20:30 - 21:00
/// Outside those windows there is NO GPS capture at all. A foreground-service
/// notification is shown ONLY while inside an active window (the service drops
/// to background mode — no notification — the rest of the day).
///
/// NOTE (Android reliability): keeping a task alive to wake exactly at 09:00
/// with the app fully closed is inherently unreliable on aggressive OEMs
/// (Xiaomi/Oppo/Vivo/Samsung battery managers). This uses a persistent
/// background service + boot restart to maximise survival, but the employee
/// should disable battery optimization for the app for it to fire reliably
/// when the app is not open. See README.

const _notifChannelId = 'attendance_location';
const _notifId = 8801;

/// Window boundaries (local device time), in minutes-since-midnight.
const _morningStart = 9 * 60; // 09:00
const _morningEnd = 9 * 60 + 30; // 09:30
const _eveningStart = 20 * 60 + 30; // 20:30
const _eveningEnd = 21 * 60; // 21:00

/// Minimum gap between two pings within a window.
const _minGapMs = 5 * 60 * 1000;

String? windowForTime(DateTime now) {
  final mins = now.hour * 60 + now.minute;
  if (mins >= _morningStart && mins < _morningEnd) return 'Morning';
  if (mins >= _eveningStart && mins < _eveningEnd) return 'Evening';
  return null;
}

/// Configure (and optionally start) the background service. Called from main().
Future<void> configureLocationService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onLocationServiceStart,
      autoStart: false, // started explicitly only when always-permission granted
      isForegroundMode: true,
      autoStartOnBoot: true,
      notificationChannelId: _notifChannelId,
      initialNotificationTitle: 'Attendance',
      initialNotificationContent: 'Location tracking scheduled',
      foregroundServiceNotificationId: _notifId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

Future<void> startLocationServiceIfNeeded() async {
  final service = FlutterBackgroundService();
  if (!await service.isRunning()) {
    await service.startService();
  }
}

Future<void> stopLocationService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stopService');
  }
}

/// Background isolate entry point. Runs its own 60s check loop.
@pragma('vm:entry-point')
void onLocationServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  const storage = FlutterSecureStorage();
  bool isForeground = true; // service starts in foreground mode

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Future<void> tick() async {
    final now = DateTime.now();
    final window = windowForTime(now);

    // toggle foreground notification: ONLY inside a window
    if (service is AndroidServiceInstance) {
      if (window != null) {
        if (!isForeground) {
          service.setAsForegroundService();
          isForeground = true;
        }
        service.setForegroundNotificationInfo(
          title: 'Attendance location tracking active',
          content: '$window window (09:00–09:30 / 20:30–21:00)',
        );
      } else {
        if (isForeground) {
          service.setAsBackgroundService();
          isForeground = false;
        }
      }
    }

    if (window == null) return; // outside windows: zero GPS activity

    // 5-minute throttle, persisted so an isolate restart doesn't double-send
    final prefs = await SharedPreferences.getInstance();
    final key = 'lastping_${window}_${now.year}-${now.month}-${now.day}';
    final last = prefs.getInt(key) ?? 0;
    if (now.millisecondsSinceEpoch - last < _minGapMs) return;

    // GPS
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      return;
    }

    // session creds (written by ApiService; shared via secure storage)
    final baseUrl = await storage.read(key: 'base_url');
    final sid = await storage.read(key: 'sid');
    if (baseUrl == null || sid == null || sid.isEmpty) return;

    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/method/attendance_log.api.log_location_ping'),
            headers: {'Cookie': 'sid=$sid'},
            body: {
              'latitude': pos.latitude.toString(),
              'longitude': pos.longitude.toString(),
              'accuracy_meter': pos.accuracy.toString(),
              'window': window,
              'capture_time': now.toIso8601String(),
            },
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        await prefs.setInt(key, now.millisecondsSinceEpoch);
      }
    } catch (_) {
      // network hiccup — will retry on the next in-window tick
    }
  }

  // initial check immediately, then every 60s
  await tick();
  Timer.periodic(const Duration(seconds: 60), (_) => tick());
}
