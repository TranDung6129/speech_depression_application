import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'storage_service.dart';
import 'upload_queue.dart';

/// Manages authentication, profile state, and onboarding routing.
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
  bool _profileLoaded = false;

  String? _userId;
  String? _displayName;
  String? _sex;
  int? _birthYear;
  String? _dialectRegion;
  String? _studyCode;
  String? _clinicId;
  String? _consentVersion;
  bool _needsConsent = false;
  bool _profileComplete = false;

  String? get token => _token;

  /// `user_id` ghi vào metadata mỗi file (mục 5.1).
  String? get userId => _userId;
  bool get isSignedIn => _token != null;
  bool get isProfileLoaded => _profileLoaded;
  String get displayName =>
      (_displayName?.trim().isNotEmpty ?? false) ? _displayName!.trim() : 'Your name';
  String? get sex => _sex;
  int? get birthYear => _birthYear;
  String? get dialectRegion => _dialectRegion;
  String? get studyCode => _studyCode;
  String? get clinicId => _clinicId;
  String? get consentVersion => _consentVersion;
  bool get needsConsent => _needsConsent;
  bool get profileComplete => _profileComplete;

  bool get needsOnboarding => isSignedIn && isProfileLoaded && (needsConsent || !profileComplete);

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  Future<void> restore() async {
    _token = await _storage.read(key: _kToken);
    _role = await _storage.read(key: _kRole);
    final pc = await _storage.read(key: 'profile_complete');
    _profileComplete = pc == 'true';
    if (_token == null) {
      _profileLoaded = true;
      notifyListeners();
      return;
    }
    await refreshProfile();
  }

  Future<void> _persist(String token, String role) async {
    _token = token;
    _role = role;
    _profileLoaded = false;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kRole, value: role);
    notifyListeners();
  }

  Future<void> _persistProfileComplete(bool complete) async {
    _profileComplete = complete;
    await _storage.write(key: 'profile_complete', value: complete ? 'true' : 'false');
  }

  Future<void> signOut() async {
    _token = null;
    _role = null;
    await _storage.deleteAll();
    await StorageService.instance.wipeAll();
    await UploadQueue.instance.clearAll();
    _profileLoaded = false;
    _userId = null;
    _displayName = null;
    _sex = null;
    _birthYear = null;
    _dialectRegion = null;
    _studyCode = null;
    _clinicId = null;
    _consentVersion = null;
    _needsConsent = false;
    _profileComplete = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (_token == null) {
      _profileLoaded = true;
      notifyListeners();
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/me'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        _applyProfile(jsonDecode(response.body) as Map<String, dynamic>);
        _profileLoaded = true;
        notifyListeners();
        return;
      }

      if (response.statusCode == 401) {
        await signOut();
        return;
      }
    } catch (_) {
      // Keep the current auth session but allow the app to continue.
    }

    _profileLoaded = true;
    notifyListeners();
  }

  void _applyProfile(Map<String, dynamic> body) {
    _userId = body['id'] as String?;
    _displayName = body['display_name'] as String?;
    _sex = body['sex'] as String?;
    _birthYear = body['birth_year'] as int?;
    _dialectRegion = body['dialect_region'] as String?;
    _studyCode = body['study_code'] as String?;
    _clinicId = body['clinic_id'] as String?;
    _consentVersion = body['consent_version'] as String?;
    _needsConsent = body['needs_consent'] as bool? ?? false;
    
    final pc = body['profile_complete'] as bool? ?? false;
    if (_profileComplete != pc) {
      _persistProfileComplete(pc);
    } else {
      _profileComplete = pc;
    }
  }

  Future<AuthOutcome> register({
    required String email,
    required String password,
    required String displayName,
    required String sex,
    required int birthYear,
    required String consentVersion,
    String? dialectRegion,
    String? inviteCode,
  }) async {
    try {
      final payload = <String, dynamic>{
        'email': email,
        'password': password,
        'display_name': displayName,
        'consent_version': consentVersion,
        'sex': sex,
        'birth_year': birthYear,
      };
      if (dialectRegion != null && dialectRegion.isNotEmpty) {
        payload['dialect_region'] = dialectRegion;
      }
      if (inviteCode != null && inviteCode.trim().isNotEmpty) {
        payload['invite_code'] = inviteCode.trim();
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await StorageService.instance.wipeAll();
        await UploadQueue.instance.clearAll();
        await _persist(
          body['access_token'] as String,
          body['role'] as String,
        );
        await refreshProfile();
        return const AuthOutcome.success();
      }

      if (response.statusCode == 409) {
        return const AuthOutcome.failure('This email is already registered.');
      }

      if (response.statusCode == 422) {
        return _parse422(response.body);
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Unable to reach the server. Please check your connection and try again.',
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
        await StorageService.instance.wipeAll();
        await UploadQueue.instance.clearAll();
        await _persist(
          body['access_token'] as String,
          body['role'] as String,
        );
        await refreshProfile();
        return const AuthOutcome.success();
      }

      if (response.statusCode == 401) {
        return const AuthOutcome.failure('The email or password is incorrect.');
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Unable to reach the server. Please check your connection and try again.',
      );
    }
  }

  Future<ConsentVersionState> checkConsentVersion() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/consent'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return ConsentVersionState.ok;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['version'] == AppConfig.consentVersion
          ? ConsentVersionState.ok
          : ConsentVersionState.mismatch;
    } catch (_) {
      return ConsentVersionState.ok;
    }
  }

  Future<AuthOutcome> acceptConsent() async {
    return updateProfile(consentVersion: AppConfig.consentVersion);
  }

  Future<AuthOutcome> updateProfile({
    String? displayName,
    String? sex,
    int? birthYear,
    String? dialectRegion,
    String? consentVersion,
  }) async {
    final payload = <String, dynamic>{};
    if (displayName != null) payload['display_name'] = displayName.trim();
    if (sex != null) payload['sex'] = sex;
    if (birthYear != null) payload['birth_year'] = birthYear;
    if (dialectRegion != null) payload['dialect_region'] = dialectRegion;
    if (consentVersion != null) payload['consent_version'] = consentVersion;

    if (payload.isEmpty) return const AuthOutcome.success();

    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/me'),
            headers: _authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        _applyProfile(jsonDecode(response.body) as Map<String, dynamic>);
        _profileLoaded = true;
        notifyListeners();
        return const AuthOutcome.success();
      }

      if (response.statusCode == 422) {
        return _parse422(response.body);
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Unable to reach the server. Please check your connection and try again.',
      );
    }
  }

  Future<AuthOutcome> joinClinic(String inviteCode) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/auth/me/clinic'),
            headers: _authHeaders,
            body: jsonEncode({'invite_code': inviteCode}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        _applyProfile(jsonDecode(response.body) as Map<String, dynamic>);
        _profileLoaded = true;
        notifyListeners();
        return const AuthOutcome.success();
      }

      if (response.statusCode == 422) {
        return _parse422(response.body);
      }

      return AuthOutcome.failure(_readDetail(response.body));
    } catch (_) {
      return const AuthOutcome.failure(
        'Unable to reach the server. Please check your connection and try again.',
      );
    }
  }

  static AuthOutcome _parse422(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final detail = parsed['detail'];
        if (detail is String) {
          return AuthOutcome.failure(detail);
        }
        if (detail is List) {
          final fieldErrors = <String, String>{};
          for (final item in detail) {
            if (item is! Map) continue;
            final loc = item['loc'];
            final msg = item['msg'];
            if (loc is List && loc.isNotEmpty && msg is String) {
              final rawField = loc.length > 1 ? loc[1].toString() : loc.last.toString();
              fieldErrors[_normalizeField(rawField)] = msg;
            }
          }
          if (fieldErrors.isNotEmpty) {
            return AuthOutcome.failure(
              'Please fix the highlighted fields.',
              fieldErrors: fieldErrors,
            );
          }
        }
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return const AuthOutcome.failure('Please check the highlighted fields.');
  }

  static String _normalizeField(String field) {
    switch (field) {
      case 'display_name':
      case 'email':
      case 'password':
      case 'consent_version':
      case 'sex':
      case 'birth_year':
      case 'dialect_region':
      case 'invite_code':
        return field;
      default:
        return field;
    }
  }

  static String _readDetail(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['detail'] is String) {
        return parsed['detail'] as String;
      }
    } catch (_) {
      // Body is not JSON — fall through to the generic message.
    }
    return 'Something went wrong. Please try again later.';
  }
  /// Phiên đã nhận trên máy chủ, mới nhất trước. Chỉ có số liệu về việc thu
  /// và cờ chất lượng — schema bệnh nhân không có trường điểm (mục 11).
  Future<List<Map<String, dynamic>>?> fetchSessions() async {
    if (_token == null) return null;
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/v1/sessions'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return null;
  }
}

enum ConsentVersionState { ok, mismatch, error }

class AuthOutcome {
  final bool ok;
  final String? message;
  final Map<String, String> fieldErrors;

  const AuthOutcome.success()
      : ok = true,
        message = null,
        fieldErrors = const {};

  const AuthOutcome.failure(this.message, {this.fieldErrors = const {}})
      : ok = false;
}
