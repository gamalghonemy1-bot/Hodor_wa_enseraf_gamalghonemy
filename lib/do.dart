import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

typedef DbRow = Map<String, Object?>;

/// يُزاد عند أي تغيير في البيانات لتحديث الشاشات.
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
void notifyDataChanged() => dataVersion.value++;

enum ScanResult { ok, duplicate, notFound, wrongClass, closed }

class ScanOutcome {
  final ScanResult result;
  final String? name;
  const ScanOutcome(this.result, [this.name]);
}

enum SessionState { upcoming, active, ended }

final DateFormat _dateFmt = DateFormat('yyyy-MM-dd', 'en');
String fmtDate(DateTime d) => _dateFmt.format(d);

DateTime _at(String date, String time) => DateTime.parse('$date $time:00');

SessionState sessionState(DbRow s, [DateTime? now]) {
  now ??= DateTime.now();
  final start = _at(s['date'] as String, s['start_time'] as String);
  final end = _at(s['date'] as String, s['end_time'] as String);
  if (!now.isBefore(end)) return SessionState.ended;
  if (!now.isBefore(start)) return SessionState.active;
  return SessionState.upcoming;
}

String _newCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  static const _fileName = 'attendance.db';

  Database? _db;
  Future<Database>? _opening;

  Future<String> get dbPath async =>
      p.join(await getDatabasesPath(), _fileName);

  Future<Database> get db {
    final cur = _db;
    if (cur != null) return Future.value(cur);
    return _opening ??= _open().then((d) {
      _db = d;
      _opening = null;
      return d;
    });
  }

  Future<Database> _open() async {
    return openDatabase(
      await dbPath,
      version: 1,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE classes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            code TEXT NOT NULL UNIQUE,
            class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
            phone TEXT
          )''');
        await d.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
            subject TEXT NOT NULL,
            date TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            finalized INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            status TEXT NOT NULL,
            scanned_at TEXT,
            UNIQUE(session_id, student_id)
          )''');
        await d.execute('CREATE INDEX idx_sessions_date ON sessions(date)');
      },
    );
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    _opening = null;
    await d?.close();
  }

  // ---------------- الفصول ----------------
  Future<List<DbRow>> classes() async => (await db).rawQuery('''
        SELECT c.id, c.name,
          (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id) AS students_count
        FROM classes c ORDER BY c.name''');

  Future<void> addClass(String name) async {
    await (await db).insert('classes', {'name': name});
    notifyDataChanged();
  }

  Future<void> renameClass(int id, String name) async {
    await (await db)
        .update('classes', {'name': name}, where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  Future<void> deleteClass(int id) async {
    await (await db).delete('classes', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ---------------- الطلاب ----------------
  Future<List<DbRow>> students({int? classId}) async => (await db).rawQuery('''
        SELECT s.id, s.name, s.code, s.phone, s.class_id, c.name AS class_name
        FROM students s JOIN classes c ON c.id = s.class_id
        ${classId == null ? '' : 'WHERE s.class_id = ?'}
        ORDER BY s.name''', classId == null ? [] : [classId]);

  Future<void> addStudent(String name, int classId, String? phone) async {
    final d = await db;
    String code;
    do {
      code = _newCode();
    } while ((await d.query('students', where: 'code = ?', whereArgs: [code]))
        .isNotEmpty);
    await d.insert('students', {
      'name': name,
      'code': code,
      'class_id': classId,
      'phone': (phone == null || phone.isEmpty) ? null : phone,
    });
    notifyDataChanged();
  }

  Future<void> updateStudent(
      int id, String name, int classId, String? phone) async {
    await (await db).update(
        'students',
        {
          'name': name,
          'class_id': classId,
          'phone': (phone == null || phone.isEmpty) ? null : phone,
        },
        where: 'id = ?',
        whereArgs: [id]);
    notifyDataChanged();
  }

  Future<void> deleteStudent(int id) async {
    await (await db).delete('students', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ---------------- الحصص ----------------
  Future<List<DbRow>> sessionsOnDate(String date) async => (await db).rawQuery('''
        SELECT s.*, c.name AS class_name,
          (SELECT COUNT(*) FROM attendance a
             WHERE a.session_id = s.id AND a.status = 'present') AS present_count,
          (SELECT COUNT(*) FROM students st WHERE st.class_id = s.class_id) AS total
        FROM sessions s JOIN classes c ON c.id = s.class_id
        WHERE s.date = ? ORDER BY s.start_time''', [date]);

  Future<void> addSession({
    required int classId,
    required String subject,
    required String date,
    required String start,
    required String end,
  }) async {
    await (await db).insert('sessions', {
      'class_id': classId,
      'subject': subject,
      'date': date,
      'start_time': start,
      'end_time': end,
      'finalized': 0,
    });
    notifyDataChanged();
  }

  Future<void> deleteSession(int id) async {
    await (await db).delete('sessions', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  Future<List<DbRow>> roster(int sessionId, int classId) async =>
      (await db).rawQuery('''
        SELECT st.id, st.name, a.status, a.scanned_at
        FROM students st
        LEFT JOIN attendance a ON a.student_id = st.id AND a.session_id = ?
        WHERE st.class_id = ? ORDER BY st.name''', [sessionId, classId]);

  Future<int> presentCount(int sessionId) async {
    final r = await (await db).rawQuery(
        "SELECT COUNT(*) AS n FROM attendance WHERE session_id = ? AND status = 'present'",
        [sessionId]);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> setStatus(int sessionId, int studentId, String status) async {
    await (await db).insert(
        'attendance',
        {
          'session_id': sessionId,
          'student_id': studentId,
          'status': status,
          'scanned_at':
              status == 'present' ? DateTime.now().toIso8601String() : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDataChanged();
  }

  // ---------------- تسجيل الحضور ----------------
  Future<ScanOutcome> recordScan(int sessionId, String code) async {
    final d = await db;
    final ss =
        await d.query('sessions', where: 'id = ?', whereArgs: [sessionId]);
    if (ss.isEmpty) return const ScanOutcome(ScanResult.closed);
    final s = ss.first;
    if (sessionState(s) != SessionState.active) {
      return const ScanOutcome(ScanResult.closed);
    }
    final st = await d.query('students', where: 'code = ?', whereArgs: [code]);
    if (st.isEmpty) return const ScanOutcome(ScanResult.notFound);
    final stu = st.first;
    final name = stu['name'] as String;
    if (stu['class_id'] != s['class_id']) {
      return ScanOutcome(ScanResult.wrongClass, name);
    }
    final ex = await d.query('attendance',
        where: 'session_id = ? AND student_id = ?',
        whereArgs: [sessionId, stu['id']]);
    if (ex.isNotEmpty && ex.first['status'] == 'present') {
      return ScanOutcome(ScanResult.duplicate, name);
    }
    await d.insert(
        'attendance',
        {
          'session_id': sessionId,
          'student_id': stu['id'],
          'status': 'present',
          'scanned_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDataChanged();
    return ScanOutcome(ScanResult.ok, name);
  }

  /// تسجيل الغياب تلقائياً لكل طالب لم يُسجَّل حضوره في حصة انتهت.
  Future<int> finalizeEnded() async {
    final d = await db;
    final now = DateTime.now();
    final rows = await d.query('sessions', where: 'finalized = 0');
    var n = 0;
    for (final s in rows) {
      final end = _at(s['date'] as String, s['end_time'] as String);
      if (now.isBefore(end)) continue;
      await d.transaction((t) async {
        await t.rawInsert('''
          INSERT OR IGNORE INTO attendance(session_id, student_id, status, scanned_at)
          SELECT ?, id, 'absent', NULL FROM students WHERE class_id = ?''',
            [s['id'], s['class_id']]);
        await t.update('sessions', {'finalized': 1},
            where: 'id = ?', whereArgs: [s['id']]);
      });
      n++;
    }
    if (n > 0) notifyDataChanged();
    return n;
  }

  // ---------------- التقارير ----------------
  Future<({int sessions, List<DbRow> rows})> monthlyReport(
      int classId, int year, int month) async {
    await finalizeEnded();
    final d = await db;
    final from = '$year-${month.toString().padLeft(2, '0')}-01';
    final ny = month == 12 ? year + 1 : year;
    final nm = month == 12 ? 1 : month + 1;
    final to = '$ny-${nm.toString().padLeft(2, '0')}-01';

    final cnt = await d.rawQuery(
        'SELECT COUNT(*) AS n FROM sessions WHERE class_id = ? AND date >= ? AND date < ? AND finalized = 1',
        [classId, from, to]);
    final rows = await d.rawQuery('''
        SELECT st.id, st.name,
          SUM(CASE WHEN x.status = 'present' THEN 1 ELSE 0 END) AS present,
          SUM(CASE WHEN x.status = 'absent' THEN 1 ELSE 0 END) AS absent,
          GROUP_CONCAT(CASE WHEN x.status = 'absent' THEN x.date END, ', ') AS absent_dates
        FROM students st
        LEFT JOIN (
          SELECT a.student_id, a.status, s.date
          FROM attendance a JOIN sessions s ON s.id = a.session_id
          WHERE s.class_id = ? AND s.date >= ? AND s.date < ?
        ) x ON x.student_id = st.id
        WHERE st.class_id = ?
        GROUP BY st.id ORDER BY st.name''', [classId, from, to, classId]);
    return (sessions: (cnt.first['n'] as int?) ?? 0, rows: rows);
  }

  // ---------------- النسخ الاحتياطي ----------------
  Future<File> createBackupFile() async {
    await db; // يضمن وجود الملف
    await close(); // يضمن كتابة كل التغييرات قبل النسخ
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm', 'en').format(DateTime.now());
    final out = File(p.join(dir.path, 'attendance_backup_$stamp.db'));
    await File(await dbPath).copy(out.path);
    return out;
  }

  Future<void> restoreFrom(String srcPath) async {
    final dir = await getTemporaryDirectory();
    final tmp = p.join(dir.path, 'restore_check.db');
    await File(srcPath).copy(tmp);
    final test = await openDatabase(tmp, readOnly: true);
    try {
      final t = await test
          .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
      final names = t.map((e) => e['name']).toSet();
      for (final n in ['classes', 'students', 'sessions', 'attendance']) {
        if (!names.contains(n)) {
          throw const FormatException('ملف النسخة الاحتياطية غير صالح');
        }
      }
    } finally {
      await test.close();
    }
    await close();
    final path = await dbPath;
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(tmp).copy(path);
    notifyDataChanged();
  }
}
