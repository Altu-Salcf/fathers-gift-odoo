import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://testerp.dmu.ae:5002';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Helper method for headers
  Future<Map<String, String>> _headers({bool requiresAuth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (requiresAuth) {
      final token = await _storage.read(key: 'auth_token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token'; // The user requested Bearer token
      }
    }
    return headers;
  }

  /// Login API
  /// Returns a Map with token and potentially user info
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/login'),
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
      

      
      if (data['student_id'] != null) {
        await _storage.write(key: 'user_id', value: data['student_id'].toString());
      }
      if (data['wallet_nfc'] != null) {
        await _storage.write(key: 'wallet_nfc', value: data['wallet_nfc'].toString());
      }
      if (data['wallet_id'] != null) {
        await _storage.write(key: 'wallet_id', value: data['wallet_id'].toString());
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
      Uri.parse('$baseUrl/api/mobile/balance'),
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
      Uri.parse('$baseUrl/api/mobile/transactions'),
      headers: await _headers(requiresAuth: true),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get transactions: ${response.statusCode} - ${response.body}');
    }
  }


  /// Logout - clears local storage
  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'wallet_nfc');
    await _storage.delete(key: 'user_name');
    await _storage.delete(key: 'wallet_id');
  }
}
