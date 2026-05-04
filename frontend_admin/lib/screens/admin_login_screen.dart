import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/services/admin_api_service.dart';
import '/theme/admin_theme.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading       = false;
  bool _obscure       = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  Future<void> _login() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final user = await AdminApiService.login(
        _emailCtrl.text.trim(), _passwordCtrl.text.trim());
    setState(() => _loading = false);
    if (user != null && mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => AdminDashboardScreen(admin: user)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid credentials or not an admin")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Logo / brand
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AdminTheme.skyBlue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                      color: AdminTheme.skyBlue.withOpacity(0.35),
                      blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.admin_panel_settings_rounded,
                    color: Colors.white, size: 36),
              ),

              const SizedBox(height: 28),
              const Text("Admin Portal",
                  style: TextStyle(
                      color: AdminTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text("Laundoor Car Wash Management",
                  style: TextStyle(
                      color: AdminTheme.textMuted, fontSize: 14)),

              const SizedBox(height: 48),

              // Email
              _buildLabel("Email"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _emailCtrl,
                hint: "admin@laundoor.in",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 20),

              // Password
              _buildLabel("Password"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _passwordCtrl,
                hint: "••••••••",
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off_outlined
                             : Icons.visibility_outlined,
                    color: AdminTheme.textMuted, size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),

              const SizedBox(height: 36),

              // Login button
              GestureDetector(
                onTap: _loading ? null : _login,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: AdminTheme.skyBlue.withOpacity(0.35),
                        blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Text("Sign In",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(text,
      style: const TextStyle(
          color: AdminTheme.textPrimary,
          fontWeight: FontWeight.w600, fontSize: 13));

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(
            color: AdminTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: AdminTheme.textMuted, fontSize: 14),
          prefixIcon: Icon(icon, color: AdminTheme.textMuted, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}