import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_login_screen.dart';

void main() {
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Laundoor Admin",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF4F8FF),
      ),
      home: const _AdminAuthGate(),
    );
  }
}

class _AdminAuthGate extends StatelessWidget {
  const _AdminAuthGate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getSavedAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF4F8FF),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.admin_panel_settings_rounded,
                      color: Color(0xFF38B6FF), size: 56),
                  SizedBox(height: 16),
                  Text("Laundoor Admin",
                      style: TextStyle(color: Color(0xFF0F172A),
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 12),
                  CircularProgressIndicator(
                      color: Color(0xFF38B6FF), strokeWidth: 2),
                ],
              ),
            ),
          );
        }
        final admin = snapshot.data;
        if (admin != null) return AdminDashboardScreen(admin: admin);
        return const AdminLoginScreen();
      },
    );
  }

  Future<Map<String, dynamic>?> _getSavedAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('admin_token');
      final id    = prefs.getString('admin_id');
      final name  = prefs.getString('admin_name');
      final email = prefs.getString('admin_email');
      if (token != null && token.isNotEmpty &&
          id   != null && id.isNotEmpty) {
        return {'_id': id, 'name': name ?? '', 'email': email ?? '',
                'role': 'admin'};
      }
    } catch (e) {
      print('[AdminAuth] Session check error: $e');
    }
    return null;
  }
}