import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart';
import '../widgets.dart';

/// Mark attendance (location only — no selfie / face match).
/// A single "Mark Attendance" button captures the current GPS and submits the
/// punch. The first mark of the day is a Check In (morning), the second a Check
/// Out (evening). Marking is never blocked: if it is past the on-time window
/// the punch still records and the result popup shows how late/early it is.
class AttendScreen extends StatefulWidget {
  const AttendScreen({super.key});
  @override
  State<AttendScreen> createState() => _AttendScreenState();
}

class _AttendScreenState extends State<AttendScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  Position? _pos;
  String? _locError;
  bool _locating = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _fetchLocation();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ApiService.instance.getTodayStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locError = 'Location / GPS is turned off.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locError = 'Location permission denied.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 30));
      if (mounted) {
        setState(() {
          _pos = p;
          _locError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _locError = 'Could not get location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _mark(String punchType) async {
    // make sure we have a fresh fix first
    if (_pos == null) {
      await _fetchLocation();
      if (_pos == null) {
        _snack(_locError ?? 'Location not available. Try again.');
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.markAttendance(
        punchType: punchType,
        latitude: _pos!.latitude,
        longitude: _pos!.longitude,
        deviceInfo: 'Flutter/${Platform.operatingSystem}',
      );
      if (!mounted) return;
      await _showResult(res);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showResult(Map<String, dynamic> res) {
    final status = res['status']?.toString() ?? 'Present';
    final isLate = res['is_late'] == true;
    final isEarly = res['is_early'] == true;
    final onTime = !isLate && !isEarly;
    final lat = res['latitude'];
    final lng = res['longitude'];

    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(onTime ? Icons.check_circle : Icons.warning_amber_rounded,
              color: onTime ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          const Expanded(child: Text('Attendance Marked')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerLeft, child: StatusBadge(status)),
          const SizedBox(height: 12),
          Text(res['message']?.toString() ?? 'Attendance recorded.'),
          const SizedBox(height: 12),
          _kv('Punch', res['punch_type']),
          _kv('Time', _prettyTime(res['punch_time'])),
          if (lat != null && lng != null)
            _kv('Location',
                '${_num(lat)}, ${_num(lng)}'),
          if (res['distance_from_location_meter'] != null)
            _kv('Distance from office',
                '${_num(res['distance_from_location_meter'])} m'),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }

  String _num(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse('$v');
    return d == null ? '$v' : d.toStringAsFixed(5);
  }

  String _prettyTime(dynamic dt) {
    if (dt == null) return '--:--';
    final s = dt.toString();
    return s.contains(' ') ? s.split(' ').last.substring(0, 5) : s;
  }

  String _time(dynamic dt) {
    if (dt == null) return '--:--';
    final s = dt.toString();
    return s.contains(' ') ? s.split(' ').last.substring(0, 5) : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _status;
    final next = s?['next_action'] as String?;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ErrorBanner(_error!),
          _timesCard(context, s),
          const SizedBox(height: 16),
          _locationCard(context),
          const SizedBox(height: 20),
          _markButton(next),
          if (next == null && s != null) ...[
            const SizedBox(height: 16),
            const Center(
                child: Text("You have completed today's attendance.",
                    style: TextStyle(color: Colors.grey))),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text(
                'Check In window 9:00–9:30 AM · Check Out window 8:30–9:00 PM.\n'
                'You can still mark after the window — it will be logged as late/early.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _markButton(String? next) {
    final enabled = next != null && !_submitting;
    final label = next == null
        ? 'Attendance Complete'
        : (next == 'Check In' ? 'Mark Attendance (Check In)' : 'Mark Attendance (Check Out)');
    final color = next == 'Check Out' ? kAccentOrange : kPrimaryBlue;
    return Material(
      color: enabled ? color : Colors.grey.shade400,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? () => _mark(next) : null,
        child: Container(
          height: 110,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_submitting)
              const SizedBox(
                  height: 34,
                  width: 34,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white))
            else
              Icon(next == 'Check Out' ? Icons.logout : Icons.location_on,
                  size: 38, color: Colors.white),
            const SizedBox(height: 8),
            Text(_submitting ? 'Marking…' : label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _locationCard(BuildContext context) {
    final ok = _pos != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : kAccentOrange).withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (ok ? Colors.green : kAccentOrange).withOpacity(0.5)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.my_location : Icons.location_searching,
            color: ok ? Colors.green : kAccentOrange, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ok
                ? 'Your location: ${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}'
                : (_locating
                    ? 'Fetching your location…'
                    : (_locError ?? 'Location not available')),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!_locating)
          TextButton(
              onPressed: _fetchLocation,
              child: Text(ok ? 'Refresh' : 'Retry')),
      ]),
    );
  }

  Widget _timesCard(BuildContext context, Map<String, dynamic>? s) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _timeCol('Check In', s?['check_in_time'], Icons.login, Colors.green),
              _timeCol('Check Out', s?['check_out_time'], Icons.logout, kAccentOrange),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Status: '),
              StatusBadge(s?['current_status']?.toString() ?? 'Not Marked'),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _timeCol(String label, dynamic time, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, color: color),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(_time(time),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _kv(String k, dynamic v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 12),
          Flexible(
            child: Text('${v ?? '—'}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
