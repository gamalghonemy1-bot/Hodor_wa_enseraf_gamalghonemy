import 'package:flutter/material.dart';

import '../db.dart';
import '../ui.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
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
    final r = await AppDb.instance.classes();
    if (mounted) setState(() => _items = r);
  }

  Future<void> _add() async {
    final name = await promptText(context, 'فصل جديد', label: 'اسم الفصل');
    if (name == null || name.isEmpty) return;
    await AppDb.instance.addClass(name);
  }

  Future<void> _rename(DbRow c) async {
    final name = await promptText(context, 'تعديل اسم الفصل',
        initial: c['name'] as String, label: 'اسم الفصل');
    if (name == null || name.isEmpty) return;
    await AppDb.instance.renameClass(c['id'] as int, name);
  }

  Future<void> _delete(DbRow c) async {
    final ok = await confirmDialog(context,
        'حذف الفصل "${c['name']}" سيحذف طلابه وحصصه وسجلات حضوره. متابعة؟');
    if (!ok) return;
    await AppDb.instance.deleteClass(c['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفصول')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const Center(child: Text('لا توجد فصول. أضف فصلاً للبدء.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _items[i];
                return ListTile(
                  title: Text(c['name'] as String),
                  subtitle: Text('عدد الطلاب: ${c['students_count']}'),
                  onTap: () => _rename(c),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(c),
                  ),
                );
              },
            ),
    );
  }
}
