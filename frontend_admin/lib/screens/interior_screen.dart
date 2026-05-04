import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'customer_history_screen.dart';

// ── Shared search field ───────────────────────────────────────────────────────
Widget _buildSearchField(TextEditingController ctrl, String current,
    VoidCallback onClear) {
  return TextField(
    controller: ctrl,
    style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      hintText: "Search by name or vehicle...",
      hintStyle: const TextStyle(color: AdminTheme.textMuted, fontSize: 13),
      prefixIcon: const Icon(Icons.search_rounded,
          color: AdminTheme.textMuted, size: 18),
      suffixIcon: current.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: AdminTheme.textMuted, size: 18),
              onPressed: onClear)
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
  );
}

// ── InteriorScreen ────────────────────────────────────────────────────────────
class InteriorScreen extends StatefulWidget {
  const InteriorScreen({Key? key}) : super(key: key);
  @override State<InteriorScreen> createState() => _InteriorScreenState();
}

class _InteriorScreenState extends State<InteriorScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  late int _month;
  late int _year;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  void initState() {
    super.initState();
    _tab  = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _month = now.month;
    _year  = now.year;
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _prevMonth() {
    setState(() {
      if (_month == 1) { _month = 12; _year--; }
      else _month--;
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year > now.year || (_year == now.year && _month >= now.month)) return;
    setState(() {
      if (_month == 12) { _month = 1; _year++; }
      else _month++;
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month == now.month && _year == now.year;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Interior Checklist",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(97),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                  color: AdminTheme.white,
                  border: Border(
                      bottom: BorderSide(color: AdminTheme.border))),
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
                Text("${_months[_month - 1]} $_year",
                    style: const TextStyle(
                        color: AdminTheme.textPrimary,
                        fontSize: 15, fontWeight: FontWeight.w800)),
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
            TabBar(
              controller: _tab,
              labelColor: AdminTheme.skyBlue,
              unselectedLabelColor: AdminTheme.textMuted,
              indicatorColor: AdminTheme.skyBlue,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(text: "To-Do"),
                Tab(text: "History"),
              ],
            ),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _TodoTab(month: _month, year: _year),
          _HistoryTab(month: _month, year: _year),
        ],
      ),
    );
  }
}

// ── To-Do Tab ─────────────────────────────────────────────────────────────────
class _TodoTab extends StatefulWidget {
  final int month, year;
  const _TodoTab({required this.month, required this.year});
  @override State<_TodoTab> createState() => _TodoTabState();
}

class _TodoTabState extends State<_TodoTab> {
  List<dynamic> _all  = [];
  String _filter      = 'done_last_month';
  bool   _loading     = true;
  final  _searchCtrl  = TextEditingController();
  String _search      = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() =>
        setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  void didUpdateWidget(_TodoTab old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month || old.year != widget.year) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getInteriorTodo(
        month: widget.month, year: widget.year);
    if (mounted) setState(() {
      _all     = (data?['customers'] as List?) ?? [];
      _loading = false;
    });
  }

  List<dynamic> _forFilter(String f) {
    switch (f) {
      case 'done_last_month':
        return _all.where((c) => c['doneLastMonth'] == true).toList();
      case 'not_done':
        return _all.where((c) =>
            c['doneLastMonth'] == false && c['isNew'] == false).toList();
      case 'new':
        return _all.where((c) => c['isNew'] == true).toList();
      default: return _all;
    }
  }

  List<dynamic> get _filtered {
    var list = _forFilter(_filter);
    if (_search.isNotEmpty) {
      list = list.where((c) {
        final name = (c['customerName'] ?? '').toString().toLowerCase();
        final veh  = (c['vehicleNumber'] ?? '').toString().toLowerCase();
        return name.contains(_search) || veh.contains(_search);
      }).toList();
    }
    return list;
  }

  Widget _filterChip(String value, String label, int count) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AdminTheme.skyBlue : AdminTheme.skyLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? AdminTheme.skyBlue
                  : AdminTheme.skyBlue.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
              color: active ? Colors.white : AdminTheme.skyBlue,
              fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: active
                    ? Colors.white.withOpacity(0.25) : AdminTheme.white,
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(
                color: active ? Colors.white : AdminTheme.skyBlue,
                fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  Widget _empty() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.cleaning_services_rounded,
          color: AdminTheme.border, size: 48),
      const SizedBox(height: 12),
      Text(
        _search.isNotEmpty
            ? 'No results for "$_search"'
            : _filter == 'done_last_month'
                ? "All customers done last month\nare complete this month"
                : _filter == 'not_done'
                    ? "No customers skipped last month"
                    : "No new customers this month",
        textAlign: TextAlign.center,
        style: const TextStyle(color: AdminTheme.textMuted, fontSize: 14),
      ),
    ],
  ));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildSearchField(_searchCtrl, _search,
            () { _searchCtrl.clear(); setState(() => _search = ''); }),
      ),
      Container(
        height: 48,
        color: AdminTheme.white,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _filterChip('done_last_month', 'Done Last Month',
                _forFilter('done_last_month').length),
            const SizedBox(width: 8),
            _filterChip('not_done', 'Not Done Last Month',
                _forFilter('not_done').length),
            const SizedBox(width: 8),
            _filterChip('new', 'New Customers',
                _forFilter('new').length),
          ],
        ),
      ),
      const Divider(height: 1, color: AdminTheme.border),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AdminTheme.skyBlue))
            : _filtered.isEmpty
                ? _empty()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AdminTheme.skyBlue,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) =>
                          _CustomerCard(customer: _filtered[i]),
                    ),
                  ),
      ),
    ]);
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────
class _HistoryTab extends StatefulWidget {
  final int month, year;
  const _HistoryTab({required this.month, required this.year});
  @override State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<dynamic> _jobs   = [];
  bool          _loading = true;
  final _searchCtrl      = TextEditingController();
  String _search         = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() =>
        setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  void didUpdateWidget(_HistoryTab old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month || old.year != widget.year) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getInteriorHistory(
        month: widget.month, year: widget.year);
    if (mounted) setState(() {
      _jobs    = (data?['jobs'] as List?) ?? [];
      _loading = false;
    });
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _jobs;
    return _jobs.where((j) {
      final name = (j['customerName'] ?? '').toString().toLowerCase();
      final veh  = (j['vehicleNumber'] ?? '').toString().toLowerCase();
      return name.contains(_search) || veh.contains(_search);
    }).toList();
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h12  = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      final min  = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${m[dt.month-1]} · $h12:$min $ampm';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
          color: AdminTheme.skyBlue));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildSearchField(_searchCtrl, _search,
            () { _searchCtrl.clear(); setState(() => _search = ''); }),
      ),
      if (_jobs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: AdminTheme.skyLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AdminTheme.skyBlue.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cleaning_services_rounded,
                    color: AdminTheme.skyBlue, size: 13),
                const SizedBox(width: 5),
                Text(
                  "${_filtered.length} interior"
                  "${_search.isNotEmpty ? ' found' : ' this month'}",
                  style: const TextStyle(
                      color: AdminTheme.skyBlue,
                      fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 8),
      const Divider(height: 1, color: AdminTheme.border),
      Expanded(
        child: _filtered.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.history_rounded,
                    color: AdminTheme.border, size: 48),
                const SizedBox(height: 12),
                Text(
                  _search.isNotEmpty
                      ? 'No results for "$_search"'
                      : "No interior jobs completed this month",
                  style: const TextStyle(color: AdminTheme.textMuted)),
              ]))
            : RefreshIndicator(
                onRefresh: _load,
                color: AdminTheme.skyBlue,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) =>
                      _HistoryCard(job: _filtered[i], fmtDate: _fmtDate),
                ),
              ),
      ),
    ]);
  }
}

