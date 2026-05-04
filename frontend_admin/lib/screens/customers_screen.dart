import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';
import '../widgets/admin_form_widgets.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({Key? key}) : super(key: key);

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<dynamic> _customers = [];
  List<dynamic> _filtered  = [];
  bool _loading = true;
  final _search = TextEditingController();

  static const Color _bg         = Color(0xFFF4F8FF);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _skyBlue    = Color(0xFF38B6FF);
  static const Color _skyLight   = Color(0xFFE8F5FF);
  static const Color _success    = Color(0xFF22C55E);
  static const Color _textPrimary= Color(0xFF0F172A);
  static const Color _textMuted  = Color(0xFF64748B);
  static const Color _border     = Color(0xFFDDE8F5);

  static const List<String> _carTypes = ['Hatchback', 'Sedan', 'SUV'];
  static const List<String> _interiorTypes = [
    'None', 'Interior Standard', 'Interior Premium'
  ];
  static const List<String> _serviceTypes = [
    'Exterior', 'Interior Standard', 'Interior Premium'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApiService.getCustomers();
    if (mounted) setState(() {
      _customers = data;
      _filtered  = data;
      _loading   = false;
    });
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _customers.where((c) =>
        (c['customerName'] ?? '').toLowerCase().contains(q) ||
        (c['vehicleNumber'] ?? '').toLowerCase().contains(q) ||
        (c['carModel'] ?? '').toLowerCase().contains(q)
      ).toList();
    });
  }

  // ── Create Customer Modal ──────────────────────────────────────────────────
  void _showCreateModal() {
    final name     = TextEditingController();
    final address  = TextEditingController();
    final vehicle  = TextEditingController();
    final color    = TextEditingController();
    final model    = TextEditingController();
    final phone    = TextEditingController();
    final mapsLink = TextEditingController();
    String selectedCarType      = 'Hatchback';
    String selectedInteriorType = 'None';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("New Customer",
                    style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 20),
                modalField(name,    "Customer Name",  Icons.person_outline_rounded),
                const SizedBox(height: 10),
                modalField(address, "Address",        Icons.location_on_outlined),
                const SizedBox(height: 10),
                modalField(vehicle, "Vehicle Number", Icons.pin_outlined),
                const SizedBox(height: 10),
                modalField(color,   "Vehicle Color",  Icons.palette_outlined),
                const SizedBox(height: 10),
                modalField(model,   "Car Model",      Icons.directions_car_outlined),
                const SizedBox(height: 10),
                modalField(phone,   "Phone",          Icons.phone_outlined,
                    type: TextInputType.phone),
                const SizedBox(height: 10),
                modalField(mapsLink, "Google Maps Link (optional)",
                    Icons.map_outlined,
                    type: TextInputType.url),
                const SizedBox(height: 6),
                const Text("Car Type",
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                // Car type selector
                Row(
                  children: _carTypes.map((type) {
                    final selected = selectedCarType == type;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setModal(() => selectedCarType = type),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? _skyBlue : _skyLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? _skyBlue : _border,
                            ),
                          ),
                          child: Text(type,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: selected ? Colors.white : _skyBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text("Interior Service",
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Column(
                  children: _interiorTypes.map((type) {
                    final selected = selectedInteriorType == type;
                    return GestureDetector(
                      onTap: () => setModal(
                          () => selectedInteriorType = type),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? _skyBlue : _skyLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selected ? _skyBlue : _border),
                        ),
                        child: Row(children: [
                          Text(
                            type == 'None' ? '🚫 No interior'
                                : type == 'Interior Standard'
                                    ? '🪑 Interior Standard'
                                    : '✨ Interior Premium',
                            style: TextStyle(
                                color: selected
                                    ? Colors.white : _skyBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final payload = <String, dynamic>{
                      'customerName':  name.text.trim(),
                      'address':       address.text.trim(),
                      'vehicleNumber': vehicle.text.trim(),
                      'vehicleColor':  color.text.trim(),
                      'carModel':      model.text.trim(),
                      'carType':       selectedCarType,
                      'interiorType':  selectedInteriorType,
                      'phone':         phone.text.trim(),
                    };
                    if (mapsLink.text.trim().isNotEmpty) {
                      payload['mapsLink'] = mapsLink.text.trim();
                    }
                    final ok = await AdminApiService.createCustomer(payload);
                    if (ok && mounted) {
                      Navigator.pop(ctx);
                      _load();
                    }
                  },
                  child: primaryButton("Create Customer", false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Assign Modal ───────────────────────────────────────────────────────────
  void _showAssignModal(Map<String, dynamic> customer) async {
    final employees = await AdminApiService.getEmployees();
    if (!mounted) return;

    // Build available service types based on customer's interiorType
    final interiorType = customer['interiorType'] as String? ?? 'None';
    final List<String> availableServices;
    if (interiorType == 'None') {
      availableServices = ['Exterior'];
    } else {
      availableServices = ['Exterior', interiorType];
    }

    String? selectedEmployeeId;
    // Default: first available service type
    String  selectedServiceType = availableServices.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Assign: ${customer['customerName']}",
                  style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A))),
              Text("${customer['carModel']} · ${customer['vehicleNumber']}",
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontSize: 12)),
              const SizedBox(height: 20),

              // Service type selector
              const Text("Service Type",
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Column(
                children: availableServices.map((type) {
                  final selected = selectedServiceType == type;
                  return GestureDetector(
                    onTap: () => setModal(() => selectedServiceType = type),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? _skyBlue : _skyLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected ? _skyBlue : _border),
                      ),
                      child: Text(type,
                          style: TextStyle(
                              color: selected ? Colors.white : _skyBlue,
                              fontWeight: FontWeight.w700)),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              const Text("Assign To",
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 8),

              // Employee list
              ...employees.map((emp) {
                final selected = selectedEmployeeId == emp['_id'];
                return GestureDetector(
                  onTap: () =>
                      setModal(() => selectedEmployeeId = emp['_id']),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? _skyLight : _white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected ? _skyBlue : _border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (emp['isActive'] == true)
                              ? _success : _border,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(emp['name'],
                          style: TextStyle(
                              color: _textPrimary,
                              fontWeight: selected
                                  ? FontWeight.w700 : FontWeight.w500))),
                      Text("${emp['todayJobs'] ?? 0} jobs today",
                          style: const TextStyle(
                              color: _textMuted, fontSize: 11)),
                    ]),
                  ),
                );
              }).toList(),

              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  if (selectedEmployeeId == null) return;
                  final err = await AdminApiService.assignCustomer(
                    customerId:  customer['_id'],
                    employeeId:  selectedEmployeeId!,
                    serviceType: selectedServiceType,
                  );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(err ?? "Assigned successfully"),
                    backgroundColor: err == null ? _success : Colors.red,
                  ));
                },
                child: primaryButton("Assign", false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white, elevation: 0,
        title: const Text("Customers",
            style: TextStyle(color: Color(0xFF0F172A),
                fontSize: 17, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: _skyBlue),
            onPressed: _showCreateModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _skyBlue),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: _white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: "Search by name, vehicle no, model...",
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Color(0xFF64748B)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: _skyBlue))
                : _filtered.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _skyBlue,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _buildCustomerCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> c) {
    final count = c['serviceCount'] ?? 0;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customer: c),
      )).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _skyLight,
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.directions_car_rounded,
                color: _skyBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['customerName'] ?? '',
                  style: const TextStyle(color: _textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text("${c['carModel']} · ${c['vehicleNumber']}",
                  style: const TextStyle(
                      color: _textMuted, fontSize: 11)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: _skyLight,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(c['carType'] ?? 'Hatchback',
                      style: const TextStyle(
                          color: _skyBlue, fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Text("$count service${count == 1 ? '' : 's'}",
                    style: const TextStyle(
                        color: _textMuted, fontSize: 10)),
              ]),
            ],
          )),
          Column(children: [
            IconButton(
              icon: const Icon(Icons.assignment_ind_rounded,
                  color: _skyBlue, size: 22),
              onPressed: () => _showAssignModal(c),
              tooltip: "Assign",
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.people_outline_rounded,
            color: _textMuted, size: 64),
        const SizedBox(height: 16),
        const Text("No customers yet",
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _showCreateModal,
          icon: const Icon(Icons.add_rounded, color: _skyBlue),
          label: const Text("Add first customer",
              style: TextStyle(color: _skyBlue)),
        ),
      ],
    ));
  }
}