import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard_screen.dart';

void main() {
  runApp(const ProviderScope(child: ObdApp()));
}

class ObdApp extends StatelessWidget {
  const ObdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "OBD Scanner",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
      ),
      home: const DashboardScreen(),
    );
  }
}
