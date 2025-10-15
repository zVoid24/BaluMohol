import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/auth_storage.dart';

class AuthProvider with ChangeNotifier {
  AuthProvider() {
    _restoreSession();
  }

  String? _token;
  Map<String, dynamic>? _user;
  bool _isRestoringSession = true;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isRestoringSession => _isRestoringSession;

  Future<void> _restoreSession() async {
    final savedToken = await AuthStorage.getToken();
    if (savedToken != null) {
      _token = savedToken;
    }
    _isRestoringSession = false;
    notifyListeners();
  }

  final String baseUrl = "http://192.168.68.133:8080/api/auth";

  Future<bool> login({
    String? email,
    String? username,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/login");
    final body = jsonEncode({
      "email": email,
      "username": username,
      "password": password,
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _token = data["token"];
      _user = data["user"];
      await AuthStorage.saveToken(_token!);
      if (_isRestoringSession) {
        _isRestoringSession = false;
      }
      notifyListeners();
      return true;
    } else {
      debugPrint("Login failed: ${response.body}");
      return false;
    }
  }

  Future<bool> signup({
    required String email,
    required String username,
    required String name,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/register");
    final body = jsonEncode({
      "email": email,
      "username": username,
      "name": name,
      "password": password,
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      _token = data["token"];
      _user = data["user"];
      await AuthStorage.saveToken(_token!);
      if (_isRestoringSession) {
        _isRestoringSession = false;
      }
      notifyListeners();
      return true;
    } else {
      debugPrint("Signup failed: ${response.body}");
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await AuthStorage.clearToken();
    if (_isRestoringSession) {
      _isRestoringSession = false;
    }
    notifyListeners();
  }
}
