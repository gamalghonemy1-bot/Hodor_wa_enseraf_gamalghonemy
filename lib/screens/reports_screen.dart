import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../db.dart';
import '../ui.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<DbRow> _classes = [];
  int? _classId;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int _sessions = 0;
  List<DbRow> _rows = [];
  bool _busy = false;

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
    final cls = await AppDb.instance.classes();
    int? cid = _classId;
    if (cid == null || !cls.any((c) => c['id'] == cid)) {
      cid = cls.isEmpty ? null : cls.first['id'] as int;
    }
    var sessions = 0;
    List<DbRow> rows = [];
    if (cid != null) {
      final rep = await AppDb.instance.monthlyReport(cid, _year, _month);
      sessions = rep.sessions;
      rows = rep.rows;
    }
    if (!mounted) return;
    setState(() {
      _classes = cls;
      _classId = cid;
      _sessions = sessions;
      _rows = rows;
    });
  }

  void _shiftMonth(int d) {
    var m = _month + d;
    var y = _year;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    _month = m;
    _year = y;
    _load();
  }

  String _className() => _classes
      .firstWhere((c) => c['id'] == _classId, orElse: () => {'name': ''})['name']
      as String;

  String _pct(DbRow r) {
    final p = (r['present'] as int?) ?? 0;
    final a = (r['absent'] as int?) ?? 0;
    if (p + a == 0) return '—';
    return '${(p * 100 / (p + a)).round()}%';
  }

  String _html() {
    final b = StringBuffer();
    var i = 0;
    for (final r in _rows) {
      i++;
      final dates = (r['absent_dates'] as String?) ?? '';
      b.write('<tr><td>$i</td><td>${esc(r['name'] as String)}</td>'
          '<td>${(r['present'] as int?) ?? 0}</td>'
          '<td>${(r['absent'] as int?) ?? 0}</td>'
          '<td>${_pct(r)}</td><td class="d">${esc(dates)}</td></tr>');
    }
    return '''
<html dir="rtl" lang="ar"><head><meta charset="utf-8"><style>
body{font-family:sans-serif;direction:rtl;padding:12px}
h1{font-size:20px;text-align:center;margin:0 0 4px}
h2{font-size:14px;text-align:center;margin:0 0 12px;color:#444;font-weight:normal}
table{width:100%;border-collapse:collapse;font-size:12px}
th,td{border:1px solid #666;padding:5px;text-align:center}
th{background:#d9ece8}.d{font-size:10px;direction:ltr}
tr{page-break-inside:avoid}
</style></head><body>
<h1>تقرير الحضور والغياب الشهري</h1>
<h2>الفصل: ${esc(_className())} — ${arabicMonths[_month - 1]} $_year — عدد الحصص المنتهية: $_sessions</h2>
<table><tr><th>#</th><th>اسم الطالب</th><th>حضور</th><th>غياب</th><th>النسبة</th><th>تواريخ الغياب</th></tr>
$b</table></body></html>''';
  }

  Future<void> _pdf({required bool share}) async {
    if (_rows.isEmpty) {
      toast(context, 'لا توجد بيانات لهذا الفصل');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await Printing.convertHtml(html: _html());
      final name = 'report_${_year}_${_month.toString().padLeft(2, '0')}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      }
    } catch (e) {
      if (mounted) toast(context, 'تعذّر إنشاء التقرير: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير الشهرية')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: DropdownButtonFormField<int>(
            value: _classId,
            decoration: const InputDecoration(labelText: 'الفصل'),
            items: [
              for (final c in _classes)
                DropdownMenuItem(
                    value: c['id'] as int, child: Text(c['name'] as String)),
            ],
            onChanged: (v) {
              _classId = v;
              _load();
            },
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_right)),
          Text('${arabicMonths[_month - 1]} $_year',
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_left)),
        ]),
        Text('الحصص المنتهية في الشهر: $_sessions'),
        const Divider(),
        Expanded(
          child: _rows.isEmpty
              ? const Center(child: Text('لا توجد بيانات'))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return ListTile(
                      title: Text(r['name'] as String),
                      subtitle: Text(
                          'حضور ${(r['present'] as int?) ?? 0}   غياب ${(r['absent'] as int?) ?? 0}'),
                      trailing: Text(_pct(r)),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _pdf(share: false),
                  icon: const Icon(Icons.print),
                  label: const Text('عرض / طباعة PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pdf(share: true),
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة PDF'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
