import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';

/// Lịch sử phiên thu trên máy này.
///
/// Lịch chỉ cho biết ngày nào đã thu. Không tô màu theo bất kỳ số đo nào,
/// không bao giờ hiển thị điểm (WP2 mục 11). Không có nút nghe lại để thu đè:
/// bản thu đã lưu là bản cuối cùng (mục 6).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageService.instance;

  List<LocalSession> _sessions = [];
  Set<DateTime> _recordedDays = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _storage.loadSessions();
    final days = await _storage.recordedDays();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _recordedDays = days;
    });
  }

  void _showDay(DateTime day) {
    final daySessions = _sessions
        .where((s) =>
            s.recordedAt.year == day.year &&
            s.recordedAt.month == day.month &&
            s.recordedAt.day == day.day)
        .toList();
    if (daySessions.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('d MMMM y', 'en').format(day),
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            ...daySessions.map(_sessionTile),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Your sessions', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _monthCard(),
          const SizedBox(height: 18),
          if (_sessions.isEmpty)
            _emptyState()
          else ...[
            const Text('Recent', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            ..._sessions.take(20).map(_sessionTile),
          ],
        ],
      ),
    );
  }

  Widget _monthCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() =>
                    _month = DateTime(_month.year, _month.month - 1)),
                icon: Icon(Icons.chevron_left, size: 18),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              Text(DateFormat('MMMM y', 'en').format(_month),
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              IconButton(
                onPressed: _month.isBefore(
                        DateTime(DateTime.now().year, DateTime.now().month))
                    ? () => setState(() =>
                        _month = DateTime(_month.year, _month.month + 1))
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 6),
          MonthGrid(
            month: _month,
            recordedDays: _recordedDays,
            onTapDay: _showDay,
          ),
          SizedBox(height: 10),
          Text(
            'Dark days are days with a recorded session. Tap to see them.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(LocalSession session) {
    final tips = session.qualityFlags.map(guidanceFor).whereType<String>();
    final quality = tips.isEmpty ? 'Good recording' : 'See tips for next time';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.mic_none_rounded,
                size: 15, color: AppColors.blueDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session · ${DateFormat('d MMMM, HH:mm', 'en').format(session.recordedAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${session.speechSec.round()} s of speaking · $quality',
                  style: TextStyle(
                      fontSize: 10, color: muted.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          Icon(
            session.uploaded
                ? Icons.cloud_done_outlined
                : Icons.cloud_upload_outlined,
            size: 16,
            color: muted.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 30),
      child: Column(
        children: [
          Icon(Icons.mic_none_rounded,
              size: 34, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          SizedBox(height: 14),
          Text('No sessions yet',
              style: TextStyle(fontSize: 15)),
          SizedBox(height: 6),
          Text(
            'Record your first session from the home screen. It takes about two minutes.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
