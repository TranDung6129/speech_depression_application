import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';

/// History screen.
/// The important rule: the monthly view shows only whether a day has a recording.
/// It never colors by emotion and never displays model scores.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageService.instance;
  final _player = AudioPlayer();

  List<JournalEntry> _entries = [];
  List<AssessmentSession> _sessions = [];
  Set<DateTime> _recordedDays = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await _storage.loadEntries();
    final sessions = await _storage.loadSessions();
    final days = await _storage.recordedDays();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _sessions = sessions;
      _recordedDays = days;
    });
  }

  Future<void> _togglePlay(JournalEntry entry) async {
    if (_playingId == entry.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }

    try {
      await _player.setFilePath(entry.audioPath);
      await _player.play();
      setState(() => _playingId = entry.id);
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playingId = null);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This recording could not be opened.')),
      );
    }
  }

  void _showDay(DateTime day) {
    final dayEntries = _entries
        .where((e) =>
            e.recordedAt.year == day.year &&
            e.recordedAt.month == day.month &&
            e.recordedAt.day == day.day)
        .toList();

    if (dayEntries.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(22, 16, 22, 30),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat("d MMMM y", 'en').format(day),
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            ...dayEntries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(
                        e.selfTag?.icon ?? Icons.mic_none_rounded,
                        size: 17,
                        color: AppColors.greenDeep,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.selfTag?.label ?? 'No label yet',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm').format(e.recordedAt),
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                )),
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
        title: const Text('Your journal', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _monthCard(),
          const SizedBox(height: 18),
          if (_entries.isEmpty && _sessions.isEmpty)
            _emptyState()
          else ...[
            const Text('Recent', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            ..._entries.take(10).map(_entryTile),
            ..._sessions.take(5).map(_sessionTile),
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
            'Dark days indicate entries you have recorded. Tap to review.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(JournalEntry entry) {
    final playing = _playingId == entry.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.selfTag?.icon ?? Icons.mic_none_rounded,
                size: 15, color: AppColors.greenDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Journal · ${DateFormat("d MMMM", 'en').format(entry.recordedAt)}',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  '${entry.duration.inSeconds} seconds'
                  '${entry.selfTag != null ? ' · ${entry.selfTag!.label}' : ''}',
                  style: TextStyle(
                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _togglePlay(entry),
            icon: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(AssessmentSession session) {
    final label = switch (session.status) {
      SessionStatus.completed =>
        'Completed ${session.answeredCount}/${AssessmentQuestion.total}',
      SessionStatus.abandoned =>
        'Stopped at ${session.answeredCount}/${AssessmentQuestion.total}',
      SessionStatus.draft => 'In progress',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
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
            child: const Icon(Icons.assignment_outlined,
                size: 15, color: AppColors.blueDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assessment · ${DateFormat("d MMMM", 'en').format(session.startedAt)}',
                  style: TextStyle(fontSize: 12),
                ),
                Text(label,
                    style: TextStyle(
                        fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
              ],
            ),
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
          Text('No recordings yet',
              style: TextStyle(fontSize: 15)),
          SizedBox(height: 6),
          Text(
            'Record your first journal entry from the home screen. It only takes about a minute.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
