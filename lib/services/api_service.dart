// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // !! Change this to your actual domain !!
  static const String baseUrl = 'https://taxflujo.com/app/public/contractors/api';

  static const _storage      = FlutterSecureStorage();
  static const _tokenKey     = 'jwt_token';
  static const _profileKey   = 'contractor_profile';
  static const _companiesKey = 'contractor_companies';

  // ─── Token & cache ──────────────────────────────────────────────────────────

  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() =>
      _storage.read(key: _tokenKey);

  static Future<bool> isLoggedIn() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  static Future<void> saveProfile(Map<String, dynamic> p) =>
      _storage.write(key: _profileKey, value: jsonEncode(p));

  static Future<Map<String, dynamic>?> getCachedProfile() async {
    final raw = await _storage.read(key: _profileKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> saveCompanies(List<dynamic> companies) =>
      _storage.write(key: _companiesKey, value: jsonEncode(companies));

  static Future<List<dynamic>> getCachedCompanies() async {
    final raw = await _storage.read(key: _companiesKey);
    if (raw == null) return [];
    return jsonDecode(raw) as List<dynamic>;
  }

  static Future<void> clearAll() => _storage.deleteAll();

  // ─── HTTP helpers ────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _handle(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 401) throw UnauthorizedException('Session expired. Please login again.');
    if (!(body['success'] as bool? ?? false)) {
      throw ApiException(body['message'] as String? ?? 'Something went wrong');
    }
    return body['data'];
  }

  // ─── Auth ────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? fcmToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, if (fcmToken != null) 'fcm_token': fcmToken}),
    ).timeout(const Duration(seconds: 15));

    final data = _handle(response) as Map<String, dynamic>;
    await saveToken(data['token'] as String);
    await saveProfile(data['contractor'] as Map<String, dynamic>);
    await saveCompanies(data['companies'] as List<dynamic>? ?? []);
    return data;
  }

  static Future<void> logout() => clearAll();

  // ─── Invoices: list ──────────────────────────────────────────────────────────

  static Future<List<dynamic>> getInvoices({
    String? status,
    int? companyId,
    String? fromDate,
    String? toDate,
    String? search,
  }) async {
    final params = <String, String>{};
    if (status != null)    params['status']     = status;
    if (companyId != null) params['company_id'] = companyId.toString();
    if (fromDate != null)  params['from_date']  = fromDate;
    if (toDate != null)    params['to_date']    = toDate;
    if (search != null)    params['search']     = search;

    final uri = Uri.parse('$baseUrl/invoices.php').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: await _authHeaders()).timeout(const Duration(seconds: 15));
    final data = _handle(response);
    return data as List<dynamic>? ?? [];
  }

  // ─── Invoices: single ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getInvoice(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/invoices.php?id=$id'),
      headers: await _authHeaders(),
    ).timeout(const Duration(seconds: 15));
    return _handle(response) as Map<String, dynamic>;
  }

  // ─── Invoices: generate invoice number ───────────────────────────────────────

  static Future<String> generateInvoiceNumber(int companyId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/invoices.php?action=gen_num&company_id=$companyId'),
      headers: await _authHeaders(),
    ).timeout(const Duration(seconds: 10));
    final data = _handle(response) as Map<String, dynamic>;
    return data['invoice_number'] as String;
  }

  // ─── Invoices: duplicate check ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> checkDuplicate({
    required String checkType,
    int? companyId,
    String? invoiceNumber,
    String? invoiceDate,
    double? totalAmount,
  }) async {
    final params = <String, String>{'action': 'check_dup', 'check_type': checkType};
    if (companyId != null)     params['company_id']     = companyId.toString();
    if (invoiceNumber != null) params['invoice_number'] = invoiceNumber;
    if (invoiceDate != null)   params['invoice_date']   = invoiceDate;
    if (totalAmount != null)   params['total_amount']   = totalAmount.toStringAsFixed(2);

    final uri = Uri.parse('$baseUrl/invoices.php').replace(queryParameters: params);
    final response = await http.get(uri, headers: await _authHeaders()).timeout(const Duration(seconds: 10));
    return _handle(response) as Map<String, dynamic>;
  }

  // ─── Invoices: create ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> createInvoice(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/invoices.php'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    return _handle(response) as Map<String, dynamic>;
  }

  // ─── Invoices: update ────────────────────────────────────────────────────────

  static Future<void> updateInvoice(int id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl/invoices.php?id=$id'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    _handle(response);
  }

  // ─── Invoices: delete ────────────────────────────────────────────────────────

  static Future<void> deleteInvoice(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/invoices.php?id=$id'),
      headers: await _authHeaders(),
    ).timeout(const Duration(seconds: 15));
    _handle(response);
  }

  // ─── Profile ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/profile.php'),
      headers: await _authHeaders(),
    ).timeout(const Duration(seconds: 15));
    return _handle(response) as Map<String, dynamic>;
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl/profile.php'),
      headers: await _authHeaders(),
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    _handle(response);
  }
}

// ─── Exceptions ──────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message);
}
