import 'package:flutter/material.dart';
import '../widgets.dart';

/// UI-only Apply for Leave screen. Submit shows a demo message; no API call yet.
/// Will be wired to Leave Application / Leave Details doctypes in a later pass.
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

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Select date' : '${d.day}/${d.month}/${d.year}';

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

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Leave request submitted (demo only — not yet connected to backend)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(context, 'New Request', [
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
            decoration: _dec(context, Icons.notes_outlined,
                hint: 'Reason for leave'),
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
        const SectionLabel('My Leave Requests'),
        _emptyState(context, Icons.event_busy_outlined, 'No requests yet',
            'Your submitted leave requests will appear here.'),
      ],
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

  Widget _card(BuildContext context, String title, List<Widget> children) {
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
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
      BuildContext context, IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(icon, size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(sub,
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
