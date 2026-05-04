import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class EditEmployeeScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  const EditEmployeeScreen({Key? key, required this.employee}) : super(key: key);
  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final _nameCtrl        = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _emergencyCtrl   = TextEditingController();
  final _locationCtrl    = TextEditingController();
  final _passCtrl        = TextEditingController();
  final _confirmCtrl     = TextEditingController();

  DateTime? _joiningDate;
  bool _saving = false;
  bool _showPass = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameCtrl.text      = e['name']             ?? '';
    _emailCtrl.text     = e['email']            ?? '';
    _phoneCtrl.text     = e['phone']            ?? '';
    _emergencyCtrl.text = e['emergencyContact'] ?? '';
    _locationCtrl.text  = e['homeMapsLink']     ?? '';
    if (e['joiningDate'] != null) {
      try { _joiningDate = DateTime.parse(e['joiningDate']); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _emergencyCtrl.dispose(); _locationCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<String> _resolveUrl(String url) async {
    if (!url.contains('goo.gl') && !url.contains('maps.app')) return url;
    try {
      final response = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 10) Chrome/91.0'})
          .timeout(const Duration(seconds: 8));
      return response.request?.url.toString() ?? url;
    } catch (_) { return url; }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate:  DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AdminTheme.skyBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });

    // Validate
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() { _saving = false; _error = "Name and email are required."; });
      return;
    }
    if (_emergencyCtrl.text.trim().isEmpty) {
      setState(() { _saving = false; _error = "Emergency contact is required."; });
      return;
    }
    if (_passCtrl.text.isNotEmpty && _passCtrl.text != _confirmCtrl.text) {
      setState(() { _saving = false; _error = "Passwords do not match."; });
      return;
    }

    // Build update payload
    final updates = <String, dynamic>{
      'name':             _nameCtrl.text.trim(),
      'email':            _emailCtrl.text.trim(),
      'phone':            _phoneCtrl.text.trim(),
      'emergencyContact': _emergencyCtrl.text.trim(),
    };
    if (_joiningDate != null) {
      updates['joiningDate'] = _joiningDate!.toIso8601String().split('T')[0];
    }
    if (_passCtrl.text.isNotEmpty) {
      updates['password'] = _passCtrl.text;
    }
    final rawLink = _locationCtrl.text.trim();
    if (rawLink.isNotEmpty) {
      updates['homeMapsLink'] = await _resolveUrl(rawLink);
    }

    final result = await AdminApiService.updateEmployee(
        widget.employee['_id'].toString(), updates);

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Employee updated ✓"),
              backgroundColor: AdminTheme.success));
      Navigator.pop(context, true); // return true so caller can refresh
    } else {
      setState(() { _saving = false; _error = "Failed to save. Try again."; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Edit Employee",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AdminTheme.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _section("Basic Info", Icons.person_rounded),
          _field("Full Name", _nameCtrl, hint: "John Doe"),
          const SizedBox(height: 12),
          _field("Email", _emailCtrl, hint: "john@example.com",
              keyboard: TextInputType.emailAddress),

          const SizedBox(height: 24),
          _section("Additional Info", Icons.info_outline_rounded),
          _field("Phone", _phoneCtrl, hint: "+91 9876543210",
              keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          _field("Emergency Contact *", _emergencyCtrl,
              hint: "+91 9876543210",
              keyboard: TextInputType.phone),
          const SizedBox(height: 12),

          // Joining date
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AdminTheme.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminTheme.border),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AdminTheme.skyBlue, size: 16),
                const SizedBox(width: 10),
                Text(
                  _joiningDate != null
                      ? "${_joiningDate!.day.toString().padLeft(2,'0')} "
                        "${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_joiningDate!.month-1]} "
                        "${_joiningDate!.year}"
                      : "Joining Date (tap to pick)",
                  style: TextStyle(
                      color: _joiningDate != null
                          ? AdminTheme.textPrimary : AdminTheme.textMuted,
                      fontSize: 14),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 24),
          _section("Home Location", Icons.location_on_rounded),
          _field("Google Maps Link", _locationCtrl,
              hint: "https://maps.app.goo.gl/...", maxLines: 2),

          const SizedBox(height: 24),
          _section("Reset Password", Icons.lock_reset_rounded),
          const Text("Leave blank to keep current password",
              style: TextStyle(color: AdminTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 10),
          _passwordField("New Password", _passCtrl),
          const SizedBox(height: 12),
          _passwordField("Confirm Password", _confirmCtrl),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 28),
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AdminTheme.skyBlue, Color(0xFF1A90D9)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: AdminTheme.skyBlue.withOpacity(0.3),
                    blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Center(child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text("Save Changes",
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _section(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Icon(icon, color: AdminTheme.skyBlue, size: 16),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: AdminTheme.textPrimary,
          fontWeight: FontWeight.w700, fontSize: 14)),
    ]),
  );

  Widget _field(String label, TextEditingController ctrl, {
    String? hint, TextInputType? keyboard, int maxLines = 1,
  }) => TextField(
    controller: ctrl,
    keyboardType: keyboard,
    maxLines: maxLines,
    style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: AdminTheme.textMuted),
      labelStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 12),
      filled: true, fillColor: AdminTheme.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminTheme.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminTheme.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminTheme.skyBlue, width: 1.5)),
    ),
  );

  Widget _passwordField(String label, TextEditingController ctrl) =>
    TextField(
      controller: ctrl,
      obscureText: !_showPass,
      style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 12),
        filled: true, fillColor: AdminTheme.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTheme.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTheme.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTheme.skyBlue, width: 1.5)),
        suffixIcon: IconButton(
          icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => setState(() => _showPass = !_showPass),
        ),
      ),
    );
}