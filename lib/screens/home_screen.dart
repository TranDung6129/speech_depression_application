import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'session_screen.dart';

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
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: AppColors.greenDeep),
              child: Text('Settings', style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 24)),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: appThemeMode,
              builder: (context, mode, _) {
                return SwitchListTile(
                  title: const Text('Dark Mode'),
                  value: mode == ThemeMode.dark,
                  onChanged: (val) {
                    appThemeMode.value = val ? ThemeMode.dark : ThemeMode.light;
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => AuthService.instance.signOut(),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _HomeTab(),
          _ComingSoonTab(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chat',
            body:
                'The chat experience is still being built with our care team.\n'
                'For now, you can record your daily session in the Home tab.',
          ),
          _ComingSoonTab(
            icon: Icons.spa_outlined,
            title: 'Relax',
            body: 'Breathing exercises and calming sounds will appear here soon.',
          ),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: AppColors.greenTint,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.greenDeep),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            label: 'Relax',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
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

/// Màn hình chính của bệnh nhân (WP2 mục 11).
///
/// Bệnh nhân thấy: đã thu bao nhiêu phiên, chất lượng thu của phiên vừa rồi
/// kèm hướng dẫn cải thiện, và đường dẫn tới hỗ trợ. Bệnh nhân KHÔNG BAO GIỜ
/// thấy điểm, nhãn hay mức rủi ro, và không có từ ngữ chẩn đoán nào ở đây.
class _HomeTabState extends State<_HomeTab> {
  final _storage = StorageService.instance;

  Set<DateTime> _recordedDays = {};
  int _sessionCount = 0;
  bool _doneToday = false;
  List<String> _lastFlags = const [];
  bool _hasLast = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final local = await _storage.loadSessions();
    final server = await AuthService.instance.fetchSessions();
    if (!mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Máy chủ là nguồn đầy đủ nhất (kể cả phiên thu trên máy cũ); phiên chưa
    // tải lên thì chỉ có ở máy này. Gộp theo session_id.
    final byId = <String, (DateTime, List<String>)>{};
    for (final s in server ?? const <Map<String, dynamic>>[]) {
      byId[s['session_id'] as String] = (
        DateTime.parse('${s['timestamp_utc']}Z').toLocal(),
        (s['quality_flags'] as List<dynamic>).cast<String>(),
      );
    }
    for (final s in local) {
      byId.putIfAbsent(s.id, () => (s.recordedAt, s.qualityFlags));
    }
    final all = byId.values.toList()..sort((a, b) => b.$1.compareTo(a.$1));
    final days = all
        .map((s) => DateTime(s.$1.year, s.$1.month, s.$1.day))
        .toSet();

    setState(() {
      _recordedDays = days;
      _sessionCount = all.length;
      _doneToday = days.contains(today);
      _hasLast = all.isNotEmpty;
      _lastFlags = all.isEmpty ? const [] : all.first.$2;
    });

    // Đặt lại lịch nhắc mỗi lần mở màn hình chính: đã thu hôm nay thì lần
    // nhắc kế tiếp là ngày mai.
    final (hour, minute) = await _storage.reminderTime();
    await ReminderService.instance.schedule(
      hour: hour,
      minute: minute,
      doneToday: days.contains(today),
      askPermission: true,
    );
  }

  Future<void> _openSession() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SessionScreen()),
    );
    if (saved != null) _load();
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
              _doneToday
                  ? 'You have recorded today'
                  : 'Ready for today\'s session?',
              style: const TextStyle(fontSize: 20, height: 1.35),
            ),
            const SizedBox(height: 16),
            _sessionCard(),
            const SizedBox(height: 12),
            if (_hasLast) ...[
              _lastQualityCard(),
              const SizedBox(height: 12),
            ],
            _statsRow(),
            const SizedBox(height: 12),
            _weekCard(),
            const SizedBox(height: 12),
            _supportTile(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

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
          child: const Icon(Icons.person_outline_rounded,
              size: 18, color: AppColors.greenDeep),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7))),
              AnimatedBuilder(
                animation: AuthService.instance,
                builder: (context, _) {
                  return Text(AuthService.instance.displayName,
                      style: const TextStyle(fontSize: 14));
                },
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HistoryScreen()),
          ),
          icon: Icon(Icons.calendar_today_outlined,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        IconButton(
          onPressed: () => Scaffold.of(context).openEndDrawer(),
          icon: Icon(Icons.menu_rounded,
              size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _sessionCard() {
    return GestureDetector(
      onTap: _openSession,
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Icon(
                _doneToday ? Icons.check_rounded : Icons.mic_none_rounded,
                size: 23,
                color: AppColors.greenDeep,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _doneToday ? 'Record another session' : 'Today\'s session',
              style: const TextStyle(fontSize: 14, color: AppColors.greenDeep),
            ),
            const SizedBox(height: 3),
            const Text('Three short steps · about two minutes',
                style: TextStyle(fontSize: 11, color: Color(0xFF085041))),
          ],
        ),
      ),
    );
  }

  /// Chất lượng thu của phiên gần nhất. Chỉ nói về điều kiện thu.
  Widget _lastQualityCard() {
    final tips = _lastFlags.map(guidanceFor).whereType<String>().toList();
    final good = tips.isEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(good ? Icons.graphic_eq_rounded : Icons.tips_and_updates_outlined,
                  size: 18,
                  color: good ? AppColors.greenDeep : AppColors.amberInk),
              const SizedBox(width: 8),
              const Text('Your last recording', style: TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          if (good)
            Text('Recording quality looked good.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            ...tips.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                )),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = List.generate(7, (i) => today.subtract(Duration(days: i)));
    final daysThisWeek = week.where(_recordedDays.contains).length;
    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: Icons.mic_none_rounded,
            iconColor: const Color(0xFF185FA5),
            value: '$_sessionCount',
            label: 'sessions recorded',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            icon: Icons.event_available_outlined,
            iconColor: AppColors.greenDeep,
            value: '$daysThisWeek / 7',
            label: 'days in the last week',
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _weekCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('This week', style: TextStyle(fontSize: 13)),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                child: Icon(Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WeekStrip(recordedDays: _recordedDays),
        ],
      ),
    );
  }

  Widget _supportTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      leading: const Icon(Icons.support_agent_outlined),
      title: const Text('Need support?', style: TextStyle(fontSize: 13)),
      subtitle: const Text('Ways to reach a person', style: TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => showSupportSheet(context),
    );
  }
}

/// Đường dẫn tới hỗ trợ (mục 11). App này không thay thế chăm sóc y tế.
void showSupportSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Support', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 12),
          const Text(
            'This app records your voice for a research study. It does not '
            'give results and it is not a replacement for care.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            '• If you want to talk to someone, contact your clinic or the '
            'study team.\n'
            '• If you are in danger or need urgent help, call 115 or go to '
            'the nearest emergency department.',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Tab for features not built yet.
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
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 25, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
              SizedBox(height: 18),
              Text(title, style: TextStyle(fontSize: 17)),
              SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
