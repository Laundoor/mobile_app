import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminApiService {
  static const String baseUrl = 'http://api.laundoor.in:5000';

  // ── TOKEN ──────────────────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type':  'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── AUTH ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> login(
      String email, String password) async {
    try {
      print('[AdminApi] Attempting login for $email');
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      print('[AdminApi] Login status: ${res.statusCode}');
      print('[AdminApi] Login body: ${res.body}');

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final user = data['user'] as Map<String, dynamic>?;
      if (user == null) return null;

      final role = user['role']?.toString() ?? '';
      if (role != 'admin') {
        print('[AdminApi] Blocked — not an admin');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_token', data['token'] ?? '');
      await prefs.setString('admin_id',    user['_id']   ?? '');
      await prefs.setString('admin_name',  user['name']  ?? '');
      await prefs.setString('admin_email', user['email'] ?? '');
      return user;
    } catch (e) {
      print('[AdminApi] Login error: $e');
      return null;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    await prefs.remove('admin_id');
    await prefs.remove('admin_name');
    await prefs.remove('admin_email');
  }

  // ── DASHBOARD ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getDashboard() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/dashboard'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] Dashboard error: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[AdminApi] Dashboard error: $e');
    }
    return [];
  }

  // ── EMPLOYEES ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getEmployees() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/employees'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] Employees error: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[AdminApi] Employees error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getEmployee(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/employees/$id'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) {
      print('[AdminApi] GetEmployee error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createEmployeeRaw({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/employees'),
        headers: await _headers(),
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] CreateEmployee error: $e'); }
    return null;
  }

  // Keep old bool version for backward compat (employees_screen still uses it)
  static Future<bool> createEmployee(
      String name, String email, String password) async {
    final result = await createEmployeeRaw(
        name: name, email: email, password: password);
    return result != null;
  }

  static Future<bool> uploadEmployeeDocument({
    required String empId,
    required String docType,
    required File file,
  }) async {
    try {
      final token = await getToken();
      final uri   = Uri.parse('$baseUrl/upload/employee-doc'
          '?empId=$empId&docType=$docType');
      final req   = http.MultipartRequest('POST', uri);
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('image', file.path));
      final res = await req.send().timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (e) {
      print('[AdminApi] uploadEmployeeDocument error: $e');
      return false;
    }
  }

  static Future<bool> deleteEmployee(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/employees/$id'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      print('[AdminApi] DeleteEmployee error: $e');
      return false;
    }
  }

  // Hard reset — deletes all jobs + attendance for an employee on a date
  // Restores customer service counts. Testing use only.
  static Future<Map<String, dynamic>?> resetDay(
      String employeeId, String date) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/reset-day/$employeeId?date=$date'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] resetDay error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> revertJob(String jobId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/jobs/$jobId/revert'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] revertJob error: ${res.statusCode} ${res.body}');
    } catch (e) { print('[AdminApi] revertJob error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> reassignJob(
      String jobId, String employeeId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/jobs/$jobId/reassign'),
        headers: await _headers(),
        body: jsonEncode({'employeeId': employeeId}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] reassignJob error: ${res.statusCode} ${res.body}');
    } catch (e) { print('[AdminApi] reassignJob error: $e'); }
    return null;
  }

  // ── CUSTOMERS ─────────────────────────────────────────────────────────────

  static Future<String?> uploadCustomerPhoto(
      String customerId, File file) async {
    try {
      final token = await getToken();
      final uri   = Uri.parse('$baseUrl/upload/customer-photo'
          '?customerId=$customerId');
      final req   = http.MultipartRequest('POST', uri);
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('image', file.path));
      final res  = await req.send().timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final body = await res.stream.bytesToString();
        return jsonDecode(body)['url'] as String?;
      }
    } catch (e) { print('[AdminApi] uploadCustomerPhoto error: $e'); }
    return null;
  }

  static Future<List<dynamic>> getCustomers() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/customers'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] Customers error: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[AdminApi] Customers error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getCustomer(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/customers/$id'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) {
      print('[AdminApi] GetCustomer error: $e');
    }
    return null;
  }

  // Returns { jobs: [...], monthlyCount: int } for a customer's service history
  static Future<Map<String, dynamic>> getCustomerHistory(
      String customerId, {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/customers/$customerId/history')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return {
          'jobs':    body['jobs']    ?? [],
          'summary': body['summary'] ?? {},
          'month':   body['month']   ?? month,
          'year':    body['year']    ?? year,
        };
      }
      print('[AdminApi] CustomerHistory error: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[AdminApi] CustomerHistory error: $e');
    }
    return { 'jobs': [], 'summary': {}, 'month': month, 'year': year };
  }

  static Future<bool> createCustomer(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/customers'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      print('[AdminApi] CreateCustomer error: $e');
      return false;
    }
  }


  static Future<bool> deleteCustomer(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/customers/$id'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      print('[AdminApi] DeleteCustomer error: $e');
      return false;
    }
  }

  // ── JOBS / ASSIGNMENT ─────────────────────────────────────────────────────

  // Assign customer to employee with service type
  // Returns null on success, error string on failure
  static Future<String?> assignCustomer({
    required String customerId,
    required String employeeId,
    required String serviceType,
    String? assignedDate,
  }) async {
    try {
      final body = <String, String>{
        'customerId':  customerId,
        'employeeId':  employeeId,
        'serviceType': serviceType,
        if (assignedDate != null) 'assignedDate': assignedDate,
      };
      final res = await http.post(
        Uri.parse('$baseUrl/admin/assign'),
        headers: await _headers(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body).toString();
    } catch (e) {
      print('[AdminApi] Assign error: $e');
      return 'Network error';
    }
  }

  // ── ATTENDANCE ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAttendance(
      String employeeId, String date) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/attendance/$employeeId?date=$date'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getAttendance error: $e'); }
    return null;
  }

  // type: 'selfie' | 'towels' | 'towelSoak' | 'dusterSoak'
  // status: 'approved' | 'rejected' | 'pending'
  static Future<bool> approveAttendance(
      String employeeId, String date, String type, String status) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/admin/attendance/$employeeId/approve?date=$date'),
        headers: await _headers(),
        body: jsonEncode({ 'type': type, 'status': status }),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] approveAttendance error: $e'); }
    return false;
  }

  // Excuse pass — grant incentive regardless of criteria
  static Future<bool> excuseAttendance(
      String employeeId, String date, {bool excused = true}) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/admin/attendance/$employeeId/excuse?date=$date'),
        headers: await _headers(),
        body: jsonEncode({ 'excused': excused }),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] excuseAttendance error: $e'); }
    return false;
  }



  static Future<Map<String, dynamic>?> raiseComplaint({
    required String jobId,
    required String reason,
    String? note,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/complaints/$jobId'),
        headers: await _headers(),
        body: jsonEncode({ 'reason': reason, if (note != null) 'note': note }),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] raiseComplaint error: ${res.statusCode} ${res.body}');
    } catch (e) { print('[AdminApi] raiseComplaint error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> resolveComplaint(String jobId) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/complaints/$jobId/resolve'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] resolveComplaint error: ${res.statusCode} ${res.body}');
    } catch (e) { print('[AdminApi] resolveComplaint error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> getEmployeeComplaints(
      String employeeId, int month, int year) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/employees/$employeeId/complaints?month=$month&year=$year'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getEmployeeComplaints error: $e'); }
    return null;
  }



  static Future<List<dynamic>> getPlannerJobs(
      String employeeId, String date) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/planner/$employeeId?date=$date'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getPlannerJobs error: $e'); }
    return [];
  }

  static Future<bool> reorderJobs(List<String> jobIds) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/planner/reorder'),
        headers: await _headers(),
        body: jsonEncode({'jobIds': jobIds}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] reorderJobs error: $e'); return false; }
  }

  static Future<bool> removePlannerJob(String jobId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/planner/$jobId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] removePlannerJob error: $e'); return false; }
  }

  static Future<List<dynamic>> searchCustomers(String query) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/customers?search=${Uri.encodeComponent(query)}'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] searchCustomers error: $e'); }
    return [];
  }


  static Future<String?> reassignCustomer(
      String jobId, String newEmployeeId) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/reassign'),
        headers: await _headers(),
        body: jsonEncode(
            {'jobId': jobId, 'newEmployeeId': newEmployeeId}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return null;
      return res.body;
    } catch (e) {
      print('[AdminApi] Reassign error: $e');
      return 'Network error';
    }
  }

  // ── CONFIG ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPricing() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/config/pricing'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getPricing error: $e'); }
    // Return defaults if fetch fails
    return {
      'exterior': {'Hatchback': 20, 'Sedan': 25, 'SUV': 30},
      'interiorStandard': 40,
      'interiorPremium':  60,
      'distancePerKm':    2,
    };
  }

  static Future<void> savePricing(Map<String, dynamic> pricing) async {
    final res = await http.put(
      Uri.parse('$baseUrl/admin/config/pricing'),
      headers: await _headers(),
      body: jsonEncode(pricing),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception(res.body);
  }

  // ── SALARY ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSalary({
    required String employeeId,
    required int month,
    required int year,
  }) async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/salary/$employeeId?month=$month&year=$year'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception(res.body);
  }

  // ── EMPLOYEE UPDATE ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> updateEmployee(
      String employeeId, Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/employees/$employeeId'),
        headers: await _headers(),
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] updateEmployee error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> updateCustomer(
      String customerId, Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/customers/$customerId'),
        headers: await _headers(),
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] updateCustomer error: $e'); }
    return null;
  }

  // ── INTERIOR CHECKLIST ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getInteriorTodo(
      {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/interior/todo')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getInteriorTodo error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> getInteriorHistory(
      {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/interior/history')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getInteriorHistory error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> getCustomerMonthlyCounts(
      String customerId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/customers/$customerId/monthly-counts'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));
      print('[AdminApi] getCustomerMonthlyCounts status=${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getCustomerMonthlyCounts error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> updateCustomerPricing(
      String customerId, Map<String, dynamic> pricing) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/customers/$customerId/pricing'),
        headers: await _headers(),
        body: jsonEncode(pricing),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] updateCustomerPricing error: ${res.statusCode}');
    } catch (e) { print('[AdminApi] updateCustomerPricing error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> getInvoicePricing() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/config/invoicePricing'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getInvoicePricing error: $e'); }
    return null;
  }

  // ── INVOICE ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getInvoiceList(
      {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/invoice/list')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getInvoiceList error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> computeInvoice(
      String customerId, {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/invoice/compute/$customerId')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] computeInvoice error: ${res.statusCode}');
    } catch (e) { print('[AdminApi] computeInvoice error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> generateInvoice(
      String customerId, {int? month, int? year, double? adjustment}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/invoice/generate/$customerId')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final body = adjustment != null && adjustment != 0
          ? jsonEncode({'adjustment': adjustment})
          : null;
      final res = await http.post(uri,
          headers: await _headers(), body: body)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      print('[AdminApi] generateInvoice error: ${res.statusCode} ${res.body}');
    } catch (e) { print('[AdminApi] generateInvoice error: $e'); }
    return null;
  }

  static Future<bool> markInvoiceCollected(String invoiceId) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/invoice/$invoiceId/mark-collected'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] markInvoiceCollected error: $e'); }
    return false;
  }

  static Future<Map<String, dynamic>?> getInvoiceMetrics(
      {int? month, int? year}) async {
    try {
      final q = <String, String>{};
      if (month != null) q['month'] = month.toString();
      if (year  != null) q['year']  = year.toString();
      final uri = Uri.parse('$baseUrl/admin/invoice/metrics')
          .replace(queryParameters: q.isNotEmpty ? q : null);
      final res = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] getInvoiceMetrics error: $e'); }
    return null;
  }

  static Future<bool> markInvoiceShared(String invoiceId) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/invoice/$invoiceId/mark-shared'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) { print('[AdminApi] markInvoiceShared error: $e'); }
    return false;
  }

  static Future<String?> uploadQrImage(File file, int contactIndex) async {
    try {
      final token = await getToken();
      final uri   = Uri.parse(
          '$baseUrl/upload/qr-image?contactIndex=$contactIndex');
      final req   = http.MultipartRequest('POST', uri);
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('image', file.path));
      final res  = await req.send().timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final body = await res.stream.bytesToString();
        return jsonDecode(body)['url'] as String?;
      }
    } catch (e) { print('[AdminApi] uploadQrImage error: $e'); }
    return null;
  }

  static Future<Map<String, dynamic>?> updateInvoicePricing(
      Map<String, dynamic> pricing) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/config/invoicePricing'),
        headers: await _headers(),
        body: jsonEncode(pricing),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print('[AdminApi] updateInvoicePricing error: $e'); }
    return null;
  }
}