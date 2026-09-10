import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';

/// Apply for Leave — wired to Frappe HR Leave Application via attendance_log API.
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  static const _types = ['Casual Leave', 'Privilege Leave', 'Loss of Pay'];
  String _type = _types.first;
  DateTime? _from;
  DateTime? _to;
  final _reason = TextEditingController();
  bool _submitting = false;

  List _requests = [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Select date' : '${d.day}/${d.month}/${d.year}';

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadRequests() async {
    setState(() => _loadingList = true);
    try {
      final res = await ApiService.instance.getMyLeaveRequests();
      if (mounted) setState(() => _requests = res['requests'] ?? []);
    } catch (_) {
      // keep whatever we had; list just won't refresh
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) {
      setState(() {
        if (from) {
          _from = d;
          if (_to != null && _to!.isBefore(d)) _to = d;
        } else {
          _to = d;
        }
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _submit() async {
    if (_from == null || _to == null) {
      _snack('Please select start and end dates', error: true);
      return;
    }
    if (_to!.isBefore(_from!)) {
      _snack('End date must be on or after start date', error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      _snack('Please enter a reason', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService.instance.applyLeave(
        leaveType: _type,
        fromDate: _iso(_from!),
        toDate: _iso(_to!),
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      _snack('Leave request submitted — status: ${res['status'] ?? 'Open'}');
      setState(() {
        _from = null;
        _to = null;
        _reason.clear();
      });
      _loadRequests();
    } catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _formCard(context),
          const SectionLabel('My Leave Requests'),
          if (_loadingList)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (_requests.isEmpty)
            _emptyState(context)
          else
            ..._requests.map((r) => _requestCard(context, r as Map)),
        ],
      ),
    );
  }

  Widget _formCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New Request',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const _FieldLabel('Leave type'),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: _dec(context, Icons.category_outlined),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _dateField(context, 'Start date', _from, () => _pick(true))),
              const SizedBox(width: 12),
              Expanded(child: _dateField(context, 'End date', _to, () => _pick(false))),
            ]),
            const SizedBox(height: 16),
            const _FieldLabel('Reason'),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: _dec(context, Icons.notes_outlined, hint: 'Reason for leave'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting...' : 'Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(BuildContext context, Map r) {
    final days = r['total_leave_days'];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(r['leave_type']?.toString() ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              StatusBadge(r['status']?.toString() ?? ''),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.date_range, size: 15, color: Colors.grey),
              const SizedBox(width: 6),
              Text('${r['from_date']} → ${r['to_date']}'
                  '${days != null ? '  ($days d)' : ''}'),
            ]),
            if ((r['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r['description'].toString(),
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateField(
      BuildContext context, String label, DateTime? value, VoidCallback onTap) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: _dec(context, Icons.calendar_today_outlined),
          child: Text(_fmt(value),
              style: TextStyle(
                  color: value == null
                      ? Theme.of(context).hintColor
                      : Theme.of(context).colorScheme.onSurface)),
        ),
      ),
    ]);
  }

  InputDecoration _dec(BuildContext context, IconData icon, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(Icons.event_busy_outlined,
            size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        const Text('No requests yet',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text('Your submitted leave requests will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
