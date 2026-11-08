import 'package:flutter/material.dart';

import '../db.dart';
import 'scan_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  final DbRow session;
  const SessionDetailScreen({super.key, required this.session});
  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<DbRow> _roster = [];

  int get _sid => widget.session['id'] as int;

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
    final r = await AppDb.instance
        .roster(_sid, widget.session['class_id'] as int);
    if (mounted) setState(() => _roster = r);
  }

  @override
  Widget build(BuildContext context) {
    final st = sessionState(widget.session);
    final present = _roster.where((r) => r['status'] == 'present').length;
    final absent = _roster.where((r) => r['status'] == 'absent').length;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.session['subject']}')),
      floatingActionButton: st == SessionState.active
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ScanScreen(session: widget.session)),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('مسح QR'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${widget.session['date']}   ${widget.session['start_time']} – ${widget.session['end_time']}\n'
            'حاضر: $present    غائب: $absent    الإجمالي: ${_roster.length}',
            textAlign: TextAlign.center,
          ),
        ),
        if (st == SessionState.upcoming)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('الحصة لم تبدأ بعد؛ يفتح المسح عند وقت البداية.'),
          ),
        if (st == SessionState.ended)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('انتهت الحصة وسُجّل الغياب تلقائياً. يمكنك التعديل يدوياً.'),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _roster.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = _roster[i];
              final status = r['status'] as String?;
              final (label, color) = switch (status) {
                'present' => ('حاضر', Colors.green),
                'absent' => ('غائب', Colors.red),
                _ => ('لم يُسجَّل', Colors.grey),
              };
              return ListTile(
                title: Text(r['name'] as String),
                subtitle: Text(label, style: TextStyle(color: color)),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) =>
                      AppDb.instance.setStatus(_sid, r['id'] as int, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'present', child: Text('تسجيل حاضر')),
                    PopupMenuItem(value: 'absent', child: Text('تسجيل غائب')),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
