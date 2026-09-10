import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';
import '../location_permission.dart';
import 'history_screen.dart';
import 'late_early_screen.dart';

/// The redesigned landing content (rendered inside HomeShell's Scaffold).
class HomeTab extends StatefulWidget {
  final void Function(int tabIndex) onGoToTab;
  const HomeTab({super.key, required this.onGoToTab});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _status;
  double? _leaveTotal; // remaining leave balance (null = unavailable)
  bool _loading = true;
  String? _error;
  bool _locDegraded = false; // background location not "always" granted
  bool _bannerDismissed = false; // dismissed this session only

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    // slight delay so the one-time permission dialog (from HomeShell) resolves
    await Future.delayed(const Duration(seconds: 2));
    final degraded = await LocationPermissionFlow.isDegraded();
    if (mounted) setState(() => _locDegraded = degraded);
  }

  Widget _locationBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kAccentOrange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAccentOrange.withOpacity(0.5)),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.location_off, color: kAccentOrange),
        title: const Text('Background location tracking is off',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: const Text('Tap to enable in Settings', style: TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _bannerDismissed = true),
        ),
        onTap: () => LocationPermissionFlow.openSettings(),
      ),
    );
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
    }
    // leave balance is best-effort; its failure shouldn't blank the screen
    try {
      final b = await ApiService.instance.getLeaveBalance();
      if (mounted) setState(() => _leaveTotal = (b['total'] as num?)?.toDouble());
    } catch (_) {
      if (mounted) setState(() => _leaveTotal = null);
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _leaveBalText {
    if (_leaveTotal == null) return '—';
    final v = _leaveTotal!;
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s d';
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  String _fmtTime(dynamic dt) {
    if (dt == null) return '';
    final s = dt.toString();
    return s.contains(' ') ? s.split(' ').last.substring(0, 5) : s;
  }

  String _workedToday(Map<String, dynamic> s) {
    final ci = s['check_in_time'], co = s['check_out_time'];
    if (ci == null) return '—';
    try {
      final inT = DateTime.parse(ci.toString());
      final outT = co == null ? DateTime.now() : DateTime.parse(co.toString());
      final d = outT.difference(inT);
      if (d.isNegative) return '—';
      final h = d.inHours, m = d.inMinutes % 60;
      return '${h}h ${m}m';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _status;
    final name = s?['employee_name']?.toString() ?? '';
    final status = s?['current_status']?.toString() ?? 'Not Marked';
    final checkedIn = s?['checked_in'] == true;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_error != null) ErrorBanner(_error!),
          if (_locDegraded && !_bannerDismissed) _locationBanner(context),

          const SectionLabel('Today Overview'),

          // greeting
          Text('${greetingForNow()},',
              style: Theme.of(context).textTheme.titleMedium),
          Text(name.isEmpty ? '—' : name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(_fmtDate(s?['date']?.toString()),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),

          const SizedBox(height: 16),
          _statusCard(context, s, status, checkedIn),

          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: StatTile(
                label: 'Status',
                value: checkedIn ? 'Marked' : 'Not Marked',
                icon: checkedIn ? Icons.check_circle : Icons.pending_outlined,
                color: checkedIn ? Colors.green : kAccentOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: 'Leave Bal.',
                value: _leaveBalText, // total remaining CL+PL from Frappe HR
                icon: Icons.event_available_outlined,
                color: kPrimaryBlue,
              ),
            ),
          ]),

          const SectionLabel('Quick Actions'),
          QuickActionTile(
            icon: Icons.fingerprint,
            color: kPrimaryBlue,
            title: 'Mark attendance',
            subtitle: 'Face + geofence verified',
            onTap: () => widget.onGoToTab(1),
          ),
          QuickActionTile(
            icon: Icons.history,
            color: Colors.teal,
            title: 'Attendance history',
            subtitle: 'Timeline & monthly summary',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          QuickActionTile(
            icon: Icons.event_note,
            color: kAccentOrange,
            title: 'Apply for leave',
            subtitle: 'Submit & track requests',
            onTap: () => widget.onGoToTab(2),
          ),
          QuickActionTile(
            icon: Icons.schedule,
            color: Colors.purple,
            title: 'Late / Early request',
            subtitle: 'Apply for late coming or early going',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LateEarlyScreen())),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, Map<String, dynamic>? s,
      String status, bool checkedIn) {
    final ciText = checkedIn
        ? 'Checked in at ${_fmtTime(s?['check_in_time'])}'
        : 'No check-in yet today';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // thin gradient progress bar across the top
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kPrimaryBlue, kAccentOrange]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(status),
                      const SizedBox(height: 10),
                      Text(ciText,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('WORKED TODAY',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(_workedToday(s ?? {}),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
