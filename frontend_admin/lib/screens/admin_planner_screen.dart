import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';

class AdminPlannerScreen extends StatefulWidget {
  const AdminPlannerScreen({Key? key}) : super(key: key);
  @override
  State<AdminPlannerScreen> createState() => _AdminPlannerScreenState();
}

class _AdminPlannerScreenState extends State<AdminPlannerScreen> {
  List<dynamic> _employees = [];
  bool     _loading = true;
  DateTime _selectedDate = DateTime.now();

  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await AdminApiService.getEmployees();
    if (mounted) setState(() { _employees = data; _loading = false; });
  }

  List<dynamic> get _filteredEmployees {
    if (_search.isEmpty) return _employees;
    return _employees.where((e) =>
        (e['name'] ?? '').toString().toLowerCase().contains(_search)).toList();
  }

  String get _dateLabel {
    final now      = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    if (_selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day) return 'Today';
    if (_selectedDate.year == tomorrow.year &&
        _selectedDate.month == tomorrow.month &&
        _selectedDate.day == tomorrow.day) return 'Tomorrow';
    return '${_selectedDate.day} ${_months[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate:  DateTime.now().add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AdminTheme.skyBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text("Planner",
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminTheme.skyBlue))
          : RefreshIndicator(
              onRefresh: _load,
              color: AdminTheme.skyBlue,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Global date selector ────────────────────────────────
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AdminTheme.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AdminTheme.skyBlue.withOpacity(0.4)),
                        boxShadow: [BoxShadow(
                            color: AdminTheme.skyBlue.withOpacity(0.08),
                            blurRadius: 12, offset: const Offset(0, 3))],
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: AdminTheme.skyLight,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.calendar_today_rounded,
                              color: AdminTheme.skyBlue, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Assigning for",
                                style: TextStyle(
                                    color: AdminTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(_dateLabel,
                                style: const TextStyle(
                                    color: AdminTheme.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        )),
                        const Icon(Icons.edit_calendar_rounded,
                            color: AdminTheme.skyBlue, size: 18),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Search
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                        color: AdminTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Search employee...",
                      hintStyle: const TextStyle(
                          color: AdminTheme.textMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AdminTheme.textMuted, size: 18),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AdminTheme.textMuted, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              })
                          : null,
                      filled: true,
                      fillColor: AdminTheme.white,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AdminTheme.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AdminTheme.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AdminTheme.skyBlue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Text("Select Employee",
                        style: TextStyle(color: AdminTheme.textMuted,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_search.isNotEmpty)
                      Text("${_filteredEmployees.length} found",
                          style: const TextStyle(
                              color: AdminTheme.skyBlue,
                              fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 12),
                  if (_filteredEmployees.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No employee found for "$_search"',
                          style: const TextStyle(
                              color: AdminTheme.textMuted, fontSize: 13)),
                      ),
                    )
                  else
                    ..._filteredEmployees.map(
                        (emp) => _buildEmployeeCard(emp)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmployeeCard(dynamic emp) {
    final isActive = emp['isActive'] == true;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _EmployeePlannerScreen(
                employeeId:   emp['_id'].toString(),
                employeeName: emp['name'].toString(),
                initialDate:  _selectedDate,
              ))).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isActive ? AdminTheme.successLight : AdminTheme.skyLight,
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              emp['name'][0].toUpperCase(),
              style: TextStyle(
                  color: isActive ? AdminTheme.success : AdminTheme.skyBlue,
                  fontWeight: FontWeight.w800, fontSize: 17),
            )),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emp['name'].toString(),
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text(emp['email'].toString(),
                  style: const TextStyle(color: AdminTheme.textMuted,
                      fontSize: 11)),
            ],
          )),
          // Show selected date as a small badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: AdminTheme.skyLight,
                borderRadius: BorderRadius.circular(8)),
            child: Text(_dateLabel,
                style: const TextStyle(color: AdminTheme.skyBlue,
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AdminTheme.textMuted, size: 20),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-employee planner with date picker, job list, drag-to-reorder
// ─────────────────────────────────────────────────────────────────────────────
class _EmployeePlannerScreen extends StatefulWidget {
  final String   employeeId;
  final String   employeeName;
  final DateTime initialDate;
  const _EmployeePlannerScreen({
    required this.employeeId,
    required this.employeeName,
    required this.initialDate,
  });
  @override
  State<_EmployeePlannerScreen> createState() => _EmployeePlannerScreenState();
}

class _EmployeePlannerScreenState extends State<_EmployeePlannerScreen> {
  late DateTime _date;
  List<dynamic> _jobs = [];
  bool _loading      = true;
  bool _reordering   = false;

  static const _serviceTypes = [
    'Exterior', 'Interior Standard', 'Interior Premium'
  ];

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _loadJobs();
  }

  String get _dateStr =>
      '${_date.year}-${_date.month.toString().padLeft(2,'0')}-${_date.day.toString().padLeft(2,'0')}';

  String get _dateLabel {
    final now = DateTime.now();
    if (_date.year == now.year && _date.month == now.month && _date.day == now.day)
      return 'Today';
    final tomorrow = now.add(const Duration(days: 1));
    if (_date.year == tomorrow.year && _date.month == tomorrow.month && _date.day == tomorrow.day)
      return 'Tomorrow';
    return '${_date.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_date.month-1]} ${_date.year}';
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getPlannerJobs(widget.employeeId, _dateStr);
    if (mounted) setState(() { _jobs = data; _loading = false; });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate:  DateTime.now().add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AdminTheme.skyBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadJobs();
    }
  }

  Future<void> _saveOrder() async {
    setState(() => _reordering = true);
    final ids = _jobs.map((j) => j['_id'].toString()).toList();
    await AdminApiService.reorderJobs(ids);
    if (mounted) setState(() => _reordering = false);
  }

  Future<void> _removeJob(dynamic job) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminTheme.white,
        title: const Text("Remove Job",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontWeight: FontWeight.w800)),
        content: Text(
            "Remove ${job['customerId']?['customerName'] ?? 'this job'} from the plan?",
            style: const TextStyle(color: AdminTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text("Remove",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await AdminApiService.removePlannerJob(job['_id'].toString());
    if (ok) _loadJobs();
  }

  Future<void> _showAssignSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignSheet(
        employeeId: widget.employeeId,
        date:       _dateStr,
        onAssigned: _loadJobs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.employeeName,
              style: const TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          const Text("Planner",
              style: TextStyle(color: AdminTheme.textMuted, fontSize: 11)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_reordering)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: AdminTheme.skyBlue)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AdminTheme.border),
        ),
      ),
      body: Column(children: [
        // Date picker bar
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: AdminTheme.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.skyBlue.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded,
                  color: AdminTheme.skyBlue, size: 18),
              const SizedBox(width: 10),
              Text(_dateLabel,
                  style: const TextStyle(color: AdminTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              Text(_dateStr,
                  style: const TextStyle(color: AdminTheme.textMuted, fontSize: 12)),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more_rounded,
                  color: AdminTheme.textMuted, size: 18),
            ]),
          ),
        ),

        // Job count header
        if (!_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text("${_jobs.length} job${_jobs.length == 1 ? '' : 's'} planned",
                  style: const TextStyle(color: AdminTheme.textMuted,
                      fontSize: 12, fontWeight: FontWeight.w600)),
              if (_jobs.isNotEmpty) ...[
                const Spacer(),
                const Icon(Icons.drag_indicator_rounded,
                    color: AdminTheme.textMuted, size: 14),
                const SizedBox(width: 4),
                const Text("Hold to reorder",
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 11)),
              ],
            ]),
          ),

        const SizedBox(height: 10),

        // Job list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AdminTheme.skyBlue))
              : _jobs.isEmpty
                  ? Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_note_rounded,
                            color: AdminTheme.border, size: 56),
                        const SizedBox(height: 12),
                        const Text("No jobs planned",
                            style: TextStyle(color: AdminTheme.textMuted,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text("Tap + to assign customers",
                            style: TextStyle(color: AdminTheme.textMuted,
                                fontSize: 12)),
                      ],
                    ))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _jobs.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = _jobs.removeAt(oldIndex);
                          _jobs.insert(newIndex, item);
                        });
                        _saveOrder();
                      },
                      itemBuilder: (_, i) {
                        final job      = _jobs[i];
                        final customer = job['customerId'];
                        final status   = job['status'] ?? 'Pending';
                        final isPending = status == 'Pending';
                        return _JobPlanCard(
                          key: ValueKey(job['_id']),
                          index: i,
                          job: job,
                          customer: customer,
                          status: status,
                          isPending: isPending,
                          onRemove: isPending ? () => _removeJob(job) : null,
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssignSheet,
        backgroundColor: AdminTheme.skyBlue,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text("Assign Customer",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single job card in planner
// ─────────────────────────────────────────────────────────────────────────────
class _JobPlanCard extends StatelessWidget {
  final int index;
  final dynamic job;
  final dynamic customer;
  final String status;
  final bool isPending;
  final VoidCallback? onRemove;

  const _JobPlanCard({
    Key? key,
    required this.index,
    required this.job,
    required this.customer,
    required this.status,
    required this.isPending,
    this.onRemove,
  }) : super(key: key);

  Color get _statusColor {
    if (status == 'Completed')  return AdminTheme.success;
    if (status == 'In Progress') return AdminTheme.skyBlue;
    if (status == 'Cancelled')  return Colors.red;
    return AdminTheme.warning;
  }

  Color get _statusBg {
    if (status == 'Completed')  return AdminTheme.successLight;
    if (status == 'In Progress') return AdminTheme.skyLight;
    if (status == 'Cancelled')  return const Color(0xFFFEF2F2);
    return AdminTheme.warningLight;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // Order number
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: AdminTheme.skyLight, shape: BoxShape.circle),
          child: Center(child: Text('${index + 1}',
              style: const TextStyle(color: AdminTheme.skyBlue,
                  fontWeight: FontWeight.w900, fontSize: 13))),
        ),
        const SizedBox(width: 10),

        // Customer info
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customer?['customerName'] ?? 'Unknown',
                style: const TextStyle(color: AdminTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              Text(job['serviceType'] ?? '',
                  style: const TextStyle(color: AdminTheme.textMuted,
                      fontSize: 11)),
              if (customer?['carType'] != null) ...[
                const Text(' · ', style: TextStyle(color: AdminTheme.textMuted)),
                Text(customer!['carType'].toString(),
                    style: const TextStyle(color: AdminTheme.textMuted,
                        fontSize: 11)),
              ],
            ]),
          ],
        )),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: _statusBg, borderRadius: BorderRadius.circular(8)),
          child: Text(status,
              style: TextStyle(color: _statusColor,
                  fontWeight: FontWeight.w700, fontSize: 10)),
        ),
        const SizedBox(width: 8),

        // Remove (only pending) or drag handle
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.remove_circle_outline_rounded,
                color: Colors.red, size: 20),
          )
        else
          const Icon(Icons.lock_outline_rounded,
              color: AdminTheme.textMuted, size: 16),

        const SizedBox(width: 6),
        const Icon(Icons.drag_indicator_rounded,
            color: AdminTheme.textMuted, size: 20),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assign bottom sheet — search customer, pick service, assign
