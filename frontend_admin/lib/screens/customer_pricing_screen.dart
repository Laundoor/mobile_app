import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class CustomerPricingScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerPricingScreen({Key? key, required this.customer})
      : super(key: key);
  @override
  State<CustomerPricingScreen> createState() => _CustomerPricingScreenState();
}

class _CustomerPricingScreenState extends State<CustomerPricingScreen> {
  bool _saving   = false;
  bool _loading  = true;
  bool _enabled  = false;

  // Slab controllers — 3 slabs, each has one field per car type
  // We only show the relevant car type column for this customer
  // but store all three so the schema stays consistent
  final _s1H = TextEditingController();
  final _s1S = TextEditingController();
  final _s1U = TextEditingController();
  final _s2H = TextEditingController();
  final _s2S = TextEditingController();
  final _s2U = TextEditingController();
  final _s3H = TextEditingController();
  final _s3S = TextEditingController();
  final _s3U = TextEditingController();

  final _intStdCtrl  = TextEditingController();
  final _intPremCtrl = TextEditingController();

  late String _carType;
  late String _interiorType;

  @override
  void initState() {
    super.initState();
    _carType      = widget.customer['carType']      ?? 'Hatchback';
    _interiorType = widget.customer['interiorType'] ?? 'None';
    _initFromCustomer();
  }

  @override
  void dispose() {
    _s1H.dispose(); _s1S.dispose(); _s1U.dispose();
    _s2H.dispose(); _s2S.dispose(); _s2U.dispose();
    _s3H.dispose(); _s3S.dispose(); _s3U.dispose();
    _intStdCtrl.dispose(); _intPremCtrl.dispose();
    super.dispose();
  }

