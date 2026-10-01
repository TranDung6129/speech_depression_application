import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vòng tròn thở — chỉ dùng ở màn NHẬT KÝ.
///
/// Chu kỳ 4 giây một nhịp, chậm hơn nhịp thở bình thường một chút.
/// Đây là chuyển động duy nhất không do người dùng kích hoạt trong app;
/// mọi hiệu ứng khác đều là phản hồi cho một hành động cụ thể.
class BreathingCircle extends StatefulWidget {
  const BreathingCircle({
    super.key,
    required this.child,
    this.size = 118,
    this.active = true,
  });

  final Widget child;
  final double size;
  final bool active;

  @override
  State<BreathingCircle> createState() => _BreathingCircleState();
}

class _BreathingCircleState extends State<BreathingCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.animateTo(0, duration: const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tôn trọng cài đặt giảm chuyển động của hệ điều hành.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return SizedBox(
      width: widget.size * 1.2,
      height: widget.size * 1.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_controller.value);
                return Container(
                  width: widget.size * (1 + 0.14 * t),
                  height: widget.size * (1 + 0.14 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.greenPale
                            .withValues(alpha: 0.55 - 0.33 * t),
                        AppColors.greenPale.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.72],
                    ),
                  ),
                );
              },
            ),
          Container(
            width: widget.size * 0.78,
            height: widget.size * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Waveform phản hồi biên độ thật từ micro.
///
/// Dùng ở cả hai luồng nhưng khác bảng màu: xanh lá cho nhật ký,
/// xanh dương cho đánh giá chuyên sâu.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({
    super.key,
    required this.levels,
    required this.palette,
    this.barCount = 7,
    this.maxHeight = 46,
    this.barWidth = 3.5,
  });

  /// Lịch sử biên độ gần nhất, mỗi giá trị trong khoảng 0..1.
  final List<double> levels;
  final List<Color> palette;
  final int barCount;
  final double maxHeight;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final bars = <Widget>[];

    for (var i = 0; i < barCount; i++) {
      // Lấy các mẫu gần nhất, cột ngoài cùng bên phải là mới nhất.
      final idx = levels.length - barCount + i;
      final level = (idx >= 0 && idx < levels.length) ? levels[idx] : 0.18;

      // Ép về khoảng nhìn được: cột quá thấp trông như đang hỏng.
      final h = maxHeight * (0.28 + 0.72 * level.clamp(0.0, 1.0));

      bars.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          width: barWidth,
          height: h,
          margin: EdgeInsets.symmetric(horizontal: barWidth * 0.5),
          decoration: BoxDecoration(
            color: palette[i % palette.length],
            borderRadius: BorderRadius.circular(barWidth / 2),
          ),
        ),
      );
    }

    return SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: bars,
      ),
    );
  }

  static const warmPalette = [
    AppColors.greenSoft,
    AppColors.greenMid,
    AppColors.greenDeep,
    AppColors.greenMid,
    AppColors.greenSoft,
    AppColors.greenMid,
    AppColors.greenSoft,
  ];

  static const coolPalette = [
    AppColors.bluePale,
    AppColors.blueSoft,
    AppColors.blueMid,
    AppColors.blueSoft,
    AppColors.bluePale,
  ];
}

/// Dải 7 ngày trong tuần trên màn hình chính.
/// Chỉ hai trạng thái: đã ghi / chưa ghi. Không mã hoá cảm xúc bằng màu.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.recordedDays});

  final Set<DateTime> recordedDays;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        final isFuture = day.isAfter(DateTime(today.year, today.month, today.day));
        final done = recordedDays.contains(day);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppColors.greenSoft
                    : isFuture
                        ? Colors.transparent
                        : AppColors.borderStrong,
                border: isFuture
                    ? Border.all(
                        color: AppColors.borderStrong,
                        width: 1.5,
                        strokeAlign: BorderSide.strokeAlignInside,
                      )
                    : null,
              ),
            ),
            SizedBox(height: 4),
            Text(labels[i],
                style: TextStyle(
                    fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        );
      }),
    );
  }
}

/// Đồng hồ đếm thời lượng, định dạng mm:ss.
String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Vẽ lịch tháng dạng lưới ô vuông cho màn Lịch sử.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.recordedDays,
    this.onTapDay,
  });

  final DateTime month;
  final Set<DateTime> recordedDays;
  final ValueChanged<DateTime>? onTapDay;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;
    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.1,
      ),
      itemCount: leadingBlanks + daysInMonth,
      itemBuilder: (context, index) {
        if (index < leadingBlanks) return const SizedBox.shrink();

        final dayNum = index - leadingBlanks + 1;
        final day = DateTime(month.year, month.month, dayNum);
        final done = recordedDays.contains(day);
        final isFuture =
            day.isAfter(DateTime(today.year, today.month, today.day));

        return GestureDetector(
          onTap: done ? () => onTapDay?.call(day) : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: done
                  ? AppColors.greenSoft
                  : isFuture
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surfaceVariant,
              border: isFuture
                  ? Border.all(color: AppColors.border, width: 1)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$dayNum',
              style: TextStyle(
                fontSize: 10,
                color: done ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      },
    );
  }
}
