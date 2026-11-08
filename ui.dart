import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<String?> promptText(BuildContext c, String title,
    {String initial = '', String label = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('حفظ')),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext c, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد')),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

String fmtTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const arabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

String qrPayload(String code) => 'ATT:$code';

/// صورة PNG لرمز QR على خلفية بيضاء مع هامش.
Future<Uint8List> qrPng(String data, {double size = 480}) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square, color: Colors.black),
  );
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
  final pad = size * 0.08;
  canvas.translate(pad, pad);
  painter.paint(canvas, Size(size - 2 * pad, size - 2 * pad));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

Future<File> writeTemp(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, name));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

String esc(String s) => const HtmlEscape().convert(s);
