import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/admin_api_service.dart';
import 'customer_history_screen.dart';
import 'customer_pricing_screen.dart';
import 'edit_customer_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerDetailScreen({Key? key, required this.customer})
      : super(key: key);

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Map<String, dynamic> _customer;
  bool _loading       = false;
  bool _uploadingPhoto = false;

  static const Color _bg         = Color(0xFFF4F8FF);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _skyBlue    = Color(0xFF38B6FF);
  static const Color _skyLight   = Color(0xFFE8F5FF);
  static const Color _skyDark    = Color(0xFF1A90D9);
  static const Color _success    = Color(0xFF22C55E);
  static const Color _textPrimary= Color(0xFF0F172A);
  static const Color _textMuted  = Color(0xFF64748B);
  static const Color _border     = Color(0xFFDDE8F5);

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Delete Customer",
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800)),
        content: Text(
            "Permanently delete ${_customer['customerName'] ?? 'this customer'}? This cannot be undone.",
            style: const TextStyle(color: Color(0xFF64748B), height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    final ok = await AdminApiService.deleteCustomer(
        _customer['_id'].toString());
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Customer deleted")));
        Navigator.pop(context, true); // pop back to customer list
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to delete")));
      }
    }
  }

  Future<void> _refresh() async {    setState(() => _loading = true);
    final fresh = await AdminApiService.getCustomer(_customer['_id']);
    if (mounted && fresh != null) setState(() => _customer = fresh);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final count = _customer['serviceCount'] ?? 0;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white, elevation: 0,
        title: Text(_customer['customerName'] ?? '',
            style: const TextStyle(color: Color(0xFF0F172A),
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: _skyBlue, size: 20),
            onPressed: () async {
              final updated = await Navigator.push<bool>(context,
                  MaterialPageRoute(builder: (_) =>
                      EditCustomerScreen(customer: Map<String, dynamic>.from(_customer))));
              if (updated == true) _refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.red, size: 20),
            onPressed: _confirmDelete,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _skyBlue),
            onPressed: _refresh,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: _skyBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                _buildInfoCard(count),
                const SizedBox(height: 16),
                _buildCarPhotoCard(),
                const SizedBox(height: 16),
                _buildStatsCard(count),
                const SizedBox(height: 16),
                _buildCustomPricingCard(),
                const SizedBox(height: 16),
                _buildHistoryButton(),
                const SizedBox(height: 32),
              ]),
            ),
    );
  }

  Widget _buildInfoCard(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _skyLight,
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.directions_car_rounded,
                color: _skyBlue, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_customer['customerName'] ?? '',
                  style: const TextStyle(color: _textPrimary,
                      fontSize: 17, fontWeight: FontWeight.w800)),
              Text(_customer['carModel'] ?? '',
                  style: const TextStyle(
                      color: _textMuted, fontSize: 13)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: _skyLight,
                borderRadius: BorderRadius.circular(12)),
            child: Text(_customer['carType'] ?? 'Hatchback',
                style: const TextStyle(color: _skyDark,
                    fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          if (_customer['customPricing']?['enabled'] == true) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text("₹ Custom",
                  style: TextStyle(color: _skyBlue,
                      fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        const Divider(color: _border),
        const SizedBox(height: 12),
        _infoRow(Icons.confirmation_number_rounded,
            "Vehicle No", _customer['vehicleNumber'] ?? ''),
        const SizedBox(height: 10),
        _infoRow(Icons.palette_outlined,
            "Color", _customer['vehicleColor'] ?? ''),
        const SizedBox(height: 10),
        _infoRow(Icons.location_on_outlined,
            "Address", _customer['address'] ?? ''),
        const SizedBox(height: 10),
        _infoRow(Icons.phone_outlined,
            "Phone", _customer['phone']?.isEmpty == true
                ? 'Not provided' : (_customer['phone'] ?? 'Not provided')),
        const SizedBox(height: 14),
        const Divider(color: _border),
        const SizedBox(height: 12),
        _buildLocationRow(),
      ]),
    );
  }

  Widget _buildLocationRow() {
    final loc     = _customer['location'];
    final hasLoc  = loc != null && loc['lat'] != null;

    return Row(children: [
      Icon(
        hasLoc ? Icons.location_on_rounded : Icons.location_off_outlined,
        color: hasLoc ? _success : _textMuted, size: 16,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          hasLoc
              ? "Location set ✓"
              : "No location — distance allowance disabled",
          style: TextStyle(
              color: hasLoc ? _success : _textMuted,
              fontSize: 13,
              fontWeight: hasLoc ? FontWeight.w600 : FontWeight.normal),
        ),
      ),
      if (hasLoc)
        GestureDetector(
          onTap: () async {
            final lat = loc['lat'];
            final lng = loc['lng'];
            final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              await launchUrl(
                Uri.parse('https://maps.google.com/?q=$lat,$lng'),
                mode: LaunchMode.externalApplication,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(7),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: _skyLight, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.map_rounded, color: _skyBlue, size: 16),
          ),
        ),
      GestureDetector(
        onTap: _showLocationDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: _skyLight,
              borderRadius: BorderRadius.circular(8)),
          child: Text(hasLoc ? "Edit" : "Set",
              style: const TextStyle(color: _skyBlue,
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  Future<String> _resolveUrl(String url) async {
    if (!url.contains('goo.gl') && !url.contains('maps.app')) return url;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 10) Chrome/91.0'},
      ).timeout(const Duration(seconds: 8));
      return response.request?.url.toString() ?? url;
    } catch (e) {
      return url;
    }
  }

  Future<void> _showLocationDialog() async {
    final ctrl = TextEditingController(
        text: _customer['mapsLink'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        title: const Text("Customer Location",
            style: TextStyle(color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Paste a Google Maps link for this customer's address.",
              style: TextStyle(color: Color(0xFF64748B),
                  fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Color(0xFFF4F8FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFDDE8F5)),
              ),
              child: TextField(
                controller: ctrl,
                maxLines: 3,
                style: const TextStyle(
                    color: Color(0xFF0F172A), fontSize: 12),
                decoration: const InputDecoration(
                  hintText: "https://maps.app.goo.gl/... or full URL",
                  hintStyle: TextStyle(color: Color(0xFF64748B)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel",
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _skyBlue),
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _loading = true);
              // Expand short URL on device before sending to backend
              final rawLink  = ctrl.text.trim();
              final fullLink = await _resolveUrl(rawLink);
              final result = await AdminApiService.updateCustomer(
                _customer['_id'].toString(),
                {'mapsLink': fullLink},
              );
              if (result != null && mounted) {
                setState(() {
                  _customer = Map<String, dynamic>.from(result);
                  _loading  = false;
                });
                final extracted = result['location']?['lat'] != null;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(extracted
                      ? "Location saved ✓"
                      : "Could not extract coordinates. Try the full Maps URL."),
                  backgroundColor: extracted
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF59E0B),
                ));
              } else {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: const Text("Save",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadCarPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await AdminApiService.uploadCustomerPhoto(
        _customer['_id'].toString(),
        File(picked.path),
      );
      if (url != null && mounted) {
        setState(() {
          _customer = Map<String, dynamic>.from(_customer)
            ..['carPhoto'] = url;
          _uploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Car photo updated ✓")));
      } else {
        if (mounted) setState(() => _uploadingPhoto = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Upload failed: $e")));
      }
    }
  }

  Widget _buildCarPhotoCard() {
    final photoUrl = _customer['carPhoto'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _skyLight, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.photo_camera_rounded,
                color: _skyBlue, size: 18),
          ),
          const SizedBox(width: 10),
          const Text("Car Photo",
              style: TextStyle(color: _textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: _uploadingPhoto ? null : _uploadCarPhoto,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: _skyLight, borderRadius: BorderRadius.circular(10)),
              child: _uploadingPhoto
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _skyBlue))
                  : Text(photoUrl != null ? "Replace" : "Upload",
                      style: const TextStyle(color: _skyBlue,
                          fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (photoUrl != null)
          Stack(children: [
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.black,
                  insetPadding: EdgeInsets.zero,
                  child: Stack(children: [
                    InteractiveViewer(
                      child: Image.network(photoUrl,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity),
                    ),
                    Positioned(top: 40, right: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(photoUrl,
                    width: double.infinity, height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      decoration: BoxDecoration(
                          color: _skyLight,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Center(child: Icon(Icons.broken_image_rounded,
                          color: _textMuted, size: 36)),
                    )),
              ),
            ),
            // Replace button overlay
            Positioned(
              bottom: 10, right: 10,
              child: GestureDetector(
                onTap: _uploadingPhoto ? null : _uploadCarPhoto,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text("Replace",
                        style: TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
            if (_uploadingPhoto)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    child: const Center(child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
                  ),
                ),
              ),
          ])
        else
          GestureDetector(
            onTap: _uploadingPhoto ? null : _uploadCarPhoto,
            child: Container(
              width: double.infinity, height: 120,
              decoration: BoxDecoration(
                color: _skyLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _skyBlue.withOpacity(0.3),
                    style: BorderStyle.solid),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_rounded,
                        color: _skyBlue.withOpacity(0.6), size: 36),
                    const SizedBox(height: 8),
                    const Text("Tap to upload car photo",
                        style: TextStyle(color: _textMuted, fontSize: 12)),
                  ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildStatsCard(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _skyBlue.withOpacity(0.3),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        const Icon(Icons.local_car_wash_rounded,
            color: Colors.white, size: 32),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Total Services",
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text("$count wash${count == 1 ? '' : 'es'} completed",
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        const Spacer(),
        // Count badge — tap to edit
        GestureDetector(
          onTap: () => _editServiceCount(count),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text("#$count",
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded,
                  color: Colors.white70, size: 14),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _editServiceCount(int current) async {
    final ctrl = TextEditingController(text: current.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text("Correct Service Count",
            style: TextStyle(color: _textPrimary,
                fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            "Manually set the total number of completed services for this customer.",
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "Service Count",
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.tag_rounded),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel",
                style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _skyBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Save",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newCount = int.tryParse(ctrl.text.trim());
    if (newCount == null || newCount < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid number")));
      return;
    }
    if (newCount == current) return; // no change

    setState(() => _loading = true);
    final result = await AdminApiService.updateCustomer(
      _customer['_id'].toString(),
      {'serviceCount': newCount},
    );
    if (result != null && mounted) {
      setState(() {
        _customer = Map<String, dynamic>.from(result);
        _loading  = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Service count updated ✓")));
    } else {
      if (mounted) setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Update failed. Try again.")));
    }
  }

  Widget _buildCustomPricingCard() {
    final cp        = _customer['customPricing'] as Map?;
    final enabled   = cp?['enabled'] == true;
    final carType   = (_customer['carType'] ?? 'Hatchback').toString();
    final intType   = (_customer['interiorType'] ?? 'None').toString();
    final hasInt    = intType != 'None';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: enabled
                ? _skyBlue.withOpacity(0.4) : _border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.price_change_rounded,
              color: _skyBlue, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text("Invoice Pricing",
              style: TextStyle(color: _textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w800))),
          if (enabled)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _skyLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text("Custom",
                  style: TextStyle(color: _skyBlue,
                      fontSize: 10, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          enabled
              ? "Using custom rates for this customer"
              : "Using global invoice pricing",
          style: const TextStyle(color: _textMuted, fontSize: 11)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => CustomerPricingScreen(
                customer: _customer,
              ),
            ));
            _refresh();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: enabled ? _skyLight : const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _skyBlue.withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(enabled
                  ? Icons.edit_rounded : Icons.tune_rounded,
                  color: _skyBlue, size: 16),
              const SizedBox(width: 8),
              Text(enabled ? "Edit Custom Pricing" : "Set Custom Pricing",
                  style: const TextStyle(color: _skyBlue,
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildHistoryButton() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CustomerHistoryScreen(customer: _customer),
      )).then((_) => _refresh()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _skyBlue.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, color: _skyBlue, size: 22),
            SizedBox(width: 10),
            Text("View Service History",
                style: TextStyle(color: _skyBlue,
                    fontWeight: FontWeight.w800, fontSize: 15)),
            SizedBox(width: 10),
            Icon(Icons.arrow_forward_ios_rounded,
                color: _skyBlue, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: _skyBlue, size: 16),
      const SizedBox(width: 8),
      Text("$label: ", style: const TextStyle(
          color: _textMuted, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(
          color: _textPrimary, fontWeight: FontWeight.w600,
          fontSize: 13))),
    ]);
  }
}