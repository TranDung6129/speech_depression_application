import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Quản lý phiên đăng nhập.
///
/// Token lưu trong secure storage (Keychain trên iOS, EncryptedSharedPreferences
/// trên Android) chứ không phải `shared_preferences`: đây là thông tin xác thực
/// truy cập dữ liệu sức khoẻ, không phải tuỳ chọn giao diện.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kToken = 'access_token';
  static const _kRole = 'role';

  String? _token;
  String? _role;

  String? get token => _token;
  bool get isSignedIn => _token != null;

  /// Nạp token đã lưu lúc khởi động app.
  Future<void> restore() async {
    _token = await _storage.read(key: _kToken);
    _role = await _storage.read(key: _kRole);
    notifyListeners();
  }

  Future<void> _persist(String token, String role) async {
    _token = token;
    _role = role;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kRole, value: role);
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _role = null;
    await _storage.deleteAll();
    notifyListeners();
  }

  Future<AuthOutcome> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'display_name': displayName,
              'role': 'patient',
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await _persist(
          body['access_token'] as String,
          body['role'] as String,
        );
        return const AuthOutcome.success();
      }

      if (response.statusCode == 409) {
        return const AuthOutcome.failure('Email này đã được đăng ký.');
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Không kết nối được máy chủ. Bạn kiểm tra mạng giúp mình nhé.',
      );
    }
  }

  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Endpoint login dùng OAuth2 password flow nên nhận form-encoded,
      // không phải JSON.
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/login'),
            body: {'username': email, 'password': password},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await _persist(
          body['access_token'] as String,
          body['role'] as String,
        );
        return const AuthOutcome.success();
      }

      if (response.statusCode == 401) {
        return const AuthOutcome.failure('Email hoặc mật khẩu không đúng.');
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Không kết nối được máy chủ. Bạn kiểm tra mạng giúp mình nhé.',
      );
    }
  }

  static String _readDetail(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['detail'] is String) {
        return parsed['detail'] as String;
      }
    } catch (_) {
      // Body không phải JSON — rơi xuống thông báo chung.
    }
    return 'Có lỗi xảy ra. Bạn thử lại sau nhé.';
  }
}

class AuthOutcome {
  final bool ok;
  final String? message;

  const AuthOutcome.success() : ok = true, message = null;
  const AuthOutcome.failure(this.message) : ok = false;
}
