import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../ui.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<DbRow> _students = [];
  List<DbRow> _classes = [];
  int? _filter;
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
    final st = await AppDb.instance.students(classId: _filter);
    if (!mounted) return;
    setState(() {
      _classes = cls;
      _students = st;
    });
  }

  Future<void> _form([DbRow? s]) async {
    if (_classes.isEmpty) {
      toast(context, 'أضف فصلاً أولاً من تبويب الفصول');
      return;
    }
    final name = TextEditingController(text: (s?['name'] as String?) ?? '');
    final phone = TextEditingController(text: (s?['phone'] as String?) ?? '');
    int classId = (s?['class_id'] as int?) ??
        _filter ??
        (_classes.first['id'] as int);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s == null ? 'طالب جديد' : 'تعديل الطالب'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم الطالب'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: classId,
                decoration: const InputDecoration(labelText: 'الفصل'),
                items: [
                  for (final c in _classes)
                    DropdownMenuItem(
                        value: c['id'] as int, child: Text(c['name'] as String))
                ],
                onChanged: (v) => setD(() => classId = v ?? classId),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'هاتف ولي الأمر (اختياري)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (s == null) {
      await AppDb.instance.addStudent(name.text.trim(), classId, phone.text.trim());
    } else {
      await AppDb.instance
          .updateStudent(s['id'] as int, name.text.trim(), classId, phone.text.trim());
    }
  }

  Future<void> _delete(DbRow s) async {
    final ok = await confirmDialog(
        context, 'حذف الطالب "${s['name']}" وكل سجلات حضوره؟');
    if (ok) await AppDb.instance.deleteStudent(s['id'] as int);
  }

  void _showQr(DbRow s) {
    final code = s['code'] as String;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['name'] as String),
        content: SizedBox(
          width: 240,
          height: 260,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            QrImageView(
              data: qrPayload(code),
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(code, style: const TextStyle(letterSpacing: 2)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final png = await qrPng(qrPayload(code));
              final f = await writeTemp('qr_$code.png', png);
              await Share.shareXFiles([XFile(f.path)], text: s['name'] as String);
            },
            child: const Text('مشاركة كصورة'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  /// بطاقات QR لكل طلاب الفصل المحدد في ملف PDF للطباعة.
  Future<void> _printCards() async {
    if (_filter == null) {
      toast(context, 'اختر فصلاً من القائمة أعلاه أولاً');
      return;
    }
    if (_students.isEmpty) {
      toast(context, 'لا يوجد طلاب في هذا الفصل');
      return;
    }
    setState(() => _busy = true);
    try {
      final cards = StringBuffer();
      for (final s in _students) {
        final png = await qrPng(qrPayload(s['code'] as String), size: 360);
        cards.write('<div class="card"><img src="data:image/png;base64,'
            '${base64Encode(png)}"/><div class="n">${esc(s['name'] as String)}</div>'
            '<div class="c">${esc(s['class_name'] as String)}</div></div>');
      }
      final html = '''
<html dir="rtl"><head><meta charset="utf-8"><style>
body{font-family:sans-serif;direction:rtl;margin:0}
.card{display:inline-block;width:30%;margin:1.5%;padding:8px;border:1px solid #444;
border-radius:8px;text-align:center;page-break-inside:avoid;box-sizing:border-box}
img{width:100%}.n{font-weight:bold;font-size:15px;margin-top:4px}.c{font-size:12px;color:#555}
</style></head><body>$cards</body></html>''';
      final bytes = await Printing.convertHtml(html: html);
      await Printing.sharePdf(bytes: bytes, filename: 'qr_cards.pdf');
    } catch (e) {
      if (mounted) toast(context, 'تعذّر إنشاء البطاقات: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الطلاب'),
        actions: [
          IconButton(
            tooltip: 'طباعة بطاقات QR للفصل',
            onPressed: _busy ? null : _printCards,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.qr_code_2),
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton(onPressed: () => _form(), child: const Icon(Icons.person_add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: DropdownButtonFormField<int?>(
            value: _filter,
            decoration: const InputDecoration(labelText: 'الفصل'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('كل الفصول')),
              for (final c in _classes)
                DropdownMenuItem<int?>(
                    value: c['id'] as int, child: Text(c['name'] as String)),
            ],
            onChanged: (v) {
              _filter = v;
              _load();
            },
          ),
        ),
        Expanded(
          child: _students.isEmpty
              ? const Center(child: Text('لا يوجد طلاب'))
              : ListView.separated(
                  itemCount: _students.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = _students[i];
                    return ListTile(
                      title: Text(s['name'] as String),
                      subtitle: Text(s['class_name'] as String),
                      onTap: () => _showQr(s),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _form(s);
                          if (v == 'del') _delete(s);
                          if (v == 'qr') _showQr(s);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'qr', child: Text('عرض QR')),
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'del', child: Text('حذف')),
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
