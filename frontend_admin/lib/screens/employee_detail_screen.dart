import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'customer_detail_screen.dart';
import 'edit_employee_screen.dart';
import 'complaint_sheet.dart';
import '../services/job_share_service.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const EmployeeDetailScreen({
    Key? key,
    required this.employeeId,
    required this.employeeName,
  }) : super(key: key);

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _sharingJobId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _attendanceRefreshKey = 0;

  Future<void> _load() async {
    final data = await AdminApiService.getEmployee(widget.employeeId);
    if (mounted) setState(() {
      _data = data;
      _loading = false;
      _attendanceRefreshKey++; // triggers AttendanceSection rebuild+refetch
    });
  }

  @override
  Widget build(BuildContext context) {
    final emp    = _data?['employee'];
    // API now returns 'jobs' not 'cars'
    final jobs   = _data?['jobs'] as List? ?? [];
    final isActive = emp?['isActive'] == true;

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: Text(widget.employeeName,
            style: const TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AdminTheme.skyBlue, size: 20),
            onPressed: emp == null ? null : () async {
              final updated = await Navigator.push<bool>(context,
                  MaterialPageRoute(builder: (_) =>
                      EditEmployeeScreen(employee: Map<String, dynamic>.from(emp))));
              if (updated == true) _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AdminTheme.skyBlue),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AdminTheme.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AdminTheme.skyBlue))
          : RefreshIndicator(
              onRefresh: _load,
              color: AdminTheme.skyBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEmployeeInfo(emp, isActive),
                    const SizedBox(height: 16),

                    // Today's attendance (selfie + towels from attendance collection)
                    AttendanceSection(
                      key: ValueKey(_attendanceRefreshKey),
                      employeeId: widget.employeeId,
                    ),
                    const SizedBox(height: 24),

                    // Jobs section header
                    Row(children: [
                      Container(width: 3, height: 20,
                          decoration: BoxDecoration(
                              color: AdminTheme.skyBlue,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      const Text("Assigned Customers",
                          style: TextStyle(color: AdminTheme.textPrimary,
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text("${jobs.length} total",
                          style: const TextStyle(
                              color: AdminTheme.textMuted, fontSize: 12)),
                    ]),
                    const SizedBox(height: 14),

                    if (jobs.isEmpty)
                      _buildEmptyState("No customers assigned yet")
                    else
                      ...jobs.map((job) => _buildJobCard(job)).toList(),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmployeeInfo(dynamic emp, bool isActive) {
    if (emp == null) return const SizedBox();
    final hasHome = emp['homeLocation']?['lat'] != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? AdminTheme.success.withOpacity(0.3) : AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: isActive ? AdminTheme.successLight : AdminTheme.skyLight,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(
                (emp['name'] as String)[0].toUpperCase(),
                style: TextStyle(
                    color: isActive ? AdminTheme.success : AdminTheme.skyBlue,
                    fontWeight: FontWeight.w900, fontSize: 22),
              )),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp['name'], style: const TextStyle(
                    color: AdminTheme.textPrimary,
                    fontWeight: FontWeight.w800, fontSize: 16)),
                Text(emp['email'], style: const TextStyle(
                    color: AdminTheme.textMuted, fontSize: 12)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AdminTheme.successLight : AdminTheme.border,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: isActive
                            ? AdminTheme.success : AdminTheme.textMuted,
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(isActive ? "Active" : "Inactive",
                    style: TextStyle(
                        color: isActive
                            ? AdminTheme.success : AdminTheme.textMuted,
                        fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ]),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFEDF2FB)),
          const SizedBox(height: 12),

          // Phone numbers row
          if ((emp['phone'] ?? '').toString().isNotEmpty ||
              (emp['emergencyContact'] ?? '').toString().isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.phone_rounded,
                  color: AdminTheme.skyBlue, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((emp['phone'] ?? '').toString().isNotEmpty)
                    Text(emp['phone'],
                        style: const TextStyle(
                            color: AdminTheme.textPrimary,
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  if ((emp['emergencyContact'] ?? '').toString().isNotEmpty)
                    Row(children: [
                      Text(emp['emergencyContact'],
                          style: const TextStyle(
                              color: AdminTheme.textMuted, fontSize: 12)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AdminTheme.skyLight,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text("Emergency",
                            style: TextStyle(
                                color: AdminTheme.skyBlue,
                                fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                ],
              )),
            ]),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEDF2FB)),
            const SizedBox(height: 12),
          ],

          // Home location row
          Row(children: [
            Icon(
              hasHome ? Icons.home_rounded : Icons.home_outlined,
              color: hasHome ? AdminTheme.success : AdminTheme.textMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasHome
                    ? "Home location set ✓"
                    : "No home location — distance allowance disabled",
                style: TextStyle(
                    color: hasHome ? AdminTheme.success : AdminTheme.textMuted,
                    fontSize: 12),
              ),
            ),
            if (hasHome)
              GestureDetector(
                onTap: () async {
                  final lat = emp['homeLocation']['lat'];
                  final lng = emp['homeLocation']['lng'];
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
                    color: AdminTheme.skyLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.map_rounded,
                      color: AdminTheme.skyBlue, size: 16),
                ),
              ),
            GestureDetector(
              onTap: () => _showHomeLocationDialog(emp),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AdminTheme.skyLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(hasHome ? "Edit" : "Set",
                    style: const TextStyle(color: AdminTheme.skyBlue,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }




  // Expand shortened URLs (maps.app.goo.gl) on device — Google allows this from mobile
  Future<String> _resolveUrl(String url) async {
    if (!url.contains('goo.gl') && !url.contains('maps.app')) return url;
    try {
      // http.get follows redirects automatically on mobile
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 10) Chrome/91.0'},
      ).timeout(const Duration(seconds: 8));
      // The final URL after all redirects is in response.request!.url
      return response.request?.url.toString() ?? url;
    } catch (e) {
      return url; // fallback to original if anything fails
    }
  }

  Future<void> _showHomeLocationDialog(dynamic emp) async {
    final ctrl = TextEditingController(text: emp['homeMapsLink'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminTheme.white,
        title: const Text("Home Location",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Paste a Google Maps link for the employee's home address.",
              style: TextStyle(color: AdminTheme.textMuted,
                  fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AdminTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminTheme.border),
              ),
              child: TextField(
                controller: ctrl,
                maxLines: 3,
                style: const TextStyle(
                    color: AdminTheme.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: "https://maps.app.goo.gl/... or full URL",
                  hintStyle: TextStyle(color: AdminTheme.textMuted),
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
                style: TextStyle(color: AdminTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.skyBlue),
            onPressed: () async {
              Navigator.pop(context);
              // Expand short URL on device before sending to backend
              final rawLink   = ctrl.text.trim();
              final fullLink  = await _resolveUrl(rawLink);
              final result = await AdminApiService.updateEmployee(
                emp['_id'].toString(),
                {'homeMapsLink': fullLink},
              );
              if (result != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['homeLocation']?['lat'] != null
                        ? "Home location saved ✓"
                        : "Could not extract coordinates. Try the full Maps URL."),
                    backgroundColor: result['homeLocation']?['lat'] != null
                        ? AdminTheme.success : AdminTheme.warning,
                  ),
                );
                _load();
              }
            },
            child: const Text("Save",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final status       = job['status']      ?? 'Pending';
    final serviceType  = job['serviceType'] ?? '';
    final serviceCount = job['serviceCount'] ?? 0;
    final images          = job['images'];
    final isInterior      = serviceType == 'Interior Standard' ||
                            serviceType == 'Interior Premium';
    final hasAfter        = isInterior
        ? ((images?['interiorAfter'] as List?)?.any((a) => a['url'] != null) == true)
        : ((images?['after'] as List?)?.any((a) => a['url'] != null) == true);
    final hasInteriorBefore = (images?['interiorBefore'] as List?)?.isNotEmpty == true;
    final cancelPhoto     = job['cancelPhotoUrl'] as String?;
    final cancelReason    = job['cancelReason']   as String?;

    // Time tracking
    final beforeRaw    = job['beforeUploadedAt'];
    final completedRaw = job['completedAt'];
    final cancelledRaw = job['cancelledAt'];
    int? minsTaken;
    try {
      final start = beforeRaw != null
          ? DateTime.parse(beforeRaw.toString()) : null;
      final end   = completedRaw != null
          ? DateTime.parse(completedRaw.toString())
          : cancelledRaw != null
              ? DateTime.parse(cancelledRaw.toString()) : null;
      if (start != null && end != null) {
        final diff = end.difference(start).inMinutes;
        if (diff > 0) minsTaken = diff;
      }
    } catch (_) {}

    final customer     = job['customerId'];
    final customerName = customer is Map
        ? customer['customerName'] ?? '' : '';
    final carModel     = customer is Map
        ? customer['carModel'] ?? '' : '';
    final vehicleNo    = customer is Map
        ? customer['vehicleNumber'] ?? '' : '';

    // Complaint state
    final complaint    = job['complaint'] as Map<String, dynamic>?;
    final hasComplaint = complaint?['raised']  == true;
    final isResolved   = complaint?['resolved'] == true;
    final canComplain  = status == 'Completed';

    final canShare = (status == 'Completed' &&
                        (hasAfter || hasInteriorBefore)) ||
                     (status == 'Cancelled' && cancelPhoto != null);

    return GestureDetector(
      onTap: () {
        if (customer is Map) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(
                customer: Map<String, dynamic>.from(customer)),
          )).then((_) => _load());
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasComplaint && !isResolved
                ? Colors.red.withOpacity(0.4)
                : AdminTheme.statusColor(status).withOpacity(0.25),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(children: [

          // Complaint banner
          if (hasComplaint && !isResolved)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(children: [
                const Icon(Icons.report_problem_rounded,
                    color: Colors.red, size: 13),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  "Complaint: ${complaint?['reason'] ?? ''}",
                  style: const TextStyle(color: Colors.red,
                      fontWeight: FontWeight.w700, fontSize: 11),
                )),
              ]),
            ),

          if (hasComplaint && isResolved)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AdminTheme.success, size: 13),
                const SizedBox(width: 6),
                Text(
                  "Resolved · ${complaint?['reason'] ?? ''}",
                  style: const TextStyle(color: AdminTheme.success,
                      fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ]),
            ),

          // Cancel reason banner
          if (status == 'Cancelled' && cancelReason != null && cancelReason.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(children: [
                const Icon(Icons.cancel_outlined, color: Colors.red, size: 13),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  "Cancelled: $cancelReason",
                  style: const TextStyle(color: Colors.red,
                      fontWeight: FontWeight.w700, fontSize: 11),
                )),
              ]),
            ),

          // Job row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Car icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AdminTheme.statusBg(status),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.directions_car_rounded,
                        color: AdminTheme.statusColor(status), size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Name + details
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status badge on its own line at top right
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(customerName,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                    color: AdminTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AdminTheme.statusBg(status),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(status,
                                style: TextStyle(
                                    color: AdminTheme.statusColor(status),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text("$carModel · $vehicleNo",
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                              color: AdminTheme.textMuted, fontSize: 11)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AdminTheme.skyLight,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(serviceType,
                              style: const TextStyle(
                                  color: AdminTheme.skyBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (serviceCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AdminTheme.skyLight,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("#$serviceCount",
                                style: const TextStyle(
                                    color: AdminTheme.skyDark,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                        if (hasAfter) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.photo_library_rounded,
                              color: AdminTheme.skyBlue, size: 12),
                          const SizedBox(width: 3),
                          const Text("Photos",
                              style: TextStyle(color: AdminTheme.skyBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                        if (minsTaken != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AdminTheme.successLight,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("⏱ ${minsTaken}m",
                                style: const TextStyle(
                                    color: AdminTheme.success,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                    ],
                  )),
                ]),

                // Share button — full width row below if available
                if (canShare) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _sharingJobId == job['_id'] ? null : () async {
                      setState(() => _sharingJobId = job['_id']);
                      try {
                        final c = job['customerId'];
                        await JobShareService.shareJobPhotos(
                          job: job,
                          customer: c is Map
                              ? Map<String, dynamic>.from(c) : {},
                        );
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                                content: Text("Share failed: $e")));
                      } finally {
                        if (mounted) setState(() => _sharingJobId = null);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: status == 'Cancelled'
                            ? const Color(0xFFFEF2F2)
                            : AdminTheme.skyLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: status == 'Cancelled'
                              ? Colors.red.withOpacity(0.2)
                              : AdminTheme.skyBlue.withOpacity(0.2),
                        ),
                      ),
                      child: _sharingJobId == job['_id']
                          ? Row(mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                        color: AdminTheme.skyBlue,
                                        strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text("Preparing...",
                                    style: TextStyle(
                                        color: AdminTheme.skyBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ])
                          : Row(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.share_rounded,
                                    color: status == 'Cancelled'
                                        ? Colors.red : AdminTheme.skyBlue,
                                    size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  status == 'Cancelled'
                                      ? "Share Cancel Info"
                                      : "Share Work Photos",
                                  style: TextStyle(
                                      color: status == 'Cancelled'
                                          ? Colors.red : AdminTheme.skyBlue,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Complaint action + Revert + Reassign
          if (canComplain || status == 'In Progress' || status == 'Completed') ...[
            const Divider(height: 1, color: AdminTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(children: [

                // ── Complaint row ────────────────────────────────────────
                if (canComplain)
                  GestureDetector(
                    onTap: hasComplaint && !isResolved
                        ? () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AdminTheme.white,
                                title: const Text("Resolve Complaint",
                                    style: TextStyle(color: AdminTheme.textPrimary,
                                        fontWeight: FontWeight.w800)),
                                content: const Text(
                                    "Mark as resolved? Service count and salary will be restored.",
                                    style: TextStyle(
                                        color: AdminTheme.textMuted, height: 1.4)),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text("Cancel")),
                                  TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text("Resolve",
                                          style: TextStyle(
                                              color: AdminTheme.success,
                                              fontWeight: FontWeight.w700))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final r = await AdminApiService.resolveComplaint(
                                  job['_id'].toString());
                              if (r != null) _load();
                            }
                          }
                        : !hasComplaint
                            ? () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => ComplaintSheet(
                                    jobId:        job['_id'].toString(),
                                    customerName: customerName,
                                    onDone:       _load,
                                  ),
                                )
                            : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  ? AdminTheme.success.withOpacity(0.4)
                                  : AdminTheme.warning.withOpacity(0.4),
                        ),
                      ),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Icon(
                            hasComplaint && !isResolved
                                ? Icons.check_circle_outline_rounded
                                : isResolved
                                    ? Icons.verified_rounded
                                    : Icons.report_problem_rounded,
                            color: hasComplaint && !isResolved
                                ? Colors.red
                                : isResolved
                                    ? AdminTheme.success
                                    : AdminTheme.warning,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasComplaint && !isResolved
                                ? "Resolve Complaint"
                                : isResolved
                                    ? "Complaint Resolved"
                                    : "Raise Complaint",
                            style: TextStyle(
                                color: hasComplaint && !isResolved
                                    ? Colors.red
                                    : isResolved
                                        ? AdminTheme.success
                                        : AdminTheme.warning,
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ]),
                        // Show resolvedBy if resolved
                        if (isResolved &&
                            (complaint?['resolvedBy'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Resolved by ${complaint!['resolvedBy']}",
                            style: const TextStyle(
                                color: AdminTheme.success,
                                fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ]),
                    ),
                  ),

                // ── Reassign button (unresolved complaint only) ───────────
                if (hasComplaint && !isResolved) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showReassignSheet(context, job),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AdminTheme.skyLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AdminTheme.skyBlue.withOpacity(0.4)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                        Icon(Icons.swap_horiz_rounded,
                            color: AdminTheme.skyBlue, size: 16),
                        SizedBox(width: 6),
                        Text("Reassign to Another Employee",
                            style: TextStyle(
                                color: AdminTheme.skyBlue,
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ],

                // ── Revert button (In Progress or Completed, no complaint) ─
                if (!hasComplaint &&
                    (status == 'In Progress' || status == 'Completed')) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _confirmRevert(context, job),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AdminTheme.warning.withOpacity(0.4)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                        Icon(Icons.undo_rounded,
                            color: AdminTheme.warning, size: 16),
                        SizedBox(width: 6),
                        Text("Revert to Pending",
                            style: TextStyle(
                                color: AdminTheme.warning,
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ],

              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _confirmRevert(
      BuildContext context, Map<String, dynamic> job) async {
    final status = job['status'] ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminTheme.white,
        title: const Text("Revert to Pending",
            style: TextStyle(
                color: AdminTheme.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
          status == 'Completed'
              ? "This will clear all photos and reset status to Pending. Service count will be decremented. This cannot be undone."
              : "This will clear all photos and reset status to Pending. This cannot be undone.",
          style: const TextStyle(color: AdminTheme.textMuted, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Revert",
                  style: TextStyle(
                      color: AdminTheme.warning,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm == true) {
      final r = await AdminApiService.revertJob(job['_id'].toString());
      if (r != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Job reverted to Pending ✓")));
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Revert failed. Try again.")));
      }
    }
  }

  Future<void> _showReassignSheet(
      BuildContext context, Map<String, dynamic> job) async {
    // Fetch all active employees
    final employees = await AdminApiService.getEmployees();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReassignSheet(
        job:       job,
        employees: employees,
        onDone:    _load,
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Center(child: Column(children: [
        const Icon(Icons.inbox_rounded, color: AdminTheme.textMuted, size: 40),
        const SizedBox(height: 10),
        Text(msg, style: const TextStyle(
            color: AdminTheme.textMuted, fontSize: 13)),
      ])),
    );
  }

  Widget _buildPhotoError(double w, double h) {
    return Container(width: w, height: h,
        color: AdminTheme.border,
        child: const Icon(Icons.broken_image_rounded,
            color: AdminTheme.textMuted));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTENDANCE SECTION — standalone StatefulWidget (avoids StatefulBuilder reset bug)
// ═══════════════════════════════════════════════════════════════════════════

class AttendanceSection extends StatefulWidget {
  final String employeeId;
  const AttendanceSection({Key? key, required this.employeeId}) : super(key: key);

  @override
  State<AttendanceSection> createState() => _AttendanceSectionState();
}

class _AttendanceSectionState extends State<AttendanceSection> {

  // Returns YYYY-MM-DD in device local time (not UTC)
  static String _localDateString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _selectedDate = _localDateString(DateTime.now());
  Map<String, dynamic>? _att;
  bool _loading  = true;
  bool _excusing = false;

  // Local approval states (optimistic UI)
  String _selfieApproval     = 'pending';
  String _towelsApproval     = 'pending';
  String _soakApproval       = 'pending';
  String _dusterApproval     = 'pending';
  bool   _incentiveExcused   = false;
  Map<String, dynamic>? _incentive;

  bool get _isSaturday =>
      DateTime.parse(_selectedDate).weekday == DateTime.saturday;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.red, size: 22),
          const SizedBox(width: 10),
          const Text("Reset Day",
              style: TextStyle(color: Colors.red,
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        content: Text(
          "This will permanently delete:\n\n"
          "• All jobs on $_selectedDate\n"
          "• Attendance (selfie + towels + soak)\n"
          "• Customer service counts restored\n\n"
          "This cannot be undone.",
          style: const TextStyle(color: AdminTheme.textPrimary,
              fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text("Cancel",
                style: TextStyle(color: AdminTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2)),
            child: const Text("Delete Everything",
                style: TextStyle(color: Colors.red,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resetDay();
  }

  Future<void> _resetDay() async {
    setState(() => _loading = true);
    final result = await AdminApiService.resetDay(
        widget.employeeId, _selectedDate);
    if (!mounted) return;
    if (result != null && result['success'] == true) {
      final jobs    = result['jobsDeleted']           ?? 0;
      final att     = result['attendanceReset'] == true ? 'yes' : 'no';
      final counts  = result['serviceCountsRestored'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "$jobs job${jobs == 1 ? '' : 's'} deleted · "
            "Attendance reset: $att · "
            "$counts count${counts == 1 ? '' : 's'} restored"),
        backgroundColor: AdminTheme.success,
        duration: const Duration(seconds: 4),
      ));
      await _fetch(); // refresh attendance section
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Reset failed. Try again."),
        backgroundColor: Colors.red,
      ));
      setState(() => _loading = false);
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getAttendance(
        widget.employeeId, _selectedDate);
    if (!mounted) return;
    setState(() {
      _att               = data;
      _loading           = false;
      _selfieApproval    = data?['selfieApproval']     ?? 'pending';
      _towelsApproval    = data?['towelsApproval']     ?? 'pending';
      _soakApproval      = data?['towelSoakApproval']  ?? 'pending';
      _dusterApproval    = data?['dusterSoakApproval'] ?? 'pending';
      _incentiveExcused  = data?['incentiveExcused']   == true;
      _incentive         = data?['incentive'] as Map<String, dynamic>?;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AdminTheme.skyBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _selectedDate = _localDateString(picked);
      _fetch();
    }
  }

  Future<void> _doApprove(String type, String status) async {
    final ok = await AdminApiService.approveAttendance(
        widget.employeeId, _selectedDate, type, status);
    if (ok && mounted) {
      setState(() {
        if (type == 'selfie')     _selfieApproval  = status;
        if (type == 'towels')     _towelsApproval  = status;
        if (type == 'towelSoak')  _soakApproval    = status;
        if (type == 'dusterSoak') _dusterApproval  = status;
      });
      // Refresh incentive status after approval change
      final data = await AdminApiService.getAttendance(
          widget.employeeId, _selectedDate);
      if (mounted) setState(() => _incentive = data?['incentive']);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${_label(type)} $status"),
        backgroundColor:
            status == 'approved' ? AdminTheme.success : Colors.red,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _doExcuse(bool excused) async {
    setState(() => _excusing = true);
    final ok = await AdminApiService.excuseAttendance(
        widget.employeeId, _selectedDate, excused: excused);
    if (ok && mounted) {
      // Immediately reflect locally so UI doesn't lag
      setState(() {
        _incentiveExcused = excused;
        if (_incentive != null) {
          _incentive = {
            ..._incentive!,
            'excused': excused,
            'earned':  excused ? true : false,
            'reasons': excused ? [] : _incentive!['reasons'],
          };
        }
      });
      // Then re-fetch authoritative data from backend
      final data = await AdminApiService.getAttendance(
          widget.employeeId, _selectedDate);
      if (mounted) setState(() {
        _incentive = data?['incentive'];
        _excusing  = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(excused ? "Excuse pass granted ✓" : "Excuse pass removed"),
        backgroundColor: excused ? AdminTheme.success : AdminTheme.textMuted,
        duration: const Duration(seconds: 2),
      ));
    } else {
      if (mounted) setState(() => _excusing = false);
    }
  }

  String _label(String type) {
    switch (type) {
      case 'selfie':     return 'Selfie';
      case 'towels':     return 'Towels';
      case 'towelSoak':  return 'Towel Soak';
      case 'dusterSoak': return 'Duster Soak';
      default:           return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfieUrl          = _att?['selfieUrl']          as String?;
    final selfieUploadedAtRaw= _att?['selfieUploadedAt'];
    final towelUrls     = (_att?['towelUrls']    as List?)?.cast<String>() ?? [];
    final towelSoakUrl  = _att?['towelSoakUrl']  as String?;
    final dusterSoakUrl = _att?['dusterSoakUrl'] as String?;
    final hasData       = selfieUrl != null ||
                          towelUrls.isNotEmpty ||
                          towelSoakUrl != null ||
                          dusterSoakUrl != null;

    // Parse login time (selfieUploadedAt → AM/PM string)
    String? loginTimeStr;
    if (selfieUploadedAtRaw != null) {
      try {
        final dt  = DateTime.parse(selfieUploadedAtRaw.toString()).toLocal();
        final h12 = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
        final ampm= dt.hour < 12 ? 'AM' : 'PM';
        final m   = dt.minute.toString().padLeft(2, '0');
        loginTimeStr = '$h12:$m $ampm';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header + date picker ──────────────────────────────────────────
        Row(children: [
          Container(width: 3, height: 18,
              decoration: BoxDecoration(color: AdminTheme.skyBlue,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          const Text("Attendance",
              style: TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AdminTheme.skyLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminTheme.skyBlue.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AdminTheme.skyBlue, size: 13),
                const SizedBox(width: 6),
                Text(_selectedDate,
                    style: const TextStyle(color: AdminTheme.skyBlue,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _fetch,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AdminTheme.skyLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AdminTheme.skyBlue, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          // Reset button — testing only
          GestureDetector(
            onTap: _confirmReset,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: Colors.red, size: 16),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // ── Content ───────────────────────────────────────────────────────
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: AdminTheme.skyBlue)),
          ))
        else if (!hasData)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminTheme.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: AdminTheme.textMuted, size: 16),
              const SizedBox(width: 8),
              Text("No attendance recorded for $_selectedDate",
                  style: const TextStyle(color: AdminTheme.textMuted,
                      fontSize: 12)),
            ]),
          )
        else ...[
          // ── SELFIE ────────────────────────────────────────────────────
          if (selfieUrl != null) ...[
            _buildPhotoBlock(
              label: "Selfie",
              icon: Icons.face_rounded,
              approval: _selfieApproval,
              onApprove: () => _doApprove('selfie', 'approved'),
              onReject:  () => _doApprove('selfie', 'rejected'),
              onReset:   () => _doApprove('selfie', 'pending'),
              child: GestureDetector(
                onTap: () => _viewFullscreen(selfieUrl, "Selfie"),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(selfieUrl,
                      height: 110, width: 110, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(110, 110),
                      loadingBuilder: (_, child, p) =>
                          p == null ? child : _placeholder(110, 110)),
                ),
              ),
            ),
            if (loginTimeStr != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.login_rounded,
                    color: AdminTheme.skyBlue, size: 14),
                const SizedBox(width: 6),
                Text("Login time: $loginTimeStr",
                    style: const TextStyle(
                        color: AdminTheme.skyBlue,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ],
            const SizedBox(height: 12),
          ],

          // ── TOWELS ────────────────────────────────────────────────────
          if (towelUrls.isNotEmpty) ...[
            _buildPhotoBlock(
              label: "Towels (${towelUrls.length})",
              icon: Icons.water_drop_rounded,
              approval: _towelsApproval,
              onApprove: () => _doApprove('towels', 'approved'),
              onReject:  () => _doApprove('towels', 'rejected'),
              onReset:   () => _doApprove('towels', 'pending'),
              child: SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: towelUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _viewFullscreen(towelUrls[i], "Towel ${i + 1}"),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(children: [
                        Image.network(towelUrls[i],
                            width: 82, height: 82, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(82, 82),
                            loadingBuilder: (_, child, p) =>
                                p == null ? child : _placeholder(82, 82)),
                        Positioned(top: 4, left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black54,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text("T${i + 1}",
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── TOWEL SOAK ────────────────────────────────────────────────
          if (towelSoakUrl != null) ...[
            _buildPhotoBlock(
              label: "Towel Soak",
              icon: Icons.opacity_rounded,
              approval: _soakApproval,
              onApprove: () => _doApprove('towelSoak', 'approved'),
              onReject:  () => _doApprove('towelSoak', 'rejected'),
              onReset:   () => _doApprove('towelSoak', 'pending'),
              child: GestureDetector(
                onTap: () => _viewFullscreen(towelSoakUrl, "Towel Soak"),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(towelSoakUrl,
                      height: 110, width: 110, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(110, 110),
                      loadingBuilder: (_, child, p) =>
                          p == null ? child : _placeholder(110, 110)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── DUSTER SOAK (Saturdays) ───────────────────────────────────
          if (_isSaturday) ...[
            if (dusterSoakUrl != null)
              _buildPhotoBlock(
                label: "Duster Soak",
                icon: Icons.cleaning_services_rounded,
                approval: _dusterApproval,
                onApprove: () => _doApprove('dusterSoak', 'approved'),
                onReject:  () => _doApprove('dusterSoak', 'rejected'),
                onReset:   () => _doApprove('dusterSoak', 'pending'),
                child: GestureDetector(
                  onTap: () => _viewFullscreen(dusterSoakUrl, "Duster Soak"),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(dusterSoakUrl,
                        height: 110, width: 110, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(110, 110),
                        loadingBuilder: (_, child, p) =>
                            p == null ? child : _placeholder(110, 110)),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.cleaning_services_rounded,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  const Text("Duster soak photo not uploaded (Saturday)",
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ]),
              ),
            const SizedBox(height: 12),
          ],

          // ── INCENTIVE STATUS ──────────────────────────────────────────
          _buildIncentiveBlock(),
        ],
      ]),
    );
  }

  Widget _buildIncentiveBlock() {
    final earned  = _incentive?['earned']  == true;
    final excused = _incentive?['excused'] == true;
    final amount  = _incentive?['amount']  ?? 0;
    final reasons = List<String>.from(_incentive?['reasons'] ?? []);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: earned
            ? AdminTheme.successLight
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: earned
              ? AdminTheme.success.withOpacity(0.3)
              : AdminTheme.warning.withOpacity(0.4),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            earned ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
            color: earned ? AdminTheme.success : AdminTheme.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            earned ? "Incentive Earned — ₹$amount" : "Incentive Not Earned",
            style: TextStyle(
              color: earned ? AdminTheme.success : AdminTheme.warning,
              fontSize: 13, fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Excuse pass button
          GestureDetector(
            onTap: _excusing ? null : () => _doExcuse(!_incentiveExcused),
            child: _excusing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AdminTheme.skyBlue))
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _incentiveExcused
                          ? AdminTheme.successLight
                          : AdminTheme.skyLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _incentiveExcused
                            ? AdminTheme.success.withOpacity(0.4)
                            : AdminTheme.skyBlue.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _incentiveExcused ? "✓ Excused" : "Excuse Pass",
                      style: TextStyle(
                        color: _incentiveExcused
                            ? AdminTheme.success
                            : AdminTheme.skyBlue,
                        fontSize: 11, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ]),
        if (excused) ...[
          const SizedBox(height: 6),
          const Text("Excuse pass granted — incentive awarded regardless",
              style: TextStyle(color: AdminTheme.textMuted, fontSize: 11)),
        ],
        if (!earned && !excused && reasons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6,
            children: reasons.map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Text(_reasonLabel(r),
                  style: const TextStyle(color: Colors.red,
                      fontSize: 10, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  String _reasonLabel(String r) {
    switch (r) {
      case 'selfie':           return 'Selfie not approved';
      case 'towels':           return 'Towels not approved';
      case 'towelSoakMissing': return 'Towel soak missing';
      case 'towelSoak':        return 'Towel soak not approved';
      case 'dusterSoakMissing':return 'Duster soak missing';
      case 'dusterSoak':       return 'Duster soak not approved';
      case 'late':             return 'After 6:15 AM';
      case 'minCars':          return 'Less than 5 cars';
      case 'complaint':        return 'Complaint raised';
      default:                 return r;
    }
  }

  Widget _buildPhotoBlock({
    required String label,
    required IconData icon,
    required String approval,
    required VoidCallback onApprove,
    required VoidCallback onReject,
    required VoidCallback onReset,
    required Widget child,
  }) {
    Color badgeColor;
    Color badgeBg;
    String badgeText;
    IconData badgeIcon;
    switch (approval) {
      case 'approved':
        badgeColor = AdminTheme.success;
        badgeBg    = AdminTheme.successLight;
        badgeText  = "Approved";
        badgeIcon  = Icons.check_circle_rounded;
        break;
      case 'rejected':
        badgeColor = Colors.red;
        badgeBg    = const Color(0xFFFEF2F2);
        badgeText  = "Rejected";
        badgeIcon  = Icons.cancel_rounded;
        break;
      default:
        badgeColor = AdminTheme.textMuted;
        badgeBg    = AdminTheme.border;
        badgeText  = "Pending";
        badgeIcon  = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: approval == 'approved'
              ? AdminTheme.success.withOpacity(0.35)
              : approval == 'rejected'
                  ? Colors.red.withOpacity(0.3)
                  : AdminTheme.border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Label + badge
        Row(children: [
          Icon(icon, color: AdminTheme.skyBlue, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AdminTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: approval != 'pending' ? onReset : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: badgeBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(badgeIcon, color: badgeColor, size: 12),
                const SizedBox(width: 4),
                Text(badgeText, style: TextStyle(color: badgeColor,
                    fontSize: 10, fontWeight: FontWeight.w700)),
                if (approval != 'pending') ...[
                  const SizedBox(width: 4),
                  Icon(Icons.replay_rounded, color: badgeColor, size: 10),
                ],
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Photo
        child,
        const SizedBox(height: 12),

        // Approve / Reject buttons
        if (approval == 'pending')
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onApprove,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AdminTheme.successLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AdminTheme.success.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded,
                          color: AdminTheme.success, size: 16),
                      SizedBox(width: 6),
                      Text("Approve", style: TextStyle(
                          color: AdminTheme.success,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: onReject,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.35)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, color: Colors.red, size: 16),
                      SizedBox(width: 6),
                      Text("Reject", style: TextStyle(color: Colors.red,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ]),
      ]),
    );
  }

  void _viewFullscreen(String url, String label) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(fit: StackFit.expand, children: [
          InteractiveViewer(
            child: Center(
              child: Image.network(url, fit: BoxFit.contain,
                  loadingBuilder: (_, child, p) => p == null ? child
                      : const Center(child: CircularProgressIndicator(
                          color: Colors.white))),
            ),
          ),
          Positioned(top: 48, left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
          Positioned(top: 52, left: 0, right: 0,
            child: Center(child: Text(label,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 15))),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(double w, double h) => Container(
    width: w, height: h, color: AdminTheme.skyLight,
    child: const Center(child: SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2,
            color: AdminTheme.skyBlue))),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// REASSIGN SHEET
// ═══════════════════════════════════════════════════════════════════════════
class _ReassignSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  final List<dynamic>        employees;
  final VoidCallback         onDone;
  const _ReassignSheet({
    required this.job, required this.employees, required this.onDone});
  @override State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  bool _loading = false;

  Future<void> _reassign(Map<String, dynamic> employee) async {
    setState(() => _loading = true);
    final result = await AdminApiService.reassignJob(
        widget.job['_id'].toString(),
        employee['_id'].toString());
    if (!mounted) return;
    setState(() => _loading = false);
    if (result != null) {
      Navigator.pop(context);
      widget.onDone();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Reassigned to ${employee['name']} ✓")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reassign failed. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerName = (widget.job['customerId'] is Map)
        ? widget.job['customerId']['customerName'] ?? ''
        : '';
    return Container(
      decoration: const BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        // Title
        Text("Reassign — $customerName",
            style: const TextStyle(color: AdminTheme.textPrimary,
                fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text("Select employee to reassign this job to",
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: AdminTheme.skyBlue),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.employees.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AdminTheme.border),
              itemBuilder: (_, i) {
                final emp  = widget.employees[i] as Map<String, dynamic>;
                final name = emp['name'] ?? '';
                final isActive = emp['isActive'] == true;
                return ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: isActive
                            ? AdminTheme.successLight
                            : AdminTheme.skyLight,
                        shape: BoxShape.circle),
                    child: Center(child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                          color: isActive
                              ? AdminTheme.success : AdminTheme.skyBlue,
                          fontWeight: FontWeight.w800, fontSize: 16),
                    )),
                  ),
                  title: Text(name,
                      style: const TextStyle(
                          color: AdminTheme.textPrimary,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(
                    isActive ? "Active today" : "Not active today",
                    style: TextStyle(
                        color: isActive
                            ? AdminTheme.success : AdminTheme.textMuted,
                        fontSize: 11),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded,
                      color: AdminTheme.textMuted, size: 14),
                  onTap: () => _reassign(emp),
                );
              },
            ),
          ),
      ]),
    );
  }
}