import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets.dart';

/// Late / Early Request — wired to JEW Late Early Application via the API.
class LateEarlyScreen extends StatefulWidget {
  const LateEarlyScreen({super.key});
  @override
  State<LateEarlyScreen> createState() => _LateEarlyScreenState();
}

class _LateEarlyScreenState extends State<LateEarlyScreen> {
  static const _types = ['Late Coming', 'Early Going'];
  String _type = _types.first;
  DateTime? _date;
  TimeOfDay? _time;
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

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _timeApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _loadRequests() async {
    setState(() => _loadingList = true);
    try {
      final res = await ApiService.instance.getMyLateEarlyRequests();
      if (mounted) setState(() => _requests = res['requests'] ?? []);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: _time ?? TimeOfDay.now());
    if (t != null) setState(() => _time = t);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _submit() async {
    if (_date == null) return _snack('Please select a date', error: true);
    if (_time == null) return _snack('Please select the expected time', error: true);
    if (_reason.text.trim().isEmpty) {
      return _snack('Please enter a reason', error: true);
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService.instance.applyLateEarly(
        applicationType: _type,
        applicationDate: _iso(_date!),
        expectedTime: _timeApi(_time!),
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      _snack('Request submitted — status: ${res['status'] ?? 'Pending'}');
      setState(() {
        _date = null;
        _time = null;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Late / Early Request')),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _formCard(context),
            const SectionLabel('My Requests'),
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
            const _Label('Request type'),
            SegmentedButton<String>(
              segments: _types
                  .map((t) => ButtonSegment(value: t, label: Text(t)))
                  .toList(),
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            const _Label('Application date'),
            _tapField(
                context,
                Icons.calendar_today_outlined,
                _date == null
                    ? 'Select date'
                    : '${_date!.day}/${_date!.month}/${_date!.year}',
                _date != null,
                _pickDate),
            const SizedBox(height: 16),
            const _Label('Expected time'),
            _tapField(context, Icons.access_time,
                _time == null ? 'Select time' : _time!.format(context),
                _time != null, _pickTime),
            const SizedBox(height: 16),
            const _Label('Reason'),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason for late coming / early going',
                prefixIcon: const Icon(Icons.notes_outlined, size: 20),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
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
                child: Text(r['application_type']?.toString() ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              StatusBadge(r['status']?.toString() ?? ''),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.event, size: 15, color: Colors.grey),
              const SizedBox(width: 6),
              Text('${r['application_date']}   ·   '
                  '${r['expected_time'].toString().split('.').first}'),
            ]),
            if ((r['reason']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r['reason'].toString(),
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tapField(BuildContext context, IconData icon, String text,
      bool filled, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text,
            style: TextStyle(
                color: filled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(Icons.schedule_outlined,
            size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        const Text('No requests yet',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
