import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'screens/profile_completion_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/upload_queue.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load English date formatting before building the UI.
  await initializeDateFormatting('en');

  // Restore the saved sign-in session.
  await AuthService.instance.restore();

  // Restart the upload queue: any recordings left pending from a previous session
  // will be sent as soon as the network is available.
  await UploadQueue.instance.start();

  runApp(const VoiceJournalApp());
}

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

class VoiceJournalApp extends StatelessWidget {
  const VoiceJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Voice Journal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          darkTheme: AppTheme.buildDark(), 
          themeMode: currentMode,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthGate(),
        );
      },
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
        final auth = AuthService.instance;

        if (!auth.isSignedIn) {
          return const SignInScreen();
        }
        if (!auth.isProfileLoaded) {
          return const _LoadingScreen();
        }
        if (auth.needsConsent) {
          return const ConsentScreen();
        }
        if (!auth.profileComplete) {
          return const ProfileCompletionScreen();
        }
        return const HomeShell();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
