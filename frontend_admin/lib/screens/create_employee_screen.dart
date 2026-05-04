import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class CreateEmployeeScreen extends StatefulWidget {
  const CreateEmployeeScreen({Key? key}) : super(key: key);

  @override
  State<CreateEmployeeScreen> createState() => _CreateEmployeeScreenState();
}

class _CreateEmployeeScreenState extends State<CreateEmployeeScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _nameCtrl       = TextEditingController();
  final _emailCtrl          = TextEditingController();
  final _passCtrl           = TextEditingController();
  final _phoneCtrl          = TextEditingController();
  final _emergencyCtrl      = TextEditingController();
  final _joiningCtrl        = TextEditingController();
  final _homeLinkCtrl       = TextEditingController();

  bool _obscurePass = true;
  bool _saving      = false;

  // Document photos
  File? _profilePhoto;
  File? _aadhaarFront;
  File? _aadhaarBack;
  File? _panFront;
  File? _panBack;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    _phoneCtrl.dispose(); _emergencyCtrl.dispose();
    _joiningCtrl.dispose(); _homeLinkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(Function(File) onPicked, {bool frontCamera = false}) async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AdminTheme.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AdminTheme.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded,
                color: AdminTheme.skyBlue),
            title: const Text("Take Photo"),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded,
                color: AdminTheme.skyBlue),
            title: const Text("Choose from Gallery"),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    final xfile = await _picker.pickImage(
      source: choice,
      imageQuality: 60,
      maxWidth: 1200,
      preferredCameraDevice:
          frontCamera ? CameraDevice.front : CameraDevice.rear,
    );
    if (xfile != null && mounted) {
      setState(() => onPicked(File(xfile.path)));
    }
  }

  Future<void> _selectJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AdminTheme.skyBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _joiningCtrl.text =
          "${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}";
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // Step 1 — create employee (mandatory fields only)
      final created = await AdminApiService.createEmployeeRaw(
        name:     _nameCtrl.text.trim(),
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      if (created == null) {
        _showSnack("Failed — email may already exist", error: true);
        setState(() => _saving = false);
        return;
      }

      final empId = created['_id'].toString();

      // Step 2 — update optional text fields + home location
      final updates = <String, dynamic>{};
      if (_phoneCtrl.text.trim().isNotEmpty)
        updates['phone'] = _phoneCtrl.text.trim();
      if (_emergencyCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Emergency contact is required")));
        return;
      }
      if (_emergencyCtrl.text.trim().isNotEmpty)
        updates['emergencyContact'] = _emergencyCtrl.text.trim();
      if (_joiningCtrl.text.isNotEmpty)
        updates['joiningDate'] = _joiningCtrl.text;
      if (_homeLinkCtrl.text.trim().isNotEmpty)
        updates['homeMapsLink'] = _homeLinkCtrl.text.trim();

      if (updates.isNotEmpty) {
        await AdminApiService.updateEmployee(empId, updates);
      }

      // Step 3 — upload document photos one by one
      final docs = <String, File?>{
        'profile':      _profilePhoto,
        'aadhaar_front': _aadhaarFront,
        'aadhaar_back':  _aadhaarBack,
        'pan_front':     _panFront,
        'pan_back':      _panBack,
      };

      for (final entry in docs.entries) {
        if (entry.value != null) {
          await AdminApiService.uploadEmployeeDocument(
              empId: empId,
              docType: entry.key,
              file: entry.value!);
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // signal refresh
        _showSnack("Employee created successfully ✓");
      }
    } catch (e) {
      _showSnack("Error: $e", error: true);
      setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AdminTheme.error : AdminTheme.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("New Employee",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: AdminTheme.textMuted, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text("Save",
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AdminTheme.border)),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Profile photo
              Center(child: _buildProfilePicker()),
              const SizedBox(height: 28),

              // ── Mandatory fields ──────────────────────────────────────
              _sectionHeader("Basic Info", "* Required", Icons.person_rounded),
              const SizedBox(height: 14),
              _buildCard([
                _textField(_nameCtrl, "Full Name *",
                    Icons.person_outline_rounded,
                    validator: (v) => v!.trim().isEmpty ? "Name is required" : null),
                _divider(),
                _textField(_emailCtrl, "Email *",
                    Icons.email_outlined,
                    keyboard: TextInputType.emailAddress,
                    validator: (v) => v!.trim().isEmpty ? "Email is required" : null),
                _divider(),
                _passwordField(),
              ]),

              const SizedBox(height: 24),

              // ── Optional fields ───────────────────────────────────────
              _sectionHeader("Additional Info", "Optional",
                  Icons.info_outline_rounded),
              const SizedBox(height: 14),
              _buildCard([
                _textField(_phoneCtrl, "Phone Number",
                    Icons.phone_outlined,
                    keyboard: TextInputType.phone),
                const SizedBox(height: 16),
                _textField(_emergencyCtrl, "Emergency Contact *",
                    Icons.phone_in_talk_outlined,
                    keyboard: TextInputType.phone),
                _divider(),
                _dateField(),
                _divider(),
                _textField(_homeLinkCtrl, "https://maps.app.goo.gl/...",
                    Icons.home_outlined),
              ]),

              const SizedBox(height: 24),

              // ── Documents ─────────────────────────────────────────────
              _sectionHeader("Documents", "Optional — upload or take photo",
                  Icons.badge_rounded),
              const SizedBox(height: 14),
              _buildDocSection("Aadhaar Card", [
                _docPhoto("Front", _aadhaarFront,
                    (f) => setState(() => _aadhaarFront = f)),
                _docPhoto("Back",  _aadhaarBack,
                    (f) => setState(() => _aadhaarBack  = f)),
              ]),
              const SizedBox(height: 14),
              _buildDocSection("PAN Card", [
                _docPhoto("Front", _panFront,
                    (f) => setState(() => _panFront = f)),
                _docPhoto("Back",  _panBack,
                    (f) => setState(() => _panBack  = f)),
              ]),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile photo picker ────────────────────────────────────────────────────
  Widget _buildProfilePicker() {
    return GestureDetector(
      onTap: () => _pickPhoto(
          (f) => setState(() => _profilePhoto = f), frontCamera: true),
      child: Stack(children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AdminTheme.skyLight,
            border: Border.all(color: AdminTheme.skyBlue.withOpacity(0.3),
                width: 2),
            image: _profilePhoto != null
                ? DecorationImage(
                    image: FileImage(_profilePhoto!),
                    fit: BoxFit.cover)
                : null,
          ),
          child: _profilePhoto == null
              ? const Icon(Icons.person_rounded,
                  color: AdminTheme.skyBlue, size: 44)
              : null,
        ),
        Positioned(
          bottom: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
                color: AdminTheme.skyBlue, shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt_rounded,
                color: Colors.white, size: 14),
          ),
        ),
      ]),
    );
  }

  // ── Document photo pair ─────────────────────────────────────────────────────
  Widget _buildDocSection(String title, List<Widget> photos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            color: AdminTheme.textPrimary,
            fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Row(children: photos
            .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
            .toList()..removeLast()),
      ]),
    );
  }

  Widget _docPhoto(String label, File? file, Function(File) onPick) {
    return GestureDetector(
      onTap: () => _pickPhoto(onPick),
      child: Column(children: [
        Container(
          height: 90,
          decoration: BoxDecoration(
            color: AdminTheme.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: file != null
                  ? AdminTheme.success.withOpacity(0.4)
                  : AdminTheme.border,
              width: 1.5,
            ),
            image: file != null
                ? DecorationImage(
                    image: FileImage(file), fit: BoxFit.cover)
                : null,
          ),
          child: file == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: AdminTheme.textMuted.withOpacity(0.6),
                        size: 28),
                    const SizedBox(height: 4),
                    Text("Add",
                        style: TextStyle(
                            color: AdminTheme.textMuted.withOpacity(0.6),
                            fontSize: 11)),
                  ],
                )
              : Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: AdminTheme.success,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 10),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(
            color: AdminTheme.textMuted,
            fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── Form helpers ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, String sub, IconData icon) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AdminTheme.skyLight,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AdminTheme.skyBlue, size: 18),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            color: AdminTheme.textPrimary,
            fontSize: 15, fontWeight: FontWeight.w700)),
        Text(sub, style: const TextStyle(
            color: AdminTheme.textMuted, fontSize: 11)),
      ]),
    ]);
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: children),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType keyboard = TextInputType.text,
       String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        validator: validator,
        style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: AdminTheme.textMuted, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
          errorStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextFormField(
        controller: _passCtrl,
        obscureText: _obscurePass,
        validator: (v) => v!.trim().isEmpty ? "Password is required" : null,
        style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Password *",
          hintStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.lock_outline_rounded,
              color: AdminTheme.textMuted, size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePass ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AdminTheme.textMuted, size: 18),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
          errorStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _dateField() {
    return GestureDetector(
      onTap: _selectJoiningDate,
      child: AbsorbPointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _joiningCtrl,
            style: const TextStyle(
                color: AdminTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: "Joining Date",
              hintStyle: TextStyle(
                  color: AdminTheme.textMuted, fontSize: 13),
              prefixIcon: Icon(Icons.calendar_today_outlined,
                  color: AdminTheme.textMuted, size: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                  vertical: 16, horizontal: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
      height: 1, thickness: 1,
      color: Color(0xFFEDF2FB), indent: 16, endIndent: 16);
}