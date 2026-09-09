import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';
import 'home_shell.dart' show performLogout;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _employee;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ApiService.instance.getTodayStatus();
      if (mounted) {
        setState(() {
          _name = s['employee_name']?.toString();
          _employee = s['employee']?.toString();
        });
      }
    } catch (_) {
      // ignore; profile still shows username + logout
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService.instance.username ?? '—';
    final name = (_name == null || _name!.isEmpty) ? 'Employee' : _name!;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 12),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: kPrimaryBlue.withOpacity(0.14),
            child: Text(initial,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryBlue)),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(name,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Center(
          child: Text('N.Air HVAC Solutions',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 24),
        if (_loading) const LinearProgressIndicator(),
        _infoTile(context, Icons.badge_outlined, 'Employee ID',
            _employee ?? '—'),
        _infoTile(context, Icons.email_outlined, 'Username / Email', user),
        _infoTile(context, Icons.dns_outlined, 'Server',
            ApiService.instance.baseUrl),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () => performLogout(context),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Log Out'),
        ),
      ],
    );
  }

  Widget _infoTile(
      BuildContext context, IconData icon, String label, String value) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: Icon(icon, color: kPrimaryBlue),
        title: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        subtitle: Text(value,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
