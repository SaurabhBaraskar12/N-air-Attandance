import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notes = [];
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
      final res = await ApiService.instance.getNotifications();
      setState(() { _notes = res['notifications'] ?? []; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'Success': return Icons.check_circle;
      case 'Warning': return Icons.warning_amber;
      case 'Error': return Icons.error;
      default: return Icons.info;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'Success': return Colors.green;
      case 'Warning': return Colors.orange;
      case 'Error': return Colors.red;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [Padding(
                      padding: const EdgeInsets.all(16), child: ErrorBanner(_error!))])
                  : _notes.isEmpty
                      ? ListView(children: const [Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No unread notifications.')))])
                      : ListView.separated(
                          itemCount: _notes.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = _notes[i] as Map;
                            final type = n['notification_type']?.toString() ?? 'Info';
                            return ListTile(
                              leading: Icon(_icon(type), color: _color(type)),
                              title: Text(n['title']?.toString() ?? ''),
                              subtitle: Text(n['message']?.toString() ?? ''),
                              isThreeLine: true,
                            );
                          },
                        ),
            ),
    );
  }
}
