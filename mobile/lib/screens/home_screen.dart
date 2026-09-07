import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'punch_screen.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await ApiService.instance.getTodayStatus();
      setState(() { _status = s; _loading = false; });
    } catch (e) {
      if (e is ApiException && e.unauthorized) return _forceLogout();
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _forceLogout() async {
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _punch(String type) async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PunchScreen(punchType: type)));
    if (result == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final nextAction = s?['next_action'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HistoryScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _forceLogout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ErrorBanner(_error!),
                  if (s != null) ...[
                    Text('Hello, ${s['employee_name'] ?? ''}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('${s['date']}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    _timesCard(s),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: _bigButton(
                          label: 'Check In',
                          icon: Icons.login,
                          color: Colors.green,
                          enabled: nextAction == 'Check In',
                          onTap: () => _punch('Check In'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _bigButton(
                          label: 'Check Out',
                          icon: Icons.logout,
                          color: Colors.deepOrange,
                          enabled: nextAction == 'Check Out',
                          onTap: () => _punch('Check Out'),
                        ),
                      ),
                    ]),
                    if (nextAction == null) ...[
                      const SizedBox(height: 16),
                      const Center(
                          child: Text('You have completed today\'s attendance.',
                              style: TextStyle(color: Colors.grey))),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _timesCard(Map<String, dynamic> s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _timeCol('Check In', s['check_in_time'], Icons.login, Colors.green),
              _timeCol('Check Out', s['check_out_time'], Icons.logout, Colors.deepOrange),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Status: '),
              StatusBadge(s['current_status']?.toString() ?? 'Not Marked'),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _timeCol(String label, dynamic time, IconData icon, Color color) {
    final t = time == null ? '--:--' : time.toString().split(' ').last.substring(0, 5);
    return Column(children: [
      Icon(icon, color: color),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
      color: enabled ? color : Colors.grey.shade300,
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
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}
