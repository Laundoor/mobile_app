import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';
import '../services/job_share_service.dart';
import 'complaint_sheet.dart';

class CustomerHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerHistoryScreen({Key? key, required this.customer})
      : super(key: key);

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  List<dynamic>       _jobs     = [];
  Map<String, dynamic> _summary = {};
  bool   _loading       = true;
  String? _selectedDate;
  String? _sharingJobId;
  late int _month;
  late int _year;

  static const _monthNames = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  static const Color _bg          = Color(0xFFF4F8FF);
  static const Color _white       = Color(0xFFFFFFFF);
  static const Color _skyBlue     = Color(0xFF38B6FF);
  static const Color _skyLight    = Color(0xFFE8F5FF);
  static const Color _skyDark     = Color(0xFF1A90D9);
  static const Color _success     = Color(0xFF22C55E);
  static const Color _successLight= Color(0xFFECFDF5);
  static const Color _warning     = Color(0xFFF59E0B);
  static const Color _warningLight= Color(0xFFFFFBEB);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textMuted   = Color(0xFF64748B);
  static const Color _border      = Color(0xFFDDE8F5);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year  = now.year;
    _load();
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) { _month = 12; _year--; }
      else _month--;
      _selectedDate = null;
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year > now.year || (_year == now.year && _month >= now.month)) return;
    setState(() {
      if (_month == 12) { _month = 1; _year++; }
      else _month++;
      _selectedDate = null;
    });
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month == now.month && _year == now.year;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getCustomerHistory(
        widget.customer['_id'].toString(),
        month: _month, year: _year);
    if (mounted) setState(() {
      _jobs    = data['jobs']    as List;
      _summary = data['summary'] as Map<String, dynamic>? ?? {};
      _loading = false;
    });
  }

  // Group jobs by assignedDate → map of date → list of jobs
  Map<String, List<dynamic>> get _byDate {
    final map = <String, List<dynamic>>{};
    for (final j in _jobs) {
      final d = (j['assignedDate'] as String?) ?? '';
      map.putIfAbsent(d, () => []).add(j);
    }
    // Sort dates descending
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  }

  Future<void> _sharePdf(Map<String, dynamic> job) async {
    final status      = job['status'] ?? '';
    final images      = job['images'] as Map<String, dynamic>?;
    final before      = images?['before'];
    final interiorBef = (images?['interiorBefore'] as List?) ?? [];
    final serviceType = job['serviceType'] ?? '';
    final isInterior  = serviceType == 'Interior Standard' ||
                        serviceType == 'Interior Premium';
    final cancelPhoto = job['cancelPhotoUrl'];
    final jobId       = job['_id'];

    if (status == 'Cancelled') {
      if (cancelPhoto == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("No cancel photo available")));
        return;
      }
    } else {
      // For interior jobs check interiorBefore, for exterior check before
      final hasPhoto = isInterior
          ? interiorBef.isNotEmpty
          : (before != null);
      if (!hasPhoto) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Cannot share — before photo not available")));
        return;
      }
    }

    setState(() => _sharingJobId = jobId);
    try {
      await JobShareService.shareJobPhotos(
          job: job, customer: widget.customer);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Share failed: $e")));
    } finally {
      if (mounted) setState(() => _sharingJobId = null);
    }
  }

  Future<void> _raiseComplaint(Map<String, dynamic> job) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComplaintSheet(
        jobId:        job['_id'].toString(),
        customerName: widget.customer['customerName'] ?? '',
        onDone:       _load,
      ),
    );
  }

  Future<void> _resolveComplaint(Map<String, dynamic> job) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        title: const Text("Resolve Complaint",
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800)),
        content: const Text(
            "Mark this complaint as resolved? Service count and salary will be restored.",
            style: TextStyle(color: _textMuted, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text("Resolve",
                  style: TextStyle(color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await AdminApiService.resolveComplaint(job['_id'].toString());
    if (result != null) _load();
  }

  Color _statusColor(String s) {
    if (s == 'In Progress') return _skyBlue;
    if (s == 'Completed')   return _success;
    if (s == 'Cancelled')   return Colors.red;
    return _warning;
  }

  Color _statusBg(String s) {
    if (s == 'In Progress') return _skyLight;
    if (s == 'Completed')   return _successLight;
    if (s == 'Cancelled')   return const Color(0xFFFEF2F2);
    return _warningLight;
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.customer['customerName'] ?? '',
              style: const TextStyle(color: Color(0xFF0F172A),
                  fontSize: 16, fontWeight: FontWeight.w800)),
          Text(_selectedDate == null
              ? "Service History"
              : "Jobs on ${_formatDate(_selectedDate)}",
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textMuted, size: 18),
          onPressed: () {
            if (_selectedDate != null) {
              setState(() => _selectedDate = null);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.calendar_month_rounded, color: _skyBlue),
              onPressed: () => setState(() => _selectedDate = null),
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: _skyBlue),
              onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            // Month navigator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _white,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: _skyBlue),
                  onPressed: _prevMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text("${_monthNames[_month - 1]} $_year",
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                IconButton(
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _isCurrentMonth ? _border : _skyBlue),
                  onPressed: _isCurrentMonth ? null : _nextMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Container(height: 1, color: _border),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _skyBlue))
          : _jobs.isEmpty
              ? _buildEmpty()
              : _selectedDate == null
                  ? _buildDateList()
                  : _buildJobsForDate(_selectedDate!),
    );
  }

  Widget _summaryChip(String label, String value,
      Color labelColor, Color valueColor) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle(
            color: valueColor, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(
            color: labelColor, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    ));
  }

  // ── DATE LIST VIEW ─────────────────────────────────────────────────────────
  Widget _buildDateList() {
    final grouped = _byDate;
    final total            = _summary['total']            as int? ?? 0;
    final completed        = _summary['completed']        as int? ?? 0;
    final cancelled        = _summary['cancelled']        as int? ?? 0;
    final complaints       = _summary['complaints']       as int? ?? 0;
    final exteriorBillable = _summary['exteriorBillable'] as int? ?? 0;
    final interiorBillable = _summary['interiorBillable'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _load, color: _skyBlue,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Summary strip ───────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              // Row 1: Attempted / Completed / Cancelled / Complaints
              Row(children: [
                _summaryChip("Attempted",  "$total",      Colors.white70, Colors.white),
                const SizedBox(width: 6),
                _summaryChip("Completed",  "$completed",  Colors.white70, Colors.white),
                const SizedBox(width: 6),
                _summaryChip("Cancelled",  "$cancelled",  Colors.white70, Colors.white),
                const SizedBox(width: 6),
                _summaryChip("Complaints", "$complaints", Colors.white70, Colors.white),
              ]),
              const SizedBox(height: 10),
              // Row 2: Exterior Billable / Interior Billable
              Row(children: [
                _summaryChip("Ext. Billable", "$exteriorBillable", Colors.white70, Colors.white),
                const SizedBox(width: 6),
                _summaryChip("Int. Billable", "$interiorBillable", Colors.white70, Colors.white),
                const Spacer(),
                const Spacer(),
              ]),
            ]),
          ),

          // Date cards
          ...grouped.entries.map((entry) {
            final date     = entry.key;
            final dayJobs  = entry.value;
            final completed = dayJobs.where(
                (j) => j['status'] == 'Completed').length;
            final cancelled = dayJobs.where(
                (j) => j['status'] == 'Cancelled').length;
            final hasComplaint = dayJobs.any((j) =>
                j['complaint']?['raised'] == true &&
                j['complaint']?['resolved'] != true);
            final hasInterior = dayJobs.any((j) {
              final st = j['serviceType']?.toString() ?? '';
              return st == 'Interior Standard' || st == 'Interior Premium';
            });

            return GestureDetector(
              onTap: () => setState(() => _selectedDate = date),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasComplaint
                        ? Colors.red.withOpacity(0.4) : _border,
                  ),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(children: [
                  // Date badge
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                        color: _skyLight,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(_dayOfMonth(date),
                          style: const TextStyle(color: _skyDark,
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(_monthAbbr(date),
                          style: const TextStyle(color: _skyBlue,
                              fontSize: 10, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_formatDate(date),
                        style: const TextStyle(color: _textPrimary,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (completed > 0) _badge(
                          "$completed done", _success, _successLight),
                      if (completed > 0) const SizedBox(width: 6),
                      if (cancelled > 0) _badge(
                          "$cancelled cancelled",
                          Colors.red, const Color(0xFFFEF2F2)),
                      if (hasComplaint) ...[
                        const SizedBox(width: 6),
                        _badge("⚠ complaint",
                            Colors.red, const Color(0xFFFEF2F2)),
                      ],
                      if (hasInterior) ...[
                        const SizedBox(width: 6),
                        _badge("Interior",
                            const Color(0xFF009688), const Color(0xFFE0F2F1)),
                      ],
                    ]),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: _textMuted, size: 14),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── JOBS FOR SELECTED DATE ─────────────────────────────────────────────────
  Widget _buildJobsForDate(String date) {
    final dayJobs = _byDate[date] ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dayJobs.length,
      itemBuilder: (_, i) => _buildJobCard(dayJobs[i]),
    );
  }

  Widget _badge(String label, Color color, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _timeChip(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(
          color: _textMuted, fontSize: 10, fontWeight: FontWeight.w500)),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    ],
  );

  String _dayOfMonth(String date) {
    try { return DateTime.parse(date).day.toString(); } catch (_) { return '?'; }
  }

  String _monthAbbr(String date) {
    try {
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return m[DateTime.parse(date).month - 1];
    } catch (_) { return ''; }
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final status       = job['status']       ?? 'Pending';
    final serviceType  = job['serviceType']  ?? '';
    final serviceCount = job['serviceCount'] ?? 0;
    final date         = _formatDate(job['assignedDate']);
    final employee     = job['employeeId'];
    final empName      = employee is Map ? employee['name'] ?? 'Unknown' : 'Unknown';
    final images           = job['images'] as Map<String, dynamic>?;
    final beforeUrl        = images?['before'];
    final afterList        = (images?['after'] as List?) ?? [];
    final interiorBefore   = (images?['interiorBefore'] as List?) ?? [];
    final interiorAfter    = (images?['interiorAfter']  as List?) ?? [];
    final isInterior       = serviceType == 'Interior Standard' ||
                             serviceType == 'Interior Premium';
    final cancelPhoto  = job['cancelPhotoUrl'] as String?;
    final cancelReason = job['cancelReason']   as String?;
    final cancelledAt  = job['cancelledAt']    as String?;
    final jobId        = job['_id'];
    final isGenerating = _sharingJobId == jobId;

    // Share: exterior uses before photo, interior uses first before (Front Left)
    // and 7th after (Boot, index 6)
    final shareUrl = isInterior
        ? (interiorBefore.isNotEmpty
            ? interiorBefore[0]['url'] as String? : null)
        : beforeUrl;
    final canShare = (status == 'Completed' && shareUrl != null) ||
                     (status == 'Cancelled' && cancelPhoto != null);

    // Time tracking
    String? startTimeStr;
    String? endTimeStr;
    int?    minsTaken;
    try {
      final beforeRaw    = job['beforeUploadedAt'];
      final completedRaw = job['completedAt'];
      final cancelledRaw = job['cancelledAt'];
      final start = beforeRaw    != null
          ? DateTime.parse(beforeRaw.toString()).toLocal()    : null;
      final end   = completedRaw != null
          ? DateTime.parse(completedRaw.toString()).toLocal()
          : cancelledRaw != null
              ? DateTime.parse(cancelledRaw.toString()).toLocal() : null;
      String _hm(DateTime dt) {
        final h12  = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
        final ampm = dt.hour < 12 ? 'AM' : 'PM';
        final m    = dt.minute.toString().padLeft(2, '0');
        return '$h12:$m $ampm';
      }
      if (start != null) startTimeStr = _hm(start);
      if (end   != null) endTimeStr   = _hm(end);
      if (start != null && end != null) {
        final diff = end.difference(start).inMinutes;
        if (diff > 0) minsTaken = diff;
      }
    } catch (_) {}

    // Complaint state
    final complaint     = job['complaint'] as Map<String, dynamic>?;
    final hasComplaint  = complaint?['raised']   == true;
    final isResolved    = complaint?['resolved']  == true;
    final canComplain   = status == 'Completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _white, borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasComplaint && !isResolved
              ? Colors.red.withOpacity(0.4)
              : _border,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Complaint banner (unresolved)
        if (hasComplaint && !isResolved)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF2F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              const Icon(Icons.report_problem_rounded,
                  color: Colors.red, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(
                "Complaint: ${complaint?['reason'] ?? ''}",
                style: const TextStyle(color: Colors.red,
                    fontWeight: FontWeight.w700, fontSize: 12),
              )),
            ]),
          ),

        // Resolved banner
        if (hasComplaint && isResolved)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF22C55E), size: 14),
              const SizedBox(width: 6),
              Text(
                "Complaint resolved · ${complaint?['reason'] ?? ''}",
                style: const TextStyle(color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ]),
          ),

        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _statusBg(status),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.local_car_wash_rounded,
                  color: _statusColor(status), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(serviceType, style: const TextStyle(
                      color: _textPrimary, fontWeight: FontWeight.w800,
                      fontSize: 14)),
                  const SizedBox(width: 8),
                  if (serviceCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _skyLight,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text("#$serviceCount", style: const TextStyle(
                          color: _skyDark, fontWeight: FontWeight.w800,
                          fontSize: 12)),
                    ),
                ]),
                const SizedBox(height: 3),
                Text("$date · $empName", style: const TextStyle(
                    color: _textMuted, fontSize: 11)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _statusBg(status),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(status, style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ]),
        ),

        // ── Time strip ────────────────────────────────────────────────
        if (startTimeStr != null || endTimeStr != null || minsTaken != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _skyLight,
              border: Border(
                top: BorderSide(color: _border),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.schedule_rounded,
                  color: _skyDark, size: 14),
              const SizedBox(width: 8),
              if (startTimeStr != null) ...[
                _timeChip("Start", startTimeStr!, _skyDark),
                const SizedBox(width: 8),
              ],
              if (endTimeStr != null) ...[
                const Text("→", style: TextStyle(
                    color: _textMuted, fontSize: 12)),
                const SizedBox(width: 8),
                _timeChip("End", endTimeStr!, _statusColor(status)),
              ],
              if (minsTaken != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("⏱ ${minsTaken}m",
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          ),

        // Photos
        if (beforeUrl != null || afterList.isNotEmpty ||
            interiorBefore.isNotEmpty || interiorAfter.isNotEmpty ||
            cancelPhoto != null) ...[
          const Divider(height: 1, color: Color(0xFFDDE8F5)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Exterior before photo
                if (beforeUrl != null) ...[
                  const Text("Before", style: TextStyle(color: _textMuted,
                      fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _viewPhoto(context, beforeUrl, "Before"),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(beforeUrl,
                          height: 140, width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : Container(
                                height: 140,
                                decoration: BoxDecoration(color: _skyLight,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Center(child:
                                    CircularProgressIndicator(color: _skyBlue)),
                              )),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Interior before photos (8 grid)
                if (interiorBefore.isNotEmpty) ...[
                  Text("Before (${interiorBefore.length}/8)",
                      style: const TextStyle(color: Color(0xFFF59E0B),
                          fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
                    itemCount: interiorBefore.length,
                    itemBuilder: (_, i) {
                      final url   = (interiorBefore[i]['url']   ?? '') as String;
                      final label = (interiorBefore[i]['label'] ?? '') as String;
                      if (url.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => _viewPhoto(context, url, label),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(url, fit: BoxFit.cover),
                            Positioned(bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                color: Colors.black54,
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 8,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                // Exterior after photos
                if (afterList.isNotEmpty) ...[
                  const Text("After", style: TextStyle(color: _textMuted,
                      fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
                    itemCount: afterList.length,
                    itemBuilder: (_, i) {
                      final item  = afterList[i];
                      final url   = item['url']   ?? '';
                      final label = item['label'] ?? '';
                      if (url.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => _viewPhoto(context, url, label),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(url, fit: BoxFit.cover),
                            Positioned(bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                color: Colors.black54,
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 8,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ],
                // Interior after photos (8 grid)
                if (interiorAfter.isNotEmpty) ...[
                  Text("After (${interiorAfter.length}/8)",
                      style: const TextStyle(color: Color(0xFF009688),
                          fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
                    itemCount: interiorAfter.length,
                    itemBuilder: (_, i) {
                      final url   = (interiorAfter[i]['url']   ?? '') as String;
                      final label = (interiorAfter[i]['label'] ?? '') as String;
                      if (url.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => _viewPhoto(context, url, label),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(url, fit: BoxFit.cover),
                            Positioned(bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                color: Colors.black54,
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 8,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ],
                // Cancel photo + reason
                if (cancelPhoto != null) ...[
                  const Text("Cancellation Photo",
                      style: TextStyle(color: Colors.red,
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _viewPhoto(context, cancelPhoto, "Cancellation"),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(cancelPhoto,
                          height: 140, width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : Container(
                                height: 140,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Center(child:
                                    CircularProgressIndicator(color: Colors.red)),
                              )),
                    ),
                  ),
                  if (cancelReason != null && cancelReason.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Reason",
                              style: TextStyle(color: Colors.red,
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(cancelReason,
                              style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          if (cancelledAt != null) ...[
                            const SizedBox(height: 4),
                            Text(_formatDate(cancelledAt.split('T')[0]),
                                style: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],

        // Action buttons row
        const Divider(height: 1, color: Color(0xFFDDE8F5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [

            // Share button
            Expanded(child: GestureDetector(
              onTap: canShare ? () => _sharePdf(job) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: canShare ? _skyLight : _border.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: canShare ? _skyBlue.withOpacity(0.4) : _border),
                ),
                child: isGenerating
                    ? const Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _skyBlue)),
                          SizedBox(width: 8),
                          Text("Preparing...", style: TextStyle(
                              color: _skyBlue, fontWeight: FontWeight.w600,
                              fontSize: 12)),
                        ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded,
                              color: canShare ? _skyBlue : _textMuted,
                              size: 16),
                          const SizedBox(width: 6),
                          Text("Share",
                              style: TextStyle(
                                  color: canShare ? _skyBlue : _textMuted,
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ]),
              ),
            )),

            if (canComplain) ...[
              const SizedBox(width: 10),

              // Complaint / Resolve button
              Expanded(child: GestureDetector(
                onTap: hasComplaint && !isResolved
                    ? () => _resolveComplaint(job)
                    : (!hasComplaint ? () => _raiseComplaint(job) : null),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: hasComplaint && !isResolved
                        ? const Color(0xFFFEF2F2)
                        : isResolved
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasComplaint && !isResolved
                          ? Colors.red.withOpacity(0.4)
                          : isResolved
                              ? _success.withOpacity(0.4)
                              : _warning.withOpacity(0.4),
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(
                      hasComplaint && !isResolved
                          ? Icons.check_circle_outline_rounded
                          : isResolved
                              ? Icons.verified_rounded
                              : Icons.report_problem_rounded,
                      color: hasComplaint && !isResolved
                          ? Colors.red
                          : isResolved ? _success : _warning,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasComplaint && !isResolved
                          ? "Resolve"
                          : isResolved
                              ? "Resolved"
                              : "Complain",
                      style: TextStyle(
                          color: hasComplaint && !isResolved
                              ? Colors.red
                              : isResolved ? _success : _warning,
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ]),
                ),
              )),
            ],
          ]),
        ),
      ]),
    );
  }

  void _viewPhoto(BuildContext context, String url, String label) {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black, insetPadding: EdgeInsets.zero,
      child: Stack(children: [
        Center(child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain))),
        Positioned(top: 40, left: 16,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ),
        Positioned(bottom: 40, left: 0, right: 0,
          child: Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14))),
      ]),
    ));
  }

  Widget _buildEmpty() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.history_rounded, color: _textMuted, size: 64),
        const SizedBox(height: 16),
        Text("No service history for ${widget.customer['customerName']}",
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMuted, fontSize: 14)),
        const SizedBox(height: 8),
        const Text("Jobs will appear here after completion",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ],
    ));
  }
}