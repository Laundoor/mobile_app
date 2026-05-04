import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'customer_pricing_screen.dart';

class EditCustomerScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const EditCustomerScreen({Key? key, required this.customer}) : super(key: key);
  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  final _nameCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _vehicleNoCtrl = TextEditingController();
  final _vehicleColorCtrl = TextEditingController();
  final _carModelCtrl = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _mapsCtrl    = TextEditingController();

  String _carType      = 'Hatchback';
  String _interiorType = 'None';
  bool _saving    = false;
  String? _error;
  // Payment contact
  List<Map<String, dynamic>> _contacts = [];
  int?   _selectedContactIndex; // null = none selected

  static const _carTypes      = ['Hatchback', 'Sedan', 'SUV'];
  static const _interiorTypes = ['None', 'Interior Standard', 'Interior Premium'];

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl.text         = c['customerName'] ?? '';
    _addressCtrl.text      = c['address']      ?? '';
    _vehicleNoCtrl.text    = c['vehicleNumber'] ?? '';
    _vehicleColorCtrl.text = c['vehicleColor']  ?? '';
    _carModelCtrl.text     = c['carModel']      ?? '';
    _phoneCtrl.text        = c['phone']         ?? '';
    _mapsCtrl.text         = c['mapsLink']      ?? '';
    _carType = (c['carType'] != null && _carTypes.contains(c['carType']))
        ? c['carType'] : 'Hatchback';
    _interiorType = (c['interiorType'] != null &&
            _interiorTypes.contains(c['interiorType']))
        ? c['interiorType'] : 'None';
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final config = await AdminApiService.getInvoicePricing();
    if (!mounted) return;
    final contacts = (config?['contacts'] as List? ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    // Match existing customer payment contact
    final existing = widget.customer['paymentContact'] as Map?;
    int? selectedIdx;
    if (existing != null && existing['number'] != null) {
      for (int i = 0; i < contacts.length; i++) {
        if (contacts[i]['number'] == existing['number']) {
          selectedIdx = i;
          break;
        }
      }
    }
    setState(() {
      _contacts              = contacts;
      _selectedContactIndex  = selectedIdx;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _addressCtrl.dispose(); _vehicleNoCtrl.dispose();
    _vehicleColorCtrl.dispose(); _carModelCtrl.dispose();
    _phoneCtrl.dispose(); _mapsCtrl.dispose();
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

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = "Customer name is required.");
      return;
    }
    setState(() { _saving = true; _error = null; });

    final rawLink = _mapsCtrl.text.trim();
    final fullLink = rawLink.isNotEmpty ? await _resolveUrl(rawLink) : '';

    final updates = <String, dynamic>{
      'customerName':  _nameCtrl.text.trim(),
      'address':       _addressCtrl.text.trim(),
      'vehicleNumber': _vehicleNoCtrl.text.trim(),
      'vehicleColor':  _vehicleColorCtrl.text.trim(),
      'carModel':      _carModelCtrl.text.trim(),
      'carType':       _carType,
      'interiorType':  _interiorType,
      'phone':         _phoneCtrl.text.trim(),
      if (fullLink.isNotEmpty) 'mapsLink': fullLink,
      if (_selectedContactIndex != null &&
          _selectedContactIndex! < _contacts.length)
        'paymentContact': _contacts[_selectedContactIndex!],
    };

    final result = await AdminApiService.updateCustomer(
        widget.customer['_id'].toString(), updates);

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Customer updated ✓"),
              backgroundColor: AdminTheme.success));
      Navigator.pop(context, true);
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
        title: const Text("Edit Customer",
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

          _section("Customer Info", Icons.person_rounded),
          _field("Full Name *", _nameCtrl, hint: "Customer Name"),
          const SizedBox(height: 12),
          _field("Phone", _phoneCtrl, hint: "+91 9876543210",
              keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          _field("Address", _addressCtrl, hint: "Street, City", maxLines: 2),

          const SizedBox(height: 24),
          _section("Vehicle Info", Icons.directions_car_rounded),

          // Car type selector
          const Text("Car Type",
              style: TextStyle(color: AdminTheme.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: _carTypes.map((t) {
            final active = _carType == t;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _carType = t),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AdminTheme.skyBlue : AdminTheme.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: active ? AdminTheme.skyBlue : AdminTheme.border),
                ),
                child: Center(child: Text(t,
                    style: TextStyle(
                        color: active ? Colors.white : AdminTheme.textMuted,
                        fontWeight: FontWeight.w700, fontSize: 12))),
              ),
            ));
          }).toList()),
          const SizedBox(height: 12),
          _field("Car Model", _carModelCtrl, hint: "e.g. Maruti Swift"),
          const SizedBox(height: 12),
          _field("Vehicle Number", _vehicleNoCtrl, hint: "TN 01 AB 1234"),
          const SizedBox(height: 12),
          _field("Vehicle Color", _vehicleColorCtrl, hint: "e.g. White"),
          const SizedBox(height: 16),

          // Interior type selector
          const Text("Interior Service",
              style: TextStyle(color: AdminTheme.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._interiorTypes.map((t) {
            final active = _interiorType == t;
            return GestureDetector(
              onTap: () => setState(() => _interiorType = t),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AdminTheme.skyBlue : AdminTheme.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: active
                          ? AdminTheme.skyBlue : AdminTheme.border),
                ),
                child: Text(
                  t == 'None' ? '🚫 No interior'
                      : t == 'Interior Standard'
                          ? '🪑 Interior Standard'
                          : '✨ Interior Premium',
                  style: TextStyle(
                      color: active ? Colors.white : AdminTheme.textMuted,
                      fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            );
          }),

          const SizedBox(height: 24),
          _section("Location", Icons.location_on_rounded),
          _field("Google Maps Link", _mapsCtrl,
              hint: "https://maps.app.goo.gl/...", maxLines: 2),

          const SizedBox(height: 24),
          _section("Payment Contact", Icons.payment_rounded),
          if (_contacts.isEmpty)
            const Text("No payment contacts configured. Set them in Config → Invoice Pricing.",
                style: TextStyle(color: AdminTheme.textMuted, fontSize: 12))
          else
            Column(children: [
              // None option
              GestureDetector(
                onTap: () => setState(() => _selectedContactIndex = null),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _selectedContactIndex == null
                        ? AdminTheme.skyBlue : AdminTheme.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _selectedContactIndex == null
                            ? AdminTheme.skyBlue : AdminTheme.border),
                  ),
                  child: Text("None",
                      style: TextStyle(
                          color: _selectedContactIndex == null
                              ? Colors.white : AdminTheme.textMuted,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              ..._contacts.asMap().entries.map((entry) {
                final i    = entry.key;
                final c    = entry.value;
                final name = c['name'] ?? '';
                final num  = c['number'] ?? '';
                if (name.isEmpty && num.isEmpty) return const SizedBox.shrink();
                final active = _selectedContactIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedContactIndex = i),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? AdminTheme.skyBlue : AdminTheme.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: active
                              ? AdminTheme.skyBlue : AdminTheme.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_rounded,
                          color: active
                              ? Colors.white : AdminTheme.skyBlue,
                          size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Text("$name · $num",
                          style: TextStyle(
                              color: active
                                  ? Colors.white : AdminTheme.textPrimary,
                              fontWeight: FontWeight.w600, fontSize: 13))),
                      if (active)
                        const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16),
                    ]),
                  ),
                );
              }),
            ]),

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

          const SizedBox(height: 24),

          // ── Custom pricing shortcut ────────────────────────────────
          _buildPricingShortcut(),

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

  Widget _buildPricingShortcut() {
    final cp      = widget.customer['customPricing'] as Map?;
    final enabled = cp?['enabled'] == true;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => CustomerPricingScreen(customer: widget.customer),
        ));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: enabled
                  ? AdminTheme.skyBlue.withOpacity(0.4)
                  : AdminTheme.border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AdminTheme.skyLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.price_change_rounded,
                color: AdminTheme.skyBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text("Invoice Pricing",
                style: TextStyle(color: AdminTheme.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              enabled
                  ? "Custom rates set for this customer"
                  : "Using global rates — tap to customise",
              style: const TextStyle(
                  color: AdminTheme.textMuted, fontSize: 11)),
          ])),
          if (enabled)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AdminTheme.skyLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text("Custom",
                  style: TextStyle(color: AdminTheme.skyBlue,
                      fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AdminTheme.textMuted, size: 18),
        ]),
      ),
    );
  }

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
}