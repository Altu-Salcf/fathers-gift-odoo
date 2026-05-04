import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'http://10.10.131.43:8069/api/mobile';
  static const String baseNfcUrl = 'http://10.10.131.43:5174/api';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Helper method for headers
  Future<Map<String, String>> _headers({bool requiresAuth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (requiresAuth) {
      final token = await _storage.read(key: 'auth_token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token'; // The user requested Bearer token
      }
      final cookie = await _storage.read(key: 'session_cookie');
      if (cookie != null) {
        headers['Cookie'] = cookie;
      }
    }
    return headers;
  }

  /// Login API
  /// Returns a Map with token and potentially user info
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      // Odoo often wraps failure payloads inside 200 OK responses natively
      if (data['status'] != null && data['status'] != 'success') {
        throw Exception(data['message'] ?? 'Odoo responded with a failure status payload.');
      }
      
      final token = data['access_token'];
      if (token != null) {
        await _storage.write(key: 'auth_token', value: token);
      }
      
      final rawCookie = response.headers['set-cookie'];
      if (rawCookie != null) {
        int index = rawCookie.indexOf(';');
        String cookie = (index == -1) ? rawCookie : rawCookie.substring(0, index);
        await _storage.write(key: 'session_cookie', value: cookie);
      }
      
      if (data['student_id'] != null) {
        await _storage.write(key: 'user_id', value: data['student_id'].toString());
      }
      if (data['wallet_nfc'] != null) {
        await _storage.write(key: 'wallet_nfc', value: data['wallet_nfc'].toString());
      }
      if (data['student_name'] != null) {
        await _storage.write(key: 'user_name', value: data['student_name'].toString());
      }
      
      return data;
    } else {
      throw Exception('Network Code ${response.statusCode} | ${response.body}');
    }
  }

  /// Balance API
  /// Updated to use GET and send token via HEADERS
  Future<Map<String, dynamic>> getBalance() async {
    final response = await http.get(
      Uri.parse('$baseUrl/balance'),
      headers: await _headers(requiresAuth: true),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get balance: ${response.statusCode} - ${response.body}');
    }
  }

  /// Transactions API
  /// Updated to use GET and send token via HEADERS
  Future<Map<String, dynamic>> getTransactions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/transactions'),
      headers: await _headers(requiresAuth: true),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get transactions: ${response.statusCode} - ${response.body}');
    }
  }

  /// NFC Tap API
  Future<Map<String, dynamic>> nfcTap(String nfcId) async {
    final response = await http.post(
      Uri.parse('$baseNfcUrl/nfc_tap'),
      headers: await _headers(),
      body: jsonEncode({
        'nfc_id': nfcId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('NFC Tap failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Logout - clears local storage
  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'wallet_nfc');
    await _storage.delete(key: 'user_name');
    await _storage.delete(key: 'session_cookie');
  }
}