// ─────────────────────────────────────────────────────────────────────────────
class _AssignSheet extends StatefulWidget {
  final String employeeId;
  final String date;
  final VoidCallback onAssigned;
  const _AssignSheet({
    required this.employeeId,
    required this.date,
    required this.onAssigned,
  });
  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _results     = [];
  dynamic _selected          = null;
  String _serviceType        = 'Exterior';
  bool _searching            = false;
  bool _assigning            = false;
  String? _error;

  // Derived from selected customer's interiorType
  List<String> get _availableServices {
    if (_selected == null) return ['Exterior'];
    final it = _selected['interiorType'] as String? ?? 'None';
    if (it == 'None') return ['Exterior'];
    return ['Exterior', it];
  }

  // When customer is selected, reset serviceType to first available
  void _selectCustomer(dynamic customer) {
    setState(() {
      _selected = customer;
      _results  = [];
      _searchCtrl.clear();
      // Pre-select based on interiorType: if customer has interior, default to Exterior
      // (admin can switch to interior if needed)
      _serviceType = 'Exterior';
    });
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    final data = await AdminApiService.searchCustomers(q.trim());
    if (mounted) setState(() { _results = data; _searching = false; });
  }

  Future<void> _assign() async {
    if (_selected == null) return;

    // ── Monthly count warning ─────────────────────────────────────────────
    if (_serviceType == 'Exterior') {
      final hasInterior = (_selected!['interiorType'] ?? 'None') != 'None';
      final customerId  = _selected!['_id'].toString();

      // Fetch accurate monthly billable counts from backend
      final counts = await AdminApiService.getCustomerMonthlyCounts(customerId);
      if (!mounted) return;

      final extCount = (counts?['exterior'] as num?)?.toInt() ?? 0;
      final intCount = (counts?['interior'] as num?)?.toInt() ?? 0;

      debugPrint('[PlannerWarning] customerId=$customerId hasInterior=$hasInterior extCount=$extCount intCount=$intCount counts=$counts');

      String? warningMessage;

      if (hasInterior) {
        if (extCount >= 12 && intCount == 0) {
          // Scenario 1: 12 exteriors done, interior still pending
          warningMessage =
              "$extCount exteriors completed this month. Only interior cleaning is pending.";
        } else if (extCount >= 12 && intCount > 0) {
          // Scenario 2: 12 exteriors AND interior already done
          warningMessage =
              "$extCount exteriors and $intCount interior already completed this month. Do you still want to proceed?";
        } else if (extCount >= 12) {
          // Fallback — shouldn't reach here but just in case
          warningMessage =
              "$extCount exteriors completed this month for this customer.";
        }
      } else {
        if (extCount >= 12) {
          // No interior customer — just show total
          warningMessage =
              "$extCount cleanings completed this month for this customer.";
        }
      }

      if (warningMessage != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AdminTheme.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.warning_amber_rounded,
                    color: AdminTheme.warning, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text("Monthly Limit",
                    style: TextStyle(color: AdminTheme.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
            content: Text(warningMessage ?? '',
                style: const TextStyle(
                    color: AdminTheme.textMuted,
                    fontSize: 13, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel",
                    style: TextStyle(color: AdminTheme.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("OK, Proceed",
                    style: TextStyle(
                        color: AdminTheme.skyBlue,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (ok != true) return;
      }
    }

    setState(() { _assigning = true; _error = null; });
    final err = await AdminApiService.assignCustomer(
      customerId:   _selected['_id'].toString(),
      employeeId:   widget.employeeId,
      serviceType:  _serviceType,
      assignedDate: widget.date,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      widget.onAssigned();
    } else {
      setState(() { _assigning = false; _error = err; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 18),

          const Text("Assign Customer",
              style: TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),

          // Search bar
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.border),
            ),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _search,
              style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: "Search customer name...",
                hintStyle: TextStyle(color: AdminTheme.textMuted),
                prefixIcon: Icon(Icons.search_rounded,
                    color: AdminTheme.textMuted, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Search results
          if (_searching)
            const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2,
                  color: AdminTheme.skyBlue),
            ))
          else if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final c      = _results[i];
                  final isSelected = _selected?['_id'] == c['_id'];
                  return GestureDetector(
                    onTap: () => _selectCustomer(c),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AdminTheme.skyLight
                            : AdminTheme.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AdminTheme.skyBlue.withOpacity(0.4)
                              : AdminTheme.border,
                        ),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['customerName'] ?? '',
                                style: const TextStyle(
                                    color: AdminTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            if (c['vehicleNumber'] != null)
                              Text(c['vehicleNumber'],
                                  style: const TextStyle(
                                      color: AdminTheme.textMuted,
                                      fontSize: 11)),
                          ],
                        )),
                        if (c['carType'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AdminTheme.skyLight,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(c['carType'],
                                style: const TextStyle(
                                    color: AdminTheme.skyBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ),

          // Selected customer chip
          if (_selected != null && _results.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AdminTheme.successLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AdminTheme.success.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AdminTheme.success, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selected!['customerName'] ?? '',
                      style: const TextStyle(color: AdminTheme.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    if ((_selected!['interiorType'] as String?) != null &&
                        _selected!['interiorType'] != 'None')
                      Text(
                        '${_selected!['interiorType']} available',
                        style: const TextStyle(
                            color: AdminTheme.textMuted, fontSize: 10),
                      ),
                  ],
                )),
                GestureDetector(
                  onTap: () => setState(() {
                    _selected = null;
                    _serviceType = 'Exterior';
                    _searchCtrl.clear();
                  }),
                  child: const Icon(Icons.close_rounded,
                      color: AdminTheme.textMuted, size: 16),
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          const SizedBox(height: 4),

          // Service type selector — filtered by customer's interiorType
          const Text("Service Type",
              style: TextStyle(color: AdminTheme.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: _availableServices.map((s) {
            final active = _serviceType == s;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _serviceType = s),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AdminTheme.skyBlue : AdminTheme.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? AdminTheme.skyBlue : AdminTheme.border,
                  ),
                ),
                child: Center(child: Text(
                  s == 'Interior Standard' ? 'Int. Std'
                      : s == 'Interior Premium' ? 'Int. Pre'
                      : s,
                  style: TextStyle(
                      color: active ? Colors.white : AdminTheme.textMuted,
                      fontWeight: FontWeight.w700, fontSize: 11),
                )),
              ),
            ));
          }).toList()),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],

          const SizedBox(height: 18),

          // Assign button
          GestureDetector(
            onTap: (_selected == null || _assigning) ? null : _assign,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: _selected != null
                    ? const LinearGradient(colors: [
                        AdminTheme.skyBlue, Color(0xFF1A90D9)
                      ])
                    : null,
                color: _selected == null ? AdminTheme.border : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: _assigning
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : Text("Assign",
                      style: TextStyle(
                          color: _selected != null
                              ? Colors.white : AdminTheme.textMuted,
                          fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
        ],
      ),
    );
  }
}