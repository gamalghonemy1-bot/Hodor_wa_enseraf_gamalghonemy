import 'package:flutter/material.dart';

import '../db.dart';
import '../ui.dart';
import 'session_detail_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  DateTime _day = DateTime.now();
  List<DbRow> _items = [];

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await AppDb.instance.sessionsOnDate(fmtDate(_day));
    if (mounted) setState(() => _items = r);
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      _day = d;
      _load();
    }
  }

  void _shift(int days) {
    _day = _day.add(Duration(days: days));
    _load();
  }

  Future<void> _addSession() async {
    final classes = await AppDb.instance.classes();
    if (!mounted) return;
    if (classes.isEmpty) {
      toast(context, 'أضف فصلاً وطلاباً أولاً');
      return;
    }
    int classId = classes.first['id'] as int;
    final subject = TextEditingController();
    DateTime date = _day;
    TimeOfDay start = TimeOfDay.now();
    TimeOfDay end = TimeOfDay(
        hour: (start.hour + 1) % 24, minute: start.minute);
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('حصة جديدة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: classId,
                decoration: const InputDecoration(labelText: 'الفصل'),
                items: [
                  for (final c in classes)
                    DropdownMenuItem(
                        value: c['id'] as int, child: Text(c['name'] as String))
                ],
                onChanged: (v) => setD(() => classId = v ?? classId),
              ),
              TextField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'المادة'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(fmtDate(date)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (d != null) setD(() => date = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text('البداية: ${fmtTimeOfDay(start)}'),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: start);
                  if (t != null) setD(() => start = t);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text('النهاية: ${fmtTimeOfDay(end)}'),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: end);
                  if (t != null) setD(() => end = t);
                },
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (subject.text.trim().isEmpty) {
                  setD(() => error = 'أدخل اسم المادة');
                } else if (fmtTimeOfDay(end).compareTo(fmtTimeOfDay(start)) <= 0) {
                  setD(() => error = 'وقت النهاية يجب أن يكون بعد البداية');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await AppDb.instance.addSession(
      classId: classId,
      subject: subject.text.trim(),
      date: fmtDate(date),
      start: fmtTimeOfDay(start),
      end: fmtTimeOfDay(end),
    );
    _day = date;
    _load();
  }

  Future<void> _delete(DbRow s) async {
    final ok = await confirmDialog(context, 'حذف الحصة وسجلات حضورها؟');
    if (ok) await AppDb.instance.deleteSession(s['id'] as int);
  }

  Widget _chip(SessionState st) {
    final (label, color) = switch (st) {
      SessionState.upcoming => ('قادمة', Colors.orange),
      SessionState.active => ('جارية', Colors.green),
      SessionState.ended => ('منتهية', Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحصص'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right)),
            TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_month),
              label: Text(fmtDate(_day)),
            ),
            IconButton(
                onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left)),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _addSession, child: const Icon(Icons.add)),
      body: _items.isEmpty
          ? const Center(child: Text('لا توجد حصص في هذا اليوم'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _items[i];
                final st = sessionState(s);
                return ListTile(
                  title: Text('${s['subject']} — ${s['class_name']}'),
                  subtitle: Text(
                      '${s['start_time']} – ${s['end_time']}   •   حضور ${s['present_count']}/${s['total']}'),
                  leading: _chip(st),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(s),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SessionDetailScreen(session: s)),
                  ),
                );
              },
            ),
    );
  }
}