// ── Customer Card (To-Do) ─────────────────────────────────────────────────────
class _CustomerCard extends StatelessWidget {
  final Map customer;
  const _CustomerCard({required this.customer});

  String _fmtDate(String? iso) {
    if (iso == null) return 'Not done last month';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${m[dt.month-1]} ${dt.year}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final type      = customer['interiorType'] as String? ?? '';
    final isPrem    = type.contains('Premium');
    final typeColor = isPrem
        ? const Color(0xFF6A1B9A) : const Color(0xFF1565C0);
    final typeBg    = isPrem
        ? const Color(0xFFF3E5F5) : const Color(0xFFE3F2FD);
    final isNew     = customer['isNew'] == true;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CustomerHistoryScreen(
          customer: Map<String, dynamic>.from(customer as Map),
        ),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: typeBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(
              (customer['customerName'] as String? ?? '?')[0].toUpperCase(),
              style: TextStyle(color: typeColor,
                  fontSize: 18, fontWeight: FontWeight.w900),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(
                  customer['customerName'] ?? '',
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                )),
                if (isNew)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AdminTheme.successLight,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text("New",
                        style: TextStyle(color: AdminTheme.success,
                            fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(
                "${customer['carModel'] ?? ''} · "
                "${customer['vehicleNumber'] ?? ''}",
                style: const TextStyle(
                    color: AdminTheme.textMuted, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                "Last done: ${_fmtDate(customer['lastDoneDate'])}",
                style: const TextStyle(
                    color: AdminTheme.textMuted, fontSize: 10),
              ),
            ],
          )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: typeBg, borderRadius: BorderRadius.circular(8)),
            child: Text(
              isPrem ? 'Premium' : 'Standard',
              style: TextStyle(color: typeColor,
                  fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── History Card ──────────────────────────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final Map job;
  final String Function(String?) fmtDate;
  const _HistoryCard({required this.job, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final type      = job['interiorType'] as String? ?? '';
    final isPrem    = type.contains('Premium');
    final typeColor = isPrem
        ? const Color(0xFF6A1B9A) : const Color(0xFF1565C0);
    final typeBg    = isPrem
        ? const Color(0xFFF3E5F5) : const Color(0xFFE3F2FD);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CustomerHistoryScreen(
          customer: {
            '_id':           job['customerId'],
            'customerName':  job['customerName']  ?? '',
            'vehicleNumber': job['vehicleNumber'] ?? '',
            'carModel':      job['carModel']      ?? '',
            'carType':       job['carType']       ?? '',
          },
        ),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: typeBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(
              (job['customerName'] as String? ?? '?')[0].toUpperCase(),
              style: TextStyle(color: typeColor,
                  fontSize: 18, fontWeight: FontWeight.w900),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job['customerName'] ?? '',
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                "${job['carModel'] ?? ''} · ${job['vehicleNumber'] ?? ''}",
                style: const TextStyle(
                    color: AdminTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.person_outline_rounded,
                    color: AdminTheme.textMuted, size: 11),
                const SizedBox(width: 4),
                Text(job['employeeName'] ?? '',
                    style: const TextStyle(
                        color: AdminTheme.textMuted, fontSize: 10)),
                const SizedBox(width: 10),
                const Icon(Icons.schedule_rounded,
                    color: AdminTheme.textMuted, size: 11),
                const SizedBox(width: 4),
                Text(fmtDate(job['completedAt']),
                    style: const TextStyle(
                        color: AdminTheme.textMuted, fontSize: 10)),
              ]),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: typeBg, borderRadius: BorderRadius.circular(8)),
            child: Text(
              isPrem ? 'Premium' : 'Standard',
              style: TextStyle(color: typeColor,
                  fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ),
    );
  }
}