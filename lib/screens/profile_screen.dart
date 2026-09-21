import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/upload_queue.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = StorageService.instance;

  int _reminderHour = 20;
  int _reminderMinute = 0;
  int _intervalDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (h, m) = await _storage.reminderTime();
    final days = await _storage.assessmentIntervalDays();
    if (!mounted) return;
    setState(() {
      _reminderHour = h;
      _reminderMinute = m;
      _intervalDays = days;
    });
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null) return;
    await _storage.setReminderTime(picked.hour, picked.minute);
    if (!mounted) return;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
  }

  /// Tần suất đánh giá do người dùng tự chọn.
  ///
  /// Lưu ý cho phía phân tích: giá trị này CHỈ điều khiển lời nhắc.
  /// Khoảng cách thực tế giữa các phiên phải đọc từ timestamp của từng phiên,
  /// không được suy ra từ cài đặt này — người dùng thường làm không đúng lịch.
  Future<void> _pickInterval() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bao lâu nhắc bạn một lần?',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Bạn vẫn có thể làm bất cứ lúc nào bạn muốn.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ...[
              (3, 'Ba ngày một lần'),
              (7, 'Mỗi tuần'),
              (14, 'Hai tuần một lần'),
              (0, 'Không nhắc — mình tự chủ động'),
            ].map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(opt.$2, style: const TextStyle(fontSize: 14)),
                  trailing: _intervalDays == opt.$1
                      ? const Icon(Icons.check_rounded,
                          size: 18, color: AppColors.greenDeep)
                      : null,
                  onTap: () => Navigator.of(context).pop(opt.$1),
                )),
          ],
        ),
      ),
    );

    if (picked == null) return;
    await _storage.setAssessmentIntervalDays(picked);
    if (!mounted) return;
    setState(() => _intervalDays = picked);
  }

  Future<void> _confirmWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Xoá toàn bộ bản ghi?',
            style: TextStyle(fontSize: 17)),
        content: const Text(
          'Tất cả bản ghi và đánh giá trên máy sẽ bị xoá. '
          'Việc này không hoàn tác được.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá hết',
                style: TextStyle(color: AppColors.riskHigh)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _storage.wipeAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xoá toàn bộ bản ghi.')),
    );
  }

  String get _intervalLabel => switch (_intervalDays) {
        3 => 'Ba ngày một lần',
        7 => 'Mỗi tuần',
        14 => 'Hai tuần một lần',
        _ => 'Không nhắc',
      };

  @override
  Widget build(BuildContext context) {
    final time =
        '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
        children: [
          _profileHeader(),
          const SizedBox(height: 18),
          _syncCard(),
          const SizedBox(height: 14),
          _sectionCard([
            _row(
              icon: Icons.notifications_none_rounded,
              title: 'Nhắc ghi nhật ký',
              subtitle: 'Hằng ngày · $time',
              onTap: _pickReminder,
            ),
            _divider(),
            _row(
              icon: Icons.assignment_outlined,
              title: 'Tần suất đánh giá',
              subtitle: 'Bạn tự chọn · $_intervalLabel',
              onTap: _pickInterval,
            ),
            _divider(),
            _row(
              icon: Icons.lock_outline_rounded,
              title: 'Quyền riêng tư và dữ liệu',
              subtitle: 'Xem, tải về hoặc xoá',
              onTap: _confirmWipe,
            ),
          ]),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Sắp có',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          _sectionCard([
            _lockedRow(Icons.chat_bubble_outline_rounded, 'Trò chuyện cùng AI'),
            _divider(),
            _lockedRow(Icons.spa_outlined, 'Thư giãn và âm nhạc'),
            _divider(),
            _lockedRow(Icons.bedtime_outlined, 'Giấc ngủ và năng lượng'),
            _divider(),
            _lockedRow(
                Icons.medical_services_outlined, 'Kết nối chuyên gia'),
          ]),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _confirmSignOut,
              child: const Text('Đăng xuất',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  /// Cho người dùng thấy còn bản ghi nào chưa gửi được.
  ///
  /// Hiện cả khi mọi thứ bình thường, không chỉ khi có lỗi: nếu chỉ hiện lúc
  /// hỏng thì người dùng không có cách nào biết dữ liệu của mình đã lên đến
  /// nơi hay chưa.
  Widget _syncCard() {
    return AnimatedBuilder(
      animation: UploadQueue.instance,
      builder: (context, _) {
        final pending = UploadQueue.instance.pendingCount;
        final failed = UploadQueue.instance.failedCount;
        final allClear = pending == 0 && failed == 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: failed > 0 ? AppColors.amberTint : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                allClear
                    ? Icons.cloud_done_outlined
                    : failed > 0
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_sync_outlined,
                size: 18,
                color: failed > 0
                    ? const Color(0xFF854F0B)
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  allClear
                      ? 'Đã lưu xong tất cả bản ghi'
                      : failed > 0
                          ? '$failed bản ghi chưa gửi được'
                          : 'Đang gửi $pending bản ghi',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (failed > 0)
                TextButton(
                  onPressed: () => UploadQueue.instance.retryFailed(),
                  child: const Text('Thử lại',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut() async {
    final pending = UploadQueue.instance.pendingCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Đăng xuất?', style: TextStyle(fontSize: 17)),
        content: Text(
          pending > 0
              ? 'Còn $pending bản ghi chưa gửi lên. Chúng vẫn nằm trên máy '
                  'và sẽ được gửi khi bạn đăng nhập lại.'
              : 'Bản ghi trên máy vẫn được giữ nguyên.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ở lại'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.instance.signOut();
    }
  }

  Widget _profileHeader() {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.greenTint,
          ),
          alignment: Alignment.center,
          child: const Text('MD',
              style: TextStyle(
                  fontSize: 19,
                  color: AppColors.greenDeep,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 10),
        const Text('Minh Dũng', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 3),
        const Text('Liên kết với phòng khám',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => const Divider(
      height: 0.5, thickness: 0.5, color: AppColors.border, indent: 14);

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _lockedRow(IconData icon, String title) {
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 13)),
            ),
            const Text('Sắp có',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
