import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Central Frappe API client. Handles login (capturing the `sid` session
/// cookie), stores it securely, and sends it on every subsequent request.
///
/// Base URL: for testing on a REAL phone, point this at the bench machine's
/// LAN IP (e.g. http://192.168.1.50:8000) — `localhost` on the phone will NOT
/// reach the PC. It can be changed at runtime on the Login screen and is
/// persisted. See README.md.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const _storage = FlutterSecureStorage();
  static const _kBaseUrl = 'base_url';
  static const _kSid = 'sid';
  static const _kUser = 'username';

  // sensible default; overridden by the value saved on the Login screen.
  String _baseUrl = 'http://10.0.2.2:8000'; // 10.0.2.2 = host from Android emu
  String? _sid;
  String? _username;

  Future<void> load() async {
    _baseUrl = (await _storage.read(key: _kBaseUrl)) ?? _baseUrl;
    _sid = await _storage.read(key: _kSid);
    _username = await _storage.read(key: _kUser);
  }

  String get baseUrl => _baseUrl;
  String? get username => _username;
  bool get isLoggedIn => _sid != null && _sid!.isNotEmpty;

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _storage.write(key: _kBaseUrl, value: _baseUrl);
  }

  Map<String, String> get _cookieHeader =>
      _sid == null ? {} : {'Cookie': 'sid=$_sid'};

  void _captureSid(http.BaseResponse resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null) return;
    final match = RegExp(r'sid=([^;]+)').firstMatch(raw);
    if (match != null && match.group(1) != 'Guest') {
      _sid = match.group(1);
      _storage.write(key: _kSid, value: _sid);
    }
  }

  // ---- auth ----
  Future<void> login(String usr, String pwd) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/method/login'),
      body: {'usr': usr, 'pwd': pwd},
    );
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp) ?? 'Login failed (${resp.statusCode})');
    }
    _captureSid(resp);
    if (!isLoggedIn) throw ApiException('Login failed: no session returned');
    _username = usr.trim();
    await _storage.write(key: _kUser, value: _username);
  }

  Future<void> logout() async {
    _sid = null;
    _username = null;
    await _storage.delete(key: _kSid);
    await _storage.delete(key: _kUser);
  }

  // ---- endpoints ----
  Future<Map<String, dynamic>> markAttendance({
    required String punchType,
    required double latitude,
    required double longitude,
    required File selfie,
    String? deviceInfo,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/api/method/attendance_log.api.mark_attendance');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_cookieHeader)
      ..fields['punch_type'] = punchType
      ..fields['latitude'] = latitude.toString()
      ..fields['longitude'] = longitude.toString()
      ..fields['device_info'] = deviceInfo ?? 'Flutter App'
      ..files.add(await http.MultipartFile.fromPath('selfie_image', selfie.path));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    return _unwrap(resp);
  }

  Future<Map<String, dynamic>> getTodayStatus() =>
      _get('attendance_log.api.get_today_status');

  Future<Map<String, dynamic>> getAttendanceHistory(
          {String? fromDate, String? toDate}) =>
      _get('attendance_log.api.get_attendance_history', {
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
      });

  Future<Map<String, dynamic>> getNotifications() =>
      _get('attendance_log.api.get_my_notifications');

  // ---- helpers ----
  Future<Map<String, dynamic>> _get(String method,
      [Map<String, String>? query]) async {
    final uri = Uri.parse('$_baseUrl/api/method/$method')
        .replace(queryParameters: query);
    final resp = await http.get(uri, headers: _cookieHeader);
    return _unwrap(resp);
  }

  Map<String, dynamic> _unwrap(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw ApiException('Session expired. Please log in again.', unauthorized: true);
    }
    if (resp.statusCode >= 400) {
      throw ApiException(_extractError(resp) ?? 'Request failed (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final msg = body is Map && body.containsKey('message') ? body['message'] : body;
    return msg is Map<String, dynamic> ? msg : {'message': msg};
  }

  String? _extractError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map) {
        // Frappe puts a human message in _server_messages or exception
        if (body['_server_messages'] != null) {
          final list = jsonDecode(body['_server_messages']);
          if (list is List && list.isNotEmpty) {
            final m = jsonDecode(list.first);
            return m is Map ? (m['message'] ?? m.toString()) : list.first.toString();
          }
        }
        return body['message']?.toString() ?? body['exception']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

class ApiException implements Exception {
  final String message;
  final bool unauthorized;
  ApiException(this.message, {this.unauthorized = false});
  @override
  String toString() => message;
}
