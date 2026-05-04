import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';
import '../theme/admin_theme.dart';
import 'employee_detail_screen.dart';
import 'create_employee_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({Key? key}) : super(key: key);

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<dynamic> _employees = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final data = await AdminApiService.getEmployees();
    if (mounted) setState(() { _employees = data; _loading = false; });
  }

  void _openCreateScreen() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const CreateEmployeeScreen()));
    if (result == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Employee created ✓"),
              backgroundColor: AdminTheme.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.white, elevation: 0,
        title: const Text("Employees",
            style: TextStyle(color: AdminTheme.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AdminTheme.textMuted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: AdminTheme.skyBlue),
            onPressed: _openCreateScreen,
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
              child: _employees.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _employees.length,
                      itemBuilder: (_, i) => _buildCard(_employees[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AdminTheme.skyBlue,
        onPressed: _openCreateScreen,
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> emp) {
    final isActive = emp['isActive'] == true;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => EmployeeDetailScreen(
              employeeId: emp['_id'], employeeName: emp['name']))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminTheme.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AdminTheme.border),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isActive ? AdminTheme.successLight : AdminTheme.skyLight,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(
                (emp['name'] as String)[0].toUpperCase(),
                style: TextStyle(
                    color: isActive ? AdminTheme.success : AdminTheme.skyBlue,
                    fontWeight: FontWeight.w800, fontSize: 18),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp['name'], style: const TextStyle(
                      color: AdminTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(emp['email'], style: const TextStyle(
                      color: AdminTheme.textMuted, fontSize: 11)),
                  Text(
                    "Today: ${emp['todayCars'] ?? 0} cars",
                    style: const TextStyle(
                        color: AdminTheme.skyBlue,
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AdminTheme.error, size: 20),
              onPressed: () => _confirmDelete(emp),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> emp) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AdminTheme.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Delete Employee",
          style: TextStyle(color: AdminTheme.textPrimary,
              fontWeight: FontWeight.w800)),
      content: Text("Remove ${emp['name']}? This cannot be undone.",
          style: const TextStyle(color: AdminTheme.textMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel",
              style: TextStyle(color: AdminTheme.textMuted)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await AdminApiService.deleteEmployee(emp['_id']);
            _load();
          },
          child: const Text("Delete",
              style: TextStyle(color: AdminTheme.error,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.people_outline_rounded,
            color: AdminTheme.textMuted, size: 56),
        SizedBox(height: 12),
        Text("No employees yet",
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 15)),
        SizedBox(height: 6),
        Text("Tap + to add one",
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12)),
      ],
    ),
  );
}