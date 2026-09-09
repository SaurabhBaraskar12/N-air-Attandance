import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';
import 'punch_screen.dart';

/// Mark attendance: shows today's state and Check In / Check Out buttons,
/// which open the EXISTING camera + GPS PunchScreen (unchanged logic).
class AttendScreen extends StatefulWidget {
  const AttendScreen({super.key});
  @override
  State<AttendScreen> createState() => _AttendScreenState();
}

class _AttendScreenState extends State<AttendScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
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

  Future<void> _punch(String type) async {
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PunchScreen(punchType: type)));
    if (ok == true) _refresh();
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
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: _bigButton(
                label: 'Check In',
                icon: Icons.login,
                color: Colors.green,
                enabled: next == 'Check In',
                onTap: () => _punch('Check In'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _bigButton(
                label: 'Check Out',
                icon: Icons.logout,
                color: kAccentOrange,
                enabled: next == 'Check Out',
                onTap: () => _punch('Check Out'),
              ),
            ),
          ]),
          if (next == null && s != null) ...[
            const SizedBox(height: 16),
            const Center(
                child: Text("You have completed today's attendance.",
                    style: TextStyle(color: Colors.grey))),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text('Every punch is verified with a selfie face-match + GPS geofence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
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

  Widget _bigButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? color : Colors.grey.shade400,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 120,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}
