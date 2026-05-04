import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class AdminConfigScreen extends StatefulWidget {
  const AdminConfigScreen({Key? key}) : super(key: key);
  @override State<AdminConfigScreen> createState() => _AdminConfigScreenState();
}

class _AdminConfigScreenState extends State<AdminConfigScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  bool _loading = true;

  // ── Employee pricing ──────────────────────────────────────────────────────
  final _hatchbackCtrl = TextEditingController();
  final _sedanCtrl     = TextEditingController();
  final _suvCtrl       = TextEditingController();
  final _intStdCtrl    = TextEditingController();
  final _intPremCtrl   = TextEditingController();
  final _distCtrl      = TextEditingController();
  final _incentiveCtrl = TextEditingController();
  bool _savingEmp      = false;

  // ── Invoice pricing ───────────────────────────────────────────────────────
  // Slabs: fixed 3 rows — 1-5, 6-10, 11+
  final _slab1H = TextEditingController();
  final _slab1S = TextEditingController();
  final _slab1U = TextEditingController();
  final _slab2H = TextEditingController();
  final _slab2S = TextEditingController();
  final _slab2U = TextEditingController();
  final _slab3H = TextEditingController();
  final _slab3S = TextEditingController();
  final _slab3U = TextEditingController();
  final _invIntStdCtrl  = TextEditingController();
  final _invIntPremCtrl = TextEditingController();
  // Contacts
  final _contact0NameCtrl = TextEditingController();
  final _contact0NumCtrl  = TextEditingController();
  final _contact1NameCtrl = TextEditingController();
  final _contact1NumCtrl  = TextEditingController();
  String? _qr0Url;
  String? _qr1Url;
  bool _savingInv = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _hatchbackCtrl.dispose(); _sedanCtrl.dispose(); _suvCtrl.dispose();
    _intStdCtrl.dispose(); _intPremCtrl.dispose();
    _distCtrl.dispose(); _incentiveCtrl.dispose();
    _slab1H.dispose(); _slab1S.dispose(); _slab1U.dispose();
    _slab2H.dispose(); _slab2S.dispose(); _slab2U.dispose();
    _slab3H.dispose(); _slab3S.dispose(); _slab3U.dispose();
    _invIntStdCtrl.dispose(); _invIntPremCtrl.dispose();
    _contact0NameCtrl.dispose(); _contact0NumCtrl.dispose();
    _contact1NameCtrl.dispose(); _contact1NumCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final emp = await AdminApiService.getPricing();
      final inv = await AdminApiService.getInvoicePricing();
      if (!mounted) return;

      // Employee pricing
      final ext = emp?['exterior'] as Map? ?? {};
      _hatchbackCtrl.text = (ext['Hatchback'] ?? 20).toString();
      _sedanCtrl.text     = (ext['Sedan']     ?? 25).toString();
      _suvCtrl.text       = (ext['SUV']        ?? 30).toString();
      _intStdCtrl.text    = (emp?['interiorStandard'] ?? 40).toString();
      _intPremCtrl.text   = (emp?['interiorPremium']  ?? 60).toString();
      _distCtrl.text      = (emp?['distancePerKm']    ?? 2).toString();
      _incentiveCtrl.text = (emp?['dailyIncentive']   ?? 100).toString();

      // Invoice pricing slabs
      final slabs = (inv?['slabs'] as List?) ?? [];
      void fillSlab(int i, TextEditingController h,
          TextEditingController s, TextEditingController u) {
        if (i < slabs.length) {
          final sl = slabs[i] as Map? ?? {};
          h.text = (sl['hatchback'] ?? 0).toString();
          s.text = (sl['sedan']     ?? 0).toString();
          u.text = (sl['suv']       ?? 0).toString();
        }
      }
      fillSlab(0, _slab1H, _slab1S, _slab1U);
      fillSlab(1, _slab2H, _slab2S, _slab2U);
      fillSlab(2, _slab3H, _slab3S, _slab3U);
      _invIntStdCtrl.text  = (inv?['interiorStandard'] ?? 0).toString();
      _invIntPremCtrl.text = (inv?['interiorPremium']  ?? 0).toString();

      // Contacts
      final contacts = (inv?['contacts'] as List?) ?? [];
      if (contacts.isNotEmpty) {
        final c0 = contacts[0] as Map? ?? {};
        _contact0NameCtrl.text = c0['name']   ?? '';
        _contact0NumCtrl.text  = c0['number'] ?? '';
        _qr0Url = c0['qrImageUrl'] as String?;
      }
      if (contacts.length > 1) {
        final c1 = contacts[1] as Map? ?? {};
        _contact1NameCtrl.text = c1['name']   ?? '';
        _contact1NumCtrl.text  = c1['number'] ?? '';
        _qr1Url = c1['qrImageUrl'] as String?;
      }

      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveEmployee() async {
    setState(() => _savingEmp = true);
    try {
      await AdminApiService.savePricing({
        'exterior': {
          'Hatchback': double.tryParse(_hatchbackCtrl.text) ?? 20,
          'Sedan':     double.tryParse(_sedanCtrl.text)     ?? 25,
          'SUV':       double.tryParse(_suvCtrl.text)       ?? 30,
        },
        'interiorStandard': double.tryParse(_intStdCtrl.text)   ?? 40,
        'interiorPremium':  double.tryParse(_intPremCtrl.text)  ?? 60,
        'distancePerKm':    double.tryParse(_distCtrl.text)     ?? 2,
        'dailyIncentive':   double.tryParse(_incentiveCtrl.text) ?? 100,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Employee pricing saved ✓"),
              backgroundColor: AdminTheme.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: $e")));
    } finally {
      if (mounted) setState(() => _savingEmp = false);
    }
  }

  Future<void> _saveInvoice() async {
    setState(() => _savingInv = true);
    try {
      final body = {
        'slabs': [
          { 'from': 1,  'to': 5,    'hatchback': double.tryParse(_slab1H.text) ?? 0, 'sedan': double.tryParse(_slab1S.text) ?? 0, 'suv': double.tryParse(_slab1U.text) ?? 0 },
          { 'from': 6,  'to': 10,   'hatchback': double.tryParse(_slab2H.text) ?? 0, 'sedan': double.tryParse(_slab2S.text) ?? 0, 'suv': double.tryParse(_slab2U.text) ?? 0 },
          { 'from': 11, 'to': null, 'hatchback': double.tryParse(_slab3H.text) ?? 0, 'sedan': double.tryParse(_slab3S.text) ?? 0, 'suv': double.tryParse(_slab3U.text) ?? 0 },
        ],
        'interiorStandard': double.tryParse(_invIntStdCtrl.text) ?? 0,
        'interiorPremium':  double.tryParse(_invIntPremCtrl.text) ?? 0,
        'contacts': [
          { 'name': _contact0NameCtrl.text.trim(), 'number': _contact0NumCtrl.text.trim(), 'qrImageUrl': _qr0Url },
          { 'name': _contact1NameCtrl.text.trim(), 'number': _contact1NumCtrl.text.trim(), 'qrImageUrl': _qr1Url },
        ],
      };
      await AdminApiService.updateInvoicePricing(body);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invoice pricing saved ✓"),
              backgroundColor: AdminTheme.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: $e")));
    } finally {
      if (mounted) setState(() => _savingInv = false);
    }
  }

  Future<void> _uploadQr(int index) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    final url = await AdminApiService.uploadQrImage(File(picked.path), index);
    if (url != null && mounted) {
      setState(() { index == 0 ? _qr0Url = url : _qr1Url = url; });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("QR uploaded ✓"),
              backgroundColor: AdminTheme.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Config",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: AdminTheme.skyBlue,
          unselectedLabelColor: AdminTheme.textMuted,
          indicatorColor: AdminTheme.skyBlue,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: "Employee Pricing"),
            Tab(text: "Invoice Pricing"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminTheme.skyBlue))
          : TabBarView(controller: _tab, children: [
              _buildEmployeeTab(),
              _buildInvoiceTab(),
            ]),
    );
  }

  // ── Employee Pricing Tab ───────────────────────────────────────────────────
  Widget _buildEmployeeTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoBanner("Changes apply to new salary calculations immediately. Past salary records are not affected."),
      const SizedBox(height: 24),
      _sectionHeader("Exterior Wash", "Price per car type (₹)", Icons.local_car_wash_rounded),
      const SizedBox(height: 14),
      _card([
        _priceRow("Hatchback", _hatchbackCtrl, Icons.directions_car_rounded),
        _divider(),
        _priceRow("Sedan",     _sedanCtrl,     Icons.directions_car_filled_rounded),
        _divider(),
        _priceRow("SUV",       _suvCtrl,       Icons.airport_shuttle_rounded),
      ]),
      const SizedBox(height: 24),
      _sectionHeader("Interior Wash", "Same rate for all car types (₹)", Icons.cleaning_services_rounded),
      const SizedBox(height: 14),
      _card([
        _priceRow("Interior Standard", _intStdCtrl,  Icons.star_outline_rounded),
        _divider(),
        _priceRow("Interior Premium",  _intPremCtrl, Icons.star_rounded),
      ]),
      const SizedBox(height: 24),
      _sectionHeader("Distance Allowance", "Rate per kilometre (₹/km)", Icons.route_rounded),
      const SizedBox(height: 14),
      _card([_priceRow("Per Kilometre", _distCtrl, Icons.straighten_rounded)]),
      const SizedBox(height: 24),
      _sectionHeader("Daily Incentive", "Awarded when all criteria are met (₹/day)", Icons.emoji_events_rounded),
      const SizedBox(height: 14),
      _card([_priceRow("Per Day", _incentiveCtrl, Icons.star_rounded)]),
      const SizedBox(height: 32),
      _saveButton("Save Employee Pricing", _savingEmp, _saveEmployee),
      const SizedBox(height: 32),
    ]),
  );

  // ── Invoice Pricing Tab ────────────────────────────────────────────────────
  Widget _buildInvoiceTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoBanner("These prices are used for customer invoices. Independent from employee salary pricing."),
      const SizedBox(height: 24),

      // Exterior slabs
      _sectionHeader("Exterior Slabs", "Price per wash (₹) by count range", Icons.local_car_wash_rounded),
      const SizedBox(height: 14),
      // Header row
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: const [
          Expanded(flex: 2, child: Text("Range", style: TextStyle(color: AdminTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
          Expanded(child: Text("Hatch", textAlign: TextAlign.center, style: TextStyle(color: AdminTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
          Expanded(child: Text("Sedan", textAlign: TextAlign.center, style: TextStyle(color: AdminTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
          Expanded(child: Text("SUV",   textAlign: TextAlign.center, style: TextStyle(color: AdminTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
      ),
      _card([
        _slabRow("1 – 5",   _slab1H, _slab1S, _slab1U),
        _divider(),
        _slabRow("6 – 10",  _slab2H, _slab2S, _slab2U),
        _divider(),
        _slabRow("11 +",    _slab3H, _slab3S, _slab3U),
      ]),
      const SizedBox(height: 24),

      // Interior invoice prices
      _sectionHeader("Interior Wash", "Flat rate per service (₹)", Icons.cleaning_services_rounded),
      const SizedBox(height: 14),
      _card([
        _priceRow("Interior Standard", _invIntStdCtrl,  Icons.star_outline_rounded),
        _divider(),
        _priceRow("Interior Premium",  _invIntPremCtrl, Icons.star_rounded),
      ]),
      const SizedBox(height: 24),

      // Payment contacts
      _sectionHeader("Payment Contacts", "Two business numbers for invoices", Icons.payment_rounded),
      const SizedBox(height: 14),
      _contactCard(0, _contact0NameCtrl, _contact0NumCtrl, _qr0Url),
      const SizedBox(height: 12),
      _contactCard(1, _contact1NameCtrl, _contact1NumCtrl, _qr1Url),
      const SizedBox(height: 32),
      _saveButton("Save Invoice Pricing", _savingInv, _saveInvoice),
      const SizedBox(height: 32),
    ]),
  );

  Widget _contactCard(int index, TextEditingController nameCtrl,
      TextEditingController numCtrl, String? qrUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Contact ${index + 1}",
            style: const TextStyle(color: AdminTheme.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _textField(nameCtrl, "Name", Icons.person_rounded),
        const SizedBox(height: 10),
        _textField(numCtrl, "Mobile Number", Icons.phone_rounded,
            keyboard: TextInputType.phone),
        const SizedBox(height: 12),
        // QR image
        Row(children: [
          if (qrUrl != null && qrUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(qrUrl, width: 70, height: 70,
                  fit: BoxFit.cover),
            ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _uploadQr(index),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                  color: AdminTheme.skyLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AdminTheme.skyBlue.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.qr_code_rounded,
                    color: AdminTheme.skyBlue, size: 16),
                const SizedBox(width: 6),
                Text(qrUrl != null ? "Replace QR" : "Upload QR",
                    style: const TextStyle(
                        color: AdminTheme.skyBlue,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _infoBanner(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AdminTheme.skyLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.skyBlue.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: AdminTheme.skyBlue, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(
          color: AdminTheme.skyDark, fontSize: 12, height: 1.4))),
    ]),
  );

  Widget _sectionHeader(String title, String sub, IconData icon) =>
      Row(children: [
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: AdminTheme.skyLight,
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: AdminTheme.skyBlue, size: 18),
    ),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AdminTheme.textPrimary,
          fontSize: 15, fontWeight: FontWeight.w700)),
      Text(sub, style: const TextStyle(
          color: AdminTheme.textMuted, fontSize: 11)),
    ]),
  ]);

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(children: children),
  );

  Widget _priceRow(String label, TextEditingController ctrl, IconData icon) =>
      Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AdminTheme.textMuted, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: const TextStyle(
          color: AdminTheme.textPrimary, fontSize: 14,
          fontWeight: FontWeight.w500))),
      const Text("₹ ", style: TextStyle(color: AdminTheme.textMuted,
          fontSize: 14, fontWeight: FontWeight.w600)),
      SizedBox(width: 80, child: _numField(ctrl)),
    ]),
  );

  Widget _slabRow(String range, TextEditingController h,
      TextEditingController s, TextEditingController u) =>
      Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(flex: 2, child: Text(range, style: const TextStyle(
          color: AdminTheme.textPrimary, fontSize: 13,
          fontWeight: FontWeight.w600))),
      Expanded(child: _numField(h)),
      const SizedBox(width: 6),
      Expanded(child: _numField(s)),
      const SizedBox(width: 6),
      Expanded(child: _numField(u)),
    ]),
  );

  Widget _numField(TextEditingController ctrl) => TextField(
    controller: ctrl,
    textAlign: TextAlign.center,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
    style: const TextStyle(color: AdminTheme.textPrimary,
        fontSize: 14, fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AdminTheme.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminTheme.skyBlue)),
    ),
  );

  Widget _textField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard}) =>
      TextField(
    controller: ctrl,
    keyboardType: keyboard,
    style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AdminTheme.textMuted, size: 18),
      labelStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 12),
      filled: true, fillColor: AdminTheme.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminTheme.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminTheme.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminTheme.skyBlue, width: 1.5)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
    ),
  );

  Widget _divider() => Divider(height: 1, thickness: 1,
      color: AdminTheme.border, indent: 16, endIndent: 16);

  Widget _saveButton(String label, bool saving, VoidCallback onTap) =>
      GestureDetector(
    onTap: saving ? null : onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: AdminTheme.skyBlue.withOpacity(0.35),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Center(child: saving
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 16))),
    ),
  );
}