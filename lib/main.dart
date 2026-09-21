import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/upload_queue.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nạp dữ liệu định dạng ngày tháng tiếng Việt trước khi dựng giao diện,
  // nếu không DateFormat(..., 'vi') sẽ ném lỗi ở lần gọi đầu tiên.
  await initializeDateFormatting('vi');

  // Khôi phục phiên đăng nhập đã lưu.
  await AuthService.instance.restore();

  // Chạy lại hàng đợi tải lên: những bản ghi còn kẹt từ lần dùng trước
  // sẽ được gửi đi ngay khi có mạng.
  await UploadQueue.instance.start();

  runApp(const VoiceJournalApp());
}

class VoiceJournalApp extends StatelessWidget {
  const VoiceJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nhật ký giọng nói',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthGate(),
    );
  }
}

/// Chuyển giữa màn đăng nhập và app tuỳ trạng thái phiên.
///
/// Lắng nghe `AuthService` (một `ChangeNotifier`) để khi token hết hạn giữa
/// chừng, app tự quay về màn đăng nhập mà không cần từng màn hình tự kiểm tra.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        if (!AuthService.instance.isSignedIn) {
          return const SignInScreen();
        }
        return const HomeShell();
      },
    );
  }
}
