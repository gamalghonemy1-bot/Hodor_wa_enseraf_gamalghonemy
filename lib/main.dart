import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'db.dart';
import 'screens/backup_screen.dart';
import 'screens/classes_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/students_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حضور الطلاب',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00695C),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppDb.instance.finalizeEnded();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      AppDb.instance.finalizeEnded();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppDb.instance.finalizeEnded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SessionsScreen(),
          StudentsScreen(),
          ClassesScreen(),
          ReportsScreen(),
          BackupScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.event_note), label: 'الحصص'),
          NavigationDestination(icon: Icon(Icons.people), label: 'الطلاب'),
          NavigationDestination(icon: Icon(Icons.class_), label: 'الفصول'),
          NavigationDestination(
              icon: Icon(Icons.picture_as_pdf), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.backup), label: 'النسخ'),
        ],
      ),
    );
  }
}
