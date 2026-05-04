import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'invoice_preview_screen.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({Key? key}) : super(key: key);
  @override State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  List<dynamic> _customers = [];
  Map<String, dynamic>? _metrics;
  bool   _loading = true;
  late int _month;
  late int _year;

  // Filter + search
  String _filter = 'All'; // All, Shared, Not Shared, Collected, Awaiting Payment
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _filters = [
    'All', 'Shared', 'Not Shared', 'Collected', 'Awaiting Payment'
  ];

  static const _monthNames = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year  = now.year;
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) { _month = 12; _year--; }
      else _month--;
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year > now.year || (_year == now.year && _month >= now.month)) return;
    setState(() {
      if (_month == 12) { _month = 1; _year++; }
      else _month++;
    });
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month == now.month && _year == now.year;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AdminApiService.getInvoiceList(month: _month, year: _year),
      AdminApiService.getInvoiceMetrics(month: _month, year: _year),
    ]);
    if (mounted) setState(() {
      _customers = (results[0]?['customers'] as List?) ?? [];
      _metrics   = results[1];
      _loading   = false;
    });
  }

  List<dynamic> get _filtered {
    var list = _customers.where((c) {
      // Search
      if (_search.isNotEmpty) {
        final name    = (c['customerName'] ?? '').toString().toLowerCase();
        final vehicle = (c['vehicleNumber'] ?? '').toString().toLowerCase();
        if (!name.contains(_search) && !vehicle.contains(_search)) return false;
      }
      // Filter
      final shared    = c['shared']            == true;
      final collected = c['paymentCollected']  == true;
      switch (_filter) {
        case 'Shared':           return shared;
        case 'Not Shared':       return !shared;
        case 'Collected':        return collected;
        case 'Awaiting Payment': return shared && !collected;
        default:                 return true;
      }
    }).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Invoices",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AdminTheme.skyBlue),
              onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AdminTheme.white,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: AdminTheme.skyBlue),
                  onPressed: _prevMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text("${_monthNames[_month - 1]} $_year",
                    style: const TextStyle(color: AdminTheme.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                IconButton(
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _isCurrentMonth
                          ? AdminTheme.border : AdminTheme.skyBlue),
                  onPressed: _isCurrentMonth ? null : _nextMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Container(height: 1, color: AdminTheme.border),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminTheme.skyBlue))
          : Column(children: [
              // Metrics strip
              if (_metrics != null) _buildMetrics(),
              // Search
              _buildSearch(),
              // Filter chips
              _buildFilterChips(),
              Container(height: 1, color: AdminTheme.border),
              // List
              Expanded(
                child: _filtered.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AdminTheme.skyBlue,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _CustomerInvoiceCard(
                            data:    _filtered[i],
                            month:   _month,
                            year:    _year,
                            onDone:  _load,
                          ),
                        ),
                      ),
              ),
            ]),
    );
  }

  Widget _buildMetrics() {
    final revenue   = (_metrics!['totalRevenue']   as num?)?.toInt() ?? 0;
    final collected = (_metrics!['totalCollected'] as num?)?.toInt() ?? 0;
    final pending   = (_metrics!['totalPending']   as num?)?.toInt() ?? 0;
    final byContact = (_metrics!['byContact'] as List?) ?? [];

    return Container(
      color: AdminTheme.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        // Row 1: Revenue / Collected / Pending
        Row(children: [
          _metricBox("Revenue",   "₹$revenue",   AdminTheme.skyBlue,   AdminTheme.skyLight),
          const SizedBox(width: 8),
          _metricBox("Collected", "₹$collected", AdminTheme.success,   AdminTheme.successLight),
          const SizedBox(width: 8),
          _metricBox("Pending",   "₹$pending",   AdminTheme.warning,   const Color(0xFFFFFBEB)),
        ]),
        if (byContact.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Row 2: Per contact
          Row(children: byContact.asMap().entries.map((e) {
            final i    = e.key;
            final c    = e.value as Map;
            final name = c['name'] ?? '';
            final inv  = (c['invoiced']  as num?)?.toInt() ?? 0;
            final col  = (c['collected'] as num?)?.toInt() ?? 0;
            return Expanded(child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: AdminTheme.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminTheme.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name, style: const TextStyle(
                    color: AdminTheme.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text("₹$col / ₹$inv",
                    style: const TextStyle(
                        color: AdminTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 3),
                const Text("collected / invoiced",
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 9)),
              ]),
            ));
          }).toList()),
        ],
      ]),
    );
  }

  Widget _metricBox(String label, String val, Color c, Color bg) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withOpacity(0.2))),
        child: Column(children: [
          Text(val, style: TextStyle(
              color: c, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              color: AdminTheme.textMuted, fontSize: 10)),
        ]),
      ));

  Widget _buildSearch() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: TextField(
      controller: _searchCtrl,
      style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: "Search by name or vehicle...",
        hintStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded,
            color: AdminTheme.textMuted, size: 18),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AdminTheme.textMuted, size: 18),
                onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
            : null,
        filled: true, fillColor: AdminTheme.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTheme.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTheme.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: AdminTheme.skyBlue, width: 1.5)),
      ),
    ),
  );

  Widget _buildFilterChips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Row(children: _filters.map((f) {
      final active = _filter == f;
      // Count for this filter
      int count;
      switch (f) {
        case 'Shared':
          count = _customers.where((c) => c['shared'] == true).length; break;
        case 'Not Shared':
          count = _customers.where((c) => c['shared'] != true).length; break;
        case 'Collected':
          count = _customers.where((c) => c['paymentCollected'] == true).length; break;
        case 'Awaiting Payment':
          count = _customers.where((c) =>
              c['shared'] == true && c['paymentCollected'] != true).length; break;
        default:
          count = _customers.length;
      }
      return GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AdminTheme.skyBlue : AdminTheme.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? AdminTheme.skyBlue : AdminTheme.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(f, style: TextStyle(
                color: active ? Colors.white : AdminTheme.textMuted,
                fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withOpacity(0.25)
                      : AdminTheme.skyLight,
                  borderRadius: BorderRadius.circular(10)),
              child: Text("$count", style: TextStyle(
                  color: active ? Colors.white : AdminTheme.skyBlue,
                  fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
    }).toList()),
  );

  Widget _buildEmpty() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.receipt_long_rounded,
          color: AdminTheme.border, size: 48),
      const SizedBox(height: 12),
      Text("No results for ${_monthNames[_month-1]} $_year",
          style: const TextStyle(color: AdminTheme.textMuted)),
    ],
  ));
}

