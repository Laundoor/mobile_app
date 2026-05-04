import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onShared;
  const InvoicePreviewScreen({
    Key? key, required this.invoice, required this.onShared,
  }) : super(key: key);
  @override State<InvoicePreviewScreen> createState() =>
      _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _sharing = false;
  Uint8List? _qrBytes;

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    final qrUrl = widget.invoice['paymentContact']?['qrImageUrl'] as String?;
    if (qrUrl == null || qrUrl.isEmpty) return;
    try {
      final res = await http.get(Uri.parse(qrUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && mounted) {
        setState(() => _qrBytes = res.bodyBytes);
      }
    } catch (_) {}
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // Capture invoice widget as image
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception("Could not capture invoice");

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(
          format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Could not encode image");

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final file  = File(
          '${dir.path}/invoice_${widget.invoice['invoiceNumber']}.png');
      await file.writeAsBytes(bytes);

      final contactName = (widget.invoice['paymentContact']?['name'] ?? '').toString();
      final contactNum  = (widget.invoice['paymentContact']?['number'] ?? '').toString();
      final shareText   = contactName.isNotEmpty && contactNum.isNotEmpty
          ? 'Pay to $contactName · $contactNum'
          : contactNum.isNotEmpty
              ? 'Pay to $contactNum'
              : widget.invoice['invoiceNumber'] ?? '';

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: shareText,
      );

      // Mark shared
      final invoiceId = widget.invoice['_id']?.toString();
      if (invoiceId != null) {
        await AdminApiService.markInvoiceShared(invoiceId);
      }
      widget.onShared();

      // Cleanup
      Future.delayed(const Duration(minutes: 2), () {
        if (file.existsSync()) file.deleteSync();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Share failed: $e")));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: Text(widget.invoice['invoiceNumber'] ?? 'Invoice',
            style: const TextStyle(color: AdminTheme.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w800)),
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
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: RepaintBoundary(
              key: _repaintKey,
              child: _buildInvoice(),
            ),
          ),
        ),
        // Share button
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          color: AdminTheme.white,
          child: GestureDetector(
            onTap: _sharing ? null : _share,
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
              child: Center(child: _sharing
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text("Share Invoice",
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ])),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInvoice() {
    final inv          = widget.invoice;
    final month        = inv['month'] as int? ?? 1;
    final year         = inv['year']  as int? ?? 2026;
    final lineItems    = (inv['lineItems'] as List?) ?? [];
    final grandTotal   = (inv['grandTotal'] as num?)?.toInt() ?? 0;
    final contact      = inv['paymentContact'] as Map? ?? {};
    final contactName  = contact['name']   as String? ?? '';
    final contactNum   = contact['number'] as String? ?? '';

    // Split stats
    final extAttempted = inv['extAttempted'] as int? ?? 0;
    final extCleaned   = inv['extCleaned']   as int? ?? 0;
    final extCancelled = inv['extCancelled'] as int? ?? 0;
    final intAttempted = inv['intAttempted'] as int? ?? 0;
    final intCleaned   = inv['intCleaned']   as int? ?? 0;
    final intCancelled = inv['intCancelled'] as int? ?? 0;
    final hasInterior  = intAttempted > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF38B6FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("LAUNDOOR",
                    style: TextStyle(color: Colors.white,
                        fontSize: 22, fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                const SizedBox(height: 4),
                Text("Car Wash Services",
                    style: TextStyle(color: Colors.white.withOpacity(0.8),
                        fontSize: 11)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text("INVOICE",
                    style: TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(inv['invoiceNumber'] ?? '',
                    style: TextStyle(color: Colors.white.withOpacity(0.9),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text("${_months[month - 1]} $year",
                    style: TextStyle(color: Colors.white.withOpacity(0.8),
                        fontSize: 11)),
              ]),
            ],
          ),
        ),

        // ── Customer details ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label("BILLED TO"),
            const SizedBox(height: 6),
            Text(inv['customerName'] ?? '',
                style: const TextStyle(color: Color(0xFF0F172A),
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              "${inv['vehicleNumber'] ?? ''} · ${inv['carModel'] ?? ''} · ${inv['carType'] ?? ''}",
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            if ((inv['customerPhone'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(inv['customerPhone'].toString(),
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontSize: 12)),
            ],
          ]),
        ),

        _divider(),

        // ── Charges — moved above service summary ────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(children: [
            _label("CHARGES"),
            const SizedBox(height: 8),
            ...lineItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (item['label'] as String? ?? '')
                          .contains('Interior')
                      ? const Color(0xFFF3E5F5)
                      : const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE8F5)),
                ),
                child: Row(children: [
                  Expanded(child: Text(item['label'] ?? '',
                      style: const TextStyle(color: Color(0xFF0F172A),
                          fontSize: 14, fontWeight: FontWeight.w600))),
                  Text("₹${(item['amount'] as num?)?.toInt() ?? 0}",
                      style: const TextStyle(color: Color(0xFF0F172A),
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ]),
              ),
            )),
          ]),
        ),

        // ── Total ────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF283593)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Text("Total Amount",
                style: TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text("₹$grandTotal",
                style: const TextStyle(color: Colors.white,
                    fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
        ),

        _divider(),

        // ── Service Summary — moved below charges ────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label("SERVICE SUMMARY"),
            const SizedBox(height: 10),

            // Exterior row
            _serviceStatsRow(
              label: "Exterior",
              icon: "🚗",
              attempted: extAttempted,
              cleaned: extCleaned,
              cancelled: extCancelled,
              color: const Color(0xFF1565C0),
              bg: const Color(0xFFEFF6FF),
            ),

            // Interior row
            if (hasInterior) ...[
              const SizedBox(height: 12),
              _serviceStatsRow(
                label: lineItems.any((i) =>
                    i['label'] == 'Interior Premium')
                    ? "Interior Premium"
                    : "Interior Standard",
                icon: "🪑",
                attempted: intAttempted,
                cleaned: intCleaned,
                cancelled: intCancelled,
                color: const Color(0xFF6A1B9A),
                bg: const Color(0xFFF3E5F5),
              ),
            ],
          ]),
        ),

        // ── Payment ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label("PAY TO"),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(contactName,
                    style: const TextStyle(color: Color(0xFF0F172A),
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(contactNum,
                    style: const TextStyle(color: Color(0xFF38B6FF),
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ])),
              if (_qrBytes != null)
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDE8F5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.memory(_qrBytes!, fit: BoxFit.cover),
                  ),
                ),
            ]),
          ]),
        ),

        // ── Footer ───────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFFF4F8FF),
            borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20)),
          ),
          child: const Text("Thank you for your business! 🚗✨",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B),
                  fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _serviceStatsRow({
    required String label,
    required String icon,
    required int attempted,
    required int cleaned,
    required int cancelled,
    required Color color,
    required Color bg,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Label with colour bar
      Row(children: [
        Container(width: 4, height: 14, decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text("$icon $label",
            style: TextStyle(color: color, fontSize: 11,
                fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      ]),
      const SizedBox(height: 8),
      // Stats
      Row(children: [
        _statBox("Attempted", "$attempted", const Color(0xFF64748B),
            const Color(0xFFF1F5F9)),
        const SizedBox(width: 6),
        _statBox("Cleaned",   "$cleaned",   const Color(0xFF22C55E),
            const Color(0xFFECFDF5)),
        const SizedBox(width: 6),
        _statBox("Cancelled", "$cancelled",  Colors.red,
            const Color(0xFFFEF2F2)),
      ]),
    ]);
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Color(0xFF94A3B8),
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2));

  Widget _divider({double top = 0}) => Container(
      margin: EdgeInsets.only(top: top),
      height: 1, color: const Color(0xFFDDE8F5));

  Widget _statBox(String label, String val, Color color, Color bg) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(val, style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            color: Color(0xFF64748B), fontSize: 10)),
      ]),
    ),
  );
}