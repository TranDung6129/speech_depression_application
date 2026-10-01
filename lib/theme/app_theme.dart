import 'package:flutter/material.dart';

/// Hệ màu của app được chia làm hai nhánh có chủ đích:
///
///  - [Warm]  : dùng cho luồng NHẬT KÝ hằng ngày. Ấm, mềm, có nhịp thở.
///  - [Cool]  : dùng cho luồng ĐÁNH GIÁ CHUYÊN SÂU. Mát, có cấu trúc, nghiêm túc hơn.
///
/// Việc tách hai bảng màu là quyết định thiết kế, không phải trang trí:
/// người dùng phải phân biệt được ngay mình đang ở luồng nào.
class AppColors {
  AppColors._();

  // ---- Nền chung ----
  static const Color canvas = Color(0xFFFAFAF8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F2EF);
  static const Color border = Color(0xFFE6E5E0);
  static const Color borderStrong = Color(0xFFD3D1C7);

  // ---- Chữ ----
  static const Color textPrimary = Color(0xFF2B2A27);
  static const Color textSecondary = Color(0xFF6B6459);
  static const Color textMuted = Color(0xFF8A8177);

  // ---- Nhánh ẤM: nhật ký ----
  static const Color warmGradientTop = Color(0xFFFDF6EE);
  static const Color warmGradientMid = Color(0xFFF2F8F3);
  static const Color warmGradientBottom = Color(0xFFE8F4EE);
  static const Color greenDeep = Color(0xFF1D8A66);
  static const Color greenMid = Color(0xFF3FA882);
  static const Color greenSoft = Color(0xFF6FC4A3);
  static const Color greenPale = Color(0xFFA8DCC6);
  static const Color greenTint = Color(0xFFE1F5EE);
  static const Color amberInk = Color(0xFF8A6A38);
  static const Color amberTint = Color(0xFFFAEEDA);

  // ---- Nhánh MÁT: đánh giá chuyên sâu ----
  static const Color coolCanvas = Color(0xFFF7F8FA);
  static const Color coolSurface = Color(0xFFFFFFFF);
  static const Color coolBorder = Color(0xFFE4E8ED);
  static const Color blueDeep = Color(0xFF2F5F82);
  static const Color blueMid = Color(0xFF4A7FA8);
  static const Color blueSoft = Color(0xFF6A99BC);
  static const Color bluePale = Color(0xFF92B4CC);
  static const Color blueTint = Color(0xFFE8F0F6);
  static const Color coolTextPrimary = Color(0xFF2B3038);
  static const Color coolTextSecondary = Color(0xFF6E7480);
  static const Color coolTextMuted = Color(0xFF8A9099);
  static const Color coolTrack = Color(0xFFD5DAE1);

  /// Ba mức rủi ro — CHỈ dùng ở dashboard bác sĩ (web), không bao giờ
  /// hiển thị cho bệnh nhân. Đặt ở đây để hai client dùng chung một hệ màu.
  static const Color riskLow = Color(0xFF639922);
  static const Color riskMedium = Color(0xFFBA7517);
  static const Color riskHigh = Color(0xFFE24B4A);
}

class AppRadius {
  AppRadius._();

  /// Nhật ký: bo tròn hoàn toàn — cảm giác mềm, không góc cạnh.
  static const double pill = 999;
  static const double card = 20;
  static const double screen = 26;

  /// Đánh giá: bo vuông vắn hơn — cảm giác có cấu trúc.
  static const double structuredCard = 20;
  static const double structuredButton = 14;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.greenDeep,
        secondary: AppColors.blueDeep,
        surface: AppColors.surface, surfaceVariant: AppColors.surfaceMuted, outlineVariant: AppColors.border, outline: AppColors.borderStrong, onSurface: AppColors.textPrimary, onSurfaceVariant: AppColors.textSecondary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ).copyWith(
        // Câu hỏi gợi ý — phần tử "nổi bật" của màn nhật ký.
        headlineSmall: const TextStyle(
          fontSize: 21,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: Color(0xFF3D3833),
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.textMuted,
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static ThemeData buildDark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.greenSoft,
        secondary: AppColors.blueSoft,
        surface: const Color(0xFF242424), surfaceVariant: const Color(0xFF303030), outlineVariant: const Color(0xFF424242), outline: const Color(0xFF5A5A5A), onSurface: const Color(0xFFE0E0E0), onSurfaceVariant: const Color(0xFFB0B0B0),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: const Color(0xFFE0E0E0),
        displayColor: const Color(0xFFE0E0E0),
      ).copyWith(
        headlineSmall: const TextStyle(
          fontSize: 21,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: Color(0xFFF5F5F5),
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: const Color(0xFFAAAAAA),
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// Gradient nền của màn nhật ký.
const LinearGradient kJournalGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    AppColors.warmGradientTop,
    AppColors.warmGradientMid,
    AppColors.warmGradientBottom,
  ],
  stops: [0.0, 0.55, 1.0],
);

const LinearGradient kJournalGradientDark = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF2A2621),
    Color(0xFF1E2622),
    Color(0xFF18221D),
  ],
  stops: [0.0, 0.55, 1.0],
);

LinearGradient getJournalGradient(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? kJournalGradientDark
      : kJournalGradient;
}