// ── Customer Invoice Card ─────────────────────────────────────────────────────
class _CustomerInvoiceCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final int month, year;
  final VoidCallback onDone;
  const _CustomerInvoiceCard({
    required this.data, required this.month,
    required this.year, required this.onDone,
  });
  @override State<_CustomerInvoiceCard> createState() =>
      _CustomerInvoiceCardState();
}

class _CustomerInvoiceCardState extends State<_CustomerInvoiceCard> {
  bool _generating = false;

  Map<String, dynamic> get _data => widget.data;

  Future<void> _tap() async {
    if (!_data['hasPaymentContact']) return;

    setState(() => _generating = true);

    // Step 1 — fetch fresh computed total from server (always accurate)
    final computed = await AdminApiService.computeInvoice(
        _data['customerId'].toString(),
        month: widget.month, year: widget.year);
    if (!mounted) return;
    setState(() => _generating = false);

    if (computed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load pricing. Try again.")));
      return;
    }

    final freshTotal  = (computed['computedTotal'] as num?)?.toDouble() ?? 0;
    final hasExterior = (computed['lineItems'] as List? ?? [])
        .any((i) => ['Hatchback','Sedan','SUV'].contains(i['label']));

    // Step 2 — show adjustment sheet with fresh total as base
    double adjustment = 0;
    if (hasExterior) {
      final result = await showModalBottomSheet<double?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdjustmentSheet(
          currentTotal: freshTotal,
          existingAdj:  0, // always start fresh — no stale adjustments
        ),
      );
      if (!mounted) return;
      if (result == null) return; // dismissed — cancel
      adjustment = result == double.negativeInfinity ? 0 : result;
    }

