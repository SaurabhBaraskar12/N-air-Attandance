import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.instance.getAttendanceHistory();
      setState(() { _records = res['records'] ?? []; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [Padding(
                      padding: const EdgeInsets.all(16), child: ErrorBanner(_error!))])
                  : _records.isEmpty
                      ? ListView(children: const [Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No records in the last 30 days.')))])
                      : ListView.separated(
                          itemCount: _records.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _tile(_records[i]),
                        ),
            ),
    );
  }

  Widget _tile(Map r) {
    final type = r['punch_type']?.toString() ?? '';
    final dt = r['punch_datetime']?.toString() ?? '';
    final date = r['attendance_date']?.toString() ?? dt.split(' ').first;
    final time = dt.contains(' ') ? dt.split(' ').last.substring(0, 5) : '';
    final isIn = type == 'Check In';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (isIn ? Colors.green : Colors.deepOrange).withOpacity(0.15),
        child: Icon(isIn ? Icons.login : Icons.logout,
            color: isIn ? Colors.green : Colors.deepOrange),
      ),
      title: Text('$type  •  $time'),
      subtitle: Text(date),
      trailing: StatusBadge(r['status']?.toString() ?? ''),
    );
  }
}
