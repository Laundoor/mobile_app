import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class AdminSalaryScreen extends StatefulWidget {
  const AdminSalaryScreen({Key? key}) : super(key: key);

  @override
  State<AdminSalaryScreen> createState() => _AdminSalaryScreenState();
}

class _AdminSalaryScreenState extends State<AdminSalaryScreen> {
  List<dynamic> _employees = [];
  bool _loadingEmployees   = true;

  String?  _selectedEmployeeId;
  String?  _selectedEmployeeName;
  int      _selectedMonth = DateTime.now().month;
  int      _selectedYear  = DateTime.now().year;

  Map<String, dynamic>? _salaryData;
  bool _loadingSalary = false;

  final List<String> _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final data = await AdminApiService.getEmployees();
    if (mounted) setState(() {
      _employees       = data;
      _loadingEmployees= false;
    });
  }

  Future<void> _loadSalary() async {
    if (_selectedEmployeeId == null) return;
    setState(() { _loadingSalary = true; _salaryData = null; });
    try {
      final data = await AdminApiService.getSalary(
        employeeId: _selectedEmployeeId!,
        month: _selectedMonth,
        year:  _selectedYear,
      );
      if (mounted) setState(() { _salaryData = data; _loadingSalary = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingSalary = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Salary",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AdminTheme.border)),
      ),
      body: _loadingEmployees
          ? const Center(child: CircularProgressIndicator(
              color: AdminTheme.skyBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilters(),
                  const SizedBox(height: 20),

                  if (_loadingSalary)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          color: AdminTheme.skyBlue),
                    ))
                  else if (_salaryData != null)
                    _buildSalaryResult()
                  else if (_selectedEmployeeId != null)
                    _buildEmptyHint()
                  else
                    _buildSelectHint(),
                ],
              ),
            ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Select Employee & Period",
              style: TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Employee dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AdminTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text("Select Employee",
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 14)),
                value: _selectedEmployeeId,
                items: _employees.map((e) => DropdownMenuItem<String>(
                  value: e['_id'].toString(),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: const BoxDecoration(
                          color: AdminTheme.skyLight, shape: BoxShape.circle),
                      child: Center(child: Text(
                        (e['name'] as String)[0].toUpperCase(),
                        style: const TextStyle(color: AdminTheme.skyBlue,
                            fontWeight: FontWeight.w800, fontSize: 12),
                      )),
                    ),
                    const SizedBox(width: 10),
                    Text(e['name'], style: const TextStyle(
                        color: AdminTheme.textPrimary, fontSize: 14)),
                  ]),
                )).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedEmployeeId   = val;
                    _selectedEmployeeName = _employees
                        .firstWhere((e) => e['_id'].toString() == val)['name'];
                    _salaryData = null;
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Month + Year row
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: AdminTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.border)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedMonth,
                    items: List.generate(12, (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(_months[i], style: const TextStyle(
                          color: AdminTheme.textPrimary, fontSize: 13)),
                    )),
                    onChanged: (v) => setState(() {
                      _selectedMonth = v!; _salaryData = null;
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: AdminTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.border)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedYear,
                    items: List.generate(3, (i) {
                      final y = DateTime.now().year - 1 + i;
                      return DropdownMenuItem(value: y,
                          child: Text(y.toString(), style: const TextStyle(
                              color: AdminTheme.textPrimary, fontSize: 13)));
                    }),
                    onChanged: (v) => setState(() {
                      _selectedYear = v!; _salaryData = null;
                    }),
                  ),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Calculate button
          GestureDetector(
            onTap: _selectedEmployeeId == null || _loadingSalary
                ? null : _loadSalary,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: _selectedEmployeeId != null
                    ? const LinearGradient(
                        colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: _selectedEmployeeId == null ? AdminTheme.border : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text("Calculate Salary",
                  style: TextStyle(
                      color: _selectedEmployeeId != null
                          ? Colors.white : AdminTheme.textMuted,
                      fontWeight: FontWeight.w700, fontSize: 14))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryResult() {
    final summary    = _salaryData!['summary']    as Map;
    final details    = _salaryData!['jobDetails'] as List;
    final dayDetails = _salaryData!['dayDetails'] as List? ?? [];
    final emp        = _salaryData!['employee']   as Map;
    final pricing    = _salaryData!['pricing']    as Map;
    final counts     = summary['carTypeCounts']   as Map;
    final hasHome    = emp['hasHomeLocation']      == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Grand total card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: AdminTheme.skyBlue.withOpacity(0.3),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(children: [
            Text(_selectedEmployeeName ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text("${_months[_selectedMonth-1]} $_selectedYear",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            Text("₹ ${summary['grandTotal']}",
                style: const TextStyle(color: Colors.white,
                    fontSize: 36, fontWeight: FontWeight.w900)),
            const Text("Total Earnings",
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),

        const SizedBox(height: 20),

        // Summary breakdown
        _buildCard("Earnings Breakdown", [
          _buildSummaryRow(Icons.work_rounded, "Total Jobs",
              "${summary['totalJobs']} jobs", AdminTheme.skyBlue),
          _buildSummaryRow(Icons.payments_rounded, "Job Earnings",
              "₹ ${summary['totalJobEarnings']}", AdminTheme.success),
          _buildSummaryRow(Icons.route_rounded, "Distance",
              hasHome
                  ? "${summary['totalDistanceKm']} km"
                  : "No home location set",
              hasHome ? AdminTheme.warning : AdminTheme.textMuted),
          _buildSummaryRow(Icons.directions_bike_rounded, "Distance Allowance",
              hasHome
                  ? "₹ ${summary['totalDistanceEarnings']}"
                  : "—",
              hasHome ? AdminTheme.warning : AdminTheme.textMuted),
        ]),

        if (!hasHome) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.warning.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AdminTheme.warning, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Set home location in employee profile to include distance allowance.",
                  style: TextStyle(color: AdminTheme.warning,
                      fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

        // Warning: some customers missing coordinates
        if (hasHome && (summary['skippedCustomers'] ?? 0) > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.location_off_rounded,
                  color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${summary['skippedCustomers']} customer(s) have no location set — excluded from distance. "
                  "Open each customer and set their Maps link to fix this.",
                  style: const TextStyle(color: Colors.red,
                      fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ],

        // ── INCENTIVES ────────────────────────────────────────────────────
        const SizedBox(height: 20),
        _buildCard("Incentives", [
          _buildSummaryRow(Icons.emoji_events_rounded, "Total Incentive",
              "₹ ${summary['totalIncentive'] ?? 0}",
              const Color(0xFFF59E0B)),
        ]),

        // Per-day incentive breakdown
        if ((_salaryData!['incentiveDetails'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.border),
            ),
            child: Column(
              children: [
                ...(_salaryData!['incentiveDetails'] as List).map((d) {
                  final day     = d['date']    as String? ?? '';
                  final earned  = d['earned']  == true;
                  final excused = d['excused'] == true;
                  final amount  = d['amount']  ?? 0;
                  final reasons = List<String>.from(d['reasons'] ?? []);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(
                          color: AdminTheme.border, width: 0.5)),
                    ),
                    child: Row(children: [
                      Text(day.length >= 10 ? day.substring(5) : day,
                          style: const TextStyle(
                              color: AdminTheme.textMuted,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(child: earned
                          ? Text(excused ? "Excused ✓" : "Earned ✓",
                              style: const TextStyle(
                                  color: AdminTheme.success,
                                  fontSize: 12, fontWeight: FontWeight.w600))
                          : Text(
                              reasons.map(_shortReason).join(', '),
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            )),
                      Text(earned ? "+₹$amount" : "₹0",
                          style: TextStyle(
                              color: earned
                                  ? AdminTheme.success : AdminTheme.textMuted,
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Car type counts
        _buildCard("Jobs by Car Type", [
          _buildSummaryRow(Icons.directions_car_rounded,
              "Hatchback", "${counts['Hatchback']} jobs",
              AdminTheme.skyBlue),
          _buildSummaryRow(Icons.directions_car_filled_rounded,
              "Sedan", "${counts['Sedan']} jobs",
              AdminTheme.skyBlue),
          _buildSummaryRow(Icons.airport_shuttle_rounded,
              "SUV", "${counts['SUV']} jobs",
              AdminTheme.skyBlue),
        ]),

        const SizedBox(height: 20),

        // Per-day job details — grouped by date
        if (details.isNotEmpty) ...[
          Row(children: [
            Container(width: 3, height: 20,
                decoration: BoxDecoration(color: AdminTheme.skyBlue,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            const Text("Daily Breakdown",
                style: TextStyle(color: AdminTheme.textPrimary,
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          _DayCardList(details: details, dayDetails: dayDetails, pricing: pricing),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  String _shortReason(String r) {
    switch (r) {
      case 'selfie':           return 'Selfie';
      case 'towels':           return 'Towels';
      case 'towelSoakMissing': return 'No towel soak';
      case 'towelSoak':        return 'Towel soak';
      case 'dusterSoakMissing':return 'No duster soak';
      case 'dusterSoak':       return 'Duster soak';
      case 'late':             return 'Late';
      case 'minCars':          return 'Under 5 cars';
      case 'complaint':        return 'Complaint';
      default:                 return r;
    }
  }

  Widget _buildCard(String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: const TextStyle(
                color: AdminTheme.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2FB)),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label,
      String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(
            color: AdminTheme.textMuted, fontSize: 13))),
        Text(value, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    );
  }

  Widget _buildJobDetailCard(Map job, Map pricing) {
    final svcType  = job['serviceType'] ?? '';
    final carType  = job['carType']     ?? '';
    final earnings = job['earnings'];
    final count    = job['serviceCount'];

    Color cardColor;
    if (svcType == 'Exterior')          cardColor = AdminTheme.skyBlue;
    else if (svcType.contains('Premium')) cardColor = AdminTheme.success;
    else                                  cardColor = AdminTheme.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: cardColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.directions_car_rounded,
              color: cardColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(job['customerName'] ?? '',
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 6),
              if (count != null && count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AdminTheme.skyLight,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text("#$count",
                      style: const TextStyle(color: AdminTheme.skyDark,
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 2),
            Text("$carType · ${job['vehicleNo'] ?? ''}",
                style: const TextStyle(color: AdminTheme.textMuted,
                    fontSize: 11)),
            const SizedBox(height: 2),
            Text(svcType, style: TextStyle(
                color: cardColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text("₹ $earnings",
              style: const TextStyle(color: AdminTheme.textPrimary,
                  fontWeight: FontWeight.w800, fontSize: 15)),
          Text(job['date'] ?? '',
              style: const TextStyle(color: AdminTheme.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _buildSelectHint() => _buildHint(
      Icons.person_search_rounded, "Select an employee and period above");

  Widget _buildEmptyHint() => _buildHint(
      Icons.inbox_rounded, "No completed jobs found for this period");

  Widget _buildHint(IconData icon, String msg) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(children: [
        Icon(icon, color: AdminTheme.textMuted, size: 52),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center,
            style: const TextStyle(color: AdminTheme.textMuted, fontSize: 13)),
      ]),
    ));
  }
}

// ── Day card list — collapsible per-day breakdown ─────────────────────────────
class _DayCardList extends StatefulWidget {
  final List details;
  final List dayDetails;
  final Map  pricing;
  const _DayCardList({
    required this.details,
    required this.dayDetails,
    required this.pricing,
  });
  @override State<_DayCardList> createState() => _DayCardListState();
}

class _DayCardListState extends State<_DayCardList> {
  final Set<String> _expanded = {};

  Map<String, List> get _byDate {
    final map = <String, List>{};
    for (final j in widget.details) {
      final d = (j['date'] as String?) ?? '';
      map.putIfAbsent(d, () => []).add(j);
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
  }

  // Build a lookup of dayDetails by date
  Map<String, Map> get _dayMap {
    final m = <String, Map>{};
    for (final d in widget.dayDetails) {
      m[(d['date'] as String?) ?? ''] = d as Map;
    }
    return m;
  }

  String _fmtDate(String date) {
    try {
      final d = DateTime.parse(date);
      const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'];
      const wd = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${wd[d.weekday-1]}, ${d.day} ${mo[d.month-1]}';
    } catch (_) { return date; }
  }

  String _shortReason(String r) {
    switch (r) {
      case 'selfie':            return 'Selfie';
      case 'towels':            return 'Towels';
      case 'towelSoakMissing':  return 'No towel soak';
      case 'towelSoak':         return 'Towel soak';
      case 'dusterSoakMissing': return 'No duster soak';
      case 'dusterSoak':        return 'Duster soak';
      case 'late':              return 'Late';
      case 'minCars':           return 'Under 5 cars';
      case 'complaint':         return 'Complaint';
      default:                  return r;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byDate;
    final dayMap  = _dayMap;

    return Column(children: grouped.entries.map((entry) {
      final date    = entry.key;
      final dayJobs = entry.value;
      final isOpen  = _expanded.contains(date);
      final dd      = dayMap[date];

      final jobEarnings      = (dd?['jobEarnings']      as num?)?.toDouble() ?? 0;
      final distKm           = (dd?['distanceKm']       as num?)?.toDouble() ?? 0;
      final distEarn         = (dd?['distanceEarnings'] as num?)?.toDouble() ?? 0;
      final incentive        = (dd?['incentive']        as num?)?.toDouble() ?? 0;
      final incEarned        = dd?['incentiveEarned']   == true;
      final incReasons       = List<String>.from(dd?['incentiveReasons'] ?? []);
      final dayTotal         = (dd?['dayTotal']         as num?)?.toDouble() ??
                               (jobEarnings + distEarn + incentive);
      final carCounts        = dd?['carCounts'] as Map? ?? {};
      final jobCount         = dayJobs.length;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOpen
                ? AdminTheme.skyBlue.withOpacity(0.3)
                : AdminTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [

          // ── Header ─────────────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() =>
                isOpen ? _expanded.remove(date) : _expanded.add(date)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isOpen ? AdminTheme.skyLight : AdminTheme.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                // Date badge
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isOpen
                        ? AdminTheme.skyBlue : AdminTheme.skyLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(
                      (() {
                        try {
                          final dt = DateTime.parse(date);
                          const wd = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                          return wd[dt.weekday-1];
                        } catch (_) { return ''; }
                      })(),
                      style: TextStyle(
                          color: isOpen ? Colors.white70 : AdminTheme.skyBlue,
                          fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      DateTime.tryParse(date)?.day.toString() ?? '',
                      style: TextStyle(
                          color: isOpen ? Colors.white : AdminTheme.skyDark,
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_fmtDate(date), style: const TextStyle(
                      color: AdminTheme.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text("$jobCount job${jobCount == 1 ? '' : 's'}",
                        style: const TextStyle(
                            color: AdminTheme.textMuted, fontSize: 11)),
                    if (distKm > 0) ...[
                      const Text("  ·  ",
                          style: TextStyle(color: AdminTheme.textMuted,
                              fontSize: 11)),
                      Text("${distKm.toStringAsFixed(1)} km",
                          style: const TextStyle(
                              color: AdminTheme.skyDark,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(width: 6),
                    // Incentive status dot
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: incEarned
                            ? AdminTheme.successLight
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        incEarned ? "✓ Incentive" : "✗ Incentive",
                        style: TextStyle(
                            color: incEarned
                                ? AdminTheme.success : Colors.red,
                            fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Text("₹ ${dayTotal.toInt()}",
                      style: const TextStyle(
                          color: AdminTheme.success,
                          fontSize: 16, fontWeight: FontWeight.w900)),
                  const Text("total",
                      style: TextStyle(
                          color: AdminTheme.textMuted, fontSize: 10)),
                ]),
                const SizedBox(width: 6),
                Icon(isOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                    color: AdminTheme.textMuted, size: 20),
              ]),
            ),
          ),

          // ── Expanded ───────────────────────────────────────────────────
          if (isOpen) ...[
            const Divider(height: 1, color: AdminTheme.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [

                // Car type counts
                if ((carCounts['Hatchback'] ?? 0) > 0 ||
                    (carCounts['Sedan'] ?? 0) > 0 ||
                    (carCounts['SUV'] ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AdminTheme.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminTheme.border),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                      _carBadge("🚗", "Hatchback",
                          (carCounts['Hatchback'] ?? 0) as int),
                      _carBadge("🚙", "Sedan",
                          (carCounts['Sedan'] ?? 0) as int),
                      _carBadge("🚕", "SUV",
                          (carCounts['SUV'] ?? 0) as int),
                    ]),
                  ),

                // Earnings breakdown
                _earnRow("🚗 Car Wash",
                    "₹ ${jobEarnings.toInt()}",
                    AdminTheme.skyBlue),
                if (distKm > 0) ...[
                  const SizedBox(height: 6),
                  _earnRow(
                      "⛽ Petrol (${distKm.toStringAsFixed(1)} km)",
                      "₹ ${distEarn.toInt()}",
                      const Color(0xFF7C3AED)),
                ],
                const SizedBox(height: 6),
                _earnRow(
                    "🏆 Incentive",
                    incEarned
                        ? "+ ₹ ${incentive.toInt()}"
                        : "₹ 0",
                    incEarned
                        ? AdminTheme.success : AdminTheme.textMuted),

                // Incentive miss reasons
                if (!incEarned && incReasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Wrap(spacing: 6, runSpacing: 4,
                      children: incReasons.map((r) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(_shortReason(r),
                            style: const TextStyle(
                                color: Colors.red, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      )).toList(),
                    ),
                  ),
                ],

                // Day total
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminTheme.successLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AdminTheme.success.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Text("Day Total",
                        style: TextStyle(
                            color: AdminTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text("₹ ${dayTotal.toInt()}",
                        style: const TextStyle(
                            color: AdminTheme.success,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ]),
                ),

                // Per-job list
                if (dayJobs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AdminTheme.border),
                  ...dayJobs.map((j) {
                    final svcType  = j['serviceType'] ?? '';
                    final carType  = j['carType']     ?? '';
                    final earnings = j['earnings'];
                    final name     = j['customerName'] ?? '';
                    final isCan    = j['status'] == 'Cancelled';
                    final hasComp  = j['complaint'] != null;

                    Color color;
                    if (svcType == 'Exterior')            color = AdminTheme.skyBlue;
                    else if (svcType.contains('Premium')) color = AdminTheme.success;
                    else                                  color = AdminTheme.warning;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(
                            color: AdminTheme.border, width: 0.5)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(7)),
                          child: Icon(Icons.directions_car_rounded,
                              color: color, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name,
                              style: const TextStyle(
                                  color: AdminTheme.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                          Text("$carType · $svcType",
                              style: TextStyle(
                                  color: isCan
                                      ? Colors.red
                                      : AdminTheme.textMuted,
                                  fontSize: 10)),
                        ])),
                        if (hasComp)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 12),
                          ),
                        Text(
                          isCan ? "—" : "₹ $earnings",
                          style: TextStyle(
                              color: isCan
                                  ? AdminTheme.textMuted
                                  : AdminTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w800),
                        ),
                      ]),
                    );
                  }),
                ],
              ]),
            ),
          ],
        ]),
      );
    }).toList());
  }

  Widget _carBadge(String emoji, String label, int count) =>
    Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      Text(count.toString(),
          style: const TextStyle(color: AdminTheme.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(
          color: AdminTheme.textMuted, fontSize: 9)),
    ]);

  Widget _earnRow(String label, String value, Color c) =>
    Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: AdminTheme.textMuted,
              fontSize: 12))),
      Text(value, style: TextStyle(
          color: c, fontSize: 13, fontWeight: FontWeight.w800)),
    ]);

}