import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'admin_login_screen.dart';
import 'employee_detail_screen.dart';
import 'employees_screen.dart';
import 'customers_screen.dart';
import 'admin_salary_screen.dart';
import 'admin_config_screen.dart';
import 'admin_planner_screen.dart';
import 'interior_screen.dart';
import 'invoice_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> admin;
  const AdminDashboardScreen({Key? key, required this.admin}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<dynamic> _employees = [];
  bool _loading = true;
  Timer? _refreshTimer;
  int _selectedTab = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _load();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await AdminApiService.getDashboard();
    if (mounted) setState(() { _employees = data; _loading = false; });
  }

  int get _totalActive    => _employees.where((e) => e['isActive'] == true).length;
  int get _totalToday     => _employees.fold(0, (s, e) => s + (e['totalToday'] as int? ?? 0));
  int get _totalCompleted => _employees.fold(0, (s, e) => s + (e['completed'] as int? ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AdminTheme.bg,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminTheme.skyBlue))
          : RefreshIndicator(
              onRefresh: _load,
              color: AdminTheme.skyBlue,
              child: _buildBody(),
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AdminTheme.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded, color: AdminTheme.textPrimary),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Laundoor Admin",
              style: TextStyle(color: AdminTheme.textPrimary,
                  fontSize: 17, fontWeight: FontWeight.w800)),
          Text("Welcome, ${widget.admin['name']}",
              style: const TextStyle(
                  color: AdminTheme.textMuted, fontSize: 11)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AdminTheme.skyBlue),
          onPressed: _load,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AdminTheme.border),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildSectionHeader("Today's Employees",
              "${_employees.length} staff"),
          const SizedBox(height: 14),
          ..._employees.map((e) => _buildEmployeeCard(e)).toList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        _buildStatCard("Active", "$_totalActive",
            Icons.person_rounded, AdminTheme.success, AdminTheme.successLight),
        _buildStatCard("Jobs Today", "$_totalToday",
            Icons.directions_car_rounded, AdminTheme.skyBlue, AdminTheme.skyLight),
        _buildStatCard("Completed", "$_totalCompleted",
            Icons.check_circle_rounded, AdminTheme.warning, AdminTheme.warningLight),
      ],
    );
  }

  Widget _buildStatCard(String title, String value,
      IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(
              color: AdminTheme.textPrimary,
              fontSize: 20, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(
              color: AdminTheme.textMuted, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String sub) {
    return Row(
      children: [
        Container(width: 3, height: 20,
            decoration: BoxDecoration(
                color: AdminTheme.skyBlue,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(
            color: AdminTheme.textPrimary,
            fontSize: 15, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(sub, style: const TextStyle(
            color: AdminTheme.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    final isActive = emp['isActive'] == true;
    final total    = emp['totalToday'] ?? 0;
    final pending  = emp['pending'] ?? 0;
    final progress = emp['inProgress'] ?? 0;
    final done     = emp['completed'] ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => EmployeeDetailScreen(employeeId: emp['_id'],
              employeeName: emp['name']))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? AdminTheme.success.withOpacity(0.3)
                : AdminTheme.border,
          ),
          boxShadow: [BoxShadow(
              color: isActive
                  ? AdminTheme.success.withOpacity(0.06)
                  : Colors.black.withOpacity(0.03),
              blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AdminTheme.successLight
                        : AdminTheme.skyLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      emp['name'][0].toUpperCase(),
                      style: TextStyle(
                          color: isActive
                              ? AdminTheme.success
                              : AdminTheme.skyBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp['name'],
                          style: const TextStyle(
                              color: AdminTheme.textPrimary,
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(emp['email'],
                          style: const TextStyle(
                              color: AdminTheme.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
                // Active badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AdminTheme.successLight
                        : AdminTheme.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AdminTheme.success
                              : AdminTheme.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isActive ? "Active" : "Inactive",
                        style: TextStyle(
                            color: isActive
                                ? AdminTheme.success
                                : AdminTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (total > 0) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildMiniStat("Total", "$total", AdminTheme.textMuted),
                  _buildMiniStat("Pending", "$pending", AdminTheme.warning),
                  _buildMiniStat("In Progress", "$progress", AdminTheme.skyBlue),
                  _buildMiniStat("Done", "$done", AdminTheme.success),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(
              color: AdminTheme.textMuted, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AdminTheme.white,
      child: SafeArea(
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF38B6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(
                  (widget.admin['name'] as String? ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.w900),
                )),
              ),
              const SizedBox(height: 12),
              Text(widget.admin['name'] ?? 'Admin',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const Text("Administrator",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          _drawerItem(Icons.directions_car_rounded, "Customers", () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const CustomersScreen()));
          }),
          _drawerItem(Icons.cleaning_services_rounded, "Interior Checklist", () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const InteriorScreen()));
          }),
          _drawerItem(Icons.receipt_long_rounded, "Invoices", () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const InvoiceScreen()));
          }),
          _drawerItem(Icons.tune_rounded, "Config", () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AdminConfigScreen()));
          }),
          const Spacer(),
          const Divider(color: AdminTheme.border),
          _drawerItem(Icons.logout_rounded, "Logout", () async {
            Navigator.pop(context);
            await AdminApiService.logout();
            if (mounted) Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
          }, color: Colors.red),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label,
      VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color != null
                ? Colors.red.withOpacity(0.1)
                : AdminTheme.skyLight,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color ?? AdminTheme.skyBlue, size: 20),
      ),
      title: Text(label, style: TextStyle(
          color: color ?? AdminTheme.textPrimary,
          fontWeight: FontWeight.w700, fontSize: 14)),
      onTap: onTap,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.white,
        border: Border(top: BorderSide(color: AdminTheme.border)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded,      "Dashboard"),
              _buildNavItem(1, Icons.people_rounded,         "Employees"),
              _buildNavItem(3, Icons.calendar_month_rounded, "Planner"),
              _buildNavItem(4, Icons.payments_rounded,       "Salary"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final active = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        if (index == 1) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const EmployeesScreen()));
        } else if (index == 3) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminPlannerScreen()));
        } else if (index == 4) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminSalaryScreen()));
        }
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            color: active ? AdminTheme.skyBlue : AdminTheme.textMuted,
            size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(
            color: active ? AdminTheme.skyBlue : AdminTheme.textMuted,
            fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}