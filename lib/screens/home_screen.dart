import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';
import 'assessment_screen.dart';
import 'history_screen.dart';
import 'journal_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _HomeTab(),
          _ComingSoonTab(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Trò chuyện',
            body:
                'Phần trò chuyện đang được xây dựng cùng chuyên gia tâm lý.\n'
                'Hiện tại bạn dùng nhật ký giọng nói ở tab Trang chủ.',
          ),
          _ComingSoonTab(
            icon: Icons.spa_outlined,
            title: 'Thư giãn',
            body: 'Bài tập thở và âm thanh thư giãn sẽ có ở đây.',
          ),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.greenTint,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.greenDeep),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Trò chuyện',
          ),
          NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            label: 'Thư giãn',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final _storage = StorageService.instance;

  Set<DateTime> _recordedDays = {};
  AssessmentSession? _draft;
  int _streak = 0;
  int _monthCount = 0;
  bool _journaledToday = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await _storage.recordedDays();
    final draft = await _storage.loadDraft();
    final entries = await _storage.loadEntries();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Streak: đếm ngược từ hôm nay, dừng ở ngày đầu tiên không có bản ghi.
    var streak = 0;
    var cursor = days.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    if (!mounted) return;
    setState(() {
      _recordedDays = days;
      _draft = draft;
      _streak = streak;
      _journaledToday = days.contains(today);
      _monthCount = entries
          .where((e) =>
              e.recordedAt.year == now.year && e.recordedAt.month == now.month)
          .length;
    });
  }

  Future<void> _openJournal() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const JournalScreen()),
    );
    if (saved == true) _load();
  }

  Future<void> _openAssessment() async {
    // Có draft dở thì hỏi trước, không tự động nhảy vào giữa chừng.
    if (_draft != null && !_draft!.isComplete) {
      final choice = await showModalBottomSheet<_DraftChoice>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _ResumeDraftSheet(draft: _draft!),
      );

      if (choice == null) return;

      if (choice == _DraftChoice.startNew) {
        // Draft cũ không bị xoá — chuyển sang trạng thái abandoned và giữ lại.
        // Các câu đã trả lời vẫn là mẫu giọng hợp lệ, đáng giữ cho phân tích.
        await _storage.archiveDraftAsAbandoned();
        if (!mounted) return;
        final done = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const AssessmentScreen()),
        );
        if (done != null) _load();
        return;
      }

      if (!mounted) return;
      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (_) => AssessmentScreen(resumeSession: _draft)),
      );
      if (done != null) _load();
      return;
    }

    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AssessmentScreen()),
    );
    if (done != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _header(),
            const SizedBox(height: 18),
            Text(
              _journaledToday
                  ? 'Hôm nay bạn đã ghi rồi'
                  : 'Bạn thấy thế nào hôm nay?',
              style: const TextStyle(fontSize: 20, height: 1.35),
            ),
            const SizedBox(height: 16),
            _journalCard(),
            const SizedBox(height: 12),
            _assessmentCard(),
            const SizedBox(height: 12),
            _statsRow(),
            const SizedBox(height: 12),
            _weekCard(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Chào buổi sáng'
        : hour < 18
            ? 'Chào buổi chiều'
            : 'Chào buổi tối';

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.greenTint,
          ),
          alignment: Alignment.center,
          child: const Text('MD',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.greenDeep,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
              const Text('Minh Dũng', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HistoryScreen()),
          ),
          icon: const Icon(Icons.calendar_today_outlined,
              size: 20, color: AppColors.textSecondary),
        ),
        IconButton(
          onPressed: () => Scaffold.of(context).openEndDrawer(),
          icon: const Icon(Icons.menu_rounded,
              size: 22, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _journalCard() {
    return GestureDetector(
      onTap: _openJournal,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.greenTint,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Icon(
                _journaledToday
                    ? Icons.check_rounded
                    : Icons.mic_none_rounded,
                size: 23,
                color: AppColors.greenDeep,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _journaledToday ? 'Ghi thêm một đoạn nữa' : 'Nhật ký hôm nay',
              style: const TextStyle(fontSize: 14, color: AppColors.greenDeep),
            ),
            const SizedBox(height: 3),
            const Text('Khoảng một phút',
                style: TextStyle(fontSize: 11, color: Color(0xFF085041))),
          ],
        ),
      ),
    );
  }

  Widget _assessmentCard() {
    final hasDraft = _draft != null && !_draft!.isComplete;

    return GestureDetector(
      onTap: _openAssessment,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hasDraft ? AppColors.amberTint : AppColors.blueTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                hasDraft ? Icons.bookmark_outline_rounded : Icons.assignment_outlined,
                size: 17,
                color: hasDraft
                    ? const Color(0xFF854F0B)
                    : AppColors.blueDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Đánh giá chuyên sâu',
                      style: TextStyle(fontSize: 13)),
                  Text(
                    hasDraft
                        ? 'Đang dở ${_draft!.answeredCount}/${AssessmentQuestion.total} câu'
                        : 'Bốn câu, khoảng năm phút',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: Icons.local_fire_department_outlined,
            iconColor: const Color(0xFFD85A30),
            value: '$_streak ngày',
            label: 'liên tiếp',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            icon: Icons.show_chart_rounded,
            iconColor: const Color(0xFF185FA5),
            value: '$_monthCount',
            label: 'bản ghi tháng này',
          ),
        ),
      ],
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _weekCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tuần này', style: TextStyle(fontSize: 13)),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                child: const Icon(Icons.chevron_right,
                    size: 16, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WeekStrip(recordedDays: _recordedDays),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------

enum _DraftChoice { resume, startNew }

/// Hỏi trước khi vào phiên dở — không tự động nhảy vào giữa chừng,
/// vì người dùng có thể đã quên mình đang trả lời đến đâu.
class _ResumeDraftSheet extends StatelessWidget {
  const _ResumeDraftSheet({required this.draft});

  final AssessmentSession draft;

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(draft.lastTouchedAt).inDays;
    final ago = days == 0
        ? 'hôm nay'
        : days == 1
            ? 'hôm qua'
            : '$days ngày trước';

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amberTint,
            ),
            child: const Icon(Icons.bookmark_outline_rounded,
                color: Color(0xFF854F0B), size: 21),
          ),
          const SizedBox(height: 16),
          const Text('Bạn đang có một đánh giá dang dở',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Đã trả lời ${draft.answeredCount}/${AssessmentQuestion.total} câu · $ago',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DraftChoice.resume),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blueDeep,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.structuredButton),
                ),
                elevation: 0,
              ),
              child: Text('Tiếp tục từ câu ${draft.answeredCount + 1}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DraftChoice.startNew),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.borderStrong),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.structuredButton),
                ),
              ),
              child: const Text('Bắt đầu đánh giá mới',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Các câu đã trả lời vẫn được giữ lại',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Tab cho các phần chưa xây dựng. Hiện rõ là chưa có, không giả vờ hoạt động.
class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 25, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
