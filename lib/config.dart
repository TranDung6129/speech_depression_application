/// Cấu hình đọc lúc build, truyền qua `--dart-define`.
///
/// Ví dụ:
/// ```
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// ```
///
/// Dùng `--dart-define` thay vì file `.env`: giá trị được ghim vào binary lúc
/// biên dịch nên bản debug và bản release không thể vô tình trỏ nhầm nhau,
/// và không có file cấu hình nào bị commit nhầm.
class AppConfig {
  AppConfig._();

  static const String consentVersion = 'v1';

  /// Ghi vào `app_version` trong metadata (mục 5.1). Giữ khớp với
  /// `version` trong pubspec.yaml.
  static const String appVersion = '0.2.0+2';

  /// Địa chỉ API backend.
  /// Mặc định `http://127.0.0.1:8000` hoạt động trực tiếp khi:
  /// - Chạy trên Linux Desktop / Web / iOS simulator
  /// - Cắm cáp USB vào điện thoại thật qua `adb reverse tcp:8000 tcp:8000`
  /// Đối với Android Emulator (nếu không dùng adb reverse): truyền `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'http://127.0.0.1:8000';
  }

  /// Số lần thử lại tối đa cho một bản ghi trước khi đánh dấu thất bại.
  static const int maxUploadAttempts = 6;

  /// Khoảng chờ cơ sở cho backoff luỹ thừa: 2s, 4s, 8s, 16s...
  static const Duration retryBaseDelay = Duration(seconds: 2);

  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
