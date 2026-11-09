import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../ui.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, 'حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToDevice() => _run(() async {
        final f = await AppDb.instance.createBackupFile();
        final bytes = await f.readAsBytes();
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ النسخة الاحتياطية',
          fileName: f.uri.pathSegments.last,
          bytes: bytes,
        );
        if (!mounted) return;
        toast(context, path == null ? 'أُلغي الحفظ' : 'تم حفظ النسخة الاحتياطية');
      });

  Future<void> _share() => _run(() async {
        final f = await AppDb.instance.createBackupFile();
        await Share.shareXFiles([XFile(f.path)], text: 'نسخة احتياطية - حضور الطلاب');
      });

  Future<void> _restore() async {
    final ok = await confirmDialog(context,
        'ستُستبدل كل البيانات الحالية بمحتوى النسخة المختارة. هل تريد المتابعة؟');
    if (!ok) return;
    await _run(() async {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      await AppDb.instance.restoreFrom(path);
      if (mounted) toast(context, 'تمت استعادة البيانات بنجاح');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'قاعدة البيانات محفوظة على هذا الهاتف فقط. خذ نسخة احتياطية بانتظام '
          'واحفظها خارج الهاتف (واتساب، البريد، الملفات، ...).',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _saveToDevice,
          icon: const Icon(Icons.save_alt),
          label: const Text('حفظ نسخة احتياطية في ملف'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.share),
          label: const Text('مشاركة نسخة احتياطية'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('استعادة من ملف نسخة احتياطية'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ]),
    );
  }
}