  Future<void> _initFromCustomer() async {
    setState(() => _loading = true);
    final cp = widget.customer['customPricing'] as Map?;

    if (cp != null && cp['enabled'] == true) {
      _enabled = true;
      final slabs = (cp['slabs'] as List?) ?? [];
      void fill(int i, TextEditingController h,
          TextEditingController s, TextEditingController u) {
        if (i < slabs.length) {
          final sl = slabs[i] as Map? ?? {};
          h.text = (sl['hatchback'] ?? 0).toString();
          s.text = (sl['sedan']     ?? 0).toString();
          u.text = (sl['suv']       ?? 0).toString();
        }
      }
      fill(0, _s1H, _s1S, _s1U);
      fill(1, _s2H, _s2S, _s2U);
      fill(2, _s3H, _s3S, _s3U);
      _intStdCtrl.text  = (cp['interiorStandard'] ?? 0).toString();
      _intPremCtrl.text = (cp['interiorPremium']  ?? 0).toString();
    } else {
      // Pre-fill from global pricing as starting point
      final global = await AdminApiService.getInvoicePricing();
      if (mounted && global != null) {
        final slabs = (global['slabs'] as List?) ?? [];
        void fill(int i, TextEditingController h,
            TextEditingController s, TextEditingController u) {
          if (i < slabs.length) {
            final sl = slabs[i] as Map? ?? {};
            h.text = (sl['hatchback'] ?? 0).toString();
            s.text = (sl['sedan']     ?? 0).toString();
            u.text = (sl['suv']       ?? 0).toString();
          }
        }
        fill(0, _s1H, _s1S, _s1U);
        fill(1, _s2H, _s2S, _s2U);
        fill(2, _s3H, _s3S, _s3U);
        _intStdCtrl.text  = (global['interiorStandard'] ?? 0).toString();
        _intPremCtrl.text = (global['interiorPremium']  ?? 0).toString();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // Helper to get/set the right controller for this customer's car type
  TextEditingController _ctrlForType(
      TextEditingController h,
      TextEditingController s,
      TextEditingController u) {
    switch (_carType) {
      case 'Sedan': return s;
      case 'SUV':   return u;
      default:      return h; // Hatchback
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'enabled': _enabled,
      'slabs': [
        { 'from': 1,  'to': 5,    'hatchback': double.tryParse(_s1H.text) ?? 0, 'sedan': double.tryParse(_s1S.text) ?? 0, 'suv': double.tryParse(_s1U.text) ?? 0 },
        { 'from': 6,  'to': 10,   'hatchback': double.tryParse(_s2H.text) ?? 0, 'sedan': double.tryParse(_s2S.text) ?? 0, 'suv': double.tryParse(_s2U.text) ?? 0 },
        { 'from': 11, 'to': null, 'hatchback': double.tryParse(_s3H.text) ?? 0, 'sedan': double.tryParse(_s3S.text) ?? 0, 'suv': double.tryParse(_s3U.text) ?? 0 },
      ],
      'interiorStandard': double.tryParse(_intStdCtrl.text) ?? 0,
      'interiorPremium':  double.tryParse(_intPremCtrl.text) ?? 0,
    };

    final result = await AdminApiService.updateCustomerPricing(
        widget.customer['_id'].toString(), payload);

    if (!mounted) return;
    setState(() => _saving = false);

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_enabled
              ? "Custom pricing saved ✓"
              : "Custom pricing cleared — using global rates"),
          backgroundColor: AdminTheme.success));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Save failed. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInterior = _interiorType != 'None';
    final isStd  = _interiorType == 'Interior Standard';

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Custom Pricing",
              style: TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          Text(widget.customer['customerName'] ?? '',
              style: const TextStyle(
                  color: AdminTheme.textMuted, fontSize: 11)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AdminTheme.border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AdminTheme.skyBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                // ── Enable toggle ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _enabled
                            ? AdminTheme.skyBlue.withOpacity(0.4)
                            : AdminTheme.border),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text("Custom Pricing",
                          style: TextStyle(color: AdminTheme.textPrimary,
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        _enabled
                            ? "Using individual rates for this customer"
                            : "Using global invoice pricing rates",
                        style: const TextStyle(
                            color: AdminTheme.textMuted, fontSize: 11)),
                    ])),
                    Switch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      activeColor: AdminTheme.skyBlue,
                    ),
                  ]),
                ),

                if (!_enabled) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AdminTheme.warning.withOpacity(0.3))),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AdminTheme.warning, size: 16),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Toggle on to set individual rates. "
                          "Rates below are pre-filled from global config.",
                          style: TextStyle(color: AdminTheme.warning,
                              fontSize: 11, height: 1.4)),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Customer info strip ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: AdminTheme.skyLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AdminTheme.skyBlue.withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.directions_car_rounded,
                        color: AdminTheme.skyBlue, size: 16),
                    const SizedBox(width: 8),
                    Text("$_carType · $_interiorType",
                        style: const TextStyle(
                            color: AdminTheme.skyDark,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      "Showing rates for $_carType only",
                      style: const TextStyle(
                          color: AdminTheme.textMuted, fontSize: 10)),
                  ]),
                ),

                const SizedBox(height: 24),

                // ── Exterior slabs ──────────────────────────────────────
                _sectionHeader("Exterior Wash",
                    "Price per wash (₹) — $_carType",
                    Icons.local_car_wash_rounded),
                const SizedBox(height: 12),
                _buildSlabsCard(),

                if (hasInterior) ...[
                  const SizedBox(height: 24),
                  // ── Interior ─────────────────────────────────────────
                  _sectionHeader("Interior Wash",
                      "Flat rate per service (₹)",
                      Icons.cleaning_services_rounded),
                  const SizedBox(height: 12),
                  _buildCard([
                    if (isStd || _interiorType == 'Interior Standard')
                      _priceRow("Interior Standard", _intStdCtrl,
                          Icons.star_outline_rounded),
                    if (!isStd)
                      _priceRow("Interior Premium", _intPremCtrl,
                          Icons.star_rounded),
                  ]),
                ],

                const SizedBox(height: 32),

                // ── Save ────────────────────────────────────────────────
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _enabled
                            ? [AdminTheme.skyBlue, const Color(0xFF1A90D9)]
                            : [AdminTheme.textMuted, AdminTheme.textMuted],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _enabled ? [BoxShadow(
                          color: AdminTheme.skyBlue.withOpacity(0.35),
                          blurRadius: 18, offset: const Offset(0, 6))] : [],
                    ),
                    child: Center(child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(
                            _enabled ? "Save Custom Pricing" : "Save (Use Global Rates)",
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 15))),
                  ),
                ),
                const SizedBox(height: 16),

                // Clear custom pricing button
                if (_enabled)
                  GestureDetector(
                    onTap: _saving ? null : () async {
                      setState(() => _enabled = false);
                      await _save();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AdminTheme.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.red.withOpacity(0.3)),
                      ),
                      child: const Center(
                        child: Text("Clear Custom Pricing",
                            style: TextStyle(color: Colors.red,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
              ]),
            ),
    );
  }

  Widget _buildSlabsCard() {
    final ranges = ['1 – 5', '6 – 10', '11 +'];
    final slabCtrls = [
      _ctrlForType(_s1H, _s1S, _s1U),
      _ctrlForType(_s2H, _s2S, _s2U),
      _ctrlForType(_s3H, _s3S, _s3U),
    ];

    return _buildCard(List.generate(3, (i) => Column(children: [
      if (i > 0)
        const Divider(height: 1, color: AdminTheme.border,
            indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AdminTheme.skyLight,
                borderRadius: BorderRadius.circular(8)),
            child: Text(ranges[i],
                style: const TextStyle(color: AdminTheme.skyDark,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          const Text("₹ ",
              style: TextStyle(color: AdminTheme.textMuted,
                  fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(width: 90, child: _numField(slabCtrls[i])),
          const SizedBox(width: 6),
          Text("/ wash",
              style: const TextStyle(color: AdminTheme.textMuted,
                  fontSize: 11)),
        ]),
      ),
    ])));
  }

  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(children: children),
  );

  Widget _priceRow(String label, TextEditingController ctrl,
      IconData icon) =>
      Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AdminTheme.textMuted, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label,
          style: const TextStyle(color: AdminTheme.textPrimary,
              fontSize: 14, fontWeight: FontWeight.w500))),
      const Text("₹ ",
          style: TextStyle(color: AdminTheme.textMuted,
              fontSize: 14, fontWeight: FontWeight.w600)),
      SizedBox(width: 90, child: _numField(ctrl)),
    ]),
  );

  Widget _numField(TextEditingController ctrl) => TextField(
    controller: ctrl,
    textAlign: TextAlign.center,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(
        RegExp(r'^\d+\.?\d{0,2}'))],
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
}