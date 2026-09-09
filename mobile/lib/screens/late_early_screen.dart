import 'package:flutter/material.dart';

/// UI-only Late / Early Request screen. Submit shows a demo message; no API
/// call yet. Will be wired to JEW Late Early Application in a later pass.
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

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
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

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Request submitted (demo only — not yet connected to backend)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Late / Early Request')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, [
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
            _tapField(context, Icons.calendar_today_outlined,
                _date == null
                    ? 'Select date'
                    : '${_date!.day}/${_date!.month}/${_date!.year}',
                _date != null, _pickDate),
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
              onPressed: _submit,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.send),
              label: const Text('Submit'),
            ),
          ]),
        ],
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

  Widget _card(BuildContext context, List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
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