    // Step 3 — generate invoice with the chosen adjustment
    setState(() => _generating = true);
    final invoice = await AdminApiService.generateInvoice(
        _data['customerId'].toString(),
        month: widget.month, year: widget.year,
        adjustment: adjustment);
    if (!mounted) return;
    setState(() => _generating = false);

    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to generate invoice.")));
      return;
    }

    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => InvoicePreviewScreen(
        invoice:  invoice,
        onShared: widget.onDone,
      ),
    ));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final data         = _data;
    final hasPayment   = data['hasPaymentContact'] == true;
    final shared       = data['shared']            == true;
    final collected    = data['paymentCollected']  == true;
    final invoiceId    = data['invoiceId']?.toString();
    final invoiceNumber= data['invoiceNumber'] as String?;
    final grandTotal   = (data['displayTotal'] as num?)?.toInt()
        ?? (data['grandTotal'] as num?)?.toInt() ?? 0;
    final attempted    = data['attempted']   as int? ?? 0;
    final cleaned      = data['cleaned']     as int? ?? 0;
    final cancelled    = data['cancelled']   as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: collected
              ? AdminTheme.success.withOpacity(0.4)
              : !hasPayment
                  ? AdminTheme.warning.withOpacity(0.5)
                  : shared
                      ? AdminTheme.skyBlue.withOpacity(0.3)
                      : AdminTheme.border,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Main card — tap to generate/preview
        GestureDetector(
          onTap: _generating ? null : _tap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                      color: AdminTheme.skyLight, shape: BoxShape.circle),
                  child: Center(child: Text(
                    (data['customerName'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AdminTheme.skyBlue,
                        fontSize: 18, fontWeight: FontWeight.w900),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data['customerName'] ?? '',
                      style: const TextStyle(color: AdminTheme.textPrimary,
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  Text("${data['vehicleNumber'] ?? ''} · ${data['carModel'] ?? ''}",
                      style: const TextStyle(
                          color: AdminTheme.textMuted, fontSize: 11)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _generating
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: AdminTheme.skyBlue, strokeWidth: 2))
                      : Text("₹$grandTotal",
                          style: const TextStyle(
                              color: AdminTheme.textPrimary,
                              fontSize: 17, fontWeight: FontWeight.w900)),
                  if (invoiceNumber != null)
                    Text(invoiceNumber, style: const TextStyle(
                        color: AdminTheme.textMuted, fontSize: 9)),
                ]),
              ]),

              const SizedBox(height: 12),

              // Stats strip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AdminTheme.bg,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                  _stat("Attempted", "$attempted", AdminTheme.textMuted),
                  _divider(),
                  _stat("Cleaned",   "$cleaned",   AdminTheme.success),
                  _divider(),
                  _stat("Cancelled", "$cancelled",  Colors.red),
                ]),
              ),

              const SizedBox(height: 10),

              // Status tag
              if (!hasPayment)
                _tag(Icons.warning_amber_rounded,
                    "Set payment contact to generate invoice",
                    AdminTheme.warning, const Color(0xFFFFFBEB))
              else if (collected)
                _tag(Icons.check_circle_rounded,
                    "Payment collected ✓",
                    AdminTheme.success, AdminTheme.successLight)
              else if (shared)
                _tag(Icons.receipt_rounded,
                    "Invoice shared — awaiting payment",
                    AdminTheme.skyBlue, AdminTheme.skyLight)
              else
                _tag(Icons.touch_app_rounded,
                    "Tap to preview & share invoice",
                    AdminTheme.textMuted, AdminTheme.bg),
            ]),
          ),
        ),

        // Payment collected button — show if shared and not yet collected
        if (hasPayment && shared && !collected && invoiceId != null) ...[
          Container(height: 1, color: AdminTheme.border),
          GestureDetector(
            onTap: () async {
              final ok = await AdminApiService.markInvoiceCollected(invoiceId);
              if (ok) widget.onDone();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AdminTheme.successLight,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                Icon(Icons.payments_rounded,
                    color: AdminTheme.success, size: 16),
                SizedBox(width: 6),
                Text("Mark Payment Collected",
                    style: TextStyle(color: AdminTheme.success,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _stat(String label, String val, Color color) =>
      Column(children: [
    Text(val, style: TextStyle(
        color: color, fontSize: 15, fontWeight: FontWeight.w800)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(
        color: AdminTheme.textMuted, fontSize: 10)),
  ]);

  Widget _divider() => Container(width: 1, height: 28, color: AdminTheme.border);

  Widget _tag(IconData icon, String label, Color c, Color bg) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, color: c, size: 13),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      );
}

// ── Adjustment Bottom Sheet ───────────────────────────────────────────────────
class _AdjustmentSheet extends StatefulWidget {
  final double currentTotal;
  final double existingAdj;
  const _AdjustmentSheet(
      {required this.currentTotal, required this.existingAdj});
  @override State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingAdj != 0) {
      _ctrl.text = widget.existingAdj.toString();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  double get _adj => double.tryParse(_ctrl.text) ?? 0;
  double get _newTotal => widget.currentTotal + _adj;  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text("Amount Adjustment",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text("Added to exterior amount. Use negative to reduce.",
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 20),
        // Current → adjusted preview
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AdminTheme.bg, borderRadius: BorderRadius.circular(12)),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Computed", style: TextStyle(
                  color: AdminTheme.textMuted, fontSize: 11)),
              Text("₹${widget.currentTotal.toInt().toString()}",
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
            const Icon(Icons.arrow_forward_rounded,
                color: AdminTheme.textMuted, size: 18),
            StatefulBuilder(builder: (_, set) => Column(
                crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text("After Adjustment", style: TextStyle(
                  color: AdminTheme.textMuted, fontSize: 11)),
              Text("₹${_newTotal.toInt().toString()}",
                  style: TextStyle(
                      color: _adj == 0
                          ? AdminTheme.textPrimary
                          : _adj > 0
                              ? AdminTheme.success : Colors.red,
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))
          ],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AdminTheme.textPrimary,
              fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: "Adjustment amount (e.g. 2.8 or -1)",
            labelStyle: const TextStyle(
                color: AdminTheme.textMuted, fontSize: 12),
            filled: true, fillColor: AdminTheme.bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AdminTheme.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AdminTheme.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AdminTheme.skyBlue, width: 1.5)),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context, double.negativeInfinity),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: AdminTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminTheme.border)),
              child: const Center(child: Text("No Adjustment",
                  style: TextStyle(color: AdminTheme.textMuted,
                      fontWeight: FontWeight.w600))),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context, _adj),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AdminTheme.skyBlue, Color(0xFF1A90D9)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(
                "Apply ₹${_newTotal.toInt().toString()}",
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700))),
            ),
          )),
        ]),
      ]),
    );
  }
}